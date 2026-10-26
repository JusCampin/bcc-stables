TackService = TackService or {}

local tackLocks = {}

local function canUseTackShop(src, siteId)
    local site = type(siteId) == 'string' and Stables[siteId]
    if not site then return false end
    local playerPed = GetPlayerPed(src)
    if playerPed == 0 or #(GetEntityCoords(playerPed) - site.npc.coords) > 10.0 then return false end

    if site.shop.jobsEnabled then
        local characterState = Player(src).state.Character or {}
        local job = characterState.Job or 'unemployed'
        local grade = tonumber(characterState.Grade) or 0
        if grade < (tonumber(site.shop.jobs[job]) or math.huge) then return false end
    end
    return true
end

local function release(lockKey)
    tackLocks[lockKey] = nil
end

local function serializeLoadout(rows)
    local loadout = {}
    for _, row in ipairs(rows or {}) do
        local catalogItem = Tack.GetItem(row.catalog_id)
        if catalogItem and catalogItem.slot == row.slot then
            loadout[row.slot] = {
                itemId = tonumber(row.tack_item_id),
                catalogId = row.catalog_id,
                durability = tonumber(row.durability) or 100,
            }
        end
    end
    return loadout
end

local function createToken()
    return ('%04x%04x-%04x-%04x-%04x-%04x%04x%04x'):format(
        math.random(0, 0xFFFF), math.random(0, 0xFFFF), math.random(0, 0xFFFF),
        math.random(0, 0xFFFF), math.random(0, 0xFFFF), math.random(0, 0xFFFF),
        math.random(0, 0xFFFF), math.random(0, 0xFFFF)
    )
end

local function normalizeCheckout(charId, horseId, desired, currency)
    if type(desired) ~= 'table' then return nil, 'Invalid tack selection.' end
    if currency ~= 'cash' and currency ~= 'gold' then return nil, 'Invalid currency.' end

    local inventoryRows = TackRepository.getInventory(charId)
    local inventory = {}
    for _, row in ipairs(inventoryRows) do
        inventory[tonumber(row.id)] = row
    end

    local selections, purchases, usedInstances = {}, {}, {}
    local total = 0

    for _, slot in ipairs(Tack.Slots) do
        local choice = desired[slot.id]
        if choice ~= nil and choice ~= false then
            if type(choice) ~= 'table' then return nil, 'Invalid tack selection.' end

            if choice.itemId then
                local itemId = tonumber(choice.itemId)
                local owned = itemId and inventory[itemId]
                local catalogItem = owned and Tack.GetItem(owned.catalog_id)
                if not catalogItem or catalogItem.slot ~= slot.id or usedInstances[itemId] then
                    return nil, 'Owned tack selection is invalid.'
                end
                usedInstances[itemId] = true
                selections[#selections + 1] = { slot = slot.id, itemId = itemId }
            elseif choice.catalogId then
                local catalogItem = Tack.GetItem(choice.catalogId)
                if not catalogItem or catalogItem.slot ~= slot.id then
                    return nil, 'Catalog tack selection is invalid.'
                end
                if catalogItem.currency ~= TackCurrency.EITHER and catalogItem.currency ~= TackCurrency.FREE
                    and not (catalogItem.currency == TackCurrency.CASH and currency == 'cash')
                    and not (catalogItem.currency == TackCurrency.GOLD and currency == 'gold') then
                    return nil, 'That item cannot be purchased with this currency.'
                end

                total = total + (currency == 'gold' and catalogItem.goldPrice or catalogItem.cashPrice)
                purchases[#purchases + 1] = {
                    slot = slot.id,
                    catalogId = catalogItem.id,
                    token = createToken(),
                }
            else
                return nil, 'Invalid tack selection.'
            end
        end
    end

    return { selections = selections, purchases = purchases, total = total }
end

local function checkoutHasChanges(currentRows, checkout)
    if #checkout.purchases > 0 then return true end

    local current = {}
    for _, row in ipairs(currentRows or {}) do
        current[row.slot] = tonumber(row.tack_item_id)
    end

    local desired = {}
    for _, selection in ipairs(checkout.selections) do
        desired[selection.slot] = selection.itemId
    end

    for _, slot in ipairs(Tack.Slots) do
        if current[slot.id] ~= desired[slot.id] then return true end
    end
    return false
end

Core.Callback.Register('bcc-horses:GetTackShopData', function(source, cb, data)
    local _, charId = ServerUtils.getCharacter(source, 'tack shop data callback')
    local horseId = type(data) == 'table' and tonumber(data.horseId)
    local siteId = type(data) == 'table' and data.siteId
    if not charId or not horseId or not canUseTackShop(source, siteId)
        or not TackRepository.getOwnedHorse(charId, horseId) then
        return cb(false)
    end

    cb({
        inventory = TackRepository.getInventory(charId),
        loadout = serializeLoadout(TackRepository.getLoadout(horseId, charId)),
    })
end)

Core.Callback.Register('bcc-horses:CheckoutTack', function(source, cb, data)
    local src = source
    local character, charId = ServerUtils.getCharacter(src, 'tack checkout callback')
    local horseId = type(data) == 'table' and tonumber(data.horseId)
    if not character or not charId or not horseId or not canUseTackShop(src, data.siteId) then
        return cb(false, 'Invalid purchase request.')
    end

    local lockKey = ('%s:%s'):format(charId, horseId)
    if tackLocks[lockKey] then return cb(false, 'A tack transaction is already active.') end
    tackLocks[lockKey] = true

    if not TackRepository.getOwnedHorse(charId, horseId) then
        release(lockKey)
        return cb(false, 'Horse ownership could not be verified.')
    end

    local checkout, checkoutError = normalizeCheckout(charId, horseId, data.loadout, data.currency)
    if not checkout then
        release(lockKey)
        return cb(false, checkoutError)
    end


    local currentLoadout = TackRepository.getLoadout(horseId, charId)
    if not checkoutHasChanges(currentLoadout, checkout) then
        release(lockKey)
        return cb(false, 'No tack changes were selected.')
    end

    local currencyType = data.currency == 'gold' and 1 or 0
    local balance = currencyType == 1 and tonumber(character.gold) or tonumber(character.money)
    if (balance or 0) < checkout.total then
        release(lockKey)
        return cb(false, currencyType == 1 and (_U('shortGold') or 'Insufficient gold!') or (_U('shortCash') or 'Insufficient cash!'))
    end

    if checkout.total > 0 then character.removeCurrency(currencyType, checkout.total) end
    local success = TackRepository.replaceLoadout(horseId, charId, checkout.selections, checkout.purchases)
    if not success then
        if checkout.total > 0 then character.addCurrency(currencyType, checkout.total) end
        release(lockKey)
        DBG:Error(('Tack checkout transaction failed for character %s, horse %s.'):format(charId, horseId))
        return cb(false, 'The tack transaction could not be saved. Your payment was refunded.')
    end

    local loadout = serializeLoadout(TackRepository.getLoadout(horseId, charId))
    release(lockKey)
    local successMessage = checkout.total > 0
        and (_U('purchaseSuccessful') or 'Purchase successful!')
        or 'Tack updated successfully.'
    Core.NotifyRightTip(src, successMessage, 4000)
    cb(true, { loadout = loadout, charged = { currency = data.currency, amount = checkout.total } })
end)

function TackService.transferItem(itemId, fromCharId, toCharId)
    itemId, fromCharId, toCharId = tonumber(itemId), tonumber(fromCharId), tonumber(toCharId)
    if not itemId or not fromCharId or not toCharId or fromCharId == toCharId then return false, 'invalid' end
    return TackRepository.transferItem(itemId, fromCharId, toCharId)
end
