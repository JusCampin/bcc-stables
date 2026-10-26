local function formatCheckoutTotal(currency)
    local total = TackSession.getCheckoutTotal(currency)
    return currency == 'gold' and ('Total: %d gold'):format(total) or ('Total: $%d'):format(total)
end

local function addCheckoutLoadout(page, session)
    local lines = {}
    for _, slot in ipairs(Tack.Slots) do
        local equipped = session.preview[slot.id]
        if equipped then
            local item = Tack.GetItem(equipped.catalogId)
            lines[#lines + 1] = ('%s: %s (%s)'):format(
                slot.label,
                item and item.label or 'Unknown',
                equipped.purchase and 'new' or 'owned'
            )
        end
    end

    StableUI.AddText(
        page,
        'tack_checkout_loadout',
        #lines > 0 and table.concat(lines, '\n') or 'All equipped tack will be removed.'
    )
end

function BuildTackCheckoutPage()
    local session = TackSession.getState()
    if not session or not TackSession.hasChanges() then
        Core.NotifyRightTip('No tack changes to review.', 4000)
        return false
    end

    local page = StableUI.RegisterPage('tack_checkout')
    local allowCash, allowGold, isFree = TackSession.getCheckoutCurrencies()
    local preferred = TackSession.getCurrency()
    local currency = preferred == 'gold' and allowGold and 'gold' or (allowCash and 'cash' or 'gold')
    local priceDisplay
    local checkoutPending = false

    StableUI.AddHeader(page, 'Tack Checkout')
    addCheckoutLoadout(page, session)

    if isFree then
        StableUI.AddText(page, 'tack_checkout_total', 'No charge', StableUI.Styles.success)
    elseif not allowCash and not allowGold then
        StableUI.AddText(
            page,
            'tack_checkout_error',
            'The selected items do not share a compatible currency.',
            StableUI.Styles.danger
        )
    elseif allowCash and allowGold then
        priceDisplay = StableUI.AddText(
            page, 'tack_checkout_total', formatCheckoutTotal(currency), StableUI.Styles.success
        )
        page:RegisterElement('arrows', {
            id = 'tack_checkout_currency', label = _U('currency') or 'Currency', slot = 'content',
            start = currency == 'gold' and 2 or 1, persist = true,
            options = {
                { display = _U('cash') or 'Cash', extra = 'cash' },
                { display = _U('gold') or 'Gold', extra = 'gold' },
            },
        }, function(data)
            local option = data and data.value
            if not option then return end
            currency = option.extra
            TackSession.setCurrency(currency)
            priceDisplay:update({ value = formatCheckoutTotal(currency) })
        end)
    else
        StableUI.AddText(
            page,
            'tack_checkout_currency_label',
            allowCash and (_U('cash') or 'Cash') or (_U('gold') or 'Gold')
        )
        StableUI.AddText(page, 'tack_checkout_total', formatCheckoutTotal(currency), StableUI.Styles.success)
    end

    StableUI.AddFooter(page)
    StableUI.AddButton(
        page,
        'tack_checkout_submit',
        isFree and 'Apply Changes' or (_U('purchase') or 'Purchase'),
        'footer',
        function()
            if checkoutPending then return end
            if not allowCash and not allowGold then
                Core.NotifyRightTip('Choose items that share cash or gold as a payment method.', 4000)
                return
            end

            checkoutPending = true
            TackSession.checkout(currency, function(success, result)
                checkoutPending = false
                if not success then
                    Core.NotifyRightTip(type(result) == 'string' and result or 'Tack purchase failed.', 5000)
                    return
                end
                BuildTackCategoriesPage()
                StableUI.OpenPage('tack_categories')
            end)
        end,
        StableUI.Styles.success
    )
    StableUI.AddButton(page, 'tack_checkout_back', _U('backButton') or 'Back', 'footer', function()
        StopRotation()
        BuildTackCategoriesPage()
        StableUI.OpenPage('tack_categories')
    end)
    return true
end
