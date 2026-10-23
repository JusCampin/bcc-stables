local function fixture(mode)
    local e=setmetatable({},{__index=_G}); local m={commands={},logs={},time=0}
    e.RegisterCommand=function(name,fn) m.commands[name]=fn end
    e.CreateThread=function(fn) fn() end
    e.GetGameTimer=function() return m.time end
    e.Wait=function(ms) m.time=m.time+ms end
    e.print=function(v) m.logs[#m.logs+1]=v end
    e.exports={['feather-core']={CallRPC=function(_,route,payload,callback)
        m.callback=callback; m.payload=payload
        if mode=='missing' then callback({ok=false,code='quote_not_found'}); return end
        if mode=='timeout' then return end
        if mode=='denied' then callback(nil,{code='too_far'}); return end
        if route=='stables.quote.get.v1' and m.expired then callback({ok=false,code='quote_expired'}); return end
        local value={quoteId='00000000-0000-4000-8000-000000000001',stableId='valentine',catalogId='morgan_bay',
            expiresInMs=45000,confirmAvailable=mode=='malformed',price={currency='dollars',amount=10000,precision=2}}
        callback({ok=true,value=value})
    end}}
    assert(loadfile('client/quotes.lua','t',e))()
    m.run=function(name,args) m.commands[name](0,args or {}) end
    return m
end
local m=fixture(); m.run('BccStablesQuoteSmokeTest'); assert(m.logs[1]:find('PASS',1,true))
m.expired=true; m.run('BccStablesQuoteInspect'); assert(m.logs[2]:find('quote_expired',1,true))
print('PASS quote client create/read and expiry diagnostics')
m=fixture('denied'); m.run('BccStablesQuoteSmokeTest'); assert(m.logs[1]:find('too_far',1,true))
print('PASS quote client preserves location rejection')
m=fixture('timeout'); m.run('BccStablesQuoteSmokeTest'); assert(m.time==6000 and m.logs[1]:find('timeout',1,true))
m.callback({ok=true,value={}}); assert(#m.logs==1)
print('PASS quote client timeout ignores late replies')
m=fixture('malformed'); m.run('BccStablesQuoteSmokeTest'); assert(not m.logs[1]:find('PASS',1,true))
print('PASS quote client refuses enabled confirmation')
m=fixture('missing')
local id='1d7534d7-ce6e-11f1-9ad4-e0d55eaa2deb'
m.run('BccStablesQuoteInspect',{id})
assert(m.payload.quoteId==id and m.logs[1]:find('quote_not_found',1,true))
print('PASS explicit quote inspection reaches server without client memory')
print('5/5 quote client cases passed; CFX remains pending.')
