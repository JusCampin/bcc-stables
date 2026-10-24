-- Native creation only follows a server dispatch instruction for a durable generation.
local active, busy
local retired, retiredOrder = {}, {}
local lastRetired
local holdNextBind = false

local function Timing(pattern, ...)
    local args = table.pack(...)
    -- Diagnostics cannot change a committed result or trigger entity cleanup.
    pcall(function() print('[bcc-stables:timing] ' .. pattern:format(table.unpack(args, 1, args.n))) end)
end

local function Uuid(v)
    return type(v) == 'string' and
    v:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') ~= nil
end

local function Rpc(name, payload)
    local reply, done
    exports['feather-core']:CallRPC('stables.horses.call.' .. name .. '.v1', payload, function(...)
        if not done then
            reply, done = table.pack(...), true
        end
    end, nil, 15000)

    local started = GetGameTimer()
    while not done and GetGameTimer() - started < 16000 do
        Wait(25)
    end

    done = true
    if not reply then
        return { ok = false, code = 'timeout' }
    end

    local result, failure = reply[1], reply[2]
    return type(result) == 'table' and result or
    { ok = false, code = type(failure) == 'table' and failure.code or 'invalid_result' }
end

local function Yes(value)
    return value == true or value == 1
end

local function Exists(entity)
    return entity ~= nil and entity ~= 0 and Yes(DoesEntityExist(entity))
end

local function SameHorse(record)
    return not record.cancelled and not record.identityLost and Exists(record.entity)
        and Entity(record.entity).state.bccStablesGeneration == record.generationId
        and Entity(record.entity).state.bccStablesObserver == record.observerId
        and GetEntityModel(record.entity) == record.hash
        and NetworkGetNetworkIdFromEntity(record.entity) == record.netId
end

local function StillControlled(record)
    return SameHorse(record) and Yes(NetworkHasControlOfEntity(record.entity))
end

local function AuthorizeProof(r)
    local result = Rpc('movement_proof', {})
    local v = type(result) == 'table' and result.value
    assert(result.ok and type(v) == 'table' and v.generationId == r.generationId and v.observerId == r.observerId
        and v.netId == r.netId and v.modelKey == r.modelKey and v.state == 'active'
        and v.movementProof == true and v.gameplayAvailable == false, 'Native proof refused: ' .. tostring(result.code))
    assert(active == r and StillControlled(r), 'Horse identity/control changed during authorization')
end

local function CompanionSlots(player)
    local saddle = Citizen.InvokeNative(0xB48050D326E9A2F3, player, Citizen.ResultAsInteger()) -- GetSaddleHorseForPlayer
    local mount = Citizen.InvokeNative(0x46FA0AE18F4C7FA9, player, Citizen.ResultAsInteger()) -- GetActiveHorseForPlayer
    assert(type(saddle) == 'number' and saddle % 1 == 0 and saddle >= 0 and type(mount) == 'number' and mount % 1 == 0 and mount >= 0,
        'Native horse association getters returned invalid handles')
    return saddle, mount
end

local function ClearCompanion(r)
    local link = r.companionProof
    if not link then return end

    -- Do not clear a different character or a reused/unverified entity handle.
    if PlayerId() ~= link.player or PlayerPedId() ~= link.ped or r.identityLost or not Exists(r.entity)
        or GetEntityModel(r.entity) ~= r.hash or NetworkGetNetworkIdFromEntity(r.entity) ~= r.netId
        or Entity(r.entity).state.bccStablesGeneration ~= r.generationId
        or Entity(r.entity).state.bccStablesObserver ~= r.observerId then
        return
    end

    local saddle, mount = CompanionSlots(link.player)
    if link.wroteSaddle and saddle == r.entity then Citizen.InvokeNative(0xD2CB0FB0FDCB473D, link.player, 0) end -- SetPedAsSaddleHorseForPlayer
    -- The saddle setter may establish an active link too. Only undo it when
    -- that slot was empty beforehand and it still identifies our same horse.
    if link.clearActive and mount == r.entity then Citizen.InvokeNative(0x8FBF9EDB378CCB8C, link.player, 0) end -- SetPedActivePlayerHorse
    r.companionProof = nil
end

local function CurrentCompanion(r, link)
    return active == r and r.companionProof == link and PlayerId() == link.player
        and PlayerPedId() == link.ped and SameHorse(r)
end

local function WhistleControl(r, link)
    local started = GetGameTimer()
    while CurrentCompanion(r, link) and not StillControlled(r) and GetGameTimer()-started < 1000 do
        NetworkRequestControlOfEntity(r.entity)
        Wait(25)
    end
    return CurrentCompanion(r, link) and StillControlled(r)
end

-- Event payload: whistling ped at byte 0, whistle kind at byte 8.
-- One frame listener only while an explicitly authorized companion is present.
local function ListenForWhistle(r)
    if r.whistleListening then return end
    r.whistleListening = true
    r.whistleStats = { frames = 0, gated = 0, events = 0, whistles = 0, payloads = 0, owned = 0, tasks = 0, hashes = {} }
    CreateThread(function()
        local ok, failure = pcall(function()
            local makeBlob = rawget(string, 'blob') or function(n) return string.rep('\0', n) end
            local buffer = makeBlob(16)
            local lastWhistle = -2000
            while active == r and not r.cancelled and r.companionProof do
                Wait(0)
                if active ~= r or r.cancelled or not r.companionProof then break end
                local link = r.companionProof
                local stats = r.whistleStats
                stats.frames = stats.frames + 1
                if CurrentCompanion(r, link) then
                    if not StillControlled(r) then stats.gated = stats.gated + 1 end
                    if r.whistleApproaching and StillControlled(r) then
                        -- Match BCC Horses arrival handling without a second frame loop.
                        if Yes(IsPedOnMount(link.ped)) or GetRiderOfMount(r.entity, false) ~= 0 then
                            r.whistleApproaching = nil
                        else
                            local horsePos, ownerPos = GetEntityCoords(r.entity), GetEntityCoords(link.ped)
                            local dx, dy, dz = horsePos.x-ownerPos.x, horsePos.y-ownerPos.y, horsePos.z-ownerPos.z
                            if dx*dx+dy*dy+dz*dz <= 100.0 then
                                ClearPedTasks(r.entity)
                                r.whistleApproaching = nil
                            end
                        end
                    end
                    local count = GetNumberOfEvents(0)
                    stats.events = stats.events + count
                    for index = 0, count - 1 do
                        local hash = Citizen.InvokeNative(0xA85E614430EFF816, 0, index)
                        if #stats.hashes < 8 and stats.hashes[#stats.hashes] ~= hash then stats.hashes[#stats.hashes + 1] =
                            hash end
                        if hash == 1327216456 then
                            stats.whistles = stats.whistles + 1
                            if Yes(Citizen.InvokeNative(0x57EC5FA4D4D6AFCA, 0, index, buffer, 2)) then
                                stats.payloads = stats.payloads + 1
                                stats.eventPed = string.unpack('<i4', buffer, 1)
                                if stats.eventPed == link.ped then
                                    stats.owned = stats.owned + 1
                                    if GetGameTimer() - lastWhistle >= 1500 then
                                        local saddle = CompanionSlots(link.player)
                                        stats.saddle = saddle
                                        stats.mounted = Yes(IsPedOnMount(link.ped))
                                        stats.rider = GetRiderOfMount(r.entity, false)
                                        if saddle == r.entity and not stats.mounted and stats.rider == 0 then
                                            lastWhistle = GetGameTimer()
                                            if WhistleControl(r, link) and CompanionSlots(link.player) == r.entity
                                                and not Yes(IsPedOnMount(link.ped)) and GetRiderOfMount(r.entity, false) == 0 then
                                            TaskGoToEntity(r.entity, link.ped, -1, 10.2, 2.0, 0.0, 0)
                                            r.whistleApproaching = true
                                            stats.tasks = stats.tasks + 1
                                            print('[bcc-stables] whistle received; current horse approach requested.')
                                            else
                                                if CurrentCompanion(r, link) and CompanionSlots(link.player) == r.entity then
                                                    local reply=Rpc('whistle',{})
                                                    if reply.ok and reply.value and reply.value.generationId==r.generationId and reply.value.relayed then
                                                        print('[bcc-stables] whistle relayed to current network owner '..tostring(reply.value.networkOwner)..'.')
                                                    else print('[bcc-stables] whistle relay refused: '..tostring(reply.code)) end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                else
                    r.whistleApproaching = nil
                    stats.gated = stats.gated + 1
                end
            end
        end)
        r.whistleListening = nil
        if not ok then print('[bcc-stables] whistle listener failed: ' .. tostring(failure)) end
    end)
end

local function Initialize(record)
    local horse = record.entity
    SetEntityVisible(horse, false)
    FreezeEntityPosition(horse, true)
    SetEntityInvincible(horse, true)
    SetBlockingOfNonTemporaryEvents(horse, true)
    Citizen.InvokeNative(0x283978A15512B2FE, horse, true) -- Random outfit variation.

    local position = GetEntityCoords(horse)
    local started, collision = GetGameTimer(), false
    while StillControlled(record) and GetGameTimer() - started < 5000 do
        RequestCollisionAtCoord(position.x, position.y, position.z)
        collision = Yes(HasCollisionLoadedAroundEntity(horse))
        if collision then break end
        Wait(25)
    end
    if not collision or not StillControlled(record) then return false, collision, false end

    FreezeEntityPosition(horse, false)
    ClearPedTasksImmediately(horse, false, false)
    -- Same RDR3 grounding native used by BCC Horses and Character arrival.
    Citizen.InvokeNative(0x9587913B9E772D29, horse, true) -- PlaceEntityOnGroundProperly
    TaskStandStill(horse, 2000)

    -- Allow the physics/animation pose to settle before freezing the fixture.
    -- A freeze immediately after creation can retain a visible mid-air pose.
    started = GetGameTimer()
    local stableSince
    while StillControlled(record) and GetGameTimer() - started < 3000 do
        if not Yes(IsEntityInAir(horse)) and not Yes(IsPedFalling(horse)) then
            stableSince = stableSince or GetGameTimer()
            if GetGameTimer() - stableSince >= 750 then
                FreezeEntityPosition(horse, true)
                return true, true, true
            end
        else
            stableSince = nil
        end
        Wait(50)
    end
    -- Do not re-freeze/reveal an unsettled horse as a successful fixture.
    return false, true, false
end

local function Release(r, deleteLocally)
    pcall(ClearCompanion, r)
    r.cancelled = true
    if type(r.netId) == 'number' and r.netId % 1 == 0 and r.netId > 0 then
        lastRetired = { generationId = r.generationId, netId = r.netId }
    end
    if not retired[r.generationId] then
        retired[r.generationId] = true; retiredOrder[#retiredOrder + 1] = r.generationId
        if #retiredOrder > 64 then retired[table.remove(retiredOrder, 1)] = nil end
    end
    if deleteLocally ~= false and r.createdLocally and not r.identityLost and Exists(r.entity) and GetEntityModel(r.entity) == r.hash
        and (r.netId == nil or NetworkGetNetworkIdFromEntity(r.entity) == r.netId)
        and (not r.marked or (Entity(r.entity).state.bccStablesGeneration == r.generationId
            and Entity(r.entity).state.bccStablesObserver == r.observerId))
        and Yes(NetworkHasControlOfEntity(r.entity)) then
        DeleteEntity(r.entity)
    end
    if r.hash then SetModelAsNoLongerNeeded(r.hash) end
    if active == r then active = nil end
end

local function Spec(p)
    if type(p) ~= 'table' or not Uuid(p.generationId) or not Uuid(p.observerId)
        or type(p.modelKey) ~= 'string' or #p.modelKey > 100 or not p.modelKey:match('^a_c_horse_[a-z0-9_]+$')
        or type(p.position) ~= 'table' then
        return false
    end
    for _, k in ipairs({ 'x', 'y', 'z', 'heading' }) do
        local v = p.position[k]; if type(v) ~= 'number' or v ~= v or math.abs(v) > 1000000 then return false end
    end
    return true
end

RegisterNetEvent('bcc-stables:call:cancel', function(id)
    if source == 65535 and active and active.generationId == id then Release(active, false) end
end)

RegisterNetEvent('bcc-stables:call:create', function(spec)
    if source ~= 65535 or not Spec(spec) or active or retired[spec.generationId] then return end

    local r = { generationId = spec.generationId, observerId = spec.observerId, modelKey = spec.modelKey, holdBind = holdNextBind }
    active = r
    local timing = { started = GetGameTimer() }
    holdNextBind = false
    CreateThread(function()
        local ok, failure = pcall(function()
            if GetResourceState('feather-toolkit') ~= 'started' then error('feather-toolkit unavailable') end

            local caps = exports['feather-toolkit']:GetCapabilities()
            assert(type(caps) == 'table' and caps.ok and type(caps.value) == 'table' and caps.value.contract == 1
                and type(caps.value.features) == 'table' and caps.value.features.models == 1, 'Toolkit model contract unavailable')
            local loaded = exports['feather-toolkit']:LoadModel(spec.modelKey, 5000)
            assert(
            type(loaded) == 'table' and loaded.ok and type(loaded.value) == 'table' and type(loaded.value.hash) ==
            'number', 'Model load failed')
            timing.modelMs = GetGameTimer() - timing.started
            local entityStarted = GetGameTimer()
            r.hash = loaded.value.hash
            if r.cancelled then
                SetModelAsNoLongerNeeded(r.hash)
                return
            end

            local p = spec.position
            r.entity = CreatePed(r.hash, p.x + 0.0, p.y + 0.0, p.z + 0.0, p.heading + 0.0, true, true, false, false)
            assert(Exists(r.entity), 'Client CreatePed failed')
            r.createdLocally = true
            SetEntityVisible(r.entity, false); FreezeEntityPosition(r.entity, true)
            SetEntityAsMissionEntity(r.entity, true, true)
            Entity(r.entity).state:set('bccStablesGeneration', spec.generationId, true)
            Entity(r.entity).state:set('bccStablesObserver', spec.observerId, true)
            r.marked = true
            if not Yes(NetworkGetEntityIsNetworked(r.entity)) then NetworkRegisterEntityAsNetworked(r.entity) end

            local started = GetGameTimer()
            repeat
                if r.cancelled then return end

                local id = NetworkGetNetworkIdFromEntity(r.entity)
                if id and id > 0 then
                    r.netId = id; break
                end

                assert(GetGameTimer() - started < 5000, 'Network ID unavailable'); Wait(25)
            until false
            timing.entityMs = GetGameTimer() - entityStarted
            local groundingStarted = GetGameTimer()
            local initialized, collision, settled = Initialize(r)
            timing.groundingMs = GetGameTimer() - groundingStarted
            assert(initialized and collision and settled, 'Horse did not settle on loaded ground')
            if r.cancelled then return end

            local holdStarted = GetGameTimer()
            if r.holdBind then
                print('[bcc-stables] native binding paused for 10 seconds; log out to character selection now.')
                local paused = GetGameTimer()
                while not r.cancelled and GetGameTimer() - paused < 10000 do Wait(50) end
                if r.cancelled then
                    print('[bcc-stables] paused native spawn cancelled; no bind sent.')
                    return
                end
                assert(StillControlled(r), 'Paused horse identity/control changed before binding')
            end

            timing.holdMs = GetGameTimer() - holdStarted
            local bindStarted = GetGameTimer()
            local bound = Rpc('bind', { generationId = r.generationId, netId = r.netId })
            timing.bindMs = GetGameTimer() - bindStarted
            assert(bound.ok and type(bound.value) == 'table' and bound.value.state == 'active'
                and bound.value.generationId == r.generationId and bound.value.netId == r.netId,
                'Binding rejected: ' .. tostring(bound.code))
            if r.cancelled then return end

            assert(StillControlled(r), 'Horse control lost before reveal')
            r.bound = true
            SetEntityVisible(r.entity, true)
            -- First controlled lifecycle gate retains the accepted proof's frozen,
            -- invincible pose. Riding/following/tack are separate gameplay work.
            print(('[bcc-stables] native horse bound; generationId=%s netId=%s initialized=true collisionLoaded=true settled=true')
            :format(r.generationId, r.netId))
            Timing('client generationId=%s modelMs=%d entityMs=%d groundingMs=%d holdMs=%d bindRpcMs=%d totalMs=%d',
                r.generationId, timing.modelMs, timing.entityMs, timing.groundingMs, timing.holdMs, timing.bindMs,
                GetGameTimer() - timing.started)
        end)

        if not ok then
            print('[bcc-stables] native horse failed: ' ..
            tostring(failure) .. '; inspect the call generation before retrying.')
            Release(r)
            pcall(Rpc, 'store', { generationId = r.generationId })
        end
    end)
end)

AddEventHandler('entityRemoved', function(entity)
    if active and active.entity == entity then active.identityLost = true end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and active then Release(active) end
end)

local function Command(name, route)
    RegisterCommand(name, function(_, args)
        if busy then return end
        args = args or {}
        local current = route == 'store' and #args == 0
        if not current and (#args ~= 1 or not Uuid(args[1])) then
            print('[bcc-stables] ' .. name .. ' ' .. (route == 'store' and '[generationId]' or '<generationId>')); return
        end
        busy = true
        CreateThread(function()
            local ok, result = pcall(Rpc, current and 'store_current' or route,
                current and {} or { generationId = args[1]:lower() })
            local v = ok and result.value
            local valid = type(v) == 'table' and v.gameplayAvailable == false
                and ((current and ((v.state == 'empty' and v.generationId == nil) or (v.state == 'released' and Uuid(v.generationId))))
                    or (not current and v.generationId == args[1]:lower() and v.state == (route == 'dispatch' and 'submitting' or 'released')))
                and (route ~= 'dispatch' or v.entitySpawning == true)
            if ok and result.ok == true and valid then
                print(('[bcc-stables] %s PASS; generationId=%s state=%s'):format(name,
                    tostring(result.value.generationId), tostring(result.value.state)))
            elseif route == 'store' and ok and result.ok == false and result.code == 'cleanup_pending' then
                print('[bcc-stables] ' .. name .. ' pending; deletion requested, waiting for disappearance.')
            else
                print('[bcc-stables] ' .. name ..
                ' failed: ' .. tostring(ok and (result.code or 'invalid_result') or result))
            end
            busy = false
        end)
    end, false)
end

Command('BccStablesCallDispatch', 'dispatch')

Command('BccStablesHorseStore', 'store')

RegisterCommand('BccStablesHorseCall', function(_, args)
    args = args or {}
    if #args ~= 0 then
        print('[bcc-stables] BccStablesHorseCall'); return
    end
    if busy then return end
    busy = true
    CreateThread(function()
        local requestStarted = GetGameTimer()
        local ok, result = pcall(Rpc, 'request', {})
        local v = ok and type(result) == 'table' and result.value
        if ok and result.ok == true and type(v) == 'table' and Uuid(v.generationId)
            and v.state == 'submitting' and v.entitySpawning == true and v.gameplayAvailable == false then
            print('[bcc-stables] call requested; generationId=' .. v.generationId .. '; waiting for native binding.')
            Timing('request_rpc generationId=%s roundTripMs=%d', v.generationId, GetGameTimer() - requestStarted)
        else
            print('[bcc-stables] call failed: ' ..
                tostring(ok and type(result) == 'table' and (result.code or 'invalid_result') or result)
                .. '; run BccStablesCallInspect before retrying.')
        end
        busy = false
    end)
end, false)

-- One-shot local acceptance aid; cannot authorize a spawn or alter server leases.
RegisterCommand('BccStablesCallHold', function(_, args)
    args = args or {}
    if #args == 1 and args[1] == 'cancel' then
        holdNextBind = false
        print('[bcc-stables] next native-bind pause disarmed.')
        return
    end
    if #args ~= 0 then
        print('[bcc-stables] BccStablesCallHold [cancel]'); return
    end
    if active then
        print('[bcc-stables] store the active horse before arming a native-bind pause.'); return
    end
    holdNextBind = true
    print('[bcc-stables] next native spawn will pause before binding for 10 seconds.')
end, false)


-- Replay only this client's recorded identity. Never consumes a success as a
-- creation instruction, and never accepts caller-supplied IDs or model data.
RegisterCommand('BccStablesCallReplay', function(_, args)
    args = args or {}
    if busy then return end
    local mode = #args == 1 and args[1]
    if mode ~= 'duplicate' and mode ~= 'stale' then
        print('[bcc-stables] BccStablesCallReplay duplicate|stale'); return
    end
    local record = mode == 'duplicate' and active or mode == 'stale' and lastRetired
    if not record or not record.netId or (mode == 'duplicate' and (not record.bound or record.cancelled)) then
        print(
        '[bcc-stables] replay requires duplicate (active bound horse) or stale (previously retired native identity).')
        return
    end
    local payload = { generationId = record.generationId, netId = record.netId }
    local expected = mode == 'duplicate' and 'binding_conflict' or 'stale_call'
    busy = true
    CreateThread(function()
        Wait(2100) -- Keep replay outside the ordinary bind rate window.
        local called, reply = pcall(Rpc, 'bind', payload)
        local outcome = called and type(reply) == 'table' and (reply.ok == true and 'accepted' or reply.code) or
        'transport_error'
        local passed = called and type(reply) == 'table' and reply.ok == false and outcome == expected
        print(('[bcc-stables] bind replay %s %s; generationId=%s expected=%s outcome=%s'):format(
            mode, passed and 'PASS' or 'FAIL', payload.generationId, expected, tostring(outcome)))
        busy = false
    end)
end, false)

-- Explicit native movement feasibility; the ordinary call remains frozen.
RegisterCommand('BccStablesMovementProof', function(_, args)
    args = args or {}
    if #args ~= 0 then
        print('[bcc-stables] BccStablesMovementProof'); return
    end
    if busy then return end
    local r = active
    if not r or not r.bound or not StillControlled(r) then
        print('[bcc-stables] movement proof requires your current bound, controlled horse.'); return
    end
    busy = true
    CreateThread(function()
        local ok, failure = pcall(function()
            AuthorizeProof(r)
            if not r.movementProof then
                SetBlockingOfNonTemporaryEvents(r.entity, false)
                FreezeEntityPosition(r.entity, false)
                ClearPedTasksImmediately(r.entity, false, false)
                r.movementProof = true
            end
            print(
            '[bcc-stables] movement proof enabled; horse unfrozen, invincibility retained. Dismount before storing.')
        end)
        if not ok then
            if active == r and not r.movementProof and StillControlled(r) then
                pcall(function()
                    FreezeEntityPosition(r.entity, true); SetBlockingOfNonTemporaryEvents(r.entity, true)
                end)
            end
            print('[bcc-stables] movement proof failed: ' .. tostring(failure))
        end
        busy = false
    end)
end, false)

RegisterCommand('BccStablesCompanionProof', function(_, args)
    args = args or {}
    if #args ~= 0 then
        print('[bcc-stables] BccStablesCompanionProof'); return
    end

    if busy then return end

    local r = active
    if not r or not r.bound or not r.movementProof or not StillControlled(r) then
        print('[bcc-stables] call your horse and enable BccStablesMovementProof first.'); return
    end

    busy = true
    CreateThread(function()
        local ok, failure = pcall(function()
            AuthorizeProof(r)
            local player, ped = PlayerId(), PlayerPedId()
            assert(type(player) == 'number' and player >= 0 and Exists(ped), 'Current player/ped required')
            local saddle, mount = CompanionSlots(player)
            assert((saddle == 0 or saddle == r.entity) and (mount == 0 or mount == r.entity),
                'Another horse owns a native association; nothing changed')
            if r.companionProof then assert(r.companionProof.player == player and r.companionProof.ped == ped,
                    'Association belongs to another player incarnation') end
            if not r.companionProof then
                r.companionProof = { player = player, ped = ped, wroteSaddle = saddle == 0, clearActive = saddle == 0 and
                mount == 0 }
                if saddle == 0 then Citizen.InvokeNative(0xD2CB0FB0FDCB473D, player, r.entity) end
            end
            local actual = CompanionSlots(player)
            assert(actual == r.entity, 'Native saddle-horse association did not bind')
            ListenForWhistle(r)
            print(
            '[bcc-stables] companion proof PASS; saddle association matches the current horse; whistle listener enabled.')
        end)
        if not ok then
            if active == r then pcall(ClearCompanion, r) end
            print('[bcc-stables] companion proof failed: ' .. tostring(failure))
        end
        busy = false
    end)
end, false)

RegisterCommand('BccStablesCompanionInspect', function(_, args)
    if #(args or {}) ~= 0 then
        print('[bcc-stables] BccStablesCompanionInspect'); return
    end
    local ok, failure = pcall(function()
        local saddle, mount = CompanionSlots(PlayerId())
        local matches = active and active.bound and not active.cancelled and saddle == active.entity or false
        print(('[bcc-stables] companion inspect; saddle=%s active=%s matchesBoundHorse=%s'):format(saddle, mount,
            tostring(matches)))
    end)
    if not ok then print('[bcc-stables] companion inspect failed: ' .. tostring(failure)) end
end, false)

RegisterCommand('BccStablesWhistleInspect', function(_, args)
    if #(args or {}) ~= 0 then
        print('[bcc-stables] BccStablesWhistleInspect'); return
    end
    local r = active
    if not r or not r.whistleStats then
        print('[bcc-stables] no whistle listener diagnostic; enable companion proof first.'); return
    end
    local s = r.whistleStats
    print(('[bcc-stables] whistle inspect; listening=%s frames=%s gated=%s events=%s whistles=%s payloads=%s owned=%s tasks=%s eventPed=%s ownerPed=%s saddle=%s horse=%s mounted=%s rider=%s hashes=%s')
    :format(
        tostring(r.whistleListening == true), s.frames, s.gated, s.events, s.whistles, s.payloads, s.owned, s.tasks,
        tostring(s.eventPed), tostring(r.companionProof and r.companionProof.ped), tostring(s.saddle), tostring(r.entity),
        tostring(s.mounted), tostring(s.rider), table.concat(s.hashes, ',')))
end, false)


-- Simulation delegation is a server instruction, not horse ownership. Tickets
-- are redeemed against the live observer before any entity task is applied.
local delegated={}
RegisterNetEvent('bcc-stables:call:whistle_cancel',function(p)
    if source~=65535 or type(p)~='table' then return end
    local r=delegated[p.generationId]
    if r and r.sequence==p.sequence and (not r.observerId or r.observerId==p.observerId) then
        r.cancelled=true
    end
end)
RegisterNetEvent('bcc-stables:call:whistle',function(p)
    if source~=65535 or type(p)~='table' or not Uuid(p.generationId)
        or type(p.sequence)~='number' or p.sequence%1~=0 or p.sequence<1 then return end
    local previous=delegated[p.generationId]
    if previous and previous.sequence>=p.sequence then return end
    local count=0; for _ in pairs(delegated) do count=count+1 end
    if not previous and count>=32 then return end
    if previous then previous.cancelled=true end
    local r={sequence=p.sequence}; delegated[p.generationId]=r
    CreateThread(function()
        local ok,failure=pcall(function()
            local reply=Rpc('whistle_claim',{generationId=p.generationId,sequence=p.sequence})
            local v=reply.value
            if not reply.ok then print('[bcc-stables] delegated whistle claim refused: '..tostring(reply.code)); return end
            if not reply.ok or type(v)~='table' or r.cancelled or delegated[p.generationId]~=r
                or v.generationId~=p.generationId or v.sequence~=p.sequence or not Uuid(v.observerId)
                or type(v.netId)~='number' or v.netId%1~=0 or v.netId<1
                or type(v.targetNetId)~='number' or v.targetNetId%1~=0 or v.targetNetId<1
                or type(v.modelKey)~='string' or not v.modelKey:match('^a_c_horse_[a-z0-9_]+$') then return end
            r.observerId=v.observerId
            local horse=NetworkGetEntityFromNetworkId(v.netId)
            local target=NetworkGetEntityFromNetworkId(v.targetNetId)
            local function valid()
                local player=GetPlayerFromServerId(v.ownerSource)
                return not r.cancelled and delegated[p.generationId]==r and player~=-1
                    and GetPlayerPed(player)==target and Exists(target) and Exists(horse)
                    and GetEntityModel(horse)==GetHashKey(v.modelKey)
                    and NetworkGetNetworkIdFromEntity(horse)==v.netId
                    and NetworkGetNetworkIdFromEntity(target)==v.targetNetId
                    and Entity(horse).state.bccStablesGeneration==v.generationId
                    and Entity(horse).state.bccStablesObserver==v.observerId
                    and Yes(NetworkHasControlOfEntity(horse))
                    and not Yes(IsPedOnMount(target)) and GetRiderOfMount(horse,false)==0
            end
            if not valid() then return end
            TaskGoToEntity(horse,target,-1,10.2,2.0,0.0,0)
            print('[bcc-stables] delegated whistle approach started.')
            local started=GetGameTimer()
            while valid() and GetGameTimer()-started<20000 do
                local a,b=GetEntityCoords(horse),GetEntityCoords(target)
                local dx,dy,dz=a.x-b.x,a.y-b.y,a.z-b.z
                if dx*dx+dy*dy+dz*dz<=100 then break end
                Wait(50)
            end
            -- Never clear rider tasks or touch a changed/reused entity.
            -- Cancellation can stop our exact task if control/identity survives.
            local cancelled=r.cancelled; r.cancelled=false
            if delegated[p.generationId]==r and valid() then ClearPedTasks(horse) end
            r.cancelled=cancelled
        end)
        if delegated[p.generationId]==r then delegated[p.generationId]=nil end
        if not ok then print('[bcc-stables] delegated whistle failed: '..tostring(failure)) end
    end)
end)


-- Explicit relay acceptance aid: avoids the local control-acquisition path.
-- Server still resolves and authorizes the current generation/character owner.
RegisterCommand('BccStablesWhistleRelayProof',function(_,args)
    if #(args or {})~=0 then print('[bcc-stables] BccStablesWhistleRelayProof'); return end
    if busy then return end
    local r=active; local link=r and r.companionProof
    if not link or not CurrentCompanion(r,link) or CompanionSlots(link.player)~=r.entity then
        print('[bcc-stables] relay proof requires your current companion horse.'); return
    end
    busy=true
    CreateThread(function()
        local ok,failure=pcall(function()
            local reply=Rpc('whistle',{})
            if reply.ok and reply.value and reply.value.generationId==r.generationId and reply.value.relayed then
                print('[bcc-stables] relay proof sent to current network owner '..tostring(reply.value.networkOwner)..'; task/arrival not yet confirmed.')
            else print('[bcc-stables] relay proof refused: '..tostring(reply.code)) end
        end)
        busy=false
        if not ok then print('[bcc-stables] relay proof failed: '..tostring(failure)) end
    end)
end,false)
