local env=setmetatable({},{__index=_G})
env.RegisterCommand=function() end
assert(loadfile('shared/contracts.lua','t',env))()
assert(loadfile('server/operations.lua','t',env))()
assert(loadfile('server/care_operations.lua','t',env))()
local C,S=env.Stables.CareOperations,env.Stables
local function Terms() return {operationId='10000000-0000-4000-8000-000000000001',characterId='20000000-0000-4000-8000-000000000002',
    horseId='30000000-0000-4000-8000-000000000003',instanceId=5,definitionId=10,itemRevision=2,itemName='existing_apple',policyRevision=1,healthGain=20,staminaGain=30} end
local function Condition() return {horseId=Terms().horseId,healthCore=71,staminaCore=90,policyRevision=1,revision=0} end
local function Prepared() return assert(C.New(Terms(),Condition()).value) end
local function Receipt(state)
    local r=C.InventoryRequest(Prepared()).value
    r.contractVersion=1; r.sourceResource='bcc-stables'; r.state=state or 'consumed'; r.inventoryId=r.state=='consumed' and 7 or 0; r.replayed=false
    return r
end
local count=0
local function test(name,fn) fn(); count=count+1; print('PASS care model '..name) end
test('explicit condition seed and immutable bounded targets; no client baseline default',function()
    assert(not C.New(Terms(),nil).ok)
    local t,b=Terms(),Condition(); local r=C.New(t,b).value
    assert(r.after.healthCore==91 and r.after.staminaCore==100 and r.after.revision==1)
    t.healthGain=100; b.healthCore=0
    assert(r.terms.healthGain==20 and r.before.healthCore==71 and C.Validate(r).ok)
end)
test('full condition and zero benefit refuse before consumption',function()
    local b=Condition(); b.healthCore=100; b.staminaCore=100
    assert(C.New(Terms(),b).code=='care_no_benefit')
    local t=Terms(); t.healthGain=0; t.staminaGain=0
    assert(C.New(t,Condition()).code=='care_no_benefit')
end)
test('invalid terms values policies and revision overflow fail closed',function()
    for _,patch in ipairs({{healthGain=-1},{staminaGain=101},{itemRevision=1.5},{instanceId=0},{definitionId='10'},
        {policyRevision=0},{policyRevision=2},{itemName='bad|name'},{operationId='bad'},{unexpected=true}}) do
        local t=Terms(); for k,v in pairs(patch) do t[k]=v end; assert(not C.New(t,Condition()).ok)
    end
    local b=Condition(); b.revision=9007199254740991; assert(not C.New(Terms(),b).ok)
end)
test('fingerprint binds benefits and condition baseline',function()
    local original=Prepared()
    local t=Terms(); t.healthGain=21; assert(C.New(t,Condition()).value.fingerprint~=original.fingerprint)
    local b=Condition(); b.healthCore=70; assert(C.New(Terms(),b).value.fingerprint~=original.fingerprint)
end)
test('receipt binds exact operation horse policy item owner source and revision',function()
    for _,key in ipairs({'operationId','characterId','instanceId','definitionId','expectedRevision','itemName','purpose','effectReference','sourceResource'}) do
        local receipt=Receipt(); receipt[key]=type(receipt[key])=='number' and receipt[key]+1 or 'different'
        assert(not C.Resolve(Prepared(),receipt).ok)
    end
    assert(not C.Resolve(Prepared(),{state='not_found'}).ok)
end)
test('durable consumed replay stays owed until explicit apply',function()
    local resolved=C.Resolve(Prepared(),Receipt()).value
    assert(resolved.operation.state=='consumed_effect_pending' and resolved.operation.revision==1)
    local receipt=Receipt(); receipt.replayed=true
    local replay=C.Resolve(resolved.operation,receipt).value
    assert(replay.replayed and replay.operation.state=='consumed_effect_pending')
    assert(C.Validate(S.Copy(replay.operation)).ok)
end)
test('cancellation is terminal and cannot yield a benefit or change to consumed',function()
    local cancelled=C.Resolve(Prepared(),Receipt('cancelled')).value.operation
    assert(cancelled.state=='cancelled' and C.Validate(cancelled).ok)
    assert(not C.Apply(cancelled,Condition()).ok and not C.Resolve(cancelled,Receipt()).ok)
end)
test('effect advances condition independently once and refuses second apply',function()
    local pending=C.Resolve(Prepared(),Receipt()).value.operation
    local result=C.Apply(pending,Condition()).value
    assert(result.operation.state=='applied' and result.operation.revision==2 and result.condition.revision==1)
    assert(result.condition.healthCore==91 and result.condition.staminaCore==100)
    assert(C.Validate(result.operation).ok and not C.Apply(result.operation,result.condition).ok)
    assert(C.Resolve(result.operation,Receipt()).value.replayed)
end)
test('changed condition retains consumed obligation and refuses rebase',function()
    local pending=C.Resolve(Prepared(),Receipt()).value.operation
    for _,key in ipairs({'revision','healthCore','staminaCore','policyRevision'}) do
        local c=Condition(); c[key]=c[key]+1
        assert(C.Apply(pending,c).code=='condition_revision_conflict')
    end
    assert(pending.state=='consumed_effect_pending' and pending.revision==1)
end)
test('tampered journal target fingerprint state and receipt refuse',function()
    local r=Prepared(); r.after.healthCore=100; assert(not C.Validate(r).ok)
    r=Prepared(); r.fingerprint='bad'; assert(not C.Validate(r).ok)
    r=Prepared(); r.revision=2; assert(not C.Validate(r).ok)
    r=C.Resolve(Prepared(),Receipt()).value.operation; r.receipt.instanceId=100; assert(not C.Validate(r).ok)
end)
print(('%d/%d care model cases passed; no persistence/economic/native integration implied.'):format(count,count))
