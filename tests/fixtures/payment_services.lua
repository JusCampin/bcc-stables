local fixture=assert(loadfile('tests/fixtures/persistence.lua'))()
local function setup(quoteSnapshot)
    local m=fixture(); assert(m.start().ok)
    local t={operationId='10000000-0000-4000-8000-000000000001',characterId='20000000-0000-4000-8000-000000000002',
        horseId='30000000-0000-4000-8000-000000000003',quoteId='40000000-0000-4000-8000-000000000004',
        walletAccountId='50000000-0000-4000-8000-000000000005',sinkAccountId='60000000-0000-4000-8000-000000000006',
        catalogId='morgan_bay',catalogRevision=1,currency='dollars',amount=100}
    if quoteSnapshot then t.horseId=t.operationId; t.quoteId=t.operationId end
    assert(m.r.Reserve(t,quoteSnapshot).ok)
    local S=m.env.Stables; m.t,m.S,m.calls=t,S,{}
    S.Foundation={RequireReady=function() return S.Ok(true) end}
    S.Economy={
        Account=function(id)
            assert(not m.inTx); m.calls[#m.calls+1]='account'
            local v={accountId=id,ownerType=id==t.walletAccountId and 'character' or 'system',
                ownerId=id==t.walletAccountId and t.characterId or 'system',
                accountType=id==t.walletAccountId and 'wallet' or 'system_sink',currency='dollars',status='open'}
            if m.changeAccount then m.changeAccount(v) end
            return S.Ok(v)
        end,
        Transfer=function(req)
            assert(not m.inTx and m.r.Get(t.operationId,t.characterId).value.state=='payment_pending')
            assert(req.idempotencyKey=='stables.purchase:'..t.operationId); m.calls[#m.calls+1]='transfer'
            if m.failTransfer then return S.Err(m.failTransfer,'Unknown or refused transfer.') end
            if not m.receipt then
                m.charges=(m.charges or 0)+1
                m.receipt=S.Copy(req); m.receipt.operation='transfer'; m.receipt.sourceResource='bcc-stables'
                m.receipt.transactionId='70000000-0000-4000-8000-000000000007'
            end
            if m.lostReply then return S.Err('transaction_failed','Committed reply lost.') end
            local r=S.Copy(m.receipt); if m.changeReceipt then m.changeReceipt(r) end
            return S.Ok(r)
        end,
        Transaction=function(id)
            assert(not m.inTx); m.calls[#m.calls+1]='journal'
            local source=id==m.receipt.transactionId and m.receipt or m.refund
            assert(source and id==source.transactionId)
            if m.readError then return S.Err('transaction_not_found','Missing.') end
            local v=S.Copy(source); v.status='committed'
            v.entries={{accountId=source.fromAccountId,amount=-100},{accountId=source.toAccountId,amount=100}}
            if m.changeJournal then m.changeJournal(v) end
            if m.onRead then m.onRead() end
            return S.Ok(v)
        end,
        Reverse=function(id)
            assert(not m.inTx and id==m.receipt.transactionId)
            local current=m.r.Get(t.operationId,t.characterId).value
            assert(current.state=='compensation_pending' and (current.registrationFence=='unregistered_v1' or current.registrationFence=='linked_retirement_v1'))
            m.calls[#m.calls+1]='reverse'
            if m.refundError then return S.Err(m.refundError,'Reversal failed.') end
            if not m.refund then
                m.refunds=(m.refunds or 0)+1; m.refund=S.Copy(m.receipt)
                m.refund.transactionId='80000000-0000-4000-8000-000000000008'
                m.refund.operation='reversal'; m.refund.reasonCode='stables.payment_reversal'
                m.refund.referenceType='economy_transaction'; m.refund.referenceId=id
                m.refund.fromAccountId,m.refund.toAccountId=t.sinkAccountId,t.walletAccountId
            end
            if m.lostRefund then return S.Err('transaction_failed','Reversal committed reply lost.') end
            local receipt=S.Copy(m.refund); if m.changeRefund then m.changeRefund(receipt) end
            return S.Ok(receipt)
        end,
    }
    m.load=function() assert(loadfile('server/payments.lua','t',m.env))(); m.paid=S.Payments end
    m.load(); m.pay=function() return m.paid.Pay(t.operationId,t.characterId) end
    m.reverse=function() return m.paid.RefundUnregistered(t.operationId,t.characterId) end
    return m
end
return setup
