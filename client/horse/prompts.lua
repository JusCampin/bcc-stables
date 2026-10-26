OpenShop, OpenCall, OpenReturn = 0, 0, 0
ShopGroup = GetRandomIntInRange(0, 0xffffff)

LootHorse = 0
LootGroup = GetRandomIntInRange(0, 0xffffff)

local TARGET_INFO_CONTEXT <const> = 35
local HORSE_FLEE_CONTEXT <const> = 33
local TARGET_PROMPT_DISTANCE <const> = 2.8
local BONDING_RANK_REFRESH_MS <const> = 500
local PAT_REWARD_DELAY_MS <const> = 3000
local PAT_REWARD_COOLDOWN_MS <const> = 3000
local PAT_COMPLETION_DISTANCE <const> = 4.0

local INPUT_OPEN_SATCHEL_HORSE_MENU <const> = `INPUT_OPEN_SATCHEL_HORSE_MENU`
local INPUT_REVIVE <const> = `INPUT_REVIVE`
local INPUT_HORSE_COMMAND_FLEE <const> = `INPUT_HORSE_COMMAND_FLEE`
local INPUT_INTERACT_OPTION1 <const> = `INPUT_INTERACT_OPTION1`

local promptGroupsInitialized = false
local horsePromptLoopRunning = false
local horsePromptsRegistered = false
local horsePromptsVisible = false
local horsePromptGroup = nil
local defaultPromptHorse = 0
local defaultHorsePromptsVisible = false
local lastBondingRank = -1
local lastInteractionState = nil
local nextBondingRankRefresh = 0
local patRewardPending = false
local nextPatRewardAt = 0

local keys <const> = Config.controls

local horsePrompts = {
    {
        control = keys.drink,
        localeKey = 'drinkPrompt',
        fallback = 'Drink',
        level = 0,
        dynamicLabel = function(horse)
            return GetHorseCarePromptLabel(horse)
        end,
        action = function() StartHorseContextCare() end,
    },
    {
        control = keys.rest,
        localeKey = 'restPrompt',
        fallback = 'Rest',
        level = 2,
        action = function() HorseResting() end,
    },
    {
        control = keys.sleep,
        localeKey = 'sleepPrompt',
        fallback = 'Sleep',
        level = 3,
        action = function() HorseSleeping() end,
    },
    {
        control = keys.wallow,
        localeKey = 'wallowPrompt',
        fallback = 'Wallow',
        level = 4,
        action = function() HorseWallowing() end,
    },
}

local function promptText(localeKey, fallback)
    return CreateVarString(10, 'LITERAL_STRING', _U(localeKey) or fallback)
end

local function registerPrompt(control, text, group, holdDuration, enabled)
    local prompt = UiPromptRegisterBegin()

    UiPromptSetControlAction(prompt, control)
    UiPromptSetText(prompt, text)
    UiPromptSetVisible(prompt, true)

    if enabled ~= nil then
        UiPromptSetEnabled(prompt, enabled)
    end

    if holdDuration then
        UiPromptSetHoldMode(prompt, holdDuration)
    else
        UiPromptSetStandardMode(prompt, true)
    end

    if group then
        UiPromptSetGroup(prompt, group, 0)
    end

    UiPromptRegisterEnd(prompt)
    return prompt
end

function StartPrompts()
    if promptGroupsInitialized then return end

    OpenShop = registerPrompt(keys.openStable, promptText('shopPrompt', 'Open Stable'), ShopGroup)
    OpenCall = registerPrompt(keys.stableAction, promptText('callPrompt', 'Call Active Horse'), ShopGroup)
    OpenReturn = registerPrompt(keys.stableAction, promptText('returnPrompt', 'Return Horse'), ShopGroup)

    LootHorse = registerPrompt(keys.lootHorse, promptText('lootHorsePrompt', 'Open'), LootGroup, nil, true)

    promptGroupsInitialized = true
end

local function setHorsePromptVisibility(visible)
    if not horsePromptsRegistered or horsePromptsVisible == visible then return end

    for i = 1, #horsePrompts do
        UiPromptSetVisible(horsePrompts[i].handle, visible)
    end

    horsePromptsVisible = visible
end

local function registerHorsePrompts(group)
    for i = 1, #horsePrompts do
        local definition = horsePrompts[i]
        definition.handle = registerPrompt(
            definition.control,
            promptText(definition.localeKey, definition.fallback),
            group,
            nil,
            false
        )
    end

    horsePromptsRegistered = true
    horsePromptsVisible = true
    horsePromptGroup = group
end

local function updateHorsePromptGroup(group)
    if not horsePromptsRegistered then
        registerHorsePrompts(group)
        return
    end

    setHorsePromptVisibility(true)

    if horsePromptGroup == group then return end

    for i = 1, #horsePrompts do
        UiPromptSetGroup(horsePrompts[i].handle, group, 0)
    end

    horsePromptGroup = group
end

local function updateHorsePromptAvailability(horse)
    local now = GetGameTimer()
    local isInteracting = IsInteractingWithHorse == true

    if now < nextBondingRankRefresh and lastInteractionState == isInteracting then return end

    if now >= nextBondingRankRefresh then
        lastBondingRank = GetHorseBondingData(horse, ActiveHorseXp)
        nextBondingRankRefresh = now + BONDING_RANK_REFRESH_MS
    end

    for i = 1, #horsePrompts do
        local definition = horsePrompts[i]
        UiPromptSetEnabled(definition.handle, not isInteracting and lastBondingRank >= definition.level)

        if definition.dynamicLabel then
            UiPromptSetText(
                definition.handle,
                CreateVarString(10, 'LITERAL_STRING', definition.dynamicLabel(horse))
            )
        end
    end

    lastInteractionState = isInteracting
end

function HorseTargetPrompts(group)
    local horse = MyHorse
    if not horse or horse == 0 or not DoesEntityExist(horse) then return end

    updateHorsePromptGroup(group)
    updateHorsePromptAvailability(horse)
end

local function hideHorseTargetPrompts()
    setHorsePromptVisibility(false)
    horsePromptGroup = nil
    lastBondingRank = -1
    lastInteractionState = nil
    nextBondingRankRefresh = 0
end

local function setDefaultHorsePromptsVisible(player, horse, visible)
    if not horse or horse == 0 or not DoesEntityExist(horse) then return end
    if defaultPromptHorse == horse and defaultHorsePromptsVisible == visible then return end

    Citizen.InvokeNative(0xA3DB37EDF9A74635, player, horse, TARGET_INFO_CONTEXT, 1, not visible) -- ModifyPlayerUiPromptForPed

    if Config.stable.fleeEnabled then
        Citizen.InvokeNative(0xA3DB37EDF9A74635, player, horse, HORSE_FLEE_CONTEXT, 1, not visible) -- ModifyPlayerUiPromptForPed
    end

    defaultPromptHorse = horse
    defaultHorsePromptsVisible = visible
end

function RemoveHorsePrompts()
    local horse = MyHorse

    hideHorseTargetPrompts()
    setDefaultHorsePromptsVisible(PlayerId(), horse, false)

    if not horse or horse == 0 or not DoesEntityExist(horse) then
        defaultPromptHorse = 0
        defaultHorsePromptsVisible = false
    end
end

local function handleHorseAction()
    if IsInteractingWithHorse then return end

    for i = 1, #horsePrompts do
        local definition = horsePrompts[i]
        if UiPromptHasStandardModeCompleted(definition.handle, 0) then
            definition.action()
            return
        end
    end
end

local function queuePatReward(horse)
    local now = GetGameTimer()
    if patRewardPending or now < nextPatRewardAt then return end

    patRewardPending = true
    nextPatRewardAt = now + PAT_REWARD_COOLDOWN_MS

    CreateThread(function()
        Wait(PAT_REWARD_DELAY_MS)
        patRewardPending = false

        if horse ~= MyHorse or not DoesEntityExist(horse) or IsEntityDead(horse) then return end
        if not MyHorseId or MyHorseId == 0 or not CanPlayerTrainHorses() then return end

        local playerPed = PlayerPedId()
        if IsEntityDead(playerPed) or IsPedOnMount(playerPed) then return end
        if #(GetEntityCoords(playerPed) - GetEntityCoords(horse)) > PAT_COMPLETION_DISTANCE then return end

        SaveXp('pat')
    end)
end

local function wasPatControlPressed()
    return IsControlJustPressed(0, INPUT_INTERACT_OPTION1)
        or IsDisabledControlJustPressed(0, INPUT_INTERACT_OPTION1)
end

local function runHorsePromptLoop()
    local player = PlayerId()

    while MyHorse and MyHorse ~= 0 do
        local horse = MyHorse
        local sleep = 500

        if DoesEntityExist(horse) then
            local playerPed = PlayerPedId()

            if IsEntityDead(playerPed) then
                RemoveHorsePrompts()
                sleep = 1000
            elseif IsPlayerFreeAiming(player) then
                RemoveHorsePrompts()
            else
                local distance = #(GetEntityCoords(playerPed) - GetEntityCoords(horse))

                if distance <= TARGET_PROMPT_DISTANCE then
                    sleep = 0

                    if IsInteractingWithHorse then
                        -- Passive interactions own the prompt UI until their exit animation finishes.
                        RemoveHorsePrompts()
                    elseif InWrithe then
                        RemoveHorsePrompts()

                        if Citizen.InvokeNative(0x91AEF906BCA88877, 0, INPUT_REVIVE) then -- IsDisabledControlJustPressed
                            TriggerEvent('bcc-horses:ReviveHorse')
                        end
                    else
                        if Citizen.InvokeNative(0x91AEF906BCA88877, 0, INPUT_OPEN_SATCHEL_HORSE_MENU) then -- IsDisabledControlJustPressed
                            OpenInventory(horse, MyHorseId, false)
                        end

                        setDefaultHorsePromptsVisible(player, horse, true)

                        if Citizen.InvokeNative(0x27F89FDC16688A7A, player, horse, false) then -- IsPlayerTargettingEntity
                            local group = Citizen.InvokeNative(0xB796970BD125FCE8, horse) -- PromptGetGroupIdForTargetEntity
                            HorseTargetPrompts(group)
                            handleHorseAction()

                            if wasPatControlPressed() then
                                queuePatReward(horse)
                            end

                            if Config.stable.fleeEnabled and Citizen.InvokeNative(0x580417101DDB492F, 0, INPUT_HORSE_COMMAND_FLEE) then -- IsControlJustPressed
                                FleeHorse()
                            end
                        else
                            hideHorseTargetPrompts()
                        end
                    end
                else
                    RemoveHorsePrompts()
                end
            end
        else
            RemoveHorsePrompts()
            break
        end

        Wait(sleep)
    end

    RemoveHorsePrompts()
    horsePromptLoopRunning = false
end

AddEventHandler('bcc-horses:HorsePrompts', function()
    if horsePromptLoopRunning or not MyHorse or MyHorse == 0 then return end

    horsePromptLoopRunning = true
    CreateThread(runHorsePromptLoop)
end)
