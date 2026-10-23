-- Internal payment/refund helpers used by opt-in proofs and guarded admission
-- routes. No automatic payment worker or gameplay fulfillment is installed.
Stables.Payments = {}
local P, O = Stables.Payments, Stables.Operations
local function Accounts(terms, initial)
    local wallet = Stables.Economy.Account(terms.walletAccountId); if not wallet.ok then return wallet end
    local sink = Stables.Economy.Account(terms.sinkAccountId); if not sink.ok then return sink end
    local w, s = wallet.value, sink.value
    if type(w) ~= 'table' or type(s) ~= 'table' or w.accountId ~= terms.walletAccountId or s.accountId ~= terms.sinkAccountId
        or w.ownerType ~= 'character' or w.ownerId ~= terms.characterId or w.accountType ~= 'wallet'
        or s.ownerType ~= 'system' or s.accountType ~= 'system_sink'
        or (initial and (w.status ~= 'open' or s.status ~= 'open'))
        or w.currency ~= terms.currency or s.currency ~= terms.currency then
        return Stables.Err('invalid_payment_accounts', 'Server-resolved wallet/sink do not match this purchase.')
    end
    return Stables.Ok(true)
end
local function Verify(record, receipt)
    -- Validate the exact transfer receipt through the existing pure rules first.
    local initial = O.New(record.terms)
    if not initial.ok then return initial end
    local pending = O.Advance(initial.value, 0, 'payment_pending').value
    local matched = O.Advance(pending, pending.revision, 'paid', { paymentReceipt = receipt })
    if not matched.ok then return matched end
    local read = Stables.Economy.Transaction(receipt.transactionId); if not read.ok then return read end
    local t, v = record.terms, read.value
    if type(v) ~= 'table' or v.transactionId ~= receipt.transactionId or v.status ~= 'committed'
        or v.operation ~= 'transfer' or v.sourceResource ~= 'bcc-stables' or v.reasonCode ~= 'stables.horse_purchase'
        or v.referenceType ~= 'stables_order' or v.referenceId ~= t.operationId or v.currency ~= t.currency or v.amount ~= t.amount
        or type(v.entries) ~= 'table' or #v.entries ~= 2 then
        return Stables.Err('invalid_receipt', 'Committed Economy journal does not match this purchase.')
    end
    local debit, credit = false, false
    for _, entry in ipairs(v.entries) do
        if type(entry) ~= 'table' then return Stables.Err('invalid_receipt', 'Invalid payment journal entry.') end
        debit = debit or (entry.accountId == t.walletAccountId and entry.amount == -t.amount)
        credit = credit or (entry.accountId == t.sinkAccountId and entry.amount == t.amount)
    end
    if not debit or not credit then return Stables.Err('invalid_receipt',
            'Payment journal entries do not balance the saved terms.') end
    return Stables.Ok(true)
end

local function CompleteRefund(operationId, characterId, record, save, authorize)
    local E = Stables.Economy
    local receipt = record.refundReceipt
    if not receipt then
        if authorize then
            local allowed = authorize(); if not allowed.ok then return allowed end
        end
        -- Economy derives amount/accounts and the single reversal key from the
        -- original transaction. Caller cannot choose a new key or partial amount.
        local reversed = E.Reverse(record.paymentReceipt.transactionId)
        if not reversed.ok then return reversed end
        receipt = reversed.value
    end
    local candidate = Stables.Copy(record)
    if candidate.state == 'refunded' then
        candidate.state = 'compensation_pending'; candidate.refundReceipt = nil
    end
    local matched = O.Advance(candidate, candidate.revision, 'refunded', { refundReceipt = receipt })
    if not matched.ok then return matched end
    local journal = E.Transaction(receipt.transactionId); if not journal.ok then return journal end
    local j, t = journal.value, record.terms
    if type(j) ~= 'table' or j.transactionId ~= receipt.transactionId or j.operation ~= 'reversal' or j.status ~= 'committed'
        or j.sourceResource ~= 'bcc-stables' or j.reasonCode ~= 'stables.payment_reversal'
        or j.referenceType ~= 'economy_transaction' or j.referenceId ~= record.paymentReceipt.transactionId
        or j.currency ~= t.currency or j.amount ~= t.amount or type(j.entries) ~= 'table' or #j.entries ~= 2 then
        return Stables.Err('invalid_receipt', 'Committed refund journal does not match the fenced purchase.')
    end
    local debit, credit = false, false
    for _, entry in ipairs(j.entries) do
        if type(entry) ~= 'table' then return Stables.Err('invalid_receipt', 'Invalid reversal journal entry.') end
        debit = debit or (entry.accountId == t.sinkAccountId and entry.amount == -t.amount)
        credit = credit or (entry.accountId == t.walletAccountId and entry.amount == t.amount)
    end
    if not debit or not credit then return Stables.Err('invalid_receipt',
            'Reversal entries do not reverse the full payment.') end
    if record.state == 'refunded' then return Stables.Ok(record) end
    local saved = save(operationId, characterId, record.revision, receipt)
    if saved.ok or saved.code ~= 'revision_conflict' then return saved end
    -- Leave concurrent outcomes to an explicit retry/re-read; never post another key.
    return saved
end
P.VerifyPayment = Verify

-- Pre-registration compensation only. No worker/route invokes it. This cannot
-- cancel a prepared/submitted Assets intent and must never be used for one.
function P.RefundUnregistered(operationId, characterId, authorize)
    local ready = Stables.Foundation.RequireReady(); if not ready.ok then return ready end
    local R, E = Stables.Repository, Stables.Economy
    local read = R.Get(operationId, characterId); if not read.ok then return read end
    local record = read.value
    if record.state ~= 'paid' and record.state ~= 'compensation_pending' and record.state ~= 'refunded' then
        return Stables.Err('registration_not_fenced', 'Only verified pre-registration payments can be compensated.')
    end
    local original = Verify(record, record.paymentReceipt); if not original.ok then return original end
    if record.state ~= 'refunded' then
        if authorize then
            local allowed = authorize(); if not allowed.ok then return allowed end
        end
        local fenced = R.FenceUnregistered(operationId, characterId, record.revision)
        if not fenced.ok then return fenced end -- unknown fence commit cannot invoke reversal
        record = fenced.value
    elseif record.registrationFence ~= 'unregistered_v1' then
        return Stables.Err('registration_not_fenced', 'A durable unregistered fence is required.')
    end
    return CompleteRefund(operationId, characterId, record, R.SaveUnregisteredRefund, authorize)
end

function P.RefundRetired(operationId, characterId, authorize)
    local ready = Stables.Foundation.RequireReady(); if not ready.ok then return ready end
    local read = Stables.Repository.Get(operationId, characterId); if not read.ok then return read end
    local record = read.value
    if (record.state ~= 'compensation_pending' and record.state ~= 'refunded') or record.registrationFence ~= 'linked_retirement_v1' then
        return Stables.Err('registration_not_fenced', 'A linked-retirement compensation fence is required.')
    end
    local original = Verify(record, record.paymentReceipt); if not original.ok then return original end
    local retired = Stables.LinkedCleanup.Confirm(record); if not retired.ok then return retired end
    return CompleteRefund(operationId, characterId, record, Stables.Repository.SaveLinkedRefund, authorize)
end

function P.Pay(operationId, characterId, authorize)
    local ready = Stables.Foundation.RequireReady(); if not ready.ok then return ready end
    local R, E = Stables.Repository, Stables.Economy
    local read = R.Get(operationId, characterId); if not read.ok then return read end
    local record = read.value
    if record.state == 'paid' then
        local verified = Verify(record, record.paymentReceipt)
        return verified.ok and Stables.Ok(record) or verified
    end
    if record.state == 'reserved' then
        local checked = Accounts(record.terms, true); if not checked.ok then return checked end
        if authorize then
            local allowed = authorize(); if not allowed.ok then return allowed end
        end
        local pending = R.Advance(operationId, characterId, record.revision, 'payment_pending')
        if not pending.ok then return pending end -- unknown commit cannot trigger remote payment
        record = pending.value
    end
    if record.state ~= 'payment_pending' then return Stables.Err('invalid_transition',
            'Purchase is not awaiting payment.') end
    -- Pending snapshots may predate this consumer. Recheck immutable account
    -- ownership/shape, but allow closed accounts so committed replay can recover.
    local accounts = Accounts(record.terms, false); if not accounts.ok then return accounts end
    local request = O.PaymentRequest(record); if not request.ok then return request end
    if authorize then
        local allowed = authorize(); if not allowed.ok then return allowed end
    end
    -- Economy has no lookup by key. Replay the SAME transfer; its receipt lock
    -- returns the committed result before current balance/account checks.
    local posted = E.Transfer(request.value); if not posted.ok then return posted end
    local verified = Verify(record, posted.value); if not verified.ok then return verified end
    local paid = R.Advance(operationId, characterId, record.revision, 'paid', { paymentReceipt = posted.value })
    if paid.ok or paid.code ~= 'revision_conflict' then return paid end
    -- Another identical caller may have saved this same payment while we read.
    local current = R.Get(operationId, characterId)
    if current.ok and current.value.state == 'paid' and current.value.paymentReceipt.transactionId == posted.value.transactionId then
        local checked = Verify(current.value, current.value.paymentReceipt)
        return checked.ok and current or checked
    end
    return paid
end
