local ID='10000000-0000-4000-8000-000000000001'
local function fixture(mode)
    local e=setmetatable({},{__index=_G}); local m={commands={},logs={},time=0,calls={}}
    e.RegisterCommand=function(name,fn) m.commands[name]=fn end
    e.CreateThread=function(fn) fn() end
    e.GetGameTimer=function() return m.time end
    e.Wait=function(ms) m.time=m.time+ms end
    e.print=function(value) m.logs[#m.logs+1]=value end
    e.exports={['feather-core']={CallRPC=function(_,route,payload,callback)
        m.calls[#m.calls+1]={route=route,payload=payload}; m.callback=callback
        if mode=='timeout' then return end
        if mode=='disabled' then callback(nil,{code='admission_disabled'}); return end
        local value={operationId=ID,state=route=='stables.purchase.cancel.v1' and 'cancelled' or 'reserved',
            revision=route=='stables.purchase.cancel.v1' and 1 or 0,price={currency='dollars',amount=10000,precision=2},
            stableId='valentine',catalogId='morgan_bay',modelKey='a_c_horse_morgan_bay',replayed=false,paymentAvailable=false}
        if route=='stables.purchase.pay.v1' then value.state,value.revision='paid',2 end
        if route=='stables.purchase.refund.v1' then value.state,value.revision='refunded',4 end
        if route:find('stables.purchase.registration.',1,true)==1 then
            value={operationId=ID,registrationState='linked',assetId='90000000-0000-4000-8000-000000000009',
                assetStatus=mode=='retired' and 'retired' or 'active',assetRevision=mode=='retired' and 2 or 1,gameplayAvailable=false}
        end
        if route=='stables.purchase.fulfill.v1' or route=='stables.purchase.fulfillment.get.v1' then
            value={operationId=ID,horseId=ID,assetId='90000000-0000-4000-8000-000000000009',state='fulfilled',
                revision=3,availability='stored',projectionRevision=0,outboxPending=true,gameplayAvailable=false}
            if mode=='active-projection' then value.availability='active'; value.projectionRevision=1 end
            if mode=='bad-projection' then value.availability='active' end
        end
        if mode=='malformed' then value.price.amount=-1 end
        callback({ok=true,value=value})
    end}}
    assert(loadfile('client/admissions.lua','t',e))()
    m.run=function(name,args) m.commands[name](0,args or {ID}) end
    return m
end
local m=fixture(); m.run('BccStablesAdmissionSmokeTest')
assert(#m.calls==2 and m.calls[1].payload.quoteId==ID and m.calls[2].payload.operationId==ID and m.logs[2]:find('PASS',1,true))
print('PASS admission client reserve and read same operation ID')
m=fixture(); m.run('BccStablesAdmissionInspect'); m.run('BccStablesAdmissionCancel')
assert(m.calls[1].route=='stables.purchase.get.v1' and m.logs[2]:find('state=cancelled',1,true))
print('PASS admission client explicit IDs survive client reload')
m=fixture('disabled'); m.run('BccStablesAdmissionSmokeTest'); assert(m.logs[2]:find('admission_disabled',1,true))
print('PASS admission client preserves disabled rejection')
m=fixture('timeout'); m.run('BccStablesAdmissionSmokeTest'); assert(m.time==6000 and m.logs[2]:find('SAME operation ID',1,true))
m.callback({ok=true,value={}}); assert(#m.logs==2)
print('PASS admission client timeout retains recovery instructions and ignores late replies')
m=fixture('malformed'); m.run('BccStablesAdmissionSmokeTest'); assert(not m.logs[2]:find('PASS',1,true))
print('PASS admission client rejects malformed saved price')
m=fixture(); m.run('BccStablesAdmissionPay',{ID,'10000','dollars'})
assert(m.calls[1].payload.expectedAmount==10000 and m.calls[1].payload.currency=='dollars' and m.logs[2]:find('state=paid',1,true))
print('PASS payment client sends explicit saved-price acknowledgment')
m=fixture(); m.run('BccStablesAdmissionRefund'); assert(m.logs[1]:find('state=refunded',1,true))
print('PASS refund client requires terminal refunded response')
m=fixture(); m.run('BccStablesAdmissionPay',{ID,'1.5','dollars'}); assert(#m.calls==0)
print('PASS payment client refuses fractional base-unit acknowledgment')
m=fixture(); m.run('BccStablesAdmissionRegister'); assert(m.logs[1]:find('registrationState=linked',1,true))
print('PASS canonical client requires active linked registration')
m=fixture('retired'); m.run('BccStablesAdmissionAssetInspect'); assert(m.logs[1]:find('assetStatus=retired',1,true))
print('PASS canonical client explicit inspect reports retirement')
m=fixture(); m.run('BccStablesAdmissionFulfill'); assert(m.logs[1]:find('state=fulfilled',1,true) and m.logs[1]:find('outboxPending=true',1,true))
print('PASS stored horse client reports atomic fulfillment receipt')
m=fixture(); m.run('BccStablesStoredHorseInspect'); assert(m.calls[1].payload.operationId==ID and m.logs[1]:find('gameplayAvailable=false',1,true))
print('PASS stored horse client explicit inspect preserves no-spawn contract')
m=fixture('active-projection'); m.run('BccStablesStoredHorseInspect'); assert(m.logs[1]:find('availability=active projectionRevision=1',1,true))
m=fixture('bad-projection'); m.run('BccStablesStoredHorseInspect'); assert(not m.logs[1]:find('PASS',1,true))
print('PASS fulfilled horse client accepts current active state and rejects inconsistent revision')
print('13/13 admission client cases passed; CFX remains pending.')
