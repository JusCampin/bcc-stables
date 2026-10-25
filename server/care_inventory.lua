-- Optional read/recovery adapter. No consumption/cancellation export is called
-- here and no player route or automatic polling worker is installed.
Stables.CareInventory={}
local I,S=Stables.CareInventory,Stables
local function Call(method,payload)
    if GetResourceState('feather-inventory')~='started' then return S.Err('inventory_unavailable','Inventory is not started; retain the care operation.') end
    local called,result=pcall(function()
        local provider=exports['feather-inventory']
        if payload==nil then return provider[method](provider) end
        return provider[method](provider,payload)
    end)
    if not called then return S.Err('inventory_outcome_unknown','Inventory reply unavailable; retain the original care operation.') end
    return S.Ok(result)
end
function I.Probe()
    local call=Call('GetConsumptionContract'); if not call.ok then return call end
    local c=call.value
    if type(c)~='table' or c.contractVersion~=1 or c.ready~=true or c.durableConsumption~=1 then
        return S.Err('inventory_contract_unavailable','Ready durable consumption Contract1 is required.')
    end
    return S.Ok({ok=true,contract=1,ready=true,recoveryRead=true,feedingEnabled=false})
end
function I.Inspect(record)
    local request=S.CareOperations.InventoryRequest(record); if not request.ok then return request end
    local ready=I.Probe(); if not ready.ok then return ready end
    local called=Call('InspectCharacterConsumption',request.value); if not called.ok then return called end
    local result=called.value
    if type(result)~='table' or type(result.ok)~='boolean' then return S.Err('inventory_invalid_contract','Invalid Inventory receipt envelope; retain care reservation.') end
    if not result.ok then
        local code=type(result.error)=='table' and result.error.code
        if type(code)~='string' or #code>64 or not code:match('^[a-z_]+$') then
            return S.Err('inventory_invalid_contract','Invalid Inventory error; retain care reservation.')
        end
        if code=='not_found' then return S.Err('care_consumption_unresolved','Receipt absent at observation time; no cancellation or benefit is inferred.') end
        return S.Err('inventory_'..code,'Inventory inspection refused; retain the exact care operation.')
    end
    local receipt=result.value
    local match=S.CareOperations.MatchReceipt(record,receipt); if not match.ok then return match end
    -- Copy only the verified flat receipt contract, never arbitrary provider data.
    local view={}
    for _,name in ipairs({'contractVersion','sourceResource','state','inventoryId','replayed','operationId','characterId',
        'instanceId','definitionId','expectedRevision','itemName','purpose','effectReference'}) do view[name]=receipt[name] end
    return S.Ok(view)
end
function I.Recover(operationId,characterId,authorize)
    local saved=S.CareRepository.Get(operationId,characterId,authorize)
    if not saved.ok then return saved end
    local r=saved.value
    if r.state=='applied' or r.state=='cancelled' then
        -- Verify durable local effect/slot evidence without a provider round trip.
        return S.CareRepository.CommitReceipt(operationId,characterId,r.receipt,authorize)
    end
    local receipt=I.Inspect(r); if not receipt.ok then return receipt end
    -- Fresh authority is checked again by the repository after the yielding read.
    return S.CareRepository.CommitReceipt(operationId,characterId,receipt.value,authorize)
end
RegisterCommand('BccStablesCareInventorySmokeTest',function(source,args)
    if source~=0 then return end
    if #(args or {})~=0 then print('[bcc-stables:care-inventory] BccStablesCareInventorySmokeTest'); return end
    local ready=S.Foundation.RequireReady()
    local result=ready.ok and I.Probe() or ready
    print('[bcc-stables:care-inventory] '..json.encode(result))
end,true)
