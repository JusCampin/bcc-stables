local passed=0
local function test(name,body)
    local ok,err=pcall(body); assert(ok,name..': '..tostring(err)); passed=passed+1; print('PASS owned menu '..name)
end
local H='a0000000-0000-4000-8000-000000000001'
local A='b0000000-0000-4000-8000-000000000001'
local O='c0000000-0000-4000-8000-000000000001'
local function copy(value)
    if type(value)~='table' then return value end
    local result={}; for k,v in pairs(value) do result[k]=copy(v) end; return result
end
-- Run schema integration when the sibling provider source is available, while
-- keeping the Stables behavior suite runnable from a standalone repo checkout.
local V
local providerRoot=os.getenv('STABLES_MENU_VALIDATION_ROOT') or '../../feather-scripts/feather-menu-v2'
local source=io.open(providerRoot..'/client/validation.lua','r')
if source then
    source:close()
    local validator=setmetatable({},{__index=_G})
    assert(loadfile(providerRoot..'/client/results.lua','t',validator))()
    assert(loadfile(providerRoot..'/client/validation.lua','t',validator))()
    V=validator.MenuValidation
else
    print('SKIP optional Menu v2 schema integration: set STABLES_MENU_VALIDATION_ROOT; behavior cases still run.')
    V={Menu=function() end,Page=function() end,Element=function() end,OpenOptions=function() end}
end

local function fixture()
    local m={time=0,commands={},events={},handlers={},logs={},rpc={},elements={},buttons={},menus={},created=0,destroyed=0,openCount=0}
    local e=setmetatable({},{__index=_G})
    local function ok(value) return {ok=true,value=value or {}} end
    m.horse={horseId=H,assetId=A,operationId=O,modelKey='a_c_horse_morgan_bay',availability='stored',
        projectionRevision=136,assetRevision=1,gameplayAvailable=false}
    m.page={items={copy(m.horse)},pageSize=10,selectionAvailable=true,gameplayAvailable=false}
    m.selection={revision=19,selected=true,available=true,horse=copy(m.horse),gameplayAvailable=false}
    e.GetResourceState=function(name) return m.stopped==name and 'stopped' or 'started' end
    e.GetCurrentResourceName=function() return 'bcc-stables' end
    e.GetGameTimer=function() return m.time end
    e.Wait=function(ms) m.time=m.time+math.max(ms,1); if m.onWait then m.onWait(ms) end end
    e.CreateThread=function(fn) fn() end
    e.RegisterCommand=function(name,fn) m.commands[name]=fn end
    e.RegisterNetEvent=function(name,fn) m.events[name]=fn end
    e.AddEventHandler=function(name,fn) m.handlers[name]=fn end
    e.print=function(line) m.logs[#m.logs+1]=line end
    e.source=65535
    local menu={}
    menu.GetCapabilities=function() return ok({contract=m.contract or 1,features={menus=1,pages=1,elements=1,focus=1,ownerCleanup=1,boundedValidation=1,reactiveState=1}}) end
    menu.AwaitReady=function() return m.notReady and {ok=false,code='timeout'} or ok({state='ready'}) end
    menu.CreateMenu=function(_,spec)
        assert(not V.Menu(spec,'spec',true)); assert(not m.menus.owned)
        m.created=m.created+1; m.menus.owned={}; m.buttons={}; m.elements={}; m.lifecycle=nil; return ok({menuId='owned'})
    end
    menu.CreatePage=function(_,id,spec)
        assert(id=='owned' and not V.Page(spec,'spec',true)); return ok({pageId='horses'})
    end
    menu.AddElement=function(_,id,page,kind,spec,callback)
        assert(id=='owned' and page=='horses' and not V.Element(kind,spec,'spec'))
        if m.failElement then return {ok=false,code='limit_exceeded'} end
        m.elements[#m.elements+1]={kind=kind,spec=copy(spec)}
        if callback then m.buttons[spec.key]=callback end
        return ok({elementId=spec.key})
    end
    menu.UpdateElement=function(_,id,page,element,changes)
        assert(id=='owned' and page=='horses')
        local key=element:match('[^/]+$')
        for i=#m.elements,1,-1 do
            local entry=m.elements[i]
            if entry.spec.key==key then
                local merged=copy(entry.spec); for k,v in pairs(changes) do merged[k]=v end
                assert(not V.Element(entry.kind,merged,'spec'))
                entry.spec=merged
                if key=='notice' then m.notice=changes.value end
                return ok()
            end
        end
        error('element not found')
    end
    menu.RegisterMenuLifecycle=function(_,_,callback) m.lifecycle=callback; return ok() end
    menu.OpenMenu=function(_,id,options)
        assert(id=='owned' and not V.OpenOptions(options) and options.replace==false)
        if m.otherMenu then return {ok=false,code='focus_unavailable'} end
        m.openCount=m.openCount+1; m.active=id; return ok()
    end
    menu.DestroyMenu=function(_,id)
        assert(id=='owned'); m.destroyed=m.destroyed+1; m.menus.owned=nil; m.active=nil
        if m.lifecycle then m.lifecycle({event='closed'}) end
        return ok()
    end
    e.exports={['feather-menu-v2']=menu,['feather-core']={CallRPC=function(_,route,payload,callback,source,timeout)
        assert(source==nil and timeout==5000)
        assert(route=='stables.horses.list.v1' or route=='stables.horses.selection.get.v1'
            or route=='stables.horses.selection.set.v1' or route=='stables.horses.selection.clear.v1','Unexpected menu route')
        m.rpc[#m.rpc+1]={route=route,payload=copy(payload),at=m.time}
        if m.rpcOverride then return m.rpcOverride(route,payload,callback) end
        if route=='stables.horses.selection.clear.v1' then
            assert(payload.expectedRevision==m.selection.revision and payload.horseId==nil)
            m.selection={revision=m.selection.revision+1,selected=false,available=false,gameplayAvailable=false}
        elseif route=='stables.horses.selection.set.v1' then
            assert(payload.expectedRevision==m.selection.revision and payload.horseId==H)
            m.selection={revision=m.selection.revision+1,selected=true,available=true,horse=copy(m.horse),gameplayAvailable=false}
        end
        callback(ok(copy(route=='stables.horses.list.v1' and m.page or m.selection)))
    end}}
    assert(loadfile('client/owned_menu.lua','t',e))(); m.env=e
    m.open=function() m.commands.BccStablesMenu(0,{}) end
    return m
end

test('renders bounded selected horse without writes or internal IDs',function()
    local m=fixture(); m.open()
    assert(m.openCount==1 and #m.rpc==2)
    local label,status=false,false
    for _,element in ipairs(m.elements) do
        if element.spec.value=='Morgan Bay' then label=true end
        if element.spec.value=='Selected · Stored' then status=true end
        assert(not tostring(element.spec.value):find(H,1,true))
    end
    assert(label and status and m.buttons.refresh and m.buttons.close)
end)

test('independent owned and selected requests start together before awaiting',function()
    local m=fixture(); local pending={}
    m.rpcOverride=function(route,_,cb) pending[route]=cb end
    m.onWait=function()
        assert(#m.rpc==2)
        pending['stables.horses.list.v1']({ok=true,value=copy(m.page)})
        pending['stables.horses.selection.get.v1']({ok=true,value=copy(m.selection)})
    end
    m.open(); assert(m.openCount==1)
end)

test('empty page and unavailable selection render with no invented horse',function()
    local m=fixture(); m.page.items={}; m.selection={revision=0,selected=false,available=false,gameplayAvailable=false}
    m.open(); assert(m.openCount==1)
    for _,element in ipairs(m.elements) do assert(element.spec.value~='Morgan Bay') end
end)

test('missing incompatible and unready Menu fail without RPC or legacy fallback',function()
    for _,mode in ipairs({'missing','contract','ready'}) do
        local m=fixture()
        if mode=='missing' then m.stopped='feather-menu-v2' end
        if mode=='contract' then m.contract=2 end
        if mode=='ready' then m.notReady=true end
        m.open(); assert(m.openCount==0 and #m.rpc==0 and #m.logs==1)
    end
end)

test('no-character error tuple malformed replies and invalid projections never render',function()
    for _,mode in ipairs({'session','horse','order','selection','cursor','array'}) do
        local m=fixture()
        if mode=='session' then m.rpcOverride=function(_,_,cb) cb(nil,{code='character_required'}) end end
        if mode=='horse' then m.page.items[1].projectionRevision=1 end
        if mode=='order' then m.page.items[2]=copy(m.horse) end
        if mode=='selection' then m.selection.horse.assetId='bad' end
        if mode=='cursor' then m.page.nextCursor='bad' end
        if mode=='array' then m.page.items.extra=copy(m.horse) end
        m.open(); assert(m.openCount==0 and m.created==0)
    end
end)

test('server session invalidation cancels pending reads and blocks late reply rendering',function()
    local m=fixture(); local callbacks={}
    m.rpcOverride=function(_,_,cb) callbacks[#callbacks+1]=cb end
    m.onWait=function() m.events['bcc-stables:menu:invalidate']() end
    m.open(); assert(m.created==0 and m.openCount==0)
    callbacks[1]({ok=true,value=copy(m.page)}); callbacks[2]({ok=true,value=copy(m.selection)})
    assert(m.created==0)
end)

test('server invalidation closes menu and stale callbacks cannot reopen or read again',function()
    local m=fixture(); m.open(); local refresh=m.buttons.refresh
    m.events['bcc-stables:menu:invalidate'](); local count=#m.rpc
    assert(not m.active and m.destroyed==1)
    refresh(); assert(#m.rpc==count and m.openCount==1)
end)

test('forged local invalidation does not close the owned view',function()
    local m=fixture(); m.open(); m.env.source=1
    m.events['bcc-stables:menu:invalidate'](); assert(m.active=='owned')
end)

test('timeout ignores late replies without retries or menu allocation',function()
    local m=fixture(); local callbacks={}
    m.rpcOverride=function(_,_,cb) callbacks[#callbacks+1]=cb end
    m.open(); assert(#m.rpc==2 and m.time==6000 and m.created==0)
    callbacks[1]({ok=true,value=copy(m.page)}); callbacks[2]({ok=true,value=copy(m.selection)})
    assert(m.openCount==0)
end)

test('read-only pagination and Previous preserve cursor boundaries and refresh only on action',function()
    local m=fixture(); local nextId='a0000000-0000-4000-8000-000000000002'
    m.page.nextCursor=H; m.open(); assert(m.buttons.next)
    local second=copy(m.horse); second.horseId=nextId
    m.page={items={second},pageSize=10,selectionAvailable=true,gameplayAvailable=false}
    m.buttons.next(); assert(m.rpc[3].payload.afterHorseId==H and m.buttons.previous)
    m.page={items={copy(m.horse)},pageSize=10,selectionAvailable=true,gameplayAvailable=false}
    m.buttons.previous(); assert(next(m.rpc[5].payload)==nil and m.openCount==3)
    local before=#m.rpc; m.time=m.time+60000; assert(#m.rpc==before)
end)

test('Close lifecycle dependency stop and partial build failure destroy only owned menu',function()
    for _,mode in ipairs({'button','escape','core','build'}) do
        local m=fixture(); if mode=='build' then m.failElement=true end
        m.open()
        if mode=='button' then m.buttons.close() end
        if mode=='escape' then m.lifecycle({event='closed'}) end
        if mode=='core' then m.handlers.onClientResourceStop('feather-core') end
        assert(m.destroyed==1 and not m.active)
    end
end)

test('menu never steals another resource focus and rejects command arguments',function()
    local m=fixture(); m.otherMenu=true; m.open()
    assert(m.openCount==0 and m.otherMenu and m.destroyed==1)
    local n=#m.rpc; m.commands.BccStablesMenu(0,{H}); assert(#m.rpc==n)
end)

test('rapid menu refreshes stay within existing read-route budgets without retrying',function()
    local m=fixture(); m.open(); m.buttons.refresh(); m.buttons.refresh()
    assert(m.openCount==3 and #m.rpc==6)
    assert(m.rpc[5].at-m.rpc[1].at>=2000)
end)

test('Unselect and Select use snapshot revisions and refresh server truth without spawning',function()
    local m=fixture(); m.open(); assert(m.buttons.unselect and not m.buttons['select-1'])
    m.buttons.unselect()
    assert(m.rpc[3].route=='stables.horses.selection.clear.v1' and m.rpc[3].payload.expectedRevision==19)
    assert(m.selection.revision==20 and not m.selection.selected and m.buttons['select-1'] and not m.buttons.unselect)
    m.buttons['select-1']()
    assert(m.rpc[6].route=='stables.horses.selection.set.v1' and m.rpc[6].payload.expectedRevision==20 and m.rpc[6].payload.horseId==H)
    assert(m.selection.revision==21 and m.selection.horse.horseId==H and m.buttons.unselect)
end)

test('selection controls are absent when server selection feature is disabled',function()
    local m=fixture(); m.page.selectionAvailable=false; m.open()
    assert(not m.buttons.unselect and not m.buttons['select-1'] and #m.rpc==2)
end)

test('selection conflicts and busy refusals show useful feedback and require explicit refresh',function()
    for _,code in ipairs({'revision_conflict','horse_busy','selection_disabled'}) do
        local m=fixture(); m.open(); local choose=m.buttons.unselect
        m.rpcOverride=function(route,_,cb)
            assert(route=='stables.horses.selection.clear.v1')
            cb({ok=false,code=code})
        end
        choose(); assert(#m.rpc==3 and m.notice and m.notice~='Updating selection...')
        choose(); assert(#m.rpc==3 and m.selection.revision==19)
        m.rpcOverride=nil; m.buttons.refresh(); assert(#m.rpc==5 and m.openCount==2)
    end
end)

test('rapid overlapping selection callbacks submit exactly one mutation',function()
    local m=fixture(); m.open(); local choose=m.buttons.unselect
    m.rpcOverride=function(route,_,cb)
        assert(route=='stables.horses.selection.clear.v1')
        local before=#m.rpc; choose(); assert(#m.rpc==before)
        m.selection={revision=20,selected=false,available=false,gameplayAvailable=false}
        m.rpcOverride=nil; cb({ok=true,value=copy(m.selection)})
    end
    choose(); assert(#m.rpc==5 and m.selection.revision==20)
end)

test('unknown selection outcome never retries and Refresh reads any committed state',function()
    local m=fixture(); m.open(); local late; local choose=m.buttons.unselect
    m.rpcOverride=function(route,_,cb) assert(route=='stables.horses.selection.clear.v1'); late=cb end
    choose(); assert(#m.rpc==3 and m.notice:find('Could not confirm',1,true))
    choose(); assert(#m.rpc==3)
    m.selection={revision=20,selected=false,available=false,gameplayAvailable=false}
    late({ok=true,value=copy(m.selection)})
    assert(m.openCount==1 and #m.rpc==3)
    m.rpcOverride=nil; m.buttons.refresh()
    assert(#m.rpc==5 and m.buttons['select-1'] and not m.buttons.unselect)
end)

test('session invalidation during selection discards completion without reopening old UI',function()
    local m=fixture(); m.open()
    m.rpcOverride=function(route,_,cb)
        assert(route=='stables.horses.selection.clear.v1')
        m.events['bcc-stables:menu:invalidate']()
        cb({ok=true,value={revision=20,selected=false,available=false,gameplayAvailable=false}})
    end
    m.buttons.unselect(); assert(m.openCount==1 and not m.active and #m.rpc==3)
end)

test('malformed mutation success does not optimistically change selection or trigger reads',function()
    local m=fixture(); m.open()
    m.rpcOverride=function(_,_,cb) cb({ok=true,value={revision=20,selected=true,available=false,gameplayAvailable=false}}) end
    m.buttons.unselect()
    assert(#m.rpc==3 and m.openCount==1 and m.selection.revision==19 and m.notice:find('Could not confirm',1,true))
end)

test('menu Call uses shared no-identity controller once and closes input on accepted start',function()
    local m=fixture(); local calls=0
    m.env.StablesNativeControls={Call=function(...)
        assert(select('#',...)==0); calls=calls+1
        m.buttons.call() -- An overlapping click cannot start another action.
        return true
    end}
    m.open(); assert(m.buttons.call and not m.buttons.store)
    local stale=m.buttons.call; m.buttons.call()
    assert(calls==1 and #m.rpc==2 and not m.active and m.destroyed==1)
    stale(); assert(calls==1)
end)

test('menu Store preserves focus on occupancy refusal and closes only when accepted',function()
    local m=fixture(); m.horse.availability='active'; m.horse.projectionRevision=137
    m.page.items={copy(m.horse)}; m.selection.horse=copy(m.horse)
    local calls=0
    m.env.StablesNativeControls={Store=function(...)
        assert(select('#',...)==0); calls=calls+1; return false,'horse_occupied'
    end}
    m.open(); assert(m.buttons.store)
    m.buttons.store(); assert(m.active and m.notice:find('Dismount',1,true) and calls==1 and #m.rpc==2)
    m.env.StablesNativeControls.Store=function() calls=calls+1; return true end
    m.buttons.store(); assert(not m.active and calls==2 and m.destroyed==1 and #m.rpc==2)
end)

test('menu native busy missing controller and no selection cannot create a fallback request',function()
    local m=fixture(); m.env.StablesNativeControls={Call=function() return false,'busy' end}
    m.open(); m.buttons.call(); assert(m.active and m.notice:find('in progress',1,true) and #m.rpc==2)
    m.env.StablesNativeControls=nil; m.buttons.call()
    assert(m.active and m.notice:find('unavailable',1,true) and #m.rpc==2)
    m.selection={revision=20,selected=false,available=false,gameplayAvailable=false}
    m.buttons.refresh(); assert(not m.buttons.call and not m.buttons.store)
end)

test('uncertain selection blocks selection-dependent Call until fresh readback',function()
    local m=fixture(); local calls=0
    m.env.StablesNativeControls={Call=function() calls=calls+1; return true end}
    m.open(); m.rpcOverride=function() end
    m.buttons.unselect(); m.buttons.call()
    assert(calls==0 and m.active and #m.rpc==3)
end)

print(('%d owned menu cases passed; actual RedM visual/focus acceptance remains pending.'):format(passed))
