local DEATH_STATE <const> = {
    DOWNED = 'killed',
    KILLED = 'mercy_killed',
    REVIVED = 'revived',
}

local isDeathProcessingActive = false

local function isValidHorse(horse)
    return horse and horse ~= 0 and DoesEntityExist(horse)
end

local function setDeathProcessing(active)
    isDeathProcessingActive = active
end

local function persistDeathState(state)
    if not MyHorseId then return false end

    return Core.Callback.TriggerAwait('bcc-horses:TransitionHorseDeathState', MyHorseId, state) == true
end

local function deleteActiveHorse()
    local horse = MyHorse
    if isValidHorse(horse) then
        SetEntityAsMissionEntity(horse, true, true)
        DeleteEntity(horse)
    end

    InWrithe = false
end

---@param horseEntity integer
---@return boolean
function ForceHorseIntoWritheState(horseEntity)
    if not isValidHorse(horseEntity) then return false end

    InWrithe = true

    ClearPedTasksImmediately(horseEntity)
    Citizen.InvokeNative(0x71BC8E838B9C6035, horseEntity)             -- ResurrectPed
    SetEntityHealth(horseEntity, 150)                                 -- Tiny health buffer
    Citizen.InvokeNative(0x1913FE4CBF41C463, horseEntity, 136, true)  -- SetPedConfigFlag / CannotBeMounted
    Citizen.InvokeNative(0x8C038A39C4A4B6D6, horseEntity, 0, 0)       -- TaskAnimalWrithe
    Wait(100)
    Citizen.InvokeNative(0x925A160133003AC6, horseEntity, true)       -- SetPausePedWritheBleedout

    if type(RemoveHorsePrompts) == 'function' then RemoveHorsePrompts() end

    Core.NotifyRightTip(_U('horseWrithe') or 'Your horse is severely injured!', 4000)
    return true
end

local function downHorse()
    if not ForceHorseIntoWritheState(MyHorse) then return end

    persistDeathState(DEATH_STATE.DOWNED)
    SaveHorseStats(true)
    Wait(3000)
end

local function killHorse(state)
    if Config.death.permanentDeath or Config.death.deselectOnDeath then
        Core.NotifyRightTip(_U('horseDied'), 4000)
    end

    persistDeathState(state)
    SaveHorseStats(true)
    Wait(5000)
    deleteActiveHorse()
end

AddEventHandler('bcc-horses:ManageHorseDeath', function()
    if isDeathProcessingActive then return end
    setDeathProcessing(true)

    if not Config.death.writheEnabled then
        killHorse(DEATH_STATE.DOWNED)
    elseif InWrithe then
        killHorse(DEATH_STATE.KILLED)
    else
        downHorse()
    end

    setDeathProcessing(false)
end)

AddEventHandler('bcc-horses:ReviveHorse', function()
    if isDeathProcessingActive or not InWrithe or not isValidHorse(MyHorse) or IsEntityDead(MyHorse) then return end
    setDeathProcessing(true)

    local horse = MyHorse
    local horseId = MyHorseId
    local playerPed = PlayerPedId()

    if not Core.Callback.TriggerAwait('bcc-horses:HorseReviveItem') then
        Core.NotifyRightTip(_U('noReviver'), 4000)
        setDeathProcessing(false)
        return
    end

    ClearPedTasks(playerPed)
    Citizen.InvokeNative(0x356088527D9EBAAD, playerPed, horse, `s_inv_horsereviver01x`) -- TaskReviveTarget
    Wait(5500)

    if not isValidHorse(horse) or MyHorse ~= horse or MyHorseId ~= horseId then
        setDeathProcessing(false)
        return
    end

    -- Re-check and consume on the server after the animation. This closes the
    -- item-check race without letting the client choose which item is removed.
    local revived = Core.Callback.TriggerAwait('bcc-horses:TransitionHorseDeathState', horseId, DEATH_STATE.REVIVED)
    if not revived then
        ClearPedTasks(playerPed)
        Core.NotifyRightTip(_U('noReviver'), 4000)
        setDeathProcessing(false)
        return
    end

    Citizen.InvokeNative(0x1913FE4CBF41C463, horse, 136, false) -- Remove CannotBeMounted restriction
    ClearPedTasks(horse)
    ClearPedTasks(playerPed)
    SetEntityHealth(horse, GetEntityMaxHealth(horse))

    local currentHealthLevel = tonumber(MyHorseStats.health) or 0
    local currentStaminaLevel = tonumber(MyHorseStats.stamina) or 0
    AdjustHorseCores(0, (currentHealthLevel + 1) * 10)
    AdjustHorseCores(1, (currentStaminaLevel + 1) * 10)

    InWrithe = false
    IsMyHorseActive = true
    SaveHorseStats(false)
    setDeathProcessing(false)
end)
