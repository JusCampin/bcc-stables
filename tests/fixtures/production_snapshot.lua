-- Real production snapshot module with a coherent row-set DB model.
return function(m)
    local e,S=m.env,m.S
    if not S.OwnedSnapshot.QuerySpec then assert(loadfile('server/owned_snapshot.lua','t',e))() end
    local q=S.OwnedSnapshot; local query=e.DB.query
    local function pack(id,char)
        local db=m.db; local stable=db.characters[char]; if not stable then return {} end
        local op=db.operations[id]; if op and op.character_id~=char then op=nil end
        local horse,event,history,outbox
        if op then
            for _,v in pairs(db.horses) do if v.origin_operation_id==id then horse=v end end
            for _,v in pairs(db.history) do if v[3]==id and v[4]=='purchased' then
                history={event_id=v[1],horse_id=v[2],operation_id=v[3],event_kind=v[4],facts_json=v[5]} end end
            for _,v in pairs(db.outbox) do if v[2]==id and v[3]=='stables.purchase.fulfilled.v1' then
                outbox={event_id=v[1],operation_id=v[2],event_name=v[3],payload_json=v[4],delivered=v.delivered or 0} end end
        end
        if horse then for _,v in pairs(db.runtimeEvents) do
            if v.horse_id==horse.horse_id and (not event or v.revision>event.revision) then event=v end end end
        local slot=db.callSlots[char]
        local rows={stable=stable,operation=op,registration=op and db.registrations[id],horse=horse,event=event,slot=slot,history=history,outbox=outbox}
        for _,v in ipairs({{'previous',event and event.generation_id},{'current',slot and slot.generation_id}}) do
            local prefix,key=v[1],v[2]
            if key then
                local lease=db.callLeases[key]
                rows[prefix..'Lease']=lease and lease.character_id==char and lease or nil
                rows[prefix..'Binding']=db.callBindings[key]; rows[prefix..'Audit']=db.callRecoveries[key]; rows[prefix..'Epoch']=db.callEpochs[key]
            end
        end
        local flat={orphan_exists=0}; local _,specs=q.QuerySpec()
        for _,spec in ipairs(specs) do local row=rows[spec.name]
            if row then for _,field in ipairs(spec.fields) do flat[spec.name..'__'..field]=row[field] end end end
        if horse then for _,v in pairs(db.callLeases) do
            if v.horse_id==horse.horse_id and v.state~='released' then flat.orphan_exists=1 end end end
        return {flat}
    end
    e.DB.query=function(sql,...)
        if sql:match('^SHOW VARIABLES') then return {
            {Variable_name='autocommit',Value='ON'},{Variable_name='transaction_isolation',Value='REPEATABLE-READ'}} end
        if sql:find('SELECT TABLE_NAME,ENGINE FROM information_schema.TABLES',1,true) then
            local tables={}; for _,name in ipairs({'fs_character_stables','fs_operations','fs_asset_registrations','fs_horses',
                'fs_horse_history','fs_outbox','fs_horse_runtime_events','fs_call_slots','fs_call_leases','fs_call_bindings','fs_call_recoveries','fs_call_process_epochs'}) do
                tables[#tables+1]={TABLE_NAME=name,ENGINE='InnoDB'} end
            return tables
        end
        if sql:find('AS `stable__character_id`',1,true) then
            m.snapshotReads=(m.snapshotReads or 0)+1
            return pack(...)
        end
        return query(sql,...)
    end
    assert(q.Start().ok)
    m.productionSnapshotRows=pack
end
