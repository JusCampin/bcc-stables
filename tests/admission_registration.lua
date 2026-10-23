local base=assert(loadfile('tests/fixtures/linked_services.lua'))()
local count=0
local MODEL='a_c_horse_morgan_bay'
local function test(name,body)
    local ok,err=pcall(body); assert(ok,name..': '..tostring(err)); count=count+1; print('PASS admission registration '..name)
end
local function fixture(kind)
    local m=base(true,{kind=kind or 'quote_admission_v1',stableId='valentine',stableRevision=1,modelKey=MODEL,precision=2})
    local S,e=m.S,m.env
    m.current=true; m.context={source=1,sessionId='session-a',characterId=m.t.characterId,accountId='account-a'}
    S.Foundation.CheckSession=function(source,context)
        assert(not m.inTx)
        return m.current and source==1 and context.sessionId==m.context.sessionId and S.Ok(true) or S.Err('session_stale','stale')
    end
    for _,file in ipairs({'server/quote_intents.lua','server/admissions.lua','server/admission_payments.lua','server/admission_registration.lua'}) do assert(loadfile(file,'t',e))() end
    e.StablesConfig.purchaseRegistration=true; assert(S.Admissions.Start().ok); assert(S.AdmissionRegistration.Start().ok)
    m.register=function() return S.AdmissionRegistration.Register({operationId=m.t.operationId},1,m.context) end
    m.inspect=function() return S.AdmissionRegistration.Get({operationId=m.t.operationId},1,m.context) end
    m.refundRoute=function() return S.AdmissionPayments.Refund({operationId=m.t.operationId},1,m.context) end
    return m
end
test('disabled register creates no registration intent',function()
    local m=fixture(); m.env.StablesConfig.purchaseRegistration=false; assert(m.S.AdmissionRegistration.Start().ok)
    assert(m.register().code=='registration_disabled' and next(m.db.registrations)==nil)
end)
test('paid admission registers saved model with separate canonical identity',function()
    local m=fixture(); local r=m.register()
    assert(r.ok and r.value.registrationState=='linked' and r.value.assetStatus=='active' and r.value.assetId~=m.t.horseId)
    assert(not r.value.gameplayAvailable and m.r.Get(m.t.operationId,m.t.characterId).value.state=='paid')
    assert(next(m.db.horses)==nil and next(m.db.history)==nil and next(m.db.outbox)==nil)
end)
test('same request and restart link recovery do not allocate another asset',function()
    local m=fixture(); local first=m.register().value.assetId; assert(m.register().value.assetId==first)
    m.reload(); assert(m.start().ok); m.loadLinked()
    assert(m.inspect().value.assetId==first and m.registerCalls==1)
end)
test('lost canonical registration reply resumes same submitted intent',function()
    local m=fixture(); m.lostRegistration=true; assert(m.register().code=='transaction_failed')
    assert(m.db.registrations[m.t.operationId].state=='submitted')
    m.lostRegistration=false; assert(m.register().ok and m.registerCalls==1)
end)
test('saved snapshot model cannot be overridden by internal caller',function()
    local m=fixture(); assert(m.g.Prepare(m.t.operationId,m.t.characterId,'a_c_horse_arabian_white').code=='idempotency_conflict')
    assert(next(m.db.registrations)==nil)
end)
test('proof kind and foreign character cannot register or inspect',function()
    local m=fixture('quote_intent_proof_v1'); assert(m.register().code=='intent_conflict')
    m=fixture(); m.context.characterId='20000000-0000-4000-8000-000000000099'
    assert(m.register().code=='operation_not_found' and m.inspect().code=='operation_not_found')
end)
test('unverified paid journal refuses registration',function()
    local m=fixture(); m.changeJournal=function(j) j.amount=1 end
    assert(m.register().code=='invalid_receipt' and not m.registerCalls)
end)
test('session change during lookup prevents remote registration',function()
    local m=fixture(); m.onAssetFind=function() m.current=false end
    assert(m.register().code=='session_stale' and not m.registerCalls)
    assert(m.db.registrations[m.t.operationId].state=='submitted')
    m.current=true; m.onAssetFind=nil; assert(m.register().ok)
end)
test('prepared registration cannot be refunded as absent',function()
    local m=fixture(); assert(m.g.Prepare(m.t.operationId,m.t.characterId,MODEL).ok)
    assert(m.refundRoute().code=='registration_not_linked' and not m.refunds)
end)
test('linked refund retires before reversal and remains idempotent when disabled',function()
    local m=fixture(); assert(m.register().ok)
    m.env.StablesConfig.purchaseRegistration=false; assert(m.S.AdmissionRegistration.Start().ok)
    local r=m.refundRoute(); assert(r.ok,tostring(r.code)..': '..tostring(r.message)); assert(r.value.state=='refunded' and m.asset.status=='retired')
    assert(m.refundRoute().value.revision==4 and m.refunds==1 and m.retireCalls==1)
    assert(m.inspect().value.assetStatus=='retired' and m.inspect().value.assetRevision==2)
end)
test('changed canonical owner blocks inspection and retirement',function()
    local m=fixture(); assert(m.register().ok); m.asset.owner.holderId='20000000-0000-4000-8000-000000000099'
    assert(m.inspect().code=='asset_changed' and m.refundRoute().code=='asset_changed' and not m.refunds)
end)
test('session change before retirement prevents mutation after durable fence',function()
    local m=fixture(); assert(m.register().ok)
    local fence=m.r.FenceLinked
    m.r.FenceLinked=function(...) local r=fence(...); m.current=false; return r end
    assert(m.refundRoute().code=='session_stale' and not m.retireCalls and not m.refunds)
    assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='compensation_pending')
end)
test('session change after retirement prevents reversal until same-order retry',function()
    local m=fixture(); assert(m.register().ok); m.onRetire=function() m.current=false end
    assert(m.refundRoute().code=='session_stale' and m.asset.status=='retired' and not m.refunds)
    m.current=true; m.onRetire=nil
    assert(m.refundRoute().value.state=='refunded' and m.refunds==1 and m.retireCalls==1)
end)
test('session change after registration commit preserves link but suppresses response',function()
    local m=fixture(); m.onAssetRead=function() m.current=false end
    assert(m.register().code=='session_stale' and m.db.registrations[m.t.operationId].state=='linked')
    m.current=true; m.onAssetRead=nil; assert(m.inspect().value.assetStatus=='active')
end)
test('malformed config and model payload fail closed',function()
    local m=fixture(); m.env.StablesConfig.purchaseRegistration='true'
    assert(m.S.AdmissionRegistration.Start().code=='config_error')
    assert(m.S.AdmissionRegistration.Register({operationId=m.t.operationId,modelKey=MODEL},1,m.context).code=='invalid_input')
end)
test('registration routes are bounded and character required',function()
    local m=fixture(); local routes={}
    m.S.Core={Call=function(_,name,callback,options) routes[name]=options; return m.S.Ok(true) end}
    assert(m.S.AdmissionRegistration.Install().ok)
    for _,name in ipairs({'register','get'}) do
        local options=routes['stables.purchase.registration.'..name..'.v1']
        assert(options.requireCharacter and options.maxPayloadBytes==128 and options.maxCalls==2)
        assert(options.validatePayload({operationId=m.t.operationId}) and not options.validatePayload({operationId=m.t.operationId,characterId=m.t.characterId}))
    end
end)
print(count..'/'..count..' admission registration cases passed; canonical player RPC remains a live gate.')
