local function formatCooldown(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    if seconds >= 60 then
        local minutes = math.ceil(seconds / 60)
        return ('%d %s'):format(minutes, minutes == 1 and (_U('minute') or 'minute') or (_U('minutes') or 'minutes'))
    end
    return ('%d %s'):format(seconds, seconds == 1 and (_U('second') or 'second') or (_U('seconds') or 'seconds'))
end

local function notifySellCooldown(seconds)
    local remaining = formatCooldown(seconds)
    local template = _U('sellCooldown') or 'You must wait %s before selling another horse.'
    Core.NotifyRightTip(template:find('%%s') and template:format(remaining) or (template .. ' ' .. remaining), 4000)
end

local function getWildHorseData(mount)
    if not mount or mount == 0 or not DoesEntityExist(mount) then return nil end
    local modelHash = GetEntityModel(mount)
    local modelName = ResolveHorseModelName(modelHash)
    local breed, coat = StableUI.GetCoat(modelName)
    if not modelName or not coat then return nil end

    local sell = Config.taming.sale
    local currency = tostring(sell.currency or 'cash'):lower()
    local gold = currency == 'gold'
    local basePrice = gold and tonumber(coat.goldPrice) or tonumber(coat.cashPrice)

    return {
        modelHash = modelHash,
        modelName = modelName,
        breed = breed or 'Wild Horse',
        color = coat.color or 'Unknown',
        gold = gold,
        payout = math.ceil((basePrice or 0) * (tonumber(sell.priceMultiplier) or 0)),
    }
end

local function formatWildPayout(data)
    return data.gold and ('%d gold'):format(data.payout) or ('$%d'):format(data.payout)
end

local function formatRegistrationCost(config)
    local price = math.max(0, tonumber(config.price) or 0)
    return tostring(config.currency):lower() == 'gold'
        and ('%d gold'):format(price)
        or ('$%d'):format(price)
end

--- @param mount integer
function BuildWildHorsePage(mount)
    local horse = getWildHorseData(mount)
    if not horse then
        Core.NotifyRightTip('This wild horse cannot be managed at the stable.', 4000)
        return false
    end

    local page = StableUI.RegisterPage('wild_horse')
    local salePending = false
    local registerConfig = Config.taming.registration
    local sellConfig = Config.taming.sale
    StableUI.AddHeader(page, horse.breed)
    StableUI.AddText(page, 'wild_horse_summary', ('Coat: %s\nSale Value: %s'):format(
        horse.color, formatWildPayout(horse)
    ))

    if sellConfig.enabled then
        StableUI.AddButton(page, 'wild_horse_sell', 'Sell for ' .. formatWildPayout(horse), 'content', function()
            if salePending then return end
            salePending = true

            Core.Callback.TriggerAsync('bcc-horses:CheckPlayerCooldown', function(onCooldown, remaining)
                salePending = false
                if onCooldown then
                    notifySellCooldown(remaining)
                    return
                end
                if not CanPlayerManageTamedHorses() then
                    Core.NotifyRightTip(_U('trainerSellHorse') or 'Only trainers can sell wild horses.', 4000)
                    return
                end

                TriggerServerEvent('bcc-horses:SellTamedHorse', horse.modelHash, NetworkGetNetworkIdFromEntity(mount))
                StableMenu:Close()
                RemoveTamedHorseEntity(mount)
            end, 'sellTame')
        end, StableUI.Styles.danger)
    end

    if registerConfig.enabled then
        StableUI.AddButton(
            page,
            'wild_horse_register',
            'Register Horse (' .. formatRegistrationCost(registerConfig) .. ')',
            'content',
            function()
                if not CanPlayerManageTamedHorses() then
                    Core.NotifyRightTip(_U('trainerRegHorse') or 'Only trainers can register horses.', 4000)
                    return
                end

                local male = Citizen.InvokeNative(0x6D9F5FAA7488BA46, mount)
                StableMenu:Close()
                OpenNamingPage({
                    ModelH = horse.modelName,
                    origin = 'tameHorse',
                    Gender = male and 'male' or 'female',
                    mount = mount,
                    mountNetId = NetworkGetNetworkIdFromEntity(mount),
                })
            end,
            StableUI.Styles.success
        )
    end

    StableUI.AddFooter(page)
    StableUI.AddButton(page, 'wild_horse_close', _U('closeButton') or 'Close', 'footer', function()
        StableMenu:Close()
    end)
    return true
end
