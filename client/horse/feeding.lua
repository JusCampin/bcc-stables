-- Inventory starts care. No Feed prompt, frame reader or client item selection.
local H,C=Stables.Horse,Stables.Client
local animation
local revisions,revisionOrder={},{}
local function yes(v) return v==true or v==1 end
local function alive(e) return e and e~=0 and yes(DoesEntityExist(e)) and not yes(IsEntityDead(e)) end
local function eligible(r,ped)
    local now=H.GetActive()
    if not now or now.generationId~=r.generationId or now.entity~=r.entity or ped~=PlayerPedId()
        or not alive(ped) or not alive(r.entity) or IsNuiFocused() then return false end
    if yes(IsPedOnMount(ped)) and GetMount(ped)~=r.entity then return false end
    for _,flag in ipairs({false,true}) do
        local rider=GetRiderOfMount(r.entity,flag)
        if type(rider)~='number' or (rider~=0 and rider~=ped) then return false end
    end
    local led=Citizen.InvokeNative(0xAC5045AB7F1A34FD,r.entity)
    if led~=false and led~=0 then return false end
    local a,b=GetEntityCoords(ped),GetEntityCoords(r.entity)
    return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2<=6.25
end
local function message(key,...)
    local text=C.Text('menu_'..key,...)
    C.Message(text)
    if GetResourceState('feather-notify')=='started' then
        pcall(function() exports['feather-notify']:ShowNotification({style='right',message=text,duration=4000}) end)
    end
end
RegisterNetEvent('bcc-stables:feed:result',function(v)
    if source~=65535 or type(v)~='table' or type(v.ok)~='boolean' then return end
    if v.ok and type(v.value)=='table' and (v.value.state=='applied' or v.value.state=='cancelled') then
        local brush=v.value.action=='brush'
        message(v.value.state=='applied' and (brush and 'brushApplied' or 'feedApplied') or (brush and 'brushCancelled' or 'feedCancelled'))
        if brush and v.value.broken then message('brushBroken')
        elseif brush and type(v.value.remainingDurability)=='number' then
            message('brushDurability',v.value.remainingDurability,v.value.maximumDurability)
        end
        local c=v.value.condition
        if v.value.state=='applied' and c then C.Message(C.Text('menu_feedSaved',c.healthCore,c.staminaCore,c.revision)) end
    else
        local keys={care_full='feedFull',care_food_missing='feedMissing',care_uninitialized='feedUninitialized',
            care_ineligible='feedBeside',care_disabled='feedDisabled',care_busy='feedBusy',care_stale='feedCancelled',
            care_cancelled='feedCancelled',care_not_ready='feedNotReady',care_moving='feedMoving',
            care_observation_unknown='feedObservation',care_life='feedLife',care_occupied='feedOccupied'}
        if v.code=='care_too_far' and type(v.distance)=='number' and v.distance>=0 and v.distance<1000000 then
            message('feedTooFar',v.distance)
        elseif v.action=='brush' and v.code=='care_occupied' then message('brushDismount')
        elseif v.action=='brush' and v.code=='care_food_missing' then message('brushUnavailable')
        elseif v.action=='brush' and (v.code=='care_cancelled' or v.code=='care_stale') then message('brushCancelled')
        else message(keys[v.code] or 'feedPending') end
    end
end)
RegisterNetEvent('bcc-stables:feed:animate',function(p)
    if source~=65535 or animation or type(p)~='table' or not C.Uuid(p.operationId)
        or not C.Uuid(p.generationId) or type(p.netId)~='number' then return end
    local a={id=p.operationId,ped=PlayerPedId()};animation=a
    CreateThread(function()
        -- Allow Inventory's normal close event to release NUI before care starts.
        local deadline=GetGameTimer()+2000
        while animation==a and IsNuiFocused() and GetGameTimer()<deadline do Wait(25) end
        local r,ped=H.GetActive(),a.ped
        local started=animation==a and r and r.generationId==p.generationId and r.netId==p.netId and eligible(r,ped) or false
        local ok=pcall(function()
            if started then
                Citizen.InvokeNative(0xCD181A959CFDD7F4,ped,r.entity,GetHashKey(p.action=='brush' and 'Interaction_Brush' or 'Interaction_Food'),
                    GetHashKey(p.action=='brush' and 'p_brushHorse02x' or 's_horsnack_haycube01x'),true)
            end
        end)
        started=started and ok
        C.Rpc('feed',{operationId=p.operationId,started=started})
        if started then
            message(p.action=='brush' and 'brushStay' or 'feedStay')
            deadline=GetGameTimer()+5000
            while GetGameTimer()<deadline do
                Wait(100)
                if animation~=a or not eligible(r,ped) then
                    C.Rpc('feed',{operationId=p.operationId,cancel=true})
                    if ped==PlayerPedId() and alive(ped) then ClearPedTasks(ped) end
                    break
                end
            end
        end
        if animation==a then animation=nil end
    end)
end)
RegisterNetEvent('bcc-stables:feed:condition', function(p)
    if source ~= 65535 or type(p) ~= 'table' or not C.Uuid(p.generationId) or not C.Uuid(p.observerId)
        or type(p.modelKey) ~= 'string' or type(p.netId) ~= 'number' or type(p.condition) ~= 'table' then
        return
    end
    local c = p.condition
    if type(c.revision) ~= 'number' or c.revision % 1 ~= 0 or c.revision < 1 or c.revision > 9007199254740991 then return end
    for _, k in ipairs({ 'healthCore', 'staminaCore' }) do
        if type(c[k]) ~= 'number' or c[k] % 1 ~= 0 or c[k] < 0 or c[k] > 100 then return end
    end
    local e = NetworkGetEntityFromNetworkId(p.netId)
    if not alive(e) or NetworkGetNetworkIdFromEntity(e) ~= p.netId or not yes(NetworkHasControlOfEntity(e))
        or GetEntityModel(e) ~= GetHashKey(p.modelKey) or Entity(e).state.bccStablesGeneration ~= p.generationId
        or Entity(e).state.bccStablesObserver ~= p.observerId or (revisions[p.generationId] or 0) >= c.revision then
        return
    end
    if not revisions[p.generationId] then
        revisionOrder[#revisionOrder + 1] = p.generationId
        if #revisionOrder > 128 then revisions[table.remove(revisionOrder, 1)] = nil end
    end
    revisions[p.generationId] = c.revision
    Citizen.InvokeNative(0xC6258F41D86676E0, e, 0, c.healthCore)
    Citizen.InvokeNative(0xC6258F41D86676E0, e, 1, c.staminaCore)
    Entity(e).state:set('bccStablesCoreRevision',c.revision,true)
    if p.action=='brush' then
        Citizen.InvokeNative(0x6585D955A68452A5,e,0.0)
        Citizen.InvokeNative(0x523C79AEEFCC4A2A,e,10,'ALL')
        Citizen.InvokeNative(0x8FE22675A5A45817,e)
    end
end)
AddEventHandler('onResourceStop',function(name)
    if name==GetCurrentResourceName() then
        local a=animation;animation=nil
        if a and a.ped==PlayerPedId() and alive(a.ped) then ClearPedTasks(a.ped) end
    end
end)
