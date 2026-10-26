local function canAccessModel(model, job)
    local locks = Horses.ModelJobLocks and Horses.ModelJobLocks.Models
    local allowedJobs = locks and locks[model]
    return not allowedJobs or allowedJobs[job] == true
end

local function breedHasAccessibleCoat(breed, job)
    for model in pairs(breed.colors or {}) do
        if canAccessModel(model, job) then return true end
    end
    return false
end

function BuildTraderPage()
    local page = StableUI.RegisterPage('trader')
    StableUI.AddHeader(page, _U('horseTrader') or 'Horse Trader')

    if IsPlayerBlockedFromCurrentTrainerShop() then
        StableUI.AddText(
            page,
            'trader_access_denied',
            _U('trainerBuyHorse') or 'Only trainers can purchase horses at this stable.',
            StableUI.Styles.danger
        )
    else
        local character = LocalPlayer.state.Character or {}
        local job = character.Job or 'unemployed'

        for index, breedName in ipairs(Horses.BreedsOrder or {}) do
            local breed = Horses.BreedCatalog[breedName]
            if breed and breedHasAccessibleCoat(breed, job) then
                StableUI.AddButton(page, 'trader_breed_' .. index, breedName, 'content', function()
                    SelectedBreedName = breedName
                    BuildTraderColorsPage()
                    StableUI.OpenPage('trader_colors')
                end)
            end
        end
    end

    StableUI.AddFooter(page)
    StableUI.AddButton(page, 'trader_back', _U('backButton') or 'Back', 'footer', function()
        StopRotation()
        ExpandedHorseId = nil
        BuildMyHorsesPage()
        StableUI.OpenPage('my_horses')
    end)
end
