-- One saved total per horse. The existing controller tick samples only live
-- bound horses; SQL is used at rewards, dirty care refresh and owned reads.
Stables.Bonding={}
local G,F,R,H=Stables.Bonding,Stables.Feather,Stables.OwnedRepository,Stables.HorseController
local installed=false
local pending,dirty={},{}
local MAX_XP=1000000000
local function bad(code) return F.Error(code or 'bonding_unavailable','Saved bonding is unavailable.') end
function G.Enabled() return Config.bonding and Config.bonding.enabled==true end
function G.Reward(reason)
    local value=Config.bonding and Config.bonding.xpRewards and Config.bonding.xpRewards[reason]
    return F.IsRevision(value) and value<=1000000 and value or 0
end
function G.StatRewardsEnabled() return G.Enabled() and Config.bonding.statRewardsEnabled==true end
local STAT_KEYS={'health','stamina','handling','acceleration','speed'}
local function validBase(base)
    if type(base)~='table' then return false end
    local count=0
    for key,value in pairs(base) do
        local known=false;for _,stat in ipairs(STAT_KEYS) do if key==stat then known=true end end
        if not known or not F.IsRevision(value) or value>9 then return false end
        count=count+1
    end
    return count==5
end
local function ranks(base,level,bonus)
    local result,capacity={},0
    for _,key in ipairs(STAT_KEYS) do result[key]=base[key];capacity=capacity+math.min(bonus,9-base[key]) end
    -- Work is bounded by available ranks, even for a horse with a billion XP.
    for n=1,math.min(level,capacity) do
        for offset=0,4 do
            local key=STAT_KEYS[(n-1+offset)%5+1]
            if result[key]<math.min(9,base[key]+bonus) then result[key]=result[key]+1;break end
        end
    end
    return result,capacity
end
local function decodeTraining(raw,xp)
    local ok,t=pcall(json.decode,raw)
    if not ok or type(t)~='table' or t.version~=1 or not validBase(t.base)
        or not F.IsRevision(t.xpPerLevel) or t.xpPerLevel<1 or t.xpPerLevel>MAX_XP
        or not F.IsRevision(t.maxBonus) or t.maxBonus<1 or t.maxBonus>9
        or not F.IsRevision(t.level) or t.level>math.floor(xp/t.xpPerLevel) then return nil end
    t.ranks,t.capacity=ranks(t.base,t.level,t.maxBonus)
    if t.level>t.capacity then return nil end
    return t
end
local function advance(value,model,xp)
    if not G.StatRewardsEnabled() then return true end
    local t=value.training;local changed=false
    if not t then
        local mapping=Horses.ModelToBreedMap[model]
        local breed=mapping and Horses.BreedCatalog[mapping.breed]
        local coat=breed and breed.colors[model]
        if not coat or not validBase(coat.stats) then return false end
        local base=ranks(coat.stats,0,Config.bonding.maxStatBonus)
        t={version=1,base=base,xpPerLevel=Config.bonding.xpPerLevel,maxBonus=Config.bonding.maxStatBonus,level=0}
        value.training=t;changed=true
    end
    local _,capacity=ranks(t.base,0,t.maxBonus)
    local level=math.min(capacity,math.floor(xp/t.xpPerLevel))
    value.levelsGained=level-t.level
    if level~=t.level then t.level=level;changed=true end
    t.ranks,t.capacity=ranks(t.base,t.level,t.maxBonus)
    return true,changed and json.encode({version=1,base=t.base,xpPerLevel=t.xpPerLevel,maxBonus=t.maxBonus,level=t.level}) or nil
end
local function snapshot(row)
    if not row then return F.Ok({xp=0,revision=0}) end
    local xp,revision=tonumber(row.xp),tonumber(row.revision)
    if not F.IsRevision(xp) or xp>MAX_XP or not F.IsRevision(revision) then return bad() end
    local value={xp=xp,revision=revision}
    if G.StatRewardsEnabled() and row.training_json~=nil then
        value.training=decodeTraining(row.training_json,xp);if not value.training then return bad() end
    end
    return F.Ok(value)
end
function G.Read(horseId)
    if not G.Enabled() then return F.Ok(nil) end
    if not installed or not F.IsUuid(horseId) then return bad() end
    return snapshot(DB.one('SELECT xp,revision'..(G.StatRewardsEnabled() and ',training_json' or '')..' FROM fs_horse_bonding WHERE horse_id=?',horseId))
end
function G.FromOwnedRow(row) return snapshot(row.bonding_xp~=nil and {xp=row.bonding_xp,revision=row.bonding_revision,training_json=row.bonding_training} or nil) end
function G.NeedsStats(value)
    return G.StatRewardsEnabled() and (not value or not value.training
        or value.training.level<math.min(value.training.capacity,math.floor(value.xp/value.training.xpPerLevel)))
end
function G.EnsureStats(tx,horseId,model)
    tx.exec('INSERT IGNORE INTO fs_horse_bonding(horse_id) VALUES(?)',horseId)
    local saved=snapshot(tx.one('SELECT * FROM fs_horse_bonding WHERE horse_id=? FOR UPDATE',horseId))
    if not saved.ok then return saved end
    local value=saved.value;local ok,raw=advance(value,model,value.xp)
    if not ok then return bad() end
    if raw then
        if tx.exec('UPDATE fs_horse_bonding SET training_json=?,revision=revision+1 WHERE horse_id=? AND revision=?',raw,horseId,value.revision)~=1 then return bad() end
        value.revision=value.revision+1
    end
    return F.Ok(value)
end
function G.Forget(r) pending[r.id]=nil;dirty[r.horse.horseId]=nil end
function G.Changed(horseId) if installed then dirty[horseId]=true end end
-- Runs inside the caller's character admission/care transaction. Care's own
-- prepared -> applied CAS is its XP receipt; replay cannot award a second time.
function G.Care(tx,q)
    local amount=q.bondingReward
    if amount==nil or amount==0 then return F.Ok(nil) end
    if not F.IsRevision(amount) or amount>1000000 then return bad() end
    local horse=tx.one('SELECT owner_character_id,biological_state,catalog_id FROM fs_horses WHERE horse_id=? FOR UPDATE',q.horseId)
    if not horse or horse.owner_character_id~=q.characterId or horse.biological_state~='alive' then return bad() end
    tx.exec('INSERT IGNORE INTO fs_horse_bonding(horse_id) VALUES(?)',q.horseId)
    local row=tx.one('SELECT * FROM fs_horse_bonding WHERE horse_id=? FOR UPDATE',q.horseId)
    local saved=snapshot(row);if not saved.ok then return saved end
    local value=saved.value
    local column=q.action=='brush' and 'last_brush_at' or q.action=='feed' and 'last_feed_at'
    if not column or not F.IsRevision(q.bondingAt) or not F.IsRevision(q.bondingCooldown) or q.bondingCooldown>86400 then return bad() end
    local last=tonumber(row[column]) or 0
    if last>0 and q.bondingAt-last<q.bondingCooldown then amount=0 end
    amount=math.min(amount,MAX_XP-value.xp)
    local ok,raw=advance(value,horse.catalog_id,value.xp+amount);if not ok then return bad() end
    if amount>0 or raw then
        local sql='UPDATE fs_horse_bonding SET xp=xp+?,revision=revision+1,'..column..'=?'
        local at=amount>0 and q.bondingAt or last
        local updated=raw and tx.exec(sql..',training_json=? WHERE horse_id=? AND revision=?',amount,at,raw,q.horseId,value.revision)
            or tx.exec(sql..' WHERE horse_id=? AND revision=?',amount,at,q.horseId,value.revision)
        if updated~=1 then return bad() end
        value.xp=value.xp+amount;value.revision=value.revision+1
    end
    value.amount=amount;return F.Ok(value)
end
local function eligible(r)
    return G.Enabled() and installed and H.MovementRecord(r.session)==r and not r.care and not r.flee
end
local function position(entity)
    local p=GetEntityCoords(entity)
    for _,key in ipairs({'x','y','z'}) do
        local n=p and p[key];if type(n)~='number' or n~=n or math.abs(n)>1000000 then return nil end
    end
    return {x=p.x,y=p.y,z=p.z}
end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
local function award(r,reward)
    if not eligible(r) then return bad('stale_call') end
    local owned=R.ReadSelected(r.session)
    if not owned.ok or owned.value.horseId~=r.horse.horseId or owned.value.assetId~=r.horse.assetId then return bad('stale_call') end
    local result
    local committed=DB.transaction(function(tx)
        if not tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',r.session.characterId) then return false end
        local horse=tx.one('SELECT owner_character_id,availability,biological_state FROM fs_horses WHERE horse_id=? FOR UPDATE',r.horse.horseId)
        local slot=tx.one('SELECT generation_id FROM fs_call_slots WHERE character_id=? FOR UPDATE',r.session.characterId)
        if not horse or horse.owner_character_id~=r.session.characterId or horse.availability~='active'
            or horse.biological_state~='alive' or not slot or slot.generation_id~=r.id or not eligible(r) then return false end
        tx.exec('INSERT IGNORE INTO fs_horse_bonding(horse_id) VALUES(?)',r.horse.horseId)
        local row=tx.one('SELECT * FROM fs_horse_bonding WHERE horse_id=? FOR UPDATE',r.horse.horseId)
        local saved=snapshot(row);if not saved.ok then return false end
        result=saved.value
        if row.travel_generation==r.id and tonumber(row.travel_sequence)>=reward.sequence then return true end
        local amount=math.min(reward.amount,MAX_XP-result.xp)
        local ok,raw=advance(result,owned.value.modelKey,result.xp+amount);if not ok then return false end
        local sql='UPDATE fs_horse_bonding SET xp=xp+?,revision=revision+1,travel_generation=?,travel_sequence=?'
        local updated=raw and tx.exec(sql..',training_json=? WHERE horse_id=? AND revision=?',amount,r.id,reward.sequence,raw,r.horse.horseId,result.revision)
            or tx.exec(sql..' WHERE horse_id=? AND revision=?',amount,r.id,reward.sequence,r.horse.horseId,result.revision)
        if updated~=1 then return false end
        result.xp=result.xp+amount;result.revision=result.revision+1
        return eligible(r)
    end)
    return committed==true and F.Ok(result) or bad()
end
function G.Sample(source,p)
    local r=pending[p.generationId];local t=r and r.bondingTicket
    if not r or not t or t.sequence~=p.sequence or t.owner~=source or GetGameTimer()>t.expires or not eligible(r)
        or NetworkGetEntityOwner(r.entity)~=source or GetPlayerRoutingBucket(source)~=0 or GetPlayerPed(r.session.source)~=t.target
        or NetworkGetNetworkIdFromEntity(t.target)~=t.targetNet then return bad('stale_call') end
    pending[r.id]=nil;r.bondingTicket=nil
    local now=GetGameTimer();local ownerPos=position(t.target);local horsePos=position(r.entity)
    local previous=r.bondingLast;r.bondingLast={at=t.at,pos=t.pos,owner=t.owner,mode=p.mode}
    if not p.alive or not ownerPos or not horsePos or distance(ownerPos,horsePos)>5 then
        r.bondingLast=nil;r.ridingTicks=0;r.leadingTicks=0;return F.Ok(true)
    end
    local elapsed=previous and (t.at-previous.at) or 0
    local speed=elapsed>0 and distance(previous.pos,t.pos)*1000/elapsed or 0
    if not previous or previous.owner~=source or elapsed<1500 or elapsed>3500 or speed<=0.8 or speed>=35 then
        r.ridingTicks=math.max(0,(r.ridingTicks or 0)-1);r.leadingTicks=math.max(0,(r.leadingTicks or 0)-1)
        return F.Ok(true)
    end
    if p.mode~=previous.mode then return F.Ok(true) end
    -- No unobserved/late interval is credited, and teleport deltas cannot count.
    if distance(horsePos,t.pos)>35*math.max(0.1,(now-t.at)/1000)+3 then return F.Ok(true) end
    if p.mode=='riding' or p.mode=='leading' then
        local key=p.mode=='riding' and 'ridingTicks' or 'leadingTicks'
        r[key]=(r[key] or 0)+1
        local required=p.mode=='riding' and 30 or 15
        if r[key]>=required then
            r[key]=0
            local amount=G.Reward(p.mode)
            if amount>0 then r.bondingReward={sequence=t.sequence,amount=amount,reason=p.mode,retryAt=now} end
        end
    end
    return F.Ok(true)
end
function G.Tick(r)
    local now=GetGameTimer()
    if r.bondingNext and now<r.bondingNext then return end;r.bondingNext=now+2000
    if not eligible(r) then pending[r.id]=nil;r.bondingTicket=nil;r.bondingLast=nil;return end
    if dirty[r.horse.horseId] then
        local saved=G.Read(r.horse.horseId);if not saved.ok then return end
        r.bonding=saved.value;dirty[r.horse.horseId]=nil
    end
    if r.bondingReward then
        local q=r.bondingReward
        if r.bondingWorking or now<q.retryAt then return end
        q.retryAt=now+5000;r.bondingWorking=true
        CreateThread(function()
            local ok,result=pcall(award,r,q)
            r.bondingWorking=nil
            if not ok or not result.ok then return end
            r.bonding=result.value;r.bondingReward=nil
            if H.MovementRecord(r.session)==r then
                TriggerClientEvent('bcc-stables:bonding:earned',r.session.source,{generationId=r.id,horseId=r.horse.horseId,
                    amount=q.amount,reason=q.reason,xp=result.value.xp,training=result.value.training,levelsGained=result.value.levelsGained})
            end
        end)
        return
    end
    if r.bondingTicket then
        if now<=r.bondingTicket.expires then return end
        pending[r.id]=nil;r.bondingTicket=nil;r.bondingLast=nil
    end
    local owner=NetworkGetEntityOwner(r.entity);local target=GetPlayerPed(r.session.source)
    if type(owner)~='number' or owner<1 or GetPlayerRoutingBucket(owner)~=0 or not DoesEntityExist(target) then return end
    if r.bonding and (r.bondingSentOwner~=owner or r.bondingSentRevision~=r.bonding.revision) then
        TriggerClientEvent('bcc-stables:bonding:apply',owner,{generationId=r.id,observerId=r.observerId,netId=r.netId,modelKey=r.horse.modelKey,bonding=r.bonding})
        r.bondingSentOwner=owner;r.bondingSentRevision=r.bonding.revision
    end
    local targetNet=NetworkGetNetworkIdFromEntity(target);local pos,ownerPos=position(r.entity),position(target)
    if not pos or not ownerPos or distance(pos,ownerPos)>5 or not F.IsRevision(targetNet) or targetNet<1 then
        r.bondingLast=nil;return
    end
    local previous=r.bondingPoll;r.bondingPoll={at=now,pos=pos,owner=owner}
    local elapsed=previous and now-previous.at or 0
    local speed=elapsed>0 and distance(previous.pos,pos)*1000/elapsed or 0
    if not previous or previous.owner~=owner or elapsed<1500 or elapsed>3500 or speed<=0.8 or speed>=35 then
        r.bondingLast=nil
        r.ridingTicks=math.max(0,(r.ridingTicks or 0)-1);r.leadingTicks=math.max(0,(r.leadingTicks or 0)-1)

        return
    end
    r.bondingSequence=(r.bondingSequence or 0)+1
    local t={owner=owner,target=target,targetNet=targetNet,sequence=r.bondingSequence,at=now,pos=pos,expires=now+1500}
    pending[r.id]=r;r.bondingTicket=t
    TriggerClientEvent('bcc-stables:bonding:observe',owner,{generationId=r.id,observerId=r.observerId,sequence=t.sequence,
        netId=r.netId,modelKey=r.horse.modelKey,targetNet=targetNet,bonding=r.bonding})
end
function G.Start()
    if not G.Enabled() then installed=false;return F.Ok(true) end
    installed=pcall(DB.query,'SELECT horse_id,xp,revision,travel_generation,travel_sequence,last_feed_at,last_brush_at FROM fs_horse_bonding LIMIT 0')
    if G.Enabled() and not installed then return bad('bonding_schema_required') end
    if G.StatRewardsEnabled() then
        if not F.IsRevision(Config.bonding.xpPerLevel) or Config.bonding.xpPerLevel<1 or Config.bonding.xpPerLevel>MAX_XP
            or not F.IsRevision(Config.bonding.maxStatBonus) or Config.bonding.maxStatBonus<1 or Config.bonding.maxStatBonus>9 then return bad('invalid_bonding_config') end
        if not pcall(DB.query,'SELECT training_json FROM fs_horse_bonding LIMIT 0') then installed=false;return bad('progression_schema_required') end
    end
    if G.Enabled() then
        if not F.IsRevision(Config.bonding.careCooldownSeconds) or Config.bonding.careCooldownSeconds>86400 then return bad('invalid_bonding_config') end
        for _,reason in ipairs({'riding','leading','feed','brush'}) do
            local value=Config.bonding.xpRewards and Config.bonding.xpRewards[reason]
            if not F.IsRevision(value) or value>1000000 then return bad('invalid_bonding_config') end
        end
    end
    return F.Call('feather-core','RegisterRpc','stables.horses.call.bonding_sample.v1',function(p,source) return G.Sample(source,p) end,{
        contract=1,direction='client_to_server',requireCharacter=false,windowMs=2000,maxCalls=64,maxPayloadBytes=160,maxDepth=1,maxNodes=6,
        validatePayload=function(p)
            if type(p)~='table' or not F.IsUuid(p.generationId) or not F.IsRevision(p.sequence) or p.sequence<1 or type(p.alive)~='boolean'
                or p.mode~='idle' and p.mode~='riding' and p.mode~='leading' then return false end
            for key in pairs(p) do if key~='generationId' and key~='sequence' and key~='alive' and key~='mode' then return false end end
            return true
        end})
end
function G.Status() return {enabled=G.Enabled(),ready=not G.Enabled() or installed,statRewardsEnabled=G.StatRewardsEnabled()} end
