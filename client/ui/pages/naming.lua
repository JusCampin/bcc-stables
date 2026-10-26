local namingSubmissionActive = false

local function showRoster(selectedHorseId, beforeOpen)
    FetchRosterAndAction(function()
        local function openRoster()
            ShowSelectedHorseRoster(selectedHorseId, true)
            namingSubmissionActive = false
        end

        if beforeOpen then
            beforeOpen(openRoster)
        else
            openRoster()
        end
    end, function()
        namingSubmissionActive = false
        Core.NotifyRightTip('Failed to refresh the stable roster. Please try again.', 5000)
    end)
end

local function submitPurchase(data, name)
    local request = {}
    for key, value in pairs(data) do request[key] = value end
    request.name = name

    Core.Callback.TriggerAsync('bcc-horses:ProcessHorsePurchase', function(success, result)
        if success then
            showRoster(result)
        else
            namingSubmissionActive = false
            Core.NotifyRightTip(result or 'Horse purchase failed.', 5000)
        end
    end, request)
end

local function submitRegistration(data, name)
    local request = {}
    for key, value in pairs(data) do request[key] = value end
    request.name = name

    Core.Callback.TriggerAsync('bcc-horses:RegisterHorse', function(success, result)
        if not success then
            namingSubmissionActive = false
            Core.NotifyRightTip(result or 'Horse registration failed.', 5000)
            return
        end

        RemoveTamedHorseEntity(data.mount)
        showRoster(result, function(openRoster)
            StableUI.EnterPreview(function(success)
                if success then
                    openRoster()
                else
                    namingSubmissionActive = false
                end
            end)
        end)
    end, request)
end

local function submitRename(data, name)
    Core.Callback.TriggerAsync('bcc-horses:RenameHorse', function(success)
        if not success then
            namingSubmissionActive = false
            Core.NotifyRightTip('The horse name could not be updated.', 4000)
            return
        end

        showRoster(tonumber(data.horseId), function()
            Core.NotifyRightTip(_U('renamedHorse') or 'Horse name successfully updated!', 4000)
        end)
    end, { horseId = tonumber(data.horseId), newName = name })
end

local NAMING_HANDLERS <const> = {
    buyHorse = submitPurchase,
    tameHorse = submitRegistration,
    updateHorse = submitRename,
}

--- @param data table
function BuildNamingPage(data)
    if type(data) ~= 'table' then return false end
    local handler = NAMING_HANDLERS[data.origin]
    if not handler then
        DBG:Error('Unsupported naming page origin: ' .. tostring(data.origin))
        return false
    end

    local page = StableUI.RegisterPage('naming')
    local inputValue = data.name or ''
    StableUI.AddHeader(page, _U('nameYourHorse') or 'Name Your Horse')

    page:RegisterElement('input', {
        id = 'horse_name_input',
        label = _U('nameHorse') or 'Horse Name',
        slot = 'content',
        placeholder = 'Enter a name...',
        value = inputValue,
    }, function(input)
        inputValue = input.value or ''
    end)

    StableUI.AddButton(page, 'horse_name_confirm', _U('confirmButton') or 'Confirm', 'content', function()
        if namingSubmissionActive then return end
        local name = StableUI.Trim(inputValue)
        if name == '' then
            Core.NotifyRightTip(_U('enterName') or 'Please enter a valid horse name.', 4000)
            return
        end

        namingSubmissionActive = true
        handler(data, name)
    end)

    StableUI.AddFooter(page)
    StableUI.AddButton(page, 'horse_name_back', _U('backButton') or 'Back', 'footer', function()
        if namingSubmissionActive then return end
        StopRotation()
        if data.origin == 'tameHorse' and data.mount and data.mount ~= 0 then
            BuildWildHorsePage(data.mount)
            StableUI.OpenPage('wild_horse')
        else
            BuildMyHorsesPage()
            StableUI.OpenPage('my_horses')
        end
    end)
    return true
end

--- @param data table
function OpenNamingPage(data)
    if not BuildNamingPage(data) then return end
    StableMenu:Open({
        startupPage = Pages.naming,
        menuFocus = true,
        cursorFocus = true,
        overrideMenu = true,
        allowKeys = true,
    })
end
