local count=0
local function test(name,fn) fn(); count=count+1; print('PASS payment proof '..name) end
local ID='20000000-0000-4000-8000-000000000002'
local function fixture()
    local env=setmetatable({}, {__index=_G}); local m={logs={},calls={}}
    local values,serial={},0
    env.json={encode=function(v) serial=serial+1; values[tostring(serial)]=v; return tostring(serial) end}
    env.print=function(v) local id=v:match('^%[bcc%-stables:payment%-proof%] (.+)$'); if id then m.logs[#m.logs+1]=values[id] end end
    env.RegisterCommand=function(_,fn) m.command=fn end; env.CreateThread=function(fn) fn() end
    for _,p in ipairs({'config.lua','shared/contracts.lua','server/operations.lua'}) do assert(loadfile(p,'t',env))() end
    local S=env.Stables
    S.Foundation={RequireReady=function() return S.Ok(true) end}
    S.Core={RequireSession=function(source) return source==17 and S.Ok({characterId=ID}) or S.Err('character_required','No session.') end}
    S.Repository={Get=function(op,char)
        assert(op==ID and char==ID); return m.record and S.Ok(S.Copy(m.record)) or S.Err('operation_not_found','Not found.')
    end,Reserve=function(t)
        m.calls[#m.calls+1]='reserve'; assert(t.amount==1 and t.currency=='dollars' and t.characterId==ID)
        m.record=S.Operations.New(t).value; return S.Ok({operation=m.record,replayed=false})
    end}
    S.Economy={CharacterAccounts=function(id)
        assert(id==ID); m.calls[#m.calls+1]='accounts'
        return S.Ok(m.noWallet and {} or {{accountId='50000000-0000-4000-8000-000000000005',ownerId=ID,
            ownerType='character',accountType='wallet',currency='dollars',status='open'}})
    end,SystemSink=function(currency)
        assert(currency=='dollars'); return S.Ok({accountId='60000000-0000-4000-8000-000000000006'})
    end}
    S.Payments={Pay=function(op,char)
        assert(op==ID and char==ID); m.calls[#m.calls+1]=m.record.state=='paid' and 'paid_read' or 'pay'
        m.record.state='paid'; return S.Ok(S.Copy(m.record))
    end,RefundUnregistered=function(op,char)
        assert(op==ID and char==ID); m.calls[#m.calls+1]=m.record.state=='refunded' and 'refund_read' or 'refund'
        m.record.state='refunded'; return S.Ok(S.Copy(m.record))
    end}
    env.StablesConfig.paymentProof=true
    m.reload=function() assert(loadfile('server/payment_proof.lua','t',env))() end
    m.reload(); m.env=env
    m.run=function(args,source) m.command(source or 0,args); return m.logs[#m.logs] end
    return m
end
test('opt-in console and explicit one-unit argument required before work',function()
    local m=fixture(); m.env.StablesConfig.paymentProof=false
    assert(m.run({'run','17','1'}).code=='disabled')
    m.env.StablesConfig.paymentProof=true; m.run({'run','17','1'},17); assert(#m.calls==0)
    assert(m.run({'run','17'}).code=='invalid_input')
    assert(m.run({'run','17','100'}).code=='invalid_input' and #m.calls==0)
end)
test('selected server player and exact fixture terms constrain the charge',function()
    local m=fixture(); local r=m.run({'run','17','1'}); assert(r.ok and r.value.amount==1 and r.value.characterId==ID)
    assert(m.logs[1].event=='fixture_selected' and m.logs[1].serverPlayerId==17)
    assert(m.record.terms.operationId==ID and m.record.terms.horseId==ID and m.record.terms.quoteId==ID)
    assert(m.run({'run','18','1'}).code=='character_required')
end)
test('missing existing wallet does not provision or charge',function()
    local m=fixture(); m.noWallet=true
    assert(m.run({'run','17','1'}).code=='account_not_found' and table.concat(m.calls,',')=='accounts')
end)
test('conflicting operation terms cannot be repurposed',function()
    local m=fixture(); assert(m.run({'run','17','1'}).ok); m.record.terms.catalogId='real_purchase'; m.calls={}
    assert(m.run({'run','17','1'}).code=='proof_conflict' and #m.calls==0)
    assert(m.run({'refund',ID}).code=='proof_conflict' and #m.calls==0)
end)
test('restart inspection of pending transfer cannot submit it',function()
    local m=fixture(); assert(m.run({'run','17','1'}).ok)
    m.record.state='payment_pending'; m.reload(); m.calls={}
    assert(m.run({'inspect',ID}).value.state=='payment_pending' and #m.calls==0)
end)
test('paid inspection and refunded replay use only verified read paths',function()
    local m=fixture(); assert(m.run({'run','17','1'}).ok); m.calls={}; m.reload()
    assert(m.run({'inspect',ID}).ok and table.concat(m.calls,',')=='paid_read')
    assert(m.run({'refund',ID}).value.state=='refunded'); m.calls={}
    assert(m.run({'run','17','1'}).ok and table.concat(m.calls,',')=='refund_read')
end)
print(('%d/%d payment proof cases passed; no live currency moved.'):format(count,count))
