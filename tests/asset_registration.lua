local count=0
local function test(name,fn) fn(); count=count+1; print('PASS registration '..name) end
local fixture=assert(loadfile('tests/fixtures/persistence.lua'))()
local MODEL='a_c_horse_morgan_bay'
local function setup(unpaid)
    local m=fixture(); assert(m.start().ok)
    local t={operationId='10000000-0000-4000-8000-000000000001',characterId='20000000-0000-4000-8000-000000000002',
        horseId='30000000-0000-4000-8000-000000000003',quoteId='40000000-0000-4000-8000-000000000004',
        walletAccountId='50000000-0000-4000-8000-000000000005',sinkAccountId='60000000-0000-4000-8000-000000000006',
        catalogId='morgan_bay',catalogRevision=1,currency='dollars',amount=100}
    assert(m.r.Reserve(t).ok)
    if not unpaid then
        assert(m.r.Advance(t.operationId,t.characterId,0,'payment_pending').ok)
        assert(m.r.Advance(t.operationId,t.characterId,1,'paid',{paymentReceipt={
            transactionId='70000000-0000-4000-8000-000000000007',operation='transfer',sourceResource='bcc-stables',
            reasonCode='stables.horse_purchase',referenceType='stables_order',referenceId=t.operationId,
            fromAccountId=t.walletAccountId,toAccountId=t.sinkAccountId,currency=t.currency,amount=t.amount}}).ok)
    end
    local S=m.env.Stables
    m.t,m.S,m.calls=t,S,{}
    S.Foundation={RequireReady=function() return S.Ok(true) end}
    local function external(name)
        assert(not m.inTx,'external call while holding SQL locks')
        m.calls[#m.calls+1]=name
        local intent=m.db.registrations[t.operationId]
        assert(intent and intent.state~='prepared','remote call before durable submission intent')
    end
    S.Assets={
        FindRegistration=function(key)
            external('find'); assert(key=='stables.register:'..t.operationId)
            if m.lookupError then return S.Err('assets_unavailable','Offline.') end
            if m.badLookup then return S.Ok(m.badLookup) end
            return S.Ok(m.remote and {found=true,operation=m.remoteOperation or 'asset.register',result=S.Copy(m.remote)} or {found=false})
        end,
        RegisterHorse=function(request)
            external('register'); m.request=S.Copy(request)
            if m.registerError then return S.Err(m.registerError,'Registration refused.',{assetId='do-not-adopt'}) end
            m.remote={assetId='80000000-0000-4000-8000-000000000008',assetType='horse',modelKey=request.modelKey,
                managerResource='bcc-stables',provenanceType=request.provenanceType,provenanceId=request.provenanceId,
                status='active',revision=1,metadataVersion=1,metadata=S.Copy(request.metadata),
                owner={interestId='90000000-0000-4000-8000-000000000009',holderType='character',holderId=request.holderId}}
            if m.lostReply then return S.Err('transaction_failed','Reply lost; remote committed.') end
            return S.Ok(S.Copy(m.remote))
        end,
        ReadHorse=function(assetId)
            external('get'); assert(assetId==m.remote.assetId)
            if m.readError then return S.Err('assets_unavailable','Read unavailable.') end
            local current=S.Copy(m.remote)
            if m.changeCurrent then m.changeCurrent(current) end
            if m.onRead then m.onRead() end
            return S.Ok(current)
        end,
    }
    m.load=function() assert(loadfile('server/asset_registration.lua','t',m.env))(); m.g=S.AssetRegistration end
    m.load()
    m.run=function() return m.g.Run(t.operationId,t.characterId,MODEL) end
    return m
end

test('paid intent and canonical link remain distinct from local horse identity',function()
    local m=setup(); local r=m.run(); assert(r.ok and r.value.assetId~=m.t.horseId and not r.value.gameplayAvailable)
    local row=m.db.registrations[m.t.operationId]; assert(row.state=='linked' and row.revision==2)
    assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='paid')
    assert(next(m.db.horses)==nil and next(m.db.history)==nil and next(m.db.outbox)==nil)
    assert(table.concat(m.calls,',')=='find,register,get')
end)
test('unpaid or foreign-character operations cannot prepare or call Assets',function()
    local m=setup(true); assert(m.run().code=='payment_required' and #m.calls==0 and next(m.db.registrations)==nil)
    assert(m.g.Run(m.t.operationId,'a0000000-0000-4000-8000-00000000000a',MODEL).code=='operation_not_found')
end)
test('invalid model or identity causes no intent or external call',function()
    local m=setup()
    for _,model in ipairs({'wagon02x','a_c_horse_bad|key',string.rep('x',101)}) do
        assert(m.g.Prepare(m.t.operationId,m.t.characterId,model).code=='invalid_input')
    end
    assert(m.g.Run('bad',m.t.characterId,MODEL).code=='invalid_input' and #m.calls==0)
end)
test('same intent replays and changed model cannot repurpose the key',function()
    local m=setup(); assert(m.g.Prepare(m.t.operationId,m.t.characterId,MODEL:upper()).ok)
    assert(m.g.Prepare(m.t.operationId,m.t.characterId,MODEL).ok)
    assert(m.g.Prepare(m.t.operationId,m.t.characterId,'a_c_horse_arabian_white').code=='idempotency_conflict')
    assert(#m.calls==0)
end)
test('unknown local intent commit never starts remote registration',function()
    local m=setup(); m.unknownCommit=true; local r=m.run()
    assert(r.code=='database_error' and r.details.outcome=='unknown' and #m.calls==0)
    assert(m.db.registrations[m.t.operationId].state=='prepared')
    m.unknownCommit=false; assert(m.run().ok)
end)
test('submission CAS failure keeps prepared intent and invokes no Assets call',function()
    local m=setup(); m.failSubmit=true
    assert(m.run().code=='revision_conflict' and #m.calls==0)
    assert(m.db.registrations[m.t.operationId].state=='prepared')
end)
test('remote commit with lost reply recovers through original receipt after reload',function()
    local m=setup(); m.lostReply=true
    assert(m.run().code=='transaction_failed' and m.db.registrations[m.t.operationId].state=='submitted')
    m.reload(); assert(m.start().ok); m.load(); m.calls={}
    assert(m.run().ok and table.concat(m.calls,',')=='find,get')
end)
test('lookup failure retains submission and reserved capacity',function()
    local m=setup(); m.lookupError=true
    assert(m.run().code=='assets_unavailable' and m.db.registrations[m.t.operationId].state=='submitted')
    assert(m.r.Get(m.t.operationId,m.t.characterId).value.state=='paid')
end)
test('missing receipt retries only the identical saved registration request',function()
    local m=setup(); m.registerError='authorization_denied'; assert(m.run().code=='authorization_denied')
    local first=m.S.Copy(m.request); m.registerError=nil; assert(m.run().ok)
    assert(m.request.requestId==first.requestId and m.request.provenanceId==first.provenanceId)
    assert(m.request.holderId==first.holderId and m.request.metadata.stablesHorseId==m.t.horseId)
end)
test('asset_exists cannot adopt an unrelated provenance result',function()
    local m=setup(); m.registerError='asset_exists'; assert(m.run().code=='asset_exists')
    assert(m.db.registrations[m.t.operationId].asset_id==nil and table.concat(m.calls,',')=='find,register')
end)
test('lookup receipt operation must be asset.register',function()
    local m=setup(); assert(m.run().ok); m.remoteOperation='ownership.transfer'
    assert(m.run().code=='registration_conflict')
end)
test('malformed lookup cannot trigger registration',function()
    local m=setup(); m.badLookup={found='no'}
    assert(m.run().code=='invalid_contract' and table.concat(m.calls,',')=='find')
end)
test('receipt identity owner manager provenance model and metadata must match',function()
    local mutations={
        function(v) v.assetId='bad' end, function(v) v.assetType='wagon' end,
        function(v) v.managerResource='other' end, function(v) v.modelKey='a_c_horse_other' end,
        function(v) v.provenanceId='other' end, function(v) v.status='retired' end,
        function(v) v.owner.holderId='other' end, function(v) v.metadata.stablesHorseId='other' end,
        function(v) v.revision=0 end,
    }
    for _,change in ipairs(mutations) do
        local m=setup(); m.lostReply=true; assert(not m.run().ok); change(m.remote)
        assert(m.run().code=='registration_conflict' and m.db.registrations[m.t.operationId].asset_id==nil)
    end
end)
test('fresh read refuses ownership change despite historical receipt',function()
    local m=setup(); m.changeCurrent=function(v) v.owner.holderId='a0000000-0000-4000-8000-00000000000a'; v.revision=2 end
    assert(m.run().code=='asset_changed' and m.db.registrations[m.t.operationId].state=='submitted')
end)
test('fresh read availability failure leaves no link and retry does not register again',function()
    local m=setup(); m.readError=true; assert(m.run().code=='assets_unavailable')
    m.readError=false; m.calls={}; assert(m.run().ok and table.concat(m.calls,',')=='find,get')
end)
test('local link CAS failure recovers without duplicating the remote asset',function()
    local m=setup(); m.failLink=true; assert(m.run().code=='revision_conflict')
    assert(m.db.registrations[m.t.operationId].state=='submitted')
    m.failLink=false; m.calls={}; assert(m.run().ok and table.concat(m.calls,',')=='find,get')
end)
test('lost local link commit reply converges through durable replay',function()
    local m=setup(); m.onRead=function() m.unknownCommit=true end
    local r=m.run(); assert(r.code=='database_error' and r.details.outcome=='unknown')
    assert(m.db.registrations[m.t.operationId].state=='linked')
    m.unknownCommit=false; m.onRead=nil; m.calls={}
    assert(m.run().ok and table.concat(m.calls,',')=='find,get')
end)
test('linked replay rechecks canonical facts and refuses a missing receipt',function()
    local m=setup(); assert(m.run().ok); m.calls={}; assert(m.run().ok and table.concat(m.calls,',')=='find,get')
    m.remote=nil; m.calls={}; assert(m.run().code=='registration_conflict' and table.concat(m.calls,',')=='find')
end)
test('canonical revision cannot regress below the saved observation',function()
    local m=setup(); m.changeCurrent=function(v) v.revision=4 end; assert(m.run().ok)
    m.changeCurrent=function(v) v.revision=3 end; assert(m.run().code=='asset_changed')
end)
test('corrupt saved request or link state fails before external calls',function()
    for _,mutate in ipairs({function(row) row.request_json='bad' end,function(row) row.fingerprint='changed' end,
        function(row) row.revision=4 end,function(row) row.asset_id='80000000-0000-4000-8000-000000000008' end}) do
        local m=setup(); assert(m.g.Prepare(m.t.operationId,m.t.characterId,MODEL).ok)
        mutate(m.db.registrations[m.t.operationId]); assert(m.run().code=='invalid_registration' and #m.calls==0)
    end
end)
test('existing preliminary horse is refused without adoption or remote call',function()
    local m=setup(); m.db.horses[m.t.horseId]={horse_id=m.t.horseId,origin_operation_id=m.t.operationId}
    assert(m.run().code=='unmapped_horse' and #m.calls==0 and next(m.db.registrations)==nil)
end)
test('reconciliation winning before link keeps the asset unfulfilled',function()
    local m=setup(); m.onRead=function()
        assert(m.r.Advance(m.t.operationId,m.t.characterId,2,'reconciliation_required',{code='manual_hold'}).ok)
    end
    assert(m.run().code=='payment_required' and m.db.registrations[m.t.operationId].state=='submitted')
    assert(next(m.db.horses)==nil)
end)
print(('%d/%d registration cases passed; SQL and Assets are modeled, no live registration.'):format(count,count))
