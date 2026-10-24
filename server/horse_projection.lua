-- Current local state only. Canonical identity and ownership remain in Assets.
Stables.HorseProjection={}
local P,S=Stables.HorseProjection,Stables
local MAX=9007199254740991
local function Integer(v) return type(v)=='number' and v%1==0 and v>=0 and v<=MAX end
local function Bad() return S.Err('invalid_projection','Horse lifecycle projection requires reconciliation.') end
local function Lease(tx,id,row,identity,rows)
    if not S.CallRepository or not S.CallLifecycleRepository or not S.Operations.IsUuid(id) then return Bad() end
    if type(rows)~='table' or #rows~=2 or type(rows[1])~='table' or #rows[1]>1
        or type(rows[2])~='table' or #rows[2]>1 then return Bad() end
    local saved=S.CallRepository.ValidateSaved(rows[1][1],row.owner_character_id)
    if not saved.ok then return saved end
    local v=saved.value
    if v.horseId~=row.horse_id or v.operationId~=row.origin_operation_id
        or (identity and (v.assetId~=identity.assetId or v.modelKey~=identity.modelKey)) then return Bad() end
    local binding=S.CallLifecycleRepository.ValidateSavedState(tx,v,rows[2][1]); if not binding.ok then return binding end
    return saved
end
local function Physical(v)
    return v.state=='active' or v.state=='cleanup_pending'
        or (v.state=='reconciliation_required' and v.revision>=3)
end
function P.Validate(tx,row,identity)
    if type(row)~='table' or not S.Operations.IsUuid(row.horse_id)
        or not S.Operations.IsUuid(row.owner_character_id) or not S.Operations.IsUuid(row.origin_operation_id)
        or row.biological_state~='alive' or (row.availability~='stored' and row.availability~='active') then return Bad() end
    local revision=tonumber(row.revision)
    if not Integer(revision) or (row.availability=='active')~=(revision%2==1) then return Bad() end
    -- Reuse only within this validation snapshot. Event and slot may refer to
    -- the same generation; each invocation still performs fresh database reads.
    local leases,event,slot={},nil,nil
    local loaded,raw=false,{}
    local function ReadLease(id)
        if not S.Operations.IsUuid(id) then return Bad() end
        if not loaded then
            loaded=true
            local ids,seen={},{}
            for _,candidate in ipairs({event and event.generation_id or false,
                slot and slot.horse_id==row.horse_id and slot.generation_id or false}) do
                if S.Operations.IsUuid(candidate) and not seen[candidate] then
                    seen[candidate]=true; ids[#ids+1]=candidate
                end
            end
            if not seen[id] then ids[#ids+1]=id end
            if #ids>2 then return Bad() end
            local statements={}
            for _,key in ipairs(ids) do
                statements[#statements+1]=DB.stmt('SELECT * FROM fs_call_leases WHERE generation_id=? AND character_id=?',key,row.owner_character_id)
                statements[#statements+1]=DB.stmt('SELECT * FROM fs_call_bindings WHERE generation_id=?',key)
            end
            local rows=tx.batch(statements)
            if type(rows)~='table' or #rows~=#statements then return Bad() end
            for i=1,#statements do
                if type(rows[i])~='table' or #rows[i]>1 then return Bad() end
            end
            for i,key in ipairs(ids) do raw[key]={rows[2*i-1],rows[2*i]} end
        end
        if not raw[id] then return Bad() end
        if not leases[id] then leases[id]=Lease(tx,id,row,identity,raw[id]) end
        return leases[id]
    end
    -- Both keys are already known and independent. One bridge call, same
    -- transaction/snapshot; Lua still validates every returned lifecycle fact.
    local reads=tx.batch({
        DB.stmt('SELECT * FROM fs_horse_runtime_events WHERE horse_id=? ORDER BY revision DESC LIMIT 1',row.horse_id),
        DB.stmt('SELECT * FROM fs_call_slots WHERE character_id=?',row.owner_character_id)
    })
    if type(reads)~='table' or #reads~=2 or type(reads[1])~='table' or #reads[1]>1
        or type(reads[2])~='table' or #reads[2]>1 then return Bad() end
    event,slot=reads[1][1],reads[2][1]
    if revision==0 then
        if event or row.availability~='stored' then return Bad() end
    else
        if not event or event.horse_id~=row.horse_id or not S.Operations.IsUuid(event.generation_id)
            or tonumber(event.revision)~=revision or tonumber(event.prior_revision)~=revision-1
            or event.to_availability~=row.availability
            or event.from_availability~=(row.availability=='active' and 'stored' or 'active')
            or event.event_id~=('stables.runtime:'..event.generation_id..':'..row.availability) then return Bad() end
        local saved=ReadLease(event.generation_id); if not saved.ok then return saved end
        local v=saved.value
        if row.availability=='active' then
            if event.reason~='bound' or not Physical(v) then return Bad() end
        elseif not (v.state=='released' and ((event.reason=='observed_cleanup' and v.revision==4)
            or (event.reason=='process_ended' and v.revision==5))) then return Bad() end
    end
    if slot and slot.horse_id==row.horse_id then
        local saved=ReadLease(slot.generation_id); if not saved.ok then return saved end
        local v=saved.value
        if v.state=='released' or Physical(v)~=(row.availability=='active')
            or (row.availability=='active' and event.generation_id~=v.generationId) then return Bad() end
    elseif row.availability=='active' then return Bad()
    elseif tx.one("SELECT generation_id FROM fs_call_leases WHERE horse_id=? AND state<>'released' LIMIT 1",row.horse_id) then
        return Bad()
    end
    return S.Ok({availability=row.availability,projectionRevision=revision,
        generationId=row.availability=='active' and event.generation_id or nil})
end
local function Transition(tx,v,target,reason)
    local row=tx.one('SELECT * FROM fs_horses WHERE horse_id=? AND owner_character_id=? FOR UPDATE',v.horseId,v.characterId)
    local checked=P.Validate(tx,row,{assetId=v.assetId,modelKey=v.modelKey}); if not checked.ok then return checked end
    local from=target=='active' and 'stored' or 'active'
    if row.availability~=from then return Bad() end
    local revision=checked.value.projectionRevision
    if revision==MAX then return S.Err('revision_exhausted','Horse projection revision is exhausted.') end
    local id='stables.runtime:'..v.generationId..':'..target
    local writes=tx.batch({
        DB.stmt([[INSERT INTO fs_horse_runtime_events
            (event_id,horse_id,generation_id,from_availability,to_availability,prior_revision,revision,reason)
            VALUES (?,?,?,?,?,?,?,?)]],id,v.horseId,v.generationId,from,target,revision,revision+1,reason),
        DB.stmt([[UPDATE fs_horses SET availability=?,revision=revision+1
            WHERE horse_id=? AND owner_character_id=? AND availability=? AND revision=?]],
            target,v.horseId,v.characterId,from,revision)
    })
    if type(writes)~='table' or #writes~=2 or type(writes[1])~='table' or writes[1].affectedRows~=1 then
        return S.Err('projection_not_saved','Lifecycle receipt was not saved.')
    end
    if type(writes[2])~='table' or writes[2].affectedRows~=1 then
        return S.Err('revision_conflict','Horse projection changed; lifecycle transaction rolled back.')
    end
    return S.Ok({availability=target,projectionRevision=revision+1})
end
function P.Activate(tx,v)
    if v.state~='submitting' then return Bad() end
    return Transition(tx,v,'active','bound')
end
function P.Store(tx,v,reason)
    if not ((reason=='observed_cleanup' and v.state=='cleanup_pending')
        or (reason=='process_ended' and v.state=='reconciliation_required' and v.revision>=3)) then return Bad() end
    return Transition(tx,v,'stored',reason)
end
