-- One bounded preview session per source. Physical cleanup completes before
-- routing; no exception to the horse controller's routing fence is needed.
Stables.StableMenu={}
local M,F,C,R=Stables.StableMenu,Stables.Feather,Stables.HorseController,Stables.OwnedRepository
local sessions={}
function M.IsOpen(source) return sessions[source]~=nil end
local function near(source,site)
    local ped=GetPlayerPed(source)
    if ped==0 or not DoesEntityExist(ped) then return false end
    local a,b=GetEntityCoords(ped),site.npc.coords
    return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2<=144
end
local function close(s)
    if s.route then
        local left=F.Call('feather-routing','DeleteRoute',s.route)
        if not left.ok and left.code~='not_found' then return left end
    end
    if sessions[s.session.source]==s then sessions[s.session.source]=nil end
    TriggerClientEvent('bcc-stables:menu:closed',s.session.source,s.token)
    return F.Ok(true)
end
local function current(source,p)
    local s=sessions[source]
    if not s or not s.route or type(p)~='table' or p.token~=s.token
        or not F.IsCurrent(s.session) or not near(source,StableLocations[s.site]) then return nil end
    local route=F.Call('feather-routing','GetPlayerRoute',source)
    if not route.ok or not route.value or route.value.routeId~=s.route then return nil end
    return s
end
-- Both menus are admitted from public bucket zero, then privately routed.
-- Validate those live routes separately rather than comparing preview buckets.
function M.TradePair(s,source)
    local other=sessions[source]
    if not other or other==s or other.site~=s.site or s.session.characterId==other.session.characterId
        or current(s.session.source,{token=s.token})~=s or current(source,{token=other.token})~=other then return nil end
    local a,b=GetPlayerPed(s.session.source),GetPlayerPed(source)
    -- RedM's server sync tree does not expose ped health: GetEntityHealth
    -- returns zero even for live players. Client menu lifecycle closes on death;
    -- server admission retains current sessions, exact routes and proximity.
    if a==0 or b==0 or not DoesEntityExist(a) or not DoesEntityExist(b) then return nil end
    local x,y=GetEntityCoords(a),GetEntityCoords(b)
    if (x.x-y.x)^2+(x.y-y.y)^2+(x.z-y.z)^2>25 then return nil end
    return other
end
function M.CharacterName(characterId)
    local provider=F.Call('feather-core','GetProvider','character-profile',nil,1)
    local impl=provider.ok and type(provider.value)=='table' and provider.value.implementation
    local getProfile=type(impl)=='table' and impl.GetProfile
    local callable=type(getProfile)=='function' or type(getProfile)=='table'
        and type(rawget(getProfile,'__cfx_functionReference'))=='string'
    if not callable then return nil end
    local ok,result=pcall(getProfile,characterId)
    local profile=ok and type(result)=='table' and result.ok and result.value
    if type(profile)=='table' and type(profile.firstName)=='string' then
        return (profile.firstName..' '..(type(profile.lastName)=='string' and profile.lastName or '')):match('^%s*(.-)%s*$')
    end
end
function M.TradePlayers(s)
    local players={}
    for source in pairs(sessions) do
        local other=M.TradePair(s,source)
        if other then
            local name=M.CharacterName(other.session.characterId)
            -- Profile reads may yield; never publish a replaced character session.
            if M.TradePair(s,source)==other then players[#players+1]={source=source,name=name} end
        end
    end
    table.sort(players,function(a,b) return a.source<b.source end)
    return players
end

local function roster(s,cursor)
    if cursor~=nil and not F.IsUuid(cursor) then return F.Error('invalid_input','Invalid roster cursor.') end
    local listed=F.Call('feather-assets','ListAssetsByHolder',{
        holderType='character',holderId=s.session.characterId,assetType='horse',status='active',
        includeMetadata=true,limit=10,cursor=cursor,
    })
    if not listed.ok then return listed end
    if not F.IsCurrent(s.session) or sessions[s.session.source]~=s then return F.Error('session_stale','Session changed.') end
    local assets=listed.value
    if type(assets)~='table' or type(assets.items)~='table' or #assets.items>10
        or (assets.nextCursor~=nil and not F.IsUuid(assets.nextCursor)) then return F.Error('invalid_contract','Invalid owned asset page.') end
    local byAsset,ids,params={},{},{s.session.characterId}
    for _,asset in ipairs(assets.items) do
        if asset.managerResource=='bcc-stables' then
            if not F.IsUuid(asset.assetId) or type(asset.metadata)~='table' or not F.IsUuid(asset.metadata.stablesHorseId)
                or type(asset.owner)~='table' or asset.owner.holderType~='character' or asset.owner.holderId~=s.session.characterId then
                return F.Error('horse_reconciliation_required','Invalid roster ownership.')
            end
            byAsset[asset.assetId]=asset;ids[#ids+1]='?';params[#params+1]=asset.assetId
        end
    end
    if #ids==0 then return F.Ok({token=s.token,site=s.site,entries={},nextCursor=assets.nextCursor}) end
    local rows=DB.query([[SELECT h.horse_id,h.availability,h.revision,r.model_key,r.asset_id,
        stable.selected_horse_id,stable.revision AS selection_revision
        FROM fs_character_stables stable INNER JOIN fs_horses h ON h.owner_character_id=stable.character_id
        INNER JOIN fs_asset_registrations r ON r.operation_id=h.origin_operation_id AND r.horse_id=h.horse_id
        WHERE stable.character_id=? AND h.biological_state='alive' AND r.state='linked'
        AND r.asset_id IN (]]..table.concat(ids,',')..')',table.unpack(params))
    if not F.IsCurrent(s.session) or sessions[s.session.source]~=s then return F.Error('session_stale','Session changed.') end
    if type(rows)~='table' then return F.Error('database_unavailable','Roster unavailable.') end
    local entries={}
    local byHorse={}
    for _,row in ipairs(rows) do
        local asset=byAsset[row.asset_id]
        if not F.IsUuid(row.horse_id) or type(row.model_key)~='string' or not asset
            or asset.modelKey~=row.model_key or asset.metadata.stablesHorseId~=row.horse_id then return F.Error('horse_reconciliation_required','Invalid roster identity.') end
        byHorse[row.asset_id]={horseId=row.horse_id,modelKey=row.model_key,availability=row.availability,name=R.NormalizeName(asset.metadata.name),gender=(asset.metadata.gender=='male' or asset.metadata.gender=='female') and asset.metadata.gender or nil,
            selected=row.horse_id==row.selected_horse_id,selectionRevision=tonumber(row.selection_revision)}
    end
    for _,asset in ipairs(assets.items) do if byHorse[asset.assetId] then entries[#entries+1]=byHorse[asset.assetId] end end
    -- List is presentation only; preview/select recheck canonical ownership.
    return F.Ok({token=s.token,site=s.site,entries=entries,nextCursor=assets.nextCursor})
end
function M.Open(source,p)
    if type(p)~='table' or type(p.site)~='string' then return F.Error('invalid_input','Stable required.') end
    local site=StableLocations[p.site]
    if not site or not near(source,site) or GetPlayerRoutingBucket(source)~=0 then return F.Error('stable_unavailable','Stand beside the stable.') end
    -- Restricted locations wait for the authoritative job/world-hours integration.
    if site.shop.jobsEnabled or site.shop.hours.active then return F.Error('stable_unavailable','Restricted stable menus are not enabled yet.') end
    if sessions[source] then return F.Error('busy','A stable session is already open.') end
    local captured=F.RequireSession(source); if not captured.ok then return captured end
    local s={session=captured.value,site=p.site,expires=GetGameTimer()+20000,busy=true}
    sessions[source]=s -- Blocks concurrent call admission before any yield.
    local ok,result=pcall(function()
        local slot=DB.one('SELECT generation_id FROM fs_call_slots WHERE character_id=?',s.session.characterId)
        if slot then
            local stored=C.Store(source)
            if not stored.ok and stored.code~='cleanup_pending' then return stored end
            local deadline=GetGameTimer()+5000
            while C.HasPhysicalCall(s.session) and GetGameTimer()<deadline do Wait(50) end
            if C.HasPhysicalCall(s.session) then return F.Error('cleanup_pending','Horse cleanup is still pending.') end
        end
        if not F.IsCurrent(s.session) or not near(source,site) or GetPlayerRoutingBucket(source)~=0 then return F.Error('session_stale','Stable eligibility changed.') end
        if DB.one('SELECT generation_id FROM fs_call_slots WHERE character_id=?',s.session.characterId) then return F.Error('call_reconciliation_required','Horse slot remains occupied.') end
        local id=DB.one('SELECT UUID() AS id')
        if not id or not F.IsUuid(id.id) then return F.Error('database_unavailable','Session identity unavailable.') end
        s.token=id.id
        local route=F.Call('feather-routing','CreateRoute',{key='stables:'..s.token,mode='strict',populationEnabled=false})
        if not route.ok then return route end
        s.route=route.value.routeId
        if not F.IsCurrent(s.session) then return F.Error('session_stale','Session changed.') end
        local joined=F.Call('feather-routing','JoinRoute',s.route,source); if not joined.ok then return joined end
        return roster(s)
    end)
    s.busy=false
    if not ok or not result.ok then close(s) end
    return ok and result or F.Error('menu_unavailable','Stable could not open.')
end
function M.Request(source,p,action)
    local s=current(source,p)
    if not s then return F.Error('session_stale','Stable session changed.') end
    if action=='close' then return close(s) end
    s.expires=GetGameTimer()+30000
    if action=='ping' then return F.Ok(true) end
    if s.busy then return F.Error('busy','A stable action is finishing.') end
    s.busy=true
    local ok,result=pcall(function()
        if action=='tack_trade_list' then return Stables.TackTrade.List(s) end
        if action=='horse_trade_list' then return Stables.HorseTrade.List(s,p.horseId) end
        if action=='horse_trade_offer' then return Stables.HorseTrade.Offer(s,p) end
        if action=='horse_trade_respond' then return Stables.HorseTrade.Respond(s,p) end
        if action=='tack_trade_offer' then return Stables.TackTrade.Offer(s,p) end
        if action=='tack_trade_respond' then return Stables.TackTrade.Respond(s,p) end
        if action=='roster' then return roster(s,p.cursor) end
        if action=='rename' then
            local renamed=R.RenameOwned(s.session,p.horseId,p.revision,p.name)
            if not current(source,p) then return F.Error('rename_outcome_unknown','Stable session changed; reopen to check the saved name.') end
            return renamed
        end
        if action=='purchase_quote' then return Stables.Checkout.Quote(s.session,s.site,p,function() return current(source,p)==s end) end
        if action=='horse_sale_quote' then return Stables.HorseResale.Quote(s.session,s.site,p,function() return current(source,p)==s end) end
        if action=='horse_sale_confirm' then return Stables.HorseResale.Confirm(s.session,s.site,p,function() return current(source,p)==s end) end
        if action=='purchase_confirm' then return Stables.Checkout.Confirm(s.session,s.site,p,function() return current(source,p)==s end) end
        if action=='tack_sale_quote' then return Stables.TackResale.Quote(s.session,s.site,p,function() return current(source,p)==s end) end
        if action=='tack_sale_confirm' then return Stables.TackResale.Confirm(s.session,s.site,p,function() return current(source,p)==s end) end
        if action=='tack_quote' then return Stables.Tack.Quote(s.session,s.site,p,function() return current(source,p)==s end) end
        if action=='tack_confirm' then return Stables.Tack.Confirm(s.session,s.site,p,function() return current(source,p)==s end) end
        if action=='tack_equip' then return Stables.Tack.Equip(s.session,p,function() return current(source,p)==s end) end
        if action=='tack_shop' then return Stables.Tack.Shop(s.session,p.horseId) end
        local owned=R.ReadOwned(s.session,p.horseId); if not owned.ok then return owned end
        if not current(source,p) then return F.Error('session_stale','Stable session changed.') end
        if action=='preview' then
            if Stables.Tack then
                local equipped=Stables.Tack.Loadout(s.session,p.horseId)
                owned.value.tack=equipped.ok and equipped.value or {}
            end
            return owned
        end
        if not F.IsRevision(p.revision) or p.revision~=owned.value.selectionRevision then return F.Error('selection_conflict','Refresh the roster.') end
        local committed=DB.transaction(function(tx)
            local stable=tx.one('SELECT selected_horse_id,revision FROM fs_character_stables WHERE character_id=? FOR UPDATE',s.session.characterId)
            if not stable or tonumber(stable.revision)~=p.revision or not F.IsCurrent(s.session) then return false end
            if tx.one('SELECT generation_id FROM fs_call_slots WHERE character_id=? FOR UPDATE',s.session.characterId)
                or tx.one("SELECT operation_id FROM fs_care_operations WHERE character_id=? AND state NOT IN ('applied','cancelled') LIMIT 1 FOR UPDATE",s.session.characterId) then return false end
            local horse=tx.one('SELECT owner_character_id,biological_state,availability FROM fs_horses WHERE horse_id=? FOR UPDATE',p.horseId)
            if not horse or horse.owner_character_id~=s.session.characterId or horse.biological_state~='alive' or horse.availability~='stored' then return false end
            if stable.selected_horse_id~=p.horseId then
                if tx.exec('UPDATE fs_character_stables SET selected_horse_id=?,revision=revision+1 WHERE character_id=? AND revision=?',p.horseId,s.session.characterId,p.revision)~=1 then error('Selection write failed.') end
            end
            return F.IsCurrent(s.session) and sessions[source]==s
        end)
        if committed~=true then return F.Error('selection_conflict','Selection changed or horse is busy; refresh.') end
        return roster(s,p.cursor)
    end)
    s.busy=false
    return ok and result or F.Error('menu_outcome_unknown','Refresh before retrying the stable action.')
end
function M.Tick()
    for _,s in pairs(sessions) do
        if not s.busy and (not F.IsCurrent(s.session) or GetGameTimer()>s.expires
            or not near(s.session.source,StableLocations[s.site])) then close(s) end
    end
end
function M.Install()
    for _,action in ipairs({'open','roster','preview','select','close','ping','rename','purchase_quote','purchase_confirm','horse_sale_quote','horse_sale_confirm','horse_trade_list','horse_trade_offer','horse_trade_respond',
        'tack_trade_list','tack_trade_offer','tack_trade_respond','tack_shop','tack_quote','tack_confirm','tack_equip','tack_sale_quote','tack_sale_confirm'}) do
        local result=F.Call('feather-core','RegisterRpc','stables.horses.call.menu_'..action..'.v1',function(p,source)
            return action=='open' and M.Open(source,p) or M.Request(source,p,action)
        end,{contract=1,direction='client_to_server',requireCharacter=true,windowMs=2000,maxCalls=4,
            maxPayloadBytes=(action=='rename' or action=='purchase_quote') and 2048 or 512,maxDepth=2,maxNodes=12,validatePayload=function(p)
                if type(p)~='table' then return false end
                local allowed={token=true,site=true,horseId=true,revision=true,cursor=true}
                if action=='horse_trade_offer' then allowed.recipientSource=true;allowed.includeTack=true;allowed.amount=true;allowed.currency=true end
                if action=='horse_trade_respond' then allowed.operationId=true;allowed.accept=true;allowed.includeTack=true;allowed.amount=true;allowed.currency=true end
                if action=='tack_trade_offer' then allowed.instanceId=true;allowed.recipientSource=true;allowed.amount=true;allowed.currency=true end
                if action=='tack_trade_respond' then allowed.operationId=true;allowed.accept=true;allowed.amount=true;allowed.currency=true end
                if action=='rename' then allowed.name=true end
                if action=='horse_sale_quote' then allowed.currency=true end
                if action=='horse_sale_confirm' then allowed.operationId=true;allowed.amount=true;allowed.currency=true end
                if action=='purchase_quote' then allowed.modelKey=true;allowed.name=true;allowed.gender=true;allowed.currency=true end
                if action=='purchase_confirm' then allowed.operationId=true;allowed.amount=true;allowed.currency=true end
                if action=='tack_sale_quote' then allowed.instanceId=true end
                if action=='tack_sale_confirm' then allowed.operationId=true;allowed.dollars=true;allowed.gold=true end
                if action=='tack_quote' then allowed.catalogId=true;allowed.currency=true end
                if action=='tack_confirm' then allowed.operationId=true;allowed.amount=true;allowed.currency=true end
                if action=='tack_equip' then allowed.instanceId=true;allowed.expectedInstanceId=true;allowed.itemRevision=true;allowed.fromHorseId=true;allowed.slot=true;allowed.detach=true;allowed.fromSaddleId=true end
                for key in pairs(p) do if not allowed[key] then return false end end
                if action=='horse_trade_list' then return F.IsUuid(p.token) and (p.horseId==nil or F.IsUuid(p.horseId)) end
                if action=='horse_trade_offer' then return F.IsUuid(p.token) and F.IsUuid(p.horseId) and type(p.includeTack)=='boolean'
                    and F.IsRevision(p.recipientSource) and p.recipientSource>0 and F.IsRevision(p.amount) and p.amount<=1000000000
                    and (p.currency=='dollars' or p.currency=='gold') end
                if action=='horse_trade_respond' then return F.IsUuid(p.token) and F.IsUuid(p.operationId) and type(p.accept)=='boolean' and type(p.includeTack)=='boolean'
                    and F.IsRevision(p.amount) and (p.currency=='dollars' or p.currency=='gold') end
                if action=='horse_sale_quote' then return F.IsUuid(p.token) and F.IsUuid(p.horseId) and (p.currency=='dollars' or p.currency=='gold') end
                if action=='horse_sale_confirm' then return F.IsUuid(p.token) and F.IsUuid(p.operationId) and F.IsRevision(p.amount) and (p.currency=='dollars' or p.currency=='gold') end
                if action=='tack_trade_offer' then return F.IsUuid(p.token) and F.IsRevision(p.instanceId) and p.instanceId>0
                    and F.IsRevision(p.recipientSource) and p.recipientSource>0 and F.IsRevision(p.amount) and p.amount<=1000000000
                    and (p.currency=='dollars' or p.currency=='gold') end
                if action=='tack_trade_respond' then return F.IsUuid(p.token) and F.IsUuid(p.operationId) and type(p.accept)=='boolean'
                    and F.IsRevision(p.amount) and (p.currency=='dollars' or p.currency=='gold') end
                if action=='tack_shop' then return F.IsUuid(p.token) and (p.horseId==nil or F.IsUuid(p.horseId)) end
                if action=='tack_sale_quote' then return F.IsUuid(p.token) and F.IsRevision(p.instanceId) and p.instanceId>0 end
                if action=='tack_sale_confirm' then return F.IsUuid(p.token) and F.IsUuid(p.operationId) and F.IsRevision(p.dollars) and F.IsRevision(p.gold) end
                if action=='tack_quote' then return F.IsUuid(p.token) and type(p.catalogId)=='string' and #p.catalogId<=64 and (p.currency=='dollars' or p.currency=='gold') end
                if action=='tack_confirm' then return F.IsUuid(p.token) and F.IsUuid(p.operationId) and F.IsRevision(p.amount) and (p.currency=='dollars' or p.currency=='gold') end
                if action=='tack_equip' then return (p.detach==nil or type(p.detach)=='boolean') and (p.fromSaddleId==nil or F.IsRevision(p.fromSaddleId) and p.fromSaddleId>0) and F.IsUuid(p.token) and (F.IsUuid(p.horseId) or p.horseId==nil and p.detach==true) and F.IsRevision(p.instanceId)
                    and (p.slot==nil or type(p.slot)=='string' and Tack.PieceSlots[p.slot]~=nil)
                    and F.IsRevision(p.expectedInstanceId) and F.IsRevision(p.itemRevision) and (p.fromHorseId==nil or F.IsUuid(p.fromHorseId)) end
                if action=='purchase_quote' then return F.IsUuid(p.token) and type(p.modelKey)=='string' and #p.modelKey<=64
                    and type(p.name)=='string' and #p.name<=400 and (p.gender=='male' or p.gender=='female') and (p.currency=='dollars' or p.currency=='gold') end
                if action=='purchase_confirm' then return F.IsUuid(p.token) and F.IsUuid(p.operationId) and F.IsRevision(p.amount) and type(p.currency)=='string' and #p.currency<=32 end
                if action=='rename' then return F.IsUuid(p.token) and F.IsUuid(p.horseId) and F.IsRevision(p.revision) and type(p.name)=='string' and #p.name<=400 end
                return action=='open' and type(p.site)=='string' and #p.site<=32 or action~='open' and F.IsUuid(p.token)
            end})
        if not result.ok then return result end
    end
    AddEventHandler('onResourceStop',function(resource)
        if resource==GetCurrentResourceName() or resource=='feather-core' or resource=='feather-routing' or resource=='feather-inventory' then
            for _,s in pairs(sessions) do close(s) end
        end
    end)
    return F.Ok(true)
end
