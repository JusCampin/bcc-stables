-- Native creation only follows a server dispatch instruction for a durable generation.
local active,busy
local lastRetired
local holdNextBind=false
local retired,retiredOrder={},{}
local function Uuid(v) return type(v)=='string' and v:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$')~=nil end
local function Rpc(name,payload)
    local reply,done
    exports['feather-core']:CallRPC('stables.horses.call.'..name..'.v1',payload,function(...)
        if not done then reply,done=table.pack(...),true end
    end,nil,15000)
    local started=GetGameTimer()
    while not done and GetGameTimer()-started<16000 do Wait(25) end
    done=true
    if not reply then return {ok=false,code='timeout'} end
    local result,failure=reply[1],reply[2]
    return type(result)=='table' and result or {ok=false,code=type(failure)=='table' and failure.code or 'invalid_result'}
end
local function Yes(value)
    return value == true or value == 1
end

local function Exists(entity)
    return entity ~= nil and entity ~= 0 and Yes(DoesEntityExist(entity))
end

local function StillControlled(record)
    return not record.cancelled and not record.identityLost and Exists(record.entity)
        and Entity(record.entity).state.bccStablesGeneration==record.generationId
        and Entity(record.entity).state.bccStablesObserver==record.observerId
        and GetEntityModel(record.entity) == record.hash
        and NetworkGetNetworkIdFromEntity(record.entity) == record.netId
        and Yes(NetworkHasControlOfEntity(record.entity))
end

local function Initialize(record)
    local horse = record.entity
    SetEntityVisible(horse, false)
    FreezeEntityPosition(horse, true)
    SetEntityInvincible(horse, true)
    SetBlockingOfNonTemporaryEvents(horse, true)
    Citizen.InvokeNative(0x283978A15512B2FE, horse, true) -- Random outfit variation.

    local position = GetEntityCoords(horse)
    local started, collision = GetGameTimer(), false
    while StillControlled(record) and GetGameTimer() - started < 5000 do
        RequestCollisionAtCoord(position.x, position.y, position.z)
        collision = Yes(HasCollisionLoadedAroundEntity(horse))
        if collision then break end
        Wait(25)
    end
    if not collision or not StillControlled(record) then return false, collision, false end

    FreezeEntityPosition(horse, false)
    ClearPedTasksImmediately(horse, false, false)
    -- Same RDR3 grounding native used by BCC Horses and Character arrival.
    Citizen.InvokeNative(0x9587913B9E772D29, horse, true)
    TaskStandStill(horse, 2000)

    -- Allow the physics/animation pose to settle before freezing the fixture.
    -- A freeze immediately after creation can retain a visible mid-air pose.
    started = GetGameTimer()
    local stableSince
    while StillControlled(record) and GetGameTimer() - started < 3000 do
        if not Yes(IsEntityInAir(horse)) and not Yes(IsPedFalling(horse)) then
            stableSince = stableSince or GetGameTimer()
            if GetGameTimer() - stableSince >= 750 then
                FreezeEntityPosition(horse, true)
                return true, true, true
            end
        else
            stableSince = nil
        end
        Wait(50)
    end
    -- Do not re-freeze/reveal an unsettled horse as a successful fixture.
    return false, true, false
end


local function Release(r,deleteLocally)
    r.cancelled=true
    if type(r.netId)=='number' and r.netId%1==0 and r.netId>0 then
        lastRetired={generationId=r.generationId,netId=r.netId}
    end
    if not retired[r.generationId] then
        retired[r.generationId]=true; retiredOrder[#retiredOrder+1]=r.generationId
        if #retiredOrder>64 then retired[table.remove(retiredOrder,1)]=nil end
    end
    if deleteLocally~=false and r.createdLocally and not r.identityLost and Exists(r.entity) and GetEntityModel(r.entity)==r.hash
        and (r.netId==nil or NetworkGetNetworkIdFromEntity(r.entity)==r.netId)
        and (not r.marked or (Entity(r.entity).state.bccStablesGeneration==r.generationId
            and Entity(r.entity).state.bccStablesObserver==r.observerId))
        and Yes(NetworkHasControlOfEntity(r.entity)) then DeleteEntity(r.entity) end
    if r.hash then SetModelAsNoLongerNeeded(r.hash) end
    if active==r then active=nil end
end
local function Spec(p)
    if type(p)~='table' or not Uuid(p.generationId) or not Uuid(p.observerId)
        or type(p.modelKey)~='string' or #p.modelKey>100 or not p.modelKey:match('^a_c_horse_[a-z0-9_]+$')
        or type(p.position)~='table' then return false end
    for _,k in ipairs({'x','y','z','heading'}) do
        local v=p.position[k]; if type(v)~='number' or v~=v or math.abs(v)>1000000 then return false end
    end
    return true
end
RegisterNetEvent('bcc-stables:call:cancel',function(id)
    if source==65535 and active and active.generationId==id then Release(active,false) end
end)
RegisterNetEvent('bcc-stables:call:create',function(spec)
    if source~=65535 or not Spec(spec) or active or retired[spec.generationId] then return end
    local r={generationId=spec.generationId,observerId=spec.observerId,holdBind=holdNextBind}; active=r
    holdNextBind=false
    CreateThread(function()
        local ok,failure=pcall(function()
            if GetResourceState('feather-toolkit')~='started' then error('feather-toolkit unavailable') end
            local caps=exports['feather-toolkit']:GetCapabilities()
            assert(type(caps)=='table' and caps.ok and type(caps.value)=='table' and caps.value.contract==1
                and type(caps.value.features)=='table' and caps.value.features.models==1,'Toolkit model contract unavailable')
            local loaded=exports['feather-toolkit']:LoadModel(spec.modelKey,5000)
            assert(type(loaded)=='table' and loaded.ok and type(loaded.value)=='table' and type(loaded.value.hash)=='number','Model load failed')
            r.hash=loaded.value.hash
            if r.cancelled then SetModelAsNoLongerNeeded(r.hash); return end
            local p=spec.position
            r.entity=CreatePed(r.hash,p.x+0.0,p.y+0.0,p.z+0.0,p.heading+0.0,true,true,false,false)
            assert(Exists(r.entity),'Client CreatePed failed')
            r.createdLocally=true
            SetEntityVisible(r.entity,false); FreezeEntityPosition(r.entity,true)
            SetEntityAsMissionEntity(r.entity,true,true)
            Entity(r.entity).state:set('bccStablesGeneration',spec.generationId,true)
            Entity(r.entity).state:set('bccStablesObserver',spec.observerId,true)
            r.marked=true
            if not Yes(NetworkGetEntityIsNetworked(r.entity)) then NetworkRegisterEntityAsNetworked(r.entity) end
            local started=GetGameTimer()
            repeat
                if r.cancelled then return end
                local id=NetworkGetNetworkIdFromEntity(r.entity)
                if id and id>0 then r.netId=id; break end
                assert(GetGameTimer()-started<5000,'Network ID unavailable'); Wait(25)
            until false
            local initialized,collision,settled=Initialize(r)
            assert(initialized and collision and settled,'Horse did not settle on loaded ground')
            if r.cancelled then return end
            if r.holdBind then
                print('[bcc-stables] native binding paused for 10 seconds; log out to character selection now.')
                local paused=GetGameTimer()
                while not r.cancelled and GetGameTimer()-paused<10000 do Wait(50) end
                if r.cancelled then
                    print('[bcc-stables] paused native spawn cancelled; no bind sent.')
                    return
                end
                assert(StillControlled(r),'Paused horse identity/control changed before binding')
            end
            local bound=Rpc('bind',{generationId=r.generationId,netId=r.netId})
            assert(bound.ok and type(bound.value)=='table' and bound.value.state=='active'
                and bound.value.generationId==r.generationId and bound.value.netId==r.netId,
                'Binding rejected: '..tostring(bound.code))
            if r.cancelled then return end
            assert(StillControlled(r),'Horse control lost before reveal')
            r.bound=true
            SetEntityVisible(r.entity,true)
            -- First controlled lifecycle gate retains the accepted proof's frozen,
            -- invincible pose. Riding/following/tack are separate gameplay work.
            print(('[bcc-stables] native horse bound; generationId=%s netId=%s initialized=true collisionLoaded=true settled=true'):format(r.generationId,r.netId))
        end)
        if not ok then
            print('[bcc-stables] native horse failed: '..tostring(failure)..'; inspect the call generation before retrying.')
            Release(r)
            pcall(Rpc,'store',{generationId=r.generationId})
        end
    end)
end)
AddEventHandler('entityRemoved',function(entity)
    if active and active.entity==entity then active.identityLost=true end
end)
AddEventHandler('onResourceStop',function(resource)
    if resource==GetCurrentResourceName() and active then Release(active) end
end)
local function Command(name,route)
    RegisterCommand(name,function(_,args)
        if busy then return end
        args=args or {}
        local current=route=='store' and #args==0
        if not current and (#args~=1 or not Uuid(args[1])) then print('[bcc-stables] '..name..' '..(route=='store' and '[generationId]' or '<generationId>')); return end
        busy=true
        CreateThread(function()
            local ok,result=pcall(Rpc,current and 'store_current' or route,current and {} or {generationId=args[1]:lower()})
            local v=ok and result.value
            local valid=type(v)=='table' and v.gameplayAvailable==false
                and ((current and ((v.state=='empty' and v.generationId==nil) or (v.state=='released' and Uuid(v.generationId))))
                    or (not current and v.generationId==args[1]:lower() and v.state==(route=='dispatch' and 'submitting' or 'released')))
                and (route~='dispatch' or v.entitySpawning==true)
            if ok and result.ok==true and valid then
                print(('[bcc-stables] %s PASS; generationId=%s state=%s'):format(name,tostring(result.value.generationId),tostring(result.value.state)))
            elseif route=='store' and ok and result.ok==false and result.code=='cleanup_pending' then
                print('[bcc-stables] '..name..' pending; deletion requested, waiting for disappearance.')
            else
                print('[bcc-stables] '..name..' failed: '..tostring(ok and (result.code or 'invalid_result') or result))
            end
            busy=false
        end)
    end,false)
end
Command('BccStablesCallDispatch','dispatch')
Command('BccStablesHorseStore','store')

RegisterCommand('BccStablesHorseCall',function(_,args)
    args=args or {}
    if #args~=0 then print('[bcc-stables] BccStablesHorseCall'); return end
    if busy then return end
    busy=true
    CreateThread(function()
        local ok,result=pcall(Rpc,'request',{})
        local v=ok and type(result)=='table' and result.value
        if ok and result.ok==true and type(v)=='table' and Uuid(v.generationId)
            and v.state=='submitting' and v.entitySpawning==true and v.gameplayAvailable==false then
            print('[bcc-stables] call requested; generationId='..v.generationId..'; waiting for native binding.')
        else
            print('[bcc-stables] call failed: '..tostring(ok and type(result)=='table' and (result.code or 'invalid_result') or result)
                ..'; run BccStablesCallInspect before retrying.')
        end
        busy=false
    end)
end,false)



-- One-shot local acceptance aid; cannot authorize a spawn or alter server leases.
RegisterCommand('BccStablesCallHold',function(_,args)
    args=args or {}
    if #args==1 and args[1]=='cancel' then
        holdNextBind=false
        print('[bcc-stables] next native-bind pause disarmed.')
        return
    end
    if #args~=0 then print('[bcc-stables] BccStablesCallHold [cancel]'); return end
    if active then print('[bcc-stables] store the active horse before arming a native-bind pause.'); return end
    holdNextBind=true
    print('[bcc-stables] next native spawn will pause before binding for 10 seconds.')
end,false)


-- Replay only this client's recorded identity. Never consumes a success as a
-- creation instruction, and never accepts caller-supplied IDs or model data.
RegisterCommand('BccStablesCallReplay',function(_,args)
    args=args or {}
    if busy then return end
    local mode=#args==1 and args[1]
    if mode~='duplicate' and mode~='stale' then
        print('[bcc-stables] BccStablesCallReplay duplicate|stale'); return
    end
    local record=mode=='duplicate' and active or mode=='stale' and lastRetired
    if not record or not record.netId or (mode=='duplicate' and (not record.bound or record.cancelled)) then
        print('[bcc-stables] replay requires duplicate (active bound horse) or stale (previously retired native identity).')
        return
    end
    local payload={generationId=record.generationId,netId=record.netId}
    local expected=mode=='duplicate' and 'binding_conflict' or 'stale_call'
    busy=true
    CreateThread(function()
        Wait(2100) -- Keep replay outside the ordinary bind rate window.
        local called,reply=pcall(Rpc,'bind',payload)
        local outcome=called and type(reply)=='table' and (reply.ok==true and 'accepted' or reply.code) or 'transport_error'
        local passed=called and type(reply)=='table' and reply.ok==false and outcome==expected
        print(('[bcc-stables] bind replay %s %s; generationId=%s expected=%s outcome=%s'):format(
            mode,passed and 'PASS' or 'FAIL',payload.generationId,expected,tostring(outcome)))
        busy=false
    end)
end,false)
