local WorldCare = {
    cachedHorse = 0,
    cachedContext = nil,
    nextScanAt = 0,
    pendingReservations = {},
    interactionToken = 0,
    activeInteraction = nil,
}

local APPROACH_DISTANCE <const> = 1.0
local REQUEST_TIMEOUT_MS <const> = 3000
local GET_CLOSEST_OBJECT_OF_TYPE <const> = 0xE143FA2249364369
local DEFAULT_TRANSITION_DURATION_MS <const> = 2500

local function localized(key, fallback)
    local locale = Locales and Locales[Config.locale]
    local value = locale and locale[key]
    return type(value) == 'string' and value or fallback
end

local function horseExists(horse)
    return horse and horse ~= 0 and DoesEntityExist(horse) and not IsEntityDead(horse)
end

local function normalizeHeading(heading)
    heading = heading % 360.0
    return heading < 0.0 and heading + 360.0 or heading
end

local function animationDurationMs(animation)
    local duration = GetAnimDuration(animation.dict, animation.name)
    if not duration or duration <= 0 then return DEFAULT_TRANSITION_DURATION_MS end
    return math.max(1, math.floor(duration * 1000))
end

local function startTransition(horse, animation, active, token)
    if not animation then return 0 end
    if not LoadAnim(animation.dict) then return nil end
    if active and (WorldCare.activeInteraction ~= active or active.token ~= token) then
        RemoveAnimDict(animation.dict)
        return nil
    end

    local coords = GetEntityCoords(horse)
    local rotation = GetEntityRotation(horse, 2)
    local duration = animationDurationMs(animation)

    TaskPlayAnimAdvanced(
        horse,
        animation.dict,
        animation.name,
        coords.x,
        coords.y,
        coords.z,
        rotation.x,
        rotation.y,
        rotation.z,
        1.0,
        1.0,
        -1,
        0,
        0.0,
        0,
        0
    )
    RemoveAnimDict(animation.dict)
    return duration
end

local function playTransition(horse, animation, active, token)
    local duration = startTransition(horse, animation, active, token)
    if duration == nil then return false end
    if duration > 0 then Wait(duration) end
    return horse == MyHorse and horseExists(horse)
end

local function findProfileObject(horse, profiles, radius)
    local coords = GetEntityCoords(horse)

    for index = 1, #(profiles or {}) do
        local profile = profiles[index]
        if not profile.hash then
            profile.hash = type(profile.model) == 'number' and profile.model
                or type(profile.model) == 'string' and joaat(profile.model)
                or nil
        end

        if profile.hash then
            local object = Citizen.InvokeNative(
                GET_CLOSEST_OBJECT_OF_TYPE,
                coords.x,
                coords.y,
                coords.z,
                radius,
                profile.hash,
                false,
                false,
                false,
                Citizen.ResultAsInteger()
            )

            if object and object ~= 0 and DoesEntityExist(object) then
                return object, profile
            end
        end
    end
end

local function scanContext(horse)
    local config = Config.care.world
    if not config or config.enabled == false then return nil end

    local radius = math.max(0.5, tonumber(config.scanRadius) or 3.0)
    local object, profile = findProfileObject(horse, config.troughs and config.troughs.profiles, radius)
    if object then
        return { kind = 'trough', reward = 'drink', object = object, profile = profile, config = config.troughs }
    end

    object, profile = findProfileObject(horse, config.hay and config.hay.profiles, radius)
    if object then
        return { kind = 'hay', reward = 'feed', object = object, profile = profile, config = config.hay }
    end
end

local function getContext(horse, force)
    if not horseExists(horse) then return nil end

    local now = GetGameTimer()
    if force or horse ~= WorldCare.cachedHorse or now >= WorldCare.nextScanAt then
        WorldCare.cachedHorse = horse
        WorldCare.cachedContext = scanContext(horse)
        WorldCare.nextScanAt = now + math.max(100, tonumber(Config.care.world.scanIntervalMs) or 500)
    end

    return WorldCare.cachedContext
end

local function requestReservation(context)
    local requestId = ('%s:%s'):format(GetPlayerServerId(PlayerId()), GetGameTimer())
    local objectCoords = GetEntityCoords(context.object)
    local response

    WorldCare.pendingReservations[requestId] = function(granted, reservationKey)
        response = { granted = granted == true, key = reservationKey }
    end

    TriggerServerEvent(
        'bcc-horses:worldCare:reserve',
        requestId,
        context.kind,
        context.profile.hash,
        objectCoords.x,
        objectCoords.y,
        objectCoords.z,
        MyHorseId
    )

    local deadline = GetGameTimer() + REQUEST_TIMEOUT_MS
    while not response and GetGameTimer() < deadline do Wait(0) end
    WorldCare.pendingReservations[requestId] = nil
    return response
end

RegisterNetEvent('bcc-horses:worldCare:reservationResult', function(requestId, granted, reservationKey)
    local callback = WorldCare.pendingReservations[requestId]
    if callback then callback(granted, reservationKey) end
end)

local function releaseReservation(key)
    if key then TriggerServerEvent('bcc-horses:worldCare:release', key) end
end

local function approachInteractionPoint(horse, context, token)
    if not DoesEntityExist(context.object) then return false end

    local horseCoords = GetEntityCoords(horse)
    local objectCoords = GetEntityCoords(context.object)
    local awayX = horseCoords.x - objectCoords.x
    local awayY = horseCoords.y - objectCoords.y
    local length = math.sqrt((awayX * awayX) + (awayY * awayY))

    if length < 0.01 then
        local objectHeading = math.rad(GetEntityHeading(context.object))
        awayX = -math.sin(objectHeading)
        awayY = math.cos(objectHeading)
        length = 1.0
    end

    local distance = math.max(0.5, tonumber(context.profile.distance) or 1.1)
    local target = vector3(
        objectCoords.x + ((awayX / length) * distance),
        objectCoords.y + ((awayY / length) * distance),
        horseCoords.z
    )
    local towardX = objectCoords.x - target.x
    local towardY = objectCoords.y - target.y
    local heading = normalizeHeading(math.deg(math.atan(-towardX, towardY)))
    local timeout = math.max(1000, tonumber(Config.care.world.approachTimeoutMs) or 6000)

    TaskGoStraightToCoord(horse, target.x, target.y, target.z, 1.0, -1, heading, 0.35, 0)
    local deadline = GetGameTimer() + timeout

    while horseExists(horse) and GetGameTimer() < deadline
        and WorldCare.activeInteraction
        and WorldCare.activeInteraction.token == token do
        if #(GetEntityCoords(horse) - target) <= APPROACH_DISTANCE then
            ClearPedTasks(horse)
            SetEntityHeading(horse, heading)
            return true
        end
        Wait(100)
    end

    ClearPedTasks(horse)
    return false
end

local function resetWorldCareInteraction(active)
    if not active or WorldCare.activeInteraction ~= active then return end
    releaseReservation(active.reservationKey)
    WorldCare.activeInteraction = nil
    IsInteractingWithHorse = false
    WorldCare.nextScanAt = 0
end

local function beginWorldCareExit()
    local active = WorldCare.activeInteraction
    if not active then return 0 end
    if active.phase == 'exit' then return active.exitDuration or 0 end

    WorldCare.interactionToken = WorldCare.interactionToken + 1
    active.token = WorldCare.interactionToken

    if active.phase == 'reserve' or active.phase == 'approach' then
        local wasApproaching = active.phase == 'approach'
        if horseExists(active.horse) then ClearPedTasks(active.horse) end
        resetWorldCareInteraction(active)
        return wasApproaching and 150 or 0
    end

    active.phase = 'exit'

    local horse = active.horse
    if not horseExists(horse) then
        resetWorldCareInteraction(active)
        return 0
    end

    ClearPedTasks(horse)
    local duration = startTransition(horse, active.context.config and active.context.config.exitAnimation)
    if duration == nil then duration = 0 end
    active.exitDuration = duration

    CreateThread(function()
        if duration > 0 then Wait(duration) end
        if WorldCare.activeInteraction ~= active then return end
        if horseExists(horse) then ClearPedTasks(horse) end
        resetWorldCareInteraction(active)
    end)

    return duration
end

function IsHorseWorldCareInteractionActive(horse)
    local active = WorldCare.activeInteraction
    return active ~= nil and active.horse == horse
end

function CancelHorseWorldCareInteraction()
    return beginWorldCareExit()
end

local function runWorldCare(context)
    local horse = MyHorse
    if IsInteractingWithHorse or not horseExists(horse) or not MyHorseId or MyHorseId == 0 then return end

    IsInteractingWithHorse = true
    WorldCare.interactionToken = WorldCare.interactionToken + 1
    local active = {
        horse = horse,
        context = context,
        token = WorldCare.interactionToken,
        phase = 'reserve',
    }
    WorldCare.activeInteraction = active
    local token = active.token
    local reservation = requestReservation(context)
    if WorldCare.activeInteraction ~= active then
        if reservation and reservation.key then releaseReservation(reservation.key) end
        return
    end
    if not reservation or not reservation.granted then
        resetWorldCareInteraction(active)
        return Core.NotifyRightTip(localized('worldCareInUse', 'Another horse is already using this spot.'), 4000)
    end
    active.reservationKey = reservation.key

    if WorldCare.activeInteraction ~= active or active.token ~= token then
        releaseReservation(reservation.key)
        return
    end

    if not DoesEntityExist(context.object) or horse ~= MyHorse or not horseExists(horse) then
        resetWorldCareInteraction(active)
        return
    end

    active.phase = 'approach'
    if not approachInteractionPoint(horse, context, token) then
        if WorldCare.activeInteraction ~= active then return end
        resetWorldCareInteraction(active)
        return Core.NotifyRightTip(localized('worldCareApproachFailed', 'Your horse could not reach that spot.'), 4000)
    end

    active.phase = 'enter'
    if not playTransition(horse, context.config and context.config.enterAnimation, active, token) then
        if WorldCare.activeInteraction == active and active.token == token then
            resetWorldCareInteraction(active)
        end
        return
    end
    if WorldCare.activeInteraction ~= active or active.token ~= token then return end

    local animation = context.config and context.config.animation
    if not animation or not LoadAnim(animation.dict) then
        resetWorldCareInteraction(active)
        return DBG:Error('Failed to load world-care horse animation:', animation and animation.dict or 'missing')
    end

    active.phase = 'loop'
    local duration = math.max(1, tonumber(context.config.durationSeconds) or 10) * 1000
    TaskPlayAnim(horse, animation.dict, animation.name, 1.0, 1.0, duration, 3, 1.0, false, false, false)
    Wait(duration)
    RemoveAnimDict(animation.dict)

    if WorldCare.activeInteraction ~= active or active.token ~= token then return end
    if horse == MyHorse and horseExists(horse) then
        RewardWorldCareInteraction(context.reward, horse)
        beginWorldCareExit()
        return
    end

    resetWorldCareInteraction(active)
end

function GetHorseCarePromptLabel(horse)
    local context = getContext(horse, false)
    if context and context.kind == 'trough' then
        return localized('drinkFromTroughPrompt', 'Drink from Trough')
    end
    if context and context.kind == 'hay' then return localized('eatHayPrompt', 'Eat Hay') end
    return localized('drinkPrompt', 'Drink')
end

function StartHorseContextCare()
    local horse = MyHorse
    local context = getContext(horse, true)

    if not context then
        HorseDrinking()
        return
    end

    CreateThread(function() runWorldCare(context) end)
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    local active = WorldCare.activeInteraction
    if active and horseExists(active.horse) then ClearPedTasks(active.horse) end
    TriggerServerEvent('bcc-horses:worldCare:releaseAll')
end)
