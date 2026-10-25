-- Durable preference only. Never a substitute for current canonical ownership.
Stables.Selection = {}
local C, S = Stables.Selection, Stables
local enabled = false
local MAX = 9007199254740991
local function Revision(v) return type(v) == 'number' and v % 1 == 0 and v >= 0 and v <= MAX end
local function Payload(p, action)
    if type(p) ~= 'table' then return false end
    local fields = action == 'get' and {} or action == 'set' and { horseId = true, expectedRevision = true } or
    { expectedRevision = true }
    for key in pairs(p) do if not fields[key] then return false end end
    return action == 'get' or (Revision(p.expectedRevision) and (action ~= 'set' or S.Operations.IsUuid(p.horseId)))
end
local function Decode(row, characterId)
    if not row then return S.Ok({ revision = 0 }) end
    local revision = tonumber(row.revision)
    if row.character_id ~= characterId or not Revision(revision)
        or (row.selected_horse_id ~= nil and not S.Operations.IsUuid(row.selected_horse_id)) then
        return S.Err('invalid_selection', 'Character stable selection is invalid.')
    end
    return S.Ok({ revision = revision, horseId = row.selected_horse_id })
end
local function Read(characterId)
    local ok, row = pcall(DB.one, [[SELECT character_id,selected_horse_id,revision FROM fs_character_stables
        WHERE character_id=?]], characterId)
    return ok and Decode(row, characterId) or S.Persistence.DatabaseError(row)
end
function C.Start()
    if type(StablesConfig.horseSelection) ~= 'boolean' then return S.Err('config_error',
            'horseSelection must be a boolean.') end
    enabled = StablesConfig.horseSelection
    return S.Ok({ ok = true, enabled = enabled, entitySpawning = false })
end

function C.Enabled() return enabled end

local function Save(characterId, expected, horse)
    local ready = S.Foundation.RequireReady(); if not ready.ok then return ready end
    local result
    local ok, committed = pcall(DB.transaction, function(tx)
        local row = tx.one([[SELECT character_id,selected_horse_id,revision FROM fs_character_stables
            WHERE character_id=? FOR UPDATE]], characterId)
        local read = Decode(row, characterId)
        if not read.ok then
            result = read; return false
        end
        local current = read.value
        if S.CareRepository then
            local care=S.CareRepository.CheckCharacter(tx,characterId)
            if not care.ok then result=care; return false end
        end
        if current.revision ~= expected then
            result = S.Err('revision_conflict', 'Selection changed; inspect before retrying.'); return false
        end
        if horse then
            if not row then
                result = S.Err('invalid_selection', 'Owning character stable row is missing.'); return false
            end
            local operation = S.Repository.ValidateSnapshot(tx.one(
            'SELECT * FROM fs_operations WHERE operation_id=? AND character_id=? FOR UPDATE', horse.operationId,
                characterId))
            if not operation.ok then
                result = operation; return false
            end
            local record = operation.value
            local registration = tx.one('SELECT * FROM fs_asset_registrations WHERE operation_id=? FOR UPDATE',
                horse.operationId)
            local link = S.AssetRegistration.ValidateSaved(registration, record, registration and registration.model_key)
            if record.state ~= 'fulfilled' or not record.quoteSnapshot or record.quoteSnapshot.kind ~= 'quote_admission_v1'
                or record.terms.horseId ~= horse.horseId or not link.ok or link.value.state ~= 'linked'
                or link.value.assetId ~= horse.assetId or link.value.request.modelKey ~= horse.modelKey
                or horse.assetRevision < link.value.assetRevision then
                result = S.Err('invalid_selection', 'Owned horse link changed before selection.'); return false
            end
            local projection = tx.one('SELECT * FROM fs_horses WHERE horse_id=? AND owner_character_id=? FOR UPDATE',
                horse.horseId, characterId)
            if not projection or projection.horse_id ~= horse.horseId or projection.owner_character_id ~= characterId
                or projection.origin_operation_id ~= horse.operationId or (projection.availability ~= 'stored' and projection.availability ~= 'active')
                or projection.biological_state ~= 'alive' then
                result = S.Err('horse_not_found', 'An owned horse with valid lifecycle state is required.'); return false
            end
            local projected=S.HorseProjection.Validate(tx,projection,{assetId=horse.assetId,modelKey=horse.modelKey})
            if not projected.ok then result=projected; return false end
        end
        local desired = horse and horse.horseId or nil
        if desired == current.horseId then
            result = S.Ok(current); return true
        end
        if tx.one('SELECT * FROM fs_call_slots WHERE character_id=? FOR UPDATE', characterId) then
            result = S.Err('horse_busy', 'Abort/clean the current call before changing selection.'); return false
        end
        if current.revision == MAX then
            result = S.Err('revision_exhausted', 'Selection revision is exhausted.'); return false
        end
        if tx.exec([[UPDATE fs_character_stables SET selected_horse_id=?,revision=revision+1
            WHERE character_id=? AND revision=?]], desired, characterId, expected) ~= 1 then
            result = S.Err('revision_conflict', 'Selection changed; transaction rolled back.'); return false
        end
        result = S.Ok({ revision = expected + 1, horseId = desired })
        return true
    end)
    if not ok then return S.Persistence.DatabaseError(committed) end
    if committed ~= true then return result or S.Err('transaction_rolled_back', 'Selection did not commit.') end
    return result
end
local function View(saved, source, context)
    local view = { revision = saved.revision, selected = saved.horseId ~= nil, available = false, gameplayAvailable = false }
    if saved.horseId then
        local horse = S.OwnedHorses.Get({ horseId = saved.horseId }, source, context)
        if horse.ok then
            view.horse = horse.value; view.available = true
        elseif horse.code ~= 'horse_not_found' then
            return horse
        end
    end
    return S.Ok(view)
end
local function Request(action, p, source, context)
    if not Payload(p, action) then return S.Err('invalid_input',
            'Exact selection fields and integer expectedRevision required.') end
    local checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    context, p = S.Copy(context), S.Copy(p)
    local characterId = context.characterId:lower()
    if action == 'set' and not enabled then return S.Err('selection_disabled', 'Horse selection is disabled.') end
    local result
    if action == 'get' then
        result = Read(characterId)
    else
        local horse
        if action == 'set' then
            local owned = S.OwnedHorses.Get({ horseId = p.horseId:lower() }, source, context); if not owned.ok then return
                owned end
            horse = owned.value
        end
        checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
        result = Save(characterId, p.expectedRevision, horse)
    end
    checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    if not result.ok then return result end
    local view = View(result.value, source, context)
    checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    return view
end
function C.Get(p, source, context) return Request('get', p, source, context) end

function C.Set(p, source, context) return Request('set', p, source, context) end

function C.Clear(p, source, context) return Request('clear', p, source, context) end

function C.Install()
    for _, entry in ipairs({ { 'get', C.Get }, { 'set', C.Set }, { 'clear', C.Clear } }) do
        local action = entry[1]
        local result = S.Core.Call('RegisterRpc', 'stables.horses.selection.' .. action .. '.v1', entry[2], {
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
