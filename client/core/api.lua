local interactionLocks = {}

function GetActiveHorseData()
    local horse = MyHorse
    if not horse or horse == 0 or not DoesEntityExist(horse) then return nil end

    return {
        entity = horse,
        netId = NetworkGetNetworkIdFromEntity(horse),
        id = tonumber(MyHorseId),
        name = HorseName,
        breed = MyHorseBreed,
        coat = MyHorseColor,
        stats = MyHorseStats,
        aging = MyHorseAging,
        xp = tonumber(ActiveHorseXp) or 0,
        active = IsMyHorseActive == true,
    }
end

exports('GetActiveHorse', GetActiveHorseData)

exports('IsActiveHorse', function(horseId)
    local horse = GetActiveHorseData()
    return horse ~= nil and (horseId == nil or tonumber(horse.id) == tonumber(horseId))
end)

exports('ReturnActiveHorse', function()
    if type(FleeHorse) ~= 'function' then return false end
    FleeHorse()
    return true
end)

exports('AcquireInteractionLock', function(featureName)
    if type(featureName) ~= 'string' or featureName == '' then return false end
    if next(interactionLocks) ~= nil and interactionLocks[featureName] ~= true then return false end

    interactionLocks[featureName] = true
    IsInteractingWithHorse = true
    return true
end)

exports('ReleaseInteractionLock', function(featureName)
    if type(featureName) ~= 'string' or interactionLocks[featureName] ~= true then return false end

    interactionLocks[featureName] = nil
    IsInteractingWithHorse = next(interactionLocks) ~= nil
    return true
end)

function EmitHorseLifecycleEvent(eventName, data)
    TriggerEvent(eventName, data or GetActiveHorseData())
end
