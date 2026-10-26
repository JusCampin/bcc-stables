local VALID_TRANSITIONS <const> = {
    killed = true,
    mercy_killed = true,
    revived = true,
}
local lifecycleLocks = {}

local function getLifecycleValues(executionState)
    local cfg = Config.death or {
        writheEnabled = true,
        persistentWrithe = true,
        deselectOnDeath = false,
        permanentDeath = false,
    }

    if executionState == 'revived' then
        return 1, 0, 0
    end

    if executionState == 'killed' and cfg.writheEnabled then
        return 1, cfg.persistentWrithe and 1 or 0, 0
    end

    local selected = (cfg.permanentDeath or cfg.deselectOnDeath) and 0 or 1
    local dead = cfg.permanentDeath and 1 or 0
    return selected, 0, dead
end

local function updateHorseCache(horseId, charid, selected, writhing, dead)
    if selected == 0 then
        for _, cachedHorse in pairs(HorseXpCache) do
            if tonumber(cachedHorse.charid) == charid then
                cachedHorse.is_selected = false
            end
        end
    end

    if HorseXpCache[horseId] then
        HorseXpCache[horseId].is_selected = selected == 1
        HorseXpCache[horseId].is_dead = dead == 1
        HorseXpCache[horseId].is_writhing = writhing == 1
    end
end

Core.Callback.Register('bcc-horses:HorseReviveItem', function(source, cb)
    if not ServerUtils.getCharacter(source, 'horse reviver callback') then return cb(false) end

    local reviver = Config.items.reviver
    if type(reviver) ~= 'string' or reviver == '' then return cb(false) end

    local itemCount = tonumber(exports.vorp_inventory:getItemCount(source, nil, reviver)) or 0
    cb(itemCount > 0)
end)

Core.Callback.Register('bcc-horses:TransitionHorseDeathState', function(source, cb, horseId, executionState)
    local src = source
    local _, charid = ServerUtils.getCharacter(src, 'horse lifecycle callback')
    local targetHorseId = tonumber(horseId)

    if not charid or not targetHorseId or type(executionState) ~= 'string' or not VALID_TRANSITIONS[executionState] then
        DBG:Error(('Rejected invalid horse lifecycle transition from source %s'):format(tostring(src)))
        return cb(false)
    end

    if lifecycleLocks[targetHorseId] then return cb(false) end
    lifecycleLocks[targetHorseId] = true

    local function finish(success)
        lifecycleLocks[targetHorseId] = nil
        cb(success)
    end

    MySQL.single(
        'SELECT `id`, `is_selected`, `is_dead` FROM `bcc_player_horses` WHERE `id` = ? AND `charid` = ? LIMIT 1',
        { targetHorseId, charid },
        function(horse)
            if not horse or tonumber(horse.is_dead) == 1 then return finish(false) end

            if executionState == 'revived' then
                local reviver = Config.items.reviver
                if type(reviver) ~= 'string' or reviver == '' then return finish(false) end

                local itemCount = exports.vorp_inventory:getItemCount(src, nil, reviver) or 0
                if itemCount < 1 then return finish(false) end
            end

            local selected, writhing, dead = getLifecycleValues(executionState)
            local lifecycleQuery = 'UPDATE `bcc_player_horses` SET `is_selected` = ?, `is_writhing` = ?, `is_dead` = ? WHERE `id` = ? AND `charid` = ?'
            local lifecycleValues = { selected, writhing, dead, targetHorseId, charid }
            if dead == 1 then
                lifecycleQuery = 'UPDATE `bcc_player_horses` SET `is_selected` = ?, `is_writhing` = ?, `is_dead` = ?, `died_at` = UTC_TIMESTAMP(), `death_cause` = ? WHERE `id` = ? AND `charid` = ?'
                lifecycleValues = { selected, writhing, dead, 'injury', targetHorseId, charid }
            end
            local queries = {
                {
                    query = lifecycleQuery,
                    values = lifecycleValues,
                },
            }

            if selected == 0 then
                queries[#queries + 1] = {
                    query = 'UPDATE `bcc_player_horses` SET `is_selected` = 0 WHERE `charid` = ?',
                    values = { charid },
                }
            end

            MySQL.transaction(queries, function(success)
                if not success then return finish(false) end

                if executionState == 'revived' then
                    exports.vorp_inventory:subItem(src, Config.items.reviver, 1)
                end

                updateHorseCache(targetHorseId, charid, selected, writhing, dead)
                DBG:Info(('Horse lifecycle state "%s" persisted. Target ID: %d'):format(executionState, targetHorseId))
                finish(true)
            end)
        end
    )
end)
