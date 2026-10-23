local base=assert(loadfile('tests/fixtures/selection_services.lua'))()
local count=0
local function test(name,body)
    local ok,err=pcall(body); assert(ok,name..': '..tostring(err)); count=count+1; print('PASS call preparation '..name)
end
local function size(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local function fixture()
    local m=base(); assert(m.select(0).ok)
    for _,file in ipairs({'server/call_repository.lua','server/calls.lua'}) do assert(loadfile(file,'t',m.env))() end
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
    assert(m.callGet().code=='invalid_call' and m.prepareCall().code=='invalid_call')
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
    m.onAssetRead=function() reads=reads+1; if reads==3 then m.asset.owner.holderId='20000000-0000-4000-8000-000000000099' end end
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

print(count..'/'..count..' call preparation cases passed; native creation remains disabled.')
