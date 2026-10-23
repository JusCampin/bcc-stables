local base=assert(loadfile('tests/fixtures/fulfillment_services.lua'))()
local count=0
local function test(name,body)
    local ok,err=pcall(body); assert(ok,name..': '..tostring(err)); count=count+1; print('PASS outbox '..name)
end
local function fixture(enabled)
    local m=base(); assert(m.fulfill().ok)
    local S,e=m.S,m.env
    m.events,m.listeners,m.commands={},{},{}
    e.RegisterCommand=function(name,callback) m.commands[name]=callback end
    e.CreateThread=function(fn) m.thread=fn end
    S.Core={Call=function(method,name,payload)
        assert(not m.inTx,'Core publication must not run under SQL locks')
        if method=='DeclareEvent' then m.validator=payload.validatePayload; return S.Ok({event=name}) end
        if method=='SubscribeEvent' then m.listeners['test-token']=payload; return S.Ok({token='test-token'}) end
        if method=='UnsubscribeEvent' then m.listeners[name]=nil; return S.Ok(true) end
        assert(method=='PublishEvent' and name=='stables.purchase.fulfilled.v1')
        if m.publishFailure then return S.Err('dependency_error','Publish failed.') end
        assert(m.validator(payload)); m.events[#m.events+1]=S.Copy(payload)
        if m.onPublish then m.onPublish(payload) end
        local delivered=0
        for _,callback in pairs(m.listeners) do callback(S.Copy(payload)); delivered=delivered+1 end
        return S.Ok({delivered=delivered,failed=m.listenerFailure and 1 or 0})
    end}
    e.StablesConfig.outbox={enabled=enabled~=false,automatic=false}
    m.loadOutbox=function()
        assert(loadfile('server/outbox.lua','t',e))(); m.o=S.Outbox; assert(m.o.Start().ok)
    end
    m.loadOutbox(); m.row=m.db.outbox['stables.fulfilled:'..m.t.operationId]
    return m
end
test('disabled publisher leaves queued row untouched',function()
    local m=fixture(false); assert(m.o.Pump().code=='outbox_disabled' and #m.events==0 and not m.row.attempts)
end)
test('publishes stable historical event and acknowledges once',function()
    local m=fixture(); local r=m.o.Pump(); assert(r.ok and r.value.acknowledged==1)
    assert(#m.events==1 and m.events[1].eventId==m.row[1] and m.row.delivered==1 and m.row.attempts==1)
    assert(m.o.Pump().value.scanned==0 and m.get().value.outboxPending==false)
end)
test('listener failure retries same ID after backoff',function()
    local m=fixture(); m.listenerFailure=true; local r=m.o.Pump()
    assert(r.value.failed==1 and not m.row.delivered and m.row.next_attempt_at==5)
    assert(m.o.Pump().value.scanned==0)
    m.clock=5; m.listenerFailure=false; assert(m.o.Pump().value.acknowledged==1)
    assert(#m.events==2 and m.events[1].eventId==m.events[2].eventId)
end)
test('unknown claim commit never publishes until lease recovery',function()
    local m=fixture(); m.lostClaim=true; assert(m.o.Pump().code=='database_error' and #m.events==0)
    m.lostClaim=false; assert(m.o.Pump().value.scanned==0)
    m.clock=60; assert(m.o.Pump().value.acknowledged==1 and #m.events==1)
end)
test('failed acknowledgment replays same event and consumer can deduplicate',function()
    local m=fixture(); local seen,unique={},0
    m.listeners.consumer=function(p) if not seen[p.eventId] then seen[p.eventId]=true; unique=unique+1 end end
    m.failAck=true; assert(m.o.Pump().code=='database_error' and #m.events==1 and not m.row.delivered)
    m.failAck=false; m.clock=60; assert(m.o.Pump().value.acknowledged==1 and #m.events==2 and unique==1)
end)
test('reload preserves durable delivered state and does not republish',function()
    local m=fixture(); assert(m.o.Pump().value.acknowledged==1)
    m.loadOutbox(); assert(m.o.Pump().value.scanned==0 and #m.events==1)
end)
test('pending row remains deliverable after reload',function()
    local m=fixture(); m.o.Stop(); m.loadOutbox()
    assert(m.o.Pump().value.acknowledged==1)
end)
test('invalid payload never reaches Core and gets delayed',function()
    local m=fixture(); m.row[4]='invalid-json'
    assert(m.o.Pump().value.failed==1 and #m.events==0 and m.row.next_attempt_at==5)
end)
test('missing purchase history prevents publication',function()
    local m=fixture(); m.db.history={}
    assert(m.o.Pump().value.failed==1 and #m.events==0 and not m.row.delivered)
end)
test('historical publication does not authorize or require current canonical owner',function()
    local m=fixture(); m.asset.owner.holderId='20000000-0000-4000-8000-000000000099'
    assert(m.o.Pump().value.acknowledged==1 and m.events[1].characterId==m.t.characterId)
    assert(m.get().code=='asset_changed')
end)
test('historical event survives current projection lifecycle changes without granting access',function()
    local m=fixture(); local horse=m.db.horses[m.t.horseId]
    horse.availability='active'; horse.biological_state='dead'; horse.revision=8
    horse.owner_character_id='20000000-0000-4000-8000-000000000099'
    local evidence=m.S.FulfillmentRepository.GetHistorical(m.t.operationId,m.t.characterId)
    assert(evidence.ok and evidence.value.historical and evidence.value.availability==nil
        and evidence.value.gameplayAvailable==nil)
    assert(m.get().code=='fulfillment_conflict' and m.fulfill().code=='fulfillment_conflict')
    assert(m.o.Pump().value.acknowledged==1 and m.events[1].characterId==m.t.characterId)
end)

test('historical validation still rejects changed immutable projection identity',function()
    for _,field in ipairs({'horse_id','catalog_id','catalog_revision','origin_operation_id'}) do
        local m=fixture(); m.db.horses[m.t.horseId][field]='tampered'
        assert(m.o.Pump().value.failed==1 and #m.events==0 and not m.row.delivered,field)
    end
end)

test('historical validation rejects changed purchased facts even after lifecycle changes',function()
    local m=fixture(); m.db.horses[m.t.horseId].availability='active'
    for _,row in pairs(m.db.history) do row[5]='{}' end
    assert(m.o.Pump().value.failed==1 and #m.events==0 and not m.row.delivered)
end)

test('historical lookup remains scoped to the original purchase character',function()
    local m=fixture()
    assert(m.S.FulfillmentRepository.GetHistorical(m.t.operationId,
        '20000000-0000-4000-8000-000000000099').code=='operation_not_found')
end)

test('expired lease before dispatch cannot publish',function()
    local m=fixture(); local get=m.S.FulfillmentRepository.GetHistorical
    m.S.FulfillmentRepository.GetHistorical=function(...) local r=get(...); m.clock=61; return r end
    local r=m.o.Pump(); assert(r.value.lastCode=='outbox_claim_lost' and #m.events==0)
end)
test('stolen claim after dispatch cannot acknowledge another attempt',function()
    local m=fixture(); m.onPublish=function() m.row.attempts=2 end
    local r=m.o.Pump(); assert(r.value.lastCode=='outbox_ack_conflict' and not m.row.delivered)
end)
test('stopped generation and reentrant publisher cannot dispatch',function()
    local m=fixture(); m.onPublish=function() assert(m.o.Pump().code=='busy'); m.o.Stop() end
    assert(m.o.Pump().value.failed==1 and not m.row.delivered)
    assert(m.o.Pump().code=='outbox_stopped')
end)
test('console observer is scoped and status reflects durable counts',function()
    local m=fixture(); m.commands.BccStablesOutbox(1,{'deliver'}); assert(#m.events==0)
    m.commands.BccStablesOutbox(0,{'deliver'}); assert(#m.events==1 and next(m.listeners)==nil)
    local state=m.o.Status().value; assert(state.pending==0 and state.published==1)
end)
test('invalid automatic config refuses startup and event schema rejects extras',function()
    local m=fixture(false); m.env.StablesConfig.outbox.automatic=true
    assert(m.o.Start().code=='config_error')
    m.env.StablesConfig.outbox.enabled=true; assert(m.o.Start().ok)
    assert(m.o.Pump().value.acknowledged==1); local p=m.S.Copy(m.events[1]); p.walletAccountId='injected'
    assert(not m.validator(p))
end)
test('automatic polling can stop without a second publication',function()
    local m=fixture(); m.env.StablesConfig.outbox.automatic=true; assert(m.o.Start().ok)
    m.env.Wait=function(ms) assert(ms==5000); m.o.Stop() end
    m.o.Run(); assert(m.thread); m.thread(); assert(#m.events==1 and m.row.delivered==1)
end)
print(count..'/'..count..' outbox cases passed; real Core/SQL delivery remains a live gate.')

