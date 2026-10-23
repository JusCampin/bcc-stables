-- Gated native bridge. Durable slots own admission; this map holds live
-- creation evidence only and never reconstructs entity authority from net IDs.
Stables.NativeCalls={}
local N,S=Stables.NativeCalls,Stables
local records,enabled,running,draining={},false,false,false
local MARKER='bccStablesGeneration'
local OBSERVER='bccStablesObserver'
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
function N.Dispatch(p,source,context)
    if not Payload(p,false) then return S.Err('invalid_input','Only generationId is accepted.') end
    local checked=Check(source,context); if not checked.ok then return checked end
    if not enabled or not running then return S.Err('native_calls_disabled','Native calls are disabled.') end
    if draining then return S.Err('native_calls_draining','Native dispatch is drained until resource restart.') end
    if GetResourceState('feather-toolkit')~='started' then return S.Err('dependency_unavailable','Toolkit is required for horse models.') end
    context=S.Copy(context); context.characterId=context.characterId:lower(); local id=p.generationId:lower()
    -- Resolve character-scoped durable ownership before consulting shared live
    -- observer state. A foreign caller must not learn whether this ID is active.
    local saved=S.CallRepository.Get(context.characterId,id); if not saved.ok then return saved end
    checked=Check(source,context); if not checked.ok then return checked end
    if draining then return S.Err('native_calls_draining','Native dispatch is drained until resource restart.') end
    if records[id] then return S.Err('submission_conflict','Generation already has a live observer.') end
    local count=0; for _ in pairs(records) do count=count+1 end
    if count>=64 then return S.Err('busy','Native observer capacity reached.') end
    local position=Position(source); if not position.ok then return position end
    if draining then return S.Err('native_calls_draining','Native dispatch is drained until resource restart.') end
    local r={id=id,context=context,position=position.value,candidates={},candidateCount=0,
        started=GetGameTimer(),busy=true,phase='authorizing'}
    records[id]=r
    local ok,result=pcall(function()
        local observer=DB.value('SELECT UUID()')
        if not S.Operations.IsUuid(observer) then return S.Err('invalid_contract','Observer UUID required.') end
        r.observerId=observer:lower()
        if draining or r.cancelled or not running then return S.Err('native_calls_draining','Dispatch cancelled before submission.') end
        local epoch=N.ProcessEpoch(); if not epoch.ok then return epoch end
        if draining or r.cancelled or not running then return S.Err('native_calls_draining','Dispatch cancelled before submission.') end
        local claimed=S.Calls.ClaimSubmission({generationId=id},source,context)
        if not claimed.ok then return claimed end
        local recorded=S.CallLifecycleRepository.RecordProcessEpoch(context,id,epoch.value.processEpoch)
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
    return result
end
function N.Bind(p,source,context)
    if not Payload(p,true) then return S.Err('invalid_input','Exact generationId/netId required.') end
    local checked=Check(source,context); if not checked.ok then return checked end
    local r=records[p.generationId:lower()]
    if not r or r.context.source~=source or r.context.sessionId~=context.sessionId
        or r.context.characterId~=context.characterId:lower() then return S.Err('stale_call','No current native observer.') end
    if r.busy or r.phase~='waiting' or r.cancelled then return S.Err('binding_conflict','Binding is not available.') end
    r.busy=true
    local ok,result=pcall(function()
        local started=GetGameTimer(); local e
        repeat
            e=NetworkGetEntityFromNetworkId(p.netId)
            if Candidate(r,e) then break end
            if r.cancelled or not running or GetGameTimer()-started>=5000 then return S.Err('entity_not_observed','New horse identity did not replicate.') end
            Wait(25)
        until false
        if NetworkGetEntityOwner(e)~=source or NetworkGetNetworkIdFromEntity(e)~=p.netId then
            return S.Err('invalid_entity','Initial network identity/owner mismatch.')
        end
        checked=Check(source,context); if not checked.ok then return checked end
        local pos=Position(source); if not pos.ok then return pos end
        local lease=S.CallRepository.Get(context.characterId,r.id); if not lease.ok then return lease end
        local owned=S.OwnedHorses.Get({horseId=lease.value.horseId},source,context)
        if not owned.ok then return owned end
        checked=Check(source,context); if not checked.ok then return checked end
        if r.cancelled or not running or not Candidate(r,e) or GetPlayerRoutingBucket(source)~=0 then
            return S.Err('stale_call','Session, route or entity changed during binding.')
        end
        r.entity,r.netId=e,p.netId
        Entity(e).state:set(MARKER,r.id,true); Entity(e).state:set(OBSERVER,r.observerId,true)
        local bound=S.CallLifecycleRepository.Bind(r.context,r.id,Identity(r))
        if not bound.ok then return bound end
        owned=S.OwnedHorses.Get({horseId=lease.value.horseId},source,context)
        if not owned.ok then return owned end
        checked=Check(source,context)
        if not checked.ok or r.cancelled or GetPlayerRoutingBucket(source)~=0 or not Same(r) then
            return S.Err('stale_call','Bound generation requires cleanup.')
        end
        r.phase,r.lastOwnerCheck='active',GetGameTimer()
        return S.Ok({generationId=r.id,state='active',netId=r.netId,gameplayAvailable=false})
    end)
    r.busy=false
    if not ok then result=S.Persistence.DatabaseError(result) end
    if not result.ok then Cancel(r) end
    return result
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
                local owned=lease.ok and S.OwnedHorses.Get({horseId=lease.value.horseId},r.context.source,r.context)
                if not owned or not owned.ok then Cancel(r) end
            end
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
    enabled,running,draining=StablesConfig.nativeCalls,true,false
    return S.Ok({ok=true,enabled=enabled,entitySpawning=enabled,storeAvailable=enabled,gameplayAvailable=false})
end
function N.Install()
    for _,entry in ipairs({{'dispatch',N.Dispatch},{'bind',N.Bind},{'store',N.Store},
        {'request',N.Request,true},{'store_current',N.StoreCurrent,true}}) do
        local action,empty=entry[1],entry[3]
        local registered=S.Core.Call('RegisterRpc','stables.horses.call.'..action..'.v1',entry[2],{
            contract=1,direction='client_to_server',requireCharacter=true,windowMs=2000,maxCalls=2,
            maxPayloadBytes=empty and 16 or 192,maxDepth=empty and 1 or 2,maxNodes=empty and 2 or 6,
            validatePayload=function(p)
                if empty then return type(p)=='table' and next(p)==nil end
                return Payload(p,action=='bind')
            end})
        if not registered.ok then return registered end
    end
    RegisterCommand('BccStablesNative',function(source,args)
        if source~=0 then return end
        CreateThread(function()
            local ok,result=pcall(function()
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
                return S.Ok(v)
            end)
            print('[bcc-stables:native] '..json.encode(ok and result or S.Err('native_error','Native inspection failed.')))
        end)
    end,true)
    AddEventHandler('entityCreated',N.Created)
    AddEventHandler('playerDropped',function()
        for _,r in pairs(records) do if r.context.source==source then Cancel(r) end end
    end)
    return S.Ok({routes=5})
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
function N.Request(p,source,context)
    if type(p)~='table' or next(p)~=nil then return S.Err('invalid_input','Call request accepts no fields.') end
    local checked=Check(source,context); if not checked.ok then return checked end
    if not enabled or not running then return S.Err('native_calls_disabled','Native calls are disabled.') end
    if draining then return S.Err('native_calls_draining','Native dispatch is drained until resource restart.') end
    if GetResourceState('feather-toolkit')~='started' then return S.Err('dependency_unavailable','Toolkit is required for horse models.') end
    local position=Position(source); if not position.ok then return position end
    context=S.Copy(context)
    local selected=S.Selection.Get({},source,context); if not selected.ok then return selected end
    if not selected.value.selected or not selected.value.available then
        return S.Err('selection_required','Select an available owned horse first.')
    end
    local prepared=S.Calls.Prepare({expectedSelectionRevision=selected.value.revision},source,context)
    if not prepared.ok then return prepared end
    return N.Dispatch({generationId=prepared.value.generationId},source,context)
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
