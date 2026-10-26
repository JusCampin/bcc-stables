function BuildTackShopPage()
    if not MyEntityID or MyEntity == 0 or not DoesEntityExist(MyEntity) then
        Core.NotifyRightTip(_U('noHorse') or 'Select a horse before opening the tack shop.', 4000)
        return false
    end

    return TackSession.open(MyEntityID, MyEntity, Site, function()
        BuildTackCategoriesPage()
        StableUI.OpenPage('tack_categories')
    end)
end

function BuildTackCategoriesPage()
    local page = StableUI.RegisterPage('tack_categories')
    StableUI.AddHeader(page, _U('tackShop') or 'Tack Shop')

    for _, slot in ipairs(Tack.Slots) do
        StableUI.AddButton(page, 'tack_slot_' .. slot.id, slot.label, 'content', function()
            BuildTackItemsPage(slot.id)
            StableUI.OpenPage('tack_items')
        end)
    end

    StableUI.AddFooter(page)
    StableUI.AddButton(page, 'tack_loadout', 'View Current Loadout', 'footer', function()
        BuildTackLoadoutPage()
        StableUI.OpenPage('tack_loadout')
    end)
    StableUI.AddButton(page, 'tack_checkout', 'Review Checkout', 'footer', function()
        if not TackSession.hasChanges() then
            Core.NotifyRightTip('No tack changes to review.', 4000)
            return
        end
        BuildTackCheckoutPage()
        StableUI.OpenPage('tack_checkout')
    end, StableUI.Styles.success)
    StableUI.AddButton(page, 'tack_rotate', '\226\134\187 ' .. (_U('rotateButton') or 'Rotate'), 'footer', function()
        StableUI.ToggleRotation(-1)
    end)
    StableUI.AddButton(page, 'tack_back', _U('backButton') or 'Back', 'footer', function()
        TackSession.cancel()
        StopRotation()
        BuildMyHorsesPage()
        StableUI.OpenPage('my_horses')
    end)
end
