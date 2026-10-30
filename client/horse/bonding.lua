-- Absolute saved XP, current native simulator only. No client XP award API,
-- permanent frame loop or saved-condition defaults.
Stables.HorseBonding={}
local G,C,H=Stables.HorseBonding,Stables.Client,Stables.Horse
local thresholds={}
local applied,order={},{}
local attributes={health=0,stamina=1,handling=4,acceleration=6,speed=5}
local function yes(value) return value==true or value==1 end
local function exists(entity) return entity and entity~=0 and yes(DoesEntityExist(entity)) end
local function alive(entity) return exists(entity) and not yes(IsEntityDead(entity)) and not yes(IsPedDeadOrDying(entity,true)) end
function G.Describe(model,xp)
    local hash=type(model)=='string' and GetHashKey(model) or model
    local ranks=thresholds[hash]
    if not ranks then
        ranks={}
        for rank=1,4 do
            local n=tonumber(Citizen.InvokeNative(0x94A7F191DB49A44D,hash,7,rank))
            if n and n>0 and n%1==0 then ranks[rank]=n end
        end
        if ranks[1] and ranks[2] and ranks[3] and ranks[4] then thresholds[hash]=ranks end
    end
    local level=0
    for rank=1,4 do if ranks[rank] and xp>=ranks[rank] then level=rank end end
    return level,ranks[level+1]
end
function G.Apply(r,value)
    if not Config.bonding or not Config.bonding.enabled or type(value)~='table' or type(value.xp)~='number'
        or value.xp<0 or value.xp>1000000000 or value.xp%1~=0 or not exists(r.entity)
        or not yes(NetworkHasControlOfEntity(r.entity)) then return false end
    local level=G.Describe(r.modelKey,value.xp)
    local training=Config.bonding.statRewardsEnabled and value.training
    local key,signature,health,stamina
    if training then
        if type(training.ranks)~='table' then return false end
        signature=tostring(level)
        for _,stat in ipairs({'health','stamina','handling','acceleration','speed'}) do
            local rank=training.ranks[stat]
            if type(rank)~='number' or rank%1~=0 or rank<0 or rank>9 then return false end
            signature=signature..':'..rank
        end
        key=tostring(Entity(r.entity).state.bccStablesGeneration)..':'..r.entity
        if applied[key]~=signature then
            health=Citizen.InvokeNative(0x36731AC041289BB1,r.entity,0,Citizen.ResultAsInteger())
            stamina=Citizen.InvokeNative(0x36731AC041289BB1,r.entity,1,Citizen.ResultAsInteger())
            for _,core in ipairs({health,stamina}) do
                if type(core)~='number' or core%1~=0 or core<0 or core>100 then return false end
            end
            if health==nil or stamina==nil then return false end
        end
    end
    Citizen.InvokeNative(0x09A59688C26D88DF,r.entity,7,value.xp) -- SetAttributePoints: bonding only.
    Citizen.InvokeNative(0x1913FE4CBF41C463,r.entity,113,level>=2) -- DisableShockingEvents.
    Citizen.InvokeNative(0x1913FE4CBF41C463,r.entity,312,level>=3) -- DisableHorseGunshotFleeResponse.
    if health~=nil then
        for stat,attribute in pairs(attributes) do Citizen.InvokeNative(0x5DA12E025D47D4E5,r.entity,attribute,training.ranks[stat]) end
        Citizen.InvokeNative(0xC6258F41D86676E0,r.entity,0,health)
        Citizen.InvokeNative(0xC6258F41D86676E0,r.entity,1,stamina)
        if not applied[key] then order[#order+1]=key end
        applied[key]=signature
        if #order>128 then applied[table.remove(order,1)]=nil end
    end
    return true,level
end
local function entity(p)
    if type(p)~='table' or not C.Uuid(p.generationId) or not C.Uuid(p.observerId) or type(p.modelKey)~='string'
        or type(p.netId)~='number' or p.netId<1 or p.netId%1~=0 then return nil end
    local e=NetworkGetEntityFromNetworkId(p.netId)
    if not exists(e) or NetworkGetNetworkIdFromEntity(e)~=p.netId or GetEntityModel(e)~=GetHashKey(p.modelKey)
        or Entity(e).state.bccStablesGeneration~=p.generationId or Entity(e).state.bccStablesObserver~=p.observerId then return nil end
    return e
end
RegisterNetEvent('bcc-stables:bonding:apply',function(p)
    if source~=65535 then return end
    CreateThread(function()
        local e=entity(p);local deadline=GetGameTimer()+1000
        while e and not yes(NetworkHasControlOfEntity(e)) and GetGameTimer()<deadline do Wait(50);e=entity(p) end
        if e then G.Apply({entity=e,modelKey=p.modelKey},p.bonding) end
    end)
end)
RegisterNetEvent('bcc-stables:bonding:observe',function(p)
    if source~=65535 or not Config.bonding or not Config.bonding.enabled or type(p)~='table'
        or type(p.sequence)~='number' or p.sequence<1 or type(p.targetNet)~='number' or p.targetNet<1 then return end
    CreateThread(function()
        local e=entity(p)
        if not e or not yes(NetworkHasControlOfEntity(e)) then return end
        local owner=NetworkGetEntityFromNetworkId(p.targetNet)
        if not exists(owner) or NetworkGetNetworkIdFromEntity(owner)~=p.targetNet then return end
        G.Apply({entity=e,modelKey=p.modelKey},p.bonding)
        local mode='idle'
        local living=alive(e) and alive(owner)
        if living and yes(IsPedOnMount(owner)) and GetMount(owner)==e and GetRiderOfMount(e,false)==owner then mode='riding'
        elseif living and yes(Citizen.InvokeNative(0xEFC4303DDC6E60D3,owner))
            and Citizen.InvokeNative(0xED1F514AF4732258,owner,Citizen.ResultAsInteger())==e
            and GetRiderOfMount(e,false)==0 and GetRiderOfMount(e,true)==0 then mode='leading' end
        if entity(p)==e and yes(NetworkHasControlOfEntity(e)) then
            C.Rpc('bonding_sample',{generationId=p.generationId,sequence=p.sequence,mode=mode,alive=living})
        end
    end)
end)
RegisterNetEvent('bcc-stables:bonding:earned',function(p)
    if source~=65535 or not Config.bonding or type(p)~='table'
        or type(p.amount)~='number' or p.amount<1 or p.reason~='riding' and p.reason~='leading' then return end
    local r=H.GetActive()
    if r and r.generationId==p.generationId and r.id==p.horseId then
        if Config.bonding.showXpMessage~=false then C.Message(C.Text('menu_bondingEarned',p.amount,C.Text('menu_bondingReason_'..p.reason),p.xp)) end
        G.NotifyLevel(p)
    end
end)
function G.NotifyLevel(value)
    if Config.bonding and Config.bonding.showLevelUpMessage~=false and value.training and (value.levelsGained or 0)>0 then
        C.Message(C.Text('menu_trainingEarned',value.training.level))
    end
end
