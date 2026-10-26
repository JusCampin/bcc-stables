local TAG_UPDATE_INTERVAL_MS = 1000
local BREED_CHECK_INTERVAL_MS = 1000
local DEFAULT_TAG_DISTANCE = 15.0
local UNKNOWN_BREED = 'Unknown'
local OTHER_BREED = 'Other'

local NATIVE_CREATE_MP_GAMER_TAG_ON_ENTITY = 0xE961BF23EAB76B12
local NATIVE_SET_MP_GAMER_TAG_TOP_ICON = 0x5F57522BC1EB9D9D
local NATIVE_SET_MP_GAMER_TAG_VISIBILITY = 0x93171DDDAB274EB8
local NATIVE_IS_MP_GAMER_TAG_ACTIVE_ON_ENTITY = 0x502E1591A504F843
local NATIVE_REMOVE_MP_GAMER_TAG = 0x839BFD7D7E49FE09
local NATIVE_IS_MOUNT_SEAT_FREE = 0xAAB0FE202E9FC9F0
local NATIVE_GET_MOUNT = 0xE7E11B8DCBED1058
local horseTagGeneration = 0
local breedLabelByModel = {}

local function isValidEntity(entity)
    return entity and entity ~= 0 and DoesEntityExist(entity)
end

local function getSubmergedLevel(entity)
    return tonumber(GetEntitySubmergedLevel(entity)) or 0.0
end

local function setHorseTagVisibility(gamerTagId, isVisible)
    Citizen.InvokeNative(NATIVE_SET_MP_GAMER_TAG_VISIBILITY, gamerTagId, isVisible and 3 or 0)
end

local function removeHorseTag(gamerTagId)
    Citizen.InvokeNative(NATIVE_REMOVE_MP_GAMER_TAG, Citizen.PointerValueIntInitialized(gamerTagId))
end

local function getBreedLabel(modelHash)
    local cachedLabel = breedLabelByModel[modelHash]
    if cachedLabel then return cachedLabel end

    local modelName = ResolveHorseModelName(modelHash)
    if not modelName then return nil end

    local mapping = Horses.ModelToBreedMap and Horses.ModelToBreedMap[modelName]
    local breedName = mapping and mapping.breed or UNKNOWN_BREED
    local displayLabel = breedName

    if breedName == OTHER_BREED then
        local catalog = Horses.BreedCatalog and Horses.BreedCatalog[breedName]
        local color = catalog and catalog.colors and catalog.colors[modelName]
        displayLabel = color and color.color or breedName
    end

    breedLabelByModel[modelHash] = displayLabel
    return displayLabel
end

local function shouldDisplayHorseTag(playerPed, horse, maxDistanceSquared)
    if IsPedLeadingHorse(playerPed) and GetLastLedMount(playerPed) == horse then
        return false
    end

    if not Citizen.InvokeNative(NATIVE_IS_MOUNT_SEAT_FREE, horse, -1) then
        return false
    end

    local offset = GetEntityCoords(playerPed) - GetEntityCoords(horse)
    local distanceSquared = offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
    return distanceSquared < maxDistanceSquared
end

-- Set the active horse's name and health bar above the entity.
AddEventHandler('bcc-horses:HorseTag', function()
    horseTagGeneration = horseTagGeneration + 1

    local generation = horseTagGeneration
    local horse = MyHorse
    if not isValidEntity(horse) then return end

    local tagDistance = tonumber(Config.display.horseTag.distance) or DEFAULT_TAG_DISTANCE
    local maxDistanceSquared = tagDistance * tagDistance
    local gamerTagId = Citizen.InvokeNative(NATIVE_CREATE_MP_GAMER_TAG_ON_ENTITY, horse, HorseName)

    Citizen.InvokeNative(NATIVE_SET_MP_GAMER_TAG_TOP_ICON, gamerTagId, `PLAYER_HORSE`)

    -- nil forces the first update to explicitly apply the native's visibility state.
    local isTagVisible
    while generation == horseTagGeneration
        and IsMyHorseActive
        and MyHorse == horse
        and isValidEntity(horse)
    do
        local shouldShow = shouldDisplayHorseTag(PlayerPedId(), horse, maxDistanceSquared)

        if shouldShow ~= isTagVisible then
            if shouldShow
                or Citizen.InvokeNative(NATIVE_IS_MP_GAMER_TAG_ACTIVE_ON_ENTITY, gamerTagId, horse)
            then
                setHorseTagVisibility(gamerTagId, shouldShow)
            end

            isTagVisible = shouldShow
        end

        Wait(TAG_UPDATE_INTERVAL_MS)
    end

    removeHorseTag(gamerTagId)
end)

-- Show the breed when the player mounts a horse other than their active horse.
CreateThread(function()
    if not Config.display.showMountedHorseBreed then return end

    local lastNotifiedMount = 0

    while true do
        local mount = Citizen.InvokeNative(NATIVE_GET_MOUNT, PlayerPedId())

        if not mount or mount == 0 or mount == MyHorse then
            lastNotifiedMount = 0
        elseif mount ~= lastNotifiedMount then
            lastNotifiedMount = mount

            local displayLabel = getBreedLabel(GetEntityModel(mount))
            if displayLabel then
                Core.NotifyBottomRight(displayLabel, 1000)
            end
        end

        Wait(BREED_CHECK_INTERVAL_MS)
    end
end)

-- Clean the active horse once whenever it crosses into sufficiently deep water.
CreateThread(function()
    local waterCleaning = Config.care and Config.care.waterCleaning
    if not waterCleaning or waterCleaning.enabled == false then return end

    local minimumLevel = math.max(0.0, math.min(1.0, tonumber(waterCleaning.minimumSubmergedLevel) or 0.35))
    local checkInterval = math.max(100, math.floor(tonumber(waterCleaning.checkIntervalMs) or 500))
    local trackedHorse = 0
    local wasInDeepWater = false

    while true do
        local horse = MyHorse

        if isValidEntity(horse) and not IsEntityDead(horse) then
            if horse ~= trackedHorse then
                trackedHorse = horse
                wasInDeepWater = false
            end

            local isInDeepWater = IsEntityInWater(horse)
                and getSubmergedLevel(horse) >= minimumLevel

            if isInDeepWater and not wasInDeepWater then
                CleanHorseAppearance(horse)
            end

            wasInDeepWater = isInDeepWater
        else
            trackedHorse = 0
            wasInDeepWater = false
        end

        Wait(checkInterval)
    end
end)
