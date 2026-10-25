local function fixture()
    local e=setmetatable({RegisterCommand=function() end},{__index=_G})
    for _,file in ipairs({'shared/contracts.lua','server/operations.lua','server/care_operations.lua','config/care.lua','server/care_policy.lua'}) do assert(loadfile(file,'t',e))() end
    return {e=e,p=e.Stables.CarePolicy,c=e.StablesCareConfig}
end
local horse='30000000-0000-4000-8000-000000000003'
local function Ids() return {operationId='10000000-0000-4000-8000-000000000001',characterId='20000000-0000-4000-8000-000000000002',horseId=horse} end
local function Item(name) return {id=5,revision=2,definition={id=10,name=name or 'consumable_apple',type='item_item',instanceMode='stack'}} end
local function Condition() return {horseId=horse,healthCore=71,staminaCore=67,revision=0,policyRevision=1} end
local function Facts() return {sessionCurrent=true,sameHorse=true,sameOwner=true,defaultRoute=true,ownerAlive=true,horseAlive=true,
    unoccupied=true,notLeading=true,movementIdle=true,distance=2.5,observedAt=1000,now=2000} end
local n=0
local function test(name,fn) fn(); n=n+1; print('PASS care policy '..name) end
test('legacy food keys gains and disabled activation snapshot',function()
    local m=fixture(); local r=m.p.Start(); assert(r.ok and r.value.foodEntries==3 and r.value.feedHealth==20 and r.value.feedStamina==20)
    assert(not r.value.enabled and not r.value.activeCareAvailable and r.value.existingHorses=='uninitialized')
    for _,name in ipairs({'consumable_haycube','consumable_carrots','consumable_apple'}) do
        local built=m.p.BuildOperation(Ids(),Item(name),Condition()).value
        assert(built.after.healthCore==91 and built.after.staminaCore==87 and built.terms.itemName==name)
    end
end)
test('policy activation refused until remaining gameplay gates exist',function()
    local m=fixture(); m.c.enabled=true; assert(m.p.Start().code=='care_not_implemented')
    assert(not m.p.NewHorseSeed(horse).ok)
end)
test('new horse seed explicit and existing conditions are never adopted or overwritten',function()
    local m=fixture(); assert(m.p.Start().ok)
    local seed=m.p.NewHorseSeed(horse).value
    assert(seed.healthCore==100 and seed.staminaCore==100 and seed.policyRevision==1 and seed.revision==0)
    assert(not m.p.BuildOperation(Ids(),Item(),nil).ok)
    assert(m.p.BuildOperation(Ids(),Item(),seed).code=='care_no_benefit')
    seed.healthCore=1; assert(m.p.NewHorseSeed(horse).value.healthCore==100)
end)
test('configured policy is immutable until an explicit restart',function()
    local m=fixture(); assert(m.p.Start().ok)
    m.c.feed.healthGain=99; m.c.feed.items[1]='new_food'; m.c.newHorse.healthCore=0
    assert(m.p.BuildOperation(Ids(),Item('consumable_haycube'),Condition()).value.terms.healthGain==20)
    assert(m.p.NewHorseSeed(horse).value.healthCore==100)
end)
test('unknown unique or wrong type item cannot resolve care terms',function()
    local m=fixture(); assert(m.p.Start().ok)
    assert(m.p.BuildOperation(Ids(),Item('horsebrush'),Condition()).code=='care_food_unavailable')
    local item=Item(); item.definition.instanceMode='unique'; assert(not m.p.BuildOperation(Ids(),item,Condition()).ok)
    item=Item(); item.definition.type='item_weapon'; assert(not m.p.BuildOperation(Ids(),item,Condition()).ok)
    local ids=Ids(); ids.healthGain=100; assert(not m.p.BuildOperation(ids,Item(),Condition()).ok)
end)
test('invalid config bounds duplicate names holes and unknown fields fail startup',function()
    for _,mutate in ipairs({function(c) c.feed.maxDistance=0/0 end,function(c) c.feed.durationMs=16000 end,
        function(c) c.feed.observationTtlMs=0 end,function(c) c.feed.items[2]=c.feed.items[1] end,
        function(c) c.feed.items[2]=nil end,function(c) c.newHorse.healthCore=101 end,
        function(c) c.feed.healthGain=-1 end,function(c) c.feed.boostMultiplier=2 end,
        function(c) c.feed.items={'bad|name'} end,function(c) c.enabled='false' end}) do
        local m=fixture(); mutate(m.c); assert(not m.p.Start().ok)
    end
end)
test('active facts require exact booleans fresh observation and bounded distance',function()
    local m=fixture(); assert(m.p.Start().ok)
    local facts=Facts(); assert(m.p.CheckActiveFacts(facts).value.durationMs==5000)
    for k,v in pairs(facts) do if type(v)=='boolean' then
        local r=Facts(); r[k]=false; assert(not m.p.CheckActiveFacts(r).ok)
        r[k]=nil; assert(not m.p.CheckActiveFacts(r).ok)
    end end
    for _,patch in ipairs({{distance=2.51},{distance=0/0},{distance=-1},{observedAt=999},{observedAt=2001},{now='2000'},{clientApproved=true}}) do
        local f=Facts(); for k,v in pairs(patch) do f[k]=v end; assert(not m.p.CheckActiveFacts(f).ok)
    end
end)
test('policy version mismatch never recomputes an old condition benefit',function()
    local m=fixture(); m.c.revision=2; assert(m.p.Start().ok)
    assert(not m.p.BuildOperation(Ids(),Item(),Condition()).ok)
end)
print(('%d/%d care policy cases passed; facts are modeled, native eligibility/projection unimplemented.'):format(n,n))
