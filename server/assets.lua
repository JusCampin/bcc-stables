-- Narrow consumer boundary. No public mutation export, RPC or worker is installed.
Stables.Assets = {}
local A = Stables.Assets
local requirements = {
    lifecycle = 1,
    health = 1,
    registration = 1,
    ownership = 1,
    revisions = 1,
    idempotency = 1,
    operationLookup = 1,
    references = 1,
    holderValidation = 1,
}
-- Reserved for a read-only caller-access check; never use this ID for a mutation.
local probeRequestId = 'stables.contract.read.v1'

local function Call(method, ...)
    if GetResourceState('feather-assets') ~= 'started' then
        return Stables.Err('assets_unavailable', 'Feather Assets is not started.')
    end
    local args = table.pack(...)
    local called, result = pcall(function()
        local provider = exports['feather-assets']
        return provider[method](provider, table.unpack(args, 1, args.n))
    end)
    if not called then
        return Stables.Err('assets_dependency_error', 'An Assets operation failed; reconcile the same request ID.',
            { operation = method })
    end
    if not Stables.IsResult(result) then
        return Stables.Err('invalid_contract', 'Assets returned an invalid envelope.', { operation = method })
    end
    return result
end

-- Internal workflow calls only; transport success is not identity validation.
function A.FindRegistration(requestId) return Call('FindOperation', { requestId = requestId }) end

function A.ReadHorse(assetId) return Call('GetAsset', { assetId = assetId }) end

function A.RegisterHorse(request) return Call('RegisterAsset', Stables.Copy(request)) end

function A.RetireProof(request) return Call('RetireAsset', Stables.Copy(request)) end

function A.RequireReady()
    local result = Call('GetHealth')
    if not result.ok then return result end
    if type(result.value) ~= 'table' or result.value.state ~= 'ready' then
        return Stables.Err('assets_unavailable', 'Feather Assets is not ready.')
    end
    return Stables.Ok(true)
end

function A.Probe()
    local ready = A.RequireReady()
    if not ready.ok then return ready end
    local result = Call('GetCapabilities')
    if not result.ok then return result end
    local caps = result.value
    if type(caps) ~= 'table' or caps.resource ~= 'feather-assets' or caps.contract ~= 1
        or caps.state ~= 'ready' or type(caps.features) ~= 'table' or type(caps.assetTypes) ~= 'table' then
        return Stables.Err('unsupported_contract', 'Ready Feather Assets Contract 1 is required.')
    end
    for feature, contract in pairs(requirements) do
        if caps.features[feature] ~= contract then
            return Stables.Err('unsupported_contract', 'A required Assets feature is unavailable.', { feature = feature })
        end
    end
    local horses = false
    for _, assetType in ipairs(caps.assetTypes) do horses = horses or assetType == 'horse' end
    if not horses then return Stables.Err('unsupported_contract', 'Assets must enable the horse asset type.') end
    -- The real export derives bcc-stables from GetInvokingResource(). Capabilities
    -- alone do not prove this caller is a trusted reader. This creates no receipt.
    local lookup = Call('FindOperation', { requestId = probeRequestId })
    if not lookup.ok then return lookup end
    if type(lookup.value) ~= 'table' or lookup.value.found ~= false then
        return Stables.Err('invalid_contract', 'Reserved Assets read probe returned an unexpected receipt.')
    end
    return Stables.Ok({
        ok = true,
        contract = caps.contract,
        version = caps.version,
        horseType = true,
        trustedRead = true,
        registrationEnabled = StablesConfig.purchaseRegistration == true
    })
end

function A.Start()
    local waited = Call('AwaitReady', StablesConfig.startupTimeoutMs)
    if not waited.ok then return waited end
    return A.Probe()
end

RegisterCommand('BccStablesAssetsSmokeTest', function(source)
    if source ~= 0 then return end
    local result = A.Probe()
    print(('[BccStablesAssetsSmokeTest] Assets contract, horse type and trusted read %s%s'):format(
        result.ok and 'PASS' or 'FAIL', result.ok and '' or (' [' .. result.code .. ']')))
    print('[BccStablesAssetsSmokeTest] read-only; no assets registered, transferred or retired; no funds moved')
end, true)
