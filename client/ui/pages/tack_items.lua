local ownedModeBySlot = {}

local function formatSelectedPrice(item, ownedOnly)
    if not item then return 'No component selected' end
    if ownedOnly then
        return ('Owned - %d%% durability'):format(tonumber(item.durability) or 100)
    end
    return 'Price: ' .. Tack.FormatPrice(item)
end

local function buildComponentOptions(items, session, slotId, ownedOnly)
    local options = { { display = '0', choice = false } }
    local startIndex = 1
    local equipped = session.preview[slotId]

    for index, item in ipairs(items) do
        local catalogId = item.catalogId or item.id
        options[#options + 1] = {
            display = tostring(index),
            item = item,
            choice = {
                itemId = item.itemId,
                catalogId = catalogId,
                durability = item.durability,
                purchase = not ownedOnly,
            },
        }
        if equipped and equipped.catalogId == catalogId
            and (not ownedOnly or tonumber(equipped.itemId) == tonumber(item.itemId)) then
            startIndex = #options
        end
    end
    return options, startIndex
end

function BuildTackItemsPage(slotId, ownedOnly)
    local slot = Tack.GetSlot(slotId)
    local session = TackSession.getState()
    if not slot or not session then return false end

    if ownedOnly == nil then ownedOnly = ownedModeBySlot[slotId] == true end
    ownedModeBySlot[slotId] = ownedOnly

    local page = StableUI.RegisterPage('tack_items')
    local options, startIndex = buildComponentOptions(
        TackSession.getSlotItems(slotId, ownedOnly), session, slotId, ownedOnly
    )
    local selectedItem = options[startIndex].item
    local componentDisplay
    local priceDisplay

    StableUI.AddHeader(page, slot.label)
    page:RegisterElement('arrows', {
        id = 'tack_component_selector', label = 'Component', slot = 'content',
        start = startIndex, options = options, persist = true,
    }, function(data)
        local option = data and data.value
        if not option then return end
        selectedItem = option.item
        TackSession.select(slotId, option.choice)
        componentDisplay:update({ value = selectedItem and selectedItem.label or 'None' })
        priceDisplay:update({ value = formatSelectedPrice(selectedItem, ownedOnly) })
    end)

    page:RegisterElement('arrows', {
        id = 'tack_component_source', label = 'Source', slot = 'content',
        start = ownedOnly and 2 or 1, persist = true,
        options = {
            { display = 'Shop Catalog', extra = false },
            { display = 'Owned Tack', extra = true },
        },
    }, function(data)
        local option = data and data.value
        if not option or option.extra == ownedOnly then return end
        ownedModeBySlot[slotId] = option.extra
        BuildTackItemsPage(slotId, option.extra)
        StableUI.OpenPage('tack_items')
    end)

    componentDisplay = StableUI.AddText(
        page, 'tack_component_name', selectedItem and selectedItem.label or 'None'
    )
    priceDisplay = StableUI.AddText(
        page, 'tack_component_price', formatSelectedPrice(selectedItem, ownedOnly), StableUI.Styles.success
    )

    StableUI.AddFooter(page)
    StableUI.AddButton(page, 'tack_item_rotate', '\226\134\187 ' .. (_U('rotateButton') or 'Rotate'), 'footer', function()
        StableUI.ToggleRotation(-1)
    end)
    StableUI.AddButton(page, 'tack_item_back', _U('backButton') or 'Back', 'footer', function()
        StopRotation()
        BuildTackCategoriesPage()
        StableUI.OpenPage('tack_categories')
    end)
    return true
end
