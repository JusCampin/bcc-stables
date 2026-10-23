-- Compensation for a fully linked, unfulfilled asset only. No public API/worker.
Stables.LinkedCleanup = {}
local L, S = Stables.LinkedCleanup, Stables
local function RetirementRequest(record)
    local p = record.assetRetirement
    return {
        requestId = p.requestId,
        assetId = p.assetId,
        expectedRevision = p.expectedRevision,
        reasonCode = 'stables.purchase_cancelled',
        referenceType = 'stables_order',
        referenceId = record.terms.operationId
    }
end
local function Context(record)
    local g = S.AssetRegistration.Get(record.terms.operationId, record.terms.characterId)
    if not g.ok then return g end
    local intent = g.value
    if intent.state ~= 'linked' then
        return S.Err('registration_not_linked',
            'Only a fully linked purchase can be retired here.')
    end
    local found = S.Assets.FindRegistration(intent.request.requestId)
    if not found.ok then return found end
    local f = found.value
    if type(f) ~= 'table' or f.found ~= true or f.operation ~= 'asset.register'
        or not S.AssetRegistration.Matches(f.result, intent.request) or f.result.assetId ~= intent.assetId then
        return S.Err('registration_conflict', 'The original canonical registration receipt does not match.')
    end
    return g
end
local function Retired(snapshot, record, intent)
    local p = record.assetRetirement
    return S.AssetRegistration.Matches(snapshot, intent.request, true) and snapshot.assetId == p.assetId
        and snapshot.revision == p.expectedRevision + 1 and intent.assetId == p.assetId
end
function L.Confirm(record)
    if not S.Operations.Validate(record).ok or record.registrationFence ~= 'linked_retirement_v1'
        or (record.state ~= 'compensation_pending' and record.state ~= 'refunded') then
        return S.Err('registration_not_fenced', 'Durable linked retirement plan required.')
    end
    local context = Context(record); if not context.ok then return context end
    local found = S.Assets.FindRegistration(record.assetRetirement.requestId); if not found.ok then return found end
    local f = found.value
    if type(f) ~= 'table' or f.found ~= true or f.operation ~= 'asset.retire' or not Retired(f.result, record, context.value) then
        return S.Err('retirement_unconfirmed', 'The exact retirement receipt must exist before refund.')
    end
    local current = S.Assets.ReadHorse(record.assetRetirement.assetId); if not current.ok then return current end
    if not Retired(current.value, record, context.value) then
        return S.Err('retirement_unconfirmed',
            'Current canonical retirement does not match the saved plan.')
    end
    return S.Ok({ assetId = record.assetRetirement.assetId, status = 'retired' })
end

function L.Refund(operationId, characterId, authorize)
    local ready = S.Foundation.RequireReady(); if not ready.ok then return ready end
    local read = S.Repository.Get(operationId, characterId); if not read.ok then return read end
    local record = read.value
    if record.state ~= 'paid' and record.state ~= 'compensation_pending' and record.state ~= 'refunded' then
        return S.Err('registration_not_fenced', 'A paid or already fenced linked purchase is required.')
    end
    local payment = S.Payments.VerifyPayment(record, record.paymentReceipt); if not payment.ok then return payment end
    local context = Context(record); if not context.ok then return context end
    local intent = context.value
    if record.state == 'paid' then
        local current = S.Assets.ReadHorse(intent.assetId); if not current.ok then return current end
        if not S.AssetRegistration.Matches(current.value, intent.request) or current.value.assetId ~= intent.assetId
            or current.value.revision < intent.assetRevision then
            return S.Err('asset_changed',
                'Only the unchanged, active original owner asset can enter linked cancellation.')
        end
        if authorize then
            local allowed = authorize(); if not allowed.ok then return allowed end
        end
        local fenced = S.Repository.FenceLinked(operationId, characterId, record.revision, intent.assetId,
            current.value.revision)
        if not fenced.ok then return fenced end -- unknown local commit cannot retire or reverse
        record = fenced.value
    end
    if record.registrationFence ~= 'linked_retirement_v1' or record.assetRetirement.assetId ~= intent.assetId then
        return S.Err('registration_not_fenced', 'Retirement plan does not match the canonical link.')
    end
    local confirmed = L.Confirm(record)
    if not confirmed.ok and record.state ~= 'refunded' and confirmed.code == 'retirement_unconfirmed' then
        -- Missing receipt never proves absence of an in-flight commit. Only retry
        -- the identical retirement, and only while its exact revision remains active.
        local current = S.Assets.ReadHorse(intent.assetId); if not current.ok then return current end
        if not S.AssetRegistration.Matches(current.value, intent.request) or current.value.assetId ~= intent.assetId
            or current.value.revision ~= record.assetRetirement.expectedRevision then
            return confirmed
        end
        if authorize then
            local allowed = authorize(); if not allowed.ok then return allowed end
        end
        local retired = S.Assets.RetireProof(RetirementRequest(record)); if not retired.ok then return retired end
        if not Retired(retired.value, record, intent) then
            return S.Err('retirement_unconfirmed',
                'Retirement response does not match the saved plan.')
        end
        confirmed = L.Confirm(record)
    end
    if not confirmed.ok then return confirmed end
    return S.Payments.RefundRetired(operationId, characterId, authorize)
end
