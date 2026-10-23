-- Internal Economy consumer. No public payment/refund route or worker.
Stables.Economy = {}
local E = Stables.Economy
local function Call(method, ...)
    if GetResourceState('feather-economy') ~= 'started' then return Stables.Err('economy_unavailable',
            'Economy is not started.') end
    local args = table.pack(...)
    local called, result = pcall(function()
        local provider = exports['feather-economy']
        return provider[method](provider, table.unpack(args, 1, args.n))
    end)
    if not called then return Stables.Err('economy_dependency_error',
            'Economy call failed; reconcile the same payment key.', { operation = method }) end
    if not Stables.IsResult(result) then return Stables.Err('invalid_contract', 'Economy returned an invalid envelope.',
            { operation = method }) end
    return result
end
function E.Account(id) return Call('GetAccount', { accountId = id }) end

function E.Currency(code) return Call('GetCurrency', code) end

function E.CharacterAccounts(id) return Call('FindAccountsByOwner', { ownerType = 'character', ownerId = id }) end

function E.SystemSink(currency) return Call('GetSystemAccount', { currency = currency, accountType = 'system_sink' }) end

function E.Transaction(id) return Call('GetTransaction', { transactionId = id }) end

function E.Transfer(request) return Call('Transfer', Stables.Copy(request)) end

function E.Reverse(transactionId) return Call('ReversePayment', { transactionId = transactionId }) end

function E.RequireReady()
    local health = Call('GetHealth')
    if not health.ok then return health end
    if type(health.value) ~= 'table' or health.value.state ~= 'ready' then return Stables.Err('economy_unavailable',
            'Economy is not ready.') end
    return Stables.Ok(true)
end

function E.Probe()
    local ready = E.RequireReady(); if not ready.ok then return ready end
    local result = Call('GetCapabilities'); if not result.ok then return result end
    local c = result.value
    if type(c) ~= 'table' or c.resource ~= 'feather-economy' or c.contract ~= 1 or c.state ~= 'ready' or type(c.features) ~= 'table' then
        return Stables.Err('unsupported_contract', 'Ready Economy Contract 1 is required.')
    end
    for _, feature in ipairs({ 'health', 'accounts', 'transfers', 'journal', 'idempotency', 'transactionRead', 'scopedPaymentReversals' }) do
        if c.features[feature] ~= 1 then return Stables.Err('unsupported_contract',
                'Required Economy feature is missing.', { feature = feature }) end
    end
    local probe = E.Transaction('00000000-0000-0000-0000-000000000000')
    if probe.ok or probe.code ~= 'transaction_not_found' then
        return probe.ok and Stables.Err('invalid_contract', 'Reserved transaction read probe unexpectedly exists.') or
        probe
    end
    return Stables.Ok({ ok = true, contract = c.contract, version = c.version, trustedRead = true, paymentsEnabled =
    StablesConfig.purchasePayments == true })
end

function E.Start()
    local ready = Call('AwaitReady', StablesConfig.startupTimeoutMs)
    if not ready.ok then return ready end
    return E.Probe()
end

RegisterCommand('BccStablesEconomySmokeTest', function(source)
    if source ~= 0 then return end
    local r = E.Probe()
    print(('[BccStablesEconomySmokeTest] Economy contract and trusted transaction read %s%s'):format(
        r.ok and 'PASS' or 'FAIL', r.ok and '' or (' [' .. r.code .. ']')))
    print('[BccStablesEconomySmokeTest] read-only; no payment, reversal, account provisioning or asset mutation')
end, true)
