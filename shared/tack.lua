Tack = Tack or {}

Tack.Slots = {
    { id = 'saddlecloth', source = 'Saddlecloths', label = 'Saddlecloths', category = 0x17CEB41A },
    { id = 'saddle',      source = 'Saddles',      label = 'Saddles',      category = 0xBAA7E618 },
    { id = 'stirrups',    source = 'Stirrups',     label = 'Stirrups',     category = 0xDA6DADCA },
    { id = 'saddlebag',   source = 'SaddleBags',   label = 'Saddlebags',   category = 0x80451C25 },
    { id = 'mane',        source = 'Manes',        label = 'Manes',        category = 0xAA0217AB },
    { id = 'tail',        source = 'Tails',        label = 'Tails',        category = 0xA63CAE10 },
    { id = 'saddle_horn', source = 'SaddleHorns',  label = 'Saddle Horns', category = 0x05447332 },
    { id = 'bedroll',     source = 'Bedrolls',     label = 'Bedrolls',     category = 0xEFB31921 },
    { id = 'mask',        source = 'Masks',        label = 'Masks',        category = 0xD3500E5D },
    { id = 'mustache',    source = 'Mustaches',    label = 'Mustaches',    category = 0x30DEFDDF },
    { id = 'holster',     source = 'Holsters',     label = 'Holsters',     category = 0xAC106B30 },
    { id = 'bridle',      source = 'Bridles',      label = 'Bridles',      category = 0x94B2E3AF },
    { id = 'horseshoes',  source = 'Horseshoes',   label = 'Horseshoes',   category = 0xFACFC3C0 },
}

-- Feather item ownership/assignment policies for the currently enabled categories.
-- Keep the original saddle slot name so existing equipment and receipts replay.
Tack.PieceOrder = {'saddle', 'saddlecloth', 'stirrups', 'saddle_horn', 'saddlebag', 'bedroll', 'bridle', 'holster', 'horseshoes', 'mask', 'mane', 'tail', 'mustache'}
-- Component ownership is anchored to the saddle instance, even while stored.
Tack.AssemblyPrefixes = {stirrups='tack_stir_',saddle_horn='tack_horn_'}
-- Included visual parts when a saddle has no separately equipped upgrade.
Tack.SaddleDefaults = {
    stirrups = 'stirrups_0x03b3ab08',
    saddle_horn = 'saddle_horn_0x107d9598',
}
Tack.PieceSlots = {
    saddle = {itemName='horse_saddle',prefix='horse_',labelKey='saddles',numberKey='saddleNumber',pattern='^Saddle (%d+)$',emptyKey='noSaddle'},
    saddlecloth = {itemName='horse_saddlecloth',prefix='horse_cloth_',labelKey='saddlecloths',numberKey='saddleclothNumber',pattern='^Saddlecloth (%d+)$',emptyKey='noSaddlecloth'},
    stirrups = {itemName='horse_stirrups',prefix='horse_stir_',labelKey='stirrups',numberKey='stirrupNumber',pattern='^Stirrup (%d+)$',emptyKey='saddleDefault',requiresSaddle=true},
    saddle_horn = {itemName='horse_saddle_horn',prefix='horse_horn_',labelKey='saddleHorns',numberKey='saddleHornNumber',pattern='^Saddle Horn (%d+)$',emptyKey='saddleDefault',requiresSaddle=true},
    saddlebag = {itemName='horse_saddlebag',prefix='horse_bag_',labelKey='saddlebags',numberKey='saddlebagNumber',pattern='^Saddlebag (%d+)$',emptyKey='noSaddlebag',needsSaddle=true},
    bedroll = {itemName='horse_bedroll',prefix='horse_roll_',labelKey='bedrolls',numberKey='bedrollNumber',pattern='^Bedroll (%d+)$',emptyKey='noBedroll',needsSaddle=true},
    bridle = {itemName='horse_bridle',prefix='horse_bridle_',labelKey='bridles',numberKey='bridleNumber',pattern='^Bridle (%d+)$',emptyKey='noBridle'},
    holster = {itemName='horse_holster',prefix='horse_holster_',labelKey='holsters',numberKey='holsterNumber',pattern='^Holster (%d+)$',emptyKey='noHolster',needsSaddle=true},
    horseshoes = {itemName='horse_horseshoes',prefix='horse_shoes_',labelKey='horseshoes',numberKey='horseshoesNumber',pattern='^Horseshoe (%d+)$',emptyKey='noHorseshoe'},
    mask = {itemName='horse_mask',prefix='horse_mask_',labelKey='masks',numberKey='maskNumber',pattern='^Mask (%d+)$',emptyKey='noMask'},
    mane = {itemName='horse_mane',prefix='horse_mane_',labelKey='manes',numberKey='maneNumber',pattern='^Mane (%d+)$',emptyKey='noMane'},
    tail = {itemName='horse_tail',prefix='horse_tail_',labelKey='tails',numberKey='tailNumber',pattern='^Tail (%d+)$',emptyKey='noTail'},
    mustache = {itemName='horse_mustache',prefix='horse_must_',labelKey='mustaches',numberKey='mustacheNumber',pattern='^Mustache (%d+)$',emptyKey='noMustache'},
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
