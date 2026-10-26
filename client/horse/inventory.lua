local IDLE_POLL_INTERVAL_MS <const> = 1000
local SADDLEBAG_COMPONENT <const> = -2142954459
local LOOT_SADDLEBAGS_INTERACTION <const> = `Interaction_LootSaddleBags`

local IS_META_PED_USING_COMPONENT <const> = 0xFB4891BD7578CDC1
local TASK_ANIMAL_INTERACTION <const> = 0xCD181A959CFDD7F4
local GET_NEAR_HORSE <const> = 0x0501D52D24EA8934
local GET_PLAYER_OWNER_OF_MOUNT <const> = 0xAD03B03737CE6810
local IS_PED_LEADING_HORSE <const> = 0xEFC4303DDC6E60D3

---@param horsePedId integer
---@param horseId integer
---@param isLooting boolean
function OpenInventory(horsePedId, horseId, isLooting)
    local hasSaddlebags = Citizen.InvokeNative(
        IS_META_PED_USING_COMPONENT,
        horsePedId,
        SADDLEBAG_COMPONENT
    )

    if not isLooting and Config.inventory.requireSaddlebags and not hasSaddlebags then
        Core.NotifyRightTip(_U('noSaddlebags'), 4000)
        return
    end

    if hasSaddlebags then
        Citizen.InvokeNative(
            TASK_ANIMAL_INTERACTION,
            PlayerPedId(),
            horsePedId,
            LOOT_SADDLEBAGS_INTERACTION,
            0,
            true
        )
    end

    TriggerServerEvent('bcc-horses:OpenInventory', horseId)
end

local function canLootNearbyHorse(playerPed, horse)
    if horse == 0 or horse == MyHorse then return false end

    local owner = Citizen.InvokeNative(GET_PLAYER_OWNER_OF_MOUNT, horse)
    local isLeadingHorse = Citizen.InvokeNative(IS_PED_LEADING_HORSE, playerPed)

    return owner ~= 255 and not isLeadingHorse
end

local function runLootInventoryLoop()
    local lootLabel = CreateVarString(10, 'LITERAL_STRING', _U('lootInventory'))

    while true do
        local sleep = IDLE_POLL_INTERVAL_MS
        local playerPed = PlayerPedId()

        if not IsEntityDead(playerPed) and IsPedOnFoot(playerPed) then
            local horse = Citizen.InvokeNative(GET_NEAR_HORSE, 1, Citizen.ResultAsInteger())

            if canLootNearbyHorse(playerPed, horse) then
                sleep = 0
                UiPromptSetActiveGroupThisFrame(LootGroup, lootLabel, 1, 0, 0, 0)

                if UiPromptHasStandardModeCompleted(LootHorse, 0) then
                    local horseId = Entity(horse).state.myHorseId
                    OpenInventory(horse, horseId, true)
                end
            end
        end

        Wait(sleep)
    end
end

if Config.inventory.shared then
    CreateThread(runLootInventoryLoop)
end
