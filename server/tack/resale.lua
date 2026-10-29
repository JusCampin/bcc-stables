-- Quote -> exact Inventory surrender receipt -> idempotent Economy payout.
-- Recovery shares the existing checkout worker; no provider SQL/tx handles cross CFX.
Stables.TackResale={}
local S,F,T=Stables.TackResale,Stables.Feather,Stables.Tack
local installed,pending=false,true
local busy={}
local currencies={'dollars','gold'}
local function bad(code) return F.Error(code or 'tack_sale_pending','Tack sale is pending or changed; refresh before retrying.') end
function S.Enabled() return T.Enabled() and Config.tack.resaleEnabled==true end
local function terms(id,character)
    if not F.IsUuid(id) then return bad('invalid_input') end
    local row=DB.one('SELECT * FROM fs_tack_sales WHERE operation_id=?',id)
    if not row or row.character_id~=character then return bad('tack_not_found') end
    local ok,q=pcall(json.decode,row.record_json)
    if not ok or type(q)~='table' or q.kind~='tack_sale.v1' or q.id~=id or q.characterId~=character
        or not F.IsUuid(q.accountId) or not F.IsRevision(q.selected) or q.selected<1 or type(q.items)~='table' or #q.items<1 or #q.items>3
        or type(q.equipment)~='table' or type(q.totals)~='table' or type(q.wallets)~='table' or type(q.sources)~='table'
        or not F.IsRevision(q.expiresAt) or not F.IsRevision(q.percent) or q.percent>100
        or not ({quoted=true,retiring=true,paying=true,sold=true,cancelled=true})[row.state] then return bad() end
    for _,currency in ipairs(currencies) do
        local total=q.totals[currency]
        if not F.IsRevision(total) or total>1000000000 or total>0 and (not F.IsUuid(q.wallets[currency]) or not F.IsUuid(q.sources[currency])) then return bad() end
    end
    local selected=false
    for _,item in ipairs(q.items) do
        if not F.IsRevision(item.instanceId) or item.instanceId<1 or not F.IsRevision(item.revision) then return bad() end
        if item.instanceId==q.selected then selected=true end
    end
    if not selected or q.totals.dollars+q.totals.gold==0 then return bad() end
    row.terms=q;return F.Ok(row)
end
local function view(row)
    local q=row.terms
    return F.Ok({operationId=q.id,state=row.state,selected=q.selected,items=q.items,totals=q.totals,percent=q.percent,expiresAt=q.expiresAt})
end
local function payout(q,currency)
    return {accountId=q.wallets[currency],currency=currency,amount=q.totals[currency],reasonCode='stables.tack_sale',
        referenceType='stables_tack_sale',referenceId=q.id,idempotencyKey='stables.tack.sale:'..q.id..':'..currency}
end
local function context(q) return {actorCharacterId=q.characterId,actorAccountId=q.accountId,correlationId=q.id} end
local function preflight(q)
    for _,currency in ipairs(currencies) do if q.totals[currency]>0 then
        local allowed=F.Call('feather-economy','CheckIssue',payout(q,currency),context(q))
        if not allowed.ok or type(allowed.value)~='table' or allowed.value.allowed~=true or allowed.value.sourceAccountId~=q.sources[currency] then return bad('tack_sale_payout_unavailable') end
    end end
    return F.Ok(true)
end
function S.Start()
    local ok=pcall(DB.query,'SELECT operation_id,character_id,state,record_json FROM fs_tack_sales LIMIT 0')
    installed=ok;pending=ok
    if S.Enabled() and not ok then return bad('tack_sale_schema_required') end
    if S.Enabled() then
        local inventory=T.CheckSaleProvider();if not inventory.ok then return inventory end
        local economy=F.Call('feather-economy','CheckIssue',{}, {})
        if economy.ok or economy.code~='authorization_denied' then return bad('tack_sale_payout_unavailable') end
    end
    return F.Ok(true)
end
function S.Quote(session,site,p,authorize)
    if not installed or not S.Enabled() then return bad('tack_sale_disabled') end
    local percent=Config.tack.resalePercent
    if not F.IsRevision(percent) or percent>100 then return bad('invalid_config') end
    if not F.IsRevision(p.instanceId) or p.instanceId<1 then return bad('invalid_input') end
    if not StableLocations[site] or StableLocations[site].shop.jobsEnabled or StableLocations[site].shop.hours.active then return bad('purchase_restricted') end
    if DB.one("SELECT operation_id FROM fs_tack_sales WHERE character_id=? AND state IN ('retiring','paying') LIMIT 1",session.characterId) then return bad() end
    local snapshot=T.SaleSnapshot(session,p.instanceId);if not snapshot.ok then return snapshot end
    local q={kind='tack_sale.v1',characterId=session.characterId,accountId=session.accountId,site=site,selected=p.instanceId,
        percent=percent,expiresAt=os.time()+45,items=snapshot.value.items,equipment=snapshot.value.equipment,
        totals={dollars=0,gold=0},wallets={},sources={}}
    for _,item in ipairs(q.items) do
        local amount=math.floor(item.paid*percent*item.condition/(100*item.maximum))
        q.totals[item.currency]=q.totals[item.currency]+amount
    end
    if q.totals.dollars+q.totals.gold==0 then return bad('tack_sale_no_value') end
    if q.totals.dollars>1000000000 or q.totals.gold>1000000000 then return bad('invalid_price') end
    local accounts=F.Call('feather-economy','FindAccountsByOwner',{ownerType='character',ownerId=session.characterId})
    if not accounts.ok then return accounts end
    for _,currency in ipairs(currencies) do if q.totals[currency]>0 then
        for _,account in ipairs(accounts.value or {}) do
            if account.ownerType=='character' and account.ownerId==session.characterId and account.accountType=='wallet'
                and account.currency==currency and account.status=='open' then
                if q.wallets[currency] then return bad('ambiguous_wallet') end;q.wallets[currency]=account.accountId
            end
        end
        if not F.IsUuid(q.wallets[currency]) then return bad('account_not_found') end
        local source=F.Call('feather-economy','GetSystemAccount',{currency=currency,accountType='system_source'})
        if not source.ok or not source.value or not F.IsUuid(source.value.accountId) or source.value.accountType~='system_source'
            or source.value.currency~=currency or source.value.status~='open' then return bad('account_not_found') end
        q.sources[currency]=source.value.accountId
    end end
    local uuid=DB.one('SELECT UUID() AS id');if not uuid or not F.IsUuid(uuid.id) then return bad() end;q.id=uuid.id
    local allowed=preflight(q);if not allowed.ok then return allowed end
    if not authorize() or not F.IsCurrent(session) then return bad('session_stale') end
    if DB.exec("INSERT INTO fs_tack_sales(operation_id,character_id,state,record_json) VALUES(?,?,'quoted',?)",q.id,q.characterId,json.encode(q))~=1 then return bad() end
    return view({terms=q,state='quoted'})
end
function S.Resume(id,character)
    if not installed or busy[id] then return bad() end;busy[id]=true
    local ok,result=pcall(function()
        local read=terms(id,character);if not read.ok then return read end
        local row,q=read.value,read.value.terms
        if row.state=='quoted' or row.state=='sold' or row.state=='cancelled' then return view(row) end
        if row.state=='retiring' then
            local allowed=preflight(q);if not allowed.ok then return allowed end
            local retired=T.RetireSale(q)
            if not retired.ok then
                if retired.code=='collection_conflict' or retired.code=='not_found' then
                    DB.exec("UPDATE fs_tack_sales SET state='cancelled' WHERE operation_id=? AND state='retiring'",id)
                    return bad('tack_conflict')
                end
                return retired
            end
            local receipt=retired.value
            if type(receipt)~='table' or receipt.retired~=true or receipt.operationId~='stables.tack.sale:'..id
                or receipt.characterId~=character or receipt.count~=#q.items then return bad() end
            if DB.exec("UPDATE fs_tack_sales SET state='paying' WHERE operation_id=? AND state='retiring'",id)~=1 then return bad() end
        end
        for _,currency in ipairs(currencies) do if q.totals[currency]>0 then
            local paid=F.Call('feather-economy','Issue',payout(q,currency),context(q));if not paid.ok then return bad() end
            local r=paid.value
            if type(r)~='table' or not F.IsUuid(r.transactionId) or r.operation~='issue' or r.sourceResource~='bcc-stables'
                or r.reasonCode~='stables.tack_sale' or r.referenceType~='stables_tack_sale' or r.referenceId~=id
                or r.amount~=q.totals[currency] or r.currency~=currency or r.toAccountId~=q.wallets[currency]
                or r.fromAccountId~=q.sources[currency] then return bad() end
        end end
        if DB.exec("UPDATE fs_tack_sales SET state='sold' WHERE operation_id=? AND state='paying'",id)~=1 then return bad() end
        return view(assert(terms(id,character).value))
    end)
    busy[id]=nil;return ok and result or bad()
end
local function same(a,b)
    if #a.items~=#b.items then return false end
    for n,item in ipairs(a.items) do
        local other=b.items[n]
        for _,key in ipairs({'instanceId','revision','condition','catalogId','paid','currency','maximum'}) do if item[key]~=other[key] then return false end end
    end
    for slot,id in pairs(a.equipment) do if b.equipment[slot]~=id then return false end end
    for slot,id in pairs(b.equipment) do if a.equipment[slot]~=id then return false end end
    return true
end
function S.Confirm(session,site,p,authorize)
    local read=terms(p.operationId,session.characterId);if not read.ok then return read end
    local row,q=read.value,read.value.terms
    if p.dollars~=q.totals.dollars or p.gold~=q.totals.gold then return bad('price_conflict') end
    if row.state~='quoted' then return S.Resume(q.id,q.characterId) end
    if not S.Enabled() then return bad('tack_sale_disabled') end
    if site~=q.site or os.time()>q.expiresAt or Config.tack.resalePercent~=q.percent then return bad('quote_expired') end
    local snapshot=T.SaleSnapshot(session,q.selected);if not snapshot.ok then return snapshot end
    if not same(q,snapshot.value) then return bad('tack_conflict') end
    local allowed=preflight(q);if not allowed.ok then return allowed end
    local accepted=DB.transaction(function(tx)
        if not tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',session.characterId)
            or not authorize() or not F.IsCurrent(session) or os.time()>q.expiresAt then return false end
        if tx.one('SELECT generation_id FROM fs_call_slots WHERE character_id=? FOR UPDATE',session.characterId)
            or tx.one("SELECT operation_id FROM fs_tack_sales WHERE character_id=? AND state IN ('retiring','paying') LIMIT 1 FOR UPDATE",session.characterId) then return false end
        return tx.exec("UPDATE fs_tack_sales SET state='retiring' WHERE operation_id=? AND state='quoted'",q.id)==1
    end)
    if accepted~=true then return bad() end
    pending=true;return S.Resume(q.id,q.characterId)
end
function S.Tick()
    if not installed or not pending then return end;pending=false
    local ok,rows=pcall(DB.query,"SELECT operation_id,character_id FROM fs_tack_sales WHERE state IN ('retiring','paying') ORDER BY updated_at,operation_id LIMIT 5")
    if not ok or type(rows)~='table' then pending=true;return end
    pending=#rows>0
    for _,row in ipairs(rows) do if not S.Resume(row.operation_id,row.character_id).ok then
        DB.exec('UPDATE fs_tack_sales SET updated_at=UTC_TIMESTAMP() WHERE operation_id=?',row.operation_id)
    end end
end

function S.Status()
    if not installed then return {enabled=S.Enabled(),ready=false,pending={}} end
    local ok,rows=pcall(DB.query,"SELECT operation_id,character_id,state FROM fs_tack_sales WHERE state IN ('retiring','paying') ORDER BY updated_at,operation_id LIMIT 10")
    return {enabled=S.Enabled(),ready=true,recoveryAvailable=ok,pending=ok and rows or nil}
end
