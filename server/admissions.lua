-- Guarded player-facing unpaid admissions. Identity comes only from Core.
Stables.Admissions={}
local A,S=Stables.Admissions,Stables
local enabled,paymentsEnabled=false,false
local KIND='quote_admission_v1'
local function Payload(p,key)
    if type(p)~='table' or not S.Operations.IsUuid(p[key]) then return false end
    for field in pairs(p) do if field~=key then return false end end
    return true
end
local function View(value)
    local q=value.quoteSnapshot
    return {operationId=value.operationId,state=value.state,revision=value.revision,
        catalogId=value.catalogId,stableId=q.stableId,modelKey=q.modelKey,
        price={currency=value.currency,amount=value.amount,precision=q.precision},
        replayed=value.replayed,paymentAvailable=paymentsEnabled and (value.state=='reserved' or value.state=='payment_pending')}
end
function A.Start()
    if type(StablesConfig.purchaseAdmission)~='boolean' then return S.Err('config_error','purchaseAdmission must be a boolean.') end
    if type(StablesConfig.purchasePayments)~='boolean' then return S.Err('config_error','purchasePayments must be a boolean.') end
    if type(StablesConfig.purchaseRegistration)~='boolean' then return S.Err('config_error','purchaseRegistration must be a boolean.') end
    enabled=StablesConfig.purchaseAdmission
    paymentsEnabled=StablesConfig.purchasePayments
    return S.Ok({ok=true,reservationsEnabled=enabled,paymentsEnabled=paymentsEnabled,registrationEnabled=StablesConfig.purchaseRegistration})
end
function A.Enabled() return enabled end
function A.PaymentsEnabled() return paymentsEnabled end
function A.PaymentView(value) return View(value) end
local function Request(action,p,source,context)
    local key=action=='reserve' and 'quoteId' or 'operationId'
    if not Payload(p,key) then return S.Err('invalid_input','Only '..key..' is accepted.') end
    local checked=S.Foundation.CheckSession(source,context); if not checked.ok then return checked end
    -- Freeze authorization identity before any yielding consumer/SQL call.
    context=S.Copy(context)
    local id=p[key]:lower()
    if action=='reserve' and not enabled then return S.Err('admission_disabled','Unpaid purchase admissions are disabled.') end
    local result
    if action=='reserve' then result=S.QuoteIntents.Prepare(id,source,context,KIND)
    elseif action=='get' then result=S.QuoteIntents.Inspect(id,context.characterId,KIND)
    else result=S.QuoteIntents.Cancel(id,context.characterId,KIND) end
    -- A committed hold may outlive a session change; disclose no old-session data.
    checked=S.Foundation.CheckSession(source,context)
    if not checked.ok then return checked end
    if not result.ok then return result end
    return S.Ok(View(result.value))
end
function A.Reserve(p,source,context) return Request('reserve',p,source,context) end
function A.Get(p,source,context) return Request('get',p,source,context) end
function A.Cancel(p,source,context) return Request('cancel',p,source,context) end
function A.Install()
    for _,entry in ipairs({{'reserve',A.Reserve,'quoteId'},{'get',A.Get,'operationId'},{'cancel',A.Cancel,'operationId'}}) do
        local key=entry[3]
        local result=S.Core.Call('RegisterRpc','stables.purchase.'..entry[1]..'.v1',entry[2],{
            contract=1,direction='client_to_server',requireCharacter=true,windowMs=2000,maxCalls=2,
            maxPayloadBytes=128,maxDepth=2,maxNodes=4,validatePayload=function(p) return Payload(p,key) end})
        if not result.ok then return result end
    end
    return S.Ok(true)
end
