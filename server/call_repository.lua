-- Durable call fence and single-use submission claim. No native dispatch or active cleanup yet.
Stables.CallRepository = {}
local R, S = Stables.CallRepository, Stables
local function StateRevision(state, revision)
    local allowed={prepared={[0]=true},submitting={[1]=true},active={[2]=true},
        cleanup_pending={[3]=true},released={[1]=true,[4]=true,[5]=true},
        reconciliation_required={[2]=true,[3]=true,[4]=true}}
    return allowed[state] and allowed[state][revision] == true
end
local function Decode(row, characterId)
    if not row then return S.Err('call_not_found', 'Call generation was not found.') end
    if row.character_id ~= characterId or not S.Operations.IsUuid(row.generation_id) or not S.Operations.IsUuid(row.horse_id)
        or not S.Operations.IsUuid(row.operation_id) or not S.Operations.IsUuid(row.asset_id)
        or type(row.model_key) ~= 'string' or #row.model_key > 100 or not row.model_key:match('^a_c_horse_[a-z0-9_]+$')
        or type(row.session_id) ~= 'string' or #row.session_id < 1 or #row.session_id > 128
        or type(tonumber(row.source_id)) ~= 'number' or tonumber(row.source_id) % 1 ~= 0 or tonumber(row.source_id) < 1
        or not tonumber(row.selection_revision) or tonumber(row.selection_revision) % 1 ~= 0 or tonumber(row.selection_revision) < 0
        or not StateRevision(row.state, tonumber(row.revision)) then
        return S.Err('invalid_call', 'Call generation requires reconciliation.')
    end
    return S.Ok({
        generationId = row.generation_id,
        characterId = characterId,
        horseId = row.horse_id,
        operationId = row.operation_id,
        assetId = row.asset_id,
        modelKey = row.model_key,
        sessionId = row.session_id,
        source = tonumber(row.source_id),
        selectionRevision = tonumber(row.selection_revision),
        state = row.state,
        revision = tonumber(row.revision)
    })
end
local function Transaction(characterId, body)
    local ready = S.Foundation.RequireReady(); if not ready.ok then return ready end
    local result
    local ok, committed = pcall(DB.transaction, function(tx)
        local stable = tx.one(
        'SELECT character_id,selected_horse_id,revision FROM fs_character_stables WHERE character_id=? FOR UPDATE',
            characterId)
        if not stable then
            result = S.Err('selection_required', 'Select an owned horse first.'); return false
        end
        result = body(tx, stable); return result.ok == true
    end)
    if not ok then return S.Persistence.DatabaseError(committed) end
    if committed ~= true then return result or S.Err('transaction_rolled_back', 'Call transaction did not commit.') end
    return result
end
function R.Get(characterId, generationId)
    local ready = S.Foundation.RequireReady(); if not ready.ok then return ready end
    local function Validated(result)
        if not result.ok then return result end
        if S.CallLifecycleRepository then
            local binding=S.CallLifecycleRepository.ValidateState(DB,result.value)
            if not binding.ok then return binding end
        elseif result.value.state~='prepared' and result.value.state~='submitting'
            and not (result.value.state=='released' and result.value.revision==1) then
            return S.Err('invalid_call','Lifecycle repository is unavailable.')
        end
        return result
    end
    local ok, result = pcall(function()
        if not generationId then
            local slot = DB.one('SELECT * FROM fs_call_slots WHERE character_id=?', characterId)
            if not slot then
                if DB.one("SELECT generation_id FROM fs_call_leases WHERE character_id=? AND state<>'released' LIMIT 1",characterId) then
                    return S.Err('invalid_call','Unreleased generation has no runtime slot; reconcile before calling.')
                end
                return S.Ok({state='empty'})
            end
            local lease = Decode(
            DB.one('SELECT * FROM fs_call_leases WHERE generation_id=? AND character_id=?', slot.generation_id,
                characterId), characterId)
            if not lease.ok or lease.value.state == 'released' or slot.horse_id ~= lease.value.horseId then return S.Err(
                'invalid_call', 'Runtime slot requires reconciliation.') end
            return Validated(lease)
        end
        return Validated(Decode(
        DB.one('SELECT * FROM fs_call_leases WHERE generation_id=? AND character_id=?', generationId, characterId),
            characterId))
    end)
    return ok and result or S.Persistence.DatabaseError(result)
end

local function ValidateProjection(tx, context, horse)
    local record = S.Repository.ValidateSnapshot(tx.one(
    'SELECT * FROM fs_operations WHERE operation_id=? AND character_id=? FOR UPDATE', horse.operationId,
        context.characterId))
    if not record.ok then return record end
    if record.value.state ~= 'fulfilled' or record.value.terms.horseId ~= horse.horseId then return S.Err(
        'invalid_call', 'Fulfilled owned horse required.') end
    local row = tx.one('SELECT * FROM fs_asset_registrations WHERE operation_id=? FOR UPDATE', horse.operationId)
    local link = S.AssetRegistration.ValidateSaved(row, record.value, row and row.model_key)
    if not link.ok or link.value.state ~= 'linked' or link.value.assetId ~= horse.assetId
        or link.value.request.modelKey ~= horse.modelKey or horse.assetRevision < link.value.assetRevision then
        return S.Err('invalid_call', 'Canonical horse link changed.')
    end
    local projection = tx.one('SELECT * FROM fs_horses WHERE horse_id=? AND owner_character_id=? FOR UPDATE',
        horse.horseId, context.characterId)
    if not projection or projection.origin_operation_id ~= horse.operationId or projection.availability ~= 'stored' or projection.biological_state ~= 'alive' then
        return S.Err('horse_not_found', 'An owned stored horse is required.')
    end
    return S.Ok(true)
end

function R.Prepare(context, horse, selectionRevision, generationId)
    return Transaction(context.characterId, function(tx, stable)
        if stable.selected_horse_id ~= horse.horseId or tonumber(stable.revision) ~= selectionRevision then
            return S.Err('revision_conflict', 'Horse selection changed before call admission.')
        end
        local slot = tx.one('SELECT * FROM fs_call_slots WHERE character_id=? FOR UPDATE', context.characterId)
        if slot then
            local lease = Decode(
            tx.one('SELECT * FROM fs_call_leases WHERE generation_id=? AND character_id=? FOR UPDATE', slot
            .generation_id, context.characterId), context.characterId)
            if not lease.ok then return lease end
            if S.CallLifecycleRepository then
                local binding=S.CallLifecycleRepository.ValidateState(tx,lease.value)
                if not binding.ok then return binding end
            end
            if lease.value.state == 'released' or slot.horse_id ~= lease.value.horseId then return S.Err('invalid_call',
                    'Runtime slot requires reconciliation.') end
            if lease.value.sessionId ~= context.sessionId or lease.value.source ~= context.source then
                return S.Err('call_recovery_required',
                    'Previous-session call must be inspected/aborted before another call.')
            end
            if lease.value.state ~= 'prepared' then return S.Err('call_cleanup_required',
                    'Submission has been claimed; entity recovery must finish before another call.') end
            if lease.value.horseId ~= horse.horseId then return S.Err('horse_busy',
                    'A different call occupies the character slot.') end
            return lease
        end
        if tx.one("SELECT generation_id FROM fs_call_leases WHERE (character_id=? OR horse_id=?) AND state<>'released' LIMIT 1 FOR UPDATE",context.characterId,horse.horseId) then
            return S.Err('invalid_call','An unreleased generation requires reconciliation before another call.')
        end
        local valid = ValidateProjection(tx, context, horse); if not valid.ok then return valid end
        if tx.exec([[INSERT INTO fs_call_leases
            (generation_id,character_id,horse_id,operation_id,asset_id,model_key,session_id,source_id,selection_revision)
            VALUES (?,?,?,?,?,?,?,?,?)]], generationId, context.characterId, horse.horseId, horse.operationId, horse.assetId, horse.modelKey,
                context.sessionId, context.source, selectionRevision) ~= 1 then
            return S.Err('call_not_saved', 'Generation was not saved.')
        end
        if tx.exec('INSERT INTO fs_call_slots (character_id,horse_id,generation_id) VALUES (?,?,?)', context.characterId, horse.horseId, generationId) ~= 1 then
            return S.Err('call_not_saved', 'Runtime slot was not saved.')
        end
        return Decode(
        tx.one('SELECT * FROM fs_call_leases WHERE generation_id=? AND character_id=?', generationId, context
        .characterId), context.characterId)
    end)
end

function R.Abort(characterId, generationId)
    return Transaction(characterId, function(tx)
        local lease = Decode(
        tx.one('SELECT * FROM fs_call_leases WHERE generation_id=? AND character_id=? FOR UPDATE', generationId,
            characterId), characterId)
        if not lease.ok then return lease end
        if S.CallLifecycleRepository then
            local binding=S.CallLifecycleRepository.ValidateState(tx,lease.value)
            if not binding.ok then return binding end
        end
        if lease.value.state == 'released' then return lease end
        if lease.value.state ~= 'prepared' then return S.Err('call_cleanup_required',
                'A submitted generation cannot use unsubmitted abort.') end
        local slot = tx.one('SELECT * FROM fs_call_slots WHERE character_id=? FOR UPDATE', characterId)
        if not slot or slot.generation_id ~= generationId or slot.horse_id ~= lease.value.horseId then return S.Err(
            'invalid_call', 'Runtime slot changed.') end
        if tx.exec("UPDATE fs_call_leases SET state='released',revision=1 WHERE generation_id=? AND character_id=? AND state='prepared' AND revision=0", generationId, characterId) ~= 1
            or tx.exec('DELETE FROM fs_call_slots WHERE character_id=? AND generation_id=?', characterId, generationId) ~= 1 then
            return S.Err('revision_conflict', 'Call changed; transaction rolled back.')
        end
        lease.value.state, lease.value.revision = 'released', 1
        return lease
    end)
end


-- The winner alone may dispatch a native instruction in a future coordinator.
-- A replay/unknown commit MUST NOT produce a second instruction or free the slot.
function R.ClaimSubmission(context, horse, generationId)
    return Transaction(context.characterId, function(tx, stable)
        local slot = tx.one('SELECT * FROM fs_call_slots WHERE character_id=? FOR UPDATE', context.characterId)
        local lease = Decode(tx.one(
            'SELECT * FROM fs_call_leases WHERE generation_id=? AND character_id=? FOR UPDATE',
            generationId, context.characterId), context.characterId)
        if not lease.ok then return lease end
        local v = lease.value
        if S.CallLifecycleRepository then
            local binding=S.CallLifecycleRepository.ValidateState(tx,v)
            if not binding.ok then return binding end
        end
        if v.sessionId ~= context.sessionId or v.source ~= context.source then
            return S.Err('call_recovery_required', 'Submission requires the original current session.')
        end
        if v.state ~= 'prepared' then return S.Err('submission_conflict', 'Submission was already claimed or released.') end
        if not slot or slot.generation_id ~= generationId or slot.horse_id ~= v.horseId then
            return S.Err('invalid_call', 'Submission slot requires reconciliation.')
        end
        if stable.selected_horse_id ~= v.horseId or tonumber(stable.revision) ~= v.selectionRevision then
            return S.Err('revision_conflict', 'Selection changed before submission.')
        end
        if horse.horseId ~= v.horseId or horse.operationId ~= v.operationId or horse.assetId ~= v.assetId
            or horse.modelKey ~= v.modelKey then
            return S.Err('asset_changed', 'Observed horse does not match the prepared generation.')
        end
        local valid = ValidateProjection(tx, context, horse); if not valid.ok then return valid end
        if tx.exec("UPDATE fs_call_leases SET state='submitting',revision=1 WHERE generation_id=? AND character_id=? AND state='prepared' AND revision=0",
            generationId, context.characterId) ~= 1 then
            return S.Err('revision_conflict', 'Submission claim changed; no native instruction is authorized.')
        end
        v.state, v.revision = 'submitting', 1
        return lease
    end)
end


-- Internal transaction boundary for entity lifecycle persistence. No external
-- calls/native operations may run in body while these SQL locks are held.
function R.WithLease(characterId, generationId, body)
    if not S.Operations.IsUuid(characterId) or not S.Operations.IsUuid(generationId) then
        return S.Err('invalid_input','Character and generation UUIDs required.')
    end
    characterId,generationId=characterId:lower(),generationId:lower()
    local previous=R.Get(characterId,generationId); if not previous.ok then return previous end
    return Transaction(characterId, function(tx)
        local slot=tx.one('SELECT * FROM fs_call_slots WHERE character_id=? FOR UPDATE',characterId)
        local lease=Decode(tx.one('SELECT * FROM fs_call_leases WHERE generation_id=? AND character_id=? FOR UPDATE',
            generationId,characterId),characterId)
        if not lease.ok then return lease end
        if lease.value.state~='released' and (not slot or slot.generation_id~=generationId
            or slot.horse_id~=lease.value.horseId) then
            return S.Err('invalid_call','Lifecycle slot requires reconciliation.')
        end
        return body(tx,lease.value,slot)
    end)
end
