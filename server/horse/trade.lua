-- Both players consent to immutable terms before payment or ownership changes.
-- Horse admission stays reserved until Assets, Inventory and payment receipts
-- agree. Unknown replies retry the same operation; no replacement items/horse.
Stables.HorseTrade={}
local D,F,R,T,P=Stables.HorseTrade,Stables.Feather,Stables.OwnedRepository,Stables.Tack,Stables.TackTrade
local installed,busy=false,{}
local active="('accepted','owning','equipping','paying','refunding')"
local function bad(code) return F.Error(code or 'horse_trade_pending','Horse trade is pending or changed; refresh Trades.') end
function D.Enabled() return Config.sales and Config.sales.tradingEnabled==true and T.Enabled() end
function D.Start()
    installed=pcall(DB.query,'SELECT operation_id,horse_id,state,record_json,payment_transaction_id FROM fs_horse_trades LIMIT 0')
    if D.Enabled() and not installed then return bad('horse_trade_schema_required') end
    if D.Enabled() then return T.CheckTradeProvider() end
    return F.Ok(true)
end
local function read(id,tx)
    if not F.IsUuid(id) then return bad('invalid_input') end
    local row=(tx or DB).one('SELECT * FROM fs_horse_trades WHERE operation_id=?'..(tx and ' FOR UPDATE' or ''),id)
    if not row then return bad('not_found') end
    local ok,q=pcall(json.decode,row.record_json)
    if not ok or type(q)~='table' or q.kind~='horse_trade.v1' or q.id~=id or type(q.horse)~='table'
        or q.horse.horseId~=row.horse_id or not F.IsUuid(q.horse.horseId) or not F.IsUuid(q.horse.assetId)
        or not F.IsRevision(q.horse.assetRevision) or q.horse.assetRevision<1 or not F.IsRevision(q.horse.projectionRevision)
        or type(q.seller)~='table' or type(q.buyer)~='table' or not F.IsUuid(q.seller.accountId) or not F.IsUuid(q.buyer.accountId)
        or q.seller.characterId~=row.seller_character_id or q.buyer.characterId~=row.buyer_character_id
        or not F.IsUuid(q.seller.characterId) or not F.IsUuid(q.buyer.characterId) or q.seller.characterId==q.buyer.characterId
        or not F.IsRevision(q.amount) or q.amount>1000000000 or (q.currency~='dollars' and q.currency~='gold')
        or type(q.includeTack)~='boolean' or type(q.items)~='table' or #q.items>13 or type(q.equipment)~='table'
        or not F.IsRevision(q.expiresAt) or not ({draft=true,offered=true,accepted=true,owning=true,equipping=true,paying=true,completed=true,refunding=true,cancelled=true})[row.state] then return bad() end
    row.terms=q;return F.Ok(row)
end
local function view(row)
    local q=row.terms
    return {kind='horse',operationId=q.id,state=row.state,horse=q.horse,includeTack=q.includeTack,items=q.items,
        amount=q.amount,currency=q.currency,expiresAt=q.expiresAt,sellerSource=q.seller.source,buyerSource=q.buyer.source,
        sellerName=Stables.StableMenu.CharacterName(q.seller.characterId),buyerName=Stables.StableMenu.CharacterName(q.buyer.characterId)}
end
local function locks(tx,q)
    local chars={q.seller.characterId,q.buyer.characterId};table.sort(chars)
    for _,id in ipairs(chars) do
        tx.exec('INSERT IGNORE INTO fs_character_stables(character_id) VALUES(?)',id)
        if not tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',id) then return false end
    end
    return true
end
function D.IncomingCount(tx,character)
    if not installed then return 0 end
    local row=tx.one('SELECT COUNT(*) AS total FROM fs_horse_trades WHERE buyer_character_id=? AND state IN '..active,character)
    return row and tonumber(row.total) or math.huge
end
local function capacity(tx,character)
    local count=tx.one([[SELECT
        (SELECT COUNT(*) FROM fs_horses WHERE owner_character_id=? AND biological_state='alive' AND availability<>'sold')+
        (SELECT COUNT(*) FROM fs_operations WHERE character_id=? AND state IN ('payment_pending','paid')) AS total]],character,character)
    local limit=tonumber(Config.horseLimits.player)
    return count and F.IsRevision(tonumber(count.total)) and F.IsRevision(limit) and limit>0
        and tonumber(count.total)+D.IncomingCount(tx,character)<limit
end
local function same(q,snapshot)
    if #q.items~=#snapshot.items then return false end
    for i,item in ipairs(q.items) do for _,key in ipairs({'instanceId','revision','catalogId','slot','condition','maximum','contents','contentsRevision'}) do
        if item[key]~=snapshot.items[i][key] then return false end
    end end
    for slot,id in pairs(q.equipment) do if snapshot.equipment[slot]~=id then return false end end
    for slot,id in pairs(snapshot.equipment) do if q.equipment[slot]~=id then return false end end
    return true
end
local function fresh(q,session,tx)
    local horse=R.ReadOwned(session,q.horse.horseId);if not horse.ok then return horse end
    local h=horse.value
    if h.availability~='stored' or h.assetId~=q.horse.assetId or h.assetRevision~=q.horse.assetRevision
        or h.projectionRevision~=q.horse.projectionRevision then return bad('horse_trade_changed') end
    if q.includeTack then
        local snapshot=T.HorseTradeSnapshot(session,h.horseId,tx)
        if not snapshot.ok then return snapshot end
        if not same(q,snapshot.value) then return bad('horse_trade_changed') end
    end
    return F.Ok(true)
end
function D.Offer(s,p)
    if not installed or not D.Enabled() then return bad('horse_trade_disabled') end
    if not F.IsUuid(p.horseId) or type(p.includeTack)~='boolean' or not F.IsRevision(p.amount) or p.amount>1000000000
        or p.currency~='dollars' and p.currency~='gold' then return bad('invalid_input') end
    local pair=Stables.StableMenu.TradePair(s,p.recipientSource);if not pair then return bad('tack_trade_nearby') end
    local owned=R.ReadOwned(s.session,p.horseId);if not owned.ok then return owned end
    if owned.value.availability~='stored' then return bad('horse_busy') end
    local snapshot={items={},equipment={}}
    if p.includeTack then local result=T.HorseTradeSnapshot(s.session,p.horseId);if not result.ok then return result end;snapshot=result.value end
    local uuid=DB.one('SELECT UUID() AS id');if not uuid or not F.IsUuid(uuid.id) then return bad() end
    local q={kind='horse_trade.v1',id=uuid.id,horse=owned.value,seller=s.session,buyer=pair.session,site=s.site,
        sellerToken=s.token,buyerToken=pair.token,includeTack=p.includeTack,items=snapshot.items,equipment=snapshot.equipment,
        amount=p.amount,currency=p.currency,expiresAt=os.time()+180}
    local funded=P.PaymentTerms(q);if not funded.ok then return funded end
    local saved=DB.transaction(function(tx)
        if not locks(tx,q) or not capacity(tx,q.buyer.characterId) then return false end
        for _,id in ipairs({q.seller.characterId,q.buyer.characterId}) do
            if tx.one('SELECT operation_id FROM fs_horse_trades WHERE (seller_character_id=? OR buyer_character_id=?) AND (state IN '..active.." OR state IN ('draft','offered') AND updated_at>UTC_TIMESTAMP()-INTERVAL 180 SECOND) LIMIT 1 FOR UPDATE",id,id) then return false end
        end
        if Stables.StableMenu.TradePair(s,p.recipientSource)~=pair then return false end
        return tx.exec("INSERT INTO fs_horse_trades(operation_id,horse_id,seller_character_id,buyer_character_id,state,record_json) VALUES(?,?,?,?,'draft',?)",
            q.id,q.horse.horseId,q.seller.characterId,q.buyer.characterId,json.encode(q))==1
    end)
    return saved==true and F.Ok(view({terms=q,state='draft'})) or bad('horse_trade_busy_or_limit')
end
local function change(id,from,to,payment)
    return DB.exec('UPDATE fs_horse_trades SET state=?,payment_transaction_id=COALESCE(?,payment_transaction_id) WHERE operation_id=? AND state=?',to,payment,id,from)==1
end
local function cancel(row)
    local q=row.terms
    return DB.transaction(function(tx)
        if not locks(tx,q) then return false end
        local current=read(q.id,tx);if not current.ok or current.value.state~=row.state then return false end
        if tx.exec("UPDATE fs_horses SET availability='stored',revision=revision+1 WHERE horse_id=? AND owner_character_id=? AND availability='trading'",q.horse.horseId,q.seller.characterId)~=1 then return false end
        return tx.exec("UPDATE fs_horse_trades SET state='cancelled' WHERE operation_id=? AND state=?",q.id,row.state)==1
    end)
end
function D.Resume(id)
    if not installed or busy[id] then return bad() end;busy[id]=true
    local ok,result=pcall(function()
        local found=read(id);if not found.ok then return found end
        local row,q=found.value,found.value.terms
        if row.state=='draft' or row.state=='offered' or row.state=='completed' or row.state=='cancelled' then return F.Ok(view(row)) end
        if row.state=='accepted' then
            local captured=P.Capture(q)
            if not captured.ok then if captured.code=='insufficient_funds' then cancel(row) end;return captured end
            local payment=captured.value or nil
            if not change(id,'accepted','owning',payment) then return bad() end
            row.state='owning';row.payment_transaction_id=payment
        end
        if row.state=='owning' then
            if not q.includeTack then
                local released=T.ReleaseSoldHorse(q.seller.characterId,q.horse.horseId);if not released.ok then return released end
            end
            local transferred=F.Call('feather-assets','TransferOwnership',{requestId='stables.horse.trade:'..id,
                assetId=q.horse.assetId,expectedRevision=q.horse.assetRevision,fromHolderType='character',fromHolderId=q.seller.characterId,
                toHolderType='character',toHolderId=q.buyer.characterId,reasonCode='stables.horse_trade',referenceType='stables_horse_trade',referenceId=id})
            if not transferred.ok then
                if ({revision_conflict=true,holder_mismatch=true,asset_unavailable=true,asset_retired=true,holder_inactive=true,holder_not_found=true})[transferred.code] then
                    if q.amount>0 then change(id,'owning','refunding') else cancel(row) end
                end
                return transferred
            end
            local a=transferred.value
            if type(a)~='table' or a.assetId~=q.horse.assetId or a.revision~=q.horse.assetRevision+1 or a.status~='active'
                or type(a.owner)~='table' or a.owner.holderType~='character' or a.owner.holderId~=q.buyer.characterId then return bad() end
            if not change(id,'owning','equipping') then return bad() end;row.state='equipping'
        end
        if row.state=='equipping' then
            if q.includeTack and #q.items>0 then
                local moved=T.TransferTrade(q);if not moved.ok then return moved end
                local r=moved.value
                if type(r)~='table' or r.transferred~=true or r.operationId~='stables.horse.trade:'..id
                    or r.characterId~=q.seller.characterId or r.recipientCharacterId~=q.buyer.characterId or r.count~=#q.items then return bad() end
            end
            if not change(id,'equipping','paying') then return bad() end;row.state='paying'
        end
        if row.state=='refunding' then
            local refund=P.Refund(q,row.payment_transaction_id);if not refund.ok then return refund end
            if not cancel(row) then return bad() end
        elseif row.state=='paying' then
            local paid=P.PaySeller(q);if not paid.ok then return paid end
            local saved=DB.transaction(function(tx)
                if not locks(tx,q) then return false end
                local current=read(id,tx);if not current.ok then return false end
                if current.value.state=='completed' then return true end
                if current.value.state~='paying' then return false end
                if tx.exec("UPDATE fs_horses SET owner_character_id=?,availability='stored',revision=revision+1 WHERE horse_id=? AND owner_character_id=? AND availability='trading'",q.buyer.characterId,q.horse.horseId,q.seller.characterId)~=1 then return false end
                tx.exec('UPDATE fs_character_stables SET selected_horse_id=NULL,revision=revision+1 WHERE character_id=? AND selected_horse_id=?',q.seller.characterId,q.horse.horseId)
                tx.exec('UPDATE fs_character_stables SET selected_horse_id=?,revision=revision+1 WHERE character_id=? AND selected_horse_id IS NULL',q.horse.horseId,q.buyer.characterId)
                return tx.exec("UPDATE fs_horse_trades SET state='completed' WHERE operation_id=? AND state='paying'",id)==1
            end)
            if saved~=true then return bad() end
        end
        return F.Ok(view(assert(read(id).value)))
    end)
    busy[id]=nil;return ok and result or bad()
end
function D.Respond(s,p)
    local found=read(p.operationId);if not found.ok then return found end
    local row,q=found.value,found.value.terms
    local seller=s.session.characterId==q.seller.characterId
    if not seller and s.session.characterId~=q.buyer.characterId or row.state=='draft' and not seller then return bad('not_found') end
    if row.state~='draft' and row.state~='offered' then return F.Ok(view(row)) end
    if p.accept~=true then change(q.id,row.state,'cancelled');return F.Ok(view(assert(read(q.id).value))) end
    local other=seller and q.buyer or q.seller
    local pair=Stables.StableMenu.TradePair(s,other.source)
    if not D.Enabled() or not pair or s.token~=(seller and q.sellerToken or q.buyerToken)
        or pair.token~=(seller and q.buyerToken or q.sellerToken) or os.time()>q.expiresAt
        or p.amount~=q.amount or p.currency~=q.currency or p.includeTack~=q.includeTack then return bad('quote_expired') end
    if row.state=='draft' then
        local check=fresh(q,s.session);if not check.ok then return check end
        if not change(q.id,'draft','offered') then return bad() end
        return F.Ok(view(assert(read(q.id).value)))
    end
    if seller then return bad('not_found') end
    local check=fresh(q,pair.session);if not check.ok then return check end
    local allowed=P.Preflight(q);if not allowed.ok then return allowed end
    local refusal='horse_trade_busy_or_limit'
    local saved=DB.transaction(function(tx)
        if not locks(tx,q) then return false end
        local current=read(q.id,tx);if not current.ok or current.value.state~='offered' then return false end
        if not capacity(tx,q.buyer.characterId) or Stables.StableMenu.TradePair(s,other.source)~=pair or os.time()>q.expiresAt then return false end
        for _,id in ipairs({q.seller.characterId,q.buyer.characterId}) do
            if tx.one('SELECT generation_id FROM fs_call_slots WHERE character_id=? FOR UPDATE',id)
                or tx.one("SELECT operation_id FROM fs_care_operations WHERE character_id=? AND state NOT IN ('applied','cancelled') LIMIT 1 FOR UPDATE",id) then return false end
        end
        if q.includeTack then
            local snapshot=T.HorseTradeSnapshot(pair.session,q.horse.horseId,tx)
            if not snapshot.ok or not same(q,snapshot.value) then refusal='horse_trade_changed';return false end
        end
        if tx.exec("UPDATE fs_horses SET availability='trading',revision=revision+1 WHERE horse_id=? AND owner_character_id=? AND availability='stored' AND biological_state='alive' AND revision=?",q.horse.horseId,q.seller.characterId,q.horse.projectionRevision)~=1 then return false end
        return tx.exec("UPDATE fs_horse_trades SET state='accepted' WHERE operation_id=? AND state='offered'",q.id)==1
    end)
    return saved==true and D.Resume(q.id) or bad(refusal)
end
function D.List(s,horseId)
    if not installed or not D.Enabled() then return F.Ok({available=false,players={},offers={}}) end
    local rows=DB.query('SELECT operation_id FROM fs_horse_trades WHERE (seller_character_id=? OR buyer_character_id=?) AND (state IN '..active.." OR state IN ('draft','offered')) ORDER BY created_at DESC LIMIT 10",s.session.characterId,s.session.characterId)
    local offers={}
    for _,r in ipairs(rows) do local result=read(r.operation_id);if result.ok then
        local row,q=result.value,result.value.terms
        local seller=s.session.characterId==q.seller.characterId
        local pair=Stables.StableMenu.TradePair(s,seller and q.buyer.source or q.seller.source)
        if (row.state=='draft' or row.state=='offered') and (os.time()>q.expiresAt or not pair
            or s.token~=(seller and q.sellerToken or q.buyerToken) or pair.token~=(seller and q.buyerToken or q.sellerToken)) then change(q.id,row.state,'cancelled')
        elseif row.state~='draft' or seller then offers[#offers+1]=view(row) end
    end end
    local data={available=true,players=Stables.StableMenu.TradePlayers(s),offers=offers}
    if horseId then
        local owned=R.ReadOwned(s.session,horseId);if not owned.ok then return owned end
        if owned.value.availability~='stored' then return bad('horse_busy') end
        local snapshot=T.HorseTradeSnapshot(s.session,horseId);if not snapshot.ok then return snapshot end
        data.horse=owned.value;data.items=snapshot.value.items
    end
    return F.Ok(data)
end
function D.Tick()
    if not installed then return end
    local rows=DB.query('SELECT operation_id FROM fs_horse_trades WHERE state IN '..active..' ORDER BY updated_at,operation_id LIMIT 5')
    for _,row in ipairs(rows or {}) do if not D.Resume(row.operation_id).ok then DB.exec('UPDATE fs_horse_trades SET updated_at=UTC_TIMESTAMP() WHERE operation_id=?',row.operation_id) end end
end
function D.Status()
    if not installed then return {enabled=D.Enabled(),recoveryAvailable=false,pending={}} end
    local ok,rows=pcall(DB.query,'SELECT operation_id,horse_id,state FROM fs_horse_trades WHERE state IN '..active..' ORDER BY updated_at,operation_id LIMIT 10')
    return {enabled=D.Enabled(),recoveryAvailable=ok,pending=ok and rows or nil}
end
