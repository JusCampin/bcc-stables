-- Explicit, opt-in real-money proof. Never prepares/registers an Assets intent.
local S = Stables
local CURRENCY, CATALOG = 'dollars', 'proof.payment_only.v1'
local busy = false
local function Value(r)
    if not S.IsResult(r) then error(S.Err('invalid_contract', 'Invalid service result.'), 0) end
    if not r.ok then error(r, 0) end; return r.value
end
local function Check(ok, code, message) if not ok then error(S.Err(code, message), 0) end end
local function Log(result) print('[bcc-stables:payment-proof] ' .. json.encode(result)) end
local function Record(characterId)
    local r = Value(S.Repository.Get(characterId, characterId))
    local t = r.terms
    Check(
        t.operationId == characterId and t.characterId == characterId and t.horseId == characterId and
        t.quoteId == characterId
        and t.catalogId == CATALOG and t.catalogRevision == 1 and t.currency == CURRENCY and t.amount == 1,
        'proof_conflict', 'Existing operation does not match this exact one-unit payment fixture.')
    return r
end
local function Summary(record)
    return {
        characterId = record.terms.characterId,
        operationId = record.terms.operationId,
        state = record.state,
        revision = record.revision,
        amount = 1,
        currency = CURRENCY,
        paymentTransactionId = record.paymentReceipt and record.paymentReceipt.transactionId,
        refundTransactionId = record.refundReceipt and record.refundReceipt.transactionId,
        registrationFence = record.registrationFence,
        noAssetRegistration = true,
        noEntitySpawned = true
    }
end
local function Run(serverId)
    local session = Value(S.Core.RequireSession(serverId))
    Check(S.Operations.IsUuid(session.characterId), 'invalid_contract', 'Character UUID required.')
    local id = session.characterId:lower()
    Log({ event = 'fixture_selected', serverPlayerId = serverId, characterId = id, operationId = id, amount = 1, currency =
    CURRENCY })
    local existing = S.Repository.Get(id, id)
    if existing.ok then
        local record = Record(id)
        if record.state == 'refunded' then return Summary(Value(S.Payments.RefundUnregistered(id, id))) end
        Check(record.state == 'reserved' or record.state == 'payment_pending' or record.state == 'paid',
            'proof_pending_cleanup', 'Fixture requires inspect/refund; no new payment was submitted.')
    else
        Check(existing.code == 'operation_not_found', existing.code, existing.message)
        local accounts = Value(S.Economy.CharacterAccounts(id))
        Check(type(accounts) == 'table', 'invalid_contract', 'Account list required.')
        local wallet
        for _, account in ipairs(accounts) do
            if account.accountType == 'wallet' and account.currency == CURRENCY and account.ownerType == 'character'
                and account.ownerId == id and account.status == 'open' then
                Check(wallet == nil, 'proof_conflict', 'Multiple eligible wallets; no payment submitted.')
                wallet = account
            end
        end
        Check(wallet ~= nil, 'account_not_found', 'Existing dollars wallet required; no account was provisioned.')
        local sink = Value(S.Economy.SystemSink(CURRENCY))
        Value(S.Repository.Reserve({
            operationId = id,
            characterId = id,
            horseId = id,
            quoteId = id,
            catalogId = CATALOG,
            catalogRevision = 1,
            currency = CURRENCY,
            amount = 1,
            walletAccountId = wallet.accountId,
            sinkAccountId = sink.accountId
        }))
    end
    return Summary(Value(S.Payments.Pay(id, id)))
end
RegisterCommand('BccStablesPaymentProof', function(source, args)
    if source ~= 0 then return end
    if StablesConfig.paymentProof ~= true then
        Log(S.Err('disabled', 'Enable paymentProof only for this one-unit real-payment test.')); return
    end
    if busy then
        Log(S.Err('busy', 'Payment proof is running.')); return
    end
    local action, id = args[1], args[2]
    local playerId = tonumber(id)
    if (action == 'run' and (#args ~= 3 or args[3] ~= '1' or not playerId or playerId % 1 ~= 0 or playerId < 1 or playerId > 65535))
        or (action ~= 'run' and (action ~= 'inspect' and action ~= 'refund' or #args ~= 2 or not S.Operations.IsUuid(id))) then
        Log(S.Err('invalid_input',
            'BccStablesPaymentProof run <serverPlayerId> 1 | inspect <characterUUID> | refund <characterUUID>')); return
    end
    busy = true
    CreateThread(function()
        local ok, result = pcall(function()
            Value(S.Foundation.RequireReady())
            if action == 'run' then return Run(playerId) end
            local characterId = id:lower()
            local record = Record(characterId)
            if action == 'refund' then return Summary(Value(S.Payments.RefundUnregistered(characterId, characterId))) end
            -- Inspect never submits a pending transfer or a reversal.
            if record.state == 'paid' then record = Value(S.Payments.Pay(characterId, characterId)) end
            if record.state == 'refunded' then record = Value(S.Payments.RefundUnregistered(characterId, characterId)) end
            return Summary(record)
        end)
        busy = false
        if ok then
            Log(S.Ok(result))
        elseif S.IsResult(result) then
            Log(result)
        else
            Log(S.Err('proof_error', 'Unexpected proof error; inspect the same character before retrying.'))
        end
    end)
end, true)
