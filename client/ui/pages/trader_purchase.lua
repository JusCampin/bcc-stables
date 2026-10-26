local function formatHorsePrice(coat, useCash)
    local currency = tonumber(coat.currency) or 3
    if currency == 4 then return _U('free') or 'FREE' end
    return useCash
        and ('$%d'):format(tonumber(coat.cashPrice) or 0)
        or ('%d gold'):format(tonumber(coat.goldPrice) or 0)
end

function BuildTraderPurchasePage()
    local breedName = SelectedBreedName
    local model = SelectedColorKey
    local breed = breedName and Horses.BreedCatalog[breedName]
    local coat = breed and breed.colors and breed.colors[model]
    if not coat then
        Core.NotifyRightTip('The selected horse is unavailable.', 4000)
        return false
    end

    local page = StableUI.RegisterPage('trader_purchase')
    local currency = tonumber(coat.currency) or 3
    local useCash = currency ~= 2
    local gender = 'male'
    local horseName = ''
    local pending = false

    StableUI.AddHeader(page, breedName)
    StableUI.AddText(page, 'horse_purchase_coat', 'Coat: ' .. (coat.color or 'Unknown'))
    local priceDisplay = StableUI.AddText(
        page,
        'horse_purchase_price',
        'Price: ' .. formatHorsePrice(coat, useCash),
        currency == 4 and StableUI.Styles.success or StableUI.Styles.text
    )

    if currency == 3 then
        page:RegisterElement('arrows', {
            id = 'horse_purchase_currency',
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
            priceDisplay:update({ value = 'Price: ' .. formatHorsePrice(coat, useCash) })
        end)
    end

    page:RegisterElement('arrows', {
        id = 'horse_purchase_gender',
        label = _U('selectGender') or 'Gender',
        slot = 'content',
        start = 1,
        options = {
            { display = _U('male') or 'Male', extra = 'male' },
            { display = _U('female') or 'Female', extra = 'female' },
        },
        persist = true,
    }, function(selection)
        gender = selection.value.extra
    end)

    page:RegisterElement('input', {
        id = 'horse_purchase_name',
        label = _U('nameHorse') or 'Horse Name',
        slot = 'content',
        placeholder = 'Enter a name...',
        value = '',
    }, function(input)
        horseName = input.value or ''
    end)

    StableUI.AddButton(page, 'horse_purchase_confirm', _U('purchase') or 'Purchase', 'content', function()
        if pending then return end
        local name = StableUI.Trim(horseName)
        if name == '' then
            Core.NotifyRightTip(_U('enterName') or 'Please enter a valid horse name.', 4000)
            return
        end

        pending = true
        Core.Callback.TriggerAsync('bcc-horses:ProcessHorsePurchase', function(success, result)
            pending = false
            if not success then
                Core.NotifyRightTip(result or 'Horse purchase failed.', 5000)
                return
            end

            FetchRosterAndAction(function()
                ShowSelectedHorseRoster(result, true)
            end)
        end, {
            ModelH = model,
            Currency = currency,
            IsCash = useCash,
            Gender = gender,
            name = name,
            captured = 0,
            origin = 'buyHorse',
            siteId = Site,
        })
    end, StableUI.Styles.success)

    StableUI.AddFooter(page)
    StableUI.AddButton(page, 'horse_purchase_back', _U('backButton') or 'Back', 'footer', function()
        if pending then return end
        StopRotation()
        StableUI.OpenPage('trader_colors')
    end)
    return true
end
