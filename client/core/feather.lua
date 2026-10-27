Stables = Stables or {}
Stables.Client = {}
local C=Stables.Client
function C.Uuid(value)
    return type(value)=='string' and value:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$')~=nil
end
function C.Rpc(action,payload)
    if GetResourceState('feather-core')~='started' then return {ok=false,code='dependency_unavailable'} end
    local done,reply=false,nil
    local called=pcall(function()
        exports['feather-core']:CallRPC('stables.horses.call.'..action..'.v1',payload,function(result,failure)
            if done then return end
            reply=type(result)=='table' and result or {ok=false,code=type(failure)=='table' and failure.code or 'transport_error'}
            done=true
        end,nil,15000)
    end)
    if not called then return {ok=false,code='transport_error'} end
    local deadline=GetGameTimer()+16000
    while not done and GetGameTimer()<deadline do Wait(25) end
    done=true -- Late replies cannot complete or replay an expired player action.
    return reply or {ok=false,code='timeout'}
end
function C.Message(text) print('[bcc-stables] '..text) end
