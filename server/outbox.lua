-- At-least-once Core publication. Consumers deduplicate the stable eventId.
Stables.Outbox = {}
local O, S = Stables.Outbox, Stables
local EVENT = 'stables.purchase.fulfilled.v1'
local enabled, automatic, active, busy = false, false, false, false
local generation = 0
local function Integer(v, min, max) return type(v) == 'number' and v % 1 == 0 and v >= min and v <= max end
local function Payload(p)
    if type(p) ~= 'table' or p.eventVersion ~= 1 or not S.Operations.IsUuid(p.operationId)
        or not S.Operations.IsUuid(p.horseId) or not S.Operations.IsUuid(p.assetId) or not S.Operations.IsUuid(p.characterId)
        or p.eventId ~= 'stables.fulfilled:' .. p.operationId
        or type(p.catalogId) ~= 'string' or #p.catalogId > 64 or not p.catalogId:match('^[a-z0-9][a-z0-9_.:%-]*$')
        or type(p.modelKey) ~= 'string' or #p.modelKey > 100 or not p.modelKey:match('^a_c_horse_[a-z0-9_]+$') then
        return false
    end
    local fields = { eventVersion = true, eventId = true, operationId = true, horseId = true, assetId = true, characterId = true, catalogId = true, modelKey = true }
    for key in pairs(p) do if not fields[key] then return false end end
    return true
end
function O.Start()
    local cfg = StablesConfig.outbox
    if type(cfg) ~= 'table' or type(cfg.enabled) ~= 'boolean' or type(cfg.automatic) ~= 'boolean'
        or (cfg.automatic and not cfg.enabled) then
        return S.Err('config_error', 'outbox requires boolean enabled/automatic; automatic requires enabled.')
    end
    local declared = S.Core.Call('DeclareEvent', EVENT,
        { contract = 1, maxPayloadBytes = 2048, maxDepth = 2, maxNodes = 32, validatePayload = Payload })
    if not declared.ok then return declared end
    enabled, automatic, active = cfg.enabled, cfg.automatic, true
    generation = generation + 1
    return S.Ok({ ok = true, enabled = enabled, automatic = automatic, eventDeclared = true, leaseSeconds = 60 })
end

function O.Stop()
    active = false; generation = generation + 1
end

local function Ready(epoch)
    if not active or generation ~= epoch then return S.Err('outbox_stopped', 'Outbox publication stopped.') end
    return S.Foundation.RequireReady()
end
local function Delivery(row, epoch)
    local attempts = tonumber(row.attempts)
    if not Integer(attempts, 0, 4294967294) then
        return S.Err('invalid_outbox', 'Invalid event row.')
    end
    -- Claim outside any transaction containing external calls. attempts is the
    -- fencing token; next_attempt_at is a bounded lease/retry deadline.
    local changed = DB.exec([[UPDATE fs_outbox SET attempts=attempts+1,
        next_attempt_at=DATE_ADD(CURRENT_TIMESTAMP,INTERVAL ? SECOND)
        WHERE event_id=? AND delivered=0 AND attempts=?
        AND (next_attempt_at IS NULL OR next_attempt_at<=CURRENT_TIMESTAMP)]], 60, row.event_id, attempts)
    if changed ~= 1 then return S.Ok({ claimed = false }) end
    local token = attempts + 1
    local function Retry(code)
        local delay = math.min(300, 5 * 2 ^ math.min(attempts, 6))
        DB.exec([[UPDATE fs_outbox SET next_attempt_at=DATE_ADD(CURRENT_TIMESTAMP,INTERVAL ? SECOND)
            WHERE event_id=? AND delivered=0 AND attempts=?]], delay, row.event_id, token)
        return S.Err(code or 'publication_failed', 'Event retained for same-ID retry.')
    end
    if row.event_name ~= EVENT or type(row.payload_json) ~= 'string' or #row.payload_json > 4096 then return Retry(
        'invalid_outbox') end
    local decoded, payload = pcall(json.decode, row.payload_json)
    if not decoded or type(payload) ~= 'table' or payload.eventId ~= nil then return Retry('invalid_outbox') end
    payload.eventId = row.event_id
    if not Payload(payload) or payload.operationId ~= row.operation_id then return Retry('invalid_outbox') end
    -- Validate all immutable history/projection/outbox artifacts. This event is
    -- historical; do not require today's canonical owner to equal the buyer.
    local saved = S.FulfillmentRepository.GetHistorical(payload.operationId, payload.characterId)
    if not saved.ok then return Retry(saved.code) end
    if saved.value.horseId ~= payload.horseId or saved.value.assetId ~= payload.assetId then return Retry(
        'invalid_outbox') end
    if tonumber(DB.value([[SELECT COUNT(*) FROM fs_outbox WHERE event_id=? AND delivered=0 AND attempts=?
        AND next_attempt_at>CURRENT_TIMESTAMP]], row.event_id, token)) ~= 1 then
        return S.Err('outbox_claim_lost', 'Publication lease expired or changed before dispatch.')
    end
    local ready = Ready(epoch); if not ready.ok then return ready end
    local published = S.Core.Call('PublishEvent', EVENT, payload)
    local v = published.ok and published.value
    if type(v) ~= 'table' or not Integer(v.delivered, 0, 100000) or v.failed ~= 0 then return Retry(published.code or
        'listener_failed') end
    ready = Ready(epoch); if not ready.ok then return ready end
    local acknowledged = DB.exec([[UPDATE fs_outbox SET delivered=1,next_attempt_at=NULL
        WHERE event_id=? AND delivered=0 AND attempts=?]], row.event_id, token)
    if acknowledged ~= 1 then return S.Err('outbox_ack_conflict',
            'Publication occurred but the claim changed; same event may replay.') end
    return S.Ok({ claimed = true, published = true, subscribers = v.delivered })
end
function O.Pump()
    if not enabled then return S.Err('outbox_disabled', 'Outbox publication is disabled.') end
    if busy then return S.Err('busy', 'Outbox publisher is already running.') end
    local epoch = generation
    local ready = Ready(epoch); if not ready.ok then return ready end
    busy = true
    local ok, result = pcall(function()
        local rows = DB.query([[SELECT event_id,operation_id,event_name,payload_json,attempts FROM fs_outbox
            WHERE delivered=0 AND event_name='stables.purchase.fulfilled.v1'
            AND (next_attempt_at IS NULL OR next_attempt_at<=CURRENT_TIMESTAMP)
            ORDER BY created_at,event_id LIMIT 10]])
        if type(rows) ~= 'table' then return S.Err('invalid_outbox', 'Database did not return an event batch.') end
        local stats = { scanned = #rows, acknowledged = 0, skipped = 0, failed = 0 }
        for _, row in ipairs(rows) do
            ready = Ready(epoch); if not ready.ok then return ready end
            local delivered = Delivery(row, epoch)
            if delivered.ok and delivered.value.published then
                stats.acknowledged = stats.acknowledged + 1
            elseif delivered.ok then
                stats.skipped = stats.skipped + 1
            else
                stats.failed = stats.failed + 1; stats.lastCode = delivered.code
            end
        end
        return S.Ok(stats)
    end)
    busy = false
    return ok and result or S.Persistence.DatabaseError(result)
end

function O.Run()
    if not enabled or not automatic then return end
    local epoch = generation
    CreateThread(function()
        while active and generation == epoch do
            local result = O.Pump()
            if not result.ok then print('[bcc-stables:outbox] ' .. result.code) end
            if result.ok and result.value.failed > 0 then print('[bcc-stables:outbox] retained for retry: ' ..
                tostring(result.value.lastCode)) end
            Wait(5000)
        end
    end)
end

function O.Status()
    local ready = S.Foundation.RequireReady(); if not ready.ok then return ready end
    local ok, result = pcall(function()
        return S.Ok({
            enabled = enabled,
            automatic = automatic,
            active = active,
            busy = busy,
            pending = tonumber(DB.value('SELECT COUNT(*) FROM fs_outbox WHERE delivered=0')),
            published = tonumber(DB.value('SELECT COUNT(*) FROM fs_outbox WHERE delivered=1'))
        })
    end)
    return ok and result or S.Persistence.DatabaseError(result)
end

RegisterCommand('BccStablesOutbox', function(source, args)
    if source ~= 0 then return end
    local action = args[1] or 'status'
    if action == 'status' then
        print('[bcc-stables:outbox] ' .. json.encode(O.Status())); return
    end
    if action ~= 'deliver' then
        print('[bcc-stables:outbox] usage: BccStablesOutbox status | deliver'); return
    end
    -- A scoped, read-only observer verifies actual Core callback transport.
    local observed = 0
    local subscribed = S.Core.Call('SubscribeEvent', EVENT, function() observed = observed + 1 end)
    if not subscribed.ok then
        print('[bcc-stables:outbox] ' .. json.encode(subscribed)); return
    end
    local token = type(subscribed.value) == 'table' and subscribed.value.token
    if type(token) ~= 'string' then
        print('[bcc-stables:outbox] invalid subscription'); return
    end
    local result = O.Pump()
    local removed = S.Core.Call('UnsubscribeEvent', token)
    if result.ok then
        result.value.observed = observed; result.value.observerRemoved = removed.ok
    end
    print('[bcc-stables:outbox] ' .. json.encode(result))
end, true)
