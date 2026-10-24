-- Read-only view of local projections backed by current canonical Assets facts.
Stables.OwnedHorses = {}
local H, S = Stables.OwnedHorses, Stables
local PAGE = 10
local function Payload(p, list)
    if type(p) ~= 'table' then return false end
    local key = list and 'afterHorseId' or 'horseId'
    for field in pairs(p) do if field ~= key then return false end end
    return (list and p[key] == nil) or S.Operations.IsUuid(p[key])
end
function H.Start() return S.Ok({ ok = true, pageSize = PAGE, selectionAvailable = StablesConfig.horseSelection == true, gameplayAvailable = false }) end

local function Query(method, sql, ...)
    local ok, result = pcall(DB[method], sql, ...)
    if not ok then return S.Persistence.DatabaseError(result) end
    return S.Ok(result)
end
local function Resolve(row, characterId)
    if type(row) ~= 'table' or not S.Operations.IsUuid(row.horse_id) or not S.Operations.IsUuid(row.origin_operation_id) then
        return S.Err('invalid_projection', 'Stored horse identity is invalid.')
    end
    local snapshot=S.OwnedSnapshot and S.OwnedSnapshot.Get(row.origin_operation_id,characterId)
        or S.Err('owned_snapshot_unavailable','Owned snapshot reader is missing.')
    if not snapshot.ok then return snapshot end
    local saved,link=snapshot.value.horse,snapshot.value.registration
    if saved.horseId ~= row.horse_id or saved.operationId ~= row.origin_operation_id then
        return S.Err('invalid_projection', 'Horse and purchase identities disagree.')
    end
    if link.state ~= 'linked' or link.assetId ~= saved.assetId then
        return S.Err('invalid_projection', 'Canonical horse link disagrees with stored projection.')
    end
    local current = S.Assets.ReadHorse(link.assetId); if not current.ok then return current end
    local asset = current.value
    if type(asset) == 'table' and (asset.status == 'retired' or (asset.status == 'active' and type(asset.owner) == 'table'
            and (asset.owner.holderType ~= 'character' or asset.owner.holderId ~= characterId))) then
        return S.Err('horse_not_found', 'Horse is not available to this character.')
    end
    if not S.AssetRegistration.Matches(asset, link.request) or asset.assetId ~= link.assetId
        or asset.revision < link.assetRevision then
        return S.Err('asset_changed', 'Canonical horse facts require reconciliation.')
    end
    -- Catalogue/config changes cannot rewrite this horse's saved model/identity.
    return S.Ok({
        horseId = row.horse_id,
        operationId = row.origin_operation_id,
        assetId = asset.assetId,
        assetRevision = asset.revision,
        modelKey = asset.modelKey,
        availability = saved.availability,
        projectionRevision = saved.projectionRevision,
        gameplayAvailable = false
    })
end
local function Request(list, p, source, context, knownOperationId)
    if not Payload(p, list) then return S.Err('invalid_input',
            list and 'Only optional afterHorseId is accepted.' or 'Only horseId is accepted.') end
    local checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    context = S.Copy(context); p = S.Copy(p)
    local characterId = context.characterId:lower()
    local result
    if list then
        local cursor = p.afterHorseId and p.afterHorseId:lower()
        local rows
        if cursor then
            rows = Query('query', [[SELECT horse_id,origin_operation_id FROM fs_horses
            WHERE owner_character_id=? AND horse_id>? ORDER BY horse_id LIMIT 11]], characterId, cursor)
        else
            rows = Query('query', [[SELECT horse_id,origin_operation_id FROM fs_horses
            WHERE owner_character_id=? ORDER BY horse_id LIMIT 11]], characterId)
        end
        if not rows.ok then return rows end
        if type(rows.value) ~= 'table' or #rows.value > PAGE + 1 then return S.Err('invalid_projection',
                'Invalid horse page.') end
        local items, previous = {}, cursor
        for index, row in ipairs(rows.value) do
            if type(row) ~= 'table' or not S.Operations.IsUuid(row.horse_id) or (previous and row.horse_id <= previous) then
                return S.Err('invalid_projection', 'Horse page order/identity is invalid.')
            end
            if index > PAGE then break end
            previous = row.horse_id
            checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
            local item = Resolve(row, characterId)
            if item.ok then
                items[#items + 1] = item.value
            elseif item.code ~= 'horse_not_found' then
                return item
            end
        end
        result = S.Ok({
            items = items,
            nextCursor = #rows.value > PAGE and previous or nil,
            pageSize = PAGE,
            selectionAvailable = S.Selection ~= nil and S.Selection.Enabled(),
            gameplayAvailable = false
        })
    else
        local row
        if knownOperationId then
            -- Internal lease identity only selects the validation target. Resolve
            -- still checks the scoped purchase/projection and fresh Assets owner.
            row=S.Ok({horse_id=p.horseId:lower(),origin_operation_id=knownOperationId})
        else
            row = Query('one', [[SELECT horse_id,origin_operation_id FROM fs_horses
                WHERE horse_id=? AND owner_character_id=?]], p.horseId:lower(), characterId)
        end
        if not row.ok then return row end
        if not row.value then
            result = S.Err('horse_not_found', 'Horse is not available to this character.')
        else
            result = Resolve(row.value, characterId)
        end
    end
    checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    return result
end
function H.List(p, source, context) return Request(true, p, source, context) end

function H.Get(p, source, context) return Request(false, p, source, context) end

-- Resource-internal only; never installed as RPC/export or used as ownership evidence.
function H.GetKnown(horseId,operationId,source,context)
    if not S.Operations.IsUuid(operationId) then return S.Err('invalid_input','Known purchase UUID required.') end
    return Request(false,{horseId=horseId},source,context,operationId:lower())
end

function H.Install()
    for _, entry in ipairs({ { 'list', H.List, true }, { 'get', H.Get, false } }) do
        local list = entry[3]
        local result = S.Core.Call('RegisterRpc', 'stables.horses.' .. entry[1] .. '.v1', entry[2], {
            contract = 1,
            direction = 'client_to_server',
            requireCharacter = true,
            windowMs = 2000,
            maxCalls = 2,
            maxPayloadBytes = 128,
            maxDepth = 2,
            maxNodes = 4,
            validatePayload = function(p) return Payload(p, list) end
        })
        if not result.ok then return result end
    end
    return S.Ok(true)
end
