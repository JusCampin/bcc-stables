local count = 0
local function test(name, fn) fn(); count = count + 1; print('PASS persistence ' .. name) end
local fixture = assert(loadfile('tests/fixtures/persistence.lua'))()
local function terms(index)
    index = index or 1
    return {operationId=('10000000-0000-4000-8000-%012d'):format(index),characterId='20000000-0000-4000-8000-000000000002',
        horseId=('30000000-0000-4000-8000-%012d'):format(index),quoteId=('40000000-0000-4000-8000-%012d'):format(index),
        walletAccountId='50000000-0000-4000-8000-000000000005',sinkAccountId='60000000-0000-4000-8000-000000000006',
        catalogId='morgan_bay',catalogRevision=1,currency='dollars',amount=100}
end
local function receipt(t)
    return {transactionId='70000000-0000-4000-8000-000000000007',operation='transfer',sourceResource='bcc-stables',
        reasonCode='stables.horse_purchase',referenceType='stables_order',referenceId=t.operationId,
        fromAccountId=t.walletAccountId,toAccountId=t.sinkAccountId,currency=t.currency,amount=t.amount}
end
local function paid(m)
    local t = terms(); assert(m.r.Reserve(t).ok)
    assert(m.r.Advance(t.operationId,t.characterId,0,'payment_pending').ok)
    assert(m.r.Advance(t.operationId,t.characterId,1,'paid',{paymentReceipt=receipt(t)}).ok)
    return t
end

test('clean migration and restart retain checksummed schema',function()
    local m=fixture(); assert(m.start().ok and m.p.Health().schemaVersion==9 and m.ddl==17)
    m.reload(); local restarted=m.start(); assert(restarted.ok and restarted.value.applied==0 and m.ddl==17)
end)
test('001-only upgrade adds later migrations without changing the applied checksum',function()
    local m=fixture(); local migrations=m.env.Stables.Migrations
    m.env.Stables.Migrations={migrations[1]}
    assert(m.start().ok and m.ddl==6)
    local checksum=m.db.ledger['001_purchase_foundation'].checksum
    m.env.Stables.Migrations=migrations; m.reload(); local upgraded=m.start()
    assert(upgraded.ok and upgraded.value.schemaVersion==9 and upgraded.value.applied==8 and m.ddl==17)
    assert(m.db.ledger['001_purchase_foundation'].checksum==checksum)
end)
test('002 DDL failure resumes without reapplying 001',function()
    local m=fixture(); m.failCreate='fs_asset_registrations'; assert(not m.start().ok)
    assert(m.db.ledger['001_purchase_foundation'].state=='applied')
    assert(m.db.ledger['002_asset_registration'].state=='pending')
    m.failCreate=nil; m.reload(); local resumed=m.start()
    assert(resumed.ok and resumed.value.applied==8 and resumed.value.resumed==1 and m.ddl==17)
end)
test('checksum drift and unknown recorded migrations fail closed',function()
    local m=fixture(); assert(m.start().ok)
    m.db.ledger['001_purchase_foundation'].checksum='changed'; m.reload()
    assert(m.start().code=='migration_checksum_mismatch')
    m=fixture(); m.db.ledger.future={id='future',checksum='unknown',state='applied'}
    assert(m.start().code=='schema_newer_than_resource')
end)
test('untracked tables are not silently adopted',function()
    local m=fixture(); m.db.tables.fs_operations=true
    assert(m.start().code=='untracked_schema' and next(m.db.ledger)==nil)
end)
test('interrupted DDL resumes its original intent without dropping data',function()
    local m=fixture(); m.failCreate='fs_horses'
    assert(not m.start().ok and m.db.ledger['001_purchase_foundation'].state=='pending')
    assert(m.db.tables.fs_operations)
    m.failCreate=nil; m.reload(); local resumed=m.start()
    assert(resumed.ok and resumed.value.resumed==1 and m.ddl==17)
end)
test('missing applied table is refused instead of recreated',function()
    local m=fixture(); assert(m.start().ok); m.db.tables.fs_horses=nil; m.reload()
    assert(m.start().code=='schema_incomplete' and not m.db.tables.fs_horses)
end)
test('completion recording failure stays pending for recovery',function()
    local m=fixture(); m.failLedger=true
    assert(m.start().code=='invalid_migration_ledger')
    m.failLedger=false; m.reload(); assert(m.start().ok and m.ddl==17)
end)
test('readiness timeout and invalid capacity run no DDL',function()
    local m=fixture(); m.ready=false
    assert(m.start().code=='database_timeout' and m.ddl==0)
    m=fixture(); m.env.StablesConfig.ownedHorseLimit=0
    assert(m.start().code=='config_error' and m.ddl==0)
end)
test('identical reservation after reload returns durable original; changed terms conflict',function()
    local m=fixture(); assert(m.start().ok)
    local t=terms(); local first=m.r.Reserve(t); assert(first.ok and not first.value.replayed)
    m.reload(); assert(m.start().ok)
    local replay=m.r.Reserve(t); assert(replay.ok and replay.value.replayed)
    t.amount=101; assert(m.r.Reserve(t).code=='idempotency_conflict')
end)
test('capacity serialization retains uncertain reservations and releases cancellation',function()
    local m=fixture(); m.env.StablesConfig.ownedHorseLimit=1; assert(m.start().ok)
    local t=terms(); assert(m.r.Reserve(t).ok)
    assert(m.r.Reserve(terms(2)).code=='capacity_exceeded')
    assert(m.r.Advance(t.operationId,t.characterId,0,'cancelled').ok)
    assert(m.r.Reserve(terms(2)).ok)
end)
test('local horse evidence cannot fulfill a paid operation',function()
    local m=fixture(); assert(m.start().ok); local t=paid(m)
    assert(m.r.Advance(t.operationId,t.characterId,2,'fulfilled',{horseId=t.horseId,ownerCharacterId=t.characterId}).code=='assets_settlement_unavailable')
    assert(m.r.Get(t.operationId,t.characterId).value.state=='paid')
    assert(next(m.db.horses)==nil and next(m.db.history)==nil and next(m.db.outbox)==nil)
end)

test('caller fence cannot authorize compensation',function()
    local m=fixture(); assert(m.start().ok); local t=paid(m)
    assert(m.r.Advance(t.operationId,t.characterId,2,'compensation_pending',{fulfillmentFenced=true}).code=='assets_settlement_unavailable')
    assert(m.r.Get(t.operationId,t.characterId).value.state=='paid')
end)

test('refund evidence cannot bypass Assets settlement gate',function()
    local m=fixture(); assert(m.start().ok); local t=paid(m)
    assert(m.r.Advance(t.operationId,t.characterId,2,'refunded',{refundReceipt=receipt(t)}).code=='assets_settlement_unavailable')
    assert(m.r.Get(t.operationId,t.characterId).value.state=='paid')
end)

test('blocked fulfillment and compensation retain reserved capacity after restart',function()
    local m=fixture(); m.env.StablesConfig.ownedHorseLimit=1; assert(m.start().ok); local t=paid(m)
    for _,target in ipairs({'fulfilled','compensation_pending','refunded'}) do
        assert(m.r.Advance(t.operationId,t.characterId,2,target,{}).code=='assets_settlement_unavailable')
    end
    m.reload(); assert(m.start().ok)
    assert(m.r.Get(t.operationId,t.characterId).value.state=='paid')
    assert(m.r.Reserve(terms(2)).code=='capacity_exceeded')
end)

test('CAS refusal rolls back operation revision and payment evidence',function()
    local m=fixture(); assert(m.start().ok); local t=terms(); assert(m.r.Reserve(t).ok)
    m.failCas=true
    assert(m.r.Advance(t.operationId,t.characterId,0,'payment_pending').code=='revision_conflict')
    local record=m.r.Get(t.operationId,t.characterId).value
    assert(record.state=='reserved' and record.revision==0 and record.paymentReceipt==nil)
end)

test('paid uncertainty can enter reconciliation without horse or refund writes',function()
    local m=fixture(); assert(m.start().ok); local t=paid(m)
    assert(m.r.Advance(t.operationId,t.characterId,2,'reconciliation_required',{code='assets_unknown'}).ok)
    assert(next(m.db.horses)==nil and next(m.db.history)==nil and next(m.db.outbox)==nil)
end)

test('identity columns and corrupt JSON fail closed',function()
    local m=fixture(); assert(m.start().ok); local t=terms(); assert(m.r.Reserve(t).ok)
    m.db.operations[t.operationId].amount=1
    assert(m.r.Get(t.operationId,t.characterId).code=='invalid_operation')
    m.db.operations[t.operationId].record_json='not-json'
    assert(m.r.Get(t.operationId,t.characterId).code=='invalid_operation')
end)
test('foreign character cannot read or advance an operation',function()
    local m=fixture(); assert(m.start().ok); local t=terms(); assert(m.r.Reserve(t).ok)
    local foreign='90000000-0000-4000-8000-000000000009'
    assert(m.r.Get(t.operationId,foreign).code=='operation_not_found')
    assert(m.r.Advance(t.operationId,foreign,0,'payment_pending').code=='operation_not_found')
    assert(m.r.Get('invalid',t.characterId).code=='invalid_input')
end)
test('lost commit response preserves unknown outcome and converges by durable read',function()
    local m=fixture(); assert(m.start().ok); local t=terms(); m.unknownCommit=true
    local lost=m.r.Reserve(t); assert(lost.code=='database_error' and lost.details.outcome=='unknown')
    m.unknownCommit=false
    assert(m.r.Get(t.operationId,t.characterId).value.state=='reserved')
    assert(m.r.Reserve(t).value.replayed)
end)
test('provider loss latches persistence failure until restart',function()
    local m=fixture(); assert(m.start().ok); m.provider='stopped'
    assert(m.r.Reserve(terms()).code=='persistence_unavailable')
    m.provider='started'; assert(m.r.Reserve(terms()).code=='persistence_unavailable')
    m.reload(); assert(m.start().ok)
end)
test('foundation refusal blocks repository writes before opening a transaction',function()
    local m=fixture(); assert(m.start().ok)
    m.env.Stables.Foundation={RequireReady=function() return m.env.Stables.Err('not_ready','Core degraded.') end}
    assert(m.r.Reserve(terms()).code=='not_ready' and next(m.db.operations)==nil and next(m.db.characters)==nil)
end)
test('002 upgrade adds call tables while retaining prior checksums and character data',function()
    local m=fixture(); local migrations=m.env.Stables.Migrations
    m.env.Stables.Migrations={migrations[1],migrations[2]}; assert(m.start().ok and m.p.Health().schemaVersion==2)
    local first=m.db.ledger['001_purchase_foundation'].checksum; local second=m.db.ledger['002_asset_registration'].checksum
    m.db.characters.retained={character_id='retained',revision=2}
    m.env.Stables.Migrations=migrations; m.reload(); local r=m.start()
    assert(r.ok and r.value.schemaVersion==9 and r.value.applied==7 and m.ddl==17)
    assert(m.db.ledger['001_purchase_foundation'].checksum==first and m.db.ledger['002_asset_registration'].checksum==second)
    assert(m.db.characters.retained.revision==2)
end)
test('003 interrupted second table resumes without reapplying 001 or 002',function()
    local m=fixture(); m.failCreate='fs_call_slots'; assert(not m.start().ok)
    assert(m.db.ledger['002_asset_registration'].state=='applied' and m.db.ledger['003_call_generations'].state=='pending')
    m.failCreate=nil; m.reload(); local r=m.start()
    assert(r.ok and r.value.applied==7 and r.value.resumed==1 and m.ddl==17)
end)

test('003 upgrade adds later lifecycle tables and preserves every previous checksum',function()
    local m=fixture(); local migrations=m.env.Stables.Migrations
    m.env.Stables.Migrations={migrations[1],migrations[2],migrations[3]}; assert(m.start().ok and m.ddl==9)
    local checksums={}; for id,row in pairs(m.db.ledger) do checksums[id]=row.checksum end
    m.db.characters.retained={character_id='retained',revision=4}
    m.db.horses.retained={horse_id='retained',availability='stored',revision=0}
    m.env.Stables.Migrations=migrations; m.reload(); local r=m.start()
    assert(r.ok and r.value.schemaVersion==9 and r.value.applied==6 and m.ddl==17)
    for id,checksum in pairs(checksums) do assert(m.db.ledger[id].checksum==checksum) end
    assert(m.db.characters.retained.revision==4 and m.db.horses.retained.availability=='stored')
end)

test('004 interrupted DDL resumes original ledger without altering prior migrations',function()
    local m=fixture(); m.failCreate='fs_call_bindings'; assert(not m.start().ok)
    assert(m.db.ledger['003_call_generations'].state=='applied' and m.db.ledger['004_call_bindings'].state=='pending')
    m.failCreate=nil; m.reload(); local r=m.start()
    assert(r.ok and r.value.applied==6 and r.value.resumed==1 and m.ddl==17)
end)

test('004 upgrade adds process receipt table without changing prior checksums',function()
    local m=fixture(); local migrations=m.env.Stables.Migrations
    m.env.Stables.Migrations={migrations[1],migrations[2],migrations[3],migrations[4]}
    assert(m.start().ok and m.ddl==10)
    local checksums={}; for id,row in pairs(m.db.ledger) do checksums[id]=row.checksum end
    m.env.Stables.Migrations=migrations; m.reload(); local r=m.start()
    assert(r.ok and r.value.schemaVersion==9 and r.value.applied==5 and m.ddl==17)
    for id,checksum in pairs(checksums) do assert(m.db.ledger[id].checksum==checksum) end
end)
test('005 interrupted process receipt table migration resumes safely',function()
    local m=fixture(); m.failCreate='fs_call_process_epochs'; assert(not m.start().ok)
    assert(m.db.ledger['004_call_bindings'].state=='applied' and m.db.ledger['005_call_process_epochs'].state=='pending')
    m.failCreate=nil; m.reload(); local r=m.start()
    assert(r.ok and r.value.applied==5 and r.value.resumed==1 and m.ddl==17)
end)

test('005 upgrade adds recovery audit while preserving all existing migrations',function()
    local m=fixture(); local migrations=m.env.Stables.Migrations
    m.env.Stables.Migrations={}; for n=1,5 do m.env.Stables.Migrations[n]=migrations[n] end
    assert(m.start().ok and m.ddl==11)
    local checksums={}; for id,row in pairs(m.db.ledger) do checksums[id]=row.checksum end
    m.env.Stables.Migrations=migrations; m.reload(); local r=m.start()
    assert(r.ok and r.value.schemaVersion==9 and r.value.applied==4 and m.ddl==17)
    for id,checksum in pairs(checksums) do assert(m.db.ledger[id].checksum==checksum) end
end)
test('006 interrupted recovery audit migration resumes without replaying prior schema',function()
    local m=fixture(); m.failCreate='fs_call_recoveries'; assert(not m.start().ok)
    assert(m.db.ledger['005_call_process_epochs'].state=='applied' and m.db.ledger['006_call_recoveries'].state=='pending')
    m.failCreate=nil; m.reload(); local r=m.start()
    assert(r.ok and r.value.applied==4 and r.value.resumed==1 and m.ddl==17)
end)

test('006 upgrade adds runtime event table while preserving every prior migration',function()
    local m=fixture(); local migrations=m.env.Stables.Migrations
    m.env.Stables.Migrations={}; for n=1,6 do m.env.Stables.Migrations[n]=migrations[n] end
    assert(m.start().ok and m.ddl==12)
    local checksums={}; for id,row in pairs(m.db.ledger) do checksums[id]=row.checksum end
    m.env.Stables.Migrations=migrations; m.reload(); local r=m.start()
    assert(r.ok and r.value.schemaVersion==9 and r.value.applied==3 and m.ddl==17)
    for id,checksum in pairs(checksums) do assert(m.db.ledger[id].checksum==checksum) end
end)
test('007 interrupted runtime event migration resumes without changing existing tables',function()
    local m=fixture(); m.failCreate='fs_horse_runtime_events'; assert(not m.start().ok)
    assert(m.db.ledger['006_call_recoveries'].state=='applied' and m.db.ledger['007_horse_runtime_projection'].state=='pending')
    m.failCreate=nil; m.reload(); local r=m.start()
    assert(r.ok and r.value.applied==3 and r.value.resumed==1 and m.ddl==17)
end)

test('007 upgrade adds only managed horse-state index and restart adds nothing',function()
    local m=fixture(); local migrations=m.env.Stables.Migrations; local old={}
    for i=1,7 do old[i]=migrations[i] end
    m.env.Stables.Migrations=old; assert(m.start().ok); local checksums={}
    for id,row in pairs(m.db.ledger) do checksums[id]=row.checksum end
    m.env.Stables.Migrations=migrations; m.reload(); local r=m.start()
    assert(r.ok and r.value.schemaVersion==9 and r.value.applied==2 and m.indexDdl==1 and m.ddl==17)
    for id,value in pairs(checksums) do assert(m.db.ledger[id].checksum==value) end
    m.reload(); assert(m.start().value.applied==0 and m.indexDdl==1)
end)

test('pending index resumes after creation succeeded but ledger completion was lost',function()
    local m=fixture(); m.failIndex=true; assert(not m.start().ok)
    assert(m.db.ledger['008_call_horse_state_index'].state=='pending')
    m.failIndex=nil; m.failLedger=true; m.reload(); assert(not m.start().ok and m.indexDdl==1)
    m.failLedger=nil; m.reload(); local r=m.start()
    assert(r.ok and r.value.resumed==1 and r.value.applied==2 and m.indexDdl==1)
end)

test('missing or changed applied index fails closed without silent repair',function()
    local key='fs_call_leases.fs_call_horse_state'
    local m=fixture(); assert(m.start().ok); m.db.indexes[key]=nil; m.reload()
    assert(m.start().code=='schema_incomplete' and m.indexDdl==1)
    m=fixture(); assert(m.start().ok); m.db.indexes[key][2].COLUMN_NAME='source_id'; m.reload()
    assert(m.start().code=='schema_index_mismatch' and m.indexDdl==1)
end)

test('untracked index is not adopted and pending mismatched definition is refused',function()
    local key='fs_call_leases.fs_call_horse_state'
    local m=fixture(); m.failIndex=true; assert(not m.start().ok); m.failIndex=nil
    m.db.indexes[key]={{COLUMN_NAME='horse_id',SEQ_IN_INDEX=1,NON_UNIQUE=1,INDEX_TYPE='BTREE',COLLATION='A'}}
    m.db.ledger['008_call_horse_state_index']=nil; m.reload()
    assert(m.start().code=='untracked_schema' and not m.indexDdl)
    m=fixture(); m.failIndex=true; assert(not m.start().ok); m.failIndex=nil
    m.db.indexes[key]={{COLUMN_NAME='horse_id',SEQ_IN_INDEX=1,NON_UNIQUE=1,INDEX_TYPE='BTREE',COLLATION='A'}}; m.reload()
    assert(m.start().code=='schema_index_mismatch' and not m.indexDdl)
end)

test('managed index signature participates in checksum drift detection',function()
    local m=fixture(); assert(m.start().ok)
    m.env.Stables.Migrations[8].indexes[1].columns[2]='source_id'
    assert(m.start().code=='migration_checksum_mismatch')
end)

test('008 upgrade adds empty care foundation while preserving every prior checksum',function()
    local m=fixture(); local migrations=m.env.Stables.Migrations; local old={}
    for i=1,8 do old[i]=migrations[i] end
    m.env.Stables.Migrations=old; assert(m.start().ok and m.ddl==13)
    local checksums={}; for id,row in pairs(m.db.ledger) do checksums[id]=row.checksum end
    m.env.Stables.Migrations=migrations; m.reload(); local r=m.start()
    assert(r.ok and r.value.schemaVersion==9 and r.value.applied==1 and m.ddl==17)
    for id,checksum in pairs(checksums) do assert(m.db.ledger[id].checksum==checksum) end
    m.reload(); assert(m.start().value.applied==0 and m.ddl==17)
end)
test('009 interrupted care migration resumes without reapplying accepted migrations',function()
    local m=fixture(); m.failCreate='fs_care_slots'; assert(not m.start().ok)
    assert(m.db.ledger['008_call_horse_state_index'].state=='applied')
    assert(m.db.ledger['009_horse_care_foundation'].state=='pending' and m.db.tables.fs_care_operations)
    m.failCreate=nil; m.reload(); local r=m.start()
    assert(r.ok and r.value.resumed==1 and r.value.applied==1 and m.ddl==17)
end)
test('applied care table loss is refused without silent recreation',function()
    local m=fixture(); assert(m.start().ok); m.db.tables.fs_care_effects=nil; m.reload()
    assert(m.start().code=='schema_incomplete' and m.ddl==17)
end)

print(('%d/%d persistence cases passed; SQL/CFX are modeled, live concurrency pending.'):format(count,count))
