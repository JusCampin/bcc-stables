-- Durable checkout in the existing Stables purchase tables. No provider SQL.
Stables.Checkout = {}
local P,F,R=Stables.Checkout,Stables.Feather,Stables.OwnedRepository
local working={}
function P.Enabled() return Config.commerce and Config.commerce.purchasesEnabled==true end
local function view(row)
    local q=row.terms
    return F.Ok({operationId=q.id,horseId=q.id,modelKey=q.model,name=q.name,gender=q.gender,
        currency=q.currency,amount=q.amount,expiresAt=q.expiresAt,state=row.state})
end
local function read(id,character,tx)
    if not F.IsUuid(id) then return F.Error('invalid_input','Purchase identity required.') end
    local row=(tx or DB).one('SELECT * FROM fs_operations WHERE operation_id=? AND character_id=?'..(tx and ' FOR UPDATE' or ''),id,character)
    if not row then return F.Error('purchase_not_found','Purchase not found.') end
    local ok,q=pcall(json.decode,row.record_json)
    if not ok or type(q)~='table' or q.kind~='checkout_v1' or q.id~=id or q.characterId~=character
        or row.fingerprint~='checkout.v1:'..id or row.horse_id~=id or row.quote_id~=id
        or row.catalog_id~=q.model or row.currency~=q.currency or tonumber(row.amount)~=q.amount
        or row.wallet_account_id~=q.wallet or row.sink_account_id~=q.sink or row.payment_key~='stables.pay:'..id
        or not F.IsUuid(q.wallet) or not F.IsUuid(q.sink) or not R.NormalizeName(q.name)
        or (q.gender~='male' and q.gender~='female') or not F.IsRevision(q.amount) or q.amount<1 then
        return F.Error('purchase_reconciliation_required','Purchase evidence disagrees.')
    end
    return F.Ok({terms=q,state=row.state,payment=row.payment_transaction_id})
end
local function price(site,model,currency)
    local mapping=type(model)=='string' and Horses.ModelToBreedMap[model]
    local breed=mapping and Horses.BreedCatalog[mapping.breed]
    local coat=breed and breed.colors[model]
    local location=StableLocations[site]
    if not coat or #model>64 or not model:match('^a_c_horse_[a-z0-9_]+$') or not location
        or location.trainerBuy or location.shop.jobsEnabled or location.shop.hours.active then
        return F.Error('purchase_restricted','This horse or stable is not available for public purchase.')
    end
    -- Fail closed until authoritative job/trainer integration is connected.
    for _,models in pairs(Horses.JobLocks or {}) do
        for _,locked in ipairs(models) do if locked==model then return F.Error('purchase_restricted','This horse requires restricted access.') end end
    end
    local mode=tonumber(coat.currency) or 3
    if mode==4 then return F.Error('free_purchase_unavailable','Free checkout is not enabled by the existing schema.') end
    if (currency~='dollars' and currency~='gold') or (mode==1 and currency~='dollars')
        or (mode==2 and currency~='gold') or (mode~=1 and mode~=2 and mode~=3) then
        return F.Error('invalid_currency','Choose an available payment currency.')
    end
    local value=tonumber(currency=='dollars' and coat.cashPrice or coat.goldPrice)
    if not value or value~=value or value<=0 or value>10000000 then return F.Error('invalid_price','Catalog price unavailable.') end
    local amount=math.floor(value*100+0.5)
    if math.abs(value*100-amount)>0.000001 then return F.Error('invalid_price','Price exceeds currency precision.') end
    return F.Ok(amount)
end
function P.Quote(session,site,p,authorize)
    if not P.Enabled() then return F.Error('purchase_disabled','Purchasing is disabled.') end
    local name=R.NormalizeName(p.name)
    if not name or (p.gender~='male' and p.gender~='female') then return F.Error('invalid_name','Supply a valid horse name and sex.') end
    local cost=price(site,p.modelKey,p.currency); if not cost.ok then return cost end
    local accounts=F.Call('feather-economy','FindAccountsByOwner',{ownerType='character',ownerId=session.characterId})
    if not accounts.ok then return accounts end
    local wallet
    for _,a in ipairs(accounts.value or {}) do
        if a.accountType=='wallet' and a.currency==p.currency and a.ownerType=='character'
            and a.ownerId==session.characterId and a.status=='open' then
            if wallet then return F.Error('ambiguous_wallet','Wallet is ambiguous.') end
            wallet=a.accountId
        end
    end
    local sink=F.Call('feather-economy','GetSystemAccount',{currency=p.currency,accountType='system_sink'})
    if not sink.ok then return sink end
    if not F.IsUuid(wallet) or type(sink.value)~='table' or not F.IsUuid(sink.value.accountId)
        or sink.value.accountType~='system_sink' or sink.value.currency~=p.currency or sink.value.status~='open' then
        return F.Error('account_not_found','Matching open wallet and sink required.')
    end
    if not authorize() then return F.Error('session_stale','Stable session changed.') end
    local id=DB.one('SELECT UUID() AS id')
    if not id or not F.IsUuid(id.id) then return F.Error('database_unavailable','Purchase identity unavailable.') end
    local q={kind='checkout_v1',id=id.id,characterId=session.characterId,accountId=session.accountId,
        site=site,model=p.modelKey,name=name,gender=p.gender,currency=p.currency,amount=cost.value,
        wallet=wallet,sink=sink.value.accountId,expiresAt=os.time()+60}
    if DB.exec([[INSERT INTO fs_operations (operation_id,character_id,horse_id,quote_id,catalog_id,catalog_revision,
        currency,amount,wallet_account_id,sink_account_id,payment_key,fingerprint,state,revision,record_json)
        VALUES (?,?,?,?,?,1,?,?,?,?,?,?,'reserved',0,?)]],q.id,q.characterId,q.id,q.id,q.model,q.currency,q.amount,
        q.wallet,q.sink,'stables.pay:'..q.id,'checkout.v1:'..q.id,json.encode(q))~=1 then
        return F.Error('database_unavailable','Purchase quote not saved.')
    end
    return view({terms=q,state='reserved'})
end
local function assetRequest(q)
    return {requestId='stables.register:'..q.id,assetType='horse',modelKey=q.model,
        holderType='character',holderId=q.characterId,provenanceType='stable_purchase',provenanceId=q.id,
        metadataVersion=1,metadata={stablesHorseId=q.id,name=q.name,gender=q.gender},
        reasonCode='stables.horse_purchase',referenceType='stables_order',referenceId=q.id}
end
local function resume(id,character)
    local saved=read(id,character); if not saved.ok then return saved end
    local row,q=saved.value,saved.value.terms
    if row.state=='fulfilled' or row.state=='reserved' or row.state=='cancelled' then return view(row) end
    if row.state=='payment_pending' then
        local paid=F.Call('feather-economy','Transfer',{fromAccountId=q.wallet,toAccountId=q.sink,
            currency=q.currency,amount=q.amount,idempotencyKey='stables.pay:'..q.id,
            reasonCode='stables.horse_purchase',referenceType='stables_order',referenceId=q.id},
            {actorCharacterId=q.characterId,actorAccountId=q.accountId,correlationId=q.id})
        if not paid.ok then
            if paid.code=='insufficient_funds' then
                DB.exec("UPDATE fs_operations SET state='cancelled',revision=revision+1 WHERE operation_id=? AND state='payment_pending'",id)
                return paid
            end
            return F.Error('purchase_pending','Payment acknowledgement is pending; retry this purchase.')
        end
        local receipt=paid.value
        if type(receipt)~='table' or not F.IsUuid(receipt.transactionId) or receipt.amount~=q.amount
            or receipt.currency~=q.currency or receipt.fromAccountId~=q.wallet or receipt.toAccountId~=q.sink
            or receipt.referenceId~=q.id or receipt.referenceType~='stables_order'
            or receipt.sourceResource~='bcc-stables' or receipt.reasonCode~='stables.horse_purchase' then
            return F.Error('purchase_pending','Payment evidence requires recovery.')
        end
        if DB.exec("UPDATE fs_operations SET state='paid',payment_transaction_id=?,revision=revision+1 WHERE operation_id=? AND state='payment_pending'",receipt.transactionId,id)~=1 then
            return F.Error('purchase_pending','Payment receipt write requires recovery.')
        end
        row.state='paid'
    end
    if row.state~='paid' then return F.Error('purchase_reconciliation_required','Purchase cannot advance.') end
    local request=assetRequest(q)
    DB.exec([[INSERT IGNORE INTO fs_asset_registrations
        (operation_id,character_id,horse_id,request_id,model_key,fingerprint,request_json)
        VALUES (?,?,?,?,?,?,?)]],id,character,id,request.requestId,q.model,'checkout.v1:'..id,json.encode(request))
    local intent=DB.one('SELECT * FROM fs_asset_registrations WHERE operation_id=?',id)
    local decoded,savedRequest=pcall(json.decode,intent and intent.request_json or '')
    local function equal(a,b)
        if type(a)~=type(b) then return false end
        if type(a)~='table' then return a==b end
        for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
        for k in pairs(b) do if a[k]==nil then return false end end
        return true
    end
    if not intent or not decoded or not equal(savedRequest,request) or intent.character_id~=character then
        return F.Error('purchase_pending','Registration evidence requires recovery.')
    end
    DB.exec("UPDATE fs_asset_registrations SET state='submitted',revision=1 WHERE operation_id=? AND state='prepared'",id)
    local registered=F.Call('feather-assets','RegisterAsset',savedRequest)
    if not registered.ok then return F.Error('purchase_pending','Horse registration is pending; no new payment will be made.') end
    if type(registered.value)~='table' or not F.IsUuid(registered.value.assetId) then return F.Error('purchase_pending','Registration receipt unavailable.') end
    local fresh=F.Call('feather-assets','GetAsset',{assetId=registered.value.assetId})
    if not fresh.ok then return F.Error('purchase_pending','Canonical horse read is pending.') end
    local a=fresh.value
    if type(a)~='table' or not F.IsUuid(a.assetId) or not F.IsRevision(a.revision) or a.revision<1
        or a.assetType~='horse' or a.modelKey~=q.model or a.managerResource~='bcc-stables' or a.status~='active'
        or a.provenanceType~='stable_purchase' or a.provenanceId~=id or a.metadataVersion~=1
        or type(a.metadata)~='table' or a.metadata.stablesHorseId~=id or a.metadata.name~=q.name or a.metadata.gender~=q.gender
        or type(a.owner)~='table' or a.owner.holderType~='character' or a.owner.holderId~=character then
        return F.Error('purchase_pending','Canonical ownership evidence requires recovery.')
    end
    local committed=DB.transaction(function(tx)
        if not tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',character) then return false end
        local latest=read(id,character,tx); if not latest.ok then return false end
        if latest.value.state=='fulfilled' then return true end
        if latest.value.state~='paid' then return false end
        assert(tx.exec([[INSERT INTO fs_horses (horse_id,owner_character_id,origin_operation_id,catalog_id,catalog_revision)
            VALUES (?,?,?,?,1)]],id,character,id,q.model)==1)
        assert(tx.exec("UPDATE fs_asset_registrations SET state='linked',asset_id=?,asset_revision=?,revision=2 WHERE operation_id=? AND state='submitted'",a.assetId,a.revision,id)==1)
        local facts=json.encode({eventVersion=1,operationId=id,horseId=id,assetId=a.assetId,characterId=character,modelKey=q.model,catalogId=q.model})
        assert(tx.exec("INSERT INTO fs_horse_history (event_id,horse_id,operation_id,event_kind,facts_json) VALUES (?,?,?,'purchased',?)",id,id,id,facts)==1)
        assert(tx.exec([[INSERT INTO fs_outbox (event_id,operation_id,event_name,payload_json)
            VALUES (?,?,'stables.purchase.fulfilled.v1',?)]],'stables.fulfilled:'..id,id,facts)==1)
        assert(tx.exec('INSERT INTO fs_horse_condition (horse_id,health_core,stamina_core,policy_revision,revision) VALUES (?,100,100,1,0)',id)==1)
        assert(tx.exec("UPDATE fs_operations SET state='fulfilled',revision=revision+1 WHERE operation_id=? AND state='paid'",id)==1)
        local call=tx.one('SELECT generation_id FROM fs_call_slots WHERE character_id=? FOR UPDATE',character)
        local care=tx.one("SELECT operation_id FROM fs_care_operations WHERE character_id=? AND state NOT IN ('applied','cancelled') LIMIT 1 FOR UPDATE",character)
        if not call and not care then
            assert(tx.exec('UPDATE fs_character_stables SET selected_horse_id=?,revision=revision+1 WHERE character_id=?',id,character)==1)
        end
        return true
    end)
    if committed~=true then return F.Error('purchase_pending','Ownership projection is pending recovery.') end
    return view({terms=q,state='fulfilled'})
end
function P.Resume(id,character)
    if working[id] then return F.Error('purchase_pending','Purchase is already processing.') end
    working[id]=true
    local ok,result=pcall(resume,id,character)
    working[id]=nil
    return ok and result or F.Error('purchase_pending','Purchase acknowledgement is uncertain; retry the same purchase.')
end
function P.Confirm(session,site,p,authorize)
    local saved=read(p.operationId,session.characterId); if not saved.ok then return saved end
    local q=saved.value.terms
    if p.amount~=q.amount or p.currency~=q.currency then return F.Error('price_conflict','Confirm the exact quoted price.') end
    if saved.value.state~='reserved' then return P.Resume(q.id,q.characterId) end
    if not P.Enabled() then return F.Error('purchase_disabled','Purchasing is disabled.') end
    local cost=price(site,q.model,q.currency)
    if site~=q.site or not cost.ok or cost.value~=q.amount or os.time()>q.expiresAt then return F.Error('quote_expired','Refresh the purchase quote.') end
    if not authorize() then return F.Error('session_stale','Stable session changed.') end
    local failure='purchase_pending'
    local committed=DB.transaction(function(tx)
        tx.exec('INSERT IGNORE INTO fs_character_stables (character_id) VALUES (?)',q.characterId)
        tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',q.characterId)
        local row=read(q.id,q.characterId,tx); if not row.ok then return false end
        if row.value.state~='reserved' then return true end
        local count=tx.one([[SELECT
            (SELECT COUNT(*) FROM fs_horses WHERE owner_character_id=? AND biological_state='alive')+
            (SELECT COUNT(*) FROM fs_operations WHERE character_id=? AND state IN ('payment_pending','paid')) AS total]],q.characterId,q.characterId)
        local limit=tonumber(Config.horseLimits.player)
        local pending=tx.one("SELECT COUNT(*) AS total FROM fs_operations WHERE character_id=? AND state IN ('payment_pending','paid')",q.characterId)
        if not pending or tonumber(pending.total)~=0 then failure='purchase_pending';return false end
        if not count or not F.IsRevision(tonumber(count.total)) or not F.IsRevision(limit) or limit<1 or tonumber(count.total)>=limit then failure='horse_limit';return false end
        if not F.IsCurrent(session) or os.time()>q.expiresAt then failure='quote_expired';return false end
        return tx.exec("UPDATE fs_operations SET state='payment_pending',revision=revision+1 WHERE operation_id=? AND state='reserved'",q.id)==1
    end)
    if committed~=true then return F.Error(failure,'Purchase admission refused; no new payment requested.') end
    return P.Resume(q.id,q.characterId)
end
function P.Tick()
    if Stables.Tack then Stables.Tack.Tick() end
    -- Only confirmed new checkout intents; never submit unpaid quotes or adopt
    -- legacy/proof orders. Committed intent may complete while its buyer is offline.
    local rows=DB.query([[SELECT operation_id,character_id FROM fs_operations
        WHERE state IN ('payment_pending','paid') AND fingerprint LIKE 'checkout.v1:%'
        AND (next_attempt_at IS NULL OR next_attempt_at<=UTC_TIMESTAMP())
        ORDER BY updated_at,operation_id LIMIT 5]])
    for _,row in ipairs(rows or {}) do
        local result=P.Resume(row.operation_id,row.character_id)
        if not result.ok then DB.exec('UPDATE fs_operations SET next_attempt_at=DATE_ADD(UTC_TIMESTAMP(),INTERVAL 10 SECOND) WHERE operation_id=?',row.operation_id) end
    end
end

function P.Status()
    local ok,rows=pcall(DB.query,[[SELECT operation_id,character_id,state FROM fs_operations
        WHERE fingerprint LIKE 'checkout.v1:%' AND state IN ('payment_pending','paid')
        ORDER BY updated_at,operation_id LIMIT 10]])
    return {enabled=P.Enabled(),recoveryAvailable=ok,pending=ok and rows or nil}
end
function P.Start()
    CreateThread(function()
        while true do
            local ok=pcall(P.Tick)
            if not ok then print('[bcc-stables] purchase recovery paused; database unavailable.') end
            Wait(10000)
        end
    end)
end
