function BuildTackLoadoutPage()
    local session = TackSession.getState()
    if not session then return false end

    local page = StableUI.RegisterPage('tack_loadout')
    local lines = {}
    for _, slot in ipairs(Tack.Slots) do
        local equipped = session.preview[slot.id]
        local item = equipped and Tack.GetItem(equipped.catalogId)
        lines[#lines + 1] = ('%s: %s'):format(slot.label, item and item.label or 'None')
    end

    StableUI.AddHeader(page, 'Current Tack Loadout')
    StableUI.AddText(page, 'tack_loadout_list', table.concat(lines, '\n'), {
        ['color'] = '#C0C0C0',
        ['font-size'] = '1.481vmin',
        ['font-variant'] = 'small-caps',
        ['line-height'] = '2.0',
        ['white-space'] = 'pre-line',
    })
    StableUI.AddFooter(page)
    StableUI.AddButton(page, 'tack_loadout_back', _U('backButton') or 'Back', 'footer', function()
        StopRotation()
        BuildTackCategoriesPage()
        StableUI.OpenPage('tack_categories')
    end)
    return true
end
