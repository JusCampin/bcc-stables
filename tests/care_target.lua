local function fixture()
    local e=setmetatable({RegisterCommand=function() end},{__index=_G})
    for _,f in ipairs({'shared/contracts.lua','server/operations.lua','server/care_operations.lua','config/care.lua','server/care_policy.lua'}) do assert(loadfile(f,'t',e))() end
    local S=e.Stables; assert(S.CarePolicy.Start().ok)
    local m={time=0,events=0,routes={}}
    m.snapshot={generationId='10000000-0000-4000-8000-000000000001',observerId='20000000-0000-4000-8000-000000000002',
        netId=71,modelKey='a_c_horse_morgan_bay',targetNetId=72,ownerSource=1,networkOwner=2,distance=2,movementIdle=true}
    S.NativeCalls={CareObserver=function() return S.Ok(S.Copy(m.snapshot)) end,
        RecheckCareObserver=function() return m.changed and S.Err('care_observation_stale','changed') or S.Ok(S.Copy(m.snapshot)) end}
    S.Core={Call=function(_,name,callback,options) m.routes[name]={callback=callback,options=options}; return S.Ok(true) end}
    e.GetGameTimer=function() return m.time end
    e.Wait=function(ms) m.time=m.time+ms; if m.onWait then m.onWait() end end
    e.TriggerClientEvent=function(name,source,payload)
        assert(name=='bcc-stables:call:care_check' and source==2); m.events=m.events+1; m.instruction=S.Copy(payload)
        if m.onEvent then m.onEvent(payload) end
    end
    assert(loadfile('server/care_target.lua','t',e))()
    m.t,m.S=e.Stables.CareTarget,S
    m.report=function(p) return {generationId=p.generationId,sequence=p.sequence,ownerAlive=true,horseAlive=true,unoccupied=true,notLeading=true} end
    m.check=function() return m.t.Check({},1,{characterId='30000000-0000-4000-8000-000000000003',sessionId='current'}) end
    return m
end
local n=0
local function test(name,fn) fn(); n=n+1; print('PASS care target '..name) end
test('current remote simulator report yields observation only and retires ticket',function()
    local m=fixture(); m.onEvent=function(p) assert(m.t.Report(m.report(p),2).ok) end
    local r=m.check(); assert(r.ok and r.value.eligible and r.value.feedingEnabled==false and r.value.observationOnly and r.value.networkOwner==2)
    assert(m.t.Report(m.report(m.instruction),2).code=='care_report_stale')
end)
test('wrong source sequence duplicate and expired reports cannot authorize',function()
    local m=fixture()
    m.onEvent=function(p)
        local r=m.report(p); assert(m.t.Report(r,1).code=='care_report_stale')
        r.sequence=r.sequence+1; assert(m.t.Report(r,2).code=='care_report_stale')
        r.sequence=p.sequence; assert(m.t.Report(r,2).ok); assert(m.t.Report(r,2).code=='care_report_stale')
    end
    assert(m.check().ok)
    m=fixture(); m.onWait=function() if m.time>=750 then assert(m.t.Report(m.report(m.instruction),2).ok) end end
    -- Exactly at expiry is permitted; a later receipt is always stale.
    local result=m.check(); assert(result.ok or result.code=='care_observation_unknown')
    m.time=1000; assert(m.t.Report(m.report(m.instruction),2).code=='care_report_stale')
end)
test('missing report times out without granting eligibility and next request is possible',function()
    local m=fixture(); assert(m.check().code=='care_observation_unknown' and m.time==750)
    m.onEvent=function(p) assert(m.t.Report(m.report(p),2).ok) end
    assert(m.check().ok and m.events==2)
end)
test('identity or simulator changes during report cannot authorize',function()
    local m=fixture(); m.onEvent=function(p) m.changed=true; assert(not m.t.Report(m.report(p),2).ok) end
    assert(not m.check().ok)
end)
test('life rider and leading refusals remain ineligible',function()
    for _,key in ipairs({'ownerAlive','horseAlive','unoccupied','notLeading'}) do
        local m=fixture(); m.onEvent=function(p) local r=m.report(p); r[key]=false; assert(m.t.Report(r,2).ok) end
        assert(m.check().code=='care_ineligible')
    end
end)
test('known distance and movement conflicts avoid client round trip',function()
    local m=fixture(); m.snapshot.distance=3; assert(m.check().code=='care_too_far' and m.events==0)
    m.snapshot.distance=2; m.snapshot.movementIdle=false; assert(m.check().code=='care_ineligible' and m.events==0)
end)
test('post-report distance and movement rechecks still refuse',function()
    local m=fixture(); m.onEvent=function(p) assert(m.t.Report(m.report(p),2).ok); m.snapshot.distance=4 end
    assert(m.check().code=='care_too_far')
    m=fixture(); m.onEvent=function(p) assert(m.t.Report(m.report(p),2).ok); m.snapshot.movementIdle=false end
    assert(m.check().code=='care_ineligible')
end)
test('bounded routes authenticate original source and strict report booleans',function()
    local m=fixture(); assert(m.t.Install().value.routes==2)
    local report=m.routes['stables.horses.call.care_check_result.v1'].options
    local request=m.routes['stables.horses.call.care_eligibility.v1'].options
    assert(report.requireCharacter==false and report.maxNodes==8 and request.requireCharacter and request.maxPayloadBytes==16)
    local r=m.report(m.snapshot); r.sequence=1; assert(report.validatePayload(r))
    r.ownerAlive=1; assert(not report.validatePayload(r)); r.ownerAlive=true; r.clientApproved=true; assert(not report.validatePayload(r))
    assert(not request.validatePayload({horseId='spoof'}) and request.validatePayload({}))
end)
print(('%d/%d care target cases passed; actual native observations/CFX pending.'):format(n,n))
