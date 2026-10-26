local function getSaleQuote(horse)
    local breed, coat = StableUI.GetCoat(horse.model)
    if not coat then return nil end

    local captured = horse.captured == true or tonumber(horse.captured) == 1
    local multiplier = captured
        and tonumber(Config.taming.sale.priceMultiplier)
        or tonumber(Config.sales.purchasedHorsePriceMultiplier)

    return {
        breed = breed or 'Unknown',
        captured = captured,
        currency = tonumber(coat.currency) or 3,
        cash = math.ceil((tonumber(coat.cashPrice) or 0) * (multiplier or 0)),
        gold = math.ceil((tonumber(coat.goldPrice) or 0) * (multiplier or 0)),
    }
end

local function formatPayout(quote, useCash)
    if quote.currency == 4 then return _U('free') or 'No payout' end
    return useCash and ('$%d'):format(quote.cash) or ('%d gold'):format(quote.gold)
end

--- @param horse table
function BuildHorseSellPage(horse)
    local quote = type(horse) == 'table' and getSaleQuote(horse)
    if not quote then
        Core.NotifyRightTip('Sale information is unavailable for this horse.', 4000)
        return false
    end

    local page = StableUI.RegisterPage('horse_sell')
    local pending = false
    local useCash = quote.currency ~= 2
    local horseName = horse.name or ('Horse #' .. tostring(horse.id))

    StableUI.AddHeader(page, 'Confirm Horse Sale')
    StableUI.AddText(page, 'horse_sale_identity', ('Name: %s\nBreed: %s\nOrigin: %s'):format(
        horseName,
        quote.breed,
        quote.captured and 'Wild-Caught' or 'Purchased'
    ))
    page:RegisterElement('line', { slot = 'content' })

    local payoutDisplay = StableUI.AddText(
        page,
        'horse_sale_payout',
        'Payout: ' .. formatPayout(quote, useCash),
        quote.currency == 4 and StableUI.Styles.text or StableUI.Styles.success
    )

    if quote.currency == 3 then
        page:RegisterElement('arrows', {
            id = 'horse_sale_currency',
            label = _U('currency') or 'Currency',
            slot = 'content',
            start = 1,
            options = {
                { display = _U('cash') or 'Cash', extra = true },
                { display = _U('gold') or 'Gold', extra = false },
            },
            persist = true,
        }, function(selection)
            useCash = selection.value.extra
            payoutDisplay:update({ value = 'Payout: ' .. formatPayout(quote, useCash) })
        end)
    end

    StableUI.AddButton(page, 'horse_sale_confirm', 'Confirm Sale', 'content', function()
        if pending then return end
        pending = true

        Core.Callback.TriggerAsync('bcc-horses:SellMyHorse', function(success)
            pending = false
            if not success then
                Core.NotifyRightTip('The horse sale could not be completed.', 4000)
                return
            end

            StopRotation()
            ClearShopHorse()
            RemoveCachedHorse(horse.id)
            ExpandedHorseId = nil
            FetchRosterAndAction(function()
                BuildMyHorsesPage()
                StableUI.OpenPage('my_horses')
            end)
        end, { horseId = tonumber(horse.id), isCashPayout = useCash })
    end, StableUI.Styles.danger)

    StableUI.AddFooter(page)
    StableUI.AddButton(page, 'horse_sale_rotate', '↻ ' .. (_U('rotateButton') or 'Rotate'), 'footer', function()
        StableUI.ToggleRotation(-1)
    end)
    StableUI.AddButton(page, 'horse_sale_back', _U('backButton') or 'Back', 'footer', function()
        if pending then return end
        StopRotation()
        BuildMyHorsesPage()
        StableUI.OpenPage('my_horses')
    end)
    return true
end
