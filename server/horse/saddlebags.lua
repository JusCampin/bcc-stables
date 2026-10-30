-- The bag's Inventory instance owns storage; the active horse only gates access.
Stables.Saddlebags={}
local B,F,H=Stables.Saddlebags,Stables.Feather,Stables.HorseController
local function inventory(method,p)
    local ok,result=pcall(function() local e=exports['feather-inventory'];return e[method](e,p) end)
    if not ok then return F.Error('storage_unavailable','feather-inventory:'..method..' failed: '..tostring(result)) end
    if type(result)~='table' or type(result.ok)~='boolean' then
        return F.Error('invalid_contract','feather-inventory:'..method..' returned an invalid storage result.')
    end
    if not result.ok then
        local failure=type(result.error)=='table' and result.error or result
        return F.Error(failure.code or 'storage_unavailable','feather-inventory:'..method..': '..(failure.message or 'Storage request refused.'))
    end
    return result
end
function B.Enabled() return Stables.Tack.Enabled() and Config.saddlebags and Config.saddlebags.enabled==true end
local function record(source,instanceId)
    if not B.Enabled() then return nil end
    local session=F.RequireSession(source);if not session.ok then return nil end
    local r=H.MovementRecord(session.value)
    if not r or r.flee or r.care or not r.tack or not r.tack.saddlebag or r.tack.saddlebag.instanceId~=instanceId then return nil end
    local ped=GetPlayerPed(source)
    if not ped or ped==0 or not DoesEntityExist(ped) then return nil end
    local a,b=GetEntityCoords(ped),GetEntityCoords(r.entity)
    if not a or not b or (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2>9 then return nil end
    return r,session.value
end
function B.Start()
    if not Stables.Tack.Enabled() then return F.Ok(true) end
    local cfg=Config.saddlebags or {slots=50,maxWeight=250}
    local registered=inventory('RegisterCollectionStorage',{collectionKey='stables.tack.v1',itemName='horse_saddlebag',
        slots=cfg.slots,maxWeight=cfg.maxWeight,validate=function(source,instanceId) return record(source,instanceId)~=nil end})
    if not registered.ok then return registered end
    return F.Call('feather-core','RegisterRpc','stables.horses.call.saddlebags.v1',function(_,source)
        local session=F.RequireSession(source);if not session.ok then return session end
        local r=H.MovementRecord(session.value)
        local bag=r and r.tack and r.tack.saddlebag
        if not bag or not record(source,bag.instanceId) then return F.Error('saddlebags_unavailable','Stand beside your horse with saddlebags equipped.') end
        local allowed=H.CheckCareOccupancy(session.value,r,false)
        if not allowed or not record(source,bag.instanceId) then return F.Error('saddlebags_unavailable','Horse storage is unavailable.') end
        return inventory('OpenCollectionStorage',{source=source,characterId=session.value.characterId,
            collectionKey='stables.tack.v1',instanceId=bag.instanceId})
    end,{contract=1,direction='client_to_server',requireCharacter=true,windowMs=2000,maxCalls=1,
        maxPayloadBytes=16,maxDepth=1,maxNodes=1,validatePayload=function(p) return type(p)=='table' and next(p)==nil end})
end
function B.Summary(session,instanceId,snapshot)
    return inventory('GetCollectionStorage',{characterId=session.characterId,collectionKey='stables.tack.v1',instanceId=instanceId,snapshot=snapshot==true})
end
