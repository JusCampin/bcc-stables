local function fixture()
    local e=setmetatable({},{__index=_G})
    local m={calls={},commands={},denied=false}
    e.RegisterCommand=function(name,fn) m.commands[name]=fn end
    e.print=function() end
    for _,file in ipairs({'shared/contracts.lua','server/operations.lua','server/care_operations.lua'}) do assert(loadfile(file,'t',e))() end
    local S=e.Stables
    local terms={operationId='10000000-0000-4000-8000-000000000001',characterId='20000000-0000-4000-8000-000000000002',
        horseId='30000000-0000-4000-8000-000000000003',instanceId=5,definitionId=10,itemRevision=2,itemName='consumable_apple',policyRevision=1,healthGain=20,staminaGain=20}
    local condition={horseId=terms.horseId,healthCore=60,staminaCore=70,policyRevision=1,revision=0}
    m.record=S.CareOperations.New(terms,condition).value
    m.receipt=S.CareOperations.InventoryRequest(m.record).value
    m.receipt.contractVersion=1; m.receipt.sourceResource='bcc-stables'; m.receipt.state='consumed'; m.receipt.inventoryId=7; m.receipt.replayed=true
    m.contract={contractVersion=1,ready=true,durableConsumption=1}
    e.GetResourceState=function() return m.stopped and 'stopped' or 'started' end
    e.json={encode=function() return '{}' end}
    local provider={}
    local function Method(name,body)
        -- Real CFX provider callables can be tables; use one in every case.
        provider[name]=setmetatable({},{__call=function(_,self,request)
            assert(self==provider); m.calls[#m.calls+1]={name=name,request=request}
            if m.throw then error('lost reply') end
            return body(request)
        end})
    end
    Method('GetConsumptionContract',function() return m.contract end)
    Method('InspectCharacterConsumption',function(request)
        assert(request.operationId==terms.operationId and request.expectedRevision==2 and request.purpose=='stables.care.v1')
        if m.departOnRead then m.denied=true end
        return m.result or {ok=true,value=S.Copy(m.receipt)}
    end)
    e.exports={['feather-inventory']=provider}
    S.Foundation={RequireReady=function() return S.Ok(true) end}
    S.CareRepository={Get=function(id,char,authorize)
        assert(id==terms.operationId and char==terms.characterId)
        local auth=authorize(); if not auth.ok then return auth end
        return S.Ok(S.Copy(m.record))
    end,CommitReceipt=function(id,char,receipt,authorize)
        local auth=authorize(); if not auth.ok then return auth end
        m.commits=(m.commits or 0)+1
        return S.CareOperations.Resolve(m.record,receipt)
    end}
    m.authorize=function() return m.denied and S.Err('session_stale','Departed.') or S.Ok(true) end
    assert(loadfile('server/care_inventory.lua','t',e))()
    m.i,m.S,m.env=e.Stables.CareInventory,S,e
    m.recover=function() return m.i.Recover(terms.operationId,terms.characterId,m.authorize) end
    return m
end
local n=0
local function test(name,fn) fn(); n=n+1; print('PASS care Inventory adapter '..name) end
test('optional ready contract probe accepts callable table without SQL or item action',function()
    local m=fixture(); local result=m.i.Probe()
    assert(result.ok and result.value.feedingEnabled==false and #m.calls==1 and m.calls[1].name=='GetConsumptionContract')
end)
test('stopped unsupported and unready provider cannot recover',function()
    local m=fixture(); m.stopped=true; assert(m.i.Probe().code=='inventory_unavailable' and #m.calls==0)
    for _,contract in ipairs({false,{}, {contractVersion=2,ready=true,durableConsumption=1},{contractVersion=1,ready=false,durableConsumption=0}}) do
        m=fixture(); m.contract=contract; assert(not m.recover().ok and not m.commits and #m.calls==1)
    end
end)
test('provider exception remains unknown; no automatic consume or cancellation',function()
    local m=fixture(); m.throw=true
    assert(m.recover().code=='inventory_outcome_unknown' and #m.calls==1 and not m.commits)
end)
test('absent receipt retains care and does not infer cancellation',function()
    local m=fixture(); m.result={ok=false,error={code='not_found'}}
    assert(m.recover().code=='care_consumption_unresolved' and #m.calls==2 and not m.commits)
    assert(m.record.state=='prepared')
end)
test('Inventory error envelope is normalized and caller trust refusal retained',function()
    local m=fixture(); m.result={ok=false,error={code='authorization_denied',message='untrusted'}}
    assert(m.recover().code=='inventory_authorization_denied' and not m.commits)
    m.result={ok=false,error={code={}}}; assert(m.recover().code=='inventory_invalid_contract')
    m.result={}; assert(m.recover().code=='inventory_invalid_contract')
end)
test('mismatched item source horse policy or operation receipt never commits',function()
    for _,key in ipairs({'sourceResource','operationId','effectReference','instanceId','expectedRevision'}) do
        local m=fixture(); m.receipt[key]=type(m.receipt[key])=='number' and m.receipt[key]+1 or 'other'
        assert(not m.recover().ok and not m.commits)
    end
end)
test('matching consumed receipt recovers exact operation without item removal call',function()
    local m=fixture(); local result=m.recover()
    assert(result.ok and result.value.operation.state=='consumed_effect_pending' and m.commits==1 and #m.calls==2)
    for _,call in ipairs(m.calls) do assert(call.name~='ConsumeCharacterItemOnce' and call.name~='CancelCharacterConsumption') end
end)
test('confirmed cancellation recovers cancellation without benefit',function()
    local m=fixture(); m.receipt.state='cancelled'; m.receipt.inventoryId=0
    assert(m.recover().value.operation.state=='cancelled' and m.commits==1)
end)
test('authority rechecked after provider read; session departure cannot commit',function()
    local m=fixture(); m.departOnRead=true
    assert(m.recover().code=='session_stale' and not m.commits)
    m=fixture(); m.denied=true; assert(m.recover().code=='session_stale' and #m.calls==0)
end)
test('terminal local operation verifies locally without provider round trip',function()
    local m=fixture(); local resolved=m.S.CareOperations.Resolve(m.record,m.receipt).value.operation
    m.record=m.S.CareOperations.Apply(resolved,resolved.before).value.operation
    m.stopped=true
    assert(m.recover().value.replayed and #m.calls==0 and m.commits==1)
end)
test('smoke command is console only and contract read only',function()
    local m=fixture(); local command=m.commands.BccStablesCareInventorySmokeTest
    command(1,{}); command(0,{'extra'}); assert(#m.calls==0)
    command(0,{}); assert(#m.calls==1 and not m.commits)
end)
print(('%d/%d care Inventory adapter cases passed; CFX provider/recovery integration remains pending.'):format(n,n))
