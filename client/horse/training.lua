-- Original surveyed NPC course presentation; server observations advance it.
local C,H=Stables.Client,Stables.Horse
local menu,menuSite,menuPed,course,settling,requesting
local npcs,blips={},{}
local prompt,group
local function yes(v) return v==true or v==1 end
local function exists(e) return e and e~=0 and yes(DoesEntityExist(e)) end
local function text(key,...) return C.Text('menu_training_'..key,...) end
local function notify(key,...) (C.Notify or C.Message)(text(key,...)) end
local function value(result)
    if not result or not result.ok then error(result and result.code or 'menu_unavailable') end
    return result.value
end
local function close()
    local id=menu;menu=nil;menuSite=nil;menuPed=nil
    if id then exports['feather-menu-v2']:DestroyMenu(id) end
end
local function request(site,mode)
    if requesting then return end;requesting=true;close()
    CreateThread(function()
        local result=C.Rpc('training',{site=site,mode=mode});requesting=nil
        if not result.ok then
            local keys={training_near_instructor='near',horse_not_ready='needHorse',training_busy='busy',
                training_daily_limit='dailyLimit',training_payment_unavailable='paymentUnavailable'}
            C.Message('training request refused: '..tostring(result.code))
            notify(keys[result.code] or 'unavailable')
        end
    end)
end
local function open(site)
    if menu or requesting then return end
    local M=exports['feather-menu-v2'];local policy=Config.training
    local ok,failure=pcall(function()
        value(M:AwaitReady(5000))
        menu=value(M:CreateMenu({key='horse-training',closable=true,draggable=true,persistPosition=false,
            position={x='3%',y='3%',anchor='top-left'},size={width='32rem',maxHeight='80vh'},theme={preset='redemption'}})).menuId
        menuSite=site;menuPed=PlayerPedId()
        local id=menu;local page=value(M:CreatePage(id,{key='courses'})).pageId
        local function add(kind,key,spec,fn) spec.key=key;value(M:AddElement(id,page,kind,spec,fn)) end
        add('header','title',{value=text('title'),slot='header'})
        add('subheader','site',{value=text('site_'..site),slot='header'})
        add('textdisplay','help',{value=text('help')})
        add('textdisplay','price',{value=text('price',policy.price/100,C.Text(policy.currency=='gold' and 'menu_gold' or 'menu_cash'))})
        for _,mode in ipairs({'leading','riding'}) do
            local p=policy.courses[mode];local _,laps=Stables.TrainingCourse.Points(HorseTrainingLocations[site],mode)
            add('textdisplay',mode..'-terms',{value=text('terms',text(mode),p.xp,laps,p.secondsPerLap*laps)})
            add('button',mode,{label=text('start',text(mode))},function() request(site,mode) end)
        end
        add('button','close',{label=C.Text('menu_close'),slot='footer'},close)
        value(M:RegisterMenuLifecycle(id,function(event) if event.event=='closed' and menu==id then close() end end))
        value(M:OpenMenu(id,{pageId=page}))
    end)
    if not ok then close();C.Message('training menu failed: '..tostring(failure));notify('unavailable') end
end
local function entity(p)
    local e=NetworkGetEntityFromNetworkId(p.netId)
    if not exists(e) or NetworkGetNetworkIdFromEntity(e)~=p.netId or GetEntityModel(e)~=GetHashKey(p.modelKey)
        or Entity(e).state.bccStablesGeneration~=p.generationId or Entity(e).state.bccStablesObserver~=p.observerId then return nil end
    return e
end
RegisterNetEvent('bcc-stables:training:sample',function(p)
    if source~=65535 or not Config.training.enabled or type(p)~='table' or not C.Uuid(p.id) or not C.Uuid(p.generationId)
        or not C.Uuid(p.observerId) or type(p.netId)~='number' or type(p.modelKey)~='string' or type(p.targetNet)~='number' then return end
    local e=entity(p);local owner=NetworkGetEntityFromNetworkId(p.targetNet)
    if not e or not exists(owner) or not yes(NetworkHasControlOfEntity(e)) or NetworkGetNetworkIdFromEntity(owner)~=p.targetNet then return end
    if p.bonding and Stables.HorseBonding then Stables.HorseBonding.Apply({entity=e,modelKey=p.modelKey},p.bonding) end
    local living=not yes(IsEntityDead(e)) and not yes(IsEntityDead(owner))
    local mode='idle'
    if living and yes(IsPedOnMount(owner)) and GetMount(owner)==e and GetRiderOfMount(e,false)==owner then mode='riding'
    elseif living and yes(Citizen.InvokeNative(0xEFC4303DDC6E60D3,owner))
        and Citizen.InvokeNative(0xED1F514AF4732258,owner,Citizen.ResultAsInteger())==e
        and GetRiderOfMount(e,false)==0 and GetRiderOfMount(e,true)==0 then mode='leading' end
    CreateThread(function() C.Rpc('training_sample',{id=p.id,sequence=p.sequence,mode=mode,alive=living}) end)
end)
RegisterNetEvent('bcc-stables:training:progress',function(p)
    if source~=65535 or type(p)~='table' or not C.Uuid(p.id) or not C.Uuid(p.generationId)
        or type(p.points)~='table' or type(p.index)~='number' or not p.points[p.index] or type(p.remainingMs)~='number' then return end
    local r=H.GetActive();if not r or r.generationId~=p.generationId then return end
    local first=not course or course.id~=p.id
    p.endsAt=GetGameTimer()+p.remainingMs;p.ped=PlayerPedId();course=p
    if first then notify('started',text(p.mode)) end
    notify('checkpoint',p.index,#p.points)
end)
RegisterNetEvent('bcc-stables:training:pending',function(p)
    if source~=65535 or type(p)~='table' or not C.Uuid(p.id) or not course or course.id~=p.id then return end
    course=nil;settling=p.id
    CreateThread(function() Wait(1000);if settling==p.id then notify('pending') end end)
end)
RegisterNetEvent('bcc-stables:training:ended',function(p)
    if source~=65535 or type(p)~='table' or not C.Uuid(p.id) then return end
    if course and course.id~=p.id then return end
    course=nil;if settling==p.id then settling=nil end
    local result=p.result
    if result and result.ok and result.value and result.value.state=='completed' then
        local q=result.value;notify('completed',q.bonding and q.bonding.amount or q.earnedXp,q.score,q.amount/100,
            C.Text(q.currency=='gold' and 'menu_gold' or 'menu_cash'))
        if q.bonding and Stables.HorseBonding then Stables.HorseBonding.NotifyLevel(q.bonding) end
    else
        local keys={insufficient_funds='funds',training_boundary='boundary',training_timeout='timeout',
            training_interaction_lost='interactionLost',training_observation_lost='observationLost',
            training_movement_invalid='movementInvalid',training_actor_unavailable='actorUnavailable'}
        notify(result and keys[result.code] or 'cancelled')
    end
end)
AddEventHandler('feather-core:locale:changed',function()
    local site=menuSite
    if site then close();open(site) end
    for site,b in pairs(blips) do Citizen.InvokeNative(0x9CB1A1623062F402,b,text('site_'..site)) end
end)
CreateThread(function()
    if not Config.training or not Config.training.enabled then return end
    group=GetRandomIntInRange(1,0x7fffffff)
    prompt=UiPromptRegisterBegin();UiPromptSetControlAction(prompt,Config.training.control)
    UiPromptSetText(prompt,CreateVarString(10,'LITERAL_STRING',text('title')));UiPromptSetStandardMode(prompt,true)
    UiPromptSetGroup(prompt,group,0);UiPromptSetEnabled(prompt,false);UiPromptSetVisible(prompt,false);UiPromptRegisterEnd(prompt)
    while true do
        local pos=GetEntityCoords(PlayerPedId());local nearest,distance
        if menu and (PlayerPedId()~=menuPed or yes(IsEntityDead(PlayerPedId())) or not H.GetActive()
            or Stables.TrainingCourse.Distance(pos,HorseTrainingLocations[menuSite].npc)>8) then close() end
        for site,area in pairs(HorseTrainingLocations) do
            if area.enabled and area.configured then
                local d=Stables.TrainingCourse.Distance(pos,area.npc)
                if not blips[site] and (not area.blip or area.blip.enabled~=false) then
                    local b=Citizen.InvokeNative(0x554D9D53F696D002,1664425300,area.npc.x,area.npc.y,area.npc.z)
                    SetBlipSprite(b,1542275196,true);Citizen.InvokeNative(0x9CB1A1623062F402,b,text('site_'..site));blips[site]=b
                end
                if d<=80 and not npcs[site] then
                    local loaded=exports['feather-toolkit']:LoadModel(Config.training.instructorModel)
                    if loaded and loaded.ok then
                        local e=CreatePed(loaded.value.hash,area.npc.x,area.npc.y,area.npc.z-1,area.npc.w,false,true,true,true)
                        if exists(e) then
                            Citizen.InvokeNative(0x283978A15512B2FE,e,true);SetEntityInvincible(e,true)
                            FreezeEntityPosition(e,true);SetBlockingOfNonTemporaryEvents(e,true);npcs[site]=e
                        end
                        SetModelAsNoLongerNeeded(loaded.value.hash)
                    end
                elseif d>100 and npcs[site] then DeleteEntity(npcs[site]);npcs[site]=nil end
                if npcs[site] and (not distance or d<distance) then nearest,distance=site,d end
            end
        end
        local visible=nearest and distance<=3 and not menu and not requesting and not course and not settling and not IsNuiFocused()
            and not yes(IsEntityDead(PlayerPedId())) and H.GetActive()~=nil
        UiPromptSetVisible(prompt,visible and true or false);UiPromptSetEnabled(prompt,visible and true or false)
        if visible then
            UiPromptSetText(prompt,CreateVarString(10,'LITERAL_STRING',text('title')))
            UiPromptSetActiveGroupThisFrame(group,CreateVarString(10,'LITERAL_STRING',text('site_'..nearest)),1,0,0,0)
            if UiPromptHasStandardModeCompleted(prompt,0) then open(nearest) end
        end
        Wait(visible and 0 or 1000)
    end
end)
CreateThread(function()
    if not Config.training or not Config.training.enabled then return end
    while true do
        local q=course
        if not q then Wait(500) else
            local r=H.GetActive()
            if not r or r.generationId~=q.generationId or PlayerPedId()~=q.ped or yes(IsEntityDead(PlayerPedId())) then course=nil
            else
                local p=q.points[q.index]
                if p then
                    if not p.groundZ and GetGameTimer()>=(p.groundRetryAt or 0) then
                        local found,z=GetGroundZFor_3dCoord(p.x,p.y,p.z+10,false)
                        if yes(found) and type(z)=='number' then p.groundZ=z end
                        p.groundRetryAt=GetGameTimer()+1000
                    end
                    if p.groundZ then DrawMarker(0x94FDAE17,p.x,p.y,p.groundZ+0.03,0.0,0.0,0.0,0.0,0.0,0.0,q.radius,q.radius,0.7,
                        204,153,0,125,false,false,2,false,nil,nil,false) end
                end
                if GetGameTimer()>q.endsAt+3000 then course=nil;notify('cancelled') end
            end
            Wait(0)
        end
    end
end)
AddEventHandler('onResourceStop',function(name)
    if name==GetCurrentResourceName() then
        close();course=nil;settling=nil
        for _,e in pairs(npcs) do if exists(e) then DeleteEntity(e) end end
        for _,b in pairs(blips) do RemoveBlip(b) end
        if prompt then UiPromptDelete(prompt) end
    end
end)
