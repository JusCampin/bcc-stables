local base=assert(loadfile('tests/fixtures/linked_services.lua'))()
local function fixture(kind)
    local m=base(false,{kind=kind or 'quote_admission_v1',stableId='valentine',stableRevision=1,
        modelKey='a_c_horse_morgan_bay',precision=2})
    local S,e=m.S,m.env
    m.context={source=1,sessionId='a',characterId=m.t.characterId,accountId='account-a'}; m.current=true
    S.Foundation.CheckSession=function(source,context)
        assert(not m.inTx); return m.current and source==1 and context.sessionId==m.context.sessionId and S.Ok(true) or S.Err('session_stale','stale')
    end
    for _,file in ipairs({'server/quote_intents.lua','server/horse_projection.lua','server/fulfillment_repository.lua','server/fulfillment.lua'}) do assert(loadfile(file,'t',e))() end
    S.OwnedSnapshot={Get=function(id,char) return S.FulfillmentRepository.GetOwnedSnapshot(id,char) end}
    e.StablesConfig.purchaseFulfillment=true; assert(S.Fulfillment.Start().ok)
    m.fulfill=function() return S.Fulfillment.Commit({operationId=m.t.operationId},1,m.context) end
    m.get=function() return S.Fulfillment.Get({operationId=m.t.operationId},1,m.context) end
    return m
end
return fixture
