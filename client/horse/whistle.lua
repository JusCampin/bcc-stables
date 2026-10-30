-- Only the simulator redeems a movement ticket. The owning player's native
-- whistle listener reports intent, never a horse/target handle or coordinates.
local C, H = Stables.Client, Stables.Horse
local workers = {}

local function yes(v) return v == true or v == 1 end

local function exists(e) return e and e ~= 0 and yes(DoesEntityExist(e)) end

local function alive(e) return exists(e) and not yes(IsEntityDead(e)) and not yes(IsPedDeadOrDying(e, true)) end

local function unoccupied(e)
    for _, flag in ipairs({ false, true }) do
        local rider = GetRiderOfMount(e, flag)
        if type(rider) ~= 'number' or rider ~= 0 then return false end
    end
    local led = Citizen.InvokeNative(0xAC5045AB7F1A34FD, e)
    return led == false or led == 0
end

local function valid(w, cleanup)
    local v = w.ticket
    return alive(w.horse) and NetworkGetNetworkIdFromEntity(w.horse) == v.netId
        and GetEntityModel(w.horse) == GetHashKey(v.modelKey)
        and Entity(w.horse).state.bccStablesGeneration == v.generationId
        and Entity(w.horse).state.bccStablesObserver == v.observerId
        and yes(NetworkHasControlOfEntity(w.horse)) and unoccupied(w.horse)
        and
        (cleanup or (alive(w.target) and NetworkGetNetworkIdFromEntity(w.target) == v.targetNet and not yes(IsPedOnMount(w.target))))
end

local function stop(w)
    w.cancelled = true
    if w.ticket and workers[w.ticket.generationId] == w and valid(w, true) then ClearPedTasks(w.horse) end
end

RegisterNetEvent('bcc-stables:movement:cancel', function(p)
    if source ~= 65535 or type(p) ~= 'table' then return end
    local w = workers[p.generationId]
    if w and w.sequence == p.sequence then stop(w) end
end)

RegisterNetEvent('bcc-stables:movement:execute', function(p)
    if source ~= 65535 or type(p) ~= 'table' or not C.Uuid(p.generationId) or type(p.sequence) ~= 'number'
        or p.sequence < 1 or p.sequence % 1 ~= 0 then
        return
    end
    local previous = workers[p.generationId]
    if previous and previous.sequence >= p.sequence then return end
    if previous then stop(previous) end
    local w = { sequence = p.sequence }
    workers[p.generationId] = w
    CreateThread(function()
        local ok, failure = pcall(function()
            local claim = C.Rpc('movement_claim', p)
            local v = claim.value
            if not claim.ok or type(v) ~= 'table' or v.generationId ~= p.generationId or v.sequence ~= p.sequence
                or not C.Uuid(v.observerId) or type(v.netId) ~= 'number' or type(v.targetNet) ~= 'number'
                or type(v.modelKey) ~= 'string' or type(v.remainingMs) ~= 'number' or v.remainingMs < 0 or v.remainingMs > 30000
                or (v.mode ~= 'follow' and v.mode ~= 'approach' and v.mode ~= 'stop' and v.mode ~= 'flee') then
                return
            end
            w.ticket = v
            w.horse, w.target = NetworkGetEntityFromNetworkId(v.netId), NetworkGetEntityFromNetworkId(v.targetNet)
            if w.cancelled or workers[p.generationId] ~= w or not valid(w, v.mode == 'stop') then return end
            if v.mode == 'stop' then
                ClearPedTasks(w.horse)
                return
            end
            if v.mode == 'flee' then
                ClearPedTasksImmediately(w.horse,false,false)
                Citizen.InvokeNative(0x22B0D0E37CCB840D,w.horse,w.target,100.0,v.remainingMs,6,3.0)
                SetPedKeepTask(w.horse,true)
            elseif v.mode == 'follow' then
                Citizen.InvokeNative(0x304AE42E357B8C7E, w.horse, w.target, 2.0, -3.0, 0.0, 2.0, v.remainingMs, 3.0, true,
                    false, false, false, false, false)
            else
                TaskGoToEntity(w.horse, w.target, -1, 10.2, 2.0, 0.0, 0)
            end
            C.Message(v.mode=='flee' and 'horse fleeing.' or v.mode == 'follow' and 'horse following.' or 'horse approach requested.')
            local deadline = GetGameTimer() + v.remainingMs
            while workers[p.generationId] == w and not w.cancelled and GetGameTimer() < deadline and valid(w) do
                if v.mode == 'approach' then
                    local a, b = GetEntityCoords(w.horse), GetEntityCoords(w.target)
                    if (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2 <= 100 then break end
                end
                Wait(50)
            end
            stop(w)
        end)
        if workers[p.generationId] == w then
            if w.ticket then pcall(stop, w) end
            workers[p.generationId] = nil
        end
        if w.ticket then C.Rpc('movement_done', { generationId = p.generationId, sequence = p.sequence }) end
        if not ok then C.Message('horse movement stopped: ' .. tostring(failure)) end
    end)
end)

local requestBusy = false
function H.Whistle(mode)
    if requestBusy then return end
    if not H.HasBoundHorse() then
        if Config.stable.whistleAnywhere then H.Call() end
        return
    end
    requestBusy = true
    CreateThread(function()
        local ok, result = pcall(C.Rpc, 'whistle', { mode = mode })
        requestBusy = false
        if ok and result.code=='cleanup_pending' then
            C.Message('previous horse cleanup pending; wait for disappearance before whistling again.')
        elseif not ok or not result.ok then C.Message('whistle refused: ' ..
            tostring(ok and result.code or 'transport_error'))
        elseif type(result.value)=='table' and result.value.relocated then C.Message('horse replacement requested.') end
    end)
end

-- Event queues are frame-scoped, so read them every frame while gameplay input
-- is available. NUI focus pauses this reader, not an existing follow intent.
CreateThread(function()
    local buffer = CreateEventDataBuffer(16)
    local short = GetHashKey('WHISTLEHORSESHORT')
    local long = GetHashKey('WHISTLEHORSELONG')
    if short >= 0x80000000 then short = short - 0x100000000 end
    if long >= 0x80000000 then long = long - 0x100000000 end
    local whistleControl = GetHashKey('INPUT_WHISTLE')
    local last = -1500
    local heldSince, releasedAt, releasedDuration, pending = nil, -1000, 0, nil
    local gestureSent = false
    while true do
        Wait(0)
        if GetResourceState('feather-core') == 'started' and not IsNuiFocused() and alive(PlayerPedId()) then
            local now = GetGameTimer()
            local pressed = yes(IsControlPressed(0, whistleControl)) or yes(IsControlPressed(2, whistleControl))
            if pressed and not heldSince then
                heldSince = now
                gestureSent = false
            end
            if not pressed and heldSince then
                releasedAt, releasedDuration = now, now - heldSince
                heldSince = nil
            end
            for index = 0, GetNumberOfEvents(0) - 1 do
                if Citizen.InvokeNative(0xA85E614430EFF816, 0, index) == 1327216456
                    and yes(Citizen.InvokeNative(0x57EC5FA4D4D6AFCA, 0, index, buffer:Buffer(), 2))
                    and buffer:GetInt32(0) == PlayerPedId() then
                    local kind = buffer:GetInt32(8)
                    if (kind == short or kind == long) and now - last >= 1500
                        and not (gestureSent and (pressed or now - releasedAt < 500)) then
                        local isLong = kind == long or (not pressed and now - releasedAt <= 500 and releasedDuration >= 600)
                        if pending and pending.ped == PlayerPedId() then isLong = isLong or pending.mode ==
                            'toggle_follow' end
                        pending = { mode = isLong and 'toggle_follow' or 'approach', ped = PlayerPedId() }
                    end
                end
            end
            -- A held whistle can emit a short event first. Do not spend the
            -- cooldown on that preliminary event, classify it at release.
            if pending and not pressed and now - releasedAt <= 500 and releasedDuration >= 600 then
                pending.mode = 'toggle_follow'
            end
            if pending and (not pressed or pending.mode == 'toggle_follow') then
                local request = pending
                pending = nil
                if request.ped == PlayerPedId() and now - last >= 1500 then
                    last, gestureSent = now, true
                    H.Whistle(request.mode)
                end
            end
        else
            heldSince, pending = nil, nil
            releasedAt, releasedDuration, gestureSent = -1000, 0, false
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() or resource == 'feather-core' then
        for _, w in pairs(workers) do pcall(stop, w) end
    end
end)
