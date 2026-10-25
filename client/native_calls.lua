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

-- Continue only an acknowledged cleanup-pending relocation. Errors/unknown
-- outcomes never retry a spawn request or fall back to a normal call.
local function CompleteRelocation(reply)
    if type(reply)~='table' or not reply.ok or type(reply.value)~='table' or not reply.value.relocation then return reply end
    local original=reply.value.originalGenerationId
    if not Uuid(original) then return {ok=false,code='invalid_result'} end
    local started=GetGameTimer()
    local announced=false
    while true do
        if type(reply)~='table' or not reply.ok then return reply end
        local v=reply.value
        if type(v)~='table' or v.originalGenerationId~=original or v.gameplayAvailable~=false then return {ok=false,code='invalid_result'} end
        if v.state=='replacement_requested' and Uuid(v.generationId) and v.generationId~=original then
            print(('[bcc-stables] relocation replacement requested; oldGenerationId=%s generationId=%s.'):format(original,v.generationId))
            return {ok=true,value={generationId=v.generationId,state='submitting',entitySpawning=true,
                gameplayAvailable=false,relocation=true,originalGenerationId=original}}
        end
        if v.state~='cleanup_pending' or v.retryRequired~=true then return {ok=false,code='invalid_result'} end
        if GetGameTimer()-started>=15000 then
            print('[bcc-stables] relocation still pending; inspect the current call. Original generation '..original)
            return {ok=false,code='relocation_pending'}
        end
        if not announced then print('[bcc-stables] relocation cleanup pending; waiting for confirmed disappearance.'); announced=true end
        Wait(1500)
        reply=Rpc('relocate_proof',{generationId=original})
    end
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

local function Leading(ped)
    local leading=Citizen.InvokeNative(0xEFC4303DDC6E60D3,ped)
    local horse=Citizen.InvokeNative(0xED1F514AF4732258,ped,Citizen.ResultAsInteger())
    assert(leading==true or leading==false or leading==0 or leading==1,'Unknown leading observation')
    assert(type(horse)=='number' and horse%1==0 and horse>=0,'Unknown led horse')
    return Yes(leading),horse
end

local function HorseOccupied(entity)
    -- Check both native rider variants; reject unknown handles instead of
    -- treating a failed native as an empty saddle.
    for _,flag in ipairs({false,true}) do
        local rider=GetRiderOfMount(entity,flag)
        assert(type(rider)=='number' and rider%1==0 and rider>=0,'Invalid rider observation')
        if rider~=0 then return true end
    end
    local led=Citizen.InvokeNative(0xAC5045AB7F1A34FD,entity)
    assert(led==true or led==false or led==0 or led==1,'Unknown horse leading observation')
    if Yes(led) then return true end
    local ped=PlayerPedId()
    return Exists(ped) and Yes(IsPedOnMount(ped)) and GetMount(ped)==entity
end

-- Unknown rider observations suppress movement without terminating the listener.
local function HorseUnoccupied(entity)
    local ok,occupied=pcall(HorseOccupied,entity)
    return ok and not occupied
end

-- A missing/failed life observation cannot authorize a movement task.
local function Alive(entity)
    if not Exists(entity) then return false end
    local ok,dead,dying=pcall(function() return IsEntityDead(entity),IsPedDeadOrDying(entity,true) end)
    return ok and (dead==false or dead==0) and (dying==false or dying==0)
end

local function AuthorizeProof(r)
    local result = Rpc('movement_proof', {})
    local v = type(result) == 'table' and result.value
    assert(result.ok and type(v) == 'table' and v.generationId == r.generationId and v.observerId == r.observerId
        and v.netId == r.netId and v.modelKey == r.modelKey and v.state == 'active'
        and v.movementProof == true and v.gameplayAvailable == false, 'Native proof refused: ' .. tostring(result.code))
    assert(active == r and StillControlled(r), 'Horse identity/control changed during authorization')
    return v
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

-- Native prompt leading is not a new grant: this only observes the local
-- player's current lead on the exact already-bound companion for release.
local function OwnNativeLead(r)
    local link=r and r.companionProof
    if not r or not r.bound or not link or not CurrentCompanion(r,link)
        or not Alive(link.ped) or Yes(IsPedOnMount(link.ped)) then return false end
    local leading,horse=Leading(link.ped)
    return leading and horse==r.entity
end
local function StopLeadProof(r,includeNative)
    local proof=r.leadProof
    if not proof and includeNative and OwnNativeLead(r) then
        proof={link=r.companionProof,observed=true,started=GetGameTimer(),mode='native'}
        r.leadProof=proof
    end
    if not proof then return end
    local link=proof.link
    if CurrentCompanion(r,link) and Alive(link.ped) and not Yes(IsPedOnMount(link.ped)) then
        local leading,horse=Leading(link.ped)
        if leading and horse==r.entity then Citizen.InvokeNative(0xED27560703F37258,link.ped)
        elseif not leading and not proof.observed and GetGameTimer()-proof.started<2000 then
            proof.releaseRequested=true -- Await the exact attachment rather than stopping an unknown player task.
            return
        end
    end
    r.leadProof=nil
end

-- Wait only for a release initiated by our exact proof. No Store RPC is sent
-- until local occupancy clears; server still independently rechecks occupancy.
local function ReleaseLeadForStore(r)
    StopLeadProof(r,true)
    local deadline=GetGameTimer()+1500
    repeat
        if active~=r or not r.bound or not SameHorse(r) then return false,'stale_call' end
        if not r.leadProof and not HorseOccupied(r.entity) then return true end
        if GetGameTimer()>=deadline then return false,'horse_occupied' end
        Wait(50)
    until false
end

local function StopFollowProof(r)
    local proof=r.followProof
    if not proof then return end
    r.followProof=nil
    local link=proof.link
    -- Do not clear a rider's task or a different player/entity incarnation.
    if CurrentCompanion(r,link) and StillControlled(r) and Exists(link.ped)
        and CompanionSlots(link.player)==r.entity and not Yes(IsPedOnMount(link.ped))
        and Alive(r.entity) and HorseUnoccupied(r.entity) then ClearPedTasks(r.entity) end
end

-- Event payload: whistling ped at byte 0, whistle kind at byte 8.
-- One frame listener only while an explicitly authorized companion is present.
local function ListenForWhistle(r)
    if r.whistleListening then return end
    r.whistleListening = true
    r.whistleStats = { frames = 0, gated = 0, events = 0, whistles = 0, payloads = 0, owned = 0, requests = 0, hashes = {} }
    CreateThread(function()
        local ok, failure = pcall(function()
            local makeBlob = rawget(string, 'blob') or function(n) return string.rep('\0', n) end
            local buffer = makeBlob(16)
            local lastWhistle = -2000
            local shortWhistle=GetHashKey('WHISTLEHORSESHORT') & 0xffffffff
            local longWhistle=GetHashKey('WHISTLEHORSELONG') & 0xffffffff
            while active == r and not r.cancelled and r.companionProof do
                Wait(0)
                if active ~= r or r.cancelled or not r.companionProof then break end
                local link = r.companionProof
                local stats = r.whistleStats
                stats.frames = stats.frames + 1
                if CurrentCompanion(r, link) then
                    if not StillControlled(r) then stats.gated = stats.gated + 1 end
                    if r.leadProof and GetGameTimer()>=(r.leadProof.nextCheck or 0) then
                        local proof=r.leadProof
                        proof.nextCheck=GetGameTimer()+100
                        local leading,horse=Leading(link.ped)
                        if leading and horse==r.entity then proof.observed=true end
                        if proof.releaseRequested then
                            StopLeadProof(r)
                        elseif (proof.expires and GetGameTimer()>=proof.expires) or not StillControlled(r) or not Alive(r.entity) or not Alive(link.ped)
                            or Yes(IsPedOnMount(link.ped)) or (leading and horse~=r.entity)
                            or (not leading and GetGameTimer()-proof.started>=2000) then
                            StopLeadProof(r)
                            print('[bcc-stables] leading ended; timeout or eligibility changed.')
                        end
                    end
                    if r.followProof and GetGameTimer()>=(r.followProof.nextCheck or 0) then
                        r.followProof.nextCheck=GetGameTimer()+100
                        if GetGameTimer()>=r.followProof.expires or not StillControlled(r)
                            or CompanionSlots(link.player)~=r.entity or Yes(IsPedOnMount(link.ped))
                            or not HorseUnoccupied(r.entity) or not Alive(r.entity) or not Alive(link.ped) then
                            StopFollowProof(r)
                            print('[bcc-stables] follow proof ended; expired or movement eligibility changed.')
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
                                    stats.kind=string.unpack('<i4',buffer,9) & 0xffffffff
                                    local mode=stats.kind==shortWhistle and 'approach' or stats.kind==longWhistle and 'toggle_follow'
                                    if mode and not busy and CurrentCompanion(r,link) and GetGameTimer() - lastWhistle >= 1500 then
                                        local saddle = CompanionSlots(link.player)
                                        stats.saddle = saddle
                                        stats.mounted = Yes(IsPedOnMount(link.ped))
                                        local riderOk,rider=pcall(GetRiderOfMount,r.entity,false)
                                        stats.rider = riderOk and rider or nil
                                        if saddle == r.entity and not stats.mounted and HorseUnoccupied(r.entity) and Alive(r.entity) and Alive(link.ped) then
                                            StopFollowProof(r)
                                            lastWhistle = GetGameTimer()
                                            busy=true
                                            local called,reply=pcall(function() return CompleteRelocation(Rpc('whistle',{mode=mode})) end)
                                            busy=false
                                            if not called then reply={ok=false,code='transport_error'} end
                                            if reply.ok and reply.value and reply.value.relocation then
                                                stats.requests=stats.requests+1; stats.action='relocate'
                                                print('[bcc-stables] whistle relocation requested; waiting for native binding.')
                                            elseif reply.ok and reply.value and reply.value.generationId==r.generationId and reply.value.relayed then
                                                stats.requests=stats.requests+1
                                                stats.action=reply.value.mode
                                                if stats.action=='stop' then print('[bcc-stables] whistle follow stop requested.')
                                                else print('[bcc-stables] whistle '..tostring(stats.action)..' requested; networkOwner='..tostring(reply.value.networkOwner)..'.') end
                                            else print('[bcc-stables] whistle request refused: '..tostring(reply.code)) end
                                        end
                                    end
                                end
                            end
                        end
                    end
                else
                    StopFollowProof(r)
                    stats.gated = stats.gated + 1
                end
            end
        end)
        pcall(StopLeadProof,r)
        pcall(StopFollowProof,r)
        r.whistleListening = nil
        if not ok then print('[bcc-stables] whistle listener failed: ' .. tostring(failure)) end
    end)
end

local function EnableMovement(r)
    assert(active==r and r.bound and StillControlled(r) and Alive(r.entity) and Alive(PlayerPedId()),'Current living bound control required')
    if not r.movementProof then
        SetBlockingOfNonTemporaryEvents(r.entity,false)
        FreezeEntityPosition(r.entity,false)
        ClearPedTasksImmediately(r.entity,false,false)
        -- BCC Horses reference: native interaction lock-on exposes Lead Horse.
        -- Apply once to this verified mount, never as a per-frame/global override.
        Citizen.InvokeNative(0x1913FE4CBF41C463,r.entity,297,true)
        r.movementProof=true
    end
end

local function AttachCompanion(r)
    assert(active==r and r.bound and r.movementProof and StillControlled(r),'Current controlled movement horse required')
    local player, ped = PlayerId(), PlayerPedId()
    assert(type(player) == 'number' and player >= 0 and Alive(ped) and Alive(r.entity), 'Current living player/horse required')
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
    assert(active==r and StillControlled(r) and Alive(ped) and Alive(r.entity),'Companion control/life changed during association')
    ListenForWhistle(r)
end

local function ActivateNativeBehavior(r)
    -- Binding already completed fresh canonical/session/identity validation.
    -- Optional native behavior failure must never delete a committed horse.
    local moved,why=pcall(EnableMovement,r)
    if not moved then
        if not r.movementProof and active==r and StillControlled(r) then
            pcall(function() FreezeEntityPosition(r.entity,true); SetBlockingOfNonTemporaryEvents(r.entity,true) end)
        end
        pcall(print,'[bcc-stables] native movement unavailable; inspect current call: '..tostring(why))
        return
    end
    local linked,failure=pcall(AttachCompanion,r)
    if not linked then
        pcall(ClearCompanion,r)
        pcall(print,'[bcc-stables] horse movement enabled; companion controls unavailable: '..tostring(failure))
        return
    end
    pcall(print,'[bcc-stables] native horse ready; riding and whistle controls enabled; invincibility retained.')
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
    pcall(StopLeadProof,r,true)
    pcall(StopFollowProof,r)
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
            -- Frozen by default. Opt-in basic behavior activates only after the
            -- server-authorized bind; controlled invincibility is retained.
            print(('[bcc-stables] native horse bound; generationId=%s netId=%s initialized=true collisionLoaded=true settled=true')
            :format(r.generationId, r.netId))
            if bound.value.nativeBehavior==true then ActivateNativeBehavior(r) end
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

local function Command(name, route, serverGuardProof)
    local function Run(args)
        if busy then return false,'busy' end
        args = args or {}
        local current = route == 'store' and #args == 0
        if not current and (#args ~= 1 or not Uuid(args[1])) then
            print('[bcc-stables] ' .. name .. ' ' .. (route == 'store' and '[generationId]' or '<generationId>')); return false,'invalid_input'
        end
        if route=='store' and not serverGuardProof and active and active.bound and SameHorse(active)
            and (current or args[1]:lower()==active.generationId) then
            local observed,nativeLead=pcall(OwnNativeLead,active)
            if not observed then return false,'occupancy_unknown' end
            if active.leadProof or nativeLead then
                busy=true
                local released,clear,reason=pcall(ReleaseLeadForStore,active)
                busy=false
                if not released or not clear then
                    print('[bcc-stables] '..name..' failed: '..tostring(released and reason or 'occupancy_unknown')
                        ..'; finish releasing the lead or dismount before storing.')
                    return false,released and reason or 'occupancy_unknown'
                end
            end
            local ok,occupied=pcall(HorseOccupied,active.entity)
            if not ok or occupied then
                print('[bcc-stables] '..name..' failed: '..(ok and 'horse_occupied; dismount or finish releasing the lead before storing.' or 'occupancy_unknown; horse retained.'))
                return false,ok and 'horse_occupied' or 'occupancy_unknown'
            end
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
        return true
    end
    RegisterCommand(name,function(_,args) Run(args) end,false)
    return Run
end

Command('BccStablesCallDispatch', 'dispatch')

local StoreCurrent=Command('BccStablesHorseStore', 'store')
Command('BccStablesStoreGuardProof','store',true)

local function HorseCall()
    if busy then return false,'busy' end
    busy = true
    CreateThread(function()
        local requestStarted = GetGameTimer()
        local ok, result = pcall(function() return CompleteRelocation(Rpc('request',{})) end)
        local v = ok and type(result) == 'table' and result.value
        if ok and result.ok == true and type(v) == 'table' and Uuid(v.generationId)
            and v.state == 'submitting' and v.entitySpawning == true and v.gameplayAvailable == false then
            print('[bcc-stables] call requested; generationId=' .. v.generationId .. '; waiting for native binding.')
            Timing('request_rpc generationId=%s roundTripMs=%d', v.generationId, GetGameTimer() - requestStarted)
        elseif ok and result.ok == true and type(v)=='table' and Uuid(v.generationId)
            and v.state=='approach_requested' and v.mode=='approach' and v.relayed==true
            and v.entitySpawning==false and v.gameplayAvailable==false
            and type(v.networkOwner)=='number' and v.networkOwner%1==0 and v.networkOwner>0 then
            print('[bcc-stables] current horse approach requested; generationId='..v.generationId..'; networkOwner='..v.networkOwner..'.')
            Timing('request_rpc generationId=%s roundTripMs=%d',v.generationId,GetGameTimer()-requestStarted)
        else
            print('[bcc-stables] call failed: ' ..
                tostring(ok and type(result) == 'table' and (result.code or 'invalid_result') or result)
                .. '; run BccStablesCallInspect before retrying.')
        end
        busy = false
    end)
    return true
end
RegisterCommand('BccStablesHorseCall',function(_,args)
    if #(args or {})~=0 then print('[bcc-stables] BccStablesHorseCall'); return end
    HorseCall()
end,false)

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

-- Explicit movement diagnostic; ordinary calls may also opt into bound native behavior.
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
            EnableMovement(r)
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
            AttachCompanion(r)
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

-- Local observation only: these values never authorize a persisted care benefit.
RegisterCommand('BccStablesConditionInspect', function(_, args)
    if #(args or {})~=0 then print('[bcc-stables] BccStablesConditionInspect'); return end
    local ok,failure=pcall(function()
        local r=active
        if not r or not r.bound or not SameHorse(r) then error('no_current_bound_horse',0) end
        local function Core(index)
            local value=Citizen.InvokeNative(0x36731AC041289BB1,r.entity,index,Citizen.ResultAsInteger())
            if type(value)~='number' or value%1~=0 or value<0 or value>100 then
                error('condition_observation_unknown',0)
            end
            return value
        end
        local health,stamina=Core(0),Core(1)
        if active~=r or not SameHorse(r) then error('horse_identity_changed',0) end
        print(('[bcc-stables] condition inspect; generationId=%s healthCore=%s staminaCore=%s networkControlled=%s observationOnly=true persisted=false')
            :format(r.generationId,health,stamina,tostring(Yes(NetworkHasControlOfEntity(r.entity)))))
    end)
    if not ok then print('[bcc-stables] condition inspect failed: '..tostring(failure)) end
end,false)

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
    print(('[bcc-stables] whistle inspect; listening=%s frames=%s gated=%s events=%s whistles=%s payloads=%s owned=%s requests=%s eventPed=%s ownerPed=%s saddle=%s horse=%s mounted=%s rider=%s kind=%s action=%s hashes=%s')
    :format(
        tostring(r.whistleListening == true), s.frames, s.gated, s.events, s.whistles, s.payloads, s.owned, s.requests,
        tostring(s.eventPed), tostring(r.companionProof and r.companionProof.ped), tostring(s.saddle), tostring(r.entity),
        tostring(s.mounted), tostring(s.rider), tostring(s.kind), tostring(s.action), table.concat(s.hashes, ',')))
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
    local correlation=' generationId='..p.generationId..' sequence='..p.sequence
    CreateThread(function()
        local ok,failure=pcall(function()
            local reply=Rpc('whistle_claim',{generationId=p.generationId,sequence=p.sequence})
            local v=reply.value
            if not reply.ok then print('[bcc-stables] delegated whistle claim refused: '..tostring(reply.code)..correlation); return end
            if not reply.ok or type(v)~='table' or (v.mode~=nil and v.mode~='approach' and v.mode~='follow' and v.mode~='stop') or r.cancelled or delegated[p.generationId]~=r
                or v.generationId~=p.generationId or v.sequence~=p.sequence or not Uuid(v.observerId)
                or type(v.netId)~='number' or v.netId%1~=0 or v.netId<1
                or type(v.targetNetId)~='number' or v.targetNetId%1~=0 or v.targetNetId<1
                or type(v.modelKey)~='string' or not v.modelKey:match('^a_c_horse_[a-z0-9_]+$') then return end
            local followMs=v.followMs or 30000
            if v.mode=='follow' and (type(followMs)~='number' or followMs%1~=0 or followMs<1 or followMs>30000) then return end
            r.observerId=v.observerId
            r.reportFollowEnd=v.mode=='follow'
            local horse=NetworkGetEntityFromNetworkId(v.netId)
            local target=NetworkGetEntityFromNetworkId(v.targetNetId)
            local function valid(cleanup)
                local function refused(reason)
                    if not cleanup then r.endReason=reason end
                    return false
                end
                if r.cancelled then return refused('cancelled') end
                if delegated[p.generationId]~=r then return refused('superseded') end
                local player=GetPlayerFromServerId(v.ownerSource)
                if player==-1 or GetPlayerPed(player)~=target or not Exists(target)
                    or NetworkGetNetworkIdFromEntity(target)~=v.targetNetId then return refused('target_identity_changed') end
                if not Exists(horse) or GetEntityModel(horse)~=GetHashKey(v.modelKey)
                    or NetworkGetNetworkIdFromEntity(horse)~=v.netId
                    or Entity(horse).state.bccStablesGeneration~=v.generationId
                    or Entity(horse).state.bccStablesObserver~=v.observerId then return refused('horse_identity_changed') end
                if not Yes(NetworkHasControlOfEntity(horse)) then return refused('control_lost') end
                if Yes(IsPedOnMount(target)) then return refused('target_mounted') end
                if not HorseUnoccupied(horse) then return refused('horse_occupied_or_unknown') end
                if not Alive(horse) then return refused('horse_not_alive_or_unknown') end
                if not cleanup and not Alive(target) then return refused('target_not_alive_or_unknown') end
                return true
            end
            if not valid(v.mode=='stop') then return end
            if v.mode=='stop' then
                ClearPedTasks(horse)
                print('[bcc-stables] delegated follow stop applied.'..correlation)
                return
            end
            local following=v.mode=='follow'
            if following then
                Citizen.InvokeNative(0x304AE42E357B8C7E,horse,target,2.0,-3.0,0.0,2.0,followMs,3.0,true,false,false,false,false,false)
                print(('[bcc-stables] delegated follow started; remainingMs=%d mode=%s.'):format(followMs,v.normalFollow==true and 'normal' or 'proof')..correlation)
            else
                TaskGoToEntity(horse,target,-1,10.2,2.0,0.0,0)
                print('[bcc-stables] delegated whistle approach started.'..correlation)
            end
            local started=GetGameTimer()
            while valid() and GetGameTimer()-started<(following and followMs or 20000) do
                if not following then
                    local a,b=GetEntityCoords(horse),GetEntityCoords(target)
                    local dx,dy,dz=a.x-b.x,a.y-b.y,a.z-b.z
                    if dx*dx+dy*dy+dz*dz<=100 then r.endReason='arrived'; break end
                end
                Wait(50)
            end
            r.elapsedMs=GetGameTimer()-started
            r.endReason=r.endReason or 'timeout'
            -- Never clear rider tasks or touch a changed/reused entity.
            -- Cancellation can stop our exact task if control/identity survives.
            local cancelled=r.cancelled; r.cancelled=false
            if delegated[p.generationId]==r and valid(true) then ClearPedTasks(horse) end
            r.cancelled=cancelled
        end)
        if delegated[p.generationId]==r then delegated[p.generationId]=nil end
        -- One completion per redeemed follow, including early eligibility loss.
        -- A superseded worker's report cannot change the newer server sequence.
        if r.reportFollowEnd then
            pcall(print,('[bcc-stables] delegated follow worker ended; reason=%s elapsedMs=%d.'):format(
                r.endReason or (not ok and 'native_error' or 'eligibility_changed'),r.elapsedMs or 0)..correlation)
            pcall(function()
                local result=Rpc('whistle_done',{generationId=p.generationId,sequence=p.sequence})
                if result.ok then print('[bcc-stables] delegated follow ended; server intent cleared.'..correlation) end
            end)
        end
        if not ok then print('[bcc-stables] delegated whistle failed: '..tostring(failure)..correlation) end
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
            StopFollowProof(r)
            local reply=Rpc('whistle',{})
            if reply.ok and reply.value and reply.value.generationId==r.generationId and reply.value.relayed then
                print('[bcc-stables] relay proof sent to current network owner '..tostring(reply.value.networkOwner)..'; task/arrival not yet confirmed.')
            else print('[bcc-stables] relay proof refused: '..tostring(reply.code)) end
        end)
        busy=false
        if not ok then print('[bcc-stables] relay proof failed: '..tostring(failure)) end
    end)
end,false)


local function LeadEligible(r,link)
    if not r or not link or not r.movementProof or not CurrentCompanion(r,link)
        or CompanionSlots(link.player)~=r.entity or not Alive(r.entity) or not Alive(link.ped) then
        return false,'horse_unavailable'
    end
    if not StillControlled(r) then return false,'control_required' end
    if Yes(IsPedOnMount(link.ped)) then return false,'horse_occupied' end
    local leading,horse=Leading(link.ped)
    if r.leadProof and leading and horse==r.entity then return true,'already_leading' end
    if r.followProof or delegated[r.generationId] then return false,'movement_busy' end
    if leading or not HorseUnoccupied(r.entity) then return false,'horse_occupied' end
    local a,b=GetEntityCoords(link.ped),GetEntityCoords(r.entity)
    local dx,dy,dz=a.x-b.x,a.y-b.y,a.z-b.z
    if not (dx*dx+dy*dy+dz*dz<=6.25) then return false,'too_far' end
    return true
end

-- Shared owner-controlled leading; the diagnostic alone has a 30-second cap.
local function StartLeading(bounded)
    if busy then return false,'busy' end
    local r=active; local link=r and r.companionProof
    local checked,ready,reason=pcall(LeadEligible,r,link)
    if not checked or not ready then
        reason=checked and reason or 'horse_unavailable'
        print('[bcc-stables] leading unavailable: '..reason)
        return false,reason
    end
    if reason=='already_leading' then return true end
    busy=true
    CreateThread(function()
        local ok,failure=pcall(function()
            local authorized=AuthorizeProof(r)
            assert(bounded or authorized.nativeBehavior==true,'Normal leading requires nativeBehavior for this generation')
            assert(authorized.movementIdle==true,'Stop other movement and wait for its ticket to finish before leading')
            local ready,reason=LeadEligible(r,link)
            assert(ready,reason)
            if reason=='already_leading' then return end
            r.leadProof={link=link,started=GetGameTimer(),expires=bounded and GetGameTimer()+30000 or nil,mode=bounded and 'proof' or 'normal'}
            Citizen.InvokeNative(0x9A7A4A54596FE09D,link.ped,r.entity)
            print(bounded and '[bcc-stables] leading proof requested for up to 30 seconds; use BccStablesLeadStop to release.'
                or '[bcc-stables] leading requested; run BccStablesHorseLead again to release.')
        end)
        if not ok then pcall(StopLeadProof,r); print('[bcc-stables] leading proof failed: '..tostring(failure)) end
        busy=false
    end)
    return true
end
local function ReleaseLeading()
    if busy then return false,'busy' end
    local ok,failure=pcall(function() if active then StopLeadProof(active) end end)
    print(ok and '[bcc-stables] leading release requested.' or '[bcc-stables] leading stop failed: '..tostring(failure))
    return ok,not ok and 'horse_unavailable' or nil
end
RegisterCommand('BccStablesLeadProof',function(_,args)
    if #(args or {})~=0 then print('[bcc-stables] BccStablesLeadProof'); return end
    StartLeading(true)
end,false)
RegisterCommand('BccStablesHorseLead',function(_,args)
    if #(args or {})~=0 then print('[bcc-stables] BccStablesHorseLead'); return end
    if busy then return end
    if active and active.leadProof then ReleaseLeading(); return end
    StartLeading(false)
end,false)
RegisterCommand('BccStablesLeadStop',function(_,args)
    if #(args or {})~=0 then print('[bcc-stables] BccStablesLeadStop'); return end
    ReleaseLeading()
end,false)
RegisterCommand('BccStablesLeadInspect',function(_,args)
    if #(args or {})~=0 then print('[bcc-stables] BccStablesLeadInspect'); return end
    local ok,failure=pcall(function()
        local leading,horse=Leading(PlayerPedId())
        local tracked=active and active.leadProof
        print(('[bcc-stables] leading inspect; leading=%s horse=%s matchesBoundHorse=%s proofTracked=%s tracked=%s mode=%s'):format(
            tostring(leading),tostring(horse),tostring(active~=nil and horse==active.entity),tostring(tracked~=nil and tracked.mode=='proof'),
            tostring(tracked~=nil),tostring(tracked and tracked.mode)))
    end)
    if not ok then print('[bcc-stables] leading inspect failed: '..tostring(failure)) end
end,false)

-- Local feasibility first; long-whistle toggles and migrated follow are separate.
RegisterCommand('BccStablesFollowProof',function(_,args)
    if #(args or {})~=0 then print('[bcc-stables] BccStablesFollowProof'); return end
    if busy then return end
    local r=active; local link=r and r.companionProof
    if not link or not r.bound or not r.movementProof or not CurrentCompanion(r,link) or not StillControlled(r) then
        print('[bcc-stables] follow proof requires your current controlled movement/companion horse.'); return
    end
    busy=true
    CreateThread(function()
        local ok,failure=pcall(function()
            AuthorizeProof(r)
            assert(CurrentCompanion(r,link) and CompanionSlots(link.player)==r.entity,
                'Companion association changed during authorization')
            assert(not Yes(IsPedOnMount(link.ped)) and HorseUnoccupied(r.entity) and Alive(r.entity) and Alive(link.ped),'Living unridden horse and owner required')
            if not r.followProof then
                local old=delegated[r.generationId]
                if old then old.cancelled=true; delegated[r.generationId]=nil end
                r.followProof={link=link,expires=GetGameTimer()+30000}
                -- BCC Horses offsets/speed/range; finite timeout for this proof.
                Citizen.InvokeNative(0x304AE42E357B8C7E,r.entity,link.ped,2.0,-3.0,0.0,2.0,30000,3.0,true,false,false,false,false,false)
            end
            print('[bcc-stables] follow proof enabled for up to 30 seconds; use BccStablesFollowStop to stop.')
        end)
        if not ok then
            pcall(StopFollowProof,r)
            print('[bcc-stables] follow proof failed: '..tostring(failure))
        end
        busy=false
    end)
end,false)
RegisterCommand('BccStablesFollowStop',function(_,args)
    if #(args or {})~=0 then print('[bcc-stables] BccStablesFollowStop'); return end
    if busy then print('[bcc-stables] native command busy; retry follow stop.'); return end
    if active then StopFollowProof(active) end
    print('[bcc-stables] follow proof stopped.')
end,false)


for _,entry in ipairs({{'BccStablesFollowRelayProof','follow'},{'BccStablesFollowRelayStop','stop'}}) do
    local command,mode=entry[1],entry[2]
    RegisterCommand(command,function(_,args)
        if #(args or {})~=0 then print('[bcc-stables] '..command); return end
        if busy then return end
        local r=active; local link=r and r.companionProof
        if not link or not r.movementProof or not CurrentCompanion(r,link) or CompanionSlots(link.player)~=r.entity then
            print('[bcc-stables] follow relay requires your current movement/companion horse.'); return
        end
        busy=true
        CreateThread(function()
            local ok,failure=pcall(function()
                StopFollowProof(r)
                local reply=Rpc('whistle',{mode=mode})
                if reply.ok and reply.value and reply.value.generationId==r.generationId and reply.value.mode==mode then
                    if mode=='stop' then print('[bcc-stables] follow relay stop requested; verify the horse stops.')
                    else print('[bcc-stables] follow relay sent to current network owner '..tostring(reply.value.networkOwner)..'; movement not yet confirmed.') end
                else print('[bcc-stables] follow relay refused: '..tostring(reply.code)) end
            end)
            busy=false
            if not ok then print('[bcc-stables] follow relay failed: '..tostring(failure)) end
        end)
    end,false)
end


RegisterNetEvent('bcc-stables:call:store_check',function(p)
    if source~=65535 or type(p)~='table' or not Uuid(p.generationId) or not Uuid(p.observerId)
        or type(p.netId)~='number' or p.netId%1~=0 or p.netId<1
        or type(p.sequence)~='number' or p.sequence%1~=0 or p.sequence<1
        or type(p.modelKey)~='string' or not p.modelKey:match('^a_c_horse_[a-z0-9_]+$') then return end
    CreateThread(function()
        local ok,failure=pcall(function()
            local horse=NetworkGetEntityFromNetworkId(p.netId)
            local function valid()
                return Exists(horse) and NetworkGetNetworkIdFromEntity(horse)==p.netId
                    and GetEntityModel(horse)==GetHashKey(p.modelKey)
                    and Entity(horse).state.bccStablesGeneration==p.generationId
                    and Entity(horse).state.bccStablesObserver==p.observerId
                    and Yes(NetworkHasControlOfEntity(horse))
            end
            if not valid() then return end
            local occupied=HorseOccupied(horse)
            if not valid() then return end
            Rpc('store_check_result',{generationId=p.generationId,sequence=p.sequence,occupied=occupied})
        end)
        if not ok then print('[bcc-stables] store occupancy observation failed; server will retain horse: '..tostring(failure)) end
    end)
end)


local relocationOriginal
RegisterCommand('BccStablesRelocateProof',function(_,args)
    args=args or {}
    if #args>1 or (args[1] and not Uuid(args[1])) then print('[bcc-stables] BccStablesRelocateProof [originalGenerationId]'); return end
    if busy then return end
    local id=args[1] and args[1]:lower() or relocationOriginal or (active and active.generationId)
    if not id then print('[bcc-stables] relocation proof requires your original active generation.'); return end
    relocationOriginal=id
    busy=true
    CreateThread(function()
        local ok,failure=pcall(function()
            local reply=Rpc('relocate_proof',{generationId=id})
            local v=reply.value
            if reply.ok and type(v)=='table' and v.originalGenerationId==id and v.gameplayAvailable==false then
                if v.state=='cleanup_pending' then
                    print('[bcc-stables] relocation cleanup pending; no replacement requested. Retry BccStablesRelocateProof '..id..' after disappearance.')
                elseif v.state=='replacement_requested' and Uuid(v.generationId) and v.generationId~=id then
                    relocationOriginal=nil
                    print(('[bcc-stables] relocation replacement requested; oldGenerationId=%s generationId=%s replayed=%s; wait for native binding.'):format(id,v.generationId,tostring(v.replayed==true)))
                else print('[bcc-stables] relocation proof failed: invalid_result') end
            else print('[bcc-stables] relocation proof failed: '..tostring(reply.code or 'invalid_result')..'; inspect the current call before retrying.') end
        end)
        busy=false
        if not ok then print('[bcc-stables] relocation proof failed: '..tostring(failure)..'; inspect the current call before retrying.') end
    end)
end,false)


-- Resource-local command/menu adapter; no cross-resource export or authority.
-- Accepted means local operation started, not confirmed server/entity success.
StablesNativeControls={Call=HorseCall,Store=function() return StoreCurrent({}) end}

RegisterNetEvent('bcc-stables:call:care_check',function(p)
    if source~=65535 or type(p)~='table' or not Uuid(p.generationId) or not Uuid(p.observerId)
        or type(p.modelKey)~='string' or not p.modelKey:match('^a_c_horse_[a-z0-9_]+$') then return end
    for _,key in ipairs({'netId','ownerSource','targetNetId','sequence'}) do
        local n=p[key]; if type(n)~='number' or n%1~=0 or n<1 or n>9007199254740991 then return end
    end
    CreateThread(function()
        local ok,failure=pcall(function()
            local horse=NetworkGetEntityFromNetworkId(p.netId)
            local target=NetworkGetEntityFromNetworkId(p.targetNetId)
            local function valid()
                local player=GetPlayerFromServerId(p.ownerSource)
                return player~=-1 and GetPlayerPed(player)==target and Exists(target) and Exists(horse)
                    and NetworkGetNetworkIdFromEntity(target)==p.targetNetId and NetworkGetNetworkIdFromEntity(horse)==p.netId
                    and GetEntityModel(horse)==GetHashKey(p.modelKey) and Yes(NetworkHasControlOfEntity(horse))
                    and Entity(horse).state.bccStablesGeneration==p.generationId and Entity(horse).state.bccStablesObserver==p.observerId
            end
            if not valid() then return end
            local unoccupied=true
            for _,flag in ipairs({false,true}) do
                local rider=GetRiderOfMount(horse,flag)
                assert(type(rider)=='number' and rider%1==0 and rider>=0,'Unknown care rider observation')
                if rider~=0 then unoccupied=false end
            end
            local led=Citizen.InvokeNative(0xAC5045AB7F1A34FD,horse)
            assert(led==true or led==false or led==0 or led==1,'Unknown care leading observation')
            local report={generationId=p.generationId,sequence=p.sequence,ownerAlive=Alive(target),horseAlive=Alive(horse),
                unoccupied=unoccupied,notLeading=not Yes(led)}
            if not valid() then return end
            Rpc('care_check_result',report)
        end)
        if not ok then print('[bcc-stables] care observation unavailable: '..tostring(failure)) end
    end)
end)
RegisterCommand('BccStablesCareEligibilityProof',function(_,args)
    if #(args or {})~=0 then print('[bcc-stables] BccStablesCareEligibilityProof'); return end
    if busy then print('[bcc-stables] native command busy.'); return end
    busy=true
    CreateThread(function()
        local ok,failure=pcall(function()
            local reply=Rpc('care_eligibility',{})
            local v=reply.value
            if reply.ok and type(v)=='table' and v.eligible==true and v.feedingEnabled==false and v.observationOnly==true then
                print(('[bcc-stables] care eligibility PASS; generationId=%s networkOwner=%s distance=%.2f feedingEnabled=false observationOnly=true')
                    :format(v.generationId,v.networkOwner,v.distance))
            else print('[bcc-stables] care eligibility refused: '..tostring(reply.code or 'invalid_result')) end
        end)
        busy=false
        if not ok then print('[bcc-stables] care eligibility failed: '..tostring(failure)) end
    end)
end,false)
