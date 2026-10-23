local base=assert(loadfile('tests/fixtures/payment_services.lua'))()
local count=0
local function test(name,body)
    local ok,err=pcall(body); assert(ok,name..': '..tostring(err)); count=count+1; print('PASS admission payment '..name)
end
local function fixture(kind)
    local m=base({kind=kind or 'quote_admission_v1',stableId='valentine',stableRevision=1,
        modelKey='a_c_horse_morgan_bay',precision=2})
    local S,e=m.S,m.env
    m.current=true; m.context={source=1,sessionId='session-a',characterId=m.t.characterId,accountId='account-a'}
    S.Foundation.CheckSession=function(source,context)
        assert(not m.inTx)
        return m.current and source==1 and context.sessionId==m.context.sessionId and S.Ok(true) or S.Err('session_stale','stale')
    end
    for _,file in ipairs({'server/quote_intents.lua','server/admissions.lua','server/admission_payments.lua','server/asset_registration.lua','server/linked_cleanup.lua'}) do assert(loadfile(file,'t',e))() end
    e.StablesConfig.purchasePayments=true; assert(S.Admissions.Start().ok)
    m.payRoute=function(amount) return S.AdmissionPayments.Pay({operationId=m.t.operationId,expectedAmount=amount or 100,currency='dollars'},1,m.context) end
    m.refundRoute=function() return S.AdmissionPayments.Refund({operationId=m.t.operationId},1,m.context) end
    m.get=function() return S.Admissions.Get({operationId=m.t.operationId},1,m.context) end
    return m
end
test('disabled payments refuse before account reads and state change',function()
    local m=fixture(); m.env.StablesConfig.purchasePayments=false; assert(m.S.Admissions.Start().ok)
    assert(m.payRoute().code=='payment_disabled' and #m.calls==0)
    assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='reserved')
end)
test('price acknowledgment cannot choose the charged amount',function()
    local m=fixture(); assert(m.payRoute(1).code=='price_acknowledgment_mismatch' and #m.calls==0)
end)
test('player payment rejects proof records and other characters',function()
    local m=fixture('quote_intent_proof_v1'); assert(m.payRoute().code=='intent_conflict' and not m.charges)
    m=fixture(); m.context.characterId='20000000-0000-4000-8000-000000000099'
    assert(m.payRoute().code=='operation_not_found' and not m.charges)
end)
test('verified payment and repeated request charge once',function()
    local m=fixture(); local r=m.payRoute()
    assert(r.ok and r.value.state=='paid' and r.value.revision==2 and not r.value.paymentAvailable and m.charges==1)
    assert(m.payRoute().value.state=='paid' and m.charges==1)
    assert(m.get().value.state=='paid' and m.get().value.price.amount==100)
end)
test('lost transfer reply recovers same key without duplicate charge',function()
    local m=fixture(); m.lostReply=true
    assert(m.payRoute().code=='transaction_failed' and m.charges==1 and m.get().value.state=='payment_pending')
    m.lostReply=false; assert(m.payRoute().value.state=='paid' and m.charges==1)
end)
test('session change during initial account reads prevents pending and transfer',function()
    local m=fixture(); m.changeAccount=function() m.current=false end
    assert(m.payRoute().code=='session_stale' and not m.charges)
    assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='reserved')
end)
test('session change after pending fence prevents transfer',function()
    local m=fixture(); local reads=0
    m.changeAccount=function() reads=reads+1; if reads>=3 then m.current=false end end
    assert(m.payRoute().code=='session_stale' and not m.charges)
    assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='payment_pending')
end)
test('journal mismatch cannot become locally paid',function()
    local m=fixture(); m.changeJournal=function(j) j.amount=1 end
    assert(m.payRoute().code=='invalid_receipt' and m.get().value.state=='payment_pending')
end)
test('unregistered refund remains available with payments disabled',function()
    local m=fixture(); assert(m.payRoute().ok)
    m.env.StablesConfig.purchasePayments=false; assert(m.S.Admissions.Start().ok)
    local r=m.refundRoute(); assert(r.ok and r.value.state=='refunded' and r.value.revision==4 and m.refunds==1)
    assert(m.refundRoute().value.state=='refunded' and m.refunds==1)
    assert(m.get().value.state=='refunded')
end)
test('registered intent blocks refund before reversal',function()
    local m=fixture(); assert(m.payRoute().ok)
    m.db.registrations[m.t.operationId]={operation_id=m.t.operationId,character_id=m.t.characterId}
    assert(m.refundRoute().code=='invalid_registration' and not m.refunds)
end)
test('unknown payment cannot be cancelled or refunded',function()
    local m=fixture(); m.lostReply=true; assert(not m.payRoute().ok)
    assert(m.S.Admissions.Cancel({operationId=m.t.operationId},1,m.context).code=='proof_conflict')
    assert(m.refundRoute().code=='registration_not_fenced' and not m.refunds)
end)
test('session change while verifying payment prevents refund fence',function()
    local m=fixture(); assert(m.payRoute().ok); m.onRead=function() m.current=false end
    assert(m.refundRoute().code=='session_stale' and not m.refunds)
    assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='paid')
end)
test('session change after money commit suppresses stale response',function()
    local m=fixture(); m.onRead=function() m.current=false end
    assert(m.payRoute().code=='session_stale' and m.charges==1)
    m.current=true; m.onRead=nil; assert(m.get().value.state=='paid')
end)
test('session change after refund fence leaves compensation retryable',function()
    local m=fixture(); assert(m.payRoute().ok)
    local fence=m.r.FenceUnregistered
    m.r.FenceUnregistered=function(...) local result=fence(...); m.current=false; return result end
    assert(m.refundRoute().code=='session_stale' and not m.refunds)
    assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='compensation_pending')
    m.current=true; m.r.FenceUnregistered=fence
    assert(m.refundRoute().value.state=='refunded' and m.refunds==1)
end)
test('payload schemas disallow supplied receipts and arbitrary refund amounts',function()
    local m=fixture(); local routes={}
    m.S.Core={Call=function(_,name,callback,options) routes[name]=options; return m.S.Ok(true) end}
    assert(m.S.AdmissionPayments.Install().ok)
    local pay=routes['stables.purchase.pay.v1']; local refund=routes['stables.purchase.refund.v1']
    assert(pay.requireCharacter and refund.requireCharacter and pay.maxPayloadBytes==256)
    assert(pay.validatePayload({operationId=m.t.operationId,expectedAmount=100,currency='dollars'}))
    assert(not pay.validatePayload({operationId=m.t.operationId,expectedAmount=100,currency='dollars',receipt={}}))
    assert(not refund.validatePayload({operationId=m.t.operationId,amount=100}))
end)
print(count..'/'..count..' admission payment cases passed; real money/RPC acceptance remains pending.')
