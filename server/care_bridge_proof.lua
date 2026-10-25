-- Development-only cross-resource proof; one real disposable Inventory unit,
-- isolated bccb Stables rows, no player/Asset/Economy/native interactions.
local S=Stables
local function Id(n) return ('bccb%04x-0000-4000-8000-000000000001'):format(n) end
local CHAR,HORSE,ORIGIN=Id(1),Id(2),Id(3)
local NAME='proof_stables_care_receipt_v1'
local busy=false
local function Need(r) assert(S.IsResult(r) and r.ok,json.encode(r)); return r.value end
local function Provider(action)
    assert(GetResourceState('feather-inventory')=='started','Inventory unavailable.')
    local r=exports['feather-inventory']:StablesCareProofFixture(action)
    assert(type(r)=='table' and r.ok==true,json.encode(r)); return r.value
end
local function Authority() return S.Ok(true) end -- fixed synthetic character
local function Base()
    return Need(S.Operations.New({operationId=ORIGIN,characterId=CHAR,horseId=HORSE,quoteId=Id(4),walletAccountId=Id(5),
        sinkAccountId=Id(6),catalogId='proof.care_bridge',catalogRevision=1,currency='dollars',amount=1}))
end
local function Terms(request,index)
    assert(type(request)=='table' and request.operationId==Id(10+index) and request.characterId==CHAR
        and request.itemName==NAME and request.expectedRevision==0 and request.purpose=='stables.care.v1'
        and request.effectReference==HORSE..':policy1','Unexpected provider fixture terms.')
    return {operationId=request.operationId,characterId=CHAR,horseId=HORSE,instanceId=request.instanceId,
        definitionId=request.definitionId,itemRevision=0,itemName=NAME,policyRevision=1,healthGain=20,staminaGain=20}
end
local function Counts(db)
    local queries={stable={'SELECT COUNT(*) FROM fs_character_stables WHERE character_id=?',CHAR},
        purchase={'SELECT COUNT(*) FROM fs_operations WHERE operation_id=? OR character_id=?',ORIGIN,CHAR},
        horse={'SELECT COUNT(*) FROM fs_horses WHERE horse_id=? OR owner_character_id=?',HORSE,CHAR},
        condition={'SELECT COUNT(*) FROM fs_horse_condition WHERE horse_id=?',HORSE},
        care={'SELECT COUNT(*) FROM fs_care_operations WHERE horse_id=? OR character_id=?',HORSE,CHAR},
        slots={'SELECT COUNT(*) FROM fs_care_slots WHERE horse_id=?',HORSE},effects={'SELECT COUNT(*) FROM fs_care_effects WHERE horse_id=?',HORSE},
        calls={'SELECT COUNT(*) FROM fs_call_leases WHERE horse_id=? OR character_id=?',HORSE,CHAR},
        callSlots={'SELECT COUNT(*) FROM fs_call_slots WHERE horse_id=? OR character_id=?',HORSE,CHAR},
        history={'SELECT COUNT(*) FROM fs_horse_history WHERE horse_id=? OR operation_id=?',HORSE,ORIGIN},
        outbox={'SELECT COUNT(*) FROM fs_outbox WHERE operation_id=?',ORIGIN},
        assets={'SELECT COUNT(*) FROM fs_asset_registrations WHERE operation_id=? OR horse_id=?',ORIGIN,HORSE}}
    local counts={}; for k,q in pairs(queries) do counts[k]=tonumber(db.value(table.unpack(q))) end
    return counts
end
local function Empty(counts) for _,v in pairs(counts) do if v~=0 then return false end end; return true end
local function Run()
    assert(Empty(Counts(DB)),'Stables bridge namespace occupied; inspect before retry.')
    Need(S.CareInventory.Probe())
    local manifest=Provider('prepare')
    local firstTerms,secondTerms=Terms(manifest.consumptionRequest,1),Terms(manifest.cancellationRequest,2)
    assert(firstTerms.instanceId==secondTerms.instanceId and firstTerms.definitionId==secondTerms.definitionId)
    local purchase=Base(); local t=purchase.terms
    assert(DB.transaction(function(tx)
        assert(Empty(Counts(tx)),'Bridge namespace changed.')
        assert(tx.exec('INSERT INTO fs_character_stables (character_id) VALUES (?)',CHAR)==1)
        assert(tx.exec([[INSERT INTO fs_operations (operation_id,character_id,horse_id,quote_id,catalog_id,catalog_revision,
            currency,amount,wallet_account_id,sink_account_id,payment_key,fingerprint,state,revision,record_json)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)]],ORIGIN,CHAR,HORSE,t.quoteId,t.catalogId,1,'dollars',1,t.walletAccountId,t.sinkAccountId,
            'stables.purchase:'..ORIGIN,purchase.fingerprint,'reserved',0,json.encode(purchase))==1)
        assert(tx.exec('INSERT INTO fs_horses (horse_id,owner_character_id,origin_operation_id,catalog_id,catalog_revision) VALUES (?,?,?,?,?)',
            HORSE,CHAR,ORIGIN,t.catalogId,1)==1)
        return true
    end)==true,'Stables bridge setup not confirmed.')
    local R=S.CareRepository
    Need(R.Initialize(CHAR,{horseId=HORSE,healthCore=50,staminaCore=60,policyRevision=1,revision=0},Authority))
    Need(R.Reserve(firstTerms,Authority))
    local missing=S.CareInventory.Recover(Id(11),CHAR,Authority)
    assert(missing.code=='care_consumption_unresolved','Absent receipt must not cancel or award care: '..json.encode(missing))
    assert(Need(R.Get(Id(11),CHAR,Authority)).state=='prepared')
    -- Provider returns commitment only, deliberately withholding its receipt.
    -- The normal Inspect export is the sole receipt path into CareInventory.
    assert(Provider('consume').state=='consumed')
    local recovered=Need(S.CareInventory.Recover(Id(11),CHAR,Authority))
    assert(recovered.operation.state=='applied','Exact consumed receipt must apply the reserved effect.')
    assert(Need(S.CareInventory.Recover(Id(11),CHAR,Authority)).replayed,'Terminal care must replay without another effect.')
    Need(R.Reserve(secondTerms,Authority))
    assert(Provider('cancel').state=='cancelled')
    assert(Need(S.CareInventory.Recover(Id(12),CHAR,Authority)).operation.state=='cancelled')
    assert(DB.transaction(function(tx)
        local stable=tx.one('SELECT * FROM fs_character_stables WHERE character_id=? FOR UPDATE',CHAR)
        assert(stable and not stable.selected_horse_id and tonumber(stable.revision)==0)
        local counts=Counts(tx)
        assert(counts.stable==1 and counts.purchase==1 and counts.horse==1 and counts.condition==1 and counts.care==2 and counts.slots==0 and counts.effects==1)
        assert(counts.calls==0 and counts.callSlots==0 and counts.history==0 and counts.outbox==0 and counts.assets==0,'Unexpected bridge artifacts; retain both fixtures.')
        local h=tx.one('SELECT * FROM fs_horses WHERE horse_id=? FOR UPDATE',HORSE)
        assert(h.owner_character_id==CHAR and h.origin_operation_id==ORIGIN and h.catalog_id==t.catalogId and tonumber(h.catalog_revision)==1
            and h.biological_state=='alive' and h.availability=='stored' and tonumber(h.revision)==0)
        local p=tx.one('SELECT * FROM fs_operations WHERE operation_id=? FOR UPDATE',ORIGIN)
        assert(Need(S.Repository.ValidateSnapshot(p)).fingerprint==purchase.fingerprint and p.state=='reserved' and tonumber(p.revision)==0)
        local c=tx.one('SELECT * FROM fs_horse_condition WHERE horse_id=? FOR UPDATE',HORSE)
        assert(tonumber(c.health_core)==70 and tonumber(c.stamina_core)==80 and tonumber(c.revision)==1 and tonumber(c.policy_revision)==1)
        for i,terms in ipairs({firstTerms,secondTerms}) do
            local saved=Need(R.ValidateSaved(tx.one('SELECT * FROM fs_care_operations WHERE operation_id=? FOR UPDATE',terms.operationId),CHAR))
            local before={horseId=HORSE,healthCore=i==1 and 50 or 70,staminaCore=i==1 and 60 or 80,revision=i==1 and 0 or 1,policyRevision=1}
            assert(saved.fingerprint==Need(S.CareOperations.New(terms,before)).fingerprint and saved.state==(i==1 and 'applied' or 'cancelled'))
        end
        local effect=tx.one('SELECT * FROM fs_care_effects WHERE operation_id=? FOR UPDATE',Id(11))
        assert(effect.horse_id==HORSE and tonumber(effect.condition_revision)==1)
        assert(tx.exec('DELETE FROM fs_care_effects WHERE operation_id=? AND horse_id=?',Id(11),HORSE)==1)
        for i=1,2 do assert(tx.exec('DELETE FROM fs_care_operations WHERE operation_id=? AND character_id=? AND horse_id=?',Id(10+i),CHAR,HORSE)==1) end
        assert(tx.exec('DELETE FROM fs_horse_condition WHERE horse_id=?',HORSE)==1)
        assert(tx.exec('DELETE FROM fs_horses WHERE horse_id=? AND owner_character_id=? AND origin_operation_id=?',HORSE,CHAR,ORIGIN)==1)
        assert(tx.exec('DELETE FROM fs_operations WHERE operation_id=? AND character_id=?',ORIGIN,CHAR)==1)
        assert(tx.exec('DELETE FROM fs_character_stables WHERE character_id=?',CHAR)==1)
        return true
    end)==true,'Stables bridge cleanup not confirmed; retain Inventory evidence.')
    assert(Empty(Counts(DB)))
    local cleared=Provider('clear'); assert(cleared.cleared and cleared.productionAllowlistUnchanged)
    return {cleared=true,realItemConsumedOnce=true,missingReceiptRetained=true,receiptReadRecovery=true,
        benefitAppliedOnce=true,cancellationRecovered=true,productionAllowlistUnchanged=true,
        noPlayerItemsTouched=true,noFundsMoved=true,noAssetsMutated=true,noEntitySpawned=true}
end
RegisterCommand('BccStablesCareBridgeProof',function(source,args)
    if source~=0 then return end
    args=args or {}
    if #args~=1 or (args[1]~='run' and args[1]~='inspect') then print('[bcc-stables:care-bridge] BccStablesCareBridgeProof run|inspect'); return end
    if busy then print('[bcc-stables:care-bridge] busy'); return end
    busy=true
    CreateThread(function()
        local called,result=pcall(function()
            local ready=S.Foundation.RequireReady(); if not ready.ok then return ready end
            if args[1]=='run' then return S.Ok(Run()) end
            local observed,value=pcall(Provider,'inspect')
            return S.Ok({inspectionOnly=true,counts=Counts(DB),inventory=observed and value or nil,inventoryError=not observed and tostring(value) or nil})
        end)
        busy=false
        if not called then result=S.Err('care_bridge_proof_failed',tostring(result)..'; retain both fixtures and inspect before retry.') end
        print('[bcc-stables:care-bridge] '..json.encode(result))
    end)
end,true)
