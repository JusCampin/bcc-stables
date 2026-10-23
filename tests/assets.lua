local count = 0
local function test(name, fn) fn(); count = count + 1; print('PASS assets ' .. name) end
local function fixture()
    local env = setmetatable({}, { __index = _G })
    local m = { state = 'started', calls = {}, commands = {}, lines = {} }
    env.GetResourceState = function() return m.state end
    env.RegisterCommand = function(name, fn) m.commands[name] = fn end
    env.print = function(line) m.lines[#m.lines + 1] = line end
    local caps = { resource = 'feather-assets', contract = 1, version = '0.2.1', state = 'ready',
        assetTypes = { 'boat', 'horse', 'wagon' }, features = {
            lifecycle=1,health=1,registration=1,ownership=1,revisions=1,
            idempotency=1,operationLookup=1,references=1,holderValidation=1,
        } }
    m.caps = caps
    m.methods = {
        AwaitReady = function(timeout) assert(timeout == 30000); return { ok=true,value={state='ready'} } end,
        GetHealth = function() return { ok=true,value={state='ready'} } end,
        GetCapabilities = function() return { ok=true,value=caps } end,
        FindOperation = function(request)
            assert(request.requestId == 'stables.contract.read.v1' and next(request,'requestId') == nil)
            return { ok=true,value={found=false} }
        end,
    }
    local provider = {}
    for name in pairs(m.methods) do
        -- Model CFX callable tables as well as the export's self argument.
        provider[name] = setmetatable({ __cfx_functionReference = name }, { __call = function(_, self, ...)
            assert(self == provider); m.calls[#m.calls+1] = name
            return m.methods[name](...)
        end })
    end
    env.exports = { ['feather-assets'] = provider }
    for _,file in ipairs({'config.lua','shared/contracts.lua','server/assets.lua'}) do assert(loadfile(file,'t',env))() end
    m.a = env.Stables.Assets
    return m
end

test('startup validates real read access through callable exports without mutations',function()
    local m=fixture(); local r=m.a.Start(); assert(r.ok and r.value.trustedRead and r.value.registrationEnabled==false)
    assert(table.concat(m.calls,',')=='AwaitReady,GetHealth,GetCapabilities,FindOperation')
end)
test('stopped dependency invokes no export',function()
    local m=fixture(); m.state='stopped'; assert(m.a.Start().code=='assets_unavailable' and #m.calls==0)
end)
test('startup readiness refusal is preserved',function()
    local m=fixture(); m.methods.AwaitReady=function() return {ok=false,code='not_ready',message='Booting.'} end
    assert(m.a.Start().code=='not_ready' and #m.calls==1)
end)
test('degraded health refuses even with compatible capabilities',function()
    local m=fixture(); m.methods.GetHealth=function() return {ok=true,value={state='failed'}} end
    assert(m.a.Probe().code=='assets_unavailable' and #m.calls==1)
end)
test('wrong resource contract or missing horse type is refused',function()
    for _,field in ipairs({'resource','contract','assetTypes'}) do
        local m=fixture(); m.caps[field]=field=='assetTypes' and {'wagon'} or 'wrong'
        assert(m.a.Probe().code=='unsupported_contract')
    end
end)
test('required feature versions must match exactly',function()
    for _,feature in ipairs({'lifecycle','health','registration','ownership','revisions','idempotency','operationLookup','references','holderValidation'}) do
        for _,bad in ipairs({false,2,'1'}) do
            local m=fixture(); m.caps.features[feature]=bad; assert(m.a.Probe().code=='unsupported_contract')
        end
    end
end)
test('trusted reader denial is not mistaken for capability success',function()
    local m=fixture(); m.methods.FindOperation=function() return {ok=false,code='forbidden',message='Untrusted.'} end
    assert(m.a.Probe().code=='forbidden')
end)
test('unexpected probe receipt and malformed lookup fail closed',function()
    for _,value in ipairs({{}, {found=true,result={assetId='unexpected'}}}) do
        local m=fixture(); m.methods.FindOperation=function() return {ok=true,value=value} end
        assert(m.a.Probe().code=='invalid_contract')
    end
end)
test('export exceptions and malformed envelopes are contained',function()
    local m=fixture(); m.methods.GetHealth=function() error('transport') end
    assert(m.a.RequireReady().code=='assets_dependency_error')
    m.methods.GetHealth=function() return nil end
    assert(m.a.RequireReady().code=='invalid_contract')
end)
test('smoke command ignores clients and only performs reads',function()
    local m=fixture(); local cmd=m.commands.BccStablesAssetsSmokeTest
    cmd(12); assert(#m.calls==0 and #m.lines==0)
    cmd(0); assert(#m.calls==3 and m.lines[1]:find('PASS',1,true))
end)
print(('%d/%d Assets cases passed; cross-resource transport remains a live gate.'):format(count,count))
