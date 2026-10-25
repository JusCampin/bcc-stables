-- Fixed synthetic namespace. Real care repository and MariaDB transactions;
-- receipts below are fabricated proof evidence, never Inventory consumption.
local S=Stables
local function Id(n) return ('bccd%04x-0000-4000-8000-000000000001'):format(n) end
local CHARACTER,HORSE,ORIGIN=Id(1),Id(2),Id(3)
local busy=false
local function Need(r) assert(S.IsResult(r) and r.ok,json.encode(r)); return r.value end
local function Authority() return S.Ok(true) end -- synthetic character only
local function Purchase()
    return Need(S.Operations.New({operationId=ORIGIN,characterId=CHARACTER,horseId=HORSE,quoteId=Id(4),
        walletAccountId=Id(5),sinkAccountId=Id(6),catalogId='proof.care_repository',catalogRevision=1,currency='dollars',amount=1}))
end
local function Terms(n)
    return {operationId=Id(10+n),characterId=CHARACTER,horseId=HORSE,instanceId=n,definitionId=1,itemRevision=0,
        itemName='synthetic_care_proof',policyRevision=1,healthGain=10,staminaGain=20}
end
local function Counts(db)
    return {stable=tonumber(db.value('SELECT COUNT(*) FROM fs_character_stables WHERE character_id=?',CHARACTER)),
        horse=tonumber(db.value('SELECT COUNT(*) FROM fs_horses WHERE horse_id=? OR owner_character_id=?',HORSE,CHARACTER)),
        purchase=tonumber(db.value('SELECT COUNT(*) FROM fs_operations WHERE operation_id=? OR character_id=?',ORIGIN,CHARACTER)),
        condition=tonumber(db.value('SELECT COUNT(*) FROM fs_horse_condition WHERE horse_id=?',HORSE)),
        care=tonumber(db.value('SELECT COUNT(*) FROM fs_care_operations WHERE horse_id=? OR character_id=?',HORSE,CHARACTER)),
        slots=tonumber(db.value('SELECT COUNT(*) FROM fs_care_slots WHERE horse_id=?',HORSE)),
        effects=tonumber(db.value('SELECT COUNT(*) FROM fs_care_effects WHERE horse_id=?',HORSE)),
        calls=tonumber(db.value('SELECT COUNT(*) FROM fs_call_leases WHERE horse_id=? OR character_id=?',HORSE,CHARACTER)),
        callSlots=tonumber(db.value('SELECT COUNT(*) FROM fs_call_slots WHERE horse_id=? OR character_id=?',HORSE,CHARACTER)),
        history=tonumber(db.value('SELECT COUNT(*) FROM fs_horse_history WHERE horse_id=? OR operation_id=?',HORSE,ORIGIN)),
        outbox=tonumber(db.value('SELECT COUNT(*) FROM fs_outbox WHERE operation_id=?',ORIGIN)),
        assets=tonumber(db.value('SELECT COUNT(*) FROM fs_asset_registrations WHERE operation_id=? OR horse_id=?',ORIGIN,HORSE))}
end
local function Empty(counts)
    for _,n in pairs(counts) do if n~=0 then return false end end
    return true
end
local function PrivateRepository(mode)
    local globals={}; for k,v in pairs(S) do globals[k]=v end
    local database={}; for k,v in pairs(DB) do database[k]=v end
    database.transaction=function(body)
        local committed=DB.transaction(function(tx)
            local proxy={}; for k,v in pairs(tx) do proxy[k]=v end
            proxy.exec=function(sql,...)
                if mode=='rollback' and sql:find('INSERT INTO fs_care_effects',1,true) then return 0 end
                return tx.exec(sql,...)
            end
            return body(proxy)
        end)
        if mode=='lost_reply' and committed==true then error({code='PROOF_COMMIT_REPLY_LOST',outcome='unknown'}) end
        return committed
    end
    local e=setmetatable({Stables=globals,DB=database},{__index=_G})
    assert(load(assert(LoadResourceFile(GetCurrentResourceName(),'server/care_repository.lua')),'@care-proof/private-repository','t',e))()
    Need(e.Stables.CareRepository.Start())
    return e.Stables.CareRepository
end
local function Receipt(record,state)
    local r=Need(S.CareOperations.InventoryRequest(record))
    r.contractVersion=1; r.sourceResource='bcc-stables'; r.state=state or 'consumed'
    r.inventoryId=r.state=='consumed' and 1 or 0; r.replayed=false
    return r
end
local function Condition(db)
    return db.one('SELECT * FROM fs_horse_condition WHERE horse_id=?',HORSE)
end
local function Fence()
    assert(DB.transaction(function(tx)
        assert(tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',CHARACTER))
        assert(S.CareRepository.CheckCharacter(tx,CHARACTER).code=='horse_care_busy')
        return true
    end)==true,'Care reservation fence failed.')
    local call=S.CallRepository.Prepare({characterId=CHARACTER},{},0,Id(30))
    assert(call.code=='horse_care_busy','Actual call repository must refuse before admission.')
end
local function Run()
    assert(Empty(Counts(DB)),'Fixture namespace occupied; inspect before retry, no automatic deletion.')
    local purchase=Purchase(); local t=purchase.terms
    assert(DB.transaction(function(tx)
        assert(Empty(Counts(tx)),'Fixture namespace changed before setup.')
        assert(tx.exec('INSERT INTO fs_character_stables (character_id) VALUES (?)',CHARACTER)==1)
        assert(tx.exec([[INSERT INTO fs_operations (operation_id,character_id,horse_id,quote_id,catalog_id,catalog_revision,
            currency,amount,wallet_account_id,sink_account_id,payment_key,fingerprint,state,revision,record_json)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)]],ORIGIN,CHARACTER,HORSE,t.quoteId,t.catalogId,1,'dollars',1,t.walletAccountId,t.sinkAccountId,
            'stables.purchase:'..ORIGIN,purchase.fingerprint,'reserved',0,json.encode(purchase))==1)
        assert(tx.exec('INSERT INTO fs_horses (horse_id,owner_character_id,origin_operation_id,catalog_id,catalog_revision) VALUES (?,?,?,?,?)',
            HORSE,CHARACTER,ORIGIN,t.catalogId,1)==1)
        return true
    end)==true,'Fixture setup not confirmed.')
    local R=S.CareRepository
    Need(R.Initialize(CHARACTER,{horseId=HORSE,healthCore=50,staminaCore=60,policyRevision=1,revision=0},Authority))
    local first=Need(R.Reserve(Terms(1),Authority)).operation
    Fence()
    local receipt=Receipt(first)
    local rollback=PrivateRepository('rollback').CommitReceipt(Id(11),CHARACTER,receipt,Authority)
    assert(not rollback.ok,'Injected effect failure must not commit.')
    local c=Condition(DB)
    assert(tonumber(c.revision)==0 and tonumber(c.health_core)==50 and tonumber(c.stamina_core)==60)
    assert(Need(R.Get(Id(11),CHARACTER,Authority)).state=='prepared' and Counts(DB).effects==0)
    local lost=PrivateRepository('lost_reply').CommitReceipt(Id(11),CHARACTER,receipt,Authority)
    assert(lost.code=='database_error','Dropped commit reply must remain unknown.')
    assert(Need(R.CommitReceipt(Id(11),CHARACTER,receipt,Authority)).replayed,'Committed effect must replay without increment.')
    c=Condition(DB)
    assert(tonumber(c.revision)==1 and tonumber(c.health_core)==60 and tonumber(c.stamina_core)==80 and Counts(DB).effects==1)
    local second=Need(R.Reserve(Terms(2),Authority)).operation
    assert(Need(R.CommitReceipt(Id(12),CHARACTER,Receipt(second,'cancelled'),Authority)).operation.state=='cancelled')
    assert(tonumber(Condition(DB).revision)==1 and Counts(DB).effects==1)
    local third=Need(R.Reserve(Terms(3),Authority)).operation
    -- Exact synthetic interference only, to demonstrate retained obligation.
    assert(DB.exec('UPDATE fs_horse_condition SET stamina_core=81,revision=2 WHERE horse_id=? AND revision=1 AND health_core=60 AND stamina_core=80',HORSE)==1)
    local pending=Need(R.CommitReceipt(Id(13),CHARACTER,Receipt(third),Authority))
    assert(pending.reconciliationRequired and pending.operation.state=='consumed_effect_pending')
    local reloaded=PrivateRepository('normal')
    assert(Need(reloaded.Get(Id(13),CHARACTER,Authority)).state=='consumed_effect_pending')
    Fence()
    assert(DB.transaction(function(tx)
        assert(tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',CHARACTER))
        local counts=Counts(tx)
        assert(counts.stable==1 and counts.horse==1 and counts.purchase==1 and counts.condition==1 and counts.care==3 and counts.slots==1 and counts.effects==1)
        assert(counts.calls==0 and counts.callSlots==0 and counts.history==0 and counts.outbox==0 and counts.assets==0,'Unexpected external lifecycle artifacts; retain fixture.')
        local row=tx.one('SELECT * FROM fs_operations WHERE operation_id=? FOR UPDATE',ORIGIN)
        assert(Need(S.Repository.ValidateSnapshot(row)).fingerprint==purchase.fingerprint and row.state=='reserved' and tonumber(row.revision)==0)
        local stable=tx.one('SELECT * FROM fs_character_stables WHERE character_id=? FOR UPDATE',CHARACTER)
        assert(not stable.selected_horse_id and tonumber(stable.revision)==0)
        local h=tx.one('SELECT * FROM fs_horses WHERE horse_id=? FOR UPDATE',HORSE)
        assert(h.owner_character_id==CHARACTER and h.origin_operation_id==ORIGIN and h.catalog_id==t.catalogId
            and tonumber(h.catalog_revision)==1 and h.availability=='stored' and h.biological_state=='alive' and tonumber(h.revision)==0)
        c=Condition(tx)
        assert(tonumber(c.revision)==2 and tonumber(c.health_core)==60 and tonumber(c.stamina_core)==81 and tonumber(c.policy_revision)==1)
        local states={'applied','cancelled','consumed_effect_pending'}
        for i=1,3 do
            local saved=Need(R.ValidateSaved(tx.one('SELECT * FROM fs_care_operations WHERE operation_id=? FOR UPDATE',Id(10+i)),CHARACTER))
            local expected=Need(S.CareOperations.New(Terms(i),{horseId=HORSE,healthCore=i==1 and 50 or 60,
                staminaCore=i==1 and 60 or 80,revision=i==1 and 0 or 1,policyRevision=1}))
            assert(saved.fingerprint==expected.fingerprint and saved.state==states[i])
        end
        local effect=tx.one('SELECT * FROM fs_care_effects WHERE operation_id=? FOR UPDATE',Id(11))
        assert(effect.horse_id==HORSE and tonumber(effect.condition_revision)==1)
        local slot=tx.one('SELECT operation_id FROM fs_care_slots WHERE horse_id=? FOR UPDATE',HORSE)
        assert(slot.operation_id==Id(13))
        -- The pending receipt is fabricated and no item/funds ever moved.
        -- This deletion is fixture cleanup, never production reconciliation.
        assert(tx.exec('DELETE FROM fs_care_slots WHERE horse_id=? AND operation_id=?',HORSE,Id(13))==1)
        assert(tx.exec('DELETE FROM fs_care_effects WHERE operation_id=? AND horse_id=?',Id(11),HORSE)==1)
        for i=1,3 do assert(tx.exec('DELETE FROM fs_care_operations WHERE operation_id=? AND character_id=? AND horse_id=?',Id(10+i),CHARACTER,HORSE)==1) end
        assert(tx.exec('DELETE FROM fs_horse_condition WHERE horse_id=?',HORSE)==1)
        assert(tx.exec('DELETE FROM fs_horses WHERE horse_id=? AND owner_character_id=? AND origin_operation_id=?',HORSE,CHARACTER,ORIGIN)==1)
        assert(tx.exec('DELETE FROM fs_operations WHERE operation_id=? AND character_id=?',ORIGIN,CHARACTER)==1)
        assert(tx.exec('DELETE FROM fs_character_stables WHERE character_id=?',CHARACTER)==1)
        return true
    end)==true,'Fixture cleanup not confirmed; inspect before retry.')
    assert(Empty(Counts(DB)),'Fixture evidence remains after cleanup.')
    return {cleared=true,atomicEffect=true,rollback=true,lostCommitReply=true,replayedOnce=true,cancellation=true,
        consumedPendingRetained=true,lifecycleFence=true,noItemsConsumed=true,noFundsMoved=true,noAssetsMutated=true,noEntitySpawned=true}
end
RegisterCommand('BccStablesCareProof',function(source,args)
    if source~=0 then return end
    args=args or {}
    if #args~=1 or (args[1]~='run' and args[1]~='inspect') then print('[bcc-stables:care-proof] BccStablesCareProof run|inspect'); return end
    if busy then print('[bcc-stables:care-proof] busy'); return end
    busy=true
    CreateThread(function()
        local ok,result=pcall(function()
            local ready=S.Foundation.RequireReady(); if not ready.ok then return ready end
            return S.Ok(args[1]=='run' and Run() or {inspectionOnly=true,counts=Counts(DB)})
        end)
        busy=false
        if not ok then result=S.Err('care_proof_failed',tostring(result)..'; fixture retained, inspect before retry.') end
        print('[bcc-stables:care-proof] '..json.encode(result))
    end)
end,true)
