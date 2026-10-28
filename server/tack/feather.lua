-- Character-owned Inventory pieces; Stables authorizes purchases and horse slots.
-- Inventory owns its equipment slots too. Use only data-based provider methods;
-- never cross the CFX boundary with a transaction handle or query provider tables.
Stables.Tack={}
local T,F,R=Stables.Tack,Stables.Feather,Stables.OwnedRepository
local api,definitions,conditionKey,conditionMax
local held,working,permits,pendingHolds={},{},{},{}
local ready,pending=false,true
local collectionKey='stables.tack.v1'
local function itemPolicy(name)
    for slot,p in pairs(Tack.PieceSlots) do if p.itemName==name then return p,slot end end
end
local function bad(code) return F.Error(code or 'tack_pending','Tack action could not be confirmed; refresh before retrying.') end
local function integer(n,min) return F.IsRevision(n) and n>=(min or 0) end
local function callable(v) return type(v)=='function' or type(v)=='table' and type(rawget(v,'__cfx_functionReference'))=='string' end
function T.Enabled() return Config.tack and Config.tack.enabled==true end
local function provider(fn,...)
    local ok,v=pcall(fn,...)
    if not ok or type(v)~='table' or type(v.ok)~='boolean' then return bad() end
    if v.ok==false then return F.Error(v.code or v.error and v.error.code or 'tack_pending',
        v.message or v.error and v.error.message or 'Inventory action unavailable.') end
    return v
end
local function inventory(method,p)
    return provider(function() local e=exports['feather-inventory'];return e[method](e,p) end)
end
local function collection(character,adopt)
    return inventory('GetCharacterCollection',{characterId=character,collectionKey=collectionKey,adopt=adopt==true})
end
local function collectionItem(character,id)
    return inventory('GetCharacterCollectionItem',{characterId=character,collectionKey=collectionKey,instanceId=id})
end
local function collectionBatch(character,changes)
    return inventory('SetCharacterCollectionEquipment',{characterId=character,collectionKey=collectionKey,changes=changes})
end
local function capacity(character,itemName)
    local inv=collection(character);if not inv.ok then return inv end
    local accepted=provider(api.Inventory.InventoryCanHoldById,{{item=itemName,quantity=1}},inv.value.id)
    if not accepted.ok then return accepted end
    return accepted.value and accepted.value.accepted==true and F.Ok(true) or bad('tack_inventory_full')
end
local function order(id,character,tx)
    if not F.IsUuid(id) then return bad('invalid_input') end
    local rows=tx and tx.query('SELECT * FROM fs_tack_orders WHERE operation_id=? FOR UPDATE',{id})
    local row=tx and rows and rows[1] or not tx and DB.one('SELECT * FROM fs_tack_orders WHERE operation_id=?',id)
    if not row then return bad('tack_not_found') end
    local ok,q=pcall(json.decode,row.record_json)
    local slot=ok and type(q)=='table' and (q.kind=='saddle.v1' and 'saddle' or q.kind=='tack.v1' and q.slot)
    local policy=slot and Tack.PieceSlots[slot]
    local itemName=policy and (q.kind=='saddle.v1' and policy.itemName or q.itemName)
    if not ok or type(q)~='table' or not policy or itemName~=policy.itemName or q.id~=id or q.characterId~=row.character_id
        or character and q.characterId~=character or not F.IsUuid(q.characterId) or not F.IsUuid(q.accountId)
        or not F.IsUuid(q.wallet) or not F.IsUuid(q.sink) or not integer(q.amount) or q.amount>1000000000
        or q.collectionKey~=nil and q.collectionKey~=collectionKey
        or (q.currency~='dollars' and q.currency~='gold') or not integer(q.definitionId,1)
        or type(q.catalogId)~='string' or not q.catalogId:match('^'..slot..'_0x%x%x%x%x%x%x%x%x$')
        or type(q.conditionKey)~='string' or not integer(q.maximum,1) or not integer(q.expiresAt,1)
        or not ({reserved=true,payment_pending=true,paid=true,fulfilled=true,cancelled=true})[row.state] then return bad() end
    q.slot=slot;q.itemName=itemName
    row.terms=q;return F.Ok(row)
end
local function view(row)
    local q=row.terms
    return F.Ok({operationId=q.id,catalogId=q.catalogId,slot=q.slot,currency=q.currency,amount=q.amount,
        state=row.state,expiresAt=q.expiresAt,instanceId=tonumber(row.instance_id)})
end
local function price(site,id,currency)
    local location=StableLocations[site]
    local item=Tack.GetItem(id)
    if not location or location.shop.jobsEnabled or location.shop.hours.active or location.trainerBuy
        or not item or not Tack.PieceSlots[item.slot] then return bad('purchase_restricted') end
    local mode=item.currency
    if (currency~='dollars' and currency~='gold') or mode==1 and currency~='dollars' or mode==2 and currency~='gold' then return bad('invalid_currency') end
    local amount=mode==4 and 0 or (currency=='dollars' and item.cashPrice or item.goldPrice)*100
    if amount~=amount or amount<0 or amount>1000000000 then return bad('invalid_price') end
    local rounded=math.floor(amount+0.5)
    if math.abs(amount-rounded)>0.000001 or not integer(rounded) or rounded>1000000000 then return bad('invalid_price') end
    return F.Ok(rounded)
end
local function grant(q)
    return {grantId='stables.tack:'..q.id,characterId=q.characterId,definitionId=q.definitionId,itemName=q.itemName,collectionKey=q.collectionKey,
        metadata={stablesTackOrder=q.id,stablesTackCatalog=q.catalogId,[q.conditionKey]=q.maximum}}
end
local function equipment(character)
    local result=provider(api.GetEquippedForCharacter,character)
    if not result.ok then return result end
    local raw=result.value or {}
    -- Convert prior per-horse parts into saddle attachments without changing any
    -- instance or metadata. Include the parent slot in the provider CAS.
    local batches={}
    for _,category in ipairs({'stirrups','saddle_horn'}) do
        local prefix=Tack.PieceSlots[category].prefix
        for slot,id in pairs(raw) do
            local horse=type(slot)=='string' and slot:sub(#prefix+1)
            if type(slot)=='string' and slot:sub(1,#prefix)==prefix and F.IsUuid(horse) then
                local parent=raw[Tack.PieceSlots.saddle.prefix..horse]
                if not integer(parent,1) then return bad('tack_conflict') end
                local anchor=Tack.AssemblyPrefixes[category]..parent
                if raw[anchor] then return bad('tack_conflict') end
                local parentSlot=Tack.PieceSlots.saddle.prefix..horse
                if not batches[parentSlot] then batches[parentSlot]={{slot=parentSlot,expected=parent,instanceId=parent}} end
                local changes=batches[parentSlot]
                changes[#changes+1]={slot=slot,expected=id,instanceId=0}
                changes[#changes+1]={slot=anchor,expected=0,instanceId=id}
            end
        end
    end
    for _,changes in pairs(batches) do
        for _,c in ipairs(changes) do if c.expected>0 then permits[c.expected]=true end;if c.instanceId>0 then permits[c.instanceId]=true end end
        local migrated=collectionBatch(character,changes)
        for _,c in ipairs(changes) do permits[c.expected]=nil;permits[c.instanceId]=nil end
        if not migrated.ok then return migrated end
        result=provider(api.GetEquippedForCharacter,character);if not result.ok then return result end;raw=result.value or {}
    end
    local owned,parents={},{ }
    for slot,id in pairs(raw) do
        if slot=='tack_saddle_'..tostring(id) and integer(id,1) then owned[id]={slot='saddle',equipmentSlot=slot} end
        for _,category in ipairs({'saddle','saddlecloth'}) do
            local prefix=Tack.PieceSlots[category].prefix
            local horse=type(slot)=='string' and slot:sub(#prefix+1)
            if type(slot)=='string' and slot:sub(1,#prefix)==prefix and F.IsUuid(horse) and integer(id,1) then
                owned[id]={horseId=horse,slot=category,equipmentSlot=slot}
                if category=='saddle' then parents[id]=horse end
            end
        end
    end
    for slot,id in pairs(raw) do
        for category,prefix in pairs(Tack.AssemblyPrefixes) do
            local saddle=type(slot)=='string' and slot:match('^'..prefix..'(%d+)$')
            if saddle and integer(id,1) then
                owned[id]={horseId=parents[tonumber(saddle)],saddleId=tonumber(saddle),slot=category,equipmentSlot=slot}
            end
        end
    end
    for id,owner in pairs(held) do if owner==character then held[id]=nil end end
    for id in pairs(owned) do held[id]=character end
    if not working[character] then for id,owner in pairs(pendingHolds) do if owner==character then pendingHolds[id]=nil end end end
    return F.Ok(owned)
end
local function piece(item,q)
    local m=item and item.metadata
    local d=item and item.definition
    local catalog=type(m)=='table' and Tack.GetItem(m.stablesTackCatalog)
    local durability=m and m[conditionKey]
    return d and itemPolicy(d.name) and d.instanceMode=='unique' and d.type=='item_item'
        and catalog and Tack.PieceSlots[catalog.slot] and integer(durability,1) and durability<=conditionMax
        and q and q.state=='fulfilled' and tonumber(q.instance_id)==item.id
        and q.terms.catalogId==m.stablesTackCatalog and q.terms.id==m.stablesTackOrder
        and q.terms.slot==catalog.slot and q.terms.itemName==d.name
end
function T.Start()
    ready=false;definitions={}
    if not T.Enabled() then return F.Ok(true) end
    local available=F.Call('feather-inventory','AwaitReady',15000); if not available.ok then return available end
    local ok,value=pcall(function() return exports['feather-inventory']:initiate() end)
    if not ok or type(value)~='table' then return bad('inventory_unavailable') end
    api=value
    for _,fn in ipairs({api.MutateItem or false,api.GetEquippedForCharacter or false,api.GetCapabilities or false,
        api.Items and api.Items.GetDefinitions or false,api.Inventory and api.Inventory.GetInventoryItems or false,
        api.Inventory and api.Inventory.InventoryCanHoldById or false,
        api.Guards and api.Guards.RegisterMoveGuard or false,api.Guards and api.Guards.RegisterDestroyGuard or false,
        api.Guards and api.Guards.RegisterInstanceChangeGuard or false}) do if not callable(fn) then return bad('inventory_unavailable') end end
    local supported=provider(api.GetCapabilities)
    if not supported.ok or not supported.value.features or (supported.value.features.durableUniqueCharacterGrants~=true or supported.value.features.privateCharacterCollections~=true) then return bad('inventory_unavailable') end
    -- Validation precedes SQL in this public API: an empty request checks caller
    -- authorization without reserving a receipt or delivering an item.
    local trusted=inventory('GrantCharacterUniqueItemOnce',{})
    if trusted.ok or trusted.code~='invalid_input' then return bad('tack_grant_not_trusted') end
    local custody=inventory('GetCharacterCollection',{collectionKey=collectionKey})
    if custody.ok or custody.code~='invalid_input' then return bad('tack_collection_not_trusted') end
    local caps=exports['feather-inventory']:GetConsumptionContract()
    if type(caps)~='table' or caps.ready~=true or type(caps.conditionKey)~='string' or not integer(caps.conditionMaximum,1) then return bad('inventory_unavailable') end
    conditionKey,conditionMax=caps.conditionKey,caps.conditionMaximum
    local defs=provider(api.Items.GetDefinitions);if not defs.ok then return defs end
    for _,d in pairs(defs.value or {}) do if itemPolicy(d.name) then definitions[d.name]=d end end
    for _,policy in pairs(Tack.PieceSlots) do
        local d=definitions[policy.itemName]
        if not d or d.instance_mode~='unique' or d.type~='item_item' or tonumber(d.max_stack_size)~=1 then return bad('tack_schema_required') end
    end
    -- Fail startup before enabling calls if the optional installation is absent.
    DB.query('SELECT operation_id,character_id,state,record_json,payment_transaction_id,instance_id FROM fs_tack_orders LIMIT 0')
    local function guard(item)
        if item.definition and itemPolicy(item.definition.name) then
            local snapshot=item.equipmentSnapshot
            if not ready or held[item.id] or pendingHolds[item.id] or not snapshot or snapshot.equipped~=false then
                return false,'Unequip this tack before moving or destroying it.'
            end
        end
        return true
    end
    for _,method in ipairs({'RegisterMoveGuard','RegisterDestroyGuard'}) do
        local registered=provider(api.Guards[method],'bcc-stables:tack',guard);if not registered.ok then return registered end
    end
    local registered=provider(api.Guards.RegisterInstanceChangeGuard,'bcc-stables:tack',function(id,context)
        if context and context.operation=='collection_adoption' and context.resource==GetCurrentResourceName() then return true end
        if permits[id] and context and context.operation=='equipment_write' then return true end
        if held[id] or pendingHolds[id] then return false,'Unequip this tack before changing it.' end
        return true
    end);if not registered.ok then return registered end
    ready=true;return F.Ok(true)
end
function T.Shop(session,horseId)
    if not T.Enabled() then return F.Ok({available=false,owned={},loadout={}}) end
    if not ready then return bad('inventory_unavailable') end
    local owned=R.ReadOwned(session,horseId);if not owned.ok then return owned end
    if owned.value.availability~='stored' then return bad('horse_busy') end
    local inv=collection(session.characterId,true);if not inv.ok then return inv end
    local listed=provider(api.Inventory.GetInventoryItems,inv.value.id);if not listed.ok then return listed end
    local ids,params,byId={},{},{}
    for _,i in ipairs(listed.value or {}) do if itemPolicy(i.name) and integer(tonumber(i.id),1) then
        ids[#ids+1]='?';params[#params+1]=tonumber(i.id);byId[tonumber(i.id)]=i
    end end
    if #ids>500 then return bad('tack_limit') end
    local result={available=true,storage='stable',purchases=Stables.Checkout.Enabled(),owned={},loadout={},conditionMaximum=conditionMax}
    local assignments=equipment(session.characterId);if not assignments.ok then return assignments end
    local equipped=assignments.value
    for id,assignment in pairs(equipped) do if assignment.horseId==horseId then result.loadout[assignment.slot]=id end end
    if #ids>0 then
        local rows=DB.query("SELECT operation_id,instance_id,record_json FROM fs_tack_orders WHERE state='fulfilled' AND instance_id IN ("..table.concat(ids,',')..')',table.unpack(params))
        for _,row in ipairs(rows) do
            local i=byId[tonumber(row.instance_id)]
            local m=i.metadata
            local catalog=type(m)=='table' and Tack.GetItem(m.stablesTackCatalog)
            local decoded,q=pcall(json.decode,row.record_json)
            if catalog and Tack.PieceSlots[catalog.slot] and decoded and type(q)=='table' and q.catalogId==catalog.id
                and itemPolicy(i.name)==Tack.PieceSlots[catalog.slot] and m.stablesTackOrder==row.operation_id
                and integer(m[conditionKey],1) and m[conditionKey]<=conditionMax then
                result.owned[#result.owned+1]={instanceId=tonumber(i.id),revision=tonumber(i.row_revision),catalogId=catalog.id,
                    condition=m[conditionKey],slot=catalog.slot,horseId=equipped[tonumber(i.id)] and equipped[tonumber(i.id)].horseId,
                    saddleId=equipped[tonumber(i.id)] and equipped[tonumber(i.id)].saddleId}
            end
        end
    end
    table.sort(result.owned,function(a,b) return a.instanceId<b.instanceId end)
    if not F.IsCurrent(session) then return bad('session_stale') end
    return F.Ok(result)
end
function T.Loadout(session,horseId)
    if not T.Enabled() then return F.Ok({}) end
    if not ready then return bad('inventory_unavailable') end
    local custody=collection(session.characterId,true);if not custody.ok then return custody end
    local assignments=equipment(session.characterId);if not assignments.ok then return assignments end
    local result={}
    for id,assignment in pairs(assignments.value) do if assignment.horseId==horseId then
        local item=collectionItem(session.characterId,id)
        if not item.ok then return bad('tack_item_unavailable') end
        local q=order(item.value.metadata and item.value.metadata.stablesTackOrder)
        if not q.ok or not piece(item.value,q.value) then return bad('tack_item_unavailable') end
        if q.value.terms.slot~=assignment.slot then return bad('tack_item_unavailable') end
        result[assignment.slot]={catalogId=q.value.terms.catalogId,instanceId=id,condition=item.value.metadata[conditionKey]}
    end end
    for slot in pairs(result) do if Tack.PieceSlots[slot].requiresSaddle and not result.saddle then return bad('tack_saddle_required') end end
    return F.IsCurrent(session) and F.Ok(result) or bad('session_stale')
end
function T.Equip(session,p,authorize)
    if not ready or not T.Enabled() then return bad('tack_disabled') end
    local slot=p.slot or 'saddle'
    local policy=Tack.PieceSlots[slot];if not policy then return bad('invalid_input') end
    if not integer(p.instanceId) or not integer(p.expectedInstanceId) or not integer(p.itemRevision)
        or p.fromHorseId~=nil and not F.IsUuid(p.fromHorseId) or not F.IsUuid(p.horseId) then return bad('invalid_input') end
    if working[session.characterId] then return bad('tack_pending') end
    working[session.characterId]=true
    local ok,result=pcall(function()
        local owned=R.ReadOwned(session,p.horseId);if not owned.ok then return owned end
        if owned.value.availability~='stored' then return bad('horse_busy') end
        if p.fromHorseId and p.fromHorseId~=p.horseId then
            local source=R.ReadOwned(session,p.fromHorseId);if not source.ok then return source end
            if source.value.availability~='stored' then return bad('horse_busy') end
        end
        local custody=collection(session.characterId,true);if not custody.ok then return custody end
        local assignments=equipment(session.characterId);if not assignments.ok then return assignments end
        local current,source=0,nil
        local hasSaddle=false;local targetSaddle
        local targetSlot=policy.prefix..p.horseId
        for id,assignment in pairs(assignments.value) do
            if assignment.horseId==p.horseId and assignment.slot==slot then current=id end
            if assignment.horseId==p.horseId and assignment.slot=='saddle' then hasSaddle=true;targetSaddle=id end
            if id==p.instanceId then
                if assignment.slot~=slot then return bad('tack_conflict') end
                if policy.requiresSaddle and assignment.saddleId~=p.fromSaddleId then return bad('tack_conflict') end
                source=assignment.horseId
            end
        end
        local desired=p.instanceId
        if p.detach then
            local attachment=assignments.value[p.instanceId]
            if not policy.requiresSaddle or not attachment or not attachment.saddleId then return bad('tack_conflict') end
            targetSlot=attachment.equipmentSlot;current=p.instanceId;desired=0
        end
        if policy.requiresSaddle and not p.detach and not hasSaddle then return bad('tack_saddle_required') end
        if policy.requiresSaddle and not p.detach then targetSlot=Tack.AssemblyPrefixes[slot]..targetSaddle end
        if current~=p.expectedInstanceId and current~=p.instanceId then return bad('tack_conflict') end
        if source~=p.fromHorseId and source~=p.horseId then return bad('tack_conflict') end
        if p.instanceId>0 then
            local item=collectionItem(session.characterId,p.instanceId)
            if not item.ok then return bad('tack_item_unavailable') end
            local q=order(item.value.metadata and item.value.metadata.stablesTackOrder)
            if not q.ok or not piece(item.value,q.value) or q.value.terms.slot~=slot or item.value.revision~=p.itemRevision then return bad('tack_item_unavailable') end
            pendingHolds[p.instanceId]=session.characterId
            -- Data-only read fence locks the Inventory row and checks its revision.
            -- Pending guards prevent later moves/metadata writes until assignment.
            local fenced=provider(api.MutateItem,{resource='bcc-stables',reason='stables_tack_fence'},
                {itemInstanceId=p.instanceId,expectedRevision=p.itemRevision})
            if not fenced.ok then return fenced end
            if tonumber(custody.value.id)~=fenced.value.inventoryId then return bad('tack_item_unavailable') end
        end
        local outcome=bad()
        -- This read-only Stables transaction holds the same character admission
        -- lock as call/store. The only write is Inventory's own atomic assignment.
        -- An uncertain commit is recovered by reading that assignment, not replaying
        -- a new purchase or attempting a compensating item/currency mutation.
        local committed=DB.transaction(function(tx)
            if not tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',session.characterId)
                or not authorize() or not F.IsCurrent(session) then outcome=bad('session_stale');return false end
            if tx.one('SELECT generation_id FROM fs_call_slots WHERE character_id=? FOR UPDATE',session.characterId)
                or tx.one("SELECT operation_id FROM fs_care_operations WHERE character_id=? AND state NOT IN ('applied','cancelled') LIMIT 1 FOR UPDATE",session.characterId) then
                outcome=bad('horse_busy');return false
            end
            for _,id in ipairs({p.horseId,p.fromHorseId}) do
                local h=tx.one('SELECT owner_character_id,availability,biological_state FROM fs_horses WHERE horse_id=? FOR UPDATE',id)
                if not h or h.owner_character_id~=session.characterId or h.availability~='stored' or h.biological_state~='alive' then outcome=bad('horse_busy');return false end
            end
            local changes,bySlot={},{ }
            local function change(key,expected,id)
                if bySlot[key] then bySlot[key].instanceId=id;return end
                local c={slot=key,expected=expected,instanceId=id};bySlot[key]=c;changes[#changes+1]=c
            end
            local selected=assignments.value[p.instanceId]
            if desired>0 and selected and selected.equipmentSlot~=targetSlot then change(selected.equipmentSlot,p.instanceId,0) end
            change(targetSlot,current,desired)
            if slot=='saddle' and current>0 and current~=desired then
                change('tack_saddle_'..current,0,current)
            end
            for _,c in ipairs(changes) do if c.expected>0 then permits[c.expected]=true end;if c.instanceId>0 then permits[c.instanceId]=true end end
            outcome=collectionBatch(session.characterId,changes)
            for _,c in ipairs(changes) do permits[c.expected]=nil;permits[c.instanceId]=nil end
            return outcome.ok
        end)
        if committed~=true then return outcome.ok and bad() or outcome end
        return outcome
    end)
    permits[p.instanceId]=nil;permits[p.expectedInstanceId]=nil
    local refreshed=provider(equipment,session.characterId)
    if refreshed.ok then pendingHolds[p.instanceId]=nil end
    working[session.characterId]=nil
    if not refreshed.ok then return bad() end
    if not ok then return bad() end
    if not result.ok then return result end
    return T.Shop(session,p.horseId)
end

function T.Quote(session,site,p,authorize)
    if not ready or not T.Enabled() or not Stables.Checkout.Enabled() then return bad('purchase_disabled') end
    local cost=price(site,p.catalogId,p.currency);if not cost.ok then return cost end
    local fits=capacity(session.characterId,Tack.PieceSlots[Tack.GetItem(p.catalogId).slot].itemName);if not fits.ok then return fits end
    local accounts=F.Call('feather-economy','FindAccountsByOwner',{ownerType='character',ownerId=session.characterId})
    if not accounts.ok then return accounts end
    local wallet
    for _,a in ipairs(accounts.value or {}) do if a.accountType=='wallet' and a.currency==p.currency and a.status=='open'
        and a.ownerType=='character' and a.ownerId==session.characterId then if wallet then return bad('ambiguous_wallet') end;wallet=a.accountId end end
    local sink=F.Call('feather-economy','GetSystemAccount',{currency=p.currency,accountType='system_sink'})
    if not sink.ok then return sink end
    if not F.IsUuid(wallet) or not sink.value or not F.IsUuid(sink.value.accountId) or sink.value.currency~=p.currency or sink.value.accountType~='system_sink' or sink.value.status~='open' then return bad('account_not_found') end
    if not authorize() or not F.IsCurrent(session) then return bad('session_stale') end
    if DB.one("SELECT operation_id FROM fs_tack_orders WHERE character_id=? AND state IN ('payment_pending','paid') LIMIT 1",session.characterId) then return bad('tack_pending') end
    local uuid=DB.one('SELECT UUID() AS id');if not uuid or not F.IsUuid(uuid.id) then return bad() end
    local slot=Tack.GetItem(p.catalogId).slot;local itemName=Tack.PieceSlots[slot].itemName
    local q={kind='tack.v1',slot=slot,itemName=itemName,collectionKey=collectionKey,id=uuid.id,characterId=session.characterId,accountId=session.accountId,site=site,
        catalogId=p.catalogId,currency=p.currency,amount=cost.value,wallet=wallet,sink=sink.value.accountId,
        definitionId=tonumber(definitions[itemName].id),conditionKey=conditionKey,maximum=conditionMax,expiresAt=os.time()+60}
    assert(DB.exec("INSERT INTO fs_tack_orders (operation_id,character_id,state,record_json) VALUES (?,?,'reserved',?)",q.id,q.characterId,json.encode(q))==1)
    return view({terms=q,state='reserved'})
end
function T.Resume(id,character)
    if not ready or working[id] then return bad() end
    working[id]=true
    local ok,result=pcall(function()
        local saved=order(id,character);if not saved.ok then return saved end
        local row,q=saved.value,saved.value.terms
        if row.state=='reserved' or row.state=='fulfilled' or row.state=='cancelled' then return view(row) end
        if row.state=='payment_pending' then
            local payment
            if q.amount>0 then
                local paid=F.Call('feather-economy','Transfer',{fromAccountId=q.wallet,toAccountId=q.sink,currency=q.currency,amount=q.amount,
                    idempotencyKey='stables.tack.pay:'..q.id,reasonCode='stables.tack_purchase',referenceType='stables_order',referenceId=q.id},
                    {actorCharacterId=q.characterId,actorAccountId=q.accountId,correlationId=q.id})
                if not paid.ok then
                    if paid.code=='insufficient_funds' then DB.exec("UPDATE fs_tack_orders SET state='cancelled' WHERE operation_id=? AND state='payment_pending'",id);return paid end
                    return bad()
                end
                local r=paid.value
                if type(r)~='table' or not F.IsUuid(r.transactionId) or r.amount~=q.amount or r.currency~=q.currency
                    or r.fromAccountId~=q.wallet or r.toAccountId~=q.sink or r.referenceId~=q.id or r.referenceType~='stables_order'
                    or r.sourceResource~='bcc-stables' or r.reasonCode~='stables.tack_purchase' then return bad() end
                payment=r.transactionId
            end
            DB.exec("UPDATE fs_tack_orders SET state='paid',payment_transaction_id=? WHERE operation_id=? AND state='payment_pending'",payment,id)
            saved=order(id,character);if not saved.ok or saved.value.state~='paid' then return bad() end
        end
        local delivered=inventory('GrantCharacterUniqueItemOnce',grant(q))
        if not delivered.ok then return bad() end
        local r=delivered.value
        if type(r)~='table' or r.grantId~='stables.tack:'..id or r.characterId~=q.characterId or r.definitionId~=q.definitionId
            or r.itemName~=q.itemName or r.delivered~=true or r.cancelled~=false or not integer(r.instanceId,1) or not integer(r.revision) then return bad() end
        -- Old pending orders keep their original grant payload/receipt; adopt
        -- that historical carried delivery instead of issuing a replacement.
        local custody=collection(q.characterId,true);if not custody.ok then return custody end
        DB.exec("UPDATE fs_tack_orders SET state='fulfilled',instance_id=? WHERE operation_id=? AND state='paid'",r.instanceId,id)
        return view(assert(order(id,character).value))
    end)
    working[id]=nil
    return ok and result or bad()
end
function T.Confirm(session,site,p,authorize)
    local saved=order(p.operationId,session.characterId);if not saved.ok then return saved end
    local row,q=saved.value,saved.value.terms
    if q.amount~=p.amount or q.currency~=p.currency then return bad('price_conflict') end
    if row.state~='reserved' then return T.Resume(q.id,q.characterId) end
    if not ready or not T.Enabled() or not Stables.Checkout.Enabled() then return bad('purchase_disabled') end
    local cost=price(site,q.catalogId,q.currency)
    if q.site~=site or not cost.ok or cost.value~=q.amount or os.time()>q.expiresAt then return bad('quote_expired') end
    local fits=capacity(session.characterId,q.itemName);if not fits.ok then return fits end
    local committed=DB.transaction(function(tx)
        if not tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',q.characterId)
            or not authorize() or not F.IsCurrent(session) or os.time()>q.expiresAt then return false end
        local latest=order(q.id,q.characterId,{query=function(sql,params) local r=tx.one(sql,table.unpack(params));return r and {r} or {} end})
        if not latest.ok then return false end
        if latest.value.state~='reserved' then return true end
        if tx.one("SELECT operation_id FROM fs_tack_orders WHERE character_id=? AND state IN ('payment_pending','paid') LIMIT 1 FOR UPDATE",q.characterId) then return false end
        return tx.exec("UPDATE fs_tack_orders SET state='payment_pending' WHERE operation_id=? AND state='reserved'",q.id)==1
    end)
    if committed~=true then return bad() end
    pending=true;return T.Resume(q.id,q.characterId)
end
function T.Tick()
    if not ready or not pending then return end
    pending=false
    local ok,rows=pcall(DB.query,"SELECT operation_id,character_id FROM fs_tack_orders WHERE state IN ('payment_pending','paid') ORDER BY updated_at,operation_id LIMIT 5")
    if not ok or type(rows)~='table' then pending=true;return end
    pending=pending or #rows>0
    for _,row in ipairs(rows) do
        local result=T.Resume(row.operation_id,row.character_id)
        if not result.ok then DB.exec('UPDATE fs_tack_orders SET updated_at=UTC_TIMESTAMP() WHERE operation_id=?',row.operation_id) end
    end
end
function T.Status()
    if not T.Enabled() then return {enabled=false,ready=false,pending={}} end
    local ok,rows=pcall(DB.query,"SELECT operation_id,character_id,state FROM fs_tack_orders WHERE state IN ('payment_pending','paid') ORDER BY updated_at,operation_id LIMIT 10")
    return {enabled=true,ready=ready,storage='stable_collection',recoveryAvailable=ok,pending=ok and rows or nil}
end
AddEventHandler('onResourceStop',function(resource)
    if resource=='feather-inventory' then ready=false end
    if resource==GetCurrentResourceName() and api and api.Guards then
        ready=false
        for _,method in ipairs({'UnregisterMoveGuard','UnregisterDestroyGuard','UnregisterInstanceChangeGuard'}) do
            pcall(api.Guards[method],'bcc-stables:tack')
        end
    end
end)
