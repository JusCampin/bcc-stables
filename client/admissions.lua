local busy = false
local function Rpc(route, payload)
    local reply, done
    exports['feather-core']:CallRPC(route, payload, function(...)
        if not done then reply, done = table.pack(...), true end
    end, nil, 5000)
    local started = GetGameTimer()
    while not done and GetGameTimer() - started < 6000 do Wait(25) end
    done = true
    if not reply then error('timeout; inspect/retry the SAME operation ID', 0) end
    local result, err = reply[1], reply[2]
    if type(result) ~= 'table' or result.ok ~= true then
        error(tostring(type(result) == 'table' and result.code or type(err) == 'table' and err.code or 'invalid_result'),
            0)
    end
    return result.value
end
local function Validate(value, id)
    local p = type(value) == 'table' and value.price
    assert(type(value) == 'table' and value.operationId == id:lower()
        and ({ reserved = true, cancelled = true, payment_pending = true, paid = true, compensation_pending = true,
            refunded = true, reconciliation_required = true, fulfilled = true })[value.state] and
        type(value.paymentAvailable) == 'boolean'
        and type(value.revision) == 'number' and value.revision % 1 == 0 and value.revision >= 0
        and type(value.catalogId) == 'string' and type(value.stableId) == 'string' and type(value.modelKey) == 'string'
        and type(value.replayed) == 'boolean' and type(p) == 'table' and type(p.currency) == 'string'
        and type(p.amount) == 'number' and p.amount % 1 == 0 and p.amount > 0 and p.amount <= 1000000000
        and type(p.precision) == 'number' and p.precision % 1 == 0 and p.precision >= 0 and p.precision <= 8,
        'invalid_result')
    return value
end
local function Command(name, body, argCount)
    RegisterCommand(name, function(_, args)
        if busy then return end
        busy = true
        CreateThread(function()
            local ok, err = pcall(function()
                assert(#args == (argCount or 1) and type(args[1]) == 'string' and args[1]:match(
                    '^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'),
                    'Supply exactly one quote/operation UUID.')
                body(args[1]:lower(), args)
            end)
            busy = false
            if not ok then print('[bcc-stables] ' .. name .. ' failed: ' .. tostring(err)) end
        end)
    end, false)
end
local function Print(value)
    print(('[bcc-stables] admission RPC PASS; operationId=%s state=%s revision=%d replayed=%s paymentAvailable=%s')
    :format(
        value.operationId, value.state, value.revision, tostring(value.replayed), tostring(value.paymentAvailable)))
end
Command('BccStablesAdmissionSmokeTest', function(id)
    -- The server-issued quote ID is also the durable operation ID for recovery.
    print('[bcc-stables] unpaid reservation request; operationId=' .. id)
    local saved = Validate(Rpc('stables.purchase.reserve.v1', { quoteId = id }), id)
    local read = Validate(Rpc('stables.purchase.get.v1', { operationId = id }), id)
    assert(read.state == saved.state and read.revision == saved.revision,
        'operation_changed; inspect the same operation ID')
    Print(saved)
end)
Command('BccStablesAdmissionInspect', function(id)
    Print(Validate(Rpc('stables.purchase.get.v1', { operationId = id }), id))
end)
Command('BccStablesAdmissionCancel', function(id)
    local value = Validate(Rpc('stables.purchase.cancel.v1', { operationId = id }), id)
    assert(value.state == 'cancelled', 'invalid_result')
    Print(value)
end)
Command('BccStablesAdmissionPay', function(id, args)
    local amount = tonumber(args[2])
    assert(amount and amount % 1 == 0 and amount >= 1 and amount <= 1000000000,
        'Supply the saved amount in base units and currency.')
    print(('[bcc-stables] payment request; operationId=%s acknowledgedAmount=%d currency=%s'):format(id, amount, args[3]))
    local value = Validate(Rpc('stables.purchase.pay.v1', { operationId = id, expectedAmount = amount, currency = args
    [3] }), id)
    assert(value.state == 'paid', 'Payment not complete; inspect the SAME operation ID.')
    Print(value)
end, 3)
Command('BccStablesAdmissionRefund', function(id)
    local value = Validate(Rpc('stables.purchase.refund.v1', { operationId = id }), id)
    assert(value.state == 'refunded', 'Refund not complete; inspect the SAME operation ID.')
    Print(value)
end)
local function AssetView(value, id)
    assert(type(value) == 'table' and value.operationId == id and value.gameplayAvailable == false
        and ({ prepared = true, submitted = true, linked = true })[value.registrationState], 'invalid_result')
    if value.registrationState == 'linked' then
        assert(type(value.assetId) == 'string' and #value.assetId == 36 and type(value.assetRevision) == 'number'
            and value.assetRevision % 1 == 0 and value.assetRevision >= 1
            and (value.assetStatus == 'active' or value.assetStatus == 'retired'), 'invalid_result')
    end
    return value
end
local function PrintAsset(value)
    print(('[bcc-stables] canonical registration RPC PASS; operationId=%s registrationState=%s assetId=%s assetStatus=%s assetRevision=%s gameplayAvailable=false')
    :format(
        value.operationId, value.registrationState, tostring(value.assetId), tostring(value.assetStatus),
        tostring(value.assetRevision)))
end
Command('BccStablesAdmissionRegister', function(id)
    local value = AssetView(Rpc('stables.purchase.registration.register.v1', { operationId = id }), id)
    assert(value.registrationState == 'linked' and value.assetStatus == 'active',
        'Registration not complete; inspect/retry the SAME operation ID.')
    PrintAsset(value)
end)
Command('BccStablesAdmissionAssetInspect', function(id)
    PrintAsset(AssetView(Rpc('stables.purchase.registration.get.v1', { operationId = id }), id))
end)
local function Stored(value, id)
    assert(type(value) == 'table' and value.operationId == id and value.state == 'fulfilled' and
        value.availability == 'stored'
        and type(value.horseId) == 'string' and #value.horseId == 36 and type(value.assetId) == 'string' and
        #value.assetId == 36
        and type(value.revision) == 'number' and value.revision % 1 == 0 and value.revision >= 3
        and type(value.outboxPending) == 'boolean' and value.gameplayAvailable == false, 'invalid_result')
    print(('[bcc-stables] stored horse RPC PASS; operationId=%s horseId=%s assetId=%s state=fulfilled revision=%d outboxPending=%s gameplayAvailable=false')
    :format(
        id, value.horseId, value.assetId, value.revision, tostring(value.outboxPending)))
end
Command('BccStablesAdmissionFulfill', function(id)
    Stored(Rpc('stables.purchase.fulfill.v1', { operationId = id }), id)
end)
Command('BccStablesStoredHorseInspect', function(id)
    Stored(Rpc('stables.purchase.fulfillment.get.v1', { operationId = id }), id)
end)
