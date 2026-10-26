local activeHorseInfoMenu

local GET_ATTRIBUTE_CORE_VALUE <const> = 0x36731AC041289BB1

local ATTRIBUTE <const> = {
    health = 0,
    stamina = 1,
    handling = 4,
    speed = 5,
    acceleration = 6,
}

local TEXT_STYLE <const> = {
    ['color'] = '#C0C0C0',
    ['font-variant'] = 'small-caps',
    ['font-size'] = '1.481vmin',
    ['line-height'] = '1.8',
}

local BONDING_PERKS <const> = {
    [1] = {
        'Increases core restoration from brushing, feeding, grazing, and drinking by 25%',
    },
    [2] = {
        'Unlocks the horse Rest prompt',
        'Reduces reactions to shocking events',
        'Unlocks Rear-Up: Left Ctrl + Space',
    },
    [3] = {
        'Unlocks the horse Sleep prompt',
        'Reduces the horse gunshot flee response',
        'Unlocks Skid/Slide: Left Ctrl',
    },
    [4] = {
        'Unlocks the horse Wallow prompt',
        'Unlocks Dance: Space',
        'Unlocks Side-Pass: Space + A or D',
        'Reaches maximum bonding',
    },
}

local function nativeInteger(native, ...)
    return tonumber(Citizen.InvokeNative(native, ..., Citizen.ResultAsInteger()))
end

local function getCoreValue(horse, attribute)
    return nativeInteger(GET_ATTRIBUTE_CORE_VALUE, horse, attribute)
end

local function displayRank(rank)
    return rank and ('%d/10'):format(rank + 1) or 'N/A'
end

local function displayPercent(value)
    return value and ('%d%%'):format(math.max(0, math.min(100, value))) or 'N/A'
end

local function addText(page, id, value, style)
    page:RegisterElement('textdisplay', {
        id = id,
        value = value,
        slot = 'content',
        style = style or TEXT_STYLE,
    })
end

local function addPageHeader(page, subtitle)
    page:RegisterElement('header', {
        value = _U('horseInfo') or 'Horse Info',
        slot = 'header',
        style = { ['color'] = '#999' },
    })
    page:RegisterElement('subheader', {
        value = subtitle,
        slot = 'header',
        style = { ['font-size'] = '1.778vmin', ['color'] = '#CC9900' },
    })
    page:RegisterElement('line', { slot = 'header' })
end

local function getTrainingProgress()
    local xp = math.max(0, tonumber(ActiveHorseXp) or 0)
    local xpPerLevel = math.max(1, tonumber(Config.training.xpPerLevel) or 1000)
    local level = math.floor(xp / xpPerLevel)
    local levelXp = xp % xpPerLevel
    local percent = math.floor((levelXp / xpPerLevel) * 100)
    return level, levelXp, xpPerLevel, percent
end

local function getHorseInfo(horse)
    local trainingLevel, levelXp, xpPerLevel, trainingPercent = getTrainingProgress()
    local bondingLevel, bondingXp, milestones = GetHorseBondingData(horse, ActiveHorseXp)
    local stats = type(MyHorseStats) == 'table' and MyHorseStats or {}
    local aging = type(MyHorseAging) == 'table' and MyHorseAging or {}

    return {
        name = HorseName or 'My Horse',
        breed = MyHorseBreed or 'Unknown',
        coat = MyHorseColor or 'Unknown',
        healthCore = getCoreValue(horse, ATTRIBUTE.health),
        staminaCore = getCoreValue(horse, ATTRIBUTE.stamina),
        health = tonumber(stats.health),
        stamina = tonumber(stats.stamina),
        handling = tonumber(stats.handling),
        speed = tonumber(stats.speed),
        acceleration = tonumber(stats.acceleration),
        bondingLevel = bondingLevel,
        bondingPoints = bondingXp,
        bondingMilestones = milestones,
        trainingLevel = trainingLevel,
        trainingLevelXp = levelXp,
        xpPerLevel = xpPerLevel,
        trainingPercent = trainingPercent,
        agingEnabled = aging.agingEnabled == true,
        bornAt = aging.bornAt,
        ageYears = tonumber(aging.ageYears),
        lifeStage = aging.lifeStage,
        flamingHoovesSeconds = type(GetFlamingHoovesRemainingSeconds) == 'function'
            and GetFlamingHoovesRemainingSeconds() or 0,
    }
end

local function buildPerformancePage(page, bondingPage, info)
    addPageHeader(page, 'Performance Statistics')

    addText(page, 'horse_info_identity', ('%s\n%s %s\n%s %s'):format(
        info.name,
        _U('breed') or 'Breed:', tostring(info.breed),
        _U('coat') or 'Coat:', tostring(info.coat)
    ), {
        ['color'] = '#C0C0C0',
        ['font-size'] = '1.55vmin',
        ['line-height'] = '1.7',
        ['white-space'] = 'pre-line',
    })

    page:RegisterElement('line', { slot = 'content' })

    if info.agingEnabled then
        addText(page, 'horse_info_age', ('Born: %s  |  Age: %s  |  Life Stage: %s'):format(
            info.bornAt or 'N/A',
            info.ageYears and (tostring(info.ageYears) .. ' years') or 'N/A',
            info.lifeStage or 'N/A'
        ), {
            ['color'] = '#C0C0C0',
            ['font-size'] = '1.35vmin',
            ['line-height'] = '1.6',
        })
        page:RegisterElement('line', { slot = 'content' })
    end

    addText(page, 'horse_info_cores', ('Health Core: %s  |  Stamina Core: %s'):format(
        displayPercent(info.healthCore), displayPercent(info.staminaCore)
    ))

    if info.flamingHoovesSeconds > 0 then
        local minutes = math.floor(info.flamingHoovesSeconds / 60)
        local seconds = info.flamingHoovesSeconds % 60
        addText(page, 'horse_info_flaming_hooves', ('Flaming Hooves: %d:%02d remaining'):format(minutes, seconds), {
            ['color'] = '#FF9933',
            ['font-size'] = '1.481vmin',
        })
    end

    addText(page, 'horse_info_capacity', ('Health: %s  |  Stamina: %s'):format(
        displayRank(info.health), displayRank(info.stamina)
    ))

    addText(page, 'horse_info_performance', ('Speed: %s\nAcceleration: %s\nHandling: %s'):format(
        displayRank(info.speed), displayRank(info.acceleration), displayRank(info.handling)
    ), {
        ['color'] = '#C0C0C0',
        ['font-variant'] = 'small-caps',
        ['font-size'] = '1.481vmin',
        ['line-height'] = '1.8',
        ['white-space'] = 'pre-line',
    })

    addText(page, 'horse_info_training', ('Training Level: %d\nProgress: %d / %d XP (%d%%)'):format(
        info.trainingLevel, info.trainingLevelXp, info.xpPerLevel, info.trainingPercent
    ), {
        ['color'] = '#66CC66',
        ['font-size'] = '1.481vmin',
        ['line-height'] = '1.7',
        ['white-space'] = 'pre-line',
    })

    page:RegisterElement('bottomline', { slot = 'footer' })

    page:RegisterElement('button', {
        id = 'horse_info_bonding',
        label = 'View Bonding Unlocks',
        slot = 'footer',
        style = { ['color'] = '#E0E0E0' },
    }, function()
        bondingPage:RouteTo()
    end)

    return page
end

local function bondingRequirement(info, level)
    local requirement = info.bondingMilestones[level]
    return requirement and ('%d XP'):format(requirement) or 'N/A'
end

local function buildBondingPage(page, performancePage, levelPages, info)
    addPageHeader(page, 'Bonding Unlocks')

    addText(page, 'horse_info_bonding_status', ('Current Level: %s / 4\nCurrent XP: %s'):format(
        info.bondingLevel and tostring(info.bondingLevel) or 'N/A',
        info.bondingPoints and tostring(info.bondingPoints) or 'N/A'
    ), {
        ['color'] = '#66A3CC',
        ['font-size'] = '1.481vmin',
        ['line-height'] = '1.7',
        ['white-space'] = 'pre-line',
    })

    page:RegisterElement('line', { slot = 'content' })
    for level = 1, 4 do
        local targetPage = levelPages[level]
        local isUnlocked = info.bondingLevel >= level
        page:RegisterElement('button', {
            id = 'horse_info_bond_level_' .. level,
            label = ('Level %d — %s — %s'):format(
                level,
                bondingRequirement(info, level),
                isUnlocked and 'Unlocked' or 'Locked'
            ),
            slot = 'content',
            style = { ['color'] = isUnlocked and '#66CC66' or '#C0C0C0' },
        }, function()
            targetPage:RouteTo()
        end)
    end

    page:RegisterElement('bottomline', { slot = 'footer' })
    page:RegisterElement('button', {
        id = 'horse_info_back',
        label = _U('backButton') or 'Back',
        slot = 'footer',
        style = { ['color'] = '#E0E0E0' },
    }, function()
        performancePage:RouteTo()
    end)

    return page
end

local function buildBondingLevelPage(page, bondingPage, level, info)
    addPageHeader(page, ('Bonding Level %d'):format(level))

    local requirement = info.bondingMilestones[level]
    local isUnlocked = info.bondingLevel >= level
    addText(page, 'horse_info_bond_level_status_' .. level, ('Status: %s\nRequired: %s\nCurrent XP: %d'):format(
        isUnlocked and 'Unlocked' or 'Locked',
        bondingRequirement(info, level),
        info.bondingPoints
    ), {
        ['color'] = isUnlocked and '#66CC66' or '#CC9900',
        ['font-size'] = '1.481vmin',
        ['line-height'] = '1.7',
        ['white-space'] = 'pre-line',
    })

    page:RegisterElement('line', { slot = 'content' })
    local perks = BONDING_PERKS[level] or {}
    for index, perk in ipairs(perks) do
        addText(page, ('horse_info_bond_level_%d_perk_%d'):format(level, index), ('• %s'):format(perk))
    end

    local flamingConfig = Config.items.flamingHooves
    if flamingConfig and flamingConfig.enabled
        and math.max(0, math.min(4, math.floor(tonumber(flamingConfig.requiredBondingLevel) or 0))) == level then
        addText(page, ('horse_info_bond_level_%d_flaming_hooves'):format(level),
            '• Unlocks Flaming Hooves items')
    end

    if not requirement then
        addText(page, 'horse_info_bond_level_missing_' .. level,
            'The XP requirement is unavailable for this horse model.',
            { ['color'] = '#CC6666', ['font-size'] = '1.481vmin' })
    end

    page:RegisterElement('bottomline', { slot = 'footer' })
    page:RegisterElement('button', {
        id = 'horse_info_bond_level_back_' .. level,
        label = _U('backButton') or 'Back',
        slot = 'footer',
        style = { ['color'] = '#E0E0E0' },
    }, function()
        bondingPage:RouteTo()
    end)
end

function HorseInfoMenu()
    local horse = MyHorse
    if not horse or horse == 0 or not DoesEntityExist(horse) then
        Core.NotifyRightTip(_U('noHorse') or 'You do not have an active horse.', 4000)
        return
    end

    if activeHorseInfoMenu then activeHorseInfoMenu:Close() end

    activeHorseInfoMenu = FeatherMenu:RegisterMenu('bcc-horses:HorseInfoMenu', {
        top = '3%',
        left = '3%',
        ['720width'] = '400px',
        ['1080width'] = '500px',
        ['2kwidth'] = '600px',
        ['4kwidth'] = '800px',
        contentslot = { style = { ['height'] = '450px', ['min-height'] = '400px' } },
        draggable = true,
        canclose = true,
    })

    local info = getHorseInfo(horse)
    local performancePage = activeHorseInfoMenu:RegisterPage('info_performance')
    local bondingPage = activeHorseInfoMenu:RegisterPage('info_bonding')
    local levelPages = {}
    for level = 1, 4 do
        levelPages[level] = activeHorseInfoMenu:RegisterPage('info_bonding_level_' .. level)
    end

    buildPerformancePage(performancePage, bondingPage, info)
    buildBondingPage(bondingPage, performancePage, levelPages, info)
    for level = 1, 4 do
        buildBondingLevelPage(levelPages[level], bondingPage, level, info)
    end
    activeHorseInfoMenu:Open({ startupPage = performancePage })
end
