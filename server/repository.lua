-- Internal server repository only. No exports/RPC purchase or payment worker.
Stables.Repository = {}
local R, O, P = Stables.Repository, Stables.Operations, Stables.Persistence
local function Key(terms) return 'stables.purchase:' .. terms.operationId end
local function Identity(operationId, characterId)
    if not O.IsUuid(operationId) or not O.IsUuid(characterId) then return nil end
    return operationId:lower(), characterId:lower()
end

local function Decode(row)
    if not row then return Stables.Err('operation_not_found', 'Purchase operation was not found.') end
    if type(row.record_json) ~= 'string' or #row.record_json > 16384 then return Stables.Err('invalid_operation', 'Stored operation is invalid.') end
    local ok, record = pcall(json.decode, row.record_json)
    if not ok or not O.Validate(record).ok then return Stables.Err('invalid_operation', 'Stored operation is invalid.') end
    local terms = record.terms
    for _, pair in ipairs({ { 'operation_id', 'operationId' }, { 'character_id', 'characterId' }, { 'horse_id', 'horseId' },
        { 'quote_id', 'quoteId' }, { 'catalog_id', 'catalogId' }, { 'currency', 'currency' },
        { 'wallet_account_id', 'walletAccountId' }, { 'sink_account_id', 'sinkAccountId' } }) do
        if row[pair[1]] ~= terms[pair[2]] then return Stables.Err('invalid_operation', 'Stored operation identity is inconsistent.') end
    end
    if row.kind ~= 'horse_purchase' or tonumber(row.amount) ~= terms.amount
        or tonumber(row.catalog_revision) ~= terms.catalogRevision or row.fingerprint ~= record.fingerprint
        or row.state ~= record.state or tonumber(row.revision) ~= record.revision or row.payment_key ~= Key(terms)
        or row.payment_transaction_id ~= (record.paymentReceipt and record.paymentReceipt.transactionId or nil)
        or row.refund_transaction_id ~= (record.refundReceipt and record.refundReceipt.transactionId or nil) then
        return Stables.Err('invalid_operation', 'Stored operation columns and receipt snapshot disagree.')
    end
    return Stables.Ok(Stables.Copy(record))
end

-- Pure validation of a row already read from our own table (also used by proof).
R.ValidateSnapshot = Decode

local function Transaction(body)
    -- Foundation includes Core and persistence gates; do this before SQL locks.
    local ready = Stables.Foundation and Stables.Foundation.RequireReady() or P.RequireReady()
    if not ready.ok then return ready end
    local result
    local ok, committed = pcall(DB.transaction, function(tx)
        result = body(tx) -- Capture only the final callback result; no external side effects.
        return result.ok == true
    end)
    if not ok then return P.DatabaseError(committed) end
    if committed ~= true then return result and not result.ok and result or Stables.Err('transaction_rolled_back', 'Stables transaction did not commit.') end
    return result
end

local function LockCharacter(tx, characterId)
    return tx.one('SELECT character_id,revision FROM fs_character_stables WHERE character_id=? FOR UPDATE', characterId)
end

function R.Get(operationId, characterId)
    operationId, characterId = Identity(operationId, characterId)
    if not operationId then return Stables.Err('invalid_input', 'Operation and character UUIDs required.') end
    local ready = P.RequireReady()
    if not ready.ok then return ready end
    local ok, result = pcall(function()
        return Decode(DB.one('SELECT * FROM fs_operations WHERE operation_id=? AND character_id=?', operationId, characterId))
    end)
    return ok and result or P.DatabaseError(result)
end

function R.Reserve(input,quoteSnapshot)
    local candidate = O.New(input,quoteSnapshot)
    if not candidate.ok then return candidate end
    local record, terms = candidate.value, candidate.value.terms
    return Transaction(function(tx)
        tx.exec('INSERT IGNORE INTO fs_character_stables (character_id) VALUES (?)', terms.characterId)
        if not LockCharacter(tx, terms.characterId) then return Stables.Err('character_stable_missing', 'Character stable lock is unavailable.') end
        local existing = tx.one('SELECT * FROM fs_operations WHERE operation_id=? FOR UPDATE', terms.operationId)
        if existing then
            if existing.character_id ~= terms.characterId or existing.fingerprint ~= record.fingerprint then
                return Stables.Err('idempotency_conflict', 'Operation UUID is bound to different purchase terms.')
            end
            local decoded = Decode(existing)
            return decoded.ok and Stables.Ok({ operation = decoded.value, replayed = true }) or decoded
        end
        local owned = tonumber(tx.value('SELECT COUNT(*) FROM fs_horses WHERE owner_character_id=?', terms.characterId))
        local reserved = tonumber(tx.value([[SELECT COUNT(*) FROM fs_operations WHERE character_id=?
            AND state NOT IN ('fulfilled','cancelled','refunded')]], terms.characterId))
        if not owned or not reserved then return Stables.Err('invalid_capacity', 'Capacity counts are unavailable.') end
        if owned + reserved >= StablesConfig.ownedHorseLimit then return Stables.Err('capacity_exceeded', 'Character stable capacity is full.') end
        local encoded = json.encode(record)
        if #encoded > 16384 then return Stables.Err('invalid_operation', 'Operation snapshot exceeds its bound.') end
        local inserted = tx.exec([[INSERT INTO fs_operations
            (operation_id,character_id,horse_id,quote_id,catalog_id,catalog_revision,currency,amount,
             wallet_account_id,sink_account_id,payment_key,fingerprint,state,revision,record_json)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)]],
            terms.operationId, terms.characterId, terms.horseId, terms.quoteId, terms.catalogId, terms.catalogRevision,
            terms.currency, terms.amount, terms.walletAccountId, terms.sinkAccountId, Key(terms), record.fingerprint,
            record.state, record.revision, encoded)
        if inserted ~= 1 then return Stables.Err('operation_not_saved', 'Operation insertion did not complete.') end
        return Stables.Ok({ operation = Stables.Copy(record), replayed = false })
    end)
end

function R.Advance(operationId, characterId, expectedRevision, target, evidence)
    operationId, characterId = Identity(operationId, characterId)
    if not operationId then return Stables.Err('invalid_input', 'Operation and character UUIDs required.') end
    evidence = type(evidence) == 'table' and Stables.Copy(evidence) or {}
    -- A caller-supplied fence/horse ID cannot prove Assets registration was
    -- committed or prevented. Generic transitions stay closed, including restored
    -- preliminary compensation snapshots. Only FenceUnregistered's locked absence
    -- check below can admit the narrow never-prepared compensation path.
    if target == 'fulfilled' or target == 'compensation_pending' or target == 'refunded' then
        return Stables.Err('assets_settlement_unavailable', 'Assets-backed settlement is not implemented.')
    end
    -- Internal evidence must come from trusted Economy results / committed domain facts.
    return Transaction(function(tx)
        if not LockCharacter(tx, characterId) then return Stables.Err('operation_not_found', 'Purchase operation was not found.') end
        local decoded = Decode(tx.one('SELECT * FROM fs_operations WHERE operation_id=? AND character_id=? FOR UPDATE', operationId, characterId))
        if not decoded.ok then return decoded end
        local record = decoded.value
        local advanced = O.Advance(record, expectedRevision, target, evidence)
        if not advanced.ok then return advanced end
        local nextRecord = advanced.value
        local encoded = json.encode(nextRecord)
        if #encoded > 16384 then return Stables.Err('invalid_operation', 'Operation snapshot exceeds its bound.') end
        local changed = tx.exec([[UPDATE fs_operations SET state=?,revision=?,payment_transaction_id=?,refund_transaction_id=?,record_json=?
            WHERE operation_id=? AND character_id=? AND revision=? AND state=?]], target, nextRecord.revision,
            nextRecord.paymentReceipt and nextRecord.paymentReceipt.transactionId or nil,
            nextRecord.refundReceipt and nextRecord.refundReceipt.transactionId or nil, encoded,
            operationId, characterId, expectedRevision, record.state)
        if changed ~= 1 then return Stables.Err('revision_conflict', 'Concurrent operation update refused; transaction rolled back.') end
        return Stables.Ok(Stables.Copy(nextRecord))
    end)
end

-- Narrow exception to the generic settlement gate: registration was NEVER
-- prepared. The same character -> operation lock order excludes Prepare racing
-- this fence. Once compensation_pending commits, Prepare/Submitted require paid
-- and cannot submit later. Any registration row, even prepared, blocks this path.
local function Unregistered(operationId,characterId,expectedRevision,refundReceipt)
    operationId,characterId=Identity(operationId,characterId)
    if not operationId then return Stables.Err('invalid_input','Operation and character UUIDs required.') end
    refundReceipt=type(refundReceipt)=='table' and Stables.Copy(refundReceipt) or refundReceipt
    return Transaction(function(tx)
        if not LockCharacter(tx,characterId) then return Stables.Err('operation_not_found','Purchase was not found.') end
        local decoded=Decode(tx.one('SELECT * FROM fs_operations WHERE operation_id=? AND character_id=? FOR UPDATE',operationId,characterId))
        if not decoded.ok then return decoded end
        local record=decoded.value
        if tx.one('SELECT * FROM fs_asset_registrations WHERE operation_id=? FOR UPDATE',operationId) then
            return Stables.Err('registration_exists','Registration intent exists; this refund path is unavailable.')
        end
        if tx.one('SELECT horse_id FROM fs_horses WHERE origin_operation_id=? FOR UPDATE',operationId)
            or tonumber(tx.value('SELECT COUNT(*) FROM fs_horse_history WHERE operation_id=?',operationId))~=0
            or tonumber(tx.value('SELECT COUNT(*) FROM fs_outbox WHERE operation_id=?',operationId))~=0 then
            return Stables.Err('fulfillment_exists','Horse fulfillment artifacts require reconciliation.')
        end
        if record.revision~=expectedRevision then return Stables.Err('revision_conflict','Purchase revision changed.') end
        local target=refundReceipt and 'refunded' or 'compensation_pending'
        if record.state==target and record.registrationFence=='unregistered_v1' then
            if refundReceipt and record.refundReceipt.transactionId~=refundReceipt.transactionId then
                return Stables.Err('invalid_receipt','Refund identity changed.')
            end
            return Stables.Ok(record)
        end
        if (refundReceipt and (record.state~='compensation_pending' or record.registrationFence~='unregistered_v1'))
            or (not refundReceipt and record.state~='paid') then
            return Stables.Err('registration_not_fenced','Only a paid, never-prepared registration can be fenced here.')
        end
        local advanced=O.Advance(record,record.revision,target,refundReceipt and {refundReceipt=refundReceipt} or {fulfillmentFenced=true})
        if not advanced.ok then return advanced end
        local nextRecord=advanced.value
        nextRecord.registrationFence='unregistered_v1'
        if not O.Validate(nextRecord).ok then return Stables.Err('invalid_operation','Invalid fenced operation.') end
        local encoded=json.encode(nextRecord)
        if #encoded>16384 then return Stables.Err('invalid_operation','Fenced operation exceeds its bound.') end
        local changed=tx.exec([[UPDATE fs_operations SET state=?,revision=?,payment_transaction_id=?,refund_transaction_id=?,record_json=?
            WHERE operation_id=? AND character_id=? AND revision=? AND state=?]],nextRecord.state,nextRecord.revision,
            nextRecord.paymentReceipt.transactionId,nextRecord.refundReceipt and nextRecord.refundReceipt.transactionId or nil,
            encoded,operationId,characterId,record.revision,record.state)
        if changed~=1 then return Stables.Err('revision_conflict','Fenced purchase update did not commit.') end
        return Stables.Ok(nextRecord)
    end)
end

function R.FenceUnregistered(operationId,characterId,expectedRevision)
    return Unregistered(operationId,characterId,expectedRevision)
end

-- Evidence must be obtained and journal-verified by Payments.RefundUnregistered,
-- never accepted from a client or generic settlement transition.
function R.SaveUnregisteredRefund(operationId,characterId,expectedRevision,receipt)
    if type(receipt)~='table' then return Stables.Err('invalid_receipt','Verified reversal receipt required.') end
    return Unregistered(operationId,characterId,expectedRevision,receipt)
end

local function Linked(operationId,characterId,expectedRevision,assetId,assetRevision,receipt)
    operationId,characterId=Identity(operationId,characterId)
    if not operationId then return Stables.Err('invalid_input','Operation and character UUIDs required.') end
    receipt=Stables.Copy(receipt)
    return Transaction(function(tx)
        if not LockCharacter(tx,characterId) then return Stables.Err('operation_not_found','Purchase was not found.') end
        local decoded=Decode(tx.one('SELECT * FROM fs_operations WHERE operation_id=? AND character_id=? FOR UPDATE',operationId,characterId))
        if not decoded.ok then return decoded end
        local record=decoded.value
        local row=tx.one('SELECT * FROM fs_asset_registrations WHERE operation_id=? FOR UPDATE',operationId)
        local link=Stables.AssetRegistration.ValidateSaved(row,record,row and row.model_key)
        if not link.ok then return link end
        if link.value.state~='linked' then return Stables.Err('registration_not_linked','Only a completed canonical link can be retired here.') end
        if record.revision~=expectedRevision then return Stables.Err('revision_conflict','Purchase revision changed.') end
        if tx.one('SELECT horse_id FROM fs_horses WHERE origin_operation_id=? FOR UPDATE',operationId)
            or tonumber(tx.value('SELECT COUNT(*) FROM fs_horse_history WHERE operation_id=?',operationId))~=0
            or tonumber(tx.value('SELECT COUNT(*) FROM fs_outbox WHERE operation_id=?',operationId))~=0 then
            return Stables.Err('fulfillment_exists','Fulfilled horses require a separate cancellation protocol.')
        end
        local plan=record.assetRetirement
        if receipt then
            if record.registrationFence~='linked_retirement_v1' or not plan or plan.assetId~=link.value.assetId then
                return Stables.Err('registration_not_fenced','A matching linked-retirement fence is required.')
            end
            if record.state=='refunded' then
                if record.refundReceipt.transactionId~=receipt.transactionId then return Stables.Err('invalid_receipt','Refund identity changed.') end
                return Stables.Ok(record)
            end
        elseif record.state=='compensation_pending' and record.registrationFence=='linked_retirement_v1' then
            if plan.assetId~=assetId or plan.expectedRevision~=assetRevision then return Stables.Err('idempotency_conflict','Retirement plan changed.') end
            return Stables.Ok(record)
        elseif record.state~='paid' or assetId~=link.value.assetId or type(assetRevision)~='number'
            or assetRevision<link.value.assetRevision then
            return Stables.Err('registration_not_fenced','Current canonical asset revision and a paid purchase are required.')
        end
        local advanced=O.Advance(record,record.revision,receipt and 'refunded' or 'compensation_pending',
            receipt and {refundReceipt=receipt} or {fulfillmentFenced=true})
        if not advanced.ok then return advanced end
        local nextRecord=advanced.value
        if not receipt then
            nextRecord.registrationFence='linked_retirement_v1'
            nextRecord.assetRetirement={assetId=assetId,expectedRevision=assetRevision,requestId='stables.retire:'..operationId}
        end
        if not O.Validate(nextRecord).ok then return Stables.Err('invalid_operation','Invalid linked cancellation plan.') end
        local encoded=json.encode(nextRecord)
        if #encoded>16384 then return Stables.Err('invalid_operation','Cancellation snapshot exceeds its bound.') end
        if tx.exec([[UPDATE fs_operations SET state=?,revision=?,payment_transaction_id=?,refund_transaction_id=?,record_json=?
            WHERE operation_id=? AND character_id=? AND revision=? AND state=?]],nextRecord.state,nextRecord.revision,
            nextRecord.paymentReceipt.transactionId,nextRecord.refundReceipt and nextRecord.refundReceipt.transactionId or nil,
            encoded,operationId,characterId,record.revision,record.state)~=1 then
            return Stables.Err('revision_conflict','Linked cancellation update did not commit.')
        end
        return Stables.Ok(nextRecord)
    end)
end
function R.FenceLinked(operationId,characterId,revision,assetId,assetRevision)
    return Linked(operationId,characterId,revision,assetId,assetRevision)
end
function R.SaveLinkedRefund(operationId,characterId,revision,receipt)
    if type(receipt)~='table' then return Stables.Err('invalid_receipt','Verified reversal receipt required.') end
    return Linked(operationId,characterId,revision,nil,nil,receipt)
end
