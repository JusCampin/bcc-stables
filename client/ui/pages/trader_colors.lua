local expandedCoatModel

local function canAccessCoat(model, job)
    local locks = Horses.ModelJobLocks and Horses.ModelJobLocks.Models
    local allowedJobs = locks and locks[model]
    return not allowedJobs or allowedJobs[job] == true
end

local function sortedCoats(breed)
    local coats = {}
    for model, data in pairs(breed and breed.colors or {}) do
        coats[#coats + 1] = { model = model, data = data, label = data.color or model }
    end
    table.sort(coats, function(left, right) return left.label:lower() < right.label:lower() end)
    return coats
end

local function previewTraderCoat(modelName)
    CreateThread(function()
        ClearShopHorse()
        local requestId = StableUI.BeginPreviewRequest()
        local model = joaat(modelName)

        Citizen.InvokeNative(0x7F78CD75CC4539E4, CreateVarString(10, 'LITERAL_STRING', 'Loading trader horse...'))
        if not LoadModel(model, modelName) or not StableUI.IsPreviewRequestCurrent(requestId) then
            Citizen.InvokeNative(0x58F441B90EA84D06)
            return
        end

        local spawn = StableUI.GetPreviewHorseConfig()
        if not spawn then
            SetModelAsNoLongerNeeded(model)
            Citizen.InvokeNative(0x58F441B90EA84D06)
            return
        end

        local coords = spawn.coords
        local spawnZ = coords.z - 1.0
        local entity = CreatePed(model, coords.x, coords.y, spawnZ, spawn.heading, false, false, false, false)
        SetModelAsNoLongerNeeded(model)
        if not CheckEntityExists(entity) or not StableUI.IsPreviewRequestCurrent(requestId) then
            if entity and entity ~= 0 and DoesEntityExist(entity) then DeleteEntity(entity) end
            Citizen.InvokeNative(0x58F441B90EA84D06)
            return
        end

        ShopEntity = entity
        StableUI.HidePreviewHorse(entity)
        Citizen.InvokeNative(0x283978A15512B2FE, entity, true)
        StableUI.PlacePreviewHorse(entity, spawn)
        Citizen.InvokeNative(0x7D9EFB7AD6B19754, entity, true)
        SetBlockingOfNonTemporaryEvents(entity, true)
        SetPedConfigFlag(entity, 113, true)
        StableUI.CleanPreviewHorse(entity, function(ready)
            if not StableUI.IsPreviewRequestCurrent(requestId) then
                if not DoesEntityExist(MyEntity) and not DoesEntityExist(ShopEntity) then
                    Citizen.InvokeNative(0x58F441B90EA84D06)
                end
                return
            end
            if ready then StableUI.RevealPreviewHorse(entity) end
            Citizen.InvokeNative(0x58F441B90EA84D06)
        end)
        StableUI.FramePreviewCamera(entity)

        if not Cam then
            Cam = true
            CameraLighting()
        end
    end)
end

local function addCoatActions(page, coat, index)
    StableUI.AddButton(page, 'trader_coat_details_' .. index, '    View Stats & Details', 'content', function()
        StopRotation()
        BuildHorseDetailPage({ id = 0, model = coat.model, name = 'Horse Stats' }, 'trader_colors')
        StableUI.OpenPage('horse_detail')
    end, StableUI.Styles.text)

    StableUI.AddButton(page, 'trader_coat_purchase_' .. index, '    Purchase Selection', 'content', function()
        if BuildTraderPurchasePage() then StableUI.OpenPage('trader_purchase') end
    end, StableUI.Styles.text)
end

function BuildTraderColorsPage()
    local breedName = SelectedBreedName
    local breed = breedName and Horses.BreedCatalog[breedName]
    if not breed then
        Core.NotifyRightTip('This horse breed is unavailable.', 4000)
        return false
    end

    local page = StableUI.RegisterPage('trader_colors')
    local character = LocalPlayer.state.Character or {}
    local job = character.Job or 'unemployed'
    StableUI.AddHeader(page, breedName)

    for index, coat in ipairs(sortedCoats(breed)) do
        if canAccessCoat(coat.model, job) then
            local expanded = expandedCoatModel == coat.model
            StableUI.AddButton(
                page,
                'trader_coat_' .. index,
                expanded and (coat.label .. ' ▼') or coat.label,
                'content',
                function()
                    StopRotation()
                    expandedCoatModel = expanded and nil or coat.model
                    SelectedColorKey = expandedCoatModel
                    BuildTraderColorsPage()
                    StableUI.OpenPage('trader_colors')
                    if expandedCoatModel then previewTraderCoat(coat.model) else ClearShopHorse() end
                end,
                expanded and StableUI.Styles.subheader or StableUI.Styles.button
            )
            if expanded then addCoatActions(page, coat, index) end
        end
    end

    StableUI.AddFooter(page)
    StableUI.AddButton(page, 'trader_coat_rotate', '↻ ' .. (_U('rotateButton') or 'Rotate'), 'footer', function()
        StableUI.ToggleRotation(-1)
    end)
    StableUI.AddButton(page, 'trader_coat_back', _U('backButton') or 'Back', 'footer', function()
        StopRotation()
        ClearShopHorse()
        expandedCoatModel = nil
        SelectedColorKey = nil
        StableUI.OpenPage('trader')
    end)
    return true
end
