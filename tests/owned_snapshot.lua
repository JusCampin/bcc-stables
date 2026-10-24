local fixture=assert(loadfile('tests/fixtures/snapshot_services.lua'))()
local count=0
local function test(name,fn) local ok,err=pcall(fn); assert(ok,name..': '..tostring(err)); count=count+1; print('PASS owned snapshot '..name) end
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function parity(m)
    local a,b=m.reference(),m.decode(); assert(a.ok==b.ok and (a.ok and equal(a.value,b.value) or a.code==b.code),tostring(a.code)..' / '..tostring(b.code))
end
test('stored prepared submitting active cleanup and released snapshots match existing reader',function()
    local m=fixture(); parity(m)
    local prepared=m.S.Calls.Prepare({expectedSelectionRevision=1},1,m.context); assert(prepared.ok); parity(m)
    m.prepare(); parity(m); assert(m.bind().ok); parity(m)
    assert(m.S.CallLifecycleRepository.BeginCleanup(m.t.characterId,m.id).ok); parity(m)
    assert(m.store().ok); parity(m)
    m.prepare(); parity(m); assert(m.bind().ok); parity(m)
end)
test('snapshot decoder performs no live SQL or provider calls',function()
    local m=fixture(); m.prepare(); assert(m.bind().ok); local rows=m.pack()
    for _,name in ipairs({'one','query','value','exec','transaction'}) do m.env.DB[name]=function() error('unexpected live read') end end
    m.S.Assets.ReadHorse=function() error('snapshot is local evidence only') end
    assert(m.decode(rows).ok)
end)
test('missing and tampered purchase artifacts retain completeness checks',function()
    for _,key in ipairs({'history__event_id','outbox__event_id','registration__operation_id','operation__operation_id'}) do
        local m=fixture(); local rows=m.pack(); rows[1][key]=nil; assert(not m.decode(rows).ok)
    end
    local m=fixture(); local rows=m.pack(); rows[1].horse__revision=1; assert(not m.decode(rows).ok)
end)
test('orphan lease and foreign lease identities remain denied',function()
    local m=fixture(); m.prepare(); m.db.callSlots={}; parity(m); assert(not m.decode().ok)
    m=fixture(); m.prepare(); local rows=m.pack(); rows[1].currentLease__character_id='20000000-0000-4000-8000-000000000099'
    assert(not m.decode(rows).ok)
end)
test('same generation conflicting joined evidence and duplicate results fail closed',function()
    local m=fixture(); m.prepare(); assert(m.bind().ok); local rows=m.pack()
    rows[1].currentBinding__network_id=99; assert(m.decode(rows).code=='invalid_projection')
    assert(m.decode({rows[1],rows[1]}).code=='invalid_projection')
end)
test('snapshot read issues exactly one parameterized SELECT without transaction or writes',function()
    local m=fixture(); local rows=m.pack(); local calls=0
    m.env.DB.transaction=function() error('must not open a transaction') end
    m.env.DB.query=function(sql,id,char)
        calls=calls+1; assert(sql:match('^SELECT ') and not sql:find('FOR UPDATE',1,true))
        assert(id==m.t.operationId and char==m.t.characterId); return rows
    end
    assert(m.q.Read(m.t.operationId,m.t.characterId).ok and calls==1)
    assert(m.q.Read('bad',m.t.characterId).code=='invalid_input' and calls==1)
end)
test('snapshot SQL failures do not fall back or authorize original path',function()
    local m=fixture(); m.env.DB.query=function() error({code='QUERY_FAILED',outcome='not_executed'}) end
    m.S.FulfillmentRepository.GetOwnedSnapshot=function() error('no hidden fallback') end
    assert(m.q.Read(m.t.operationId,m.t.characterId).code=='database_error')
end)
test('process-end recovery audit and epoch are validated entirely from snapshot',function()
    local m=fixture(); m.prepare()
    local old='f0000000-0000-4000-8000-000000000001'; local new='f0000000-0000-4000-8000-000000000002'
    local l=m.S.CallLifecycleRepository
    assert(l.RecordProcessEpoch(m.context,m.id,old).ok and m.bind().ok)
    assert(l.Reconcile(m.t.characterId,m.id,'restart_lost_observation').ok); parity(m)
    m.env.GetConvar=function() return new end
    assert(l.ResolveProcessEnded(m.t.characterId,m.id,new).ok); parity(m)
    local rows=m.pack(); rows[1].previousAudit__original_epoch=new
    assert(m.decode(rows).code=='invalid_recovery_receipt')
    rows=m.pack(); rows[1].previousEpoch__generation_id=nil
    assert(m.decode(rows).code=='invalid_recovery_receipt')
end)

test('production owned reads use one snapshot and preserve fresh canonical refusal',function()
    local m=fixture(); local before=m.snapshotReads or 0; local assets=0; local read=m.S.Assets.ReadHorse
    m.S.FulfillmentRepository.GetOwnedSnapshot=function() error('production must not fall back') end
    m.env.DB.transaction=function() error('owned read must not open transaction') end
    m.S.Assets.ReadHorse=function(...) assets=assets+1; return read(...) end
    local function get() return m.S.OwnedHorses.GetKnown(m.t.horseId,m.t.operationId,1,m.context) end
    assert(get().ok and m.snapshotReads==before+1 and assets==1)
    m.asset.owner.holderId='20000000-0000-4000-8000-000000000099'
    assert(get().code=='horse_not_found' and m.snapshotReads==before+2 and assets==2)
end)
test('production snapshot errors never authorize a reference fallback',function()
    local m=fixture(); m.S.FulfillmentRepository.GetOwnedSnapshot=function() error('unexpected fallback') end
    m.env.DB.query=function() error({code='QUERY_FAILED',outcome='not_executed'}) end
    assert(m.S.OwnedHorses.GetKnown(m.t.horseId,m.t.operationId,1,m.context).code=='database_error')
end)
test('unsupported environment refuses readiness and prevents owned authorization',function()
    local m=fixture(); local query=m.env.DB.query
    m.env.DB.query=function(sql,...)
        if sql:match('^SHOW VARIABLES') then return {{Variable_name='autocommit',Value='ON'},{Variable_name='tx_isolation',Value='READ-UNCOMMITTED'}} end
        return query(sql,...)
    end
    assert(m.q.Start().code=='snapshot_environment_unsupported' and not m.q.RequireReady().ok)
    assert(m.S.OwnedHorses.GetKnown(m.t.horseId,m.t.operationId,1,m.context).code=='owned_snapshot_unavailable')
end)
test('non-InnoDB and missing engine rows refuse snapshot startup',function()
    for _,missing in ipairs({false,true}) do
        local m=fixture(); local query=m.env.DB.query
        m.env.DB.query=function(sql,...)
            local rows=query(sql,...)
            if sql:find('SELECT TABLE_NAME,ENGINE',1,true) then
                if missing then table.remove(rows) else rows[1].ENGINE='MyISAM' end
            end
            return rows
        end
        assert(m.q.Start().code=='snapshot_environment_unsupported' and not m.q.RequireReady().ok)
    end
end)
test('stopping during yielded snapshot startup cannot resurrect readiness',function()
    local m=fixture(); local query=m.env.DB.query
    m.env.DB.query=function(sql,...)
        if sql:match('^SHOW VARIABLES') then m.q.Stop() end
        return query(sql,...)
    end
    assert(m.q.Start().code=='startup_cancelled' and not m.q.RequireReady().ok)
end)

print(count..'/'..count..' owned snapshot cases passed; real SQL query plan and isolation remain pending.')
