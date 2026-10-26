CooldownService = CooldownService or {}

local SECONDS_PER_MINUTE <const> = 60
local cooldownsByCharacter = {}
local cooldownMinutesByKey <const> = {
    sellTame = function()
        return Config.taming.sale.cooldownMinutes
    end,
    registerTame = function()
        return Config.taming.registration.cooldownMinutes
    end
}

---@param cooldownKey string
---@return number
local function getDurationSeconds(cooldownKey)
    local resolveMinutes = cooldownMinutesByKey[cooldownKey]
    local minutes = resolveMinutes and tonumber(resolveMinutes()) or 0
    return math.max(0, minutes * SECONDS_PER_MINUTE)
end

---@param cooldownKey string
---@param charId integer|string
---@return boolean
function CooldownService.set(cooldownKey, charId)
    local normalizedCharId = tonumber(charId)
    if type(cooldownKey) ~= 'string' or cooldownKey == '' or not normalizedCharId then
        return false
    end

    if getDurationSeconds(cooldownKey) <= 0 then
        return false
    end

    local characterCooldowns = cooldownsByCharacter[normalizedCharId]
    if not characterCooldowns then
        characterCooldowns = {}
        cooldownsByCharacter[normalizedCharId] = characterCooldowns
    end

    characterCooldowns[cooldownKey] = os.time()
    DBG:Info(('Cooldown initialized for character %s and key %s.'):format(normalizedCharId, cooldownKey))
    return true
end

---@param cooldownKey string
---@param charId integer|string
---@return integer
function CooldownService.getRemaining(cooldownKey, charId)
    local normalizedCharId = tonumber(charId)
    if type(cooldownKey) ~= 'string' or cooldownKey == '' or not normalizedCharId then
        return 0
    end

    local durationSeconds = getDurationSeconds(cooldownKey)
    local characterCooldowns = cooldownsByCharacter[normalizedCharId]
    local startedAt = characterCooldowns and characterCooldowns[cooldownKey]

    if durationSeconds <= 0 or not startedAt then
        return 0
    end

    local remainingSeconds = durationSeconds - (os.time() - startedAt)
    if remainingSeconds > 0 then
        return math.ceil(remainingSeconds)
    end

    characterCooldowns[cooldownKey] = nil
    if next(characterCooldowns) == nil then
        cooldownsByCharacter[normalizedCharId] = nil
    end

    return 0
end

---@param cooldownKey string
---@param charId integer|string
---@return boolean isActive
---@return integer secondsRemaining
function CooldownService.isActive(cooldownKey, charId)
    local secondsRemaining = CooldownService.getRemaining(cooldownKey, charId)
    return secondsRemaining > 0, secondsRemaining
end

Core.Callback.Register('bcc-horses:CheckPlayerCooldown', function(source, cb, cooldownKey)
    local _, charId = ServerUtils.getCharacter(source, 'cooldown callback')
    if not charId then return cb(false, 0) end

    if type(cooldownKey) ~= 'string' or cooldownKey == '' then
        DBG:Warning(('Invalid cooldown key received from source: %s'):format(tostring(source)))
        return cb(false, 0)
    end

    if not cooldownMinutesByKey[cooldownKey] then
        DBG:Warning(('Unknown cooldown key received from source %s: %s'):format(source, cooldownKey))
        return cb(false, 0)
    end

    cb(CooldownService.isActive(cooldownKey, charId))
end)
