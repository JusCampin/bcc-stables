-- Ephemeral, session-bound draft quotes. No confirmation/payment/reservation API.
Stables.Quotes = {}
local Q, S = Stables.Quotes, Stables
local quotes, options = {}, nil
local function Key(v, max) return type(v) == 'string' and #v <= max and v:match('^[a-z0-9][a-z0-9_.%-]*$') ~= nil end
local function Payload(p, create)
    if type(p) ~= 'table' then return false end
    local allowed = create and { stableId = true, catalogId = true } or { quoteId = true }
    for key in pairs(p) do if not allowed[key] then return false end end
    return create and Key(p.stableId, 64) and Key(p.catalogId, 64) or (not create and S.Operations.IsUuid(p.quoteId))
end
local function Age(record) return GetGameTimer() - record.createdAt end
local function Expired(record)
    local age = Age(record); return age < 0 or age >= record.ttlMs
end
local function View(record)
    local view = S.Copy(record.public)
    view.reservationAvailable = S.Admissions ~= nil and S.Admissions.Enabled()
    view.expiresInMs = math.max(0, record.ttlMs - Age(record))
    return view
end
local function SamePrice(a, b)
    return a.revision == b.revision and a.item.modelKey == b.item.modelKey and
        a.item.price.currency == b.item.price.currency
        and a.item.price.amount == b.item.price.amount and a.item.price.precision == b.item.price.precision
end
function Q.Start()
    options = S.Locations.Options(); quotes = {}
    if not options then return S.Err('not_ready', 'Stable locations must initialize before quotes.') end
    return S.Ok({ ok = true, ttlMs = options.ttlMs, maxQuotes = options.maxQuotes, confirmAvailable = false })
end

function Q.Stop() quotes = {} end

function Q.SessionEvent(stage, session)
    if stage ~= 'leaving' and stage ~= 'left' or type(session) ~= 'table' then return end
    for source, record in pairs(quotes) do
        if record.sessionId == session.sessionId then quotes[source] = nil end
    end
end

function Q.Create(p, source, context)
    if not Payload(p, true) then return S.Err('invalid_input', 'Only stableId and catalogId are accepted.') end
    local session = S.Foundation.CheckSession(source, context); if not session.ok then return session end
    if not options then return S.Err('not_ready', 'Quotes are not initialized.') end
    local location = S.Locations.Check(source, p.stableId, p.catalogId); if not location.ok then return location end
    local catalog = S.Catalog.Resolve(p.catalogId); if not catalog.ok then return catalog end
    for key, record in pairs(quotes) do if Expired(record) then quotes[key] = nil end end
    local count = 0; for _ in pairs(quotes) do count = count + 1 end
    if not quotes[source] and count >= options.maxQuotes then return S.Err('quote_limit',
            'Quote capacity is temporarily full.') end
    local called, id = pcall(DB.value, 'SELECT UUID()') -- identifier read only; no row or reservation is written
    if not called then return S.Persistence.DatabaseError(id) end
    if not S.Operations.IsUuid(id) then return S.Err('invalid_contract', 'Database did not return a quote UUID.') end
    -- UUID lookup may yield: revalidate the exact session/location/catalogue.
    session = S.Foundation.CheckSession(source, context); if not session.ok then return session end
    local current = S.Locations.Check(source, p.stableId, p.catalogId); if not current.ok then return current end
    local fresh = S.Catalog.Resolve(p.catalogId); if not fresh.ok then return fresh end
    if current.value.revision ~= location.value.revision or not SamePrice(catalog.value, fresh.value) then
        return S.Err('quote_stale', 'Stable or catalogue terms changed while preparing the quote.')
    end
    count = 0
    for key, record in pairs(quotes) do
        if Expired(record) then
            quotes[key] = nil
        else
            count = count + 1
            if record.public.quoteId == id:lower() then return S.Err('quote_conflict', 'Quote UUID was already issued.') end
        end
    end
    if not quotes[source] and count >= options.maxQuotes then return S.Err('quote_limit',
            'Quote capacity changed while preparing the quote.') end
    local item = fresh.value.item
    local record = {
        createdAt = GetGameTimer(),
        ttlMs = options.ttlMs,
        sessionId = context.sessionId,
        accountId = context.accountId,
        characterId = context.characterId,
        public = {
            quoteId = id:lower(),
            stableId = p.stableId,
            catalogId = p.catalogId,
            catalogRevision = fresh.value.revision,
            stableRevision = current.value.revision,
            modelKey = item.modelKey,
            price = S.Copy(item.price),
            confirmAvailable = false
        }
    }
    quotes[source] = record
    return S.Ok(View(record))
end

function Q.Get(p, source, context)
    if not Payload(p, false) then return S.Err('invalid_input', 'Only quoteId is accepted.') end
    local session = S.Foundation.CheckSession(source, context); if not session.ok then return session end
    local record = quotes[source]
    if not record or record.public.quoteId ~= p.quoteId:lower() or record.sessionId ~= context.sessionId
        or record.characterId ~= context.characterId or record.accountId ~= context.accountId then
        return S.Err('quote_not_found', 'Quote is not available for this session.')
    end
    if Expired(record) then
        quotes[source] = nil; return S.Err('quote_expired', 'Quote has expired.')
    end
    local location = S.Locations.Check(source, record.public.stableId, record.public.catalogId); if not location.ok then return
        location end
    local catalog = S.Catalog.Resolve(record.public.catalogId); if not catalog.ok then return catalog end
    local v = record.public
    if location.value.revision ~= v.stableRevision or not SamePrice({ revision = v.catalogRevision, item = { modelKey = v.modelKey, price = v.price } }, catalog.value) then
        quotes[source] = nil; return S.Err('quote_stale', 'Quote terms changed; request a new quote.')
    end
    return S.Ok(View(record))
end

function Q.Install()
    for _, entry in ipairs({ { 'stables.quote.create.v1', Q.Create, true }, { 'stables.quote.get.v1', Q.Get, false } }) do
        local create = entry[3]
        local result = S.Core.Call('RegisterRpc', entry[1], entry[2],
            {
                contract = 1,
                direction = 'client_to_server',
                requireCharacter = true,
                windowMs = 2000,
                maxCalls = 2,
                maxPayloadBytes = 256,
                maxDepth = 2,
                maxNodes = 8,
                validatePayload = function(p) return Payload(p, create) end
            })
        if not result.ok then return result end
    end
    return S.Ok(true)
end

-- Explicit console-only experiment. Routing owns every bucket change.
local routeRunning, pendingRoute = false, nil
local function Routing(method, ...)
    if GetResourceState('feather-routing') ~= 'started' then return S.Err('dependency_unavailable',
            'Start feather-routing first.') end
    local args = table.pack(...)
    local ok, result = pcall(function()
        local provider = exports['feather-routing']
        return provider[method](provider, table.unpack(args, 1, args.n))
    end)
    if not ok or not S.IsResult(result) then return S.Err('dependency_error', 'Routing call failed.', { operation =
        method }) end
    return result
end
local function RunRouteTest(target, id)
    if type(target) ~= 'number' or target % 1 ~= 0 or target < 1 or not S.Operations.IsUuid(id) then
        return S.Err('invalid_input', 'BccStablesQuoteRouteTest <serverPlayerId> <quoteId>')
    end
    local session = S.Core.RequireSession(target); if not session.ok then return session end
    local context = session.value
    local before = Q.Get({ quoteId = id }, target, context); if not before.ok then return before end
    if GetPlayerRoutingBucket(target) ~= 0 then return S.Err('foreign_route', 'Player must start in the default world.') end
    local membership = Routing('GetPlayerRoute', target); if not membership.ok then return membership end
    if membership.value ~= nil then return S.Err('foreign_route', 'Player already has managed route membership.') end
    local created = Routing('CreateRoute', { key = 'stables.quote-test:' .. id, mode = 'strict', populationEnabled = false })
    local routeId = created.ok and type(created.value) == 'table' and created.value.routeId
    if type(routeId) ~= 'string' or routeId == '' then
        return created.ok and S.Err('invalid_contract', 'Routing returned no route ID.') or created
    end
    pendingRoute = routeId
    local called, result = pcall(function()
        local checked = S.Foundation.CheckSession(target, context); if not checked.ok then return checked end
        local joined = Routing('JoinRoute', routeId, target); if not joined.ok then return joined end
        if GetPlayerRoutingBucket(target) == 0 then return S.Err('route_not_observed', 'Private route was not observed.') end
        local read = Q.Get({ quoteId = id }, target, context)
        local create = Q.Create({ stableId = before.value.stableId, catalogId = before.value.catalogId }, target, context)
        if read.code ~= 'foreign_route' or create.code ~= 'foreign_route' then
            return S.Err('proof_failed', 'Quote route denial failed.', { read = read.code, create = create.code })
        end
        return S.Ok({ serverPlayerId = target, readDenied = true, createDenied = true })
    end)
    local deleted = Routing('DeleteRoute', routeId)
    if not deleted.ok then return S.Err('route_cleanup_failed', 'Run BccStablesQuoteRouteReturn to retry cleanup.',
            { routeId = routeId, cause = deleted.code }) end
    pendingRoute = nil
    if not called then return S.Err('proof_failed', 'Route test raised an exception; owned route was deleted.') end
    if not result.ok then return result end
    result.value.returnedToDefault = GetPlayerRoutingBucket(target) == 0
    if not result.value.returnedToDefault then return S.Err('route_cleanup_failed',
            'Player did not return to the default world.') end
    local restored = Q.Get({ quoteId = id }, target, context)
    result.value.quoteStillReadable = restored.ok
    if not restored.ok then return S.Err('proof_failed', 'Restored quote read failed.', { cause = restored.code }) end
    return result
end
function Q.RouteTest(target, id)
    if routeRunning or pendingRoute then return S.Err('busy', 'A route test or cleanup is pending.') end
    routeRunning = true
    local ok, result = pcall(RunRouteTest, target, id)
    routeRunning = false
    if not ok then
        if pendingRoute then
            local deleted = Routing('DeleteRoute', pendingRoute)
            if deleted.ok then pendingRoute = nil end
        end
        return S.Err('proof_failed', 'Route test raised an exception.', { cleanupPending = pendingRoute ~= nil })
    end
    return result
end

RegisterCommand('BccStablesQuoteRouteTest', function(source, args)
    if source ~= 0 then return end
    print('[bcc-stables:quote-route] ' .. json.encode(Q.RouteTest(tonumber(args[1]), args[2])))
end, true)
RegisterCommand('BccStablesQuoteRouteReturn', function(source)
    if source ~= 0 or routeRunning then return end
    local result = pendingRoute and Routing('DeleteRoute', pendingRoute) or S.Ok({ cleared = false })
    if result.ok then pendingRoute = nil end
    print('[bcc-stables:quote-route] ' .. json.encode(result))
end, true)
