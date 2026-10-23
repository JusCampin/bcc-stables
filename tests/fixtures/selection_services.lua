local base=assert(loadfile('tests/fixtures/fulfillment_services.lua'))()
local function fixture()
    local m=base(); assert(m.fulfill().ok)
    for _,file in ipairs({'server/owned_horses.lua','server/selection.lua'}) do assert(loadfile(file,'t',m.env))() end
    m.env.StablesConfig.horseSelection=true; m.c=m.S.Selection; assert(m.c.Start().ok)
    m.selected=function() return m.c.Get({},1,m.context) end
    m.select=function(revision) return m.c.Set({horseId=m.t.horseId,expectedRevision=revision},1,m.context) end
    m.clear=function(revision) return m.c.Clear({expectedRevision=revision},1,m.context) end
    m.stable=function() return m.db.characters[m.t.characterId] end
    return m
end
return fixture
