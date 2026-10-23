local base=assert(loadfile('tests/fixtures/linked_services.lua'))()
local count=0
local function test(name,body)
    local ok,err=pcall(body); assert(ok,name..': '..tostring(err)); count=count+1; print('PASS fulfillment '..name)
end
local function size(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local fixture=assert(loadfile('tests/fixtures/fulfillment_services.lua'))()
test('paid linked order commits horse history outbox and fulfilled together',function()
    local m=fixture(); local r=m.fulfill(); assert(r.ok,tostring(r.code))
    assert(r.value.state=='fulfilled' and r.value.revision==3 and r.value.assetId==m.asset.assetId and r.value.outboxPending)
    assert(size(m.db.horses)==1 and size(m.db.history)==1 and size(m.db.outbox)==1)
    assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='fulfilled' and m.asset.status=='active')
end)
test('replay and restart retain exactly one projection and event',function()
    local m=fixture(); assert(m.fulfill().ok); assert(m.fulfill().value.revision==3)
    m.reload(); assert(m.start().ok); m.loadLinked()
    assert(m.get().value.assetId==m.asset.assetId and m.fulfill().ok)
    assert(size(m.db.horses)==1 and size(m.db.history)==1 and size(m.db.outbox)==1)
end)
test('history outbox and CAS failures roll back all fulfillment writes',function()
    for _,flag in ipairs({'failHistory','failOutbox','failCas'}) do
        local m=fixture(); m[flag]=true; assert(not m.fulfill().ok)
        assert(next(m.db.horses)==nil and next(m.db.history)==nil and next(m.db.outbox)==nil)
        assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='paid')
        m[flag]=false; assert(m.fulfill().ok)
    end
end)
test('unknown committed response recovers same fulfilled state without reinserting',function()
    local m=fixture(); m.unknownCommit=true; assert(m.fulfill().code=='database_error')
    m.unknownCommit=false; assert(m.get().value.state=='fulfilled' and m.fulfill().ok)
    assert(size(m.db.horses)==1 and size(m.db.history)==1 and size(m.db.outbox)==1)
end)
test('disabled fulfillment blocks mutation but leaves stored inspection available',function()
    local m=fixture(); assert(m.fulfill().ok)
    m.env.StablesConfig.purchaseFulfillment=false; assert(m.S.Fulfillment.Start().ok)
    assert(m.fulfill().code=='fulfillment_disabled' and m.get().ok)
end)
test('fulfillment converts reservation to owned capacity without freeing a slot',function()
    local m=fixture(); m.env.StablesConfig.ownedHorseLimit=1; assert(m.fulfill().ok)
    local terms=m.S.Copy(m.t)
    terms.operationId='10000000-0000-4000-8000-000000000099'; terms.horseId=terms.operationId; terms.quoteId=terms.operationId
    assert(m.r.Reserve(terms).code=='capacity_exceeded')
end)
test('fulfilled purchases cannot use pre-fulfillment retirement refund',function()
    local m=fixture(); assert(m.fulfill().ok)
    assert(m.cleanup().code=='registration_not_fenced' and not m.retireCalls and not m.refunds)
    assert(m.asset.status=='active')
end)
test('other character and proof operations cannot fulfill or read projection',function()
    local m=fixture('quote_intent_proof_v1'); assert(m.fulfill().code=='intent_conflict')
    m=fixture(); m.context.characterId='20000000-0000-4000-8000-000000000099'
    assert(m.fulfill().code=='operation_not_found' and m.get().code=='operation_not_found')
end)
test('changed canonical owner blocks fulfillment before local writes',function()
    local m=fixture(); m.asset.owner.holderId='20000000-0000-4000-8000-000000000099'
    assert(m.fulfill().code=='asset_changed' and next(m.db.horses)==nil)
end)
test('post-commit canonical change suppresses success and cached-owner access',function()
    local m=fixture(); local reads=0
    m.onAssetRead=function() reads=reads+1; if reads==3 then m.asset.owner.holderId='20000000-0000-4000-8000-000000000099' end end
    assert(m.fulfill().code=='asset_changed' and size(m.db.horses)==1)
    assert(m.get().code=='asset_changed')
end)
test('session change before commit prevents writes',function()
    local m=fixture(); m.onAssetRead=function() m.current=false end
    assert(m.fulfill().code=='session_stale' and next(m.db.horses)==nil)
end)
test('session change after commit preserves durable recovery but hides response',function()
    local m=fixture(); local reads=0
    m.onAssetRead=function() reads=reads+1; if reads==3 then m.current=false end end
    assert(m.fulfill().code=='session_stale' and size(m.db.horses)==1)
    m.current=true; m.onAssetRead=nil; assert(m.get().ok)
end)
test('missing or tampered replay artifacts fail closed',function()
    local m=fixture(); assert(m.fulfill().ok); m.db.history={}
    assert(m.get().code=='fulfillment_incomplete' and m.fulfill().code=='fulfillment_incomplete')
    m=fixture(); assert(m.fulfill().ok); m.db.horses[m.t.horseId].owner_character_id='other'
    assert(m.get().code=='fulfillment_conflict')
end)
test('config and route payloads reject client owner and canonical evidence',function()
    local m=fixture(); m.env.StablesConfig.purchaseFulfillment='true'; assert(m.S.Fulfillment.Start().code=='config_error')
    local routes={}; m.S.Core={Call=function(_,name,callback,options) routes[name]=options; return m.S.Ok(true) end}
    assert(m.S.Fulfillment.Install().ok)
    for _,name in ipairs({'fulfill','fulfillment.get'}) do
        local options=routes['stables.purchase.'..name..'.v1']
        assert(options.requireCharacter and options.maxPayloadBytes==128 and options.maxCalls==2)
        assert(options.validatePayload({operationId=m.t.operationId}) and not options.validatePayload({operationId=m.t.operationId,assetId=m.asset.assetId}))
    end
end)
print(count..'/'..count..' fulfillment cases passed; real transactional SQL/CFX gates remain pending.')
