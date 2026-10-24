local base=assert(loadfile('tests/fixtures/selection_services.lua'))()
return function()
    local m=base(); assert(m.select(0).ok)
    for _,file in ipairs({'server/call_repository.lua','server/call_lifecycle_repository.lua','server/calls.lua','server/owned_snapshot.lua'}) do
        assert(loadfile(file,'t',m.env))()
    end
    m.env.StablesConfig.callPreparation=true; assert(m.S.Calls.Start().ok)
    assert(loadfile('tests/fixtures/production_snapshot.lua'))()(m)
    m.q=m.S.OwnedSnapshot
    m.pack=function()
        local db=m.db; local event
        for _,row in pairs(db.runtimeEvents) do if row.horse_id==m.t.horseId and (not event or row.revision>event.revision) then event=row end end
        local slot=db.callSlots[m.t.characterId]
        local h=db.history[m.t.operationId]; local o=db.outbox['stables.fulfilled:'..m.t.operationId]
        local rows={stable=db.characters[m.t.characterId],operation=db.operations[m.t.operationId],registration=db.registrations[m.t.operationId],
            horse=db.horses[m.t.horseId],event=event,slot=slot,
            history=h and {event_id=h[1],horse_id=h[2],operation_id=h[3],event_kind=h[4],facts_json=h[5]},
            outbox=o and {event_id=o[1],operation_id=o[2],event_name=o[3],payload_json=o[4],delivered=o.delivered or 0}}
        for _,pair in ipairs({{'previous',event and event.generation_id},{'current',slot and slot.generation_id}}) do
            local prefix,id=pair[1],pair[2]
            if id then
                rows[prefix..'Lease']=db.callLeases[id]; rows[prefix..'Binding']=db.callBindings[id]
                rows[prefix..'Audit']=db.callRecoveries[id]; rows[prefix..'Epoch']=db.callEpochs[id]
            end
        end
        local flat={orphan_exists=0}; local _,specs=m.q.QuerySpec()
        for _,spec in ipairs(specs) do
            local row=rows[spec.name]
            if row then for _,field in ipairs(spec.fields) do flat[spec.name..'__'..field]=row[field] end end
        end
        for _,v in pairs(db.callLeases) do if v.horse_id==m.t.horseId and v.state~='released' then flat.orphan_exists=1 end end
        return {flat}
    end
    m.decode=function(rows) return m.q.Decode(m.t.operationId,m.t.characterId,rows or m.pack()) end
    m.reference=function() return m.S.FulfillmentRepository.GetOwnedSnapshot(m.t.operationId,m.t.characterId) end
    m.prepare=function()
        local result=m.S.Calls.Prepare({expectedSelectionRevision=1},1,m.context); assert(result.ok,result.code); m.id=result.value.generationId
        assert(m.S.Calls.ClaimSubmission({generationId=m.id},1,m.context).ok)
        m.identity={generationId=m.id,observerId='c0000000-0000-4000-8000-000000000001',netId=71,initialOwner=1,bucket=0,modelKey='a_c_horse_morgan_bay'}
    end
    m.bind=function() return m.S.CallLifecycleRepository.Bind(m.context,m.id,m.identity) end
    m.store=function()
        assert(m.S.CallLifecycleRepository.BeginCleanup(m.t.characterId,m.id).ok)
        return m.S.CallLifecycleRepository.FinishCleanup(m.t.characterId,m.id,
            {generationId=m.id,observerId=m.identity.observerId,netId=71,disappeared=true})
    end
    return m
end
