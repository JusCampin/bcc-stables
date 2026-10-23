-- Internal unpaid intent service shared by proof and guarded player admissions.
Stables.QuoteIntents = {}
local I, S = Stables.QuoteIntents, Stables
local KIND = 'quote_intent_proof_v1'
local function ValidKind(kind) return kind == KIND or kind == 'quote_admission_v1' end
local function Proof(record, id, characterId, kind)
    local t = record.terms
    return record.quoteSnapshot and record.quoteSnapshot.kind == kind
        and t.operationId == id and t.quoteId == id and t.horseId == id and t.characterId == characterId
end
local function Summary(record, replayed)
    return S.Ok({
        operationId = record.terms.operationId,
        characterId = record.terms.characterId,
        state = record.state,
        revision = record.revision,
        catalogId = record.terms.catalogId,
        amount = record.terms.amount,
        currency = record.terms.currency,
        quoteSnapshot = S.Copy(record.quoteSnapshot),
        replayed = replayed == true,
        noPaymentSubmitted = record.state == 'reserved' or record.state == 'cancelled',
        noAssetRegistered = record.state == 'reserved' or record.state == 'cancelled',
        noEntitySpawned = record.state == 'reserved' or record.state == 'cancelled'
    })
end
function I.Inspect(id, characterId, kind)
    kind = kind or KIND
    if not ValidKind(kind) then return S.Err('invalid_input', 'Unknown intent kind.') end
    if not S.Operations.IsUuid(id) or not S.Operations.IsUuid(characterId) then return S.Err('invalid_input',
            'Operation and character UUIDs required.') end
    local ready = S.Foundation.RequireReady(); if not ready.ok then return ready end
    id, characterId = id:lower(), characterId:lower()
    local saved = S.Repository.Get(id, characterId); if not saved.ok then return saved end
    if not Proof(saved.value, id, characterId, kind) then return S.Err('intent_conflict',
            'Operation belongs to another intent kind.') end
    if kind == KIND and saved.value.state ~= 'reserved' and saved.value.state ~= 'cancelled' then
        return S.Err('proof_conflict', 'Operation advanced beyond this unpaid proof; no mutation allowed.')
    end
    return Summary(saved.value, true)
end

function I.Prepare(id, source, context, kind)
    kind = kind or KIND
    if not ValidKind(kind) then return S.Err('invalid_input', 'Unknown intent kind.') end
    if not S.Operations.IsUuid(id) then return S.Err('invalid_input', 'Quote UUID required.') end
    local checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    id = id:lower()
    local characterId = context.characterId:lower()
    local saved = S.Repository.Get(id, characterId)
    if saved.ok then return I.Inspect(id, characterId, kind) end
    if saved.code ~= 'operation_not_found' then return saved end
    local quote = S.Quotes.Get({ quoteId = id }, source, context); if not quote.ok then return quote end
    local accounts = S.Economy.CharacterAccounts(characterId); if not accounts.ok then return accounts end
    if type(accounts.value) ~= 'table' then return S.Err('invalid_contract', 'Economy account list required.') end
    local wallet
    for _, account in ipairs(accounts.value) do
        if type(account) == 'table' and account.accountType == 'wallet' and account.currency == quote.value.price.currency
            and account.ownerType == 'character' and account.ownerId == characterId and account.status == 'open' then
            if wallet then return S.Err('ambiguous_wallet', 'Multiple eligible wallets; no intent saved.') end
            wallet = account
        end
    end
    if not wallet then return S.Err('account_not_found', 'Existing currency wallet required; none provisioned.') end
    local sink = S.Economy.SystemSink(quote.value.price.currency); if not sink.ok then return sink end
    local account = sink.value
    if type(account) ~= 'table' or account.accountType ~= 'system_sink' or account.currency ~= quote.value.price.currency
        or account.status ~= 'open' then
        return S.Err('invalid_contract', 'Open matching Economy sink required.')
    end
    -- Account reads may yield. Revalidate the source/session, price, location and TTL.
    local fresh = S.Quotes.Get({ quoteId = id }, source, context); if not fresh.ok then return fresh end
    local a, b = quote.value, fresh.value
    if a.stableId ~= b.stableId or a.stableRevision ~= b.stableRevision or a.catalogId ~= b.catalogId
        or a.catalogRevision ~= b.catalogRevision or a.modelKey ~= b.modelKey or a.price.currency ~= b.price.currency
        or a.price.amount ~= b.price.amount or a.price.precision ~= b.price.precision then
        return S.Err('quote_stale', 'Quote changed while resolving accounts.')
    end
    local reserved = S.Repository.Reserve({
            operationId = id,
            horseId = id,
            quoteId = id,
            characterId = characterId,
            catalogId = b.catalogId,
            catalogRevision = b.catalogRevision,
            currency = b.price.currency,
            amount = b.price.amount,
            walletAccountId = wallet.accountId,
            sinkAccountId = account.accountId
        },
        { kind = kind, stableId = b.stableId, stableRevision = b.stableRevision, modelKey = b.modelKey, precision = b
        .price.precision })
    if not reserved.ok then return reserved end
    return Summary(reserved.value.operation, reserved.value.replayed)
end

function I.Cancel(id, characterId, kind)
    local inspected = I.Inspect(id, characterId, kind); if not inspected.ok then return inspected end
    if inspected.value.state == 'cancelled' then return inspected end
    if inspected.value.state ~= 'reserved' then return S.Err('proof_conflict',
            'Only an unpaid reserved intent may be cancelled.') end
    local cancelled = S.Repository.Advance(id, characterId, inspected.value.revision, 'cancelled')
    if not cancelled.ok then
        if cancelled.code == 'revision_conflict' then
            local current = I.Inspect(id, characterId, kind)
            if current.ok and current.value.state == 'cancelled' then return current end
        end
        return cancelled
    end
    return Summary(cancelled.value, false)
end

local busy = false
RegisterCommand('BccStablesQuoteIntentProof', function(source, args)
    if source ~= 0 then return end
    local function Log(result) print('[bcc-stables:quote-intent] ' .. json.encode(result)) end
    if StablesConfig.quoteIntentProof ~= true then
        Log(S.Err('disabled', 'Enable quoteIntentProof only for unpaid reservation testing.')); return
    end
    if busy then
        Log(S.Err('busy', 'Quote intent proof is running.')); return
    end
    local action = args[1]
    if #args ~= 3 or (action ~= 'run' and action ~= 'inspect' and action ~= 'cancel') then
        Log(S.Err('invalid_input',
            'BccStablesQuoteIntentProof run <serverPlayerId> <quoteId> | inspect <operationId> <characterId> | cancel <operationId> <characterId>')); return
    end
    busy = true
    CreateThread(function()
        local ok, result = pcall(function()
            if action == 'run' then
                local target = tonumber(args[2])
                if not target or target % 1 ~= 0 or target < 1 then return S.Err('invalid_input',
                        'Current server player ID required.') end
                local session = S.Core.RequireSession(target); if not session.ok then return session end
                return I.Prepare(args[3], target, session.value)
            end
            if action == 'cancel' then return I.Cancel(args[2], args[3]) end
            return I.Inspect(args[2], args[3])
        end)
        busy = false
        Log(ok and result or S.Err('proof_error', 'Unexpected error; inspect the same quote operation before retrying.'))
    end)
end, true)
