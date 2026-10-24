local base=assert(loadfile('tests/fixtures/selection_services.lua'))()
local count=0
local function test(name,fn)
    local ok,err=pcall(fn); assert(ok,name..': '..tostring(err)); count=count+1; print('PASS call lifecycle '..name)
end
local function fixture()
    local m=base(); assert(m.select(0).ok)
    for _,path in ipairs({'server/call_repository.lua','server/call_lifecycle_repository.lua','server/calls.lua'}) do
        assert(loadfile(path,'t',m.env))()
    end
    m.env.StablesConfig.callPreparation=true; assert(m.S.Calls.Start().ok)
    m.id=m.S.Calls.Prepare({expectedSelectionRevision=1},1,m.context).value.generationId
    assert(m.S.Calls.ClaimSubmission({generationId=m.id},1,m.context).ok)
    m.l=m.S.CallLifecycleRepository
    m.identity={generationId=m.id,observerId='c0000000-0000-4000-8000-000000000001',netId=71,
        initialOwner=1,bucket=0,modelKey='a_c_horse_morgan_bay'}
    m.evidence={generationId=m.id,observerId=m.identity.observerId,netId=71,disappeared=true}
    m.bind=function() return m.l.Bind(m.context,m.id,m.identity) end
    m.begin=function() return m.l.BeginCleanup(m.t.characterId,m.id) end
    m.finish=function() return m.l.FinishCleanup(m.t.characterId,m.id,m.evidence) end
    m.get=function(id) return m.S.CallRepository.Get(m.t.characterId,id) end
    m.reconcile=function(reason) return m.l.Reconcile(m.t.characterId,m.id,reason or 'restart_lost_observation') end
    return m
end
local function active() local m=fixture(); assert(m.bind().ok); return m end
local function pending() local m=active(); assert(m.begin().ok); return m end

test('binding persists exact identity and active generation atomically',function()
    local m=fixture(); local r=m.bind()
    assert(r.ok and r.value.state=='active' and r.value.revision==2)
    local b=m.db.callBindings[m.id]
    assert(b.observer_id==m.identity.observerId and b.network_id==71 and b.initial_owner==1 and b.routing_bucket==0)
    assert(m.get().value.state=='active' and m.db.horses[m.t.horseId].availability=='active' and m.db.horses[m.t.horseId].revision==1)
end)

test('duplicate bind cannot replace durable network identity',function()
    local m=active(); m.identity.netId=72
    assert(m.bind().code=='binding_conflict' and m.db.callBindings[m.id].network_id==71)
end)

test('binding from replacement session or another character is denied',function()
    local m=fixture(); m.context.sessionId='replacement'
    assert(m.bind().code=='call_recovery_required' and not m.db.callBindings[m.id])
    m.context.characterId='20000000-0000-4000-8000-000000000099'
    assert(m.bind().code=='call_not_found' and not m.db.callBindings[m.id])
end)

test('invalid observation fields never bind',function()
    local invalid={netId={0,1.5,2147483648},observerId={'bad'},initialOwner={2},bucket={1},modelKey={'a_c_horse_other'},generationId={'wrong'}}
    for field,values in pairs(invalid) do for _,value in ipairs(values) do
        local m=fixture(); m.identity[field]=value
        assert(m.bind().code=='invalid_call_binding' and not m.db.callBindings[m.id],field)
    end end
end)

test('binding insertion and generation CAS failure roll back both artifacts',function()
    local m=fixture(); m.failBindingInsert=true
    assert(m.bind().code=='database_error' and m.db.callLeases[m.id].state=='submitting' and not m.db.callBindings[m.id])
    m=fixture(); m.failLifecycleCas=true
    assert(m.bind().code=='revision_conflict' and m.db.callLeases[m.id].state=='submitting' and not m.db.callBindings[m.id])
end)

test('unknown binding commit is inspectable and never rebinds',function()
    local m=fixture(); m.unknownCommit=true; assert(m.bind().code=='database_error')
    m.unknownCommit=false
    assert(m.get().value.state=='active' and m.bind().code=='binding_conflict')
end)

test('cleanup intent persists before release and is idempotent',function()
    local m=active(); assert(m.finish().code=='cleanup_not_pending')
    assert(m.begin().value.revision==3 and m.begin().value.revision==3)
    assert(m.db.callBindings[m.id].state=='cleanup_pending' and m.db.callSlots[m.t.characterId])
end)

test('finish cleanup requires exact observer generation network ID and disappearance',function()
    local changes={function(e) e.observerId='c0000000-0000-4000-8000-000000000099' end,
        function(e) e.netId=72 end,function(e) e.generationId='bad' end,function(e) e.disappeared=false end}
    for _,change in ipairs(changes) do
        local m=pending(); change(m.evidence)
        assert(m.finish().code=='cleanup_unverified' and m.db.callSlots[m.t.characterId])
    end
end)

test('finish retains cleared binding and released receipt and frees exact slot',function()
    local m=pending(); local r=m.finish()
    assert(r.ok and r.value.state=='released' and r.value.revision==4)
    assert(m.db.callBindings[m.id].state=='cleared' and m.db.callBindings[m.id].revision==2)
    assert(m.get().value.state=='empty' and m.get(m.id).value.revision==4 and m.finish().value.revision==4)
end)

test('finish CAS and exact-slot delete failures roll back all state changes',function()
    for _,flag in ipairs({'failBindingCas','failLifecycleCas','failCallDelete'}) do
        local m=pending(); m[flag]=true
        assert(m.finish().code=='revision_conflict')
        assert(m.db.callLeases[m.id].state=='cleanup_pending' and m.db.callBindings[m.id].state=='cleanup_pending'
            and m.db.callSlots[m.t.characterId],flag)
    end
end)

test('unknown cleanup commit converges by exact receipt without touching replacement slot',function()
    local m=pending(); m.unknownCommit=true; assert(m.finish().code=='database_error')
    m.unknownCommit=false; assert(m.get().value.state=='empty')
    local nextId=m.S.Calls.Prepare({expectedSelectionRevision=1},1,m.context).value.generationId
    assert(nextId~=m.id and m.finish().value.revision==4 and m.get().value.generationId==nextId)
end)

test('unbound submitted generation cannot use entity cleanup as an abort',function()
    local m=fixture()
    assert(m.begin().code=='call_reconciliation_required' and not m.finish().ok)
    assert(m.db.callSlots[m.t.characterId] and m.db.callLeases[m.id].state=='submitting')
end)

test('reconciliation retains submitted slot without manufacturing an entity',function()
    local m=fixture(); local r=m.reconcile('submission_unknown')
    assert(r.ok and r.value.state=='reconciliation_required' and r.value.revision==2)
    assert(m.get().value.state=='reconciliation_required' and not m.db.callBindings[m.id])
    assert(m.reconcile('submission_unknown').value.revision==2 and not m.begin().ok and not m.finish().ok)
    assert(m.S.Calls.Abort({generationId=m.id},1,m.context).code=='call_cleanup_required')
end)

test('lost observer fences active or cleanup identity and never frees the slot',function()
    for _,factory in ipairs({active,pending}) do
        local m=factory(); local old=m.db.callLeases[m.id].revision
        assert(m.reconcile().value.revision==old+1)
        assert(m.db.callBindings[m.id].state=='reconciliation_required' and m.get().value.state=='reconciliation_required')
        assert(not m.finish().ok and m.db.callSlots[m.t.characterId])
    end
end)

test('reconciliation write failure is atomic',function()
    local m=active(); m.failLifecycleCas=true
    assert(m.reconcile().code=='revision_conflict' and m.db.callBindings[m.id].state=='bound')
    assert(m.get().value.state=='active')
end)

test('reloaded repository preserves binding but cannot substitute a new observer',function()
    local m=pending()
    for _,file in ipairs({'server/call_repository.lua','server/call_lifecycle_repository.lua'}) do assert(loadfile(file,'t',m.env))() end
    m.l=m.S.CallLifecycleRepository
    assert(m.get().value.state=='cleanup_pending')
    m.evidence.observerId='c0000000-0000-4000-8000-000000000099'
    assert(m.finish().code=='cleanup_unverified' and m.db.callSlots[m.t.characterId])
end)

test('missing or contradictory binding fails closed on public generation read',function()
    local m=active(); m.db.callBindings={}; assert(m.get().code=='invalid_call_binding')
    m=active(); m.db.callBindings[m.id].state='cleared'; m.db.callBindings[m.id].revision=2
    assert(m.get().code=='invalid_call_binding')
    m=active(); m.db.callBindings[m.id].state='unknown'; m.db.callBindings[m.id].revision=nil
    assert(m.get().code=='invalid_call_binding')
end)

test('binding attached to prepared generation cannot appear as harmless unsubmitted',function()
    local m=active(); m.db.callLeases[m.id].state='prepared'; m.db.callLeases[m.id].revision=0
    assert(m.get().code=='invalid_call_binding')
end)

test('lifecycle operations never register client routes or invoke native deletion',function()
    local m=fixture()
    m.env.DeleteEntity=function() error('repository cannot delete entities') end
    m.env.TriggerClientEvent=function() error('repository cannot dispatch native instructions') end
    assert(m.bind().ok and m.begin().ok and m.finish().ok)
end)

test('unknown cleanup-intent commit retains pending state and converges without releasing',function()
    local m=active(); m.unknownCommit=true; assert(m.begin().code=='database_error')
    m.unknownCommit=false
    assert(m.get().value.state=='cleanup_pending' and m.begin().value.revision==3)
    assert(m.db.callSlots[m.t.characterId] and m.db.callBindings[m.id].state=='cleanup_pending')
end)

test('unknown reconciliation commit keeps slot and retained reason on retry',function()
    local m=active(); m.unknownCommit=true; assert(m.reconcile().code=='database_error')
    m.unknownCommit=false
    assert(m.get().value.state=='reconciliation_required' and m.reconcile().value.revision==3)
    assert(m.db.callSlots[m.t.characterId] and m.db.callBindings[m.id].reason=='restart_lost_observation')
end)

test('ordinary abort cannot bypass a contradictory prepared binding',function()
    local m=active(); m.db.callLeases[m.id].state='prepared'; m.db.callLeases[m.id].revision=0
    assert(m.S.CallRepository.Abort(m.t.characterId,m.id).code=='invalid_call_binding')
    assert(m.db.callSlots[m.t.characterId] and m.db.callBindings[m.id].state=='bound')
end)

local OLD='d0000000-0000-4000-8000-000000000001'
local NEW='e0000000-0000-4000-8000-000000000001'
local function recoverable(mode)
    local m=fixture()
    assert(m.l.RecordProcessEpoch(m.context,m.id,OLD).ok)
    if mode~='unbound' then assert(m.bind().ok) end
    if mode=='pending' then assert(m.begin().ok) end
    assert(m.reconcile('identity_lost').ok)
    m.currentEpoch=NEW
    m.env.GetConvar=function(key,default) assert(key=='bcc_stables_process_epoch_v1'); return m.currentEpoch or default end
    m.resolve=function() return m.l.ResolveProcessEnded(m.t.characterId,m.id,NEW) end
    return m
end
test('process-end recovery releases bound pending and unbound generations with distinct audited tombstone',function()
    for _,mode in ipairs({'bound','pending','unbound'}) do
        local m=recoverable(mode); local prior=m.get().value.revision
        local r=m.resolve(); assert(r.ok and r.value.state=='released' and r.value.revision==5 and not r.value.replayed)
        assert(r.value.recovery.priorRevision==prior and r.value.recovery.originalProcessEpoch==OLD)
        assert(r.value.recovery.resolvedProcessEpoch==NEW and r.value.entityMutation==false)
        assert(m.get().value.state=='empty' and m.get(m.id).value.revision==5)
        assert(m.db.callRecoveries[m.id] and m.db.callEpochs[m.id].process_epoch==OLD)
        assert(mode=='unbound' or (m.db.callBindings[m.id].state=='cleared' and m.db.callBindings[m.id].reason==nil))
        assert(m.db.characters[m.t.characterId].revision==1 and m.db.horses[m.t.horseId].availability=='stored')
    end
end)
test('same-process recovery cannot free even an unbound uncertain submission',function()
    local m=recoverable('unbound'); m.currentEpoch=OLD
    assert(m.l.ResolveProcessEnded(m.t.characterId,m.id,OLD).code=='process_still_current')
    assert(m.db.callSlots[m.t.characterId] and not m.db.callRecoveries[m.id])
end)
test('missing old process evidence remains fenced rather than backfilled',function()
    local m=recoverable('bound'); m.db.callEpochs[m.id]=nil
    assert(m.resolve().code=='process_evidence_required' and not m.db.callRecoveries[m.id])
    assert(m.get().value.state=='reconciliation_required')
end)
test('invalid current epoch and wrong process convar never release',function()
    local m=recoverable('bound')
    assert(m.l.ResolveProcessEnded(m.t.characterId,m.id,'bad').code=='invalid_input')
    m.currentEpoch=OLD; assert(m.resolve().code=='process_identity_lost' and m.db.callSlots[m.t.characterId])
end)
test('ordinary submitted active and released states cannot bypass reconciliation',function()
    for _,mode in ipairs({'submitting','active','released'}) do
        local m=fixture(); assert(m.l.RecordProcessEpoch(m.context,m.id,OLD).ok)
        if mode~='submitting' then assert(m.bind().ok) end
        if mode=='released' then assert(m.begin().ok and m.finish().ok) end
        m.env.GetConvar=function() return NEW end
        assert(m.l.ResolveProcessEnded(m.t.characterId,m.id,NEW).code=='recovery_not_required')
        assert(not m.db.callRecoveries[m.id])
    end
end)
test('recovery audit binding lease and slot failures each roll back all recovery changes',function()
    for _,flag in ipairs({'failRecoveryInsert','failBindingCas','failLifecycleCas','failCallDelete'}) do
        local m=recoverable('bound'); m[flag]=true
        assert(not m.resolve().ok and not m.db.callRecoveries[m.id])
        assert(m.get().value.state=='reconciliation_required' and m.db.callBindings[m.id].state=='reconciliation_required')
        assert(m.db.callSlots[m.t.characterId] and m.db.callEpochs[m.id].process_epoch==OLD)
    end
end)
test('unknown recovery commit is readable and replay cannot free a replacement slot',function()
    local m=recoverable('bound'); m.unknownCommit=true
    assert(m.resolve().code=='database_error')
    m.unknownCommit=false
    assert(m.get(m.id).value.revision==5 and m.resolve().value.replayed)
    local next=m.S.Calls.Prepare({expectedSelectionRevision=1},1,m.context); assert(next.ok)
    local receipt=m.resolve(); assert(receipt.ok and receipt.value.replayed and m.get().value.generationId==next.value.generationId)
    assert(m.db.callSlots[m.t.characterId].generation_id==next.value.generationId)
end)
test('missing or tampered recovery audit cannot validate a released revision-five receipt',function()
    local changes={function(m) m.db.callRecoveries[m.id]=nil end,
        function(m) m.db.callRecoveries[m.id].original_epoch=NEW end,
        function(m) m.db.callRecoveries[m.id].resolved_epoch=OLD end,
        function(m) m.db.callRecoveries[m.id].prior_revision=2 end,
        function(m) m.db.callRecoveries[m.id].prior_reason=nil end}
    for _,mutate in ipairs(changes) do
        local m=recoverable('bound'); assert(m.resolve().ok); mutate(m)
        assert(not m.get(m.id).ok and not m.resolve().ok)
    end
end)
test('process change during recovery transaction rolls audit binding lease and slot back',function()
    local m=recoverable('bound'); local transaction=m.env.DB.transaction
    m.env.DB.transaction=function(body)
        return transaction(function(tx)
            local exec=tx.exec
            tx.exec=function(sql,...)
                local result=exec(sql,...)
                if sql:find('DELETE FROM fs_call_slots',1,true) then m.currentEpoch=OLD end
                return result
            end
            return body(tx)
        end)
    end
    assert(m.resolve().code=='process_identity_lost' and not m.db.callRecoveries[m.id])
    assert(m.get().value.state=='reconciliation_required' and m.db.callSlots[m.t.characterId])
end)
test('process-end recovery never invokes entity or client operations',function()
    local m=recoverable('bound')
    for _,name in ipairs({'DeleteEntity','NetworkGetEntityFromNetworkId','TriggerClientEvent','CreatePed'}) do
        m.env[name]=function() error('entity operation forbidden in recovery') end
    end
    assert(m.resolve().ok and m.resolve().value.replayed)
end)
test('foreign character cannot resolve or inspect another recovery receipt',function()
    local m=recoverable('bound')
    assert(m.l.ResolveProcessEnded('20000000-0000-4000-8000-000000000099',m.id,NEW).code=='call_not_found')
    assert(m.db.callSlots[m.t.characterId] and not m.db.callRecoveries[m.id])
end)

test('replaying recovery from a later process retains the original audit unchanged',function()
    local m=recoverable('bound'); assert(m.resolve().ok)
    local later='f0000000-0000-4000-8000-000000000001'; m.currentEpoch=later
    local r=m.l.ResolveProcessEnded(m.t.characterId,m.id,later)
    assert(r.ok and r.value.replayed and r.value.recovery.resolvedProcessEpoch==NEW)
    assert(m.db.callRecoveries[m.id].resolved_epoch==NEW)
end)

test('lifecycle mutations validate under locks without standalone lease snapshot',function()
    local m=fixture(); local validate=m.l.ValidateSavedState; local reads=0
    m.S.CallRepository.Get=function() error('redundant pre-transaction snapshot') end
    m.l.ValidateSavedState=function(tx,lease,row)
        assert(m.inTx and m.locked==m.t.characterId)
        reads=reads+1; return validate(tx,lease,row)
    end
    assert(m.l.RecordProcessEpoch(m.context,m.id,'f0000000-0000-4000-8000-000000000001').ok)
    assert(reads==1)
    assert(m.bind().ok)
    assert(m.begin().ok)
    assert(m.finish().ok)
end)

test('locked lifecycle validation refuses contradictory binding before callback',function()
    local m=fixture(); local called=false
    m.db.callBindings[m.id]={generation_id=m.id}
    local r=m.S.CallRepository.WithLease(m.t.characterId,m.id,function() called=true; return m.S.Ok(true) end)
    assert(r.code=='invalid_call_binding' and not called)
    assert(m.db.callLeases[m.id].state=='submitting' and m.db.callSlots[m.t.characterId])
end)

test('lifecycle batches exact slot lease binding keys in order',function()
    local m=fixture(); local transaction=m.env.DB.transaction; local seen=0
    m.env.DB.transaction=function(body) return transaction(function(tx)
        local batch=tx.batch
        tx.batch=function(statements)
            if statements[1].sql:find('fs_call_slots',1,true) then
                seen=seen+1; assert(#statements==3)
                assert(statements[1].params[1]==m.t.characterId)
                assert(statements[2].sql:find('fs_call_leases',1,true) and statements[2].params[1]==m.id)
                assert(statements[3].sql:find('fs_call_bindings',1,true) and statements[3].params[1]==m.id)
            end
            return batch(statements)
        end
        return body(tx)
    end) end
    assert(m.l.RecordProcessEpoch(m.context,m.id,'f0000000-0000-4000-8000-000000000001').ok and seen==1)
end)

test('malformed lifecycle batch cannot invoke callback or release slot',function()
    for _,bad in ipairs({false,{},{{},{}} ,{{{},{}},{},{}}}) do
        local m=fixture(); local transaction=m.env.DB.transaction; local called=false
        m.env.DB.transaction=function(body) return transaction(function(tx) tx.batch=function() return bad end; return body(tx) end) end
        local r=m.S.CallRepository.WithLease(m.t.characterId,m.id,function() called=true; return m.S.Ok(true) end)
        assert(r.code=='invalid_call' and not called and m.db.callSlots[m.t.characterId])
        assert(m.db.callLeases[m.id].state=='submitting')
    end
end)

test('binding batches projection and identity writes in existing transaction order',function()
    local m=fixture(); local transaction=m.env.DB.transaction; local seen={}
    m.env.DB.transaction=function(body) return transaction(function(tx)
        local batch=tx.batch
        tx.batch=function(statements)
            if statements[1].sql:find('INSERT INTO fs_horse_runtime_events',1,true) then
                assert(#statements==2 and statements[2].sql:find('UPDATE fs_horses',1,true)); seen[#seen+1]='projection'
            elseif statements[1].sql:find('INSERT INTO fs_call_bindings',1,true) then
                assert(#statements==2 and statements[2].sql:find('UPDATE fs_call_leases',1,true)); seen[#seen+1]='binding'
            end
            return batch(statements)
        end
        return body(tx)
    end) end
    assert(m.bind().ok and table.concat(seen,',')=='projection,binding')
end)

test('failed batched binding write headers roll back projection identity and lease together',function()
    for _,kind in ipairs({'fs_horse_runtime_events','fs_call_bindings'}) do
        for _,index in ipairs({1,2}) do
            local m=fixture(); local transaction=m.env.DB.transaction
            m.env.DB.transaction=function(body) return transaction(function(tx)
                local batch=tx.batch
                tx.batch=function(statements)
                    local rows=batch(statements)
                    if statements[1].sql:find('INSERT INTO '..kind,1,true) then rows[index]={affectedRows=0} end
                    return rows
                end
                return body(tx)
            end) end
            assert(not m.bind().ok)
            assert(m.db.callLeases[m.id].state=='submitting' and not m.db.callBindings[m.id])
            assert(m.db.horses[m.t.horseId].availability=='stored' and m.db.horses[m.t.horseId].revision==0)
            assert(next(m.db.runtimeEvents)==nil and m.db.callSlots[m.t.characterId].generation_id==m.id)
        end
    end
end)

print(count..'/'..count..' internal lifecycle cases passed; live native observation is not modeled as authority.')
