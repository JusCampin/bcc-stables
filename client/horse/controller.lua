-- Native presentation retained from the Horses baseline: random outfit,
-- grounding, personality, association and Lead lock-on. Server owns lifecycle.
Stables.Horse = {}
local H, C = Stables.Horse, Stables.Client
local active, busy = nil, false
local retired, order = {}, {}
local function yes(value) return value == true or value == 1 end
local function exists(entity) return entity and entity ~= 0 and yes(DoesEntityExist(entity)) end
local function same(r)
    return r and not r.identityLost and exists(r.entity) and GetEntityModel(r.entity) == r.hash
        and NetworkGetNetworkIdFromEntity(r.entity) == r.netId
        and Entity(r.entity).state.bccStablesGeneration == r.generationId
        and Entity(r.entity).state.bccStablesObserver == r.observerId
end
local function controlled(r) return same(r) and yes(NetworkHasControlOfEntity(r.entity)) end
local function usable(r) return active == r and not r.cancelled and controlled(r) end
local function retire(id)
    if retired[id] then return end
    retired[id] = true; order[#order + 1] = id
    if #order > 128 then retired[table.remove(order, 1)] = nil end
end
local function slots(player)
    return Citizen.InvokeNative(0xB48050D326E9A2F3, player, Citizen.ResultAsInteger()),
        Citizen.InvokeNative(0x46FA0AE18F4C7FA9, player, Citizen.ResultAsInteger())
end
local function releaseLead(r)
    if not same(r) or PlayerPedId() ~= r.ped then return end
    local leading = Citizen.InvokeNative(0xEFC4303DDC6E60D3, r.ped)
    local horse = Citizen.InvokeNative(0xED1F514AF4732258, r.ped, Citizen.ResultAsInteger())
    if yes(leading) and horse == r.entity then Citizen.InvokeNative(0xED27560703F37258, r.ped) end
end
local function clear(r, deleteLocal)
    r.cancelled = true
    retire(r.generationId)
    if same(r) then
        pcall(releaseLead, r)
        if r.association and PlayerId() == r.player and PlayerPedId() == r.ped then
            local saddle, mount = slots(r.player)
            if r.wroteSaddle and saddle == r.entity then Citizen.InvokeNative(0xD2CB0FB0FDCB473D, r.player, 0) end
            if r.clearActive and mount == r.entity then Citizen.InvokeNative(0x8FBF9EDB378CCB8C, r.player, 0) end
        end
        -- Server cancellation only releases local links. The observer deletes
        -- the horse. A resource stop also attempts immediate controlled cleanup.
        if deleteLocal and controlled(r) then DeleteEntity(r.entity) end
    end
    if r.hash then SetModelAsNoLongerNeeded(r.hash) end
    if HorseAppearance then HorseAppearance.resetTracking(r.entity) end
    if active == r then active = nil end
end
local function occupied(entity)
    for _, flag in ipairs({ false, true }) do
        local rider = GetRiderOfMount(entity, flag)
        assert(type(rider) == 'number' and rider >= 0 and rider % 1 == 0, 'Rider observation unavailable')
        if rider ~= 0 then return true end
    end
    local led = Citizen.InvokeNative(0xAC5045AB7F1A34FD, entity)
    assert(led == true or led == false or led == 0 or led == 1, 'Leading observation unavailable')
    return yes(led)
end
local function initialize(r)
    SetEntityVisible(r.entity, false)
    FreezeEntityPosition(r.entity, true)
    SetEntityInvincible(r.entity, true) -- Damage/death policy is not enabled in this integration slice.
    SetBlockingOfNonTemporaryEvents(r.entity, true)
    Citizen.InvokeNative(0x283978A15512B2FE, r.entity, true)
    local p = GetEntityCoords(r.entity)
    local deadline = GetGameTimer() + 5000
    while usable(r) and not yes(HasCollisionLoadedAroundEntity(r.entity)) do
        assert(GetGameTimer() < deadline, 'Collision did not load')
        RequestCollisionAtCoord(p.x, p.y, p.z); Wait(25)
    end
    assert(usable(r), 'Horse changed during initialization')
    FreezeEntityPosition(r.entity, false)
    ClearPedTasksImmediately(r.entity, false, false)
    Citizen.InvokeNative(0x9587913B9E772D29, r.entity, true)
    TaskStandStill(r.entity, 2000)
    local stableSince
    deadline = GetGameTimer() + 3000
    while usable(r) and GetGameTimer() < deadline do
        if not yes(IsEntityInAir(r.entity)) and not yes(IsPedFalling(r.entity)) then
            stableSince = stableSince or GetGameTimer()
            if GetGameTimer() - stableSince >= 750 then
                FreezeEntityPosition(r.entity, true); return
            end
        else
            stableSince = nil
        end
        Wait(50)
    end
    error('Horse did not settle on loaded ground')
end
local function ready(r, condition, tack)
    assert(usable(r) and PlayerPedId() == r.ped, 'Horse control or character changed')
    -- Outfit initialization and settling have completed before applying sex.
    if r.gender == 'male' or r.gender == 'female' then
        Citizen.InvokeNative(0x5653AB26C82938CF, r.entity, 41611, r.gender == 'female' and 1.0 or 0.0)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, r.entity, false, true, true, true, false)
    end
    if tack and next(tack) then assert(HorseAppearance.applyLoadout(r.entity,tack),'Tack appearance unavailable') end
    local saddle, mount = slots(r.player)
    assert((saddle == 0 or saddle == r.entity) and (mount == 0 or mount == r.entity),
        'Another horse owns the native association')
    r.wroteSaddle, r.clearActive = saddle == 0, saddle == 0 and mount == 0
    r.association = true
    if saddle == 0 then Citizen.InvokeNative(0xD2CB0FB0FDCB473D, r.player, r.entity) end -- SetPedAsSaddleHorseForPlayer
    Citizen.InvokeNative(0x931B241409216C1F, r.ped, r.entity, false) -- SetPedOwnsAnimal
    Citizen.InvokeNative(0xB8B6430EAD2D2437, r.entity, GetHashKey('PLAYER_HORSE')) -- SetPedPersonality
    Citizen.InvokeNative(0xE6D4E435B56D5BD0, r.player, r.entity) -- SetPlayerOwnsMount

    Citizen.InvokeNative(0x1913FE4CBF41C463, r.entity, 297, true) -- Native Lead prompt
    Citizen.InvokeNative(0x1913FE4CBF41C463, r.entity, 471, Config.horseBehavior.disableKick == true) -- DisableHorseKick
    Citizen.InvokeNative(0xE2487779957FE897, r.entity, 528) -- SetTransportUsageFlags
    if Config.feeding and Config.feeding.enabled then
        -- Original Horses hides engine feeding; food is used through Inventory.
        Citizen.InvokeNative(0xA3DB37EDF9A74635, r.player, r.entity, 50, 1, true)
    end
    if Config.brushing and Config.brushing.enabled then
        Citizen.InvokeNative(0xA3DB37EDF9A74635, r.player, r.entity, 49, 1, true)
    end
    if condition then
        for index, key in ipairs({ 'healthCore', 'staminaCore' }) do
            local value = condition[key]
            assert(type(value) == 'number' and value >= 0 and value <= 100 and value % 1 == 0, 'Invalid saved condition')
            Citizen.InvokeNative(0xC6258F41D86676E0, r.entity, index - 1, value)
        end
        Entity(r.entity).state:set('bccStablesCoreRevision',condition.revision,true)
    end
    ClearPedTasksImmediately(r.entity, false, false)
    SetBlockingOfNonTemporaryEvents(r.entity, false)
    FreezeEntityPosition(r.entity, false)
    SetEntityVisible(r.entity, true)
    r.bound = true
    C.Message('horse ready; riding and native leading enabled.')
    if condition and Config.feeding and Config.feeding.enabled then
        C.Message(C.Text('menu_feedSaved', condition.healthCore, condition.staminaCore, condition.revision))
    end
end
local function validSpec(p)
    if type(p) ~= 'table' or not C.Uuid(p.generationId) or not C.Uuid(p.observerId) or not C.Uuid(p.horseId)
        or type(p.modelKey) ~= 'string' or #p.modelKey > 100 or not p.modelKey:match('^a_c_horse_[a-z0-9_]+$')
        or type(p.position) ~= 'table' then
        return false
    end
    for _, key in ipairs({ 'x', 'y', 'z', 'heading' }) do
        local value = p.position[key]
        if type(value) ~= 'number' or value ~= value or math.abs(value) > 1000000 then return false end
    end
    return true
end
RegisterNetEvent('bcc-stables:call:create', function(spec)
    if source ~= 65535 or not validSpec(spec) or active or retired[spec.generationId] then return end
    local r = {
        generationId = spec.generationId,
        observerId = spec.observerId,
        horseId = spec.horseId,
        modelKey = spec.modelKey,
        gender = spec.gender,
        player = PlayerId(),
        ped = PlayerPedId()
    }
    active = r
    CreateThread(function()
        local ok, failure = pcall(function()
            local loaded = exports['feather-toolkit']:LoadModel(r.modelKey, 5000)
            assert(
            type(loaded) == 'table' and loaded.ok and type(loaded.value) == 'table' and type(loaded.value.hash) ==
            'number', 'Horse model unavailable')
            r.hash = loaded.value.hash
            if active ~= r or r.cancelled or PlayerPedId() ~= r.ped then
                SetModelAsNoLongerNeeded(r.hash); return
            end
            -- Reject delayed/replayed creation instructions after resource restart
            -- before CreatePed. This permission is single-use and server-scoped.
            local accepted = C.Rpc('accept', { generationId = r.generationId, observerId = r.observerId })
            assert(accepted.ok and type(accepted.value) == 'table' and accepted.value.generationId == r.generationId,
                'Spawn instruction expired')
            if active ~= r or r.cancelled or PlayerPedId() ~= r.ped then return end
            local p = spec.position
            r.entity = CreatePed(r.hash, p.x, p.y, p.z, p.heading, true, false, false, false)
            assert(exists(r.entity), 'Horse creation failed')
            SetEntityAsMissionEntity(r.entity, true, true)
            SetEntityVisible(r.entity, false); FreezeEntityPosition(r.entity, true)
            Entity(r.entity).state:set('bccStablesGeneration', r.generationId, true)
            Entity(r.entity).state:set('bccStablesObserver', r.observerId, true)
            if not yes(NetworkGetEntityIsNetworked(r.entity)) then NetworkRegisterEntityAsNetworked(r.entity) end
            local deadline = GetGameTimer() + 5000
            repeat
                if r.cancelled or active ~= r then return end
                r.netId = NetworkGetNetworkIdFromEntity(r.entity)
                if r.netId and r.netId > 0 then break end
                assert(GetGameTimer() < deadline, 'Horse network identity unavailable'); Wait(25)
            until false
            initialize(r)
            local bound = C.Rpc('bind', { generationId = r.generationId, netId = r.netId })
            assert(bound.ok and type(bound.value) == 'table' and bound.value.state == 'active'
                and bound.value.generationId == r.generationId and bound.value.netId == r.netId
                and bound.value.horseId == r.horseId, 'Horse binding refused: ' .. tostring(bound.code))
            if active ~= r or r.cancelled then return end
            ready(r, bound.value.condition, bound.value.tack)
        end)
        if r.hash then SetModelAsNoLongerNeeded(r.hash) end
        if not ok then
            C.Message('horse request failed: ' .. tostring(failure) .. '; use BccStablesHorseStore to request cleanup.')
            -- Retain the exact local identity so server cancellation/stop can
            -- undo our native links. Never create a replacement after an error.
        end
    end)
end)
RegisterNetEvent('bcc-stables:call:cancel', function(id)
    if source ~= 65535 or not C.Uuid(id) then return end
    retire(id)
    if active and active.generationId == id then clear(active, false) end
end)
RegisterNetEvent('bcc-stables:call:store_check', function(p)
    if source ~= 65535 or type(p) ~= 'table' or not C.Uuid(p.generationId) or not C.Uuid(p.observerId)
        or type(p.netId) ~= 'number' or p.netId < 1 or p.netId % 1 ~= 0 or type(p.sequence) ~= 'number'
        or p.sequence < 1 or p.sequence % 1 ~= 0 or type(p.modelKey) ~= 'string' then
        return
    end
    CreateThread(function()
        local ok, failure = pcall(function()
            local entity = NetworkGetEntityFromNetworkId(p.netId)
            local function valid()
                return exists(entity) and NetworkGetNetworkIdFromEntity(entity) == p.netId
                    and GetEntityModel(entity) == GetHashKey(p.modelKey) and yes(NetworkHasControlOfEntity(entity))
                    and Entity(entity).state.bccStablesGeneration == p.generationId
                    and Entity(entity).state.bccStablesObserver == p.observerId
            end
            if not valid() then return end
            local reply={generationId=p.generationId,sequence=p.sequence}
            if p.care==true then
                if type(p.targetNet)~='number' or p.targetNet<1 or p.targetNet%1~=0 then return end
                local owner=NetworkGetEntityFromNetworkId(p.targetNet)
                if not exists(owner) or NetworkGetNetworkIdFromEntity(owner)~=p.targetNet then return end
                reply.ownerAlive=not yes(IsEntityDead(owner)) and not yes(IsPedDeadOrDying(owner,true))
                reply.horseAlive=not yes(IsEntityDead(entity)) and not yes(IsPedDeadOrDying(entity,true))
                local led=Citizen.InvokeNative(0xAC5045AB7F1A34FD,entity)
                assert(led==true or led==false or led==0 or led==1,'Leading observation unavailable')
                reply.occupied=yes(led) or (yes(IsPedOnMount(owner)) and (p.allowMounted==false or GetMount(owner)~=entity))
                for _,flag in ipairs({false,true}) do
                    local rider=GetRiderOfMount(entity,flag)
                    assert(type(rider)=='number' and rider>=0 and rider%1==0,'Rider observation unavailable')
                    if rider~=0 and rider~=owner then reply.occupied=true end
                end
            else reply.occupied=occupied(entity) end
            if p.condition==true then
                reply.healthCore=Citizen.InvokeNative(0x36731AC041289BB1,entity,0,Citizen.ResultAsInteger())
                reply.staminaCore=Citizen.InvokeNative(0x36731AC041289BB1,entity,1,Citizen.ResultAsInteger())
                reply.appliedRevision=tonumber(Entity(entity).state.bccStablesCoreRevision) or 0
            end
            if valid() then C.Rpc('store_check_result',reply) end
        end)
        if not ok then C.Message('occupancy could not be verified: ' .. tostring(failure)) end
    end)
end)
local function action(name)
    if busy then return false end
    busy = true
    CreateThread(function()
        local ok, reply = pcall(function()
            if name == 'store_current' and active then
                releaseLead(active)
                -- Let the native detach before the current simulator reads it.
                Wait(250)
            end
            return C.Rpc(name, {})
        end)
        busy = false
        if ok and type(reply) == 'table' and reply.code == 'cleanup_pending' then
            C.Message(name == 'store_current' and 'store pending; waiting for confirmed disappearance.'
                or 'previous horse cleanup pending; wait for disappearance before calling again.')
        elseif not ok or type(reply) ~= 'table' or not reply.ok then
            C.Message('horse action refused: ' .. tostring(type(reply) == 'table' and reply.code or 'transport_error'))
        elseif type(reply.value) == 'table' then
            C.Message(reply.value.relocated and 'horse replacement requested.' or
            'horse ' .. tostring(reply.value.state) .. '.')
        end
    end)
    return true
end
function H.Call() return action('request') end

function H.Store() return action('store_current') end

function H.GetActive()
    local r = active
    if not r or not r.bound or not same(r) then return nil end
    return { id = r.horseId, entity = r.entity, netId = r.netId, generationId = r.generationId, observerId = r
    .observerId, modelKey = r.modelKey }
end

-- Streaming can remove the local entity while the server's bound call remains
-- active. Movement intent must still go to that call's current simulator.
function H.HasBoundHorse()
    return active ~= nil and active.bound == true and not active.cancelled
        and PlayerPedId() == active.ped and PlayerId() == active.player
end

function H.Lead()
    local r = active
    if busy or not r or not r.bound or not usable(r) or PlayerPedId() ~= r.ped then return false end
    local leading = Citizen.InvokeNative(0xEFC4303DDC6E60D3, r.ped)
    local horse = Citizen.InvokeNative(0xED1F514AF4732258, r.ped, Citizen.ResultAsInteger())
    if yes(leading) and horse == r.entity then
        releaseLead(r); return true
    end
    if yes(leading) or yes(IsPedOnMount(r.ped)) or occupied(r.entity)
        or #(GetEntityCoords(r.ped) - GetEntityCoords(r.entity)) > 2.5 then
        return false
    end
    Citizen.InvokeNative(0x9A7A4A54596FE09D, r.ped, r.entity)
    return true
end

for _, entry in ipairs({ { 'BccStablesHorseCall', H.Call }, { 'BccStablesHorseStore', H.Store }, { 'BccStablesHorseLead', H.Lead } }) do
    RegisterCommand(entry[1], function(_, args) if #args == 0 then entry[2]() end end, false)
end
exports('GetActiveHorse', H.GetActive)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() or resource == 'feather-core' or resource == 'feather-toolkit' then
        if active then clear(active, true) end
    end
end)
