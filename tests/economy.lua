local count=0
local function test(name,fn) fn(); count=count+1; print('PASS economy '..name) end
local function fixture()
    local env=setmetatable({}, {__index=_G})
    local m={state='started',calls={},features={health=1,accounts=1,transfers=1,journal=1,idempotency=1,transactionRead=1,scopedPaymentReversals=1}}
    env.GetResourceState=function() return m.state end
    env.RegisterCommand=function(_,fn) m.command=fn end
    env.print=function() end
    local provider=setmetatable({}, {__index=function(_,method) return setmetatable({__cfx_functionReference=method},{__call=function(_,self,request)
        m.calls[#m.calls+1]=method
        if m.throw then error('transport') end
        if m.malformed then return nil end
        if method=='GetCapabilities' then return {ok=true,value={resource='feather-economy',contract=1,version='0.5.0',state='ready',features=m.features}} end
        if method=='GetTransaction' then
            assert(request.transactionId=='00000000-0000-0000-0000-000000000000')
            return {ok=false,code=m.denied and 'authorization_denied' or 'transaction_not_found',message='Read probe.'}
        end
        return {ok=true,value={state=m.degraded and 'failed' or 'ready'}}
    end}) end})
    env.exports={['feather-economy']=provider}
    for _,path in ipairs({'config.lua','shared/contracts.lua','server/economy.lua'}) do assert(loadfile(path,'t',env))() end
    m.e=env.Stables.Economy; return m
end
test('read-only probe validates capabilities and actual trusted read',function()
    local m=fixture(); local r=m.e.Start(); assert(r.ok and r.value.trustedRead and not r.value.paymentsEnabled)
    assert(table.concat(m.calls,',')=='AwaitReady,GetHealth,GetCapabilities,GetTransaction')
end)
test('dependency health transport and malformed results fail closed',function()
    local m=fixture(); m.state='stopped'; assert(m.e.Probe().code=='economy_unavailable' and #m.calls==0)
    m=fixture(); m.throw=true; assert(m.e.Probe().code=='economy_dependency_error')
    m=fixture(); m.malformed=true; assert(m.e.Probe().code=='invalid_contract')
    m=fixture(); m.degraded=true; assert(m.e.Probe().code=='economy_unavailable')
end)
test('feature mismatch and caller denial are refused',function()
    local m=fixture(); m.features.transactionRead=2; assert(m.e.Probe().code=='unsupported_contract')
    m=fixture(); m.denied=true; assert(m.e.Probe().code=='authorization_denied')
end)
test('console smoke ignores clients and invokes no transfer',function()
    local m=fixture(); m.command(17); assert(#m.calls==0)
    m.command(0); assert(table.concat(m.calls,',')=='GetHealth,GetCapabilities,GetTransaction')
end)
print(('%d/%d Economy consumer cases passed; CFX remains a live gate.'):format(count,count))
