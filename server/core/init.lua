Core = exports.vorp_core:GetCore()
BccUtils = exports['bcc-utils'].initiate()
DBG = BccUtils.Debug:Get('bcc-horses', Config.development.enabled)

if DBG then
    DBG:Enable()
    DBG:Info('Stables debug initialized')
end

-- Initiate Globals
HorseXpCache = {}
InverseModelHashMap = {}

BccUtils.Versioner.checkFile(GetCurrentResourceName(), 'https://github.com/BryceCanyonCounty/bcc-horses')
