local previewSessions = {}

local function restorePlayerBucket(src)
    local previousBucket = previewSessions[src]
    if previousBucket == nil then return end

    previewSessions[src] = nil
    SetPlayerRoutingBucket(src, previousBucket)

    SetTimeout(250, function()
        if not GetPlayerName(src) then return end
        local horseData = Player(src).state.HorseData
        local netId = horseData and tonumber(horseData.MyHorse)
        if netId and netId ~= 0 then
            TriggerClientEvent('bcc-horses:UpdateMyHorseEntity', src, netId)
        end
    end)
end

Core.Callback.Register('bcc-horses:EnterPreviewInstance', function(source, cb)
    local src = source
    if previewSessions[src] == nil then
        previewSessions[src] = GetPlayerRoutingBucket(src)
    end

    local bucketBase = math.max(1, math.floor(tonumber(Config.preview.bucketBase) or 7000))
    SetPlayerRoutingBucket(src, bucketBase + src)
    cb(true)
end)

RegisterNetEvent('bcc-horses:ExitPreviewInstance', function()
    restorePlayerBucket(source)
end)

AddEventHandler('playerDropped', function()
    previewSessions[source] = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for src in pairs(previewSessions) do restorePlayerBucket(src) end
end)
