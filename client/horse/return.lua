local FLEE_DELETE_DISTANCE = 200.0
local FLEE_TIMEOUT_MS = 10000
local DISMOUNT_TIMEOUT_MS = 5000

local function horseExists(horse)
    return horse and horse ~= 0 and DoesEntityExist(horse)
end

local function cancelHorsePassiveInteraction()
    if type(CancelHorsePassiveInteraction) == 'function' then
        local transitionDuration = CancelHorsePassiveInteraction()
        if transitionDuration and transitionDuration > 0 then
            Wait(transitionDuration)
        end
        return
    end

    IsInteractingWithHorse = false
end

local function deleteHorseEntity(horse)
    if not horseExists(horse) then return end

    SetEntityAsMissionEntity(horse, true, true)
    DeleteEntity(horse)
end

local function clearActiveHorse(horse)
    -- Delayed cleanup must not clear a horse that was spawned in the meantime.
    if MyHorse ~= horse then return false end

    LocalPlayer.state.HorseData = { MyHorse = 0 }
    MyHorse = 0
    MyHorseId = nil
    return true
end

function FleeHorse()
    local horse = MyHorse
    if not horseExists(horse) or IsHorseFleeingState then return end

    local returnedHorse = GetActiveHorseData()

    cancelHorsePassiveInteraction()
    if type(StopFlamingHooves) == 'function' then StopFlamingHooves(false) end
    IsHorseFleeingState = true
    SaveHorseStats(false)
    GetControlOfHorse()
    ClearPedTasksImmediately(horse, false, false)

    Citizen.InvokeNative(
        0x22B0D0E37CCB840D,
        horse,
        PlayerPedId(),
        100.0,
        FLEE_TIMEOUT_MS,
        6,
        3.0
    ) -- TaskSmartFleePed
    SetPedKeepTask(horse, true)

    CreateThread(function()
        local startTime = GetGameTimer()

        while horseExists(horse) and GetGameTimer() - startTime < FLEE_TIMEOUT_MS do
            Wait(500)

            local distance = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(horse))
            if distance > FLEE_DELETE_DISTANCE then break end
        end

        deleteHorseEntity(horse)
        IsHorseFleeingState = false

        if clearActiveHorse(horse) then
            EmitHorseLifecycleEvent('bcc-horses:client:horseReturned', returnedHorse)
            DBG:Info('Active mount successfully despawned.')
        end
    end)
end

-- Return horse at a stable with prompt
---@param silent boolean|nil
function ReturnHorse(silent)
    local playerPed = PlayerPedId()
    local horse = MyHorse

    if not horseExists(horse) then
        Core.NotifyRightTip(_U('noHorse'), 4000)
        return
    end

    local returnedHorse = GetActiveHorseData()

    -- Dismount the player if they are currently mounted.
    if Citizen.InvokeNative(0x460BC76A0E10655E, playerPed) then -- IsPedOnMount
        Citizen.InvokeNative(0x48E92D3DDE23C23A, playerPed, 0, 0, 0, 0, horse) -- TaskDismountAnimal
        local dismountDeadline = GetGameTimer() + DISMOUNT_TIMEOUT_MS

        while not Citizen.InvokeNative(0x01FEE67DB37F59B2, playerPed)
            and GetGameTimer() < dismountDeadline do -- IsPedOnFoot
            Wait(10)
        end
    end

    cancelHorsePassiveInteraction()
    if type(StopFlamingHooves) == 'function' then StopFlamingHooves(false) end
    SaveHorseStats(InWrithe)
    GetControlOfHorse()
    deleteHorseEntity(horse)
    clearActiveHorse(horse)
    EmitHorseLifecycleEvent('bcc-horses:client:horseReturned', returnedHorse)

    InWrithe = false
    IsHorseFleeingState = false

    if not silent then Core.NotifyRightTip(_U('horseReturned'), 4000) end
end
