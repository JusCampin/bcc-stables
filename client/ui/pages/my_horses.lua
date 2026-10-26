local BUSY_SPINNER_TEXT <const> = 0x7F78CD75CC4539E4
local BUSY_SPINNER_OFF <const> = 0x58F441B90EA84D06

local function configurePreviewHorse(entity, horse, preview, onReady)
    Citizen.InvokeNative(0x283978A15512B2FE, entity, true) -- SetRandomOutfitVariation
    StableUI.PlacePreviewHorse(entity, preview or StableUI.GetPreviewHorseConfig())
    Citizen.InvokeNative(0x7D9EFB7AD6B19754, entity, true) -- FreezeEntityPosition

    if horse.gender == 'female' then
        Citizen.InvokeNative(0x5653AB26C82938CF, entity, 41611, 1.0) -- SetCharExpression
        Citizen.InvokeNative(0xCC8CA3E88256E58F, entity, false, true, true, true, false)
    end

    SetBlockingOfNonTemporaryEvents(entity, true)
    SetPedConfigFlag(entity, 113, true)
    HorseAppearance.resetTracking(entity)
    HorseAppearance.applyLoadout(entity, horse.tackLoadout or {})
    StableUI.CleanPreviewHorse(entity, onReady)
end

local function showPreviewCamera()
    if Cam then return end
    Cam = true
    CameraLighting()
end

local function previewHorse(horse)
    CreateThread(function()
        local cached = GetCachedHorse(horse.id)
        if cached and cached.entity ~= 0 and DoesEntityExist(cached.entity) then
            MyEntity = cached.entity
            MyEntityID = horse.id
            configurePreviewHorse(MyEntity, horse, StableUI.GetPreviewHorseConfig())
            StableUI.FramePreviewCamera(MyEntity)
            showPreviewCamera()
            return
        end

        ClearShopHorse()
        local requestId = StableUI.BeginPreviewRequest()
        local modelName = horse.model
        local model = modelName and joaat(modelName)
        if not model then return end

        Citizen.InvokeNative(BUSY_SPINNER_TEXT, CreateVarString(10, 'LITERAL_STRING', 'Loading horse...'))
        if not LoadModel(model, modelName) or not StableUI.IsPreviewRequestCurrent(requestId) then
            Citizen.InvokeNative(BUSY_SPINNER_OFF)
            return
        end

        local spawn = StableUI.GetPreviewHorseConfig()
        if not spawn then
            SetModelAsNoLongerNeeded(model)
            Citizen.InvokeNative(BUSY_SPINNER_OFF)
            return
        end

        local coords = spawn.coords
        local spawnZ = coords.z - 1.0
        local entity = CreatePed(model, coords.x, coords.y, spawnZ, spawn.heading, false, false, false, false)
        SetModelAsNoLongerNeeded(model)

        if not CheckEntityExists(entity) or not StableUI.IsPreviewRequestCurrent(requestId) then
            if entity and entity ~= 0 and DoesEntityExist(entity) then DeleteEntity(entity) end
            Citizen.InvokeNative(BUSY_SPINNER_OFF)
            return
        end

        MyEntity = entity
        MyEntityID = horse.id
        StableUI.HidePreviewHorse(entity)
        configurePreviewHorse(entity, horse, spawn, function(ready)
            if not StableUI.IsPreviewRequestCurrent(requestId) then
                if not DoesEntityExist(MyEntity) and not DoesEntityExist(ShopEntity) then
                    Citizen.InvokeNative(BUSY_SPINNER_OFF)
                end
                return
            end
            if ready then StableUI.RevealPreviewHorse(entity) end
            Citizen.InvokeNative(BUSY_SPINNER_OFF)
        end)
        StableUI.FramePreviewCamera(entity)
        showPreviewCamera()
        SetCachedHorse(horse.id, horse, entity)
    end)
end

local function findRosterHorse(horseId)
    local targetId = tonumber(horseId)
    if not targetId or type(MyHorsesData) ~= 'table' then return nil end
    for _, horse in ipairs(MyHorsesData) do
        if tonumber(horse.id) == targetId then return horse end
    end
    return nil
end

function PreviewActiveRosterHorse()
    if type(MyHorsesData) ~= 'table' then return false end
    for _, horse in ipairs(MyHorsesData) do
        if horse.is_selected == true then
            previewHorse(horse)
            return true
        end
    end
    return false
end

---Rebuilds the roster around one horse so the active marker, expanded actions,
---and physical preview always describe the same entry.
---@param horseId number|string
---@param persist boolean|nil
---@return boolean
function ShowSelectedHorseRoster(horseId, persist)
    local horse = findRosterHorse(horseId)
    if not horse then
        ExpandedHorseId = nil
        BuildMyHorsesPage()
        StableUI.OpenPage('my_horses')
        return false
    end

    SetSelectedHorseLocally(horse.id, persist)
    ExpandedHorseId = horse.id
    InvalidateHorseCache()
    BuildMyHorsesPage()
    StableUI.OpenPage('my_horses')
    previewHorse(horse)
    return true
end

local function addHorseActions(page, horse)
    local horseIsOut = MyHorse and MyHorse ~= 0 and DoesEntityExist(MyHorse)
    local selectedHorseIsOut = horseIsOut and tonumber(MyHorseId) == tonumber(horse.id)
    local stableActionLabel = selectedHorseIsOut and (_U('returnPrompt') or 'Return Horse')
        or (horseIsOut and (_U('switchHorse') or 'Switch to This Horse')
            or (_U('takeOutHorse') or 'Take Out Horse'))
    local actions = {
        {
            id = 'stable_action', label = stableActionLabel,
            style = selectedHorseIsOut and StableUI.Styles.danger or StableUI.Styles.success,
            run = function()
                StopRotation()
                ManageHorseAtStable(horse.id, Site)
            end,
        },
        {
            id = 'details', label = 'View Stats & Details',
            run = function()
                StopRotation()
                BuildHorseDetailPage(horse, 'my_horses')
                StableUI.OpenPage('horse_detail')
            end,
        },
        {
            id = 'tack', label = 'Open Tack Shop',
            run = function()
                StopRotation()
                BuildTackShopPage()
            end,
        },
        {
            id = 'rename', label = 'Rename Horse',
            run = function()
                OpenNamingPage({
                    origin = 'updateHorse',
                    horseId = tonumber(horse.id),
                    name = horse.name or '',
                })
            end,
        },
        {
            id = 'sell', label = 'Sell Horse',
            run = function()
                if BuildHorseSellPage(horse) then StableUI.OpenPage('horse_sell') end
            end,
        },
    }

    for _, action in ipairs(actions) do
        StableUI.AddButton(
            page,
            ('horse_%s_%s'):format(horse.id, action.id),
            '    ' .. action.label,
            'content',
            action.run,
            action.style or StableUI.Styles.text
        )
    end
end

function BuildMyHorsesPage()
    local page = StableUI.RegisterPage('my_horses')
    StableUI.AddHeader(page, _U('myHorses') or 'My Horses')

    if type(MyHorsesData) ~= 'table' or #MyHorsesData == 0 then
        StableUI.AddText(page, 'horse_roster_empty', _U('noPersonalHorse') or 'No horses. Visit the trader to purchase one.')
    else
        for _, horse in ipairs(MyHorsesData) do
            local expanded = tonumber(ExpandedHorseId) == tonumber(horse.id)
            local name = horse.name or ('Horse #' .. tostring(horse.id))
            if horse.is_selected == true then name = name .. ' (Active)' end

            StableUI.AddButton(
                page,
                'horse_select_' .. horse.id,
                expanded and (name .. ' ▼') or name,
                'content',
                function()
                    StopRotation()
                    local isCurrentlyExpanded = tonumber(ExpandedHorseId) == tonumber(horse.id)

                    if isCurrentlyExpanded then
                        ExpandedHorseId = nil
                        BuildMyHorsesPage()
                        StableUI.OpenPage('my_horses')
                        return
                    end

                    ExpandedHorseId = horse.id
                    SetSelectedHorseLocally(horse.id, true)
                    BuildMyHorsesPage()
                    StableUI.OpenPage('my_horses')
                    previewHorse(horse)
                end,
                expanded and StableUI.Styles.subheader or StableUI.Styles.button
            )

            if expanded then addHorseActions(page, horse) end
        end
    end

    StableUI.AddFooter(page)
    StableUI.AddButton(page, 'horse_roster_rotate', '↻ ' .. (_U('rotateButton') or 'Rotate'), 'footer', function()
        StableUI.ToggleRotation(-1)
    end)
    StableUI.AddButton(page, 'horse_roster_trader', _U('traderButton') or 'Trader', 'footer', function()
        StopRotation()
        BuildTraderPage()
        StableUI.OpenPage('trader')
    end)
end
