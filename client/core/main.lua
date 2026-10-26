IsHorseFleeingState = false
local horseMonitorGeneration = 0
local stableSnapshot = { site = nil, distance = math.huge, isClosed = false }
local stablePromptStates = { shop = {}, call = {}, returnHorse = {} }

local STABLE_SCAN_INTERVAL_MS <const> = 500
local HORSE_STATE_INTERVAL_MS <const> = 1000
local BLIP_UPDATE_INTERVAL_MS <const> = 5000
local IDLE_PROMPT_INTERVAL_MS <const> = 1000
local HORSE_SAVE_CHECK_INTERVAL_MS <const> = 1000
local DEFAULT_HORSE_SAVE_INTERVAL_MS <const> = 120000
local MINUTES_TO_MS <const> = 60000

local GET_EVENT_AT_INDEX_NATIVE <const> = 0xA85E614430EFF816
local GET_EVENT_DATA_NATIVE <const> = 0x57EC5FA4D4D6AFCA
local EVENT_PED_WHISTLE <const> = 1327216456
local EVENT_HORSE_BROKEN <const> = 218595333
local EVENT_ENTITY_DESTROYED <const> = 2145012826
local SHORT_HORSE_WHISTLE <const> = joaat('WHISTLEHORSESHORT')

---@param entity integer|nil
---@return boolean
local function entityExists(entity)
    return type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity)
end

local function deleteEntity(entity)
    if not entityExists(entity) then return end

    SetEntityAsMissionEntity(entity, true, true)
    DeleteEntity(entity)
end

CreateThread(function()
    local distanceCfg <const> = Config and Config.stable.autoReturn
    local hasDistanceCheck <const> = distanceCfg and distanceCfg.enabled
    local distanceRadius <const> = distanceCfg and tonumber(distanceCfg.maximumDistance) or 100.0
    local distanceRadiusSquared <const> = distanceRadius * distanceRadius
    local lastActiveHorse = 0

    while true do
        local horse = MyHorse
        local isHorseActive = false

        if entityExists(horse) and not IsSpawningMountActive then
            local isAlive = not IsPedDeadOrDying(horse, true) and not IsEntityDead(horse)

            if hasDistanceCheck then
                local playerPed = PlayerPedId()
                local offset = GetEntityCoords(playerPed) - GetEntityCoords(horse)
                local distanceSquared = offset.x * offset.x + offset.y * offset.y + offset.z * offset.z

                if distanceSquared > distanceRadiusSquared then
                    DBG:Info('Active horse out of range. Saving stats and clearing entity.')

                    SaveHorseStats(InWrithe)
                    deleteEntity(horse)

                    if MyHorse == horse then
                        MyHorse = 0
                        MyHorseId = nil
                    end

                    isAlive = false
                end
            end

            if isAlive and not InWrithe then
                isHorseActive = true
            end
        elseif not IsSpawningMountActive
            and not IsPreviewInstanceTransitioning()
            and MyHorse == horse then
            MyHorse = 0
            MyHorseId = nil
        end

        IsMyHorseActive = isHorseActive

        if isHorseActive and horse ~= lastActiveHorse then
            DBG:Info('Healthy horse detected. Initializing tracking loops.')

            if CanPlayerTrainHorses() then
                TriggerEvent('bcc-horses:TravelXpMonitor')
            end

            if (tonumber(Config.care.saveIntervalMinutes) or 0) > 0 then
                TriggerEvent('bcc-horses:HorseMonitor')
            end

            if Config.display.horseTag.enabled then
                TriggerEvent('bcc-horses:HorseTag')
            end
        end

        lastActiveHorse = isHorseActive and horse or 0

        Wait(HORSE_STATE_INTERVAL_MS)
    end
end)

local function isShopClosed(shopCfg, hour)
    hour = hour or GetClockHours()
    local hoursActive = shopCfg.shop.hours.active

    if not hoursActive then
        return false
    end

    local openHour = shopCfg.shop.hours.open
    local closeHour = shopCfg.shop.hours.close

    if openHour < closeHour then
        return hour < openHour or hour >= closeHour
    else
        return hour < openHour and hour >= closeHour
    end
end

---@param prompt integer
---@param stateKey 'shop'|'call'|'returnHorse'
---@param visible boolean|nil
---@param enabled boolean
local function setStablePromptState(prompt, stateKey, visible, enabled)
    local state = stablePromptStates[stateKey]

    if visible ~= nil and state.visible ~= visible then
        UiPromptSetVisible(prompt, visible)
        state.visible = visible
    end

    if state.enabled ~= enabled then
        UiPromptSetEnabled(prompt, enabled)
        state.enabled = enabled
    end
end

local function manageStableBlip(site, closed)
    local siteCfg = Stables[site]

    if (closed and not siteCfg.blip.showClosed) or (not siteCfg.blip.show) then
        if siteCfg.Blip then
            RemoveBlip(siteCfg.Blip)
            siteCfg.Blip = nil
        end
        siteCfg.lastBlipColor = nil
        return
    end

    if not siteCfg.Blip then
        siteCfg.Blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, siteCfg.npc.coords.x, siteCfg.npc.coords.y, siteCfg.npc.coords.z) -- BlipAddForCoords
        SetBlipSprite(siteCfg.Blip, siteCfg.blip.sprite, true)
        Citizen.InvokeNative(0x9CB1A1623062F402, siteCfg.Blip, siteCfg.blip.name) -- SetBlipName
        siteCfg.lastBlipColor = nil
    end

    local color = siteCfg.blip.color.open
    if siteCfg.shop.jobsEnabled then color = siteCfg.blip.color.job end
    if closed then color = siteCfg.blip.color.closed end

    if siteCfg.lastBlipColor == color then return end

    local colorModifier = Config.map.blipColors[color]
    if colorModifier then
        Citizen.InvokeNative(0x662D364ABF16DE2F, siteCfg.Blip, joaat(colorModifier)) -- BlipAddModifier
    else
        DBG:Warning('Blip color not defined for color: ' .. tostring(color))
    end

    siteCfg.lastBlipColor = color
end

local function addStableNpc(site)
    local siteCfg = Stables[site]
    if siteCfg.NPC then return end

    local modelName = siteCfg.npc.model
    local model = joaat(modelName)

    if not LoadModel(model, modelName) then return end

    siteCfg.NPC = CreatePed(model, siteCfg.npc.coords.x, siteCfg.npc.coords.y, siteCfg.npc.coords.z - 1.0, siteCfg.npc.heading, false, true, true, true)
    if not entityExists(siteCfg.NPC) then
        siteCfg.NPC = nil
        SetModelAsNoLongerNeeded(model)
        DBG:Warning(('Failed to create stable NPC for site: %s'):format(tostring(site)))
        return
    end

    Citizen.InvokeNative(0x283978A15512B2FE, siteCfg.NPC, true) -- SetRandomOutfitVariation

    TaskStartScenarioInPlace(siteCfg.NPC, `WORLD_HUMAN_WRITE_NOTEBOOK`, -1, true)
    SetEntityCanBeDamaged(siteCfg.NPC, false)
    SetEntityInvincible(siteCfg.NPC, true)
    FreezeEntityPosition(siteCfg.NPC, true)
    SetBlockingOfNonTemporaryEvents(siteCfg.NPC, true)
    SetModelAsNoLongerNeeded(model)
end

local function removeStableNpc(site)
    local siteCfg = Stables[site]
    if siteCfg.NPC then
        deleteEntity(siteCfg.NPC)
        siteCfg.NPC = nil
    end
end

local function clearStableSnapshot()
    stableSnapshot.site = nil
    stableSnapshot.distance = math.huge
    stableSnapshot.isClosed = false
end

local function refreshStableSnapshot()
    local playerPed = PlayerPedId()
    if InMenu or IsEntityDead(playerPed) then
        clearStableSnapshot()
        return
    end

    local playerCoords = GetEntityCoords(playerPed)
    local hour = GetClockHours()
    local nearestSite = nil
    local nearestDistance = math.huge
    local nearestClosed = false

    for site, siteCfg in pairs(Stables) do
        local distance = #(playerCoords - siteCfg.npc.coords)
        local isClosed = isShopClosed(siteCfg, hour)

        if distance > siteCfg.npc.distance or isClosed then
            removeStableNpc(site)
        elseif siteCfg.npc.active then
            addStableNpc(site)
        end

        if distance < nearestDistance then
            nearestSite = site
            nearestDistance = distance
            nearestClosed = isClosed
        end
    end

    stableSnapshot.site = nearestSite
    stableSnapshot.distance = nearestDistance
    stableSnapshot.isClosed = nearestClosed
end

local function getInteractionMount(playerPed)
    local mount = Citizen.InvokeNative(0xE7E11B8DCBED1058, playerPed) -- GetMount
    if mount and mount ~= 0 then return mount end

    if Citizen.InvokeNative(0xEFC4303DDC6E60D3, playerPed) then -- IsPedLeadingHorse
        return Citizen.InvokeNative(0x693126B5D0457D0D, playerPed, Citizen.ResultAsInteger()) -- GetLastLedMount
    end

    return 0
end

local function isTamedWildMount(mount)
    if not mount or mount == 0 or mount == MyHorse or not DoesEntityExist(mount) then
        return false
    end

    return NetworkGetNetworkIdFromEntity(mount) == Entity(mount).state.netId
end

---@param siteCfg table
---@param isClosed boolean
---@param isRidingTamedWild boolean
---@param isHorseSpawned boolean
---@param closedCall boolean
---@param closedReturn boolean
local function updateStablePrompts(siteCfg, isClosed, isRidingTamedWild, isHorseSpawned, closedCall, closedReturn)
    local promptHeader

    if isClosed then
        promptHeader = string.format(
            '%s%s%s%s%s%s',
            siteCfg.shop.name,
            _U('hours') or ' Hours: ',
            siteCfg.shop.hours.open,
            _U('to') or ' to ',
            siteCfg.shop.hours.close,
            _U('hundred') or '00'
        )
    else
        promptHeader = isRidingTamedWild and 'Wild Horse Management' or (siteCfg.shop.prompt or 'Stable')
    end

    UiPromptSetActiveGroupThisFrame(ShopGroup, CreateVarString(10, 'LITERAL_STRING', promptHeader), 1, 0, 0, 0)
    setStablePromptState(OpenShop, 'shop', nil, not isClosed)

    local canCall = not isHorseSpawned and (not isClosed or closedCall)
    setStablePromptState(OpenCall, 'call', canCall, canCall)

    local canReturn = isHorseSpawned and (not isClosed or closedReturn)
    setStablePromptState(OpenReturn, 'returnHorse', canReturn, canReturn)
end

local function runStableAction(site, action)
    local siteCfg = Stables[site]
    if not siteCfg.shop.jobsEnabled or CheckPlayerJob(site) then
        action(site)
    end
end

local function handleStablePromptAction(site, isClosed, isRidingTamedWild, isHorseSpawned, closedCall, closedReturn, mount)
    if not isClosed and UiPromptHasStandardModeCompleted(OpenShop, 0) then
        if isRidingTamedWild then
            Site = site
            StableName = Stables[Site].shop.name
            BuildWildHorsePage(mount)
            StableMenu:Open({ startupPage = Pages.wild_horse })
        else
            runStableAction(site, OpenStable)
        end
        return
    end

    if not isHorseSpawned and UiPromptHasStandardModeCompleted(OpenCall, 0) then
        if not isClosed or closedCall then
            runStableAction(site, CallActiveHorseAtStable)
        end
        return
    end

    if isHorseSpawned and UiPromptHasStandardModeCompleted(OpenReturn, 0) then
        if not isClosed or closedReturn then
            runStableAction(site, ReturnHorse)
        end
    end
end

CreateThread(function()
    while true do
        local hour = GetClockHours()

        for site, siteCfg in pairs(Stables) do
            manageStableBlip(site, isShopClosed(siteCfg, hour))
        end
        Wait(BLIP_UPDATE_INTERVAL_MS)
    end
end)

CreateThread(function()
    while true do
        refreshStableSnapshot()
        Wait(STABLE_SCAN_INTERVAL_MS)
    end
end)

CreateThread(function()
    StartPrompts()
    local closedCall <const> = Config.stable.whileClosed.callHorse == true
    local closedReturn <const> = Config.stable.whileClosed.returnHorse == true

    while true do
        local playerPed = PlayerPedId()
        local sleep = IDLE_PROMPT_INTERVAL_MS

        local site = stableSnapshot.site
        if not InMenu and not IsEntityDead(playerPed) and site then
            local siteCfg = Stables[site]
            local isClosed = stableSnapshot.isClosed

            if stableSnapshot.distance <= siteCfg.shop.distance then
                sleep = 0
                local mount = getInteractionMount(playerPed)
                local isRidingTamedWild = isTamedWildMount(mount)
                local isHorseSpawned = entityExists(MyHorse)

                updateStablePrompts(siteCfg, isClosed, isRidingTamedWild, isHorseSpawned, closedCall, closedReturn)
                handleStablePromptAction(site, isClosed, isRidingTamedWild, isHorseSpawned, closedCall, closedReturn, mount)
            end
        end

        Wait(sleep)
    end
end)

local function getEventData(eventGroup, eventIndex, dataSize)
    local buffer = CreateEventDataBuffer(dataSize * 8)
    local hasData = Citizen.InvokeNative(
        GET_EVENT_DATA_NATIVE,
        eventGroup,
        eventIndex,
        buffer:Buffer(),
        dataSize
    )

    return hasData and buffer or nil
end

local function handleWhistleEvent(eventIndex)
    local eventData = getEventData(0, eventIndex, 2)
    if not eventData or eventData:GetInt32(0) ~= PlayerPedId() then return end

    if eventData:GetInt32(8) == SHORT_HORSE_WHISTLE then
        DBG:Info('Whistle Horse')
        TriggerEvent('bcc-horses:WhistleHorse')
    else
        DBG:Info('Follow Whistle Horse')
        TriggerEvent('bcc-horses:LongWhistleHorse')
    end
end

local function handleHorseBrokenEvent(eventIndex)
    local eventData = getEventData(0, eventIndex, 3)
    if not eventData or eventData:GetInt32(16) ~= 2 then return end

    local horse = eventData:GetInt32(8)
    if type(horse) ~= 'number' or not entityExists(horse) then return end

    local netId = NetworkGetNetworkIdFromEntity(horse)
    if type(netId) ~= 'number' or netId == 0 then return end

    Entity(horse).state:set('netId', netId, true)
end

local function handleEntityDestroyedEvent(eventIndex)
    local eventData = getEventData(0, eventIndex, 9)
    if eventData and eventData:GetInt32(0) == MyHorse then
        CreateThread(function()
            TriggerEvent('bcc-horses:ManageHorseDeath')
        end)
    end
end

local gameEventHandlers <const> = {
    [EVENT_PED_WHISTLE] = handleWhistleEvent,
    [EVENT_HORSE_BROKEN] = handleHorseBrokenEvent,
    [EVENT_ENTITY_DESTROYED] = handleEntityDestroyedEvent
}

-- Listen for relevant game events every frame.
CreateThread(function()
    while true do
        Wait(0)

        local eventCount = GetNumberOfEvents(0)
        for eventIndex = 0, eventCount - 1 do
            local eventHash = Citizen.InvokeNative(GET_EVENT_AT_INDEX_NATIVE, 0, eventIndex)
            local handler = gameEventHandlers[eventHash]

            if handler then
                handler(eventIndex)
            end
        end
    end
end)

AddEventHandler('bcc-horses:HorseMonitor', function()
    horseMonitorGeneration = horseMonitorGeneration + 1
    local generation = horseMonitorGeneration
    local monitoredHorse = MyHorse

    CreateThread(function()
        local saveInterval = tonumber(Config.care.saveIntervalMinutes)
        local baseInterval = saveInterval and saveInterval > 0
            and saveInterval * MINUTES_TO_MS
            or DEFAULT_HORSE_SAVE_INTERVAL_MS
        local countdown = baseInterval

        while generation == horseMonitorGeneration
            and IsMyHorseActive
            and MyHorse == monitoredHorse
        do
            Wait(HORSE_SAVE_CHECK_INTERVAL_MS)

            if generation ~= horseMonitorGeneration
                or not IsMyHorseActive
                or MyHorse ~= monitoredHorse
            then
                break
            end

            if countdown <= 0 then
                if not IsHorseFleeingState and not IsInteractingWithHorse then
                    SaveHorseStats(InWrithe)
                end

                countdown = baseInterval
            else
                countdown = countdown - HORSE_SAVE_CHECK_INTERVAL_MS
            end
        end
    end)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    ClearPedTasksImmediately(PlayerPedId())
    DisplayRadar(true)

    deleteEntity(ShopEntity)
    deleteEntity(MyEntity)
    deleteEntity(MyHorse)
    ShopEntity = 0
    MyEntity = 0
    MyHorse = 0

    for _, siteCfg in pairs(Stables) do
        if siteCfg.Blip then
            RemoveBlip(siteCfg.Blip)
            siteCfg.Blip = nil
        end
        if siteCfg.NPC then
            deleteEntity(siteCfg.NPC)
            siteCfg.NPC = nil
        end
    end

    CleanupAnimalInfoHud()
end)
