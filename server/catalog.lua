Stables.Catalog = {}
local C, S = Stables.Catalog, Stables
local snapshot
local function Integer(v, min, max) return type(v) == 'number' and v % 1 == 0 and v >= min and v <= max end
local function Fields(t, known)
    if type(t) ~= 'table' then return false end
    for key in pairs(t) do if not known[key] then return false end end
    return true
end
function C.Start()
    local cfg = StablesCatalogConfig
    if not Fields(cfg, { revision = true, entries = true }) or not Integer(cfg.revision, 1, 9007199254740991)
        or type(cfg.entries) ~= 'table' or #cfg.entries < 1 or #cfg.entries > 32 then
        return S.Err('catalog_config_error', 'Catalogue requires a revision and 1..32 entries.')
    end
    for key in pairs(cfg.entries) do
        if not Integer(key, 1, #cfg.entries) then return S.Err('catalog_config_error',
                'Catalogue entries must be a dense array.') end
    end
    local ids, currencies, items = {}, {}, {}
    for _, entry in ipairs(cfg.entries) do
        if not Fields(entry, { id = true, label = true, modelKey = true, currency = true, amount = true })
            or type(entry.id) ~= 'string' or #entry.id > 64 or not entry.id:match('^[a-z0-9][a-z0-9_.%-]*$') or ids[entry.id]
            or type(entry.label) ~= 'string' or #entry.label < 1 or #entry.label > 80 or entry.label:find('%c')
            or type(entry.modelKey) ~= 'string' or #entry.modelKey > 100 or not entry.modelKey:match('^a_c_horse_[a-z0-9_]+$')
            or type(entry.currency) ~= 'string' or #entry.currency > 32 or not entry.currency:match('^[a-z][a-z0-9_]*$')
            or not Integer(entry.amount, 1, 1000000000) then
            return S.Err('catalog_config_error',
                'Catalogue IDs, labels, horse models and integer prices must be valid and unique.')
        end
        ids[entry.id] = true
        local currency = currencies[entry.currency]
        if not currency then
            local read = S.Economy.Currency(entry.currency); if not read.ok then return read end
            currency = read.value
            if type(currency) ~= 'table' or currency.code ~= entry.currency or not Integer(currency.precision, 0, 8) then
                return S.Err('invalid_contract', 'Economy returned an invalid catalogue currency.')
            end
            currencies[entry.currency] = S.Copy(currency)
        end
        items[#items + 1] = {
            id = entry.id,
            label = entry.label,
            modelKey = entry.modelKey,
            price = { currency = entry.currency, amount = entry.amount, precision = currency.precision }
        }
    end
    table.sort(items, function(a, b) return a.id < b.id end)
    snapshot = { revision = cfg.revision, items = items, purchasesAvailable = false }
    return S.Ok({ ok = true, revision = cfg.revision, entries = #items, purchasesAvailable = false })
end

function C.Resolve(id)
    if not snapshot then return S.Err('not_ready', 'Catalogue is not initialized.') end
    for _, item in ipairs(snapshot.items) do
        if item.id == id then return S.Ok({ revision = snapshot.revision, item = S.Copy(item) }) end
    end
    return S.Err('catalog_not_found', 'Catalogue entry was not found.')
end

function C.Get(source, context)
    local session = S.Foundation.CheckSession(source, context)
    if not session.ok then return session end
    if not snapshot then return S.Err('not_ready', 'Catalogue is not initialized.') end
    -- No yielding calls after session verification. Return a detached public view;
    -- no account, operation, owner or session identifiers are exposed.
    return S.Ok(S.Copy(snapshot))
end

function C.Install()
    return S.Core.Call('RegisterRpc', 'stables.catalog.get.v1', function(_, source, context)
        return C.Get(source, context)
    end, {
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
