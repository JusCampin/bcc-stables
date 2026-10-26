local reservations = {}
local reservationsBySource = {}

local function finiteNumber(value)
    value = tonumber(value)
    return value and value == value and value ~= math.huge and value ~= -math.huge
end

local function clearReservation(key)
    local reservation = reservations[key]
    if not reservation then return end

    reservations[key] = nil
    local sourceReservations = reservationsBySource[reservation.source]
    if sourceReservations then
        sourceReservations[key] = nil
        if not next(sourceReservations) then reservationsBySource[reservation.source] = nil end
    end
end

local function clearSourceReservations(src)
    local sourceReservations = reservationsBySource[src]
    if not sourceReservations then return end
    for key in pairs(sourceReservations) do reservations[key] = nil end
    reservationsBySource[src] = nil
end

local function reservationKey(kind, model, x, y, z)
    return ('%s:%s:%d:%d:%d'):format(
        kind,
        tonumber(model) or 0,
        math.floor((tonumber(x) or 0) * 2.0 + 0.5),
        math.floor((tonumber(y) or 0) * 2.0 + 0.5),
        math.floor((tonumber(z) or 0) * 2.0 + 0.5)
    )
end

RegisterNetEvent('bcc-horses:worldCare:reserve', function(requestId, kind, model, x, y, z, horseId)
    local src = source
    local _, charId = ServerUtils.getCharacter(src, 'world-care reservation')
    local targetHorseId = tonumber(horseId)
    if type(requestId) ~= 'string' or #requestId > 64
        or not charId or not targetHorseId or (kind ~= 'trough' and kind ~= 'hay')
        or not finiteNumber(model) or not finiteNumber(x) or not finiteNumber(y) or not finiteNumber(z) then
        TriggerClientEvent('bcc-horses:worldCare:reservationResult', src, requestId, false)
        return
    end

    MySQL.scalar(
        'SELECT 1 FROM `bcc_player_horses` WHERE `id` = ? AND `charid` = ? AND `is_dead` = 0 LIMIT 1',
        { targetHorseId, charId },
        function(owned)
            if not GetPlayerName(src) then return end
            if not owned then
                TriggerClientEvent('bcc-horses:worldCare:reservationResult', src, requestId, false)
                return
            end

            local key = reservationKey(kind, model, x, y, z)
            local now = os.time()
            local existing = reservations[key]
            if existing and existing.expiresAt <= now then
                clearReservation(key)
                existing = nil
            end

            if existing and existing.source ~= src then
                TriggerClientEvent('bcc-horses:worldCare:reservationResult', src, requestId, false)
                return
            end

            local settings = Config.care.world or {}
            local timeout = math.max(5, math.ceil((tonumber(settings.reservationTimeoutMs) or 25000) / 1000))
            reservations[key] = { source = src, expiresAt = now + timeout }
            reservationsBySource[src] = reservationsBySource[src] or {}
            reservationsBySource[src][key] = true
            TriggerClientEvent('bcc-horses:worldCare:reservationResult', src, requestId, true, key)
        end
    )
end)

RegisterNetEvent('bcc-horses:worldCare:release', function(key)
    local reservation = type(key) == 'string' and reservations[key]
    if reservation and reservation.source == source then clearReservation(key) end
end)

RegisterNetEvent('bcc-horses:worldCare:releaseAll', function()
    clearSourceReservations(source)
end)

AddEventHandler('playerDropped', function()
    clearSourceReservations(source)
end)

CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        local expired = {}

        for key, reservation in pairs(reservations) do
            if reservation.expiresAt <= now then expired[#expired + 1] = key end
        end

        for index = 1, #expired do clearReservation(expired[index]) end
    end
end)
