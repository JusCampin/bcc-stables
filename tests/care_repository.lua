local function Copy(v) if type(v)~='table' then return v end; local t={}; for k,x in pairs(v) do t[k]=Copy(x) end; return t end
local char='20000000-0000-4000-8000-000000000002'
local horse='30000000-0000-4000-8000-000000000003'
local op='10000000-0000-4000-8000-000000000001'
local function Terms() return {operationId=op,characterId=char,horseId=horse,instanceId=5,definitionId=10,itemRevision=0,itemName='existing_apple',policyRevision=1,healthGain=20,staminaGain=20} end
local function fixture()
    local m={db={conditions={},operations={},slots={},effects={}},sql=0}
    local e=setmetatable({RegisterCommand=function() end},{__index=_G})
    for _,f in ipairs({'shared/contracts.lua','server/operations.lua','server/care_operations.lua'}) do assert(loadfile(f,'t',e))() end
    local S=e.Stables; local docs,serial={},0
    e.json={encode=function(v) serial=serial+1; docs[tostring(serial)]=Copy(v); return tostring(serial) end,
        decode=function(v) assert(docs[v]); return Copy(docs[v]) end}
    S.Foundation={RequireReady=function() return S.Ok(true) end}
    S.Persistence={DatabaseError=function() return S.Err('database_error','Unknown outcome.') end}
    local tx={}
    function tx.one(sql,...)
        m.sql=m.sql+1; local p={...}; local d=m.db
        if sql:find('FROM fs_character_stables',1,true) then return {character_id=p[1],revision=0} end
        if sql:find('FROM fs_horses',1,true) then
            if m.foreign then return nil end
            return {horse_id=p[1],owner_character_id=p[2],biological_state=m.dead and 'dead' or 'alive',availability=m.active and 'active' or 'stored'}
        end
        if sql:find('SELECT operation_id FROM fs_care_operations',1,true) then
            for id,row in pairs(d.operations) do if row.character_id==p[1] and row.state~='applied' and row.state~='cancelled' then return {operation_id=id} end end
            return nil
        end
        if sql:find('FROM fs_care_operations',1,true) then return Copy(d.operations[p[1]]) end
        if sql:find('FROM fs_horse_condition',1,true) then return Copy(d.conditions[p[1]]) end
        if sql:find('FROM fs_care_slots',1,true) then return d.slots[p[1]] and {operation_id=d.slots[p[1]]} end
        if sql:find('FROM fs_care_effects',1,true) then return Copy(d.effects[p[1]]) end
        if sql:find('FROM fs_call_slots',1,true) then return m.call and {} or nil end
        if sql:find('FROM fs_call_leases',1,true) then return m.orphan and {} or nil end
        error(sql)
    end
    function tx.exec(sql,...)
        m.sql=m.sql+1; local p={...}; local d=m.db
        if m.fail and sql:find(m.fail,1,true) then return 0 end
        if sql:find('INSERT INTO fs_horse_condition',1,true) then
            assert(not d.conditions[p[1]]); d.conditions[p[1]]={horse_id=p[1],health_core=p[2],stamina_core=p[3],policy_revision=p[4],revision=p[5]}
        elseif sql:find('INSERT INTO fs_care_operations',1,true) then
            assert(not d.operations[p[1]]); d.operations[p[1]]={operation_id=p[1],horse_id=p[2],character_id=p[3],fingerprint=p[4],record_json=p[5],state=p[6],revision=p[7]}
        elseif sql:find('INSERT INTO fs_care_slots',1,true) then assert(not d.slots[p[1]]); d.slots[p[1]]=p[2]
        elseif sql:find('UPDATE fs_care_operations',1,true) then
            local row=d.operations[p[4]]; if not row or row.state~=p[6] or row.revision~=p[7] then return 0 end
            row.state,row.revision,row.record_json=p[1],p[2],p[3]
        elseif sql:find('UPDATE fs_horse_condition',1,true) then
            local row=d.conditions[p[4]]; if not row or row.revision~=p[5] or row.policy_revision~=p[6] or row.health_core~=p[7] or row.stamina_core~=p[8] then return 0 end
            row.health_core,row.stamina_core,row.revision=p[1],p[2],p[3]
        elseif sql:find('INSERT INTO fs_care_effects',1,true) then assert(not d.effects[p[1]]); d.effects[p[1]]={operation_id=p[1],horse_id=p[2],condition_revision=p[3]}
        elseif sql:find('DELETE FROM fs_care_slots',1,true) then if d.slots[p[1]]~=p[2] then return 0 end; d.slots[p[1]]=nil
        else error(sql) end
        return 1
    end
    e.DB={value=function()
        if m.scanFail then error('scan failed') end
        local n=0; for _,r in pairs(m.db.operations) do if r.state~='applied' and r.state~='cancelled' then n=n+1 end end; return n
    end,transaction=function(body)
        local before=Copy(m.db); local ok,result=pcall(body,tx)
        if not ok or not result then m.db=before end
        if not ok then error(result) end
        if result and m.unknown then error('lost commit acknowledgement') end
        return result
    end}
    m.env,m.tx=e,tx
    m.reload=function() assert(loadfile('server/care_repository.lua','t',e))(); m.r=S.CareRepository; return m.r.Start() end
    assert(m.reload().ok)
    m.authorize=function() return m.denied and S.Err('denied','Session changed.') or S.Ok(true) end
    m.initialize=function() return m.r.Initialize(char,{horseId=horse,healthCore=60,staminaCore=70,policyRevision=1,revision=0},m.authorize) end
    m.reserve=function(t) return m.r.Reserve(t or Terms(),m.authorize) end
    m.receipt=function(state)
        local r=S.CareOperations.InventoryRequest(m.reserve().value.operation).value
        r.contractVersion=1; r.sourceResource='bcc-stables'; r.state=state or 'consumed'; r.inventoryId=r.state=='consumed' and 7 or 0; r.replayed=false
        return r
    end
    m.commit=function(receipt) return m.r.CommitReceipt(op,char,receipt,m.authorize) end
    return m
end
local n=0
local function test(name,fn) fn(); n=n+1; print('PASS care repository '..name) end
test('no idle care fence SQL, failed startup scan closes readiness',function()
    local m=fixture(); local before=m.sql; assert(m.r.CheckCharacter(m.tx,char).ok and m.sql==before)
    m.scanFail=true; assert(not m.reload().ok)
end)
test('explicit initialization never overwrites condition or changes lifecycle',function()
    local m=fixture(); assert(m.initialize().ok and m.db.conditions[horse].health_core==60)
    assert(m.initialize().code=='condition_already_initialized' and m.db.conditions[horse].revision==0)
end)
test('authority absent or changed refuses before economic writes',function()
    local m=fixture(); assert(not m.r.Reserve(Terms(),nil).ok and next(m.db.operations)==nil)
    m.denied=true; assert(not m.initialize().ok and next(m.db.conditions)==nil)
end)
test('active horse or orphan call refuses initialization and reservation',function()
    local m=fixture(); m.active=true; assert(not m.initialize().ok)
    m.active=false; assert(m.initialize().ok); m.orphan=true; assert(m.reserve().code=='horse_busy')
end)
test('foreign or dead horse never receives condition seed or benefit',function()
    local m=fixture(); m.foreign=true; assert(not m.initialize().ok and not m.db.conditions[horse])
    m.foreign=false; assert(m.initialize().ok); local receipt=m.receipt(); m.dead=true
    local result=m.commit(receipt)
    assert(result.ok and result.value.reconciliationRequired and not m.db.effects[op] and m.db.conditions[horse].revision==0)
end)
test('reserve snapshots once and fences new lifecycle across reload',function()
    local m=fixture(); assert(m.initialize().ok and m.reserve().ok and m.db.slots[horse]==op)
    assert(m.r.CheckCharacter(m.tx,char).code=='horse_care_busy')
    assert(m.reserve().value.replayed); assert(m.reload().ok and m.r.CheckCharacter(m.tx,char).code=='horse_care_busy')
    local t=Terms(); t.healthGain=1; assert(m.reserve(t).code=='care_terms_conflict')
end)
test('atomic application and durable replay advance only condition once',function()
    local m=fixture(); assert(m.initialize().ok); local receipt=m.receipt()
    local result=m.commit(receipt); assert(result.ok and result.value.operation.state=='applied')
    assert(m.db.conditions[horse].revision==1 and m.db.conditions[horse].health_core==80 and not m.db.slots[horse])
    assert(m.reload().ok and m.commit(receipt).value.replayed and m.db.conditions[horse].revision==1)
end)
test('lost commit acknowledgement recovered by exact operation replay',function()
    local m=fixture(); assert(m.initialize().ok); local receipt=m.receipt(); m.unknown=true
    assert(m.commit(receipt).code=='database_error' and m.db.effects[op])
    m.unknown=false; assert(m.commit(receipt).value.replayed and m.db.conditions[horse].revision==1)
end)
test('effect journal or slot write failure rolls back all benefit mutations',function()
    for _,failure in ipairs({'INSERT INTO fs_care_effects','UPDATE fs_care_operations','DELETE FROM fs_care_slots'}) do
        local m=fixture(); assert(m.initialize().ok); local receipt=m.receipt(); m.fail=failure
        assert(not m.commit(receipt).ok and m.db.conditions[horse].revision==0 and not m.db.effects[op] and m.db.slots[horse]==op)
    end
end)
test('confirmed cancellation releases slot without changing condition',function()
    local m=fixture(); assert(m.initialize().ok); local receipt=m.receipt('cancelled')
    assert(m.commit(receipt).value.operation.state=='cancelled' and m.db.conditions[horse].revision==0 and not m.db.effects[op] and not m.db.slots[horse])
    assert(m.commit(receipt).value.replayed)
end)
test('condition conflict persists consumed obligation and keeps fence',function()
    local m=fixture(); assert(m.initialize().ok); local receipt=m.receipt(); m.db.conditions[horse].revision=1
    local result=m.commit(receipt)
    assert(result.ok and result.value.reconciliationRequired and result.value.operation.state=='consumed_effect_pending')
    assert(m.db.operations[op].state=='consumed_effect_pending' and m.db.slots[horse]==op and not m.db.effects[op])
    assert(m.reload().ok and m.r.CheckCharacter(m.tx,char).code=='horse_care_busy')
end)
test('corrupt slot and receipt refuse before effect; foreign identity cannot inspect',function()
    local m=fixture(); assert(m.initialize().ok); local receipt=m.receipt(); receipt.instanceId=6
    assert(not m.commit(receipt).ok and not m.db.effects[op])
    receipt.instanceId=5; m.db.slots[horse]=nil; assert(not m.commit(receipt).ok and not m.reserve().ok)
    assert(not m.r.Get(op,'40000000-0000-4000-8000-000000000004',m.authorize).ok)
end)
test('applied replay requires exact durable effect evidence',function()
    local m=fixture(); assert(m.initialize().ok); local receipt=m.receipt(); assert(m.commit(receipt).ok)
    m.db.effects[op].condition_revision=2; assert(not m.commit(receipt).ok and not m.reserve().ok)
end)
test('actual call repository admission respects pending care before its body',function()
    local m=fixture(); assert(m.initialize().ok and m.reserve().ok)
    assert(loadfile('server/call_repository.lua','t',m.env))()
    local r=m.env.Stables.CallRepository.Prepare({characterId=char},{},0,op)
    assert(r.code=='horse_care_busy')
end)
print(('%d/%d care repository cases passed; SQL transactions modeled, live care writes pending.'):format(n,n))
