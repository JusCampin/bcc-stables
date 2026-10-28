Stables.StableUI = {}
local U, C, P = Stables.StableUI, Stables.Client, Stables.Preview
local Menu = exports['feather-menu-v2']
local state, opening = nil, false
local entryPrompt
local render, renderDetails, renderRename, renderCatalog, restoreRoster, showCatalogCoat, renderCheckout, renderTack, openTack
local function yes(v) return v == true or v == 1 end

local function requireValue(result)
    if type(result) ~= 'table' or not result.ok then error(type(result) == 'table' and result.code or 'menu_unavailable',
            0) end
    return result.value
end

local function current(token) return state ~= nil and state.token == token end

local function name(row)
    if type(row.name) == 'string' and row.name ~= '' then return row.name end
    local mapping = Horses.ModelToBreedMap[row.modelKey]
    local breed = mapping and Horses.BreedCatalog[mapping.breed]
    local coat = breed and breed.colors[row.modelKey]
    return mapping and (mapping.breed .. (coat and (' - ' .. coat.color) or '')) or row.modelKey
end

local function clear(s, immediate)
    if state ~= s then return end
    state = nil; P.Clear(not immediate)
    if s.menuId then Menu:DestroyMenu(s.menuId) end
end

local function close(s, callHorse)
    if state ~= s then return end
    if s.busy then
        s.closeRequested = true; return
    end
    s.busy = true
    P.Clear(true)
    if s.menuId then Menu:CloseMenu(s.menuId) end
    CreateThread(function()
        local reply = C.Rpc('menu_close', { token = s.token })
        if not reply.ok then
            clear(s); C.Message(C.Text('menu_unavailable', reply.code)); return
        end
        clear(s)
        if callHorse and PlayerPedId() == s.ped and not yes(IsPedDeadOrDying(s.ped, true)) then Stables.Horse.Call() end
    end)
end

local function request(s, action, p, done, failed)
    if state ~= s or s.busy then return end
    s.busy = true; p = p or {}; p.token = s.token
    CreateThread(function()
        local reply = C.Rpc('menu_' .. action, p)
        s.busy = false
        if state ~= s then return end
        if s.closeRequested then
            close(s); return
        end
        if reply.ok then
            local ok, failure = pcall(done, reply.value)
            if not ok then
                C.Message(C.Text('menu_unavailable', tostring(failure))); close(s)
            end
        elseif failed then
            failed(reply)
        else
            C.Message(C.Text('menu_unavailable', reply.code))
        end
    end)
end

local function preview(s, row)
    if P.IsShowing(s.token, s.site, row.horseId, row.modelKey) then P.SetGender(row.gender);return end
    request(s, 'preview', { horseId = row.horseId }, function(value)
        if state ~= s then return end
        P.Show(s.token, s.site, value.modelKey, current, value.horseId, value.gender, value.tack)
    end)
end

local function page(s, key)
    if key ~= 'tack' and s.tack then
        if s.tack.horse then P.RestoreTack(s.token, s.site, s.tack.horse.horseId) end
        s.tack = nil
    end
    local old = s.pageId
    s.tab = key == 'tack' and 'tack' or (key == 'catalog' or key == 'checkout') and 'catalog' or 'roster'
    s.pageSequence = (s.pageSequence or 0) + 1
    local id = requireValue(Menu:CreatePage(s.menuId, { key = key .. '-' .. s.pageSequence })).pageId
    local function add(kind, key, spec, callback)
        spec.key = key; return requireValue(Menu:AddElement(s.menuId, id, kind, spec, callback)).elementId
    end
    return id, old, add
end

local function activate(s, id, old)
    -- Three stable navigation targets plus one replaceable active page. Controlled
    -- tabs keep preview changes inside this menu session without opening a route.
    local rosterId = s.tab == 'roster' and id or s.tabAnchors.roster
    local catalogId = s.tab == 'catalog' and id or s.tabAnchors.catalog
    local tackId = s.tab == 'tack' and id or s.tabAnchors.tack
    requireValue(Menu:ConfigureNavigation(s.menuId, { type = 'tabs', controlled = true, pages = {
        { pageId = rosterId, label = C.Text('menu_title') },
        { pageId = catalogId, label = C.Text('menu_browseCatalog') },
        { pageId = tackId, label = C.Text('menu_tack') },
    } }, function(event)
        if state ~= s or s.busy then return end
        P.StopRotation()
        if event.toPageId == rosterId and s.tab ~= 'roster' then
            restoreRoster(s)
        elseif event.toPageId == catalogId and s.tab ~= 'catalog' then
            local saved = s.catalogSelection
            if saved and saved.breed and saved.model then showCatalogCoat(s, saved.breed, saved.model)
            else renderCatalog(s) end
        elseif event.toPageId == tackId and s.tab ~= 'tack' then
            openTack(s)
        end
    end))
    requireValue(Menu:NavigateToPage(s.menuId, id))
    s.pageId = id
    if old then requireValue(Menu:DestroyPage(s.menuId, old, id)) end
end

local function rotation(add)
    add('button', 'left', { label = C.Text('menu_rotateLeft'), slot = 'footer', row = 'rotation' }, function() P.Rotate(-1) end)
    add('button', 'right', { label = C.Text('menu_rotateRight'), slot = 'footer', row = 'rotation' }, function() P.Rotate(1) end)
end

local function baseStats(add, coat, expanded)
    if not coat or type(coat.stats) ~= 'table' then return end
    add('accordion', 'stats-title', { label = C.Text('menu_baseStats'), value = expanded == true })
    for _, key in ipairs({ 'speed', 'acceleration', 'handling', 'health', 'stamina' }) do
        local value = tonumber(coat.stats[key])
        add('textdisplay', 'stat-' .. key, { section = 'stats-title',
            value = C.Text('menu_' .. key) .. ': ' .. (value and ('%d/10'):format(value + 1) or C.Text('menu_unknown')) })
    end
end

local function catalogCoats(breed)
    local coats = {}
    for model, coat in pairs(breed and breed.colors or {}) do
        coats[#coats + 1] = { value = model, label = coat.color or model }
    end
    table.sort(coats, function(a, b)
        local left, right = a.label:lower(), b.label:lower()
        return left == right and a.value < b.value or left < right
    end)
    return coats
end

local function catalogPrice(coat)
    local function amount(value, key)
        value = tonumber(value)
        return value and value >= 0 and value < math.huge and C.Text(key, value) or C.Text('menu_unknown')
    end
    local currency = tonumber(coat.currency) or 3
    if currency == 4 then return C.Text('menu_free') end
    if currency == 1 then return amount(coat.cashPrice, 'menu_cashPrice') end
    if currency == 2 then return amount(coat.goldPrice, 'menu_goldPrice') end
    if currency == 3 then return C.Text('menu_priceChoice', amount(coat.cashPrice, 'menu_cashPrice'), amount(coat.goldPrice, 'menu_goldPrice')) end
    return C.Text('menu_unknown')
end

local function tackLabel(item)
    local policy=Tack.PieceSlots[item.slot]
    local number = item.label:match(policy.pattern)
    return number and C.Text('menu_'..policy.numberKey, tonumber(number)) or item.label
end
local function tackError(reply)
    local keys = {insufficient_funds='purchaseFunds',quote_expired='purchaseExpired',price_conflict='purchaseExpired',
        purchase_disabled='purchaseDisabled',purchase_restricted='purchaseRestricted',
        collection_full='tackInventoryFull',tack_saddle_required='tackSaddleRequired',tack_dependents_equipped='tackDependents',tack_conflict='tackConflict',tack_item_unavailable='tackConflict',horse_busy='tackConflict',tack_inventory_full='tackInventoryFull'}
    return C.Text('menu_' .. (keys[reply.code] or 'tackPending'))
end
local function previewTackPiece(s,form,piece,catalogId)
    if form.slot=='saddle' then
        local parts={}
        for _,item in ipairs(form.shop.owned or {}) do
            if piece and item.saddleId==piece.instanceId then parts[item.slot]={catalogId=item.catalogId} end
        end
        return P.SetAssembly(s.token,s.site,form.horse.horseId,catalogId,parts)
    end
    return P.SetTack(s.token,s.site,form.horse.horseId,form.slot,catalogId)
end
local function acceptTackShop(s, form, shop, preferred)
    form.shop = shop;form.slot=form.slot or 'saddle'
    form.instanceId = preferred or shop.loadout and shop.loadout[form.slot] or 0
    form.piece = nil;form.catalogId = nil
    local saved={}
    for _, item in ipairs(shop.owned or {}) do
        local slot=Tack.GetItem(item.catalogId).slot
        if shop.loadout and item.instanceId == shop.loadout[slot] then saved[slot]={catalogId=item.catalogId} end
        if slot==form.slot and item.instanceId == form.instanceId then form.piece = item;form.catalogId = item.catalogId end
    end
    P.SetSavedTack(s.token, s.site, form.horse.horseId, saved)
    if form.quote then form.catalogId=form.quote.catalogId end
    if form.piece or form.quote then previewTackPiece(s,form,form.piece,form.catalogId) end
end
renderTack = function(s, form)
    if state ~= s then return end
    if not P.CanPreviewTack() then C.Message(C.Text('menu_tackUnavailable')); return end
    s.tack = form; s.detail = nil; s.renameForm = nil; s.catalog = nil; s.checkout = nil
    local id, old, add = page(s, 'tack')
    add('header', 'title', { value = C.Text('menu_tack'), slot = 'header' })
    if not form.horse then
        add('textdisplay', 'tack-empty', { value = C.Text('menu_tackSelectHorse') })
        add('button', 'close', { label = C.Text('menu_close'), slot = 'footer' }, function() close(s) end)
        activate(s, id, old); return
    end
    local shop = form.shop or {available=false,owned={},loadout={}}
    add('subheader', 'horse', { value = name(form.horse), slot = 'header' })
    form.slot=form.slot or 'saddle'
    local slot=form.slot
    local policy=Tack.PieceSlots[slot]
    local categories={}
    for _,category in ipairs(Tack.PieceOrder) do categories[#categories+1]={value=category,label=C.Text('menu_'..Tack.PieceSlots[category].labelKey)} end
    add('arrows','tack-category',{label=C.Text('menu_tackCategory'),value=slot,options=categories,disabled=form.quote~=nil},function(event)
        if s.busy or form.quote or s.tack~=form or not Tack.PieceSlots[event.value] then return end
        form.slot=event.value;form.error=nil;acceptTackShop(s,form,shop);renderTack(s,form)
    end)
    if policy.requiresSaddle and not shop.loadout.saddle then
        add('textdisplay','tack-parent-notice',{value=C.Text('menu_tackSaddleRequired')})
    end
    if shop.available then
        if shop.storage=='stable' then add('textdisplay','tack-storage',{value=C.Text('menu_tackStorage')}) end
        add('arrows', 'tack-view', {label=C.Text('menu_tackCollection'),value=form.mode or 'catalog',disabled=form.quote~=nil,
            options={{value='owned',label=C.Text('menu_tackOwned_'..slot)},{value='catalog',label=C.Text('menu_tackBrowse_'..slot)}}},function(event)
            if s.busy or form.quote or s.tack~=form then return end
            if event.value~='owned' and event.value~='catalog' then return end
            form.mode=event.value;acceptTackShop(s,form,shop);renderTack(s,form)
        end)
    end
    if shop.available and form.mode=='owned' then
        local options={{value='none',label=C.Text('menu_'..policy.emptyKey)}}
        for _, owned in ipairs(shop.owned) do if Tack.GetItem(owned.catalogId).slot==slot then
            local label=C.Text('menu_tackOwnedPiece',tackLabel(Tack.GetItem(owned.catalogId)),owned.instanceId)
            options[#options+1]={value=tostring(owned.instanceId),label=label}
        end end
        add('arrows','tack-owned',{label=C.Text('menu_'..policy.labelKey),value=form.piece and tostring(form.piece.instanceId) or 'none',options=options},function(event)
            if s.busy or s.tack~=form then return end
            local chosen
            for _, item in ipairs(shop.owned) do if tostring(item.instanceId)==event.value and Tack.GetItem(item.catalogId).slot==slot then chosen=item;break end end
            if event.value~='none' and not chosen then return end
            local applied=previewTackPiece(s,form,chosen,chosen and chosen.catalogId)
            form.error=not applied and policy.requiresSaddle and 'tack_saddle_required' or nil
            form.piece=chosen;form.instanceId=chosen and chosen.instanceId or 0;form.catalogId=chosen and chosen.catalogId
            renderTack(s,form)
        end)
        if form.piece then
            add('textdisplay','tack-condition',{value=C.Text('menu_tackCondition',form.piece.condition,shop.conditionMaximum or 100)})
            if form.piece.saddleId then add('textdisplay','tack-assembly',{value=C.Text('menu_tackAttached',form.piece.saddleId)}) end
            if form.piece.horseId then add('textdisplay','tack-equipped',{value=C.Text(form.piece.horseId==form.horse.horseId and 'menu_tackHere' or 'menu_tackElsewhere')}) end
        end
        if form.piece and form.piece.saddleId then
            add('button','tack-detach',{label=C.Text('menu_tackDetach'),slot='footer'},function()
                local selected=form.piece
                request(s,'tack_equip',{horseId=form.horse.horseId,slot=slot,instanceId=selected.instanceId,
                    expectedInstanceId=selected.instanceId,itemRevision=selected.revision,fromHorseId=selected.horseId,fromSaddleId=selected.saddleId,detach=true},function(value)
                    form.error=nil;acceptTackShop(s,form,value,selected.instanceId);renderTack(s,form)
                end,function(reply) form.error=reply.code;renderTack(s,form) end)
            end)
        end
        if slot=='saddle' then add('textdisplay','tack-assembly-help',{value=C.Text('menu_tackAssemblyHelp')}) end
        add('button','tack-equip',{label=C.Text((form.piece and 'menu_tackEquip_' or 'menu_tackUnequip_')..slot),slot='footer',
            disabled=(form.piece and (form.piece.instanceId==(shop.loadout[slot] or 0) or policy.requiresSaddle and not shop.loadout.saddle)) or (not form.piece and not shop.loadout[slot]),
            confirm=form.piece and form.piece.horseId and form.piece.horseId~=form.horse.horseId and
                {title=C.Text('menu_tackEquip_'..slot),message=C.Text('menu_tackMoveSummary',name(form.horse)),confirmLabel=C.Text('menu_tackEquip_'..slot),cancelLabel=C.Text('menu_cancel')} or nil},function()
            local selected=form.piece
            request(s,'tack_equip',{horseId=form.horse.horseId,slot=slot,instanceId=selected and selected.instanceId or 0,
                expectedInstanceId=shop.loadout[slot] or 0,itemRevision=selected and selected.revision or 0,
                fromHorseId=selected and selected.horseId,fromSaddleId=selected and selected.saddleId},function(value)
                form.error=nil;acceptTackShop(s,form,value);renderTack(s,form);C.Message(C.Text('menu_tackEquipped'))
            end,function(reply) form.error=reply.code;renderTack(s,form) end)
        end)
    else
        local options={{value='none',label=C.Text('menu_'..policy.emptyKey)}}
        local position=1
        for index,item in ipairs(Tack.CatalogBySlot[slot]) do
            options[#options+1]={value=item.id,label=tackLabel(item)}
            if form.catalogId==item.id then position=index+1 end
        end
        add('arrows','tack-saddle',{label=C.Text('menu_'..policy.labelKey),value=form.catalogId or 'none',options=options,disabled=form.quote~=nil},function(event)
            if state~=s or s.busy or form.quote or s.tack~=form then return end
            local item=Tack.GetItem(event.value)
            if event.value~='none' and (not item or item.slot~=slot) then return end
            local chosen=item and item.id or nil
            if chosen==form.catalogId then return end
            local applied=previewTackPiece(s,form,nil,chosen)
            form.catalogId=chosen;form.error=not applied and policy.requiresSaddle and 'tack_saddle_required' or nil;renderTack(s,form)
        end)
        add('textdisplay','tack-position',{value=C.Text('menu_coatPosition',position,#options)})
        local item=Tack.GetItem(form.catalogId)
        if item then
            add('textdisplay','tack-price',{value=C.Text('menu_catalogPrice')..': '..catalogPrice(item)})
            if shop.available and shop.purchases then
                local currencies={}
                if item.currency~=2 then currencies[#currencies+1]={value='dollars',label=C.Text('menu_cash')} end
                if item.currency~=1 then currencies[#currencies+1]={value='gold',label=C.Text('menu_gold')} end
                if not form.quote and (not form.currency or item.currency==1 and form.currency~='dollars' or item.currency==2 and form.currency~='gold') then form.currency=currencies[1].value end
                add('arrows','tack-currency',{label=C.Text('menu_currency'),value=form.currency,options=currencies,disabled=form.quote~=nil},function(event)
                    if not s.busy and not form.quote then form.currency=event.value;renderTack(s,form) end
                end)
                local q=form.quote
                local amount=q and q.amount/100 or form.currency=='dollars' and item.cashPrice or item.goldPrice
                local shown=C.Text(form.currency=='dollars' and 'menu_cashPrice' or 'menu_goldPrice',item.currency==4 and 0 or amount)
                add('button','tack-purchase',{label=C.Text(q and 'menu_tackConfirm_'..slot or 'menu_reviewPurchase'),slot='footer',
                    confirm=q and {title=C.Text('menu_tackConfirm_'..slot),message=C.Text('menu_tackBuySummary',tackLabel(item),shown),
                        confirmLabel=C.Text('menu_tackBuy_'..slot),cancelLabel=C.Text('menu_cancel')} or nil},function()
                    local function failed(reply) form.error=reply.code;renderTack(s,form) end
                    if not q then
                        request(s,'tack_quote',{catalogId=item.id,currency=form.currency},function(value)
                            form.quote=value;form.error=nil;renderTack(s,form)
                        end,failed)
                    else
                        request(s,'tack_confirm',{operationId=q.operationId,amount=q.amount,currency=q.currency},function(value)
                            if value.state~='fulfilled' then failed({code=value.state=='cancelled' and 'insufficient_funds' or 'tack_pending'});return end
                            request(s,'tack_shop',{horseId=form.horse.horseId},function(updated)
                                form.quote=nil;form.error=nil;form.mode='owned';acceptTackShop(s,form,updated,value.instanceId)
                                renderTack(s,form);C.Message(C.Text('menu_tackPurchased'))
                            end,failed)
                        end,failed)
                    end
                end)
            end
        end
        if not shop.available then add('textdisplay','tack-notice',{value=C.Text('menu_tackPreviewOnly')}) end
    end
    if form.error then add('textdisplay','tack-error',{value=tackError({code=form.error})}) end
    rotation(add)
    if shop.available then add('button','tack-refresh',{label=C.Text('menu_refresh'),slot='footer'},function()
        request(s,'tack_shop',{horseId=form.horse.horseId},function(value)
            if form.error=='quote_expired' or form.error=='price_conflict' or form.error=='insufficient_funds' then form.quote=nil end
            form.error=nil;acceptTackShop(s,form,value);renderTack(s,form)
        end)
    end) end
    add('button','tack-back',{label=C.Text('menu_back'),slot='footer',row='actions'},function()
        if not s.busy then P.StopRotation();restoreRoster(s) end
    end)
    add('button','close',{label=C.Text('menu_close'),slot='footer',row='actions'},function() close(s) end)
    activate(s,id,old)
end

openTack = function(s)
    if not P.CanPreviewTack() then C.Message(C.Text('menu_tackUnavailable')); return end
    local horse = s.selectedHorse
    if not horse then P.Clear(true); renderTack(s, {}); return end
    request(s, 'preview', { horseId = horse.horseId }, function(value)
        if not value.selected or value.availability ~= 'stored' then
            s.selectedHorse = nil; P.Clear(true); renderTack(s, {}); return
        end
        s.busy = true
        local ok = true
        if P.IsShowing(s.token, s.site, value.horseId, value.modelKey) then P.SetGender(value.gender);P.SetSavedTack(s.token,s.site,value.horseId,value.tack or {})
        else ok = pcall(P.Show, s.token, s.site, value.modelKey, current, value.horseId, value.gender, value.tack) end
        s.busy = false
        if state ~= s then return end
        if s.closeRequested then close(s); return end
        if not ok or not P.IsShowing(s.token, s.site, value.horseId, value.modelKey) then
            P.Clear(true); C.Message(C.Text('menu_previewUnavailable')); return
        end
        P.StopRotation()
        request(s,'tack_shop',{horseId=value.horseId},function(shop)
            local form={horse=value,mode=shop.available and #shop.owned>0 and 'owned' or 'catalog'}
            acceptTackShop(s,form,shop);renderTack(s,form)
        end)
    end)
end

showCatalogCoat = function(s, breed, model)
    local entry = Horses.BreedCatalog[breed]
    if state ~= s or s.busy or not entry or not entry.colors[model] then return end
    P.StopRotation()
    local identity = 'catalog:' .. model
    local showing = P.IsShowing(s.token, s.site, identity, model)
    s.busy = not showing
    renderCatalog(s, breed, model)
    if showing then return end
    CreateThread(function()
        local ok = pcall(P.Show, s.token, s.site, model, current, identity)
        s.busy = false
        if state ~= s then return end
        if s.closeRequested then close(s); return end
        if s.catalog and s.catalogCoatId then Menu:UpdateElement(s.menuId, s.pageId, s.catalogCoatId, { disabled = false }) end
        if not ok or not P.IsShowing(s.token, s.site, identity, model) then
            P.Clear(true); C.Message(C.Text('menu_previewUnavailable'))
        end
    end)
end

renderCatalog = function(s, breedName, model)
    if state ~= s then return end
    s.catalog = { breed = breedName, model = model }; s.catalogSelection = s.catalog; s.catalogCoatId = nil; s.checkout = nil; s.detail = nil; s.renameForm = nil
    local id, old, add = page(s, 'catalog')
    add('header', 'title', { value = C.Text('menu_catalog'), slot = 'header' })
    add('subheader', 'site', { value = breedName or StableLocations[s.site].shop.name, slot = 'header' })
    if not breedName then
        local count = 0
        for index, name in ipairs(Horses.BreedsOrder or {}) do
            local coats = catalogCoats(Horses.BreedCatalog[name])
            if #coats > 0 then
                count = count + 1
                add('button', 'breed-' .. index, { label = name }, function()
                    showCatalogCoat(s, name, coats[1].value)
                end)
            end
        end
        if count == 0 then add('textdisplay', 'catalog-empty', { value = C.Text('menu_catalogEmpty') }) end
    else
        P.SetGender('male')
        local breed = Horses.BreedCatalog[breedName]
        local coat = breed and breed.colors[model]
        if not coat then error('catalog_unavailable', 0) end
        local coats = catalogCoats(breed)
        local position = 1
        for index, option in ipairs(coats) do if option.value == model then position = index; break end end
        s.catalogCoatId = add('arrows', 'catalog-coat', { label = C.Text('menu_coat'), value = model, options = coats, disabled = s.busy == true }, function(event)
            showCatalogCoat(s, breedName, event.value)
        end)
        add('textdisplay', 'catalog-position', { value = C.Text('menu_coatPosition', position, #coats) })
        add('textdisplay', 'catalog-price', { value = C.Text('menu_catalogPrice') .. ': ' .. catalogPrice(coat) })
        local enabled=Config.commerce and Config.commerce.purchasesEnabled==true and tonumber(coat.currency)~=4
        if not enabled then add('textdisplay', 'catalog-notice', { value = C.Text('menu_browsingOnly') }) end
        add('button', 'purchase', {label=C.Text('menu_purchase'),disabled=not enabled},function()
            if s.busy then return end
            P.StopRotation()
            renderCheckout(s,{breed=breedName,model=model,name='',gender='male',currency=tonumber(coat.currency)==2 and 'gold' or 'dollars'})
        end)
        baseStats(add, coat, true)
        rotation(add)
        add('button', 'catalog-back', { label = C.Text('menu_back'), slot = 'footer', row = 'actions' }, function()
            if s.busy then return end
            P.StopRotation(); renderCatalog(s)
        end)
    end
    add('button', 'close', { label = C.Text('menu_close'), slot = 'footer', row = 'actions' }, function() close(s) end)
    activate(s, id, old)
end

local function purchaseError(reply)
    local keys={invalid_name='nameInvalid',insufficient_funds='purchaseFunds',horse_limit='purchaseLimit',
        quote_expired='purchaseExpired',price_conflict='purchaseExpired',purchase_restricted='purchaseRestricted',
        purchase_disabled='purchaseDisabled',purchase_pending='purchasePending'}
    return C.Text('menu_'..(keys[reply.code] or 'purchaseFailed'))
end

renderCheckout = function(s,form)
    if state~=s then return end
    s.checkout=form;s.catalog=nil;s.detail=nil;s.renameForm=nil
    P.SetGender(form.gender)
    local id,old,add=page(s,'checkout')
    local coat=Horses.BreedCatalog[form.breed].colors[form.model]
    local q=form.quote
    add('header','title',{value=C.Text('menu_purchase'),slot='header'})
    add('subheader','horse',{value=form.breed..' - '..coat.color,slot='header'})
    add('input','purchase-name',{label=C.Text('menu_horseName'),value=form.name,maxLength=100,disabled=q~=nil,
        error=form.error=='invalid_name' and purchaseError({code=form.error}) or nil},function(event) if not s.busy then form.name=event.value end end)
    add('arrows','purchase-gender',{label=C.Text('menu_sex'),value=form.gender,disabled=q~=nil,
        options={{value='male',label=C.Text('menu_male')},{value='female',label=C.Text('menu_female')}}},
        function(event) if not s.busy then form.gender=event.value;P.SetGender(form.gender) end end)
    local mode=tonumber(coat.currency) or 3
    local currencies={}
    if mode~=2 then currencies[#currencies+1]={value='dollars',label=C.Text('menu_cash')} end
    if mode~=1 then currencies[#currencies+1]={value='gold',label=C.Text('menu_gold')} end
    add('arrows','purchase-currency',{label=C.Text('menu_currency'),value=form.currency,options=currencies,disabled=q~=nil},
        function(event) if not s.busy then form.currency=event.value;renderCheckout(s,form) end end)
    local selectedPrice=q and q.amount/100 or tonumber(form.currency=='dollars' and coat.cashPrice or coat.goldPrice)
    local shown=selectedPrice and C.Text(form.currency=='dollars' and 'menu_cashPrice' or 'menu_goldPrice',selectedPrice) or C.Text('menu_unknown')
    add('textdisplay','purchase-price',{value=C.Text('menu_catalogPrice')..': '..shown})
    if form.error and form.error~='invalid_name' then add('textdisplay','purchase-error',{value=purchaseError({code=form.error})}) end
    local actionId
    actionId=add('button','purchase-submit',{label=C.Text(q and 'menu_confirmPurchase' or 'menu_reviewPurchase'),busyLabel=C.Text('menu_purchasing'),
        slot='footer',confirm=q and {title=C.Text('menu_confirmPurchase'),message=C.Text('menu_purchaseSummary',q.name,form.breed,coat.color,C.Text(q.gender=='female' and 'menu_female' or 'menu_male'),shown),
            confirmLabel=C.Text('menu_purchase'),cancelLabel=C.Text('menu_cancel')} or nil},function()
        if s.busy then return end
        requireValue(Menu:UpdateElement(s.menuId,id,actionId,{busy=true}))
        local function failed(reply) form.error=reply.code;renderCheckout(s,form) end
        if not q then
            request(s,'purchase_quote',{modelKey=form.model,name=form.name,gender=form.gender,currency=form.currency},function(value)
                form.quote=value;form.name=value.name;form.error=nil;renderCheckout(s,form)
            end,failed)
        else
            request(s,'purchase_confirm',{operationId=q.operationId,amount=q.amount,currency=q.currency},function(value)
                if value.state~='fulfilled' then failed({code=value.state=='cancelled' and 'insufficient_funds' or 'purchase_pending'});return end
                request(s,'roster',{},function(data)
                    s.expanded=value.horseId;render(s,data)
                    for _,row in ipairs(data.entries) do if row.horseId==value.horseId then preview(s,row);break end end
                    C.Message(C.Text('menu_purchaseComplete'))
                end)
            end,failed)
        end
    end)
    add('button','purchase-refresh',{label=C.Text('menu_refresh'),slot='footer'},function()
        if s.busy then return end
        if q and form.error and form.error~='quote_expired' and form.error~='price_conflict' and form.error~='insufficient_funds' and form.error~='horse_limit' then return end
        form.quote=nil;form.error=nil;renderCheckout(s,form)
    end)
    add('button','back',{label=C.Text('menu_back'),slot='footer',row='actions'},function()
        if not s.busy then renderCatalog(s,form.breed,form.model) end
    end)
    add('button','close',{label=C.Text('menu_close'),slot='footer',row='actions'},function() close(s) end)
    activate(s,id,old)
end

restoreRoster = function(s)
    render(s, s.data)
    local target
    for _, row in ipairs(s.data.entries) do
        if row.horseId == s.expanded then target = row; break end
        if row.selected then target = row end
    end
    if target then preview(s, target) else P.Clear(true) end
end

local function beginRename(s, horse)
    request(s, 'preview', { horseId = horse.horseId }, function(value)
        renderRename(s, { horse = value, draft = value.name or '' })
    end)
end

renderRename = function(s, form)
    if state ~= s then return end
    s.renameForm = form; s.detail = nil
    local id, old, add = page(s, 'rename')
    add('header', 'title', { value = C.Text('menu_rename'), slot = 'header' })
    add('subheader', 'horse', { value = name(form.horse), slot = 'header' })
    add('input', 'horse-name', {
        label = C.Text('menu_horseName'),
        value = form.draft,
        placeholder = C.Text('menu_namePlaceholder'),
        maxLength = 100,
        error = form.error and C.Text(form.error) or nil
    }, function(event)
        if state == s and s.renameForm == form and not s.busy then form.draft = event.value end
    end)
    add('textdisplay', 'name-help', { value = C.Text('menu_nameHelp') })
    local saveId
    saveId = add('button', 'save-name', { label = C.Text('menu_saveName'), busyLabel = C.Text('menu_savingName'), slot = 'footer', row = 'rename-actions' }, function()
        if s.busy then return end
        requireValue(Menu:UpdateElement(s.menuId, id, saveId, { busy = true }))
        request(s, 'rename', { horseId = form.horse.horseId, revision = form.horse.assetRevision, name = form.draft },
            function(saved)
                for _, row in ipairs(s.data.entries) do if row.horseId == saved.horseId then row.name = saved.name end end
                renderDetails(s, saved)
                C.Message(C.Text('menu_nameSaved'))
            end, function(failure)
            if failure.code == 'invalid_name' then
                form.error = 'menu_nameInvalid'
            elseif failure.code == 'revision_conflict' or failure.code == 'idempotency_conflict' then
                form.error = 'menu_nameConflict'
            elseif failure.code == 'authorization_denied' then
                form.error = 'menu_nameDenied'
            else
                form.error = 'menu_nameFailed'
            end
            renderRename(s, form)
        end)
    end)
    add('button', 'refresh', { label = C.Text('menu_refresh'), slot = 'footer', row = 'rename-actions' }, function()
        request(s, 'preview', { horseId = form.horse.horseId }, function(value)
            form.horse = value; form.error = nil; renderRename(s, form)
        end)
    end)
    add('button', 'back', { label = C.Text('menu_back'), slot = 'footer', row = 'actions' }, function()
        if s.busy then return end
        renderDetails(s, form.horse)
    end)
    add('button', 'close', { label = C.Text('menu_close'), slot = 'footer', row = 'actions' }, function() close(s) end)
    activate(s, id, old)
end

renderDetails = function(s, horse)
    if state ~= s then return end
    s.detail = horse; s.renameForm = nil
    local id, old, add = page(s, 'details')
    local mapping = Horses.ModelToBreedMap[horse.modelKey]
    local breed = mapping and Horses.BreedCatalog[mapping.breed]
    local coat = breed and breed.colors[horse.modelKey]
    local status = horse.availability == 'stored' and 'stored' or horse.availability == 'active' and 'active' or
    'unavailableStatus'
    add('header', 'title', { value = C.Text('menu_details'), slot = 'header' })
    add('subheader', 'horse', { value = name(horse), slot = 'header' })
    local section = 'information'
    add('accordion', section, { label = C.Text('menu_horseInformation'), value = true })
    local function field(key, label, value)
        add('textdisplay', key, { value = C.Text('menu_' .. label) .. ': ' .. tostring(value), section = section })
    end
    field('breed', 'breed', mapping and mapping.breed or C.Text('menu_unknown'))
    field('coat', 'coat', coat and coat.color or C.Text('menu_unknown'))
    field('sex', 'sex', horse.gender and C.Text('menu_' .. horse.gender) or C.Text('menu_notRecorded'))
    field('ownership', 'ownership', C.Text('menu_owned')) -- ReadOwned verified fresh canonical ownership.
    field('selection', 'selection', C.Text(horse.selected and 'menu_selected' or 'menu_notSelected'))
    field('status', 'status', C.Text('menu_' .. status))
    section = 'condition-title'
    add('accordion', section, { label = C.Text('menu_savedCondition'), value = true })
    local condition = horse.condition
    field('health-core', 'savedHealth', condition and (tostring(condition.healthCore) .. '%') or
    C.Text('menu_notRecorded'))
    field('stamina-core', 'savedStamina',
        condition and (tostring(condition.staminaCore) .. '%') or C.Text('menu_notRecorded'))
    -- Existing Feather schema has no persisted progression ranks. Catalog base
    -- values are explicitly labelled; never invent trained stats or core defaults.
    baseStats(add, coat, false)
    rotation(add)
    if horse.availability == 'stored' then
        add('button', 'rename', { label = C.Text('menu_rename'), slot = 'footer', row = 'details-actions' },
            function() beginRename(s, horse) end)
    end
    add('button', 'refresh', { label = C.Text('menu_refresh'), slot = 'footer', row = 'details-actions' }, function()
        request(s, 'preview', { horseId = horse.horseId }, function(value) renderDetails(s, value) end)
    end)
    add('button', 'back', { label = C.Text('menu_back'), slot = 'footer', row = 'actions' }, function()
        if s.busy then return end
        P.StopRotation(); render(s, s.data)
    end)
    add('button', 'close', { label = C.Text('menu_close'), slot = 'footer', row = 'actions' }, function() close(s) end)
    activate(s, id, old)
end

render = function(s, data)
    if state ~= s then return end
    s.data = data; s.detail = nil; s.renameForm = nil; s.catalog = nil; s.checkout = nil
    for _, horse in ipairs(data.entries) do if horse.selected then s.selectedHorse = horse; break end end
    local id, old, add = page(s, 'roster')
    add('header', 'title', { value = C.Text('menu_title'), slot = 'header' })
    add('subheader', 'site', { value = StableLocations[s.site].shop.name, slot = 'header' })
    if #data.entries == 0 then add('textdisplay', 'empty', { value = C.Text('menu_empty') }) end
    for index, row in ipairs(data.entries) do
        local key = 'horse-' .. index
        local label = name(row)
        if row.availability == 'active' then
            label = label .. ' · ' .. C.Text('menu_active')
        elseif row.availability ~= 'stored' then
            label = label .. ' · ' .. C.Text('menu_unavailableStatus')
        end
        add('accordion', key, { label = label, value = s.expanded == row.horseId, labelAlign = 'center', notify = true, selected = row.selected == true }, function(event)
            if s.busy then return end
            local opened = event and event.value
            if opened == nil then opened = s.expanded ~= row.horseId end
            if opened and not row.selected and row.availability=='stored' then
                request(s,'select',{horseId=row.horseId,revision=row.selectionRevision,cursor=s.cursor},function(updated)
                    s.expanded=row.horseId;render(s,updated)
                    for _,fresh in ipairs(updated.entries) do if fresh.horseId==row.horseId then preview(s,fresh);break end end
                end,function(reply)
                    render(s,s.data);C.Message(C.Text('menu_unavailable',reply.code))
                end)
            else
                s.expanded = opened and row.horseId or nil
                render(s, s.data)
                if s.expanded then preview(s, row) end
            end
        end)
        if s.expanded == row.horseId then
            add('button', key .. '-details', { label = C.Text('menu_details'), section = key }, function()
                request(s, 'preview', { horseId = row.horseId }, function(value) renderDetails(s, value) end)
            end)
        end
        if s.expanded == row.horseId and row.availability == 'stored' then
            add('button', key .. '-select',
                { label = C.Text(row.selected and 'menu_takeOut' or 'menu_select'), section = key },
                function()
                    request(s, 'select', { horseId = row.horseId, revision = row.selectionRevision, cursor = s.cursor },
                        function(updated)
                            if row.selected then close(s, true) else render(s, updated) end
                        end)
                end)
        end
    end
    rotation(add)
    if data.nextCursor then
        add('button', 'next', { label = C.Text('menu_next'), slot = 'footer' }, function()
            local cursor = data.nextCursor
            request(s, 'roster', { cursor = cursor },
                function(updated)
                    s.cursor = cursor; s.expanded = nil; render(s, updated)
                end)
        end)
    end
    add('button', 'refresh', { label = C.Text('menu_refresh'), slot = 'footer', row = 'actions' }, function()
        request(s, 'roster', {}, function(updated)
            s.cursor = nil; s.expanded = nil; render(s, updated)
        end)
    end)
    add('button', 'close', { label = C.Text('menu_close'), slot = 'footer', row = 'actions' }, function() close(s) end)
    activate(s, id, old)
end

function U.Open(site)
    if opening or state then return end
    opening = true
    C.Message(C.Text('menu_opening'))
    CreateThread(function()
        local token
        local ok, failure = pcall(function()
            requireValue(Menu:AwaitReady(5000))
            local data = requireValue(C.Rpc('menu_open', { site = site })); token = data.token
            local s = { token = token, site = data.site, ped = PlayerPedId() }; state = s
            s.menuId = requireValue(Menu:CreateMenu({
                key = 'stable',
                draggable = true,
                closable = true,
                persistPosition = false,
                position = { x = '3%', y = '3%', anchor = 'top-left' },
                size = { width = '32rem', maxHeight = '80vh' },
                theme = { preset = 'redemption' }
            })).menuId
            s.tabAnchors = {
                roster = requireValue(Menu:CreatePage(s.menuId, { key = 'roster-tab' })).pageId,
                catalog = requireValue(Menu:CreatePage(s.menuId, { key = 'catalog-tab' })).pageId,
                tack = requireValue(Menu:CreatePage(s.menuId, { key = 'tack-tab' })).pageId,
            }
            requireValue(Menu:RegisterMenuLifecycle(s.menuId, function(event)
                if event.event == 'closed' and state == s then close(s) end
            end))
            render(s, data)
            requireValue(Menu:OpenMenu(s.menuId, { pageId = s.pageId }))
            for _, row in ipairs(data.entries) do if row.selected then
                    preview(s, row); break
                end end
        end)
        opening = false
        if not ok then
            if state then clear(state) end
            if token then C.Rpc('menu_close', { token = token }) end
            C.Message(C.Text('menu_unavailable', tostring(failure)))
        end
    end)
end

RegisterNetEvent('bcc-stables:menu:closed', function(token)
    if source == 65535 and state and state.token == token then clear(state) end
end)

AddEventHandler('feather-core:locale:changed', function()
    local s = state
    if s and s.data then
        local ok = pcall(function()
            if s.tack then
                renderTack(s, s.tack)
            elseif s.checkout then
                renderCheckout(s,s.checkout)
            elseif s.catalog then
                renderCatalog(s, s.catalog.breed, s.catalog.model)
            elseif s.renameForm then
                renderRename(s, s.renameForm)
            elseif s.detail then
                renderDetails(s, s.detail)
            else
                render(s, s.data)
            end
        end)
        if not ok then close(s) end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and entryPrompt then
        UiPromptDelete(entryPrompt); entryPrompt = nil
    end
    if resource == GetCurrentResourceName() or resource == 'feather-core' or resource == 'feather-menu-v2' or resource == 'feather-routing' then
        P.Clear()
        local s = state
        if s then
            clear(s, true)
            if resource ~= GetCurrentResourceName() and resource ~= 'feather-core' then CreateThread(function() C.Rpc(
                    'menu_close', { token = s.token }) end) end
        end
    end
end)

CreateThread(function()
    local group = GetRandomIntInRange(0, 0xffffff)
    local prompt = UiPromptRegisterBegin()
    entryPrompt = prompt
    UiPromptSetControlAction(prompt, Config.controls.openStable)
    UiPromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', C.Text('shopPrompt')))
    UiPromptSetStandardMode(prompt, true); UiPromptSetGroup(prompt, group, 0)
    UiPromptSetEnabled(prompt, true); UiPromptSetVisible(prompt, true); UiPromptRegisterEnd(prompt)
    while true do
        local wait = 500
        local ped = PlayerPedId()
        if not state and not opening and not IsNuiFocused() and not yes(IsPedDeadOrDying(ped, true)) then
            local coords = GetEntityCoords(ped)
            for id, site in pairs(StableLocations) do
                if #(coords - site.npc.coords) <= site.shop.distance then
                    wait = 0
                    UiPromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', C.Text('shopPrompt')))
                    UiPromptSetActiveGroupThisFrame(group, CreateVarString(10, 'LITERAL_STRING', site.shop.name), 1, 0, 0,
                        0)
                    if UiPromptHasStandardModeCompleted(prompt, 0) then U.Open(id) end
                    break
                end
            end
        end
        if state and (state.ped ~= ped or yes(IsPedDeadOrDying(ped, true))) then close(state) end
        local s = state
        if s and not s.pinging and GetGameTimer() >= (s.nextPing or 0) then
            s.pinging = true; s.nextPing = GetGameTimer() + 10000
            CreateThread(function()
                local reply = C.Rpc('menu_ping', { token = s.token }); s.pinging = false
                if state == s and not reply.ok then clear(s) end
            end)
        end
        Wait(wait)
    end
end)
