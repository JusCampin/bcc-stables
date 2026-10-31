-- Original animations, exact-generation simulator execution. Input is read by
-- the existing nearby target-menu worker; inactive care creates no frame loop.
Stables.HorseWorldCare = {}
local W, C, H = Stables.HorseWorldCare, Stables.Client, Stables.Horse
local active, seen, order = {}, {}, {}
local ownerState
local deferredMount, shuttingDown = false, false

local function remember(p)
    if not seen[p.generationId] then order[#order + 1] = p.generationId end
    seen[p.generationId] = math.max(seen[p.generationId] or 0, p.sequence)
    if #order > 128 then seen[table.remove(order, 1)] = nil end
end

local animations = {
    drink = { 'amb_creature_mammal@world_horse_drink_ground', 'idle', 'idle_a' },
    rest = { 'amb_creature_mammal@world_horse_resting', 'idle', 'idle_a' },
    sleep = { 'amb_creature_mammal@world_horse_sleeping', 'base', 'base' },
    wallow = { 'amb_creature_mammal@world_horse_wallow_shake', 'idle', 'idle_a' },
}

local function yes(v) return v == true or v == 1 end

local function alive(e) return e and e ~= 0 and yes(DoesEntityExist(e)) and not yes(IsEntityDead(e)) end

local function entity(p)
    if type(p) ~= 'table' or not C.Uuid(p.generationId) or not C.Uuid(p.observerId) or not animations[p.action]
        or type(p.sequence) ~= 'number' or p.sequence % 1 ~= 0 or p.sequence < 1 or type(p.netId) ~= 'number' or type(p.modelKey) ~= 'string' then
        return nil
    end
    local e = NetworkGetEntityFromNetworkId(p.netId)
    if not alive(e) or NetworkGetNetworkIdFromEntity(e) ~= p.netId or GetEntityModel(e) ~= GetHashKey(p.modelKey)
        or Entity(e).state.bccStablesGeneration ~= p.generationId or Entity(e).state.bccStablesObserver ~= p.observerId then
        return nil
    end
    return e
end

local function eligible(t)
    local e = entity(t.p); local ped = NetworkGetEntityFromNetworkId(t.p.targetNet)
    return e == t.entity and alive(ped) and NetworkGetNetworkIdFromEntity(ped) == t.p.targetNet
        and yes(NetworkHasControlOfEntity(e)) and not yes(IsPedOnMount(ped))
        and GetRiderOfMount(e, false) == 0 and GetRiderOfMount(e, true) == 0
        and not yes(Citizen.InvokeNative(0xAC5045AB7F1A34FD, e))
        and (t.p.action ~= 'drink' or t.waterStarted)
end

local function targeting(t, enabled)
    if entity(t.p) ~= t.entity or not yes(NetworkHasControlOfEntity(t.entity)) then return end
    Citizen.InvokeNative(0x1913FE4CBF41C463, t.entity, 297, enabled)
    Citizen.InvokeNative(0x1913FE4CBF41C463, t.entity, 301, not enabled)
    Citizen.InvokeNative(0x1913FE4CBF41C463, t.entity, 412, not enabled)
end

local function controlled(t)
    return entity(t.p) == t.entity and yes(NetworkHasControlOfEntity(t.entity))
        and GetRiderOfMount(t.entity, false) == 0 and GetRiderOfMount(t.entity, true) == 0
end

local function load(t, dict, exiting)
    RequestAnimDict(dict); local deadline = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline and (not t.cancelled or exiting) do Wait(25) end
    if (t.cancelled and not exiting) or (exiting and active[t.p.generationId] ~= t) or not HasAnimDictLoaded(dict) then
        RemoveAnimDict(dict); return false
    end
    return exiting and controlled(t) or eligible(t)
end

local function play(t, dict, name, loop, exiting)
    if not load(t, dict, exiting) then return nil end
    if loop then
        TaskPlayAnim(t.entity, dict, name, 1.0, 1.0, -1, 3, 1.0, false, false, false)
    else
        local a, b = GetEntityCoords(t.entity), GetEntityRotation(t.entity, 2)
        -- AF_HOLD_LAST_FRAME prevents an idle/locomotion beat before the next
        -- clip, or a second return-to-idle before exit cleanup.
        TaskPlayAnimAdvanced(t.entity, dict, name, a.x, a.y, a.z, b.x, b.y, b.z, 1.0, 1.0, -1, 2, 0.0, 0, 0)
    end
    local seconds = GetAnimDuration(dict, name)
    if type(seconds) ~= 'number' or seconds <= 0 or seconds ~= seconds then seconds = 2.5 end
    local duration = math.max(1, math.floor(seconds * 1000))
    RemoveAnimDict(dict); return duration
end

local function exitConfirmed(p, e)
    if entity(p) == e and yes(NetworkHasControlOfEntity(e)) then
        CreateThread(function() C.Rpc('world_exit', { generationId = p.generationId, sequence = p.sequence }) end)
    end
end

function W.CancelForInjury(id)
    local t=active[id]
    if t then t.cancelled=true;t.stopping=true;targeting(t,true);active[id]=nil end
end
local function stop(t)
    if t.stopping then return end; t.stopping = true
    t.cancelled = true
    RemoveAnimDict(animations[t.p.action][1] .. '@' .. animations[t.p.action][2])
    if not controlled(t) or not t.entered then
        targeting(t, true); if active[t.p.generationId] == t then active[t.p.generationId] = nil end
        exitConfirmed(t.p, t.entity); return
    end
    CreateThread(function()
        local quick = t.phase == 'enter' and (t.p.action == 'rest' or t.p.action == 'sleep')
        t.phase = 'exit'
        local duration = play(t, animations[t.p.action][1] .. (quick and '@quick_exit' or '@stand_exit'),
            quick and 'quick_exit' or 'exit', false, true)
        if duration then Wait(duration) end
        if active[t.p.generationId] == t then
            targeting(t, true)
            if controlled(t) then ClearPedTasks(t.entity) end
            active[t.p.generationId] = nil
            exitConfirmed(t.p, t.entity)
        end
    end)
end

RegisterNetEvent('bcc-stables:world:start', function(p)
    if source ~= 65535 or not Config.worldCare or not Config.worldCare.enabled then return end
    local e = entity(p); if not e or not yes(NetworkHasControlOfEntity(e)) then return end
    if p.sequence <= (seen[p.generationId] or 0) then return end
    remember(p)
    local previous = active[p.generationId]
    if previous then stop(previous) end -- A newer authoritative action supersedes the old worker.
    local t = { p = p, entity = e, phase = 'load', lease = GetGameTimer() + 10000, waterStarted = yes(IsEntityInWater(e)) }; active[p.generationId] =
    t
    CreateThread(function()
        local a = animations[p.action]
        -- Original Horses loads both dictionaries before starting the transition.
        if not load(t, a[1] .. '@stand_enter') or not load(t, a[1] .. '@' .. a[2]) then
            stop(t); return
        end
        targeting(t, false); t.phase = 'enter'
        local duration = play(t, a[1] .. '@stand_enter', 'enter', false)
        t.entered = duration ~= nil
        local deadline = GetGameTimer() + (duration or 0)
        while duration and GetGameTimer() < deadline and not t.cancelled and eligible(t) do
            Wait(deadline - GetGameTimer() > 100 and 100 or 0)
        end
        if duration and not t.cancelled and eligible(t) and play(t, a[1] .. '@' .. a[2], a[3], true) then
            t.phase = 'loop'
            while not t.cancelled and GetGameTimer() < t.lease and eligible(t) do Wait(100) end
        end
        if not t.cancelled then stop(t) end
    end)
end)

RegisterNetEvent('bcc-stables:world:sample', function(p)
    if source ~= 65535 then return end
    local e = entity(p); local t = e and active[p.generationId]
    if not e or type(p.sample) ~= 'number' or not yes(NetworkHasControlOfEntity(e)) then return end
    CreateThread(function()
        local a = animations[p.action]
        local function playing()
            return t and (t.phase == 'enter' or t.phase == 'loop') and
            yes(IsEntityPlayingAnim(e, a[1] .. (t.phase == 'loop' and '@' .. a[2] or '@stand_enter'),
                t.phase == 'loop' and a[3] or 'enter', 3)) or false
        end
        local deadline = GetGameTimer() + 500
        while t and not t.cancelled and eligible(t) and not playing() and GetGameTimer() < deadline do Wait(25) end
        local ok = t and t.p.sequence == p.sequence and not t.cancelled and eligible(t) or false
        if ok then t.lease = GetGameTimer() + 4500 end
        local isPlaying = ok and playing() or false
        local health = Citizen.InvokeNative(0x36731AC041289BB1, e, 0, Citizen.ResultAsInteger())
        local stamina = Citizen.InvokeNative(0x36731AC041289BB1, e, 1, Citizen.ResultAsInteger())
        if type(health) ~= 'number' or type(stamina) ~= 'number' then
            ok = false; health = 0; stamina = 0
        end
        C.Rpc('world_sample', {
            generationId = p.generationId,
            sequence = p.sample,
            eligible = ok,
            playing = isPlaying,
            loop = t and t.phase == 'loop' or false,
            water = t and t.waterStarted or yes(IsEntityInWater(e)),
            healthCore = health,
            staminaCore = stamina,
            appliedRevision = tonumber(Entity(e).state.bccStablesCoreRevision) or 0
        })
    end)
end)

RegisterNetEvent('bcc-stables:world:stop', function(p)
    if source ~= 65535 or type(p) ~= 'table' then return end
    local e = entity(p); if not e or p.sequence < (seen[p.generationId] or 0) then return end
    remember(p)
    if p.immediate then W.CancelForInjury(p.generationId);return end
    local t = active[p.generationId]
    if t and t.p.sequence == p.sequence then
        stop(t)
    elseif e and yes(NetworkHasControlOfEntity(e)) then
        local a = animations[p.action]
        targeting({ p = p, entity = e }, true)
        if GetRiderOfMount(e, false) == 0 and GetRiderOfMount(e, true) == 0
            and (yes(IsEntityPlayingAnim(e, a[1] .. '@' .. a[2], a[3], 3)) or yes(IsEntityPlayingAnim(e, a[1] .. '@stand_enter', 'enter', 3))) then
            ClearPedTasks(e)
        end
        exitConfirmed(p, e)
    end
end)

RegisterNetEvent('bcc-stables:world:reward', function(p)
    if source ~= 65535 or type(p) ~= 'table' then return end
    local r = H.GetActive(); if not r or r.generationId ~= p.generationId or r.id ~= p.horseId then return end
    local xp = p.bonding
    if xp and (xp.amount or 0) > 0 then
        if Config.bonding.showXpMessage ~= false then C.Notify(C.Text('menu_bondingEarned', xp.amount,
                C.Text('menu_bondingReason_drink'), xp.xp)) end
        Stables.HorseBonding.NotifyLevel(xp)
    end
end)

RegisterNetEvent('bcc-stables:world:ended', function(p)
    local r = H.GetActive()
    if source == 65535 and type(p) == 'table' and type(p.sequence) == 'number' and r and r.generationId == p.generationId
        and (not ownerState or ownerState.generationId ~= p.generationId or p.sequence >= ownerState.sequence) then
        ownerState = { generationId = p.generationId, sequence = p.sequence, ended = true, completed = p.completed ==
        true, mountAllowed = p.mountAllowed ~= false }
        C.Notify(C.Text('menu_worldEnded'))
    end
end)

RegisterNetEvent('bcc-stables:world:owner_state', function(p)
    local r = H.GetActive()
    if source ~= 65535 or type(p) ~= 'table' or type(p.sequence) ~= 'number' or not animations[p.action]
        or not r or r.generationId ~= p.generationId then
        return
    end
    if not ownerState or ownerState.generationId ~= p.generationId or p.sequence > ownerState.sequence then ownerState =
        p end
end)

local prompts = {}
local nextLabels, nextRequest = 0, 0

local function visible(entry, value)
    if entry.visible ~= value then
        UiPromptSetVisible(entry.handle, value); entry.visible = value
    end
end

function W.Hide()
    for _, entry in pairs(prompts) do visible(entry, false) end
end

local function prompt(action, group)
    local entry = prompts[action]
    if not entry then
        local handle = UiPromptRegisterBegin()
        UiPromptSetControlAction(handle, Config.controls[action])
        UiPromptSetText(handle, CreateVarString(10, 'LITERAL_STRING', C.Text('menu_worldPrompt_' .. action)))
        UiPromptSetStandardMode(handle, true)
        UiPromptSetGroup(handle, group, 0)
        UiPromptSetEnabled(handle, true)
        UiPromptSetVisible(handle, false)
        UiPromptRegisterEnd(handle)
        entry = { handle = handle, group = group, visible = false }
        prompts[action] = entry
    elseif entry.group ~= group then
        UiPromptSetGroup(entry.handle, group, 0)
        entry.group = group
    end
    return entry
end

local function mountAfterExit(r, state)
    if deferredMount then return end; deferredMount = true
    local ped = PlayerPedId()
    CreateThread(function()
        local ok, result = pcall(C.Rpc, 'world_care', { action = 'stop' })
        local deadline = GetGameTimer() + 30000
        while ok and result.ok and not shuttingDown and GetGameTimer() < deadline do
            local current = H.GetActive()
            if not current or current.generationId ~= r.generationId or current.entity ~= r.entity or PlayerPedId() ~= ped or not alive(ped) then break end
            if ownerState and ownerState.generationId == r.generationId and ownerState.sequence == state.sequence and ownerState.ended then
                local a, b = GetEntityCoords(ped), GetEntityCoords(r.entity)
                if ownerState.completed and ownerState.mountAllowed and not IsNuiFocused() and not yes(IsPedOnMount(ped))
                    and GetRiderOfMount(r.entity, false) == 0 and GetRiderOfMount(r.entity, true) == 0
                    and (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2 <= 16 then
                    Citizen.InvokeNative(0x92DB0739813C5186, ped, r.entity, -1, -1, 2.0, 1, 0, 0)
                end
                break
            end
            Wait(50)
        end
        deferredMount = false
    end)
end

function W.Input(r)
    if Stables.HorseInjuries and Stables.HorseInjuries.Blocked(r.generationId) then W.Hide();return end
    if not Config.worldCare or not Config.worldCare.enabled or not r then
        W.Hide()
        return
    end

    local state = ownerState and ownerState.generationId == r.generationId and not ownerState.ended and ownerState
    local actions, group
    if state then
        W.Hide()
        DisableControlAction(0, 0xCEFD9220, true) -- Normal INPUT_ENTER / mount key.
        if yes(IsDisabledControlJustPressed(0, 0xCEFD9220)) then
            mountAfterExit(r, state)
        end
        return
    elseif yes(Citizen.InvokeNative(0x27F89FDC16688A7A, PlayerId(), r.entity, false)) and not IsPlayerFreeAiming(PlayerId()) then
        group = Citizen.InvokeNative(0xB796970BD125FCE8, r.entity)
        actions = { 'drink', 'rest', 'sleep', 'wallow' }
    else
        W.Hide()
        return
    end

    if not group or group == 0 then
        W.Hide()
        return
    end

    local shown = {}
    for _, action in ipairs(actions) do
        shown[action] = true
    end

    for action, entry in pairs(prompts) do
        if not shown[action] then
            visible(entry, false)
        end
    end

    local now = GetGameTimer()
    local refreshLabels = now >= nextLabels
    if refreshLabels then
        nextLabels = now + 500
    end

    local idle = GetRiderOfMount(r.entity, false) == 0 and GetRiderOfMount(r.entity, true) == 0
        and not yes(Citizen.InvokeNative(0xAC5045AB7F1A34FD, r.entity))
    local water = yes(IsEntityInWater(r.entity))
    -- Register/rebind the complete group before accepting any action, as the
    -- original resource did; an immediate click cannot leave a partial group.
    for _, action in ipairs(actions) do prompt(action, group) end
    for _, action in ipairs(actions) do
        local entry = prompt(action, group); visible(entry, true)
        local allowed = idle and (action ~= 'drink' or water)
        allowed = allowed and now >= nextRequest
        if entry.enabled ~= allowed then
            UiPromptSetEnabled(entry.handle, allowed); entry.enabled = allowed
        end
        if refreshLabels then
            UiPromptSetText(entry.handle, CreateVarString(10, 'LITERAL_STRING', C.Text('menu_worldPrompt_' .. action)))
        end
        if allowed and yes(UiPromptHasStandardModeCompleted(entry.handle, 0)) then
            nextRequest = now + 1500
            CreateThread(function()
                local result = C.Rpc('world_care', { action = action })
                if result.ok then
                    C.Notify(C.Text('menu_worldStarted', C.Text('menu_world_' .. action)))
                else
                    C.Notify(C.Text(result.code == 'world_care_locked' and 'menu_worldLocked' or 'menu_worldUnavailable'))
                end
            end)
            return
        end
    end
end

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    shuttingDown = true
    for _, t in pairs(active) do
        t.cancelled = true
        targeting(t, true)
        if entity(t.p) and yes(NetworkHasControlOfEntity(t.entity)) and GetRiderOfMount(t.entity, false) == 0 and GetRiderOfMount(t.entity, true) == 0 then
            ClearPedTasks(t.entity) end
    end
    active = {}
    for _, entry in pairs(prompts) do UiPromptDelete(entry.handle) end
    prompts = {}
end)
