local HORSE_INVENTORY_PREFIX <const> = 'horse_'
local DEFAULT_INVENTORY_LIMIT <const> = 50
local registeredInventories = {}
local horseFoodItems = {}

for _, itemName in ipairs(Config.items.food or {}) do
    horseFoodItems[itemName] = true
end

local function inventoryId(horseId)
    return HORSE_INVENTORY_PREFIX .. horseId
end

local function applyInventoryRules(id, data)
    if data.UsePermissions and Config.inventory.permissions then
        for _, permission in ipairs(Config.inventory.permissions.allowedJobsTakeFrom or {}) do
            exports.vorp_inventory:AddPermissionTakeFromCustom(id, permission.name, permission.grade)
        end

        for _, permission in ipairs(Config.inventory.permissions.allowedJobsMoveTo or {}) do
            exports.vorp_inventory:AddPermissionMoveToCustom(id, permission.name, permission.grade)
        end
    end

    if data.whitelistItems then
        for _, item in ipairs(Config.inventory.items.allowList or {}) do
            exports.vorp_inventory:setCustomInventoryItemLimit(id, item.name, item.limit)
        end
    end

    if data.whitelistWeapons then
        for _, weapon in ipairs(Config.inventory.weapons.allowList or {}) do
            exports.vorp_inventory:setCustomInventoryWeaponLimit(id, weapon.name, weapon.limit)
        end
    end

    if data.UseBlackList then
        for _, itemName in ipairs(Config.inventory.items.blockList or {}) do
            exports.vorp_inventory:BlackListCustomAny(id, itemName)
        end
    end
end

local function registerHorseInventory(horseId, model)
    if registeredInventories[horseId] then return true end

    local colorConfig = ServerUtils.getHorseConfig(model)
    if not colorConfig then
        DBG:Error(('Inventory registration failed for unknown horse model: %s'):format(tostring(model)))
        return false
    end

    local id = inventoryId(horseId)
    local data = {
        id = id,
        name = _U('horseInv') or 'Horse Inventory',
        limit = tonumber(colorConfig.invLimit) or DEFAULT_INVENTORY_LIMIT,
        acceptWeapons = Config.inventory.weapons.enabled == true,
        shared = Config.inventory.shared == true,
        ignoreItemStackLimit = Config.inventory.items.ignoreStackLimit ~= false,
        whitelistItems = Config.inventory.items.useAllowList == true,
        UsePermissions = Config.inventory.permissions.enabled == true,
        UseBlackList = Config.inventory.items.useBlockList == true,
        whitelistWeapons = Config.inventory.weapons.useAllowList == true
    }

    exports.vorp_inventory:registerInventory(data)
    applyInventoryRules(id, data)
    registeredInventories[horseId] = true
    return true
end

local function isHorseNearby(src, horseId)
    local playerPed = GetPlayerPed(src)
    if playerPed == 0 then return false end

    local playerCoords = GetEntityCoords(playerPed)
    for _, ped in ipairs(GetAllPeds()) do
        if tonumber(Entity(ped).state.myHorseId) == horseId then
            local offset = playerCoords - GetEntityCoords(ped)
            return offset.x * offset.x + offset.y * offset.y + offset.z * offset.z <= 100.0
        end
    end

    return false
end

RegisterNetEvent('bcc-horses:RegisterInventory', function(horseId)
    local src = source
    local _, charId = ServerUtils.getCharacter(src, 'horse inventory registration')
    local targetHorseId = tonumber(horseId)
    if not charId or not targetHorseId then return end

    MySQL.scalar(
        'SELECT `model` FROM `bcc_player_horses` WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0 LIMIT 1',
        { targetHorseId, charId },
        function(model)
            if type(model) == 'string' then
                registerHorseInventory(targetHorseId, model)
            else
                DBG:Warning(('Rejected inventory registration for unowned horse ID %s.'):format(targetHorseId))
            end
        end
    )
end)

RegisterNetEvent('bcc-horses:OpenInventory', function(horseId)
    local src = source
    local _, charId = ServerUtils.getCharacter(src, 'horse inventory open event')
    local targetHorseId = tonumber(horseId)
    if not charId or not targetHorseId then return end

    MySQL.single(
        'SELECT `model`, `charid` FROM `bcc_player_horses` WHERE `id` = ? AND `is_dead` = 0 LIMIT 1',
        { targetHorseId },
        function(row)
            if not row or type(row.model) ~= 'string' then return end

            local ownsHorse = tonumber(row.charid) == charId
            if not ownsHorse and (not Config.inventory.shared or not isHorseNearby(src, targetHorseId)) then
                return
            end

            if registerHorseInventory(targetHorseId, row.model) then
                exports.vorp_inventory:openInventory(src, inventoryId(targetHorseId))
            end
        end
    )
end)

---@param item string
RegisterNetEvent('bcc-horses:RemoveItem', function(item)
    local src = source
    if not ServerUtils.getCharacter(src, 'horse food removal event') then return end
    if type(item) ~= 'string' or not horseFoodItems[item] then return end

    exports.vorp_inventory:subItem(src, item, 1)
end)
