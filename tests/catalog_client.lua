local count=0
local function test(name,fn) fn(); count=count+1; print('PASS catalogue client '..name) end
local function fixture(response,err,missing)
    local env=setmetatable({}, {__index=_G}); local m={logs={},time=0}
    env.RegisterCommand=function(_,fn) m.command=fn end
    env.CreateThread=function(fn) fn() end
    env.print=function(v) m.logs[#m.logs+1]=v end
    env.GetGameTimer=function() return m.time end
    env.Wait=function(ms) m.time=m.time+ms end
    env.exports={['feather-core']={CallRPC=function(_,route,payload,callback)
        assert(route=='stables.catalog.get.v1' and next(payload)==nil)
        m.callback=callback; if not missing then callback(response,err) end
    end}}
    assert(loadfile('client/catalog.lua','t',env))()
    return m
end
local function response()
    return {ok=true,value={revision=1,purchasesAvailable=false,items={{id='morgan_bay',label='Morgan - Bay',price={currency='dollars',amount=10000,precision=2}}}}}
end
test('callback catalogue displays current price in currency units',function()
    local m=fixture(response()); m.command(); assert(m.logs[1]:find('PASS',1,true) and m.logs[2]:find('dollars 100.00',1,true))
end)
test('no-character and domain rejection codes are preserved',function()
    local m=fixture(nil,{code='character_required'}); m.command(); assert(m.logs[1]:find('character_required',1,true))
    m=fixture({ok=false,code='not_ready'}); m.command(); assert(m.logs[1]:find('not_ready',1,true))
end)
test('timeout is bounded and late success cannot print PASS',function()
    local m=fixture(nil,nil,true); m.command(); assert(m.time==6000 and m.logs[1]:find('timeout',1,true))
    m.callback(response()); assert(#m.logs==1)
end)
test('malformed prices and purchase availability never print PASS',function()
    for _,change in ipairs({function(v) v.purchasesAvailable=true end,function(v) v.items[1].price.precision=9 end,
        function(v) v.items[1].price.amount=-1 end,function(v) v.items={} end}) do
        local r=response(); change(r.value); local m=fixture(r); m.command()
        assert(m.logs[1]:find('invalid_result',1,true))
    end
end)
print(('%d/%d catalogue client cases passed; CFX remains a live gate.'):format(count,count))
