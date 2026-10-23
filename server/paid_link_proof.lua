-- Opt-in one-unit real payment plus durable canonical link. No physical horse.
local S = Stables
local CURRENCY, CATALOG = 'dollars', 'proof.paid_link.v1'
local MODEL = 'a_c_horse_morgan_bay'
local function OperationId(characterId)
    return ('%x'):format((tonumber(characterId:sub(1, 1), 16) + 8) % 16) .. characterId:sub(2)
end
local busy = false
local function Value(r)
    if not S.IsResult(r) then error(S.Err('invalid_contract', 'Invalid service result.'), 0) end
    if not r.ok then error(r, 0) end; return r.value
end
local function Check(ok, code, message) if not ok then error(S.Err(code, message), 0) end end
local function Log(result) print('[bcc-stables:paid-link-proof] ' .. json.encode(result)) end
local function Record(characterId)
    local r = Value(S.Repository.Get(OperationId(characterId), characterId))
    local t = r.terms
    Check(
        t.operationId == OperationId(characterId) and t.characterId == characterId and
        t.horseId == OperationId(characterId) and t.quoteId == OperationId(characterId)
        and t.catalogId == CATALOG and t.catalogRevision == 1 and t.currency == CURRENCY and t.amount == 1,
        'proof_conflict', 'Existing operation does not match this exact one-unit payment fixture.')
    return r
end
local function Cleanup(characterId)
    local link = S.AssetRegistration.Get(OperationId(characterId), characterId)
    if not link.ok and link.code == 'registration_not_found' then
        return S.Payments.RefundUnregistered(OperationId(characterId), characterId)
    end
    if not link.ok then return link end
    return S.LinkedCleanup.Refund(OperationId(characterId), characterId)
end
local function Summary(record)
    local t = record.terms
    local result = {
        characterId = t.characterId,
        operationId = t.operationId,
        state = record.state,
        revision = record.revision,
        amount = 1,
        currency = CURRENCY,
        paymentTransactionId = record.paymentReceipt and record.paymentReceipt.transactionId,
        refundTransactionId = record.refundReceipt and record.refundReceipt.transactionId,
        registrationFence = record.registrationFence,
        noEntitySpawned = true
    }
    local link = S.AssetRegistration.Get(t.operationId, t.characterId)
    if not link.ok then
        Check(link.code == 'registration_not_found', link.code, link.message)
        result.registrationState = 'absent'; return result
    end
    result.registrationState = link.value.state
    result.assetId = link.value.assetId
    if result.assetId then
        local asset = Value(S.Assets.ReadHorse(result.assetId))
        Check(
            S.AssetRegistration.Matches(asset, link.value.request, asset.status == 'retired') and
            asset.assetId == result.assetId,
            'asset_changed', 'Canonical fixture facts changed; inspect before further action.')
        result.assetStatus, result.assetRevision = asset.status, asset.revision
    end
    return result
end
local function Run(serverId)
    local session = Value(S.Core.RequireSession(serverId))
    Check(S.Operations.IsUuid(session.characterId), 'invalid_contract', 'Character UUID required.')
    local id = session.characterId:lower()
    Log({ event = 'fixture_selected', serverPlayerId = serverId, characterId = id, operationId = OperationId(id), amount = 1, currency =
    CURRENCY })
    local existing = S.Repository.Get(OperationId(id), id)
    if existing.ok then
        local record = Record(id)
        if record.state == 'refunded' then return Summary(Value(Cleanup(id))) end
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
            operationId = OperationId(id),
            characterId = id,
            horseId = OperationId(id),
            quoteId = OperationId(id),
            catalogId = CATALOG,
            catalogRevision = 1,
            currency = CURRENCY,
            amount = 1,
            walletAccountId = wallet.accountId,
            sinkAccountId = sink.accountId
        }))
    end
    Value(S.Payments.Pay(OperationId(id), id))
    Value(S.AssetRegistration.Run(OperationId(id), id, MODEL))
    return Summary(Record(id))
end
RegisterCommand('BccStablesPaidLinkProof', function(source, args)
    if source ~= 0 then return end
    if StablesConfig.paidLinkProof ~= true then
        Log(S.Err('disabled', 'Enable paidLinkProof only for this one-unit payment/Assets test.')); return
    end
    if busy then
        Log(S.Err('busy', 'Paid-link proof is running.')); return
    end
    local action, id = args[1], args[2]
    local playerId = tonumber(id)
    if (action == 'run' and (#args ~= 3 or args[3] ~= '1' or not playerId or playerId % 1 ~= 0 or playerId < 1 or playerId > 65535))
        or (action ~= 'run' and (action ~= 'inspect' and action ~= 'refund' or #args ~= 2 or not S.Operations.IsUuid(id))) then
        Log(S.Err('invalid_input',
            'BccStablesPaidLinkProof run <serverPlayerId> 1 | inspect <characterUUID> | refund <characterUUID>')); return
    end
    busy = true
    CreateThread(function()
        local ok, result = pcall(function()
            Value(S.Foundation.RequireReady())
            if action == 'run' then return Run(playerId) end
            local characterId = id:lower()
            local record = Record(characterId)
            if action == 'refund' then return Summary(Value(Cleanup(characterId))) end
            -- Inspect never submits a pending transfer or a reversal.
            if record.state == 'paid' then record = Value(S.Payments.Pay(OperationId(characterId), characterId)) end
            if record.state == 'refunded' then
                if record.registrationFence == 'linked_retirement_v1' then
                    Value(S.LinkedCleanup.Confirm(record))
                else
                    Value(S.Payments.RefundUnregistered(OperationId(characterId), characterId))
                end
            end
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
