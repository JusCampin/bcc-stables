local base=assert(loadfile('tests/fixtures/persistence.lua'))()
local count=0
local function test(name,body)
    local ok,err=pcall(body); assert(ok,name..': '..tostring(err)); count=count+1; print('PASS quote intent '..name)
end
local ID='10000000-0000-4000-8000-000000000001'
local CHAR='20000000-0000-4000-8000-000000000002'
local fixture=assert(loadfile('tests/fixtures/quote_intents.lua'))()
test('saves quote snapshot and capacity reservation in one operation',function()
    local m=fixture(); local r=m.prepare(); assert(r.ok and r.value.state=='reserved' and r.value.noPaymentSubmitted)
    local record=m.r.Get(ID,CHAR).value
    assert(record.terms.amount==10000 and record.quoteSnapshot.modelKey==m.quote.modelKey)
    assert(next(m.db.horses)==nil and next(m.db.history)==nil and next(m.db.outbox)==nil and next(m.db.registrations)==nil)
end)
test('lost reservation commit response replays the original intent after restart',function()
    local m=fixture(); m.unknownCommit=true; assert(m.prepare().code=='database_error')
    m.unknownCommit=false; m.reload(); assert(m.start().ok)
    local reads=m.accountReads; m.quoteError='quote_not_found'
    local r=m.prepare(); assert(r.ok and r.value.replayed and m.accountReads==reads)
    assert(m.s.QuoteIntents.Inspect(ID,CHAR).ok)
end)
test('cancel is durable idempotent and releases capacity without deleting audit',function()
    local m=fixture(); assert(m.prepare().ok)
    assert(m.s.QuoteIntents.Cancel(ID,CHAR).value.state=='cancelled')
    assert(m.s.QuoteIntents.Cancel(ID,CHAR).value.state=='cancelled')
    assert(m.db.operations[ID] and m.r.Get(ID,CHAR).value.revision==1)
    assert(m.prepare().value.state=='cancelled')
end)
test('full capacity refuses quote intent',function()
    local m=fixture(); m.env.StablesConfig.ownedHorseLimit=1
    m.db.horses.other={owner_character_id=CHAR}
    assert(m.prepare().code=='capacity_exceeded' and not m.db.operations[ID])
end)
test('session change during account lookup refuses reservation',function()
    local m=fixture(); m.onAccounts=function() m.current=false end
    assert(m.prepare().code=='session_stale' and not m.db.operations[ID])
end)
test('expiry or movement during account lookup refuses reservation',function()
    for _,code in ipairs({'quote_expired','too_far','foreign_route'}) do
        local m=fixture(); m.onSink=function() m.quoteError=code end
        assert(m.prepare().code==code and not m.db.operations[ID])
    end
end)
test('terms changed during account lookup refuse reservation',function()
    local m=fixture(); m.onSink=function() m.quote.price.amount=1 end
    assert(m.prepare().code=='quote_stale' and not m.db.operations[ID])
end)
test('missing ambiguous or invalid wallets never create an intent',function()
    local m=fixture(); m.accounts={}; assert(m.prepare().code=='account_not_found')
    m=fixture(); m.accounts={m.wallet,m.wallet}; assert(m.prepare().code=='ambiguous_wallet')
    m=fixture(); m.wallet.accountId='bad'; assert(m.prepare().code=='invalid_input')
end)
test('wrong sink currency or status refuses intent',function()
    local m=fixture(); m.sink.currency='gold'; assert(m.prepare().code=='invalid_contract')
    m=fixture(); m.sink.status='closed'; assert(m.prepare().code=='invalid_contract')
end)
test('snapshot is immutable in repository replay and validation',function()
    local m=fixture(); assert(m.prepare().ok); local original=m.r.Get(ID,CHAR).value
    local changed=m.s.Copy(original.quoteSnapshot); changed.modelKey='a_c_horse_other'
    assert(m.r.Reserve(original.terms,changed).code=='idempotency_conflict')
    original.quoteSnapshot.precision=3; assert(m.s.Operations.Validate(original).code=='invalid_operation')
end)
test('proof cannot cancel payment pending operations',function()
    local m=fixture(); assert(m.prepare().ok); assert(m.r.Advance(ID,CHAR,0,'payment_pending').ok)
    assert(m.s.QuoteIntents.Cancel(ID,CHAR).code=='proof_conflict')
end)
test('console gate is opt-in and denies player invocation',function()
    local m=fixture(); m.commands.BccStablesQuoteIntentProof(1,{'run','1',ID}); assert(#m.outputs==0)
    m.commands.BccStablesQuoteIntentProof(0,{'run','1',ID}); assert(not m.db.operations[ID])
    m.env.StablesConfig.quoteIntentProof=true
    m.commands.BccStablesQuoteIntentProof(0,{'run','1',ID}); assert(m.db.operations[ID])
end)
print(count..'/'..count..' quote intent cases passed; real SQL acceptance remains pending.')
