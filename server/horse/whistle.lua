-- Movement intent belongs to the character owner; execution belongs to the
-- current network simulator. No task authority comes from client coordinates.
Stables.Whistle={}
local W,F,C=Stables.Whistle,Stables.Feather,Stables.HorseController
W.pending={}
local function cancel(r)
    local ticket=r.movement
    if ticket then
        TriggerClientEvent('bcc-stables:movement:cancel',ticket.owner,{generationId=r.id,sequence=ticket.sequence})
        r.movement=nil
    end
    W.pending[r.id]=nil
end
C.CancelMovement=cancel
local function current(r)
    return C.MovementRecord(r.session)==r
end
local function issue(r,mode)
    local owner=NetworkGetEntityOwner(r.entity)
    local target=GetPlayerPed(r.session.source)
    local targetExists=DoesEntityExist(target)
    if type(owner)~='number' or owner<1 or GetPlayerRoutingBucket(owner)~=0 or (targetExists~=true and targetExists~=1) then
        return F.Error('control_unavailable','Current horse simulator or owner is unavailable.')
    end
    local targetNet=NetworkGetNetworkIdFromEntity(target)
    if type(targetNet)~='number' or targetNet<1 then return F.Error('target_unavailable','Owner network identity unavailable.') end
    local a,b=GetEntityCoords(r.entity),GetEntityCoords(target)
    if mode~='stop' and (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2>10000 then return F.Error('horse_too_far','Horse is too far away for approach/follow.') end
    cancel(r)
    r.movementSequence=(r.movementSequence or 0)+1
    local ticket={sequence=r.movementSequence,mode=mode,owner=owner,target=target,targetNet=targetNet,
        expires=GetGameTimer()+5000,endsAt=GetGameTimer()+(mode=='follow' and 30000 or 20000)}
    r.movement=ticket
    W.pending[r.id]=r
    TriggerClientEvent('bcc-stables:movement:execute',owner,{generationId=r.id,sequence=ticket.sequence})
    return F.Ok({generationId=r.id,mode=mode,networkOwner=owner})
end
function W.Request(source,p)
    if type(p)~='table' or (p.mode~='approach' and p.mode~='toggle_follow') then return F.Error('invalid_input','Whistle mode required.') end
    local session=F.RequireSession(source); if not session.ok then return session end
    local r=C.MovementRecord(session.value)
    if not r or r.whistleBusy or r.care then return F.Error('horse_not_ready','A current idle owned horse is required.') end
    local mode=p.mode=='toggle_follow' and (r.movement and r.movement.mode=='follow' and 'stop' or 'follow') or 'approach'
    if mode~='stop' and GetGameTimer()-(r.lastWhistle or -2000)<1500 then return F.Error('rate_limited','Wait before whistling again.') end
    r.whistleBusy=true
    local called,result=pcall(function()
        if mode=='approach' and C.IsDistant(session.value)==true then return C.Call(source) end
        local owned=Stables.OwnedRepository.ReadSelected(session.value); if not owned.ok then return owned end
        if not current(r) or owned.value.horseId~=r.horse.horseId or owned.value.assetId~=r.horse.assetId then
            return F.Error('stale_call','Horse ownership or session changed.')
        end
        r.lastWhistle=GetGameTimer()
        return issue(r,mode)
    end)
    r.whistleBusy=false
    return called and result or F.Error('movement_unavailable','Whistle request could not be verified.')
end
local function find(source,p)
    if type(p)~='table' or not F.IsUuid(p.generationId) or not F.IsRevision(p.sequence) or p.sequence<1 then return nil end
    -- The simulator can differ from the owning character. Resolve only an exact
    -- server-created ticket; no global entity scan or supplied target is used.
    local r=W.pending[p.generationId]
    local t=r and r.movement
    if not r or not t or t.sequence~=p.sequence or t.owner~=source or not current(r)
        or NetworkGetEntityOwner(r.entity)~=source or GetPlayerRoutingBucket(source)~=0 then return nil end
    return r,t
end
function W.Claim(source,p)
    local r,t=find(source,p)
    if not r or t.claimed or t.claiming or GetGameTimer()>t.expires then return F.Error('stale_movement','Movement ticket is unavailable.') end
    t.claiming=true
    local called,result=pcall(function()
        local owned=Stables.OwnedRepository.ReadSelected(r.session); if not owned.ok then return owned end
        if not find(source,p) or r.movement~=t or GetGameTimer()>t.expires
            or owned.value.horseId~=r.horse.horseId or owned.value.assetId~=r.horse.assetId
            or GetPlayerPed(r.session.source)~=t.target or NetworkGetNetworkIdFromEntity(t.target)~=t.targetNet then
            return F.Error('stale_movement','Movement identity changed.')
        end
        t.claimed=true
        return F.Ok({generationId=r.id,observerId=r.observerId,sequence=t.sequence,mode=t.mode,
            netId=r.netId,modelKey=r.horse.modelKey,targetNet=t.targetNet,remainingMs=math.max(0,t.endsAt-GetGameTimer())})
    end)
    t.claiming=false
    return called and result or F.Error('movement_unavailable','Movement claim could not be verified.')
end
function W.Done(source,p)
    local r,t=find(source,p)
    if not r or not t.claimed then return F.Error('stale_movement','Movement has already changed.') end
    cancel(r)
    return F.Ok(true)
end
C.MovementTick=function(r)
    local t=r.movement
    if not t or r.whistleBusy or t.claiming then return end
    local now=GetGameTimer()
    if not current(r) or GetPlayerPed(r.session.source)~=t.target
        or NetworkGetNetworkIdFromEntity(t.target)~=t.targetNet then cancel(r); return end
    local a,b=GetEntityCoords(r.entity),GetEntityCoords(t.target)
    if t.mode~='stop' and (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2>10000 then cancel(r); return end
    if (not t.claimed and now>t.expires) or now>=t.endsAt then cancel(r); return end
    if t.mode=='follow' and t.claimed and (NetworkGetEntityOwner(r.entity)~=t.owner or t.endsAt-now<=5000) then issue(r,'follow') end
end
function W.Install()
    for _,entry in ipairs({{'whistle',W.Request},{'movement_claim',W.Claim},{'movement_done',W.Done}}) do
        local action,handler=entry[1],entry[2]
        local result=F.Call('feather-core','RegisterRpc','stables.horses.call.'..action..'.v1',function(p,source) return handler(source,p) end,{
            contract=1,direction='client_to_server',requireCharacter=action=='whistle',windowMs=2000,maxCalls=4,
            maxPayloadBytes=128,maxDepth=2,maxNodes=4,validatePayload=function(p)
                if type(p)~='table' then return false end
                if action=='whistle' then
                    for key in pairs(p) do if key~='mode' then return false end end
                    return p.mode=='approach' or p.mode=='toggle_follow'
                end
                for key in pairs(p) do if key~='generationId' and key~='sequence' then return false end end
                return F.IsUuid(p.generationId) and F.IsRevision(p.sequence) and p.sequence>0
            end})
        if not result.ok then return result end
    end
    return F.Ok(true)
end
