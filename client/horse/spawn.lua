local sendingHorse = nil
local followingHorse = nil
local isSelectedHorseRequestActive = false
local RESPAWN_DISTANCE = 100.0
local ARRIVAL_DISTANCE = 10.0
local FOLLOW_OFFSET_X = 2.0
local FOLLOW_OFFSET_Y = -3.0
local FOLLOW_SPEED = 2.0
local FOLLOW_STOPPING_RANGE = 3.0

local function horseExists(horse)
    return horse and horse ~= 0 and DoesEntityExist(horse)
end

local function cancelHorsePassiveInteraction()
    if type(CancelHorsePassiveInteraction) == 'function' then
        local transitionDuration = CancelHorsePassiveInteraction()
        if transitionDuration and transitionDuration > 0 then
            Wait(transitionDuration)
        end
    end
end

local function deleteHorseEntity(horse)
    if not horseExists(horse) then return end

    SetEntityAsMissionEntity(horse, true, true)
    DeleteEntity(horse)
end

local function setHorseStateNetId(netId)
    local horseData = LocalPlayer.state.HorseData or {}
    horseData.MyHorse = netId or 0
    LocalPlayer.state.HorseData = horseData
end

local function finishSpawning(model)
    if model then SetModelAsNoLongerNeeded(model) end
    IsSpawningMountActive = false
end

local function releaseStableDelivery(spawnOptions)
    if type(spawnOptions) ~= 'table' or not spawnOptions.deliveryToken then return end
    TriggerServerEvent(
        'bcc-horses:ReleaseStableDelivery',
        spawnOptions.stableSite,
        spawnOptions.deliveryToken
    )
    spawnOptions.deliveryToken = nil
end

local function getStableDeliveryDestination(stableSite)
    local configured = stableSite and stableSite.horse and stableSite.horse.delivery
    if configured then return configured end

    -- The player opens the menu or prompt outside the stable, making their
    -- request position a natural delivery target without per-site setup.
    return GetEntityCoords(PlayerPedId())
end

local function getHeadingToward(fromCoords, destination, fallbackHeading)
    if not fromCoords or not destination then return fallbackHeading end

    local deltaX = destination.x - fromCoords.x
    local deltaY = destination.y - fromCoords.y
    if math.abs(deltaX) < 0.001 and math.abs(deltaY) < 0.001 then return fallbackHeading end

    -- RedM headings increase clockwise: +X (east) is 270 degrees, not 90.
    local heading = math.deg(math.atan(-deltaX, deltaY))
    return (heading + 360.0) % 360.0
end

local function startStableDelivery(horse, stableSpawn, spawnOptions)
    local destination = spawnOptions.deliveryDestination
    if not destination then
        releaseStableDelivery(spawnOptions)
        return
    end

    local settings = Config.stable.delivery or {}
    local speed = tonumber(settings.walkSpeed) or 1.25
    local arrivalDistance = tonumber(settings.arrivalDistance) or 2.5
    local routeHeading = getHeadingToward(stableSpawn.coords, destination, stableSpawn.heading)
    TaskGoStraightToCoord(
        horse,
        destination.x,
        destination.y,
        destination.z,
        speed,
        -1,
        tonumber(destination.w) or routeHeading,
        arrivalDistance
    )

    CreateThread(function()
        local clearance = tonumber(settings.spawnClearance) or 4.0
        local timeout = math.max(5000, tonumber(settings.reservationTimeoutMs) or 15000)
        local deadline = GetGameTimer() + timeout

        while horseExists(horse) and GetGameTimer() < deadline do
            if #(GetEntityCoords(horse) - stableSpawn.coords) >= clearance then break end
            Wait(250)
        end

        releaseStableDelivery(spawnOptions)
    end)
end

local function revealStableDeliveryHorse(horse, stableSpawn, spawnOptions)
    CreateThread(function()
        -- Newly created horse models briefly use an uninitialized pose while
        -- their variation, tack, and animation state settle.
        SetEntityAlpha(horse, 0, false)
        SetEntityVisible(horse, false, false)
        Wait(400)

        if MyHorse ~= horse or not horseExists(horse) then
            releaseStableDelivery(spawnOptions)
            return
        end

        SetEntityVisible(horse, true, false)
        SetEntityAlpha(horse, 0, false)
        startStableDelivery(horse, stableSpawn, spawnOptions)

        for alpha = 40, 240, 40 do
            if MyHorse ~= horse or not horseExists(horse) then return end
            SetEntityAlpha(horse, alpha, false)
            Wait(30)
        end

        if MyHorse == horse and horseExists(horse) then ResetEntityAlpha(horse) end
    end)
end

local function isStableSpawnClear(coords, radius)
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= PlayerPedId() and DoesEntityExist(ped)
            and #(GetEntityCoords(ped) - coords) < radius then
            return false
        end
    end
    return true
end

---@param horseId number|string|nil
---@param spawnOptions table|nil
function GetSelectedHorse(horseId, spawnOptions)
    if isSelectedHorseRequestActive or IsSpawningMountActive then return end
    isSelectedHorseRequestActive = true

    local function requestHorseData()
        Core.Callback.TriggerAsync('bcc-horses:GetSelectedHorseData', function(result)
            isSelectedHorseRequestActive = false

            if not result then
                releaseStableDelivery(spawnOptions)
                DBG:Warning('No active selected-horse profile returned from server database!')
                return
            end

            SpawnHorse(result, spawnOptions)
        end, horseId and { horseId = tonumber(horseId) } or nil)
    end

    local siteId = type(spawnOptions) == 'table' and spawnOptions.stableSite
    local stableSite = siteId and Stables[siteId]
    if not stableSite then
        requestHorseData()
        return
    end

    Core.NotifyRightTip('The stable hand is preparing your horse.', 3000)
    Core.Callback.TriggerAsync('bcc-horses:ReserveStableDelivery', function(reservation)
        if type(reservation) ~= 'table' or not reservation.token then
            isSelectedHorseRequestActive = false
            Core.NotifyRightTip('The stable is busy. Please try again.', 4000)
            return
        end

        spawnOptions.deliveryToken = reservation.token
        spawnOptions.deliveryDestination = getStableDeliveryDestination(stableSite)
        requestHorseData()
    end, siteId)
end

---@param siteId string
function CallActiveHorseAtStable(siteId)
    if not Stables[siteId] then return false end
    GetSelectedHorse(nil, { stableSite = siteId })
    return true
end

---@param horseId number|string
---@param siteId string
function ManageHorseAtStable(horseId, siteId)
    local selectedHorseId = tonumber(horseId)
    local spawnedHorseId = tonumber(MyHorseId)
    if not selectedHorseId or not Stables[siteId] then return false end

    CreateThread(function()
        local horseIsOut = horseExists(MyHorse)
        if horseIsOut then ReturnHorse(spawnedHorseId ~= selectedHorseId) end

        StableMenu:Close()
        Wait(450)

        if not horseIsOut or spawnedHorseId ~= selectedHorseId then
            SetSelectedHorseLocally(selectedHorseId, false)
            GetSelectedHorse(selectedHorseId, { stableSite = siteId })
        end
    end)
    return true
end

local function sendHorse()
    local playerPed = PlayerPedId()
    local horse = MyHorse

    if not horseExists(horse) then
        sendingHorse = nil
        return
    end

    TaskGoToEntity(horse, playerPed, -1, 10.2, 2.0, 0.0, 0)

    while sendingHorse == horse and MyHorse == horse and horseExists(horse) do
        Wait(0)
        local distance = #(GetEntityCoords(playerPed) - GetEntityCoords(horse))
        if distance <= ARRIVAL_DISTANCE then
            ClearPedTasks(horse)
            break
        end
    end

    if sendingHorse == horse then sendingHorse = nil end
end

local function sendHorseToPlayer(horse)
    followingHorse = nil
    sendingHorse = horse
    CreateThread(sendHorse)
end

local function toggleHorseFollow(horse, playerPed)
    sendingHorse = nil

    if followingHorse == horse then
        followingHorse = nil
        ClearPedTasks(horse)
        return
    end

    followingHorse = horse
    Citizen.InvokeNative(
        0x304AE42E357B8C7E,
        horse,
        playerPed,
        FOLLOW_OFFSET_X,
        FOLLOW_OFFSET_Y,
        0.0,
        FOLLOW_SPEED,
        -1,
        FOLLOW_STOPPING_RANGE,
        true
    ) -- TaskFollowToOffsetOfEntity
end

function WhistleSpawn()
    if Config.stable.whistleAnywhere then
        GetSelectedHorse()
    else
        Core.NotifyRightTip(_U('stableSpawn'), 4000)
    end
end

-- Call Horse to Player
AddEventHandler('bcc-horses:WhistleHorse', function()
    local horse = MyHorse
    if not horseExists(horse) then
        followingHorse = nil
        MyHorse = 0
        WhistleSpawn()
        return
    end

    cancelHorsePassiveInteraction()
    if not GetControlOfHorse(1000) then return end

    local distance = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(horse))

    if distance >= RESPAWN_DISTANCE then
        followingHorse = nil
        sendingHorse = nil
        deleteHorseEntity(horse)
        MyHorse = 0
        setHorseStateNetId(0)
        GetSelectedHorse()
    else
        sendHorseToPlayer(horse)
    end
end)

-- Call Horse or have Horse Follow Player
AddEventHandler('bcc-horses:LongWhistleHorse', function()
    local playerPed = PlayerPedId()
    local horse = MyHorse

    if not horseExists(horse) then
        followingHorse = nil
        MyHorse = 0
        WhistleSpawn()
        return
    end

    cancelHorsePassiveInteraction()
    if not GetControlOfHorse(1000) then return end

    toggleHorseFollow(horse, playerPed)
end)

local function calculateSpawnPosition(playerPed)
    local x, y, z = table.unpack(GetOffsetFromEntityInWorldCoords(playerPed, 0.0, -10.0, 0.0))

    -- Search for an established trail or road node first
    for i = 0, 24, 3 do
        local nodeCheck, node = GetNthClosestVehicleNode(x, y, z, i, 1, 1077936128, 0)
        if nodeCheck and node ~= vector3(0, 0, 0) then
            return node
        end
    end

    -- Fallback to scanning the open ground if no road node is nearby
    local maxScan = 1000
    local maxScanDown = 300
    for offset = maxScan, -maxScanDown, -1 do
        local groundCheck, groundZ = GetGroundZAndNormalFor_3dCoord(x, y, z + offset)
        if groundCheck then
            return vector3(x, y, groundZ)
        end
    end

    return nil
end

local function applyHorseAttributes(horseEntity, statsData, xpParam, dbCurrentHealth, dbCurrentStamina, agingData)
    local stats = {}
    if type(statsData) == 'string' and statsData ~= '' then
        local wasDecoded, decodedStats = pcall(json.decode, statsData)
        if wasDecoded and type(decodedStats) == 'table' then
            stats = decodedStats
        else
            DBG:Warning('Unable to decode horse stats; using default values.')
        end
    else
        stats = type(statsData) == 'table' and statsData or {}
    end

    local healthStat  = tonumber(stats.health) or 0
    local staminaStat = tonumber(stats.stamina) or 0
    local speedStat   = tonumber(stats.speed) or 0
    local accelStat   = tonumber(stats.acceleration) or 0
    local handleStat  = tonumber(stats.handling) or 0

    local healthCorePercent  = tonumber(dbCurrentHealth) or 100
    local staminaCorePercent = tonumber(dbCurrentStamina) or 100

    ActiveHorseXp = tonumber(xpParam) or 0

    MyHorseStats = {
        health       = healthStat,
        stamina      = staminaStat,
        speed        = speedStat,
        acceleration = accelStat,
        handling     = handleStat
    }

    local aging = Config.aging or {}
    local effects = aging.seniorEffects or {}
    if aging.enabled == true and effects.enabled == true and agingData and agingData.agingEnabled == true then
        local age = math.max(0, tonumber(agingData.ageYears) or 0)
        local seniorAge = tonumber((aging.lifeStages or {}).senior) or 16
        local seniorYears = math.max(0, age - seniorAge + 1)
        local maximum = math.max(0, math.min(1, tonumber(effects.maximumPenalty) or 0.30))
        local function penalized(value, rate)
            local penalty = math.min(maximum, seniorYears * math.max(0, tonumber(rate) or 0))
            return math.max(0, math.floor(value * (1.0 - penalty) + 0.5))
        end
        staminaStat = penalized(staminaStat, effects.staminaPenaltyPerYear)
        speedStat = penalized(speedStat, effects.speedPenaltyPerYear)
        accelStat = penalized(accelStat, effects.accelerationPenaltyPerYear)
    end

    -- SetAttributeCoreValue
    Citizen.InvokeNative(0xC6258F41D86676E0, horseEntity, 0, healthCorePercent)  -- Health Core
    Citizen.InvokeNative(0xC6258F41D86676E0, horseEntity, 1, staminaCorePercent) -- Stamina Core

    -- SetAttributeBaseRank
    Citizen.InvokeNative(0x5DA12E025D47D4E5, horseEntity, 0, healthStat)  -- PA_HEALTH Max Ring Capacity
    Citizen.InvokeNative(0x5DA12E025D47D4E5, horseEntity, 1, staminaStat) -- PA_STAMINA Max Ring Capacity
    Citizen.InvokeNative(0x5DA12E025D47D4E5, horseEntity, 4, handleStat)  -- PA_AGILITY / Handling
    Citizen.InvokeNative(0x5DA12E025D47D4E5, horseEntity, 5, speedStat)   -- PA_SPEED
    Citizen.InvokeNative(0x5DA12E025D47D4E5, horseEntity, 6, accelStat)   -- PA_ACCELERATION

    -- SetAttributePoints
    Citizen.InvokeNative(0x09A59688C26D88DF, horseEntity, 7, ActiveHorseXp) -- Bonding

    local bondingLevel = GetHorseBondingData(horseEntity, ActiveHorseXp)
    MaxBonding = bondingLevel >= 4
end

local function applyConfigFlags(horseEntity)
    local currentLevel = GetHorseBondingData(horseEntity, ActiveHorseXp)

    if currentLevel >= 2 then
        Citizen.InvokeNative(0x1913FE4CBF41C463, horseEntity, 113, true) -- DisableShockingEvents
    end

    if currentLevel >= 3 then
        Citizen.InvokeNative(0x1913FE4CBF41C463, horseEntity, 312, true) -- DisableHorseGunshotFleeResponse
    end

    Citizen.InvokeNative(0x1913FE4CBF41C463, horseEntity, 297, true) -- ForceInteractionLockonOnTargetPed (Lead Horse)
    Citizen.InvokeNative(0x1913FE4CBF41C463, horseEntity, 471, Config.horseBehavior.disableKick) -- DisableHorseKick
    Citizen.InvokeNative(0xE2487779957FE897, horseEntity, 528) -- SetTransportUsageFlags
end

function SpawnHorse(data, spawnOptions)
    if IsSpawningMountActive then
        releaseStableDelivery(spawnOptions)
        return
    end
    IsSpawningMountActive = true
    sendingHorse = nil
    followingHorse = nil

    if type(data) ~= 'table' or not data.model then
        DBG:Error('Cannot spawn horse: invalid horse data received.')
        releaseStableDelivery(spawnOptions)
        finishSpawning()
        return
    end

    if type(StopFlamingHooves) == 'function' then StopFlamingHooves(false) end
    deleteHorseEntity(MyHorse)
    MyHorse = 0

    local horseStateBag = LocalPlayer.state.HorseData
    local oldNetId = horseStateBag and horseStateBag.MyHorse

    if oldNetId and oldNetId ~= 0 and NetworkDoesNetworkIdExist(oldNetId) then
        local historicalEntity = NetworkGetEntityFromNetworkId(oldNetId)

        if horseExists(historicalEntity) then
            deleteHorseEntity(historicalEntity)
            DBG:Info('State Bag Purge: Removed old horse NetID reference.')
        end
    end
    setHorseStateNetId(0)

    MyHorseId = data.id
    HorseName = data.name
    MyHorseAging = {
        agingEnabled = data.agingEnabled == true,
        bornAt = data.bornAt,
        naturalDeathAt = data.naturalDeathAt,
        ageYears = tonumber(data.ageYears),
        lifeStage = data.lifeStage,
    }
    local modelName = data.model
    local modelHash = joaat(modelName)

    if not LoadModel(modelHash, modelName) then
        DBG:Error('Failed to load horse model:', data.model)
        releaseStableDelivery(spawnOptions)
        finishSpawning()
        return
    end

    local parentMappingData = Horses.ModelToBreedMap and Horses.ModelToBreedMap[modelName]
    MyHorseBreed = parentMappingData and parentMappingData.breed or 'Unknown'

    local breedCatalogData = MyHorseBreed and Horses.BreedCatalog[MyHorseBreed]
    local colorData = breedCatalogData and breedCatalogData.colors and breedCatalogData.colors[modelName]
    MyHorseColor = colorData and colorData.color or 'Unknown'

    local player = PlayerId()
    local playerPed = PlayerPedId()

    local stableSite = type(spawnOptions) == 'table' and Stables[spawnOptions.stableSite]
    local stableSpawn = stableSite and stableSite.horse
    local spawnPosition = stableSpawn and stableSpawn.coords or calculateSpawnPosition(playerPed)
    if not spawnPosition then
        DBG:Error('Failed to find a valid ground or node position for horse spawn.')
        releaseStableDelivery(spawnOptions)
        finishSpawning(modelHash)
        return
    end

    if stableSpawn then
        local clearance = tonumber((Config.stable.delivery or {}).spawnClearance) or 4.0
        local deadline = GetGameTimer() + 5000
        while not isStableSpawnClear(spawnPosition, clearance) and GetGameTimer() < deadline do Wait(250) end
        if not isStableSpawnClear(spawnPosition, clearance) then
            DBG:Warning(('Stable spawn remained obstructed at site: %s'):format(tostring(spawnOptions.stableSite)))
            Core.NotifyRightTip('The stable exit is obstructed. Please try again.', 4000)
            releaseStableDelivery(spawnOptions)
            finishSpawning(modelHash)
            return
        end
    end

    local spawnHeading = stableSpawn
        and getHeadingToward(stableSpawn.coords, spawnOptions.deliveryDestination, stableSpawn.heading)
        or GetEntityHeading(playerPed)
    local horse = CreatePed(modelHash, spawnPosition.x, spawnPosition.y, spawnPosition.z, spawnHeading, true, false, false, false)
    if not CheckEntityExists(horse) then
        DBG:Error('Failed to spawn horse.')
        releaseStableDelivery(spawnOptions)
        finishSpawning(modelHash)
        return
    end

    MyHorse = horse
    SetModelAsNoLongerNeeded(modelHash)

    if stableSpawn and not data.is_writhing then
        SetEntityAlpha(horse, 0, false)
        SetEntityVisible(horse, false, false)
    end

    if not NetworkGetEntityIsNetworked(horse) then
        NetworkRegisterEntityAsNetworked(horse)
    end

    local netId = NetworkGetNetworkIdFromEntity(horse)
    if netId and netId ~= 0 then
        setHorseStateNetId(netId)
    else
        DBG:Error('Failed to generate a synchronized NetID for the spawned horse!')
        setHorseStateNetId(0)
    end

    -- Base Horse Initialization Natives
    Citizen.InvokeNative(0x9587913B9E772D29, horse, 0) -- PlaceEntityOnGroundProperly
    Citizen.InvokeNative(0x283978A15512B2FE, horse, true) -- SetRandomOutfitVariation

    if data.gender == 'female' then
        Citizen.InvokeNative(0x5653AB26C82938CF, horse, 41611, 1.0) -- SetCharExpression
        Citizen.InvokeNative(0xCC8CA3E88256E58F, horse, false, true, true, true, false) -- UpdatePedVariation
    end

    Citizen.InvokeNative(0xD2CB0FB0FDCB473D, playerPed, horse) -- SetPedAsSaddleHorseForPlayer
    Citizen.InvokeNative(0x931B241409216C1F, playerPed, horse, false) -- SetPedOwnsAnimal
    Citizen.InvokeNative(0xB8B6430EAD2D2437, horse, `PLAYER_HORSE`) -- SetPedPersonality
    Citizen.InvokeNative(0xE6D4E435B56D5BD0, player, horse) -- SetPlayerOwnsMount

    -- Prompt overrides - ModifyPlayerUiPromptForPed
    Citizen.InvokeNative(0xA3DB37EDF9A74635, player, horse, 49, 1, true) -- HORSE_BRUSH
    Citizen.InvokeNative(0xA3DB37EDF9A74635, player, horse, 50, 1, true) -- HORSE_FEED
    if not Config.stable.fleeEnabled then
        Citizen.InvokeNative(0xA3DB37EDF9A74635, player, horse, 33, 1, true) -- HORSE_FLEE
    end

    -- Process Handlers
    applyHorseAttributes(horse, data.stats, data.xp, data.current_health, data.current_stamina, data)
    applyConfigFlags(horse)

    -- Blip Registration
    local horseBlip = Citizen.InvokeNative(0x23f74c2fda6e7c61, -1230993421, horse) -- BlipAddForEntity
    Citizen.InvokeNative(0x9CB1A1623062F402, horseBlip, HorseName) -- SetBlipName
    SetPedPromptName(horse, HorseName)

    -- Event Triggering Pipeline
    TriggerServerEvent('bcc-horses:RegisterInventory', MyHorseId)
    Entity(horse).state:set('myHorseId', MyHorseId, true)

    TriggerEvent('bcc-horses:HorsePrompts')

    HorseAppearance.resetTracking(horse)
    HorseAppearance.applyLoadout(horse, data.tackLoadout or {})
    EmitHorseLifecycleEvent('bcc-horses:client:horseSpawned')

    -- Reset Local State Flags
    InWrithe, UsingLantern = false, false
    finishSpawning()

    if data.is_writhing then
        releaseStableDelivery(spawnOptions)
        ForceHorseIntoWritheState(horse)
        return
    end

    if stableSpawn then
        revealStableDeliveryHorse(horse, stableSpawn, spawnOptions)
    else
        sendHorseToPlayer(horse)
    end
end

RegisterNetEvent('bcc-horses:HorsesDiedOfOldAge', function(horseIds)
    local expired = {}
    for _, horseId in ipairs(type(horseIds) == 'table' and horseIds or {}) do
        local numericId = tonumber(horseId)
        if numericId then expired[numericId] = true end
    end

    if MyHorseId and expired[tonumber(MyHorseId)] then
        deleteHorseEntity(MyHorse)
        MyHorse = 0
        MyHorseId = nil
        MyHorseAging = {}
        IsMyHorseActive = false
        setHorseStateNetId(0)
        Core.NotifyRightTip('Your horse has passed away from old age.', 6000)
    end

    if type(MyHorsesData) == 'table' then
        for index = #MyHorsesData, 1, -1 do
            if expired[tonumber(MyHorsesData[index].id)] then table.remove(MyHorsesData, index) end
        end
    end
end)
