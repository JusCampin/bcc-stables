local busy, lastQuote = false, nil
local function Rpc(route, payload)
    local response, done
    exports['feather-core']:CallRPC(route, payload, function(...)
        if not done then response, done = table.pack(...), true end
    end, nil, 5000)
    local started = GetGameTimer()
    while not done and GetGameTimer() - started < 6000 do Wait(25) end
    done = true
    if not response then error('timeout', 0) end
    local result, err = response[1], response[2]
    if type(result) ~= 'table' or result.ok ~= true then
        error(tostring(type(result) == 'table' and result.code or type(err) == 'table' and err.code or 'invalid_result'),
            0)
    end
    return result.value
end
local function Quote(value)
    local p = type(value) == 'table' and value.price
    assert(type(value) == 'table' and type(value.quoteId) == 'string' and #value.quoteId == 36
        and type(value.stableId) == 'string' and type(value.catalogId) == 'string'
        and type(value.expiresInMs) == 'number' and value.expiresInMs > 0 and value.expiresInMs <= 120000
        and value.confirmAvailable == false and type(p) == 'table' and type(p.currency) == 'string'
        and type(p.amount) == 'number' and p.amount % 1 == 0 and p.amount > 0 and p.amount <= 1000000000
        and type(p.precision) == 'number' and p.precision % 1 == 0 and p.precision >= 0 and p.precision <= 8,
        'invalid_result')
    return value
end
local function Command(name, body)
    RegisterCommand(name, function(_, args)
        if busy then return end
        busy = true
        CreateThread(function()
            local ok, err = pcall(body, args)
            busy = false
            if not ok then print('[bcc-stables] ' .. name .. ' failed: ' .. tostring(err)) end
        end)
    end, false)
end
Command('BccStablesLocationsSmokeTest', function()
    local v = Rpc('stables.locations.list.v1', {})
    assert(type(v) == 'table' and type(v.items) == 'table' and #v.items > 0 and #v.items <= 32
        and v.purchasesAvailable == false, 'invalid_result')
    for _, item in ipairs(v.items) do
        assert(type(item) == 'table' and type(item.id) == 'string' and type(item.position) == 'table'
            and type(item.position.x) == 'number' and type(item.position.y) == 'number'
            and type(item.position.z) == 'number' and type(item.radius) == 'number', 'invalid_result')
    end
    print('[bcc-stables] locations RPC PASS; purchasesAvailable=false')
    for _, item in ipairs(v.items) do
        print(('[bcc-stables] %s | %.2f, %.2f, %.2f | radius %.1fm'):format(item.id, item.position.x, item.position.y,
            item.position.z, item.radius))
    end
end)
Command('BccStablesQuoteSmokeTest', function(args)
    local stableId, catalogId = args[1] or 'valentine', args[2] or 'morgan_bay'
    local created = Quote(Rpc('stables.quote.create.v1', { stableId = stableId, catalogId = catalogId }))
    assert(created.stableId == stableId and created.catalogId == catalogId, 'invalid_result')
    lastQuote = created.quoteId
    local checked = Quote(Rpc('stables.quote.get.v1', { quoteId = lastQuote }))
    assert(checked.quoteId == lastQuote and checked.stableId == stableId and checked.catalogId == catalogId,
        'invalid_result')
    print(('[bcc-stables] quote create/read PASS; quoteId=%s expiresInMs=%d confirmAvailable=false'):format(lastQuote,
        checked.expiresInMs))
end)
Command('BccStablesQuoteInspect', function(args)
    local quoteId = args[1] or lastQuote
    assert(quoteId, 'Run BccStablesQuoteSmokeTest first, or supply its quote ID.')
    local v = Quote(Rpc('stables.quote.get.v1', { quoteId = quoteId }))
    assert(v.quoteId == quoteId:lower(), 'invalid_result')
    print(('[bcc-stables] quote read PASS; expiresInMs=%d confirmAvailable=false'):format(v.expiresInMs))
end)
