-- Pure internal model only. No routes, exports, SQL, Inventory calls or native
-- setters. A future repository must atomically journal/apply these transitions.
Stables.CareOperations={}
local C,S=Stables.CareOperations,Stables
local MAX=9007199254740991
local names={'operationId','characterId','horseId','instanceId','definitionId','itemRevision','itemName','policyRevision','healthGain','staminaGain'}
local function Int(v,min,max) return type(v)=='number' and v%1==0 and v>=min and v<=max end
local function Bad() return S.Err('invalid_care','Care terms or condition require reconciliation.') end
local function Condition(c,horse)
    if type(c)~='table' then return false end
    local fields={horseId=true,healthCore=true,staminaCore=true,revision=true,policyRevision=true}
    for k in pairs(c) do if not fields[k] then return false end end
    return c.horseId==horse and Int(c.healthCore,0,100) and Int(c.staminaCore,0,100)
        and Int(c.revision,0,MAX) and Int(c.policyRevision,1,4294967295)
end
function C.ValidateCondition(c)
    if type(c)~='table' or not S.Operations.IsUuid(c.horseId) or c.horseId~=c.horseId:lower() or not Condition(c,c.horseId) then return Bad() end
    return S.Ok(S.Copy(c))
end
function C.New(input,condition)
    if type(input)~='table' then return Bad() end
    local t={}
    for k in pairs(input) do local known=false; for _,name in ipairs(names) do if name==k then known=true; break end end; if not known then return Bad() end end
    for _,name in ipairs(names) do t[name]=input[name] end
    for _,name in ipairs({'operationId','characterId','horseId'}) do
        if not S.Operations.IsUuid(t[name]) then return Bad() end
        t[name]=t[name]:lower()
    end
    if not Int(t.instanceId,1,MAX) or not Int(t.definitionId,1,MAX) or not Int(t.itemRevision,0,MAX)
        or not Int(t.policyRevision,1,4294967295) or not Int(t.healthGain,0,100) or not Int(t.staminaGain,0,100)
        or type(t.itemName)~='string' or #t.itemName>100 or not t.itemName:match('^[a-z0-9_]+$')
        or not Condition(condition,t.horseId) or condition.policyRevision~=t.policyRevision or condition.revision==MAX then return Bad() end
    local after={horseId=t.horseId,healthCore=math.min(100,condition.healthCore+t.healthGain),
        staminaCore=math.min(100,condition.staminaCore+t.staminaGain),policyRevision=t.policyRevision,revision=condition.revision+1}
    if after.healthCore==condition.healthCore and after.staminaCore==condition.staminaCore then
        return S.Err('care_no_benefit','Care must have a bounded benefit before consumption.')
    end
    local parts={}
    for _,name in ipairs(names) do parts[#parts+1]=type(t[name])=='number' and string.format('%.0f',t[name]) or t[name] end
    for _,name in ipairs({'healthCore','staminaCore','revision'}) do parts[#parts+1]=string.format('%.0f',condition[name]) end
    return S.Ok({contract=1,terms=t,before=S.Copy(condition),after=after,fingerprint=table.concat(parts,'|'),state='prepared',revision=0})
end
function C.Validate(record)
    if type(record)~='table' or record.contract~=1 then return Bad() end
    local built=C.New(record.terms,record.before)
    if not built.ok or built.value.fingerprint~=record.fingerprint then return Bad() end
    for _,name in ipairs({'horseId','healthCore','staminaCore','policyRevision','revision'}) do
        if type(record.after)~='table' or record.after[name]~=built.value.after[name] then return Bad() end
    end
    local revisions={prepared=0,consumed_effect_pending=1,applied=2,cancelled=1}
    if revisions[record.state]~=record.revision then return Bad() end
    if record.state~='prepared' then
        local receipt=record.receipt
        local checked=C.MatchReceipt(built.value,receipt)
        if not checked.ok or (record.state=='cancelled')~=(receipt.state=='cancelled') then return Bad() end
    elseif record.receipt~=nil then return Bad() end
    return S.Ok(S.Copy(record))
end
function C.InventoryRequest(record)
    local valid=C.Validate(record); if not valid.ok then return valid end
    local t=valid.value.terms
    return S.Ok({operationId=t.operationId,characterId=t.characterId,instanceId=t.instanceId,definitionId=t.definitionId,
        expectedRevision=t.itemRevision,itemName=t.itemName,purpose='stables.care.v1',
        effectReference=t.horseId..':policy'..string.format('%.0f',t.policyRevision)})
end
function C.MatchReceipt(record,receipt)
    if type(record)~='table' or type(record.terms)~='table' then return Bad() end
    local t=record.terms
    if not S.Operations.IsUuid(t.horseId) or not Int(t.policyRevision,1,4294967295) then return Bad() end
    if type(receipt)~='table' or receipt.contractVersion~=1 or receipt.sourceResource~='bcc-stables'
        or (receipt.state~='consumed' and receipt.state~='cancelled') or type(receipt.replayed)~='boolean'
        or not Int(receipt.inventoryId,0,MAX) or (receipt.state=='consumed' and receipt.inventoryId==0)
        or (receipt.state=='cancelled' and receipt.inventoryId~=0) then return Bad() end
    local expected={operationId=t.operationId,characterId=t.characterId,instanceId=t.instanceId,definitionId=t.definitionId,
        expectedRevision=t.itemRevision,itemName=t.itemName,purpose='stables.care.v1',
        effectReference=t.horseId..':policy'..string.format('%.0f',t.policyRevision)}
    for k,v in pairs(expected) do if receipt[k]~=v then return S.Err('care_receipt_conflict','Consumption receipt does not match reserved care terms.') end end
    return S.Ok(true)
end
function C.Resolve(record,receipt)
    local valid=C.Validate(record); if not valid.ok then return valid end
    local match=C.MatchReceipt(valid.value,receipt); if not match.ok then return match end
    local r=valid.value
    if r.state~='prepared' then
        if r.receipt.state~=receipt.state or r.receipt.inventoryId~=receipt.inventoryId then return Bad() end
        return S.Ok({operation=r,replayed=true})
    end
    r.receipt=S.Copy(receipt); r.state=receipt.state=='consumed' and 'consumed_effect_pending' or 'cancelled'; r.revision=1
    return S.Ok({operation=r,replayed=false})
end
function C.Apply(record,current)
    local valid=C.Validate(record); if not valid.ok then return valid end
    local r=valid.value
    if r.state~='consumed_effect_pending' then return S.Err('care_effect_not_pending','An unapplied consumed receipt is required.') end
    if not Condition(current,r.terms.horseId) then return Bad() end
    for _,name in ipairs({'healthCore','staminaCore','revision','policyRevision'}) do
        if current[name]~=r.before[name] then return S.Err('condition_revision_conflict','Retain consumed operation for reconciliation; do not consume again.') end
    end
    r.state='applied'; r.revision=2
    return S.Ok({operation=r,condition=S.Copy(r.after)})
end
