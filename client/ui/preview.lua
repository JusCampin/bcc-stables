-- One local preview, never the physical/networked horse. Scoped to menu session.
Stables.Preview={}
local P=Stables.Preview
local active,sequence=nil,0
local retiring={}
local function yes(v) return v==true or v==1 end
local function delete(p)
    retiring[p]=nil
    if p.entity and DoesEntityExist(p.entity) then DeleteEntity(p.entity) end
end
local function applyGender(p)
    if p.gender~='male' and p.gender~='female' then return end
    Citizen.InvokeNative(0x5653AB26C82938CF,p.entity,41611,p.gender=='female' and 1.0 or 0.0)
    Citizen.InvokeNative(0xCC8CA3E88256E58F,p.entity,false,true,true,true,false)
end
local function clean(entity)
    -- Same appearance cleanup used by the preserved horse preview.
    Citizen.InvokeNative(0x6585D955A68452A5,entity) -- ClearPedEnvDirt
    Citizen.InvokeNative(0x523C79AEEFCC4A2A,entity,10,'ALL') -- ClearPedDamageDecalByZone
    Citizen.InvokeNative(0x8FE22675A5A45817,entity) -- ClearPedBloodDamage
end
function P.SetGender(gender)
    local p=active
    if not p or (gender~='male' and gender~='female') or p.gender==gender or not DoesEntityExist(p.entity) then return end
    p.gender=gender;applyGender(p);clean(p.entity)
    CreateThread(function()
        Wait(300)
        if active==p and p.gender==gender and DoesEntityExist(p.entity)
            and GetEntityModel(p.entity)==GetHashKey(p.modelKey) then clean(p.entity) end
    end)
end
local function fade(p,target,current,finished)
    local initial=p.alpha or 255
    CreateThread(function()
        local started=GetGameTimer()
        while current() and p.entity and DoesEntityExist(p.entity) do
            local progress=math.min(1,math.max(0,GetGameTimer()-started)/180)
            p.alpha=math.floor(initial+(target-initial)*progress)
            SetEntityAlpha(p.entity,p.alpha,false)
            if progress>=1 then finished();return end
            Wait(0)
        end
    end)
end
function P.Clear(fadeOut)
    sequence=sequence+1
    -- Resource-stop/error cleanup must also remove any previews mid-transition.
    if not fadeOut then for p in pairs(retiring) do delete(p) end end
    local p=active; active=nil
    if not p then return end
    if fadeOut and p.entity and DoesEntityExist(p.entity) then
        retiring[p]=true
        fade(p,0,function() return retiring[p]==true end,function() delete(p) end)
    else delete(p) end
    if p.camera and DoesCamExist(p.camera) then
        RenderScriptCams(false,false,0,true,false,0); DestroyCam(p.camera,true)
    end
    -- Always release the radar hide owned by this preview, including swaps
    -- and close/stop cleanup. Never recapture a stale hidden native state.
    DisplayRadar(true)
end
function P.IsShowing(token,siteId,horseId,modelKey)
    local p=active
    return horseId~=nil and p~=nil and p.token==token and p.siteId==siteId
        and p.horseId==horseId and p.modelKey==modelKey
        and p.entity~=nil and DoesEntityExist(p.entity)
        and p.camera~=nil and DoesCamExist(p.camera)
end
function P.Show(token,siteId,modelKey,isCurrent,horseId,gender)
    if isCurrent(token) and P.IsShowing(token,siteId,horseId,modelKey) then P.SetGender(gender);return end
    sequence=sequence+1
    local request=sequence
    local site=StableLocations[siteId]
    if not site then return end
    local model=GetHashKey(modelKey)
    if not yes(IsModelValid(model)) then return end
    RequestModel(model)
    local deadline=GetGameTimer()+5000
    while not yes(HasModelLoaded(model)) and GetGameTimer()<deadline and isCurrent(token) and sequence==request do Wait(0) end
    if sequence~=request or not isCurrent(token) or not yes(HasModelLoaded(model)) then SetModelAsNoLongerNeeded(model); return end
    P.Clear(true)
    local cfg=Config.preview.camera
    local spawn,rig=site.horse,site.horse.preview or {}
    local overrides=rig.cameraSettings or {}
    local function setting(key,fallback) return tonumber(overrides[key]) or tonumber(cfg[key]) or fallback end
    local p={token=token,siteId=siteId,horseId=horseId,modelKey=modelKey,gender=gender,alpha=0,
        ped=PlayerPedId()}
    active=p
    p.entity=CreatePed(model,spawn.coords.x,spawn.coords.y,spawn.coords.z-1.0,rig.heading or spawn.heading,false,false,false,false)
    SetModelAsNoLongerNeeded(model)
    if not p.entity or p.entity==0 or not DoesEntityExist(p.entity) then P.Clear(); return end
    SetEntityAlpha(p.entity,0,false)
    Citizen.InvokeNative(0x283978A15512B2FE,p.entity,true)
    SetEntityInvincible(p.entity,true); SetBlockingOfNonTemporaryEvents(p.entity,true)
    Citizen.InvokeNative(0x9587913B9E772D29,p.entity,false)
    FreezeEntityPosition(p.entity,true)
    applyGender(p);clean(p.entity)
    -- Metaped variation can apply dirt after creation. Two bounded follow-ups,
    -- scoped to this exact preview, avoid a permanent cleaning/frame loop.
    CreateThread(function()
        for _,delay in ipairs({300,700}) do
            Wait(delay)
            if active~=p or not isCurrent(token) or not DoesEntityExist(p.entity)
                or GetEntityModel(p.entity)~=model then return end
            applyGender(p);clean(p.entity)
        end
    end)
    -- Menu v2 captures movement input. Leave player freeze state to its owner;
    -- RedM clients do not expose IsEntityPositionFrozen here.
    local distance=setting('distance',3.25)
    local heading=math.rad(tonumber(rig.heading) or spawn.heading or 0)
    local side=tonumber(rig.cameraSide)==-1 and -1 or 1
    local dx,dy=math.cos(heading)*side,math.sin(heading)*side
    local offset=setting('horizontalOffset',0.85)*math.min(1,distance/setting('referenceDistance',4.75))
    p.camera=CreateCam('DEFAULT_SCRIPTED_CAMERA',true)
    SetCamCoord(p.camera,spawn.coords.x+dx*distance,spawn.coords.y+dy*distance,spawn.coords.z+setting('cameraHeightOffset',0.2))
    PointCamAtCoord(p.camera,spawn.coords.x+dy*offset,spawn.coords.y-dx*offset,spawn.coords.z+setting('targetHeightOffset',0.05))
    local fov=setting('fov',math.deg(2*math.atan(setting('referenceDistance',4.75)/distance*math.tan(math.rad(setting('referenceFov',42)/2)))))
    SetCamFov(p.camera,math.max(setting('minimumFov',30),math.min(setting('maximumFov',65),fov)))
    SetCamActive(p.camera,true); RenderScriptCams(true,false,0,true,false,0); DisplayRadar(false)
    fade(p,255,function() return active==p and isCurrent(token) end,function() ResetEntityAlpha(p.entity) end)
end
function P.StopRotation()
    if active then active.rotation=nil end
end
function P.Rotate(direction)
    local p=active
    if not p or not p.entity or not DoesEntityExist(p.entity) or (direction~=-1 and direction~=1) then return end
    if p.rotation==direction then p.rotation=nil else p.rotation=direction end
    if not p.rotation or p.rotating then return end
    p.rotating=true
    CreateThread(function()
        local previous=GetGameTimer()
        while active==p and p.rotation and DoesEntityExist(p.entity) do
            Wait(0)
            if active~=p or not p.rotation or not DoesEntityExist(p.entity) then break end
            local now=GetGameTimer()
            -- Degrees per second, independent of frame rate. Bound stalls so
            -- a delayed frame does not jump through a large rotation.
            local seconds=math.max(0,math.min(100,now-previous))/1000
            previous=now
            SetEntityHeading(p.entity,(GetEntityHeading(p.entity)+p.rotation*35*seconds)%360)
        end
        p.rotating=false
    end)
end
