local DEFAULT_DURABILITY <const> = 100
local DEFAULT_DURABILITY_USE <const> = 1

local function metadataWithDurability(item, description, durability)
    return {
        description = description .. '</br>' .. (_U('durability') or 'Durability: ') .. durability .. '%',
        durability = durability,
        id = item.id
    }
end

local function useDurableItem(src, config, description, brokenMessage, removeById, allowFinalUse)
    local itemName = config and config.name
    if type(itemName) ~= 'string' or itemName == '' then return false end

    local item = exports.vorp_inventory:getItem(src, itemName)
    if not item then return false end

    exports.vorp_inventory:closeInventory(src)
    if not config.durabilityEnabled then return true end

    local metadata = ServerUtils.decodeTable(item.metadata, {})
    local current = tonumber(metadata.durability) or tonumber(config.maximumDurability) or DEFAULT_DURABILITY
    local durabilityUse = math.max(1, tonumber(config.durabilityUsedPerAction) or DEFAULT_DURABILITY_USE)
    local remaining = math.max(0, current - durabilityUse)

    if remaining <= 0 then
        if removeById then
            exports.vorp_inventory:subItemID(src, item.id)
        else
            exports.vorp_inventory:subItem(src, itemName, 1)
        end

        Core.NotifyRightTip(src, brokenMessage, 4000)
        return allowFinalUse == true
    end

    exports.vorp_inventory:setItemMetadata(
        src,
        item.id,
        metadataWithDurability(item, description, remaining),
        1
    )
    return true
end

local function registerDurableUsable(config, clientEvent, description, brokenMessage, removeById, triggerWhenBroken)
    if not config or type(config.name) ~= 'string' or config.name == '' then return end

    exports.vorp_inventory:registerUsableItem(config.name, function(data)
        local src = tonumber(data and data.source)
        if not src or not ServerUtils.getCharacter(src, clientEvent .. ' usable item') then return end

        local usable = useDurableItem(src, config, description, brokenMessage, removeById)
        if usable or triggerWhenBroken then
            TriggerClientEvent(clientEvent, src)
        end
    end)
end

for _, itemName in ipairs(Config.items.food or {}) do
    exports.vorp_inventory:registerUsableItem(itemName, function(data)
        local src = tonumber(data and data.source)
        if not src then return end

        exports.vorp_inventory:closeInventory(src)
        TriggerClientEvent('bcc-horses:FeedHorse', src, itemName)
    end)
end

registerDurableUsable(
    Config.items.brush,
    'bcc-horses:BrushHorse',
    _U('horsebrushDesc') or 'Horse Brush',
    _U('itemBroke') or 'Your brush has worn out and broken!',
    false,
    false
)

registerDurableUsable(
    Config.items.lantern,
    'bcc-horses:UseLantern',
    _U('lanternDesc') or 'Horse Lantern Attachment',
    _U('itemBroke') or 'Your lantern attachment has broken from wear!',
    false,
    false
)

local flamingHoovesCooldowns = {}
local flamingHoovesLocks = {}

local function formatCooldown(seconds)
    local totalSeconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local minutes = math.floor(totalSeconds / 60)
    local remainingSeconds = totalSeconds % 60
    local minuteLabel = minutes == 1 and 'minute' or 'minutes'
    local secondLabel = remainingSeconds == 1 and 'second' or 'seconds'
    return ('%d %s %d %s'):format(minutes, minuteLabel, remainingSeconds, secondLabel)
end

if Config.items.flamingHooves and Config.items.flamingHooves.enabled then
    local flamingConfig = Config.items.flamingHooves

    exports.vorp_inventory:registerUsableItem(flamingConfig.name, function(data)
        local src = tonumber(data and data.source)
        if not src or not ServerUtils.getCharacter(src, 'flaming hooves usable item') then return end

        exports.vorp_inventory:closeInventory(src)
        TriggerClientEvent('bcc-horses:TryFlamingHooves', src)
    end)
end

Core.Callback.Register('bcc-horses:ActivateFlamingHooves', function(source, cb, data)
    local src = source
    local flamingConfig = Config.items.flamingHooves
    local _, charId = ServerUtils.getCharacter(src, 'flaming hooves activation')
    local horseId = type(data) == 'table' and tonumber(data.horseId) or nil
    local bondingLevel = type(data) == 'table' and math.floor(tonumber(data.bondingLevel) or -1) or -1

    if not flamingConfig or not flamingConfig.enabled or not charId or not horseId then
        return cb({ success = false, message = 'Flaming hooves are unavailable.' })
    end
    if flamingHoovesLocks[charId] then
        return cb({ success = false, message = 'Flaming hooves are already being prepared.' })
    end

    local now = os.time()
    local cooldownEndsAt = flamingHoovesCooldowns[charId] or 0
    if cooldownEndsAt > now then
        return cb({
            success = false,
            message = ('Flaming hooves will be ready in %s.'):format(formatCooldown(cooldownEndsAt - now)),
        })
    end

    local requiredLevel = math.max(0, math.min(4, math.floor(tonumber(flamingConfig.requiredBondingLevel) or 0)))
    if bondingLevel < requiredLevel then
        return cb({
            success = false,
            message = ('Bonding level %d is required.'):format(requiredLevel),
        })
    end

    flamingHoovesLocks[charId] = true
    local function finish(result)
        flamingHoovesLocks[charId] = nil
        cb(result)
    end

    MySQL.single(
        'SELECT `id` FROM `bcc_player_horses` WHERE `id` = ? AND `charid` = ? AND `is_selected` = 1 AND `is_dead` = 0 LIMIT 1',
        { horseId, charId },
        function(horse)
            if not horse then
                return finish({ success = false, message = 'The active horse could not be verified.' })
            end

            local usable = useDurableItem(
                src,
                flamingConfig,
                _U('flameHooveDesc'),
                _U('itemBroke'),
                true,
                true
            )
            if not usable then
                return finish({ success = false, message = 'The required item could not be used.' })
            end

            local cooldownSeconds = math.max(0, math.floor((tonumber(flamingConfig.cooldownMinutes) or 0) * 60))
            flamingHoovesCooldowns[charId] = os.time() + cooldownSeconds
            finish({
                success = true,
                durationMs = math.max(1000, math.floor((tonumber(flamingConfig.durationMinutes) or 2) * 60000)),
            })
        end
    )
end)
