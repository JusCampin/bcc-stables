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
        AND r.character_id=stable.character_id AND r.asset_id IN (]]..table.concat(ids,',')..')',table.unpack(params))
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
        if action=='roster' then return roster(s,p.cursor) end
        if action=='rename' then
            local renamed=R.RenameOwned(s.session,p.horseId,p.revision,p.name)
            if not current(source,p) then return F.Error('rename_outcome_unknown','Stable session changed; reopen to check the saved name.') end
            return renamed
        end
        if action=='purchase_quote' then return Stables.Checkout.Quote(s.session,s.site,p,function() return current(source,p)==s end) end
        if action=='purchase_confirm' then return Stables.Checkout.Confirm(s.session,s.site,p,function() return current(source,p)==s end) end
        local owned=R.ReadOwned(s.session,p.horseId); if not owned.ok then return owned end
        if not current(source,p) then return F.Error('session_stale','Stable session changed.') end
        if action=='preview' then return owned end
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
    for _,action in ipairs({'open','roster','preview','select','close','ping','rename','purchase_quote','purchase_confirm'}) do
        local result=F.Call('feather-core','RegisterRpc','stables.horses.call.menu_'..action..'.v1',function(p,source)
            return action=='open' and M.Open(source,p) or M.Request(source,p,action)
        end,{contract=1,direction='client_to_server',requireCharacter=true,windowMs=2000,maxCalls=4,
            maxPayloadBytes=(action=='rename' or action=='purchase_quote') and 2048 or 512,maxDepth=2,maxNodes=12,validatePayload=function(p)
                if type(p)~='table' then return false end
                local allowed={token=true,site=true,horseId=true,revision=true,cursor=true}
                if action=='rename' then allowed.name=true end
                if action=='purchase_quote' then allowed.modelKey=true;allowed.name=true;allowed.gender=true;allowed.currency=true end
                if action=='purchase_confirm' then allowed.operationId=true;allowed.amount=true;allowed.currency=true end
                for key in pairs(p) do if not allowed[key] then return false end end
                if action=='purchase_quote' then return F.IsUuid(p.token) and type(p.modelKey)=='string' and #p.modelKey<=64
                    and type(p.name)=='string' and #p.name<=400 and (p.gender=='male' or p.gender=='female') and (p.currency=='dollars' or p.currency=='gold') end
                if action=='purchase_confirm' then return F.IsUuid(p.token) and F.IsUuid(p.operationId) and F.IsRevision(p.amount) and type(p.currency)=='string' and #p.currency<=32 end
                if action=='rename' then return F.IsUuid(p.token) and F.IsUuid(p.horseId) and F.IsRevision(p.revision) and type(p.name)=='string' and #p.name<=400 end
                return action=='open' and type(p.site)=='string' and #p.site<=32 or action~='open' and F.IsUuid(p.token)
            end})
        if not result.ok then return result end
    end
    AddEventHandler('onResourceStop',function(resource)
        if resource==GetCurrentResourceName() or resource=='feather-core' or resource=='feather-routing' then
            for _,s in pairs(sessions) do close(s) end
        end
    end)
    return F.Ok(true)
end
