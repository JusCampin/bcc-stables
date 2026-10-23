local base=assert(loadfile('tests/fixtures/quote_intents.lua'))()
local count=0
local ID='10000000-0000-4000-8000-000000000001'
local CHAR='20000000-0000-4000-8000-000000000002'
local function test(name,body)
    local ok,err=pcall(body); assert(ok,name..': '..tostring(err)); count=count+1; print('PASS admission '..name)
end
local function fixture(enabled)
    local m=base(); m.env.StablesConfig.purchaseAdmission=enabled==true
    assert(loadfile('server/admissions.lua','t',m.env))()
    m.a=m.s.Admissions; assert(m.a.Start().ok)
    m.reserve=function() return m.a.Reserve({quoteId=ID},1,m.context) end
    m.get=function() return m.a.Get({operationId=ID},1,m.context) end
    m.cancel=function() return m.a.Cancel({operationId=ID},1,m.context) end
    return m
end
test('disabled reservation performs no account lookup or write',function()
    local m=fixture(false); assert(m.reserve().code=='admission_disabled')
    assert(not m.accountReads and next(m.db.operations)==nil)
end)
test('player reservation persists isolated kind and exposes bounded view',function()
    local m=fixture(true); local r=m.reserve(); assert(r.ok and r.value.state=='reserved' and r.value.paymentAvailable==false)
    assert(r.value.characterId==nil and r.value.walletAccountId==nil and r.value.quoteSnapshot==nil)
    assert(m.r.Get(ID,CHAR).value.quoteSnapshot.kind=='quote_admission_v1')
    r.value.price.amount=1; assert(m.get().value.price.amount==10000)
end)
test('malicious identity price and account fields are refused',function()
    local m=fixture(true)
    for _,key in ipairs({'characterId','source','amount','walletAccountId','state'}) do
        local p={quoteId=ID}; p[key]='injected'
        assert(m.a.Reserve(p,1,m.context).code=='invalid_input')
    end
    assert(not m.accountReads and not m.db.operations[ID])
end)
test('lost commit response recovers same operation after reload',function()
    local m=fixture(true); m.unknownCommit=true; assert(m.reserve().code=='database_error')
    m.unknownCommit=false; m.reload(); assert(m.start().ok); m.quoteError='quote_not_found'
    assert(m.reserve().value.replayed and m.get().value.state=='reserved')
end)
test('feature off retains recovery and cancellation of admitted holds',function()
    local m=fixture(true); assert(m.reserve().ok)
    m.env.StablesConfig.purchaseAdmission=false; assert(m.a.Start().ok)
    assert(m.reserve().code=='admission_disabled' and m.get().ok)
    assert(m.cancel().value.state=='cancelled' and m.cancel().value.revision==1)
end)
test('other character cannot read or cancel operation',function()
    local m=fixture(true); assert(m.reserve().ok)
    m.context.characterId='20000000-0000-4000-8000-000000000099'
    assert(m.get().code=='operation_not_found' and m.cancel().code=='operation_not_found')
    assert(m.r.Get(ID,CHAR).value.state=='reserved')
end)
test('proof and player operations cannot adopt each other',function()
    local m=fixture(true); assert(m.prepare().ok)
    assert(m.get().code=='intent_conflict' and m.cancel().code=='intent_conflict' and m.reserve().code=='intent_conflict')
    m=fixture(true); assert(m.reserve().ok)
    assert(m.s.QuoteIntents.Cancel(ID,CHAR).code=='intent_conflict')
end)
test('session change after commit suppresses response without duplicating hold',function()
    local m=fixture(true); local reserve=m.r.Reserve
    m.r.Reserve=function(...) local r=reserve(...); m.current=false; return r end
    assert(m.reserve().code=='session_stale' and m.db.operations[ID])
    m.current=true; assert(m.get().value.state=='reserved')
end)
test('cancellation cannot advance a payment pending record',function()
    local m=fixture(true); assert(m.reserve().ok); assert(m.r.Advance(ID,CHAR,0,'payment_pending').ok)
    assert(m.cancel().code=='proof_conflict' and m.r.Get(ID,CHAR).value.state=='payment_pending')
end)
test('concurrent completed cancellation is an idempotent success',function()
    local m=fixture(true); assert(m.reserve().ok); local advance=m.r.Advance
    m.r.Advance=function(...) assert(advance(...).ok); return m.s.Err('revision_conflict','changed') end
    assert(m.cancel().value.state=='cancelled' and m.get().value.revision==1)
end)
test('startup rejects malformed admission switch',function()
    local m=fixture(false); m.env.StablesConfig.purchaseAdmission='true'; assert(m.a.Start().code=='config_error')
end)
test('all RPCs require character and exact bounded UUID payload',function()
    local m=fixture(false); local routes={}
    m.s.Core.Call=function(_,name,callback,options) routes[name]={callback=callback,options=options}; return m.s.Ok(true) end
    assert(m.a.Install().ok)
    for _,action in ipairs({'reserve','get','cancel'}) do
        local r=routes['stables.purchase.'..action..'.v1']; local key=action=='reserve' and 'quoteId' or 'operationId'
        assert(r.options.requireCharacter and r.options.maxCalls==2 and r.options.maxPayloadBytes==128)
        assert(r.options.validatePayload({[key]=ID}) and not r.options.validatePayload({[key]=ID,characterId=CHAR}))
    end
end)
print(count..'/'..count..' admission cases passed; CFX transport remains a live gate.')
