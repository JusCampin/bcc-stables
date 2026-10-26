local HORSES_TABLE <const> = 'bcc_player_horses'

local function getHorse(horseId)
    horseId = tonumber(horseId)
    if not horseId then return nil end

    return MySQL.single.await(
        ('SELECT * FROM `%s` WHERE `id` = ? LIMIT 1'):format(HORSES_TABLE),
        { horseId }
    )
end

local function getOwnedHorse(sourceId, horseId)
    local _, charId = ServerUtils.getCharacter(sourceId, 'horse feature ownership validation')
    horseId = tonumber(horseId)
    if not charId or not horseId then return nil end

    return MySQL.single.await(
        ('SELECT * FROM `%s` WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0 LIMIT 1')
            :format(HORSES_TABLE),
        { horseId, charId }
    )
end

exports('GetHorse', getHorse)
exports('GetOwnedHorse', getOwnedHorse)

exports('GetHorseLimit', function(sourceId)
    return ServerUtils.getHorseLimit(sourceId)
end)

exports('GetHorseOwner', function(horseId)
    local horse = getHorse(horseId)
    return horse and tonumber(horse.charid) or nil
end)

exports('ValidateOwnedHorse', function(sourceId, horseId, horseNetId)
    local horse = getOwnedHorse(sourceId, horseId)
    horseNetId = tonumber(horseNetId)
    if not horse or not horseNetId then return false end

    local entity = NetworkGetEntityFromNetworkId(horseNetId)
    return entity ~= 0 and tonumber(Entity(entity).state.myHorseId) == tonumber(horse.id)
end)

exports('IsHorseNearby', function(sourceId, horseId, maximumDistance)
    local playerPed = GetPlayerPed(sourceId)
    horseId = tonumber(horseId)
    if playerPed == 0 or not horseId then return false end

    local playerCoords = GetEntityCoords(playerPed)
    local allowedDistance = math.max(0.0, tonumber(maximumDistance) or 5.0)
    for _, ped in ipairs(GetAllPeds()) do
        if tonumber(Entity(ped).state.myHorseId) == horseId
            and #(playerCoords - GetEntityCoords(ped)) <= allowedDistance then
            return true
        end
    end
    return false
end)

---Awards horse XP from trusted server-side feature resources.
---The core verifies that the horse is alive and belongs to ownerSource.
exports('AddHorseXp', function(ownerSource, horseId, amount, reason)
    if not HorseProgression or type(HorseProgression.addXp) ~= 'function' then return false end
    return HorseProgression.addXp(ownerSource, horseId, amount, reason or 'external', true)
end)

---Transfers a living horse between characters after an external feature validates consent.
---Ownership mutation remains authoritative inside the core resource.
exports('TransferHorse', function(senderSource, recipientSource, horseId)
    local _, senderCharId = ServerUtils.getCharacter(senderSource, 'horse transfer sender')
    local _, recipientCharId = ServerUtils.getCharacter(recipientSource, 'horse transfer recipient')
    horseId = tonumber(horseId)
    if not senderCharId or not recipientCharId or senderCharId == recipientCharId or not horseId then
        return false, 'invalid_transfer'
    end
    local horse = getOwnedHorse(senderSource, horseId)
    if not horse then return false, 'horse_unavailable' end

    local recipientCount = tonumber(MySQL.scalar.await(
        ('SELECT COUNT(*) FROM `%s` WHERE `charid` = ? AND `is_dead` = 0'):format(HORSES_TABLE),
        { recipientCharId }
    )) or 0
    if recipientCount >= ServerUtils.getHorseLimit(recipientSource) then return false, 'stable_full' end

    local success = MySQL.transaction.await({
        {
            query = 'DELETE FROM `bcc_horse_tack_loadouts` WHERE `horse_id` = ?',
            values = { horseId },
        },
        {
            query = ('UPDATE `%s` SET `charid` = ?, `is_selected` = 0 WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0')
                :format(HORSES_TABLE),
            values = { recipientCharId, horseId, senderCharId },
        },
    })
    if not success then return false, 'database_error' end

    HorseXpCache[horseId] = nil
    EmitHorseServerLifecycleEvent('bcc-horses:server:horseOwnerChanged', {
        id = horseId,
        previousOwnerCharId = senderCharId,
        ownerCharId = recipientCharId,
        previousOwnerSource = senderSource,
        ownerSource = recipientSource,
    })
    LogToDiscord(
        'Horse ownership transferred',
        ('Horse ID %d transferred from character %s to character %s.')
            :format(horseId, senderCharId, recipientCharId)
    )
    return true
end)

function EmitHorseServerLifecycleEvent(eventName, data)
    TriggerEvent(eventName, data)
end
