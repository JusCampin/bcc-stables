-- Pure server policy validation/building. Facts and item snapshots must later
-- come from trusted services; passing these checks alone grants no authority.
Stables.CarePolicy={}
local P,S=Stables.CarePolicy,Stables
local policy,foods
local MAX=9007199254740991
local function Int(v,min,max) return type(v)=='number' and v%1==0 and v>=min and v<=max end
local function Closed(value,keys)
    if type(value)~='table' then return false end
    for k in pairs(value) do if not keys[k] then return false end end
    return true
end
function P.Start()
    policy,foods=nil,nil
    local c=StablesCareConfig
    if not Closed(c,{enabled=true,revision=true,newHorse=true,feed=true}) or type(c.enabled)~='boolean' then
        return S.Err('care_policy_invalid','Explicit server care policy required.')
    end
    if c.enabled then return S.Err('care_not_implemented','Feeding activation requires the remaining eligibility/projection/recovery gates.') end
    local f=c.feed
    if not Int(c.revision,1,4294967295) or not Closed(c.newHorse,{healthCore=true,staminaCore=true})
        or not Int(c.newHorse.healthCore,0,100) or not Int(c.newHorse.staminaCore,0,100)
        or not Closed(f,{healthGain=true,staminaGain=true,durationMs=true,maxDistance=true,observationTtlMs=true,items=true})
        or not Int(f.healthGain,0,100) or not Int(f.staminaGain,0,100) or f.healthGain+f.staminaGain==0
        or not Int(f.durationMs,1000,15000) or type(f.maxDistance)~='number' or f.maxDistance~=f.maxDistance
        or f.maxDistance<0.5 or f.maxDistance>3 or not Int(f.observationTtlMs,100,1500)
        or type(f.items)~='table' or #f.items<1 or #f.items>16 then return S.Err('care_policy_invalid','Bounded care policy values required.') end
    local allowed={}; local count=0
    for i,name in pairs(f.items) do
        if not Int(i,1,#f.items) or type(name)~='string' or #name>100 or not name:match('^[a-z0-9_]+$') or allowed[name] then
            return S.Err('care_policy_invalid','Distinct established food names in a dense array required.')
        end
        allowed[name]=true; count=count+1
    end
    if count~=#f.items then return S.Err('care_policy_invalid','Dense food array required.') end
    policy,foods=S.Copy(c),allowed
    return S.Ok({ok=true,enabled=false,revision=c.revision,foodEntries=count,feedHealth=f.healthGain,feedStamina=f.staminaGain,
        existingHorses='uninitialized',activeCareAvailable=false})
end
function P.NewHorseSeed(horseId)
    if not policy then return S.Err('care_policy_unavailable','Care policy is unavailable.') end
    if not S.Operations.IsUuid(horseId) or horseId~=horseId:lower() then return S.Err('invalid_input','Canonical horse UUID required.') end
    return S.Ok({horseId=horseId,healthCore=policy.newHorse.healthCore,staminaCore=policy.newHorse.staminaCore,revision=0,policyRevision=policy.revision})
end
function P.BuildOperation(ids,item,condition)
    if not policy then return S.Err('care_policy_unavailable','Care policy is unavailable.') end
    if not Closed(ids,{operationId=true,characterId=true,horseId=true}) or type(item)~='table' or type(item.definition)~='table' then
        return S.Err('care_item_invalid','Exact server-resolved item/horse identities required.')
    end
    local d=item.definition
    if not foods[d.name] or d.type~='item_item' or d.instanceMode~='stack' then return S.Err('care_food_unavailable','Configured ordinary food instance required.') end
    return S.CareOperations.New({operationId=ids.operationId,characterId=ids.characterId,horseId=ids.horseId,
        instanceId=item.id,definitionId=d.id,itemRevision=item.revision,itemName=d.name,policyRevision=policy.revision,
        healthGain=policy.feed.healthGain,staminaGain=policy.feed.staminaGain},condition)
end
function P.CheckActiveFacts(facts)
    if not policy then return S.Err('care_policy_unavailable','Care policy is unavailable.') end
    local required={'sessionCurrent','sameHorse','sameOwner','defaultRoute','ownerAlive','horseAlive','unoccupied','notLeading','movementIdle'}
    local allowed={distance=true,observedAt=true,now=true}; for _,k in ipairs(required) do allowed[k]=true end
    if not Closed(facts,allowed) then return S.Err('care_eligibility_unknown','Complete server/simulator observations required.') end
    for _,k in ipairs(required) do if facts[k]~=true then return S.Err('care_ineligible','Care eligibility is false or unknown.',{gate=k}) end end
    if not Int(facts.now,0,MAX) or not Int(facts.observedAt,0,MAX) or facts.now<facts.observedAt
        or facts.now-facts.observedAt>policy.feed.observationTtlMs then return S.Err('care_observation_stale','Fresh observations required before consumption.') end
    if type(facts.distance)~='number' or facts.distance~=facts.distance or facts.distance<0 or facts.distance>policy.feed.maxDistance then
        return S.Err('care_too_far','Stay beside your horse for care.')
    end
    return S.Ok({eligible=true,policyRevision=policy.revision,durationMs=policy.feed.durationMs})
end
function P.ObservationRules()
    if not policy then return S.Err('care_policy_unavailable','Care policy is unavailable.') end
    return S.Ok({maxDistance=policy.feed.maxDistance,ttlMs=policy.feed.observationTtlMs})
end
