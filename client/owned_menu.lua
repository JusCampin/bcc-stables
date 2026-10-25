-- Optional Menu v2 presentation. Existing RPCs own read/mutation authorization.
local busy,epoch,menuId=false,0,nil
local nextReadAt=0
local Open
local MENU='feather-menu-v2'
local function Require(result)
    if type(result)~='table' or result.ok~=true then
        error(type(result)=='table' and type(result.code)=='string' and result.code or 'invalid_result',0)
    end
    return result.value
end
local function Menu(method,...)
    assert(GetResourceState(MENU)=='started','menu_unavailable')
    local provider=exports[MENU]
    return Require(provider[method](provider,...))
end
local function Reset()
    epoch=epoch+1
    local old=menuId; menuId=nil
    if old and GetResourceState(MENU)=='started' then pcall(Menu,'DestroyMenu',old) end
end
local function Current(token)
    if token~=epoch then error('cancelled',0) end
end
local function Pending(route,payload,token)
    local packed,done
    local began=GetGameTimer()
    exports['feather-core']:CallRPC(route,payload,function(...)
        if not done then packed,done=table.pack(...),true end
    end,nil,5000)
    return function()
        while not done do
            if token~=epoch then done=true; error('cancelled',0) end
            if GetGameTimer()-began>=6000 then done=true; error('timeout',0) end
            Wait(25)
        end
        Current(token)
        local result,transport=packed[1],packed[2]
        if result==nil and type(transport)=='table' then error(transport.code or 'invalid_result',0) end
        return Require(result)
    end
end
local function Uuid(v)
    return type(v)=='string' and v:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$')~=nil
end
local function Integer(v,minimum)
    return type(v)=='number' and v%1==0 and v>=minimum and v<=9007199254740991
end
local function Horse(v)
    return type(v)=='table' and Uuid(v.horseId) and Uuid(v.operationId) and Uuid(v.assetId)
        and type(v.modelKey)=='string' and #v.modelKey<=100 and v.modelKey:match('^a_c_horse_[a-z0-9_]+$')
        and (v.availability=='stored' or v.availability=='active') and v.gameplayAvailable==false
        and Integer(v.assetRevision,1) and Integer(v.projectionRevision,0)
        and (v.availability=='active')==(v.projectionRevision%2==1)
end
local function Selection(selection)
    assert(type(selection)=='table' and Integer(selection.revision,0) and type(selection.selected)=='boolean'
        and type(selection.available)=='boolean' and selection.gameplayAvailable==false,'invalid_result')
    if selection.available then assert(selection.selected and Horse(selection.horse),'invalid_result')
    else assert(selection.horse==nil,'invalid_result') end
end
local function Validate(page,selection,cursor)
    assert(type(page)=='table' and type(page.items)=='table' and #page.items<=10 and page.pageSize==10
        and type(page.selectionAvailable)=='boolean' and page.gameplayAvailable==false
        and (page.nextCursor==nil or Uuid(page.nextCursor)),'invalid_result')
    local count=0
    for key in pairs(page.items) do
        assert(Integer(key,1) and key<=#page.items,'invalid_result'); count=count+1
    end
    assert(count==#page.items,'invalid_result')
    local previous=cursor
    for _,horse in ipairs(page.items) do
        assert(Horse(horse) and (not previous or horse.horseId>previous),'invalid_result')
        previous=horse.horseId
    end
    assert(not page.nextCursor or ((not previous or page.nextCursor>=previous) and (not cursor or page.nextCursor>cursor)), 'invalid_result')
    Selection(selection)
end
local function Label(model)
    return (model:gsub('^a_c_horse_',''):gsub('_',' '):gsub('%a[%w]*',function(word)
        return word:sub(1,1):upper()..word:sub(2)
    end))
end
local function Build(page,selection,cursor,history,token)
    local value=Menu('CreateMenu',{key='owned',closable=true,draggable=true,
        size={width='32rem',maxHeight='85vh'},theme={preset='redemption',accent='#9b6a42'}})
    assert(type(value)=='table' and type(value.menuId)=='string' and #value.menuId<=256,'invalid_result')
    menuId=value.menuId; local id=menuId
    local created=Menu('CreatePage',id,{key='horses'})
    assert(type(created)=='table' and type(created.pageId)=='string','invalid_result')
    local pageId=created.pageId
    local function Add(kind,spec,callback) return Menu('AddElement',id,pageId,kind,spec,callback) end
    local mutationButtons={}
    local noticeId
    local writable=true
    local function Button(key,label,callback,slot,mutation)
        local added=Add('button',{key=key,label=label,slot=slot or 'footer'},function()
            if token==epoch and menuId==id and not busy and (not mutation or writable) then callback() end
        end)
        if mutation then
            assert(type(added)=='table' and type(added.elementId)=='string','invalid_result')
            mutationButtons[#mutationButtons+1]=added.elementId
        end
    end
    local function Feedback(text)
        if noticeId then pcall(Menu,'UpdateElement',id,pageId,noticeId,{value=text}) end
    end
    local function DisableMutations()
        for _,element in ipairs(mutationButtons) do pcall(Menu,'UpdateElement',id,pageId,element,{disabled=true}) end
    end
    local function Choose(horseId)
        busy=true
        DisableMutations(); Feedback('Updating selection...')
        CreateThread(function()
            local ok,result=pcall(function()
                local payload={expectedRevision=selection.revision}
                if horseId then payload.horseId=horseId end
                local read=Pending('stables.horses.selection.'..(horseId and 'set' or 'clear')..'.v1',payload,token)
                local value=read(); Selection(value)
                assert(value.revision>=selection.revision and
                    (horseId and value.available and value.horse.horseId==horseId or not horseId and not value.selected),'invalid_result')
                return value
            end)
            if token~=epoch or menuId~=id then busy=false; return end
            if ok then
                busy=false; Open(cursor,history) -- Re-read; no optimistic state or automatic write retry.
            else
                writable=false
                local messages={revision_conflict='Your selection changed elsewhere. Refresh before choosing again.',
                    horse_busy='Store your active horse before changing selection, then refresh.',
                    selection_disabled='Horse selection is unavailable. Refresh to check again.'}
                Feedback(messages[result] or 'Could not confirm selection. Refresh to check your current choice.')
                busy=false
            end
        end)
    end
    local function NativeAction(method)
        busy=true
        Feedback(method=='Call' and 'Calling your selected horse...' or 'Storing your current horse...')
        CreateThread(function()
            local ok,accepted,reason=pcall(function() return StablesNativeControls[method]() end)
            if token==epoch and menuId==id then
                if ok and accepted==true then Reset()
                else
                    local messages={busy='Another horse action is still in progress.',
                        horse_occupied='Dismount or release the lead before storing your horse.',
                        occupancy_unknown='Horse occupancy could not be confirmed. Try again when it is clear.',
                        stale_call='Your active horse changed. Refresh before trying again.'}
                    Feedback(ok and messages[reason] or 'Horse controls are unavailable. Close and try again.')
                end
            end
            busy=false
        end)
    end
    Add('header',{key='title',value='My Horses',slot='header'})
    local notice=Add('textdisplay',{key='notice',value=page.selectionAvailable and 'Your selection chooses which horse you call.' or ''})
    assert(type(notice)=='table' and type(notice.elementId)=='string','invalid_result')
    noticeId=notice.elementId
    if #page.items==0 then Add('textdisplay',{key='empty',value='No horses on this page.'}) end
    for index,horse in ipairs(page.items) do
        Add('subheader',{key='horse-'..index,value=Label(horse.modelKey)})
        local state=horse.availability=='stored' and 'Stored' or 'Active'
        if selection.available and selection.horse.horseId==horse.horseId then state='Selected · '..state end
        Add('textdisplay',{key='status-'..index,value=state})
        if page.selectionAvailable and not (selection.available and selection.horse.horseId==horse.horseId) then
            Button('select-'..index,'Select',function() Choose(horse.horseId) end,'content',true)
        end
        Add('line',{key='line-'..index})
    end
    if #history>0 then Button('previous','Previous',function()
        local previous=history[#history]; local shorter={}
        for i=1,#history-1 do shorter[i]=history[i] end
        Open(previous.after,shorter)
    end) end
    if page.nextCursor and #history<32 then Button('next','Next',function()
        local longer={}; for i,value in ipairs(history) do longer[i]=value end
        longer[#longer+1]={after=cursor}
        Open(page.nextCursor,longer)
    end) end
    if selection.available then Button('call','Call selected horse',function() NativeAction('Call') end,'footer',true) end
    local active=selection.available and selection.horse.availability=='active'
    for _,horse in ipairs(page.items) do if horse.availability=='active' then active=true end end
    if active then Button('store','Store current horse',function() NativeAction('Store') end) end
    if page.selectionAvailable and selection.selected then Button('unselect','Unselect horse',function() Choose(nil) end,'footer',true) end
    Button('refresh','Refresh',function() Open(cursor,history) end)
    Button('close','Close',Reset)
    Menu('RegisterMenuLifecycle',id,function(event)
        if type(event)=='table' and event.event=='closed' and menuId==id then Reset() end
    end)
    Current(token)
    Menu('OpenMenu',id,{pageId=pageId,keyboard=true,cursor=true,replace=false})
end
Open=function(cursor,history)
    if busy then return end
    Reset(); busy=true
    local token=epoch
    CreateThread(function()
        local ok,failure=pcall(function()
            assert(GetResourceState('feather-core')=='started','core_unavailable')
            local capabilities=Menu('GetCapabilities')
            assert(type(capabilities)=='table' and capabilities.contract==1 and type(capabilities.features)=='table','menu_contract')
            for _,feature in ipairs({'menus','pages','elements','focus','ownerCleanup','boundedValidation','reactiveState'}) do
                assert(capabilities.features[feature]==1,'menu_contract')
            end
            Menu('AwaitReady',5000); Current(token)
            -- Both read routes permit two calls per two seconds. Pace rapid
            -- Refresh/Next actions without retries or background polling.
            while GetGameTimer()<nextReadAt do Wait(25); Current(token) end
            nextReadAt=GetGameTimer()+1100
            -- Independent authorized reads start together; no idle/background polling.
            local list=Pending('stables.horses.list.v1',cursor and {afterHorseId=cursor} or {},token)
            local selected=Pending('stables.horses.selection.get.v1',{},token)
            local page,selection=list(),selected()
            Validate(page,selection,cursor); Current(token)
            Build(page,selection,cursor,history or {},token)
        end)
        if not ok and token==epoch then
            Reset()
            print('[bcc-stables] horse menu failed: '..tostring(failure))
        end
        busy=false
    end)
end
RegisterCommand('BccStablesMenu',function(_,args)
    if #(args or {})~=0 then print('[bcc-stables] BccStablesMenu'); return end
    Open(nil,{})
end,false)
RegisterNetEvent('bcc-stables:menu:invalidate',function()
    if source==65535 then Reset() end
end)
local function Stopped(resource)
    if resource==GetCurrentResourceName() or resource==MENU or resource=='feather-core'
        or resource=='feather-assets' or resource=='feather-economy' or resource=='feather-mysql' then Reset() end
end
AddEventHandler('onClientResourceStop',Stopped)
AddEventHandler('onResourceStop',Stopped)
