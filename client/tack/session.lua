TackSession = TackSession or {}

local state
local openRequestId = 0

local function copyLoadout(loadout)
    local copy = {}
    for slotId, equipped in pairs(loadout or {}) do
        copy[slotId] = {
            itemId = equipped.itemId,
            catalogId = equipped.catalogId,
            durability = equipped.durability,
        }
    end
    return copy
end

local function updateRoster(loadout)
    local equippedItemIds = {}
    for _, equipped in pairs(loadout or {}) do
        if equipped.itemId then equippedItemIds[tonumber(equipped.itemId)] = true end
    end

    for _, horse in ipairs(MyHorsesData or {}) do
        for slotId, equipped in pairs(horse.tackLoadout or {}) do
            if equippedItemIds[tonumber(equipped.itemId)] then
                horse.tackLoadout[slotId] = nil
            end
        end
        if tonumber(horse.id) == state.horseId then
            horse.tackLoadout = copyLoadout(loadout)
        end
    end
end

function TackSession.open(horseId, entity, siteId, onReady)
    horseId = tonumber(horseId)
    if not horseId or not DoesEntityExist(entity) then return false end

    openRequestId = openRequestId + 1
    local requestId = openRequestId
    Core.Callback.TriggerAsync('bcc-horses:GetTackShopData', function(data)
        if requestId ~= openRequestId then return end
        if type(data) ~= 'table' then
            Core.NotifyRightTip('Unable to load tack inventory.', 4000)
            return
        end

        state = {
            horseId = horseId,
            siteId = siteId,
            entity = entity,
            inventory = data.inventory or {},
            original = copyLoadout(data.loadout),
            preview = copyLoadout(data.loadout),
            pending = false,
            currency = 'cash',
        }
        if type(onReady) == 'function' then onReady() end
    end, { horseId = horseId, siteId = siteId })
    return true
end

function TackSession.getState()
    return state
end

function TackSession.hasChanges()
    if not state then return false end

    for _, slot in ipairs(Tack.Slots) do
        local original = state.original[slot.id]
        local preview = state.preview[slot.id]
        if (original and not preview) or (preview and not original) then return true end
        if original and preview then
            if preview.purchase or tonumber(original.itemId) ~= tonumber(preview.itemId) then return true end
        end
    end
    return false
end

function TackSession.setCurrency(currency)
    if state and (currency == 'cash' or currency == 'gold') then
        state.currency = currency
    end
end

function TackSession.getCurrency()
    return state and state.currency or 'cash'
end

function TackSession.getSlotItems(slotId, ownedOnly)
    if not state then return {} end
    local items = {}

    if ownedOnly then
        for _, owned in ipairs(state.inventory) do
            local catalogItem = Tack.GetItem(owned.catalog_id)
            if catalogItem and catalogItem.slot == slotId then
                items[#items + 1] = {
                    itemId = tonumber(owned.id),
                    catalogId = catalogItem.id,
                    label = catalogItem.label,
                    durability = tonumber(owned.durability) or 100,
                }
            end
        end
    else
        for _, catalogItem in ipairs(Tack.CatalogBySlot[slotId] or {}) do
            items[#items + 1] = catalogItem
        end
    end
    return items
end

function TackSession.select(slotId, choice)
    if not state or not Tack.GetSlot(slotId) then return false end
    state.preview[slotId] = choice and {
        itemId = choice.itemId,
        catalogId = choice.catalogId,
        durability = choice.durability,
        purchase = choice.purchase == true,
    } or nil
    HorseAppearance.applyLoadout(state.entity, state.preview)
    return true
end

function TackSession.getCheckoutCurrencies()
    if not state then return false, false, true end
    local allowCash, allowGold, hasPurchase = true, true, false

    for _, equipped in pairs(state.preview) do
        if equipped.purchase then
            local item = Tack.GetItem(equipped.catalogId)
            if item and item.currency ~= TackCurrency.FREE then
                hasPurchase = true
                if item.currency == TackCurrency.CASH then allowGold = false end
                if item.currency == TackCurrency.GOLD then allowCash = false end
            end
        end
    end
    return allowCash, allowGold, not hasPurchase
end

function TackSession.getCheckoutTotal(currency)
    if not state then return 0 end
    local total = 0
    for _, equipped in pairs(state.preview) do
        if equipped.purchase then
            local item = Tack.GetItem(equipped.catalogId)
            if item and item.currency ~= TackCurrency.FREE then
                total = total + (currency == 'gold' and item.goldPrice or item.cashPrice)
            end
        end
    end
    return total
end

function TackSession.cancel()
    openRequestId = openRequestId + 1
    if not state then return end
    HorseAppearance.applyLoadout(state.entity, state.original)
    state = nil
end

function TackSession.checkout(currency, callback)
    if not state or state.pending or not TackSession.hasChanges() then return false end
    state.pending = true

    local desired = {}
    for _, slot in ipairs(Tack.Slots) do
        local choice = state.preview[slot.id]
        if choice then
            desired[slot.id] = choice.purchase
                and { catalogId = choice.catalogId }
                or { itemId = choice.itemId }
        else
            desired[slot.id] = false
        end
    end

    Core.Callback.TriggerAsync('bcc-horses:CheckoutTack', function(success, result)
        state.pending = false
        if success and type(result) == 'table' then
            state.original = copyLoadout(result.loadout)
            state.preview = copyLoadout(result.loadout)
            local knownItems = {}
            for _, owned in ipairs(state.inventory) do knownItems[tonumber(owned.id)] = true end
            for _, equipped in pairs(result.loadout) do
                if equipped.itemId and not knownItems[equipped.itemId] then
                    state.inventory[#state.inventory + 1] = {
                        id = equipped.itemId,
                        catalog_id = equipped.catalogId,
                        durability = equipped.durability,
                    }
                end
            end
            updateRoster(result.loadout)
            HorseAppearance.applyLoadout(state.entity, result.loadout)
        end
        if type(callback) == 'function' then callback(success, result) end
    end, { horseId = state.horseId, siteId = state.siteId, currency = currency, loadout = desired })
    return true
end
