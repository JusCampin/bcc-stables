-- Feather integration boundary. Loaded by the new runtime once its lifecycle is
-- ported; deliberately not mixed with the VORP runtime in fxmanifest.lua.
Stables = Stables or {}
local F = {}
Stables.Feather = F

function F.Ok(value) return { ok = true, value = value } end
function F.Error(code, message) return { ok = false, code = code, message = message } end

function F.IsUuid(value)
    return type(value) == 'string' and value:match(
        '^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') ~= nil
end

function F.IsRevision(value)
    return type(value) == 'number' and value >= 0 and value <= 9007199254740991 and value % 1 == 0
end

function F.Call(resource, method, ...)
    if GetResourceState(resource) ~= 'started' then
        return F.Error('dependency_unavailable', resource .. ' is not started.')
    end
    local args = table.pack(...)
    local called, result = pcall(function()
        local provider = exports[resource]
        return provider[method](provider, table.unpack(args, 1, args.n))
    end)
    if not called then return F.Error('dependency_error', resource .. ':' .. method .. ' failed.') end
    if type(result) ~= 'table' or (result.ok ~= true and
        not (result.ok == false and type(result.code) == 'string' and type(result.message) == 'string')) then
        return F.Error('invalid_contract', resource .. ':' .. method .. ' returned an invalid result.')
    end
    return result
end

function F.IsCurrent(session)
    if type(session) ~= 'table' or GetResourceState('feather-core') ~= 'started' then return false end
    local called, current = pcall(function()
        return exports['feather-core']:IsSessionCurrent(session.source, session.sessionId, session.characterId)
    end)
    return called and current == true
end

function F.RequireSession(source)
    if type(source) ~= 'number' or source < 1 or source % 1 ~= 0 then
        return F.Error('character_required', 'A current player character is required.')
    end
    local result = F.Call('feather-core', 'RequireSession', source)
    if not result.ok then return result end
    local session = result.value
    if type(session) ~= 'table' or session.source ~= source or session.state ~= 'ready'
        or not F.IsUuid(session.characterId) or not F.IsUuid(session.sessionId)
        or not F.IsUuid(session.accountId) then
        return F.Error('invalid_contract', 'Core returned an invalid character session.')
    end
    -- Capture scalars: provider-owned tables must not change our authorization.
    session = { source = source, state = 'ready', characterId = session.characterId,
        sessionId = session.sessionId, accountId = session.accountId }
    if not F.IsCurrent(session) then return F.Error('session_stale', 'The character session changed.') end
    return F.Ok(session)
end
