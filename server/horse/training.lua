-- NPC courses: observed checkpoints, durable completion, idempotent payment and
-- one XP transaction. No fee or reward is owed for an unfinished course.
Stables.Training={}
local T,F,H,G,C=Stables.Training,Stables.Feather,Stables.HorseController,Stables.Bonding,Stables.TrainingCourse
local live,working,abandoned={},{},{}
local installed=false
local pending=true
local function bad(code) return F.Error(code or 'training_pending','Horse training is unavailable.') end
function T.Enabled() return Config.training and Config.training.enabled==true end
function T.Status()
    local active={}
    for _,r in pairs(live) do
        local q=r.training
        if q then active[#active+1]={id=q.id,ownerSource=r.session.source,horseId=q.horseId,
            mode=q.mode,state=q.state,checkpoint=q.index,total=#q.points} end
    end
    return {enabled=T.Enabled(),ready=installed,active=active,recoveryPending=pending}
end
local function read(id,tx)
    local row=(tx or DB).one('SELECT * FROM fs_training_sessions WHERE operation_id=?'..(tx and ' FOR UPDATE' or ''),id)
    if not row then return nil end
    local ok,q=pcall(json.decode,row.record_json)
    if not ok or type(q)~='table' or q.id~=id or not F.IsUuid(id) or q.characterId~=row.character_id or q.horseId~=row.horse_id
        or not F.IsUuid(q.accountId) or not F.IsUuid(q.wallet) or not F.IsUuid(q.sink) or not F.IsUuid(q.horseId)
        or not F.IsRevision(q.amount) or q.amount<1 or q.amount>1000000 or (q.currency~='dollars' and q.currency~='gold')
        or not F.IsRevision(tonumber(row.earned_xp)) or tonumber(row.earned_xp)>1000 then return nil end
    q.state,q.earnedXp,q.payment=row.state,tonumber(row.earned_xp),row.payment_transaction_id
    return q
end
local function transaction(character,body)
    local result
    local ok,committed=pcall(DB.transaction,function(tx)
        if not tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',character) then return false end
        result=body(tx);return result and result.ok==true
    end)
    return ok and committed==true and result or (result and not result.ok and result or bad())
end
function T.Clear(character,tx)
    if not installed then return not T.Enabled() end
    return not (tx or DB).one([[SELECT operation_id FROM fs_training_sessions
        WHERE character_id=? AND state IN ('active','payment_pending','paid') LIMIT 1]]..(tx and ' FOR UPDATE' or ''),character)
end
local function send(r,q)
    TriggerClientEvent('bcc-stables:training:progress',r.session.source,{id=q.id,generationId=r.id,site=q.site,mode=q.mode,
        index=q.index,points=q.points,radius=q.radius,remainingMs=math.max(0,q.endsAt-GetGameTimer())})
end
local function stop(r,q,result)
    if r.training==q then r.training=nil end;live[q.id]=nil
    if F.IsCurrent(r.session) then TriggerClientEvent('bcc-stables:training:ended',r.session.source,{id=q.id,result=result}) end
end
function T.Cancel(r,reason)
    local q=r.training;if not q then return end
    if q.verified and q.working then
        if r.cancelled then live[q.id]=nil;pending=true end
        return -- The last server-verified checkpoint has already completed.
    end
    if q.state~='active' then
        if r.cancelled then live[q.id]=nil;r.training=nil;pending=true end
        return -- Completed obligations survive logout/cleanup.
    end
    pending=true
    local ok=pcall(DB.exec,"UPDATE fs_training_sessions SET state='cancelled' WHERE operation_id=? AND state='active'",q.id)
    if not ok then abandoned[q.id]=true end
    reason=reason or 'training_cancelled'
    print(('[bcc-stables] training cancelled; operationId=%s reason=%s checkpoint=%d elapsedMs=%d'):format(q.id,reason,q.index,GetGameTimer()-q.startedAt))
    stop(r,q,bad(reason))
end
function T.Settle(id)
    local q=read(id);if not q then return bad() end
    if q.state=='completed' or q.state=='cancelled' then return F.Ok(q) end
    if q.state=='payment_pending' then
        local paid=F.Call('feather-economy','Transfer',{fromAccountId=q.wallet,toAccountId=q.sink,currency=q.currency,amount=q.amount,
            idempotencyKey='stables.training:'..q.id,reasonCode='stables.training',referenceType='stables_training',referenceId=q.id},
            {actorCharacterId=q.characterId,actorAccountId=q.accountId,correlationId=q.id})
        if not paid.ok then
            if paid.code=='insufficient_funds' then
                DB.exec("UPDATE fs_training_sessions SET state='cancelled' WHERE operation_id=? AND state='payment_pending'",id)
            end
            return paid
        end
        local v=paid.value
        if type(v)~='table' or not F.IsUuid(v.transactionId) or v.amount~=q.amount or v.currency~=q.currency
            or v.fromAccountId~=q.wallet or v.toAccountId~=q.sink or v.reasonCode~='stables.training'
            or v.referenceType~='stables_training' or v.referenceId~=q.id or v.sourceResource~='bcc-stables' then return bad() end
        DB.exec("UPDATE fs_training_sessions SET state='paid',payment_transaction_id=? WHERE operation_id=? AND state='payment_pending'",v.transactionId,id)
        q=read(id);if not q then return bad() end
    end
    if q.state=='paid' then
        local result=transaction(q.characterId,function(tx)
            local current=read(id,tx);if not current then return bad() end
            if current.state=='completed' then return F.Ok(current) end
            if current.state~='paid' or not F.IsUuid(current.payment) or current.earnedXp<1 then return bad() end
            local xp=G.Course(tx,current.horseId,current.characterId,current.earnedXp);if not xp.ok then return xp end
            current.bonding=xp.value
            if tx.exec("UPDATE fs_training_sessions SET state='completed',record_json=? WHERE operation_id=? AND state='paid'",json.encode(current),id)~=1 then return bad() end
            current.state='completed';return F.Ok(current)
        end)
        if result.ok then G.Changed(q.horseId) end
        return result
    end
    return bad()
end
local function finish(r,q)
    q.working=true;pending=true
    local result=transaction(q.characterId,function(tx)
        if r.training~=q or q.verified~=true then return bad('training_cancelled') end
        local row=read(q.id,tx);if not row or row.state~='active' then return bad() end
        local horse=tx.one('SELECT owner_character_id,biological_state FROM fs_horses WHERE horse_id=? FOR UPDATE',q.horseId)
        if not horse or horse.owner_character_id~=q.characterId or (horse.biological_state~='alive' and horse.biological_state~='downed') then return bad('training_cancelled') end
        local earned,score=C.Reward(q.baseXp,(GetGameTimer()-q.startedAt)/1000,q.duration)
        local day=os.date('!%Y-%m-%d')
        local used=tx.one([[SELECT COALESCE(SUM(earned_xp),0) AS xp FROM fs_training_sessions
            WHERE horse_id=? AND training_day=? AND state IN ('payment_pending','paid','completed')]],q.horseId,day)
        earned=math.min(earned,math.max(0,q.dailyLimit-tonumber(used and used.xp or 0)))
        if earned<1 then return bad('training_daily_limit') end
        q.earnedXp,q.score,q.day,q.state=earned,score,day,'payment_pending'
        if tx.exec([[UPDATE fs_training_sessions SET state='payment_pending',training_day=?,earned_xp=?,record_json=?
            WHERE operation_id=? AND state='active']],day,earned,json.encode(q),q.id)~=1 then return bad() end
        return F.Ok(true)
    end)
    if not result.ok then
        -- A lost commit reply may already have reserved payment. Inspect the
        -- same ID; never create another completion or retry XP blindly.
        local saved=read(q.id)
        if not saved or saved.state=='active' then q.state='active';q.working=nil;T.Cancel(r);return end
    end
    local settled=T.Settle(q.id)
    q.working=nil
    if settled.ok or settled.code=='insufficient_funds' then stop(r,q,settled)
    else q.state='payment_pending';q.retryAt=GetGameTimer()+5000 end
end
function T.Request(source,p)
    if not T.Enabled() then return bad('training_disabled') end
    local captured=F.RequireSession(source);if not captured.ok then return captured end
    local s=captured.value;local r=H.MovementRecord(s)
    if not r then return bad('horse_not_ready') end
    if p.cancel then
        if r.training and r.training.id==p.id then T.Cancel(r) end
        return F.Ok(true)
    end
    if working[s.characterId] or r.training or r.care or r.worldCare or r.worldExit or r.movement or r.flee
        or (Stables.Injuries and Stables.Injuries.Blocked(r)) then return bad('training_busy') end
    local area=HorseTrainingLocations[p.site];local policy=Config.training.courses[p.mode]
    if not area or not area.configured or not area.enabled or not policy then return bad('training_unavailable') end
    local function eligible()
        return H.MovementRecord(s)==r and not r.training and not r.care and not r.worldCare and not r.movement and not r.flee
            and not (Stables.Injuries and Stables.Injuries.Blocked(r))
            and C.Distance(GetEntityCoords(GetPlayerPed(source)),area.npc)<=8
            and C.Distance(GetEntityCoords(GetPlayerPed(source)),GetEntityCoords(r.entity))<=6
    end
    if not eligible() then return bad('training_near_instructor') end
    working[s.characterId]=true
    local ok,result=pcall(function()
        local owned=Stables.OwnedRepository.ReadSelected(s)
        if not owned.ok or owned.value.horseId~=r.horse.horseId or not owned.value.condition then return bad('training_unavailable') end
        local accounts=F.Call('feather-economy','FindAccountsByOwner',{ownerType='character',ownerId=s.characterId})
        local sink=F.Call('feather-economy','GetSystemAccount',{currency=Config.training.currency,accountType='system_sink'})
        if not accounts.ok or not sink.ok then return bad('training_payment_unavailable') end
        local wallet
        for _,a in ipairs(accounts.value or {}) do
            if a.accountType=='wallet' and a.currency==Config.training.currency and a.status=='open' and a.ownerId==s.characterId and a.ownerType=='character' then
                if wallet then return bad('training_payment_unavailable') end;wallet=a.accountId
            end
        end
        if not F.IsUuid(wallet) or not F.IsUuid(sink.value.accountId) or sink.value.accountType~='system_sink'
            or sink.value.currency~=Config.training.currency or sink.value.status~='open' then return bad('training_payment_unavailable') end
        local id=DB.one('SELECT UUID() AS id');if not id or not F.IsUuid(id.id) then return bad() end
        local points,laps=C.Points(area,p.mode);if not points then return bad('training_unavailable') end
        local q={id=id.id,characterId=s.characterId,accountId=s.accountId,horseId=r.horse.horseId,generationId=r.id,
            wallet=wallet,sink=sink.value.accountId,currency=Config.training.currency,amount=Config.training.price,
            site=p.site,mode=p.mode,points=points,index=1,startedAt=GetGameTimer(),duration=policy.secondsPerLap*laps,
            minimumSeconds=policy.minimumSeconds,radius=policy.radius,baseXp=policy.xp,dailyLimit=Config.training.dailyHorseXpLimit,
            day=os.date('!%Y-%m-%d'),state='active',entryUntil=GetGameTimer()+(area.entryGraceSeconds or 15)*1000}
        q.endsAt=q.startedAt+q.duration*1000
        local saved=transaction(s.characterId,function(tx)
            if not eligible() or not T.Clear(s.characterId,tx) then return bad('training_busy') end
            local used=tx.one([[SELECT COALESCE(SUM(earned_xp),0) AS xp FROM fs_training_sessions
                WHERE horse_id=? AND training_day=? AND state IN ('payment_pending','paid','completed')]],q.horseId,q.day)
            if tonumber(used and used.xp or 0)>=q.dailyLimit then return bad('training_daily_limit') end
            if tx.one("SELECT operation_id FROM fs_care_slots WHERE horse_id=? FOR UPDATE",q.horseId) then return bad('training_busy') end
            if tx.exec([[INSERT INTO fs_training_sessions(operation_id,character_id,horse_id,state,training_day,record_json)
                VALUES(?,?,?,'active',?,?)]],q.id,q.characterId,q.horseId,q.day,json.encode(q))~=1 then return bad() end
            return F.Ok(q)
        end)
        if not saved.ok then abandoned[q.id]=true;pending=true;return saved end
        if not eligible() then abandoned[q.id]=true;pending=true;return bad('training_stale') end
        r.bonding=owned.value.bonding;r.training=q;live[q.id]=r;send(r,q)
        return F.Ok({id=q.id})
    end)
    working[s.characterId]=nil
    return ok and result or bad()
end
function T.Sample(source,p)
    local r=live[p.id];local q=r and r.training;local t=q and q.sample
    if not t or q.state~='active' or t.sequence~=p.sequence or t.owner~=source or GetGameTimer()>t.expires
        or H.MovementRecord(r.session)~=r or NetworkGetEntityOwner(r.entity)~=source
        or GetPlayerPed(r.session.source)~=t.target or NetworkGetNetworkIdFromEntity(t.target)~=t.targetNet then return bad('training_stale') end
    q.sample=nil
    if p.alive~=true then T.Cancel(r,'training_actor_unavailable');return F.Ok(false) end
    local now=GetGameTimer();local pos=GetEntityCoords(r.entity);local player=GetEntityCoords(GetPlayerPed(r.session.source))
    local area=HorseTrainingLocations[q.site]
    if not C.Inside(pos,area,1.5) or not C.Inside(player,area,q.mode=='leading' and 4 or 1.5) then
        q.outsideSince=q.outsideSince or now
        if (q.entered and now-q.outsideSince>=3000) or (not q.entered and now>q.entryUntil) then T.Cancel(r,'training_boundary') end
        return F.Ok(false)
    end
    q.outsideSince=nil
    q.entered=true
    if p.mode~=q.mode then
        q.wrongSince=q.wrongSince or now
        if now-q.wrongSince>3000 and now>q.entryUntil then T.Cancel(r,'training_interaction_lost') end
        return F.Ok(false)
    end
    q.wrongSince=nil
    local point=q.points[q.index]
    if not C.AtCheckpoint(pos,point,q.radius+0.5) or C.Distance(player,pos)>5
        or not C.AtCheckpoint(player,point,q.radius+3) then return F.Ok(false) end
    if now-(q.lastPointAt or q.startedAt)<2000 then return F.Ok(false) end
    if q.index==#q.points and now-q.startedAt<q.minimumSeconds*1000 then return F.Ok(false) end
    q.index=q.index+1;q.lastPointAt=now
    if q.index>#q.points then
        q.verified=true;q.working=true
        TriggerClientEvent('bcc-stables:training:pending',r.session.source,{id=q.id})
        CreateThread(function() local ok=pcall(finish,r,q);if not ok then q.working=nil;q.retryAt=GetGameTimer()+5000;pending=true end end)
    else send(r,q) end
    return F.Ok(true)
end
function T.Tick(r)
    local q=r.training;if not q or q.working then return end
    if q.state~='active' then
        if GetGameTimer()>=(q.retryAt or 0) then
            q.retryAt=GetGameTimer()+5000;q.working=true
            CreateThread(function()
                local ok,v=pcall(T.Settle,q.id);q.working=nil
                if ok and v.ok then stop(r,q,v)
                else local saved=read(q.id);if saved and saved.state=='active' then q.state='active' end end
            end)
        end
        return
    end
    if q.index>#q.points then
        if GetGameTimer()>=(q.retryAt or 0) then
            q.working=true
            CreateThread(function() local ok=pcall(finish,r,q);if not ok then q.working=nil;q.retryAt=GetGameTimer()+5000;pending=true end end)
        end
        return
    end
    if H.MovementRecord(r.session)~=r or r.care or r.worldCare or r.movement or r.flee
        or (Stables.Injuries and Stables.Injuries.Blocked(r)) then T.Cancel(r,'training_actor_unavailable');return end
    if GetGameTimer()>q.endsAt then T.Cancel(r,'training_timeout');return end
    local now=GetGameTimer();local pos=GetEntityCoords(r.entity)
    local speed=q.mode=='leading' and 6 or 35
    if q.lastPosition and C.Distance(pos,q.lastPosition)>speed*math.max(0.1,(now-q.lastAt)/1000)+3 then T.Cancel(r,'training_movement_invalid');return end
    q.lastPosition={x=pos.x,y=pos.y,z=pos.z};q.lastAt=now
    if q.nextAt and now<q.nextAt then return end;q.nextAt=now+1000
    local owner=NetworkGetEntityOwner(r.entity);local target=GetPlayerPed(r.session.source)
    if not owner or owner<1 or not target or target==0 then T.Cancel(r,'training_observation_lost');return end
    if q.sample and q.sample.owner~=owner then q.sample=nil end -- Migration replaces, never renews, the course deadline.
    if q.sample then if now>q.sample.expires then T.Cancel(r,'training_observation_lost') end;return end
    local targetNet=NetworkGetNetworkIdFromEntity(target)
    q.sequence=(q.sequence or 0)+1;q.sample={owner=owner,sequence=q.sequence,expires=now+2000,target=target,targetNet=targetNet}
    TriggerClientEvent('bcc-stables:training:sample',owner,{id=q.id,generationId=r.id,observerId=r.observerId,
        netId=r.netId,modelKey=r.horse.modelKey,sequence=q.sequence,targetNet=targetNet,bonding=r.bonding})
end
function T.Recover()
    if not pending then return end
    for id in pairs(abandoned) do
        DB.exec("UPDATE fs_training_sessions SET state='cancelled' WHERE operation_id=? AND state='active'",id)
        abandoned[id]=nil
    end
    local rows=DB.query("SELECT operation_id,state FROM fs_training_sessions WHERE state IN ('payment_pending','paid') ORDER BY created_at LIMIT 16")
    if type(rows)~='table' then return end
    pending=false
    for _,row in ipairs(rows) do
        local r=live[row.operation_id]
        if not r then
            local ok,v=pcall(T.Settle,row.operation_id);if not ok or not v.ok then pending=true end
        end
    end
    if #rows==16 then pending=true end
end
function T.Start()
    if not T.Enabled() and not DB.one([[SELECT TABLE_NAME FROM information_schema.TABLES
        WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='fs_training_sessions']]) then return F.Ok(true) end
    installed=pcall(DB.query,'SELECT operation_id,character_id,horse_id,state,earned_xp,record_json FROM fs_training_sessions LIMIT 0')
    if not installed then return T.Enabled() and bad('training_schema_required') or F.Ok(true) end
    local owed=DB.one("SELECT operation_id FROM fs_training_sessions WHERE state IN ('payment_pending','paid') LIMIT 1")
    if not T.Enabled() and not owed then
        DB.exec("UPDATE fs_training_sessions SET state='cancelled' WHERE state='active'")
        pending=false;return F.Ok(true)
    end
    if not G.Enabled() then return bad('training_bonding_required') end
    if not T.Enabled() then
        local ready=F.Call('feather-economy','AwaitReady',15000);if not ready.ok then return ready end
        DB.exec("UPDATE fs_training_sessions SET state='cancelled' WHERE state='active'")
        T.Recover();CreateThread(function() while true do Wait(5000);pcall(T.Recover) end end)
        return F.Ok(true)
    end
    local c=Config.training
    if not G.Enabled() or not F.IsRevision(c.price) or c.price<1 or c.price>1000000
        or not F.IsRevision(c.dailyHorseXpLimit) or c.dailyHorseXpLimit<1 or c.dailyHorseXpLimit>1000
        or (c.currency~='dollars' and c.currency~='gold') then return bad('invalid_training_config') end
    for _,mode in ipairs({'leading','riding'}) do
        local p=c.courses[mode]
        if type(p)~='table' then return bad('invalid_training_config') end
        for _,key in ipairs({'laps','secondsPerLap','minimumSeconds','xp'}) do
            if not F.IsRevision(p[key]) or p[key]<1 or p[key]>1000 then return bad('invalid_training_config') end
        end
        if p.laps>10 or type(p.radius)~='number' or p.radius~=p.radius or p.radius<1 or p.radius>5 then return bad('invalid_training_config') end
    end
    local ready=F.Call('feather-economy','AwaitReady',15000);if not ready.ok then return ready end
    local currency=F.Call('feather-economy','GetCurrency',c.currency)
    if not currency.ok or currency.value.precision~=2 then return bad('training_payment_unavailable') end
    DB.exec("UPDATE fs_training_sessions SET state='cancelled' WHERE state='active'")
    T.Recover()
    for _,name in ipairs({'training','training_sample'}) do
        local installed=F.Call('feather-core','RegisterRpc','stables.horses.call.'..name..'.v1',
            name=='training' and function(p,source) return T.Request(source,p) end or function(p,source) return T.Sample(source,p) end,{
                contract=1,direction='client_to_server',requireCharacter=name=='training',windowMs=2000,maxCalls=name=='training' and 2 or 64,
                maxPayloadBytes=192,maxDepth=2,maxNodes=8,validatePayload=function(p)
                    if type(p)~='table' then return false end
                    if name=='training_sample' then
                        for k in pairs(p) do if k~='id' and k~='sequence' and k~='mode' and k~='alive' then return false end end
                        return F.IsUuid(p.id) and F.IsRevision(p.sequence) and p.sequence>0 and type(p.alive)=='boolean'
                            and (p.mode=='leading' or p.mode=='riding' or p.mode=='idle')
                    end
                    for k in pairs(p) do if k~='site' and k~='mode' and k~='cancel' and k~='id' then return false end end
                    if p.cancel then return p.cancel==true and F.IsUuid(p.id) end
                    return type(p.site)=='string' and #p.site<=32 and (p.mode=='leading' or p.mode=='riding')
                end})
        if not installed.ok then return installed end
    end
    CreateThread(function() while true do Wait(5000);pcall(T.Recover) end end)
    return F.Ok(true)
end
