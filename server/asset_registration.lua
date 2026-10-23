-- Canonical registration coordinator used by explicit proofs and guarded player
-- admission routes. No automatic worker or gameplay fulfillment.
Stables.AssetRegistration = {}
local G, O, P = Stables.AssetRegistration, Stables.Operations, Stables.Persistence
local MAX = 9007199254740991
local function Integer(v, min) return type(v) == 'number' and v % 1 == 0 and v >= min and v <= MAX end
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function Request(record, model)
    local t = record.terms
    return {
        requestId = 'stables.register:' .. t.operationId,
        assetType = 'horse',
        modelKey = model,
        holderType = 'character',
        holderId = t.characterId,
        provenanceType = 'stable_purchase',
        provenanceId = t.operationId,
        metadataVersion = 1,
        metadata = { stablesHorseId = t.horseId },
        reasonCode = 'stables.horse_purchase',
        referenceType = 'stables_order',
        referenceId = t.operationId,
    }
end

local function Decode(row, record, model)
    if not row then return Stables.Err('registration_not_found', 'Registration intent is missing.') end
    if record.quoteSnapshot and record.quoteSnapshot.modelKey ~= model then
        return Stables.Err('invalid_registration', 'Registration model disagrees with the immutable quote snapshot.')
    end
    local request = Request(record, model)
    local decoded, saved = false, nil
    if type(row.request_json) == 'string' and #row.request_json <= 4096 then decoded, saved = pcall(json.decode,
            row.request_json) end
    if row.operation_id ~= record.terms.operationId or row.character_id ~= record.terms.characterId
        or row.horse_id ~= record.terms.horseId or row.request_id ~= request.requestId or row.model_key ~= model
        or row.fingerprint ~= record.fingerprint .. '|' .. model or not decoded or not Equal(saved, request)
        or not Integer(tonumber(row.revision), 0) then
        return Stables.Err('invalid_registration', 'Persisted registration terms disagree with the purchase.')
    end
    local rev = tonumber(row.revision)
    if (row.state == 'prepared' and rev ~= 0) or (row.state == 'submitted' and rev ~= 1)
        or (row.state == 'linked' and (rev ~= 2 or not O.IsUuid(row.asset_id) or not Integer(tonumber(row.asset_revision), 1)))
        or (row.state ~= 'prepared' and row.state ~= 'submitted' and row.state ~= 'linked')
        or (row.state ~= 'linked' and (row.asset_id ~= nil or row.asset_revision ~= nil)) then
        return Stables.Err('invalid_registration', 'Persisted registration state is inconsistent.')
    end
    return Stables.Ok({
        request = request,
        state = row.state,
        revision = rev,
        assetId = row.asset_id,
        assetRevision = row.asset_revision and tonumber(row.asset_revision)
    })
end

G.ValidateSaved = Decode

function G.Get(operationId, characterId)
    local record = Stables.Repository.Get(operationId, characterId)
    if not record.ok then return record end
    local called, row = pcall(DB.one, 'SELECT * FROM fs_asset_registrations WHERE operation_id=?',
        record.value.terms.operationId)
    if not called then return P.DatabaseError(row) end
    return Decode(row, record.value, row and row.model_key)
end

local function Transaction(operationId, characterId, body)
    if not O.IsUuid(operationId) or not O.IsUuid(characterId) then return Stables.Err('invalid_input',
            'Operation and character UUIDs required.') end
    local ready = Stables.Foundation.RequireReady()
    if not ready.ok then return ready end
    local result
    local called, committed = pcall(DB.transaction, function(tx)
        -- Match reservation lock order; never invoke Assets while holding SQL locks.
        if not tx.one('SELECT character_id,revision FROM fs_character_stables WHERE character_id=? FOR UPDATE', characterId) then
            result = Stables.Err('operation_not_found', 'Purchase was not found.'); return false
        end
        local record = Stables.Repository.ValidateSnapshot(tx.one(
            'SELECT * FROM fs_operations WHERE operation_id=? AND character_id=? FOR UPDATE', operationId, characterId))
        if not record.ok then
            result = record; return false
        end
        if record.value.state ~= 'paid' then
            result = Stables.Err('payment_required', 'A verified paid operation is required.'); return false
        end
        if tx.one('SELECT horse_id FROM fs_horses WHERE origin_operation_id=? FOR UPDATE', operationId) then
            result = Stables.Err('unmapped_horse', 'An existing preliminary horse requires explicit reconciliation.'); return false
        end
        result = body(tx, record.value)
        return result.ok == true
    end)
    if not called then return P.DatabaseError(committed) end
    if committed ~= true then return result and not result.ok and result or
        Stables.Err('transaction_rolled_back', 'Registration transaction did not commit.') end
    return result
end

-- modelKey comes from immutable server-owned terms, never a client model field.
function G.Prepare(operationId, characterId, modelKey)
    if O.IsUuid(operationId) then operationId = operationId:lower() end
    if O.IsUuid(characterId) then characterId = characterId:lower() end
    if type(modelKey) ~= 'string' or #modelKey > 100 or not modelKey:lower():match('^a_c_horse_[a-z0-9_]+$') then
        return Stables.Err('invalid_input', 'A server-selected horse model key is required.')
    end
    modelKey = modelKey:lower()
    return Transaction(operationId, characterId, function(tx, record)
        if record.quoteSnapshot and record.quoteSnapshot.modelKey ~= modelKey then
            return Stables.Err('idempotency_conflict', 'Registration model disagrees with the immutable quote snapshot.')
        end
        local row = tx.one('SELECT * FROM fs_asset_registrations WHERE operation_id=? FOR UPDATE', operationId)
        if row then
            if row.model_key ~= modelKey then return Stables.Err('idempotency_conflict',
                    'Registration model is already reserved.') end
            return Decode(row, record, modelKey)
        end
        local req = Request(record, modelKey)
        local encoded = json.encode(req)
        if #encoded > 4096 then return Stables.Err('invalid_registration', 'Registration request exceeds its bound.') end
        local inserted = tx.exec([[INSERT INTO fs_asset_registrations
            (operation_id,character_id,horse_id,request_id,model_key,fingerprint,request_json)
            VALUES (?,?,?,?,?,?,?)]], operationId, characterId, record.terms.horseId, req.requestId,
            modelKey, record.fingerprint .. '|' .. modelKey, encoded)
        if inserted ~= 1 then return Stables.Err('registration_not_saved', 'Registration intent was not saved.') end
        return Stables.Ok({ request = req, state = 'prepared', revision = 0 })
    end)
end

local function Submitted(operationId, characterId, model)
    return Transaction(operationId, characterId, function(tx, record)
        local checked = Decode(
        tx.one('SELECT * FROM fs_asset_registrations WHERE operation_id=? FOR UPDATE', operationId), record, model)
        if not checked.ok or checked.value.state ~= 'prepared' then return checked end
        if tx.exec([[UPDATE fs_asset_registrations SET state='submitted',revision=1
            WHERE operation_id=? AND state='prepared' AND revision=0]], operationId) ~= 1 then
            return Stables.Err('revision_conflict', 'Registration submission intent changed.')
        end
        checked.value.state, checked.value.revision = 'submitted', 1
        return checked
    end)
end

local function Matches(snapshot, request, retired)
    return type(snapshot) == 'table' and O.IsUuid(snapshot.assetId) and snapshot.assetType == 'horse'
        and snapshot.modelKey == request.modelKey and snapshot.managerResource == 'bcc-stables'
        and snapshot.provenanceType == request.provenanceType and snapshot.provenanceId == request.provenanceId
        and snapshot.status == (retired and 'retired' or 'active') and Integer(snapshot.revision, 1)
        and
        ((retired and snapshot.owner == nil) or (not retired and type(snapshot.owner) == 'table' and O.IsUuid(snapshot.owner.interestId)
            and snapshot.owner.holderType == 'character' and snapshot.owner.holderId == request.holderId))
        and snapshot.metadataVersion == 1 and Equal(snapshot.metadata, request.metadata)
end
G.Matches = Matches

function G.Run(operationId, characterId, modelKey, authorize)
    if O.IsUuid(operationId) then operationId = operationId:lower() end
    if O.IsUuid(characterId) then characterId = characterId:lower() end
    if authorize then
        local allowed = authorize(); if not allowed.ok then return allowed end
    end
    local prepared = G.Prepare(operationId, characterId, modelKey)
    if not prepared.ok then return prepared end
    local submitted = Submitted(operationId, characterId, prepared.value.request.modelKey)
    if not submitted.ok then return submitted end -- unknown local commit must be read before remote submission
    local intent, A = submitted.value, Stables.Assets
    local lookup = A.FindRegistration(intent.request.requestId)
    if not lookup.ok then return lookup end
    if type(lookup.value) ~= 'table' or type(lookup.value.found) ~= 'boolean' then
        return Stables.Err('invalid_contract', 'Assets operation lookup is malformed.')
    end
    local receipt
    if lookup.value.found then
        if lookup.value.operation ~= 'asset.register' then return Stables.Err('registration_conflict',
                'Assets request ID belongs to another operation.') end
        receipt = lookup.value.result
    else
        if intent.state == 'linked' then return Stables.Err('registration_conflict',
                'Linked Assets receipt is missing; reconcile without resubmission.') end
        -- A missing receipt permits only the identical idempotent registration.
        -- It NEVER authorizes cancellation/refund or a replacement request key.
        if authorize then
            local allowed = authorize(); if not allowed.ok then return allowed end
        end
        local registered = A.RegisterHorse(intent.request)
        if not registered.ok then return registered end -- including asset_exists: never adopt its details.assetId
        receipt = registered.value
    end
    if not Matches(receipt, intent.request) then return Stables.Err('registration_conflict',
            'Assets registration receipt does not match the saved intent.') end
    local current = A.ReadHorse(receipt.assetId)
    if not current.ok then return current end
    if not Matches(current.value, intent.request) or current.value.assetId ~= receipt.assetId
        or current.value.revision < receipt.revision or (intent.assetRevision and current.value.revision < intent.assetRevision) then
        return Stables.Err('asset_changed', 'Current Assets facts do not match the purchase; reconcile without refund.')
    end
    return Transaction(operationId, characterId, function(tx, record)
        local checked = Decode(
        tx.one('SELECT * FROM fs_asset_registrations WHERE operation_id=? FOR UPDATE', operationId), record,
            intent.request.modelKey)
        if not checked.ok then return checked end
        local saved = checked.value
        if saved.state == 'linked' then
            if saved.assetId ~= receipt.assetId then return Stables.Err('registration_conflict',
                    'Canonical Assets link changed.') end
        elseif saved.state ~= 'submitted' then
            return Stables.Err('registration_conflict', 'Registration was not submitted.')
        elseif tx.exec([[UPDATE fs_asset_registrations SET state='linked',asset_id=?,asset_revision=?,revision=2
            WHERE operation_id=? AND state='submitted' AND revision=1]], receipt.assetId, current.value.revision, operationId) ~= 1 then
            return Stables.Err('revision_conflict', 'Registration link changed.')
        end
        -- Historical observation only. No ownership authorization, horse projection,
        -- fulfillment, history, outbox or capacity release is committed here.
        return Stables.Ok({
            assetId = receipt.assetId,
            assetRevision = current.value.revision,
            state = 'linked',
            gameplayAvailable = false
        })
    end)
end
