local HORSES_TABLE <const> = 'bcc_player_horses'
local MAX_HORSE_NAME_LENGTH <const> = 100

local DEFAULT_HORSE_STATS <const> = {
    speed = 0,
    acceleration = 0,
    handling = 0,
    health = 0,
    stamina = 0
}

local function copyDefaultStats()
    return {
        speed = DEFAULT_HORSE_STATS.speed,
        acceleration = DEFAULT_HORSE_STATS.acceleration,
        handling = DEFAULT_HORSE_STATS.handling,
        health = DEFAULT_HORSE_STATS.health,
        stamina = DEFAULT_HORSE_STATS.stamina
    }
end

local function syncSelectedHorseStats(src, horseRow)
    if type(horseRow) ~= 'table' or not ServerUtils.databaseBoolean(horseRow.is_selected) then return end

    TriggerClientEvent(
        'bcc-horses:SyncHorseStats',
        src,
        type(horseRow.stats) == 'string' and horseRow.stats or json.encode(horseRow.stats or copyDefaultStats()),
        tonumber(horseRow.id),
        tonumber(horseRow.xp) or 0,
        tonumber(horseRow.current_health) or 100,
        tonumber(horseRow.current_stamina) or 100
    )
end

---@param horseRow table
---@return table|nil
local function parseRawHorseRow(horseRow)
    if type(horseRow) ~= 'table' then return nil end

    local horseId = tonumber(horseRow.id)
    if not horseId then return nil end

    local stats = ServerUtils.decodeTable(horseRow.stats, copyDefaultStats())
    local xp = tonumber(horseRow.xp) or 0
    local health = tonumber(horseRow.current_health) or 100
    local stamina = tonumber(horseRow.current_stamina) or 100
    local isSelected = ServerUtils.databaseBoolean(horseRow.is_selected)
    local isWrithing = ServerUtils.databaseBoolean(horseRow.is_writhing)

    HorseXpCache[horseId] = {
        charid = tonumber(horseRow.charid) or horseRow.charid,
        name = horseRow.name,
        xp = xp,
        stats = stats,
        is_selected = isSelected,
        is_dead = false,
        is_writhing = isWrithing,
        current_health = health,
        current_stamina = stamina
    }

    return HorseAging.decorate({
        id = horseId,
        charid = tonumber(horseRow.charid) or horseRow.charid,
        name = horseRow.name,
        model = horseRow.model,
        gender = horseRow.gender,
        tackLoadout = {},
        stats = stats,
        xp = xp,
        captured = tonumber(horseRow.captured) or 0,
        is_selected = isSelected,
        is_writhing = isWrithing,
        current_health = health,
        current_stamina = stamina,
        born_at = horseRow.born_at,
        natural_death_at = horseRow.natural_death_at,
        aging_exempt = horseRow.aging_exempt,
        age_years = horseRow.age_years
    })
end

Core.Callback.Register('bcc-horses:GetSelectedHorseData', function(source, cb, request)
    local src = source
    local _, charId = ServerUtils.getCharacter(src, 'selected horse callback')
    if not charId then return cb(false) end

    local requestedHorseId = type(request) == 'table' and tonumber(request.horseId) or nil

    HorseAging.expireCharacter(charId, function()
        local function returnParsedHorse(horseRow)
            if not horseRow then
                Core.NotifyRightTip(src, _U('noSelectedHorse') or 'No horse currently selected!', 4000)
                return cb(false)
            end

            syncSelectedHorseStats(src, horseRow)
            local horse = parseRawHorseRow(horseRow)
            if horse then
                horse.tackLoadout = TackRepository.resolveLoadout(TackRepository.getLoadout(horse.id, charId))
            end
            cb(horse or false)
        end

        local function returnHorse(horseRow)
            if not horseRow then return returnParsedHorse(nil) end
            HorseProgression.reconcileRow(horseRow, returnParsedHorse)
        end

        if not requestedHorseId then
            MySQL.single(
                ('SELECT %s FROM `%s` WHERE `charid` = ? AND `is_selected` = 1 AND `is_dead` = 0 LIMIT 1'):format(HorseAging.selectList(), HORSES_TABLE),
                { charId },
                returnHorse
            )
            return
        end

        MySQL.scalar(
            ('SELECT `id` FROM `%s` WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0 LIMIT 1'):format(HORSES_TABLE),
            { requestedHorseId, charId },
            function(ownedHorseId)
                if tonumber(ownedHorseId) ~= requestedHorseId then return cb(false) end

                MySQL.transaction({
                    {
                        query = ('UPDATE `%s` SET `is_selected` = 0 WHERE `charid` = ? AND `is_dead` = 0'):format(HORSES_TABLE),
                        values = { charId },
                    },
                    {
                        query = ('UPDATE `%s` SET `is_selected` = 1 WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0'):format(HORSES_TABLE),
                        values = { requestedHorseId, charId },
                    },
                }, function(success)
                    if not success then return cb(false) end

                    MySQL.single(
                        ('SELECT %s FROM `%s` WHERE `id` = ? AND `charid` = ? AND `is_selected` = 1 AND `is_dead` = 0 LIMIT 1'):format(HorseAging.selectList(), HORSES_TABLE),
                        { requestedHorseId, charId },
                        function(horseRow)
                            if horseRow then
                                for cachedHorseId, cachedHorse in pairs(HorseXpCache) do
                                    if tonumber(cachedHorse.charid) == charId then
                                        cachedHorse.is_selected = tonumber(cachedHorseId) == requestedHorseId
                                    end
                                end
                            end
                            returnHorse(horseRow)
                        end
                    )
                end)
            end
        )
    end)
end)

Core.Callback.Register('bcc-horses:GetMyHorsesData', function(source, cb)
    local src = source
    local _, charId = ServerUtils.getCharacter(src, 'horse roster callback')
    if not charId then return cb(false) end

    HorseAging.expireCharacter(charId, function()
        MySQL.query(
            ('SELECT %s FROM `%s` WHERE `charid` = ? AND `is_dead` = 0'):format(HorseAging.selectList(), HORSES_TABLE),
            { charId },
            function(rows)
                HorseProgression.reconcileRows(rows, function(reconciledRows)
                    local roster = {}

                    for _, horseRow in ipairs(reconciledRows or {}) do
                        syncSelectedHorseStats(src, horseRow)
                        local horse = parseRawHorseRow(horseRow)
                        if horse then
                            roster[#roster + 1] = horse
                        end
                    end

                    local byHorse = {}
                    for _, row in ipairs(TackRepository.getCharacterLoadouts(charId)) do
                        local horseId = tonumber(row.horse_id)
                        byHorse[horseId] = byHorse[horseId] or {}
                        byHorse[horseId][#byHorse[horseId] + 1] = row
                    end
                    for _, horse in ipairs(roster) do
                        horse.tackLoadout = TackRepository.resolveLoadout(byHorse[horse.id])
                    end

                    cb(roster)
                end)
            end
        )
    end)
end)

RegisterNetEvent('bcc-horses:SelectActiveHorse', function(horseId)
    local src = source
    local _, charId = ServerUtils.getCharacter(src, 'horse selection event')
    if not charId then return end

    local targetHorseId = tonumber(horseId)
    if not targetHorseId then
        DBG:Warning(('Invalid horse ID received from source: %s'):format(tostring(src)))
        return
    end

    MySQL.scalar(
        ('SELECT `id` FROM `%s` WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0 LIMIT 1'):format(HORSES_TABLE),
        { targetHorseId, charId },
        function(ownedHorseId)
            if tonumber(ownedHorseId) ~= targetHorseId then
                DBG:Warning(('Horse selection rejected for source %s: horse is not owned.'):format(tostring(src)))
                return
            end

            MySQL.transaction({
                {
                    query = ('UPDATE `%s` SET `is_selected` = 0 WHERE `charid` = ? AND `is_dead` = 0'):format(HORSES_TABLE),
                    values = { charId }
                },
                {
                    query = ('UPDATE `%s` SET `is_selected` = 1 WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0'):format(HORSES_TABLE),
                    values = { targetHorseId, charId }
                }
            }, function(success)
                if not success then
                    DBG:Error(('Failed to select horse ID %s for character %s.'):format(targetHorseId, charId))
                    return
                end

                for cachedHorseId, cachedHorse in pairs(HorseXpCache) do
                    if tonumber(cachedHorse.charid) == charId then
                        cachedHorse.is_selected = tonumber(cachedHorseId) == targetHorseId
                    end
                end

                DBG:Info('Horse selection recorded for ID:', targetHorseId)
                EmitHorseServerLifecycleEvent('bcc-horses:server:horseSelected', {
                    id = targetHorseId,
                    ownerCharId = charId,
                    source = src,
                })
            end)
        end
    )
end)

Core.Callback.Register('bcc-horses:RenameHorse', function(source, cb, data)
    local src = source
    local _, charId = ServerUtils.getCharacter(src, 'horse rename callback')
    if not charId then return cb(false) end
    if type(data) ~= 'table' then return cb(false) end

    local horseId = tonumber(data.horseId)
    local newName = ServerUtils.normalizeName(data.newName, MAX_HORSE_NAME_LENGTH)

    if not horseId or not newName then
        DBG:Warning(('Horse rename rejected due to invalid data. Source: %s'):format(tostring(src)))
        return cb(false)
    end

    MySQL.update(
        ('UPDATE `%s` SET `name` = ? WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0'):format(HORSES_TABLE),
        { newName, horseId, charId },
        function(rowsAffected)
            if not rowsAffected or rowsAffected <= 0 then
                return cb(false)
            end

            local cachedHorse = HorseXpCache[horseId]
            if cachedHorse and tonumber(cachedHorse.charid) == charId then
                cachedHorse.name = newName
            end

            DBG:Info('Horse name recorded for ID:', horseId)
            LogToDiscord(charId, ('Renamed horse ID %d to: %s'):format(horseId, newName))
            cb(true)
        end
    )
end)

RegisterNetEvent('vorp_core:instanceplayers', function(setRoom)
    if tonumber(setRoom) ~= 0 then return end

    local src = source
    local _, charId = ServerUtils.getCharacter(src, 'instance synchronization event')
    if not charId then return end

    local horseData = Player(src).state.HorseData
    local currentNetId = horseData and tonumber(horseData.MyHorse)

    if currentNetId and currentNetId ~= 0 then
        TriggerClientEvent('bcc-horses:UpdateMyHorseEntity', src, currentNetId)
    end
end)
