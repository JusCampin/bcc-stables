-- Opt-in console proof of the real Assets boundary, independent of paid purchases.
-- One fixture per character; retirement retains canonical identity/audit forever.
local S, A, O = Stables, Stables.Assets, Stables.Operations
local MODEL, MARKER = 'a_c_horse_morgan_bay', 'bcc-stables.assets.v1'
local busy = false
local function Check(condition, code, message)
    if not condition then error(S.Err(code,message),0) end
end
local function Value(result)
    Check(S.IsResult(result),'invalid_contract','Invalid service result.')
    if not result.ok then error(result,0) end
    return result.value
end
local function Request(characterId)
    return {requestId='stables.asset-proof:'..characterId,assetType='horse',modelKey=MODEL,
        holderType='character',holderId=characterId,provenanceType='stables_asset_proof',provenanceId=characterId,
        reasonCode='stables.asset_proof',metadataVersion=1,
        metadata={proof=MARKER,proofCharacterId=characterId}}
end
local function Facts(value,characterId)
    -- Do not allow extra metadata to be silently destroyed by fixture retirement.
    if type(value)~='table' or type(value.metadata)~='table' then return false end
    for key in pairs(value.metadata) do if key~='proof' and key~='proofCharacterId' then return false end end
    -- Identity validation does not depend on Lua hash iteration order.
    return O.IsUuid(value.assetId) and value.assetType=='horse' and value.modelKey==MODEL
        and value.managerResource=='bcc-stables' and value.provenanceType=='stables_asset_proof'
        and value.provenanceId==characterId and value.metadataVersion==1
        and value.metadata.proof==MARKER and value.metadata.proofCharacterId==characterId
end
local function Original(value,characterId)
    return Facts(value,characterId) and value.status=='active' and value.revision==1
        and type(value.owner)=='table' and value.owner.holderType=='character'
        and value.owner.holderId==characterId and O.IsUuid(value.owner.interestId)
end
local function Receipt(characterId)
    local found=Value(A.FindRegistration(Request(characterId).requestId))
    Check(type(found)=='table' and type(found.found)=='boolean','invalid_contract','Invalid operation lookup.')
    if not found.found then return nil end
    Check(found.operation=='asset.register' and Original(found.result,characterId),
        'proof_conflict','Registration receipt does not match this exact fixture.')
    return found.result
end
local function Current(characterId,receipt)
    local value=Value(A.ReadHorse(receipt.assetId))
    Check(Facts(value,characterId) and value.assetId==receipt.assetId,'proof_conflict','Current asset is not this fixture.')
    return value
end
local function Retired(value,characterId)
    return Facts(value,characterId) and value.status=='retired' and value.revision==2 and value.owner==nil
end
local function Inspect(characterId)
    local receipt=Receipt(characterId)
    if not receipt then return {state='absent',characterId=characterId} end
    local current=Current(characterId,receipt)
    Check(Original(current,characterId) or Retired(current,characterId),
        'proof_conflict','Fixture has changed; manual reconciliation required.')
    return {state=current.status,characterId=characterId,assetId=current.assetId,revision=current.revision,
        registrationRequestId=Request(characterId).requestId,noPaymentSubmitted=true,noEntitySpawned=true}
end
local function Run(source)
    local session=Value(S.Core.RequireSession(source))
    local characterId=session.characterId
    Check(O.IsUuid(characterId),'invalid_contract','Session character UUID required.')
    characterId=characterId:lower()
    print('[bcc-stables:assets-proof] '..json.encode({event='fixture_selected',serverPlayerId=source,characterId=characterId,
        registrationRequestId=Request(characterId).requestId}))
    -- Deterministic identity survives resource/server restart; do not generate a new fixture on retry.
    local request=Request(characterId)
    local receipt=Receipt(characterId)
    if not receipt then receipt=Value(A.RegisterHorse(request)) end
    Check(Original(receipt,characterId),'proof_conflict','Registration result does not match the fixture.')
    local current=Current(characterId,receipt)
    Check(Original(current,characterId),'proof_conflict','Fixture is changed or already retired; no new fixture was created.')
    local replay=Value(A.RegisterHorse(request))
    Check(Original(replay,characterId) and replay.assetId==receipt.assetId and replay.replayed==true,
        'proof_failed','Identical registration did not replay the same asset.')
    local changed=S.Copy(request); changed.modelKey='a_c_horse_arabian_white'
    local conflict=A.RegisterHorse(changed)
    Check(S.IsResult(conflict) and not conflict.ok and conflict.code=='idempotency_conflict',
        'proof_failed','Changed request terms were not rejected.')
    local inspected=Inspect(characterId)
    Check(inspected.assetId==receipt.assetId and inspected.state=='active','proof_failed','Receipt recovery changed fixture identity.')
    inspected.identicalReplay,inspected.changedTermsRefused,inspected.serverPlayerId=true,true,source
    return inspected
end
local function Retire(characterId)
    local receipt=Receipt(characterId)
    Check(receipt~=nil,'proof_absent','No proof registration receipt exists; nothing was retired.')
    local current=Current(characterId,receipt)
    local request={requestId='stables.asset-proof.retire:'..characterId,assetId=receipt.assetId,
        expectedRevision=1,reasonCode='stables.asset_proof_cleanup'}
    if Retired(current,characterId) then
        local found=Value(A.FindRegistration(request.requestId))
        Check(type(found)=='table' and found.found==true and found.operation=='asset.retire'
            and Retired(found.result,characterId) and found.result.assetId==receipt.assetId,
            'proof_conflict','Retired state lacks this fixture cleanup receipt.')
    else
        Check(Original(current,characterId),'proof_conflict','Changed fixture will not be retired.')
        local retired=Value(A.RetireProof(request))
        Check(Retired(retired,characterId) and retired.assetId==receipt.assetId,'proof_failed','Retirement result did not match.')
    end
    local inspected=Inspect(characterId)
    Check(inspected.state=='retired','proof_failed','Retirement is not confirmed by a current read.')
    inspected.auditRetained=true
    return inspected
end

RegisterCommand('BccStablesAssetsProof',function(source,args)
    if source~=0 then return end
    local function Log(result) print('[bcc-stables:assets-proof] '..json.encode(result)) end
    if StablesConfig.assetProof~=true then Log(S.Err('disabled','Set assetProof=true only for this controlled test.')); return end
    if busy then Log(S.Err('busy','Assets proof is already running.')); return end
    local action,id=args[1],args[2]
    local playerId=tonumber(id)
    if #args~=2 or (action~='run' and action~='inspect' and action~='retire')
        or (action=='run' and (not playerId or playerId%1~=0 or playerId<1 or playerId>65535))
        or (action~='run' and not O.IsUuid(id)) then
        Log(S.Err('invalid_input','BccStablesAssetsProof run <serverPlayerId> | inspect <characterUUID> | retire <characterUUID>')); return
    end
    busy=true
    CreateThread(function()
        local ok,result=pcall(function()
            Value(S.Foundation.RequireReady())
            if action=='run' then return Run(playerId) end
            if action=='inspect' then return Inspect(id:lower()) end
            return Retire(id:lower())
        end)
        busy=false
        if ok then Log(S.Ok(result))
        elseif S.IsResult(result) then Log(result)
        else Log(S.Err('proof_error','Unexpected proof error; inspect the same character UUID before retrying.')) end
    end)
end,true)
