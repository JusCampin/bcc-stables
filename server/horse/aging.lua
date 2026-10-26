HorseAging = HorseAging or {}

local TABLE_NAME <const> = 'bcc_player_horses'
local MONTH_NAMES <const> = {
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
}
local initialized = false

local function config()
    return Config.aging or {}
end

local function enabled()
    return config().enabled == true
end

local function daysPerYear()
    return math.max(1, math.floor(tonumber(config().daysPerYear) or 7))
end

local function lifespanDays()
    local lifespan = config().lifespan or {}
    local minimum = math.max(1, math.floor(tonumber(lifespan.minimumYears) or 18))
    local maximum = math.max(minimum, math.floor(tonumber(lifespan.maximumYears) or 28))
    return math.random(minimum, maximum) * daysPerYear()
end

local function lifeStage(ageYears)
    local stages = config().lifeStages or {}
    local age = math.max(0, tonumber(ageYears) or 0)
    if age >= (tonumber(stages.elderly) or 22) then return 'Elderly' end
    if age >= (tonumber(stages.senior) or 16) then return 'Senior' end
    if age >= (tonumber(stages.adult) or 3) then return 'Adult' end
    return 'Young'
end

local function displayDate(value)
    if value == nil then return nil end

    local timestamp = tonumber(value)
    if timestamp then
        -- oxmysql may return DATETIME values as JavaScript milliseconds.
        if timestamp > 100000000000 then timestamp = timestamp / 1000 end
        local success, date = pcall(os.date, '!*t', math.floor(timestamp))
        if success and date and MONTH_NAMES[date.month] then
            return ('%s %d, %d'):format(MONTH_NAMES[date.month], date.day, date.year)
        end
        return nil
    end

    local year, month, day = tostring(value):match('^(%d%d%d%d)[-/](%d%d)[-/](%d%d)')
    month = tonumber(month)
    day = tonumber(day)
    if not year or not month or not day or not MONTH_NAMES[month] then return nil end

    return ('%s %d, %s'):format(MONTH_NAMES[month], day, year)
end

function HorseAging.isEnabled()
    return enabled()
end

function HorseAging.selectList()
    if not enabled() then return '*' end
    return ('*, GREATEST(0, FLOOR(TIMESTAMPDIFF(DAY, `born_at`, UTC_TIMESTAMP()) / %d)) AS `age_years`')
        :format(daysPerYear())
end

function HorseAging.decorate(horse)
    if type(horse) ~= 'table' then return horse end
    horse.agingEnabled = enabled() and not ServerUtils.databaseBoolean(horse.aging_exempt)
    horse.bornAt = displayDate(horse.born_at)
    horse.naturalDeathAt = displayDate(horse.natural_death_at)
    horse.ageYears = horse.agingEnabled and math.max(0, tonumber(horse.age_years) or 0) or nil
    horse.lifeStage = horse.ageYears and lifeStage(horse.ageYears) or nil
    return horse
end

function HorseAging.newHorseValues()
    if not enabled() then return nil end
    return lifespanDays()
end

local function updateExpiredCache(rows)
    for _, row in ipairs(rows or {}) do
        local horseId = tonumber(row.id)
        if horseId and HorseXpCache[horseId] then
            HorseXpCache[horseId].is_selected = false
            HorseXpCache[horseId].is_dead = true
        end
    end
end

local function notifyExpiredOwners(rows)
    local byCharacter = {}
    for _, row in ipairs(rows or {}) do
        local charId = tonumber(row.charid)
        if charId then
            byCharacter[charId] = byCharacter[charId] or {}
            byCharacter[charId][#byCharacter[charId] + 1] = tonumber(row.id)
        end
    end

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local user = src and Core.getUser(src)
        local character = user and user.getUsedCharacter
        local horseIds = character and byCharacter[tonumber(character.charIdentifier)]
        if horseIds then TriggerClientEvent('bcc-horses:HorsesDiedOfOldAge', src, horseIds) end
    end
end

function HorseAging.expireCharacter(charId, callback)
    if not enabled() then return callback({}) end
    MySQL.query(
        ('SELECT `id`, `charid` FROM `%s` WHERE `charid` = ? AND `is_dead` = 0 AND `aging_exempt` = 0 AND `natural_death_at` IS NOT NULL AND `natural_death_at` <= UTC_TIMESTAMP()'):format(TABLE_NAME),
        { charId },
        function(rows)
            if not rows or #rows == 0 then return callback({}) end
            MySQL.update(
                ('UPDATE `%s` SET `is_selected` = 0, `is_writhing` = 0, `is_dead` = 1, `died_at` = UTC_TIMESTAMP(), `death_cause` = ? WHERE `charid` = ? AND `is_dead` = 0 AND `aging_exempt` = 0 AND `natural_death_at` IS NOT NULL AND `natural_death_at` <= UTC_TIMESTAMP()'):format(TABLE_NAME),
                { 'old_age', charId },
                function()
                    updateExpiredCache(rows)
                    notifyExpiredOwners(rows)
                    callback(rows)
                end
            )
        end
    )
end

local function expireAll()
    if not enabled() or not initialized then return end
    MySQL.query(
        ('SELECT `id`, `charid` FROM `%s` WHERE `is_dead` = 0 AND `aging_exempt` = 0 AND `natural_death_at` IS NOT NULL AND `natural_death_at` <= UTC_TIMESTAMP()'):format(TABLE_NAME),
        {},
        function(rows)
            if not rows or #rows == 0 then return end
            MySQL.update(
                ('UPDATE `%s` SET `is_selected` = 0, `is_writhing` = 0, `is_dead` = 1, `died_at` = UTC_TIMESTAMP(), `death_cause` = ? WHERE `is_dead` = 0 AND `aging_exempt` = 0 AND `natural_death_at` IS NOT NULL AND `natural_death_at` <= UTC_TIMESTAMP()'):format(TABLE_NAME),
                { 'old_age' },
                function()
                    updateExpiredCache(rows)
                    notifyExpiredOwners(rows)
                    DBG:Info(('Natural aging retired %d horse(s).'):format(#rows))
                end
            )
        end
    )
end

local function initializeExistingHorses()
    if not enabled() then return end
    local settings = config().existingHorses or {}
    local policy = tostring(settings.policy or 'grace_period')
    if policy ~= 'grace_period' and policy ~= 'reset_age' and policy ~= 'natural_age' and policy ~= 'exclude_existing' then
        DBG:Warning(('Unknown horse aging migration policy "%s"; using grace_period.'):format(policy))
        policy = 'grace_period'
    end
    local minimumRemainingDays = math.max(0, math.floor(tonumber(settings.minimumRemainingYears) or 2)) * daysPerYear()
    local rows = MySQL.query.await(
        ('SELECT `id`, `born_at`, TIMESTAMPDIFF(DAY, `born_at`, UTC_TIMESTAMP()) AS `age_days` FROM `%s` WHERE `is_dead` = 0 AND `aging_initialized` = 0'):format(TABLE_NAME)
    ) or {}

    local resetBirths, graceExtensions, excluded = 0, 0, 0
    for _, row in ipairs(rows) do
        local horseId = tonumber(row.id)
        if policy == 'exclude_existing' then
            MySQL.update.await(('UPDATE `%s` SET `aging_initialized` = 1, `aging_exempt` = 1 WHERE `id` = ?'):format(TABLE_NAME), { horseId })
            excluded = excluded + 1
        else
            local ageDays = tonumber(row.age_days)
            local invalidBirth = not ageDays or ageDays < 0
            local remainingDays = lifespanDays() - (invalidBirth and 0 or ageDays)

            if policy == 'reset_age' or invalidBirth then
                if policy == 'reset_age' then remainingDays = lifespanDays() end
                resetBirths = resetBirths + 1
                MySQL.update.await(
                    ('UPDATE `%s` SET `born_at` = UTC_TIMESTAMP(), `natural_death_at` = DATE_ADD(UTC_TIMESTAMP(), INTERVAL ? DAY), `aging_initialized` = 1, `aging_exempt` = 0 WHERE `id` = ?'):format(TABLE_NAME),
                    { remainingDays, horseId }
                )
            else
                if policy == 'grace_period' and remainingDays < minimumRemainingDays then
                    remainingDays = minimumRemainingDays
                    graceExtensions = graceExtensions + 1
                end
                MySQL.update.await(
                    ('UPDATE `%s` SET `natural_death_at` = DATE_ADD(UTC_TIMESTAMP(), INTERVAL ? DAY), `aging_initialized` = 1, `aging_exempt` = 0 WHERE `id` = ?'):format(TABLE_NAME),
                    { remainingDays, horseId }
                )
            end
        end
    end

    DBG:Info(('Horse aging migration: %d initialized, %d birth dates reset, %d grace extensions, %d excluded.')
        :format(#rows, resetBirths, graceExtensions, excluded))
end

MySQL.ready(function()
    initializeExistingHorses()
    initialized = true
    expireAll()
end)

CreateThread(function()
    while true do
        local minutes = math.max(1, tonumber(config().checkIntervalMinutes) or 15)
        Wait(minutes * 60000)
        expireAll()
    end
end)
