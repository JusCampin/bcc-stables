-- Shared food/tool care: one durable item outcome and one saved horse benefit.
-- Recovery cancels the SAME receipt; an already committed use remains owed.
Stables.Feeding={}
local P,F,H,R=Stables.Feeding,Stables.Feather,Stables.HorseController,Stables.OwnedRepository
local working,jobs={},{}
local pending=true -- Scan once after startup; idle servers do not poll care SQL.
local conditionKey='condition'
local function bad(code,distance)
    local v=F.Error(code or 'care_pending','Horse care could not be confirmed.')
    v.distance=distance;return v
end
local function brushing() return Config.brushing and Config.brushing.enabled==true end
function P.Enabled() return (Config.feeding and Config.feeding.enabled==true) or brushing() end
local function inventory(method,p)
    local ok,v=pcall(function()
        local api=exports['feather-inventory']; return api[method](api,p)
    end)
    if not ok or type(v)~='table' or v.ok~=true then return bad('inventory_unavailable') end
    return F.Ok(v.value)
end
function P.Probe()
    local ok,c=pcall(function() return exports['feather-inventory']:GetConsumptionContract() end)
    if not ok or type(c)~='table' or c.contractVersion~=1 or c.ready~=true or c.durableConsumption~=1
        or (brushing() and c.durableWear~=1) then
        return bad('inventory_unavailable')
    end
    if brushing() then
        if type(c.conditionKey)~='string' or not F.IsRevision(c.conditionMaximum)
            or Config.items.brush.maximumDurability>c.conditionMaximum then return bad('inventory_unavailable') end
        conditionKey=c.conditionKey
    end
    return F.Ok(true)
end
local function food(name)
    local policy=Config.feeding and Config.feeding.foods and Config.feeding.foods[name]
    if type(policy)~='table' or not F.IsRevision(policy.health) or policy.health>100
        or not F.IsRevision(policy.stamina) or policy.stamina>100 or policy.health+policy.stamina==0 then return nil end
    return policy
end
local function policy(name)
    if brushing() and name==Config.items.brush.name then
        local p=Config.brushing
        if F.IsRevision(p.health) and p.health<=100 and F.IsRevision(p.stamina) and p.stamina<=100 then return p,'brush' end
    elseif Config.feeding and Config.feeding.enabled then return food(name),'feed' end
end
local function findItem(character,p)
    local ok,v=pcall(function()
        local api=exports['feather-inventory']:initiate()
        local item=api.GetItemForCharacter(character,p.instanceId)
        if item.ok and p.action=='brush' and item.value.metadata and item.value.metadata[conditionKey]~=nil then
            local durability=item.value.metadata[conditionKey]
            if not F.IsRevision(durability) or durability<1 or durability>Config.items.brush.maximumDurability then return nil end
        end
        if item.ok and item.value.id==p.instanceId and item.value.revision==p.expectedRevision
            and item.value.definition.id==p.definitionId and item.value.definition.name==p.food
            and item.value.definition.type=='item_item' and (p.action=='brush' or item.value.definition.instanceMode=='stack')
            and policy(p.food) then return item.value end
    end)
    return ok and v or nil
end
local function condition(c)
    return type(c)=='table' and F.IsRevision(c.revision) and c.revision<9007199254740991
        and c.policyRevision==1 and F.IsRevision(c.healthCore) and c.healthCore<=100
        and F.IsRevision(c.staminaCore) and c.staminaCore<=100
end
local function read(id,tx)
    local row=(tx or DB).one('SELECT * FROM fs_care_operations WHERE operation_id=?'..(tx and ' FOR UPDATE' or ''),id)
    if not row then return nil end
    local ok,q=pcall(json.decode,row.record_json)
    local action=ok and type(q)=='table' and (q.kind=='brush_v1' and 'brush' or q.kind=='feed_v1' and 'feed')
    if not action or q.id~=id or row.fingerprint~=action..'.v1:'..id
        or q.characterId~=row.character_id or q.horseId~=row.horse_id or not F.IsUuid(q.horseId)
        or not F.IsUuid(q.assetId) or not condition(q.before) or not condition(q.after)
        or q.after.revision~=q.before.revision+1 or q.after.healthCore<q.before.healthCore
        or q.after.staminaCore<q.before.staminaCore or type(q.request)~='table'
        or q.request.operationId~=id or q.request.characterId~=q.characterId
        or q.request.purpose~=(action=='brush' and 'stables.brush.v1' or 'stables.care.v1')
        or q.request.effectReference~=q.horseId..':'..action..'.v1:'..q.before.revision
        -- Recovery honors the immutable saved terms, even if food effects change.
        or type(q.request.itemName)~='string' or #q.request.itemName>100 or not q.request.itemName:match('^[a-z0-9_]+$')
        or not F.IsRevision(q.request.instanceId) or q.request.instanceId<1
        or not F.IsRevision(q.request.definitionId) or q.request.definitionId<1 or not F.IsRevision(q.request.expectedRevision) then return nil end
    if action=='brush' and (not F.IsRevision(q.request.wear) or not F.IsRevision(q.request.maximumDurability)
        or q.request.maximumDurability<1 or q.request.maximumDurability>1000000 or q.request.wear>q.request.maximumDurability) then return nil end
    q.state,q.action=row.state,action
    return q
end
local function transaction(character,body)
    local result
    local ok,committed=pcall(DB.transaction,function(tx)
        if not tx.one('SELECT character_id FROM fs_character_stables WHERE character_id=? FOR UPDATE',character) then
            result=bad();return false
        end
        result=body(tx);return result.ok
    end)
    return ok and committed==true and result or (result and not result.ok and result or bad())
end
local function eligible(session,r)
    if not r or r.flee or H.MovementRecord(session)~=r then return false,'care_not_ready' end
    if r.care and r.care.cancelled then return false,'care_cancelled' end
    if r.movement then return false,'care_moving' end
    local ped=GetPlayerPed(session.source)
    if not ped or ped==0 then return false,'care_observation_unknown' end
    local a,b=GetEntityCoords(ped),GetEntityCoords(r.entity)
    if not a or not b then return false,'care_observation_unknown' end
    local distance=math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)
    if distance~=distance or distance==math.huge then return false,'care_observation_unknown' end
    if distance>2.5 then return false,'care_too_far',distance end
    return true
end
local function owned(session,r)
    local v=R.ReadSelected(session)
    return v.ok and v.value.horseId==r.horse.horseId and v.value.assetId==r.horse.assetId and v.value or nil
end
-- Checkpoint native depletion at care/store boundaries, not in a polling loop.
-- Simulator observations can lower saved cores; only committed care raises them.
function P.Capture(session,r,observation,authorize,horse)
    if type(observation)~='table' or not F.IsRevision(observation.healthCore) or observation.healthCore>100
        or not F.IsRevision(observation.staminaCore) or observation.staminaCore>100
        or not F.IsRevision(observation.appliedRevision) or type(observation.observedAt)~='number' then return bad('care_observation_unknown') end
    local function current()
        return authorize() and F.IsCurrent(session) and NetworkGetEntityOwner(r.entity)==observation.owner
            and GetGameTimer()-observation.observedAt>=0 and GetGameTimer()-observation.observedAt<=3000
    end
    if not current() then return bad('care_observation_unknown') end
    horse=horse or owned(session,r)
    if not horse then return bad('care_not_ready') end
    if not horse.condition then return F.Ok({}) end -- Never silently initialize old horses.
    if not condition(horse.condition) then return bad('care_pending') end
    if observation.appliedRevision<(r.requiredConditionRevision or 0) then
        -- Do not mistake a missed native benefit delivery for riding depletion.
        r.requiredConditionRevision=horse.condition.revision
        TriggerClientEvent('bcc-stables:feed:condition',observation.owner,{generationId=r.id,observerId=r.observerId,
            netId=r.netId,modelKey=r.horse.modelKey,condition=horse.condition})
        return bad('care_observation_unknown')
    end
    local restore
    local result=transaction(session.characterId,function(tx)
        if not current() then return bad('care_observation_unknown') end
        if tx.one("SELECT operation_id FROM fs_care_operations WHERE character_id=? AND state NOT IN ('applied','cancelled') LIMIT 1 FOR UPDATE",session.characterId) then
            return F.Ok({condition=horse.condition,deferred=true}) -- Preserve the pending receipt's before/after evidence.
        end
        local row=tx.one([[SELECT c.*,h.owner_character_id,h.biological_state,h.availability,s.generation_id,
            (SELECT MAX(e.condition_revision) FROM fs_care_effects e WHERE e.horse_id=c.horse_id) AS last_care_revision
            FROM fs_horse_condition c INNER JOIN fs_horses h ON h.horse_id=c.horse_id
            LEFT JOIN fs_call_slots s ON s.character_id=h.owner_character_id WHERE c.horse_id=? FOR UPDATE]],r.horse.horseId)
        if not row or row.owner_character_id~=session.characterId or row.biological_state~='alive'
            or row.availability~='active' or row.generation_id~=r.id then return bad('care_pending') end
        local c={healthCore=tonumber(row.health_core),staminaCore=tonumber(row.stamina_core),
            revision=tonumber(row.revision),policyRevision=tonumber(row.policy_revision)}
        if not condition(c) then return bad('care_pending') end
        if observation.appliedRevision<(tonumber(row.last_care_revision) or 0) then
            restore=c;return bad('care_observation_unknown')
        end
        local health,stamina=math.min(c.healthCore,observation.healthCore),math.min(c.staminaCore,observation.staminaCore)
        if health~=c.healthCore or stamina~=c.staminaCore then
            assert(tx.exec([[UPDATE fs_horse_condition SET health_core=?,stamina_core=?,revision=revision+1
                WHERE horse_id=? AND revision=?]],health,stamina,r.horse.horseId,c.revision)==1)
            c.healthCore,c.staminaCore,c.revision=health,stamina,c.revision+1
        end
        if not current() then return bad('care_observation_unknown') end
        return F.Ok({condition=c})
    end)
    if restore and current() then
        r.requiredConditionRevision=restore.revision
        TriggerClientEvent('bcc-stables:feed:condition',observation.owner,{generationId=r.id,observerId=r.observerId,
            netId=r.netId,modelKey=r.horse.modelKey,condition=restore})
    end
    return result
end
local function reserve(session,r,item,c)
    local id=DB.one('SELECT UUID() AS id')
    if not id or not F.IsUuid(id.id) then return bad() end
    local effect,action=policy(item.definition.name)
    if not effect then return bad('care_disabled') end
    local health,stamina=effect.health,effect.stamina
    local q={kind=action..'_v1',action=action,id=id.id,characterId=session.characterId,horseId=r.horse.horseId,assetId=r.horse.assetId,
        before=c,after={healthCore=math.min(100,c.healthCore+health),staminaCore=math.min(100,c.staminaCore+stamina),
            revision=c.revision+1,policyRevision=c.policyRevision}}
    if Stables.Bonding and Stables.Bonding.Enabled() then
        q.bondingReward=Stables.Bonding.Reward(action);q.bondingAt=os.time();q.bondingCooldown=Config.bonding.careCooldownSeconds
    end
    if action=='feed' and q.before.healthCore==q.after.healthCore and q.before.staminaCore==q.after.staminaCore then return bad('care_full') end
    q.request={operationId=q.id,characterId=q.characterId,instanceId=item.id,definitionId=item.definition.id,
        expectedRevision=item.revision,itemName=item.definition.name,purpose=action=='brush' and 'stables.brush.v1' or 'stables.care.v1',
        effectReference=q.horseId..':'..action..'.v1:'..c.revision}
    if action=='brush' then
        q.request.wear=Config.items.brush.durabilityEnabled and Config.items.brush.durabilityUsedPerAction or 0
        q.request.maximumDurability=Config.items.brush.maximumDurability
        if not F.IsRevision(q.request.wear) or not F.IsRevision(q.request.maximumDurability) or q.request.maximumDurability<1
            or q.request.maximumDurability>1000000 or q.request.wear>q.request.maximumDurability then return bad('care_disabled') end
    end
    pending=true -- Set before committing, including a lost reservation reply.
    return transaction(q.characterId,function(tx)
        if not eligible(session,r) then return bad('care_ineligible') end
        local slot=tx.one('SELECT generation_id FROM fs_call_slots WHERE character_id=? FOR UPDATE',q.characterId)
        local lease=tx.one('SELECT state FROM fs_call_leases WHERE generation_id=? FOR UPDATE',r.id)
        local horse=tx.one('SELECT owner_character_id,biological_state,availability FROM fs_horses WHERE horse_id=? FOR UPDATE',q.horseId)
        local saved=tx.one('SELECT * FROM fs_horse_condition WHERE horse_id=? FOR UPDATE',q.horseId)
        if not slot or slot.generation_id~=r.id or not lease or lease.state~='active' or not horse
            or horse.owner_character_id~=q.characterId or horse.biological_state~='alive' or horse.availability~='active'
            or not saved or tonumber(saved.revision)~=c.revision or tonumber(saved.health_core)~=c.healthCore
            or tonumber(saved.stamina_core)~=c.staminaCore or tonumber(saved.policy_revision)~=c.policyRevision then return bad() end
        if tx.one("SELECT operation_id FROM fs_care_operations WHERE character_id=? AND state NOT IN ('applied','cancelled') LIMIT 1 FOR UPDATE",q.characterId) then return bad() end
        assert(tx.exec("INSERT INTO fs_care_operations (operation_id,horse_id,character_id,fingerprint,record_json,state,revision) VALUES (?,?,?,?,?,'prepared',0)",
            q.id,q.horseId,q.characterId,action..'.v1:'..q.id,json.encode(q))==1)
        assert(tx.exec('INSERT INTO fs_care_slots (horse_id,operation_id) VALUES (?,?)',q.horseId,q.id)==1)
        assert(tx.exec([[INSERT INTO fs_care_targets (operation_id,generation_id,observer_id,network_id,source_id,session_id)
            VALUES (?,?,?,?,?,?)]],q.id,r.id,r.observerId,r.netId,session.source,session.sessionId)==1)
        if not eligible(session,r) then return bad('care_ineligible') end
        return F.Ok(q)
    end)
end
local function receipt(q,v)
    local terminal=q.action=='brush' and 'used' or 'consumed'
    if type(v)~='table' or v.contractVersion~=1 or v.sourceResource~='bcc-stables'
        or (v.state~=terminal and v.state~='cancelled') or not F.IsRevision(v.inventoryId)
        or (v.state==terminal and v.inventoryId<1) or (v.state=='cancelled' and v.inventoryId~=0) then return false end
    if terminal=='used' and v.state=='used' and (not F.IsRevision(v.remainingDurability) or v.remainingDurability>q.request.maximumDurability
        or v.broken~=(v.remainingDurability==0)) then return false end
    for k,value in pairs(q.request) do if v[k]~=value then return false end end
    return true
end
local function view(q)
    return {state=q.state,condition=q.state=='applied' and q.after or q.before,action=q.action,bonding=q.bonding,
        remainingDurability=q.receipt and q.receipt.remainingDurability,broken=q.receipt and q.receipt.broken,
        maximumDurability=q.request.maximumDurability}
end
function P.Settle(id,consume)
    local q=read(id);if not q then return bad() end
    if q.state=='applied' or q.state=='cancelled' then
        if (q.action=='brush' and not q.receipt) or (q.receipt and (not receipt(q,q.receipt)
            or (q.state=='cancelled')~=(q.receipt.state=='cancelled'))) then return bad() end
        if q.bonding and Stables.Bonding then Stables.Bonding.Changed(q.horseId) end
        return F.Ok(view(q))
    end
    if q.state~='prepared' then return bad() end
    -- Never re-consume during recovery. Cancel races on Inventory's same key.
    local method=q.action=='brush' and (consume and 'WearCharacterItemOnce' or 'CancelCharacterItemWear')
        or (consume and 'ConsumeCharacterItemOnce' or 'CancelCharacterConsumption')
    local reply=inventory(method,q.request)
    if not reply.ok or not receipt(q,reply.value) then return bad() end
    local v=reply.value
    local settled=transaction(q.characterId,function(tx)
        local current=read(id,tx);if not current then return bad() end
        if current.state=='applied' or current.state=='cancelled' then return F.Ok(view(current)) end
        local slot=tx.one('SELECT operation_id FROM fs_care_slots WHERE horse_id=? FOR UPDATE',q.horseId)
        if not slot or slot.operation_id~=id then return bad() end
        local state=v.state~='cancelled' and 'applied' or 'cancelled'
        if state=='applied' then
            local c=q.after
            assert(tx.exec([[UPDATE fs_horse_condition SET health_core=?,stamina_core=?,revision=? WHERE horse_id=?
                AND revision=? AND health_core=? AND stamina_core=? AND policy_revision=?]],c.healthCore,c.staminaCore,c.revision,
                q.horseId,q.before.revision,q.before.healthCore,q.before.staminaCore,q.before.policyRevision)==1)
            assert(tx.exec('INSERT INTO fs_care_effects (operation_id,horse_id,condition_revision) VALUES (?,?,?)',id,q.horseId,c.revision)==1)
            if q.bondingReward and q.bondingReward>0 then
                if not Stables.Bonding then return bad('bonding_unavailable') end
                local xp=Stables.Bonding.Care(tx,q);if not xp.ok then return xp end;q.bonding=xp.value
            end
        end
        q.state,q.receipt=state,v
        assert(tx.exec('UPDATE fs_care_operations SET state=?,record_json=?,revision=1 WHERE operation_id=? AND state=\'prepared\'',state,json.encode(q),id)==1)
        assert(tx.exec('DELETE FROM fs_care_slots WHERE horse_id=? AND operation_id=?',q.horseId,id)==1)
        return F.Ok(view(q))
    end)
    if settled.ok and settled.value.bonding and Stables.Bonding then Stables.Bonding.Changed(q.horseId) end
    return settled
end
function P.Request(source,p,captured,ticket)
    captured=captured or F.RequireSession(source);if not captured.ok then return captured end
    local session=captured.value
    if not F.IsCurrent(session) then return bad('care_stale') end
    local job=jobs[session.characterId]
    if p.operationId then
        if p.started==nil and p.cancel==nil then
            if working[session.characterId] then return bad('care_busy') end
            local q=read(p.operationId)
            if not q or q.characterId~=session.characterId then return bad('care_stale') end
            working[session.characterId]=true
            local ok,v=pcall(P.Settle,p.operationId,false)
            working[session.characterId]=nil
            return ok and v or bad()
        end
        if not job or job.id~=p.operationId or job.sessionId~=session.sessionId then return bad('care_stale') end
        if p.started~=nil and job.started==nil then job.started=p.started;job.startedAt=GetGameTimer() end
        if p.cancel==true then job.cancelled=true end
        return F.Ok(true)
    end
    if not P.Enabled() then return bad('care_disabled') end
    if working[session.characterId] and working[session.characterId]~=ticket then return bad('care_busy') end
    working[session.characterId]=ticket or true
    local r
    local ok,result=pcall(function()
        if not P.Probe().ok then return bad('inventory_unavailable') end
        r=H.MovementRecord(session)
        local allowed,reason,distance=eligible(session,r)
        if not allowed then return bad(reason,distance) end
        job={sessionId=session.sessionId};jobs[session.characterId]=job;r.care=job
        local free,why,observation=H.CheckCareOccupancy(session,r)
        if not free then return bad(why or 'care_observation_unknown') end
        allowed,reason,distance=eligible(session,r)
        if not allowed then return bad(reason,distance) end
        local horse=owned(session,r)
        if not horse or not condition(horse.condition) then return bad('care_uninitialized') end
        local captured=P.Capture(session,r,observation,function() return eligible(session,r) end,horse)
        if not captured.ok then return captured end
        horse.condition=captured.value.condition
        local item=findItem(session.characterId,p)
        if not item then return bad('care_food_missing') end
        local saved=reserve(session,r,item,horse.condition);if not saved.ok then return saved end
        job.id=saved.value.id
        TriggerClientEvent('bcc-stables:feed:animate',source,{operationId=job.id,generationId=r.id,netId=r.netId,action=saved.value.action})
        local deadline=GetGameTimer()+5000
        repeat
            Wait(100)
            if not eligible(session,r) then job.cancelled=true end
        until job.started~=nil or GetGameTimer()>=deadline or job.cancelled
        if job.started==true and not job.cancelled then
            repeat
                Wait(100)
                if not eligible(session,r) then job.cancelled=true end
            until GetGameTimer()>=job.startedAt+5000 or job.cancelled
        end
        local consume=not job.cancelled and job.started==true and eligible(session,r)
        if consume then consume=H.CheckCareOccupancy(session,r) and owned(session,r)~=nil and eligible(session,r) end
        local settled=P.Settle(job.id,consume)
        if settled.ok and settled.value.state=='applied' and H.MovementRecord(session)==r then
            -- Absolute saved values, exact live generation, current simulator.
            r.requiredConditionRevision=settled.value.condition.revision
            TriggerClientEvent('bcc-stables:feed:condition',NetworkGetEntityOwner(r.entity),{generationId=r.id,
                observerId=r.observerId,netId=r.netId,modelKey=r.horse.modelKey,condition=settled.value.condition,action=settled.value.action})
        end
        return settled
    end)
    if r and r.care==job then r.care=nil end
    jobs[session.characterId],working[session.characterId]=nil,nil
    return ok and result or bad()
end
-- Inventory releases its active-use guard when this callback RETURNS. Enqueue
-- first, then re-read the exact instance after yielding one tick; no callback
-- token/guard bypass or transaction spanning an animation is needed.
function P.UseItem(item,source)
    local captured=F.RequireSession(source)
    if not captured.ok then return F.Ok(false) end
    local session=captured.value
    local function notify(v)
        if type(item)=='table' and Config.items.brush and item.name==Config.items.brush.name then v.action='brush' end
        if F.IsCurrent(session) then TriggerClientEvent('bcc-stables:feed:result',source,v) end
    end
    if not P.Enabled() then notify(bad('care_disabled'));return F.Ok(false) end
    if working[session.characterId] then notify(bad('care_busy'));return F.Ok(false) end
    local p=type(item)=='table' and {instanceId=tonumber(item.id),definitionId=tonumber(item.item_id),
        expectedRevision=tonumber(item.row_revision),food=item.name} or {}
    if not F.IsRevision(p.instanceId) or p.instanceId<1 or not F.IsRevision(p.definitionId) or p.definitionId<1
        or not F.IsRevision(p.expectedRevision) or not policy(p.food) then notify(bad('care_food_missing'));return F.Ok(false) end
    local _,action=policy(p.food);p.action=action
    local called,closed=pcall(function() return exports['feather-inventory']:initiate().Inventory.CloseInventory(source) end)
    if not called or type(closed)~='table' or not closed.ok or not F.IsCurrent(session) then notify(bad());return F.Ok(false) end
    local token={}
    -- Recheck after yielding providers before acquiring this character's queue.
    if working[session.characterId] then notify(bad('care_busy'));return F.Ok(false) end
    working[session.characterId]=token
    CreateThread(function()
        Wait(0)
        local ok,v=pcall(P.Request,source,p,captured,token)
        if working[session.characterId]==token then working[session.characterId]=nil end
        notify(ok and v or bad())
    end)
    return F.Ok({queued=true})
end
function P.Tick()
    if not pending then return end
    local rows=DB.query([[SELECT operation_id,character_id FROM fs_care_operations
        WHERE state='prepared' AND (fingerprint LIKE 'feed.v1:%' OR fingerprint LIKE 'brush.v1:%') ORDER BY created_at LIMIT 5]])
    if type(rows)~='table' then return end
    if #rows==0 then pending=false;return end
    for _,row in ipairs(rows or {}) do
        if not working[row.character_id] then
            working[row.character_id]=true
            pcall(P.Settle,row.operation_id,false)
            working[row.character_id]=nil
        end
    end
end
function P.Start()
    if P.Enabled() then
        local ok,result=pcall(function()
            local api=exports['feather-inventory']:initiate()
            -- Validate every configured policy before registering any callbacks.
            local names={}
            if Config.feeding and Config.feeding.enabled then
                if type(Config.feeding.foods)~='table' or not next(Config.feeding.foods) then return bad('invalid_feed_policy') end
                for name in pairs(Config.feeding.foods) do
                    if type(name)~='string' or #name>100 or not name:match('^[a-z0-9_]+$') or not food(name) then return bad('invalid_feed_policy') end
                    names[#names+1]=name
                end
            end
            if brushing() then
                local name=Config.items.brush.name
                if type(name)~='string' or #name>100 or not name:match('^[a-z0-9_]+$') or not policy(name) then return bad('invalid_brush_policy') end
                for _,foodName in ipairs(names) do if foodName==name then return bad('invalid_brush_policy') end end
                names[#names+1]=name
            end
            table.sort(names)
            for _,name in ipairs(names) do
                local registered=api.Items.RegisterUsableItem(name,P.UseItem,GetCurrentResourceName())
                if type(registered)~='table' or not registered.ok then return bad('food_registration_conflict') end
            end
            return F.Ok(true)
        end)
        if not ok then return bad('inventory_unavailable') end
        if not result.ok then return result end
    end
    local installed=F.Call('feather-core','RegisterRpc','stables.horses.call.feed.v1',function(p,source) return P.Request(source,p) end,{
        contract=1,direction='client_to_server',requireCharacter=true,windowMs=2000,maxCalls=8,maxPayloadBytes=256,maxDepth=2,maxNodes=8,
        validatePayload=function(p)
            if type(p)~='table' then return false end
            for k in pairs(p) do if k~='operationId' and k~='started' and k~='cancel' then return false end end
            if p.operationId then return F.IsUuid(p.operationId)
                and (p.started==nil or type(p.started)=='boolean') and (p.cancel==nil or type(p.cancel)=='boolean') end
            return false -- New feeding begins only through Inventory's server callback.
        end})
    if not installed.ok then return installed end
    CreateThread(function() while true do Wait(10000);pcall(P.Tick) end end)
    return F.Ok(true)
end
