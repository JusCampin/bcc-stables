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
    e.Wait=function(ms) if ms==0 then coroutine.yield(); return end; m.time=m.time+ms; if m.onWait then m.onWait(ms) end end
    e.CreateThread=function(fn)
        local co=coroutine.create(fn); local ok,err=coroutine.resume(co); assert(ok,err)
        if coroutine.status(co)~='dead' then m.listener=co end
    end
    e.print=function(msg) m.logs[#m.logs+1]=msg; if msg:find('native binding paused',1,true) then m.pausedAt=m.time end end
    e.DoesEntityExist=function(id) return (id==42 and m.exists) or id==99 end
    e.PlayerId=function() return 0 end
    e.PlayerPedId=function() return 99 end
    e.GetEntityModel=function() return 123 end
    e.GetEntityCoords=function() return {x=3,y=0,z=0} end
    e.NetworkHasControlOfEntity=function() return m.control end
    e.NetworkRequestControlOfEntity=function() m.controlRequests=(m.controlRequests or 0)+1; if m.grantControl then m.control=true end end
    e.NetworkGetEntityIsNetworked=function() return true end
    e.NetworkGetNetworkIdFromEntity=function() return 71 end
    e.NetworkRegisterEntityAsNetworked=function() end
    e.Entity=function() m.state.set=function(_,key,v) m.state[key]=v end; return {state=m.state} end
    e.CreatePed=function(hash,x,y,z,heading,networked,host)
        assert(hash==123 and x==3 and y==0 and z==0 and heading==0 and networked and host)
        m.created=(m.created or 0)+1; return 42
    end
    e.GetNumberOfEvents=function() return 0 end
    e.IsPedOnMount=function() return false end
    e.GetRiderOfMount=function(horse,flag) assert(horse==42 and flag==false,'rider native requires mount and explicit boolean'); return 0 end
    e.ClearPedTasks=function(horse) assert(horse==42); m.arrivals=(m.arrivals or 0)+1 end
    e.TaskGoToEntity=function(horse,ped,timeout,distance,speed)
        assert(horse==42 and ped==99 and timeout==-1 and distance==10.2 and speed==2.0)
        m.approaches=(m.approaches or 0)+1
    end
    e.SetEntityAsMissionEntity=function() end
    e.SetEntityVisible=function(_,v) m.visible=v end
    e.FreezeEntityPosition=function(_,v) m.frozen=v end
    e.SetEntityInvincible=function() end
    e.SetBlockingOfNonTemporaryEvents=function(_,value) m.blocked=value end
    e.RequestCollisionAtCoord=function() end
    e.HasCollisionLoadedAroundEntity=function() return not m.noCollision end
    e.ClearPedTasksImmediately=function() m.clears=(m.clears or 0)+1 end
    e.TaskStandStill=function() end
    e.IsEntityInAir=function() return m.inAir==true end
    e.IsPedFalling=function() return false end
    m.saddleSlot,m.activeSlot=0,0
    e.Citizen={ResultAsInteger=function() return 'integer-result' end,InvokeNative=function(hash,player,horse)
        if hash==0xB48050D326E9A2F3 then assert(player==0); return m.saddleSlot end
        if hash==0x46FA0AE18F4C7FA9 then assert(player==0); return m.activeSlot end
        if hash==0xD2CB0FB0FDCB473D then
            assert(player==0); m.saddleSlot=horse; m.associationWrites=(m.associationWrites or 0)+1
            if horse~=0 then m.activeSlot=horse end
        end
        if hash==0x8FBF9EDB378CCB8C then assert(player==0); m.activeSlot=horse end
    end}
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

test('client timing measures model entity grounding and bind separately',function()
    local m=fixture(); local model=m.env.exports['feather-toolkit'].LoadModel
    m.env.exports['feather-toolkit'].LoadModel=function(...) m.time=m.time+120; return model(...) end
    local create=m.env.CreatePed; m.env.CreatePed=function(...) m.time=m.time+80; return create(...) end
    m.rpcOverride=function(_,payload,callback)
        m.time=m.time+300
        callback({ok=true,value={generationId=payload.generationId,state='active',netId=71}})
    end
    m.spawn(); assert(m.visible and m.created==1)
    assert(m.logs[#m.logs]:find('modelMs=120 entityMs=80 groundingMs=750 holdMs=0 bindRpcMs=300 totalMs=1250',1,true))
end)
test('optional bind hold is measured separately from normal grounding',function()
    local m=fixture(); m.commands.BccStablesCallHold(0,{}); m.spawn()
    assert(m.visible and m.logs[#m.logs]:find('groundingMs=750 holdMs=10000 bindRpcMs=0 totalMs=10750',1,true))
end)
test('request RPC timing does not create from response or add a retry',function()
    local m=fixture(); m.rpcOverride=function(_,_,callback)
        m.time=m.time+250; callback({ok=true,value={generationId=ID,state='submitting',entitySpawning=true,gameplayAvailable=false}})
    end
    m.commands.BccStablesHorseCall(0,{})
    assert(#m.rpc==1 and not m.created and m.logs[#m.logs]:find('roundTripMs=250',1,true))
end)
test('timing output failure cannot delete a successfully bound client horse',function()
    local m=fixture(); local print=m.env.print
    m.env.print=function(msg)
        if msg:find('[bcc-stables:timing]',1,true) then error('logging unavailable') end
        return print(msg)
    end
    m.spawn(); assert(m.visible and m.deleted==0 and #m.rpc==1)
end)

local function movementReply(callback)
    callback({ok=true,value={generationId=ID,observerId=OBS,netId=71,modelKey='a_c_horse_morgan_bay',
        state='active',movementProof=true,gameplayAvailable=false}})
end
test('movement proof waits for matching authorization and applies pose change once',function()
    local m=fixture(); m.spawn(); local clears=m.clears
    m.rpcOverride=function(route,payload,callback)
        assert(route=='stables.horses.call.movement_proof.v1' and next(payload)==nil); movementReply(callback)
    end
    m.commands.BccStablesMovementProof(0,{})
    assert(not m.frozen and not m.blocked and m.clears==clears+1 and m.deleted==0)
    m.commands.BccStablesMovementProof(0,{})
    assert(m.clears==clears+1 and m.created==1)
end)
test('movement denial retains frozen fixture and does not delete or mutate identity',function()
    local m=fixture(); m.spawn(); local clears=m.clears
    m.rpcOverride=function(_,_,callback) callback(nil,{code='horse_not_found'}) end
    m.commands.BccStablesMovementProof(0,{})
    assert(m.frozen and m.blocked and m.clears==clears and m.deleted==0)
end)
test('movement control loss during authorization prevents unfreezing',function()
    local m=fixture(); m.spawn(); local clears=m.clears
    m.rpcOverride=function(_,_,callback) m.control=false; movementReply(callback) end
    m.commands.BccStablesMovementProof(0,{})
    assert(m.frozen and m.blocked and m.clears==clears and m.deleted==0)
end)

local function companionFixture()
    local m=fixture(); m.spawn(); m.rpcOverride=function(_,_,callback) movementReply(callback) end
    m.commands.BccStablesMovementProof(0,{})
    return m
end
test('companion proof uses player ID and verifies the saddle link',function()
    local m=companionFixture(); m.commands.BccStablesCompanionProof(0,{})
    assert(m.saddleSlot==42 and m.activeSlot==42 and m.associationWrites==1)
    m.commands.BccStablesCompanionProof(0,{})
    assert(m.associationWrites==1)
end)
test('companion proof refuses foreign native associations',function()
    local m=companionFixture(); m.saddleSlot=1234
    m.commands.BccStablesCompanionProof(0,{})
    assert(m.saddleSlot==1234 and m.activeSlot==0 and not m.associationWrites)
end)
test('companion cleanup clears only its own unchanged links before entity deletion',function()
    local m=companionFixture(); m.commands.BccStablesCompanionProof(0,{})
    m.handlers['bcc-stables:call:cancel'](ID)
    assert(m.saddleSlot==0 and m.activeSlot==0 and m.deleted==0)
end)
test('companion cleanup preserves replacement links owned by other resources',function()
    local m=companionFixture(); m.commands.BccStablesCompanionProof(0,{})
    m.saddleSlot,m.activeSlot=1234,5678
    m.handlers['bcc-stables:call:cancel'](ID)
    assert(m.saddleSlot==1234 and m.activeSlot==5678 and m.associationWrites==1)
end)
test('companion proof never claims association after authorization control loss',function()
    local m=companionFixture(); m.rpcOverride=function(_,_,callback) m.control=false; movementReply(callback) end
    m.commands.BccStablesCompanionProof(0,{})
    assert(m.saddleSlot==0 and not m.associationWrites)
end)

test('owner whistle approaches once per cooldown and refuses lost control',function()
    local m=companionFixture()
    m.env.string=setmetatable({blob=function() return string.pack('<i4i4i4i4',99,0,0,0) end},{__index=string})
    m.env.GetNumberOfEvents=function() return 1 end
    local native=m.env.Citizen.InvokeNative
    m.env.Citizen.InvokeNative=function(hash,...)
        if hash==0xA85E614430EFF816 then return 1327216456 end
        if hash==0x57EC5FA4D4D6AFCA then return true end
        return native(hash,...)
    end
    m.commands.BccStablesCompanionProof(0,{})
    assert(coroutine.resume(m.listener)); assert(m.approaches==1)
    assert(coroutine.resume(m.listener)); assert(m.approaches==1 and m.arrivals==1)
    m.time=m.time+1600; m.control=false
    assert(coroutine.resume(m.listener)); assert(m.approaches==1)
end)

test('owner whistle reacquires migrated control before approach',function()
    local m=companionFixture()
    m.env.string=setmetatable({blob=function() return string.pack('<i4i4i4i4',99,0,0,0) end},{__index=string})
    m.env.GetNumberOfEvents=function() return 1 end
    local native=m.env.Citizen.InvokeNative
    m.env.Citizen.InvokeNative=function(hash,...)
        if hash==0xA85E614430EFF816 then return 1327216456 end
        if hash==0x57EC5FA4D4D6AFCA then return true end
        return native(hash,...)
    end
    m.commands.BccStablesCompanionProof(0,{})
    m.control=false; m.grantControl=true
    assert(coroutine.resume(m.listener)); assert(m.approaches==1 and m.controlRequests==1)
end)

test('release during whistle control acquisition prevents approach',function()
    local m=companionFixture()
    m.env.string=setmetatable({blob=function() return string.pack('<i4i4i4i4',99,0,0,0) end},{__index=string})
    m.env.GetNumberOfEvents=function() return 1 end
    local native=m.env.Citizen.InvokeNative
    m.env.Citizen.InvokeNative=function(hash,...)
        if hash==0xA85E614430EFF816 then return 1327216456 end
        if hash==0x57EC5FA4D4D6AFCA then return true end
        return native(hash,...)
    end
    m.commands.BccStablesCompanionProof(0,{})
    m.control=false; m.onWait=function(ms) if ms==25 then m.handlers['bcc-stables:call:cancel'](ID) end end
    assert(coroutine.resume(m.listener)); assert(not m.approaches and m.controlRequests==1)
end)

test('foreign ped whistle never tasks the owned horse',function()
    local m=companionFixture()
    m.env.string=setmetatable({blob=function() return string.pack('<i4i4i4i4',101,0,0,0) end},{__index=string})
    m.env.GetNumberOfEvents=function() return 1 end
    local native=m.env.Citizen.InvokeNative
    m.env.Citizen.InvokeNative=function(hash,...)
        if hash==0xA85E614430EFF816 then return 1327216456 end
        if hash==0x57EC5FA4D4D6AFCA then return true end
        return native(hash,...)
    end
    m.commands.BccStablesCompanionProof(0,{})
    assert(coroutine.resume(m.listener)); assert(not m.approaches)
end)

test('whistle listener stops after companion release',function()
    local m=companionFixture(); m.commands.BccStablesCompanionProof(0,{})
    assert(m.listener and coroutine.status(m.listener)=='suspended')
    m.handlers['bcc-stables:call:cancel'](ID)
    assert(coroutine.resume(m.listener)); assert(coroutine.status(m.listener)=='dead' and not m.approaches)
end)


local function relayFixture()
    local m=fixture()
    m.state.bccStablesGeneration=ID; m.state.bccStablesObserver=OBS
    m.env.NetworkGetEntityFromNetworkId=function(net) return net==71 and 42 or net==72 and 99 or 0 end
    m.env.NetworkGetNetworkIdFromEntity=function(entity) return entity==42 and 71 or 72 end
    m.env.GetHashKey=function(model) assert(model=='a_c_horse_morgan_bay'); return 123 end
    m.env.GetPlayerFromServerId=function(id) return id==1 and 7 or -1 end
    m.env.GetPlayerPed=function(player) return player==7 and 99 or 0 end
    m.rpcOverride=function(route,payload,callback)
        assert(route=='stables.horses.call.whistle_claim.v1' and payload.generationId==ID and payload.sequence==1)
        callback({ok=true,value={generationId=ID,observerId=OBS,sequence=1,netId=71,targetNetId=72,
            modelKey='a_c_horse_morgan_bay',ownerSource=1}})
    end
    return m
end

test('delegated whistle redeems server ticket and applies matching horse approach and arrival',function()
    local m=relayFixture(); m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
    assert(m.approaches==1 and m.arrivals==1 and #m.rpc==1 and not m.created)
end)

test('local forged delegated whistle and denied claim issue no task',function()
    local m=relayFixture(); m.env.source=1
    m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1}); assert(#m.rpc==0)
    m.env.source=65535; m.rpcOverride=function(_,_,cb) cb({ok=false,code='stale_whistle'}) end
    m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1}); assert(not m.approaches)
end)

test('delegated whistle refuses changed marker control target ped and rider',function()
    for _,mode in ipairs({'marker','control','target','rider'}) do
        local m=relayFixture()
        if mode=='marker' then m.state.bccStablesObserver='different' end
        if mode=='control' then m.control=false end
        if mode=='target' then m.env.GetPlayerPed=function() return 100 end end
        if mode=='rider' then m.env.GetRiderOfMount=function() return 100 end end
        m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
        assert(not m.approaches and not m.arrivals)
    end
end)

test('delegated cancellation while claim awaits prevents movement',function()
    local m=relayFixture(); local reply=m.rpcOverride
    m.rpcOverride=function(route,payload,callback)
        m.handlers['bcc-stables:call:whistle_cancel']({generationId=ID,observerId=OBS,sequence=1})
        reply(route,payload,callback)
    end
    m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
    assert(not m.approaches)
end)

test('delegated cleanup stops owned approach but never clears a new rider task',function()
    for _,ridden in ipairs({false,true}) do
        local m=relayFixture()
        m.env.GetEntityCoords=function(entity) return {x=entity==42 and 30 or 0,y=0,z=0} end
        m.onWait=function(ms)
            if ms==50 then
                m.handlers['bcc-stables:call:whistle_cancel']({generationId=ID,observerId=OBS,sequence=1})
                if ridden then m.env.GetRiderOfMount=function() return 100 end end
            end
        end
        m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
        assert(m.approaches==1 and (ridden and not m.arrivals or not ridden and m.arrivals==1))
    end
end)

test('explicit relay proof sends empty owner request without acquiring migrated control',function()
    local m=companionFixture(); m.commands.BccStablesCompanionProof(0,{})
    m.control=false
    m.rpcOverride=function(route,payload,callback)
        assert(route=='stables.horses.call.whistle.v1' and next(payload)==nil)
        callback({ok=true,value={generationId=ID,relayed=true,networkOwner=2}})
    end
    local before=#m.rpc; m.commands.BccStablesWhistleRelayProof(0,{})
    assert(#m.rpc==before+1 and not m.controlRequests and not m.approaches)
end)

print(count..'/'..count..' native client cases passed; grounding/replication remain live gates.')
