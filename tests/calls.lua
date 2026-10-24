local base=assert(loadfile('tests/fixtures/selection_services.lua'))()
local count=0
local function test(name,body)
    local ok,err=pcall(body); assert(ok,name..': '..tostring(err)); count=count+1; print('PASS call preparation '..name)
end
local function size(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local function fixture()
    local m=base(); assert(m.select(0).ok)
    for _,file in ipairs({'server/call_repository.lua','server/call_lifecycle_repository.lua','server/calls.lua'}) do assert(loadfile(file,'t',m.env))() end
    m.env.StablesConfig.callPreparation=true; m.calls=m.S.Calls; assert(m.calls.Start().ok)
    m.prepareCall=function(revision) return m.calls.Prepare({expectedSelectionRevision=revision or 1},1,m.context) end
    m.callGet=function(id) return m.calls.Get(id and {generationId=id} or {},1,m.context) end
    m.abort=function(id) return m.calls.Abort({generationId=id},1,m.context) end
    return m
end
test('durable generation and slot are prepared without changing horse state',function()
    local m=fixture(); local r=m.prepareCall(); assert(r.ok,tostring(r.code))
    assert(r.value.state=='prepared' and r.value.revision==0 and r.value.sessionCurrent and not r.value.entitySpawning)
    assert(size(m.db.callLeases)==1 and size(m.db.callSlots)==1)
    assert(m.db.horses[m.t.horseId].availability=='stored' and m.asset.status=='active')
end)
test('same-session replay and reload retain original generation',function()
    local m=fixture(); local id=m.prepareCall().value.generationId
    assert(m.prepareCall().value.generationId==id and size(m.db.callLeases)==1)
    m.reload(); assert(m.start().ok)
    assert(loadfile('server/call_repository.lua','t',m.env))()
    assert(m.callGet().value.generationId==id)
end)
test('abort retains released receipt and frees only the exact slot',function()
    local m=fixture(); local id=m.prepareCall().value.generationId
    assert(m.abort(id).value.state=='released' and m.abort(id).value.revision==1)
    assert(m.callGet().value.state=='empty' and size(m.db.callLeases)==1 and size(m.db.callSlots)==0)
    local nextId=m.prepareCall().value.generationId; assert(nextId~=id)
    assert(m.abort(id).value.state=='released' and m.callGet().value.generationId==nextId)
end)
test('pending slot blocks selection change but permits same-selection no-op',function()
    local m=fixture(); assert(m.prepareCall().ok)
    assert(m.clear(1).code=='horse_busy' and m.select(1).value.revision==1)
end)
test('previous-session generation requires explicit recovery before another call',function()
    local m=fixture(); local id=m.prepareCall().value.generationId
    m.context.sessionId='session-b'
    assert(not m.callGet().value.sessionCurrent and m.prepareCall().code=='call_recovery_required')
    assert(m.abort(id).value.state=='released' and m.prepareCall().value.generationId~=id)
end)
test('other character cannot inspect or abort known generation',function()
    local m=fixture(); local id=m.prepareCall().value.generationId
    m.context.characterId='20000000-0000-4000-8000-000000000099'
    assert(m.callGet(id).code=='call_not_found' and m.abort(id).code=='call_not_found')
    assert(size(m.db.callSlots)==1)
end)
test('disabled preparation leaves inspect and unsubmitted abort available',function()
    local m=fixture(); local id=m.prepareCall().value.generationId
    m.env.StablesConfig.callPreparation=false; assert(m.calls.Start().ok)
    assert(m.prepareCall().code=='call_preparation_disabled' and m.callGet().value.generationId==id)
    assert(m.abort(id).value.state=='released')
end)
test('stale selection and session changes prevent lease writes',function()
    local m=fixture(); assert(m.prepareCall(0).code=='revision_conflict')
    m.onUuid=function() m.current=false end
    assert(m.prepareCall().code=='session_stale' and size(m.db.callLeases)==0)
end)
test('slot write failure rolls back generation insertion',function()
    local m=fixture(); m.failCallSlot=true
    assert(m.prepareCall().code=='database_error' and size(m.db.callLeases)==0 and size(m.db.callSlots)==0)
end)
test('abort slot-delete failure rolls back released state',function()
    local m=fixture(); local id=m.prepareCall().value.generationId; m.failCallDelete=true
    assert(m.abort(id).code=='revision_conflict' and m.db.callLeases[id].state=='prepared' and size(m.db.callSlots)==1)
end)
test('unknown generation commit recovers by current slot without another generation',function()
    local m=fixture(); local transaction=m.env.DB.transaction
    m.env.DB.transaction=function(body)
        return transaction(function(tx) local r=body(tx); if next(m.db.callSlots) then m.unknownCommit=true end; return r end)
    end
    assert(m.prepareCall().code=='database_error' and size(m.db.callLeases)==1)
    m.env.DB.transaction=transaction; m.unknownCommit=false
    local id=m.callGet().value.generationId; assert(m.prepareCall().value.generationId==id and size(m.db.callLeases)==1)
end)
test('unknown abort commit retains tombstone and can replay safely',function()
    local m=fixture(); local id=m.prepareCall().value.generationId; m.unknownCommit=true
    assert(m.abort(id).code=='database_error')
    m.unknownCommit=false; assert(m.callGet().value.state=='empty' and m.abort(id).value.state=='released')
end)
test('unsupported submitted or active state cannot be aborted as unsubmitted',function()
    local m=fixture(); local id=m.prepareCall().value.generationId; m.db.callLeases[id].state='active'
    assert(m.abort(id).code=='invalid_call' and size(m.db.callSlots)==1)
end)
test('orphan generation and corrupt slot fail closed',function()
    local m=fixture(); local id=m.prepareCall().value.generationId; m.db.callSlots={}
    assert(m.callGet().code=='invalid_call' and m.prepareCall().code=='invalid_projection')
    m=fixture(); id=m.prepareCall().value.generationId; m.db.callSlots[m.t.characterId].horse_id='bad'
    assert(m.callGet().code=='invalid_call' and m.abort(id).code=='invalid_call')
end)
test('strict routes reject client model and supplied identity',function()
    local m=fixture(); local routes={}
    m.S.Core={Call=function(_,name,callback,options) routes[name]=options; return m.S.Ok(true) end}
    assert(m.calls.Install().ok)
    local prepare=routes['stables.horses.call.prepare.v1']; local get=routes['stables.horses.call.get.v1']
    assert(prepare.requireCharacter and prepare.maxPayloadBytes==192 and get.validatePayload({}))
    assert(prepare.validatePayload({expectedSelectionRevision=1}) and not prepare.validatePayload({expectedSelectionRevision=1,modelKey='a_c_horse_morgan_bay'}))
end)
test('selection change during UUID lookup prevents call admission',function()
    local m=fixture(); m.onUuid=function() assert(m.clear(1).ok) end
    assert(m.prepareCall().code=='revision_conflict' and size(m.db.callLeases)==0)
end)
test('canonical change after durable admission leaves only an abortable fence',function()
    local m=fixture(); local reads=0
    m.onAssetRead=function() reads=reads+1; if reads==2 then m.asset.owner.holderId='20000000-0000-4000-8000-000000000099' end end
    assert(m.prepareCall().code=='horse_not_found' and size(m.db.callSlots)==1)
    local id=m.callGet().value.generationId
    assert(m.abort(id).value.state=='released' and m.clear(1).ok)
end)

local function submissionFixture()
    local m=fixture(); m.generation=m.prepareCall().value.generationId
    m.submit=function(id) return m.calls.ClaimSubmission({generationId=id or m.generation},1,m.context) end
    return m
end

test('internal submission claim is durable single-use and cannot use unsubmitted abort',function()
    local m=submissionFixture(); local r=m.submit()
    assert(r.ok and r.value.state=='submitting' and r.value.revision==1 and not r.value.entitySpawning)
    assert(m.submit().code=='submission_conflict' and m.abort(m.generation).code=='call_cleanup_required')
    assert(m.prepareCall().code=='call_cleanup_required' and m.clear(1).code=='horse_busy')
    assert(m.callGet().value.state=='submitting' and size(m.db.callSlots)==1)
    assert(m.db.horses[m.t.horseId].availability=='stored')
end)

test('submitted fence survives reload and disabled preparation',function()
    local m=submissionFixture(); assert(m.submit().ok)
    assert(loadfile('server/call_repository.lua','t',m.env))()
    m.env.StablesConfig.callPreparation=false; assert(m.calls.Start().ok)
    assert(m.callGet().value.state=='submitting' and m.submit().code=='call_preparation_disabled')
    assert(m.abort(m.generation).code=='call_cleanup_required' and size(m.db.callSlots)==1)
end)

test('unknown submission commit remains fenced and cannot authorize replay',function()
    local m=submissionFixture(); local transaction=m.env.DB.transaction
    m.env.DB.transaction=function(body)
        return transaction(function(tx)
            local result=body(tx)
            if m.db.callLeases[m.generation].state=='submitting' then m.unknownCommit=true end
            return result
        end)
    end
    assert(m.submit().code=='database_error')
    m.env.DB.transaction=transaction; m.unknownCommit=false
    assert(m.callGet().value.state=='submitting' and m.submit().code=='submission_conflict')
    assert(m.abort(m.generation).code=='call_cleanup_required')
end)

test('failed submission CAS rolls back and leaves prepared abort available',function()
    local m=submissionFixture(); m.failSubmissionCas=true
    assert(m.submit().code=='revision_conflict' and m.callGet().value.state=='prepared')
    assert(m.abort(m.generation).value.state=='released')
end)

test('submission from another character or session leaves prepared record untouched',function()
    local m=submissionFixture(); m.context.sessionId='replacement'
    assert(m.submit().code=='call_recovery_required' and m.callGet().value.state=='prepared')
    m.context.characterId='20000000-0000-4000-8000-000000000099'
    assert(m.submit().code=='call_not_found' and m.db.callLeases[m.generation].state=='prepared')
end)

test('canonical ownership loss before submission prevents claiming',function()
    local m=submissionFixture(); m.asset.owner.holderId='20000000-0000-4000-8000-000000000099'
    assert(not m.submit().ok and m.db.callLeases[m.generation].state=='prepared')
end)

test('selection changed while preparing submission cannot claim',function()
    local m=submissionFixture(); m.stable().revision=2
    assert(m.submit().code=='revision_conflict' and m.db.callLeases[m.generation].state=='prepared')
end)

test('canonical change after submitted commit suppresses success but retains fence',function()
    local m=submissionFixture(); local reads=0
    m.onAssetRead=function()
        reads=reads+1
        if reads==2 then m.asset.owner.holderId='20000000-0000-4000-8000-000000000099' end
    end
    assert(m.submit().code=='horse_not_found' and m.callGet().value.state=='submitting')
    assert(m.abort(m.generation).code=='call_cleanup_required')
end)

test('submission transaction verifies lease identity projection link and exact slot',function()
    local mutations={
        function(m) m.db.callSlots[m.t.characterId].generation_id='b0000000-0000-4000-8000-000000000999' end,
        function(m) m.db.horses[m.t.horseId].availability='active' end,
        function(m) m.db.callLeases[m.generation].asset_id='b0000000-0000-4000-8000-000000000999' end,
        function(m) m.db.registrations[m.t.operationId].asset_id='b0000000-0000-4000-8000-000000000999' end
    }
    for _,mutate in ipairs(mutations) do
        local m=submissionFixture(); local horse=m.selected().value.horse; mutate(m)
        assert(not m.S.CallRepository.ClaimSubmission(m.context,horse,m.generation).ok)
        assert(m.db.callLeases[m.generation].state=='prepared')
    end
end)

test('released generation cannot claim submission or disturb a replacement slot',function()
    local m=submissionFixture(); assert(m.abort(m.generation).ok)
    local nextId=m.prepareCall().value.generationId
    assert(m.submit().code=='submission_conflict' and m.callGet().value.generationId==nextId)
end)

test('submission is internal only with no installed RPC or native dispatch',function()
    local m=submissionFixture(); local routes={}
    m.S.Core={Call=function(_,name) routes[name]=true; return m.S.Ok(true) end}
    m.env.TriggerClientEvent=function() error('native dispatch must not occur') end
    m.env.CreatePed=function() error('native creation must not occur') end
    assert(m.calls.Install().ok and size(routes)==3 and not routes['stables.horses.call.submit.v1'])
    assert(m.submit().ok)
end)


test('session change after submission commit suppresses success without releasing slot',function()
    local m=submissionFixture(); local transaction=m.env.DB.transaction
    m.env.DB.transaction=function(body)
        local committed=transaction(body)
        if m.db.callLeases[m.generation].state=='submitting' then m.current=false end
        return committed
    end
    assert(m.submit().code=='session_stale' and m.db.callLeases[m.generation].state=='submitting')
    m.current=true; m.env.DB.transaction=transaction
    assert(m.submit().code=='submission_conflict' and m.abort(m.generation).code=='call_cleanup_required')
end)

test('stale session and malformed submission never touch prepared state',function()
    local m=submissionFixture(); m.current=false
    assert(m.submit().code=='session_stale' and m.db.callLeases[m.generation].state=='prepared')
    m.current=true
    assert(m.calls.ClaimSubmission({generationId=m.generation,modelKey='injected'},1,m.context).code=='invalid_input')
    assert(m.db.callLeases[m.generation].state=='prepared')
end)

test('UUID allocation precedes the canonical snapshot with fresh postcommit ownership',function()
    local m=fixture(); local reads=0; local uuidBeforeRead=false
    m.onUuid=function() uuidBeforeRead=reads==0 end
    m.onAssetRead=function() reads=reads+1 end
    assert(m.prepareCall().ok and uuidBeforeRead and reads==2)
end)

test('ownership lost during UUID allocation prevents durable admission',function()
    local m=fixture()
    m.onUuid=function() m.asset.owner.holderId='20000000-0000-4000-8000-000000000099' end
    assert(m.prepareCall().code=='selection_required' and size(m.db.callLeases)==0)
end)

test('observed submission skips duplicate read but still claims once under locks',function()
    local m=submissionFixture(); local saved=m.S.CallRepository.Get(m.context.characterId,m.generation).value
    local get=m.S.CallRepository.Get; local reads=0
    m.S.CallRepository.Get=function(...) reads=reads+1; return get(...) end
    local result=m.calls.ClaimObservedSubmission({generationId=m.generation},1,m.context,saved)
    assert(result.ok and result.value.state=='submitting' and reads==0)
    assert(m.calls.ClaimObservedSubmission({generationId=m.generation},1,m.context,saved).code=='submission_conflict')
end)

test('observed prepared snapshot cannot revive an aborted generation',function()
    local m=submissionFixture(); local saved=m.S.CallRepository.Get(m.context.characterId,m.generation).value
    assert(m.abort(m.generation).ok)
    assert(m.calls.ClaimObservedSubmission({generationId=m.generation},1,m.context,saved).code=='submission_conflict')
    assert(m.callGet().value.state=='empty')
end)

test('observed handoff rejects foreign identity and missing snapshot',function()
    local m=submissionFixture(); local saved=m.S.CallRepository.Get(m.context.characterId,m.generation).value
    saved.characterId='20000000-0000-4000-8000-000000000099'
    assert(m.calls.ClaimObservedSubmission({generationId=m.generation},1,m.context,saved).code=='call_not_found')
    assert(m.calls.ClaimObservedSubmission({generationId=m.generation},1,m.context,nil).code=='invalid_call')
    assert(m.callGet().value.state=='prepared')
end)

test('prepare current derives revision server-side while explicit prepare still rejects stale revision',function()
    local m=fixture(); m.stable().revision=2
    assert(m.prepareCall(1).code=='revision_conflict')
    local result=m.calls.PrepareCurrent(1,m.context)
    assert(result.ok and result.value.selectionRevision==2 and size(m.db.callSlots)==1)
end)

test('prepare current locked selection check refuses changes after fresh selected snapshot',function()
    local m=fixture(); local selected=m.S.Selection.Get
    m.S.Selection.Get=function(...)
        local result=selected(...); m.stable().revision=2; return result
    end
    assert(m.calls.PrepareCurrent(1,m.context).code=='revision_conflict' and size(m.db.callSlots)==0)
end)

test('prepare current preserves UUID-yield ownership and disabled gates',function()
    local m=fixture(); m.onUuid=function() m.asset.owner.holderId='20000000-0000-4000-8000-000000000099' end
    assert(m.calls.PrepareCurrent(1,m.context).code=='selection_required' and size(m.db.callSlots)==0)
    m=fixture(); m.env.StablesConfig.callPreparation=false; assert(m.calls.Start().ok)
    assert(m.calls.PrepareCurrent(1,m.context).code=='call_preparation_disabled' and size(m.db.callSlots)==0)
end)

test('prepared handoff is same-coroutine one-use and captures isolated lease facts',function()
    local m=fixture(); local h=m.calls.PrepareForDispatch(1,m.context).value
    local id=h.lease.generationId
    local foreign
    local thread=coroutine.create(function() foreign=h.claim(id,1,m.context) end)
    assert(coroutine.resume(thread) and foreign.code=='submission_conflict')
    h.lease.assetId='tampered'
    assert(h.claim(id,1,m.context).ok)
    assert(h.claim(id,1,m.context).code=='submission_conflict')
end)

test('prepared handoff refuses foreign generation session character and caller before mutation',function()
    local m=fixture(); local h=m.calls.PrepareForDispatch(1,m.context).value; local id=h.lease.generationId
    assert(h.claim('f0000000-0000-4000-8000-000000000001',1,m.context).code=='call_not_found')
    assert(h.claim(id,2,m.context).code=='call_not_found')
    local other=m.S.Copy(m.context); other.sessionId='foreign'
    assert(h.claim(id,1,other).code=='call_not_found')
    other=m.S.Copy(m.context); other.characterId='20000000-0000-4000-8000-000000000099'
    assert(h.claim(id,1,other).code=='call_not_found')
    assert(m.callGet().value.state=='prepared')
end)

test('prepared handoff still compares locked selection revision and cannot replay failed claim',function()
    local m=fixture(); local h=m.calls.PrepareForDispatch(1,m.context).value; local id=h.lease.generationId
    m.stable().revision=2
    assert(h.claim(id,1,m.context).code=='revision_conflict' and m.callGet().value.state=='prepared')
    m.stable().revision=1
    assert(h.claim(id,1,m.context).code=='submission_conflict')
end)

test('prepared handoff preserves fresh postclaim ownership refusal and submitted fence',function()
    local m=fixture(); local h=m.calls.PrepareForDispatch(1,m.context).value; local id=h.lease.generationId
    m.onAssetRead=function() m.asset.owner.holderId='20000000-0000-4000-8000-000000000099' end
    assert(h.claim(id,1,m.context).code=='horse_not_found')
    assert(m.callGet().value.state=='submitting' and h.claim(id,1,m.context).code=='submission_conflict')
end)

test('prepared handoff cannot revive aborted generation or disturb replacement slot',function()
    local m=fixture(); local h=m.calls.PrepareForDispatch(1,m.context).value; local id=h.lease.generationId
    assert(m.abort(id).ok); local nextId=m.prepareCall().value.generationId
    assert(h.claim(id,1,m.context).code=='submission_conflict')
    assert(m.callGet().value.generationId==nextId and m.callGet().value.state=='prepared')
end)

test('prepare and claim batch projection locks in original order',function()
    local m=fixture(); local transaction=m.env.DB.transaction; local seen=0
    m.env.DB.transaction=function(body) return transaction(function(tx)
        local batch=tx.batch
        tx.batch=function(statements)
            if statements[1].sql:find('fs_operations',1,true) then
                seen=seen+1; assert(#statements==3)
                assert(statements[2].sql:find('fs_asset_registrations',1,true))
                assert(statements[3].sql:find('fs_horses',1,true))
                for _,v in ipairs(statements) do assert(v.sql:find('FOR UPDATE',1,true)) end
            end
            return batch(statements)
        end
        return body(tx)
    end) end
    local h=m.calls.PrepareForDispatch(1,m.context); assert(h.ok)
    assert(h.value.claim(h.value.lease.generationId,1,m.context).ok and seen==2)
end)

test('malformed projection batch rolls back preparation without slot or lease',function()
    for _,bad in ipairs({{},{{},{},{}},{{{},{}},{},{}},false}) do
        local m=fixture(); local transaction=m.env.DB.transaction
        m.env.DB.transaction=function(body) return transaction(function(tx)
            local batch=tx.batch
            tx.batch=function(statements)
                if statements[1].sql:find('fs_operations',1,true) then return bad end
                return batch(statements)
            end
            return body(tx)
        end) end
        assert(not m.prepareCall().ok)
        assert(size(m.db.callLeases)==0 and size(m.db.callSlots)==0)
    end
end)

test('claim batches scoped lifecycle reads and refuses contradictory binding',function()
    local m=fixture(); local h=m.calls.PrepareForDispatch(1,m.context).value; local id=h.lease.generationId
    local transaction=m.env.DB.transaction; local seen=0
    m.env.DB.transaction=function(body) return transaction(function(tx)
        local batch=tx.batch
        tx.batch=function(statements)
            if statements[1].sql:find('fs_call_slots',1,true) then
                seen=seen+1; assert(#statements==3)
                assert(statements[1].params[1]==m.context.characterId)
                assert(statements[2].params[1]==id and statements[2].params[2]==m.context.characterId)
                assert(statements[3].params[1]==id)
            end
            return batch(statements)
        end
        return body(tx)
    end) end
    m.db.callBindings[id]={generation_id=id}
    assert(h.claim(id,1,m.context).code=='invalid_call_binding' and seen==1)
    assert(m.db.callLeases[id].state=='prepared' and m.db.callSlots[m.context.characterId].generation_id==id)
end)

test('malformed claim lifecycle batch leaves prepared fence unchanged',function()
    local m=fixture(); local h=m.calls.PrepareForDispatch(1,m.context).value; local id=h.lease.generationId
    local transaction=m.env.DB.transaction
    m.env.DB.transaction=function(body) return transaction(function(tx)
        local batch=tx.batch
        tx.batch=function(statements)
            if statements[1].sql:find('fs_call_slots',1,true) then return {{},{}} end
            return batch(statements)
        end
        return body(tx)
    end) end
    assert(h.claim(id,1,m.context).code=='invalid_call')
    assert(m.db.callLeases[id].state=='prepared' and m.db.callSlots[m.context.characterId].generation_id==id)
end)

test('prepared write batch executes in order and replay avoids another insertion',function()
    local m=fixture(); local transaction=m.env.DB.transaction; local seen=0
    m.env.DB.transaction=function(body) return transaction(function(tx)
        local batch=tx.batch
        tx.batch=function(statements)
            if statements[1].sql:find('INSERT INTO fs_call_leases',1,true) then
                seen=seen+1; assert(#statements==3)
                assert(statements[2].sql:find('INSERT INTO fs_call_slots',1,true))
                assert(statements[3].sql:find('SELECT * FROM fs_call_leases',1,true))
            end
            return batch(statements)
        end
        return body(tx)
    end) end
    local r=m.prepareCall(); assert(r.ok and seen==1)
    assert(m.prepareCall().value.generationId==r.value.generationId and seen==1)
end)

test('bad write batch headers or missing saved row roll back both insertions',function()
    for _,index in ipairs({1,2,3}) do
        local m=fixture(); local transaction=m.env.DB.transaction
        m.env.DB.transaction=function(body) return transaction(function(tx)
            local batch=tx.batch
            tx.batch=function(statements)
                local results=batch(statements)
                if statements[1].sql:find('INSERT INTO fs_call_leases',1,true) then
                    results[index]=index==3 and {} or {affectedRows=0}
                end
                return results
            end
            return body(tx)
        end) end
        assert(m.prepareCall().code=='call_not_saved')
        assert(size(m.db.callLeases)==0 and size(m.db.callSlots)==0)
    end
end)

test('preparation timing measures UUID selection repository and ownership separately',function()
    local m=fixture(); local now=0; m.env.GetGameTimer=function() return now end
    local value=m.env.DB.value; m.env.DB.value=function(...) now=now+10; return value(...) end
    local selection=m.S.Selection.Get; m.S.Selection.Get=function(...) now=now+20; return selection(...) end
    local prepare=m.S.CallRepository.Prepare; m.S.CallRepository.Prepare=function(...) now=now+30; return prepare(...) end
    local owned=m.S.OwnedHorses.Get; m.S.OwnedHorses.Get=function(...) now=now+5; return owned(...) end
    local known=m.S.OwnedHorses.GetKnown; m.S.OwnedHorses.GetKnown=function(...) now=now+5; return known(...) end
    local stages={}; local h=m.calls.PrepareForDispatch(1,m.context,stages)
    assert(h.ok and h.value.lease.state=='prepared')
    assert(stages.generationUuidMs==10 and stages.selectionMs==25)
    assert(stages.transactionMs==30 and stages.recheckMs==5)
end)

local EPOCH='f0000000-0000-4000-8000-000000000001'
test('one-shot plan makes no lease until preparation claim and receipt commit together',function()
    local m=fixture(); local h=m.calls.PlanForDispatch(1,m.context).value; local id=h.lease.generationId
    assert(size(m.db.callLeases)==0 and size(m.db.callSlots)==0)
    local transaction=m.env.DB.transaction; local committed={}
    m.env.DB.transaction=function(body)
        local result=transaction(body)
        if result then committed[#committed+1]=m.db.callLeases[id] and m.db.callLeases[id].state or 'absent' end
        return result
    end
    local r=h.claim(id,1,m.context,nil,EPOCH)
    assert(r.ok and r.value.state=='submitting' and r.value.processEpoch==EPOCH)
    assert(committed[1]=='submitting' and m.db.callEpochs[id].process_epoch==EPOCH)
    assert(h.claim(id,1,m.context,nil,EPOCH).code=='submission_conflict')
end)

test('one-shot fresh preparation rolls back all rows when receipt insertion fails',function()
    local m=fixture(); local h=m.calls.PlanForDispatch(1,m.context).value
    m.failEpochInsert=true
    assert(h.claim(h.lease.generationId,1,m.context,nil,EPOCH).code=='database_error')
    assert(size(m.db.callLeases)==0 and size(m.db.callSlots)==0 and size(m.db.callEpochs)==0)
end)

test('competing uncommitted plans authorize only the winning generation',function()
    local m=fixture(); local a=m.calls.PlanForDispatch(1,m.context).value
    local b=m.calls.PlanForDispatch(1,m.context).value
    assert(a.lease.generationId~=b.lease.generationId)
    assert(a.claim(a.lease.generationId,1,m.context,nil,EPOCH).ok)
    assert(not b.claim(b.lease.generationId,1,m.context,nil,EPOCH).ok)
    assert(size(m.db.callLeases)==1 and size(m.db.callEpochs)==1)
    assert(m.db.callSlots[m.t.characterId].generation_id==a.lease.generationId)
end)

test('new plan cannot consume a different explicit prepared winner',function()
    local m=fixture(); local h=m.calls.PlanForDispatch(1,m.context).value
    local winner=m.prepareCall().value.generationId
    assert(h.claim(h.lease.generationId,1,m.context,nil,EPOCH).code=='submission_conflict')
    assert(m.db.callLeases[winner].state=='prepared' and size(m.db.callEpochs)==0)
    assert(m.db.callSlots[m.t.characterId].generation_id==winner)
end)

test('one-shot locked selection conflict leaves no partially prepared generation',function()
    local m=fixture(); local h=m.calls.PlanForDispatch(1,m.context).value
    m.stable().revision=2
    assert(h.claim(h.lease.generationId,1,m.context,nil,EPOCH).code=='revision_conflict')
    assert(size(m.db.callLeases)==0 and size(m.db.callSlots)==0)
end)

test('unknown one-shot commit preserves submitted receipt and prevents capability replay',function()
    local m=fixture(); local h=m.calls.PlanForDispatch(1,m.context).value; local id=h.lease.generationId
    m.unknownCommit=true
    assert(h.claim(id,1,m.context,nil,EPOCH).code=='database_error')
    assert(m.db.callLeases[id].state=='submitting' and m.db.callEpochs[id].process_epoch==EPOCH)
    assert(h.claim(id,1,m.context,nil,EPOCH).code=='submission_conflict')
end)

test('combined claim rejection rolls back its fresh preparation as well',function()
    local m=fixture(); local h=m.calls.PlanForDispatch(1,m.context).value
    local transaction=m.env.DB.transaction
    m.env.DB.transaction=function(body) return transaction(function(tx)
        local batch=tx.batch
        tx.batch=function(statements)
            local rows=batch(statements)
            if statements[1].sql:find("UPDATE fs_call_leases SET state='submitting'",1,true) then rows[1]={affectedRows=0} end
            return rows
        end
        return body(tx)
    end) end
    assert(h.claim(h.lease.generationId,1,m.context,nil,EPOCH).code=='revision_conflict')
    assert(size(m.db.callLeases)==0 and size(m.db.callSlots)==0 and size(m.db.callEpochs)==0)
end)

print(count..'/'..count..' call preparation cases passed; native creation remains disabled.')
