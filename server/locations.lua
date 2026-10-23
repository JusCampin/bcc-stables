Stables.Locations = {}
local L, S = Stables.Locations, Stables
local locations, public, options
local function Integer(v, min, max) return type(v) == 'number' and v % 1 == 0 and v >= min and v <= max end
local function Finite(v) return type(v) == 'number' and v == v and math.abs(v) <= 100000 end
local function Fields(t, known)
    if type(t) ~= 'table' then return false end
    for k in pairs(t) do if not known[k] then return false end end
    return true
end
local function Array(t, max)
    if type(t) ~= 'table' or #t < 1 or #t > max then return false end
    for k in pairs(t) do if not Integer(k, 1, #t) then return false end end
    return true
end
function L.Start()
    local cfg = StablesLocationsConfig
    if not Fields(cfg, { revision = true, quoteTtlMs = true, maxQuotes = true, locations = true })
        or not Integer(cfg.revision, 1, 9007199254740991) or not Integer(cfg.quoteTtlMs, 1000, 120000)
        or not Integer(cfg.maxQuotes, 1, 1024) or not Array(cfg.locations, 32) then
        return S.Err('location_config_error', 'Valid revision, quote bounds and 1..32 stable locations required.')
    end
    local saved, list = {}, {}
    for _, entry in ipairs(cfg.locations) do
        if not Fields(entry, { id = true, label = true, position = true, radius = true, quoteEnabled = true, catalogIds = true })
            or type(entry.id) ~= 'string' or #entry.id > 64 or not entry.id:match('^[a-z][a-z0-9_]*$') or saved[entry.id]
            or type(entry.label) ~= 'string' or #entry.label < 1 or #entry.label > 80 or entry.label:find('%c')
            or not Fields(entry.position, { x = true, y = true, z = true }) or not Finite(entry.position.x)
            or not Finite(entry.position.y) or not Finite(entry.position.z)
            or type(entry.radius) ~= 'number' or entry.radius ~= entry.radius or entry.radius < 1 or entry.radius > 10
            or type(entry.quoteEnabled) ~= 'boolean' or not Array(entry.catalogIds, 32) then
            return S.Err('location_config_error', 'Stable identity, position, radius and quote service must be valid.')
        end
        local ids = {}
        for _, id in ipairs(entry.catalogIds) do
            if type(id) ~= 'string' or ids[id] or not S.Catalog.Resolve(id).ok then
                return S.Err('location_config_error', 'Stable catalogue IDs must be unique and configured.')
            end
            ids[id] = true
        end
        saved[entry.id] = S.Copy(entry); saved[entry.id].allowed = ids
        list[#list + 1] = { id = entry.id, label = entry.label, position = S.Copy(entry.position), radius = entry.radius, quoteEnabled =
        entry.quoteEnabled }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    locations, public, options = saved, { revision = cfg.revision, items = list, purchasesAvailable = false },
        { revision = cfg.revision, ttlMs = cfg.quoteTtlMs, maxQuotes = cfg.maxQuotes }
    return S.Ok({ ok = true, revision = cfg.revision, entries = #list })
end

function L.Options() return options and S.Copy(options) end

function L.Check(source, id, catalogId)
    local stable = locations and locations[id]
    if not stable then return S.Err('stable_not_found', 'Stable was not found.') end
    if not stable.quoteEnabled then return S.Err('service_unavailable', 'This stable does not offer quotes.') end
    if not stable.allowed[catalogId] then return S.Err('catalog_unavailable', 'This horse is not listed at the stable.') end
    local called, near, code = pcall(function()
        if GetPlayerRoutingBucket(source) ~= 0 then return false, 'foreign_route' end
        local ped = GetPlayerPed(source)
        if not ped or ped == 0 then return false, 'position_unavailable' end
        local exists = DoesEntityExist(ped)
        if exists ~= true and exists ~= 1 then return false, 'position_unavailable' end
        local pos = GetEntityCoords(ped)
        if not Finite(pos.x) or not Finite(pos.y) or not Finite(pos.z) then return false, 'position_unavailable' end
        local p = stable.position
        return (pos.x - p.x) ^ 2 + (pos.y - p.y) ^ 2 + (pos.z - p.z) ^ 2 <= stable.radius ^ 2, 'too_far'
    end)
    if not called then return S.Err('position_unavailable', 'Server could not observe stable proximity.') end
    if not near then return S.Err(code, 'A quote requires a visible character near this stable in the default world.') end
    return S.Ok({ revision = options.revision, stableId = id })
end

function L.List(source, context)
    local checked = S.Foundation.CheckSession(source, context); if not checked.ok then return checked end
    if not public then return S.Err('not_ready', 'Locations are not initialized.') end
    return S.Ok(S.Copy(public))
end

function L.Install()
    return S.Core.Call('RegisterRpc', 'stables.locations.list.v1',
        function(_, source, context) return L.List(source, context) end,
        {
            contract = 1,
            direction = 'client_to_server',
            requireCharacter = true,
            windowMs = 2000,
            maxCalls = 2,
            maxPayloadBytes = 64,
            maxDepth = 2,
            maxNodes = 4,
            validatePayload = S.EmptyPayload
        })
end
