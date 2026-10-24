local base=assert(loadfile('tests/fixtures/selection_services.lua'))()
local count=0
local function test(name,fn) local ok,err=pcall(fn); assert(ok,name..': '..tostring(err)); count=count+1; print('PASS native calls '..name) end
local function fixture()
    local m=base(); assert(m.select(0).ok)
    for _,f in ipairs({'server/call_repository.lua','server/call_lifecycle_repository.lua','server/calls.lua'}) do assert(loadfile(f,'t',m.env))() end
    local e,S=m.env,m.S
    e.StablesConfig.callPreparation=true; assert(S.Calls.Start().ok)
    m.id=S.Calls.Prepare({expectedSelectionRevision=1},1,m.context).value.generationId
    m.time,m.events,m.routes,m.handlers,m.threads=0,{},{},{},{}
    m.entities={[10]={exists=true,model=0,netId=72,owner=1,bucket=0,pos={x=0,y=0,z=0},state={}}}
    m.convars={}
    e.GetConvar=function(key,default) return m.convars[key] or default end
    e.SetConvar=function(key,value) m.convars[key]=value end
    e.GetGameTimer=function() return m.time end
    e.Wait=function(ms) m.time=m.time+ms; if m.onWait then m.onWait(ms) end end
    e.GetResourceState=function(name) return name=='feather-toolkit' and (m.noToolkit and 'stopped' or 'started') or m.provider end
    e.GetCurrentResourceName=function() return 'bcc-stables' end
    e.GetPlayerRoutingBucket=function() return m.bucket or 0 end
    e.GetPlayerPed=function() return 10 end
    e.DoesEntityExist=function(id) local r=m.entities[id]; return r and r.exists and (m.numeric and 1 or true) or false end
    e.GetEntityCoords=function(id) return m.entities[id].pos end
    e.GetEntityHeading=function() return 0 end
    e.GetEntityModel=function(id) return m.entities[id].model end
    e.GetHashKey=function(model) return model=='a_c_horse_morgan_bay' and 123 or 999 end
    e.GetEntityScript=function(id) return m.entities[id].script end
    e.NetworkGetEntityOwner=function(id) return m.entities[id].owner end
    e.GetEntityRoutingBucket=function(id) return m.entities[id].bucket end
    e.NetworkGetNetworkIdFromEntity=function(id) return m.entities[id].netId end
    e.NetworkGetEntityFromNetworkId=function(netId)
        for id,r in pairs(m.entities) do if r.netId==netId then return id end end
        return 0
    end
    e.Entity=function(id)
        local state=m.entities[id].state
        state.set=function(_,key,value) state[key]=value end
        return {state=state}
    end
    e.DeleteEntity=function(id)
        m.deletes=(m.deletes or 0)+1
        if not m.delayDelete then m.entities[id].exists=false end
    end
    e.TriggerClientEvent=function(name,source,payload)
        m.events[#m.events+1]={name=name,source=source,payload=S.Copy(payload)}
        if name=='bcc-stables:call:create' then m.instruction=payload end
    end
    e.AddEventHandler=function(name,fn) m.handlers[name]=fn end
    e.RegisterCommand=function(name,fn) m.handlers[name]=fn end
    e.CreateThread=function(fn) m.threads[#m.threads+1]=fn end
    S.Core={IsSessionCurrent=function(context) return m.current and context.sessionId==m.context.sessionId end,
        Call=function(_,name,callback,options) m.routes[name]={callback=callback,options=options}; return S.Ok(true) end}
    local query=e.DB.query
    e.DB.query=function(sql,...)
        if sql:find("WHERE state NOT IN ('prepared','released') AND generation_id>?",1,true) then
            if m.recoveryRows then return m.recoveryRows end
            local cursor=...; local rows={}
            for _,r in pairs(m.db.callLeases) do
                if r.state~='prepared' and r.state~='released' and r.generation_id>cursor then
                    rows[#rows+1]={generation_id=r.generation_id,character_id=r.character_id}
                end
            end
            table.sort(rows,function(a,b) return a.generation_id<b.generation_id end)
            while #rows>11 do table.remove(rows) end
            return rows
        end
        if sql:find('SELECT generation_id,character_id FROM fs_call_leases',1,true) then
            local cursor=...; local rows={}
            for _,r in pairs(m.db.callLeases) do
                if ({submitting=true,active=true,cleanup_pending=true})[r.state] and r.generation_id>cursor then
                    rows[#rows+1]={generation_id=r.generation_id,character_id=r.character_id}
                end
            end
            table.sort(rows,function(a,b) return a.generation_id<b.generation_id end)
            return rows
        end
        return query(sql,...)
    end
    assert(loadfile('server/native_calls.lua','t',e))()
    m.n=S.NativeCalls; e.StablesConfig.nativeCalls=true; assert(m.n.Start().ok and m.n.Install().ok)
    assert(loadfile('tests/fixtures/production_snapshot.lua'))()(m)
    S.Core.RequireSession=function(source)
        if source~=1 then return S.Err('character_required','No current character.') end
        return S.Ok(S.Copy(m.context))
    end
    m.setupRouting=function()
        m.routeCalls={}; m.allocations=0
        local provider={}
        provider.GetCapabilities=function()
            return S.Ok({contract=1,state='ready',features={routes=1,ownership=1,cleanup=1,opaqueHandles=1}})
        end
        provider.GetPlayerRoute=function() return S.Ok(m.managedRoute) end
        provider.CreateRoute=function(_,spec)
            assert(spec.mode=='strict' and spec.populationEnabled==false)
            m.routeCalls[#m.routeCalls+1]='create'
            if not m.routeHandle then m.allocations=m.allocations+1; m.routeHandle='owned-route'; m.routeKey=spec.key end
            assert(spec.key==m.routeKey)
            if m.loseCreate then m.loseCreate=false; return S.Err('dependency_error','Lost create response.') end
            return S.Ok({routeId=m.routeHandle})
        end
        provider.JoinRoute=function(_,id,source)
            assert(id==m.routeHandle and source==1); m.routeCalls[#m.routeCalls+1]='join'
            m.managedRoute={routeId=id}; m.bucket=100
            if m.loseJoin then m.loseJoin=false; return S.Err('dependency_error','Lost join response.') end
            return S.Ok({routeId=id})
        end
        provider.DeleteRoute=function(_,id)
            assert(id=='owned-route'); m.routeCalls[#m.routeCalls+1]='delete'
            if m.failRouteDelete then return S.Err('dependency_error','Delete unavailable.') end
            if not m.routeHandle then return S.Err('not_found','Already deleted.') end
            m.routeHandle,m.managedRoute,m.bucket=nil,nil,0
            if m.loseDelete then m.loseDelete=false; return S.Err('dependency_error','Lost delete response.') end
            return S.Ok({routeId=id})
        end
        e.exports={['feather-routing']=provider}
        m.onWait=function() m.n.Tick() end
        return provider
    end
    m.dispatch=function() return m.n.Dispatch({generationId=m.id},1,m.context) end
    m.bind=function(netId) return m.n.Bind({generationId=m.id,netId=netId or 71},1,m.context) end
    m.store=function() return m.n.Store({generationId=m.id},1,m.context) end
    m.horse=function(observe)
        local p=assert(m.instruction)
        m.entities[20]={exists=true,model=123,owner=1,bucket=0,netId=71,pos=S.Copy(p.position),
            state={bccStablesGeneration=p.generationId,bccStablesObserver=p.observerId}}
        if observe~=false then m.n.Created(20) end
    end
    m.get=function() return S.CallRepository.Get(m.t.characterId) end
    return m
end
local function active() local m=fixture(); assert(m.dispatch().ok); m.horse(); assert(m.bind().ok); return m end

test('abort during observer UUID lookup defeats observed prepared handoff',function()
    local m=fixture(); local once=false
    m.onUuid=function()
        if not once then once=true; assert(m.S.Calls.Abort({generationId=m.id},1,m.context).ok) end
    end
    assert(m.dispatch().code=='submission_conflict' and not m.instruction)
    assert(m.get().value.state=='empty')
end)

test('ownership loss during observer UUID lookup prevents native instruction',function()
    local m=fixture()
    m.onUuid=function() m.asset.owner.holderId='20000000-0000-4000-8000-000000000099' end
    assert(not m.dispatch().ok and not m.instruction)
    assert(m.get().value.state=='prepared')
end)

test('disabled dispatch cannot claim prepared generation',function()
    local m=fixture(); m.env.StablesConfig.nativeCalls=false; assert(m.n.Start().ok)
    assert(m.dispatch().code=='native_calls_disabled' and m.get().value.state=='prepared' and not m.instruction)
end)

test('foreign route missing Toolkit and invalid coordinates refuse before submission',function()
    local m=fixture(); m.bucket=3; assert(m.dispatch().code=='foreign_route')
    m.bucket=0; m.noToolkit=true; assert(m.dispatch().code=='dependency_unavailable')
    m.noToolkit=false; m.entities[10].pos.x=0/0; assert(m.dispatch().code=='invalid_position')
    assert(m.get().value.state=='prepared' and not m.instruction)
end)

test('one durable submission precedes exactly one server instruction',function()
    local m=fixture(); assert(m.dispatch().ok and m.get().value.state=='submitting')
    assert(m.instruction.generationId==m.id and m.instruction.position.x==3 and m.instruction.modelKey=='a_c_horse_morgan_bay')
    assert(m.dispatch().code=='submission_conflict' and #m.events==1)
end)

test('server creation observation marker model owner route and position bind exact horse',function()
    local m=fixture(); m.numeric=true; assert(m.dispatch().ok); m.horse()
    local r=m.bind(); assert(r.ok and r.value.netId==71 and m.get().value.state=='active')
    assert(m.bind().code=='binding_conflict')
end)

test('preexisting entity with matching client marker cannot bind',function()
    local m=fixture(); assert(m.dispatch().ok); m.horse(false)
    assert(m.bind().code=='entity_not_observed' and m.get().value.state=='submitting')
end)

test('wrong owner model bucket position script or marker cannot bind',function()
    local changes={function(h) h.owner=2 end,function(h) h.model=999 end,function(h) h.bucket=2 end,
        function(h) h.pos.x=100 end,function(h) h.script='another-resource' end,
        function(h) h.state.bccStablesGeneration='other' end,function(h) h.state.bccStablesObserver='other' end}
    for _,change in ipairs(changes) do
        local m=fixture(); assert(m.dispatch().ok); m.horse(); change(m.entities[20])
        assert(not m.bind().ok and m.get().value.state=='submitting')
    end
end)

test('network ownership migration does not prevent exact cleanup',function()
    local m=active(); m.entities[20].owner=5
    local r=m.store(); assert(r.ok and m.get().value.state=='empty' and not m.entities[20].exists and m.deletes==1)
    assert(m.store().value.state=='released' and m.deletes==1)
end)

test('asynchronous deletion retains pending slot until disappearance',function()
    local m=active(); m.delayDelete=true
    assert(m.store().code=='cleanup_pending' and m.get().value.state=='cleanup_pending')
    m.entities[20].exists=false; m.n.Tick(); assert(m.get().value.state=='empty')
end)

test('reused handle or changed marker is fenced without server deletion',function()
    local m=active(); m.entities[20].state.bccStablesGeneration='other'
    assert(m.store().code=='call_reconciliation_required' and m.get().value.state=='reconciliation_required' and not m.deletes)
    m=active(); m.n.Created(20)
    assert(m.store().code=='call_reconciliation_required' and m.get().value.state=='reconciliation_required' and not m.deletes)
end)

test('logout event and route change drive exact cleanup',function()
    local m=active(); m.n.SessionEvent('leaving',{sessionId=m.context.sessionId}); m.n.Tick()
    assert(m.get().value.state=='empty' and m.deletes==1)
    m=active(); m.bucket=2; m.n.Tick(); assert(m.get().value.state=='empty' and m.deletes==1)
end)

test('canonical ownership change drives cleanup without authorizing a replacement owner',function()
    local m=active(); m.asset.owner.holderId='20000000-0000-4000-8000-000000000099'
    m.time=5000; m.n.Tick(); assert(m.get().value.state=='empty' and m.deletes==1)
end)

test('cancelled unbound creation is recovered only from exact live candidate',function()
    local m=fixture(); assert(m.dispatch().ok); m.horse()
    assert(m.store().ok and m.get().value.state=='empty' and m.deletes==1)
end)

test('unobserved cancelled spawn never frees slot based on timeout alone',function()
    local m=fixture(); assert(m.dispatch().ok)
    assert(m.store().code=='cleanup_pending'); m.time=31000; m.n.Tick()
    assert(m.get().value.state=='reconciliation_required' and not m.deletes)
end)

test('lost dispatch commit cannot emit a native instruction',function()
    local m=fixture(); local transaction=m.env.DB.transaction
    m.env.DB.transaction=function(body)
        return transaction(function(tx)
            local r=body(tx)
            if m.db.callLeases[m.id].state=='submitting' then m.unknownCommit=true end
            return r
        end)
    end
    assert(m.dispatch().code=='database_error' and not m.instruction)
    m.unknownCommit=false; m.env.DB.transaction=transaction
    assert(m.get().value.state~='prepared' and m.dispatch().code=='submission_conflict')
end)

test('lost binding response converges to exact cleanup without re-dispatch',function()
    local m=fixture(); assert(m.dispatch().ok); m.horse(); m.unknownCommit=true
    assert(m.bind().code=='database_error'); m.unknownCommit=false
    m.n.Tick(); assert(m.get().value.state=='empty' and m.deletes==1)
end)

test('old resource observer cannot recover native authority after reload',function()
    local m=active(); assert(loadfile('server/native_calls.lua','t',m.env))(); m.n=m.S.NativeCalls
    assert(m.n.Start().ok); m.n.Run()
    m.onWait=function() m.n.Stop() end
    m.threads[#m.threads]()
    assert(m.get().value.state=='reconciliation_required' and m.entities[20].exists and not m.deletes)
    assert(m.store().code=='call_reconciliation_required')
end)

test('store from another character cannot touch a known generation',function()
    local m=active(); m.context.characterId='20000000-0000-4000-8000-000000000099'
    assert(m.store().code=='call_not_found' and not m.deletes)
end)

test('native RPCs bound payloads reject client coordinates models or supplied identity',function()
    local m=fixture()
    for _,action in ipairs({'dispatch','bind','store'}) do
        local opts=m.routes['stables.horses.call.'..action..'.v1'].options
        assert(opts.requireCharacter and opts.maxPayloadBytes==192 and opts.maxDepth==2 and opts.maxCalls==2)
        local p={generationId=m.id}; if action=='bind' then p.netId=71 end
        assert(opts.validatePayload(p)); p.modelKey='injected'; assert(not opts.validatePayload(p))
    end
end)

test('failed cleanup intent never calls native deletion before durable commit',function()
    local m=active(); m.failLifecycleCas=true
    assert(m.store().code=='revision_conflict' and not m.deletes and m.entities[20].exists)
    m.failLifecycleCas=false; m.n.Tick()
    assert(m.get().value.state=='empty' and m.deletes==1)
end)

test('canonical change after bind commit suppresses active response and cleans exact entity',function()
    local m=fixture(); assert(m.dispatch().ok); m.horse(); local reads=0
    m.onAssetRead=function()
        reads=reads+1
        if reads==2 then m.asset.owner.holderId='20000000-0000-4000-8000-000000000099' end
    end
    assert(m.bind().code=='horse_not_found' and m.get().value.state=='active')
    m.n.Tick(); assert(m.get().value.state=='empty' and m.deletes==1)
end)

test('graceful stop deletes positively observed horse but retains durable fence',function()
    local m=active(); m.n.Stop()
    assert(m.deletes==1 and not m.entities[20].exists and m.get().value.state=='active')
    assert(m.dispatch().code=='native_calls_disabled')
end)

test('stop can delete only a unique observed unbound candidate',function()
    local m=fixture(); assert(m.dispatch().ok); m.horse(); m.n.Stop()
    assert(m.deletes==1 and m.get().value.state=='submitting')
    m=fixture(); assert(m.dispatch().ok); m.horse(false); m.n.Stop()
    assert(not m.deletes and m.entities[20].exists)
end)


test('cancelled creation arriving late still contributes cleanup evidence',function()
    local m=fixture(); assert(m.dispatch().ok); assert(m.store().code=='cleanup_pending')
    m.horse(); m.n.Tick(); assert(m.get().value.state=='empty' and m.deletes==1)
end)

test('stop contains native getter failures and preserves the persistent fence',function()
    local m=active(); m.env.GetEntityModel=function() error('native failure') end
    m.n.Stop(); assert(not m.deletes and m.get().value.state=='active')
end)


test('foreign dispatch cannot reveal a live observer or cancel its active horse',function()
    local m=active(); local events,uuid=#m.events,m.uuidSerial
    m.context.characterId='20000000-0000-4000-8000-000000000099'
    assert(m.dispatch().code=='call_not_found' and m.store().code=='call_not_found')
    assert(#m.events==events and m.uuidSerial==uuid and not m.deletes and m.entities[20].exists)
    local own=m.S.CallRepository.Get(m.t.characterId,m.id)
    assert(own.ok and own.value.state=='active' and own.value.revision==2)
end)

test('session change during scoped dispatch lookup cannot claim or emit an instruction',function()
    local m=fixture(); local get=m.S.CallRepository.Get
    m.S.CallRepository.Get=function(...)
        local result=get(...); m.current=false; return result
    end
    assert(m.dispatch().code=='session_stale' and not m.instruction)
    assert(m.db.callLeases[m.id].state=='prepared')
end)


test('owned route test observes normal cleanup and restores default without changing selection',function()
    local m=active(); m.setupRouting(); local r=m.n.RouteTest(1,m.id)
    assert(r.ok and r.value.nativeJoined and r.value.generationCleared and r.value.entityGone
        and r.value.returnedToDefault and r.value.sessionCurrent)
    assert(m.bucket==0 and not m.routeHandle and m.get().value.state=='empty' and m.deletes==1)
    assert(m.stable().revision==1 and m.stable().selected_horse_id==m.t.horseId)
end)

test('route test refuses wrong target generation or existing membership before creating',function()
    local m=active(); m.setupRouting()
    assert(m.n.RouteTest(2,m.id).code=='character_required')
    assert(m.n.RouteTest(1,'bad').code=='invalid_input')
    m.managedRoute={routeId='foreign'}
    assert(m.n.RouteTest(1,m.id).code=='foreign_route' and #m.routeCalls==0 and not m.deletes)
end)

test('route helper times out and restores rather than invoking cleanup itself',function()
    local m=active(); m.setupRouting(); m.onWait=nil
    assert(m.n.RouteTest(1,m.id).code=='route_cleanup_pending')
    assert(m.bucket==0 and not m.routeHandle and m.get().value.state=='active' and not m.deletes)
end)

test('failed join response always attempts owned-route restoration',function()
    local m=active(); m.setupRouting(); m.loseJoin=true
    assert(m.n.RouteTest(1,m.id).code=='dependency_error')
    assert(m.bucket==0 and not m.routeHandle and m.routeCalls[#m.routeCalls]=='delete')
end)

test('lost route allocation response is recovered only through saved stable key',function()
    local m=active(); m.setupRouting(); m.loseCreate=true
    assert(m.n.RouteTest(1,m.id).code=='dependency_error')
    assert(m.allocations==1 and not m.routeHandle and m.bucket==0 and #m.routeCalls==3)
end)

test('failed route cleanup retains exact handle and blocks another test until return',function()
    local m=active(); m.setupRouting(); m.failRouteDelete=true
    assert(m.n.RouteTest(1,m.id).code=='route_cleanup_failed' and m.bucket==100)
    assert(m.n.RouteTest(1,m.id).code=='busy')
    m.failRouteDelete=false; assert(m.n.RouteReturn().ok and m.bucket==0 and not m.routeHandle)
    assert(m.n.RouteReturn().value.cleared==false)
end)

test('unknown route deletion response converges without arbitrary route deletion',function()
    local m=active(); m.setupRouting(); m.loseDelete=true
    assert(m.n.RouteTest(1,m.id).code=='route_cleanup_failed' and m.bucket==0)
    assert(m.n.RouteReturn().ok and m.bucket==0 and not m.routeHandle)
end)

test('session change during route test restores the route and never reports acceptance',function()
    local m=active(); m.setupRouting(); m.onWait=function() m.current=false end
    assert(m.n.RouteTest(1,m.id).code=='session_stale' and m.bucket==0 and not m.routeHandle)
end)

test('route helper capability failure has no routing or native side effects',function()
    local m=active(); local p=m.setupRouting()
    p.GetCapabilities=function() return m.S.Ok({contract=2}) end
    assert(m.n.RouteTest(1,m.id).code=='invalid_contract' and #m.routeCalls==0 and not m.deletes)
end)

test('route helper is console-only and return cannot accept an arbitrary handle',function()
    local m=active(); m.setupRouting()
    m.handlers.BccStablesNative(1,{'route_test','1',m.id})
    assert(#m.threads==0 and #m.routeCalls==0)
    assert(m.n.RouteReturn('foreign-handle').value.cleared==false and #m.routeCalls==0)
end)


test('session change during route deletion cannot produce a successful route proof',function()
    local m=active(); local p=m.setupRouting(); local delete=p.DeleteRoute
    p.DeleteRoute=function(...)
        local result=delete(...); m.current=false; return result
    end
    assert(m.n.RouteTest(1,m.id).code=='session_stale' and m.bucket==0 and not m.routeHandle)
end)


test('logout before bind recovers exact observed creation solely for cleanup',function()
    local m=fixture(); assert(m.dispatch().ok); m.horse()
    m.current=false
    m.n.SessionEvent('leaving',{sessionId=m.context.sessionId})
    m.n.Tick()
    assert(m.get().value.state=='empty' and m.deletes==1 and not m.entities[20].exists)
    local receipt=m.S.CallRepository.Get(m.t.characterId,m.id)
    assert(receipt.ok and receipt.value.state=='released' and receipt.value.revision==4)
end)


test('late bind after completed release cannot recreate observer or change receipt',function()
    local m=active(); assert(m.store().ok); local events=#m.events
    assert(m.bind().code=='stale_call' and #m.events==events and m.deletes==1)
    assert(m.get().value.state=='empty')
    local receipt=m.S.CallRepository.Get(m.t.characterId,m.id)
    assert(receipt.value.state=='released' and receipt.value.revision==4)
end)


test('drain closes active observed horse and blocks new dispatch until reload',function()
    local m=active(); local r=m.n.Drain()
    assert(r.ok and r.value.state=='drained' and r.value.dispatchBlocked and r.value.liveObservers==0)
    assert(m.get().value.state=='empty' and m.deletes==1)
    assert(m.dispatch().code=='native_calls_draining')
    assert(m.n.Drain().value.state=='drained' and m.deletes==1)
end)

test('drain permits prepared nonphysical slot and same selection across restart',function()
    local m=fixture(); local r=m.n.Drain()
    assert(r.ok and m.get().value.state=='prepared' and m.stable().revision==1 and not m.instruction)
    assert(m.dispatch().code=='native_calls_draining')
    assert(loadfile('server/native_calls.lua','t',m.env))(); m.n=m.S.NativeCalls; assert(m.n.Start().ok)
    assert(m.dispatch().ok)
end)

test('drain waits for asynchronous deletion instead of releasing on request alone',function()
    local m=active(); m.delayDelete=true
    m.onWait=function() m.entities[20].exists=false end
    assert(m.n.Drain().ok and m.get().value.state=='empty' and m.time>=100)
end)

test('drain refuses unresolved generation without live observer and never clears it',function()
    local m=active(); assert(loadfile('server/native_calls.lua','t',m.env))(); m.n=m.S.NativeCalls; assert(m.n.Start().ok)
    local r=m.n.Drain()
    assert(r.code=='drain_pending' and r.details.unresolvedGenerations==1 and r.details.unclearedBindings==1)
    assert(m.get().value.state=='active' and not m.deletes and m.dispatch().code=='native_calls_draining')
end)

test('drain count failure cannot acknowledge restart readiness or unblock dispatch',function()
    local m=fixture(); m.failDrainRead=true
    assert(m.n.Drain().code=='database_error' and m.dispatch().code=='native_calls_draining')
    m.failDrainRead=false; assert(m.n.Drain().ok)
end)

test('drain during yielding dispatch cannot emit a late instruction',function()
    local m=fixture(); local drained
    m.onUuid=function() drained=m.n.Drain() end
    assert(m.dispatch().code=='native_calls_draining' and drained.code=='drain_pending' and not m.instruction)
    m.onUuid=nil; assert(m.get().value.state=='prepared' and m.n.Drain().ok)
end)

test('drain failure leaves uncertain identity fenced and preserves unrelated horse',function()
    local m=active(); m.entities[20].state.bccStablesGeneration='unrelated'
    assert(m.n.Drain().code=='drain_pending' and m.get().value.state=='reconciliation_required')
    assert(not m.deletes and m.entities[20].exists)
end)

test('drain is console-only and does not accept arbitrary target arguments',function()
    local m=fixture(); m.handlers.BccStablesNative(1,{'drain'})
    assert(#m.threads==0 and m.dispatch().ok)
    m=fixture(); m.handlers.BccStablesNative(0,{'drain','unexpected-target'})
    m.threads[#m.threads](); assert(m.dispatch().ok)
end)

test('offline recovery inspection does not mutate active generation',function()
    local m=active(); m.current=false; local events=#m.events
    local r=m.n.RecoveryInspect(m.t.characterId,m.id)
    assert(r.ok and r.value.state=='active' and r.value.liveObserver and r.value.inspectionOnly)
    assert(#m.events==events and not m.deletes)
end)
test('recovery inspection retains lost-observer fence',function()
    local m=active(); assert(m.S.CallLifecycleRepository.Reconcile(m.t.characterId,m.id,'restart_lost_observation').ok)
    assert(loadfile('server/native_calls.lua','t',m.env))(); m.n=m.S.NativeCalls; assert(m.n.Start().ok)
    local r=m.n.RecoveryInspect(m.t.characterId,m.id)
    assert(r.ok and r.value.reconciliationRequired and not r.value.liveObserver and not m.deletes)
end)
test('recovery inspection validates UUID and character scope',function()
    local m=fixture()
    assert(m.n.RecoveryInspect('bad',m.id).code=='invalid_input')
    assert(m.n.RecoveryInspect('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',m.id).code=='call_not_found')
end)
test('recovery console command refuses player callers',function()
    local m=fixture(); m.handlers.BccStablesNative(1,{'recovery_inspect',m.t.characterId,m.id})
    assert(#m.threads==0 and not m.instruction)
end)

test('recovery queue omits prepared and released receipts without changing dispatch',function()
    local m=fixture(); assert(#m.n.RecoveryList().value.entries==0)
    assert(m.dispatch().ok); m.horse(); assert(m.bind().ok)
    local page=m.n.RecoveryList()
    assert(page.ok and #page.value.entries==1 and not page.value.nextCursor)
    assert(page.value.entries[1].binding.state=='bound' and not page.value.dispatchBlocked)
    assert(not m.deletes and m.store().ok and #m.n.RecoveryList().value.entries==0)
end)
test('recovery queue retains corrupt blockers as inspection errors',function()
    local m=active(); m.db.callBindings[m.id].state='invalid'
    local page=m.n.RecoveryList()
    assert(page.ok and #page.value.entries==1 and page.value.entries[1].inspectionError=='invalid_call_binding')
    assert(page.value.entries[1].generationId==m.id and not m.deletes)
end)
test('recovery queue provides bounded forward cursor and preserves offline IDs',function()
    local m=fixture(); m.recoveryRows={}
    for n=1,11 do m.recoveryRows[n]={generation_id=string.format('%08x-aaaa-aaaa-aaaa-aaaaaaaaaaaa',n),character_id=m.t.characterId} end
    local page=m.n.RecoveryList()
    assert(page.ok and #page.value.entries==10 and page.value.nextCursor==m.recoveryRows[10].generation_id)
    assert(page.value.entries[1].inspectionError=='call_not_found')
    m.recoveryRows={m.recoveryRows[11]}
    assert(not m.n.RecoveryList(page.value.nextCursor).value.nextCursor)
end)
test('recovery queue rejects malformed unordered oversized and backward pages',function()
    local m=fixture(); assert(m.n.RecoveryList('bad').code=='invalid_input')
    m.recoveryRows={{generation_id='bad',character_id=m.t.characterId}}
    assert(m.n.RecoveryList().code=='invalid_contract')
    local row={generation_id=m.id,character_id=m.t.characterId}
    m.recoveryRows={row,row}; assert(m.n.RecoveryList().code=='invalid_contract')
    m.recoveryRows={row}; assert(m.n.RecoveryList(m.id).code=='invalid_contract')
    for n=1,12 do m.recoveryRows[n]=row end
    assert(m.n.RecoveryList().code=='invalid_contract' and not m.deletes)
end)
test('recovery inspection includes original binding reconciliation reason',function()
    local m=active(); assert(m.S.CallLifecycleRepository.Reconcile(m.t.characterId,m.id,'identity_lost').ok)
    local r=m.n.RecoveryInspect(m.t.characterId,m.id)
    assert(r.ok and r.value.binding.reason=='identity_lost' and r.value.binding.netId==71)
end)
test('recovery queue refuses player callers and extra console arguments',function()
    local m=fixture(); m.handlers.BccStablesNative(1,{'recovery_list'})
    assert(#m.threads==0)
    m.handlers.BccStablesNative(0,{'recovery_list','bad','extra'}); m.threads[#m.threads]()
    assert(m.get().value.state=='prepared' and not m.instruction)
end)

test('recovery queue database failure remains a read error',function()
    local m=fixture(); m.env.DB.query=function() error('database offline') end
    assert(m.n.RecoveryList().code=='database_error' and m.get().value.state=='prepared')
end)
test('recovery diagnosis requires ready foundation',function()
    local m=fixture(); m.S.Foundation.RequireReady=function() return m.S.Err('not_ready','Stopped') end
    assert(m.n.RecoveryList().code=='not_ready')
    assert(m.n.RecoveryInspect(m.t.characterId,m.id).code=='not_ready')
end)

test('server process identity survives resource reload without being regenerated',function()
    local m=fixture(); local first=m.n.ProcessEpoch(); assert(first.ok)
    local serial=m.uuidSerial
    assert(loadfile('server/native_calls.lua','t',m.env))(); m.n=m.S.NativeCalls; assert(m.n.Start().ok)
    assert(m.n.ProcessEpoch().value.processEpoch==first.value.processEpoch and m.uuidSerial==serial)
    assert(m.get().value.state=='prepared' and not m.instruction)
end)
test('process identity changes fail closed and cannot be repaired by reverting convar',function()
    local m=fixture(); local epoch=m.n.ProcessEpoch().value.processEpoch
    m.convars.bcc_stables_process_epoch_v1='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    assert(m.dispatch().code=='process_identity_lost' and m.get().value.state=='prepared')
    m.convars.bcc_stables_process_epoch_v1=epoch
    assert(m.dispatch().code=='process_identity_lost' and not m.instruction)
end)
test('malformed reserved process convar cannot authorize submission',function()
    local m=fixture(); m.convars.bcc_stables_process_epoch_v1='configured-wrong'
    assert(m.dispatch().code=='invalid_process_epoch' and not m.instruction)
    assert(m.get().value.state=='prepared' and not m.db.callEpochs[m.id])
end)
test('concurrent process initialization cannot overwrite an in-flight identity',function()
    local m=fixture(); local raced
    m.onUuid=function() raced=m.n.ProcessEpoch() end
    local r=m.n.ProcessEpoch(); assert(r.ok and raced.code=='busy')
    m.onUuid=nil; assert(m.n.ProcessEpoch().value.processEpoch==r.value.processEpoch)
end)
test('immutable process receipt exists before the only native creation instruction',function()
    local m=fixture(); local trigger=m.env.TriggerClientEvent; local observed=false
    m.env.TriggerClientEvent=function(name,...)
        if name=='bcc-stables:call:create' then
            observed=true; assert(m.db.callEpochs[m.id].process_epoch==m.convars.bcc_stables_process_epoch_v1)
        end
        return trigger(name,...)
    end
    assert(m.dispatch().ok and observed)
    local receipt=m.n.RecoveryInspect(m.t.characterId,m.id)
    assert(receipt.value.processEvidence.recorded)
    assert(m.S.CallLifecycleRepository.RecordProcessEpoch(m.context,m.id,m.db.callEpochs[m.id].process_epoch).ok)
    assert(m.S.CallLifecycleRepository.RecordProcessEpoch(m.context,m.id,'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa').code=='process_epoch_conflict')
end)
test('process receipt write rollback suppresses native creation and retains durable fence',function()
    local m=fixture(); m.failEpochInsert=true
    assert(m.dispatch().code=='database_error' and not m.instruction and not m.db.callEpochs[m.id])
    assert(m.get().value.state=='reconciliation_required' and m.db.callSlots[m.t.characterId])
end)
test('unknown process receipt commit never replays a native creation instruction',function()
    local m=fixture(); local transaction=m.env.DB.transaction; local lost=false
    m.env.DB.transaction=function(body)
        local result=transaction(body)
        if m.db.callEpochs[m.id] and not lost then lost=true; error({code='REPLY_LOST',outcome='unknown'}) end
        return result
    end
    assert(m.dispatch().code=='database_error' and lost and not m.instruction)
    assert(m.db.callEpochs[m.id] and m.get().value.state=='reconciliation_required')
    assert(not m.dispatch().ok and not m.instruction)
end)
test('historical process evidence is absent rather than backfilled on inspection',function()
    local m=fixture(); local r=m.n.RecoveryInspect(m.t.characterId,m.id)
    assert(r.ok and r.value.processEvidence.recorded==false and next(m.convars)==nil)
    assert(not m.db.callEpochs[m.id])
end)
test('contradictory process receipt is exposed as recovery inspection error',function()
    local m=active(); m.db.callEpochs[m.id].process_epoch='bad'
    assert(m.n.RecoveryInspect(m.t.characterId,m.id).code=='invalid_process_evidence')
    assert(m.n.RecoveryList().value.entries[1].inspectionError=='invalid_process_evidence' and not m.deletes)
end)
test('process status command refuses player callers and extra arguments',function()
    local m=fixture(); m.handlers.BccStablesNative(1,{'process_status'}); assert(#m.threads==0)
    m.handlers.BccStablesNative(0,{'process_status','extra'}); m.threads[#m.threads]()
    assert(next(m.convars)==nil and not m.instruction)
end)

local function lostObserver(newProcess)
    local m=active(); m.oldEpoch=m.convars.bcc_stables_process_epoch_v1
    assert(m.S.CallLifecycleRepository.Reconcile(m.t.characterId,m.id,'restart_lost_observation').ok)
    m.entities[20].exists=false
    assert(loadfile('server/native_calls.lua','t',m.env))(); m.n=m.S.NativeCalls; assert(m.n.Start().ok and m.n.Install().ok)
    if newProcess then m.convars.bcc_stables_process_epoch_v1='f0000000-0000-4000-8000-000000000001' end
    return m
end
test('console recovery resolves prior-process fence without entity lookup or mutation',function()
    local m=lostObserver(true); local events=#m.events
    m.env.NetworkGetEntityFromNetworkId=function() error('saved net ID cannot authorize recovery') end
    local r=m.n.RecoveryResolve(m.t.characterId,m.id)
    assert(r.ok and r.value.revision==5 and r.value.entityMutation==false and #m.events==events and not m.deletes)
    local receipt=m.n.RecoveryInspect(m.t.characterId,m.id)
    assert(receipt.ok and receipt.value.recovery.originalProcessEpoch==m.oldEpoch)
    assert(receipt.value.binding.state=='cleared' and #m.n.RecoveryList().value.entries==0)
    assert(m.n.RecoveryResolve(m.t.characterId,m.id).value.replayed)
end)
test('resource restart in same process cannot resolve lost observer fence',function()
    local m=lostObserver(false)
    assert(m.n.RecoveryResolve(m.t.characterId,m.id).code=='process_still_current')
    assert(m.get().value.state=='reconciliation_required' and not m.deletes)
end)
test('recovery refuses a live observer and scopes foreign character before shared state',function()
    local m=active()
    assert(m.n.RecoveryResolve(m.t.characterId,m.id).code=='live_observer_present')
    assert(m.n.RecoveryResolve('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',m.id).code=='call_not_found')
    assert(m.get().value.state=='active' and not m.deletes)
end)
test('recovery command rejects player caller malformed identity and extra arguments',function()
    local m=lostObserver(true)
    local n=#m.threads; m.handlers.BccStablesNative(1,{'recovery_resolve',m.t.characterId,m.id}); assert(#m.threads==n)
    m.handlers.BccStablesNative(0,{'recovery_resolve',m.t.characterId,m.id,'extra'}); m.threads[#m.threads]()
    assert(m.n.RecoveryResolve('bad',m.id).code=='invalid_input')
    assert(m.get().value.state=='reconciliation_required')
end)

test('one-request call uses server selection and single-use dispatch with no client IDs',function()
    local m=fixture(); local r=m.n.Request({},1,m.context)
    assert(r.ok and r.value.generationId==m.id and m.get().value.state=='submitting')
    local events=#m.events
    assert(m.n.Request({},1,m.context).code=='call_cleanup_required' and #m.events==events)
    m.horse(); assert(m.bind().ok and m.get().value.state=='active')
end)
test('call helper refuses disabled toolkit route and drain before claiming submission',function()
    local m=fixture(); m.noToolkit=true; assert(m.n.Request({},1,m.context).code=='dependency_unavailable')
    m.noToolkit=false; m.bucket=1; assert(m.n.Request({},1,m.context).code=='foreign_route')
    m.bucket=0; assert(m.n.Drain().ok and m.n.Request({},1,m.context).code=='native_calls_draining')
    assert(m.get().value.state=='prepared' and not m.instruction)
    m=fixture(); m.env.StablesConfig.nativeCalls=false; assert(m.n.Start().ok)
    assert(m.n.Request({},1,m.context).code=='native_calls_disabled' and not m.instruction)
end)
test('empty helper RPC contracts refuse IDs coordinates models and extra fields',function()
    local m=fixture()
    for _,name in ipairs({'request','store_current'}) do
        local opts=m.routes['stables.horses.call.'..name..'.v1'].options
        assert(opts.requireCharacter and opts.maxPayloadBytes==16 and opts.maxDepth==1 and opts.maxCalls==2)
        assert(opts.validatePayload({}) and not opts.validatePayload({generationId=m.id}))
        assert(not opts.validatePayload({modelKey='injected'}) and not opts.validatePayload({1}))
    end
    assert(m.n.Request({horseId=m.t.horseId},1,m.context).code=='invalid_input')
    assert(m.n.StoreCurrent({generationId=m.id},1,m.context).code=='invalid_input')
end)
test('call helper requires an available canonical owned selection',function()
    local m=fixture(); assert(m.S.Calls.Abort({generationId=m.id},1,m.context).ok and m.clear(1).ok)
    assert(m.n.Request({},1,m.context).code=='selection_required' and m.get().value.state=='empty')
    m=fixture(); m.asset.status='retired'
    assert(m.n.Request({},1,m.context).code=='selection_required' and not m.instruction)
end)
test('selection change during request admission cannot dispatch an unintended revision',function()
    local m=fixture(); local get=m.S.Selection.Get; local first=true
    m.S.Selection.Get=function(...)
        local r=get(...)
        if first then first=false; m.stable().revision=2 end
        return r
    end
    assert(m.n.Request({},1,m.context).code=='revision_conflict' and not m.instruction)
    assert(m.get().value.state=='prepared')
end)
test('unknown single-use claim through call helper never retries or emits creation',function()
    local m=fixture(); local transaction=m.env.DB.transaction; local lost=false
    m.env.DB.transaction=function(body)
        local result=transaction(body)
        if m.db.callLeases[m.id].state=='submitting' and not lost then lost=true; error({code='LOST',outcome='unknown'}) end
        return result
    end
    assert(m.n.Request({},1,m.context).code=='database_error' and lost and not m.instruction)
    assert(m.get().value.state=='reconciliation_required')
    assert(not m.n.Request({},1,m.context).ok and not m.instruction)
end)
test('store current deletes only exact owned active generation and repeats as empty',function()
    local m=active(); local r=m.n.StoreCurrent({},1,m.context)
    assert(r.ok and r.value.generationId==m.id and r.value.state=='released' and m.deletes==1)
    assert(m.n.StoreCurrent({},1,m.context).value.state=='empty' and m.deletes==1)
end)
test('store current can abort unsubmitted preparation while creation switches are disabled',function()
    local m=fixture(); m.env.StablesConfig.nativeCalls=false; assert(m.n.Start().ok)
    m.env.StablesConfig.callPreparation=false; assert(m.S.Calls.Start().ok)
    local r=m.n.StoreCurrent({},1,m.context)
    assert(r.ok and r.value.state=='released' and r.value.revision==1 and m.get().value.state=='empty')
    assert(not m.instruction and not m.deletes and m.stable().revision==1)
end)
test('current store from another character cannot touch owner active generation',function()
    local m=active(); local other=m.S.Copy(m.context); other.characterId='20000000-0000-4000-8000-000000000099'
    assert(m.n.StoreCurrent({},1,other).value.state=='empty' and not m.deletes)
    assert(m.get().value.state=='active')
end)
test('store current snapshot cannot release a replacement prepared slot',function()
    local m=fixture(); local get=m.S.CallRepository.Get; local changed=false; local nextId
    m.S.CallRepository.Get=function(character,id)
        local r=get(character,id)
        if not id and not changed then
            changed=true; assert(m.S.CallRepository.Abort(character,m.id).ok)
            nextId=m.S.Calls.Prepare({expectedSelectionRevision=1},1,m.context).value.generationId
        end
        return r
    end
    assert(m.n.StoreCurrent({},1,m.context).ok)
    assert(m.get().value.generationId==nextId and m.get().value.state=='prepared' and not m.deletes)
end)
test('store current refuses unresolved lost observer without force release',function()
    local m=lostObserver(false)
    assert(m.n.StoreCurrent({},1,m.context).code=='call_reconciliation_required')
    assert(m.get().value.state=='reconciliation_required' and not m.deletes)
end)
test('concurrent submission wins over ordinary prepared abort without freeing its fence',function()
    local m=fixture(); local abort=m.S.Calls.Abort
    m.S.Calls.Abort=function(...)
        assert(m.S.Calls.ClaimSubmission({generationId=m.id},1,m.context).ok)
        return abort(...)
    end
    assert(m.n.StoreCurrent({},1,m.context).code=='call_cleanup_required')
    assert(m.get().value.state=='submitting' and not m.instruction)
end)
test('session loss after current-slot read suppresses mutation',function()
    local m=fixture(); local get=m.S.CallRepository.Get
    m.S.CallRepository.Get=function(...)
        local r=get(...); m.current=false; return r
    end
    assert(m.n.StoreCurrent({},1,m.context).code=='session_stale')
    assert(m.db.callLeases[m.id].state=='prepared' and not m.instruction)
end)

test('request timings include its single selection snapshot inside preparation',function()
    local m=fixture(); local logs={}; m.env.print=function(msg) logs[#logs+1]=msg end
    local check=m.S.Foundation.CheckSession; m.S.Foundation.CheckSession=function(...) m.time=m.time+20; return check(...) end
    m.S.Selection.Get=function() error('outer request must not perform another selection read') end
    m.S.Calls.PlanForDispatch=function(source,context,stages)
        stages.generationUuidMs=10; stages.selectionMs=50; stages.transactionMs=100; stages.recheckMs=40
        m.time=m.time+200; return m.S.Ok({lease={generationId=m.id}}) end
    m.n.DispatchPrepared=function() m.time=m.time+300; return m.S.Ok({generationId=m.id,state='submitting'}) end
    assert(m.n.Request({},1,m.context).ok)
    assert(logs[1]:find('preflightMs=40 selectionMs=0 preparationMs=200 dispatchMs=300 totalMs=540',1,true))
    assert(logs[2]:find('generationUuidMs=10 selectionMs=50 transactionMs=100 recheckMs=40',1,true))
end)
test('bind timings distinguish durable commit and both canonical validations',function()
    local m=fixture(); assert(m.dispatch().ok); m.horse()
    local logs={}; m.env.print=function(msg) logs[#logs+1]=msg end
    local owned=m.S.OwnedHorses.Get; m.S.OwnedHorses.Get=function(...) m.time=m.time+40; return owned(...) end
    local known=m.S.OwnedHorses.GetKnown; m.S.OwnedHorses.GetKnown=function(...) m.time=m.time+40; return known(...) end
    local bind=m.S.CallLifecycleRepository.Bind; m.S.CallLifecycleRepository.Bind=function(...) m.time=m.time+60; return bind(...) end
    assert(m.bind().ok and m.get().value.state=='active')
    assert(logs[1]:find('observationMs=0 validationMs=40 commitMs=60 recheckMs=40 totalMs=140',1,true))
end)
test('timing sink failure cannot change a successful server binding',function()
    local m=fixture(); assert(m.dispatch().ok); m.horse()
    m.env.print=function(msg) if msg:find('[bcc-stables:timing]',1,true) then error('logging unavailable') end end
    assert(m.bind().ok and m.get().value.state=='active' and not m.deletes)
end)

test('dispatch timings separate scoped read UUID claim and process receipt',function()
    local m=fixture(); assert(m.n.ProcessEpoch().ok)
    local logs={}; m.env.print=function(msg) logs[#logs+1]=msg end
    local get=m.S.CallRepository.Get
    m.S.CallRepository.Get=function(...) m.time=m.time+10; return get(...) end
    m.onUuid=function() m.time=m.time+20 end
    local claim=m.S.Calls.ClaimObservedSubmission
    m.S.Calls.ClaimObservedSubmission=function(...) m.time=m.time+30; return claim(...) end
    local receipt=m.S.CallLifecycleRepository.RecordProcessEpoch
    m.S.CallLifecycleRepository.RecordProcessEpoch=function(...) m.time=m.time+40; return receipt(...) end
    assert(m.dispatch().ok and m.instruction)
    assert(logs[1]:find('scopedReadMs=10 observerUuidMs=20 processEpochMs=0 claimMs=30 processReceiptMs=40 totalMs=100',1,true))
end)

test('dispatch timing sink failure cannot suppress its single spawn instruction',function()
    local m=fixture()
    m.env.print=function(msg) if msg:find('[bcc-stables:timing]',1,true) then error('logging unavailable') end end
    assert(m.dispatch().ok and m.instruction and #m.events==1)
    assert(m.get().value.state=='submitting')
end)

test('claim timings separate selected ownership transaction and postcommit ownership',function()
    local m=fixture(); local logs={}; m.env.print=function(msg) logs[#logs+1]=msg end
    local selected=m.S.Selection.Get
    m.S.Selection.Get=function(...) m.time=m.time+10; return selected(...) end
    local owned=m.S.OwnedHorses.Get
    m.S.OwnedHorses.Get=function(...) m.time=m.time+40; return owned(...) end
    local known=m.S.OwnedHorses.GetKnown; m.S.OwnedHorses.GetKnown=function(...) m.time=m.time+40; return known(...) end
    local claim=m.S.CallRepository.ClaimSubmission
    m.S.CallRepository.ClaimSubmission=function(...) m.time=m.time+20; return claim(...) end
    assert(m.dispatch().ok and m.instruction)
    assert(logs[2]:find('claim generationId='..m.id..' selectionMs=50 transactionMs=20 recheckMs=40',1,true))
end)

local function probeFixture()
    local m=fixture(); m.probeCounts={bridge=0,direct=0,transaction=0,assets=0}
    m.env.DB.isReady=function()
        assert(not m.inTx)
        m.probeCounts.bridge=m.probeCounts.bridge+1; m.time=m.time+7
        return true
    end
    m.env.DB.value=function(sql)
        assert(sql=='SELECT 1' and not m.inTx)
        m.probeCounts.direct=m.probeCounts.direct+1; m.time=m.time+10
        return 1
    end
    m.env.DB.stmt=function(sql) return {sql=sql,params={}} end
    m.env.DB.transaction=function(body)
        m.time=m.time+20; m.inTx=true
        local result=body({value=function(sql)
            assert(sql=='SELECT 1' and m.inTx)
            m.probeCounts.transaction=m.probeCounts.transaction+1; m.time=m.time+30
            return 1
        end,batch=function(statements)
            assert(#statements==3 and m.inTx)
            for _,statement in ipairs(statements) do assert(statement.sql=='SELECT 1 AS probe_value') end
            m.time=m.time+60
            return {{{probe_value=1}},{{probe_value=1}},{{probe_value=1}}}
        end})
        m.inTx=false; m.time=m.time+40
        return result
    end
    m.S.Assets.ReadHorse=function(id)
        assert(id==m.asset.assetId and not m.inTx)
        m.probeCounts.assets=m.probeCounts.assets+1; m.time=m.time+50
        return m.S.Ok({assetId=id,assetType='horse'})
    end
    m.probe=function() return m.n.LatencyProbe(m.asset.assetId) end
    return m
end

test('read-only probe bounds all samples and separates transaction begin finish and query costs',function()
    local m=probeFixture(); local r=m.probe(); assert(r.ok)
    local v=r.value
    assert(v.readOnly and v.sampleCount==3 and v.bridge.medianMs==7 and v.database.medianMs==10 and v.assets.medianMs==50)
    assert(v.transaction.medianMs==30 and v.transaction.beginMs==20 and v.transaction.finishMs==40 and v.transaction.totalMs==150)
    assert(v.batchedTransaction.batchCallMs==60 and v.batchedTransaction.totalMs==120)
    assert(m.probeCounts.bridge==3 and m.probeCounts.direct==3 and m.probeCounts.transaction==3 and m.probeCounts.assets==3)
    assert(not m.instruction and not m.deletes and m.db.callLeases[m.id].state=='prepared')
end)

test('read-only probe refuses overlap and resets its busy guard after dependency failure',function()
    local m=probeFixture(); local read=m.S.Assets.ReadHorse
    m.S.Assets.ReadHorse=function(id)
        assert(m.probe().code=='busy')
        return m.S.Err('assets_unavailable','Unavailable')
    end
    assert(m.probe().code=='assets_unavailable')
    m.S.Assets.ReadHorse=read; assert(m.probe().ok)
end)

test('read-only probe rejects invalid identity results and clears guard after SQL error',function()
    local m=probeFixture(); assert(m.n.LatencyProbe('bad').code=='invalid_input' and m.probeCounts.direct==0)
    local value=m.env.DB.value
    m.env.DB.value=function() error({code='CONNECTION_LOST',outcome='unknown'}) end
    assert(m.probe().code=='database_error')
    m.env.DB.value=function() return 2 end
    assert(m.probe().code=='invalid_contract')
    m.env.DB.value=value
    m.S.Assets.ReadHorse=function() return m.S.Ok({assetId='wrong',assetType='horse'}) end
    assert(m.probe().code=='invalid_contract')
end)

test('read-only probe console entry refuses player callers and extra arguments',function()
    local m=probeFixture(); local command=m.handlers.BccStablesNative
    local before=#m.threads; command(1,{'latency_probe',m.asset.assetId})
    assert(#m.threads==before and m.probeCounts.direct==0)
    command(0,{'latency_probe',m.asset.assetId,'SELECT 2'})
    m.threads[#m.threads]()
    assert(m.probeCounts.direct==0)
    command(0,{'latency_probe',m.asset.assetId}); m.threads[#m.threads]()
    assert(m.probeCounts.direct==3 and m.probeCounts.assets==3)
end)

test('read-only probe refuses invalid or uncommitted transaction results before Assets reads',function()
    local m=probeFixture(); local transaction=m.env.DB.transaction
    m.env.DB.transaction=function(body)
        return body({value=function() return 2 end})
    end
    assert(m.probe().code=='invalid_contract' and m.probeCounts.assets==0)
    m.env.DB.transaction=function(body) transaction(body); return false end
    assert(m.probe().code=='transaction_rolled_back' and m.probeCounts.assets==0)
    m.env.DB.transaction=transaction; assert(m.probe().ok)
end)

test('no-SQL readiness probe failure stops before SQL and permits a later retry',function()
    local m=probeFixture(); local ready=m.env.DB.isReady
    m.env.DB.isReady=function() return false end
    assert(m.probe().code=='dependency_unavailable' and m.probeCounts.direct==0 and m.probeCounts.assets==0)
    m.env.DB.isReady=ready
    assert(m.probe().ok and m.probeCounts.bridge==3)
end)

test('simplified request uses one selection snapshot and two fresh Assets reads through dispatch',function()
    local m=fixture(); local selected=m.S.Selection.Get; local owned=m.S.Assets.ReadHorse
    local selections,assets=0,0
    m.S.Selection.Get=function(...) selections=selections+1; return selected(...) end
    m.S.Assets.ReadHorse=function(...) assets=assets+1; return owned(...) end
    m.S.Calls.Prepare=function() error('must not compose the explicit client-revision entry') end
    assert(m.n.Request({},1,m.context).ok and m.instruction)
    assert(selections==1 and assets==2)
end)

test('prepared request performs no yielding reads between handoff and locked claim',function()
    local m=fixture(); local after,entered=false,false
    local prepare=m.S.Calls.PlanForDispatch
    m.S.Calls.PlanForDispatch=function(...)
        local result=prepare(...); after=true; return result
    end
    local value=m.env.DB.value
    m.env.DB.value=function(...) assert(not after or entered,'UUID query after fresh handoff'); return value(...) end
    local get=m.S.CallRepository.Get
    m.S.CallRepository.Get=function(...) assert(not after or entered,'scoped reread after fresh handoff'); return get(...) end
    local selected=m.S.Selection.Get
    m.S.Selection.Get=function(...) assert(not after or entered,'selection reread after fresh handoff'); return selected(...) end
    local claim=m.S.CallRepository.PrepareAndClaim
    m.S.CallRepository.PrepareAndClaim=function(...) entered=true; return claim(...) end
    assert(m.n.Request({},1,m.context).ok and entered and m.instruction)
end)

test('observer allocation failure occurs before any current preparation snapshot or new claim',function()
    local m=fixture(); m.S.Calls.PlanForDispatch=function() error('preparation must not run') end
    m.env.DB.value=function() error({code='UNAVAILABLE',outcome='not_executed'}) end
    assert(m.n.Request({},1,m.context).code=='database_error' and not m.instruction)
    assert(m.get().value.state=='prepared')
end)

test('prepared dispatch rejects missing capability without consulting shared observer state',function()
    local m=fixture()
    assert(m.n.DispatchPrepared({},1,m.context).code=='invalid_input')
    local r=m.n.DispatchPrepared({lease={generationId=m.id,characterId=m.t.characterId,source=1,sessionId=m.context.sessionId}},1,m.context)
    assert(r.code=='call_not_found' and not m.instruction and m.get().value.state=='prepared')
end)

test('simplified claim commits process receipt before instruction without second receipt transaction',function()
    local m=fixture(); local trigger=m.env.TriggerClientEvent; local seen=false
    m.S.CallLifecycleRepository.RecordProcessEpoch=function() error('redundant receipt transaction') end
    m.env.TriggerClientEvent=function(name,...)
        if name=='bcc-stables:call:create' then
            seen=true; assert(m.db.callLeases[m.id].state=='submitting')
            assert(m.db.callEpochs[m.id].process_epoch==m.convars.bcc_stables_process_epoch_v1)
        end
        return trigger(name,...)
    end
    assert(m.n.Request({},1,m.context).ok and seen and m.instruction)
end)

test('atomic process insert failure rolls back claim and never instructs creation',function()
    local m=fixture(); m.failEpochInsert=true
    assert(m.n.Request({},1,m.context).code=='database_error' and not m.instruction)
    assert(not m.db.callEpochs[m.id] and m.db.callLeases[m.id].state=='prepared')
    assert(m.db.callSlots[m.t.characterId].generation_id==m.id)
    m.failEpochInsert=false
    assert(m.n.Request({},1,m.context).ok and m.instruction)
end)

test('unknown atomic claim receipt commit retains fence without creation or replay',function()
    local m=fixture(); local transaction=m.env.DB.transaction; local lost=false
    m.env.DB.transaction=function(body)
        local result=transaction(body)
        if m.db.callEpochs[m.id] and not lost then lost=true; error({code='REPLY_LOST',outcome='unknown'}) end
        return result
    end
    assert(m.n.Request({},1,m.context).code=='database_error' and lost and not m.instruction)
    assert(m.db.callEpochs[m.id] and m.db.callLeases[m.id].state=='reconciliation_required')
    assert(m.db.callSlots[m.t.characterId] and not m.n.Request({},1,m.context).ok and not m.instruction)
end)

test('ownership loss after atomic claim keeps receipt and blocks native instruction',function()
    local m=fixture(); local transaction=m.env.DB.transaction
    m.env.DB.transaction=function(body)
        local result=transaction(body)
        if m.db.callEpochs[m.id] then m.asset.owner.holderId='20000000-0000-4000-8000-000000000099' end
        return result
    end
    assert(m.n.Request({},1,m.context).code=='horse_not_found' and not m.instruction)
    assert(m.db.callEpochs[m.id] and m.db.callSlots[m.t.characterId])
    assert(m.db.callLeases[m.id].state=='reconciliation_required')
end)

test('binding skips redundant identity lookups but keeps both canonical observations',function()
    local m=fixture(); assert(m.dispatch().ok); m.horse()
    local one=m.env.DB.one; local assets=m.S.Assets.ReadHorse; local reads=0
    m.env.DB.one=function(sql,...)
        assert(not sql:find('SELECT horse_id,origin_operation_id FROM fs_horses',1,true),'redundant identity lookup')
        return one(sql,...)
    end
    m.S.Assets.ReadHorse=function(...) reads=reads+1; return assets(...) end
    assert(m.bind().ok and reads==2 and m.get().value.state=='active')
end)

test('atomic claim groups seven ordered reads and its two writes',function()
    local m=fixture(); local transaction=m.env.DB.transaction; local reads,writes=0,0
    m.env.DB.transaction=function(body) return transaction(function(tx)
        local batch=tx.batch
        tx.batch=function(statements)
            if #statements==7 then
                reads=reads+1
                for i,name in ipairs({'fs_call_slots','fs_call_leases','fs_call_bindings','fs_operations','fs_asset_registrations','fs_horses','fs_call_process_epochs'}) do
                    assert(statements[i].sql:find(name,1,true))
                end
            elseif statements[1].sql:find("UPDATE fs_call_leases SET state='submitting'",1,true) then
                writes=writes+1; assert(#statements==2 and statements[2].sql:find('INSERT INTO fs_call_process_epochs',1,true))
            end
            return batch(statements)
        end
        return body(tx)
    end) end
    assert(m.n.Request({},1,m.context).ok and m.instruction and reads==1 and writes==1)
end)

test('atomic claim bad write headers roll back receipt and submission together',function()
    for _,index in ipairs({1,2}) do
        local m=fixture(); local transaction=m.env.DB.transaction
        m.env.DB.transaction=function(body) return transaction(function(tx)
            local batch=tx.batch
            tx.batch=function(statements)
                local rows=batch(statements)
                if statements[1].sql:find("UPDATE fs_call_leases SET state='submitting'",1,true) then rows[index]={affectedRows=0} end
                return rows
            end
            return body(tx)
        end) end
        assert(not m.n.Request({},1,m.context).ok and not m.instruction)
        assert(m.db.callLeases[m.id].state=='prepared' and not m.db.callEpochs[m.id])
        assert(m.db.callSlots[m.t.characterId].generation_id==m.id)
    end
end)

test('fresh call and bind stay within database transport budgets',function()
    local m=fixture(); assert(m.dispatch().ok); m.horse(); assert(m.bind().ok)
    m.n.Store({generationId=m.id},1,m.context); m.n.Tick()
    assert(m.get().value.state=='empty' and m.n.ProcessEpoch().ok)
    local bridges,assets=0,0
    local transaction=m.env.DB.transaction
    m.env.DB.transaction=function(body)
        bridges=bridges+2 -- begin and commit; no failures in this measured path
        return transaction(function(tx)
            local depth=0
            for _,name in ipairs({'one','query','exec','value'}) do
                local fn=tx[name]
                tx[name]=function(...) if depth==0 then bridges=bridges+1 end; return fn(...) end
            end
            local batch=tx.batch
            tx.batch=function(statements)
                bridges=bridges+1; depth=depth+1
                local result=batch(statements); depth=depth-1; return result
            end
            return body(tx)
        end)
    end
    for _,name in ipairs({'one','query','exec','value'}) do
        local fn=m.env.DB[name]
        m.env.DB[name]=function(...) bridges=bridges+1; return fn(...) end
    end
    local read=m.S.Assets.ReadHorse
    m.S.Assets.ReadHorse=function(...) assets=assets+1; return read(...) end
    local requested=m.n.Request({},1,m.context); assert(requested.ok)
    local requestBridges,requestAssets=bridges,assets
    m.id=requested.value.generationId; m.horse(); bridges,assets=0,0
    assert(m.bind().ok)
    assert(requestBridges<=17,'request database transport budget exceeded: '..requestBridges)
    assert(bridges<=13,'binding database transport budget exceeded: '..bridges)
    assert(requestAssets==2 and assets==2,'canonical freshness checks changed')
end)

test('unknown new-generation combined commit never instructs and retains exact recovery slot',function()
    local m=fixture(); assert(m.S.Calls.Abort({generationId=m.id},1,m.context).ok)
    local transaction=m.env.DB.transaction; local lost=false
    m.env.DB.transaction=function(body)
        local result=transaction(body)
        if next(m.db.callEpochs) and not lost then lost=true; error({code='REPLY_LOST',outcome='unknown'}) end
        return result
    end
    assert(m.n.Request({},1,m.context).code=='database_error' and lost and not m.instruction)
    local slot=m.db.callSlots[m.t.characterId]; assert(slot and slot.generation_id~=m.id)
    assert(m.db.callLeases[slot.generation_id].state=='reconciliation_required' and m.db.callEpochs[slot.generation_id])
    assert(not m.n.Request({},1,m.context).ok and not m.instruction)
end)

test('movement proof authorizes only fresh owned active controlled identity',function()
    local m=active(); local assets=0; local read=m.S.Assets.ReadHorse
    m.S.Assets.ReadHorse=function(...) assets=assets+1; return read(...) end
    local result=m.n.MovementProof({},1,m.context)
    assert(result.ok and result.value.generationId==m.id and result.value.netId==71)
    assert(result.value.movementProof and not result.value.gameplayAvailable and assets==1)
    assert(m.get().value.state=='active' and m.db.horses[m.t.horseId].revision==1)
end)
test('movement proof refuses stale foreign and client-supplied identity',function()
    local m=active(); assert(m.n.MovementProof({generationId=m.id},1,m.context).code=='invalid_input')
    m.context.characterId='20000000-0000-4000-8000-000000000099'
    assert(not m.n.MovementProof({},1,m.context).ok and not m.deletes)
end)
test('movement proof refuses canonical loss without granting cached access',function()
    local m=active(); m.asset.owner.holderId='20000000-0000-4000-8000-000000000099'
    assert(m.n.MovementProof({},1,m.context).code=='horse_not_found' and not m.deletes)
end)
test('movement proof refuses migrated control and altered observed marker',function()
    local m=active(); m.entities[20].owner=2
    assert(m.n.MovementProof({},1,m.context).code=='control_required')
    m.entities[20].owner=1; m.entities[20].state.bccStablesObserver='foreign'
    assert(m.n.MovementProof({},1,m.context).code=='stale_call')
end)

test('movement proof requires nearby current player coordinates',function()
    local m=active(); m.entities[10].pos={x=100,y=0,z=0}
    assert(m.n.MovementProof({},1,m.context).code=='too_far' and not m.deletes)
end)


test('whistle delegates to migrated network owner and ticket is one use',function()
    local m=active(); m.entities[20].owner=2
    local result=m.n.Whistle({},1,m.context); assert(result.ok and result.value.networkOwner==2)
    local event=m.events[#m.events]; assert(event.name=='bcc-stables:call:whistle' and event.source==2)
    m.S.Foundation.CheckSession=function(source) return (source==1 or source==2) and m.S.Ok(true) or m.S.Err('stale_session','test') end
    local claim=m.n.WhistleClaim(event.payload,2,m.context)
    assert(claim.ok and claim.value.netId==71 and claim.value.targetNetId==72)
    assert(m.n.WhistleClaim(event.payload,2,m.context).code=='stale_whistle')
end)

test('whistle rejects foreign character and canonical ownership loss',function()
    local m=active(); local foreign=m.S.Copy(m.context); foreign.characterId='20000000-0000-4000-8000-000000000099'
    assert(not m.n.Whistle({},1,foreign).ok)
    m.asset.owner.holderId=foreign.characterId
    assert(not m.n.Whistle({},1,m.context).ok)
    for _,event in ipairs(m.events) do assert(event.name~='bcc-stables:call:whistle') end
end)

test('whistle ticket rejects expiry and changed network owner',function()
    local m=active(); assert(m.n.Whistle({},1,m.context).ok)
    local event=m.events[#m.events]
    m.entities[20].owner=2
    assert(not m.n.WhistleClaim(event.payload,1,m.context).ok)
    m.entities[20].owner=1; m.time=m.time+5001
    assert(m.n.WhistleClaim(event.payload,1,m.context).code=='stale_whistle')
end)

test('store cancels delegated ticket and prevents delayed task claim',function()
    local m=active(); assert(m.n.Whistle({},1,m.context).ok)
    local event=m.events[#m.events]; assert(m.store().ok)
    assert(m.n.WhistleClaim(event.payload,1,m.context).code=='stale_whistle')
    local cancelled=false; for _,e in ipairs(m.events) do if e.name=='bcc-stables:call:whistle_cancel' then cancelled=true end end
    assert(cancelled)
end)

test('whistle refuses far target and malformed task ticket',function()
    local m=active(); m.entities[10].pos.x=200
    assert(m.n.Whistle({},1,m.context).code=='too_far')
    assert(m.n.WhistleClaim({generationId=m.id,sequence=1,netId=71},1,m.context).code=='invalid_input')
end)

test('whistle claim rechecks canonical ownership and current character incarnation',function()
    local m=active(); assert(m.n.Whistle({},1,m.context).ok)
    local ticket=m.events[#m.events].payload
    m.asset.owner.holderId='20000000-0000-4000-8000-000000000099'
    assert(not m.n.WhistleClaim(ticket,1,m.context).ok)
    m=active(); assert(m.n.Whistle({},1,m.context).ok); ticket=m.events[#m.events].payload
    m.entities[10].netId=99
    assert(m.n.WhistleClaim(ticket,1,m.context).code=='stale_whistle')
end)

print(count..'/'..count..' native coordinator cases passed; native/CFX replication remains a live gate.')
