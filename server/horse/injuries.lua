-- Biological state belongs to Stables. Network ownership only selects the
-- simulator that observes damage; Inventory's care receipt authorizes revival.
Stables.Injuries={}
local I,F,H=Stables.Injuries,Stables.Feather,Stables.HorseController
local live={}
function I.Enabled() return Config.death and Config.death.enabled==true end
function I.Blocked(r) return r and (r.injuryPending or r.horse.biologicalState=='downed') end
function I.Forget(r) live[r.id]=nil end
function I.Changed(id,revision)
    for _,r in pairs(live) do if r.horse.horseId==id then r.injuryDirty=true;r.recoveryRevision=revision end end
end
local function current(r) return H.MovementRecord(r.session)==r end
function I.Down(r,authorize)
    if not I.Enabled() or not authorize() then return F.Error('injury_stale','Horse injury observation expired.') end
    if r.horse.biologicalState=='downed' and not r.injuryPending then return F.Ok(true) end
    if r.injuryWriting then return F.Error('injury_pending','Horse injury is awaiting persistence.') end
    r.injuryWriting=true
    r.recovered=nil
    r.injuryPending=true
    if r.care then r.care.cancelled=true end
    if H.CancelMovement then H.CancelMovement(r) end
    if Stables.WorldCare then Stables.WorldCare.Stop(r,true) end
    local row
    local ok,committed=pcall(DB.transaction,function(tx)
        if not authorize() then return false end
        if not tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',r.session.characterId) then return false end
        row=tx.one('SELECT owner_character_id,biological_state,availability,revision FROM fs_horses WHERE horse_id=? FOR UPDATE',r.horse.horseId)
        local slot=tx.one('SELECT generation_id FROM fs_call_slots WHERE character_id=? FOR UPDATE',r.session.characterId)
        if not row or row.owner_character_id~=r.session.characterId or row.availability~='active'
            or not slot or slot.generation_id~=r.id then return false end
        if row.biological_state=='alive' then
            if tx.exec("UPDATE fs_horses SET biological_state='downed',revision=revision+1 WHERE horse_id=? AND revision=? AND biological_state='alive'",
                r.horse.horseId,tonumber(row.revision))~=1 then return false end
            row.biological_state,row.revision='downed',tonumber(row.revision)+1
        elseif row.biological_state~='downed' then return false end
        return authorize()
    end)
    r.injuryWriting=nil
    if not ok or committed~=true then return F.Error('injury_pending','Horse injury is awaiting persistence.') end
    r.horse.biologicalState,r.horse.projectionRevision='downed',tonumber(row.revision)
    r.injuryPending=nil;r.injurySignature=nil
    return F.Ok(true)
end
function I.Tick(r)
    if not I.Enabled() or not current(r) then return end
    live[r.id]=r
    if r.injuryDirty then
        local row=DB.one('SELECT biological_state,revision FROM fs_horses WHERE horse_id=? AND owner_character_id=?',r.horse.horseId,r.session.characterId)
        if not row or (row.biological_state~='alive' and row.biological_state~='downed') or not current(r) then return end
        if r.horse.biologicalState=='downed' and row.biological_state=='alive' then r.recovered=r.recoveryRevision end
        r.horse.biologicalState,r.horse.projectionRevision=row.biological_state,tonumber(row.revision)
        r.injuryDirty=nil;r.injurySignature=nil
    end
    if r.injuryPending and GetGameTimer()>=(r.injuryRetryAt or 0) then
        r.injuryRetryAt=GetGameTimer()+3000
        I.Down(r,function() return current(r) end)
    end
    local owner=NetworkGetEntityOwner(r.entity)
    if type(owner)~='number' or owner<1 then return end
    local mode=I.Blocked(r) and 'downed' or 'alive'
    if mode=='downed' and r.care and r.care.action=='revive' and r.care.started==true and not r.care.cancelled then mode='reviving' end
    local signature=owner..':'..mode..':'..tostring(r.horse.projectionRevision)
    if r.injurySignature==signature then return end
    r.injurySignature=signature;r.injurySequence=(r.injurySequence or 0)+1;r.injuryOwner=owner
    local p={generationId=r.id,observerId=r.observerId,netId=r.netId,modelKey=r.horse.modelKey,
        state=mode,revision=r.horse.projectionRevision,sequence=r.injurySequence,recovered=r.recovered}
    TriggerClientEvent('bcc-stables:injury:state',owner,p)
    if owner~=r.session.source then TriggerClientEvent('bcc-stables:injury:state',r.session.source,p) end
end
function I.Report(source,p)
    local r=live[p.generationId]
    if not r or not current(r) or r.observerId~=p.observerId or r.injurySequence~=p.sequence
        or r.injuryOwner~=source or NetworkGetEntityOwner(r.entity)~=source then return F.Error('injury_stale','Horse simulator changed.') end
    if r.care and r.care.action=='revive' and r.care.started and not r.care.cancelled then return F.Ok(false) end
    return I.Down(r,function() return current(r) and NetworkGetEntityOwner(r.entity)==source end)
end
function I.Start()
    if not I.Enabled() then return F.Ok(true) end
    if Config.death.permanentDeath or Config.death.writheEnabled~=true or Config.death.persistentWrithe~=true then
        return F.Error('invalid_injury_policy','This release requires persistent, recoverable injuries; permanent death is unsupported.')
    end
    for _,key in ipairs({'reviveHealth','reviveStamina'}) do
        if not F.IsRevision(Config.death[key]) or Config.death[key]>100 then return F.Error('invalid_injury_policy','Invalid revival core benefit.') end
    end
    return F.Call('feather-core','RegisterRpc','stables.horses.call.injury.v1',function(p,source) return I.Report(source,p) end,{
        contract=1,direction='client_to_server',requireCharacter=false,windowMs=2000,maxCalls=2,maxPayloadBytes=192,maxDepth=2,maxNodes=5,
        validatePayload=function(p)
            if type(p)~='table' then return false end
            for k in pairs(p) do if k~='generationId' and k~='observerId' and k~='sequence' then return false end end
            return F.IsUuid(p.generationId) and F.IsUuid(p.observerId) and F.IsRevision(p.sequence) and p.sequence>0
        end})
end
