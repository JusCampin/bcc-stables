-- Character-bound money operations for admitted orders only. No Assets writer.
Stables.AdmissionPayments = {}
local A, S = Stables.AdmissionPayments, Stables
local function Payload(p, pay)
    if type(p) ~= 'table' or not S.Operations.IsUuid(p.operationId) then return false end
    local fields = pay and { operationId = true, expectedAmount = true, currency = true } or { operationId = true }
    for key in pairs(p) do if not fields[key] then return false end end
    return not pay or (type(p.expectedAmount) == 'number' and p.expectedAmount % 1 == 0 and p.expectedAmount >= 1
        and p.expectedAmount <= 1000000000 and type(p.currency) == 'string' and #p.currency <= 32
        and p.currency:match('^[a-z][a-z0-9_]*$') ~= nil)
end
local function Request(pay, p, source, context)
    if not Payload(p, pay) then return S.Err('invalid_input', 'Exact operation ID and payment acknowledgment required.') end
    local checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    context, p = S.Copy(context), S.Copy(p)
    if pay and not S.Admissions.PaymentsEnabled() then return S.Err('payment_disabled', 'Purchase payments are disabled.') end
    local id = p.operationId:lower()
    local read = S.QuoteIntents.Inspect(id, context.characterId, 'quote_admission_v1'); if not read.ok then return read end
    if pay and (read.value.amount ~= p.expectedAmount or read.value.currency ~= p.currency) then
        return S.Err('price_acknowledgment_mismatch', 'Acknowledge the exact saved price; no funds moved.')
    end
    local function Authorize() return S.Foundation.CheckSession(source, context) end
    checked = Authorize(); if not checked.ok then return checked end
    local result
    if pay then
        result = S.Payments.Pay(id, context.characterId, Authorize)
    else
        local registration = S.AssetRegistration.Get(id, context.characterId)
        if registration.ok then
            result = S.LinkedCleanup.Refund(id, context.characterId, Authorize)
        elseif registration.code == 'registration_not_found' then
            result = S.Payments.RefundUnregistered(id, context.characterId, Authorize)
        else
            return registration
        end
    end
    checked = Authorize(); if not checked.ok then return checked end
    if not result.ok then return result end
    local current = S.QuoteIntents.Inspect(id, context.characterId, 'quote_admission_v1')
    checked = Authorize(); if not checked.ok then return checked end
    if not current.ok then return current end
    return S.Ok(S.Admissions.PaymentView(current.value))
end
function A.Pay(p, source, context) return Request(true, p, source, context) end

function A.Refund(p, source, context) return Request(false, p, source, context) end

function A.Install()
    for _, entry in ipairs({ { 'pay', A.Pay, true }, { 'refund', A.Refund, false } }) do
        local pay = entry[3]
        local result = S.Core.Call('RegisterRpc', 'stables.purchase.' .. entry[1] .. '.v1', entry[2], {
            contract = 1,
            direction = 'client_to_server',
            requireCharacter = true,
            windowMs = 2000,
            maxCalls = 2,
            maxPayloadBytes = 256,
            maxDepth = 2,
            maxNodes = 8,
            validatePayload = function(p) return Payload(p, pay) end
        })
        if not result.ok then return result end
    end
    return S.Ok(true)
end
