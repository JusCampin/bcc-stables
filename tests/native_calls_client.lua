local ID='b0000000-0000-4000-8000-000000000001'
local OBS='c0000000-0000-4000-8000-000000000001'
local count=0
local function test(name,fn) local ok,err=pcall(fn); assert(ok,name..': '..tostring(err)); count=count+1; print('PASS native client '..name) end
local function fixture()
    local e=setmetatable({},{__index=_G})
    local m={time=0,handlers={},commands={},logs={},rpc={},state={},exists=true,control=true,loads=0,deleted=0,released=0}
    e.source=65535
    e.RegisterNetEvent=function(name,fn) m.handlers[name]=fn end
    e.AddEventHandler=e.RegisterNetEvent
    e.RegisterCommand=function(name,fn) m.commands[name]=fn end
    e.GetCurrentResourceName=function() return 'bcc-stables' end
    e.GetResourceState=function() return 'started' end
    e.GetGameTimer=function() return m.time end
    e.Wait=function(ms) m.time=m.time+ms; if m.onWait then m.onWait(ms) end end
    e.CreateThread=function(fn) fn() end
    e.print=function(msg) m.logs[#m.logs+1]=msg; if msg:find('native binding paused',1,true) then m.pausedAt=m.time end end
    e.DoesEntityExist=function(id) return id==42 and m.exists end
    e.GetEntityModel=function() return 123 end
    e.GetEntityCoords=function() return {x=3,y=0,z=0} end
    e.NetworkHasControlOfEntity=function() return m.control end
    e.NetworkGetEntityIsNetworked=function() return true end
    e.NetworkGetNetworkIdFromEntity=function() return 71 end
    e.NetworkRegisterEntityAsNetworked=function() end
    e.Entity=function() m.state.set=function(_,key,v) m.state[key]=v end; return {state=m.state} end
    e.CreatePed=function(hash,x,y,z,heading,networked,host)
        assert(hash==123 and x==3 and y==0 and z==0 and heading==0 and networked and host)
        m.created=(m.created or 0)+1; return 42
    end
    e.SetEntityAsMissionEntity=function() end
    e.SetEntityVisible=function(_,v) m.visible=v end
    e.FreezeEntityPosition=function(_,v) m.frozen=v end
    e.SetEntityInvincible=function() end
    e.SetBlockingOfNonTemporaryEvents=function() end
    e.RequestCollisionAtCoord=function() end
    e.HasCollisionLoadedAroundEntity=function() return not m.noCollision end
    e.ClearPedTasksImmediately=function() end
    e.TaskStandStill=function() end
    e.IsEntityInAir=function() return m.inAir==true end
    e.IsPedFalling=function() return false end
    e.Citizen={InvokeNative=function() end}
    e.SetModelAsNoLongerNeeded=function() m.released=m.released+1 end
    e.DeleteEntity=function() m.deleted=m.deleted+1; m.exists=false end
    e.exports={['feather-toolkit']={
        GetCapabilities=function() return {ok=true,value={contract=1,features={models=1}}} end,
        LoadModel=function()
            m.loads=m.loads+1
            if m.cancelOnLoad then m.handlers['bcc-stables:call:cancel'](ID) end
            return {ok=true,value={hash=123}}
        end},['feather-core']={CallRPC=function(_,route,payload,callback,source,timeout)
            assert(source==nil and timeout==15000); m.rpc[#m.rpc+1]={route=route,payload=payload}
            m.callback=callback
            if m.rpcOverride then return m.rpcOverride(route,payload,callback) end
            if m.noCallback then return end
            if m.rejectBind and route=='stables.horses.call.bind.v1' then callback(nil,{code='entity_not_observed'}); return end
            callback({ok=true,value={generationId=payload.generationId,state=route=='stables.horses.call.bind.v1' and 'active' or route=='stables.horses.call.dispatch.v1' and 'submitting' or 'released',netId=71,gameplayAvailable=false,entitySpawning=route=='stables.horses.call.dispatch.v1'}})
        end}}
    assert(loadfile('client/native_calls.lua','t',e))()
    m.env=e
    m.spec={generationId=ID,observerId=OBS,modelKey='a_c_horse_morgan_bay',position={x=3,y=0,z=0,heading=0}}
    m.spawn=function() m.handlers['bcc-stables:call:create'](m.spec) end
    return m
end

test('server instruction loads creates settles binds and only then reveals',function()
    local m=fixture(); m.spawn()
    assert(m.created==1 and m.loads==1 and m.visible and m.frozen and #m.rpc==1)
    assert(m.rpc[1].route=='stables.horses.call.bind.v1' and m.rpc[1].payload.netId==71)
    assert(m.state.bccStablesGeneration==ID and m.state.bccStablesObserver==OBS)
end)

test('local forged create and cancel events are ignored',function()
    local m=fixture(); m.env.source=1; m.spawn(); assert(m.loads==0)
    m.env.source=65535; m.spawn(); m.env.source=1
    m.handlers['bcc-stables:call:cancel'](ID); assert(m.deleted==0)
end)

test('cancel while model loading prevents any native creation',function()
    local m=fixture(); m.cancelOnLoad=true; m.spawn()
    assert(m.loads==1 and not m.created and #m.rpc==0 and m.released==1)
end)

test('bind rejection deletes only its own local creation and requests cleanup',function()
    local m=fixture(); m.rejectBind=true; m.spawn()
    assert(m.created==1 and m.deleted==1 and not m.visible and #m.rpc==2 and m.released==1)
    assert(m.rpc[2].route=='stables.horses.call.store.v1')
end)

test('missing collision refuses reveal and never sends a successful bind',function()
    local m=fixture(); m.noCollision=true; m.spawn()
    assert(m.deleted==1 and not m.visible and #m.rpc==1 and m.rpc[1].route=='stables.horses.call.store.v1')
end)

test('retired instruction cannot create another horse',function()
    local m=fixture(); m.spawn(); m.handlers['bcc-stables:call:cancel'](ID); m.spawn()
    assert(m.created==1 and m.deleted==0)
end)

test('marker mismatch or reused handle prevents client deletion',function()
    local m=fixture(); m.spawn(); m.state.bccStablesObserver='other'
    m.handlers.onResourceStop('bcc-stables'); assert(m.deleted==0)
    m=fixture(); m.spawn(); m.handlers.entityRemoved(42)
    m.handlers.onResourceStop('bcc-stables'); assert(m.deleted==0)
end)

test('timed out callback cannot reveal or resurrect cancelled creation',function()
    local m=fixture(); m.noCallback=true; m.spawn()
    assert(m.deleted==1 and not m.visible and m.time<=33000)
    local logs=#m.logs; m.callback({ok=true,value={generationId=ID,state='active',netId=71}})
    assert(#m.logs==logs and not m.visible)
end)

test('malformed server descriptor and injected command input cannot create',function()
    local m=fixture(); m.spec.position.x=0/0; m.spawn(); assert(m.loads==0)
    m.commands.BccStablesCallDispatch(0,{'invalid'}); assert(#m.rpc==0)
end)

test('dispatch command never creates a horse directly',function()
    local m=fixture(); m.commands.BccStablesCallDispatch(0,{ID})
    assert(not m.created and #m.rpc==1 and m.rpc[1].route=='stables.horses.call.dispatch.v1')
end)

test('server cancellation never deletes ahead of durable server cleanup intent',function()
    local m=fixture(); m.spawn(); m.handlers['bcc-stables:call:cancel'](ID)
    assert(m.deleted==0 and m.released==1)
end)


test('one-shot hold pauses only the next accepted spawn before bind',function()
    local m=fixture(); m.commands.BccStablesCallHold(0,{})
    assert(not m.created and #m.rpc==0)
    m.spawn(); assert(m.pausedAt and m.time-m.pausedAt==10000 and #m.rpc==1)
    m.handlers['bcc-stables:call:cancel'](ID)
    m.spec.generationId='b0000000-0000-4000-8000-000000000002'
    local started=m.time; m.spawn()
    assert(m.created==2 and m.time-started<10000 and #m.rpc==2)
end)

test('server cancellation during pause sends no late bind or client deletion',function()
    local m=fixture(); m.commands.BccStablesCallHold(0,{})
    m.onWait=function()
        if m.pausedAt then m.handlers['bcc-stables:call:cancel'](ID) end
    end
    m.spawn()
    assert(m.created==1 and #m.rpc==0 and not m.visible and m.deleted==0 and m.released==1)
    assert(m.logs[#m.logs]:find('no bind sent',1,true))
end)

test('disarmed or malformed hold arguments cannot pause a normal spawn',function()
    local m=fixture(); m.commands.BccStablesCallHold(0,{})
    m.commands.BccStablesCallHold(0,{'cancel'}); m.spawn()
    assert(not m.pausedAt and m.time<10000)
    m=fixture(); m.commands.BccStablesCallHold(0,{'invalid'}); m.spawn()
    assert(not m.pausedAt and m.time<10000)
end)

test('hold cannot be armed while another horse is active',function()
    local m=fixture(); m.spawn(); m.commands.BccStablesCallHold(0,{})
    m.handlers['bcc-stables:call:cancel'](ID)
    m.spec.generationId='b0000000-0000-4000-8000-000000000002'; m.spawn()
    assert(not m.pausedAt and m.created==2)
end)

test('forged descriptor cannot consume an armed pause',function()
    local m=fixture(); m.commands.BccStablesCallHold(0,{})
    m.env.source=1; m.spawn(); assert(not m.created)
    m.env.source=65535; m.spawn(); assert(m.pausedAt and #m.rpc==1)
end)

test('resource stop during paused creation prevents late bind',function()
    local m=fixture(); m.commands.BccStablesCallHold(0,{})
    m.onWait=function() if m.pausedAt then m.handlers.onResourceStop('bcc-stables') end end
    m.spawn(); assert(#m.rpc==0 and m.deleted==1 and m.released==1 and not m.visible)
end)


test('duplicate bind replay uses only recorded identity and never creates another horse',function()
    local m=fixture(); m.spawn()
    m.rpcOverride=function(route,p,callback)
        assert(route=='stables.horses.call.bind.v1' and p.generationId==ID and p.netId==71)
        callback(nil,{code='binding_conflict'})
    end
    m.commands.BccStablesCallReplay(0,{'duplicate'})
    assert(m.created==1 and m.logs[#m.logs]:find('duplicate PASS',1,true))
end)

test('stale bind replay uses retired identity without reveal or recreation',function()
    local m=fixture(); m.spawn(); m.handlers['bcc-stables:call:cancel'](ID)
    m.rpcOverride=function(_,p,callback)
        assert(p.generationId==ID and p.netId==71); callback(nil,{code='stale_call'})
    end
    m.commands.BccStablesCallReplay(0,{'stale'})
    assert(m.created==1 and m.logs[#m.logs]:find('stale PASS',1,true))
end)

test('replay refuses missing record malformed arguments and supplied generation IDs',function()
    local m=fixture()
    m.commands.BccStablesCallReplay(0,{'stale'})
    m.commands.BccStablesCallReplay(0,{'duplicate'})
    m.commands.BccStablesCallReplay(0,{'duplicate',ID})
    assert(#m.rpc==0 and not m.created)
end)

test('unexpected bind replay acceptance is reported as failure and never executes native work',function()
    local m=fixture(); m.spawn(); m.commands.BccStablesCallReplay(0,{'duplicate'})
    assert(m.created==1 and m.logs[#m.logs]:find('duplicate FAIL',1,true)
        and m.logs[#m.logs]:find('outcome=accepted',1,true))
end)

test('replay timeout is bounded and late response cannot print another pass',function()
    local m=fixture(); m.spawn(); m.noCallback=true
    m.commands.BccStablesCallReplay(0,{'duplicate'})
    assert(m.logs[#m.logs]:find('duplicate FAIL',1,true) and m.created==1 and m.time<20000)
    local logs=#m.logs; m.callback(nil,{code='binding_conflict'}); assert(#m.logs==logs)
end)

test('simple call sends only empty request and never creates from RPC response',function()
    local m=fixture()
    m.rpcOverride=function(route,payload,callback)
        assert(route=='stables.horses.call.request.v1' and next(payload)==nil)
        callback({ok=true,value={generationId=ID,state='submitting',entitySpawning=true,gameplayAvailable=false}})
    end
    m.commands.BccStablesHorseCall(0,{})
    assert(#m.rpc==1 and not m.created and m.logs[1]:find('call requested',1,true))
end)
test('simple call rejects arguments before RPC',function()
    local m=fixture(); m.commands.BccStablesHorseCall(0,{ID})
    assert(#m.rpc==0 and not m.created)
end)
test('simple call times out once without retry and ignores late reply',function()
    local m=fixture(); m.noCallback=true; m.commands.BccStablesHorseCall(0,{})
    assert(#m.rpc==1 and not m.created and m.time>=16000 and m.logs[1]:find('timeout',1,true))
    local logs=#m.logs; m.callback({ok=true,value={generationId=ID}}); assert(#m.logs==logs)
end)
test('simple call rejects malformed success and surfaces Core rejection tuple',function()
    local m=fixture(); m.rpcOverride=function(_,_,callback) callback({ok=true,value={generationId=ID,state='active'}}) end
    m.commands.BccStablesHorseCall(0,{}); assert(m.logs[1]:find('invalid_result',1,true) and not m.created)
    m=fixture(); m.rpcOverride=function(_,_,callback) callback(nil,{code='character_required'}) end
    m.commands.BccStablesHorseCall(0,{}); assert(m.logs[1]:find('character_required',1,true))
end)
test('no-ID store sends current-slot request and accepts an empty slot',function()
    local m=fixture(); m.rpcOverride=function(route,payload,callback)
        assert(route=='stables.horses.call.store_current.v1' and next(payload)==nil)
        callback({ok=true,value={state='empty',gameplayAvailable=false}})
    end
    m.commands.BccStablesHorseStore(0,{})
    assert(#m.rpc==1 and m.logs[1]:find('PASS',1,true) and m.deleted==0)
end)
test('store reports cleanup pending as pending rather than failed or completed',function()
    local m=fixture(); m.rpcOverride=function(_,_,callback) callback({ok=false,code='cleanup_pending'}) end
    m.commands.BccStablesHorseStore(0,{})
    assert(m.logs[1]:find('pending',1,true) and not m.logs[1]:find('failed',1,true) and not m.logs[1]:find('PASS',1,true))
end)
test('no-ID store accepts valid released receipt but rejects malformed response',function()
    local m=fixture(); m.rpcOverride=function(_,_,callback) callback({ok=true,value={generationId=ID,state='released',gameplayAvailable=false}}) end
    m.commands.BccStablesHorseStore(0,{}); assert(m.logs[1]:find('PASS',1,true))
    m=fixture(); m.rpcOverride=function(_,_,callback) callback({ok=true,value={state='released',gameplayAvailable=false}}) end
    m.commands.BccStablesHorseStore(0,{}); assert(m.logs[1]:find('invalid_result',1,true))
end)
test('local in-flight request prevents overlapping call and store commands',function()
    local m=fixture(); m.rpcOverride=function(_,_,callback)
        m.commands.BccStablesHorseCall(0,{}); m.commands.BccStablesHorseStore(0,{})
        callback({ok=true,value={generationId=ID,state='submitting',entitySpawning=true,gameplayAvailable=false}})
    end
    m.commands.BccStablesHorseCall(0,{}); assert(#m.rpc==1 and not m.created)
end)

print(count..'/'..count..' native client cases passed; grounding/replication remain live gates.')
