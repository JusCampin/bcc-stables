local count=0
local function test(name,fn) fn(); count=count+1; print('PASS linked cleanup '..name) end
local paymentSetup=assert(loadfile('tests/fixtures/payment_services.lua'))()
local MODEL='a_c_horse_morgan_bay'
local setup=assert(loadfile('tests/fixtures/linked_services.lua'))()
test('paid canonical link survives reload and exact terminal retirement precedes refund',function()
    local m=setup(); m.reload(); assert(m.start().ok); m.load(); m.loadLinked()
    assert(m.g.Run(m.t.operationId,m.t.characterId,MODEL).ok and m.registerCalls==1)
    local r=m.cleanup(); assert(r.ok and r.value.state=='refunded' and m.asset.status=='retired')
    assert(r.value.registrationFence=='linked_retirement_v1' and r.value.assetRetirement.assetId==m.asset.assetId)
    assert(m.refunds==1 and m.retireCalls==1 and next(m.db.horses)==nil and next(m.db.outbox)==nil)
end)
test('completed cleanup is read-only and preserves both journal identities',function()
    local m=setup(); local r=m.cleanup(); assert(r.ok); m.calls={}
    local again=m.cleanup(); assert(again.ok and again.value.refundReceipt.transactionId==r.value.refundReceipt.transactionId)
    assert(m.refunds==1 and m.retireCalls==1 and m.registerCalls==1)
    for _,call in ipairs(m.calls) do assert(call~='reverse' and call~='retire' and call~='register') end
end)
test('prepared and submitted intents cannot use linked retirement or unregistered compensation',function()
    for _,state in ipairs({'prepared','submitted'}) do
        local m=setup(true); assert(m.g.Prepare(m.t.operationId,m.t.characterId,MODEL).ok)
        local row=m.db.registrations[m.t.operationId]; row.state,row.revision=state,state=='prepared' and 0 or 1
        assert(m.cleanup().code=='registration_not_linked' and not m.retireCalls and not m.refunds)
        assert(m.reverse().code=='registration_exists')
    end
end)
test('unknown local retirement plan commit cannot call Assets or reverse funds',function()
    local m=setup(); m.unknownCommit=true; local r=m.cleanup()
    assert(r.code=='database_error' and not m.retireCalls and not m.refunds)
    assert(m.r.Get(m.t.operationId,m.t.characterId).value.registrationFence=='linked_retirement_v1')
    m.unknownCommit=false; assert(m.cleanup().ok)
end)
test('retirement refusal preserves fence and prevents registration finalization',function()
    local m=setup(); m.retireError='assets_unavailable'; assert(m.cleanup().code=='assets_unavailable' and not m.refunds)
    assert(m.g.Run(m.t.operationId,m.t.characterId,MODEL).code=='payment_required')
end)
test('lost retirement reply recovers exact receipt without retiring twice',function()
    local m=setup(); m.lostRetirement=true; assert(m.cleanup().code=='transaction_failed' and not m.refunds)
    m.lostRetirement=false; m.reload(); assert(m.start().ok); m.load(); m.loadLinked()
    assert(m.cleanup().ok and m.retireCalls==1 and m.refunds==1)
end)
test('owner metadata or status change before fencing refuses retirement and refund',function()
    for _,change in ipairs({function(v) v.owner.holderId='foreign' end,function(v) v.metadata.extra=true end,
        function(v) v.status='held' end}) do
        local m=setup(); change(m.asset); assert(m.cleanup().code=='asset_changed')
        assert(not m.retireCalls and not m.refunds and m.r.Get(m.t.operationId,m.t.characterId).value.state=='paid')
    end
end)
test('asset revision race after fence cannot refresh retirement terms or refund',function()
    local m=setup(); m.onRetire=function() m.asset.revision=2 end
    assert(m.cleanup().code=='revision_conflict' and not m.refunds)
    local plan=m.r.Get(m.t.operationId,m.t.characterId).value.assetRetirement
    assert(plan.expectedRevision==1)
end)
test('retired status without the exact cleanup receipt cannot authorize reversal',function()
    local m=setup(); assert(m.r.FenceLinked(m.t.operationId,m.t.characterId,2,m.asset.assetId,1).ok)
    m.asset.status,m.asset.owner,m.asset.revision='retired',nil,2
    assert(m.cleanup().code=='retirement_unconfirmed' and not m.refunds and not m.retireCalls)
end)
test('wrong retirement receipt operation or canonical identity refuses refund',function()
    for _,mutate in ipairs({function(m) m.retirementOperation='asset.register' end,
        function(m) m.retirement.assetId='b0000000-0000-4000-8000-00000000000b' end}) do
        local m=setup(); m.lostRetirement=true; assert(not m.cleanup().ok); mutate(m)
        assert(m.cleanup().code=='retirement_unconfirmed' and not m.refunds)
    end
end)
test('lost reversal reply replays original refund without re-registering or re-retiring',function()
    local m=setup(); m.lostRefund=true; assert(m.cleanup().code=='transaction_failed' and m.refunds==1)
    m.lostRefund=false; assert(m.cleanup().ok and m.refunds==1 and m.retireCalls==1 and m.registerCalls==1)
end)
test('fulfilled artifacts block the local retirement plan',function()
    local m=setup(); m.db.horses[m.t.horseId]={horse_id=m.t.horseId,origin_operation_id=m.t.operationId}
    assert(m.cleanup().code=='fulfillment_exists' and not m.retireCalls and not m.refunds)
end)
test('lost terminal refund commit reply recovers through durable link and journals',function()
    local m=setup(); m.onRead=function() if m.refund then m.unknownCommit=true end end
    assert(m.cleanup().code=='database_error')
    assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='refunded')
    m.unknownCommit=false; m.onRead=nil; assert(m.cleanup().ok and m.refunds==1)
end)
test('local fence winning after another registration read blocks final link transaction',function()
    local m=setup()
    m.onAssetRead=function()
        m.onAssetRead=nil
        assert(m.r.FenceLinked(m.t.operationId,m.t.characterId,2,m.asset.assetId,1).ok)
    end
    assert(m.g.Run(m.t.operationId,m.t.characterId,MODEL).code=='payment_required')
    assert(m.paid.RefundRetired(m.t.operationId,m.t.characterId).code=='retirement_unconfirmed' and not m.refunds)
end)
print(('%d/%d linked cleanup cases passed; SQL/Assets/Economy are modeled.'):format(count,count))
