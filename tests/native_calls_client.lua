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
    e.GetHashKey=function(value) return value=='WHISTLEHORSESHORT' and 11 or value=='WHISTLEHORSELONG' and 12 or 123 end
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
    e.IsEntityDead=function() return false end
    e.IsPedDeadOrDying=function(_,flag) assert(flag==true); return false end
    e.GetMount=function() return 0 end
    e.GetRiderOfMount=function(horse,flag) assert(horse==42 and type(flag)=='boolean','rider native requires mount and explicit boolean'); return 0 end
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
    e.Citizen={ResultAsInteger=function() return 'integer-result' end,InvokeNative=function(hash,player,horse,...)
        if hash==0x1913FE4CBF41C463 then
            assert(player==42 and horse==297 and select(1,...)==true)
            m.leadPromptFlags=(m.leadPromptFlags or 0)+1
        end
        if hash==0xEFC4303DDC6E60D3 then return m.leading==true end
        if hash==0xED1F514AF4732258 then return m.ledHorse or 0 end
        if hash==0xAC5045AB7F1A34FD then return m.leading==true and m.ledHorse==player end
        if hash==0x9A7A4A54596FE09D then assert(player==99 and horse==42); m.leading=true; m.ledHorse=horse; m.leadStarts=(m.leadStarts or 0)+1 end
        if hash==0xED27560703F37258 then assert(player==99); m.leading=false; m.ledHorse=0; m.leadStops=(m.leadStops or 0)+1 end
        if hash==0x304AE42E357B8C7E then
            assert(player==42 and horse==99)
            local args=table.pack(...)
            assert(args.n==12 and args[1]==2.0 and args[2]==-3.0 and args[3]==0.0 and args[4]==2.0
                and type(args[5])=='number' and args[5]>=1 and args[5]<=30000 and args[6]==3.0 and args[7]==true)
            for i=8,12 do assert(args[i]==false) end
            m.followDuration=args[5]
            m.followTasks=(m.followTasks or 0)+1
        end
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
            callback({ok=true,value={generationId=payload.generationId,state=route=='stables.horses.call.bind.v1' and 'active' or route=='stables.horses.call.dispatch.v1' and 'submitting' or 'released',netId=71,nativeBehavior=route=='stables.horses.call.bind.v1' and m.nativeBehavior==true,gameplayAvailable=false,entitySpawning=route=='stables.horses.call.dispatch.v1'}})
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

local function whistleFixture(kind,ped,signed)
    local m=companionFixture()
    if signed then m.env.GetHashKey=function(value) return value=='WHISTLEHORSESHORT' and -1 or value=='WHISTLEHORSELONG' and -2 or 123 end end
    m.env.string=setmetatable({blob=function() return string.pack('<i4i4i4i4',ped or 99,0,kind or 11,0) end},{__index=string})
    m.env.GetNumberOfEvents=function() return 1 end
    local native=m.env.Citizen.InvokeNative
    m.env.Citizen.InvokeNative=function(hash,...)
        if hash==0xA85E614430EFF816 then return 1327216456 end
        if hash==0x57EC5FA4D4D6AFCA then return true end
        return native(hash,...)
    end
    m.commands.BccStablesCompanionProof(0,{})
    m.whistleRequests=0
    m.rpcOverride=function(route,payload,callback)
        assert(route=='stables.horses.call.whistle.v1')
        m.whistleRequests=m.whistleRequests+1; m.lastMode=payload.mode
        callback({ok=true,value={generationId=ID,mode=payload.mode=='toggle_follow' and 'follow' or payload.mode,relayed=true,networkOwner=2}})
    end
    return m
end

test('owner short whistle delegates once per cooldown without local native movement',function()
    local m=whistleFixture()
    assert(coroutine.resume(m.listener)); assert(m.whistleRequests==1 and m.lastMode=='approach')
    assert(coroutine.resume(m.listener)); assert(m.whistleRequests==1)
    assert(not m.approaches and not m.controlRequests)
end)

test('owner whistle still delegates when simulation control is remote',function()
    local m=whistleFixture(); m.control=false
    assert(coroutine.resume(m.listener)); assert(m.whistleRequests==1 and not m.controlRequests and not m.approaches)
end)

test('owner long whistle requests server follow toggle without trusting local follow state',function()
    local m=whistleFixture(12)
    assert(coroutine.resume(m.listener)); assert(m.whistleRequests==1 and m.lastMode=='toggle_follow')
    m.time=m.time+1600
    assert(coroutine.resume(m.listener)); assert(m.whistleRequests==2 and m.lastMode=='toggle_follow')
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
        if route=='stables.horses.call.whistle_done.v1' then
            assert(payload.generationId==ID and payload.sequence==1)
            m.followEnds=(m.followEnds or 0)+1
            callback({ok=true,value={state='ended'}}); return
        end
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


local function followFixture()
    local m=companionFixture(); m.commands.BccStablesCompanionProof(0,{})
    return m
end

test('follow proof requires companion and fresh owner authorization',function()
    local m=companionFixture(); m.commands.BccStablesFollowProof(0,{})
    assert(not m.followTasks)
    m=followFixture(); m.rpcOverride=function(_,_,cb) cb({ok=false,code='horse_not_found'}) end
    m.commands.BccStablesFollowProof(0,{}); assert(not m.followTasks)
end)

test('follow proof uses full native signature and repeat does not replace task',function()
    local m=followFixture(); m.commands.BccStablesFollowProof(0,{})
    assert(m.followTasks==1 and not m.arrivals)
    m.commands.BccStablesFollowProof(0,{}); assert(m.followTasks==1)
    m.commands.BccStablesFollowStop(0,{}); assert(m.arrivals==1)
    m.commands.BccStablesFollowStop(0,{}); assert(m.arrivals==1)
end)

test('follow refuses mount control or association changes during authorization',function()
    for _,mode in ipairs({'control','association','mounted','rider'}) do
        local m=followFixture()
        m.rpcOverride=function(_,_,cb)
            if mode=='control' then m.control=false end
            if mode=='association' then m.saddleSlot=100 end
            if mode=='mounted' then m.env.IsPedOnMount=function() return true end end
            if mode=='rider' then m.env.GetRiderOfMount=function() return 100 end end
            movementReply(cb)
        end
        m.commands.BccStablesFollowProof(0,{})
        assert(not m.followTasks and not m.arrivals)
    end
end)

test('follow expires using existing listener and clears only its task once',function()
    local m=followFixture(); m.commands.BccStablesFollowProof(0,{})
    m.time=m.time+30001; assert(coroutine.resume(m.listener)); assert(m.arrivals==1)
    assert(coroutine.resume(m.listener)); assert(m.arrivals==1)
end)

test('follow mounting or migrated control never clears rider or remote task',function()
    for _,mode in ipairs({'mounted','rider','control','marker'}) do
        local m=followFixture(); m.commands.BccStablesFollowProof(0,{})
        if mode=='control' then m.control=false end
        if mode=='marker' then m.state.bccStablesObserver='different' end
        if mode=='mounted' then m.env.IsPedOnMount=function() return true end end
        if mode=='rider' then m.env.GetRiderOfMount=function() return 100 end end
        assert(coroutine.resume(m.listener)); assert(not m.arrivals)
        m.commands.BccStablesFollowStop(0,{}); assert(not m.arrivals)
    end
end)

test('follow cancellation clears current task before companion refs and never deletes remote identity',function()
    local m=followFixture(); m.commands.BccStablesFollowProof(0,{})
    m.handlers['bcc-stables:call:cancel'](ID)
    assert(m.arrivals==1 and m.saddleSlot==0 and m.activeSlot==0 and m.deleted==0)
end)


test('delegated follow persists at arrival and responds to cancellation',function()
    local m=relayFixture(); local reply=m.rpcOverride
    m.rpcOverride=function(route,payload,cb) reply(route,payload,function(result) result.value.mode='follow'; cb(result) end) end
    m.onWait=function(ms) if ms==50 then m.handlers['bcc-stables:call:whistle_cancel']({generationId=ID,observerId=OBS,sequence=1}) end end
    m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
    assert(m.followTasks==1 and not m.approaches and m.arrivals==1)
end)

test('delegated follow times out and preserves any rider task',function()
    for _,ridden in ipairs({false,true}) do
        local m=relayFixture(); local reply=m.rpcOverride; local started=m.time
        m.rpcOverride=function(route,payload,cb) reply(route,payload,function(result) result.value.mode='follow'; cb(result) end) end
        if ridden then m.onWait=function(ms) if ms==50 then m.env.GetRiderOfMount=function() return 100 end end end end
        m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
        assert(m.followTasks==1 and (ridden and not m.arrivals or not ridden and m.arrivals==1))
        if not ridden then assert(m.time-started==30000) end
    end
end)

test('delegated stop clears exact unridden entity but not a rider or changed identity',function()
    for _,mode in ipairs({'valid','rider','marker'}) do
        local m=relayFixture(); local reply=m.rpcOverride
        m.rpcOverride=function(route,payload,cb) reply(route,payload,function(result) result.value.mode='stop'; cb(result) end) end
        if mode=='rider' then m.env.GetRiderOfMount=function() return 100 end end
        if mode=='marker' then m.state.bccStablesObserver='different' end
        m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
        assert(not m.followTasks and not m.approaches)
        assert(mode=='valid' and m.arrivals==1 or mode~='valid' and not m.arrivals)
    end
end)

test('follow relay proof and stop use bounded mode payloads without local control requests',function()
    local m=followFixture(); m.control=false
    local mode='follow'
    m.rpcOverride=function(route,payload,cb)
        assert(route=='stables.horses.call.whistle.v1' and payload.mode==mode)
        cb({ok=true,value={generationId=ID,mode=mode,networkOwner=2,relayed=true}})
    end
    m.commands.BccStablesFollowRelayProof(0,{})
    mode='stop'; m.commands.BccStablesFollowRelayStop(0,{})
    assert(not m.controlRequests and not m.followTasks and not m.approaches)
end)

test('unknown whistle kind and foreign whistling ped never request movement',function()
    for _,m in ipairs({whistleFixture(13),whistleFixture(11,101)}) do
        assert(coroutine.resume(m.listener)); assert(m.whistleRequests==0 and not m.approaches)
    end
end)

test('whistle denied server response never applies a local fallback task',function()
    local m=whistleFixture(12)
    m.rpcOverride=function(_,_,cb) cb({ok=false,code='horse_not_found'}) end
    assert(coroutine.resume(m.listener)); assert(not m.approaches and not m.followTasks)
end)

test('signed native whistle hashes match normalized event payloads',function()
    for _,case in ipairs({{-1,'approach'},{-2,'toggle_follow'}}) do
        local m=whistleFixture(case[1],99,true)
        assert(coroutine.resume(m.listener)); assert(m.whistleRequests==1 and m.lastMode==case[2])
    end
end)

test('normal store rejects mounted horse locally without server mutation request',function()
    local m=companionFixture(); local count=#m.rpc
    m.env.GetRiderOfMount=function() return 99 end
    m.commands.BccStablesHorseStore(0,{})
    assert(#m.rpc==count and m.saddleSlot==0 and m.deleted==0)
    assert(m.logs[#m.logs]:find('horse_occupied',1,true))
end)

test('mounted store checks both native rider variants and local mount fallback',function()
    for _,mode in ipairs({'second','fallback','unknown'}) do
        local m=companionFixture(); local count=#m.rpc
        m.env.GetRiderOfMount=function(_,flag) if mode=='unknown' then return nil end; return mode=='second' and flag and 99 or 0 end
        if mode=='fallback' then m.env.IsPedOnMount=function() return true end; m.env.GetMount=function() return 42 end end
        m.commands.BccStablesHorseStore(0,{})
        assert(#m.rpc==count and m.deleted==0)
    end
end)

test('server guard proof bypasses only local fast check not server store request',function()
    local m=companionFixture(); m.env.GetRiderOfMount=function() return 99 end
    m.rpcOverride=function(route,payload,cb)
        assert(route=='stables.horses.call.store_current.v1' and next(payload)==nil)
        cb({ok=false,code='horse_occupied'})
    end
    local count=#m.rpc; m.commands.BccStablesStoreGuardProof(0,{})
    assert(#m.rpc==count+1 and m.deleted==0)
end)

test('simulator reports observed occupancy only for exact controlled server instruction',function()
    for _,mode in ipairs({'empty','rider','control','marker','forged'}) do
        local m=relayFixture()
        if mode=='rider' then m.env.GetRiderOfMount=function() return 99 end end
        if mode=='control' then m.control=false end
        if mode=='marker' then m.state.bccStablesObserver='other' end
        if mode=='forged' then m.env.source=1 end
        local calls=0
        m.rpcOverride=function(route,p,cb)
            assert(route=='stables.horses.call.store_check_result.v1' and p.generationId==ID and p.sequence==1)
            assert(p.occupied==(mode=='rider')); calls=calls+1; cb({ok=true,value={recorded=true}})
        end
        m.handlers['bcc-stables:call:store_check']({generationId=ID,observerId=OBS,netId=71,modelKey='a_c_horse_morgan_bay',sequence=1})
        assert(calls==((mode=='empty' or mode=='rider') and 1 or 0) and not m.approaches and m.deleted==0)
    end
end)

test('relocation pending retries original generation without local spawn or delete',function()
    local m=fixture(); m.spawn(); local calls=0; local new='b0000000-0000-4000-8000-000000000009'
    m.rpcOverride=function(route,p,cb)
        assert(route=='stables.horses.call.relocate_proof.v1' and p.generationId==ID)
        calls=calls+1
        if calls==1 then
            m.handlers['bcc-stables:call:cancel'](ID)
            cb({ok=true,value={state='cleanup_pending',originalGenerationId=ID,gameplayAvailable=false}})
        else cb({ok=true,value={state='replacement_requested',originalGenerationId=ID,generationId=new,gameplayAvailable=false}}) end
    end
    m.commands.BccStablesRelocateProof(0,{})
    m.commands.BccStablesRelocateProof(0,{})
    assert(calls==2 and m.created==1 and m.deleted==0)
end)

test('relocation result cannot create an entity and malformed result is not accepted',function()
    local m=fixture(); m.spawn()
    m.rpcOverride=function(_,_,cb) cb({ok=true,value={state='replacement_requested',originalGenerationId=ID,generationId=ID,gameplayAvailable=false}}) end
    m.commands.BccStablesRelocateProof(0,{})
    assert(m.created==1 and m.deleted==0 and m.logs[#m.logs]:find('invalid_result',1,true))
end)

test('ordinary call automatically continues only same-original cleanup pending receipt',function()
    local m=fixture(); local calls=0
    local new='b0000000-0000-4000-8000-000000000009'
    m.rpcOverride=function(route,p,cb)
        calls=calls+1
        if calls==1 then
            assert(route=='stables.horses.call.request.v1' and next(p)==nil)
            cb({ok=true,value={relocation=true,originalGenerationId=ID,state='cleanup_pending',retryRequired=true,gameplayAvailable=false}})
        else
            assert(route=='stables.horses.call.relocate_proof.v1' and p.generationId==ID)
            cb({ok=true,value={originalGenerationId=ID,generationId=new,state='replacement_requested',gameplayAvailable=false}})
        end
    end
    m.commands.BccStablesHorseCall(0,{})
    assert(calls==2 and m.time==1500 and not m.created and m.logs[#m.logs]:find('request_rpc',1,true))
end)

test('automatic relocation aborts on unknown error without retrying normal request',function()
    local m=fixture(); local calls=0
    m.rpcOverride=function(route,p,cb)
        calls=calls+1
        if calls==1 then cb({ok=true,value={relocation=true,originalGenerationId=ID,state='cleanup_pending',retryRequired=true,gameplayAvailable=false}})
        else assert(route=='stables.horses.call.relocate_proof.v1'); cb({ok=false,code='database_error'}) end
    end
    m.commands.BccStablesHorseCall(0,{})
    assert(calls==2 and not m.created and m.logs[#m.logs]:find('database_error',1,true))
end)

test('automatic relocation has bounded cleanup polling and rejects changed original receipt',function()
    for _,changed in ipairs({false,true}) do
        local m=fixture(); local calls=0
        m.rpcOverride=function(_,_,cb)
            calls=calls+1
            cb({ok=true,value={relocation=calls==1,originalGenerationId=changed and calls>1 and OBS or ID,
                state='cleanup_pending',retryRequired=true,gameplayAvailable=false}})
        end
        m.commands.BccStablesHorseCall(0,{})
        assert(not m.created)
        if changed then assert(calls==2 and m.logs[#m.logs]:find('invalid_result',1,true))
        else assert(calls==11 and m.time==15000 and m.logs[#m.logs]:find('relocation_pending',1,true)) end
    end
end)

test('natural short whistle completes pending relocation after original client record is cancelled',function()
    local m=whistleFixture(); local calls=0
    m.rpcOverride=function(route,p,cb)
        calls=calls+1
        if calls==1 then
            assert(route=='stables.horses.call.whistle.v1' and p.mode=='approach')
            m.handlers['bcc-stables:call:cancel'](ID)
            cb({ok=true,value={relocation=true,originalGenerationId=ID,state='cleanup_pending',retryRequired=true,gameplayAvailable=false}})
        else
            assert(route=='stables.horses.call.relocate_proof.v1' and p.generationId==ID)
            cb({ok=true,value={originalGenerationId=ID,generationId='b0000000-0000-4000-8000-000000000009',state='replacement_requested',gameplayAvailable=false}})
        end
    end
    assert(coroutine.resume(m.listener))
    assert(calls==2 and m.created==1 and m.deleted==0 and m.logs[#m.logs]:find('whistle relocation requested',1,true))
end)

test('enabled bound behavior unfreezes associates and listens with no extra authorization RPC',function()
    local m=fixture(); m.nativeBehavior=true; m.spawn()
    assert(not m.frozen and not m.blocked and m.saddleSlot==42 and m.activeSlot==42 and m.visible)
    assert(#m.rpc==1 and m.rpc[1].route=='stables.horses.call.bind.v1' and m.listener and m.deleted==0)
end)

test('create instruction cannot grant automatic behavior without bind authorization',function()
    local m=fixture(); m.spec.nativeBehavior=true; m.spawn()
    assert(m.frozen and m.blocked and not m.associationWrites and not m.listener)
end)

test('rejected bind never enables native behavior or companion association',function()
    local m=fixture(); m.nativeBehavior=true; m.rejectBind=true; m.spawn()
    assert(not m.associationWrites and m.saddleSlot==0 and m.deleted==1)
end)

test('automatic companion conflict preserves foreign association and committed visible horse',function()
    local m=fixture(); m.nativeBehavior=true; m.saddleSlot=100; m.spawn()
    assert(not m.frozen and m.visible and m.saddleSlot==100 and not m.associationWrites)
    assert(m.deleted==0 and #m.rpc==1 and not m.listener)
end)

test('automatic movement failure refreezes without deleting committed horse',function()
    local m=fixture(); m.nativeBehavior=true
    m.rpcOverride=function(route,p,cb)
        assert(route=='stables.horses.call.bind.v1')
        m.env.ClearPedTasksImmediately=function() error('native failure') end
        cb({ok=true,value={generationId=ID,state='active',netId=71,nativeBehavior=true,gameplayAvailable=false}})
    end
    m.spawn()
    assert(m.visible and m.frozen and m.blocked and m.deleted==0 and #m.rpc==1 and not m.associationWrites)
end)

test('automatic companion native failure never deletes committed entity or falls back to store',function()
    local m=fixture(); m.nativeBehavior=true; local native=m.env.Citizen.InvokeNative
    m.env.Citizen.InvokeNative=function(hash,...)
        if hash==0xD2CB0FB0FDCB473D then error('association failed') end
        return native(hash,...)
    end
    m.spawn()
    assert(m.visible and not m.frozen and m.deleted==0 and #m.rpc==1)
end)

test('automatic behavior cleans references and reapplies on a fresh replacement generation',function()
    local m=fixture(); m.nativeBehavior=true; m.spawn()
    m.handlers['bcc-stables:call:cancel'](ID)
    assert(m.saddleSlot==0 and m.activeSlot==0 and m.deleted==0)
    m.spec.generationId='b0000000-0000-4000-8000-000000000009'
    m.spawn()
    assert(m.created==2 and not m.frozen and m.saddleSlot==42 and #m.rpc==2 and m.deleted==0)
end)

print(count..'/'..count..' native client cases passed; grounding/replication remain live gates.')


test('delegated movement and stop reject second rider and invalid observations',function()
    for _,action in ipairs({'approach','follow','stop'}) do
        for _,observation in ipairs({'second','unknown','throws'}) do
            local m=relayFixture(); local reply=m.rpcOverride
            m.rpcOverride=function(route,payload,cb) reply(route,payload,function(result) result.value.mode=action; cb(result) end) end
            m.env.GetRiderOfMount=function(_,flag)
                if observation=='throws' then error('native unavailable') end
                if observation=='unknown' then return nil end
                return flag and 100 or 0
            end
            m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
            assert(not m.approaches and not m.followTasks and not m.arrivals)
        end
    end
end)

test('delegated movement preserves newly occupied or unknown tasks',function()
    for _,action in ipairs({'approach','follow'}) do
        for _,observation in ipairs({'second','unknown','throws'}) do
            local m=relayFixture(); local reply=m.rpcOverride
            m.env.GetEntityCoords=function(entity) return {x=entity==42 and 30 or 0,y=0,z=0} end
            m.rpcOverride=function(route,payload,cb) reply(route,payload,function(result) result.value.mode=action; cb(result) end) end
            m.onWait=function(ms) if ms==50 then
                m.env.GetRiderOfMount=function(_,flag)
                    if observation=='throws' then error('native unavailable') end
                    if observation=='unknown' then return nil end
                    return flag and 100 or 0
                end
            end end
            m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
            assert((m.approaches==1 or m.followTasks==1) and not m.arrivals)
        end
    end
end)

test('local follow preserves tasks on second rider or unknown occupancy',function()
    for _,observation in ipairs({'second','unknown','throws'}) do
        local m=followFixture(); m.commands.BccStablesFollowProof(0,{})
        assert(m.followTasks==1)
        m.env.GetRiderOfMount=function(_,flag)
            if observation=='throws' then error('native unavailable') end
            if observation=='unknown' then return nil end
            return flag and 100 or 0
        end
        assert(coroutine.resume(m.listener))
        m.commands.BccStablesFollowStop(0,{})
        assert(not m.arrivals)
    end
end)


test('delegated follow reports one completion on expiration or early occupancy loss',function()
    for _,mode in ipairs({'timeout','occupied','invalid_start'}) do
        local m=relayFixture(); local reply=m.rpcOverride
        m.rpcOverride=function(route,payload,cb)
            if route=='stables.horses.call.whistle_claim.v1' then
                reply(route,payload,function(result) result.value.mode='follow'; cb(result) end)
            else reply(route,payload,cb) end
        end
        if mode=='invalid_start' then m.control=false end
        if mode=='occupied' then m.onWait=function(ms) if ms==50 then m.env.GetRiderOfMount=function() return 100 end end end end
        m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
        assert(m.followEnds==1 and #m.rpc==2)
        assert((mode=='invalid_start' and not m.followTasks) or (mode~='invalid_start' and m.followTasks==1))
    end
end)

test('approach and stop do not add follow completion RPCs',function()
    for _,mode in ipairs({'approach','stop'}) do
        local m=relayFixture(); local reply=m.rpcOverride
        m.rpcOverride=function(route,payload,cb) reply(route,payload,function(result) result.value.mode=mode; cb(result) end) end
        m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
        assert(not m.followEnds and #m.rpc==1)
    end
end)

test('lost completion reply never retries or deletes the bound horse',function()
    local m=relayFixture(); local reply=m.rpcOverride; local completions=0
    m.rpcOverride=function(route,payload,cb)
        if route=='stables.horses.call.whistle_done.v1' then completions=completions+1; cb({ok=false,code='timeout'}); return end
        reply(route,payload,function(result) result.value.mode='follow'; cb(result) end)
    end
    m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
    assert(completions==1 and m.followTasks==1 and m.deleted==0)
end)


test('nearby HorseCall accepts approach receipt without creation or bind waiting',function()
    local m=fixture()
    m.rpcOverride=function(route,payload,cb)
        assert(route=='stables.horses.call.request.v1' and next(payload)==nil)
        cb({ok=true,value={generationId=ID,state='approach_requested',mode='approach',relayed=true,
            entitySpawning=false,gameplayAvailable=false,networkOwner=2}})
    end
    m.commands.BccStablesHorseCall(0,{})
    assert(#m.rpc==1 and not m.created and m.logs[1]:find('current horse approach requested',1,true))
end)

test('nearby HorseCall malformed approach receipt cannot become a spawn instruction',function()
    for _,mode in ipairs({'owner','spawning','state','mode','relay'}) do
        local m=fixture()
        m.rpcOverride=function(_,_,cb)
            local v={generationId=ID,state='approach_requested',mode='approach',relayed=true,
                entitySpawning=false,gameplayAvailable=false,networkOwner=2}
            if mode=='owner' then v.networkOwner=0 end
            if mode=='spawning' then v.entitySpawning=true end
            if mode=='state' then v.state='active' end
            if mode=='mode' then v.mode='follow' end
            if mode=='relay' then v.relayed=false end
            cb({ok=true,value=v})
        end
        m.commands.BccStablesHorseCall(0,{})
        assert(#m.rpc==1 and not m.created and m.logs[1]:find('invalid_result',1,true))
    end
end)


test('delegated handoff follow uses bounded remaining duration rather than restarting thirty seconds',function()
    local m=relayFixture(); local reply=m.rpcOverride; local started=m.time
    m.rpcOverride=function(route,payload,cb)
        if route=='stables.horses.call.whistle_claim.v1' then
            reply(route,payload,function(result) result.value.mode='follow'; result.value.followMs=1250; cb(result) end)
        else reply(route,payload,cb) end
    end
    m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
    assert(m.followTasks==1 and m.followDuration==1250 and m.time-started==1250 and m.followEnds==1)
    assert(table.concat(m.logs,'\n'):find('reason=timeout elapsedMs=1250',1,true))
end)

test('delegated follow refuses malformed or unbounded remaining duration',function()
    for _,duration in ipairs({0,-1,30001,1.5,'1000'}) do
        local m=relayFixture(); local reply=m.rpcOverride
        m.rpcOverride=function(route,payload,cb)
            reply(route,payload,function(result) result.value.mode='follow'; result.value.followMs=duration; cb(result) end)
        end
        m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
        assert(not m.followTasks and not m.arrivals and not m.followEnds)
    end
end)


test('delegated task logs correlate the generation and ticket sequence',function()
    for _,mode in ipairs({'approach','follow','stop'}) do
        local m=relayFixture(); local reply=m.rpcOverride
        m.rpcOverride=function(route,payload,cb)
            if route=='stables.horses.call.whistle_claim.v1' then
                reply(route,payload,function(result) result.value.mode=mode; cb(result) end)
            else reply(route,payload,cb) end
        end
        m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
        local observed=false
        for _,line in ipairs(m.logs) do
            if line:find('delegated',1,true) then
                assert(line:find('generationId='..ID,1,true) and line:find('sequence=1',1,true)); observed=true
            end
        end
        assert(observed)
    end
end)


test('delegated approach and follow reject dead dying and unknown life observations',function()
    for _,action in ipairs({'approach','follow'}) do
        for _,subject in ipairs({42,99}) do
            for _,observation in ipairs({'dead','dying','unknown','throws'}) do
                local m=relayFixture(); local reply=m.rpcOverride
                m.rpcOverride=function(route,payload,cb)
                    if route=='stables.horses.call.whistle_claim.v1' then
                        reply(route,payload,function(result) result.value.mode=action; cb(result) end)
                    else reply(route,payload,cb) end
                end
                m.env.IsEntityDead=function(entity)
                    if entity~=subject then return false end
                    if observation=='throws' then error('native unavailable') end
                    if observation=='unknown' then return nil end
                    return observation=='dead'
                end
                m.env.IsPedDeadOrDying=function(entity) return entity==subject and observation=='dying' end
                m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
                assert(not m.approaches and not m.followTasks and not m.arrivals and m.deleted==0)
                assert(action~='follow' or m.followEnds==1)
            end
        end
    end
end)

test('target death ends delegated movement and clears only the surviving unridden horse task',function()
    for _,action in ipairs({'approach','follow'}) do
        local m=relayFixture(); local reply=m.rpcOverride
        m.env.GetEntityCoords=function(entity) return {x=entity==42 and 30 or 0,y=0,z=0} end
        m.rpcOverride=function(route,payload,cb)
            if route=='stables.horses.call.whistle_claim.v1' then
                reply(route,payload,function(result) result.value.mode=action; cb(result) end)
            else reply(route,payload,cb) end
        end
        m.onWait=function(ms) if ms==50 then m.env.IsEntityDead=function(entity) return entity==99 end end end
        m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
        assert((m.approaches==1 or m.followTasks==1) and m.arrivals==1 and m.deleted==0)
        if action=='follow' then assert(table.concat(m.logs,'\n'):find('reason=target_not_alive_or_unknown',1,true)) end
    end
end)

test('horse death ends delegated movement without clearing dead horse or deleting entity',function()
    local m=relayFixture(); local reply=m.rpcOverride
    m.rpcOverride=function(route,payload,cb)
        if route=='stables.horses.call.whistle_claim.v1' then
            reply(route,payload,function(result) result.value.mode='follow'; cb(result) end)
        else reply(route,payload,cb) end
    end
    m.onWait=function(ms) if ms==50 then m.env.IsPedDeadOrDying=function(entity) return entity==42 end end end
    m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
    assert(m.followTasks==1 and not m.arrivals and m.followEnds==1 and m.deleted==0)
    assert(table.concat(m.logs,'\n'):find('reason=horse_not_alive_or_unknown',1,true))
end)

test('dead owner whistle is ignored and revived same-ped listener recovers',function()
    local m=whistleFixture(12)
    m.env.IsEntityDead=function(entity) return entity==99 end
    assert(coroutine.resume(m.listener)); assert(m.whistleRequests==0)
    m.env.IsEntityDead=function() return false end
    assert(coroutine.resume(m.listener)); assert(m.whistleRequests==1)
end)

test('local follow eligibility ends on target death while preserving living horse identity',function()
    local m=followFixture(); m.commands.BccStablesFollowProof(0,{})
    m.env.IsEntityDead=function(entity) return entity==99 end
    assert(coroutine.resume(m.listener))
    assert(m.followTasks==1 and m.arrivals==1 and m.deleted==0 and m.saddleSlot==42)
end)


local function leadFixture()
    local m=followFixture()
    m.rpcOverride=function(route,payload,callback)
        assert(route=='stables.horses.call.movement_proof.v1')
        movementReply(function(result) result.value.movementIdle=true; callback(result) end)
    end
    return m
end

test('leading proof starts exact native once and stop releases only its own led horse',function()
    local m=leadFixture(); m.commands.BccStablesLeadProof(0,{})
    assert(m.leadStarts==1 and m.leading and m.ledHorse==42 and m.deleted==0)
    m.commands.BccStablesLeadProof(0,{}); assert(m.leadStarts==1)
    m.commands.BccStablesLeadInspect(0,{})
    assert(m.logs[#m.logs]:find('matchesBoundHorse=true',1,true))
    m.commands.BccStablesLeadStop(0,{})
    assert(m.leadStops==1 and not m.leading and m.deleted==0)
    m.commands.BccStablesLeadStop(0,{}); assert(m.leadStops==1)
end)

test('leading proof refuses distant mounted dead foreign lead and denied authorization',function()
    for _,mode in ipairs({'distance','mounted','dead','foreign','denied','movement','remote'}) do
        local m=leadFixture()
        if mode=='distance' then m.env.GetEntityCoords=function(entity) return {x=entity==42 and 10 or 0,y=0,z=0} end end
        if mode=='mounted' then m.env.IsPedOnMount=function() return true end end
        if mode=='dead' then m.env.IsEntityDead=function() return true end end
        if mode=='foreign' then m.leading=true; m.ledHorse=43 end
        if mode=='denied' then m.rpcOverride=function(_,_,cb) cb({ok=false,code='horse_not_found'}) end end
        if mode=='movement' then m.rpcOverride=function(_,_,cb) movementReply(function(result) result.value.movementIdle=false; cb(result) end) end end
        if mode=='remote' then m.control=false end
        m.commands.BccStablesLeadProof(0,{})
        assert(not m.leadStarts and not m.leadStops and m.deleted==0)
    end
end)

test('leading proof expires via existing listener and cancellation releases before refs clear',function()
    for _,mode in ipairs({'timeout','cancel'}) do
        local m=leadFixture(); m.commands.BccStablesLeadProof(0,{})
        if mode=='timeout' then m.time=m.time+30001; assert(coroutine.resume(m.listener))
        else m.handlers['bcc-stables:call:cancel'](ID) end
        assert(m.leadStops==1 and not m.leading and m.deleted==0)
    end
end)

test('leading stop preserves another led horse or changed player incarnation',function()
    for _,mode in ipairs({'horse','player','identity'}) do
        local m=leadFixture(); m.commands.BccStablesLeadProof(0,{})
        if mode=='horse' then m.ledHorse=43 end
        if mode=='player' then m.env.PlayerPedId=function() return 100 end end
        if mode=='identity' then m.state.bccStablesObserver='different' end
        m.commands.BccStablesLeadStop(0,{})
        assert(not m.leadStops and m.deleted==0)
    end
end)

test('normal store requests exact proof release before occupancy check and RPC',function()
    local m=leadFixture(); m.commands.BccStablesLeadProof(0,{})
    m.rpcOverride=function(route,_,cb)
        assert(route=='stables.horses.call.store_current.v1' and m.leadStops==1 and not m.leading)
        cb({ok=true,value={state='empty',gameplayAvailable=false}})
    end
    m.commands.BccStablesHorseStore(0,{})
    assert(m.leadStops==1 and m.logs[#m.logs]:find('PASS',1,true))
end)

test('horse led by another actor blocks store and follow without releasing foreign leading task',function()
    local m=leadFixture(); local native=m.env.Citizen.InvokeNative
    m.env.Citizen.InvokeNative=function(hash,...)
        if hash==0xAC5045AB7F1A34FD then return true end
        return native(hash,...)
    end
    local before=#m.rpc; m.commands.BccStablesHorseStore(0,{})
    assert(#m.rpc==before and not m.leadStops)
    m.commands.BccStablesFollowProof(0,{})
    assert(not m.followTasks and not m.leadStops)
end)


test('Store waits for own asynchronous leading release before its only RPC',function()
    local m=leadFixture(); m.commands.BccStablesLeadProof(0,{})
    local native=m.env.Citizen.InvokeNative; local pending=false; local releaseAt
    m.env.Citizen.InvokeNative=function(hash,...)
        if hash==0xED27560703F37258 then pending=true; releaseAt=m.time+200 end
        if hash==0xAC5045AB7F1A34FD and pending then return m.time<releaseAt end
        return native(hash,...)
    end
    local before=#m.rpc
    m.rpcOverride=function(route,_,cb)
        assert(route=='stables.horses.call.store_current.v1' and pending and m.time>=releaseAt)
        cb({ok=true,value={state='empty',gameplayAvailable=false}})
    end
    m.commands.BccStablesHorseStore(0,{})
    assert(#m.rpc==before+1 and m.time==releaseAt and m.leadStops==1)
end)

test('Store never submits after stuck release unknown occupancy or changed generation',function()
    for _,mode in ipairs({'stuck','unknown','changed'}) do
        local m=leadFixture(); m.commands.BccStablesLeadProof(0,{})
        local native=m.env.Citizen.InvokeNative; local pending=false
        m.env.Citizen.InvokeNative=function(hash,...)
            if hash==0xED27560703F37258 then pending=true end
            if hash==0xAC5045AB7F1A34FD and pending then
                if mode=='unknown' then return nil end
                return true
            end
            return native(hash,...)
        end
        if mode=='changed' then m.onWait=function() m.state.bccStablesObserver='different' end end
        local before=#m.rpc; local started=m.time
        m.commands.BccStablesHorseStore(0,{})
        assert(#m.rpc==before and m.time-started<=1500 and m.deleted==0)
        assert(m.logs[#m.logs]:find('failed',1,true))
    end
end)

test('Store release wait stays busy and never bypasses a newly mounted rider',function()
    local m=leadFixture(); m.commands.BccStablesLeadProof(0,{})
    local native=m.env.Citizen.InvokeNative; local pending=false; local attempted=false; local began=m.time
    m.env.Citizen.InvokeNative=function(hash,...)
        if hash==0xED27560703F37258 then pending=true end
        if hash==0xAC5045AB7F1A34FD and pending then return m.time<began+100 end
        return native(hash,...)
    end
    local before=#m.rpc
    m.onWait=function()
        if not attempted then
            attempted=true; m.commands.BccStablesHorseCall(0,{})
            m.env.GetRiderOfMount=function() return 100 end
        end
    end
    m.commands.BccStablesHorseStore(0,{})
    assert(attempted and #m.rpc==before and m.deleted==0 and m.logs[#m.logs]:find('horse_occupied',1,true))
end)


local function normalLeadFixture()
    local m=leadFixture()
    m.rpcOverride=function(route,payload,cb)
        assert(route=='stables.horses.call.movement_proof.v1')
        movementReply(function(result) result.value.movementIdle=true; result.value.nativeBehavior=true; cb(result) end)
    end
    return m
end

test('normal leading toggles start release and survives past proof timeout without more RPC',function()
    local m=normalLeadFixture(); m.commands.BccStablesHorseLead(0,{})
    assert(m.leadStarts==1 and m.leading)
    local rpc=#m.rpc; m.time=m.time+31000; assert(coroutine.resume(m.listener))
    assert(m.leading and not m.leadStops and #m.rpc==rpc)
    m.commands.BccStablesLeadInspect(0,{})
    assert(m.logs[#m.logs]:find('mode=normal',1,true))
    m.commands.BccStablesHorseLead(0,{})
    assert(m.leadStops==1 and not m.leading and #m.rpc==rpc)
end)

test('normal leading requires server generation policy and accepts no identity arguments',function()
    local m=leadFixture(); m.commands.BccStablesHorseLead(0,{})
    assert(not m.leadStarts)
    local before=#m.rpc; m.commands.BccStablesHorseLead(0,{ID})
    assert(#m.rpc==before and not m.leadStarts)
end)

test('normal leading Store and cancellation reuse exact release lifecycle',function()
    for _,mode in ipairs({'store','cancel'}) do
        local m=normalLeadFixture(); m.commands.BccStablesHorseLead(0,{})
        if mode=='store' then
            m.rpcOverride=function(route,_,cb)
                assert(route=='stables.horses.call.store_current.v1' and not m.leading)
                cb({ok=true,value={state='empty',gameplayAvailable=false}})
            end
            m.commands.BccStablesHorseStore(0,{})
        else m.handlers['bcc-stables:call:cancel'](ID) end
        assert(m.leadStops==1 and not m.leading and m.deleted==0)
    end
end)

test('leading release during initial attachment waits for exact native target',function()
    local m=normalLeadFixture(); local native=m.env.Citizen.InvokeNative; local starting=false
    m.env.Citizen.InvokeNative=function(hash,...)
        if hash==0x9A7A4A54596FE09D then starting=true; return end
        return native(hash,...)
    end
    m.commands.BccStablesHorseLead(0,{})
    assert(starting and not m.leading)
    m.commands.BccStablesHorseLead(0,{})
    assert(not m.leadStops)
    m.leading=true; m.ledHorse=42; m.time=m.time+100
    assert(coroutine.resume(m.listener))
    assert(m.leadStops==1 and not m.leading)
end)


test('normal Follow receipt still executes a bounded worker and logs normal mode',function()
    local m=relayFixture(); local reply=m.rpcOverride; local began=m.time
    m.rpcOverride=function(route,payload,cb)
        if route=='stables.horses.call.whistle_claim.v1' then
            reply(route,payload,function(result) result.value.mode='follow'; result.value.normalFollow=true; result.value.followMs=1000; cb(result) end)
        else reply(route,payload,cb) end
    end
    m.handlers['bcc-stables:call:whistle']({generationId=ID,sequence=1})
    assert(m.followTasks==1 and m.followDuration==1000 and m.time-began==1000 and m.followEnds==1)
    assert(table.concat(m.logs,'\n'):find('mode=normal',1,true))
end)


test('shared native menu adapter uses identical empty request and current Store routes',function()
    local m=fixture(); local call,store=0,0
    m.rpcOverride=function(route,payload,cb)
        assert(next(payload)==nil)
        if route=='stables.horses.call.request.v1' then
            call=call+1; cb({ok=true,value={generationId=ID,state='submitting',entitySpawning=true,gameplayAvailable=false}})
        else
            assert(route=='stables.horses.call.store_current.v1'); store=store+1
            cb({ok=true,value={state='empty',gameplayAvailable=false}})
        end
    end
    assert(m.env.StablesNativeControls.Call()==true and call==1 and not m.created)
    assert(m.env.StablesNativeControls.Store()==true and store==1 and m.deleted==0)
end)

test('shared native adapter returns busy and mounted refusal without RPC or deletion',function()
    local m=fixture(); local checked=false; m.noCallback=true
    m.onWait=function()
        if not checked then
            checked=true
            local ok,reason=m.env.StablesNativeControls.Store()
            assert(ok==false and reason=='busy')
        end
    end
    assert(m.env.StablesNativeControls.Call()==true and checked and #m.rpc==1 and not m.created)
    m=companionFixture(); m.env.GetRiderOfMount=function() return 100 end
    local before=#m.rpc; local ok,reason=m.env.StablesNativeControls.Store()
    assert(ok==false and reason=='horse_occupied' and #m.rpc==before and m.deleted==0)
end)

test('shared Store adapter retains exact own-leading release before current-slot RPC',function()
    local m=normalLeadFixture(); m.commands.BccStablesHorseLead(0,{})
    m.rpcOverride=function(route,_,cb)
        assert(route=='stables.horses.call.store_current.v1' and m.leadStops==1 and not m.leading)
        cb({ok=true,value={state='empty',gameplayAvailable=false}})
    end
    assert(m.env.StablesNativeControls.Store()==true and m.leadStops==1 and m.deleted==0)
end)


test('verified movement initializes native leading lock-on once on the exact horse',function()
    local m=fixture(); m.nativeBehavior=true; m.spawn()
    assert(m.leadPromptFlags==1 and m.visible and not m.frozen and m.created==1)
    m.rpcOverride=function(_,_,cb) movementReply(cb) end
    m.commands.BccStablesMovementProof(0,{})
    assert(m.leadPromptFlags==1)
    m=fixture(); m.nativeBehavior=true; m.rejectBind=true; m.spawn()
    assert(not m.leadPromptFlags)
end)

test('Store releases exact owner native-prompt lead without diagnostic tracking',function()
    local m=leadFixture(); m.leading=true; m.ledHorse=42
    m.rpcOverride=function(route,_,cb)
        assert(route=='stables.horses.call.store_current.v1' and m.leadStops==1 and not m.leading)
        cb({ok=true,value={state='empty',gameplayAvailable=false}})
    end
    assert(m.env.StablesNativeControls.Store()==true and m.leadStops==1 and m.deleted==0)
end)

test('Store never releases an unrelated native lead or someone else leading the registered horse',function()
    local m=leadFixture(); m.leading=true; m.ledHorse=43
    m.rpcOverride=function(route,_,cb)
        assert(route=='stables.horses.call.store_current.v1')
        cb({ok=true,value={state='empty',gameplayAvailable=false}})
    end
    assert(m.env.StablesNativeControls.Store()==true and not m.leadStops and m.ledHorse==43)
    m=leadFixture(); local native=m.env.Citizen.InvokeNative
    m.env.Citizen.InvokeNative=function(hash,...)
        if hash==0xAC5045AB7F1A34FD then return true end
        return native(hash,...)
    end
    local before=#m.rpc; local accepted,reason=m.env.StablesNativeControls.Store()
    assert(accepted==false and reason=='horse_occupied' and not m.leadStops and #m.rpc==before)
end)

test('native-prompt lead generation cleanup releases exact owner lead before clearing references',function()
    local m=leadFixture(); m.leading=true; m.ledHorse=42
    m.handlers['bcc-stables:call:cancel'](ID)
    assert(m.leadStops==1 and not m.leading and m.saddleSlot==0 and m.deleted==0)
end)

test('condition diagnostic reads exact bound cores without RPC or control request',function()
    local m=fixture(); m.spawn(); local before=#m.rpc; local native=m.env.Citizen.InvokeNative
    m.env.Citizen.InvokeNative=function(hash,horse,index,result)
        if hash==0x36731AC041289BB1 then
            assert(horse==42 and result=='integer-result'); return index==0 and 100 or 73
        end
        return native(hash,horse,index,result)
    end
    m.control=false
    m.commands.BccStablesConditionInspect(0,{})
    assert(m.logs[#m.logs]:find('healthCore=100 staminaCore=73 networkControlled=false',1,true))
    assert(#m.rpc==before and not m.controlRequests and m.deleted==0)
end)

test('condition diagnostic refuses missing horse and invalid core observations',function()
    local m=fixture(); m.commands.BccStablesConditionInspect(0,{})
    assert(m.logs[#m.logs]:find('no_current_bound_horse',1,true) and #m.rpc==0)
    m.spawn()
    for _,value in ipairs({false,101,-1,1.5,'50'}) do
        m.env.Citizen.InvokeNative=function() return value end
        m.commands.BccStablesConditionInspect(0,{})
        assert(m.logs[#m.logs]:find('condition_observation_unknown',1,true))
    end
end)

test('condition diagnostic rejects identity changes during observation',function()
    local m=fixture(); m.spawn()
    m.env.Citizen.InvokeNative=function() m.state.bccStablesGeneration='changed'; return 100 end
    m.commands.BccStablesConditionInspect(0,{})
    assert(m.logs[#m.logs]:find('horse_identity_changed',1,true))
end)

local function careReportFixture()
    local m=fixture(); m.spawn(); local e=m.env
    e.NetworkGetEntityFromNetworkId=function(net) return net==71 and 42 or net==72 and 99 or 0 end
    e.NetworkGetNetworkIdFromEntity=function(entity) return entity==99 and 72 or 71 end
    e.GetPlayerFromServerId=function(source) return source==1 and 0 or -1 end
    e.GetPlayerPed=function(player) assert(player==0); return 99 end
    m.instruction={generationId=ID,observerId=OBS,netId=71,targetNetId=72,ownerSource=1,modelKey='a_c_horse_morgan_bay',sequence=1}
    m.report=function() m.handlers['bcc-stables:call:care_check'](m.instruction) end
    return m
end
test('care report observes current simulator life rider and leading without tasks or control requests',function()
    local m=careReportFixture(); local before=#m.rpc; local clears=m.clears
    m.report(); local report=m.rpc[#m.rpc]
    assert(#m.rpc==before+1 and report.route=='stables.horses.call.care_check_result.v1')
    assert(report.payload.ownerAlive and report.payload.horseAlive and report.payload.unoccupied and report.payload.notLeading)
    assert(not m.controlRequests and not m.approaches and m.clears==clears and m.deleted==0)
end)
test('care report ignores forged source missing control and changed identity',function()
    local m=careReportFixture(); local before=#m.rpc
    m.env.source=1; m.report(); assert(#m.rpc==before)
    m.env.source=65535; m.control=false; m.report(); assert(#m.rpc==before)
    m.control=true; m.env.GetRiderOfMount=function() m.state.bccStablesObserver='changed'; return 0 end
    m.report(); assert(#m.rpc==before)
end)
test('care report rejects unknown natives and reports occupied or dead facts as false',function()
    local m=careReportFixture(); local before=#m.rpc
    m.env.GetRiderOfMount=function() return nil end; m.report(); assert(#m.rpc==before)
    m=careReportFixture(); m.env.GetRiderOfMount=function() return 10 end
    m.env.IsEntityDead=function() return true end; m.report()
    local report=m.rpc[#m.rpc].payload
    assert(report.unoccupied==false and report.ownerAlive==false and report.horseAlive==false and m.deleted==0)
end)
