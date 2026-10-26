local HORSE_INFO_MAX_DISTANCE = 3.0
local NOTIFICATION_DURATION = 4000

local NATIVE = {
    setAnimalIsWild = 0xAEB97D84CDF3C00B,
    clearActiveAnimalOwner = 0xBCC76708E5677E1D,
    setAnimalTuningBoolParam = 0x9FF1E042FA597187,
    taskAnimalWrithe = 0x8C038A39C4A4B6D6,
}

local function notifyNoHorse()
    Core.NotifyRightTip(_U('noHorse'), NOTIFICATION_DURATION)
end

---@param commandHandler function
---@return function
local function developerCommand(commandHandler)
    return function()
        if not Config.development.enabled then
            print('Command used in Developer Mode Only!')
            return
        end

        commandHandler()
    end
end

RegisterCommand(Config.commands.respawnHorse, function()
    IsSpawningMountActive = false
    WhistleSpawn()
end, false)

RegisterCommand(Config.commands.setHorseWild, developerCommand(function()
    local mount = GetMount(PlayerPedId())
    if mount == 0 or not DoesEntityExist(mount) then
        notifyNoHorse()
        return
    end

    Citizen.InvokeNative(NATIVE.setAnimalIsWild, mount, true)
    Citizen.InvokeNative(NATIVE.clearActiveAnimalOwner, mount, true)
    Citizen.InvokeNative(NATIVE.setAnimalTuningBoolParam, mount, 97, false)
end), false)

RegisterCommand(Config.commands.setHorseWrithe, developerCommand(function()
    local horse = MyHorse
    if not horse or horse == 0 or not DoesEntityExist(horse) then
        notifyNoHorse()
        return
    end

    Citizen.InvokeNative(NATIVE.taskAnimalWrithe, horse, 0, 0)
end), false)

RegisterCommand(Config.commands.horseInfo, function()
    local horse = MyHorse
    if not horse or horse == 0 or not DoesEntityExist(horse) then
        notifyNoHorse()
        return
    end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local horseCoords = GetEntityCoords(horse)

    if #(playerCoords - horseCoords) > HORSE_INFO_MAX_DISTANCE then
        Core.NotifyRightTip(_U('tooFar'), NOTIFICATION_DURATION)
        return
    end

    HorseInfoMenu()
end, false)
