-- Atomic local projection; canonical facts must be observed by the coordinator.
Stables.FulfillmentRepository = {}
local R, S = Stables.FulfillmentRepository, Stables
local EVENT = 'stables.purchase.fulfilled.v1'
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function Facts(record, link)
    local t = record.terms
    return {
        eventVersion = 1,
        operationId = t.operationId,
        horseId = t.horseId,
        assetId = link.assetId,
        characterId = t.characterId,
        catalogId = t.catalogId,
        modelKey = record.quoteSnapshot.modelKey
    }
end
local function Decode(tx, record, link, historical)
    local t = record.terms
    local horse = tx.one('SELECT * FROM fs_horses WHERE origin_operation_id=?', t.operationId)
    local history = tx.one('SELECT * FROM fs_horse_history WHERE operation_id=? AND event_kind=?', t.operationId,
        'purchased')
    local outbox = tx.one('SELECT * FROM fs_outbox WHERE operation_id=? AND event_name=?', t.operationId, EVENT)
    if not horse or not history or not outbox then return S.Err('fulfillment_incomplete',
            'Projection/history/outbox must all exist.') end
    local facts = Facts(record, link)
    local ok, h, o = pcall(function() return json.decode(history.facts_json), json.decode(outbox.payload_json) end)
    if horse.horse_id ~= t.horseId or horse.catalog_id ~= t.catalogId
        or tonumber(horse.catalog_revision) ~= t.catalogRevision or horse.origin_operation_id ~= t.operationId
        or history.event_id ~= t.operationId or history.horse_id ~= t.horseId or history.operation_id ~= t.operationId
        or history.event_kind ~= 'purchased' or outbox.event_id ~= 'stables.fulfilled:' .. t.operationId
        or outbox.operation_id ~= t.operationId or outbox.event_name ~= EVENT or not ok or not Equal(h, facts) or not Equal(o, facts) then
        return S.Err('fulfillment_conflict', 'Stored projection/history/outbox disagree with the purchase.')
    end
    -- Purchase evidence remains historical when a later lifecycle changes the
    -- owner cache or availability. It must never grant current horse access.
    if historical then return S.Ok({
        operationId = t.operationId,
        horseId = t.horseId,
        assetId = link.assetId,
        historical = true
    }) end
    if horse.owner_character_id ~= t.characterId or horse.availability ~= 'stored'
        or horse.biological_state ~= 'alive' or tonumber(horse.revision) ~= 0 then
        return S.Err('fulfillment_conflict', 'Current projection is not the initial stored horse.')
    end
    return S.Ok({
        operationId = t.operationId,
        horseId = t.horseId,
        assetId = link.assetId,
        state = 'fulfilled',
        revision = record.revision,
        availability = 'stored',
        gameplayAvailable = false,
        outboxPending = tonumber(outbox.delivered) == 0
    })
end
local function Transaction(id, characterId, body)
    if not S.Operations.IsUuid(id) or not S.Operations.IsUuid(characterId) then return S.Err('invalid_input',
            'Operation and character UUIDs required.') end
    id, characterId = id:lower(), characterId:lower()
    local ready = S.Foundation.RequireReady(); if not ready.ok then return ready end
    local result
    local ok, committed = pcall(DB.transaction, function(tx)
        if not tx.one('SELECT character_id,revision FROM fs_character_stables WHERE character_id=? FOR UPDATE', characterId) then
            result = S.Err('operation_not_found', 'Purchase was not found.'); return false
        end
        local record = S.Repository.ValidateSnapshot(tx.one(
        'SELECT * FROM fs_operations WHERE operation_id=? AND character_id=? FOR UPDATE', id, characterId))
        if not record.ok then
            result = record; return false
        end
        local r = record.value
        if not r.quoteSnapshot or r.quoteSnapshot.kind ~= 'quote_admission_v1' then
            result = S.Err('intent_conflict', 'Only player admission purchases qualify.'); return false
        end
        local row = tx.one('SELECT * FROM fs_asset_registrations WHERE operation_id=? FOR UPDATE', id)
        local link = S.AssetRegistration.ValidateSaved(row, r, row and row.model_key)
        if not link.ok then
            result = link; return false
        end
        if link.value.state ~= 'linked' then
            result = S.Err('registration_not_linked', 'Canonical registration must be linked.'); return false
        end
        result = body(tx, r, link.value)
        return result.ok == true
    end)
    if not ok then return S.Persistence.DatabaseError(committed) end
    if committed ~= true then return result or S.Err('transaction_rolled_back', 'Fulfillment transaction did not commit.') end
    return result
end
function R.Get(id, characterId)
    return Transaction(id, characterId, function(tx, record, link)
        if record.state ~= 'fulfilled' then return S.Err('fulfillment_not_found', 'Order is not fulfilled.') end
        return Decode(tx, record, link)
    end)
end

-- Internal historical evidence only; current ownership/state authorization must
-- continue through Get/OwnedHorses and canonical Assets reads.
function R.GetHistorical(id, characterId)
    return Transaction(id, characterId, function(tx, record, link)
        if record.state ~= 'fulfilled' then return S.Err('fulfillment_not_found', 'Order is not fulfilled.') end
        return Decode(tx, record, link, true)
    end)
end

function R.Commit(id, characterId, observed)
    observed = S.Copy(observed)
    return Transaction(id, characterId, function(tx, record, link)
        id = record.terms.operationId
        if not S.AssetRegistration.Matches(observed, link.request) or observed.assetId ~= link.assetId
            or observed.revision < link.assetRevision then
            return S.Err('asset_changed', 'Canonical observation does not match the purchase.')
        end
        if record.state == 'fulfilled' then return Decode(tx, record, link) end
        if record.state ~= 'paid' then return S.Err('payment_required', 'Only a paid unfenced purchase may fulfill.') end
        if tx.one('SELECT horse_id FROM fs_horses WHERE origin_operation_id=? FOR UPDATE', id)
            or tonumber(tx.value('SELECT COUNT(*) FROM fs_horse_history WHERE operation_id=?', id)) ~= 0
            or tonumber(tx.value('SELECT COUNT(*) FROM fs_outbox WHERE operation_id=?', id)) ~= 0 then
            return S.Err('fulfillment_conflict', 'Uncommitted fulfillment artifacts require reconciliation.')
        end
        local t = record.terms
        local advanced = S.Operations.Advance(record, record.revision, 'fulfilled',
            { horseId = t.horseId, ownerCharacterId = t.characterId })
        if not advanced.ok then return advanced end
        local nextRecord = advanced.value
        local encoded = json.encode(nextRecord)
        local facts = json.encode(Facts(record, link))
        if #encoded > 16384 or #facts > 4096 then return S.Err('invalid_operation',
                'Fulfillment snapshot exceeds its bounds.') end
        if tx.exec([[INSERT INTO fs_horses (horse_id,owner_character_id,origin_operation_id,catalog_id,catalog_revision)
            VALUES (?,?,?,?,?)]], t.horseId, t.characterId, id, t.catalogId, t.catalogRevision) ~= 1 then
            return S.Err('fulfillment_not_saved', 'Horse projection was not saved.')
        end
        if tx.exec([[INSERT INTO fs_horse_history (event_id,horse_id,operation_id,event_kind,facts_json)
            VALUES (?,?,?,?,?)]], id, t.horseId, id, 'purchased', facts) ~= 1
            or tx.exec([[INSERT INTO fs_outbox (event_id,operation_id,event_name,payload_json)
            VALUES (?,?,?,?)]], 'stables.fulfilled:' .. id, id, EVENT, facts) ~= 1 then
            return S.Err('fulfillment_not_saved', 'History/outbox was not saved.')
        end
        if tx.exec([[UPDATE fs_operations SET state=?,revision=?,payment_transaction_id=?,refund_transaction_id=?,record_json=?
            WHERE operation_id=? AND character_id=? AND revision=? AND state=?]], 'fulfilled', nextRecord.revision,
                nextRecord.paymentReceipt.transactionId, nil, encoded, id, t.characterId, record.revision, 'paid') ~= 1 then
            return S.Err('revision_conflict', 'Fulfillment state changed; transaction rolled back.')
        end
        return Decode(tx, nextRecord, link)
    end)
end
