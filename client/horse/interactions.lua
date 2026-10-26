IsInteractingWithHorse = false

local passiveInteractionToken = 0
local passiveInteractionPhase = 'none'
local passiveInteractionAction = 'none'
local passiveInteractionHorse = 0
local isDeferredMountPending = false
local groundDrinkToken = 0
local groundDrinkPhase = 'none'
local groundDrinkHorse = 0
local cancelGroundHorseDrinking
local lanternHorse = 0
local passiveExitPromptGroup = GetRandomIntInRange(0, 0xffffff)
local passiveExitPrompt = 0
local visiblePassiveExitPrompt = 'none'

local INTERACTION_DISTANCE <const> = 3.5
local MOUNT_CHECK_DISTANCE <const> = 4.0
local INPUT_ENTER <const> = 0xCEFD9220
local CORE_HEALTH <const> = 0
local CORE_STAMINA <const> = 1
local LANTERN_COMPONENT <const> = 0x635E387C
local FLAMING_HOOVES_FLAG <const> = 207
local HORSE_ACTION_REAR_UP <const> = 1
local DISABLE_SHOCKING_EVENTS_FLAG <const> = 113
local DISABLE_GUNSHOT_FLEE_FLAG <const> = 312
local FORCE_INTERACTION_LOCKON_FLAG <const> = 297
local DISABLE_INTERACTION_LOCKON_FLAG <const> = 301
local BLOCK_HORSE_PROMPTS_FLAG <const> = 412
local HORSE_REST_ENTER_DICT <const> = 'amb_creature_mammal@world_horse_resting@stand_enter'
local HORSE_REST_ENTER_NAME <const> = 'enter'
local HORSE_REST_ANIM_DICT <const> = 'amb_creature_mammal@world_horse_resting@idle'
local HORSE_REST_ANIM_NAME <const> = 'idle_a'
local HORSE_REST_EXIT_DICT <const> = 'amb_creature_mammal@world_horse_resting@stand_exit'
local HORSE_REST_EXIT_NAME <const> = 'exit'
local HORSE_REST_QUICK_EXIT_DICT <const> = 'amb_creature_mammal@world_horse_resting@quick_exit'
local HORSE_REST_QUICK_EXIT_NAME <const> = 'quick_exit'
local HORSE_SLEEP_ENTER_DICT <const> = 'amb_creature_mammal@world_horse_sleeping@stand_enter'
local HORSE_SLEEP_ENTER_NAME <const> = 'enter'
local HORSE_SLEEP_ANIM_DICT <const> = 'amb_creature_mammal@world_horse_sleeping@base'
local HORSE_SLEEP_ANIM_NAME <const> = 'base'
local HORSE_SLEEP_EXIT_DICT <const> = 'amb_creature_mammal@world_horse_sleeping@stand_exit'
local HORSE_SLEEP_EXIT_NAME <const> = 'exit'
local HORSE_SLEEP_QUICK_EXIT_DICT <const> = 'amb_creature_mammal@world_horse_sleeping@quick_exit'
local HORSE_SLEEP_QUICK_EXIT_NAME <const> = 'quick_exit'
local HORSE_WALLOW_ENTER_DICT <const> = 'amb_creature_mammal@world_horse_wallow_shake@stand_enter'
local HORSE_WALLOW_ENTER_NAME <const> = 'enter'
local HORSE_WALLOW_ANIM_DICT <const> = 'amb_creature_mammal@world_horse_wallow_shake@idle'
local HORSE_WALLOW_ANIM_NAME <const> = 'idle_a'
local HORSE_WALLOW_EXIT_DICT <const> = 'amb_creature_mammal@world_horse_wallow_shake@stand_exit'
local HORSE_WALLOW_EXIT_NAME <const> = 'exit'
local HORSE_DRINK_ENTER_DICT <const> = 'amb_creature_mammal@world_horse_drink_ground@stand_enter'
local HORSE_DRINK_ENTER_NAME <const> = 'enter'
local HORSE_DRINK_IDLE_DICT <const> = 'amb_creature_mammal@world_horse_drink_ground@idle'
local HORSE_DRINK_IDLE_NAME <const> = 'idle_a'
local HORSE_DRINK_EXIT_DICT <const> = 'amb_creature_mammal@world_horse_drink_ground@stand_exit'
local HORSE_DRINK_EXIT_NAME <const> = 'exit'
local DEFAULT_TRANSITION_DURATION_MS <const> = 2500

---@param horse integer|nil
---@return boolean
local function horseExists(horse)
    return horse ~= nil and horse ~= 0 and DoesEntityExist(horse)
end

---@param horse integer|nil
---@param enabled boolean
local function setNativeHorseTargeting(horse, enabled)
    if not horseExists(horse) then return end
    Citizen.InvokeNative(0x1913FE4CBF41C463, horse, FORCE_INTERACTION_LOCKON_FLAG, enabled)
    Citizen.InvokeNative(0x1913FE4CBF41C463, horse, DISABLE_INTERACTION_LOCKON_FLAG, not enabled)
    Citizen.InvokeNative(0x1913FE4CBF41C463, horse, BLOCK_HORSE_PROMPTS_FLAG, not enabled)
end

---@param control integer
---@param label string
---@return integer
local function registerPassiveExitPrompt(control, label)
    local prompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(prompt, control)
    UiPromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', label))
    UiPromptSetStandardMode(prompt, true)
    UiPromptSetGroup(prompt, passiveExitPromptGroup, 0)
    UiPromptSetEnabled(prompt, true)
    UiPromptSetVisible(prompt, false)
    UiPromptRegisterEnd(prompt)
    return prompt
end

local function ensurePassiveExitPrompts()
    if passiveExitPrompt ~= 0 then return end
    passiveExitPrompt = registerPassiveExitPrompt(Config.controls.standOrWake, _U('standPrompt') or 'Stand')
end

---@param state 'none'|'rest'|'sleep'|'wallow'
local function setPassiveExitPromptVisibility(state)
    if visiblePassiveExitPrompt == state then return end
    visiblePassiveExitPrompt = state

    if passiveExitPrompt ~= 0 then
        local label = state == 'sleep' and _U('wakeHorsePrompt') or _U('standPrompt')
        UiPromptSetText(passiveExitPrompt, CreateVarString(10, 'LITERAL_STRING', label))
        UiPromptSetVisible(passiveExitPrompt, state ~= 'none')
    end
end

---@param notify boolean
---@return integer|nil
local function getActiveHorse(notify)
    local horse = MyHorse
    if horseExists(horse) then return horse end

    if notify then
        Core.NotifyRightTip(_U('noHorse') or 'You do not have an active mount summoned!', 4000)
    end
end

---@param horse integer
---@return boolean
local function isCurrentHorse(horse)
    return (MyHorse or 0) == horse
end

---@return integer|nil
local function getNearbyHorse()
    local horse = getActiveHorse(true)
    if not horse then return end

    local playerPed = PlayerPedId()
    if #(GetEntityCoords(playerPed) - GetEntityCoords(horse)) > INTERACTION_DISTANCE then
        Core.NotifyRightTip(_U('tooFar') or 'You are too far from your horse!', 4000)
        return
    end

    return horse
end

local function adjustHorseCores(horse, attributeIndex, boostAmount)
    boostAmount = math.floor((tonumber(boostAmount) or 0) + 0.5)
    if boostAmount <= 0 or not horseExists(horse) then return end

    local current = Citizen.InvokeNative(
        0x36731AC041289BB1,
        horse,
        attributeIndex,
        Citizen.ResultAsInteger()
    ) or 100 -- GetAttributeCoreValue
    local target = math.min(current + boostAmount, 100)

    Citizen.InvokeNative(0xC6258F41D86676E0, horse, attributeIndex, target) -- SetAttributeCoreValue
    if target >= 100 then
        Citizen.InvokeNative(0x4AF5A4C7B9157D14, horse, attributeIndex, 1.0, true) -- EnableAttributeCoreOverpower
    end

    DBG:Info(('Vitals Sync: Core Index %d boosted by %d. New Fill: %d%%')
        :format(attributeIndex, boostAmount, target))
end

---@param attributeIndex integer
---@param boostAmount number
function AdjustHorseCores(attributeIndex, boostAmount)
    adjustHorseCores(MyHorse, attributeIndex, boostAmount)
end

local function playCoreFillSound()
    Citizen.InvokeNative(0x67C540AA08E4A6F5, 'Core_Fill_Up', 'Consumption_Sounds', true, 0)
end

---@param dict string
---@param name string
---@return integer
local function getAnimationDurationMs(dict, name)
    local duration = GetAnimDuration(dict, name)
    if not duration or duration <= 0 then return DEFAULT_TRANSITION_DURATION_MS end
    return math.max(math.floor(duration * 1000), 1)
end

---@param horse integer
---@param dict string
---@param name string
local function playAdvancedTransition(horse, dict, name)
    local coords = GetEntityCoords(horse)
    local rotation = GetEntityRotation(horse, 2)

    TaskPlayAnimAdvanced(
        horse,
        dict,
        name,
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
end

local function rewardInteraction(horse, boost, xpAction, xpAmount, playSound, defaultBoost)
    if not horseExists(horse) or not isCurrentHorse(horse) then return end

    local multiplier = 1.0
    if xpAction == 'brush' or xpAction == 'feed' or xpAction == 'drink' then
        local bondingLevel = GetHorseBondingData(horse, ActiveHorseXp)
        if bondingLevel >= 1 then
            multiplier = math.max(1.0, tonumber(Config.care.bondedRestorationMultiplier) or 1.25)
        end
    end

    adjustHorseCores(horse, CORE_HEALTH, (boost.health or defaultBoost or 0) * multiplier)
    adjustHorseCores(horse, CORE_STAMINA, (boost.stamina or defaultBoost or 0) * multiplier)

    if xpAmount and xpAmount > 0 and CanPlayerTrainHorses() then
        SaveXp(xpAction)
    end

    SaveHorseStats(false)

    if playSound then
        playCoreFillSound()
    end
end

---@param action 'feed'|'drink'
---@param horse integer
function RewardWorldCareInteraction(action, horse)
    if action == 'drink' then
        rewardInteraction(horse, Config.care.boosts.drink, 'drink', Config.training.xpRewards.drink, true, 10)
    elseif action == 'feed' then
        rewardInteraction(horse, Config.care.boosts.feed, 'feed', Config.training.xpRewards.feed, true, 25)
    end
end

---@param action 'rest'|'sleep'
---@param horse number
local function processPassiveRegen(action, horse)
    local boost = Config.care.boosts[action]
    local tickRate = math.max(tonumber(boost.tickIntervalSeconds) or 1, 0.1) * 1000

    CreateThread(function()
        while IsMyHorseActive and IsInteractingWithHorse and passiveInteractionPhase == 'loop'
            and isCurrentHorse(horse) and horseExists(horse) do
            Wait(tickRate)

            if not IsInteractingWithHorse or passiveInteractionPhase ~= 'loop'
                or not isCurrentHorse(horse) or not horseExists(horse) then break end

            adjustHorseCores(horse, CORE_HEALTH, boost.health or 0)
            adjustHorseCores(horse, CORE_STAMINA, boost.stamina or 0)

            if MyHorseId and MyHorseId ~= 0 then
                SaveHorseStats(false)
            elseif IsMyHorseActive then
                DBG:Error('Passive core saving blocked on client: MyHorseId variable is missing or nil!')
            end

            if Config.care.playPassiveRegenSound then
                playCoreFillSound()
            end
        end
    end)
end

---@param action 'rest'|'sleep'|'wallow'
---@param horse number
local function startPassiveRegen(action, horse)
    if action == 'rest' then
        processPassiveRegen('rest', horse)
    elseif action == 'sleep' then
        processPassiveRegen('sleep', horse)
    end
end

local function resetPassiveInteraction(token)
    if token and token ~= passiveInteractionToken then return end

    setNativeHorseTargeting(passiveInteractionHorse, true)
    setPassiveExitPromptVisibility('none')
    passiveInteractionHorse = 0
    IsInteractingWithHorse = false
    passiveInteractionAction = 'none'
    passiveInteractionPhase = 'none'
end

local function finishPassiveInteraction()
    if passiveInteractionAction == 'none' then return 0 end
    if passiveInteractionPhase == 'exit' then return 0 end

    local horse = passiveInteractionHorse
    passiveInteractionToken = passiveInteractionToken + 1
    local token = passiveInteractionToken

    if horseExists(horse) then
        local wasEntering = passiveInteractionPhase == 'enter'
        local dict
        local name

        if passiveInteractionAction == 'rest' then
            dict = wasEntering and HORSE_REST_QUICK_EXIT_DICT or HORSE_REST_EXIT_DICT
            name = wasEntering and HORSE_REST_QUICK_EXIT_NAME or HORSE_REST_EXIT_NAME
        elseif passiveInteractionAction == 'sleep' then
            dict = wasEntering and HORSE_SLEEP_QUICK_EXIT_DICT or HORSE_SLEEP_EXIT_DICT
            name = wasEntering and HORSE_SLEEP_QUICK_EXIT_NAME or HORSE_SLEEP_EXIT_NAME
        elseif passiveInteractionAction == 'wallow' then
            dict = HORSE_WALLOW_EXIT_DICT
            name = HORSE_WALLOW_EXIT_NAME
        end

        if dict and name and LoadAnim(dict) then
            local duration = getAnimationDurationMs(dict, name)
            DBG:Info(('Horse passive exit animation %s/%s duration: %d ms'):format(dict, name, duration))
            passiveInteractionPhase = 'exit'
            playAdvancedTransition(horse, dict, name)
            RemoveAnimDict(dict)

            CreateThread(function()
                Wait(duration)
                if horseExists(horse) then ClearPedTasks(horse) end
                resetPassiveInteraction(token)
            end)
            return duration
        end
    end

    if horseExists(horse) then ClearPedTasks(horse) end
    resetPassiveInteraction(token)
    return 0
end

function CancelHorsePassiveInteraction()
    return finishPassiveInteraction()
end

local function runTimedInteraction(horse, duration, callback)
    CreateThread(function()
        Wait(duration)
        callback()
        if isCurrentHorse(horse) then
            IsInteractingWithHorse = false
        end
    end)
end

RegisterNetEvent('bcc-horses:BrushHorse', function()
    if IsInteractingWithHorse then return end

    local horse = getNearbyHorse()
    if not horse then return end
    local playerPed = PlayerPedId()

    IsInteractingWithHorse = true
    ClearPedTasks(playerPed)
    Citizen.InvokeNative(0xCD181A959CFDD7F4, playerPed, horse, `Interaction_Brush`, `p_brushHorse02x`, true)

    runTimedInteraction(horse, 5000, function()
        if not horseExists(horse) or not isCurrentHorse(horse) then return end

        CleanHorseAppearance(horse)
        rewardInteraction(horse, Config.care.boosts.brush, 'brush', Config.training.xpRewards.brush, false, 15)
    end)
end)

RegisterNetEvent('bcc-horses:FeedHorse', function(item)
    if IsInteractingWithHorse then return end

    local horse = getNearbyHorse()
    if not horse then return end
    local playerPed = PlayerPedId()

    IsInteractingWithHorse = true
    ClearPedTasks(playerPed)
    Citizen.InvokeNative(0xCD181A959CFDD7F4, playerPed, horse, `Interaction_Food`, `s_horsnack_haycube01x`, true)
    TriggerServerEvent('bcc-horses:RemoveItem', item)

    runTimedInteraction(horse, 5000, function()
        rewardInteraction(horse, Config.care.boosts.feed, 'feed', Config.training.xpRewards.feed, true, 25)
    end)
end)

RegisterNetEvent('bcc-horses:UseLantern', function()
    local horse = getNearbyHorse()
    if not horse then return end
    local playerPed = PlayerPedId()

    ClearPedTasks(playerPed)

    if lanternHorse ~= horse then
        SetComponent(horse, '0x635E387C')
        lanternHorse = horse
        Core.NotifyRightTip('Lantern attached to mount saddle.', 4000)
        return
    end

    Citizen.InvokeNative(0x0D7FFA1B2F69ED82, horse, LANTERN_COMPONENT, 0, 0) -- RemoveShopItemFromPed
    Citizen.InvokeNative(0xCC8CA3E88256E58F, horse, false, true, true, true, false) -- UpdatePedVariation
    lanternHorse = 0
    Core.NotifyRightTip('Lantern removed from mount saddle.', 4000)
end)

function HorseDrinking()
    if IsInteractingWithHorse then return end

    local horse = getActiveHorse(true)
    if not horse then return end

    if not IsEntityInWater(horse) then
        local name = tostring(HorseName or 'Your horse')
        return Core.NotifyRightTip(name .. (_U('needWater') or ' needs to be standing in water to drink!'), 4000)
    end

    IsInteractingWithHorse = true
    groundDrinkToken = groundDrinkToken + 1
    local token = groundDrinkToken
    groundDrinkHorse = horse
    groundDrinkPhase = 'enter'
    local duration = (tonumber(Config.care.boosts.drink.durationSeconds) or 15) * 1000

    CreateThread(function()
        if not LoadAnim(HORSE_DRINK_ENTER_DICT) or not LoadAnim(HORSE_DRINK_IDLE_DICT) then
            RemoveAnimDict(HORSE_DRINK_ENTER_DICT)
            RemoveAnimDict(HORSE_DRINK_IDLE_DICT)
            DBG:Error('Failed to load ground-drinking enter or loop animation.')
            groundDrinkPhase = 'none'
            groundDrinkHorse = 0
            IsInteractingWithHorse = false
            return
        end

        if token ~= groundDrinkToken then
            RemoveAnimDict(HORSE_DRINK_ENTER_DICT)
            RemoveAnimDict(HORSE_DRINK_IDLE_DICT)
            return
        end

        local enterDuration = getAnimationDurationMs(HORSE_DRINK_ENTER_DICT, HORSE_DRINK_ENTER_NAME)
        playAdvancedTransition(horse, HORSE_DRINK_ENTER_DICT, HORSE_DRINK_ENTER_NAME)
        RemoveAnimDict(HORSE_DRINK_ENTER_DICT)
        Wait(enterDuration)

        if token ~= groundDrinkToken or not isCurrentHorse(horse) or not horseExists(horse) then
            RemoveAnimDict(HORSE_DRINK_IDLE_DICT)
            return
        end

        groundDrinkPhase = 'loop'
        TaskPlayAnim(
            horse,
            HORSE_DRINK_IDLE_DICT,
            HORSE_DRINK_IDLE_NAME,
            1.0,
            1.0,
            duration,
            3,
            1.0,
            false,
            false,
            false
        )
        Wait(duration)
        RemoveAnimDict(HORSE_DRINK_IDLE_DICT)

        if token ~= groundDrinkToken or not isCurrentHorse(horse) or not horseExists(horse) then return end

        rewardInteraction(horse, Config.care.boosts.drink, 'drink', Config.training.xpRewards.drink, true, 10)
        cancelGroundHorseDrinking()
    end)
end

---@return integer
cancelGroundHorseDrinking = function()
    local horse = groundDrinkHorse
    if groundDrinkPhase == 'none' then return 0 end
    if not horseExists(horse) then
        groundDrinkToken = groundDrinkToken + 1
        groundDrinkPhase = 'none'
        groundDrinkHorse = 0
        IsInteractingWithHorse = false
        return 0
    end
    if groundDrinkPhase == 'exit' then
        return getAnimationDurationMs(HORSE_DRINK_EXIT_DICT, HORSE_DRINK_EXIT_NAME)
    end

    groundDrinkToken = groundDrinkToken + 1
    local token = groundDrinkToken
    groundDrinkPhase = 'exit'

    if not LoadAnim(HORSE_DRINK_EXIT_DICT) then
        ClearPedTasks(horse)
        groundDrinkPhase = 'none'
        groundDrinkHorse = 0
        IsInteractingWithHorse = false
        return 0
    end

    local duration = getAnimationDurationMs(HORSE_DRINK_EXIT_DICT, HORSE_DRINK_EXIT_NAME)
    playAdvancedTransition(horse, HORSE_DRINK_EXIT_DICT, HORSE_DRINK_EXIT_NAME)
    RemoveAnimDict(HORSE_DRINK_EXIT_DICT)

    CreateThread(function()
        Wait(duration)
        if token ~= groundDrinkToken then return end
        if horseExists(horse) then ClearPedTasks(horse) end
        groundDrinkPhase = 'none'
        groundDrinkHorse = 0
        IsInteractingWithHorse = false
    end)

    return duration
end

local function hasMountBlockingInteraction(horse)
    return passiveInteractionAction ~= 'none'
        or (groundDrinkHorse == horse and groundDrinkPhase ~= 'none')
        or (type(IsHorseWorldCareInteractionActive) == 'function'
            and IsHorseWorldCareInteractionActive(horse))
end

local function cancelMountBlockingInteraction()
    if passiveInteractionAction ~= 'none' then return CancelHorsePassiveInteraction() or 0 end
    if groundDrinkPhase ~= 'none' then return cancelGroundHorseDrinking() or 0 end
    if type(CancelHorseWorldCareInteraction) == 'function' then
        return CancelHorseWorldCareInteraction() or 0
    end
    return 0
end

---@param action 'rest'|'sleep'|'wallow'
---@param animDict string
---@param animName string
local function startPassiveInteraction(action, animDict, animName)
    if IsInteractingWithHorse then return end

    local horse = getActiveHorse(true)
    if not horse then return end

    if not Citizen.InvokeNative(0xAAB0FE202E9FC9F0, horse, -1) then -- IsMountSeatFree
        return Core.NotifyRightTip(_U('horseOccupied'), 4000)
    end

    IsInteractingWithHorse = true
    passiveInteractionAction = action
    passiveInteractionHorse = horse
    setNativeHorseTargeting(horse, false)
    passiveInteractionToken = passiveInteractionToken + 1
    local token = passiveInteractionToken

    local enterDict = action == 'rest' and HORSE_REST_ENTER_DICT
        or action == 'sleep' and HORSE_SLEEP_ENTER_DICT
        or HORSE_WALLOW_ENTER_DICT
    local enterName = action == 'rest' and HORSE_REST_ENTER_NAME
        or action == 'sleep' and HORSE_SLEEP_ENTER_NAME
        or HORSE_WALLOW_ENTER_NAME

    if (enterDict and not LoadAnim(enterDict)) or not LoadAnim(animDict)
        or not horseExists(horse) or not isCurrentHorse(horse) then
        if enterDict then RemoveAnimDict(enterDict) end
        resetPassiveInteraction(token)
        DBG:Error(('Failed to start horse %s animation: %s'):format(action, animDict))
        return
    end

    if enterDict and enterName then
        local enterDuration = getAnimationDurationMs(enterDict, enterName)
        DBG:Info(('Horse %s enter animation %s/%s duration: %d ms')
            :format(action, enterDict, enterName, enterDuration))
        passiveInteractionPhase = 'enter'
        playAdvancedTransition(horse, enterDict, enterName)
        RemoveAnimDict(enterDict)

        CreateThread(function()
            Wait(enterDuration)
            if token ~= passiveInteractionToken or not IsInteractingWithHorse
                or not isCurrentHorse(horse) or not horseExists(horse) then
                RemoveAnimDict(animDict)
                return
            end

            passiveInteractionPhase = 'loop'
            TaskPlayAnim(horse, animDict, animName, 1.0, 1.0, -1, 3, 1.0, false, false, false)
            RemoveAnimDict(animDict)
            startPassiveRegen(action, horse)
        end)
        return
    end

    passiveInteractionPhase = 'loop'
    TaskPlayAnim(horse, animDict, animName, 1.0, 1.0, -1, 3, 1.0, false, false, false)
    RemoveAnimDict(animDict)
    startPassiveRegen(action, horse)
end

function HorseResting()
    startPassiveInteraction('rest', HORSE_REST_ANIM_DICT, HORSE_REST_ANIM_NAME)
end

function HorseSleeping()
    startPassiveInteraction('sleep', HORSE_SLEEP_ANIM_DICT, HORSE_SLEEP_ANIM_NAME)
end

function HorseWallowing()
    startPassiveInteraction('wallow', HORSE_WALLOW_ANIM_DICT, HORSE_WALLOW_ANIM_NAME)
end

CreateThread(function()
    ensurePassiveExitPrompts()

    while true do
        local delay = 1000
        local horse = MyHorse
        local playerPed = PlayerPedId()

        if horseExists(horse) and hasMountBlockingInteraction(horse) then
            delay = 0
            local isPlayerAlive = not IsPedDeadOrDying(playerPed, true)
            local isNearby = isPlayerAlive
                and #(GetEntityCoords(playerPed) - GetEntityCoords(horse)) <= MOUNT_CHECK_DISTANCE

            if isNearby then
                local promptState = passiveInteractionAction
                setPassiveExitPromptVisibility(promptState)
                if promptState ~= 'none' then
                    UiPromptSetActiveGroupThisFrame(
                        passiveExitPromptGroup,
                        CreateVarString(10, 'LITERAL_STRING', tostring(HorseName or 'Horse')),
                        1,
                        0,
                        0,
                        0
                    )
                end

                if passiveExitPrompt ~= 0 and UiPromptHasStandardModeCompleted(passiveExitPrompt, 0) then
                    CancelHorsePassiveInteraction()
                end

                DisableControlAction(0, INPUT_ENTER, true)

                if IsDisabledControlJustPressed(0, INPUT_ENTER) and not isDeferredMountPending then
                    isDeferredMountPending = true
                    local transitionDuration = cancelMountBlockingInteraction()
                    local mountingPlayer = playerPed
                    local mountingHorse = horse

                    CreateThread(function()
                        if transitionDuration > 0 then Wait(transitionDuration + 50) end
                        isDeferredMountPending = false

                        if not horseExists(mountingHorse) or not isCurrentHorse(mountingHorse)
                            or IsPedDeadOrDying(mountingPlayer, true) then return end

                        if #(GetEntityCoords(mountingPlayer) - GetEntityCoords(mountingHorse))
                            > MOUNT_CHECK_DISTANCE
                            or not Citizen.InvokeNative(0xAAB0FE202E9FC9F0, mountingHorse, -1) then return end

                        Citizen.InvokeNative(
                            0x92DB0739813C5186,
                            mountingPlayer,
                            mountingHorse,
                            -1,
                            -1,
                            2.0,
                            1,
                            0,
                            0
                        ) -- TaskMountAnimal
                    end)
                end
            else
                setPassiveExitPromptVisibility('none')
            end
        else
            setPassiveExitPromptVisibility('none')
        end

        Wait(delay)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    setNativeHorseTargeting(passiveInteractionHorse, true)
    setNativeHorseTargeting(MyHorse, true)
    if type(StopFlamingHooves) == 'function' then StopFlamingHooves(false) end
end)

local flamingHoovesHorse = 0
local flamingHoovesEndsAt = 0
local flamingHoovesToken = 0
local flamingHoovesActive = false

local function setGoldenCore(horse, core, enabled)
    if not horseExists(horse) then return end
    if enabled then Citizen.InvokeNative(0xC6258F41D86676E0, horse, core, 100) end
    Citizen.InvokeNative(0x4AF5A4C7B9157D14, horse, core, enabled and 1.0 or 0.0, true)
end

function GetFlamingHoovesRemainingSeconds()
    if not flamingHoovesActive then return 0 end
    return math.max(0, math.ceil((flamingHoovesEndsAt - GetGameTimer()) / 1000))
end

function StopFlamingHooves(notify)
    flamingHoovesToken = flamingHoovesToken + 1
    local horse = flamingHoovesHorse
    local config = Config.items.flamingHooves or {}

    if horseExists(horse) then
        Citizen.InvokeNative(0x1913FE4CBF41C463, horse, FLAMING_HOOVES_FLAG, false)
        if config.goldenHealthCore then setGoldenCore(horse, CORE_HEALTH, false) end
        if config.goldenStaminaCore then setGoldenCore(horse, CORE_STAMINA, false) end
        if config.fearResistance then
            local bondingLevel = GetHorseBondingData(horse, ActiveHorseXp)
            Citizen.InvokeNative(0x1913FE4CBF41C463, horse, DISABLE_SHOCKING_EVENTS_FLAG, bondingLevel >= 2)
            Citizen.InvokeNative(0x1913FE4CBF41C463, horse, DISABLE_GUNSHOT_FLEE_FLAG, bondingLevel >= 3)
        end
    end

    local wasActive = flamingHoovesActive
    flamingHoovesActive = false
    flamingHoovesHorse = 0
    flamingHoovesEndsAt = 0
    if notify and wasActive then
        Core.NotifyRightTip(_U('flameHoovesDeactivated'), 4000)
    end
end

local function activateFlamingHooves(horse, horseId, durationMs)
    local config = Config.items.flamingHooves
    flamingHoovesToken = flamingHoovesToken + 1
    local token = flamingHoovesToken
    flamingHoovesActive = true
    flamingHoovesHorse = horse
    flamingHoovesEndsAt = GetGameTimer() + durationMs

    Citizen.InvokeNative(0x1913FE4CBF41C463, horse, FLAMING_HOOVES_FLAG, true)
    if config.goldenHealthCore then setGoldenCore(horse, CORE_HEALTH, true) end
    if config.goldenStaminaCore then setGoldenCore(horse, CORE_STAMINA, true) end
    if config.fearResistance then
        Citizen.InvokeNative(0x1913FE4CBF41C463, horse, DISABLE_SHOCKING_EVENTS_FLAG, true)
        Citizen.InvokeNative(0x1913FE4CBF41C463, horse, DISABLE_GUNSHOT_FLEE_FLAG, true)
    end
    if config.rearOnActivation then
        Citizen.InvokeNative(0xA09CFD29100F06C3, horse, HORSE_ACTION_REAR_UP, 0, 0) -- TaskHorseAction
    end
    Core.NotifyRightTip(_U('flameHoovesActivated'), 4000)

    CreateThread(function()
        local warned = false
        local warningSeconds = math.max(0, math.floor(tonumber(config.expiryWarningSeconds) or 0))
        while token == flamingHoovesToken and flamingHoovesActive and horseExists(horse)
            and not IsEntityDead(horse) and MyHorse == horse and tonumber(MyHorseId) == horseId
            and GetGameTimer() < flamingHoovesEndsAt do
            local remaining = GetFlamingHoovesRemainingSeconds()
            if not warned and warningSeconds > 0 and remaining <= warningSeconds then
                warned = true
                Core.NotifyRightTip(('Flaming hooves will fade in %d seconds.'):format(remaining), 4000)
            end
            if config.goldenHealthCore then setGoldenCore(horse, CORE_HEALTH, true) end
            if config.goldenStaminaCore then setGoldenCore(horse, CORE_STAMINA, true) end
            Wait(1000)
        end

        if token == flamingHoovesToken then
            StopFlamingHooves(horseExists(horse) and not IsEntityDead(horse))
        end
    end)
end

RegisterNetEvent('bcc-horses:TryFlamingHooves', function()
    if flamingHoovesActive then
        return Core.NotifyRightTip('Flaming hooves are already active.', 4000)
    end

    local horse = getNearbyHorse()
    local horseId = tonumber(MyHorseId)
    if not horse or not horseId or IsEntityDead(horse) then return end

    local bondingLevel = GetHorseBondingData(horse, ActiveHorseXp)
    local requiredLevel = math.max(0, math.min(4,
        math.floor(tonumber(Config.items.flamingHooves.requiredBondingLevel) or 0)))
    if bondingLevel < requiredLevel then
        return Core.NotifyRightTip(('Bonding level %d is required.'):format(requiredLevel), 4000)
    end

    local result = Core.Callback.TriggerAwait('bcc-horses:ActivateFlamingHooves', {
        horseId = horseId,
        bondingLevel = bondingLevel,
    })
    if type(result) ~= 'table' or result.success ~= true then
        return Core.NotifyRightTip(type(result) == 'table' and result.message
            or 'Flaming hooves could not be activated.', 4000)
    end

    if MyHorse ~= horse or tonumber(MyHorseId) ~= horseId or not horseExists(horse) or IsEntityDead(horse) then
        return Core.NotifyRightTip('The horse is no longer available.', 4000)
    end
    activateFlamingHooves(horse, horseId, tonumber(result.durationMs) or 120000)
end)
