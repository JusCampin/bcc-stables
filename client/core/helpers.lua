local isLightingThreadRunning = false
local isHorseEntitySyncRunning = false
local pendingHorseEntityNetId = nil

local DEFAULT_TIMEOUT_MS = 5000
local ENTITY_REGISTRATION_TIMEOUT_MS = 500
local HORSE_SYNC_ATTEMPTS = 30
local HORSE_SYNC_INTERVAL_MS = 500
local NETWORK_CONTROL_RETRY_MS = 100
local UNEMPLOYED_JOB = 'unemployed'

local function getCharacterJob()
    local character = LocalPlayer.state.Character
    if not character then return nil, 0 end

    return character.Job or UNEMPLOYED_JOB, tonumber(character.Grade) or 0
end

local function hasRequiredGrade(jobGrades, job, grade)
    local jobConfig = jobGrades and jobGrades[job]
    local requiredGrade = type(jobConfig) == 'table' and jobConfig.minimumGrade or jobConfig
    return requiredGrade ~= nil and grade >= requiredGrade
end

---Internal helper to check if the player's active job matches the trainer criteria
---@return boolean
local function hasTrainerJobRequirements()
    local job, grade = getCharacterJob()
    return job ~= nil and hasRequiredGrade(Config.training.trainerJobs, job, grade)
end

---Checks if the player is allowed to train horses based on the active config state
---@return boolean
function CanPlayerTrainHorses()
    if Config.training.trainerOnly then
        return hasTrainerJobRequirements()
    end

    return true
end

--Checks if the player has permission to manage wild horses (selling/registering)
---@return boolean
function CanPlayerManageTamedHorses()
    if Config.training.tamingTrainerOnly then
        return hasTrainerJobRequirements()
    end

    return true
end

---Checks if a player is blocked from accessing the current stable node
---@return boolean -- True if the player is BLOCKED, False if they are allowed in
function IsPlayerBlockedFromCurrentTrainerShop()
    local currentStableNode = Stables[Site]

    if not currentStableNode or not currentStableNode.trainerBuy then
        return false
    end

    return not hasTrainerJobRequirements()
end

-- Job check for general stable access and available horses
function CheckPlayerJob(siteId)
    JobMatchedHorses = {}

    local activeJob, activeGrade = getCharacterJob()
    if not activeJob then return false end

    local stableNode = Stables[siteId]
    if not stableNode then return false end

    local shop = stableNode.shop
    local isAuthorized = hasRequiredGrade(shop and shop.jobs, activeJob, activeGrade)

    if activeJob ~= UNEMPLOYED_JOB then
        JobMatchedHorses = Horses.ModelJobLocks and Horses.ModelJobLocks.Jobs and Horses.ModelJobLocks.Jobs[activeJob] or {}
    end

    if shop and shop.jobsEnabled and not isAuthorized then
        Core.NotifyRightTip(_U('needJob') or 'You do not have the required job to access this stable!', 4000)
        return false
    end

    return true
end

---@param targetNetId number
RegisterNetEvent('bcc-horses:UpdateMyHorseEntity', function(targetNetId)
    if not targetNetId or targetNetId == 0 then return end

    pendingHorseEntityNetId = targetNetId
    if isHorseEntitySyncRunning then return end

    isHorseEntitySyncRunning = true

    CreateThread(function()
        while pendingHorseEntityNetId do
            local netId = pendingHorseEntityNetId
            pendingHorseEntityNetId = nil
            local isEntityFound = false
            local remainingAttempts = HORSE_SYNC_ATTEMPTS

            while remainingAttempts > 0 do
                if pendingHorseEntityNetId and pendingHorseEntityNetId ~= netId then
                    break
                end

                if NetworkDoesNetworkIdExist(netId) then
                    local resolvedEntity = NetworkGetEntityFromNetworkId(netId)

                    if resolvedEntity and resolvedEntity ~= 0 and DoesEntityExist(resolvedEntity) then
                        MyHorse = resolvedEntity
                        local entityState = Entity(resolvedEntity).state
                        MyHorseId = (entityState and entityState.myHorseId) or MyHorseId
                        IsHorseFleeingState = false
                        isEntityFound = true

                        if pendingHorseEntityNetId == netId then
                            pendingHorseEntityNetId = nil
                        end

                        DBG:Info('Horse entity handle successfully re-synchronized across server-instance boundaries: ', resolvedEntity)
                        break
                    end
                end

                remainingAttempts = remainingAttempts - 1
                Wait(HORSE_SYNC_INTERVAL_MS)
            end

            if not isEntityFound and not pendingHorseEntityNetId then
                DBG:Warning('Instance Sync Timeout: The mount asset entity failed to stream back into local client RAM.')
            end
        end

        isHorseEntitySyncRunning = false
    end)
end)

function GetControlOfHorse(timeoutMs)
    local horse = MyHorse
    if not horse or horse == 0 or not DoesEntityExist(horse) then return false end

    local timeout = tonumber(timeoutMs) or DEFAULT_TIMEOUT_MS
    local startTime = GetGameTimer()

    while MyHorse == horse and DoesEntityExist(horse) do
        if NetworkHasControlOfEntity(horse) then
            return true
        end

        if GetGameTimer() - startTime >= timeout then
            break
        end

        NetworkRequestControlOfEntity(horse)
        Wait(NETWORK_CONTROL_RETRY_MS)
    end

    if MyHorse ~= horse or not DoesEntityExist(horse) then
        return false
    end

    DBG:Warning('Timed out while requesting network control of the active horse.')
    return false
end

function LoadModel(model, modelName)
    if not IsModelValid(model) then
        DBG:Error('Invalid horse model:', modelName)
        return false
    end

    if not HasModelLoaded(model) then
        RequestModel(model)

        local startTime = GetGameTimer()

        while not HasModelLoaded(model) do
            if GetGameTimer() - startTime > DEFAULT_TIMEOUT_MS then
                DBG:Error('Failed to load horse model:', modelName)
                return false
            end
            Wait(0)
        end
    end

    return true
end

---Remove dirt, decals, and blood without removing the horse's wet appearance.
---@param horse integer
---@return boolean cleaned
function CleanHorseAppearance(horse)
    if not horse or horse == 0 or not DoesEntityExist(horse) then
        return false
    end

    Citizen.InvokeNative(0x6585D955A68452A5, horse) -- ClearPedEnvDirt
    Citizen.InvokeNative(0x523C79AEEFCC4A2A, horse, 10, 'ALL') -- ClearPedDamageDecalByZone
    Citizen.InvokeNative(0x8FE22675A5A45817, horse) -- ClearPedBloodDamage
    return true
end

function LoadAnim(dict)
    RequestAnimDict(dict)
    local startTime = GetGameTimer()

    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() - startTime > DEFAULT_TIMEOUT_MS then
            DBG:Error(('Failed to load animation dictionary: %s'):format(dict))
            return false
        end
        Wait(0)
    end
    return true
end

function CheckEntityExists(entity)
    if not entity or entity == 0 then
        DBG:Error('Entity instantiation failed immediately. Invalid entity handle received.')
        return false
    end

    if DoesEntityExist(entity) then
        return true
    end

    local startTime = GetGameTimer()

    while not DoesEntityExist(entity) do
        if GetGameTimer() - startTime > ENTITY_REGISTRATION_TIMEOUT_MS then
            DBG:Error(('Entity registration timed out. Handle ID: %s'):format(entity))
            return false
        end
        Wait(0)
    end

    return true
end

function GetClosestPlayer()
    local players = GetActivePlayers()
    local localPlayer = PlayerId()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local closestDistance = math.huge
    local closestPlayer = nil

    for _, playerId in ipairs(players) do
        if playerId ~= localPlayer then
            local targetCoords = GetEntityCoords(GetPlayerPed(playerId))
            local distance = #(playerCoords - targetCoords)
            if distance < closestDistance then
                closestPlayer = playerId
                closestDistance = distance
            end
        end
    end

    return closestPlayer, closestDistance
end

---@param onSuccess function
---@param onFailure function|nil
function FetchRosterAndAction(onSuccess, onFailure)
    Core.Callback.TriggerAsync('bcc-horses:GetMyHorsesData', function(horseData)
        if horseData then
            MyHorsesData = horseData

            if type(onSuccess) == 'function' then
                onSuccess(horseData)
            end
        else
            DBG:Warning('Failed to retrieve stable roster from server!')
            MyHorsesData = {}

            if type(onFailure) == 'function' then
                onFailure()
            end
        end
    end)
end

---@param horse integer
---@param xp number|nil
---@return integer level
---@return integer currentXp
---@return table<integer, number|nil> thresholds
function GetHorseBondingData(horse, xp)
    local currentXp = math.max(0, math.floor(tonumber(xp) or 0))
    local level = 0
    local thresholds = {}

    if not horse or horse == 0 or not DoesEntityExist(horse) then
        return level, currentXp, thresholds
    end

    local model = GetEntityModel(horse)
    for rank = 1, 4 do
        local requirement = tonumber(Citizen.InvokeNative(0x94A7F191DB49A44D, model, 7, rank))
        thresholds[rank] = requirement and math.max(0, math.floor(requirement)) or nil
    end

    for rank = 1, 4 do
        local requirement = thresholds[rank]
        if requirement and requirement > 0 and currentXp >= requirement then
            level = rank
        end
    end

    return level, currentXp, thresholds
end

--- Update the locally selected horse and optionally persist the selection.
---@param horseId number|string
---@param persist boolean|nil
---@return boolean
function SetSelectedHorseLocally(horseId, persist)
    local selectedHorseId = tonumber(horseId)
    if not selectedHorseId then return false end

    MyHorseId = selectedHorseId

    if MyHorsesData then
        for _, horse in ipairs(MyHorsesData) do
            horse.is_selected = tonumber(horse.id) == selectedHorseId
        end
    end

    if persist then
        TriggerServerEvent('bcc-horses:SelectActiveHorse', selectedHorseId)
    end

    return true
end

--- Dismount the player from a temporary tamed horse and remove its entity.
--- Must be called from a yieldable context such as CreateThread.
---@param mount number
---@param timeoutMs number|nil
function RemoveTamedHorseEntity(mount, timeoutMs)
    if not mount or mount == 0 or not DoesEntityExist(mount) then return end

    local playerPed = PlayerPedId()
    if IsPedOnMount(playerPed) and GetMount(playerPed) == mount then
        Citizen.InvokeNative(0x48E92D3DDE23C23A, playerPed, 0, 0, 0, 0, mount) -- TaskDismountAnimal

        local startTime = GetGameTimer()
        local timeout = tonumber(timeoutMs) or DEFAULT_TIMEOUT_MS
        while IsPedOnMount(playerPed) and GetGameTimer() - startTime < timeout do
            Wait(NETWORK_CONTROL_RETRY_MS)
        end
    end

    if DoesEntityExist(mount) then
        SetEntityAsMissionEntity(mount, true, true)
        DeleteEntity(mount)
    end
end

function CameraLighting()
    if isLightingThreadRunning then return end
    isLightingThreadRunning = true

    CreateThread(function()
        local preview = StableUI.GetPreviewHorseConfig()
        if not preview then
            isLightingThreadRunning = false
            return
        end
        local coords = preview.coords

        while Cam do
            Wait(0)
            Citizen.InvokeNative(0xD2D9E04C0DF927F4, coords.x, coords.y, coords.z + 3.0, 130, 130, 85, 4.0, 15.0) -- DrawLightWithRange
        end

        isLightingThreadRunning = false
    end)
end
