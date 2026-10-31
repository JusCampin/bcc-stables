Stables.HorseInjuries={}
local I,C=Stables.HorseInjuries,Stables.Client
local states={}
local function yes(v) return v==true or v==1 end
function I.Enabled() return Config.death and Config.death.enabled==true end
function I.Injured(e)
    return yes(IsEntityDead(e)) or GetEntityHealth(e)<=0 or yes(Citizen.InvokeNative(0xDEB6D52126E7D640,e))
end
function I.Blocked(id) local p=states[id];return p and (p.state~='alive' or p.pending) end
local function entity(p)
    local e=NetworkGetEntityFromNetworkId(p.netId)
    if not e or e==0 or not yes(DoesEntityExist(e)) or NetworkGetNetworkIdFromEntity(e)~=p.netId
        or GetEntityModel(e)~=GetHashKey(p.modelKey) or Entity(e).state.bccStablesGeneration~=p.generationId
        or Entity(e).state.bccStablesObserver~=p.observerId then return nil end
    return e
end
local function resurrect(e)
    local cores={}
    for index=0,1 do cores[index]=Citizen.InvokeNative(0x36731AC041289BB1,e,index,Citizen.ResultAsInteger()) end
    Citizen.InvokeNative(0x71BC8E838B9C6035,e)
    for index=0,1 do Citizen.InvokeNative(0xC6258F41D86676E0,e,index,cores[index]) end
end
function I.Forget(id) states[id]=nil end
function I.Input(r)
    local p=states[r.generationId]
    if not p or p.state~='downed' or p.requesting then return end
    -- Match original Horses' INPUT_REVIVE handling. Limit it to the engine's
    -- actual revive target/prompt; a key press beside another horse cannot act.
    if not yes(Citizen.InvokeNative(0x756C7B4C43DF0422,false))
        or Citizen.InvokeNative(0x351F74ED6177EBE7,Citizen.ResultAsInteger())~=r.entity then return end
    local control=GetHashKey('INPUT_REVIVE')
    if not yes(Citizen.InvokeNative(0x91AEF906BCA88877,0,control)) and not IsControlJustPressed(0,control) then return end
    p.requesting=true
    local result=C.Rpc('revive',{generationId=r.generationId})
    p.requesting=nil
    if not result.ok then (C.Notify or C.Message)(C.Text('menu_revivePending')) end
end
function I.Bind(r,s)
    if not I.Enabled() then return end
    local previous=states[r.generationId]
    if not previous then
        states[r.generationId]={generationId=r.generationId,observerId=r.observerId,netId=r.netId,
            modelKey=r.modelKey,state=s or 'alive',sequence=0,revision=0}
    end
end
RegisterNetEvent('bcc-stables:injury:state',function(p)
    if source~=65535 or not I.Enabled() or type(p)~='table' or not C.Uuid(p.generationId) or not C.Uuid(p.observerId)
        or (p.state~='alive' and p.state~='downed' and p.state~='reviving') or type(p.sequence)~='number'
        or type(p.revision)~='number' or type(p.netId)~='number' or type(p.modelKey)~='string' then return end
    local old=states[p.generationId]
    if old and old.sequence>=p.sequence then return end
    if old then p.pending=old.pending and p.state=='alive' and old.revision==p.revision end
    states[p.generationId]=p
    if p.state=='downed' and (not old or old.state=='alive') then
        local r=Stables.Horse.GetActive()
        if r and r.generationId==p.generationId then (C.Notify or C.Message)(C.Text('menu_horseDowned')) end
    end
end)
-- The existing server observer sends only state/owner changes. Native sampling
-- is local to streamed horses; there is no SQL or network polling while idle.
CreateThread(function()
    if not I.Enabled() then return end
    while true do
        Wait(500)
        for id,p in pairs(states) do
            local e=entity(p)
            if not e then
                -- Keep a small owner-side record while the horse streams out.
                local current=Stables.Horse.GetActive()
                if not current or current.generationId~=id then states[id]=nil end
            elseif yes(NetworkHasControlOfEntity(e)) then
                local r=Stables.Horse.GetActive()
                if not r or r.generationId~=id or r.entity==e and r.bound~=false then
                    local marker=Entity(e).state.bccStablesInjury
                    if p.state=='alive' then
                        if type(p.recovered)=='number' and marker==p.recovered then
                            -- TaskReviveTarget owns the stand-up transition. Do
                            -- not resurrect/reset an already living actor at
                            -- commit; that cuts the animation and snaps its pose.
                            if yes(IsEntityDead(e)) then resurrect(e)
                            elseif yes(Citizen.InvokeNative(0xDEB6D52126E7D640,e)) then ClearPedTasks(e) end
                            SetEntityHealth(e,GetEntityMaxHealth(e))
                            Citizen.InvokeNative(0x1913FE4CBF41C463,e,136,false)
                            Citizen.InvokeNative(0x1913FE4CBF41C463,e,297,true)
                            Entity(e).state:set('bccStablesInjury',nil,true)
                            p.pending=nil
                        elseif I.Injured(e) or p.pending then
                            p.pending=true;SetEntityInvincible(e,true)
                            Citizen.InvokeNative(0x1913FE4CBF41C463,e,136,true)
                            if p.sequence>0 and GetGameTimer()>=(p.retryAt or 0) then
                                p.retryAt=GetGameTimer()+3000
                                CreateThread(function() C.Rpc('injury',{generationId=id,observerId=p.observerId,sequence=p.sequence}) end)
                            end
                        end
                        if not p.pending then SetEntityInvincible(e,false) end
                    else
                        SetEntityInvincible(e,true)
                        Citizen.InvokeNative(0x1913FE4CBF41C463,e,136,true)
                        Citizen.InvokeNative(0x1913FE4CBF41C463,e,297,false)
                        if Stables.HorseWorldCare and Stables.HorseWorldCare.CancelForInjury then Stables.HorseWorldCare.CancelForInjury(id) end
                        if p.state=='downed' and (not marker or not yes(Citizen.InvokeNative(0xDEB6D52126E7D640,e))) then
                            ClearPedTasksImmediately(e,false,false)
                            if yes(IsEntityDead(e)) then resurrect(e) end
                            SetEntityHealth(e,math.min(150,GetEntityMaxHealth(e)))
                            Citizen.InvokeNative(0x8C038A39C4A4B6D6,e,0,0)
                            Citizen.InvokeNative(0x925A160133003AC6,e,true)
                        end
                        if p.sequence>0 then Entity(e).state:set('bccStablesInjury',p.revision,true) end
                    end
                end
            end
        end
    end
end)
