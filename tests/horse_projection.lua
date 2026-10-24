local base=assert(loadfile('tests/fixtures/selection_services.lua'))()
local count=0
local function test(name,fn) local ok,err=pcall(fn); assert(ok,name..': '..tostring(err)); count=count+1; print('PASS horse projection '..name) end
local function size(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local function fixture()
    local m=base(); assert(m.select(0).ok)
    for _,f in ipairs({'server/call_repository.lua','server/call_lifecycle_repository.lua','server/calls.lua'}) do assert(loadfile(f,'t',m.env))() end
    m.env.StablesConfig.callPreparation=true; assert(m.S.Calls.Start().ok)
    m.l=m.S.CallLifecycleRepository
    m.row=function() return m.db.horses[m.t.horseId] end
    m.read=function() return m.S.OwnedHorses.Get({horseId=m.t.horseId},1,m.context) end
    m.prepare=function()
        local r=m.S.Calls.Prepare({expectedSelectionRevision=1},1,m.context); assert(r.ok,r.code)
        m.id=r.value.generationId
        assert(m.S.Calls.ClaimSubmission({generationId=m.id},1,m.context).ok)
        m.identity={generationId=m.id,observerId='c0000000-0000-4000-8000-000000000001',netId=71,initialOwner=1,bucket=0,modelKey='a_c_horse_morgan_bay'}
        return r
    end
    m.bind=function() return m.l.Bind(m.context,m.id,m.identity) end
    m.begin=function() return m.l.BeginCleanup(m.t.characterId,m.id) end
    m.finish=function() return m.l.FinishCleanup(m.t.characterId,m.id,{generationId=m.id,observerId=m.identity.observerId,netId=71,disappeared=true}) end
    return m
end
local function active() local m=fixture(); m.prepare(); assert(m.bind().ok); return m end
local function pending() local m=active(); assert(m.begin().ok); return m end

test('initial purchased horse remains stored at revision zero without runtime history',function()
    local m=fixture(); local r=m.read()
    assert(r.ok and r.value.availability=='stored' and r.value.projectionRevision==0 and size(m.db.runtimeEvents)==0)
end)
test('binding atomically activates projection and owned read while retaining purchase history',function()
    local m=active(); local r=m.read()
    assert(r.ok and r.value.availability=='active' and r.value.projectionRevision==1)
    assert(size(m.db.runtimeEvents)==1 and size(m.db.history)==1 and size(m.db.outbox)==1)
    assert(m.asset.status=='active' and m.stable().revision==1)
end)
test('cleanup intent retains active projection until verified disappearance commit',function()
    local m=pending(); assert(m.row().availability=='active' and m.row().revision==1)
    assert(m.finish().ok and m.row().availability=='stored' and m.row().revision==2)
    local r=m.read(); assert(r.ok and r.value.availability=='stored' and r.value.projectionRevision==2)
end)
test('new generation advances stored and active revisions without rewriting old receipts',function()
    local m=pending(); assert(m.finish().ok); local old=m.id
    m.prepare(); assert(m.id~=old and m.bind().ok and m.row().revision==3)
    assert(m.begin().ok and m.finish().ok and m.row().revision==4 and size(m.db.runtimeEvents)==4)
end)
test('aborting prepared generation never changes horse projection',function()
    local m=fixture(); local r=m.S.Calls.Prepare({expectedSelectionRevision=1},1,m.context); assert(r.ok)
    assert(m.S.Calls.Abort({generationId=r.value.generationId},1,m.context).ok)
    assert(m.row().revision==0 and m.row().availability=='stored' and size(m.db.runtimeEvents)==0)
end)
test('missing or altered runtime receipt cannot authorize active projection',function()
    local changes={function(m) m.db.runtimeEvents={} end,
        function(m) for _,e in pairs(m.db.runtimeEvents) do e.reason='observed_cleanup' end end,
        function(m) for _,e in pairs(m.db.runtimeEvents) do e.prior_revision=99 end end,
        function(m) for _,e in pairs(m.db.runtimeEvents) do e.event_id='bad' end end,
        function(m) for _,e in pairs(m.db.runtimeEvents) do e.generation_id='c0000000-0000-4000-8000-000000000099' end end}
    for _,change in ipairs(changes) do local m=active(); change(m); assert(not m.read().ok) end
end)
test('availability and revision parity corruption fail closed',function()
    local m=active(); m.row().revision=0; assert(not m.read().ok)
    m=active(); m.row().availability='stored'; assert(not m.read().ok)
end)
test('active projection cannot survive loss of its exact runtime slot as an authorized read',function()
    local m=active(); m.db.callSlots={}; assert(not m.read().ok)
    m=active(); m.db.callSlots[m.t.characterId].generation_id='c0000000-0000-4000-8000-000000000099'
    assert(not m.read().ok)
end)
test('activation history insertion and projection CAS failures roll back binding and lease',function()
    for _,flag in ipairs({'failRuntimeEvent','failProjectionCas','failBindingInsert','failLifecycleCas'}) do
        local m=fixture(); m.prepare(); m[flag]=true; assert(not m.bind().ok)
        assert(m.row().availability=='stored' and m.row().revision==0 and size(m.db.runtimeEvents)==0)
        assert(not m.db.callBindings[m.id] and m.db.callLeases[m.id].state=='submitting')
    end
end)
test('cleanup history projection and binding failures roll the entire release back',function()
    for _,flag in ipairs({'failRuntimeEvent','failProjectionCas','failBindingCas','failLifecycleCas','failCallDelete'}) do
        local m=pending(); m[flag]=true; assert(not m.finish().ok)
        assert(m.row().availability=='active' and m.row().revision==1 and size(m.db.runtimeEvents)==1)
        assert(m.db.callLeases[m.id].state=='cleanup_pending' and m.db.callSlots[m.t.characterId])
    end
end)
test('unknown activation commit is readable and cannot insert duplicate activation',function()
    local m=fixture(); m.prepare(); m.unknownCommit=true; assert(m.bind().code=='database_error')
    m.unknownCommit=false
    assert(m.read().value.availability=='active' and size(m.db.runtimeEvents)==1)
    assert(m.bind().code=='binding_conflict' and m.row().revision==1)
end)
test('unknown release commit and old replay preserve later active projection',function()
    local m=pending(); m.unknownCommit=true; assert(m.finish().code=='database_error'); m.unknownCommit=false
    assert(m.read().value.projectionRevision==2 and m.finish().ok and size(m.db.runtimeEvents)==2)
    local old=m.id; local evidence={generationId=old,observerId=m.identity.observerId,netId=71,disappeared=true}
    m.prepare(); assert(m.bind().ok)
    assert(m.l.FinishCleanup(m.t.characterId,old,evidence).ok)
    assert(m.row().availability=='active' and m.row().revision==3 and size(m.db.runtimeEvents)==3)
end)
local function recovery(bound)
    local m=fixture(); m.prepare()
    local old='d0000000-0000-4000-8000-000000000001'; local new='e0000000-0000-4000-8000-000000000001'
    assert(m.l.RecordProcessEpoch(m.context,m.id,old).ok)
    if bound then assert(m.bind().ok) end
    assert(m.l.Reconcile(m.t.characterId,m.id,'restart_lost_observation').ok)
    m.env.GetConvar=function() return new end
    m.resolve=function() return m.l.ResolveProcessEnded(m.t.characterId,m.id,new) end
    return m
end
test('bound process-end recovery stores projection with immutable recovery receipt',function()
    local m=recovery(true); assert(m.row().availability=='active' and m.resolve().ok)
    assert(m.row().availability=='stored' and m.row().revision==2 and m.read().ok)
    local event=m.db.runtimeEvents['stables.runtime:'..m.id..':stored']; assert(event.reason=='process_ended')
    assert(m.resolve().value.replayed and size(m.db.runtimeEvents)==2)
end)
test('unbound process-end recovery leaves original stored projection untouched',function()
    local m=recovery(false); assert(m.resolve().ok)
    assert(m.row().availability=='stored' and m.row().revision==0 and size(m.db.runtimeEvents)==0 and m.read().ok)
end)
test('recovery audit failure rolls projection and history back with its generation',function()
    local m=recovery(true); m.failRecoveryInsert=true; assert(not m.resolve().ok)
    assert(m.row().availability=='active' and m.row().revision==1 and size(m.db.runtimeEvents)==1)
    assert(m.db.callLeases[m.id].state=='reconciliation_required' and not m.db.callRecoveries[m.id])
end)
test('historical purchase evidence survives active runtime state without rewriting outbox',function()
    local m=active(); local r=m.S.FulfillmentRepository.GetHistorical(m.t.operationId,m.t.characterId)
    assert(r.ok and r.value.historical and size(m.db.history)==1 and size(m.db.outbox)==1)
    assert(m.fulfill().ok and m.row().availability=='active' and size(m.db.runtimeEvents)==1)
end)
test('canonical ownership still denies an otherwise valid active local projection',function()
    local m=active(); m.asset.owner.holderId='20000000-0000-4000-8000-000000000099'
    assert(m.read().code=='horse_not_found')
end)
test('selected active horse is a no-op selection but busy clear remains refused',function()
    local m=active(); assert(m.select(1).ok and m.stable().revision==1)
    assert(m.clear(1).code=='horse_busy' and m.read().value.availability=='active')
end)
test('stored receipt must match the actual normal or process-ended release kind',function()
    local m=pending(); assert(m.finish().ok)
    m.db.runtimeEvents['stables.runtime:'..m.id..':stored'].reason='process_ended'
    assert(not m.read().ok)
end)
test('orphan unsubmitted generation cannot make a horse look freely stored',function()
    local m=fixture(); m.prepare(); m.db.callSlots={}
    assert(not m.read().ok and m.row().availability=='stored')
end)
test('reconciliation retains active projection until process-end proof commits',function()
    local m=active(); assert(m.l.Reconcile(m.t.characterId,m.id,'identity_lost').ok)
    local read=m.read(); assert(read.ok and read.value.availability=='active' and read.value.projectionRevision==1)
    assert(size(m.db.runtimeEvents)==1)
end)

test('owned snapshot reuses validated registration but exposes no private registration in player view',function()
    local m=active()
    m.S.AssetRegistration.Get=function() error('duplicate registration read must not occur') end
    local bundled=m.S.FulfillmentRepository.GetOwnedSnapshot(m.t.operationId,m.t.characterId)
    assert(bundled.ok and bundled.value.horse.availability=='active' and bundled.value.registration.assetId==m.asset.assetId)
    local view=m.read(); assert(view.ok and view.value.registration==nil and view.value.horse==nil)
end)
test('fresh canonical ownership after bundled transaction still denies access immediately',function()
    local m=active(); local get=m.S.FulfillmentRepository.GetOwnedSnapshot
    m.S.FulfillmentRepository.GetOwnedSnapshot=function(...)
        local r=get(...); m.asset.owner.holderId='20000000-0000-4000-8000-000000000099'; return r
    end
    assert(m.read().code=='horse_not_found')
end)
test('owned snapshot retains purchase history and current projection checks',function()
    local m=active(); m.db.history={}
    assert(m.S.FulfillmentRepository.GetOwnedSnapshot(m.t.operationId,m.t.characterId).code=='fulfillment_incomplete')
    m=active(); m.row().revision=0
    assert(m.S.FulfillmentRepository.GetOwnedSnapshot(m.t.operationId,m.t.characterId).code=='invalid_projection')
end)
local function CountLeaseReads(m)
    local counts={lease=0,binding=0}; local transaction=m.env.DB.transaction
    m.env.DB.transaction=function(body)
        return transaction(function(tx)
            local one=tx.one
            tx.one=function(sql,...)
                if sql:find('SELECT * FROM fs_call_leases',1,true) then counts.lease=counts.lease+1 end
                if sql:find('SELECT * FROM fs_call_bindings',1,true) then counts.binding=counts.binding+1 end
                return one(sql,...)
            end
            return body(tx)
        end)
    end
    return counts
end
test('active projection reads its shared event and slot lease only once per snapshot',function()
    local m=active(); local counts=CountLeaseReads(m); local reads=0; local read=m.S.Assets.ReadHorse
    m.S.Assets.ReadHorse=function(...) assert(not m.inTx); reads=reads+1; return read(...) end
    assert(m.read().ok and counts.lease==1 and counts.binding==1 and reads==1)
    assert(m.read().ok and counts.lease==2 and counts.binding==2 and reads==2)
end)
test('different historical and current generations are both freshly validated',function()
    local m=pending(); assert(m.finish().ok); m.prepare()
    local counts=CountLeaseReads(m)
    assert(m.read().ok and counts.lease==2 and counts.binding==2 and m.row().availability=='stored')
end)
test('bundled registration data is isolated from later reads and database state',function()
    local m=active(); local r=m.S.FulfillmentRepository.GetOwnedSnapshot(m.t.operationId,m.t.characterId)
    assert(r.ok); r.value.registration.request.modelKey='tampered'
    local next=m.S.FulfillmentRepository.GetOwnedSnapshot(m.t.operationId,m.t.characterId)
    assert(next.ok and next.value.registration.request.modelKey=='a_c_horse_morgan_bay' and m.read().ok)
end)

test('joined owned artifacts match ordinary fulfillment views across lifecycle states',function()
    for _,make in ipairs({fixture,active,pending,function() local m=pending(); assert(m.finish().ok); return m end}) do
        local m=make()
        local regular=m.S.FulfillmentRepository.Get(m.t.operationId,m.t.characterId)
        local bundled=m.S.FulfillmentRepository.GetOwnedSnapshot(m.t.operationId,m.t.characterId)
        assert(regular.ok and bundled.ok)
        for k,v in pairs(regular.value) do assert(bundled.value.horse[k]==v,k) end
    end
end)

test('joined owned artifacts preserve missing and tampered receipt refusal',function()
    local mutations={
        function(m) m.db.history={} end,
        function(m) m.db.outbox={} end,
        function(m) m.db.horses={} end,
        function(m) for _,r in pairs(m.db.history) do r[1]='tampered' end end,
        function(m) for _,r in pairs(m.db.history) do r[5]='{}' end end,
        function(m) for _,r in pairs(m.db.outbox) do r[1]='tampered' end end,
        function(m) for _,r in pairs(m.db.outbox) do r[4]='{}' end end,
        function(m) for _,r in pairs(m.db.history) do r[4]='wrong_kind' end end,
        function(m) for _,r in pairs(m.db.outbox) do r[3]='wrong_event' end end
    }
    for _,mutate in ipairs(mutations) do
        local m=active(); mutate(m)
        local old=m.S.FulfillmentRepository.Get(m.t.operationId,m.t.characterId)
        local joined=m.S.FulfillmentRepository.GetOwnedSnapshot(m.t.operationId,m.t.characterId)
        assert(not old.ok and not joined.ok and old.code==joined.code)
    end
end)

test('owned purchase artifacts use one joined query without standalone artifact reads',function()
    local m=active(); local joined,separate=0,0; local transaction=m.env.DB.transaction
    m.env.DB.transaction=function(body)
        return transaction(function(tx)
            local one=tx.one
            tx.one=function(sql,...)
                if sql:find('FROM fs_horses AS horse',1,true) then joined=joined+1 end
                if sql:find('SELECT * FROM fs_horses WHERE origin_operation_id=',1,true)
                    or sql:find('SELECT * FROM fs_horse_history WHERE operation_id=',1,true)
                    or sql:find('SELECT * FROM fs_outbox WHERE operation_id=',1,true) then separate=separate+1 end
                return one(sql,...)
            end
            return body(tx)
        end)
    end
    assert(m.read().ok and joined==1 and separate==0)
    assert(m.read().ok and joined==2 and separate==0)
end)

test('joined artifact query errors fail closed without retaining a cached snapshot',function()
    local m=active(); local transaction=m.env.DB.transaction
    m.env.DB.transaction=function(body)
        return transaction(function(tx)
            local one=tx.one
            tx.one=function(sql,...)
                if sql:find('FROM fs_horses AS horse',1,true) then error({code='QUERY_FAILED',outcome='rolled_back'}) end
                return one(sql,...)
            end
            return body(tx)
        end)
    end
    assert(m.read().code=='database_error')
    m.env.DB.transaction=transaction
    assert(m.read().ok and m.row().availability=='active')
end)

test('projection groups independent event and slot reads in one bounded transaction batch',function()
    local m=active(); local transaction=m.env.DB.transaction; local batches,leases=0,0
    m.env.DB.transaction=function(body)
        return transaction(function(tx)
            local batch=tx.batch
            tx.batch=function(statements)
                if statements[1].sql:find('fs_character_stables',1,true) then return batch(statements) end
                assert(#statements==2)
                if statements[1].sql:find('fs_horse_runtime_events',1,true) then
                    batches=batches+1
                    assert(statements[1].params[1]==m.t.horseId and statements[2].params[1]==m.t.characterId)
                else
                    leases=leases+1
                    assert(statements[1].params[1]==m.id and statements[1].params[2]==m.t.characterId
                        and statements[2].params[1]==m.id)
                end
                return batch(statements)
            end
            return body(tx)
        end)
    end
    assert(m.read().ok and batches==1 and leases==1)
    assert(m.read().ok and batches==2 and leases==2)
end)

test('projection refuses malformed or oversized batched rows and batch query errors',function()
    for _,value in ipairs({{},{{},{} ,{}},{{{},{}},{}},{{},{{},{}}}}) do
        local m=active(); local transaction=m.env.DB.transaction
        m.env.DB.transaction=function(body) return transaction(function(tx) local batch=tx.batch; tx.batch=function(statements)
            if statements[1].sql:find('fs_horse_runtime_events',1,true) then return value end
            return batch(statements) end; return body(tx) end) end
        assert(m.read().code=='invalid_projection')
    end
    local m=active(); local transaction=m.env.DB.transaction
    m.env.DB.transaction=function(body) return transaction(function(tx)
        tx.batch=function() error({code='QUERY_FAILED',outcome='rolled_back'}) end
        return body(tx)
    end) end
    assert(m.read().code=='database_error')
end)

test('batched lease binding validation preserves saved row checks without rereading binding',function()
    local m=active(); local transaction=m.env.DB.transaction
    m.S.CallLifecycleRepository.ValidateState=function() error('projection must validate its batched binding') end
    assert(m.read().ok)
    m.db.callBindings[m.id].network_id=-1
    assert(m.read().code=='invalid_call_binding')
end)

test('batched lease binding mismatch or missing lease refuses access',function()
    local m=active(); m.db.callBindings[m.id].generation_id='f0000000-0000-4000-8000-000000000001'
    assert(m.read().code=='invalid_call_binding')
    m=active(); m.db.callLeases[m.id].character_id='20000000-0000-4000-8000-000000000099'
    assert(m.read().code=='call_not_found')
end)

test('malformed binding batch response fails closed and later reads remain fresh',function()
    local m=active(); local transaction=m.env.DB.transaction
    m.env.DB.transaction=function(body) return transaction(function(tx)
        local batch=tx.batch
        tx.batch=function(statements)
            if statements[1].sql:find('fs_call_leases',1,true) then return {{},{{},{}}} end
            return batch(statements)
        end
        return body(tx)
    end) end
    assert(m.read().code=='invalid_projection')
    m.env.DB.transaction=transaction
    assert(m.read().ok)
end)

test('distinct previous receipt and current slot generations share one scoped lease batch',function()
    local m=pending(); assert(m.finish().ok); local old=m.id; m.prepare(); local current=m.id
    local transaction=m.env.DB.transaction; local seen=0
    m.env.DB.transaction=function(body) return transaction(function(tx)
        local batch=tx.batch
        tx.batch=function(statements)
            if statements[1].sql:find('SELECT * FROM fs_call_leases',1,true) then
                seen=seen+1; assert(#statements==4)
                assert(statements[1].params[1]==old and statements[2].params[1]==old)
                assert(statements[3].params[1]==current and statements[4].params[1]==current)
                assert(statements[1].params[2]==m.t.characterId and statements[3].params[2]==m.t.characterId)
            end
            return batch(statements)
        end
        return body(tx)
    end) end
    assert(m.read().ok and seen==1)
    assert(m.read().ok and seen==2)
end)

test('grouped projection generations each retain independent identity and binding validation',function()
    for _,historical in ipairs({false,true}) do
        local m=pending(); assert(m.finish().ok); local old=m.id; m.prepare()
        local id=historical and old or m.id
        m.db.callLeases[id].asset_id='f0000000-0000-4000-8000-000000000001'
        assert(m.read().code=='invalid_projection')
    end
end)

print(count..'/'..count..' horse projection cases passed; native replication and SQL concurrency require live checks.')
