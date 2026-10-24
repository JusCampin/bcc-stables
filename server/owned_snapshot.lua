-- Consistent owned-evidence reader. Canonical authorization stays in OwnedHorses.
Stables.OwnedSnapshot={}
local Q,S=Stables.OwnedSnapshot,Stables
local specs={
    {name='stable',fields={'character_id','revision'}},
    {name='operation',fields={'operation_id','kind','character_id','horse_id','quote_id','catalog_id','catalog_revision','currency','amount','wallet_account_id','sink_account_id','payment_key','fingerprint','state','revision','payment_transaction_id','refund_transaction_id','record_json'}},
    {name='registration',fields={'operation_id','character_id','horse_id','request_id','model_key','fingerprint','request_json','state','asset_id','asset_revision','revision'}},
    {name='horse',fields={'horse_id','owner_character_id','origin_operation_id','catalog_id','catalog_revision','biological_state','availability','revision'}},
    {name='history',fields={'event_id','horse_id','operation_id','event_kind','facts_json'}},
    {name='outbox',fields={'event_id','operation_id','event_name','payload_json','delivered'}},
    {name='event',fields={'event_id','horse_id','generation_id','from_availability','to_availability','prior_revision','revision','reason'}},
    {name='slot',fields={'character_id','horse_id','generation_id'}},
    {name='previousLease',fields={'generation_id','character_id','horse_id','operation_id','asset_id','model_key','session_id','source_id','selection_revision','state','revision'}},
    {name='previousBinding',fields={'generation_id','observer_id','network_id','initial_owner','routing_bucket','state','revision','reason'}},
    {name='previousAudit',fields={'generation_id','original_epoch','resolved_epoch','prior_revision','prior_reason'}},
    {name='previousEpoch',fields={'generation_id','process_epoch'}},
    {name='currentLease',fields={'generation_id','character_id','horse_id','operation_id','asset_id','model_key','session_id','source_id','selection_revision','state','revision'}},
    {name='currentBinding',fields={'generation_id','observer_id','network_id','initial_owner','routing_bucket','state','revision','reason'}},
    {name='currentAudit',fields={'generation_id','original_epoch','resolved_epoch','prior_revision','prior_reason'}},
    {name='currentEpoch',fields={'generation_id','process_epoch'}},
}
local columns={}
for _,spec in ipairs(specs) do
    for _,field in ipairs(spec.fields) do columns[#columns+1]='`'..spec.name..'`.`'..field..'` AS `'..spec.name..'__'..field..'`' end
end
columns[#columns+1]="EXISTS(SELECT 1 FROM fs_call_leases orphan WHERE orphan.horse_id=horse.horse_id AND orphan.state<>'released') AS orphan_exists"
local SQL='SELECT '..table.concat(columns,',')..[[
 FROM fs_character_stables `stable`
 LEFT JOIN fs_operations `operation` ON `operation`.operation_id=? AND `operation`.character_id=`stable`.character_id
 LEFT JOIN fs_asset_registrations `registration` ON `registration`.operation_id=`operation`.operation_id
 LEFT JOIN fs_horses `horse` ON `horse`.origin_operation_id=`operation`.operation_id
 LEFT JOIN fs_horse_history `history` ON `history`.operation_id=`operation`.operation_id AND `history`.event_kind='purchased'
 LEFT JOIN fs_outbox `outbox` ON `outbox`.operation_id=`operation`.operation_id AND `outbox`.event_name='stables.purchase.fulfilled.v1'
 LEFT JOIN fs_horse_runtime_events `event` ON `event`.event_id=(SELECT `latest`.event_id FROM fs_horse_runtime_events `latest`
     WHERE `latest`.horse_id=`horse`.horse_id ORDER BY `latest`.revision DESC LIMIT 1)
 LEFT JOIN fs_call_slots `slot` ON `slot`.character_id=`stable`.character_id
 LEFT JOIN fs_call_leases `previousLease` ON `previousLease`.generation_id=`event`.generation_id AND `previousLease`.character_id=`stable`.character_id
 LEFT JOIN fs_call_bindings `previousBinding` ON `previousBinding`.generation_id=`event`.generation_id
 LEFT JOIN fs_call_recoveries `previousAudit` ON `previousAudit`.generation_id=`event`.generation_id
 LEFT JOIN fs_call_process_epochs `previousEpoch` ON `previousEpoch`.generation_id=`event`.generation_id
 LEFT JOIN fs_call_leases `currentLease` ON `currentLease`.generation_id=`slot`.generation_id AND `currentLease`.character_id=`stable`.character_id
 LEFT JOIN fs_call_bindings `currentBinding` ON `currentBinding`.generation_id=`slot`.generation_id
 LEFT JOIN fs_call_recoveries `currentAudit` ON `currentAudit`.generation_id=`slot`.generation_id
 LEFT JOIN fs_call_process_epochs `currentEpoch` ON `currentEpoch`.generation_id=`slot`.generation_id
 WHERE `stable`.character_id=? LIMIT 2]]
-- Resource-local fixed SQL/schema for proofs and tests; never client input.
function Q.QuerySpec() return SQL,S.Copy(specs) end
local function Equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not Equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
function Q.Decode(id,characterId,result)
    if not S.Operations.IsUuid(id) or not S.Operations.IsUuid(characterId) then return S.Err('invalid_input','Operation/character UUIDs required.') end
    if type(result)~='table' or #result>1 then return S.Err('invalid_projection','Snapshot must contain at most one row.') end
    local flat=result[1]
    if not flat then return S.Err('operation_not_found','Purchase was not found.') end
    if type(flat)~='table' then return S.Err('invalid_projection','Invalid snapshot row.') end
    local rows={}
    for _,spec in ipairs(specs) do
        if flat[spec.name..'__'..spec.fields[1]]~=nil then
            local row={}; for _,field in ipairs(spec.fields) do row[field]=flat[spec.name..'__'..field] end
            rows[spec.name]=row
        end
    end
    local orphan=tonumber(flat.orphan_exists)
    if orphan~=0 and orphan~=1 then return S.Err('invalid_projection','Invalid orphan existence result.') end
    local leases,bindings,audits,epochs={},{},{},{}
    for _,prefix in ipairs({'previous','current'}) do
        for _,entry in ipairs({{'Lease',leases},{'Binding',bindings},{'Audit',audits},{'Epoch',epochs}}) do
            local row=rows[prefix..entry[1]]
            if row then
                local old=entry[2][row.generation_id]
                if old and not Equal(old,row) then return S.Err('invalid_projection','Conflicting snapshot generation evidence.') end
                entry[2][row.generation_id]=row
            end
        end
    end
    local adapter={}
    adapter.one=function(sql,...)
        local key,owner=...
        if sql:find('FROM fs_horse_runtime_events',1,true) then
            assert(rows.horse and key==rows.horse.horse_id); return rows.event
        elseif sql:find('FROM fs_call_slots',1,true) then assert(key==characterId); return rows.slot
        elseif sql:find('SELECT generation_id FROM fs_call_leases WHERE horse_id=',1,true) then
            assert(rows.horse and key==rows.horse.horse_id); return orphan==1 and {generation_id='present'} or nil
        elseif sql:find('FROM fs_call_leases',1,true) then assert(owner==characterId); return leases[key]
        elseif sql:find('FROM fs_call_bindings',1,true) then return bindings[key]
        elseif sql:find('FROM fs_call_recoveries',1,true) then return audits[key]
        elseif sql:find('FROM fs_call_process_epochs',1,true) then return epochs[key] end
        error('Snapshot decoder attempted an unsupported evidence read')
    end
    adapter.batch=function(statements)
        local values={}
        for i,statement in ipairs(statements) do
            local p=statement.params
            local row=adapter.one(statement.sql,table.unpack(p,1,p.n or #p))
            values[i]=row and {row} or {}
        end
        return values
    end
    local horse=rows.horse
    if horse then
        horse.purchase_event_id=rows.history and rows.history.event_id
        horse.purchase_horse_id=rows.history and rows.history.horse_id
        horse.purchase_operation_id=rows.history and rows.history.operation_id
        horse.purchase_kind=rows.history and rows.history.event_kind
        horse.purchase_facts_json=rows.history and rows.history.facts_json
        horse.purchase_outbox_id=rows.outbox and rows.outbox.event_id
        horse.purchase_outbox_operation_id=rows.outbox and rows.outbox.operation_id
        horse.purchase_outbox_name=rows.outbox and rows.outbox.event_name
        horse.purchase_outbox_json=rows.outbox and rows.outbox.payload_json
        horse.purchase_outbox_delivered=rows.outbox and rows.outbox.delivered
    end
    return S.FulfillmentRepository.DecodeOwnedRows(id:lower(),characterId:lower(),{
        stable=rows.stable,operation=rows.operation,registration=rows.registration,artifacts=horse and {horse} or {}
    },adapter)
end
local started,lifecycle=false,0
function Q.Stop() started=false; lifecycle=lifecycle+1 end
function Q.RequireReady()
    if not started or GetResourceState('feather-mysql')~='started' then
        return S.Err('owned_snapshot_unavailable','Owned snapshot reader requires ready database contracts.')
    end
    return S.Ok(true)
end
function Q.Start()
    lifecycle=lifecycle+1; local attempt=lifecycle
    started=false
    local persistent=S.Persistence.RequireReady(); if not persistent.ok then return persistent end
    local ok,result=pcall(function()
        local variables=DB.query("SHOW VARIABLES WHERE Variable_name IN ('transaction_isolation','tx_isolation','autocommit')")
        if type(variables)~='table' then return S.Err('snapshot_environment_unsupported','Database isolation unavailable.') end
        local isolation,autocommit
        for _,row in ipairs(variables) do
            if row.Variable_name=='autocommit' then autocommit=row.Value end
            if row.Variable_name=='transaction_isolation' or row.Variable_name=='tx_isolation' then
                if isolation and isolation~=row.Value then return S.Err('snapshot_environment_unsupported','Conflicting isolation contracts.') end
                isolation=row.Value
            end
        end
        if autocommit~='ON' or (isolation~='REPEATABLE-READ' and isolation~='READ-COMMITTED') then
            return S.Err('snapshot_environment_unsupported','Owned snapshots require autocommit ON and READ COMMITTED or REPEATABLE READ.')
        end
        local expected={fs_character_stables=true,fs_operations=true,fs_asset_registrations=true,fs_horses=true,
            fs_horse_history=true,fs_outbox=true,fs_horse_runtime_events=true,fs_call_slots=true,fs_call_leases=true,
            fs_call_bindings=true,fs_call_recoveries=true,fs_call_process_epochs=true}
        local tables=DB.query([[SELECT TABLE_NAME,ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE()
            AND TABLE_NAME IN ('fs_character_stables','fs_operations','fs_asset_registrations','fs_horses','fs_horse_history','fs_outbox',
                'fs_call_leases','fs_call_slots','fs_call_bindings','fs_call_process_epochs','fs_call_recoveries','fs_horse_runtime_events')]])
        if type(tables)~='table' or #tables~=12 then return S.Err('snapshot_environment_unsupported','Owned snapshot tables unavailable.') end
        for _,row in ipairs(tables) do
            if not expected[row.TABLE_NAME] or row.ENGINE~='InnoDB' then return S.Err('snapshot_environment_unsupported','Owned snapshots require InnoDB tables.') end
            expected[row.TABLE_NAME]=nil
        end
        if lifecycle~=attempt then return S.Err('startup_cancelled','Snapshot startup was cancelled.') end
        started=true
        return S.Ok({ok=true,state='ready',mode='single_statement',isolation=isolation,canonicalRead='fresh_assets'})
    end)
    return ok and result or S.Persistence.DatabaseError(result)
end
function Q.Get(id,characterId)
    local ready=Q.RequireReady(); if not ready.ok then return ready end
    return Q.Read(id,characterId)
end
function Q.Read(id,characterId,explain)
    if not S.Operations.IsUuid(id) or not S.Operations.IsUuid(characterId) then return S.Err('invalid_input','Operation/character UUIDs required.') end
    local ready=S.Foundation.RequireReady(); if not ready.ok then return ready end
    local ok,result=pcall(function()
        local rows=DB.query((explain and 'EXPLAIN ' or '')..SQL,id:lower(),characterId:lower())
        if explain then return S.Ok(rows) end
        return Q.Decode(id:lower(),characterId:lower(),rows)
    end)
    return ok and result or S.Persistence.DatabaseError(result)
end
local busy=false
RegisterCommand('BccStablesSnapshot',function(source,args)
    if source~=0 then return end
    if #args~=3 or not ({compare=true,explain=true})[args[1]] then
        print('[bcc-stables:snapshot] BccStablesSnapshot compare|explain <operationId> <characterId>'); return
    end
    if busy then print('[bcc-stables:snapshot] comparison already running'); return end
    busy=true
    CreateThread(function()
        local ok,result=pcall(function()
            if args[1]=='explain' then return Q.Read(args[2],args[3],true) end
            if not S.Operations.IsUuid(args[2]) or not S.Operations.IsUuid(args[3]) then return S.Err('invalid_input','Operation/character UUIDs required.') end
            local environment={version=DB.value('SELECT VERSION()'),variables=DB.query("SHOW VARIABLES WHERE Variable_name IN ('transaction_isolation','tx_isolation','autocommit')")}
            local began=GetGameTimer()
            local original=S.FulfillmentRepository.GetOwnedSnapshot(args[2],args[3])
            local middle=GetGameTimer()
            local snapshot=Q.Read(args[2],args[3])
            return S.Ok({inspectionOnly=true,environment=environment,originalMs=middle-began,snapshotMs=GetGameTimer()-middle,
                originalOk=original.ok,snapshotOk=snapshot.ok,originalCode=original.code,snapshotCode=snapshot.code,
                equivalent=original.ok==snapshot.ok and (original.ok and Equal(original.value,snapshot.value) or original.code==snapshot.code),
                note='Compare only on a quiescent fixture; two reads occur at different times.'})
        end)
        busy=false
        if not ok then result=S.Persistence.DatabaseError(result) end
        print('[bcc-stables:snapshot] '..json.encode(result))
    end)
end,false)
