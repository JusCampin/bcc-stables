local count=0
local function test(name,fn) fn(); count=count+1; print('PASS catalogue '..name) end
local function fixture()
    local env=setmetatable({}, {__index=_G})
    for _,file in ipairs({'shared/contracts.lua','config/catalog.lua','server/catalog.lua'}) do assert(loadfile(file,'t',env))() end
    local S=env.Stables; local m={s=S,env=env,reads=0,session={source=17,sessionId='current'}}
    S.Economy={Currency=function(code)
        m.reads=m.reads+1
        return m.currencyError and S.Err('currency_not_found','Unknown currency.') or S.Ok(m.badCurrency or {code=code,precision=2})
    end}
    S.Foundation={CheckSession=function(source,context)
        if source~=17 then return S.Err('character_required','No session.') end
        if context~=m.session then return S.Err('session_stale','Changed session.') end
        return S.Ok({sessionCurrent=true})
    end}
    S.Core={Call=function(method,route,callback,options)
        assert(method=='RegisterRpc'); m.route,m.callback,m.options=route,callback,options
        return S.Ok(true)
    end}
    m.start=function() return S.Catalog.Start() end
    m.get=function() return S.Catalog.Get(17,m.session) end
    return m
end
test('server-owned price and currency precision exposed without purchase authority',function()
    local m=fixture(); assert(m.start().ok)
    local value=m.get().value; assert(value.revision==1 and #value.items==1 and value.purchasesAvailable==false)
    assert(value.items[1].price.amount==10000 and value.items[1].price.precision==2)
    assert(value.characterId==nil and value.sessionId==nil)
end)
test('invalid prices models IDs labels and extra fields fail startup',function()
    for _,change in ipairs({function(e) e.amount=0 end,function(e) e.amount=1.1 end,function(e) e.amount=1000000001 end,
        function(e) e.modelKey='wagon02x' end,function(e) e.id='bad|id' end,function(e) e.label='' end,
        function(e) e.ownerId='spoof' end}) do
        local m=fixture(); change(m.env.StablesCatalogConfig.entries[1]); assert(m.start().code=='catalog_config_error')
    end
end)
test('duplicate entries and non-array keys are rejected',function()
    local m=fixture(); m.env.StablesCatalogConfig.entries[2]=m.env.StablesCatalogConfig.entries[1]
    assert(m.start().code=='catalog_config_error')
    m=fixture(); m.env.StablesCatalogConfig.entries.hidden={}; assert(m.start().code=='catalog_config_error')
end)
test('revision bounds and catalogue size are validated',function()
    local m=fixture(); m.env.StablesCatalogConfig.revision=0; assert(m.start().code=='catalog_config_error')
    m=fixture(); m.env.StablesCatalogConfig.entries={}; assert(m.start().code=='catalog_config_error')
    m=fixture(); for i=2,33 do m.env.StablesCatalogConfig.entries[i]=m.env.StablesCatalogConfig.entries[1] end
    assert(m.start().code=='catalog_config_error')
end)
test('Economy rejection or malformed currency cannot initialize prices',function()
    local m=fixture(); m.currencyError=true; assert(m.start().code=='currency_not_found')
    for _,v in ipairs({{}, {code='gold',precision=2},{code='dollars',precision=1.1},{code='dollars',precision=9}}) do
        m=fixture(); m.badCurrency=v; assert(m.start().code=='invalid_contract')
    end
end)
test('sort order deterministic and each currency resolved once',function()
    local m=fixture(); local second=m.s.Copy(m.env.StablesCatalogConfig.entries[1]); second.id='arabian_example'
    m.env.StablesCatalogConfig.entries[2]=second; assert(m.start().ok and m.reads==1)
    assert(m.get().value.items[1].id=='arabian_example')
end)
test('config and consumer mutations cannot change the frozen public snapshot',function()
    local m=fixture(); assert(m.start().ok)
    m.env.StablesCatalogConfig.entries[1].amount=1
    local value=m.get().value; value.items[1].price.amount=2
    assert(m.get().value.items[1].price.amount==10000 and m.reads==1)
end)
test('catalogue shares current-session validation and denies missing characters',function()
    local m=fixture(); assert(m.start().ok)
    assert(m.s.Catalog.Get(17,{}).code=='session_stale')
    assert(m.s.Catalog.Get(18,m.session).code=='character_required')
end)
test('empty bounded character route rejects injected identities and prices',function()
    local m=fixture(); assert(m.start().ok and m.s.Catalog.Install().ok)
    assert(m.route=='stables.catalog.get.v1' and m.options.requireCharacter and m.options.maxPayloadBytes==64)
    assert(m.options.maxDepth==2 and m.options.maxNodes==4 and m.options.maxCalls==2)
    assert(m.options.validatePayload({}) and not m.options.validatePayload({price=1}))
    assert(m.callback({},17,m.session).ok)
end)
test('uninitialized catalogue refuses reads',function()
    local m=fixture(); assert(m.get().code=='not_ready')
end)
print(('%d/%d catalogue cases passed; no native entities or money.'):format(count,count))
