local SHOW_XP_MESSAGE = Config.training.showXpMessage ~= false
local TRAVEL_TICK_INTERVAL = 2000
local MIN_TRAVEL_SPEED = 0.8
local MAX_TRAVEL_SPEED = 35.0
local RIDING_TICKS_REQUIRED = 30
local LEADING_TICKS_REQUIRED = 15

local ATTRIBUTE = {
    health = 0,
    stamina = 1,
    handling = 4,
    speed = 5,
    acceleration = 6,
    bonding = 7,
}

local NATIVE = {
    addAttributePoints = 0x75415EE0CB583760,
    getLastLedMount = 0x693126B5D0457D0D,
    getAttributeCoreValue = 0x36731AC041289BB1,
    isPedLeadingHorse = 0xEFC4303DDC6E60D3,
    setAttributeBaseRank = 0x5DA12E025D47D4E5,
    setAttributeCoreValue = 0xC6258F41D86676E0,
}

local XP_REWARDS = {
    riding = Config.training.xpRewards.riding or 10,
    leading = Config.training.xpRewards.leading or 15,
    brush = Config.training.xpRewards.brush or 5,
    pat = Config.training.xpRewards.pat or 1,
    feed = Config.training.xpRewards.feed or 5,
    drink = Config.training.xpRewards.drink or 5,
}

local DEFAULT_STATS = {
    speed = 0,
    acceleration = 0,
    handling = 0,
    health = 0,
    stamina = 0,
}

local function clampCore(value)
    return math.max(0, math.min(100, tonumber(value) or 100))
end

local function horseExists(horse)
    return horse ~= nil and horse ~= 0 and DoesEntityExist(horse)
end

local function isLivingHorse(horse)
    return horseExists(horse) and not IsEntityDead(horse)
end

local function hasActiveHorseId()
    return MyHorseId ~= nil and MyHorseId ~= 0
end

local function newDefaultStats()
    return {
        speed = DEFAULT_STATS.speed,
        acceleration = DEFAULT_STATS.acceleration,
        handling = DEFAULT_STATS.handling,
        health = DEFAULT_STATS.health,
        stamina = DEFAULT_STATS.stamina,
    }
end

local function applyHorseStats(horse, stats, healthCore, staminaCore)
    Citizen.InvokeNative(NATIVE.setAttributeCoreValue, horse, ATTRIBUTE.health, clampCore(healthCore))
    Citizen.InvokeNative(NATIVE.setAttributeCoreValue, horse, ATTRIBUTE.stamina, clampCore(staminaCore))

    Citizen.InvokeNative(NATIVE.setAttributeBaseRank, horse, ATTRIBUTE.health, stats.health)
    Citizen.InvokeNative(NATIVE.setAttributeBaseRank, horse, ATTRIBUTE.stamina, stats.stamina)
    Citizen.InvokeNative(NATIVE.setAttributeBaseRank, horse, ATTRIBUTE.handling, stats.handling)
    Citizen.InvokeNative(NATIVE.setAttributeBaseRank, horse, ATTRIBUTE.speed, stats.speed)
    Citizen.InvokeNative(NATIVE.setAttributeBaseRank, horse, ATTRIBUTE.acceleration, stats.acceleration)
end

---@param xpSource string
function SaveXp(xpSource)
    local pointsToGive = tonumber(XP_REWARDS[xpSource]) or 0
    if pointsToGive <= 0 then return end

    if isLivingHorse(MyHorse) and not MaxBonding then
        Citizen.InvokeNative(NATIVE.addAttributePoints, MyHorse, ATTRIBUTE.bonding, pointsToGive)
    end

    TriggerServerEvent('bcc-horses:UpdateHorseXp', xpSource, MyHorseId)
end

local function awardTravelXp(source, debugMessage)
    if not CanPlayerTrainHorses() or not hasActiveHorseId() then return end

    DBG:Info(debugMessage)
    SaveXp(source)
end

local function runTravelXpMonitor()
    local ridingTicks = 0
    local leadingTicks = 0

    while isLivingHorse(MyHorse) do
        local playerPed = PlayerPedId()
        local speed = GetEntitySpeed(MyHorse)
        local isMoving = speed > MIN_TRAVEL_SPEED and speed < MAX_TRAVEL_SPEED

        if isMoving then
            local isMounted = IsPedOnMount(playerPed) and GetMount(playerPed) == MyHorse

            if isMounted then
                ridingTicks = ridingTicks + 1
                if ridingTicks >= RIDING_TICKS_REQUIRED then
                    ridingTicks = 0
                    awardTravelXp('riding', 'Riding milestone hit! Saving xp...')
                end
            elseif Citizen.InvokeNative(NATIVE.isPedLeadingHorse, playerPed) then
                local ledHorse = Citizen.InvokeNative(NATIVE.getLastLedMount, playerPed)
                if ledHorse == MyHorse then
                    leadingTicks = leadingTicks + 1
                    if leadingTicks >= LEADING_TICKS_REQUIRED then
                        leadingTicks = 0
                        awardTravelXp('leading', 'Leading milestone hit! Saving xp...')
                    end
                end
            end
        else
            ridingTicks = math.max(0, ridingTicks - 1)
            leadingTicks = math.max(0, leadingTicks - 1)
        end

        Wait(TRAVEL_TICK_INTERVAL)
    end

    IsTravelMonitorActive = false
end

AddEventHandler('bcc-horses:TravelXpMonitor', function()
    if IsTravelMonitorActive then return end

    IsTravelMonitorActive = true
    CreateThread(runTravelXpMonitor)
end)

---@param dead boolean
function SaveHorseStats(dead)
    if not hasActiveHorseId() then return end

    MyHorseStats = MyHorseStats or newDefaultStats()

    local healthCore = 100
    local staminaCore = 100

    if not dead and IsMyHorseActive and horseExists(MyHorse) then
        healthCore = Citizen.InvokeNative(
            NATIVE.getAttributeCoreValue,
            MyHorse,
            ATTRIBUTE.health,
            Citizen.ResultAsInteger()
        )
        staminaCore = Citizen.InvokeNative(
            NATIVE.getAttributeCoreValue,
            MyHorse,
            ATTRIBUTE.stamina,
            Citizen.ResultAsInteger()
        )
    end

    TriggerServerEvent(
        'bcc-horses:SaveHorseStatsToDb',
        json.encode(MyHorseStats),
        MyHorseId,
        clampCore(healthCore),
        clampCore(staminaCore)
    )
end

RegisterNetEvent('bcc-horses:SyncHorseStats', function(
    statsJson,
    horseId,
    trueXp,
    dbCurrentHealth,
    dbCurrentStamina,
    awardedXp,
    xpSource
)
    if horseId ~= MyHorseId then return end

    local parsedStats = json.decode(statsJson) or {}

    ActiveHorseXp = tonumber(trueXp) or ActiveHorseXp or 0
    MaxBonding = GetHorseBondingData(MyHorse, ActiveHorseXp) >= 4
    MyHorseStats = {
        health = tonumber(parsedStats.health) or DEFAULT_STATS.health,
        stamina = tonumber(parsedStats.stamina) or DEFAULT_STATS.stamina,
        speed = tonumber(parsedStats.speed) or DEFAULT_STATS.speed,
        acceleration = tonumber(parsedStats.acceleration) or DEFAULT_STATS.acceleration,
        handling = tonumber(parsedStats.handling) or DEFAULT_STATS.handling,
    }

    if horseExists(MyHorse) then
        applyHorseStats(MyHorse, MyHorseStats, dbCurrentHealth, dbCurrentStamina)
    end

    local numericAward = tonumber(awardedXp) or 0
    if SHOW_XP_MESSAGE and numericAward > 0 then
        local displayLabel = type(xpSource) == 'string' and xpSource:gsub('^%l', string.upper) or 'Training'
        Core.NotifyRightTip(('+ %d XP (%s)'):format(numericAward, displayLabel), 3000)
    end
end)
