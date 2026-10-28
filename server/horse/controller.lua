-- One physical-horse owner. Persisted IDs are fences, not entity authority.
Stables.HorseController = {}
local C, F, R = Stables.HorseController, Stables.Feather, Stables.CallRepository
local records, characterBusy, pendingProofs = {}, {}, {}
local running, draining, epoch = false, false, nil
local PROCESS, STOP_PROOFS = 'bcc_stables_process_epoch_v1', 'bcc_stables_stop_proofs_v1'
local MARKER, OBSERVER = 'bccStablesGeneration', 'bccStablesObserver'
local function exists(e) return e and e ~= 0 and (DoesEntityExist(e) == true or DoesEntityExist(e) == 1) end
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<1000000 end
local function ownScript(e)
    local script = GetEntityScript(e)
    return script == nil or script == '' or script == GetCurrentResourceName()
end
local function same(r)
    return not r.identityLost and exists(r.entity) and NetworkGetNetworkIdFromEntity(r.entity)==r.netId
        and GetEntityModel(r.entity)==GetHashKey(r.horse.modelKey) and ownScript(r.entity)
        and Entity(r.entity).state[MARKER]==r.id and Entity(r.entity).state[OBSERVER]==r.observerId
end
local function observation(r, gone)
    return {generationId=r.id, observerId=r.observerId, netId=r.netId,
        initialOwner=r.session.source, bucket=0, modelKey=r.horse.modelKey, disappeared=gone==true}
end
local function finishStopProof(proof)
    local p=proof.observation
    if p.disappeared~=true then
        -- This process-local receipt was captured by the live observer at stop.
        -- Only observe its old handle: never reattach to, or delete, an entity
        -- loaded from this receipt. A reused handle conservatively delays release.
        if proof.deleteRequested~=true or type(proof.entityHandle)~='number'
            or proof.entityHandle<1 or proof.entityHandle%1~=0 or exists(proof.entityHandle) then return false end
        p.disappeared=true
    end
    R.Bind(proof.session,p.generationId,p,true)
    local begun=R.BeginCleanup(proof.session.characterId,p.generationId)
    return begun.ok and R.FinishCleanup(proof.session.characterId,p.generationId,p).ok
end
local function saveStopProofs()
    local journal={processEpoch=epoch,entries={}}
    for _,proof in pairs(pendingProofs) do journal.entries[#journal.entries+1]=proof end
    if epoch and GetConvar(PROCESS,'')==epoch then SetConvar(STOP_PROOFS,json.encode(journal)) end
end
local function cancel(r)
    r.cancelled = true
    if r.care then r.care.cancelled=true end
    if C.CancelMovement then C.CancelMovement(r) end
    TriggerClientEvent('bcc-stables:call:cancel', r.session.source, r.id)
end

function C.MovementRecord(session)
    if not running or draining or GetConvar(PROCESS,'')~=epoch or not F.IsCurrent(session) then return nil end
    local r=records[session.characterId]
    if not r or r.busy or r.cancelled or r.phase~='active' or r.session.source~=session.source
        or r.session.sessionId~=session.sessionId or not same(r)
        or GetPlayerRoutingBucket(session.source)~=0 or GetEntityRoutingBucket(r.entity)~=0 then return nil end
    return r
end

function C.IsDistant(session)
    local r=C.MovementRecord(session)
    local ped=GetPlayerPed(session.source)
    if not r or not exists(ped) then return nil end
    local a,b=GetEntityCoords(r.entity),GetEntityCoords(ped)
    if not a or not b then return nil end
    for _,p in ipairs({a,b}) do
        if not p or not finite(p.x) or not finite(p.y) or not finite(p.z) then return nil end
    end
    return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2>10000
end

function C.HasPhysicalCall(session) return records[session.characterId]~=nil end

-- Ask the current simulator through the existing occupancy protocol. No second
-- horse locator and no assumption that the character owns network control.
function C.CheckCareOccupancy(session,r,allowMounted)
    if C.MovementRecord(session)~=r or r.storeCheck then return false,'care_observation_unknown' end
    local owner=NetworkGetEntityOwner(r.entity)
    local ped=GetPlayerPed(session.source)
    if type(owner)~='number' or owner<1 or GetPlayerRoutingBucket(owner)~=0 or not exists(ped) then return false,'care_observation_unknown' end
    local targetNet=NetworkGetNetworkIdFromEntity(ped)
    if type(targetNet)~='number' or targetNet<1 then return false,'care_observation_unknown' end
    r.storeSequence=(r.storeSequence or 0)+1
    local t={owner=owner,sequence=r.storeSequence,expires=GetGameTimer()+1500,care=true,condition=true}
    r.storeCheck=t
    TriggerClientEvent('bcc-stables:call:store_check',owner,{generationId=r.id,observerId=r.observerId,
        netId=r.netId,modelKey=r.horse.modelKey,sequence=t.sequence,care=true,targetNet=targetNet,condition=true,
        allowMounted=allowMounted~=false})
    while t.reply==nil and GetGameTimer()<t.expires and not r.cancelled do Wait(25) end
    if r.storeCheck==t then r.storeCheck=nil end
    if t.reply==nil or C.MovementRecord(session)~=r or NetworkGetEntityOwner(r.entity)~=owner
        or GetPlayerPed(session.source)~=ped or NetworkGetNetworkIdFromEntity(ped)~=targetNet then return false,'care_observation_unknown' end
    if t.ownerAlive~=true or t.horseAlive~=true then return false,'care_life' end
    if t.reply then return false,'care_occupied' end
    return true,nil,t.cores
end

-- Console status only: observe live records without SQL, control requests or
-- ownership changes. A reused entity must not be reported as our simulator.
function C.Status()
    local calls={}
    for _,r in pairs(records) do
        local present=exists(r.entity)
        local matched=present and same(r) or false
        calls[#calls+1]={ownerSource=r.session.source,characterId=r.session.characterId,
            horseId=r.horse.horseId,generationId=r.id,netId=r.netId,phase=r.phase,
            entityExists=present==true,identityMatches=matched==true,
            networkOwner=matched and NetworkGetEntityOwner(r.entity) or nil,
            movement=r.movement and r.movement.mode or nil}
    end
    table.sort(calls,function(a,b) return a.ownerSource<b.ownerSource end)
    local pending=0
    for _ in pairs(pendingProofs) do pending=pending+1 end
    return {readOnly=true,running=running,draining=draining,pendingCleanup=pending,liveCalls=calls}
end
local function position(source)
    if GetPlayerRoutingBucket(source) ~= 0 then return nil end
    local ped = GetPlayerPed(source)
    if not exists(ped) then return nil end
    local p, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    if not p or not finite(p.x) or not finite(p.y) or not finite(p.z) or not finite(heading) then return nil end
    return {x=p.x+3.0,y=p.y,z=p.z,heading=heading}
end
local function candidate(r, e)
    if not exists(e) or not r.candidates[e] or not ownScript(e) or r.identityLost
        or GetEntityModel(e)~=GetHashKey(r.horse.modelKey) or GetEntityRoutingBucket(e)~=0
        or Entity(e).state[MARKER]~=r.id or Entity(e).state[OBSERVER]~=r.observerId then return false end
    if NetworkGetEntityOwner(e)~=r.session.source and r.candidates[e].owner~=r.session.source then return false end
    local p = GetEntityCoords(e)
    if not p or not finite(p.x) or not finite(p.y) or not finite(p.z) then return false end
    return (p.x-r.position.x)^2+(p.y-r.position.y)^2+(p.z-r.position.z)^2 <= 25
end
local function adopt(r)
    if r.entity then return same(r) end
    local found
    for e in pairs(r.candidates) do
        if candidate(r,e) then
            if found then return false end
            found=e
        end
    end
    if not found then return false end
    local netId=NetworkGetNetworkIdFromEntity(found)
    if type(netId)~='number' or netId<1 then return false end
    r.entity, r.netId = found, netId
    return same(r)
end
local function fence(r, reason)
    cancel(r)
    local result = R.Reconcile(r.session.characterId,r.id,reason)
    if result.ok then
        records[r.session.characterId]=nil
        return F.Error('call_reconciliation_required','Uncertain horse identity remains reserved for recovery.')
    end
    return result
end

local function cleanup(r)
    if r.busy then return F.Error('cleanup_pending','A horse operation is finishing.') end
    r.busy=true
    local called, result = pcall(function()
        cancel(r)
        if not r.entity and not adopt(r) then
            if GetGameTimer()-r.started<30000 then return F.Error('cleanup_pending','Waiting for creation evidence.') end
            return fence(r,'submission_unknown')
        end
        if r.identityLost or (exists(r.entity) and not same(r)) then return fence(r,'identity_lost') end
        local saved = R.Inspect(r.session.characterId,r.id); if not saved.ok then return saved end
        if saved.value.state=='released' then records[r.session.characterId]=nil; return saved end
        if saved.value.state=='submitting' then
            -- This observed entity can bind solely for deletion after logout.
            -- No ready instruction is issued, and care benefits remain fenced.
            local bound = R.Bind(r.session,r.id,observation(r),true); if not bound.ok then return bound end
        end
        local intent = R.BeginCleanup(r.session.characterId,r.id); if not intent.ok then return intent end
        r.phase='cleanup_pending'
        if exists(r.entity) then
            if not same(r) then return fence(r,'identity_lost') end
            DeleteEntity(r.entity)
            if exists(r.entity) then return F.Error('cleanup_pending','Waiting for confirmed disappearance.') end
        end
        local finished = R.FinishCleanup(r.session.characterId,r.id,observation(r,true))
        if finished.ok then records[r.session.characterId]=nil end
        return finished
    end)
    r.busy=false
    if not called then return F.Error('cleanup_pending','Cleanup interrupted; the same call remains reserved.') end
    return result
end

function C.EntityCreated(entity)
    for _,r in pairs(records) do
        -- A new creation reusing an old handle invalidates its live authority.
        if r.entity==entity then r.identityLost=true end
        r.candidates[entity]=nil
        if running and r.phase=='waiting' and r.accepted and r.candidateCount<128 then
            r.candidates[entity]={owner=exists(entity) and NetworkGetEntityOwner(entity) or nil}
            r.candidateCount=r.candidateCount+1
        end
    end
end

function C.Call(source)
    if not running or draining or GetConvar(PROCESS,'')~=epoch then return F.Error('calls_unavailable','Horse calls are unavailable.') end
    if Stables.StableMenu and Stables.StableMenu.IsOpen(source) then return F.Error('stable_open','Close the stable before calling a horse.') end
    local captured = F.RequireSession(source); if not captured.ok then return captured end
    local session = captured.value
    if characterBusy[session.characterId] then return F.Error('busy','A horse request is finishing.') end
    local count=0
    for _ in pairs(records) do count=count+1 end
    for id in pairs(characterBusy) do if not records[id] then count=count+1 end end
    for _ in pairs(pendingProofs) do count=count+1 end
    if count>=64 and not records[session.characterId] then return F.Error('busy','Horse controller capacity reached.') end
    characterBusy[session.characterId]=true
    local called,result = pcall(function()
        local previous=records[session.characterId]
        if previous then
            if previous.cancelled or previous.phase=='cleanup_pending' then
                return F.Error('cleanup_pending','Previous horse cleanup is still completing.')
            end
            if C.IsDistant(session)~=true then return F.Error('horse_busy','The current horse is nearby or not ready for relocation.') end
            local owned=Stables.OwnedRepository.ReadSelected(session); if not owned.ok then return owned end
            if owned.value.horseId~=previous.horse.horseId or owned.value.assetId~=previous.horse.assetId
                or owned.value.modelKey~=previous.horse.modelKey then return F.Error('stale_call','Horse selection or ownership changed.') end
            -- Store uses the current simulator's occupancy guard. Do not bypass
            -- a rider/leader to relocate, and never spawn before exact release.
            local stored=C.Store(source,previous.id)
            if not stored.ok and stored.code~='cleanup_pending' then return stored end
            local deadline=GetGameTimer()+5000
            while records[session.characterId]==previous and GetGameTimer()<deadline do
                local released=cleanup(previous)
                if not released.ok and released.code~='cleanup_pending' then return released end
                if records[session.characterId]==previous then Wait(100) end
            end
            if records[session.characterId] then return F.Error('cleanup_pending','Relocation awaits confirmed disappearance; no replacement requested.') end
        end
        local horse = Stables.OwnedRepository.ReadSelected(session); if not horse.ok then return horse end
        if not horse.value.selected then return F.Error('selection_required','Select an owned horse first.') end
        if previous and (horse.value.horseId~=previous.horse.horseId or horse.value.assetId~=previous.horse.assetId
            or horse.value.modelKey~=previous.horse.modelKey) then return F.Error('stale_call','Horse selection or ownership changed after cleanup.') end
        if not running or draining or GetConvar(PROCESS,'')~=epoch then return F.Error('calls_unavailable','Horse calls are unavailable.') end
        local pos = position(source); if not pos then return F.Error('player_unavailable','Call your horse in the default world.') end
        local ids = DB.one('SELECT UUID() AS generation_id,UUID() AS observer_id')
        if not ids or not F.IsUuid(ids.generation_id) or not F.IsUuid(ids.observer_id) then
            return F.Error('database_unavailable','Horse request identities are unavailable.')
        end
        local r={id=ids.generation_id,observerId=ids.observer_id,session=session,horse=horse.value,
            position=pos,candidates={},candidateCount=0,phase='reserving',started=GetGameTimer(),busy=true}
        records[session.characterId]=r
        local reserved = R.Reserve(session,r.horse,r.id,epoch)
        r.busy=false
        if not reserved.ok then
            records[session.characterId]=nil -- Any uncertain SQL result retains its durable slot.
            return reserved
        end
        if not running or draining or not F.IsCurrent(session) or GetConvar(PROCESS,'')~=epoch then
            return fence(r,'submission_unknown')
        end
        r.position=position(source)
        if not r.position then return fence(r,'submission_unknown') end
        r.phase='waiting'
        TriggerClientEvent('bcc-stables:call:create',source,{generationId=r.id,observerId=r.observerId,
            modelKey=r.horse.modelKey,horseId=r.horse.horseId,gender=r.horse.gender,position=r.position})
        if previous then
            reserved.value.relocated=true
            reserved.value.originalGenerationId=previous.id
        end
        return reserved
    end)
    characterBusy[session.characterId]=nil
    if not called then
        local r=records[session.characterId]
        if r then r.busy=false; cancel(r) end
        return F.Error('call_outcome_unknown','Horse request interrupted; inspect its retained call before retrying.')
    end
    return result
end

function C.Accept(source,p)
    if type(p)~='table' or not F.IsUuid(p.generationId) or not F.IsUuid(p.observerId) then
        return F.Error('invalid_input','Spawn instruction identity required.')
    end
    local session=F.RequireSession(source); if not session.ok then return session end
    local r=records[session.value.characterId]
    if not running or draining or not r or r.cancelled or r.busy or r.phase~='waiting' or r.accepted
        or r.id~=p.generationId or r.observerId~=p.observerId or r.session.source~=source
        or r.session.sessionId~=session.value.sessionId or GetGameTimer()-r.started>=30000
        or GetConvar(PROCESS,'')~=epoch or not position(source) then
        return F.Error('stale_call','Spawn instruction expired or has already been accepted.')
    end
    r.accepted=true
    return F.Ok({generationId=r.id})
end

function C.Bind(source, p)
    if type(p)~='table' or not F.IsUuid(p.generationId) or type(p.netId)~='number'
        or p.netId<1 or p.netId>2147483647 or p.netId%1~=0 then return F.Error('invalid_input','Generation and network identity required.') end
    local captured = F.RequireSession(source); if not captured.ok then return captured end
    local session=captured.value
    local r=records[session.characterId]
    if not running or draining or not r or r.id~=p.generationId or r.session.sessionId~=session.sessionId
        or r.session.source~=source or r.phase~='waiting' or not r.accepted or r.cancelled or r.busy then return F.Error('stale_call','No matching pending horse call.') end
    r.busy=true
    local called,result=pcall(function()
        local deadline=GetGameTimer()+5000
        local entity
        repeat
            entity=NetworkGetEntityFromNetworkId(p.netId)
            if candidate(r,entity) then break end
            if not running or r.cancelled or GetGameTimer()>=deadline then return F.Error('entity_not_observed','Horse creation was not observed.') end
            Wait(25)
        until false
        if NetworkGetEntityOwner(entity)~=source or NetworkGetNetworkIdFromEntity(entity)~=p.netId then
            return F.Error('invalid_observation','Initial horse simulator does not match the caller.')
        end
        r.entity,r.netId=entity,p.netId
        local owned=Stables.OwnedRepository.ReadSelected(session); if not owned.ok then return owned end
        if owned.value.horseId~=r.horse.horseId or owned.value.assetId~=r.horse.assetId
            or owned.value.modelKey~=r.horse.modelKey or owned.value.selectionRevision~=r.horse.selectionRevision
            or not running or draining or r.cancelled or GetConvar(PROCESS,'')~=epoch
            or not position(source) or not same(r) then return F.Error('stale_call','Horse authority changed during binding.') end
        local tack=Stables.Tack and Stables.Tack.Loadout(session,r.horse.horseId) or F.Ok({})
        if not tack.ok then return tack end
        local bound=R.Bind(session,r.id,observation(r)); if not bound.ok then return bound end
        if not running or draining or r.cancelled or not F.IsCurrent(session) or not same(r)
            or not position(source) or GetConvar(PROCESS,'')~=epoch then return F.Error('stale_call','Bound horse requires cleanup.') end
        r.phase='active'
        r.requiredConditionRevision=owned.value.condition and owned.value.condition.revision or 0
        return F.Ok({generationId=r.id,horseId=r.horse.horseId,state='active',netId=r.netId,condition=owned.value.condition,tack=tack.value})
    end)
    r.busy=false
    if not called then result=F.Error('call_outcome_unknown','Binding interrupted; the call remains reserved.') end
    if not result.ok then cancel(r) end
    return result
end

function C.OccupancyResult(source,p)
    if type(p)~='table' or not F.IsUuid(p.generationId) or type(p.sequence)~='number' or p.sequence%1~=0 or p.sequence<1
        or type(p.occupied)~='boolean' then return F.Error('invalid_input','Occupancy ticket required.') end
    for _,r in pairs(records) do
        local ticket=r.storeCheck
        if r.id==p.generationId and ticket and ticket.owner==source and ticket.sequence==p.sequence
            and GetGameTimer()<=ticket.expires and ticket.reply==nil and same(r)
            and NetworkGetEntityOwner(r.entity)==source then
            if ticket.care and (type(p.ownerAlive)~='boolean' or type(p.horseAlive)~='boolean') then
                return F.Error('invalid_input','Care life observation required.')
            end
            if ticket.condition then
                if not F.IsRevision(p.healthCore) or p.healthCore>100 or not F.IsRevision(p.staminaCore)
                    or p.staminaCore>100 or not F.IsRevision(p.appliedRevision) then
                    return F.Error('invalid_input','Current core observation required.')
                end
                ticket.cores={healthCore=p.healthCore,staminaCore=p.staminaCore,appliedRevision=p.appliedRevision,
                    owner=source,observedAt=GetGameTimer()}
            end
            ticket.reply,ticket.ownerAlive,ticket.horseAlive=p.occupied,p.ownerAlive,p.horseAlive
            return F.Ok(true)
        end
    end
    return F.Error('stale_call','Occupancy ticket expired or its simulator changed.')
end

function C.Store(source,relocationGeneration)
    local captured=F.RequireSession(source); if not captured.ok then return captured end
    local session=captured.value
    local r=records[session.characterId]
    if not r then return F.Error('call_not_observed','No live horse observer; saved identities will not be deleted.') end
    if r.care then r.care.cancelled=true; return F.Error('horse_care_busy','Feeding is cancelling; retry after it finishes.') end
    if r.busy or r.session.sessionId~=session.sessionId then return F.Error('busy','A horse operation is finishing.') end
    if r.cancelled then return cleanup(r) end
    if r.phase~='active' or not same(r) then return F.Error('horse_not_ready','Wait for your horse before storing it.') end
    r.busy=true
    local called,result=pcall(function()
        local owner=NetworkGetEntityOwner(r.entity)
        if type(owner)~='number' or owner<1 or GetPlayerRoutingBucket(owner)~=0 then return F.Error('occupancy_unknown','Horse simulator is unavailable.') end
        r.storeSequence=(r.storeSequence or 0)+1
        local ticket={owner=owner,sequence=r.storeSequence,expires=GetGameTimer()+1500,condition=Stables.Feeding~=nil}
        r.storeCheck=ticket
        TriggerClientEvent('bcc-stables:call:store_check',owner,{generationId=r.id,observerId=r.observerId,
            netId=r.netId,modelKey=r.horse.modelKey,sequence=ticket.sequence,condition=ticket.condition})
        while ticket.reply==nil and GetGameTimer()<ticket.expires and not r.cancelled do Wait(25) end
        if not F.IsCurrent(session) or r.cancelled or not same(r) or NetworkGetEntityOwner(r.entity)~=owner
            or GetEntityRoutingBucket(r.entity)~=0 or not position(source) then return F.Error('occupancy_unknown','Horse or session changed during the store check.') end
        if ticket.reply==true then return F.Error('horse_occupied','Dismount before storing this horse.') end
        if ticket.reply~=false then return F.Error('occupancy_unknown','Horse occupancy could not be verified.') end
        if Stables.Feeding then
            local saved=Stables.Feeding.Capture(session,r,ticket.cores,function()
                return F.IsCurrent(session) and not r.cancelled and same(r) and NetworkGetEntityOwner(r.entity)==owner
                    and records[session.characterId]==r and r.phase=='active' and GetPlayerRoutingBucket(source)==0
            end)
            if not saved.ok then return saved end
        end
        return F.Ok(true)
    end)
    r.storeCheck,r.busy=nil,false
    if not called then return F.Error('occupancy_unknown','Horse occupancy could not be verified.') end
    if not result.ok then return result end
    if relocationGeneration and (r.id~=relocationGeneration or C.IsDistant(session)~=true) then
        return F.Error('horse_nearby','Relocation distance changed; the current horse was retained.')
    end
    return cleanup(r)
end

function C.Tick()
    if not running then return end
    if Stables.StableMenu then Stables.StableMenu.Tick() end
    if GetConvar(PROCESS,'')==epoch then
        for id,proof in pairs(pendingProofs) do
            local awaitingEntity=proof.observation.disappeared~=true and exists(proof.entityHandle)
            if not awaitingEntity and (not proof.retryAt or GetGameTimer()>=proof.retryAt) then
                local called,finished=pcall(finishStopProof,proof)
                if called and finished then
                    pendingProofs[id]=nil
                    saveStopProofs()
                else proof.retryAt=GetGameTimer()+5000 end
            end
        end
    end
    for _,r in pairs(records) do
        if not r.busy then
            local called=pcall(function()
                if not F.IsCurrent(r.session) or GetPlayerRoutingBucket(r.session.source)~=0
                    or GetConvar(PROCESS,'')~=epoch or (r.phase=='waiting' and GetGameTimer()-r.started>=30000)
                    or (r.entity and (not exists(r.entity) or not same(r))) then cancel(r) end
                if r.cancelled then cleanup(r) end
                if not r.cancelled and C.MovementTick then C.MovementTick(r) end
            end)
            if not called then cancel(r) end
        end
    end
end

function C.Drain()
    draining=true
    local deadline=GetGameTimer()+20000
    for _,r in pairs(records) do cancel(r) end
    repeat
        C.Tick()
        if next(records)==nil and next(pendingProofs)==nil then return F.Ok({state='drained'}) end
        Wait(50)
    until GetGameTimer()>=deadline
    return F.Error('cleanup_pending','Shutdown cleanup remains unresolved; durable reservations retained.')
end

-- Synchronous stop: no SQL, timers, self-restart or ACE requirements. A process-
-- local proof records only disappearance already confirmed by this live observer.
function C.Stop()
    if not running and draining then return end
    running,draining=false,true
    for _,r in pairs(records) do
        pcall(function()
            cancel(r)
            if not r.entity then adopt(r) end
            if same(r) then
                DeleteEntity(r.entity)
                pendingProofs[r.id]={session=r.session,observation=observation(r,false),
                    entityHandle=r.entity,deleteRequested=true}
            end
            if r.entity and r.netId and not r.identityLost and not exists(r.entity) then
                pendingProofs[r.id]={session=r.session,observation=observation(r,true)}
            end
        end)
    end
    saveStopProofs()
end

function C.Start()
    if running then return F.Ok(true) end
    if draining then return F.Error('restart_required','Restart the resource before accepting new calls.') end
    local current=GetConvar(PROCESS,'')
    if current=='' then
        current=DB.value('SELECT UUID()')
        if not F.IsUuid(current) then return F.Error('process_identity_lost','Server process identity is unavailable.') end
        SetConvar(PROCESS,current)
    end
    if not F.IsUuid(current) then return F.Error('process_identity_lost','Reserved process identity is invalid.') end
    epoch=current
    local proofMap={}
    local encoded=GetConvar(STOP_PROOFS,'')
    local decoded,proofs=pcall(json.decode,encoded)
    if decoded and type(proofs)=='table' and proofs.processEpoch==epoch and type(proofs.entries)=='table' and #proofs.entries<=64 then
        for _,proof in ipairs(proofs.entries) do
            if type(proof)=='table' and type(proof.session)=='table' and F.IsUuid(proof.session.characterId)
                and type(proof.observation)=='table' and F.IsUuid(proof.observation.generationId)
                and (proof.observation.disappeared==true or (proof.deleteRequested==true
                    and type(proof.entityHandle)=='number' and proof.entityHandle>0 and proof.entityHandle%1==0)) then
                proof.retryAt=nil -- Game timer deadlines are not restart evidence.
                proofMap[proof.observation.generationId]=proof
            end
        end
    end
    pendingProofs=proofMap
    -- Complete startup reconciliation before accepting any player dispatch.
    local cursor,seen='',{}
    repeat
        local rows=DB.query([[SELECT character_id,generation_id FROM fs_call_leases
            WHERE state<>'released' AND generation_id>? ORDER BY generation_id LIMIT 64]],cursor)
        if type(rows)~='table' or #rows>64 then return F.Error('recovery_unavailable','Call recovery scan failed.') end
        for _,row in ipairs(rows) do
            if not F.IsUuid(row.character_id) or not F.IsUuid(row.generation_id) or row.generation_id<=cursor then
                return F.Error('recovery_unavailable','Invalid call recovery identity.')
            end
            cursor=row.generation_id
            seen[row.generation_id]=true
            local proof=proofMap[row.generation_id]
            if proof and proof.session.characterId~=row.character_id then
                proof,pendingProofs[row.generation_id]=nil,nil
            end
            local restored=false
            if proof and proof.session.characterId==row.character_id then
                -- A delayed deletion may still be replicating. Retain its
                -- original observer receipt and let Tick confirm disappearance.
                restored=finishStopProof(proof)
                if restored then pendingProofs[row.generation_id]=nil
                else print('[bcc-stables] stop cleanup pending; retaining deletion evidence: '..row.generation_id) end
            end
            -- Do not discard positive disappearance evidence because a SQL
            -- retry failed. A future startup can safely finish the same proof.
            if not restored and not proof then
                local fenced=R.Reconcile(row.character_id,row.generation_id,'restart_lost_observation')
                if fenced.ok then
                    local recovered=R.RecoverProcessEnded(row.character_id,row.generation_id,epoch)
                    if not recovered.ok and recovered.code~='process_still_current' then
                        print('[bcc-stables] call remains reserved: '..row.generation_id..' ['..recovered.code..']')
                    end
                else print('[bcc-stables] call requires reconciliation: '..row.generation_id..' ['..fenced.code..']') end
            end
        end
        if #rows<64 then break end
        Wait(0)
    until false
    -- A lost commit reply can leave a proof for a release that actually saved;
    -- that generation is absent from the unreleased scan on the next startup.
    for id,proof in pairs(pendingProofs) do
        if not seen[id] then
            local saved=R.Inspect(proof.session.characterId,id)
            if saved.ok and saved.value.state=='released' then pendingProofs[id]=nil end
        end
    end
    -- Retain same-process proofs for a retry if startup cleanup failed.
    if GetConvar(PROCESS,'')~=epoch then return F.Error('process_identity_lost','Server process identity changed.') end
    saveStopProofs()
    running,draining=true,false
    return F.Ok(true)
end

-- Called once by the Feather boot path when the native client is also loaded.
-- Reuse the established route names; no diagnostic or self-restart commands.
function C.Install()
    local routes={
        {'request',function(_,source) return C.Call(source) end,true},
        {'accept',function(p,source) return C.Accept(source,p) end},
        {'bind',function(p,source) return C.Bind(source,p) end},
        {'store_current',function(_,source) return C.Store(source) end,true},
        {'store_check_result',function(p,source) return C.OccupancyResult(source,p) end}
    }
    for _,entry in ipairs(routes) do
        local action,handler,empty=entry[1],entry[2],entry[3]
        local result=F.Call('feather-core','RegisterRpc','stables.horses.call.'..action..'.v1',handler,{
            contract=1,direction='client_to_server',requireCharacter=action~='store_check_result',
            windowMs=2000,maxCalls=2,maxPayloadBytes=empty and 16 or 384,maxDepth=2,maxNodes=10,
            validatePayload=function(p)
                if type(p)~='table' then return false end
                if empty then return next(p)==nil end
                if not F.IsUuid(p.generationId) then return false end
                for key in pairs(p) do
                    if key~='generationId' and (action=='bind' and key~='netId' or action=='accept' and key~='observerId'
                        or action=='store_check_result' and key~='sequence' and key~='occupied' and key~='ownerAlive' and key~='horseAlive'
                            and key~='healthCore' and key~='staminaCore' and key~='appliedRevision') then return false end
                end
                if action=='bind' then return type(p.netId)=='number' and p.netId%1==0 and p.netId>0 and p.netId<=2147483647 end
                if action=='accept' then return F.IsUuid(p.observerId) end
                return type(p.sequence)=='number' and p.sequence%1==0 and p.sequence>0 and type(p.occupied)=='boolean'
                    and (p.ownerAlive==nil or type(p.ownerAlive)=='boolean') and (p.horseAlive==nil or type(p.horseAlive)=='boolean')
                    and (p.healthCore==nil or (F.IsRevision(p.healthCore) and p.healthCore<=100))
                    and (p.staminaCore==nil or (F.IsRevision(p.staminaCore) and p.staminaCore<=100))
                    and (p.appliedRevision==nil or F.IsRevision(p.appliedRevision))
            end
        })
        if not result.ok then return result end
    end
    if Stables.Whistle then
        local installed=Stables.Whistle.Install(); if not installed.ok then return installed end
    end
    AddEventHandler('entityCreated',C.EntityCreated)
    AddEventHandler('playerDropped',function()
        for _,r in pairs(records) do if r.session.source==source then cancel(r) end end
    end)
    AddEventHandler('onResourceStop',function(resource)
        if resource==GetCurrentResourceName() or resource=='feather-core'
            or resource=='feather-mysql' or resource=='feather-assets' or resource=='feather-inventory' then C.Stop() end
    end)
    AddEventHandler('txAdmin:events:serverShuttingDown',function() draining=true; for _,r in pairs(records) do cancel(r) end end)
    exports('PrepareShutdown',C.Drain)
    local started=C.Start(); if not started.ok then return started end
    CreateThread(function()
        while running do
            Wait(500)
            C.Tick()
        end
    end)
    return started
end
