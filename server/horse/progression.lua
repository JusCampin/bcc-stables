local STAT_KEYS <const> = { 'health', 'stamina', 'handling', 'acceleration', 'speed' }
local MAX_STAT_RANK <const> = 9
local MAX_CORE_VALUE <const> = 100
local xpLocks = {}
local lastXpAward = {}

HorseProgression = HorseProgression or {}

local XP_REWARDS <const> = {
    riding = function() return Config.training.xpRewards.riding end,
    leading = function() return Config.training.xpRewards.leading end,
    brush = function() return Config.training.xpRewards.brush end,
    pat = function() return Config.training.xpRewards.pat end,
    feed = function() return Config.training.xpRewards.feed end,
    drink = function() return Config.training.xpRewards.drink end
}

local XP_INTERVALS <const> = {
    riding = 50,
    leading = 25,
    brush = 3,
    pat = 3,
    feed = 3,
    drink = 10
}

local function clampCore(value)
    return math.max(0, math.min(MAX_CORE_VALUE, tonumber(value) or MAX_CORE_VALUE))
end

local function normalizeStats(rawStats)
    local stats = {}
    local total = 0

    for _, key in ipairs(STAT_KEYS) do
        local value = tonumber(rawStats and rawStats[key]) or 0
        if value < 0 or value > MAX_STAT_RANK or value % 1 ~= 0 then return nil, nil end
        stats[key] = value
        total = total + value
    end

    return stats, total
end

local function updateStatsCache(horseId, charId, stats, health, stamina, xp)
    local cached = HorseXpCache[horseId] or {}
    cached.charid = charId
    cached.stats = stats
    cached.current_health = health
    cached.current_stamina = stamina
    cached.xp = tonumber(xp) or tonumber(cached.xp) or 0
    HorseXpCache[horseId] = cached
end

RegisterNetEvent('bcc-horses:SaveHorseStatsToDb', function(statsJson, horseId, healthCore, staminaCore)
    local src = source
    local _, charId = ServerUtils.getCharacter(src, 'horse stat save event')
    local targetHorseId = tonumber(horseId)
    if not charId or not targetHorseId or type(statsJson) ~= 'string' then return end

    local clientStats, clientTotal = normalizeStats(ServerUtils.decodeTable(statsJson, {}))
    if not clientStats then
        DBG:Warning(('Rejected invalid horse stats from source %s.'):format(src))
        return
    end

    MySQL.single(
        'SELECT `stats`, `xp` FROM `bcc_player_horses` WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0 LIMIT 1',
        { targetHorseId, charId },
        function(row)
            if not row then return end

            local serverStats, serverTotal = normalizeStats(ServerUtils.decodeTable(row.stats, {}))
            if not serverStats or clientTotal > serverTotal then
                DBG:Warning(('Rejected modified horse stats from source %s for horse %s.'):format(src, targetHorseId))
                return
            end

            local health = clampCore(healthCore)
            local stamina = clampCore(staminaCore)
            MySQL.update(
                'UPDATE `bcc_player_horses` SET `stats` = ?, `current_health` = ?, `current_stamina` = ? WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0',
                { json.encode(clientStats), health, stamina, targetHorseId, charId },
                function(rowsAffected)
                    if rowsAffected and rowsAffected > 0 then
                        updateStatsCache(targetHorseId, charId, clientStats, health, stamina, row.xp)
                    end
                end
            )
        end
    )
end)

local function canAwardXp(charId, horseId, xpSource, cooldownMultiplier)
    local now = os.time()
    local cacheKey = ('%s:%s:%s'):format(charId, horseId, xpSource)
    local minimumInterval = (XP_INTERVALS[xpSource] or 10) * (cooldownMultiplier or 1.0)
    local previousAward = lastXpAward[cacheKey]

    if previousAward and now - previousAward < minimumInterval then return false end
    lastXpAward[cacheKey] = now
    return true
end

local function allocateLevelStats(src, stats, oldLevel, newLevel, notify)
    for level = oldLevel + 1, newLevel do
        local preferredIndex = ((level - 1) % #STAT_KEYS) + 1
        local increasedStat

        for offset = 0, #STAT_KEYS - 1 do
            local key = STAT_KEYS[((preferredIndex - 1 + offset) % #STAT_KEYS) + 1]
            if stats[key] < MAX_STAT_RANK then
                stats[key] = stats[key] + 1
                increasedStat = key
                break
            end
        end

        if notify and increasedStat then
            local label = increasedStat:gsub('^%l', string.upper)
            Core.NotifyRightTip(src, ('Level %d! %s increased to %d!'):format(level, label, stats[increasedStat]), 5000)
        elseif notify and not increasedStat then
            Core.NotifyRightTip(src, ('Level %d reached! Your mount has achieved maximum performance potential!'):format(level), 5000)
        end
    end
end

local function levelForXp(xp)
    local xpPerLevel = math.max(1, tonumber(Config.training.xpPerLevel) or 1000)
    return math.floor(math.max(0, tonumber(xp) or 0) / xpPerLevel)
end

---Applies level rewards missing from a loaded database row exactly once.
---@param horseRow table
---@param callback fun(horseRow: table)
function HorseProgression.reconcileRow(horseRow, callback)
    local horseId = type(horseRow) == 'table' and tonumber(horseRow.id) or nil
    local charId = type(horseRow) == 'table' and tonumber(horseRow.charid) or nil
    local appliedLevel = math.max(0, math.floor(tonumber(horseRow and horseRow.training_levels_applied) or 0))
    local earnedLevel = levelForXp(horseRow and horseRow.xp)

    if not horseId or not charId or earnedLevel <= appliedLevel then
        callback(horseRow)
        return
    end

    local stats = normalizeStats(ServerUtils.decodeTable(horseRow.stats, {}))
    if not stats then
        DBG:Warning(('Could not reconcile invalid stats for horse %s.'):format(tostring(horseId)))
        callback(horseRow)
        return
    end

    allocateLevelStats(nil, stats, appliedLevel, earnedLevel, false)
    local encodedStats = json.encode(stats)

    MySQL.update(
        [[UPDATE `bcc_player_horses`
          SET `stats` = ?, `training_levels_applied` = ?
          WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0 AND `training_levels_applied` = ?]],
        { encodedStats, earnedLevel, horseId, charId, appliedLevel },
        function(rowsAffected)
            if rowsAffected and rowsAffected > 0 then
                horseRow.stats = encodedStats
                horseRow.training_levels_applied = earnedLevel
            end
            callback(horseRow)
        end
    )
end

---Reconciles a roster sequentially so every row is ready before it reaches the UI.
---@param rows table
---@param callback fun(rows: table)
function HorseProgression.reconcileRows(rows, callback)
    rows = rows or {}
    local index = 1

    local function nextRow()
        if index > #rows then
            callback(rows)
            return
        end

        local currentIndex = index
        index = index + 1
        HorseProgression.reconcileRow(rows[currentIndex], function(row)
            rows[currentIndex] = row
            nextRow()
        end)
    end

    nextRow()
end

---Awards XP to a living horse owned by the supplied online player.
---This is the server-only integration point for optional horse feature resources.
---@param ownerSource number
---@param horseId number
---@param reward number
---@param xpSource string
---@param notifyLevelUp? boolean
---@return boolean success
function HorseProgression.addXp(ownerSource, horseId, reward, xpSource, notifyLevelUp)
    local src = tonumber(ownerSource)
    local targetHorseId = tonumber(horseId)
    local amount = math.max(0, math.floor(tonumber(reward) or 0))
    local _, charId = ServerUtils.getCharacter(src, 'horse XP award')
    if not src or not charId or not targetHorseId or amount <= 0 or xpLocks[targetHorseId] then return false end

    xpLocks[targetHorseId] = true
    local ok, awarded = pcall(function()
        local row = MySQL.single.await(
            'SELECT `xp`, `training_levels_applied`, `stats`, `current_health`, `current_stamina` FROM `bcc_player_horses` WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0 LIMIT 1',
            { targetHorseId, charId }
        )
        if not row then return false end

        local stats = normalizeStats(ServerUtils.decodeTable(row.stats, {}))
        if not stats then return false end

        local oldXp = tonumber(row.xp) or 0
        local newXp = oldXp + amount
        local appliedLevel = math.max(0, math.floor(tonumber(row.training_levels_applied) or 0))
        local newLevel = levelForXp(newXp)
        if newLevel > appliedLevel then
            allocateLevelStats(src, stats, appliedLevel, newLevel, notifyLevelUp ~= false)
        end

        local rowsAffected = MySQL.update.await(
            'UPDATE `bcc_player_horses` SET `xp` = ?, `stats` = ?, `training_levels_applied` = ? WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0',
            { newXp, json.encode(stats), math.max(appliedLevel, newLevel), targetHorseId, charId }
        )
        if not rowsAffected or rowsAffected <= 0 then return false end

        local health = clampCore(row.current_health)
        local stamina = clampCore(row.current_stamina)
        updateStatsCache(targetHorseId, charId, stats, health, stamina, newXp)
        TriggerClientEvent('bcc-horses:SyncHorseStats', src, json.encode(stats), targetHorseId,
            newXp, health, stamina, amount, xpSource)
        EmitHorseServerLifecycleEvent('bcc-horses:server:xpAwarded', {
            source = src, charId = charId, horseId = targetHorseId,
            amount = amount, reason = xpSource, totalXp = newXp,
        })
        return true
    end)
    xpLocks[targetHorseId] = nil

    if not ok then
        DBG:Error(('Horse XP award failed for horse %s: %s'):format(targetHorseId, tostring(awarded)))
        return false
    end
    return awarded == true
end

RegisterNetEvent('bcc-horses:UpdateHorseXp', function(xpSource, horseId)
    local src = source
    local _, charId = ServerUtils.getCharacter(src, 'horse XP event')
    local targetHorseId = tonumber(horseId)
    local resolveReward = type(xpSource) == 'string' and XP_REWARDS[xpSource]
    local reward = resolveReward and tonumber(resolveReward()) or 0
    if not charId or not targetHorseId or reward <= 0 then return end
    if not canAwardXp(charId, targetHorseId, xpSource, 1.0) then return end
    HorseProgression.addXp(src, targetHorseId, reward, xpSource, true)
end)
