local activeSales = {}

local function saleKey(charId, horseId)
    return ('%s:%s'):format(charId, horseId)
end

local function payoutCharacter(character, currencyType, amount)
    if amount > 0 then
        character.addCurrency(currencyType, amount)
    end
end

Core.Callback.Register('bcc-horses:SellMyHorse', function(source, cb, data)
    local src = source
    local character, charId = ServerUtils.getCharacter(src, 'owned horse sale callback')
    if not character or not charId or type(data) ~= 'table' then return cb(false) end

    local horseId = tonumber(data.horseId)
    if not horseId then return cb(false) end

    local lockKey = saleKey(charId, horseId)
    if activeSales[lockKey] then return cb(false) end
    activeSales[lockKey] = true

    MySQL.single(
        'SELECT `model`, `captured` FROM `bcc_player_horses` WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0 LIMIT 1',
        { horseId, charId },
        function(row)
            if not row then
                activeSales[lockKey] = nil
                return cb(false)
            end

            local colorConfig = ServerUtils.getHorseConfig(row.model)
            if not colorConfig then
                activeSales[lockKey] = nil
                return cb(false)
            end

            local multiplier = ServerUtils.databaseBoolean(row.captured)
                and (tonumber(Config.taming.sale.priceMultiplier) or 0.25)
                or (tonumber(Config.sales.purchasedHorsePriceMultiplier) or 0.5)
            local configuredCurrency = tonumber(colorConfig.currency) or 3
            local currencyType = data.isCashPayout == true and 0 or 1

            if configuredCurrency == 1 then currencyType = 0 end
            if configuredCurrency == 2 then currencyType = 1 end

            local basePrice = currencyType == 0
                and (tonumber(colorConfig.cashPrice) or 0)
                or (tonumber(colorConfig.goldPrice) or 0)
            local payout = configuredCurrency == 4 and 0 or math.max(0, math.ceil(basePrice * multiplier))

            MySQL.update(
                'DELETE FROM `bcc_player_horses` WHERE `id` = ? AND `charid` = ?',
                { horseId, charId },
                function(rowsAffected)
                    activeSales[lockKey] = nil
                    if not rowsAffected or rowsAffected <= 0 then return cb(false) end

                    HorseXpCache[horseId] = nil
                    EmitHorseServerLifecycleEvent('bcc-horses:server:horseRemoved', {
                        id = horseId,
                        ownerCharId = charId,
                        reason = 'sold',
                        source = src,
                    })
                    payoutCharacter(character, currencyType, payout)

                    local message = payout > 0
                        and ((_U('soldHorse') or 'Horse Sold: ') .. (currencyType == 0 and ('$' .. payout) or (payout .. ' Gold')))
                        or 'Mount successfully returned to the stable.'
                    Core.NotifyRightTip(src, message, 4000)
                    LogToDiscord(charId, _U('discordHorseSold') or 'Horse sold.')
                    cb(true)
                end
            )
        end
    )
end)

local function getNearbyTamedHorse(src, modelHash, netId)
    local targetNetId = tonumber(netId)
    if not targetNetId or targetNetId == 0 then return nil end

    local horse = NetworkGetEntityFromNetworkId(targetNetId)
    if not horse or horse == 0 or not DoesEntityExist(horse) then return nil end
    if GetEntityModel(horse) ~= tonumber(modelHash) then return nil end

    local state = Entity(horse).state
    if tonumber(state.netId) ~= targetNetId or state.myHorseId then return nil end

    local playerPed = GetPlayerPed(src)
    if playerPed == 0 then return nil end

    return #(GetEntityCoords(playerPed) - GetEntityCoords(horse)) <= 10.0 and horse or nil
end

RegisterNetEvent('bcc-horses:SellTamedHorse', function(modelHash, netId)
    local src = source
    local character, charId = ServerUtils.getCharacter(src, 'tamed horse sale event')
    if not character or not charId then return end

    local sellConfig = Config.taming.sale
    if not sellConfig.enabled then return end
    if Config.training.tamingTrainerOnly and not IsSourceAuthorizedTrainer(src) then return end

    local cooldownActive, secondsRemaining = CooldownService.isActive('sellTame', charId)
    if cooldownActive then
        Core.NotifyRightTip(src, ('%s (%d seconds)'):format(_U('sellCooldown') or 'Sale cooldown active.', secondsRemaining), 4000)
        return
    end

    local horse = getNearbyTamedHorse(src, modelHash, netId)
    local modelName = horse and InverseModelHashMap[tonumber(modelHash)]
    local colorConfig = modelName and ServerUtils.getHorseConfig(modelName)
    if not horse or not colorConfig then
        DBG:Warning(('Rejected invalid tamed horse sale from source %s.'):format(src))
        return
    end

    local currencyType = type(sellConfig.currency) == 'string' and sellConfig.currency:lower() == 'gold' and 1 or 0
    local basePrice = currencyType == 1
        and (tonumber(colorConfig.goldPrice) or 0)
        or (tonumber(colorConfig.cashPrice) or 0)
    local payout = math.max(0, math.ceil(basePrice * (tonumber(sellConfig.priceMultiplier) or 0.25)))

    payoutCharacter(character, currencyType, payout)
    CooldownService.set('sellTame', charId)
    DeleteEntity(horse)

    local message = currencyType == 1
        and ((_U('soldHorse') or 'Horse Sold: ') .. payout .. ' Gold')
        or ((_U('soldHorse') or 'Horse Sold: ') .. '$' .. payout)
    Core.NotifyRightTip(src, message, 4000)
    LogToDiscord(charId, _U('discordTamedSold') or 'Tamed horse sold.')
end)
