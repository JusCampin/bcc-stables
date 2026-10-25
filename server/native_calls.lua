-- Gated native bridge. Durable slots own admission; this map holds live
-- creation evidence only and never reconstructs entity authority from net IDs.
Stables.NativeCalls={}
local N,S=Stables.NativeCalls,Stables
local records,enabled,running,draining={},false,false,false
local behaviorEnabled=false
local FollowHandoff
local MARKER='bccStablesGeneration'
local OBSERVER='bccStablesObserver'
local function Timing(pattern,...)
    local args=table.pack(...)
    -- Diagnostics cannot change a committed result or trigger entity cleanup.
    pcall(function() print('[bcc-stables:timing] '..pattern:format(table.unpack(args,1,args.n))) end)
end

-- Runtime-only, non-replicated convar: survives this resource's restart and is
-- intentionally never written to configuration/KVP. Reserve it for Stables.
local PROCESS_KEY='bcc_stables_process_epoch_v1'
local processEpoch,epochBusy,epochFailed=nil,false,false
function N.ProcessEpoch()
    if epochFailed then return S.Err('process_identity_lost','Process identity changed; dispatch remains fenced.') end
    if epochBusy then return S.Err('busy','Process identity initialization is in progress.') end
    epochBusy=true
    local called,result=pcall(function()
        local current=GetConvar(PROCESS_KEY,'')
        if processEpoch then
            if current~=processEpoch then epochFailed=true; return S.Err('process_identity_lost','Process identity changed.') end
            return S.Ok({processEpoch=processEpoch})
        end
        if current=='' then
            local proposed=DB.value('SELECT UUID()')
            if not S.Operations.IsUuid(proposed) then return S.Err('invalid_contract','Process UUID required.') end
            -- Another initialization may have completed during the SQL yield.
            current=GetConvar(PROCESS_KEY,'')
            if current=='' then SetConvar(PROCESS_KEY,proposed:lower()); current=GetConvar(PROCESS_KEY,'') end
        end
        if not S.Operations.IsUuid(current) or current~=current:lower() then
            epochFailed=true; return S.Err('invalid_process_epoch','Reserved process convar is invalid.')
        end
        processEpoch=current
        return S.Ok({processEpoch=processEpoch})
    end)
    epochBusy=false
    if not called then return S.Persistence.DatabaseError(result) end
    return result
end

local function Exists(e) local v=e and e~=0 and DoesEntityExist(e); return v==true or v==1 end
local function Finite(v) return type(v)=='number' and v==v and math.abs(v)<1000000 end
local function Script(e)
    local name=GetEntityScript(e)
    return name==nil or name=='' or name==GetCurrentResourceName()
end
local function Same(r)
    return not r.identityLost and Exists(r.entity) and NetworkGetNetworkIdFromEntity(r.entity)==r.netId
        and GetEntityModel(r.entity)==GetHashKey(r.modelKey) and Script(r.entity)
        and Entity(r.entity).state[MARKER]==r.id and Entity(r.entity).state[OBSERVER]==r.observerId
end
local function Identity(r)
    return {generationId=r.id,observerId=r.observerId,netId=r.netId,
        initialOwner=r.context.source,bucket=0,modelKey=r.modelKey}
end
local function Cancel(r)
    r.cancelled=true
    if r.whistle then
        TriggerClientEvent('bcc-stables:call:whistle_cancel',r.whistle.owner,{generationId=r.id,observerId=r.observerId,sequence=r.whistle.sequence})
        r.whistle=nil
    end
    TriggerClientEvent('bcc-stables:call:cancel',r.context.source,r.id)
end
local function Reconcile(r,reason)
    local result=S.CallLifecycleRepository.Reconcile(r.context.characterId,r.id,reason)
    if result.ok then records[r.id]=nil end
    return result
end
local function Payload(p,bind)
    if type(p)~='table' or not S.Operations.IsUuid(p.generationId) then return false end
    for k in pairs(p) do if k~='generationId' and (not bind or k~='netId') then return false end end
    return not bind or (type(p.netId)=='number' and p.netId%1==0 and p.netId>0 and p.netId<=2147483647)
end
local function Check(source,context)
    return S.Foundation.CheckSession(source,context)
end
local function Distant(r,source)
    local ped=GetPlayerPed(source)
    if not Exists(ped) then return S.Err('player_unavailable','Current player required.') end
    local a,b=GetEntityCoords(ped),GetEntityCoords(r.entity)
    if not a or not b or not Finite(a.x) or not Finite(a.y) or not Finite(a.z)
        or not Finite(b.x) or not Finite(b.y) or not Finite(b.z) then return S.Err('invalid_position','Finite server positions required.') end
    return S.Ok((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2>10000)
end

local function AutomaticRelocation(id,source,context)
    local reply=N.RelocateProof({generationId=id},source,context)
    if reply.ok then reply.value.relocation=true end
    return reply
end

local function Position(source)
    if GetPlayerRoutingBucket(source)~=0 then return S.Err('foreign_route','Calling requires the default world.') end
    local ped=GetPlayerPed(source)
    if not Exists(ped) then return S.Err('player_unavailable','Player ped is unavailable.') end
    local p,h=GetEntityCoords(ped),GetEntityHeading(ped)
    if not p or not Finite(p.x) or not Finite(p.y) or not Finite(p.z) or not Finite(h) then
        return S.Err('invalid_position','Finite server coordinates required.')
    end
    return S.Ok({x=p.x+3.0,y=p.y,z=p.z,heading=h})
end
local function Candidate(r,e)
    if not Exists(e) or not r.candidates[e] or not Script(e)
        or GetEntityModel(e)~=GetHashKey(r.modelKey)
        or Entity(e).state[MARKER]~=r.id or Entity(e).state[OBSERVER]~=r.observerId
        or GetEntityRoutingBucket(e)~=0 then return false end
    local owner=NetworkGetEntityOwner(e)
    if owner~=r.context.source and r.candidates[e].owner~=r.context.source then return false end
    local p=GetEntityCoords(e)
    if not p or not Finite(p.x) or not Finite(p.y) or not Finite(p.z) then return false end
    local dx,dy,dz=p.x-r.position.x,p.y-r.position.y,p.z-r.position.z
    return dx*dx+dy*dy+dz*dz<=25.0
end
local function Cleanup(r)
    if r.busy then return S.Err('cleanup_pending','Binding or dispatch is finishing.') end
    Cancel(r)
    local saved=S.CallRepository.Get(r.context.characterId,r.id); if not saved.ok then return saved end
    if saved.value.state=='released' then records[r.id]=nil; return S.Ok({state='released',generationId=r.id}) end
    if not r.entity then
        local candidates={}
        for e in pairs(r.candidates) do if Candidate(r,e) then candidates[#candidates+1]=e end end
        if #candidates==1 then
            r.entity,r.netId=candidates[1],NetworkGetNetworkIdFromEntity(candidates[1])
        else
            -- Cancellation does not prove that an in-flight CreatePed never ran.
            if GetGameTimer()-r.started<30000 then return S.Err('cleanup_pending','Waiting for in-flight creation evidence.') end
            return Reconcile(r,'submission_unknown')
        end
    end
    if r.identityLost or (Exists(r.entity) and not Same(r)) then return Reconcile(r,'identity_lost') end
    if saved.value.state=='submitting' then
        if not Same(r) then return Reconcile(r,'submission_unknown') end
        -- Recover only this live observer's exact candidate, solely for deletion.
        local bound=S.CallLifecycleRepository.Bind(r.context,r.id,Identity(r))
        if not bound.ok then return bound end
    end
    local intent=S.CallLifecycleRepository.BeginCleanup(r.context.characterId,r.id)
    if not intent.ok then return intent end
    r.phase='cleanup_pending'
    if Exists(r.entity) then
        if not Same(r) then return Reconcile(r,'identity_lost') end
        DeleteEntity(r.entity)
        if Exists(r.entity) then return S.Err('cleanup_pending','Deletion requested; awaiting disappearance.') end
    end
    local released=S.CallLifecycleRepository.FinishCleanup(r.context.characterId,r.id,
        {generationId=r.id,observerId=r.observerId,netId=r.netId,disappeared=true})
    if released.ok then records[r.id]=nil end
    return released
end
local function Dispatch(p,source,context,handoff)
    local dispatchStarted=GetGameTimer()
    if not Payload(p,false) then return S.Err('invalid_input','Only generationId is accepted.') end
    local checked=Check(source,context); if not checked.ok then return checked end
    if not enabled or not running then return S.Err('native_calls_disabled','Native calls are disabled.') end
    if draining then return S.Err('native_calls_draining','Native dispatch is drained until resource restart.') end
    if GetResourceState('feather-toolkit')~='started' then return S.Err('dependency_unavailable','Toolkit is required for horse models.') end
    context=S.Copy(context); context.characterId=context.characterId:lower(); local id=p.generationId:lower()
    -- Resolve character-scoped durable ownership before consulting shared live
    -- observer state. A foreign caller must not learn whether this ID is active.
    local readStarted=GetGameTimer()
    local saved
    if handoff then
        local lease=type(handoff)=='table' and handoff.lease
        -- claim is a local Lua capability, never a cross-resource function ref.
        if type(lease)~='table' or type(handoff.claim)~='function' or lease.generationId~=id
            or lease.characterId~=context.characterId or lease.sessionId~=context.sessionId or lease.source~=source
            or not S.Operations.IsUuid(handoff.observerId) then return S.Err('call_not_found','Invalid prepared handoff.') end
        saved=S.Ok(lease)
    else
        saved=S.CallRepository.Get(context.characterId,id)
    end
    if not saved.ok then return saved end
    local timing={scopedReadMs=GetGameTimer()-readStarted,claimStages={}}
    checked=Check(source,context); if not checked.ok then return checked end
    if draining then return S.Err('native_calls_draining','Native dispatch is drained until resource restart.') end
    if records[id] then return S.Err('submission_conflict','Generation already has a live observer.') end
    local count=0; for _ in pairs(records) do count=count+1 end
    if count>=64 then return S.Err('busy','Native observer capacity reached.') end
    local position=Position(source); if not position.ok then return position end
    if draining then return S.Err('native_calls_draining','Native dispatch is drained until resource restart.') end
    local r={id=id,context=context,position=position.value,candidates={},candidateCount=0,
        started=GetGameTimer(),busy=true,phase='authorizing',nativeBehavior=behaviorEnabled}
    records[id]=r
    local ok,result=pcall(function()
        local uuidStarted=GetGameTimer()
        local observer
        if handoff then observer=handoff.observerId else observer=DB.value('SELECT UUID()') end
        timing.observerUuidMs=GetGameTimer()-uuidStarted
        if not S.Operations.IsUuid(observer) then return S.Err('invalid_contract','Observer UUID required.') end
        r.observerId=observer:lower()
        if draining or r.cancelled or not running then return S.Err('native_calls_draining','Dispatch cancelled before submission.') end
        local epochStarted=GetGameTimer()
        local epoch=N.ProcessEpoch(); if not epoch.ok then return epoch end
        timing.processEpochMs=GetGameTimer()-epochStarted
        if draining or r.cancelled or not running then return S.Err('native_calls_draining','Dispatch cancelled before submission.') end
        local claimStarted=GetGameTimer()
        local claimed
        if handoff then claimed=handoff.claim(id,source,context,timing.claimStages,epoch.value.processEpoch)
        else claimed=S.Calls.ClaimObservedSubmission({generationId=id},source,context,saved.value,timing.claimStages) end
        timing.claimMs=GetGameTimer()-claimStarted
        if not claimed.ok then return claimed end
        local receiptStarted=GetGameTimer()
        local recorded
        if handoff then
            -- This internal claim committed its process receipt atomically.
            recorded=claimed.value.processEpoch==epoch.value.processEpoch and S.Ok(true)
                or S.Err('invalid_process_evidence','Atomic claim receipt is missing.')
        else
            recorded=S.CallLifecycleRepository.RecordProcessEpoch(context,id,epoch.value.processEpoch)
        end
        timing.processReceiptMs=GetGameTimer()-receiptStarted
        if not recorded.ok then return recorded end
        local unchanged=N.ProcessEpoch(); if not unchanged.ok then return unchanged end
        r.modelKey=claimed.value.modelKey
        local now=Position(source); if not now.ok then return now end
        checked=Check(source,context); if not checked.ok then return checked end
        if r.cancelled or not running or draining then return S.Err('session_stale','Dispatch was cancelled.') end
        r.position,r.phase=now.value,'waiting'
        -- Exactly one durable claim precedes this instruction. Never replay it.
        TriggerClientEvent('bcc-stables:call:create',source,{generationId=id,observerId=r.observerId,
            modelKey=r.modelKey,position=S.Copy(r.position)})
        return S.Ok({generationId=id,state='submitting',entitySpawning=true,gameplayAvailable=false})
    end)
    r.busy=false
    if not ok then result=S.Persistence.DatabaseError(result) end
    if not result.ok then
        Cancel(r)
        if r.phase=='authorizing' then
            local current=S.CallRepository.Get(context.characterId,id)
            if current.ok and current.value.state=='submitting' then Reconcile(r,'submission_unknown') end
            records[id]=nil -- A durable unresolved slot still prevents another dispatch.
        end
    end
    if result.ok then
        Timing('dispatch generationId=%s scopedReadMs=%d observerUuidMs=%d processEpochMs=%d claimMs=%d processReceiptMs=%d totalMs=%d',
            id,timing.scopedReadMs,timing.observerUuidMs,timing.processEpochMs,timing.claimMs,
            timing.processReceiptMs,GetGameTimer()-dispatchStarted)
        Timing('claim generationId=%s selectionMs=%d transactionMs=%d recheckMs=%d',
            id,timing.claimStages.selectionMs,timing.claimStages.transactionMs,timing.claimStages.recheckMs)
    end
    return result
end
function N.Dispatch(p,source,context) return Dispatch(p,source,context) end
-- Internal prepared path only; not registered as an RPC/export.
function N.DispatchPrepared(handoff,source,context)
    if type(handoff)~='table' or type(handoff.lease)~='table' then return S.Err('invalid_input','Prepared handoff required.') end
    return Dispatch({generationId=handoff.lease.generationId},source,context,handoff)
end
function N.Bind(p,source,context)
    if not Payload(p,true) then return S.Err('invalid_input','Exact generationId/netId required.') end
    local bindStarted=GetGameTimer()
    local checked=Check(source,context); if not checked.ok then return checked end
    local r=records[p.generationId:lower()]
    if not r or r.context.source~=source or r.context.sessionId~=context.sessionId
        or r.context.characterId~=context.characterId:lower() then return S.Err('stale_call','No current native observer.') end
    if r.busy or r.phase~='waiting' or r.cancelled then return S.Err('binding_conflict','Binding is not available.') end
    r.busy=true
    local timing={started=bindStarted,gatesMs=GetGameTimer()-bindStarted}
    local ok,result=pcall(function()
        local started=GetGameTimer(); local e
        repeat
            e=NetworkGetEntityFromNetworkId(p.netId)
            if Candidate(r,e) then break end
            if r.cancelled or not running or GetGameTimer()-started>=5000 then return S.Err('entity_not_observed','New horse identity did not replicate.') end
            Wait(25)
        until false
        timing.observationMs=GetGameTimer()-started
        timing.validationStarted=GetGameTimer()
        if NetworkGetEntityOwner(e)~=source or NetworkGetNetworkIdFromEntity(e)~=p.netId then
            return S.Err('invalid_entity','Initial network identity/owner mismatch.')
        end
        checked=Check(source,context); if not checked.ok then return checked end
        local pos=Position(source); if not pos.ok then return pos end
        local lease=S.CallRepository.Get(context.characterId,r.id); if not lease.ok then return lease end
        local owned=S.OwnedHorses.GetKnown(lease.value.horseId,lease.value.operationId,source,context)
        if not owned.ok then return owned end
        checked=Check(source,context); if not checked.ok then return checked end
        if r.cancelled or not running or not Candidate(r,e) or GetPlayerRoutingBucket(source)~=0 then
            return S.Err('stale_call','Session, route or entity changed during binding.')
        end
        r.entity,r.netId,r.horseId=e,p.netId,lease.value.horseId
        Entity(e).state:set(MARKER,r.id,true); Entity(e).state:set(OBSERVER,r.observerId,true)
        timing.validationMs=GetGameTimer()-timing.validationStarted
        local commitStarted=GetGameTimer()
        local bound=S.CallLifecycleRepository.Bind(r.context,r.id,Identity(r))
        timing.commitMs=GetGameTimer()-commitStarted
        if not bound.ok then return bound end
        local recheckStarted=GetGameTimer()
        owned=S.OwnedHorses.GetKnown(lease.value.horseId,lease.value.operationId,source,context)
        if not owned.ok then return owned end
        checked=Check(source,context)
        if not checked.ok or r.cancelled or GetPlayerRoutingBucket(source)~=0 or not Same(r) then
            return S.Err('stale_call','Bound generation requires cleanup.')
        end
        timing.recheckMs=GetGameTimer()-recheckStarted
        r.phase,r.lastOwnerCheck='active',GetGameTimer()
        return S.Ok({generationId=r.id,state='active',netId=r.netId,nativeBehavior=r.nativeBehavior==true,gameplayAvailable=false})
    end)
    r.busy=false
    if not ok then result=S.Persistence.DatabaseError(result) end
    if not result.ok then Cancel(r)
    else
        Timing('bind generationId=%s gatesMs=%d observationMs=%d validationMs=%d commitMs=%d recheckMs=%d totalMs=%d',
            r.id,timing.gatesMs,timing.observationMs,timing.validationMs,timing.commitMs,timing.recheckMs,GetGameTimer()-timing.started)
    end
    return result
end
function N.StoreCheckPayload(p)
    if type(p)~='table' or not S.Operations.IsUuid(p.generationId) or type(p.sequence)~='number'
        or p.sequence%1~=0 or p.sequence<1 or type(p.occupied)~='boolean' then return false end
    for k in pairs(p) do if k~='generationId' and k~='sequence' and k~='occupied' then return false end end
    return true
end

function N.StoreCheckResult(p,source)
    if not N.StoreCheckPayload(p) then return S.Err('invalid_input','Exact store occupancy result required.') end
    local r=records[p.generationId]; local ticket=r and r.storeCheck
    if not r or not ticket or ticket.sequence~=p.sequence or ticket.owner~=source or ticket.reply~=nil
        or GetGameTimer()>ticket.expires or r.cancelled or not running
        or r.phase~='active' or not Same(r) or NetworkGetEntityOwner(r.entity)~=source
        or GetEntityRoutingBucket(r.entity)~=0 or GetPlayerRoutingBucket(source)~=0 then
        return S.Err('stale_store_check','Store occupancy check is no longer current.')
    end
    ticket.reply=p.occupied
    return S.Ok({recorded=true})
end

local function StoreOccupancy(r,source,context)
    if r.busy then return S.Err('busy','Horse is busy.') end
    r.busy=true
    local ok,result=pcall(function()
        if not Same(r) or GetEntityRoutingBucket(r.entity)~=0 then return S.Err('occupancy_unknown','Horse identity is unavailable.') end
        local owner=NetworkGetEntityOwner(r.entity)
        if type(owner)~='number' or owner<1 or GetPlayerRoutingBucket(owner)~=0 then return S.Err('occupancy_unknown','Current simulator is unavailable.') end
        r.storeSequence=(r.storeSequence or 0)+1
        local ticket={sequence=r.storeSequence,owner=owner,expires=GetGameTimer()+1500}
        r.storeCheck=ticket
        TriggerClientEvent('bcc-stables:call:store_check',owner,{generationId=r.id,observerId=r.observerId,
            netId=r.netId,modelKey=r.modelKey,sequence=ticket.sequence})
        while ticket.reply==nil and GetGameTimer()<ticket.expires and not r.cancelled do Wait(25) end
        local checked=Check(source,context); if not checked.ok then return checked end
        if r.cancelled or r.phase~='active' or not running or draining or records[r.id]~=r
            or not Same(r) or GetEntityRoutingBucket(r.entity)~=0 or NetworkGetEntityOwner(r.entity)~=owner
            or GetPlayerRoutingBucket(owner)~=0 or not S.Core.IsSessionCurrent(r.context) then
            return S.Err('occupancy_unknown','Observer/session/control changed during the store check.')
        end
        if ticket.reply==true then return S.Err('horse_occupied','Dismount before storing this horse.') end
        if ticket.reply~=false then return S.Err('occupancy_unknown','No current simulator occupancy result; horse retained.') end
        return S.Ok(true)
    end)
    r.storeCheck=nil; r.busy=false
    return ok and result or S.Err('occupancy_unknown','Store occupancy check failed; horse retained.')
end

function N.Store(p,source,context)
    if not Payload(p,false) then return S.Err('invalid_input','Only generationId is accepted.') end
    local checked=Check(source,context); if not checked.ok then return checked end
    local saved=S.CallRepository.Get(context.characterId:lower(),p.generationId:lower()); if not saved.ok then return saved end
    if saved.value.state=='released' then return S.Ok({generationId=saved.value.generationId,state='released',gameplayAvailable=false}) end
    local r=records[p.generationId:lower()]
    if not r or r.context.characterId~=context.characterId:lower() then
        return S.Err('call_reconciliation_required','Live observer is absent; no entity will be deleted from a saved net ID.')
    end
    if r.phase=='active' and not r.cancelled and Same(r) then
        local occupied=StoreOccupancy(r,source,context); if not occupied.ok then return occupied end
    end
    Cancel(r)
    local result=Cleanup(r)
    if result.ok and result.value.state~='released' then
        return S.Err('call_reconciliation_required','Cleanup is unresolved; the durable slot remains fenced.')
    end
    if result.ok then return S.Ok({generationId=r.id,state='released',gameplayAvailable=false}) end
    return result
end
function N.Created(e)
    for _,r in pairs(records) do
        if r.entity==e then r.identityLost=true end
        if r.phase=='waiting' and r.candidateCount<128 and not r.candidates[e] then
            r.candidates[e]={owner=Exists(e) and NetworkGetEntityOwner(e) or nil}
            r.candidateCount=r.candidateCount+1
        end
    end
end
function N.SessionEvent(stage,p)
    if stage=='ready' or type(p)~='table' then return end
    for _,r in pairs(records) do
        if (p.source==nil or p.source==r.context.source) and p.sessionId==r.context.sessionId then Cancel(r) end
    end
end
function N.Tick()
    for _,r in pairs(records) do
        local ok=pcall(function()
        if not r.busy then
            if not S.Core.IsSessionCurrent(r.context) or GetPlayerRoutingBucket(r.context.source)~=0
                or (r.phase=='waiting' and GetGameTimer()-r.started>30000)
                or (r.phase=='active' and (not Same(r) or GetEntityRoutingBucket(r.entity)~=0)) then Cancel(r) end
            if r.phase=='active' and not r.cancelled and GetGameTimer()-(r.lastOwnerCheck or 0)>=5000 then
                r.lastOwnerCheck=GetGameTimer()
                local lease=S.CallRepository.Get(r.context.characterId,r.id)
                local owned=lease.ok and S.OwnedHorses.GetKnown(lease.value.horseId,lease.value.operationId,r.context.source,r.context)
                if not owned or not owned.ok then Cancel(r) end
            end
            if not r.cancelled and r.phase=='active' and FollowHandoff then FollowHandoff(r) end
            if r.cancelled then Cleanup(r) end
        end
        end)
        if not ok then
            pcall(Cancel,r)
            pcall(Reconcile,r,'identity_lost')
            print('[bcc-stables] native observer failed; unresolved identity remains fenced.')
        end
    end
end
function N.Stop()
    running=false
    -- Stop callbacks cannot wait for SQL/replication. Keep the durable slot;
    -- next boot fences lost observation even if best-effort deletion succeeds.
    for _,r in pairs(records) do
        local ok=pcall(function()
            Cancel(r)
            if not r.entity then
                local matches={}
                for e in pairs(r.candidates) do if Candidate(r,e) then matches[#matches+1]=e end end
                if #matches==1 then r.entity,r.netId=matches[1],NetworkGetNetworkIdFromEntity(matches[1]) end
            end
            if Same(r) then DeleteEntity(r.entity) end
        end)
        if not ok then print('[bcc-stables] native stop could not confirm cleanup; durable slot retained.') end
    end
end
function N.Start()
    if type(StablesConfig.nativeCalls)~='boolean' then return S.Err('config_error','nativeCalls must be boolean.') end
    if StablesConfig.nativeCalls and StablesConfig.callPreparation~=true then
        return S.Err('config_error','nativeCalls requires callPreparation=true.')
    end
    if StablesConfig.nativeBehavior~=nil and type(StablesConfig.nativeBehavior)~='boolean' then
        return S.Err('config_error','nativeBehavior must be boolean when supplied.')
    end
    if StablesConfig.nativeBehavior==true and not StablesConfig.nativeCalls then
        return S.Err('config_error','nativeBehavior requires nativeCalls=true.')
    end
    enabled,running,draining=StablesConfig.nativeCalls,true,false
    behaviorEnabled=StablesConfig.nativeBehavior==true
    return S.Ok({ok=true,enabled=enabled,entitySpawning=enabled,storeAvailable=enabled,
        nativeBehaviorEnabled=behaviorEnabled,gameplayAvailable=false})
end
-- Console-only read probe. Fixed sample counts, no arbitrary SQL or mutations.
local probeBusy=false
local function Samples(values)
    local sorted={table.unpack(values)}; table.sort(sorted)
    return {samplesMs=values,minMs=sorted[1],medianMs=sorted[2],maxMs=sorted[3]}
end
function N.LatencyProbe(assetId)
    if not S.Operations.IsUuid(assetId) then return S.Err('invalid_input','Horse asset UUID required.') end
    local ready=S.Foundation.RequireReady(); if not ready.ok then return ready end
    if probeBusy then return S.Err('busy','A latency probe is already running.') end
    probeBusy=true; assetId=assetId:lower()
    local ok,result=pcall(function()
        local bridge,direct,transaction,assets={},{},{},{}
        -- ReadyV1 returns cached driver state through the same callback bridge;
        -- unlike SELECT 1, this path does not acquire a connection or issue SQL.
        for index=1,3 do
            local began=GetGameTimer()
            local ready=DB.isReady()
            bridge[index]=GetGameTimer()-began
            if ready~=true then return S.Err('dependency_unavailable','Database readiness bridge probe failed.') end
        end
        for index=1,3 do
            local began=GetGameTimer()
            local value=DB.value('SELECT 1')
            direct[index]=GetGameTimer()-began
            if tonumber(value)~=1 then return S.Err('invalid_contract','Database probe result must be one.') end
        end
        local transactionStarted=GetGameTimer()
        local entered,leaving,valid
        local committed=DB.transaction(function(tx)
            entered=GetGameTimer(); valid=true
            for index=1,3 do
                local began=GetGameTimer()
                local value=tx.value('SELECT 1')
                transaction[index]=GetGameTimer()-began
                if tonumber(value)~=1 then valid=false; return false end
            end
            leaving=GetGameTimer()
            return true
        end)
        local transactionFinished=GetGameTimer()
        if not valid then return S.Err('invalid_contract','Transaction probe result must be one.') end
        if committed~=true then return S.Err('transaction_rolled_back','Read-only probe transaction did not complete.') end
        local batchStarted=GetGameTimer()
        local batchEntered,batchLeaving,batchCallMs,batchValid
        local batchCommitted=DB.transaction(function(tx)
            batchEntered=GetGameTimer()
            local began=GetGameTimer()
            local values=tx.batch({DB.stmt('SELECT 1 AS probe_value'),DB.stmt('SELECT 1 AS probe_value'),DB.stmt('SELECT 1 AS probe_value')})
            batchCallMs=GetGameTimer()-began
            batchValid=type(values)=='table' and #values==3
            if batchValid then for index=1,3 do
                local rows=values[index]
                if type(rows)~='table' or #rows~=1 or tonumber(rows[1].probe_value)~=1 then batchValid=false; break end
            end end
            batchLeaving=GetGameTimer()
            return batchValid
        end)
        local batchFinished=GetGameTimer()
        if not batchValid then return S.Err('invalid_contract','Batch probe result must be three rows of one.') end
        if batchCommitted~=true then return S.Err('transaction_rolled_back','Batch probe transaction did not complete.') end
        for index=1,3 do
            local began=GetGameTimer()
            local read=S.Assets.ReadHorse(assetId)
            assets[index]=GetGameTimer()-began
            if not read.ok then return read end
            if type(read.value)~='table' or read.value.assetId~=assetId or read.value.assetType~='horse' then
                return S.Err('invalid_contract','Assets probe must return the requested horse.')
            end
        end
        local tx=Samples(transaction)
        tx.beginMs,tx.finishMs,tx.totalMs=entered-transactionStarted,transactionFinished-leaving,
            transactionFinished-transactionStarted
        return S.Ok({readOnly=true,sampleCount=3,assetId=assetId,bridge=Samples(bridge),database=Samples(direct),
            transaction=tx,batchedTransaction={statementCount=3,batchCallMs=batchCallMs,
                beginMs=batchEntered-batchStarted,finishMs=batchFinished-batchLeaving,totalMs=batchFinished-batchStarted},
            assets=Samples(assets)})
    end)
    probeBusy=false
    return ok and result or S.Persistence.DatabaseError(result)
end
function N.Install()
    for _,entry in ipairs({{'dispatch',N.Dispatch},{'bind',N.Bind},{'store',N.Store},
        {'request',N.Request,true},{'store_current',N.StoreCurrent,true},{'movement_proof',N.MovementProof,true},
        {'whistle',N.Whistle,false},{'whistle_claim',N.WhistleClaim,false},{'whistle_done',N.WhistleDone,false},{'store_check_result',N.StoreCheckResult,false},{'relocate_proof',N.RelocateProof,false}}) do
        local action,empty=entry[1],entry[3]
        local registered=S.Core.Call('RegisterRpc','stables.horses.call.'..action..'.v1',entry[2],{
            contract=1,direction='client_to_server',requireCharacter=action~='store_check_result',windowMs=2000,maxCalls=2,
            maxPayloadBytes=empty and 16 or 192,maxDepth=empty and 1 or 2,maxNodes=empty and 2 or 6,
            validatePayload=function(p)
                if empty then return type(p)=='table' and next(p)==nil end
                if action=='store_check_result' then return N.StoreCheckPayload(p) end
                if action=='whistle' then return N.WhistleInput(p) end
                if action=='whistle_claim' or action=='whistle_done' then return N.WhistlePayload(p) end
                return Payload(p,action=='bind')
            end})
        if not registered.ok then return registered end
    end
    RegisterCommand('BccStablesNative',function(source,args)
        if source~=0 then return end
        CreateThread(function()
            local ok,result=pcall(function()
                if args[1]=='latency_probe' then
                    if #args~=2 then return S.Err('invalid_input','BccStablesNative latency_probe <horseAssetId>') end
                    return N.LatencyProbe(args[2])
                end
                if args[1]=='process_status' then
                    if #args~=1 then return S.Err('invalid_input','BccStablesNative process_status') end
                    local ready=S.Foundation.RequireReady(); if not ready.ok then return ready end
                    return N.ProcessEpoch()
                end
                if args[1]=='recovery_resolve' then
                    if #args~=3 then return S.Err('invalid_input','BccStablesNative recovery_resolve <characterId> <generationId>') end
                    return N.RecoveryResolve(args[2],args[3])
                end
                if args[1]=='recovery_list' then
                    if #args>2 then return S.Err('invalid_input','BccStablesNative recovery_list [afterGenerationId]') end
                    return N.RecoveryList(args[2])
                end
                if args[1]=='recovery_inspect' then
                    if #args~=3 then return S.Err('invalid_input','BccStablesNative recovery_inspect <characterId> <generationId>') end
                    return N.RecoveryInspect(args[2],args[3])
                end
                if args[1]=='drain' then
                    if #args~=1 then return S.Err('invalid_input','BccStablesNative drain') end
                    return N.Drain()
                end
                if args[1]=='route_test' then return N.RouteTest(tonumber(args[2]),args[3]) end
                if args[1]=='route_return' then return N.RouteReturn() end
                local playerId=tonumber(args[2])
                if args[1]~='inspect' or not playerId or playerId%1~=0 or playerId<1 then
                    return S.Err('invalid_input','BccStablesNative inspect <serverPlayerId>')
                end
                local session=S.Core.RequireSession(playerId); if not session.ok then return session end
                local saved=S.CallRepository.Get(session.value.characterId); if not saved.ok then return saved end
                local v=S.Copy(saved.value); local r=v.generationId and records[v.generationId]
                v.serverPlayerId,v.characterId=playerId,session.value.characterId
                v.liveObserver=r~=nil; v.exists=r and Same(r) or false
                v.netId=r and r.netId or nil
                v.networkOwner=r and Same(r) and NetworkGetEntityOwner(r.entity) or nil
                local ticket=r and r.whistle
                if ticket then
                    local now=GetGameTimer()
                    local expired=(ticket.followUntil and now>=ticket.followUntil) or (not ticket.claimed and now>ticket.expires)
                    v.movementTicket={sequence=ticket.sequence,mode=ticket.mode,simulator=ticket.owner,
                        state=ticket.completed and 'ended' or expired and 'expired' or ticket.claimed and 'claimed' or 'pending',
                        normalFollow=ticket.normalFollow==true,
                        claimRemainingMs=math.max(0,ticket.expires-now),
                        followRemainingMs=ticket.followUntil and math.max(0,ticket.followUntil-now) or nil}
                end
                return S.Ok(v)
            end)
            print('[bcc-stables:native] '..json.encode(ok and result or S.Err('native_error','Native inspection failed.')))
        end)
    end,true)
    AddEventHandler('entityCreated',N.Created)
    AddEventHandler('playerDropped',function()
        for _,r in pairs(records) do if r.context.source==source then Cancel(r) end end
    end)
    return S.Ok({routes=11})
end
function N.Run()
    CreateThread(function()
        -- No world scan: prior live evidence has been lost, so retain/fence
        -- every unresolved submitted slot via bounded keyset pages.
        local cursor=''
        while running do
            local ok,rows=pcall(DB.query,[[SELECT generation_id,character_id FROM fs_call_leases
                WHERE state IN ('submitting','active','cleanup_pending') AND generation_id>?
                ORDER BY generation_id LIMIT 64]],cursor)
            if not ok or type(rows)~='table' then print('[bcc-stables] native recovery scan failed; submitted slots remain fenced.'); break end
            if #rows>64 then print('[bcc-stables] invalid native recovery page; slots retained.'); break end
            local invalid=false
            for _,row in ipairs(rows) do
                if type(row)~='table' or not S.Operations.IsUuid(row.generation_id)
                    or not S.Operations.IsUuid(row.character_id) or row.generation_id<=cursor then
                    invalid=true; print('[bcc-stables] invalid native recovery identity/order; slots retained.'); break
                end
                cursor=row.generation_id
                if not records[row.generation_id] then
                    local fenced=S.CallLifecycleRepository.Reconcile(row.character_id,row.generation_id,'restart_lost_observation')
                    if not fenced.ok then print('[bcc-stables] native recovery retained unresolved generation '..tostring(row.generation_id)..': '..tostring(fenced.code)) end
                end
            end
            if invalid or #rows<64 then break end
            Wait(0)
        end
        while running do
            Wait(500)
            local ok=pcall(N.Tick)
            if not ok then print('[bcc-stables] native observer tick failed; durable slots retained.') end
        end
    end)
end


-- Console-only acceptance fixture. Feather Routing owns allocation, membership
-- and restore; never mutate a raw bucket or delete an arbitrary supplied handle.
local routeRunning,pendingRoute=false,nil
local function Routing(method,...)
    if GetResourceState('feather-routing')~='started' then
        return S.Err('dependency_unavailable','Start feather-routing before the route test.')
    end
    local args=table.pack(...)
    local ok,result=pcall(function()
        local provider=exports['feather-routing']
        return provider[method](provider,table.unpack(args,1,args.n))
    end)
    if not ok or not S.IsResult(result) then return S.Err('dependency_error','Routing operation failed.',{operation=method}) end
    return result
end
local function RestoreRoute()
    if not pendingRoute then return S.Ok({cleared=false}) end
    local pending=pendingRoute
    if not pending.id then
        -- Recover a lost CreateRoute response using only our saved idempotent key.
        local recovered=Routing('CreateRoute',{key=pending.key,mode='strict',populationEnabled=false})
        if not recovered.ok then return recovered end
        pending.id=type(recovered.value)=='table' and recovered.value.routeId or nil
        if type(pending.id)~='string' or pending.id=='' then return S.Err('invalid_contract','Routing returned no owned handle.') end
    end
    local deleted=Routing('DeleteRoute',pending.id)
    if not deleted.ok then
        if deleted.code=='not_found' then
            local membership=Routing('GetPlayerRoute',pending.source)
            if membership.ok and membership.value==nil and GetPlayerRoutingBucket(pending.source)==0 then
                pendingRoute=nil; return S.Ok({cleared=true,alreadyDeleted=true})
            end
        end
        return deleted
    end
    pendingRoute=nil
    return S.Ok({cleared=true})
end
function N.RouteReturn()
    if routeRunning then return S.Err('busy','A route test is running.') end
    return RestoreRoute()
end
local function RunRouteTest(target,id)
    if type(target)~='number' or target%1~=0 or target<1 or not S.Operations.IsUuid(id) then
        return S.Err('invalid_input','BccStablesNative route_test <serverPlayerId> <generationId>')
    end
    local session=S.Core.RequireSession(target); if not session.ok then return session end
    local context=S.Copy(session.value); context.characterId=context.characterId:lower(); id=id:lower()
    local checked=Check(target,context); if not checked.ok then return checked end
    local before=S.CallRepository.Get(context.characterId,id); if not before.ok then return before end
    local r=records[id]
    if before.value.state~='active' or not r or r.busy or r.cancelled or r.context.source~=target
        or r.context.sessionId~=context.sessionId or not Same(r) then
        return S.Err('active_call_required','A current active owned horse with a live observer is required.')
    end
    if GetPlayerRoutingBucket(target)~=0 then return S.Err('foreign_route','Player must start in the default world.') end
    local caps=Routing('GetCapabilities'); if not caps.ok then return caps end
    local v=caps.value
    if type(v)~='table' or v.contract~=1 or v.state~='ready' or type(v.features)~='table'
        or v.features.routes~=1 or v.features.ownership~=1 or v.features.cleanup~=1 or v.features.opaqueHandles~=1 then
        return S.Err('invalid_contract','Routing Contract 1 with owned opaque routes is required.')
    end
    local membership=Routing('GetPlayerRoute',target); if not membership.ok then return membership end
    if membership.value~=nil then return S.Err('foreign_route','Existing route membership cannot be displaced.') end
    checked=Check(target,context); if not checked.ok then return checked end
    if r.cancelled or not Same(r) then return S.Err('active_call_required','Active identity changed before route allocation.') end
    pendingRoute={key='stables.native-route:'..id,source=target}
    local created=Routing('CreateRoute',{key=pendingRoute.key,mode='strict',populationEnabled=false})
    if not created.ok then return created end
    pendingRoute.id=type(created.value)=='table' and created.value.routeId or nil
    if type(pendingRoute.id)~='string' or pendingRoute.id=='' then
        return S.Err('invalid_contract','Routing returned no owned handle.')
    end
    checked=Check(target,context); if not checked.ok then return checked end
    if r.cancelled or not Same(r) or GetPlayerRoutingBucket(target)~=0 then return S.Err('stale_call','Call or route changed before joining.') end
    local joined=Routing('JoinRoute',pendingRoute.id,target); if not joined.ok then return joined end
    if GetPlayerRoutingBucket(target)==0 then return S.Err('route_not_observed','Private route was not observed.') end
    local started,last=GetGameTimer(),nil
    repeat
        if not S.Core.IsSessionCurrent(context) then return S.Err('session_stale','Session changed during the route test.') end
        local saved=S.CallRepository.Get(context.characterId,id)
        if saved.ok and saved.value.state=='released' and saved.value.revision==4 then
            return S.Ok({serverPlayerId=target,generationId=id,nativeJoined=true,generationCleared=true,
                entityGone=not Exists(r.entity),_session=S.Copy(context)})
        end
        last=saved.code or (saved.ok and saved.value.state)
        if GetGameTimer()-started>=8000 then return S.Err('route_cleanup_pending',
            'Route restored after timeout; inspect generation before proceeding.',{lastObservation=last}) end
        Wait(100) -- Normal native observer performs cleanup; the fixture never calls Store/Tick.
    until false
end
function N.RouteTest(target,id)
    if routeRunning or pendingRoute then return S.Err('busy','A route test or owned-route cleanup is pending.') end
    routeRunning=true
    local called,result=pcall(RunRouteTest,target,id)
    local restoreCalled,restored=pcall(RestoreRoute)
    routeRunning=false
    if not restoreCalled then restored=S.Err('dependency_error','Owned route cleanup raised an exception.') end
    if not restored.ok then return S.Err('route_cleanup_failed','Run BccStablesNative route_return to retry owned-route cleanup.',
        {cause=restored.code,cleanupPending=pendingRoute~=nil}) end
    if not called then return S.Err('proof_failed','Route test raised an exception; owned route cleanup was attempted.') end
    if not result.ok then return result end
    local originalSession=result.value._session; result.value._session=nil
    result.value.sessionCurrent=S.Core.IsSessionCurrent(originalSession)
    if not result.value.sessionCurrent then return S.Err('session_stale','Session changed during route restoration.') end
    result.value.returnedToDefault=GetPlayerRoutingBucket(target)==0
    if not result.value.returnedToDefault or not result.value.entityGone then
        return S.Err('proof_failed','Require default-world restore and confirmed horse disappearance.',result.value)
    end
    return result
end


-- Controlled pre-restart shutdown. Keep observers ticking and Store available,
-- but reject all new dispatches until the resource is restarted.
local drainRunning=false
function N.Drain()
    if drainRunning then return S.Err('busy','A native drain is already running.') end
    if routeRunning or pendingRoute then return S.Err('route_cleanup_pending','Finish the owned route test/return before draining.') end
    local ready=S.Foundation.RequireReady(); if not ready.ok then return ready end
    draining,drainRunning=true,true
    local called,result=pcall(function()
        local started=GetGameTimer()
        repeat
            for _,r in pairs(records) do
                local ok=pcall(function() Cancel(r); if not r.busy then Cleanup(r) end end)
                if not ok then print('[bcc-stables] native drain retained an unresolved live observer.') end
            end
            local live=0; for _ in pairs(records) do live=live+1 end
            local unresolved=tonumber(DB.value("SELECT COUNT(*) FROM fs_call_leases WHERE state NOT IN ('prepared','released')"))
            local bindings=tonumber(DB.value("SELECT COUNT(*) FROM fs_call_bindings WHERE state<>'cleared'"))
            if not unresolved or unresolved%1~=0 or unresolved<0 or unresolved>9007199254740991
                or not bindings or bindings%1~=0 or bindings<0 or bindings>9007199254740991 then
                return S.Err('invalid_contract','Drain requires valid durable blocker counts.')
            end
            if live==0 and unresolved==0 and bindings==0 then
                return S.Ok({state='drained',dispatchBlocked=true,liveObservers=0,
                    unresolvedGenerations=0,unclearedBindings=0})
            end
            if GetGameTimer()-started>=8000 then
                return S.Err('drain_pending','Dispatch remains blocked; resolve/inspect blockers before restart.',
                    {liveObservers=live,unresolvedGenerations=unresolved,unclearedBindings=bindings})
            end
            Wait(100)
        until false
    end)
    drainRunning=false
    if not called then return S.Persistence.DatabaseError(result) end
    return result
end

-- Offline durable diagnosis only. Never resolve an entity from a saved ID.
function N.RecoveryInspect(characterId,generationId)
    if not S.Operations.IsUuid(characterId) or not S.Operations.IsUuid(generationId) then
        return S.Err('invalid_input','Character and generation UUIDs are required.')
    end
    local ready=S.Foundation.RequireReady(); if not ready.ok then return ready end
    local called,result=pcall(function()
        local saved=S.CallRepository.Get(characterId,generationId)
        if not saved.ok then return saved end
        local v=saved.value
        local binding=S.CallLifecycleRepository.ValidateState(DB,v)
        if not binding.ok then return binding end
        local epoch=S.CallLifecycleRepository.ProcessEvidence(DB,v); if not epoch.ok then return epoch end
        local recovery=binding.value.recovery; binding.value.recovery=nil
        return S.Ok({characterId=characterId,generationId=generationId,horseId=v.horseId,
            state=v.state,revision=v.revision,originalServerPlayerId=v.source,
            liveObserver=records[generationId]~=nil,
            reconciliationRequired=v.state=='reconciliation_required',inspectionOnly=true,
            binding=S.Copy(binding.value),processEvidence=S.Copy(epoch.value),recovery=S.Copy(recovery)})
    end)
    if not called then return S.Persistence.DatabaseError(result) end
    return result
end

-- Fixed-size keyset pages. Include every unresolved submitted state, including
-- malformed state values, so corrupt durable blockers cannot vanish from view.
function N.RecoveryList(cursor)
    if cursor~=nil and not S.Operations.IsUuid(cursor) then
        return S.Err('invalid_input','Optional cursor must be a generation UUID.')
    end
    local ready=S.Foundation.RequireReady(); if not ready.ok then return ready end
    local called,result=pcall(function()
        local after=cursor and cursor:lower() or ''
        local rows=DB.query([[SELECT generation_id,character_id FROM fs_call_leases
            WHERE state NOT IN ('prepared','released') AND generation_id>?
            ORDER BY generation_id LIMIT 11]],after)
        if type(rows)~='table' or #rows>11 then
            return S.Err('invalid_contract','Invalid recovery queue page; no blockers changed.')
        end
        local previous=after
        for _,row in ipairs(rows) do
            if type(row)~='table' or not S.Operations.IsUuid(row.generation_id)
                or not S.Operations.IsUuid(row.character_id) or row.generation_id<=previous then
                return S.Err('invalid_contract','Invalid recovery queue identity/order; no blockers changed.')
            end
            previous=row.generation_id
        end
        local entries={}
        for index=1,math.min(#rows,10) do
            local row=rows[index]
            local inspected=N.RecoveryInspect(row.character_id,row.generation_id)
            if inspected.ok then
                entries[#entries+1]=inspected.value
            else
                -- Preserve a discoverable ID even when its receipt is corrupt
                -- or changes while this read-only diagnostic page is assembled.
                entries[#entries+1]={characterId=row.character_id,generationId=row.generation_id,
                    inspectionError=inspected.code,inspectionOnly=true}
            end
        end
        return S.Ok({entries=entries,nextCursor=#rows>10 and rows[10].generation_id or nil,
            pageSize=10,inspectionOnly=true,dispatchBlocked=draining})
    end)
    if not called then return S.Persistence.DatabaseError(result) end
    return result
end


-- Explicit operator recovery only; never accepts an epoch from command input,
-- resolves an entity handle, or sends a client create/delete instruction.
function N.RecoveryResolve(characterId,generationId)
    if not S.Operations.IsUuid(characterId) or not S.Operations.IsUuid(generationId) then
        return S.Err('invalid_input','Character and generation UUIDs are required.')
    end
    characterId,generationId=characterId:lower(),generationId:lower()
    local ready=S.Foundation.RequireReady(); if not ready.ok then return ready end
    -- Scope the receipt before consulting shared observer state.
    local saved=S.CallRepository.Get(characterId,generationId); if not saved.ok then return saved end
    if records[generationId] then return S.Err('live_observer_present','Use normal cleanup while a live observer exists.') end
    local epoch=N.ProcessEpoch(); if not epoch.ok then return epoch end
    if records[generationId] then return S.Err('live_observer_present','Live observer appeared during recovery.') end
    return S.CallLifecycleRepository.ResolveProcessEnded(characterId,generationId,epoch.value.processEpoch)
end


-- Player controls consume only the server's current owned selection/call slot.
-- A successful RPC never replaces the single authoritative create instruction.
local function RequestSelected(p,source,context,expected)
    if type(p)~='table' or next(p)~=nil then return S.Err('invalid_input','Call request accepts no fields.') end
    local started=GetGameTimer()
    local checked=Check(source,context); if not checked.ok then return checked end
    if not enabled or not running then return S.Err('native_calls_disabled','Native calls are disabled.') end
    if draining then return S.Err('native_calls_draining','Native dispatch is drained until resource restart.') end
    if GetResourceState('feather-toolkit')~='started' then return S.Err('dependency_unavailable','Toolkit is required for horse models.') end
    local position=Position(source); if not position.ok then return position end
    context=S.Copy(context)
    -- All potentially yielding native prerequisites precede the fresh owned
    -- preparation snapshot. DispatchPrepared then consumes it without DB reads.
    local allocated,observer=pcall(DB.value,'SELECT UUID()')
    if not allocated then return S.Persistence.DatabaseError(observer) end
    if not S.Operations.IsUuid(observer) then return S.Err('invalid_contract','Observer UUID required.') end
    local epoch=N.ProcessEpoch(); if not epoch.ok then return epoch end
    checked=Check(source,context); if not checked.ok then return checked end
    if draining then return S.Err('native_calls_draining','Native dispatch is drained until resource restart.') end
    local preparationStarted=GetGameTimer()
    local preparationStages={}
    local prepared=S.Calls.PlanForDispatch(source,context,preparationStages,expected)
    if not prepared.ok then return prepared end
    local preparedAt=GetGameTimer()
    prepared.value.observerId=observer:lower()
    local dispatched=N.DispatchPrepared(prepared.value,source,context)
    if dispatched.ok then
        local finished=GetGameTimer()
        Timing('request generationId=%s preflightMs=%d selectionMs=%d preparationMs=%d dispatchMs=%d totalMs=%d',
            prepared.value.lease.generationId,preparationStarted-started,0,preparedAt-preparationStarted,finished-preparedAt,finished-started)
        Timing('preparation generationId=%s generationUuidMs=%d selectionMs=%d transactionMs=%d recheckMs=%d existingLeaseMs=%d',
            prepared.value.lease.generationId,preparationStages.generationUuidMs or 0,preparationStages.selectionMs or 0,
            preparationStages.transactionMs or 0,preparationStages.recheckMs or 0,preparationStages.existingLeaseMs or 0)
    end
    return dispatched
end
function N.Request(p,source,context)
    local result=RequestSelected(p,source,context)
    -- The ordinary empty-slot call keeps its accepted transport budget. Only
    -- an existing-call refusal performs the additional distance lookup.
    if result.ok or result.code~='call_cleanup_required' then return result end
    local checked=Check(source,context); if not checked.ok then return checked end
    local saved=S.CallRepository.Get(context.characterId:lower()); if not saved.ok then return saved end
    local v=saved.value; local r=v.generationId and records[v.generationId]
    if v.state~='active' or not r or r.cancelled or r.phase~='active' or not Same(r)
        or r.context.source~=source or r.context.sessionId~=context.sessionId then return result end
    local far=Distant(r,source); if not far.ok then return far end
    if not far.value then
        -- Reuse the existing fresh authorization/ticket path. An RPC success
        -- requests approach only; it never creates another physical horse.
        local approached=N.Whistle({mode='approach'},source,context)
        if approached.ok and not approached.value.relocation then
            approached.value.state='approach_requested'
            approached.value.entitySpawning=false
        end
        return approached
    end
    return AutomaticRelocation(r.id,source,context)
end

function N.StoreCurrent(p,source,context)
    if type(p)~='table' or next(p)~=nil then return S.Err('invalid_input','Current store accepts no fields.') end
    local checked=Check(source,context); if not checked.ok then return checked end
    context=S.Copy(context)
    local saved=S.CallRepository.Get(context.characterId:lower()); if not saved.ok then return saved end
    checked=Check(source,context); if not checked.ok then return checked end
    if saved.value.state=='empty' then return S.Ok({state='empty',gameplayAvailable=false}) end
    local id=saved.value.generationId
    if saved.value.state=='prepared' then return S.Calls.Abort({generationId=id},source,context) end
    return N.Store({generationId=id},source,context)
end

-- Controlled feasibility aid only. No persistent gameplay/progression authority.
function N.MovementProof(p,source,context)
    if type(p)~='table' or next(p)~=nil then return S.Err('invalid_input','Movement proof accepts no fields.') end
    local checked=Check(source,context); if not checked.ok then return checked end
    if not enabled or not running then return S.Err('native_calls_disabled','Native calls are disabled.') end
    if draining then return S.Err('native_calls_draining','Native dispatch is draining.') end
    local saved=S.CallRepository.Get(context.characterId:lower()); if not saved.ok then return saved end
    local v=saved.value
    local r=v.generationId and records[v.generationId]
    if v.state~='active' or not r or r.context.source~=source or r.context.sessionId~=context.sessionId
        or r.context.characterId~=context.characterId:lower() then return S.Err('stale_call','Current owned active observer required.') end
    if r.busy or r.cancelled or r.phase~='active' then return S.Err('binding_conflict','Movement proof is unavailable.') end
    r.busy=true
    local ok,result=pcall(function()
        local owned=S.OwnedHorses.GetKnown(v.horseId,v.operationId,source,context); if not owned.ok then return owned end
        checked=Check(source,context); if not checked.ok then return checked end
        if r.cancelled or not running or draining or r.phase~='active' or not Same(r)
            or GetEntityRoutingBucket(r.entity)~=0 then return S.Err('stale_call','Observed identity changed.') end
        if NetworkGetEntityOwner(r.entity)~=source then return S.Err('control_required','Current owner must control the horse for this proof.') end
        local ped=GetPlayerPed(source); if not Exists(ped) then return S.Err('player_unavailable','Current player ped required.') end
        local a,b=GetEntityCoords(ped),GetEntityCoords(r.entity)
        if not a or not b or not Finite(a.x) or not Finite(a.y) or not Finite(a.z)
            or not Finite(b.x) or not Finite(b.y) or not Finite(b.z)
            or (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2>64 then return S.Err('too_far','Stand within eight meters of the horse.') end

        local ticket=r.whistle
        local movementIdle=not ticket or ticket.completed or GetGameTimer()>(ticket.followUntil
            or (ticket.mode=='approach' and ticket.expires+20000) or ticket.expires)
        r.movementProof=true -- Diagnostic only; never used to grant gameplay authority.
        return S.Ok({generationId=r.id,observerId=r.observerId,netId=r.netId,modelKey=r.modelKey,
            state='active',movementProof=true,movementIdle=movementIdle==true,nativeBehavior=r.nativeBehavior==true,gameplayAvailable=false})
    end)
    r.busy=false
    return ok and result or S.Persistence.DatabaseError(result)
end

-- Internal read-only care observation. No caller-provided entity identity is
-- trusted; fresh canonical ownership precedes the runtime-only snapshot.
local function CareView(r,source,context)
    if not r or r.context.source~=source or r.context.sessionId~=context.sessionId
        or r.context.characterId~=context.characterId:lower() or r.busy or r.cancelled
        or not running or not enabled or draining or r.phase~='active' or not Same(r)
        or not S.Core.IsSessionCurrent(r.context) or GetPlayerRoutingBucket(source)~=0 or GetEntityRoutingBucket(r.entity)~=0 then
        return S.Err('care_target_unavailable','Current owned active observer required.')
    end
    local owner=NetworkGetEntityOwner(r.entity)
    local ped=GetPlayerPed(source)
    local simulatorPed=type(owner)=='number' and owner%1==0 and owner>0 and GetPlayerPed(owner)
    if not simulatorPed or not Exists(simulatorPed) or not Exists(ped) or GetPlayerRoutingBucket(owner)~=0 then
        return S.Err('care_simulator_unavailable','Current simulator and owner ped required.')
    end
    local targetNet,simulatorNet=NetworkGetNetworkIdFromEntity(ped),NetworkGetNetworkIdFromEntity(simulatorPed)
    if type(targetNet)~='number' or targetNet%1~=0 or targetNet<1 or type(simulatorNet)~='number' or simulatorNet%1~=0 or simulatorNet<1 then
        return S.Err('care_target_unavailable','Network player identities required.')
    end
    local a,b=GetEntityCoords(ped),GetEntityCoords(r.entity)
    if not a or not b or not Finite(a.x) or not Finite(a.y) or not Finite(a.z)
        or not Finite(b.x) or not Finite(b.y) or not Finite(b.z) then return S.Err('care_target_unavailable','Finite server positions required.') end
    local ticket=r.whistle
    local movementIdle=not ticket or ticket.completed or GetGameTimer()>(ticket.followUntil
        or (ticket.mode=='approach' and ticket.expires+20000) or ticket.expires)
    return S.Ok({generationId=r.id,observerId=r.observerId,horseId=r.horseId,netId=r.netId,modelKey=r.modelKey,
        ownerSource=source,targetNetId=targetNet,simulatorPed=simulatorPed,simulatorNetId=simulatorNet,networkOwner=owner,
        movementSequence=ticket and ticket.sequence or 0,movementIdle=movementIdle==true,
        distance=math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)})
end
function N.CareObserver(source,context)
    local checked=Check(source,context); if not checked.ok then return checked end
    local saved=S.CallRepository.Get(context.characterId:lower()); if not saved.ok then return saved end
    local v=saved.value; local r=v.generationId and records[v.generationId]
    if v.state~='active' or not r then return S.Err('care_target_unavailable','Active call required.') end
    local owned=S.OwnedHorses.GetKnown(v.horseId,v.operationId,source,context); if not owned.ok then return owned end
    checked=Check(source,context); if not checked.ok then return checked end
    return CareView(r,source,context)
end
function N.RecheckCareObserver(snapshot,source,context)
    local checked=Check(source,context); if not checked.ok then return checked end
    local current=CareView(records[snapshot.generationId],source,context); if not current.ok then return current end
    for _,key in ipairs({'generationId','observerId','horseId','netId','modelKey','ownerSource','targetNetId','simulatorPed','simulatorNetId','networkOwner','movementSequence'}) do
        if current.value[key]~=snapshot[key] then return S.Err('care_observation_stale','Care observer/simulator identity changed.') end
    end
    return current
end


function N.WhistleInput(p)
    if type(p)~='table' then return false end
    for k in pairs(p) do if k~='mode' then return false end end
    return p.mode==nil or p.mode=='approach' or p.mode=='follow' or p.mode=='stop' or p.mode=='toggle_follow'
end

function N.WhistlePayload(p)
    if type(p)~='table' or not S.Operations.IsUuid(p.generationId)
        or type(p.sequence)~='number' or p.sequence%1~=0 or p.sequence<1 or p.sequence>2147483647 then return false end
    for k in pairs(p) do if k~='generationId' and k~='sequence' then return false end end
    return true
end

local function WhistleLive(r)
    return running and enabled and not draining and not r.cancelled and r.phase=='active'
        and S.Core.IsSessionCurrent(r.context) and GetPlayerRoutingBucket(r.context.source)==0
        and Same(r) and GetEntityRoutingBucket(r.entity)==0
end

-- Observe control changes and renew normal Follow using the existing tick, without SQL.
-- Every replacement still redeems a fresh canonical claim on the new simulator.
FollowHandoff=function(r)
    local ticket=r.whistle; local now=GetGameTimer()
    if not ticket or ticket.mode~='follow' or ticket.completed or not ticket.followUntil
        or now>=ticket.followUntil or not WhistleLive(r) then return end
    local owner=NetworkGetEntityOwner(r.entity)
    local renew=ticket.normalFollow==true and ticket.claimed and ticket.followUntil-now<=5000
    if (owner==ticket.owner and not renew) or type(owner)~='number' or owner<1 or GetPlayerRoutingBucket(owner)~=0
        or now-(r.lastFollowHandoff or -1000)<500 then return end
    if GetPlayerPed(r.context.source)~=ticket.target or not Exists(ticket.target)
        or NetworkGetNetworkIdFromEntity(ticket.target)~=ticket.targetNet then return end
    local far=Distant(r,r.context.source); if not far.ok or far.value then return end
    TriggerClientEvent('bcc-stables:call:whistle_cancel',ticket.owner,
        {generationId=r.id,observerId=r.observerId,sequence=ticket.sequence})
    r.whistleSequence=(r.whistleSequence or 0)+1
    r.lastFollowHandoff=now
    local deadline=renew and now+30000 or ticket.followUntil
    r.whistle={sequence=r.whistleSequence,mode='follow',owner=owner,target=ticket.target,targetNet=ticket.targetNet,
        expires=math.min(now+5000,deadline),followUntil=deadline,normalFollow=ticket.normalFollow==true}

    TriggerClientEvent('bcc-stables:call:whistle',owner,{generationId=r.id,sequence=r.whistleSequence})
end

-- Only the character owner can request movement. The simulator may only redeem
-- a short-lived server ticket for that exact live observer and target ped.
function N.Whistle(p,source,context)
    if not N.WhistleInput(p) then return S.Err('invalid_input','Whistle accepts only approach, follow, stop or toggle_follow mode.') end
    local mode=p.mode or 'approach'
    local checked=Check(source,context); if not checked.ok then return checked end
    local saved=S.CallRepository.Get(context.characterId:lower()); if not saved.ok then return saved end
    local v=saved.value; local r=v.generationId and records[v.generationId]
    if v.state~='active' or not r or r.context.source~=source or r.context.sessionId~=context.sessionId
        or r.context.characterId~=context.characterId:lower() or not WhistleLive(r) then return S.Err('stale_call','Current owned observer required.') end
    if r.busy then return S.Err('busy','Horse is busy.') end
    if mode=='toggle_follow' then
        local ticket=r.whistle
        local following=ticket and not ticket.completed and ticket.mode=='follow' and
            ((ticket.claimed and ticket.followUntil and GetGameTimer()<ticket.followUntil)
                or (not ticket.claimed and GetGameTimer()<=ticket.expires))
        mode=following and 'stop' or 'follow'
    end
    if mode~='stop' and GetGameTimer()-(r.lastWhistle or -2000)<1500 then return S.Err('rate_limited','Whistle cooldown.') end
    if mode=='approach' then
        local far=Distant(r,source); if not far.ok then return far end
        if far.value then return AutomaticRelocation(r.id,source,context) end
    end
    r.busy=true
    local ok,result=pcall(function()
        local owned=S.OwnedHorses.GetKnown(v.horseId,v.operationId,source,context); if not owned.ok then return owned end
        checked=Check(source,context); if not checked.ok then return checked end
        if not WhistleLive(r) then return S.Err('stale_call','Observer changed.') end
        if mode=='stop' then
            local old=r.whistle
            if not old then return S.Ok({generationId=r.id,mode='stop',state='stopped',relayed=true,gameplayAvailable=false}) end
            local owner=NetworkGetEntityOwner(r.entity)
            local ped=GetPlayerPed(source)
            if type(owner)~='number' or owner<1 or GetPlayerRoutingBucket(owner)~=0 or not Exists(ped) then
                return S.Err('control_unavailable','No eligible current simulator/target.')
            end
            local targetNet=NetworkGetNetworkIdFromEntity(ped)
            if type(targetNet)~='number' or targetNet<1 then return S.Err('player_unavailable','Network player ped required.') end
            TriggerClientEvent('bcc-stables:call:whistle_cancel',old.owner,{generationId=r.id,observerId=r.observerId,sequence=old.sequence})
            r.whistleSequence=(r.whistleSequence or 0)+1
            r.whistle={sequence=r.whistleSequence,mode='stop',owner=owner,target=ped,targetNet=targetNet,expires=GetGameTimer()+5000}
            TriggerClientEvent('bcc-stables:call:whistle',owner,{generationId=r.id,sequence=r.whistleSequence})
            return S.Ok({generationId=r.id,mode='stop',state='stop_requested',networkOwner=owner,relayed=true,gameplayAvailable=false})
        end
        local ped=GetPlayerPed(source); if not Exists(ped) then return S.Err('player_unavailable','Current player required.') end
        local a,b=GetEntityCoords(ped),GetEntityCoords(r.entity)
        if not a or not b or not Finite(a.x) or not Finite(a.y) or not Finite(a.z)
            or not Finite(b.x) or not Finite(b.y) or not Finite(b.z)
            or (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2>10000 then return S.Err('too_far','Whistle relay is limited to 100 meters; relocation is not implemented.') end
        local owner=NetworkGetEntityOwner(r.entity)
        if type(owner)~='number' or owner<1 or GetPlayerRoutingBucket(owner)~=0 then return S.Err('control_unavailable','No eligible network owner.') end
        local targetNet=NetworkGetNetworkIdFromEntity(ped)
        if type(targetNet)~='number' or targetNet<1 then return S.Err('player_unavailable','Network player ped required.') end
        if r.whistle then TriggerClientEvent('bcc-stables:call:whistle_cancel',r.whistle.owner,{generationId=r.id,observerId=r.observerId,sequence=r.whistle.sequence}) end
        r.whistleSequence=(r.whistleSequence or 0)+1
        r.lastWhistle=GetGameTimer()
        r.whistle={sequence=r.whistleSequence,mode=mode,owner=owner,target=ped,targetNet=targetNet,expires=GetGameTimer()+5000,
            normalFollow=mode=='follow' and p.mode=='toggle_follow' and r.nativeBehavior==true}
        TriggerClientEvent('bcc-stables:call:whistle',owner,{generationId=r.id,sequence=r.whistleSequence})
        return S.Ok({generationId=r.id,mode=mode,networkOwner=owner,relayed=true,gameplayAvailable=false})
    end)
    r.busy=false
    return ok and result or S.Persistence.DatabaseError(result)
end

function N.WhistleClaim(p,source,context)
    if not N.WhistlePayload(p) then return S.Err('invalid_input','Exact whistle ticket required.') end
    local checked=Check(source,context); if not checked.ok then return checked end
    local r=records[p.generationId]; local ticket=r and r.whistle
    if not r or not ticket or ticket.claimed or ticket.sequence~=p.sequence or ticket.owner~=source
        or GetGameTimer()>ticket.expires or not WhistleLive(r) then return S.Err('stale_whistle','Whistle ticket is unavailable.') end
    if r.busy then return S.Err('busy','Horse is busy.') end
    r.busy=true
    local ok,result=pcall(function()
        local saved=S.CallRepository.Get(r.context.characterId,r.id); if not saved.ok then return saved end
        if saved.value.state~='active' then return S.Err('stale_whistle','Call is no longer active.') end
        local owned=S.OwnedHorses.GetKnown(saved.value.horseId,saved.value.operationId,r.context.source,r.context)
        if not owned.ok then return owned end
        checked=Check(source,context); if not checked.ok then return checked end
        if r.whistle~=ticket or not WhistleLive(r) or GetGameTimer()>ticket.expires
            or NetworkGetEntityOwner(r.entity)~=source or GetPlayerPed(r.context.source)~=ticket.target
            or NetworkGetNetworkIdFromEntity(ticket.target)~=ticket.targetNet then return S.Err('stale_whistle','Task identity/control changed.') end
        ticket.claimed=true
        if ticket.mode=='follow' then
            ticket.followUntil=ticket.followUntil or (GetGameTimer()+30000)
            ticket.claimSessionId=context.sessionId
            ticket.claimCharacterId=context.characterId
        end
        return S.Ok({generationId=r.id,observerId=r.observerId,sequence=ticket.sequence,netId=r.netId,
            modelKey=r.modelKey,mode=ticket.mode,targetNetId=ticket.targetNet,ownerSource=r.context.source,normalFollow=ticket.normalFollow==true,
            followMs=ticket.mode=='follow' and math.max(1,ticket.followUntil-GetGameTimer()) or nil})
    end)
    r.busy=false
    return ok and result or S.Persistence.DatabaseError(result)
end


-- Completion can only revoke this simulator's claimed follow intent. It grants
-- no task/entity authority and performs no persistence or canonical reads.
-- Accept the original simulator after control migrates: a late report still
-- cannot revoke a newer ticket, even when that ticket uses the same generation.
function N.WhistleDone(p,source,context)
    if not N.WhistlePayload(p) then return S.Err('invalid_input','Exact whistle ticket required.') end
    local checked=Check(source,context); if not checked.ok then return checked end
    local r=records[p.generationId]; local ticket=r and r.whistle
    if not r or not ticket or not ticket.claimed or ticket.mode~='follow'
        or ticket.sequence~=p.sequence or ticket.owner~=source
        or ticket.claimSessionId~=context.sessionId or ticket.claimCharacterId~=context.characterId
        or not WhistleLive(r) then return S.Err('stale_whistle','Claimed follow ticket is unavailable.') end
    if not ticket.completed and GetGameTimer()<ticket.followUntil and NetworkGetEntityOwner(r.entity)~=ticket.owner then
        return S.Err('follow_handoff_pending','Control changed; original follow deadline retained for handoff.')
    end
    local replayed=ticket.completed==true
    ticket.completed=true
    return S.Ok({generationId=r.id,sequence=ticket.sequence,state='ended',replayed=replayed})
end


-- Controlled, explicitly retried relocation only. Durable old/new generation
-- fences remain in the existing call repositories; this correlation is process
-- local and never resumes a replacement automatically after resource restart.
local relocations={}
function N.RelocateProof(p,source,context)
    if not Payload(p,false) then return S.Err('invalid_input','Only the original generationId is accepted.') end
    local checked=Check(source,context); if not checked.ok then return checked end
    if not enabled or not running or draining then return S.Err('native_calls_disabled','Relocation requires running native calls.') end
    if GetResourceState('feather-toolkit')~='started' then return S.Err('dependency_unavailable','Toolkit is required before relocation cleanup.') end
    context=S.Copy(context)
    local id=p.generationId:lower()
    local entry=relocations[id]
    if entry and (entry.context.characterId~=context.characterId:lower() or entry.context.source~=source
        or entry.context.sessionId~=context.sessionId) then return S.Err('stale_call','Original character/session required.') end
    if entry and entry.busy then return S.Err('busy','Relocation is already in progress.') end
    if entry and entry.result then
        local reply=S.Copy(entry.result)
        if reply.ok then reply.value.replayed=true end
        return reply
    end
    if not entry then
        local saved=S.CallRepository.Get(context.characterId:lower(),id); if not saved.ok then return saved end
        local v=saved.value; local r=records[id]
        if v.state~='active' or not r or r.context.source~=source or r.context.sessionId~=context.sessionId
            or r.context.characterId~=context.characterId:lower() or not Same(r) or r.cancelled or r.phase~='active' then
            return S.Err('relocation_recovery_required','Original current active observer required; no automatic replacement.')
        end
        if r.busy then return S.Err('busy','Horse is busy.') end
        checked=Check(source,context); if not checked.ok then return checked end
        local ped=GetPlayerPed(source); if not Exists(ped) then return S.Err('player_unavailable','Current player required.') end
        local a,b=GetEntityCoords(ped),GetEntityCoords(r.entity)
        if not a or not b or not Finite(a.x) or not Finite(a.y) or not Finite(a.z)
            or not Finite(b.x) or not Finite(b.y) or not Finite(b.z) then return S.Err('invalid_position','Finite server positions required.') end
        if (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2<=10000 then return S.Err('too_near','Stand more than 100 meters from the horse.') end
        local owned=S.OwnedHorses.GetKnown(v.horseId,v.operationId,source,context); if not owned.ok then return owned end
        checked=Check(source,context); if not checked.ok then return checked end
        if not Same(r) or r.cancelled or r.phase~='active' or GetEntityRoutingBucket(r.entity)~=0 then
            return S.Err('stale_call','Original observer changed.')
        end
        local count=0
        for key,value in pairs(relocations) do
            if not value.busy and ((value.result and GetGameTimer()-(value.finished or 0)>60000)
                or not S.Core.IsSessionCurrent(value.context)) then relocations[key]=nil else count=count+1 end
        end
        if count>=32 then return S.Err('busy','Relocation proof receipt limit reached; try later.') end
        -- A simultaneous request can have installed a correlation during fresh
        -- ownership I/O. Never overwrite its in-flight or completed result.
        if relocations[id] then return S.Err('busy','Relocation was already requested; inspect before retrying.') end
        entry={context=context,original=S.Copy(v),phase='cleanup',busy=false}
        relocations[id]=entry
    end
    entry.busy=true
    local ok,result=pcall(function()
        checked=Check(source,context); if not checked.ok then return checked end
        if not running or not enabled or draining then return S.Err('native_calls_disabled','Relocation is unavailable.') end
        if entry.phase=='cleanup' then
            local r=records[id]
            if r and not r.cancelled and r.phase=='active' and Same(r) then
                local ped=GetPlayerPed(source)
                if not Exists(ped) then return S.Err('player_unavailable','Current player required.') end
                local a,b=GetEntityCoords(ped),GetEntityCoords(r.entity)
                if not a or not b or not Finite(a.x) or not Finite(a.y) or not Finite(a.z)
                    or not Finite(b.x) or not Finite(b.y) or not Finite(b.z) then return S.Err('invalid_position','Finite server positions required.') end
                if (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2<=10000 then return S.Err('too_near','Horse is nearby; no relocation cleanup started.') end
            end
        end
        local stored=N.Store({generationId=id},source,context)
        if not stored.ok then
            if stored.code=='cleanup_pending' then
                entry.phase='cleanup_pending'
                return S.Ok({state='cleanup_pending',originalGenerationId=id,retryRequired=true,gameplayAvailable=false})
            end
            return stored
        end
        if stored.value.state~='released' then return S.Err('relocation_recovery_required','Old cleanup is not confirmed.') end
        entry.phase='replacement_attempted' -- Never retry unknown submission.
        local replacement=RequestSelected({},source,context,entry.original)
        if not replacement.ok then return replacement end
        return S.Ok({state='replacement_requested',originalGenerationId=id,generationId=replacement.value.generationId,
            horseId=entry.original.horseId,replayed=false,gameplayAvailable=false})
    end)
    entry.busy=false
    if not ok then result=S.Persistence.DatabaseError(result) end
    if not result.ok or result.value.state=='replacement_requested' then
        -- Occupancy/unknown reports leave the old active call intact and may be
        -- retried explicitly; attempted replacement outcomes are terminal here.
        if entry.phase=='replacement_attempted' or result.ok then
            entry.result=S.Copy(result); entry.finished=GetGameTimer()
        end
    end
    return result
end
