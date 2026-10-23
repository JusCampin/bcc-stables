local running = false
RegisterCommand('BccStablesCatalogSmokeTest', function()
    if running then return end
    running = true
    CreateThread(function()
        local ok, failure = pcall(function()
            local response, done
            exports['feather-core']:CallRPC('stables.catalog.get.v1', {}, function(...)
                if not done then response, done = table.pack(...), true end
            end, nil, 5000)
            local start = GetGameTimer()
            while not done and GetGameTimer() - start < 6000 do Wait(25) end
            done = true
            if not response then
                print('[bcc-stables] catalogue RPC failed: timeout'); return
            end
            local result, err = response[1], response[2]
            if type(result) ~= 'table' or result.ok ~= true then
                print('[bcc-stables] catalogue RPC failed: ' ..
                    tostring(type(result) == 'table' and result.code or type(err) == 'table' and err.code or
                        'invalid_result'))
                return
            end
            local value = result.value
            if type(value) ~= 'table' or type(value.revision) ~= 'number' or value.revision % 1 ~= 0 or value.revision < 1
                or type(value.items) ~= 'table' or #value.items < 1 or #value.items > 32 or value.purchasesAvailable ~= false then
                print('[bcc-stables] catalogue RPC failed: invalid_result'); return
            end
            -- Validate the full response before printing PASS.
            for _, item in ipairs(value.items) do
                local p = type(item) == 'table' and item.price
                if type(item) ~= 'table' or type(item.id) ~= 'string' or type(item.label) ~= 'string'
                    or type(p) ~= 'table' or type(p.amount) ~= 'number' or p.amount % 1 ~= 0 or p.amount < 1 or p.amount > 1000000000
                    or type(p.currency) ~= 'string' or type(p.precision) ~= 'number' or p.precision % 1 ~= 0 or p.precision < 0 or p.precision > 8 then
                    print('[bcc-stables] catalogue RPC failed: invalid_result'); return
                end
            end
            print(('[bcc-stables] catalogue RPC PASS; revision=%d entries=%d purchasesAvailable=false'):format(
                value.revision, #value.items))
            for _, item in ipairs(value.items) do
                local p = item.price
                print(('[bcc-stables] %s | %s | %s %s'):format(item.id, item.label, p.currency,
                    ('%.' .. p.precision .. 'f'):format(p.amount / 10 ^ p.precision)))
            end
        end)
        running = false
        if not ok then print('[bcc-stables] catalogue diagnostic failed: ' .. tostring(failure)) end
    end)
end, false)
