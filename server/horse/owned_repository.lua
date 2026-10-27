-- Read the existing Feather schema. No VORP tables, DDL, import or writes.
-- This returns identity/selection only; it cannot authorize a physical spawn.
Stables.OwnedRepository = {}
local R, F = Stables.OwnedRepository, Stables.Feather
function R.NormalizeName(value)
    if type(value)~='string' or #value>400 then return nil end
    local name=value:match('^%s*(.-)%s*$')
    local length=utf8.len(name)
    if not length or length<1 or length>100 or name:find('[<>~]') then return nil end
    for _,code in utf8.codes(name) do
        if code<32 or (code>=127 and code<=159) or code==0x2028 or code==0x2029 then return nil end
    end
    return name
end
local SQL = [[SELECT stable.character_id, stable.selected_horse_id, stable.revision AS selection_revision,
    horse.horse_id, horse.owner_character_id, horse.origin_operation_id, horse.biological_state,
    horse.availability, horse.revision AS projection_revision,
    operation.state AS operation_state, operation.character_id AS operation_character_id,
    operation.horse_id AS operation_horse_id,
    registration.character_id AS registration_character_id, registration.horse_id AS registration_horse_id,
    registration.state AS registration_state, registration.asset_id, registration.asset_revision,
    registration.model_key, registration.request_id, horse_condition.health_core, horse_condition.stamina_core,
    horse_condition.policy_revision, horse_condition.revision AS condition_revision
 FROM fs_character_stables stable
 LEFT JOIN fs_horses horse ON horse.horse_id=stable.selected_horse_id
 LEFT JOIN fs_operations operation ON operation.operation_id=horse.origin_operation_id
 LEFT JOIN fs_asset_registrations registration ON registration.operation_id=horse.origin_operation_id
 LEFT JOIN fs_horse_condition horse_condition ON horse_condition.horse_id=horse.horse_id
 WHERE stable.character_id=? LIMIT 1]]

local function invalid()
    return F.Error('horse_reconciliation_required', 'Saved horse identity requires reconciliation.')
end

local function read(session, horseId,includeAsset)
    local called, row
    if horseId then
        called,row=pcall(DB.one,SQL:gsub('horse.horse_id=stable.selected_horse_id','horse.horse_id=?'),horseId,session.characterId)
    else called,row=pcall(DB.one,SQL,session.characterId) end
    if not F.IsCurrent(session) then return F.Error('session_stale', 'The character session changed.') end
    if not called then return F.Error('database_unavailable', 'Saved horse selection could not be read.') end
    if row == nil then return horseId and invalid() or F.Ok({ selected = false, selectionRevision = 0 }) end
    if type(row) ~= 'table' or row.character_id ~= session.characterId
        or not F.IsRevision(tonumber(row.selection_revision)) then return invalid() end
    if not horseId and row.selected_horse_id == nil then
        return F.Ok({ selected = false, selectionRevision = tonumber(row.selection_revision) })
    end
    if not F.IsUuid(row.horse_id) or (horseId or row.selected_horse_id) ~= row.horse_id
        or row.owner_character_id ~= session.characterId or not F.IsUuid(row.origin_operation_id)
        or row.operation_state ~= 'fulfilled' or row.operation_character_id ~= session.characterId
        or row.operation_horse_id ~= row.horse_id or row.registration_state ~= 'linked'
        or row.registration_character_id ~= session.characterId or row.registration_horse_id ~= row.horse_id
        or row.request_id ~= 'stables.register:' .. row.origin_operation_id
        or not F.IsUuid(row.asset_id) or not F.IsRevision(tonumber(row.asset_revision))
        or tonumber(row.asset_revision) < 1 or not F.IsRevision(tonumber(row.projection_revision))
        or type(row.model_key) ~= 'string' or #row.model_key > 100
        or not row.model_key:match('^a_c_horse_[a-z0-9_]+$') then return invalid() end

    local result = F.Call('feather-assets', 'GetAsset', { assetId = row.asset_id })
    if not F.IsCurrent(session) then return F.Error('session_stale', 'The character session changed.') end
    if not result.ok then return result end
    local asset = result.value
    if type(asset) ~= 'table' then return invalid() end
    if asset.status == 'retired' or (type(asset.owner) == 'table'
        and (asset.owner.holderType ~= 'character' or asset.owner.holderId ~= session.characterId)) then
        return F.Error('horse_not_owned', 'The selected horse is no longer owned by this character.')
    end
    if asset.assetId ~= row.asset_id or asset.assetType ~= 'horse' or asset.status ~= 'active'
        or asset.modelKey ~= row.model_key or asset.managerResource ~= 'bcc-stables'
        or asset.provenanceType ~= 'stable_purchase' or asset.provenanceId ~= row.origin_operation_id
        or asset.metadataVersion ~= 1 or type(asset.metadata) ~= 'table'
        or asset.metadata.stablesHorseId ~= row.horse_id or type(asset.owner) ~= 'table'
        or not F.IsUuid(asset.owner.interestId) or not F.IsRevision(asset.revision)
        or asset.revision < tonumber(row.asset_revision) then return invalid() end
    if row.biological_state ~= 'alive' then
        return F.Error('horse_unavailable', 'The selected horse is not alive.')
    end
    if row.availability ~= 'stored' and row.availability ~= 'active'
        and row.availability ~= 'reconciliation_required' then return invalid() end
    local condition
    if row.condition_revision~=nil then
        local health,stamina,revision,policy=tonumber(row.health_core),tonumber(row.stamina_core),tonumber(row.condition_revision),tonumber(row.policy_revision)
        if not F.IsRevision(health) or health>100 or not F.IsRevision(stamina) or stamina>100
            or not F.IsRevision(revision) or not F.IsRevision(policy) or policy<1 then return invalid() end
        condition={healthCore=health,staminaCore=stamina,revision=revision,policyRevision=policy}
    end
    return F.Ok({ selected = row.selected_horse_id==row.horse_id, horseId = row.horse_id, assetId = row.asset_id, condition=condition,
        name=R.NormalizeName(asset.metadata.name),gender=(asset.metadata.gender=='male' or asset.metadata.gender=='female') and asset.metadata.gender or nil,_assetSnapshot=includeAsset and asset or nil,
        modelKey = row.model_key, operationId = row.origin_operation_id,
        selectionRevision = tonumber(row.selection_revision), projectionRevision = tonumber(row.projection_revision),
        assetRevision = asset.revision, availability = row.availability })
end

function R.GetSelected(source)
    local session = F.RequireSession(source)
    if not session.ok then return session end
    return read(session.value)
end

-- Internal callers retain the same captured session through admission/binding.
function R.ReadSelected(session)
    if not F.IsCurrent(session) then return F.Error('session_stale', 'The character session changed.') end
    return read(session)
end

function R.ReadOwned(session,horseId)
    if not F.IsUuid(horseId) then return F.Error('invalid_input','Horse UUID required.') end
    if not F.IsCurrent(session) then return F.Error('session_stale','The character session changed.') end
    return read(session,horseId)
end

-- Assets owns the name, revision fence and mutation receipt. Preserve every
-- unrelated metadata field; never write directly to another provider's tables.
function R.RenameOwned(session,horseId,revision,name)
    name=R.NormalizeName(name)
    if not name or not F.IsUuid(horseId) or not F.IsRevision(revision) or revision<1 then
        return F.Error('invalid_name','Use 1-100 characters without control characters, <, > or ~.')
    end
    local owned=read(session,horseId,true); if not owned.ok then return owned end
    local value=owned.value
    local asset=value._assetSnapshot;value._assetSnapshot=nil
    if value.availability~='stored' then return F.Error('horse_busy','Store the horse before renaming.') end
    if asset.metadata.name==name then return F.Ok(value) end
    if value.assetRevision~=revision then return F.Error('revision_conflict','Refresh the horse before renaming.') end
    local metadata={}
    for key,item in pairs(asset.metadata) do metadata[key]=item end
    metadata.name=name
    if not F.IsCurrent(session) then return F.Error('session_stale','Session changed.') end
    local updated=F.Call('feather-assets','UpdateAssetMetadata',{
        requestId='stables.rename:'..value.assetId..':'..revision,
        assetId=value.assetId,expectedRevision=revision,metadataVersion=asset.metadataVersion,
        metadata=metadata,reasonCode='stables.horse.rename',actorSource=session.source,
        referenceType='horse',referenceId=horseId,
    })
    if not F.IsCurrent(session) then return F.Error('rename_outcome_unknown','Session changed; refresh to check the saved name.') end
    if not updated.ok then return updated end
    local saved=updated.value
    if type(saved)~='table' or saved.assetId~=value.assetId or saved.modelKey~=value.modelKey
        or not F.IsRevision(saved.revision) or saved.revision<=revision or type(saved.metadata)~='table'
        or saved.metadata.name~=name or saved.metadata.stablesHorseId~=horseId
        or type(saved.owner)~='table' or saved.owner.holderType~='character' or saved.owner.holderId~=session.characterId then
        return F.Error('rename_outcome_unknown','Saved name reply could not be verified; refresh.')
    end
    value.name=name;value.assetRevision=saved.revision
    return F.Ok(value)
end
