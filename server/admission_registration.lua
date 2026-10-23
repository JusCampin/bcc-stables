-- Canonical Assets link only. Ownership is never inferred from this local receipt.
Stables.AdmissionRegistration = {}
local R, S = Stables.AdmissionRegistration, Stables
local enabled = false
local function Payload(p)
    if type(p) ~= 'table' or not S.Operations.IsUuid(p.operationId) then return false end
    for key in pairs(p) do if key ~= 'operationId' then return false end end
    return true
end
function R.Start()
    if type(StablesConfig.purchaseRegistration) ~= 'boolean' then return S.Err('config_error',
            'purchaseRegistration must be a boolean.') end
    enabled = StablesConfig.purchaseRegistration
    return S.Ok({ ok = true, enabled = enabled, gameplayAvailable = false })
end

local function Read(id, characterId)
    local saved = S.AssetRegistration.Get(id, characterId); if not saved.ok then return saved end
    local intent = saved.value
    local view = { operationId = id, registrationState = intent.state, gameplayAvailable = false }
    if intent.state == 'linked' then
        local current = S.Assets.ReadHorse(intent.assetId); if not current.ok then return current end
        local asset = current.value
        if not S.AssetRegistration.Matches(asset, intent.request, type(asset) == 'table' and asset.status == 'retired')
            or asset.assetId ~= intent.assetId or asset.revision < intent.assetRevision then
            return S.Err('asset_changed', 'Canonical horse facts changed; reconcile this same operation.')
        end
        view.assetId, view.assetRevision, view.assetStatus = asset.assetId, asset.revision, asset.status
    end
    return S.Ok(view)
end
local function Request(register, p, source, context)
    if not Payload(p) then return S.Err('invalid_input', 'Only operationId is accepted.') end
    local checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    context = S.Copy(context); local id = p.operationId:lower()
    if register and not enabled then return S.Err('registration_disabled', 'Purchase registration is disabled.') end
    local order = S.QuoteIntents.Inspect(id, context.characterId, 'quote_admission_v1'); if not order.ok then return
        order end
    local function Authorize() return S.Foundation.CheckSession(source, context) end
    if register then
        if order.value.state ~= 'paid' then return S.Err('payment_required', 'Verified paid intent required.') end
        local record = S.Repository.Get(id, context.characterId); if not record.ok then return record end
        local payment = S.Payments.VerifyPayment(record.value, record.value.paymentReceipt); if not payment.ok then return
            payment end
        checked = Authorize(); if not checked.ok then return checked end
        local result = S.AssetRegistration.Run(id, context.characterId, record.value.quoteSnapshot.modelKey, Authorize)
        checked = Authorize(); if not checked.ok then return checked end
        if not result.ok then return result end
    end
    local result = Read(id, context.characterId)
    checked = Authorize(); if not checked.ok then return checked end
    return result
end
function R.Register(p, source, context) return Request(true, p, source, context) end

function R.Get(p, source, context) return Request(false, p, source, context) end

function R.Install()
    for _, entry in ipairs({ { 'register', R.Register }, { 'get', R.Get } }) do
        local result = S.Core.Call('RegisterRpc', 'stables.purchase.registration.' .. entry[1] .. '.v1', entry[2], {
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
