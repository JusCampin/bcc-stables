local passed=0
local function test(name,body)
    local ok,err=pcall(body); assert(ok,name..': '..tostring(err)); passed=passed+1
    print('PASS '..name)
end
local function fixture()
    local e=setmetatable({},{__index=_G})
    e.RegisterCommand=function() end
    local m={time=0,bucket=0,exists=1,current=true,serial=0}
    for _,file in ipairs({'config/catalog.lua','config/locations.lua','shared/contracts.lua','server/operations.lua','server/catalog.lua','server/locations.lua','server/quotes.lua'}) do assert(loadfile(file,'t',e))() end
    local s=e.Stables
    e.GetResourceState=function() return 'started' end
    s.Core={RequireSession=function() return s.Ok(s.Copy(m.context)) end}
    e.exports={['feather-routing']={
        GetPlayerRoute=function() return s.Ok(nil) end,
        CreateRoute=function() return s.Ok({routeId='route-a'}) end,
        JoinRoute=function() if m.joinError then return s.Err('join_failed','failed') end; m.bucket=7; return s.Ok(true) end,
        DeleteRoute=function() m.deletions=(m.deletions or 0)+1
            if m.deleteError then return s.Err('delete_failed','failed') end
            m.bucket=0; return s.Ok(true)
        end,
    }}
    m.context={sessionId='a',characterId='c',accountId='u'}
    e.GetGameTimer=function() return m.time end
    e.GetPlayerRoutingBucket=function() return m.bucket end
    e.GetPlayerPed=function() return 10 end
    e.DoesEntityExist=function() return m.exists end
    e.GetEntityCoords=function() return m.position end
    m.position=s.Copy(e.StablesLocationsConfig.locations[1].position)
    s.Foundation={CheckSession=function(_,context)
        if not m.current or context.sessionId~=m.context.sessionId then return s.Err('session_stale','stale') end
        return s.Ok(true)
    end}
    s.Economy={Currency=function(code) return s.Ok({code=code,precision=2}) end}
    s.Persistence={DatabaseError=function() return s.Err('database_error','failed') end}
    e.DB={value=function(sql)
        assert(sql=='SELECT UUID()'); m.serial=m.serial+1
        if m.yield then m.yield() end
        return m.fixedId or ('00000000-0000-4000-8000-%012d'):format(m.serial)
    end}
    assert(s.Catalog.Start().ok); assert(s.Locations.Start().ok); assert(s.Quotes.Start().ok)
    m.s,m.e=s,e
    m.create=function(source) return s.Quotes.Create({stableId='valentine',catalogId='morgan_bay'},source or 1,m.context) end
    m.get=function(id,source,context) return s.Quotes.Get({quoteId=id},source or 1,context or m.context) end
    return m
end
test('quote derives price and returns detached draft',function()
    local m=fixture(); local v=m.create().value
    assert(v.price.amount==10000 and v.confirmAvailable==false and v.expiresInMs==45000)
    v.price.amount=1; assert(m.get(v.quoteId).value.price.amount==10000)
end)
test('quote expiry is enforced at exact deadline',function()
    local m=fixture(); local v=m.create().value; m.time=45000
    assert(m.get(v.quoteId).code=='quote_expired'); assert(m.get(v.quoteId).code=='quote_not_found')
end)
test('quote rejects supplied identity or price',function()
    local m=fixture()
    for _,key in ipairs({'price','amount','characterId','source'}) do
        local p={stableId='valentine',catalogId='morgan_bay'}; p[key]=1
        assert(m.s.Quotes.Create(p,1,m.context).code=='invalid_input')
    end
end)
test('location rejects distant foreign and unobserved characters',function()
    local m=fixture(); m.bucket=1; assert(m.create().code=='foreign_route')
    m.bucket=0; m.exists=false; assert(m.create().code=='position_unavailable')
    m.exists=1; m.position.x=0; assert(m.create().code=='too_far')
    m.position.x=0/0; assert(m.create().code=='position_unavailable')
end)
test('quotes are source and session bound',function()
    local m=fixture(); local id=m.create().value.quoteId
    assert(m.get(id,2).code=='quote_not_found')
    m.context={sessionId='b',characterId='c',accountId='u'}
    assert(m.get(id).code=='quote_not_found')
end)
test('replacement and logout invalidate only matching session',function()
    local m=fixture(); local old=m.create().value.quoteId; local id=m.create().value.quoteId
    assert(m.get(old).code=='quote_not_found')
    m.s.Quotes.SessionEvent('left',{sessionId='old'}); assert(m.get(id).ok)
    m.s.Quotes.SessionEvent('leaving',m.context); assert(m.get(id).code=='quote_not_found')
end)
test('quote rechecks session after yielding UUID read',function()
    local m=fixture(); m.yield=function() m.current=false end
    assert(m.create().code=='session_stale')
end)
test('quote rechecks position after yielding UUID read',function()
    local m=fixture(); m.yield=function() m.position.x=0 end
    assert(m.create().code=='too_far')
end)
test('quote rechecks route after yielding UUID read',function()
    local m=fixture(); m.yield=function() m.bucket=1 end
    assert(m.create().code=='foreign_route')
end)
test('quote rechecks catalogue terms after yielding UUID read',function()
    local m=fixture(); m.yield=function()
        m.e.StablesCatalogConfig.revision=2; assert(m.s.Catalog.Start().ok)
    end
    assert(m.create().code=='quote_stale')
end)
test('bounded quote capacity releases expired entries',function()
    local m=fixture(); m.e.StablesLocationsConfig.maxQuotes=1
    assert(m.s.Locations.Start().ok); assert(m.s.Quotes.Start().ok)
    assert(m.create().ok); assert(m.create(2).code=='quote_limit')
    m.time=45000; assert(m.create(2).ok)
end)
test('duplicate UUID cannot replace existing quote',function()
    local m=fixture(); local id=m.create().value.quoteId; m.fixedId=id
    assert(m.create().code=='quote_conflict'); assert(m.get(id).ok)
end)
test('shutdown clears quotes and timer wrap expires conservatively',function()
    local m=fixture(); local id=m.create().value.quoteId; m.time=-1
    assert(m.get(id).code=='quote_expired'); m.time=0
    id=m.create().value.quoteId; m.s.Quotes.Stop(); assert(m.get(id).code=='quote_not_found')
end)
test('locations reject unknown catalogues and invalid config',function()
    local m=fixture(); assert(m.s.Locations.Check(1,'valentine','missing').code=='catalog_unavailable')
    m.e.StablesLocationsConfig.locations[1].radius=math.huge
    assert(m.s.Locations.Start().code=='location_config_error')
end)
test('quote route proof denies reads and creates then restores world',function()
    local m=fixture(); local id=m.create().value.quoteId
    local result=m.s.Quotes.RouteTest(1,id)
    assert(result.ok and result.value.readDenied and result.value.createDenied and result.value.returnedToDefault
        and result.value.quoteStillReadable and m.deletions==1)
end)
test('quote route proof cleans up failed join',function()
    local m=fixture(); local id=m.create().value.quoteId; m.joinError=true
    assert(m.s.Quotes.RouteTest(1,id).code=='join_failed'); assert(m.deletions==1 and m.bucket==0)
end)
test('quote route proof retains failed cleanup and blocks another run',function()
    local m=fixture(); local id=m.create().value.quoteId; m.deleteError=true
    assert(m.s.Quotes.RouteTest(1,id).code=='route_cleanup_failed')
    assert(m.s.Quotes.RouteTest(1,id).code=='busy')
end)
test('quote route proof refuses absent quote before moving player',function()
    local m=fixture()
    assert(m.s.Quotes.RouteTest(1,'00000000-0000-4000-8000-000000000001').code=='quote_not_found')
    assert(not m.deletions and m.bucket==0)
end)
print(passed..'/'..passed..' stable quote cases passed; live natives and RPC remain pending.')
