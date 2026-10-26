Core = exports.vorp_core:GetCore()
local bccUtils = exports['bcc-utils'].initiate()
FeatherMenu = exports['feather-menu'].initiate()
DBG = bccUtils.Debug:Get('bcc-horses', Config.development.enabled)

if DBG then
    DBG:Enable()
    DBG:Info('Stables debug initialized')
end

-- Initialize Globals
MyHorse, MyHorseId, MyEntityID = 0, nil, nil
HorseName = nil
InMenu = false
MyHorseBreed, MyHorseColor = nil, nil
ShopEntity, MyEntity = 0, 0
StableName, Site = 'Stable', nil
MaxBonding = false
MyHorseStats = {}
MyHorseAging = {}
MyHorsesData = nil
IsMyHorseActive = false
Cam = false
StableCam = nil
ExpandedHorseId = nil
Pages = {}
SelectedColorKey = nil
IsRotating = false
RotateDirection = nil
IsSpawningMountActive = false
InWrithe = false

local inverseModelHashMap = {}

---@param modelHash number
---@return string|nil
function ResolveHorseModelName(modelHash)
    return inverseModelHashMap[modelHash]
end

Horses.ModelJobLocks = {
    Models = {},
    Jobs = {}
}

-- Runs once on startup
CreateThread(function()
    if Horses.JobLocks then
        for jobName, modelList in pairs(Horses.JobLocks) do
            Horses.ModelJobLocks.Jobs[jobName] = {}

            for _, modelKey in ipairs(modelList) do
                Horses.ModelJobLocks.Jobs[jobName][modelKey] = true

                if not Horses.ModelJobLocks.Models[modelKey] then
                    Horses.ModelJobLocks.Models[modelKey] = {}
                end
                Horses.ModelJobLocks.Models[modelKey][jobName] = true
            end
        end
    end
    DBG:Info("Job restriction lookup dictionaries successfully auto-compiled!")
end)

CreateThread(function()
    while not Horses or not Horses.ModelToBreedMap do Wait(500) end

    for modelName, _ in pairs(Horses.ModelToBreedMap) do
        local rawHash = joaat(modelName)

        inverseModelHashMap[rawHash] = modelName

        if rawHash < 0 then
            inverseModelHashMap[rawHash + 4294967296] = modelName
        else
            inverseModelHashMap[rawHash - 4294967296] = modelName
        end
    end

    DBG:Info("Inverse Model Hash Map successfully auto-compiled with signed integer safety layers.")
end)
