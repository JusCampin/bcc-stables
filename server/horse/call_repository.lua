-- Existing fs_* schema, resource-local API only. Entity observations are supplied
-- by the server controller, never by a client RPC or a saved network ID alone.
Stables.CallRepository = {}
local R, F = Stables.CallRepository, Stables.Feather
local function fail(code, message) return F.Error(code, message) end
local function changed() return fail('call_reconciliation_required', 'Saved call identity changed; reconcile before retrying.') end
local function requireWrite(count)
    if count ~= 1 then error('Exact call write did not affect one row.', 0) end
end
local function writeBatch(tx, statements)
    local results = tx.batch(statements)
    if type(results) ~= 'table' or #results ~= #statements then error('Invalid call write results.', 0) end
    for _, result in ipairs(results) do requireWrite(type(result) == 'table' and result.affectedRows) end
end

local function transaction(characterId, body, session)
    if not F.IsUuid(characterId) then return fail('invalid_identity', 'Character UUID required.') end
    if session and not F.IsCurrent(session) then return fail('session_stale', 'The character session changed.') end
    local result
    local called, committed = pcall(DB.transaction, function(tx)
        local stable = tx.one('SELECT * FROM fs_character_stables WHERE character_id=? FOR UPDATE', characterId)
        if not stable or stable.character_id ~= characterId then
            result = fail('selection_required', 'Select an owned horse first.'); return false
        end
        if session and not F.IsCurrent(session) then
            result = fail('session_stale', 'The character session changed.'); return false
        end
        result = body(tx, stable)
        if not result.ok then return false end
        if session and not F.IsCurrent(session) then
            result = fail('session_stale', 'The character session changed.'); return false
        end
        return true
    end)
    -- An exception can include a lost commit acknowledgement. Never authorize a
    -- spawn or release on this response; inspect the same generation instead.
    if not called or (committed ~= true and (not result or result.ok)) then
        return fail('call_outcome_unknown', 'Call outcome is unknown; retain the generation for reconciliation.')
    end
    if not result.ok then return result end
    if session and not F.IsCurrent(session) then
        return fail('call_recovery_required', 'The session changed after commit; the call remains reserved.')
    end
    return result
end

local function careClear(tx, characterId)
    if tx.one([[SELECT operation_id FROM fs_care_operations WHERE character_id=?
        AND state NOT IN ('applied','cancelled') LIMIT 1 FOR UPDATE]], characterId) then
        return fail('horse_care_busy', 'Resolve pending horse care before calling another horse.')
    end
    if tx.one([[SELECT dispatch.operation_id FROM fs_call_slots slot
        INNER JOIN fs_care_targets target ON target.generation_id=slot.generation_id
        INNER JOIN fs_care_dispatches dispatch ON dispatch.operation_id=target.operation_id
        WHERE slot.character_id=? AND dispatch.state='claimed' LIMIT 1 FOR UPDATE]], characterId) then
        return fail('care_projection_busy', 'A condition delivery is still unresolved.')
    end
    return F.Ok(true)
end

local function load(tx, characterId, generationId)
    local rows = tx.batch({
        DB.stmt('SELECT * FROM fs_call_slots WHERE character_id=? FOR UPDATE', characterId),
        DB.stmt('SELECT * FROM fs_call_leases WHERE generation_id=? AND character_id=? FOR UPDATE', generationId, characterId),
        DB.stmt('SELECT * FROM fs_call_bindings WHERE generation_id=? FOR UPDATE', generationId),
        DB.stmt('SELECT process_epoch FROM fs_call_process_epochs WHERE generation_id=?', generationId)
    })
    if type(rows) ~= 'table' or #rows ~= 4 then return nil, nil, changed() end
    for _, result in ipairs(rows) do
        if type(result) ~= 'table' or #result > 1 then return nil, nil, changed() end
    end
    local slot, v, b, epoch = rows[1][1], rows[2][1], rows[3][1], rows[4][1]
    if not v then return nil, nil, fail('call_not_found', 'Call generation was not found.') end
    if v.character_id ~= characterId or v.generation_id ~= generationId or not F.IsUuid(v.horse_id)
        or not F.IsUuid(v.operation_id) or not F.IsUuid(v.asset_id) or not F.IsUuid(v.session_id)
        or not F.IsRevision(tonumber(v.selection_revision)) or not F.IsRevision(tonumber(v.revision))
        or not tonumber(v.source_id) or tonumber(v.source_id) < 1 or tonumber(v.source_id) % 1 ~= 0
        or type(v.model_key) ~= 'string' or not v.model_key:match('^a_c_horse_[a-z0-9_]+$') then
        return nil, nil, changed()
    end
    if not epoch or not F.IsUuid(epoch.process_epoch) then return nil, nil, changed() end
    if v.state ~= 'released' and (not slot or slot.generation_id ~= generationId or slot.horse_id ~= v.horse_id) then
        return nil, nil, changed()
    end
    local revision = tonumber(v.revision)
    if (v.state == 'submitting' and revision == 1 or v.state == 'reconciliation_required' and revision == 2)
        and b == nil then return v, nil, nil, epoch.process_epoch end
    if v.state == 'released' and revision == 5 then
        local audit = tx.one('SELECT * FROM fs_call_recoveries WHERE generation_id=?',generationId)
        if not audit or audit.original_epoch~=epoch.process_epoch or not F.IsUuid(audit.resolved_epoch)
            or audit.resolved_epoch==audit.original_epoch then return nil,nil,changed() end
        local prior=tonumber(audit.prior_revision)
        if prior==2 and b==nil and audit.prior_reason==nil then return v,nil,nil,epoch.process_epoch end
        if (prior==3 or prior==4) and b and b.state=='cleared' and tonumber(b.revision)==2 and b.reason==nil
            and ({restart_lost_observation=true,identity_lost=true,submission_unknown=true,cleanup_unknown=true})[audit.prior_reason]
            and b.generation_id==generationId and F.IsUuid(b.observer_id)
            and tonumber(b.initial_owner)==tonumber(v.source_id) and tonumber(b.routing_bucket)==0
            and tonumber(b.network_id) and tonumber(b.network_id)>0 and tonumber(b.network_id)<=2147483647
            and tonumber(b.network_id)%1==0 then return v,b,nil,epoch.process_epoch end
        return nil,nil,changed()
    end
    local expected = {active={2,'bound',0}, cleanup_pending={3,'cleanup_pending',1}, released={4,'cleared',2}}
    local state = expected[v.state]
    local recon = v.state == 'reconciliation_required' and b and b.state == 'reconciliation_required'
        and (tonumber(b.revision) == 1 or tonumber(b.revision) == 2)
        and revision == tonumber(b.revision)+2
        and ({restart_lost_observation=true,identity_lost=true,submission_unknown=true,cleanup_unknown=true})[b.reason]
    if (not recon and (not state or revision ~= state[1])) or not b or b.generation_id ~= generationId
        or not F.IsUuid(b.observer_id) or tonumber(b.initial_owner) ~= tonumber(v.source_id)
        or tonumber(b.routing_bucket) ~= 0 or not tonumber(b.network_id) or tonumber(b.network_id) < 1
        or tonumber(b.network_id) > 2147483647 or tonumber(b.network_id) % 1 ~= 0
        or (not recon and (b.state ~= state[2] or tonumber(b.revision) ~= state[3] or b.reason ~= nil)) then
        return nil, nil, changed()
    end
    return v, b, nil, epoch.process_epoch
end

local function view(v)
    return F.Ok({ generationId=v.generation_id, horseId=v.horse_id, state=v.state, revision=tonumber(v.revision) })
end

local function project(tx, v, target, reason)
    local horse = tx.one('SELECT * FROM fs_horses WHERE horse_id=? AND owner_character_id=? FOR UPDATE', v.horse_id, v.character_id)
    local from = target == 'active' and 'stored' or 'active'
    local revision = horse and tonumber(horse.revision)
    if not horse or horse.horse_id ~= v.horse_id or horse.origin_operation_id ~= v.operation_id
        or horse.owner_character_id ~= v.character_id or horse.availability ~= from
        or (target == 'active' and horse.biological_state ~= 'alive')
        or not F.IsRevision(revision) or revision == 9007199254740991 then return changed() end
    writeBatch(tx, {DB.stmt([[INSERT INTO fs_horse_runtime_events
        (event_id,horse_id,generation_id,from_availability,to_availability,prior_revision,revision,reason)
        VALUES (?,?,?,?,?,?,?,?)]], 'stables.runtime:'..v.generation_id..':'..target, v.horse_id,
        v.generation_id, from, target, revision, revision+1, reason or (target=='active' and 'bound' or 'observed_cleanup')),
        DB.stmt([[UPDATE fs_horses SET availability=?,revision=revision+1
        WHERE horse_id=? AND owner_character_id=? AND availability=? AND revision=?]], target,
        v.horse_id, v.character_id, from, revision)})
    return F.Ok(true)
end

function R.Reserve(session, horse, generationId, processEpoch)
    if type(session) ~= 'table' or not F.IsUuid(session.characterId) or not F.IsUuid(session.sessionId)
        or type(session.source) ~= 'number' or session.source < 1 or session.source % 1 ~= 0
        or type(horse) ~= 'table' or horse.selected ~= true or not F.IsUuid(horse.horseId)
        or not F.IsUuid(horse.assetId) or not F.IsUuid(horse.operationId)
        or not F.IsRevision(horse.selectionRevision) or not F.IsRevision(horse.projectionRevision)
        or not F.IsUuid(generationId) or not F.IsUuid(processEpoch) then
        return fail('invalid_identity', 'Captured character, horse and process identities are required.')
    end
    return transaction(session.characterId, function(tx, stable)
        if stable.selected_horse_id ~= horse.horseId or tonumber(stable.revision) ~= horse.selectionRevision then
            return fail('selection_changed', 'Horse selection changed before calling.')
        end
        local allowed = careClear(tx, session.characterId); if not allowed.ok then return allowed end
        if tx.one('SELECT generation_id FROM fs_call_slots WHERE character_id=? OR horse_id=? LIMIT 1 FOR UPDATE',
            session.characterId, horse.horseId) or tx.one([[SELECT generation_id FROM fs_call_leases
            WHERE (character_id=? OR horse_id=?) AND state<>'released' LIMIT 1 FOR UPDATE]], session.characterId, horse.horseId) then
            return fail('horse_busy', 'An existing call must be stored or reconciled first.')
        end
        local saved = tx.one([[SELECT horse.*, registration.asset_id, registration.model_key,
            registration.state AS registration_state, registration.character_id AS registration_character,
            registration.horse_id AS registration_horse, operation.state AS operation_state,
            operation.character_id AS operation_character, operation.horse_id AS operation_horse
            FROM fs_horses horse INNER JOIN fs_asset_registrations registration ON registration.operation_id=horse.origin_operation_id
            INNER JOIN fs_operations operation ON operation.operation_id=horse.origin_operation_id
            WHERE horse.horse_id=? AND horse.owner_character_id=? FOR UPDATE]], horse.horseId, session.characterId)
        if not saved or saved.availability ~= 'stored' or saved.biological_state ~= 'alive'
            or saved.origin_operation_id ~= horse.operationId or tonumber(saved.revision) ~= horse.projectionRevision
            or saved.asset_id ~= horse.assetId or saved.model_key ~= horse.modelKey
            or saved.registration_state ~= 'linked' or saved.registration_character ~= saved.operation_character
            or saved.registration_horse ~= horse.horseId or saved.operation_state ~= 'fulfilled'
            or not F.IsUuid(saved.operation_character) or saved.operation_horse ~= horse.horseId then return changed() end
        writeBatch(tx, {DB.stmt([[INSERT INTO fs_call_leases
            (generation_id,character_id,horse_id,operation_id,asset_id,model_key,session_id,source_id,selection_revision,state,revision)
            VALUES (?,?,?,?,?,?,?,?,?,'submitting',1)]], generationId, session.characterId, horse.horseId,
            horse.operationId, horse.assetId, horse.modelKey, session.sessionId, session.source, horse.selectionRevision),
            DB.stmt('INSERT INTO fs_call_slots (character_id,horse_id,generation_id) VALUES (?,?,?)', session.characterId, horse.horseId, generationId),
            DB.stmt('INSERT INTO fs_call_process_epochs (generation_id,process_epoch) VALUES (?,?)', generationId, processEpoch)})
        return F.Ok({generationId=generationId, horseId=horse.horseId, state='submitting', revision=1})
    end, session)
end

function R.Bind(session, generationId, observation, cleanupOnly, initializeStats)
    if type(session) ~= 'table' or not F.IsUuid(generationId) or type(observation) ~= 'table'
        or not F.IsUuid(observation.observerId) or observation.generationId ~= generationId
        or type(observation.netId) ~= 'number' or observation.netId < 1 or observation.netId > 2147483647
        or observation.netId % 1 ~= 0 or observation.initialOwner ~= session.source or observation.bucket ~= 0 then
        return fail('invalid_observation', 'A matching server observation is required.')
    end
    return transaction(session.characterId, function(tx, stable)
        local v, _, err = load(tx, session.characterId, generationId); if err then return err end
        if v.state ~= 'submitting' then return fail('binding_conflict', 'This call has already been bound or ended.') end
        if v.session_id ~= session.sessionId or tonumber(v.source_id) ~= session.source
            or (not cleanupOnly and (stable.selected_horse_id ~= v.horse_id or tonumber(stable.revision) ~= tonumber(v.selection_revision)))
            or observation.modelKey ~= v.model_key then return changed() end
        if not cleanupOnly then
            local allowed = careClear(tx, session.characterId); if not allowed.ok then return allowed end
        end
        local projected = project(tx, v, 'active'); if not projected.ok then return projected end
        local bonding
        if initializeStats and not cleanupOnly and Stables.Bonding and Stables.Bonding.StatRewardsEnabled() then
            local saved=Stables.Bonding.EnsureStats(tx,v.horse_id,v.model_key)
            if not saved.ok then return saved end;bonding=saved.value
        end
        writeBatch(tx, {DB.stmt([[INSERT INTO fs_call_bindings
            (generation_id,observer_id,network_id,initial_owner,routing_bucket) VALUES (?,?,?,?,0)]],
            generationId, observation.observerId, observation.netId, session.source),
            DB.stmt("UPDATE fs_call_leases SET state='active',revision=2 WHERE generation_id=? AND state='submitting' AND revision=1", generationId)})
        v.state, v.revision = 'active', 2
        local result=view(v);result.value.bonding=bonding;return result
    end, not cleanupOnly and session or nil)
end

function R.Inspect(characterId, generationId)
    if not F.IsUuid(generationId) then return fail('invalid_identity', 'Generation UUID required.') end
    return transaction(characterId, function(tx)
        local v, _, err = load(tx, characterId, generationId)
        return err or view(v)
    end)
end

function R.Reconcile(characterId, generationId, reason)
    if not F.IsUuid(generationId) or not ({restart_lost_observation=true,identity_lost=true,
        submission_unknown=true,cleanup_unknown=true})[reason] then return changed() end
    return transaction(characterId, function(tx)
        local v, b, err = load(tx, characterId, generationId); if err then return err end
        if v.state == 'reconciliation_required' then return view(v) end
        if v.state ~= 'submitting' and v.state ~= 'active' and v.state ~= 'cleanup_pending' then return changed() end
        tx.exec([[UPDATE fs_care_targets SET interrupted=1,interrupt_reason='reconciliation',revision=1
            WHERE generation_id=? AND interrupted=0 AND revision=0 AND operation_id IN
            (SELECT operation_id FROM fs_care_operations WHERE character_id=? AND state NOT IN ('applied','cancelled'))]], generationId, characterId)
        if b then requireWrite(tx.exec([[UPDATE fs_call_bindings SET state='reconciliation_required',revision=revision+1,reason=?
            WHERE generation_id=? AND state=? AND revision=?]], reason, generationId, b.state, tonumber(b.revision))) end
        requireWrite(tx.exec([[UPDATE fs_call_leases SET state='reconciliation_required',revision=revision+1
            WHERE generation_id=? AND state=? AND revision=?]], generationId, v.state, tonumber(v.revision)))
        v.state, v.revision = 'reconciliation_required', tonumber(v.revision)+1
        return view(v)
    end)
end

-- Only a different server process can resolve lost observation without a live
-- disappearance proof. Preserve the original epoch and an immutable audit.
function R.RecoverProcessEnded(characterId, generationId, currentEpoch)
    if not F.IsUuid(generationId) or not F.IsUuid(currentEpoch) then return changed() end
    return transaction(characterId, function(tx)
        local v, b, err, originalEpoch = load(tx, characterId, generationId); if err then return err end
        if v.state=='released' and tonumber(v.revision)==5 then return view(v) end
        if v.state ~= 'reconciliation_required' then return changed() end
        if GetConvar('bcc_stables_process_epoch_v1','') ~= currentEpoch then return fail('process_identity_lost', 'Current process changed.') end
        if originalEpoch == currentEpoch then return fail('process_still_current', 'Original server process is still current; call retained.') end
        if b then
            local projected = project(tx, v, 'stored', 'process_ended'); if not projected.ok then return projected end
            requireWrite(tx.exec([[UPDATE fs_call_bindings SET state='cleared',revision=2,reason=NULL
                WHERE generation_id=? AND state='reconciliation_required' AND revision=?]], generationId, tonumber(b.revision)))
        end
        writeBatch(tx, {
            DB.stmt([[INSERT INTO fs_call_recoveries (generation_id,original_epoch,resolved_epoch,prior_revision,prior_reason)
                VALUES (?,?,?,?,?)]], generationId, originalEpoch, currentEpoch, tonumber(v.revision), b and b.reason),
            DB.stmt([[UPDATE fs_call_leases SET state='released',revision=5 WHERE generation_id=?
                AND state='reconciliation_required' AND revision=?]], generationId, tonumber(v.revision)),
            DB.stmt('DELETE FROM fs_call_slots WHERE character_id=? AND generation_id=?', characterId, generationId)
        })
        if GetConvar('bcc_stables_process_epoch_v1','') ~= currentEpoch then error('Process changed during recovery.', 0) end
        v.state, v.revision = 'released', 5
        return view(v)
    end)
end

function R.BeginCleanup(characterId, generationId)
    if not F.IsUuid(generationId) then return fail('invalid_identity', 'Generation UUID required.') end
    return transaction(characterId, function(tx)
        local v, _, err = load(tx, characterId, generationId); if err then return err end
        if v.state == 'cleanup_pending' or v.state == 'released' then return view(v) end
        if v.state ~= 'active' then return changed() end
        -- Preserve pending care operations/receipts; prevent their native result
        -- from being delivered to a horse whose cleanup has begun.
        tx.exec([[UPDATE fs_care_targets SET interrupted=1,interrupt_reason='cleanup',revision=1
            WHERE generation_id=? AND interrupted=0 AND revision=0 AND operation_id IN
            (SELECT operation_id FROM fs_care_operations WHERE character_id=? AND state NOT IN ('applied','cancelled'))]],
            generationId, characterId)
        requireWrite(tx.exec("UPDATE fs_call_bindings SET state='cleanup_pending',revision=1 WHERE generation_id=? AND state='bound' AND revision=0", generationId))
        requireWrite(tx.exec("UPDATE fs_call_leases SET state='cleanup_pending',revision=3 WHERE generation_id=? AND state='active' AND revision=2", generationId))
        v.state, v.revision = 'cleanup_pending', 3
        return view(v)
    end)
end

function R.FinishCleanup(characterId, generationId, observation)
    if not F.IsUuid(generationId) or type(observation) ~= 'table' or observation.disappeared ~= true
        or observation.generationId ~= generationId then return fail('cleanup_unverified', 'Confirmed disappearance is required.') end
    return transaction(characterId, function(tx)
        local v, b, err = load(tx, characterId, generationId); if err then return err end
        if not b or b.observer_id ~= observation.observerId or tonumber(b.network_id) ~= observation.netId then
            return fail('cleanup_unverified', 'Disappearance must match the original server observation.')
        end
        if v.state == 'released' then return view(v) end
        if v.state ~= 'cleanup_pending' then return fail('cleanup_not_pending', 'Store intent must be saved first.') end
        local projected = project(tx, v, 'stored'); if not projected.ok then return projected end
        writeBatch(tx, {
            DB.stmt("UPDATE fs_call_bindings SET state='cleared',revision=2 WHERE generation_id=? AND state='cleanup_pending' AND revision=1", generationId),
            DB.stmt("UPDATE fs_call_leases SET state='released',revision=4 WHERE generation_id=? AND state='cleanup_pending' AND revision=3", generationId),
            DB.stmt('DELETE FROM fs_call_slots WHERE character_id=? AND generation_id=?', characterId, generationId)})
        v.state, v.revision = 'released', 4
        return view(v)
    end)
end
