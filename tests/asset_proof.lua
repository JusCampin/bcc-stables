local count=0
local function test(name,fn) fn(); count=count+1; print('PASS asset proof '..name) end
local CHAR='20000000-0000-4000-8000-000000000002'
local ASSET='80000000-0000-4000-8000-000000000008'
local function fixture()
    local env=setmetatable({}, {__index=_G})
    local m={calls={},logs={},receipts={},enabled=true}
    local stored,serial={},0
    env.json={encode=function(v) serial=serial+1; stored[tostring(serial)]=v; return tostring(serial) end}
    env.print=function(v) local id=v:match('^%[bcc%-stables:assets%-proof%] (.+)$'); if id then m.logs[#m.logs+1]=stored[id] end end
    env.CreateThread=function(fn) fn() end
    env.RegisterCommand=function(_,fn) m.command=fn end
    for _,path in ipairs({'config.lua','shared/contracts.lua','server/operations.lua'}) do assert(loadfile(path,'t',env))() end
    local S=env.Stables
    local function snap(request)
        return {assetId=ASSET,assetType='horse',modelKey=request.modelKey,managerResource='bcc-stables',
            provenanceType=request.provenanceType,provenanceId=request.provenanceId,metadataVersion=1,
            metadata=S.Copy(request.metadata),status='active',revision=1,
            owner={holderType='character',holderId=CHAR,interestId='90000000-0000-4000-8000-000000000009'}}
    end
    S.Foundation={RequireReady=function() return m.ready==false and S.Err('not_ready','Offline.') or S.Ok(true) end}
    S.Core={RequireSession=function(id)
        m.calls[#m.calls+1]='session'
        return id==17 and not m.noCharacter and S.Ok({characterId=CHAR}) or S.Err('character_required','No character.')
    end}
    S.Assets={
        FindRegistration=function(key)
            m.calls[#m.calls+1]='find'
            if m.lookupError then return S.Err('assets_unavailable','Offline.') end
            local receipt=m.receipts[key]
            return S.Ok(receipt and {found=true,operation=receipt.operation,result=S.Copy(receipt.result)} or {found=false})
        end,
        RegisterHorse=function(req)
            m.calls[#m.calls+1]='register'
            if m.onRegister then m.onRegister() end
            if m.deny then return S.Err('authorization_denied','No grant.') end
            if m.request then
                if req.modelKey~=m.request.modelKey then return S.Err('idempotency_conflict','Changed model.') end
                local value=S.Copy(m.receipts[req.requestId].result); value.replayed=true; return S.Ok(value)
            end
            m.request=S.Copy(req); m.current=snap(req)
            m.receipts[req.requestId]={operation='asset.register',result=S.Copy(m.current)}
            if m.lostRegister then return S.Err('transaction_failed','Remote commit response lost.') end
            return S.Ok(S.Copy(m.current))
        end,
        ReadHorse=function(id) m.calls[#m.calls+1]='get'; assert(id==ASSET); return S.Ok(S.Copy(m.current)) end,
        RetireProof=function(req)
            m.calls[#m.calls+1]='retire'; m.retireRequest=S.Copy(req)
            assert(req.assetId==ASSET and req.expectedRevision==1)
            m.current.status,m.current.revision,m.current.owner='retired',2,nil
            m.receipts[req.requestId]={operation='asset.retire',result=S.Copy(m.current)}
            if m.lostRetire then return S.Err('transaction_failed','Retirement response lost.') end
            return S.Ok(S.Copy(m.current))
        end,
    }
    m.reload=function() assert(loadfile('server/asset_proof.lua','t',env))() end
    m.reload()
    env.StablesConfig.assetProof=true
    m.run=function(action,id,source) m.command(source or 0,{action,id}); return m.logs[#m.logs] end
    m.S,m.env=S,env
    return m
end
test('console opt-in and exact command arguments gate all service work',function()
    local m=fixture(); m.env.StablesConfig.assetProof=false; assert(m.run('run','17').code=='disabled' and #m.calls==0)
    m.env.StablesConfig.assetProof=true; m.run('run','17',17); assert(#m.calls==0)
    assert(m.run('run','bad').code=='invalid_input')
    assert(m.run('retire','17').code=='invalid_input')
end)
test('run derives character from exact server player ID and checks replay and conflict',function()
    local m=fixture(); local r=m.run('run','17'); assert(r.ok)
    assert(r.value.characterId==CHAR and r.value.serverPlayerId==17 and r.value.assetId==ASSET)
    assert(r.value.identicalReplay and r.value.changedTermsRefused and r.value.noPaymentSubmitted and r.value.noEntitySpawned)
    assert(m.logs[1].event=='fixture_selected' and m.logs[1].characterId==CHAR)
end)
test('missing session or readiness prevents registration',function()
    local m=fixture(); assert(m.run('run','18').code=='character_required' and m.request==nil)
    m.ready=false; assert(m.run('run','17').code=='not_ready' and m.request==nil)
end)
test('policy denial preserves stable recovery identity without local payment evidence',function()
    local m=fixture(); m.deny=true; assert(m.run('run','17').code=='authorization_denied')
    assert(m.logs[1].characterId==CHAR and m.request==nil)
end)
test('lost registration reply recovers same receipt across module restart',function()
    local m=fixture(); m.lostRegister=true; assert(m.run('run','17').code=='transaction_failed')
    m.reload(); assert(m.run('inspect',CHAR).value.assetId==ASSET)
    m.calls={}; assert(m.run('run','17').ok)
    local writes=0; for _,v in ipairs(m.calls) do if v=='register' then writes=writes+1 end end
    assert(writes==2) -- deliberate replay + changed-term rejection, no fresh allocation
end)
test('inspect absent never registers and does not need an active session',function()
    local m=fixture(); local r=m.run('inspect',CHAR); assert(r.ok and r.value.state=='absent')
    assert(table.concat(m.calls,',')=='find')
end)
test('retire ends fixture and retains its original registration receipt',function()
    local m=fixture(); assert(m.run('run','17').ok)
    local r=m.run('retire',CHAR); assert(r.ok and r.value.state=='retired' and r.value.auditRetained)
    assert(m.receipts[m.request.requestId].result.status=='active')
    assert(m.run('inspect',CHAR).value.state=='retired')
end)
test('lost retirement reply recovers without a second retirement',function()
    local m=fixture(); assert(m.run('run','17').ok); m.lostRetire=true
    assert(m.run('retire',CHAR).code=='transaction_failed'); m.reload(); m.calls={}
    assert(m.run('retire',CHAR).ok)
    for _,call in ipairs(m.calls) do assert(call~='retire') end
end)
test('retired fixtures never allocate a replacement',function()
    local m=fixture(); assert(m.run('run','17').ok and m.run('retire',CHAR).ok)
    m.calls={}; assert(m.run('run','17').code=='proof_conflict')
    for _,call in ipairs(m.calls) do assert(call~='register') end
end)
test('changed owner metadata or revision blocks retirement',function()
    for _,change in ipairs({function(v) v.owner.holderId='foreign' end,function(v) v.revision=3 end,
        function(v) v.metadata.extra='unrelated' end,function(v) v.provenanceType='stable_purchase' end}) do
        local m=fixture(); assert(m.run('run','17').ok); change(m.current); m.calls={}
        assert(m.run('retire',CHAR).code=='proof_conflict')
        for _,call in ipairs(m.calls) do assert(call~='retire') end
    end
end)
test('wrong receipt operation cannot authorize inspection or retirement',function()
    local m=fixture(); assert(m.run('run','17').ok)
    m.receipts[m.request.requestId].operation='ownership.transfer'
    assert(m.run('retire',CHAR).code=='proof_conflict')
end)
test('unknown fixture cannot retire any asset',function()
    local m=fixture(); assert(m.run('retire',CHAR).code=='proof_absent' and #m.calls==1)
end)
test('retired state without the matching cleanup receipt is not adopted',function()
    local m=fixture(); assert(m.run('run','17').ok and m.run('retire',CHAR).ok)
    m.receipts[m.retireRequest.requestId]=nil
    assert(m.run('retire',CHAR).code=='proof_conflict')
end)
test('busy guard refuses overlapping commands',function()
    local m=fixture(); m.onRegister=function() m.command(0,{'inspect',CHAR}) end
    assert(m.run('run','17').ok)
    local refused=false; for _,log in ipairs(m.logs) do refused=refused or log.code=='busy' end
    assert(refused)
end)
print(('%d/%d asset proof cases passed; real Assets mutations remain a live gate.'):format(count,count))
