-- Console-only synthetic database fixture. No Core sessions, Assets or Economy calls.
Stables.SnapshotProof={}
local H,S=Stables.SnapshotProof,Stables
local function Id(n) return ('bccf%04x-0000-4000-8000-000000000001'):format(n) end
local C,O,A,G,OLD,NEW=Id(0),Id(1),Id(3),Id(4),Id(5),Id(6)
local busy,worker=false,false
local function Check(v,message) if not v then error(message,0) end end
function H.Definition()
    local t={operationId=O,characterId=C,horseId=Id(2),quoteId=Id(7),walletAccountId=Id(8),sinkAccountId=Id(9),
        catalogId='proof.snapshot',catalogRevision=1,currency='dollars',amount=1}
    local record=S.Operations.New(t,{kind='quote_admission_v1',stableId='snapshot_proof',stableRevision=1,
        modelKey='a_c_horse_morgan_bay',precision=2}).value
    record=S.Operations.Advance(record,0,'payment_pending').value
    record=S.Operations.Advance(record,1,'paid',{paymentReceipt={transactionId=Id(10),operation='transfer',sourceResource='bcc-stables',
        reasonCode='stables.horse_purchase',referenceType='stables_order',referenceId=O,fromAccountId=t.walletAccountId,
        toAccountId=t.sinkAccountId,currency='dollars',amount=1}}).value
    record=S.Operations.Advance(record,2,'fulfilled',{horseId=t.horseId,ownerCharacterId=C}).value
    local request={requestId='stables.register:'..O,assetType='horse',modelKey='a_c_horse_morgan_bay',holderType='character',holderId=C,
        provenanceType='stable_purchase',provenanceId=O,metadataVersion=1,metadata={stablesHorseId=t.horseId},
        reasonCode='stables.horse_purchase',referenceType='stables_order',referenceId=O}
    return {record=record,request=request,assetId=A,generationId=G,oldEpoch=OLD,newEpoch=NEW}
end
local function Counts(db)
    local horse=Id(2)
    return {
        stable=tonumber(db.value('SELECT COUNT(*) FROM fs_character_stables WHERE character_id=?',C)),
        operation=tonumber(db.value('SELECT COUNT(*) FROM fs_operations WHERE character_id=? OR operation_id=?',C,O)),
        horse=tonumber(db.value('SELECT COUNT(*) FROM fs_horses WHERE owner_character_id=? OR horse_id=? OR origin_operation_id=?',C,horse,O)),
        registration=tonumber(db.value('SELECT COUNT(*) FROM fs_asset_registrations WHERE character_id=? OR operation_id=? OR asset_id=?',C,O,A)),
        history=tonumber(db.value('SELECT COUNT(*) FROM fs_horse_history WHERE operation_id=? OR horse_id=?',O,horse)),
        outbox=tonumber(db.value('SELECT COUNT(*) FROM fs_outbox WHERE operation_id=?',O)),
        lease=tonumber(db.value('SELECT COUNT(*) FROM fs_call_leases WHERE character_id=? OR horse_id=? OR generation_id=?',C,horse,G)),
        slot=tonumber(db.value('SELECT COUNT(*) FROM fs_call_slots WHERE character_id=? OR horse_id=? OR generation_id=?',C,horse,G)),
        event=tonumber(db.value('SELECT COUNT(*) FROM fs_horse_runtime_events WHERE horse_id=? OR generation_id=?',horse,G)),
        binding=tonumber(db.value('SELECT COUNT(*) FROM fs_call_bindings WHERE generation_id=?',G)),
        epoch=tonumber(db.value('SELECT COUNT(*) FROM fs_call_process_epochs WHERE generation_id=?',G)),
        recovery=tonumber(db.value('SELECT COUNT(*) FROM fs_call_recoveries WHERE generation_id=?',G))
    }
end
function H.ValidateCounts(counts,revision)
    local expected={stable=1,operation=1,horse=1,registration=1,history=1,outbox=1,
        lease=revision==0 and 0 or 1,slot=revision==1 and 1 or 0,event=revision,binding=revision==0 and 0 or 1,
        epoch=revision==0 and 0 or 1,recovery=revision==2 and 1 or 0}
    if revision~=0 and revision~=1 and revision~=2 then return false end
    for key,n in pairs(expected) do if counts[key]~=n then return false end end
    return true
end
local function Empty(counts) for _,n in pairs(counts) do if n~=0 then return false end end; return true end
local function Inspect()
    local counts=Counts(DB)
    if Empty(counts) then return {state='empty',inspectionOnly=true} end
    local read=S.OwnedSnapshot.Read(O,C)
    return {state='retained',inspectionOnly=true,counts=counts,snapshotOk=read.ok,code=read.code,
        projectionRevision=read.ok and read.value.horse.projectionRevision or nil}
end
local function Create()
    Check(Empty(Counts(DB)),'Fixture namespace occupied; inspect/clear before retry.')
    local d=H.Definition(); local r,t=d.record,d.record.terms
    local facts={eventVersion=1,operationId=O,horseId=t.horseId,assetId=A,characterId=C,catalogId=t.catalogId,modelKey=d.request.modelKey}
    Check(DB.transaction(function(tx)
        Check(Empty(Counts(tx)),'Fixture appeared during creation.')
        tx.exec('INSERT INTO fs_character_stables (character_id) VALUES (?)',C)
        tx.exec([[INSERT INTO fs_operations (operation_id,character_id,horse_id,quote_id,catalog_id,catalog_revision,
            currency,amount,wallet_account_id,sink_account_id,payment_key,fingerprint,state,revision,record_json,payment_transaction_id)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)]],O,C,t.horseId,t.quoteId,t.catalogId,1,'dollars',1,t.walletAccountId,t.sinkAccountId,
            'stables.purchase:'..O,r.fingerprint,'fulfilled',3,json.encode(r),r.paymentReceipt.transactionId)
        tx.exec([[INSERT INTO fs_asset_registrations (operation_id,character_id,horse_id,request_id,model_key,fingerprint,
            request_json,state,asset_id,asset_revision,revision) VALUES (?,?,?,?,?,?,?,'linked',?,1,2)]],
            O,C,t.horseId,d.request.requestId,d.request.modelKey,r.fingerprint..'|'..d.request.modelKey,json.encode(d.request),A)
        tx.exec('INSERT INTO fs_horses (horse_id,owner_character_id,origin_operation_id,catalog_id,catalog_revision) VALUES (?,?,?,?,?)',t.horseId,C,O,t.catalogId,1)
        tx.exec('INSERT INTO fs_horse_history (event_id,horse_id,operation_id,event_kind,facts_json) VALUES (?,?,?,?,?)',O,t.horseId,O,'purchased',json.encode(facts))
        -- Already acknowledged: ordinary outbox publication cannot emit this synthetic event.
        tx.exec('INSERT INTO fs_outbox (event_id,operation_id,event_name,payload_json,delivered) VALUES (?,?,?,?,1)',
            'stables.fulfilled:'..O,O,'stables.purchase.fulfilled.v1',json.encode(facts))
        return true
    end)==true,'Fixture creation was not confirmed.')
end
local function Expect(revision,availability)
    local result=S.OwnedSnapshot.Read(O,C)
    Check(result.ok and result.value.horse.projectionRevision==revision and result.value.horse.availability==availability,
        'Snapshot did not return the expected committed state.')
end
local function Compare()
    local a,b=S.FulfillmentRepository.GetOwnedSnapshot(O,C),S.OwnedSnapshot.Read(O,C)
    Check(a.ok and b.ok and a.value.horse.projectionRevision==b.value.horse.projectionRevision
        and a.value.horse.availability==b.value.horse.availability and a.value.horse.assetId==b.value.horse.assetId,
        'Synthetic recovery snapshot/reference mismatch: '..tostring(a.code)..' / '..tostring(b.code))
end
local function Race(partial,finish,revision,availability,commit)
    local held,release,done=false,false,false
    local success,outcome,writerConnection
    worker=true
    CreateThread(function()
        success,outcome=pcall(DB.transaction,function(tx)
            writerConnection=tx.value('SELECT CONNECTION_ID()')
            partial(tx); held=true
            local deadline=GetGameTimer()+3500
            while not release and GetGameTimer()<deadline do Wait(0) end
            Check(release,'Reader did not release held writer before deadline.')
            if finish then finish(tx) end
            return commit
        end)
        worker=false; done=true
    end)
    local deadline=GetGameTimer()+5000
    while not held and not done and GetGameTimer()<deadline do Wait(0) end
    local readOk,readError=pcall(function()
        Check(held and not done,'Writer did not reach its partial transaction.')
        local readerConnection=DB.value('SELECT CONNECTION_ID()')
        Check(readerConnection~=writerConnection,'Proof requires a separate reader connection.')
        Expect(revision,availability)
    end)
    release=true
    deadline=GetGameTimer()+5000
    while not done and GetGameTimer()<deadline do Wait(0) end
    Check(done,'Writer remains unresolved; retain fixture for inspection.')
    Check(readOk,readError)
    Check(success and outcome==commit,'Writer outcome was not confirmed; fixture retained.')
end
local function Clear()
    Check(not worker,'Writer still running; do not clean fixture.')
    if Empty(Counts(DB)) then return {state='empty',cleared=false} end
    local snapshot=S.OwnedSnapshot.Read(O,C); Check(snapshot.ok,'Fixture snapshot invalid; no deletion allowed.')
    local revision=snapshot.value.horse.projectionRevision
    Check(snapshot.value.registration.assetId==A and H.ValidateCounts(Counts(DB),revision),'Fixture counts/identity changed; no deletion allowed.')
    Check(DB.transaction(function(tx)
        local stable=tx.one('SELECT character_id,selected_horse_id,revision FROM fs_character_stables WHERE character_id=? FOR UPDATE',C)
        Check(stable and stable.selected_horse_id==nil and tonumber(stable.revision)==0,'Synthetic stable changed.')
        local operation=S.Repository.ValidateSnapshot(tx.one('SELECT * FROM fs_operations WHERE operation_id=? AND character_id=? FOR UPDATE',O,C))
        Check(operation.ok and operation.value.fingerprint==H.Definition().record.fingerprint and operation.value.state=='fulfilled','Synthetic purchase changed.')
        local sql=S.OwnedSnapshot.QuerySpec()
        local repeated=S.OwnedSnapshot.Decode(O,C,tx.query(sql,O,C))
        Check(repeated.ok and repeated.value.registration.assetId==A
            and repeated.value.horse.projectionRevision==revision,'Fixture evidence changed during cleanup.')
        Check(H.ValidateCounts(Counts(tx),revision),'Fixture changed during cleanup.')
        for _,entry in ipairs({
            {'fs_horse_runtime_events','horse_id',Id(2)}, {'fs_call_recoveries','generation_id',G},
            {'fs_call_process_epochs','generation_id',G}, {'fs_call_bindings','generation_id',G}, {'fs_call_slots','character_id',C},
            {'fs_call_leases','generation_id',G}, {'fs_horse_history','operation_id',O}, {'fs_outbox','operation_id',O},
            {'fs_horses','horse_id',Id(2)}, {'fs_asset_registrations','operation_id',O},
            {'fs_operations','operation_id',O}, {'fs_character_stables','character_id',C}
        }) do tx.exec('DELETE FROM '..entry[1]..' WHERE '..entry[2]..'=?',entry[3]) end
        return true
    end)==true,'Fixture cleanup commit unconfirmed.')
    Check(Empty(Counts(DB)),'Fixture cleanup disappearance unconfirmed.')
    return {state='empty',cleared=true}
end
function H.ValidateEnvironment(rows)
    if type(rows)~='table' then return false end
    local isolation,autocommit
    for _,row in ipairs(rows) do
        if row.Variable_name=='autocommit' then autocommit=row.Value end
        if row.Variable_name=='transaction_isolation' or row.Variable_name=='tx_isolation' then
            if isolation and isolation~=row.Value then return false end
            isolation=row.Value
        end
    end
    return autocommit=='ON' and (isolation=='REPEATABLE-READ' or isolation=='READ-COMMITTED')
end
local function Run()
    Check(H.ValidateEnvironment(DB.query("SHOW VARIABLES WHERE Variable_name IN ('transaction_isolation','tx_isolation','autocommit')")),
        'Proof requires autocommit ON and READ COMMITTED or REPEATABLE READ.')
    local tables=DB.query([[SELECT TABLE_NAME,ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE()
        AND TABLE_NAME IN ('fs_character_stables','fs_operations','fs_asset_registrations','fs_horses','fs_horse_history','fs_outbox',
            'fs_call_leases','fs_call_slots','fs_call_bindings','fs_call_process_epochs','fs_call_recoveries','fs_horse_runtime_events')]])
    Check(type(tables)=='table' and #tables==12,'All proof tables must exist.')
    for _,row in ipairs(tables) do Check(row.ENGINE=='InnoDB','Snapshot proof requires InnoDB tables.') end
    Create(); Expect(0,'stored')
    Race(function(tx)
        tx.exec([[INSERT INTO fs_call_leases (generation_id,character_id,horse_id,operation_id,asset_id,model_key,session_id,
            source_id,selection_revision,state,revision) VALUES (?,?,?,?,?,?,'snapshot-proof',1,0,'active',2)]],G,C,Id(2),O,A,'a_c_horse_morgan_bay')
        tx.exec('INSERT INTO fs_call_slots (character_id,horse_id,generation_id) VALUES (?,?,?)',C,Id(2),G)
        tx.exec('INSERT INTO fs_call_bindings (generation_id,observer_id,network_id,initial_owner,routing_bucket) VALUES (?,?,1,1,0)',G,Id(11))
        tx.exec('INSERT INTO fs_call_process_epochs (generation_id,process_epoch) VALUES (?,?)',G,OLD)
        tx.exec("UPDATE fs_horses SET availability='active',revision=1 WHERE horse_id=?",Id(2))
    end,function(tx)
        tx.exec([[INSERT INTO fs_horse_runtime_events (event_id,horse_id,generation_id,from_availability,to_availability,prior_revision,revision,reason)
            VALUES (?,?,?,'stored','active',0,1,'bound')]],'stables.runtime:'..G..':active',Id(2),G)
    end,0,'stored',true)
    Expect(1,'active'); Compare()
    Race(function(tx)
        tx.exec("UPDATE fs_call_leases SET state='reconciliation_required',revision=3 WHERE generation_id=?",G)
        tx.exec("UPDATE fs_call_bindings SET state='reconciliation_required',revision=1,reason='restart_lost_observation' WHERE generation_id=?",G)
        tx.exec("UPDATE fs_horses SET availability='stored',revision=2 WHERE horse_id=?",Id(2))
    end,function(tx)
        tx.exec([[INSERT INTO fs_call_recoveries (generation_id,original_epoch,resolved_epoch,prior_revision,prior_reason)
            VALUES (?,?,?,3,'restart_lost_observation')]],G,OLD,NEW)
        tx.exec("UPDATE fs_call_leases SET state='released',revision=5 WHERE generation_id=?",G)
        tx.exec("UPDATE fs_call_bindings SET state='cleared',revision=2,reason=NULL WHERE generation_id=?",G)
        tx.exec([[INSERT INTO fs_horse_runtime_events (event_id,horse_id,generation_id,from_availability,to_availability,prior_revision,revision,reason)
            VALUES (?,?,?,'active','stored',1,2,'process_ended')]],'stables.runtime:'..G..':stored',Id(2),G)
        tx.exec('DELETE FROM fs_call_slots WHERE character_id=?',C)
    end,1,'active',true)
    Expect(2,'stored'); Compare()
    Race(function(tx) tx.exec("UPDATE fs_horses SET availability='active',revision=3 WHERE horse_id=?",Id(2)) end,nil,2,'stored',false)
    Expect(2,'stored')
    local cleared=Clear()
    return {commitSnapshots=true,recoverySnapshot=true,rollbackSnapshot=true,separateConnections=true,
        cleared=cleared.cleared,noFundsMoved=true,noAssetsMutated=true,noEntitySpawned=true}
end
RegisterCommand('BccStablesSnapshotProof',function(source,args)
    if source~=0 then return end
    if #args~=1 or not ({run=true,inspect=true,clear=true})[args[1]] then
        print('[bcc-stables:snapshot-proof] BccStablesSnapshotProof run|inspect|clear'); return
    end
    if busy or worker then print('[bcc-stables:snapshot-proof] busy; wait for writer completion'); return end
    busy=true
    CreateThread(function()
        local ok,result=pcall(function()
            local ready=S.Foundation.RequireReady(); if not ready.ok then return ready end
            return S.Ok(args[1]=='run' and Run() or args[1]=='clear' and Clear() or Inspect())
        end)
        busy=false
        if not ok then result=S.Err('snapshot_proof_failed',tostring(result)..'; fixture retained, inspect before retry.') end
        print('[bcc-stables:snapshot-proof] '..json.encode(result))
    end)
end,false)
