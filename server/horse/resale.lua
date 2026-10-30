-- Stored horse -> durable reservation -> keep tack -> retire asset -> issue once.
-- The existing checkout worker resumes confirmed sales, including while offline.
Stables.HorseResale={}
local S,F,R=Stables.HorseResale,Stables.Feather,Stables.OwnedRepository
local installed,busy=false,{}
local function bad(code) return F.Error(code or 'horse_sale_pending','Horse sale is pending or changed; refresh before retrying.') end
function S.Enabled() return Config.sales and Config.sales.enabled==true end
local function read(id,character,tx)
    if not F.IsUuid(id) then return bad('invalid_input') end
    local row=(tx or DB).one('SELECT * FROM fs_horse_sales WHERE operation_id=? AND character_id=?'..(tx and ' FOR UPDATE' or ''),id,character)
    if not row then return bad('horse_sale_not_found') end
    local ok,q=pcall(json.decode,row.record_json)
    if not ok or type(q)~='table' or q.kind~='horse_sale.v1' or q.id~=id or q.characterId~=character
        or row.horse_id~=q.horseId or not F.IsUuid(q.horseId) or not F.IsUuid(q.assetId) or not F.IsUuid(q.accountId)
        or not F.IsUuid(q.wallet) or not F.IsUuid(q.source) or not F.IsRevision(q.assetRevision) or q.assetRevision<1
        or not F.IsRevision(q.projectionRevision) or not F.IsRevision(q.amount) or q.amount<1 or q.amount>1000000000
        or not F.IsRevision(q.expiresAt) or (q.currency~='dollars' and q.currency~='gold')
        or not ({quoted=true,detaching=true,retiring=true,paying=true,sold=true,cancelled=true})[row.state] then return bad() end
    row.terms=q;return F.Ok(row)
end
local function view(row)
    local q=row.terms
    return F.Ok({operationId=q.id,horseId=q.horseId,name=q.name,amount=q.amount,currency=q.currency,state=row.state,expiresAt=q.expiresAt})
end
local function payout(q)
    return {accountId=q.wallet,currency=q.currency,amount=q.amount,reasonCode='stables.horse_sale',
        referenceType='stables_horse_sale',referenceId=q.id,idempotencyKey='stables.horse.sale:'..q.id}
end
local function context(q) return {actorCharacterId=q.characterId,actorAccountId=q.accountId,correlationId=q.id} end
local function preflight(q)
    local result=F.Call('feather-economy','CheckIssue',payout(q),context(q))
    if not result.ok or type(result.value)~='table' or result.value.allowed~=true or result.value.sourceAccountId~=q.source then return bad('horse_sale_payout_unavailable') end
    return F.Ok(true)
end
local function price(model,currency)
    local mapping=Horses.ModelToBreedMap[model]
    local breed=mapping and Horses.BreedCatalog[mapping.breed]
    local coat=breed and breed.colors[model]
    local multiplier=Config.sales.purchasedHorsePriceMultiplier
    if not coat or type(multiplier)~='number' or multiplier~=multiplier or multiplier<=0 or multiplier>1 then return nil end
    local mode=tonumber(coat.currency) or 3
    if currency~='dollars' and currency~='gold' or mode==1 and currency~='dollars' or mode==2 and currency~='gold'
        or mode~=1 and mode~=2 and mode~=3 then return nil end
    local base=tonumber(currency=='dollars' and coat.cashPrice or coat.goldPrice)
    if not base or base~=base or base<=0 or base>10000000 then return nil end
    -- Preserve the original whole-currency rounding policy.
    local amount=math.ceil(base*multiplier)*100
    return F.IsRevision(amount) and amount>0 and amount<=1000000000 and amount or nil
end
function S.Start()
    local ok=pcall(DB.query,'SELECT operation_id,character_id,horse_id,state,record_json FROM fs_horse_sales LIMIT 0')
    installed=ok
    if S.Enabled() and (not ok or not Stables.Tack.Enabled()) then return bad('horse_sale_setup_required') end
    return F.Ok(true)
end
function S.Quote(session,site,p,authorize)
    if not installed or not S.Enabled() then return bad('horse_sale_disabled') end
    local location=StableLocations[site]
    if not location or location.trainerBuy or location.shop.jobsEnabled or location.shop.hours.active then return bad('purchase_restricted') end
    local owned=R.ReadOwned(session,p.horseId);if not owned.ok then return owned end
    local h=owned.value
    if h.availability~='stored' then return bad('horse_busy') end
    local amount=price(h.modelKey,p.currency);if not amount then return bad('invalid_price') end
    local accounts=F.Call('feather-economy','FindAccountsByOwner',{ownerType='character',ownerId=session.characterId})
    if not accounts.ok then return accounts end
    local wallet
    for _,a in ipairs(accounts.value or {}) do
        if a.ownerType=='character' and a.ownerId==session.characterId and a.accountType=='wallet' and a.currency==p.currency and a.status=='open' then
            if wallet then return bad('ambiguous_wallet') end;wallet=a.accountId
        end
    end
    local source=F.Call('feather-economy','GetSystemAccount',{currency=p.currency,accountType='system_source'})
    if not source.ok then return source end
    local a=source.value
    if not F.IsUuid(wallet) or type(a)~='table' or not F.IsUuid(a.accountId) or a.currency~=p.currency or a.accountType~='system_source' or a.status~='open' then return bad('account_not_found') end
    local id=DB.one('SELECT UUID() AS id');if not id or not F.IsUuid(id.id) then return bad() end
    local q={kind='horse_sale.v1',id=id.id,characterId=session.characterId,accountId=session.accountId,horseId=h.horseId,
        assetId=h.assetId,assetRevision=h.assetRevision,projectionRevision=h.projectionRevision,name=h.name or h.modelKey,
        model=h.modelKey,currency=p.currency,amount=amount,wallet=wallet,source=a.accountId,site=site,expiresAt=os.time()+60}
    local allowed=preflight(q);if not allowed.ok then return allowed end
    if not authorize() or not F.IsCurrent(session) then return bad('session_stale') end
    if DB.exec("INSERT INTO fs_horse_sales(operation_id,character_id,horse_id,state,record_json) VALUES(?,?,?,'quoted',?)",q.id,q.characterId,q.horseId,json.encode(q))~=1 then return bad() end
    return view({terms=q,state='quoted'})
end
function S.Resume(id,character)
    if not installed or busy[id] then return bad() end;busy[id]=true
    local ok,result=pcall(function()
        local saved=read(id,character);if not saved.ok then return saved end
        local row,q=saved.value,saved.value.terms
        if row.state=='quoted' or row.state=='sold' or row.state=='cancelled' then return view(row) end
        if row.state=='detaching' then
            local outcome=bad()
            local committed=DB.transaction(function(tx)
                if not tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',character) then return false end
                local h=tx.one('SELECT owner_character_id,availability FROM fs_horses WHERE horse_id=? FOR UPDATE',q.horseId)
                if not h or h.owner_character_id~=character or h.availability~='selling' then return false end
                outcome=Stables.Tack.ReleaseSoldHorse(character,q.horseId);if not outcome.ok then return false end
                return tx.exec("UPDATE fs_horse_sales SET state='retiring' WHERE operation_id=? AND state='detaching'",id)==1
            end)
            if committed~=true then return outcome.ok and bad() or outcome end
            row.state='retiring'
        end
        if row.state=='retiring' then
            local allowed=preflight(q);if not allowed.ok then return allowed end
            local retired=F.Call('feather-assets','RetireAsset',{requestId='stables.horse.sale:'..id,assetId=q.assetId,
                expectedRevision=q.assetRevision,reasonCode='stables.horse_sale',referenceType='stables_horse_sale',referenceId=id})
            if not retired.ok then
                -- A definite CAS refusal is different from a lost reply. The
                -- latter must retain the original retirement/payout identities.
                if retired.code=='revision_conflict' then
                    DB.transaction(function(tx)
                        tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',character)
                        local current=read(id,character,tx)
                        if not current.ok or current.value.state~='retiring' then return false end
                        if tx.exec("UPDATE fs_horses SET availability='stored',revision=revision+1 WHERE horse_id=? AND owner_character_id=? AND availability='selling'",q.horseId,character)~=1 then return false end
                        return tx.exec("UPDATE fs_horse_sales SET state='cancelled' WHERE operation_id=? AND state='retiring'",id)==1
                    end)
                end
                return retired
            end
            local a=retired.value
            if type(a)~='table' or a.assetId~=q.assetId or a.status~='retired' or a.revision~=q.assetRevision+1 or a.owner~=nil then return bad() end
            if DB.exec("UPDATE fs_horse_sales SET state='paying' WHERE operation_id=? AND state='retiring'",id)~=1 then return bad() end
        end
        local paid=F.Call('feather-economy','Issue',payout(q),context(q));if not paid.ok then return paid end
        local receipt=paid.value
        if type(receipt)~='table' or not F.IsUuid(receipt.transactionId) or receipt.operation~='issue'
            or receipt.amount~=q.amount or receipt.currency~=q.currency or receipt.fromAccountId~=q.source or receipt.toAccountId~=q.wallet
            or receipt.reasonCode~='stables.horse_sale' or receipt.referenceType~='stables_horse_sale' or receipt.referenceId~=id
            or receipt.sourceResource~='bcc-stables' then return bad() end
        local committed=DB.transaction(function(tx)
            tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',character)
            local current=read(id,character,tx);if not current.ok then return false end
            if current.value.state=='sold' then return true end
            if current.value.state~='paying' then return false end
            if tx.exec("UPDATE fs_horses SET availability='sold',revision=revision+1 WHERE horse_id=? AND owner_character_id=? AND availability='selling'",q.horseId,character)~=1 then return false end
            tx.exec('UPDATE fs_character_stables SET selected_horse_id=NULL,revision=revision+1 WHERE character_id=? AND selected_horse_id=?',character,q.horseId)
            return tx.exec("UPDATE fs_horse_sales SET state='sold' WHERE operation_id=? AND state='paying'",id)==1
        end)
        if committed~=true then return bad() end
        row.state='sold';return view(row)
    end)
    busy[id]=nil;return ok and result or bad()
end
function S.Confirm(session,site,p,authorize)
    local saved=read(p.operationId,session.characterId);if not saved.ok then return saved end
    local row,q=saved.value,saved.value.terms
    if p.currency~=q.currency or p.amount~=q.amount or site~=q.site then return bad('price_conflict') end
    if row.state~='quoted' then return S.Resume(q.id,q.characterId) end
    if not S.Enabled() then return bad('horse_sale_disabled') end
    if os.time()>q.expiresAt or price(q.model,q.currency)~=q.amount then return bad('quote_expired') end
    local owned=R.ReadOwned(session,q.horseId);if not owned.ok then return owned end
    if owned.value.assetRevision~=q.assetRevision or owned.value.projectionRevision~=q.projectionRevision or owned.value.availability~='stored' then return bad('revision_conflict') end
    local allowed=preflight(q);if not allowed.ok then return allowed end
    local committed=DB.transaction(function(tx)
        if not tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',q.characterId) then return false end
        local current=read(q.id,q.characterId,tx);if not current.ok then return false end
        if current.value.state~='quoted' then return true end
        if not authorize() or not F.IsCurrent(session) or os.time()>q.expiresAt then return false end
        if tx.one('SELECT generation_id FROM fs_call_slots WHERE character_id=? FOR UPDATE',q.characterId)
            or tx.one("SELECT operation_id FROM fs_care_operations WHERE character_id=? AND state NOT IN ('applied','cancelled') LIMIT 1 FOR UPDATE",q.characterId) then return false end
        if tx.exec("UPDATE fs_horses SET availability='selling',revision=revision+1 WHERE horse_id=? AND owner_character_id=? AND availability='stored' AND biological_state='alive' AND revision=?",q.horseId,q.characterId,q.projectionRevision)~=1 then return false end
        return tx.exec("UPDATE fs_horse_sales SET state='detaching' WHERE operation_id=? AND state='quoted'",q.id)==1
    end)
    if committed~=true then return bad('horse_busy') end
    return S.Resume(q.id,q.characterId)
end
function S.Tick()
    if not installed then return end
    local rows=DB.query("SELECT operation_id,character_id FROM fs_horse_sales WHERE state IN ('detaching','retiring','paying') ORDER BY updated_at,operation_id LIMIT 5")
    for _,row in ipairs(rows or {}) do S.Resume(row.operation_id,row.character_id) end
end
function S.Status()
    if not installed then return {enabled=S.Enabled(),recoveryAvailable=false,pending={}} end
    local ok,rows=pcall(DB.query,"SELECT operation_id,character_id,horse_id,state FROM fs_horse_sales WHERE state IN ('detaching','retiring','paying') ORDER BY updated_at,operation_id LIMIT 10")
    return {enabled=S.Enabled(),recoveryAvailable=ok,pending=ok and rows or nil}
end
