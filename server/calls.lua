-- Pre-spawn call admission only. No native creation, binding or store endpoint.
Stables.Calls = {}
local C, S = Stables.Calls, Stables
local enabled = false
local PreparedHandoff
local function Payload(p, action)
    if type(p) ~= 'table' then return false end
    local key = action == 'prepare' and 'expectedSelectionRevision' or 'generationId'
    for k in pairs(p) do if k ~= key then return false end end
    if action == 'prepare' then return type(p[key]) == 'number' and p[key] % 1 == 0 and p[key] >= 0 and
        p[key] <= 9007199254740991 end
    return (action == 'get' and p[key] == nil) or S.Operations.IsUuid(p[key])
end
function C.Start()
    if type(StablesConfig.callPreparation) ~= 'boolean' then return S.Err('config_error',
            'callPreparation must be a boolean.') end
    enabled = StablesConfig.callPreparation
    return S.Ok({ ok = true, enabled = enabled, entitySpawning = false, storeAvailable = false })
end

local function View(record, context)
    if record.state == 'empty' then return { state = 'empty', entitySpawning = false, gameplayAvailable = false } end
    return {
        generationId = record.generationId,
        horseId = record.horseId,
        assetId = record.assetId,
        modelKey = record.modelKey,
        state = record.state,
        revision = record.revision,
        selectionRevision = record.selectionRevision,
        sessionCurrent = record.sessionId == context.sessionId and record.source == context.source,
        entitySpawning = false,
        gameplayAvailable = false
    }
end
local function Request(action, p, source, context, prepareCurrent, forDispatch, stages)
    local valid=prepareCurrent and action=='prepare' and type(p)=='table' and next(p)==nil
        or (not prepareCurrent and Payload(p,action))
    if not valid then return S.Err('invalid_input', 'Exact call fields required.') end
    local checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    context, p = S.Copy(context), S.Copy(p)
    context.characterId = context.characterId:lower()
    if action == 'prepare' and not enabled then return S.Err('call_preparation_disabled', 'Call preparation is disabled.') end
    local result
    if action == 'prepare' then
        if type(context.sessionId) ~= 'string' or #context.sessionId < 1 or #context.sessionId > 128 then return S.Err(
            'invalid_contract', 'Bounded Core session ID required.') end
        -- Allocate before reading selection: no UUID query may yield between the
        -- fresh canonical snapshot and the repository's locked selection CAS.
        local began=stages and GetGameTimer()
        local ok, id = pcall(DB.value, 'SELECT UUID()')
        if stages then stages.generationUuidMs=GetGameTimer()-began end
        if not ok then return S.Persistence.DatabaseError(id) end
        if not S.Operations.IsUuid(id) then return S.Err('invalid_contract', 'Database generation UUID required.') end
        began=stages and GetGameTimer()
        local selected = S.Selection.Get({}, source, context); if not selected.ok then return selected end
        if stages then stages.selectionMs=GetGameTimer()-began end
        if not prepareCurrent and selected.value.revision ~= p.expectedSelectionRevision then return S.Err('revision_conflict',
                'Inspect current selection before calling.') end
        if not selected.value.selected or not selected.value.available then return S.Err('selection_required',
                'Select an available owned horse first.') end
        began=stages and GetGameTimer()
        result = S.CallRepository.Prepare(context, selected.value.horse, selected.value.revision, id:lower())
        if stages then stages.transactionMs=GetGameTimer()-began end
    elseif action == 'abort' then
        local previous = S.CallRepository.Get(context.characterId, p.generationId:lower())
        if not previous.ok then return previous end
        result = S.CallRepository.Abort(context.characterId, p.generationId:lower())
    else
        result = S.CallRepository.Get(context.characterId, p.generationId and p.generationId:lower())
    end
    checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    if not result.ok then return result end
    if action=='prepare' then
        local began=stages and GetGameTimer()
        local owned=S.OwnedHorses.GetKnown(result.value.horseId,result.value.operationId,source,context)
        if not owned.ok then return owned end
        if stages then stages.recheckMs=GetGameTimer()-began end
        if forDispatch then return S.Ok(PreparedHandoff(result.value,owned.value,source,context)) end
    end
    return S.Ok(View(result.value, context))
end
function C.Prepare(p, source, context) return Request('prepare', p, source, context) end

-- Internal current-selection workflow only; no revision or identity comes from
-- the client. Uses the same fresh snapshot, locked CAS and postcommit checks.
function C.PrepareCurrent(source, context) return Request('prepare', {}, source, context, true) end
function C.PrepareForDispatch(source,context,stages) return Request('prepare',{},source,context,true,true,stages) end

function C.Get(p, source, context) return Request('get', p, source, context) end

function C.Abort(p, source, context) return Request('abort', p, source, context) end

function C.Install()
    for _, entry in ipairs({ { 'prepare', C.Prepare }, { 'get', C.Get }, { 'abort', C.Abort } }) do
        local action = entry[1]
        local result = S.Core.Call('RegisterRpc', 'stables.horses.call.' .. action .. '.v1', entry[2], {
            contract = 1,
            direction = 'client_to_server',
            requireCharacter = true,
            windowMs = 2000,
            maxCalls = 2,
            maxPayloadBytes = 192,
            maxDepth = 2,
            maxNodes = 6,
            validatePayload = function(p) return Payload(p, action) end
        })
        if not result.ok then return result end
    end
    return S.Ok(true)
end


local function CommitSubmission(context,horse,generationId,source,stages,processEpoch,plannedRevision)
    local began=stages and GetGameTimer()
    local result
    if plannedRevision then result=S.CallRepository.PrepareAndClaim(context,horse,plannedRevision,generationId,processEpoch)
    else result=S.CallRepository.ClaimSubmission(context,horse,generationId,processEpoch) end
    if stages then stages.transactionMs=GetGameTimer()-began end
    if not result.ok then return result end
    -- Failure after commit retains the submitted fence; never retry dispatch.
    began=stages and GetGameTimer()
    local owned=S.OwnedHorses.GetKnown(result.value.horseId,result.value.operationId,source,context)
    if not owned.ok then return owned end
    local checked=S.Foundation.CheckSession(source,context); if not checked.ok then return checked end
    if stages then stages.recheckMs=GetGameTimer()-began end
    local view=View(result.value,context)
    if processEpoch then view.processEpoch=result.value.processEpoch end
    return S.Ok(view)
end

-- Internal handoff boundary only. Not installed as RPC/export and never emits a
-- client event. Native coordination must consume a successful claim only once.
local function ClaimSubmission(p, source, context, observed, stages)
    if not Payload(p, 'submit') then return S.Err('invalid_input', 'Only generationId is accepted.') end
    local checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    if not enabled then return S.Err('call_preparation_disabled', 'Call preparation is disabled.') end
    context, p = S.Copy(context), S.Copy(p)
    context.characterId = context.characterId:lower()
    local lease
    if observed ~= nil then
        -- Server-internal handoff only. This snapshot is not submission authority:
        -- the repository rereads and validates the exact lease under its locks.
        if type(observed) ~= 'table' or observed.characterId ~= context.characterId
            or observed.generationId ~= p.generationId:lower() then
            return S.Err('call_not_found', 'Call generation was not found.')
        end
        lease = S.Ok(S.Copy(observed))
    else
        lease = S.CallRepository.Get(context.characterId, p.generationId:lower())
    end
    if not lease.ok then return lease end
    if lease.value.sessionId ~= context.sessionId or lease.value.source ~= source then
        return S.Err('call_recovery_required', 'Submission requires the original current session.')
    end
    if lease.value.state ~= 'prepared' then return S.Err('submission_conflict', 'Generation is not unsubmitted.') end
    local selectionStarted = stages and GetGameTimer()
    local selected = S.Selection.Get({}, source, context); if not selected.ok then return selected end
    if stages then stages.selectionMs = GetGameTimer() - selectionStarted end
    local v = selected.value
    if not v.available or not v.selected or v.horse.horseId ~= lease.value.horseId
        or v.revision ~= lease.value.selectionRevision then
        return S.Err('revision_conflict', 'Prepared selection is no longer available.')
    end
    checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    return CommitSubmission(context,v.horse,lease.value.generationId,source,stages)
end

function C.ClaimSubmission(p, source, context) return ClaimSubmission(p, source, context) end

-- Not installed as RPC/export. Native dispatch already performed the scoped read.
-- Never pass client payload data as observed; locked claim remains authoritative.
function C.ClaimObservedSubmission(p, source, context, observed, stages)
    if observed == nil then return S.Err('invalid_call', 'Observed generation required.') end
    return ClaimSubmission(p, source, context, observed, stages)
end


-- Fresh preparation evidence stays in a same-coroutine, one-use capability.
-- The coordinator allocates every yielding dispatch prerequisite BEFORE this
-- snapshot, then consumes it immediately without intervening DB/provider reads.
PreparedHandoff=function(lease,horse,source,context,planned)
    lease,horse,context=S.Copy(lease),S.Copy(horse),S.Copy(context)
    local thread,used=coroutine.running(),false
    return {lease=S.Copy(lease),claim=function(id,caller,current,stages,processEpoch)
        if used or coroutine.running()~=thread then return S.Err('submission_conflict','Prepared handoff is not reusable.') end
        if id~=lease.generationId or caller~=source or type(current)~='table'
            or current.source~=context.source or current.sessionId~=context.sessionId
            or current.characterId~=context.characterId or current.accountId~=context.accountId then
            return S.Err('call_not_found','Prepared handoff belongs to another request.')
        end
        used=true -- No replay even if the following commit outcome is unknown.
        local checked=S.Foundation.CheckSession(caller,current); if not checked.ok then return checked end
        if not enabled then return S.Err('call_preparation_disabled','Call preparation is disabled.') end
        if lease.sessionId~=current.sessionId or lease.source~=caller then
            return S.Err('call_recovery_required','Submission requires the original current session.')
        end
        if lease.state~='prepared' then return S.Err('submission_conflict','Generation is not unsubmitted.') end
        if stages then stages.selectionMs=0 end -- Fresh horse is captured above; locked selection is still checked below.
        return CommitSubmission(current,horse,lease.generationId,caller,stages,processEpoch,planned and lease.selectionRevision or nil)
    end}
end

-- Resource-local plan, not a persisted prepared generation or client authority.
-- Consume immediately in the same coroutine through the native coordinator.
function C.PlanForDispatch(source,context,stages)
    local checked=S.Foundation.CheckSession(source,context); if not checked.ok then return checked end
    if not enabled then return S.Err('call_preparation_disabled','Call preparation is disabled.') end
    context=S.Copy(context); context.characterId=context.characterId:lower()
    if type(context.sessionId)~='string' or #context.sessionId<1 or #context.sessionId>128 then
        return S.Err('invalid_contract','Bounded Core session ID required.')
    end
    local began=stages and GetGameTimer()
    local previous=S.CallRepository.Get(context.characterId); if not previous.ok then return previous end
    if stages then stages.existingLeaseMs=GetGameTimer()-began end
    local lease=previous.value
    if lease.state~='empty' then
        if lease.sessionId~=context.sessionId or lease.source~=source then
            return S.Err('call_recovery_required','Previous-session call requires recovery.')
        end
        if lease.state~='prepared' then return S.Err('call_cleanup_required','Current call requires cleanup.') end
    end
    local id=lease.generationId
    began=stages and GetGameTimer()
    if not id then
        local ok,value=pcall(DB.value,'SELECT UUID()'); if not ok then return S.Persistence.DatabaseError(value) end
        if not S.Operations.IsUuid(value) then return S.Err('invalid_contract','Database generation UUID required.') end
        id=value:lower()
    end
    if stages then stages.generationUuidMs=GetGameTimer()-began end
    began=stages and GetGameTimer()
    local selected=S.Selection.Get({},source,context); if not selected.ok then return selected end
    if stages then stages.selectionMs=GetGameTimer()-began; stages.transactionMs=0; stages.recheckMs=0 end
    local v=selected.value
    if not v.selected or not v.available then return S.Err('selection_required','Select an available owned horse first.') end
    if lease.state=='prepared' and (lease.horseId~=v.horse.horseId or lease.selectionRevision~=v.revision) then
        return S.Err('revision_conflict','Prepared selection changed.')
    end
    checked=S.Foundation.CheckSession(source,context); if not checked.ok then return checked end
    local plan={generationId=id,characterId=context.characterId,horseId=v.horse.horseId,
        operationId=v.horse.operationId,assetId=v.horse.assetId,modelKey=v.horse.modelKey,
        sessionId=context.sessionId,source=source,selectionRevision=v.revision,state='prepared',revision=0}
    return S.Ok(PreparedHandoff(plan,v.horse,source,context,true))
end
