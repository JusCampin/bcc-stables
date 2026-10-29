-- Two-party consent precedes durable payment/custody settlement. Recovery never
-- replaces items or repeats a debit: each provider owns its immutable receipt.
Stables.TackTrade={}
local D,F,T=Stables.TackTrade,Stables.Feather,Stables.Tack
local installed,pending=false,true
local busy={}
local active="('accepted','moving','paying','refunding')"
local function bad(code) return F.Error(code or 'tack_trade_pending','Trade changed or is pending; refresh the trade list.') end
function D.Enabled() return T.Enabled() and Config.tack.tradingEnabled==true end
function D.Start()
    installed=pcall(DB.query,'SELECT operation_id,state,record_json,payment_transaction_id FROM fs_tack_trades LIMIT 0')
    pending=installed
    if D.Enabled() and installed then return T.CheckTradeProvider() end
    return D.Enabled() and not installed and bad('tack_trade_schema_required') or F.Ok(true)
end
local function read(id)
    if not F.IsUuid(id) then return bad('invalid_input') end
    local row=DB.one('SELECT * FROM fs_tack_trades WHERE operation_id=?',id)
    if not row then return bad('not_found') end
    local ok,q=pcall(json.decode,row.record_json)
    if not ok or type(q)~='table' or q.kind~='tack_trade.v1' or q.id~=id
        or type(q.seller)~='table' or type(q.buyer)~='table' or not F.IsUuid(q.seller.characterId)
        or not F.IsUuid(q.buyer.characterId) or q.seller.characterId==q.buyer.characterId
        or q.seller.characterId~=row.seller_character_id or q.buyer.characterId~=row.buyer_character_id
        or not F.IsRevision(q.amount) or q.amount>1000000000 or (q.currency~='dollars' and q.currency~='gold')
        or type(q.items)~='table' or #q.items<1 or #q.items>3 or type(q.equipment)~='table'
        or not F.IsRevision(q.expiresAt) or not ({draft=true,offered=true,accepted=true,moving=true,paying=true,refunding=true,completed=true,cancelled=true})[row.state] then return bad() end
    row.terms=q;return F.Ok(row)
end
local function view(row)
    local q=row.terms
    return {operationId=q.id,state=row.state,items=q.items,amount=q.amount,currency=q.currency,
        sellerSource=q.seller.source,buyerSource=q.buyer.source,expiresAt=q.expiresAt,
        sellerName=Stables.StableMenu.CharacterName(q.seller.characterId),
        buyerName=Stables.StableMenu.CharacterName(q.buyer.characterId)}
end
local function context(p,id) return {actorCharacterId=p.characterId,actorAccountId=p.accountId,correlationId=id} end
local function payout(q)
    return {accountId=q.sellerWallet,currency=q.currency,amount=q.amount,reasonCode='stables.tack_trade_sale',
        referenceType='stables_tack_trade',referenceId=q.id,idempotencyKey='stables.tack.trade.sale:'..q.id}
end
local function preflight(q)
    if q.amount==0 then return F.Ok(true) end
    local result=F.Call('feather-economy','CheckIssue',payout(q),context(q.seller,q.id))
    return result.ok and result.value.allowed==true and result.value.sourceAccountId==q.sourceAccount and F.Ok(true) or bad('tack_trade_payment_unavailable')
end
local function wallet(character,currency)
    local result=F.Call('feather-economy','FindAccountsByOwner',{ownerType='character',ownerId=character})
    if not result.ok then return result end
    local id
    for _,a in ipairs(result.value or {}) do if a.ownerType=='character' and a.ownerId==character
        and a.accountType=='wallet' and a.currency==currency and a.status=='open' then
        if id then return bad('ambiguous_wallet') end;id=a.accountId
    end end
    return F.IsUuid(id) and F.Ok(id) or bad('account_not_found')
end
local function same(q,snapshot)
    if #q.items~=#snapshot.items then return false end
    for i,a in ipairs(q.items) do for _,key in ipairs({'instanceId','revision','catalogId','condition','maximum','currency','paid'}) do
        if a[key]~=snapshot.items[i][key] then return false end
    end end
    for slot,id in pairs(q.equipment) do if snapshot.equipment[slot]~=id then return false end end
    for slot,id in pairs(snapshot.equipment) do if q.equipment[slot]~=id then return false end end
    return true
end
function D.Offer(s,p)
    if not installed or not D.Enabled() then return bad('tack_trade_disabled') end
    local pair=Stables.StableMenu.TradePair(s,p.recipientSource)
    if not pair then return bad('tack_trade_nearby') end
    local snapshot=T.SaleSnapshot(s.session,p.instanceId);if not snapshot.ok then return snapshot end
    local q={kind='tack_trade.v1',seller=s.session,buyer=pair.session,site=s.site,sellerToken=s.token,buyerToken=pair.token,
        selected=p.instanceId,amount=p.amount,currency=p.currency,items=snapshot.value.items,equipment=snapshot.value.equipment,expiresAt=os.time()+180}
    if not F.IsRevision(q.amount) or q.amount>1000000000 or (q.currency~='dollars' and q.currency~='gold') then return bad('invalid_price') end
    local uuid=DB.one('SELECT UUID() AS id');if not uuid or not F.IsUuid(uuid.id) then return bad() end;q.id=uuid.id
    if q.amount>0 then
        local seller=wallet(q.seller.characterId,q.currency);if not seller.ok then return seller end;q.sellerWallet=seller.value
        local buyer=wallet(q.buyer.characterId,q.currency);if not buyer.ok then return buyer end;q.buyerWallet=buyer.value
        for _,kind in ipairs({'system_sink','system_source'}) do
            local a=F.Call('feather-economy','GetSystemAccount',{currency=q.currency,accountType=kind})
            if not a.ok or not a.value or not F.IsUuid(a.value.accountId) or a.value.accountType~=kind
                or a.value.currency~=q.currency or a.value.status~='open' then return bad('account_not_found') end
            q[kind=='system_sink' and 'sinkAccount' or 'sourceAccount']=a.value.accountId
        end
        local check=preflight(q);if not check.ok then return check end
    end
    -- One offer/settlement per character. Sorted admission locks serialize both
    -- directions without locking Inventory or Economy through this transaction.
    local chars={q.seller.characterId,q.buyer.characterId};table.sort(chars)
    local saved=DB.transaction(function(tx)
        for _,char in ipairs(chars) do
            tx.exec('INSERT IGNORE INTO fs_character_stables(character_id) VALUES(?)',char)
            if not tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',char) then return false end
            if tx.one("SELECT operation_id FROM fs_tack_trades WHERE (seller_character_id=? OR buyer_character_id=?) AND (state IN "..active.." OR state IN ('draft','offered') AND updated_at>UTC_TIMESTAMP()-INTERVAL 180 SECOND) LIMIT 1 FOR UPDATE",char,char) then return false end
        end
        if Stables.StableMenu.TradePair(s,p.recipientSource)~=pair then return false end
        return tx.exec("INSERT INTO fs_tack_trades(operation_id,seller_character_id,buyer_character_id,state,record_json) VALUES(?,?,?,'draft',?)",
            q.id,q.seller.characterId,q.buyer.characterId,json.encode(q))==1
    end)
    return saved==true and F.Ok(view({terms=q,state='draft'})) or bad('tack_trade_busy')
end
local function change(id,from,to,payment)
    return DB.exec('UPDATE fs_tack_trades SET state=?,payment_transaction_id=COALESCE(?,payment_transaction_id) WHERE operation_id=? AND state=?',to,payment,id,from)==1
end
function D.Resume(id)
    if busy[id] then return bad() end;busy[id]=true
    local ok,result=pcall(function()
        local found=read(id);if not found.ok then return found end
        local row,q=found.value,found.value.terms
        if row.state=='draft' or row.state=='offered' or row.state=='completed' or row.state=='cancelled' then return F.Ok(view(row)) end
        if row.state=='accepted' then
            local check=preflight(q);if not check.ok then return check end
            local payment
            if q.amount>0 then
                local paid=F.Call('feather-economy','Transfer',{fromAccountId=q.buyerWallet,toAccountId=q.sinkAccount,currency=q.currency,
                    amount=q.amount,reasonCode='stables.tack_trade_payment',referenceType='stables_tack_trade',referenceId=q.id,
                    idempotencyKey='stables.tack.trade.payment:'..q.id},context(q.buyer,q.id))
                if not paid.ok then
                    if paid.code=='insufficient_funds' then change(id,'accepted','cancelled') end
                    return paid
                end
                local r=paid.value
                if not F.IsUuid(r.transactionId) or r.operation~='transfer' or r.sourceResource~='bcc-stables'
                    or r.fromAccountId~=q.buyerWallet or r.toAccountId~=q.sinkAccount or r.amount~=q.amount or r.currency~=q.currency
                    or r.reasonCode~='stables.tack_trade_payment' or r.referenceType~='stables_tack_trade' or r.referenceId~=q.id then return bad() end
                payment=r.transactionId
            end
            if not change(id,'accepted','moving',payment) then return bad() end
            row.state='moving';row.payment_transaction_id=payment
        end
        if row.state=='moving' then
            local moved=T.TransferTrade(q)
            if not moved.ok then
                -- These are certain transactional refusals. Unknown replies retain
                -- moving and retry the historical transfer receipt, never refund.
                if ({collection_conflict=true,collection_full=true,denied=true})[moved.code] then
                    change(id,'moving',q.amount>0 and 'refunding' or 'cancelled')
                end
                return moved
            end
            local r=moved.value
            if r.transferred~=true or r.operationId~='stables.tack.trade:'..id or r.characterId~=q.seller.characterId
                or r.recipientCharacterId~=q.buyer.characterId or r.count~=#q.items then return bad() end
            if not change(id,'moving',q.amount>0 and 'paying' or 'completed') then return bad() end
            row.state=q.amount>0 and 'paying' or 'completed'
        end
        if row.state=='paying' then
            local paid=F.Call('feather-economy','Issue',payout(q),context(q.seller,q.id));if not paid.ok then return paid end
            local r=paid.value
            if not F.IsUuid(r.transactionId) or r.operation~='issue' or r.sourceResource~='bcc-stables'
                or r.fromAccountId~=q.sourceAccount or r.toAccountId~=q.sellerWallet or r.amount~=q.amount or r.currency~=q.currency
                or r.reasonCode~='stables.tack_trade_sale' or r.referenceType~='stables_tack_trade' or r.referenceId~=q.id then return bad() end
            if not change(id,'paying','completed') then return bad() end
        elseif row.state=='refunding' then
            local refund=F.Call('feather-economy','ReversePayment',{transactionId=row.payment_transaction_id},context(q.buyer,q.id))
            if not refund.ok then return refund end
            local r=refund.value
            if not F.IsUuid(r.transactionId) or r.operation~='reversal' or r.amount~=q.amount or r.currency~=q.currency
                or r.sourceResource~='bcc-stables' or r.reasonCode~='stables.tack_trade_refund'
                or r.fromAccountId~=q.sinkAccount or r.toAccountId~=q.buyerWallet
                or r.referenceType~='economy_transaction' or r.referenceId~=row.payment_transaction_id then return bad() end
            if not change(id,'refunding','cancelled') then return bad() end
        end
        return F.Ok(view(assert(read(id).value)))
    end)
    busy[id]=nil;return ok and result or bad()
end
function D.Respond(s,p)
    local found=read(p.operationId);if not found.ok then return found end
    local row,q=found.value,found.value.terms
    local seller=s.session.characterId==q.seller.characterId
    if not seller and s.session.characterId~=q.buyer.characterId then return bad('not_found') end
    if row.state~='offered' and row.state~='draft' then return F.Ok(view(row)) end
    if row.state=='draft' and not seller then return bad('not_found') end
    if p.accept~=true then
        change(q.id,row.state,'cancelled');return F.Ok(view(assert(read(q.id).value)))
    end
    if row.state=='draft' then
        local pair=Stables.StableMenu.TradePair(s,q.buyer.source)
        if not D.Enabled() or not pair or s.token~=q.sellerToken or pair.token~=q.buyerToken or os.time()>q.expiresAt
            or p.amount~=q.amount or p.currency~=q.currency then return bad('quote_expired') end
        local snapshot=T.SaleSnapshot(s.session,q.selected)
        if not snapshot.ok or not same(q,snapshot.value) then return bad('tack_conflict') end
        if Stables.StableMenu.TradePair(s,q.buyer.source)~=pair or os.time()>q.expiresAt then return bad('quote_expired') end
        if not change(q.id,'draft','offered') then return bad() end
        return F.Ok(view(assert(read(q.id).value)))
    end
    if seller or not D.Enabled() or p.amount~=q.amount or p.currency~=q.currency then return bad('price_conflict') end
    local pair=Stables.StableMenu.TradePair(s,q.seller.source)
    if not pair or pair.token~=q.sellerToken or s.token~=q.buyerToken or os.time()>q.expiresAt
        or s.session.sessionId~=q.buyer.sessionId or pair.session.sessionId~=q.seller.sessionId then return bad('quote_expired') end
    local snapshot=T.SaleSnapshot(pair.session,q.selected)
    if not snapshot.ok or not same(q,snapshot.value) then return bad('tack_conflict') end
    local allowed=preflight(q);if not allowed.ok then return allowed end
    if Stables.StableMenu.TradePair(s,q.seller.source)~=pair or os.time()>q.expiresAt then return bad('quote_expired') end
    if not change(q.id,'offered','accepted') then return bad() end
    pending=true;return D.Resume(q.id)
end
function D.List(s)
    if not installed or not D.Enabled() then return F.Ok({available=false,players={},offers={}}) end
    local rows=DB.query("SELECT operation_id FROM fs_tack_trades WHERE (seller_character_id=? OR buyer_character_id=?) AND (state IN "..active.." OR state IN ('draft','offered')) ORDER BY created_at DESC LIMIT 10",
        s.session.characterId,s.session.characterId)
    local offers={}
    for _,r in ipairs(rows) do local found=read(r.operation_id);if found.ok then
        local row,q=found.value,found.value.terms
        local seller=s.session.characterId==q.seller.characterId
        local pair=Stables.StableMenu.TradePair(s,seller and q.buyer.source or q.seller.source)
        local ownToken=seller and q.sellerToken or q.buyerToken
        local otherToken=seller and q.buyerToken or q.sellerToken
        if (row.state=='draft' or row.state=='offered') and (os.time()>q.expiresAt or not pair or s.token~=ownToken or pair.token~=otherToken) then
            change(q.id,row.state,'cancelled')
        elseif row.state~='draft' or s.session.characterId==q.seller.characterId then offers[#offers+1]=view(row) end
    end end
    return F.Ok({available=true,players=Stables.StableMenu.TradePlayers(s),offers=offers})
end
function D.Tick()
    if not installed or not pending then return end;pending=false
    local ok,rows=pcall(DB.query,'SELECT operation_id FROM fs_tack_trades WHERE state IN '..active..' ORDER BY updated_at,operation_id LIMIT 5')
    if not ok then pending=true;return end;pending=#rows>0
    for _,row in ipairs(rows) do if not D.Resume(row.operation_id).ok then
        DB.exec('UPDATE fs_tack_trades SET updated_at=UTC_TIMESTAMP() WHERE operation_id=?',row.operation_id)
    end end
end
function D.Status()
    if not installed then return {enabled=D.Enabled(),ready=false} end
    local ok,rows=pcall(DB.query,'SELECT operation_id,state FROM fs_tack_trades WHERE state IN '..active..' ORDER BY updated_at,operation_id LIMIT 10')
    return {enabled=D.Enabled(),ready=true,recoveryAvailable=ok,pending=ok and rows or nil}
end
