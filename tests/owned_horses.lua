local base=assert(loadfile('tests/fixtures/fulfillment_services.lua'))()
local count=0
local function test(name,body)
    local ok,err=pcall(body); assert(ok,name..': '..tostring(err)); count=count+1; print('PASS owned horses '..name)
end
local function fixture()
    local m=base(); assert(m.fulfill().ok)
    assert(loadfile('server/owned_horses.lua','t',m.env))()
    m.h=m.S.OwnedHorses
    m.list=function(p) return m.h.List(p or {},1,m.context) end
    m.ownedGet=function(id) return m.h.Get({horseId=id or m.t.horseId},1,m.context) end
    return m
end
test('list and inspect verify saved projection against canonical horse',function()
    local m=fixture(); local r=m.list(); assert(r.ok and #r.value.items==1 and not r.value.selectionAvailable)
    local h=r.value.items[1]; assert(h.horseId==m.t.horseId and h.assetId==m.asset.assetId and h.modelKey==m.asset.modelKey)
    assert(h.characterId==nil and h.walletAccountId==nil and not h.gameplayAvailable)
    assert(m.ownedGet().value.assetId==h.assetId)
end)
test('other character has empty list and cannot inspect a known ID',function()
    local m=fixture(); m.context.characterId='20000000-0000-4000-8000-000000000099'
    assert(#m.list().value.items==0 and m.ownedGet().code=='horse_not_found')
end)
test('canonical ownership change omits cached horse without changing projection',function()
    local m=fixture(); m.asset.owner.holderId='20000000-0000-4000-8000-000000000099'
    assert(#m.list().value.items==0 and m.ownedGet().code=='horse_not_found')
    assert(m.db.horses[m.t.horseId].owner_character_id==m.t.characterId)
end)
test('canonical retired asset cannot be listed as owned',function()
    local m=fixture(); m.asset.status,m.asset.owner='retired',nil
    assert(#m.list().value.items==0 and m.ownedGet().code=='horse_not_found')
end)
test('provider errors are not reported as an empty owned list',function()
    local m=fixture(); m.S.Assets.ReadHorse=function() return m.S.Err('assets_unavailable','offline') end
    assert(m.list().code=='assets_unavailable' and m.ownedGet().code=='assets_unavailable')
end)
test('corrupt canonical metadata fails instead of authorizing cached identity',function()
    local m=fixture(); m.asset.metadata.stablesHorseId='bad'
    assert(m.list().code=='asset_changed' and m.ownedGet().code=='asset_changed')
end)
test('catalogue edits do not rewrite persisted horse model',function()
    local m=fixture(); m.env.StablesCatalogConfig={revision=99,entries={}}
    assert(m.list().value.items[1].modelKey=='a_c_horse_morgan_bay')
end)
test('canonical revisions cannot move behind the saved link',function()
    local m=fixture(); m.asset.revision=0; assert(m.list().code=='asset_changed')
    m.asset.revision=2; assert(m.ownedGet().value.assetRevision==2)
end)
test('session change during canonical read suppresses old-character view',function()
    local m=fixture(); m.onAssetRead=function() m.current=false end
    assert(m.list().code=='session_stale')
    m.current=true; assert(m.ownedGet().code=='session_stale')
end)
test('payloads reject supplied identity and malformed cursor',function()
    local m=fixture()
    assert(m.list({characterId=m.t.characterId}).code=='invalid_input')
    assert(m.list({afterHorseId='bad'}).code=='invalid_input')
    assert(m.h.Get({horseId=m.t.horseId,assetId=m.asset.assetId},1,m.context).code=='invalid_input')
end)
test('missing artifacts and unknown IDs fail closed',function()
    local m=fixture(); assert(m.ownedGet('10000000-0000-4000-8000-000000000099').code=='horse_not_found')
    m.db.history={}; assert(m.list().code=='fulfillment_incomplete')
end)
test('database errors remain failures',function()
    local m=fixture(); m.env.DB.query=function() error('offline') end
    assert(m.list().code=='database_error')
end)
test('keyset pages bound canonical work and advance cursor',function()
    local m=fixture(); m.db.horses={}; local reads=0
    for i=1,12 do local id=('10000000-0000-4000-8000-%012d'):format(i)
        m.db.horses[id]={horse_id=id,origin_operation_id=id,owner_character_id=m.t.characterId}
    end
    m.S.FulfillmentRepository.Get=function(id) return m.S.Ok({horseId=id,operationId=id,assetId=id,availability='stored'}) end
    m.S.AssetRegistration.Get=function(id) return m.S.Ok({state='linked',assetId=id,assetRevision=1,request={}}) end
    m.S.AssetRegistration.Matches=function() return true end
    m.S.Assets.ReadHorse=function(id) reads=reads+1; return m.S.Ok({assetId=id,revision=1,status='active',modelKey='a_c_horse_morgan_bay',
        owner={holderType='character',holderId=m.t.characterId}}) end
    local first=m.list().value; assert(#first.items==10 and reads==10 and first.nextCursor==first.items[10].horseId)
    local second=m.list({afterHorseId=first.nextCursor}).value
    assert(#second.items==2 and second.nextCursor==nil and reads==12)
end)
test('routes require Core character and strict bounded UUID payloads',function()
    local m=fixture(); local routes={}
    m.S.Core={Call=function(_,name,callback,options) routes[name]=options; return m.S.Ok(true) end}
    assert(m.h.Install().ok)
    local list=routes['stables.horses.list.v1']; local get=routes['stables.horses.get.v1']
    assert(list.requireCharacter and get.requireCharacter and list.maxPayloadBytes==128 and list.maxCalls==2)
    assert(list.validatePayload({}) and not get.validatePayload({}) and get.validatePayload({horseId=m.t.horseId}))
end)
print(count..'/'..count..' owned horse cases passed; live Core/Assets reads remain pending.')
