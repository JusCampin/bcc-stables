-- Owner intent, current simulator observations, server-timed restoration.
-- No idle SQL polling or client-provided XP/benefit totals.
Stables.WorldCare={}
local W,F,H=Stables.WorldCare,Stables.Feather,Stables.HorseController
local pending,exits={},{}
local function bad(code) return F.Error(code or 'world_care_unavailable','World care is unavailable.') end
local function enabled() return Config.worldCare and Config.worldCare.enabled==true end
local function near(r)
    local a,b=GetEntityCoords(r.entity),GetEntityCoords(GetPlayerPed(r.session.source))
    if not a or not b then return false end
    local d=(a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2
    return d==d and d<=12.25
end
local function current(r,t)
    if Stables.Injuries and Stables.Injuries.Blocked(r) then return false end
    return enabled() and r.worldCare==t and H.MovementRecord(r.session)==r and not r.care and not r.flee and not r.movement
        and NetworkGetEntityOwner(r.entity)==t.owner and near(r)
end
local function packet(r,t)
    return {generationId=r.id,observerId=r.observerId,netId=r.netId,modelKey=r.horse.modelKey,action=t.action,sequence=t.sequence,
        targetNet=NetworkGetNetworkIdFromEntity(GetPlayerPed(r.session.source))}
end
function W.Stop(r,immediate)
    local t=r.worldCare;if not t then exits[r.id]=nil;r.worldExit=nil;return end
    r.worldCare=nil;pending[r.id]=nil
    if not r.cancelled and not immediate then t.expires=GetGameTimer()+30000;r.worldExit=t;exits[r.id]=r end
    local p=packet(r,t);p.immediate=immediate==true
    TriggerClientEvent('bcc-stables:world:stop',t.owner,p)
    local owner=NetworkGetEntityOwner(r.entity)
    if owner and owner>0 and owner~=t.owner then TriggerClientEvent('bcc-stables:world:stop',owner,p) end
end
function W.ExitResult(source,p)
    local r=exits[p.generationId];local t=r and r.worldExit
    if not t or p.sequence~=t.sequence or GetGameTimer()>t.expires or H.MovementRecord(r.session)~=r
        or NetworkGetEntityOwner(r.entity)~=source then return bad('care_stale') end
    exits[r.id]=nil;r.worldExit=nil
    TriggerClientEvent('bcc-stables:world:ended',r.session.source,{generationId=r.id,sequence=t.sequence,completed=true,mountAllowed=not t.whistleMode})
    if t.whistleMode and not r.worldCare then return Stables.Whistle.Request(r.session.source,{mode=t.whistleMode}) end
    return F.Ok(true)
end
function W.Request(source,p)
    local s=F.RequireSession(source);if not s.ok then return s end
    local r=H.MovementRecord(s.value);if not r then return bad('care_not_ready') end
    if r.training then return bad('training_busy') end
    if Stables.Injuries and Stables.Injuries.Blocked(r) then return bad('horse_downed') end
    if p.action=='stop' then
        if r.worldCare then W.Stop(r) end
        if r.worldExit then r.worldExit.whistleMode=nil end
        return F.Ok(true)
    end
    if not enabled() or not Config.worldCare.actions[p.action] then return bad() end
    if r.worldCare or r.worldExit or r.care or r.flee or r.movement or not near(r) then return bad('care_busy') end
    local owned=Stables.OwnedRepository.ReadSelected(s.value)
    if not owned.ok or owned.value.horseId~=r.horse.horseId or owned.value.assetId~=r.horse.assetId then return bad('care_stale') end
    local policy=Config.worldCare.actions[p.action]
    if not owned.value.condition then return bad('care_uninitialized') end
    if not owned.value.bonding or owned.value.bonding.xp<policy.minimumXp then return bad('world_care_locked') end
    local owner=NetworkGetEntityOwner(r.entity)
    if type(owner)~='number' or owner<1 or GetPlayerRoutingBucket(owner)~=0 or H.MovementRecord(s.value)~=r then return bad() end
    r.worldSequence=(r.worldSequence or 0)+1
    local t={action=p.action,sequence=r.worldSequence,owner=owner,nextAt=GetGameTimer(),expires=GetGameTimer()+10000,
        effect={health=policy.health,stamina=policy.stamina,xp=p.action=='drink' and Config.worldCare.drinkXp or 0},
        interval=policy.seconds*1000,position=GetEntityCoords(r.entity),startUntil=GetGameTimer()+10000,entryUntil=GetGameTimer()+60000}
    r.worldCare=t;pending[r.id]=r
    TriggerClientEvent('bcc-stables:world:owner_state',r.session.source,{generationId=r.id,sequence=t.sequence,action=t.action})
    TriggerClientEvent('bcc-stables:world:start',owner,packet(r,t))
    return F.Ok(true)
end
function W.Result(source,p)
    local r=pending[p.generationId];local t=r and r.worldCare;local sample=t and t.sample
    if not sample or sample.sequence~=p.sequence or sample.expires<GetGameTimer() or source~=t.owner or not current(r,t) then return bad('care_stale') end
    t.sample=nil -- Consume before any SQL/yield. A response cannot award twice.
    if p.eligible~=true or (t.action=='drink' and p.water~=true) then W.Stop(r);return F.Ok(false) end
    if p.playing~=true then
        if not t.readyAt and GetGameTimer()<=t.startUntil then t.expires=t.startUntil;return F.Ok(true) end
        W.Stop(r);return F.Ok(false)
    end
    local pos=GetEntityCoords(r.entity);local start=t.position
    local maximum=t.readyAt and 2.25 or 16 -- Entry clips can shift the horse's root.
    if (pos.x-start.x)^2+(pos.y-start.y)^2+(pos.z-start.z)^2>maximum then W.Stop(r);return F.Ok(false) end
    t.expires=GetGameTimer()+4000
    if not p.loop then
        if GetGameTimer()>t.entryUntil then W.Stop(r);return F.Ok(false) end
        return F.Ok(true) -- Entry animations never count as restoration time.
    end
    if not t.readyAt then t.position=pos;t.readyAt=GetGameTimer();t.rewardAt=t.readyAt+t.interval end
    if GetGameTimer()<t.rewardAt then return F.Ok(true) end
    if t.action=='wallow' then W.Stop(r);return F.Ok(true) end
    if t.full and p.healthCore==100 and p.staminaCore==100 then t.rewardAt=GetGameTimer()+t.interval;return F.Ok(true) end
    t.rewardAt=GetGameTimer()+t.interval;t.working=true
    local observation={healthCore=p.healthCore,staminaCore=p.staminaCore,appliedRevision=p.appliedRevision,owner=source,observedAt=GetGameTimer()}
    local ok,result=pcall(Stables.Feeding.WorldBenefit,r.session,r,observation,t.effect,function() return current(r,t) end)
    t.working=false
    if not ok or not result.ok then W.Stop(r);return bad('care_pending') end
    local c=result.value.condition;t.full=result.value.full or (c and c.healthCore==100 and c.staminaCore==100)
    TriggerClientEvent('bcc-stables:world:reward',r.session.source,{generationId=r.id,horseId=r.horse.horseId,bonding=result.value.bonding})
    if t.action=='drink' then W.Stop(r) end
    return F.Ok(true)
end
function W.Tick(r)
    if r.worldExit and GetGameTimer()>r.worldExit.expires then
        local t=r.worldExit;r.worldExit=nil;exits[r.id]=nil
        TriggerClientEvent('bcc-stables:world:ended',r.session.source,{generationId=r.id,sequence=t.sequence,completed=false})
    end
    local t=r.worldCare;if not t or t.working then return end
    if not current(r,t) or GetGameTimer()>t.expires then W.Stop(r);return end
    if GetGameTimer()<t.nextAt then return end
    t.nextAt=GetGameTimer()+2000
    if t.sample then W.Stop(r);return end
    t.sample={sequence=(r.worldSample or 0)+1,expires=GetGameTimer()+1500};r.worldSample=t.sample.sequence
    local p=packet(r,t);p.sample=t.sample.sequence
    TriggerClientEvent('bcc-stables:world:sample',t.owner,p)
end
function W.Start()
    if not enabled() then return F.Ok(true) end
    if not Stables.Bonding.Enabled() then return bad('bonding_required') end
    if not pcall(DB.query,'SELECT last_drink_at FROM fs_horse_bonding LIMIT 0') then return bad('world_care_schema_required') end
    if not F.IsRevision(Config.worldCare.drinkXp) or Config.worldCare.drinkXp>1000000 then return bad('invalid_world_care_config') end
    for _,action in ipairs({'drink','rest','sleep','wallow'}) do
        local p=Config.worldCare.actions and Config.worldCare.actions[action]
        if type(p)~='table' or not F.IsRevision(p.minimumXp) or not F.IsRevision(p.seconds) or p.seconds<5 or p.seconds>60
            or not F.IsRevision(p.health) or p.health>100 or not F.IsRevision(p.stamina) or p.stamina>100 then return bad('invalid_world_care_config') end
    end
    for _,action in ipairs({'world_care','world_sample','world_exit'}) do
        local sample=action=='world_sample';local exiting=action=='world_exit'
        local installed=F.Call('feather-core','RegisterRpc','stables.horses.call.'..action..'.v1',function(p,source)
            if exiting then return W.ExitResult(source,p) end
            return sample and W.Result(source,p) or W.Request(source,p)
        end,{contract=1,direction='client_to_server',requireCharacter=not sample and not exiting,windowMs=2000,maxCalls=8,maxPayloadBytes=256,maxDepth=1,maxNodes=12,
            validatePayload=function(p)
                if type(p)~='table' then return false end
                if exiting then
                    for key in pairs(p) do if key~='generationId' and key~='sequence' then return false end end
                    return F.IsUuid(p.generationId) and F.IsRevision(p.sequence) and p.sequence>0
                end
                if not sample then
                    for key in pairs(p) do if key~='action' then return false end end
                    return p.action=='stop' or p.action=='drink' or p.action=='rest' or p.action=='sleep' or p.action=='wallow'
                end
                local fields={generationId=true,sequence=true,eligible=true,playing=true,water=true,loop=true,healthCore=true,staminaCore=true,appliedRevision=true}
                for key in pairs(p) do if not fields[key] then return false end end
                return F.IsUuid(p.generationId) and F.IsRevision(p.sequence) and p.sequence>0 and type(p.eligible)=='boolean'
                    and type(p.playing)=='boolean' and type(p.water)=='boolean' and type(p.loop)=='boolean' and F.IsRevision(p.healthCore) and p.healthCore<=100
                    and F.IsRevision(p.staminaCore) and p.staminaCore<=100 and F.IsRevision(p.appliedRevision)
            end})
        if not installed.ok then return installed end
    end
    return F.Ok(true)
end
