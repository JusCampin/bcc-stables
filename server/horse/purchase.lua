local MAX_HORSE_NAME_LENGTH <const> = 100
local activeTransactions = {}
local registeredTamedEntities = {}
local tamedEntityLocks = {}

local function canPurchaseAtStable(src, siteId, model)
    local site = type(siteId) == 'string' and Stables[siteId]
    if not site then return false end

    local playerPed = GetPlayerPed(src)
    if playerPed == 0 or #(GetEntityCoords(playerPed) - site.npc.coords) > 10.0 then return false end

    if site.trainerBuy and not IsSourceAuthorizedTrainer(src) then return false end

    local characterState = Player(src).state.Character or {}
    local job = characterState.Job or 'unemployed'
    local grade = tonumber(characterState.Grade) or 0
    if site.shop.jobsEnabled and grade < (tonumber(site.shop.jobs[job]) or math.huge) then return false end

    local allowedJobs
    for jobName, models in pairs(Horses.JobLocks or {}) do
        for _, lockedModel in ipairs(models) do
            if lockedModel == model then
                allowedJobs = allowedJobs or {}
                allowedJobs[jobName] = true
            end
        end
    end

    return not allowedJobs or allowedJobs[job] == true
end

local function maxHorsesForSource(src)
    return ServerUtils.getHorseLimit(src)
end

local function finishTransaction(charId, cb, success, result)
    activeTransactions[charId] = nil
    cb(success, result)
end

---@param src integer
---@param cb function
---@param context string
---@return table|nil character
---@return integer|nil charId
local function beginTransaction(src, cb, context)
    local character, charId = ServerUtils.getCharacter(src, context)
    if not character or not charId then
        cb(false, 'Character profile unavailable.')
        return nil, nil
    end

    if activeTransactions[charId] then
        cb(false, 'Transaction actively processing. Please wait.')
        return nil, nil
    end

    activeTransactions[charId] = true
    return character, charId
end

local function checkRosterCapacity(charId, src, cb, continuation, onRejected)
    MySQL.scalar(
        'SELECT COUNT(*) FROM `bcc_player_horses` WHERE `charid` = ? AND `is_dead` = 0',
        { charId },
        function(count)
            local limit = maxHorsesForSource(src)
            if (tonumber(count) or 0) >= limit then
                if onRejected then onRejected() end
                local message = (_U('horseLimit') or 'Stable full! Limit is ') .. limit .. (_U('horses') or ' horses.')
                return finishTransaction(charId, cb, false, message)
            end

            continuation()
        end
    )
end

local function insertHorse(character, charId, data, captured, stats, price, currencyType, cb, successLog, onSuccess, onFailure)
    local lifespan = HorseAging.newHorseValues()
    local query = [[INSERT INTO `bcc_player_horses`
        (`charid`, `name`, `model`, `gender`, `captured`, `stats`, `current_health`, `current_stamina`)
      VALUES (?, ?, ?, ?, ?, ?, 100, 100)]]
    local parameters = { charId, data.name, data.ModelH, data.Gender, captured, json.encode(stats) }

    if lifespan then
        query = [[INSERT INTO `bcc_player_horses`
            (`charid`, `name`, `model`, `gender`, `captured`, `stats`, `current_health`, `current_stamina`,
             `born_at`, `natural_death_at`, `aging_initialized`, `aging_exempt`)
          VALUES (?, ?, ?, ?, ?, ?, 100, 100, UTC_TIMESTAMP(), DATE_ADD(UTC_TIMESTAMP(), INTERVAL ? DAY), 1, 0)]]
        parameters[#parameters + 1] = lifespan
    end

    MySQL.insert(
        query,
        parameters,
        function(insertId)
            if not insertId or insertId <= 0 then
                if onFailure then onFailure() end
                return finishTransaction(charId, cb, false, 'Database write failure. No money was taken.')
            end

            if price > 0 then
                character.removeCurrency(currencyType, price)
            end

            if onSuccess then onSuccess() end
            LogToDiscord(charId, successLog)
            EmitHorseServerLifecycleEvent('bcc-horses:server:horseCreated', {
                id = tonumber(insertId),
                ownerCharId = charId,
                model = data.ModelH,
                name = data.name,
                gender = data.Gender,
                captured = captured == 1,
            })
            finishTransaction(charId, cb, true, insertId)
        end
    )
end

local function validatePurchaseData(data)
    if type(data) ~= 'table' then return nil, 'Invalid purchase data.' end

    local name = ServerUtils.normalizeName(data.name, MAX_HORSE_NAME_LENGTH)
    local gender = data.Gender == 'female' and 'female' or data.Gender == 'male' and 'male' or nil
    local colorConfig = ServerUtils.getHorseConfig(data.ModelH)

    if not name or not gender or not colorConfig then
        return nil, 'Invalid horse configuration.'
    end

    data.name = name
    data.Gender = gender
    return colorConfig
end

Core.Callback.Register('bcc-horses:ProcessHorsePurchase', function(source, cb, data)
    local src = source
    local character, charId = beginTransaction(src, cb, 'horse purchase callback')
    if not character or not charId then return end

    local colorConfig, validationError = validatePurchaseData(data)
    if not colorConfig then return finishTransaction(charId, cb, false, validationError) end
    if not canPurchaseAtStable(src, data.siteId, data.ModelH) then
        return finishTransaction(charId, cb, false, 'You cannot purchase this horse at the selected stable.')
    end

    checkRosterCapacity(charId, src, cb, function()
        local configuredCurrency = tonumber(colorConfig.currency) or 3
        local currencyType = data.IsCash == true and 0 or 1

        if configuredCurrency == 1 then currencyType = 0 end
        if configuredCurrency == 2 then currencyType = 1 end

        local price = currencyType == 0
            and (tonumber(colorConfig.cashPrice) or 0)
            or (tonumber(colorConfig.goldPrice) or 0)

        if configuredCurrency == 4 then price = 0 end

        local balance = currencyType == 0 and tonumber(character.money) or tonumber(character.gold)
        if price > 0 and (balance or 0) < price then
            local message = currencyType == 0 and (_U('shortCash') or 'Insufficient cash!') or (_U('shortGold') or 'Insufficient gold!')
            return finishTransaction(charId, cb, false, message)
        end

        insertHorse(
            character,
            charId,
            data,
            0,
            colorConfig.stats or {},
            price,
            currencyType,
            cb,
            _U('discordHorsePurchased') or 'Horse purchased.'
        )
    end)
end)

local function validateTamedEntity(src, data)
    local netId = tonumber(data.mountNetId)
    if not netId or netId == 0 or registeredTamedEntities[netId] or tamedEntityLocks[netId] then return nil end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    if GetEntityModel(entity) ~= joaat(data.ModelH) then return nil end

    local playerPed = GetPlayerPed(src)
    if playerPed == 0 then return nil end

    local distance = #(GetEntityCoords(playerPed) - GetEntityCoords(entity))
    return distance <= 10.0 and netId or nil
end

Core.Callback.Register('bcc-horses:RegisterHorse', function(source, cb, data)
    local src = source
    if not Config.taming.registration.enabled then return cb(false, 'Registration is currently disabled.') end
    if Config.training.tamingTrainerOnly and not IsSourceAuthorizedTrainer(src) then
        return cb(false, _U('trainerSellHorse') or 'Only registered trainers can manage wild mounts!')
    end

    local character, charId = beginTransaction(src, cb, 'tamed horse registration callback')
    if not character or not charId then return end

    local cooldownActive, secondsRemaining = CooldownService.isActive('registerTame', charId)
    if cooldownActive then
        return finishTransaction(charId, cb, false, ('Registration cooldown active (%d seconds).'):format(secondsRemaining))
    end

    local colorConfig, validationError = validatePurchaseData(data)
    local tamedNetId = colorConfig and data.origin == 'tameHorse' and validateTamedEntity(src, data)
    if not colorConfig or not tamedNetId then
        return finishTransaction(charId, cb, false, validationError or 'Invalid tamed horse entity.')
    end

    tamedEntityLocks[tamedNetId] = true

    checkRosterCapacity(charId, src, cb, function()
        local registerConfig = Config.taming.registration
        local currencyType = type(registerConfig.currency) == 'string' and registerConfig.currency:lower() == 'gold' and 1 or 0
        local price = math.max(0, tonumber(registerConfig.price) or 25)
        local balance = currencyType == 0 and tonumber(character.money) or tonumber(character.gold)

        if price > 0 and (balance or 0) < price then
            tamedEntityLocks[tamedNetId] = nil
            local message = currencyType == 0 and (_U('shortCash') or 'Insufficient cash!') or (_U('shortGold') or 'Insufficient gold!')
            return finishTransaction(charId, cb, false, message)
        end

        insertHorse(
            character,
            charId,
            data,
            1,
            colorConfig.stats or {},
            price,
            currencyType,
            cb,
            _U('discordTamedPurchased') or 'Tamed horse registered.',
            function()
                tamedEntityLocks[tamedNetId] = nil
                registeredTamedEntities[tamedNetId] = true
                CooldownService.set('registerTame', charId)
            end,
            function()
                tamedEntityLocks[tamedNetId] = nil
            end
        )
    end, function()
        tamedEntityLocks[tamedNetId] = nil
    end)
end)
