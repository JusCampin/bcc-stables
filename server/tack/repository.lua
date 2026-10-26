TackRepository = TackRepository or {}

local ITEMS_TABLE <const> = 'bcc_horse_tack_items'
local LOADOUTS_TABLE <const> = 'bcc_horse_tack_loadouts'

function TackRepository.getOwnedHorse(charId, horseId)
    return MySQL.scalar.await(
        'SELECT `id` FROM `bcc_player_horses` WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0 LIMIT 1',
        { horseId, charId }
    )
end

function TackRepository.getInventory(charId)
    return MySQL.query.await(
        ('SELECT `id`, `catalog_id`, `durability` FROM `%s` WHERE `charid` = ? ORDER BY `catalog_id`, `id`'):format(ITEMS_TABLE),
        { charId }
    ) or {}
end

function TackRepository.getLoadout(horseId, charId)
    return MySQL.query.await(([[
        SELECT l.`slot`, l.`tack_item_id`, i.`catalog_id`, i.`durability`
        FROM `%s` l
        INNER JOIN `%s` i ON i.`id` = l.`tack_item_id`
        INNER JOIN `bcc_player_horses` h ON h.`id` = l.`horse_id`
        WHERE l.`horse_id` = ? AND h.`charid` = ?
        ORDER BY l.`slot`
    ]]):format(LOADOUTS_TABLE, ITEMS_TABLE), { horseId, charId }) or {}
end

function TackRepository.getCharacterLoadouts(charId)
    return MySQL.query.await(([[
        SELECT l.`horse_id`, l.`slot`, l.`tack_item_id`, i.`catalog_id`, i.`durability`
        FROM `%s` l
        INNER JOIN `%s` i ON i.`id` = l.`tack_item_id`
        INNER JOIN `bcc_player_horses` h ON h.`id` = l.`horse_id`
        WHERE h.`charid` = ?
    ]]):format(LOADOUTS_TABLE, ITEMS_TABLE), { charId }) or {}
end

function TackRepository.resolveLoadout(rows)
    local loadout = {}
    for _, row in ipairs(rows or {}) do
        local item = Tack.GetItem(row.catalog_id)
        if item and item.slot == row.slot then
            loadout[row.slot] = {
                itemId = tonumber(row.tack_item_id),
                catalogId = item.id,
                durability = tonumber(row.durability) or 100,
            }
        end
    end
    return loadout
end

function TackRepository.replaceLoadout(horseId, charId, selections, purchases)
    local queries = {
        {
            query = ('DELETE l FROM `%s` l INNER JOIN `bcc_player_horses` h ON h.`id` = l.`horse_id` WHERE l.`horse_id` = ? AND h.`charid` = ?'):format(LOADOUTS_TABLE),
            values = { horseId, charId }
        }
    }

    for _, purchase in ipairs(purchases) do
        queries[#queries + 1] = {
            query = ('INSERT INTO `%s` (`charid`, `catalog_id`, `durability`, `acquisition_token`) VALUES (?, ?, 100, ?)'):format(ITEMS_TABLE),
            values = { charId, purchase.catalogId, purchase.token }
        }
        queries[#queries + 1] = {
            query = ('INSERT INTO `%s` (`horse_id`, `slot`, `tack_item_id`) SELECT ?, ?, `id` FROM `%s` WHERE `acquisition_token` = ? AND `charid` = ?'):format(LOADOUTS_TABLE, ITEMS_TABLE),
            values = { horseId, purchase.slot, purchase.token, charId }
        }
    end

    for _, selection in ipairs(selections) do
        queries[#queries + 1] = {
            query = ('DELETE l FROM `%s` l INNER JOIN `%s` i ON i.`id` = l.`tack_item_id` WHERE l.`tack_item_id` = ? AND i.`charid` = ?'):format(LOADOUTS_TABLE, ITEMS_TABLE),
            values = { selection.itemId, charId }
        }
        queries[#queries + 1] = {
            query = ('INSERT INTO `%s` (`horse_id`, `slot`, `tack_item_id`) SELECT ?, ?, `id` FROM `%s` WHERE `id` = ? AND `charid` = ?'):format(LOADOUTS_TABLE, ITEMS_TABLE),
            values = { horseId, selection.slot, selection.itemId, charId }
        }
    end

    return MySQL.transaction.await(queries)
end

function TackRepository.transferItem(itemId, fromCharId, toCharId)
    local equipped = MySQL.scalar.await(
        ('SELECT 1 FROM `%s` WHERE `tack_item_id` = ? LIMIT 1'):format(LOADOUTS_TABLE),
        { itemId }
    )
    if equipped then return false, 'equipped' end

    local changed = MySQL.update.await(
        ('UPDATE `%s` SET `charid` = ? WHERE `id` = ? AND `charid` = ?'):format(ITEMS_TABLE),
        { toCharId, itemId, fromCharId }
    )
    return (changed or 0) > 0
end
