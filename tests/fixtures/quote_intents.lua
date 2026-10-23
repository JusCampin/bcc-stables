local base=assert(loadfile('tests/fixtures/persistence.lua'))()
local ID='10000000-0000-4000-8000-000000000001'
local CHAR='20000000-0000-4000-8000-000000000002'
local function fixture()
    local m=base(); assert(m.start().ok)
    local e,s=m.env,m.env.Stables
    m.commands={}; e.RegisterCommand=function(name,fn) m.commands[name]=fn end
    m.context={source=1,sessionId='session-a',characterId=CHAR,accountId='account-a'}
    m.current=true
    s.Foundation={RequireReady=function() return s.Ok(true) end,CheckSession=function(source,context)
        assert(not m.inTx,'No external session lookup while SQL locks are held')
        return m.current and source==1 and context.sessionId==m.context.sessionId and s.Ok(true) or s.Err('session_stale','stale')
    end}
    s.Core={RequireSession=function() return s.Ok(s.Copy(m.context)) end}
    m.quote={quoteId=ID,stableId='valentine',stableRevision=1,catalogId='morgan_bay',catalogRevision=1,
        modelKey='a_c_horse_morgan_bay',price={currency='dollars',amount=10000,precision=2}}
    s.Quotes={Get=function(_,source,context)
        local checked=s.Foundation.CheckSession(source,context); if not checked.ok then return checked end
        if m.quoteError then return s.Err(m.quoteError,'denied') end
        return s.Ok(s.Copy(m.quote))
    end}
    m.wallet={accountId='50000000-0000-4000-8000-000000000005',ownerType='character',ownerId=CHAR,
        accountType='wallet',currency='dollars',status='open'}
    m.sink={accountId='60000000-0000-4000-8000-000000000006',accountType='system_sink',currency='dollars',status='open'}
    s.Economy={CharacterAccounts=function()
        assert(not m.inTx); m.accountReads=(m.accountReads or 0)+1
        if m.onAccounts then m.onAccounts() end
        return s.Ok(m.accounts or {m.wallet})
    end,SystemSink=function()
        assert(not m.inTx); if m.onSink then m.onSink() end
        return s.Ok(m.sink)
    end}
    assert(loadfile('server/quote_intents.lua','t',e))()
    m.s=s; m.prepare=function() return s.QuoteIntents.Prepare(ID,1,m.context) end
    return m
end
return fixture
