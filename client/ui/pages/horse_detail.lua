local DETAIL_STATS <const> = {
    { key = 'speed', locale = 'speed', fallback = 'Speed:' },
    { key = 'acceleration', locale = 'acceleration', fallback = 'Acceleration:' },
    { key = 'handling', locale = 'handling', fallback = 'Handling:' },
    { key = 'health', locale = 'health', fallback = 'Health:' },
    { key = 'stamina', locale = 'stamina', fallback = 'Stamina:' },
}

local function displayStat(value)
    return value and ('%d/10'):format(value + 1) or 'N/A'
end

local function addHorseStats(page, horse, baseStats)
    local owned = (tonumber(horse.id) or 0) > 0
    local currentStats = owned and StableUI.AsTable(horse.stats) or baseStats

    for _, definition in ipairs(DETAIL_STATS) do
        local current = tonumber(currentStats[definition.key])
        local base = tonumber(baseStats[definition.key])
        local bonus = owned and current and base and current - base or nil
        local value = displayStat(current)

        if bonus and bonus > 0 then
            value = ('%s (+%d)'):format(value, bonus)
        end

        StableUI.AddText(
            page,
            'horse_detail_stat_' .. definition.key,
            ('%s %s'):format(_U(definition.locale) or definition.fallback, value),
            bonus and bonus > 0 and StableUI.Styles.success or StableUI.Styles.text
        )
    end
end

--- @param horse table
--- @param origin 'my_horses'|'trader_colors'|nil
function BuildHorseDetailPage(horse, origin)
    if type(horse) ~= 'table' then return end

    local page = StableUI.RegisterPage('horse_detail')
    local horseId = tonumber(horse.id)
    local horseName = horse.name or (horseId and ('Horse #%d'):format(horseId) or 'Horse Details')
    local breedName, colorData = StableUI.GetCoat(horse.model)
    local colorName = colorData and colorData.color or 'Unknown'
    local inventoryLimit = colorData and tonumber(colorData.invLimit)
    local baseStats = colorData and type(colorData.stats) == 'table' and colorData.stats or {}

    StableUI.AddHeader(page, horseName)
    StableUI.AddText(page, 'horse_detail_identity', ('%s %s\n%s %s\n%s %s'):format(
        _U('breed') or 'Breed:', breedName or 'Unknown',
        _U('color') or 'Color:', colorName,
        _U('invLimit') or 'Inventory Limit:', inventoryLimit and tostring(inventoryLimit) or 'N/A'
    ))
    if horse.agingEnabled == true then
        StableUI.AddText(page, 'horse_detail_age', ('Born: %s\nAge: %s years | Life Stage: %s'):format(
            horse.bornAt or 'N/A',
            horse.ageYears ~= nil and tostring(horse.ageYears) or 'N/A',
            horse.lifeStage or 'N/A'
        ))
    end
    page:RegisterElement('line', { slot = 'content' })
    addHorseStats(page, horse, baseStats)

    StableUI.AddFooter(page)
    StableUI.AddButton(page, 'horse_detail_rotate', '↻ ' .. (_U('rotateButton') or 'Rotate'), 'footer', function()
        StableUI.ToggleRotation(-1)
    end)
    StableUI.AddButton(page, 'horse_detail_back', _U('backButton') or 'Back', 'footer', function()
        StopRotation()
        if origin == 'trader_colors' then
            BuildTraderColorsPage()
            StableUI.OpenPage('trader_colors')
        else
            BuildMyHorsesPage()
            StableUI.OpenPage('my_horses')
        end
    end)
end
