-- Pre-spawn call admission only. No native creation, binding or store endpoint.
Stables.Calls = {}
local C, S = Stables.Calls, Stables
local enabled = false
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
local function Request(action, p, source, context)
    if not Payload(p, action) then return S.Err('invalid_input', 'Exact call fields required.') end
    local checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    context, p = S.Copy(context), S.Copy(p)
    context.characterId = context.characterId:lower()
    if action == 'prepare' and not enabled then return S.Err('call_preparation_disabled', 'Call preparation is disabled.') end
    local result
    if action == 'prepare' then
        if type(context.sessionId) ~= 'string' or #context.sessionId < 1 or #context.sessionId > 128 then return S.Err(
            'invalid_contract', 'Bounded Core session ID required.') end
        local selected = S.Selection.Get({}, source, context); if not selected.ok then return selected end
        if selected.value.revision ~= p.expectedSelectionRevision then return S.Err('revision_conflict',
                'Inspect current selection before calling.') end
        if not selected.value.selected or not selected.value.available then return S.Err('selection_required',
                'Select an available owned horse first.') end
        local ok, id = pcall(DB.value, 'SELECT UUID()')
        if not ok then return S.Persistence.DatabaseError(id) end
        if not S.Operations.IsUuid(id) then return S.Err('invalid_contract', 'Database generation UUID required.') end
        local current = S.Selection.Get({}, source, context); if not current.ok then return current end
        if current.value.revision ~= selected.value.revision or not current.value.available
            or current.value.horse.horseId ~= selected.value.horse.horseId then
            return S.Err('revision_conflict', 'Selection changed during call admission.')
        end
        result = S.CallRepository.Prepare(context, current.value.horse, current.value.revision, id:lower())
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
        local owned=S.OwnedHorses.Get({horseId=result.value.horseId},source,context)
        if not owned.ok then return owned end
    end
    return S.Ok(View(result.value, context))
end
function C.Prepare(p, source, context) return Request('prepare', p, source, context) end

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


-- Internal handoff boundary only. Not installed as RPC/export and never emits a
-- client event. Native coordination must consume a successful claim only once.
function C.ClaimSubmission(p, source, context)
    if not Payload(p, 'submit') then return S.Err('invalid_input', 'Only generationId is accepted.') end
    local checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    if not enabled then return S.Err('call_preparation_disabled', 'Call preparation is disabled.') end
    context, p = S.Copy(context), S.Copy(p)
    context.characterId = context.characterId:lower()
    local lease = S.CallRepository.Get(context.characterId, p.generationId:lower())
    if not lease.ok then return lease end
    if lease.value.sessionId ~= context.sessionId or lease.value.source ~= source then
        return S.Err('call_recovery_required', 'Submission requires the original current session.')
    end
    if lease.value.state ~= 'prepared' then return S.Err('submission_conflict', 'Generation is not unsubmitted.') end
    local selected = S.Selection.Get({}, source, context); if not selected.ok then return selected end
    local v = selected.value
    if not v.available or not v.selected or v.horse.horseId ~= lease.value.horseId
        or v.revision ~= lease.value.selectionRevision then
        return S.Err('revision_conflict', 'Prepared selection is no longer available.')
    end
    checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    local result = S.CallRepository.ClaimSubmission(context, v.horse, lease.value.generationId)
    if not result.ok then return result end
    -- Failure after commit retains the submitted fence; never retry dispatch.
    local owned = S.OwnedHorses.Get({horseId=result.value.horseId}, source, context)
    if not owned.ok then return owned end
    checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    return S.Ok(View(result.value, context))
end
