-- Stored gameplay projection only. No horse entity or outbox dispatcher.
Stables.Fulfillment = {}
local F, S = Stables.Fulfillment, Stables
local enabled = false
local function Payload(p)
    if type(p) ~= 'table' or not S.Operations.IsUuid(p.operationId) then return false end
    for key in pairs(p) do if key ~= 'operationId' then return false end end
    return true
end
function F.Start()
    if type(StablesConfig.purchaseFulfillment) ~= 'boolean' then return S.Err('config_error',
            'purchaseFulfillment must be a boolean.') end
    enabled = StablesConfig.purchaseFulfillment
    return S.Ok({
        ok = true,
        enabled = enabled,
        entitySpawning = false,
        outboxDispatch = type(StablesConfig.outbox) == 'table' and StablesConfig.outbox.enabled == true
    })
end

local function Canonical(id, characterId)
    local link = S.AssetRegistration.Get(id, characterId); if not link.ok then return link end
    if link.value.state ~= 'linked' then return S.Err('registration_not_linked', 'Canonical registration must be linked.') end
    local read = S.Assets.ReadHorse(link.value.assetId); if not read.ok then return read end
    if not S.AssetRegistration.Matches(read.value, link.value.request) or read.value.assetId ~= link.value.assetId
        or read.value.revision < link.value.assetRevision then
        return S.Err('asset_changed', 'Current canonical horse facts changed.')
    end
    return read
end
local function Request(commit, p, source, context)
    if not Payload(p) then return S.Err('invalid_input', 'Only operationId is accepted.') end
    local checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    context = S.Copy(context); local id = p.operationId:lower()
    if commit and not enabled then return S.Err('fulfillment_disabled', 'Stored horse fulfillment is disabled.') end
    local order = S.QuoteIntents.Inspect(id, context.characterId, 'quote_admission_v1'); if not order.ok then return
        order end
    if order.value.state ~= 'paid' and order.value.state ~= 'fulfilled' then return S.Err('fulfillment_not_found',
            'Paid linked purchase required.') end
    local observed = Canonical(id, context.characterId); if not observed.ok then return observed end
    local result
    if commit then
        local record = S.Repository.Get(id, context.characterId); if not record.ok then return record end
        local verified = S.Payments.VerifyPayment(record.value, record.value.paymentReceipt); if not verified.ok then return
            verified end
        observed = Canonical(id, context.characterId); if not observed.ok then return observed end
        checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
        result = S.FulfillmentRepository.Commit(id, context.characterId, observed.value)
    else
        result = S.FulfillmentRepository.Get(id, context.characterId)
    end
    if not result.ok then return result end
    -- Canonical reads and local commit are not a distributed transaction. Never
    -- authorize use from the cache; check again before returning the observation.
    local fresh = Canonical(id, context.characterId)
    checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    if not fresh.ok then return fresh end
    return result
end
function F.Commit(p, source, context) return Request(true, p, source, context) end

function F.Get(p, source, context) return Request(false, p, source, context) end

function F.Install()
    for _, entry in ipairs({ { 'fulfill', F.Commit }, { 'fulfillment.get', F.Get } }) do
        local result = S.Core.Call('RegisterRpc', 'stables.purchase.' .. entry[1] .. '.v1', entry[2], {
            contract = 1,
            direction = 'client_to_server',
            requireCharacter = true,
            windowMs = 2000,
            maxCalls = 2,
            maxPayloadBytes = 128,
            maxDepth = 2,
            maxNodes = 4,
            validatePayload = Payload
        })
        if not result.ok then return result end
    end
    return S.Ok(true)
end
