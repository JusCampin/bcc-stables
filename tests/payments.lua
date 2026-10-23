local count=0
local function test(name,fn) fn(); count=count+1; print('PASS payments '..name) end
local setup=assert(loadfile('tests/fixtures/payment_services.lua'))()
test('verified transfer saves paid receipt without creating assets or horses',function()
    local m=setup(); local r=m.pay(); assert(r.ok and r.value.state=='paid' and m.charges==1)
    assert(next(m.db.horses)==nil and next(m.db.registrations)==nil and next(m.db.outbox)==nil)
end)
test('wallet owner and account shape must match before intent/payment',function()
    for _,change in ipairs({function(v) v.ownerId='foreign' end,function(v) v.currency='gold' end,
        function(v) v.status='closed' end,function(v) v.accountType='bank' end}) do
        local m=setup(); m.changeAccount=change; assert(m.pay().code=='invalid_payment_accounts')
        assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='reserved' and not m.charges)
    end
end)
test('unknown local intent commit invokes no remote payment',function()
    local m=setup(); m.unknownCommit=true; assert(m.pay().code=='database_error' and not m.charges)
    m.unknownCommit=false; assert(m.pay().ok and m.charges==1)
end)
test('lost remote reply converges by stable transfer replay after reload',function()
    local m=setup(); m.lostReply=true; assert(m.pay().code=='transaction_failed' and m.charges==1)
    m.reload(); assert(m.start().ok); m.load(); m.lostReply=false; m.calls={}
    assert(m.pay().ok and m.charges==1 and table.concat(m.calls,',')=='account,account,transfer,journal')
end)
test('paid replay is read-only and revalidates journal',function()
    local m=setup(); assert(m.pay().ok); m.calls={}
    assert(m.pay().ok and table.concat(m.calls,',')=='journal' and m.charges==1)
end)
test('pending legacy snapshot cannot charge a foreign wallet',function()
    local m=setup(); assert(m.r.Advance(m.t.operationId,m.t.characterId,0,'payment_pending').ok)
    m.changeAccount=function(v) v.ownerId='foreign' end
    assert(m.pay().code=='invalid_payment_accounts' and not m.charges)
end)
test('closed account does not prevent replay recovery of a committed transfer',function()
    local m=setup(); m.lostReply=true; assert(not m.pay().ok)
    m.lostReply=false; m.changeAccount=function(v) v.status='closed' end
    assert(m.pay().ok and m.charges==1)
end)
test('denial or insufficient funds retain pending intent without cancellation',function()
    for _,code in ipairs({'authorization_denied','insufficient_funds','economy_unavailable'}) do
        local m=setup(); m.failTransfer=code; assert(m.pay().code==code)
        assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='payment_pending')
    end
end)
test('tampered successful receipt cannot become paid',function()
    local m=setup(); m.changeReceipt=function(v) v.amount=1 end
    assert(m.pay().code=='invalid_receipt' and m.r.Get(m.t.operationId,m.t.characterId).value.state=='payment_pending')
end)
test('committed journal and exactly balanced entries are mandatory',function()
    for _,change in ipairs({function(v) v.status='pending' end,function(v) v.sourceResource='foreign' end,
        function(v) v.referenceId='foreign' end,function(v) v.entries[1].amount=-1 end,
        function(v) v.entries[2].accountId='foreign' end,function(v) v.entries[3]=v.entries[1] end}) do
        local m=setup(); m.changeJournal=change; assert(m.pay().code=='invalid_receipt')
    end
end)
test('journal outage retains pending payment and recovers without double charge',function()
    local m=setup(); m.readError=true; assert(m.pay().code=='transaction_not_found')
    m.readError=false; assert(m.pay().ok and m.charges==1)
end)
test('lost local paid commit reply recovers by journal read alone',function()
    local m=setup(); m.onRead=function() m.unknownCommit=true end
    assert(m.pay().code=='database_error' and m.r.Get(m.t.operationId,m.t.characterId).value.state=='paid')
    m.onRead=nil; m.unknownCommit=false; m.calls={}; assert(m.pay().ok and table.concat(m.calls,',')=='journal')
end)
test('terminal and foreign operations cannot charge',function()
    local m=setup(); assert(m.r.Advance(m.t.operationId,m.t.characterId,0,'cancelled').ok)
    assert(m.pay().code=='invalid_transition' and #m.calls==0)
    assert(m.paid.Pay(m.t.operationId,'a0000000-0000-4000-8000-00000000000a').code=='operation_not_found')
end)
test('reconciliation winning before local paid commit prevents automatic continuation',function()
    local m=setup(); m.onRead=function()
        assert(m.r.Advance(m.t.operationId,m.t.characterId,1,'reconciliation_required',{code='manual_hold'}).ok)
    end
    assert(m.pay().code=='revision_conflict' and m.charges==1)
    assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='reconciliation_required')
end)
test('never-prepared payment can be durably fenced and fully refunded',function()
    local m=setup(); assert(m.pay().ok); local r=m.reverse()
    assert(r.ok and r.value.state=='refunded' and r.value.registrationFence=='unregistered_v1' and m.refunds==1)
    assert(next(m.db.registrations)==nil and next(m.db.horses)==nil)
    assert(m.pay().code=='invalid_transition')
end)
test('fence winning before preparation permanently blocks Assets registration',function()
    local m=setup(); assert(m.pay().ok)
    assert(m.r.FenceUnregistered(m.t.operationId,m.t.characterId,2).ok)
    assert(loadfile('server/asset_registration.lua','t',m.env))()
    assert(m.S.AssetRegistration.Prepare(m.t.operationId,m.t.characterId,'a_c_horse_morgan_bay').code=='payment_required')
    assert(next(m.db.registrations)==nil)
end)
test('preparation winning before fence prevents any reversal',function()
    local m=setup(); assert(m.pay().ok)
    assert(loadfile('server/asset_registration.lua','t',m.env))()
    assert(m.S.AssetRegistration.Prepare(m.t.operationId,m.t.characterId,'a_c_horse_morgan_bay').ok)
    assert(m.reverse().code=='registration_exists' and not m.refunds)
    assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='paid')
end)
test('every registration state refuses this narrow compensation path',function()
    for _,state in ipairs({'prepared','submitted','linked'}) do
        local m=setup(); assert(m.pay().ok)
        m.db.registrations[m.t.operationId]={operation_id=m.t.operationId,state=state}
        assert(m.reverse().code=='registration_exists' and not m.refunds)
    end
end)
test('horse history or outbox artifacts block fencing without deletion',function()
    for _,kind in ipairs({'horses','history','outbox'}) do
        local m=setup(); assert(m.pay().ok)
        if kind=='horses' then m.db.horses.artifact={horse_id=m.t.horseId,origin_operation_id=m.t.operationId}
        elseif kind=='history' then m.db.history.artifact={'id','horse',m.t.operationId}
        else m.db.outbox.artifact={'id',m.t.operationId} end
        assert(m.reverse().code=='fulfillment_exists' and not m.refunds and next(m.db[kind]))
    end
end)
test('unknown fence commit cannot start a reversal and recovers after reload',function()
    local m=setup(); assert(m.pay().ok); m.unknownCommit=true
    assert(m.reverse().code=='database_error' and not m.refunds)
    assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='compensation_pending')
    m.unknownCommit=false; m.reload(); assert(m.start().ok); m.load(); assert(m.reverse().ok)
end)
test('fence CAS refusal leaves paid operation and no reversal',function()
    local m=setup(); assert(m.pay().ok); m.failCas=true
    assert(m.reverse().code=='revision_conflict' and not m.refunds)
    assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='paid')
end)
test('lost reversal reply retries only original transaction and refunds once',function()
    local m=setup(); assert(m.pay().ok); m.lostRefund=true
    assert(m.reverse().code=='transaction_failed' and m.refunds==1)
    m.lostRefund=false; m.reload(); assert(m.start().ok); m.load()
    assert(m.reverse().ok and m.refunds==1)
end)
test('unknown local refunded commit converges through journal reads only',function()
    local m=setup(); assert(m.pay().ok)
    m.onRead=function() if m.refund then m.unknownCommit=true end end
    assert(m.reverse().code=='database_error')
    assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='refunded')
    m.onRead=nil; m.unknownCommit=false; m.calls={}
    assert(m.reverse().ok and table.concat(m.calls,',')=='journal,journal' and m.refunds==1)
end)
test('tampered reversal receipt or journal cannot release capacity',function()
    local m=setup(); assert(m.pay().ok); m.changeRefund=function(v) v.amount=1 end
    assert(m.reverse().code=='invalid_receipt' and m.r.Get(m.t.operationId,m.t.characterId).value.state=='compensation_pending')
    m=setup(); assert(m.pay().ok); m.changeJournal=function(v) if v.operation=='reversal' then v.entries[1].amount=-1 end end
    assert(m.reverse().code=='invalid_receipt' and m.r.Get(m.t.operationId,m.t.characterId).value.state=='compensation_pending')
end)
test('legacy caller fence flags cannot authorize reversal',function()
    local m=setup(); assert(m.pay().ok)
    local record=m.r.Get(m.t.operationId,m.t.characterId).value
    local legacy=m.S.Operations.Advance(record,2,'compensation_pending',{fulfillmentFenced=true}).value
    local row=m.db.operations[m.t.operationId]; row.state,row.revision,row.record_json=legacy.state,legacy.revision,m.env.json.encode(legacy)
    assert(m.reverse().code=='registration_not_fenced' and not m.refunds)
end)
test('refund refusal retains durable fence and no asset can be prepared',function()
    local m=setup(); assert(m.pay().ok); m.refundError='insufficient_funds'
    assert(m.reverse().code=='insufficient_funds')
    assert(m.r.Get(m.t.operationId,m.t.characterId).value.registrationFence=='unregistered_v1')
end)
test('capacity releases only after journal-verified terminal refund',function()
    local m=setup(); m.env.StablesConfig.ownedHorseLimit=1; assert(m.pay().ok)
    local other=m.S.Copy(m.t); other.operationId='a0000000-0000-4000-8000-00000000000a'
    other.horseId='b0000000-0000-4000-8000-00000000000b'
    m.lostRefund=true; assert(not m.reverse().ok)
    assert(m.r.Reserve(other).code=='capacity_exceeded')
    m.lostRefund=false; assert(m.reverse().ok and m.r.Reserve(other).ok)
end)
test('unknown fence versions or fences attached to paid snapshots are refused',function()
    local m=setup(); assert(m.pay().ok)
    local record=m.r.Get(m.t.operationId,m.t.characterId).value
    record.registrationFence='unregistered_v1'
    assert(m.S.Operations.Validate(record).code=='invalid_operation')
    record=m.S.Operations.Advance(m.r.Get(m.t.operationId,m.t.characterId).value,2,'compensation_pending',{fulfillmentFenced=true}).value
    record.registrationFence='unknown_v2'
    assert(m.S.Operations.Validate(record).code=='invalid_operation')
end)
print(('%d/%d payment cases passed; Economy and SQL are modeled, no live funds moved.'):format(count,count))
