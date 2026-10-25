-- Read-only proof tickets; no reservation, animation, core write or item use.
Stables.CareTarget={}
local T,S=Stables.CareTarget,Stables
local tickets,serial={},0
function T.Payload(p)
    if type(p)~='table' or not S.Operations.IsUuid(p.generationId) or type(p.sequence)~='number'
        or p.sequence%1~=0 or p.sequence<1 or p.sequence>9007199254740991 then return false end
    local keys={generationId=true,sequence=true,ownerAlive=true,horseAlive=true,unoccupied=true,notLeading=true}
    for k in pairs(p) do if not keys[k] then return false end end
    for _,k in ipairs({'ownerAlive','horseAlive','unoccupied','notLeading'}) do if type(p[k])~='boolean' then return false end end
    return true
end
function T.Report(p,source)
    if not T.Payload(p) then return S.Err('invalid_input','Exact care simulator report required.') end
    local ticket=tickets[p.generationId]
    if not ticket or ticket.sequence~=p.sequence or ticket.snapshot.networkOwner~=source or ticket.reply
        or GetGameTimer()>ticket.expires then return S.Err('care_report_stale','Care report ticket is no longer current.') end
    local current=S.NativeCalls.RecheckCareObserver(ticket.snapshot,ticket.source,ticket.context)
    if not current.ok then return current end
    ticket.reply=S.Copy(p)
    return S.Ok({recorded=true})
end
function T.Check(p,source,context)
    if type(p)~='table' or next(p)~=nil then return S.Err('invalid_input','Care eligibility proof accepts no fields.') end
    local observed=S.NativeCalls.CareObserver(source,context); if not observed.ok then return observed end
    local snapshot=observed.value
    local rules=S.CarePolicy.ObservationRules(); if not rules.ok then return rules end
    if snapshot.distance>rules.value.maxDistance then return S.Err('care_too_far','Stand beside your horse for care.') end
    if snapshot.movementIdle~=true then return S.Err('care_ineligible','Stop following/approach movement before care.') end
    if tickets[snapshot.generationId] then return S.Err('busy','A care observation is already pending.') end
    local count=0; for _ in pairs(tickets) do count=count+1 end
    if count>=32 or serial==9007199254740991 then return S.Err('busy','Care observation capacity reached.') end
    serial=serial+1
    local issued=GetGameTimer()
    local ticket={sequence=serial,source=source,context=S.Copy(context),snapshot=S.Copy(snapshot),issued=issued,expires=issued+math.min(750,rules.value.ttlMs)}
    tickets[snapshot.generationId]=ticket
    local ok,result=pcall(function()
        TriggerClientEvent('bcc-stables:call:care_check',snapshot.networkOwner,{generationId=snapshot.generationId,observerId=snapshot.observerId,
            netId=snapshot.netId,modelKey=snapshot.modelKey,ownerSource=source,targetNetId=snapshot.targetNetId,sequence=serial})
        while not ticket.reply and GetGameTimer()<ticket.expires do Wait(25) end
        if not ticket.reply or GetGameTimer()>ticket.expires then return S.Err('care_observation_unknown','Fresh current-simulator report required.') end
        local fresh=S.NativeCalls.RecheckCareObserver(snapshot,source,context); if not fresh.ok then return fresh end
        local reply=ticket.reply
        local facts={sessionCurrent=true,sameHorse=true,sameOwner=true,defaultRoute=true,ownerAlive=reply.ownerAlive,horseAlive=reply.horseAlive,
            unoccupied=reply.unoccupied,notLeading=reply.notLeading,movementIdle=fresh.value.movementIdle,distance=fresh.value.distance,
            observedAt=issued,now=GetGameTimer()}
        local eligible=S.CarePolicy.CheckActiveFacts(facts); if not eligible.ok then return eligible end
        return S.Ok({eligible=true,generationId=snapshot.generationId,networkOwner=snapshot.networkOwner,
            distance=fresh.value.distance,policyRevision=eligible.value.policyRevision,feedingEnabled=false,observationOnly=true})
    end)
    tickets[snapshot.generationId]=nil
    return ok and result or S.Err('care_observation_unknown','Care observation failed; no state changed.')
end
function T.Install()
    for _,r in ipairs({{'care_eligibility',T.Check,true},{'care_check_result',T.Report,false}}) do
        local request=r[3]
        local registered=S.Core.Call('RegisterRpc','stables.horses.call.'..r[1]..'.v1',r[2],{
            contract=1,direction='client_to_server',requireCharacter=request,windowMs=2000,maxCalls=2,
            maxPayloadBytes=request and 16 or 256,maxDepth=request and 1 or 2,maxNodes=request and 2 or 8,
            validatePayload=request and S.EmptyPayload or T.Payload})
        if not registered.ok then return registered end
    end
    return S.Ok({routes=2})
end
