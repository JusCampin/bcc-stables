ServerUtils = ServerUtils or {}

---@param value string|table|nil
---@param fallback table
---@return table
function ServerUtils.decodeTable(value, fallback)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return fallback end

    local success, decoded = pcall(json.decode, value)
    if success and type(decoded) == 'table' then
        return decoded
    end

    DBG:Warning('Invalid JSON found in persisted data; using the supplied fallback.')
    return fallback
end

---@param value any
---@return boolean
function ServerUtils.databaseBoolean(value)
    return value == true or tonumber(value) == 1
end

---@param sourceId integer
---@param context string
---@return table|nil character
---@return integer|nil charId
function ServerUtils.getCharacter(sourceId, context)
    local user = Core.getUser(sourceId)
    if not user then
        DBG:Error(('User not found for %s. Source: %s'):format(context, tostring(sourceId)))
        return nil, nil
    end

    local character = user.getUsedCharacter
    if not character then
        DBG:Error(('Character not found for %s. Source: %s'):format(context, tostring(sourceId)))
        return nil, nil
    end

    local charId = tonumber(character.charIdentifier)
    if not charId then
        DBG:Error(('Invalid character identifier for %s. Source: %s'):format(context, tostring(sourceId)))
        return nil, nil
    end

    return character, charId
end

---@param model string
---@return table|nil colorConfig
---@return string|nil breedName
function ServerUtils.getHorseConfig(model)
    if type(model) ~= 'string' or model == '' then return nil, nil end

    local mapping = Horses.ModelToBreedMap and Horses.ModelToBreedMap[model]
    local breedName = mapping and mapping.breed
    local catalog = breedName and Horses.BreedCatalog and Horses.BreedCatalog[breedName]
    local colorConfig = catalog and catalog.colors and catalog.colors[model]

    return colorConfig, breedName
end

---@param value any
---@param maxLength integer|nil
---@return string|nil
function ServerUtils.normalizeName(value, maxLength)
    if type(value) ~= 'string' then return nil end

    local normalized = value:match('^%s*(.-)%s*$')
    if normalized == '' or #normalized > (maxLength or 100) then return nil end
    return normalized
end

---@param sourceId integer
---@return integer
function ServerUtils.getHorseLimit(sourceId)
    return IsSourceAuthorizedTrainer(sourceId)
        and (tonumber(Config.horseLimits.trainer) or 10)
        or (tonumber(Config.horseLimits.player) or 5)
end

-- Discord logging
if Config.integrations.discord.enabled == true then
    Discord = BccUtils.Discord.setup(
        Config.integrations.discord.webhookUrl,
        Config.integrations.discord.title,
        Config.integrations.discord.avatarUrl
    )
end

function LogToDiscord(name, description, embeds)
    if Config.integrations.discord.enabled == true then
        Discord:sendMessage(name, description, embeds)
    end
end

function IsSourceAuthorizedTrainer(src)
    local characterState = Player(src).state.Character
    if not characterState then return false end

    local activeJob = characterState.Job or 'unemployed'
    local activeGrade = tonumber(characterState.Grade) or 0

    local trainerConfig = Config.training.trainerJobs[activeJob]
    local minimumRequiredGrade = type(trainerConfig) == 'table'
        and trainerConfig.minimumGrade
        or trainerConfig
    if minimumRequiredGrade and activeGrade >= minimumRequiredGrade then
        return true
    end

    return false
end

---@param src integer
---@return table|nil profile
function GetSourceTrainerProfile(src)
    local characterState = Player(src).state.Character
    if not characterState then return nil end

    local profile = Config.training.trainerJobs[characterState.Job or 'unemployed']
    local minimumGrade = type(profile) == 'table' and profile.minimumGrade or profile
    if minimumGrade == nil or (tonumber(characterState.Grade) or 0) < minimumGrade then return nil end

    if type(profile) ~= 'table' then
        return { minimumGrade = minimumGrade, xpMultiplier = 1.0, cooldownMultiplier = 1.0 }
    end

    return profile
end

CreateThread(function()
    for modelName in pairs(Horses.ModelToBreedMap or {}) do
        local modelIntegerHash = joaat(modelName)
        InverseModelHashMap[modelIntegerHash] = modelName
    end

    DBG:Info('Model hash registry successfully compiled.')
end)
