-- Internal repository only. No player route, Inventory mutation, condition
-- policy defaults or native projection. Callers must supply fresh authority.
Stables.CareRepository={}
local R,S,C=Stables.CareRepository,Stables,Stables.CareOperations
local everCare=true -- fail closed until startup scan completes
local function Bad() return S.Err('invalid_care','Stored care evidence requires reconciliation.') end
local function Identity(v) return S.Operations.IsUuid(v) and v==v:lower() end
local function Condition(row)
    if not row then return S.Err('condition_uninitialized','Explicit server policy initialization is required.') end
    local c={horseId=row.horse_id,healthCore=tonumber(row.health_core),staminaCore=tonumber(row.stamina_core),
        policyRevision=tonumber(row.policy_revision),revision=tonumber(row.revision)}
    return C.ValidateCondition(c)
end
local function Decode(row,characterId)
    if not row then return S.Err('care_not_found','Care operation not found.') end
    local ok,record=pcall(json.decode,row.record_json or '')
    local valid=ok and C.Validate(record)
    if not valid or not valid.ok then return Bad() end
    local r=valid.value
    if row.operation_id~=r.terms.operationId or row.character_id~=characterId or row.character_id~=r.terms.characterId
        or row.horse_id~=r.terms.horseId or row.state~=r.state or tonumber(row.revision)~=r.revision
        or row.fingerprint~=r.fingerprint then return Bad() end
    return valid
end
local function Authority(authorize)
    if not S.IsCallable(authorize) then return S.Err('care_authority_required','Fresh care authority is required.') end
    local ok,r=pcall(authorize)
    if not ok or not S.IsResult(r) then return S.Err('care_authority_required','Care authority observation failed.') end
    return r
end
local function Transaction(characterId,authorize,body)
    if not Identity(characterId) then return S.Err('invalid_input','Canonical character UUID required.') end
    local ready=S.Foundation.RequireReady(); if not ready.ok then return ready end
    local allowed=Authority(authorize); if not allowed.ok then return allowed end
    local result
    local ok,committed=pcall(DB.transaction,function(tx)
        local stable=tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',characterId)
        if not stable or stable.character_id~=characterId then result=S.Err('character_stable_missing','Character stable is unavailable.'); return false end
        allowed=Authority(authorize); if not allowed.ok then result=allowed; return false end
        result=body(tx)
        if not result.ok then return false end
        allowed=Authority(authorize); if not allowed.ok then result=allowed; return false end
        return true
    end)
    if not ok then return S.Persistence.DatabaseError(committed) end
    if committed~=true then return result and not result.ok and result or S.Err('care_outcome_unknown','Reconcile the exact care operation before retrying.') end
    return result
end
local function Horse(tx,id,characterId,stored)
    local row=tx.one('SELECT * FROM fs_horses WHERE horse_id=? AND owner_character_id=? FOR UPDATE',id,characterId)
    if not row or row.horse_id~=id or row.owner_character_id~=characterId or row.biological_state~='alive'
        or (stored and row.availability~='stored') then return S.Err('horse_not_found','An unchanged owned living horse is required.') end
    return S.Ok(row)
end
local function Save(tx,old,nextRecord)
    return tx.exec([[UPDATE fs_care_operations SET state=?,revision=?,record_json=?
        WHERE operation_id=? AND character_id=? AND state=? AND revision=?]],nextRecord.state,nextRecord.revision,json.encode(nextRecord),
        old.terms.operationId,old.terms.characterId,old.state,old.revision)==1
end
function R.Start()
    local ok,n=pcall(DB.value,"SELECT COUNT(*) FROM fs_care_operations WHERE state NOT IN ('applied','cancelled')")
    n=tonumber(n)
    if not ok or not n or n%1~=0 or n<0 or n>9007199254740991 then return S.Err('care_scan_failed','Pending care scan failed.') end
    everCare=tonumber(n)>0
    return S.Ok({ok=true,enabled=false,pendingOperations=tonumber(n)})
end
-- Called while the owning character stable row is locked. The sticky marker
-- is raised BEFORE any reservation transaction; no idle care adds hot-path SQL.
function R.CheckCharacter(tx,characterId)
    if not everCare then return S.Ok(true) end
    if tx.one("SELECT operation_id FROM fs_care_operations WHERE character_id=? AND state NOT IN ('applied','cancelled') LIMIT 1 FOR UPDATE",characterId) then
        return S.Err('horse_care_busy','Resolve the pending care operation before changing horse lifecycle or selection.')
    end
    return S.Ok(true)
end
function R.Initialize(characterId,seed,authorize)
    local valid=C.ValidateCondition(seed)
    if not valid.ok or seed.revision~=0 then return Bad() end
    seed=S.Copy(seed); everCare=true
    return Transaction(characterId,authorize,function(tx)
        local horse=Horse(tx,seed.horseId,characterId,true); if not horse.ok then return horse end
        local blocked=R.CheckCharacter(tx,characterId); if not blocked.ok then return blocked end
        if tx.one('SELECT * FROM fs_call_slots WHERE character_id=? FOR UPDATE',characterId)
            or tx.one("SELECT generation_id FROM fs_call_leases WHERE horse_id=? AND state<>'released' LIMIT 1 FOR UPDATE",seed.horseId) then
            return S.Err('horse_busy','Condition initialization requires no outstanding call.')
        end
        local existing=tx.one('SELECT * FROM fs_horse_condition WHERE horse_id=? FOR UPDATE',seed.horseId)
        if existing then return S.Err('condition_already_initialized','Condition initialization never overwrites existing state.') end
        if tx.exec('INSERT INTO fs_horse_condition (horse_id,health_core,stamina_core,policy_revision,revision) VALUES (?,?,?,?,?)',
            seed.horseId,seed.healthCore,seed.staminaCore,seed.policyRevision,0)~=1 then return Bad() end
        return S.Ok(seed)
    end)
end
function R.Reserve(terms,authorize)
    if type(terms)~='table' or not Identity(terms.characterId) or not Identity(terms.operationId) or not Identity(terms.horseId) then return Bad() end
    terms=S.Copy(terms); everCare=true
    return Transaction(terms.characterId,authorize,function(tx)
        local existing=tx.one('SELECT * FROM fs_care_operations WHERE operation_id=? FOR UPDATE',terms.operationId)
        if existing then
            local decoded=Decode(existing,terms.characterId); if not decoded.ok then return decoded end
            local expected=C.New(terms,decoded.value.before)
            if not expected.ok or expected.value.fingerprint~=decoded.value.fingerprint then return S.Err('care_terms_conflict','Operation is bound to other care terms.') end
            local r=decoded.value
            local slot=tx.one('SELECT operation_id FROM fs_care_slots WHERE horse_id=? FOR UPDATE',terms.horseId)
            local effect=tx.one('SELECT * FROM fs_care_effects WHERE operation_id=? FOR UPDATE',terms.operationId)
            if r.state=='prepared' or r.state=='consumed_effect_pending' then
                if not slot or slot.operation_id~=terms.operationId or effect then return Bad() end
            else
                if slot and slot.operation_id==terms.operationId then return Bad() end
                if r.state=='applied' then
                    if not effect or effect.horse_id~=terms.horseId or tonumber(effect.condition_revision)~=r.after.revision then return Bad() end
                elseif effect then return Bad() end
            end
            return S.Ok({operation=decoded.value,replayed=true})
        end
        local blocked=R.CheckCharacter(tx,terms.characterId); if not blocked.ok then return blocked end
        local horse=Horse(tx,terms.horseId,terms.characterId,true); if not horse.ok then return horse end
        if tx.one('SELECT * FROM fs_call_slots WHERE character_id=? FOR UPDATE',terms.characterId)
            or tx.one("SELECT generation_id FROM fs_call_leases WHERE horse_id=? AND state<>'released' LIMIT 1 FOR UPDATE",terms.horseId) then
            return S.Err('horse_busy','Care foundation reservations require a stored horse with no outstanding call.')
        end
        if tx.one('SELECT operation_id FROM fs_care_slots WHERE horse_id=? FOR UPDATE',terms.horseId) then return Bad() end
        local current=Condition(tx.one('SELECT * FROM fs_horse_condition WHERE horse_id=? FOR UPDATE',terms.horseId))
        if not current.ok then return current end
        local candidate=C.New(terms,current.value); if not candidate.ok then return candidate end
        local r=candidate.value
        if tx.exec([[INSERT INTO fs_care_operations (operation_id,horse_id,character_id,fingerprint,record_json,state,revision)
            VALUES (?,?,?,?,?,?,?)]],terms.operationId,terms.horseId,terms.characterId,r.fingerprint,json.encode(r),r.state,r.revision)~=1
            or tx.exec('INSERT INTO fs_care_slots (horse_id,operation_id) VALUES (?,?)',terms.horseId,terms.operationId)~=1 then return Bad() end
        return S.Ok({operation=r,replayed=false})
    end)
end
function R.Get(operationId,characterId,authorize)
    if not Identity(operationId) then return Bad() end
    return Transaction(characterId,authorize,function(tx)
        return Decode(tx.one('SELECT * FROM fs_care_operations WHERE operation_id=? FOR UPDATE',operationId),characterId)
    end)
end
function R.CommitReceipt(operationId,characterId,receipt,authorize)
    if not Identity(operationId) then return Bad() end
    receipt=S.Copy(receipt)
    return Transaction(characterId,authorize,function(tx)
        local saved=Decode(tx.one('SELECT * FROM fs_care_operations WHERE operation_id=? FOR UPDATE',operationId),characterId)
        if not saved.ok then return saved end
        local old=saved.value
        local resolved=C.Resolve(old,receipt); if not resolved.ok then return resolved end
        local r=resolved.value.operation
        local slot=tx.one('SELECT operation_id FROM fs_care_slots WHERE horse_id=? FOR UPDATE',r.terms.horseId)
        local effect=tx.one('SELECT * FROM fs_care_effects WHERE operation_id=? FOR UPDATE',operationId)
        if old.state=='applied' or old.state=='cancelled' then
            if slot and slot.operation_id==operationId then return Bad() end
            if old.state=='applied' then
                if not effect or effect.horse_id~=r.terms.horseId or tonumber(effect.condition_revision)~=r.after.revision then return Bad() end
            elseif effect then return Bad() end
            return S.Ok({operation=old,replayed=true})
        end
        if not slot or slot.operation_id~=operationId or effect then return Bad() end
        if r.state=='consumed_effect_pending' then
            local horse=Horse(tx,r.terms.horseId,characterId,true)
            local current=Condition(tx.one('SELECT * FROM fs_horse_condition WHERE horse_id=? FOR UPDATE',r.terms.horseId))
            local applied=horse.ok and current.ok and C.Apply(r,current.value)
            if not applied or not applied.ok then
                -- Persist the consumed obligation even when its target cannot
                -- safely advance. Slot remains fenced for explicit recovery.
                if old.state=='prepared' and not Save(tx,old,r) then return Bad() end
                return S.Ok({operation=r,reconciliationRequired=true,replayed=resolved.value.replayed})
            end
            r=applied.value.operation
            if tx.exec([[UPDATE fs_horse_condition SET health_core=?,stamina_core=?,revision=?
                WHERE horse_id=? AND revision=? AND policy_revision=? AND health_core=? AND stamina_core=?]],r.after.healthCore,r.after.staminaCore,r.after.revision,
                r.terms.horseId,r.before.revision,r.before.policyRevision,r.before.healthCore,r.before.staminaCore)~=1 then return Bad() end
            if tx.exec('INSERT INTO fs_care_effects (operation_id,horse_id,condition_revision) VALUES (?,?,?)',operationId,r.terms.horseId,r.after.revision)~=1 then return Bad() end
        end
        if not Save(tx,old,r) or tx.exec('DELETE FROM fs_care_slots WHERE horse_id=? AND operation_id=?',r.terms.horseId,operationId)~=1 then return Bad() end
        return S.Ok({operation=r,replayed=false})
    end)
end
R.ValidateSaved=Decode
