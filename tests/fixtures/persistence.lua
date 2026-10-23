local function copy(v) if type(v) ~= 'table' then return v end; local out = {}; for k,x in pairs(v) do out[k] = copy(x) end; return out end
local function fixture()
    local m = { db = { tables = {}, ledger = {}, characters = {}, operations = {}, horses = {}, history = {}, outbox = {}, registrations = {} },
        ready = true, provider = 'started', ddl = 0, clock = 0, outputs = {} }
    m.db.callLeases,m.db.callSlots,m.db.callBindings,m.db.callEpochs,m.db.callRecoveries={},{},{},{},{}
    local env = setmetatable({}, { __index = _G })
    env.GetResourceState = function() return m.provider end
    env.RegisterCommand = function() end
    env.CreateThread = function(fn) fn() end
    env.print = function(value) m.outputs[#m.outputs + 1] = value end
    local docs, serial = {}, 0
    env.json = { encode = function(value) serial = serial + 1; docs[tostring(serial)] = copy(value); return tostring(serial) end,
        decode = function(value) assert(docs[value], 'invalid JSON'); return copy(docs[value]) end }
    for _, path in ipairs({ 'config.lua', 'shared/contracts.lua', 'server/operations.lua', 'server/migrations.lua' }) do
        assert(loadfile(path, 't', env))()
    end
    local function execute(method, sql, ...)
        local p, db = { ... }, m.db
        if sql=='SELECT UUID()' then
            m.uuidSerial=(m.uuidSerial or 0)+1
            if m.onUuid then m.onUuid() end
            return ('b0000000-0000-4000-8000-%012d'):format(m.uuidSerial)
        elseif sql:find('SELECT COUNT(*) FROM fs_call_leases WHERE state NOT IN',1,true) then
            if m.failDrainRead then error({code='READ_FAILED',outcome='not_executed'}) end
            local n=0; for _,row in pairs(db.callLeases) do if row.state~='prepared' and row.state~='released' then n=n+1 end end
            return n
        elseif sql:find("SELECT COUNT(*) FROM fs_call_bindings WHERE state<>'cleared'",1,true) then
            local n=0; for _,row in pairs(db.callBindings) do if row.state~='cleared' then n=n+1 end end
            return n
        elseif sql:find('SELECT * FROM fs_call_recoveries',1,true) then return copy(db.callRecoveries[p[1]])
        elseif sql:find('INSERT INTO fs_call_recoveries',1,true) then
            if m.failRecoveryInsert then error({code='WRITE_FAILED',outcome='rolled_back'}) end
            assert(m.inTx and not db.callRecoveries[p[1]])
            db.callRecoveries[p[1]]={generation_id=p[1],original_epoch=p[2],resolved_epoch=p[3],prior_revision=p[4],prior_reason=p[5]}; return 1
        elseif sql:find('SELECT * FROM fs_call_process_epochs',1,true) then return copy(db.callEpochs[p[1]])
        elseif sql:find('INSERT INTO fs_call_process_epochs',1,true) then
            if m.failEpochInsert then error({code='WRITE_FAILED',outcome='rolled_back'}) end
            assert(m.inTx and not db.callEpochs[p[1]])
            db.callEpochs[p[1]]={generation_id=p[1],process_epoch=p[2]}; return 1
        elseif sql:find('SELECT * FROM fs_call_bindings',1,true) then return copy(db.callBindings[p[1]])
        elseif sql:find('INSERT INTO fs_call_bindings',1,true) then
            if m.failBindingInsert then error({code='WRITE_FAILED',outcome='rolled_back'}) end
            assert(m.inTx and not db.callBindings[p[1]])
            db.callBindings[p[1]]={generation_id=p[1],observer_id=p[2],network_id=p[3],initial_owner=p[4],routing_bucket=p[5],state='bound',revision=0}; return 1
        elseif sql:find("UPDATE fs_call_bindings SET state='cleanup_pending'",1,true) then
            local row=db.callBindings[p[1]]
            if m.failBindingCas or not row or row.state~='bound' or row.revision~=0 then return 0 end
            row.state,row.revision='cleanup_pending',1; return 1
        elseif sql:find("UPDATE fs_call_bindings SET state='cleared',revision=2,reason=NULL",1,true) then
            local row=db.callBindings[p[1]]
            if m.failBindingCas or not row or row.state~='reconciliation_required' or row.revision~=p[2] then return 0 end
            row.state,row.revision,row.reason='cleared',2,nil; return 1
        elseif sql:find("UPDATE fs_call_bindings SET state='cleared'",1,true) then
            local row=db.callBindings[p[1]]
            if m.failBindingCas or not row or row.state~='cleanup_pending' or row.revision~=1 then return 0 end
            row.state,row.revision='cleared',2; return 1
        elseif sql:find("UPDATE fs_call_bindings SET state='reconciliation_required'",1,true) then
            local row=db.callBindings[p[2]]
            if m.failBindingCas or not row or row.state~=p[3] or row.revision~=p[4] then return 0 end
            row.state,row.revision,row.reason='reconciliation_required',row.revision+1,p[1]; return 1
        elseif sql:find('UPDATE fs_call_leases SET state=?',1,true) then
            local row=db.callLeases[p[2]]
            assert(m.inTx and m.locked==p[3])
            if m.failLifecycleCas or not row or row.character_id~=p[3] or row.state~=p[4] or row.revision~=p[5] then return 0 end
            row.state,row.revision=p[1],row.revision+1; return 1
        elseif sql:find('SELECT * FROM fs_call_slots',1,true) then return copy(db.callSlots[p[1]])
        elseif sql:find('SELECT * FROM fs_call_leases',1,true) then
            local row=db.callLeases[p[1]]; return row and row.character_id==p[2] and copy(row) or nil
        elseif sql:find('SELECT generation_id FROM fs_call_leases',1,true) then
            for _,row in pairs(db.callLeases) do if row.state~='released' and (row.character_id==p[1] or (p[2] and row.horse_id==p[2])) then return {generation_id=row.generation_id} end end
        elseif sql:find('INSERT INTO fs_call_leases',1,true) then
            assert(m.inTx and m.locked==p[2] and not db.callLeases[p[1]])
            db.callLeases[p[1]]={generation_id=p[1],character_id=p[2],horse_id=p[3],operation_id=p[4],asset_id=p[5],model_key=p[6],
                session_id=p[7],source_id=p[8],selection_revision=p[9],state='prepared',revision=0}; return 1
        elseif sql:find('INSERT INTO fs_call_slots',1,true) then
            if m.failCallSlot then error({code='WRITE_FAILED',outcome='rolled_back'}) end
            assert(m.inTx and not db.callSlots[p[1]])
            for _,row in pairs(db.callSlots) do assert(row.horse_id~=p[2] and row.generation_id~=p[3]) end
            db.callSlots[p[1]]={character_id=p[1],horse_id=p[2],generation_id=p[3]}; return 1
        elseif sql:find("UPDATE fs_call_leases SET state='submitting'",1,true) then
            local row=db.callLeases[p[1]]
            assert(m.inTx and m.locked==p[2])
            if m.failSubmissionCas or not row or row.character_id~=p[2] or row.state~='prepared' or row.revision~=0 then return 0 end
            row.state,row.revision='submitting',1; return 1
        elseif sql:find("UPDATE fs_call_leases SET state='released',revision=5",1,true) then
            local row=db.callLeases[p[1]]
            if m.failLifecycleCas or not row or row.character_id~=p[2] or row.state~='reconciliation_required' or row.revision~=p[3] then return 0 end
            row.state,row.revision='released',5; return 1
        elseif sql:find("UPDATE fs_call_leases SET state='released'",1,true) then
            local row=db.callLeases[p[1]]
            if m.failCallCas or not row or row.character_id~=p[2] or row.state~='prepared' or row.revision~=0 then return 0 end
            row.state,row.revision='released',1; return 1
        elseif sql:find('DELETE FROM fs_call_slots',1,true) then
            local row=db.callSlots[p[1]]
            if m.failCallDelete or not row or row.generation_id~=p[2] then return 0 end
            db.callSlots[p[1]]=nil; return 1
        elseif sql:find('CREATE TABLE', 1, true) then
            local name = assert(sql:match('CREATE TABLE IF NOT EXISTS `([a-z_]+)`'))
            if m.failCreate == name then error({code='DDL_FAILED',outcome='not_executed'}) end
            if not db.tables[name] then m.ddl = m.ddl + 1 end
            db.tables[name] = true; return 0
        elseif sql:find('information_schema.TABLES', 1, true) then return db.tables[p[1]] and 1 or 0
        elseif sql == 'SELECT id,checksum,state FROM fs_schema_migrations' then
            local rows = {}; for _,row in pairs(db.ledger) do rows[#rows+1] = copy(row) end; return rows
        elseif sql:find('INSERT IGNORE INTO fs_schema_migrations', 1, true) then
            if db.ledger[p[1]] then return 0 end
            db.ledger[p[1]] = {id=p[1],checksum=p[2],state='pending'}; return 1
        elseif sql:find('SELECT id,checksum,state FROM fs_schema_migrations WHERE', 1, true) then return copy(db.ledger[p[1]])
        elseif sql:find('UPDATE fs_schema_migrations', 1, true) then
            if m.failLedger then return 0 end
            db.ledger[p[1]].state = 'applied'; return 1
        elseif sql:find('INSERT IGNORE INTO fs_character_stables', 1, true) then
            db.characters[p[1]] = db.characters[p[1]] or {character_id=p[1],revision=0}; return 1
        elseif sql:find('SELECT character_id,revision FROM fs_character_stables', 1, true)
            or sql:find('SELECT character_id,selected_horse_id,revision FROM fs_character_stables',1,true)
            or sql:find('SELECT character_id FROM fs_character_stables',1,true) then
            m.locked = p[1]; return copy(db.characters[p[1]])
        elseif sql:find('SELECT * FROM fs_operations WHERE character_id=',1,true) then
            local rows={}
            for _,row in pairs(db.operations) do if row.character_id==p[1] then rows[#rows+1]=copy(row) end end
            table.sort(rows,function(a,b) return a.operation_id<b.operation_id end)
            return rows
        elseif sql:find('SELECT * FROM fs_operations', 1, true) then
            local row = db.operations[p[1]]
            return row and (p[2] == nil or row.character_id == p[2]) and copy(row) or nil
        elseif sql:find('SELECT COUNT(*) FROM fs_horses',1,true) and sql:find(' OR ',1,true) then
            local n=0
            for _,horse in pairs(db.horses) do
                local match=horse.owner_character_id==p[1]
                for index=2,12 do match=match or horse.horse_id==p[index] end
                for index=13,23 do match=match or horse.origin_operation_id==p[index] end
                if match then n=n+1 end
            end
            return n
        elseif sql:find('SELECT event_id,operation_id,event_name,payload_json,attempts FROM fs_outbox',1,true) then
            local rows={}
            for _,r in pairs(db.outbox) do if (r.delivered or 0)==0 and r[3]=='stables.purchase.fulfilled.v1'
                and (not r.next_attempt_at or r.next_attempt_at<=m.clock) then
                rows[#rows+1]={event_id=r[1],operation_id=r[2],event_name=r[3],payload_json=r[4],attempts=r.attempts or 0}
            end end
            table.sort(rows,function(a,b) return a.event_id<b.event_id end)
            while #rows>10 do table.remove(rows) end
            return rows
        elseif sql:find('SELECT COUNT(*) FROM fs_outbox WHERE delivered=',1,true) then
            local n=0; local status=tonumber(sql:match('delivered=(%d)'))
            for _,r in pairs(db.outbox) do if (r.delivered or 0)==status then n=n+1 end end; return n
        elseif sql:find('SELECT COUNT(*) FROM fs_outbox WHERE event_id=',1,true) then
            local r=db.outbox[p[1]]
            return r and (r.delivered or 0)==0 and (r.attempts or 0)==p[2] and (r.next_attempt_at or 0)>m.clock and 1 or 0
        elseif sql:find('UPDATE fs_outbox SET attempts=attempts+1',1,true) then
            local r=db.outbox[p[2]]
            if not r or (r.delivered or 0)~=0 or (r.attempts or 0)~=p[3] or (r.next_attempt_at and r.next_attempt_at>m.clock) then return 0 end
            r.attempts,r.next_attempt_at=(r.attempts or 0)+1,m.clock+p[1]
            if m.lostClaim then error({code='COMMIT_REPLY_LOST',outcome='unknown'}) end
            return 1
        elseif sql:find('UPDATE fs_outbox SET next_attempt_at=',1,true) then
            local r=db.outbox[p[2]]
            if not r or (r.delivered or 0)~=0 or r.attempts~=p[3] then return 0 end
            r.next_attempt_at=m.clock+p[1]; return 1
        elseif sql:find('UPDATE fs_outbox SET delivered=1',1,true) then
            local r=db.outbox[p[1]]
            if m.failAck then error({code='WRITE_FAILED',outcome='unknown'}) end
            if not r or (r.delivered or 0)~=0 or r.attempts~=p[2] then return 0 end
            r.delivered,r.next_attempt_at=1,nil; return 1
        elseif sql:find('SELECT COUNT(*) FROM fs_horse_history',1,true) or sql:find('SELECT COUNT(*) FROM fs_outbox',1,true) then
            local history=sql:find('fs_horse_history',1,true)
            local n=0
            for _,row in pairs(history and db.history or db.outbox) do
                for _,id in ipairs(p) do if row[history and 3 or 2]==id then n=n+1; break end end
            end
            return n
        elseif sql:find('SELECT COUNT(*) FROM fs_horses', 1, true) then
            assert(m.inTx and m.locked == p[1], 'capacity read must follow the character lock')
            local n = 0; for _,horse in pairs(db.horses) do if horse.owner_character_id == p[1] then n=n+1 end end; return n
        elseif sql:find('SELECT COUNT(*) FROM fs_operations', 1, true) then
            if sql:find('state NOT IN',1,true) then assert(m.inTx and m.locked == p[1]) end
            local n = 0
            for _,row in pairs(db.operations) do
                if row.character_id==p[1] and (not sql:find('state NOT IN',1,true)
                    or row.state~='fulfilled' and row.state~='cancelled' and row.state~='refunded') then n=n+1 end
            end
            return n
        elseif sql:find('SELECT revision FROM fs_character_stables',1,true) then return db.characters[p[1]] and db.characters[p[1]].revision
        elseif sql:find('UPDATE fs_character_stables SET selected_horse_id=',1,true) then
            local row=db.characters[p[2]]
            if m.failSelectionCas or not row or row.revision~=p[3] then return 0 end
            assert(m.inTx and m.locked==p[2]); row.selected_horse_id,row.revision=p[1],row.revision+1
            return 1
        elseif sql:find('UPDATE fs_character_stables SET revision=revision+1',1,true) then
            assert(m.locked==p[1]); db.characters[p[1]].revision=db.characters[p[1]].revision+1; return 1
        elseif sql:find('DELETE FROM fs_operations',1,true) then
            local row=db.operations[p[1]]
            if m.failClearDelete or not row or row.character_id~=p[2] or row.fingerprint~=p[3] or row.state~=p[4]
                or row.revision~=p[5] or row.payment_transaction_id or row.refund_transaction_id then return 0 end
            assert(m.locked==p[2]); db.operations[p[1]]=nil; return 1
        elseif sql:find('DELETE FROM fs_character_stables',1,true) then
            local row=db.characters[p[1]]
            if not row or row.selected_horse_id~=nil or row.revision~=0 then return 0 end
            db.characters[p[1]]=nil; return 1
        elseif sql:find('SELECT COUNT(*) FROM fs_asset_registrations',1,true) then
            local n=0; for _,row in pairs(db.registrations) do if row.character_id==p[1] then n=n+1 end end; return n
        elseif sql:find('SELECT * FROM fs_asset_registrations',1,true) then
            assert(not sql:find('FOR UPDATE',1,true) or (m.inTx and m.locked~=nil)); return copy(db.registrations[p[1]])
        elseif sql:find('INSERT INTO fs_asset_registrations',1,true) then
            assert(m.inTx and m.locked==p[2] and not db.registrations[p[1]])
            db.registrations[p[1]]={operation_id=p[1],character_id=p[2],horse_id=p[3],request_id=p[4],model_key=p[5],
                fingerprint=p[6],request_json=p[7],state='prepared',revision=0}; return 1
        elseif sql:find("UPDATE fs_asset_registrations SET state='submitted'",1,true) then
            local row=db.registrations[p[1]]
            if m.failSubmit or not row or row.state~='prepared' or row.revision~=0 then return 0 end
            row.state,row.revision='submitted',1; return 1
        elseif sql:find("UPDATE fs_asset_registrations SET state='linked'",1,true) then
            local row=db.registrations[p[3]]
            if m.failLink or not row or row.state~='submitted' or row.revision~=1 then return 0 end
            for _,other in pairs(db.registrations) do assert(other.asset_id~=p[1],'unique asset identity') end
            row.state,row.asset_id,row.asset_revision,row.revision='linked',p[1],p[2],2; return 1
        elseif sql:find('INSERT INTO fs_operations', 1, true) then
            assert(m.locked == p[2])
            for _,row in pairs(db.operations) do assert(row.horse_id ~= p[3] and row.payment_key ~= p[11], 'unique constraint') end
            assert(not db.operations[p[1]])
            db.operations[p[1]] = {operation_id=p[1],kind='horse_purchase',character_id=p[2],horse_id=p[3],quote_id=p[4],catalog_id=p[5],
                catalog_revision=p[6],currency=p[7],amount=p[8],wallet_account_id=p[9],sink_account_id=p[10],payment_key=p[11],
                fingerprint=p[12],state=p[13],revision=p[14],record_json=p[15]}; return 1
        elseif sql:find('SELECT horse_id,origin_operation_id FROM fs_horses',1,true) then
            if method=='one' then
                local h=db.horses[p[1]]
                if h and h.owner_character_id==p[2] then return {horse_id=h.horse_id,origin_operation_id=h.origin_operation_id} end
            else
                local rows={}
                for _,h in pairs(db.horses) do if h.owner_character_id==p[1] and (not p[2] or h.horse_id>p[2]) then
                    rows[#rows+1]={horse_id=h.horse_id,origin_operation_id=h.origin_operation_id}
                end end
                table.sort(rows,function(a,b) return a.horse_id<b.horse_id end)
                while #rows>11 do table.remove(rows) end
                return rows
            end
        elseif sql:find('SELECT * FROM fs_horses WHERE horse_id=',1,true) then
            local h=db.horses[p[1]]
            return h and h.owner_character_id==p[2] and copy(h) or nil
        elseif sql:find('SELECT * FROM fs_horses WHERE origin_operation_id=',1,true) then
            for _,horse in pairs(db.horses) do if horse.origin_operation_id==p[1] then return copy(horse) end end
        elseif sql:find('SELECT * FROM fs_horse_history WHERE operation_id=',1,true) then
            for _,row in pairs(db.history) do if row[3]==p[1] and row[4]==p[2] then
                return {event_id=row[1],horse_id=row[2],operation_id=row[3],event_kind=row[4],facts_json=row[5]}
            end end
        elseif sql:find('SELECT * FROM fs_outbox WHERE operation_id=',1,true) then
            for _,row in pairs(db.outbox) do if row[2]==p[1] and row[3]==p[2] then
                return {event_id=row[1],operation_id=row[2],event_name=row[3],payload_json=row[4],delivered=row.delivered or 0}
            end end
        elseif sql:find('SELECT horse_id FROM fs_horses', 1, true) then
            for _,horse in pairs(db.horses) do if horse.origin_operation_id == p[1] then return {horse_id=horse.horse_id} end end
        elseif sql:find('INSERT INTO fs_horses', 1, true) then
            assert(m.locked == p[2] and not db.horses[p[1]])
            db.horses[p[1]] = {horse_id=p[1],owner_character_id=p[2],origin_operation_id=p[3],catalog_id=p[4],catalog_revision=p[5],availability='stored',biological_state='alive',revision=0}; return 1
        elseif sql:find('INSERT INTO fs_horse_history', 1, true) then
            if m.failHistory then error({code='WRITE_FAILED',outcome='rolled_back'}) end
            db.history[p[1]] = copy(p); return 1
        elseif sql:find('INSERT INTO fs_outbox', 1, true) then
            if m.failOutbox then error({code='WRITE_FAILED',outcome='rolled_back'}) end
            db.outbox[p[1]] = copy(p); return 1
        elseif sql:find('UPDATE fs_operations', 1, true) then
            local row = db.operations[p[6]]
            if m.failCas or row.character_id ~= p[7] or row.revision ~= p[8] or row.state ~= p[9] then return 0 end
            row.state,row.revision,row.payment_transaction_id,row.refund_transaction_id,row.record_json = p[1],p[2],p[3],p[4],p[5]; return 1
        else error('Unhandled SQL ' .. sql) end
    end
    env.DB = {awaitReady=function() return m.ready end}
    for _, method in ipairs({'exec','query','one','value'}) do
        env.DB[method] = function(sql,...)
            assert(not m.inTx, 'root DB call inside transaction')
            return execute(method,sql,...)
        end
    end
    env.DB.transaction = function(body)
        local snapshot, tx = copy(m.db), {}
        m.inTx,m.locked = true,nil
        for _,method in ipairs({'exec','query','one','value'}) do tx[method] = function(sql,...) return execute(method,sql,...) end end
        local ok, committed = pcall(body,tx)
        m.inTx,m.locked = false,nil
        if not ok or committed ~= true then m.db = snapshot end
        if not ok then error(committed) end
        if m.unknownCommit and committed then error({code='COMMIT_REPLY_LOST',outcome='unknown'}) end
        return committed == true
    end
    m.env = env
    m.reload = function()
        assert(loadfile('server/persistence.lua','t',env))()
        assert(loadfile('server/repository.lua','t',env))()
        m.p, m.r = env.Stables.Persistence, env.Stables.Repository
    end
    m.reload()
    m.start = function() return m.p.Start() end
    return m
end

return fixture
