local stableQueues = {}
local nextToken = 0

local function getQueue(siteId)
    local queue = stableQueues[siteId]
    if queue then return queue end

    queue = { active = nil, waiting = {} }
    stableQueues[siteId] = queue
    return queue
end

local function processQueue(siteId)
    local queue = stableQueues[siteId]
    if not queue or queue.active then return end

    while #queue.waiting > 0 do
        local request = table.remove(queue.waiting, 1)
        if GetPlayerName(request.source) then
            nextToken = nextToken + 1
            local token = ('%s:%d:%d'):format(siteId, request.source, nextToken)
            queue.active = { source = request.source, token = token }
            request.callback({ token = token })

            local settings = Config.stable.delivery or {}
            local timeout = math.max(5000, tonumber(settings.reservationTimeoutMs) or 15000)
            SetTimeout(timeout, function()
                local active = queue.active
                if not active or active.token ~= token then return end
                queue.active = nil
                processQueue(siteId)
            end)
            return
        end
    end
end

Core.Callback.Register('bcc-horses:ReserveStableDelivery', function(source, cb, siteId)
    local src = source
    if type(siteId) ~= 'string' or not Stables[siteId] then return cb(false) end

    local playerPed = GetPlayerPed(src)
    local stableCoords = Stables[siteId].npc and Stables[siteId].npc.coords
    if playerPed == 0 or not stableCoords
        or #(GetEntityCoords(playerPed) - stableCoords) > 30.0 then
        return cb(false)
    end

    local queue = getQueue(siteId)
    if queue.active and queue.active.source == src then
        return cb({ token = queue.active.token })
    end
    for _, request in ipairs(queue.waiting) do
        if request.source == src then return cb(false) end
    end

    queue.waiting[#queue.waiting + 1] = { source = src, callback = cb }
    processQueue(siteId)
end)

RegisterNetEvent('bcc-horses:ReleaseStableDelivery', function(siteId, token)
    local queue = type(siteId) == 'string' and stableQueues[siteId] or nil
    local active = queue and queue.active
    if not active or active.source ~= source or active.token ~= token then return end

    queue.active = nil
    processQueue(siteId)
end)

AddEventHandler('playerDropped', function()
    local src = source
    for siteId, queue in pairs(stableQueues) do
        if queue.active and queue.active.source == src then queue.active = nil end
        for index = #queue.waiting, 1, -1 do
            if queue.waiting[index].source == src then table.remove(queue.waiting, index) end
        end
        processQueue(siteId)
    end
end)
