Tack = Tack or {}

Tack.Slots = {
    { id = 'saddlecloth', source = 'Saddlecloths', label = 'Saddlecloths', category = 0x17CEB41A },
    { id = 'saddle',      source = 'Saddles',      label = 'Saddles',      category = 0xBAA7E618 },
    { id = 'stirrups',    source = 'Stirrups',     label = 'Stirrups',     category = 0xDA6DADCA },
    { id = 'saddlebag',   source = 'SaddleBags',   label = 'Saddlebags',   category = 0x80451C25 },
    { id = 'mane',        source = 'Manes',        label = 'Manes',        category = 0xAA0217AB },
    { id = 'tail',        source = 'Tails',        label = 'Tails',        category = 0x17CEB41A },
    { id = 'saddle_horn', source = 'SaddleHorns',  label = 'Saddle Horns', category = 0x05447332 },
    { id = 'bedroll',     source = 'Bedrolls',     label = 'Bedrolls',     category = 0xEFB31921 },
    { id = 'mask',        source = 'Masks',        label = 'Masks',        category = 0xD3500E5D },
    { id = 'mustache',    source = 'Mustaches',    label = 'Mustaches',    category = 0x30DEFDDF },
    { id = 'holster',     source = 'Holsters',     label = 'Holsters',     category = 0xAC106B30 },
    { id = 'bridle',      source = 'Bridles',      label = 'Bridles',      category = 0x94B2E3AF },
    { id = 'horseshoes',  source = 'Horseshoes',   label = 'Horseshoes',   category = 0xFACFC3C0 },
}

Tack.SlotsById = {}
Tack.Catalog = {}
Tack.CatalogBySlot = {}

local configuredCurrency = tonumber(TackConfig.currency)
if configuredCurrency ~= TackCurrency.CASH
    and configuredCurrency ~= TackCurrency.GOLD
    and configuredCurrency ~= TackCurrency.EITHER
    and configuredCurrency ~= TackCurrency.FREE then
    configuredCurrency = TackCurrency.EITHER
end
TackConfig.currency = configuredCurrency

---@param value number|string
---@return integer|nil hash
---@return string|nil label
local function normalizeHash(value)
    local hash = tonumber(value)
    if not hash then return nil end
    return hash, ('0x%08X'):format(hash & 0xFFFFFFFF)
end

for order, slot in ipairs(Tack.Slots) do
    slot.order = order
    Tack.SlotsById[slot.id] = slot
    Tack.CatalogBySlot[slot.id] = {}

    for index, rawItem in ipairs(HorseComp[slot.source] or {}) do
        local hash, hashLabel = normalizeHash(rawItem.hash)
        if hash and hashLabel then
            local itemId = ('%s_%s'):format(slot.id, hashLabel:lower())
            local item = {
                id = itemId,
                slot = slot.id,
                hash = hash,
                label = rawItem.label or ('%s %s'):format(slot.label, hashLabel),
                cashPrice = math.max(0, tonumber(rawItem.cashPrice) or 0),
                goldPrice = math.max(0, tonumber(rawItem.goldPrice) or 0),
                currency = configuredCurrency,
                order = index,
            }
            Tack.Catalog[itemId] = item
            Tack.CatalogBySlot[slot.id][#Tack.CatalogBySlot[slot.id] + 1] = item
        end
    end
end

function Tack.GetItem(itemId)
    return type(itemId) == 'string' and Tack.Catalog[itemId] or nil
end

function Tack.GetSlot(slotId)
    return type(slotId) == 'string' and Tack.SlotsById[slotId] or nil
end

function Tack.FormatPrice(item)
    if not item or item.currency == TackCurrency.FREE then return 'FREE' end
    if item.currency == TackCurrency.CASH then return ('$%d'):format(item.cashPrice) end
    if item.currency == TackCurrency.GOLD then return ('%d gold'):format(item.goldPrice) end
    return ('$%d / %d gold'):format(item.cashPrice, item.goldPrice)
end
