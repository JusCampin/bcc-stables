-- Internal persistence only. Native evidence must come from the server-owned
-- observer, never from a client report or a saved network ID alone.
Stables.CallLifecycleRepository = {}
local L,S=Stables.CallLifecycleRepository,Stables
local function Integer(v,min,max) return type(v)=='number' and v%1==0 and v>=min and v<=max end
local function Identity(row,lease)
    if not row or row.generation_id~=lease.generationId or not S.Operations.IsUuid(row.observer_id)
        or not Integer(tonumber(row.network_id),1,2147483647)
        or tonumber(row.initial_owner)~=lease.source or tonumber(row.routing_bucket)~=0 then
        return S.Err('invalid_call_binding','Bound identity requires reconciliation.')
    end
    local expected={bound=0,cleanup_pending=1,cleared=2}
    local revision=tonumber(row.revision)
    if row.state=='reconciliation_required' then
        if revision~=1 and revision~=2 then return S.Err('invalid_call_binding','Invalid reconciliation revision.') end
        if not ({restart_lost_observation=true,identity_lost=true,submission_unknown=true,cleanup_unknown=true})[row.reason] then
            return S.Err('invalid_call_binding','Invalid reconciliation reason.')
        end
    elseif expected[row.state]==nil or expected[row.state]~=revision or row.reason~=nil then
        return S.Err('invalid_call_binding','Invalid binding state.')
    end
    return S.Ok({generationId=row.generation_id,observerId=row.observer_id,netId=tonumber(row.network_id),
        initialOwner=tonumber(row.initial_owner),bucket=0,state=row.state,revision=revision,reason=row.reason})
end
function L.ValidateState(tx,lease)
    local row=tx.one('SELECT * FROM fs_call_bindings WHERE generation_id=?',lease.generationId)
    if lease.state=='released' and lease.revision==5 then return L.RecoveryBinding(tx,lease,row) end
    if lease.state=='prepared' or lease.state=='submitting' or (lease.state=='released' and lease.revision==1)
        or (lease.state=='reconciliation_required' and lease.revision==2) then
        if row then return S.Err('invalid_call_binding','Unexpected entity binding exists.') end
        return S.Ok({unbound=true})
    end
    local binding=Identity(row,lease); if not binding.ok then return binding end
    local expected={active='bound',cleanup_pending='cleanup_pending',released='cleared',
        reconciliation_required='reconciliation_required'}
    if expected[lease.state]~=binding.value.state
        or (lease.state=='reconciliation_required' and lease.revision~=binding.value.revision+2) then
        return S.Err('invalid_call_binding','Generation and binding states disagree.')
    end
    return binding
end
local function Advance(tx,v,state)
    if tx.exec('UPDATE fs_call_leases SET state=?,revision=revision+1 WHERE generation_id=? AND character_id=? AND state=? AND revision=?',
        state,v.generationId,v.characterId,v.state,v.revision)~=1 then
        return S.Err('revision_conflict','Lifecycle generation changed; transaction rolled back.')
    end
    v.state,v.revision=state,v.revision+1
    return S.Ok(v)
end
local function Observation(identity,v)
    return type(identity)=='table' and S.Operations.IsUuid(identity.observerId)
        and Integer(identity.netId,1,2147483647) and identity.initialOwner==v.source
        and identity.bucket==0 and identity.modelKey==v.modelKey and identity.generationId==v.generationId
end
function L.Bind(context,generationId,identity)
    identity=S.Copy(identity)
    return S.CallRepository.WithLease(context.characterId,generationId,function(tx,v)
        if v.state~='submitting' then return S.Err('binding_conflict','Only an unbound submission may bind.') end
        if v.sessionId~=context.sessionId or v.source~=context.source then
            return S.Err('call_recovery_required','Binding requires the original session.')
        end
        if not Observation(identity,v) then return S.Err('invalid_call_binding','Server-observed identity required.') end
        local previous=L.ValidateState(tx,v); if not previous.ok then return previous end
        if tx.exec([[INSERT INTO fs_call_bindings
            (generation_id,observer_id,network_id,initial_owner,routing_bucket) VALUES (?,?,?,?,?)]],
            v.generationId,identity.observerId,identity.netId,identity.initialOwner,0)~=1 then
            return S.Err('binding_not_saved','Bound identity was not saved.')
        end
        return Advance(tx,v,'active')
    end)
end
function L.BeginCleanup(characterId,generationId)
    return S.CallRepository.WithLease(characterId,generationId,function(tx,v)
        local binding=L.ValidateState(tx,v); if not binding.ok then return binding end
        if v.state=='cleanup_pending' or (v.state=='released' and v.revision==4) then return S.Ok(v) end
        if v.state~='active' then return S.Err('call_reconciliation_required','Unbound or uncertain submission cannot be released.') end
        if tx.exec("UPDATE fs_call_bindings SET state='cleanup_pending',revision=1 WHERE generation_id=? AND state='bound' AND revision=0",
            generationId)~=1 then return S.Err('revision_conflict','Binding changed before cleanup.') end
        return Advance(tx,v,'cleanup_pending')
    end)
end
-- Internal commit boundary after a live observer has confirmed disappearance.
-- This method does not inspect entities or accept a client acknowledgment.
function L.FinishCleanup(characterId,generationId,evidence)
    evidence=S.Copy(evidence)
    return S.CallRepository.WithLease(characterId,generationId,function(tx,v)
        local binding=L.ValidateState(tx,v); if not binding.ok then return binding end
        local b=binding.value
        if type(evidence)~='table' or evidence.observerId~=b.observerId or evidence.netId~=b.netId
            or evidence.generationId~=generationId or evidence.disappeared~=true then
            return S.Err('cleanup_unverified','The same live observer must confirm identity disappearance.')
        end
        if v.state=='released' and v.revision==4 then return S.Ok(v) end
        if v.state~='cleanup_pending' then return S.Err('cleanup_not_pending','Persist cleanup intent before releasing.') end
        if tx.exec("UPDATE fs_call_bindings SET state='cleared',revision=2 WHERE generation_id=? AND state='cleanup_pending' AND revision=1",
            generationId)~=1 then return S.Err('revision_conflict','Binding changed during cleanup.') end
        local advanced=Advance(tx,v,'released'); if not advanced.ok then return advanced end
        if tx.exec('DELETE FROM fs_call_slots WHERE character_id=? AND generation_id=?',characterId,generationId)~=1 then
            return S.Err('revision_conflict','Exact runtime slot was not released.')
        end
        return advanced
    end)
end
function L.Reconcile(characterId,generationId,reason)
    if not ({restart_lost_observation=true,identity_lost=true,submission_unknown=true,cleanup_unknown=true})[reason] then
        return S.Err('invalid_input','Bounded reconciliation reason required.')
    end
    return S.CallRepository.WithLease(characterId,generationId,function(tx,v)
        local binding=L.ValidateState(tx,v); if not binding.ok then return binding end
        if v.state=='reconciliation_required' then return S.Ok(v) end
        if v.state~='submitting' and v.state~='active' and v.state~='cleanup_pending' then
            return S.Err('call_reconciliation_required','Only unresolved submitted generations can be fenced.')
        end
        if not binding.value.unbound and tx.exec([[UPDATE fs_call_bindings SET state='reconciliation_required',revision=revision+1,reason=?
            WHERE generation_id=? AND state=? AND revision=?]],reason,generationId,binding.value.state,binding.value.revision)~=1 then
            return S.Err('revision_conflict','Binding changed before reconciliation.')
        end
        return Advance(tx,v,'reconciliation_required')
    end)
end


-- Immutable process evidence is committed after the single-use submission
-- claim and before any native instruction. Failure retains the submitted fence.
function L.ProcessEvidence(tx,lease)
    local row=tx.one('SELECT * FROM fs_call_process_epochs WHERE generation_id=?',lease.generationId)
    if not row then return S.Ok({recorded=false}) end
    if row.generation_id~=lease.generationId or not S.Operations.IsUuid(row.process_epoch) or row.process_epoch~=row.process_epoch:lower()
        or lease.state=='prepared' or (lease.state=='released' and lease.revision==1) then
        return S.Err('invalid_process_evidence','Call process evidence is contradictory.')
    end
    return S.Ok({recorded=true,processEpoch=row.process_epoch})
end
function L.RecordProcessEpoch(context,generationId,epoch)
    if not S.Operations.IsUuid(epoch) then return S.Err('invalid_input','Server process UUID required.') end
    return S.CallRepository.WithLease(context.characterId,generationId,function(tx,v)
        if v.state~='submitting' or v.sessionId~=context.sessionId or v.source~=context.source then
            return S.Err('submission_conflict','Only the original submitted generation may record process evidence.')
        end
        local evidence=L.ProcessEvidence(tx,v); if not evidence.ok then return evidence end
        if evidence.value.recorded then
            if evidence.value.processEpoch~=epoch then return S.Err('process_epoch_conflict','Immutable process evidence changed.') end
            return S.Ok(evidence.value)
        end
        if tx.exec('INSERT INTO fs_call_process_epochs (generation_id,process_epoch) VALUES (?,?)',generationId,epoch)~=1 then
            return S.Err('process_epoch_not_saved','Process evidence was not committed.')
        end
        return S.Ok({recorded=true,processEpoch=epoch})
    end)
end


local function CanonicalUuid(v) return S.Operations.IsUuid(v) and v==v:lower() end
-- A revision-5 tombstone is valid only with its immutable process-end audit.
-- Preserve the binding identity; only its cleanup state/revision are normalized.
function L.RecoveryBinding(tx,lease,row)
    local audit=tx.one('SELECT * FROM fs_call_recoveries WHERE generation_id=?',lease.generationId)
    local epoch=L.ProcessEvidence(tx,lease); if not epoch.ok then return epoch end
    if not audit or audit.generation_id~=lease.generationId or not epoch.value.recorded
        or not CanonicalUuid(audit.original_epoch) or not CanonicalUuid(audit.resolved_epoch)
        or audit.original_epoch~=epoch.value.processEpoch or audit.original_epoch==audit.resolved_epoch
        or not Integer(tonumber(audit.prior_revision),2,4) then
        return S.Err('invalid_recovery_receipt','Process-end recovery receipt requires investigation.')
    end
    local prior=tonumber(audit.prior_revision)
    local binding
    if prior==2 then
        if row or audit.prior_reason~=nil then return S.Err('invalid_recovery_receipt','Unbound recovery evidence disagrees.') end
        binding={unbound=true}
    else
        local checked=Identity(row,lease); if not checked.ok then return checked end
        if checked.value.state~='cleared' or checked.value.revision~=2
            or not ({restart_lost_observation=true,identity_lost=true,submission_unknown=true,cleanup_unknown=true})[audit.prior_reason] then
            return S.Err('invalid_recovery_receipt','Bound recovery evidence disagrees.')
        end
        binding=checked.value
    end
    binding.recovery={kind='server_process_ended_v1',originalProcessEpoch=audit.original_epoch,
        resolvedProcessEpoch=audit.resolved_epoch,priorRevision=prior,priorReason=audit.prior_reason}
    return S.Ok(binding)
end
local function EpochCurrent(epoch)
    -- A synchronous local configuration read, not an entity/provider operation.
    return GetConvar('bcc_stables_process_epoch_v1','')==epoch
end
function L.ResolveProcessEnded(characterId,generationId,currentEpoch)
    if not S.Operations.IsUuid(characterId) or not S.Operations.IsUuid(generationId) then
        return S.Err('invalid_input','Character and generation UUIDs required.')
    end
    characterId,generationId=characterId:lower(),generationId:lower()
    if not CanonicalUuid(currentEpoch) then return S.Err('invalid_input','Current server process UUID required.') end
    return S.CallRepository.WithLease(characterId,generationId,function(tx,v)
        local binding=L.ValidateState(tx,v); if not binding.ok then return binding end
        local function View(replayed,recovery)
            return S.Ok({characterId=v.characterId,generationId=v.generationId,horseId=v.horseId,
                state='released',revision=5,replayed=replayed,recovery=S.Copy(recovery),entityMutation=false})
        end
        if not EpochCurrent(currentEpoch) then return S.Err('process_identity_lost','Current process identity changed.') end
        if v.state=='released' and v.revision==5 then return View(true,binding.value.recovery) end
        if v.state~='reconciliation_required' then
            return S.Err('recovery_not_required','Only a fenced reconciliation generation can use process-end recovery.')
        end
        local evidence=L.ProcessEvidence(tx,v); if not evidence.ok then return evidence end
        if not evidence.value.recorded then return S.Err('process_evidence_required','Original process evidence is absent; slot retained.') end
        if evidence.value.processEpoch==currentEpoch then
            return S.Err('process_still_current','Original process is still current; slot retained.')
        end
        if not EpochCurrent(currentEpoch) then return S.Err('process_identity_lost','Current process identity changed.') end
        local priorRevision=v.revision
        if tx.exec([[INSERT INTO fs_call_recoveries
            (generation_id,original_epoch,resolved_epoch,prior_revision,prior_reason) VALUES (?,?,?,?,?)]],
            generationId,evidence.value.processEpoch,currentEpoch,priorRevision,binding.value.reason)~=1 then
            return S.Err('recovery_not_saved','Process-end audit was not committed.')
        end
        if not binding.value.unbound and tx.exec([[UPDATE fs_call_bindings SET state='cleared',revision=2,reason=NULL
            WHERE generation_id=? AND state='reconciliation_required' AND revision=?]],generationId,binding.value.revision)~=1 then
            return S.Err('revision_conflict','Binding changed during process-end recovery.')
        end
        if tx.exec([[UPDATE fs_call_leases SET state='released',revision=5
            WHERE generation_id=? AND character_id=? AND state='reconciliation_required' AND revision=?]],
            generationId,characterId,priorRevision)~=1 then
            return S.Err('revision_conflict','Generation changed during process-end recovery.')
        end
        if tx.exec('DELETE FROM fs_call_slots WHERE character_id=? AND generation_id=?',characterId,generationId)~=1 then
            return S.Err('revision_conflict','Exact recovery slot was not released.')
        end
        v.state,v.revision='released',5
        local receipt=L.ValidateState(tx,v); if not receipt.ok then return receipt end
        if not EpochCurrent(currentEpoch) then return S.Err('process_identity_lost','Current process identity changed; recovery rolled back.') end
        return View(false,receipt.value.recovery)
    end)
end
