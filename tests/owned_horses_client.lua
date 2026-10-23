local ID='10000000-0000-4000-8000-000000000001'
local ASSET='90000000-0000-4000-8000-000000000009'
local function fixture(mode)
    local e=setmetatable({},{__index=_G}); local m={commands={},logs={},time=0}
    e.RegisterCommand=function(name,fn) m.commands[name]=fn end
    e.CreateThread=function(fn) fn() end
    e.GetGameTimer=function() return m.time end
    e.Wait=function(ms) m.time=m.time+ms end
    e.print=function(v) m.logs[#m.logs+1]=v end
    e.exports={['feather-core']={CallRPC=function(_,route,payload,callback)
        m.callback=callback; m.payload=payload
        if mode=='timeout' then return end
        if mode=='denied' then callback(nil,{code='horse_not_found'}); return end
        if mode=='disabled' then callback(nil,{code='selection_disabled'}); return end
        local item={horseId=ID,operationId=ID,assetId=ASSET,assetRevision=1,modelKey='a_c_horse_morgan_bay',availability='stored',gameplayAvailable=false}
        if mode=='malformed' then item.gameplayAvailable=true end
        local value=route=='stables.horses.list.v1' and {items=mode=='empty' and {} or {item},pageSize=10,selectionAvailable=false,gameplayAvailable=false} or item
        if route:find('stables.horses.selection.',1,true)==1 then
            local clear=route=='stables.horses.selection.clear.v1'
            value={revision=clear and 2 or 1,selected=not clear,available=not clear,horse=not clear and item or nil,gameplayAvailable=false}
        end
        if route:find('stables.horses.call.',1,true)==1 then
            if route=='stables.horses.call.get.v1' and not payload.generationId then
                value={state='empty',entitySpawning=false,gameplayAvailable=false}
            else
                local released=route=='stables.horses.call.abort.v1'
                value={generationId=ID,horseId=ID,assetId=ASSET,modelKey='a_c_horse_morgan_bay',state=released and 'released' or 'prepared',
                    revision=released and 1 or 0,sessionCurrent=true,entitySpawning=false,gameplayAvailable=false}
            end
        end
        if mode=='submitting' then value.state='submitting'; value.revision=1 end
        local lifecycle={active=2,cleanup_pending=3,released=4,reconciliation_required=3}
        if lifecycle[mode] then value.state=mode; value.revision=lifecycle[mode] end
        if mode=='recovered' then value.state='released'; value.revision=5 end
        if mode=='bad-recovery' then value.state='released'; value.revision=6 end
        if mode=='bad-submission' then value.state='submitting'; value.revision=0 end
        callback({ok=true,value=value})
    end}}
    assert(loadfile('client/owned_horses.lua','t',e))()
    m.run=function(name,args) m.commands[name](0,args or {}) end
    return m
end
local m=fixture(); m.run('BccStablesOwnedHorsesSmokeTest'); assert(m.logs[1]:find('entries=1',1,true) and m.logs[2]:find(ASSET,1,true))
m.run('BccStablesOwnedHorseInspect',{ID}); assert(m.payload.horseId==ID and m.logs[3]:find('PASS',1,true))
print('PASS owned horse client validates list and exact-ID read')
m=fixture('empty'); m.run('BccStablesOwnedHorsesSmokeTest'); assert(m.logs[1]:find('entries=0',1,true))
m=fixture('denied'); m.run('BccStablesOwnedHorseInspect',{ID}); assert(m.logs[1]:find('horse_not_found',1,true))
print('PASS owned horse client empty and denied outcomes remain distinct')
m=fixture('timeout'); m.run('BccStablesOwnedHorsesSmokeTest'); assert(m.time==6000 and m.logs[1]:find('timeout',1,true))
m.callback({ok=true,value={}}); assert(#m.logs==1)
print('PASS owned horse client bounds waits and ignores late results')
m=fixture('malformed'); m.run('BccStablesOwnedHorsesSmokeTest'); assert(not m.logs[1]:find('PASS',1,true))
print('PASS owned horse client rejects advertised gameplay')
m=fixture(); m.run('BccStablesSelectionInspect'); assert(m.logs[1]:find('revision=1',1,true) and m.logs[1]:find('selected=true',1,true))
m=fixture('disabled'); m.run('BccStablesSelectHorse',{ID,'0'}); assert(m.logs[1]:find('selection_disabled',1,true))
print('PASS selection client inspect and disabled rejection')
m=fixture(); m.run('BccStablesSelectHorse',{ID,'0'}); assert(m.payload.expectedRevision==0 and m.payload.horseId==ID)
m.run('BccStablesSelectionClear',{'1'}); assert(m.payload.expectedRevision==1 and m.logs[2]:find('selected=false',1,true))
print('PASS selection client sends explicit CAS revision for set and clear')
m=fixture(); m.run('BccStablesSelectHorse',{ID,'-1'}); assert(m.payload==nil and not m.logs[1]:find('PASS',1,true))
print('PASS selection client rejects invalid revision before RPC')
m=fixture(); m.run('BccStablesCallInspect'); assert(m.logs[1]:find('state=empty',1,true))
print('PASS call client distinguishes empty runtime slot')
m=fixture(); m.run('BccStablesCallPrepare',{'1'}); assert(m.payload.expectedSelectionRevision==1 and m.logs[1]:find('state=prepared',1,true))
print('PASS call client prepares with explicit selection revision')
m=fixture(); m.run('BccStablesCallAbort',{ID}); assert(m.payload.generationId==ID and m.logs[1]:find('state=released',1,true))
print('PASS call client aborts exact generation without spawning')
m=fixture('submitting'); m.run('BccStablesCallInspect',{ID}); assert(m.logs[1]:find('state=submitting',1,true))
m=fixture('bad-submission'); m.run('BccStablesCallInspect',{ID}); assert(not m.logs[1]:find('PASS',1,true))
print('PASS call client inspects submitted fence and refuses inconsistent revision')
for _,state in ipairs({'active','cleanup_pending','released','reconciliation_required'}) do
    m=fixture(state); m.run('BccStablesCallInspect',{ID}); assert(m.logs[1]:find('state='..state,1,true))
end
print('PASS call client inspects durable lifecycle states without advertising native spawning')
m=fixture('recovered'); m.run('BccStablesCallInspect',{ID}); assert(m.logs[1]:find('revision=5',1,true))
m=fixture('bad-recovery'); m.run('BccStablesCallInspect',{ID}); assert(not m.logs[1]:find('PASS',1,true))
print('PASS call client accepts audited recovery revision and rejects unknown released revision')
print('13/13 owned horse selection and call client cases passed; CFX remains pending.')
