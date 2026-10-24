local busy = false
local function Uuid(v)
    return type(v) == 'string' and
        v:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') ~= nil
end
local function Rpc(route, payload)
    local reply, done
    exports['feather-core']:CallRPC(route, payload, function(...)
        if not done then reply, done = table.pack(...), true end
    end, nil, 5000)
    local started = GetGameTimer()
    while not done and GetGameTimer() - started < 6000 do Wait(25) end
    done = true
    if not reply then error('timeout', 0) end
    local result, err = reply[1], reply[2]
    if type(result) ~= 'table' or result.ok ~= true then
        error(tostring(type(result) == 'table' and result.code or type(err) == 'table' and err.code or 'invalid_result'),
            0)
    end
    return result.value
end
local function Validate(item)
    return type(item) == 'table' and Uuid(item.horseId) and Uuid(item.assetId) and Uuid(item.operationId)
        and type(item.modelKey) == 'string' and #item.modelKey <= 100 and item.modelKey:match('^a_c_horse_[a-z0-9_]+$')
        and type(item.assetRevision) == 'number' and item.assetRevision % 1 == 0 and item.assetRevision >= 1
        and (item.availability == 'stored' or item.availability == 'active') and item.gameplayAvailable == false
        and type(item.projectionRevision)=='number' and item.projectionRevision%1==0
        and item.projectionRevision>=0 and item.projectionRevision<=9007199254740991
        and (item.availability=='active')==(item.projectionRevision%2==1)
end
local function Print(item)
    print(('[bcc-stables] horseId=%s assetId=%s model=%s availability=%s projectionRevision=%d assetRevision=%d gameplayAvailable=false')
        :format(
            item.horseId, item.assetId, item.modelKey, item.availability, item.projectionRevision, item.assetRevision))
end
local function Command(name, body)
    RegisterCommand(name, function(_, args)
        if busy then return end
        busy = true
        CreateThread(function()
            local ok, err = pcall(body, args)
            busy = false
            if not ok then print('[bcc-stables] ' .. name .. ' failed: ' .. tostring(err)) end
        end)
    end, false)
end
Command('BccStablesOwnedHorsesSmokeTest', function(args)
    assert(#args <= 1 and (not args[1] or Uuid(args[1])), 'Use optional afterHorseId UUID.')
    local cursor = args[1] and args[1]:lower()
    local v = Rpc('stables.horses.list.v1', cursor and { afterHorseId = cursor } or {})
    assert(type(v) == 'table' and type(v.items) == 'table' and #v.items <= 10 and v.pageSize == 10
        and type(v.selectionAvailable) == 'boolean' and v.gameplayAvailable == false and
        (v.nextCursor == nil or Uuid(v.nextCursor)), 'invalid_result')
    local previous = cursor
    for _, item in ipairs(v.items) do
        assert(Validate(item) and (not previous or item.horseId > previous), 'invalid_result'); previous = item.horseId
    end
    assert(not v.nextCursor or ((not previous or v.nextCursor >= previous) and (not cursor or v.nextCursor > cursor)),
        'invalid_result')
    print(('[bcc-stables] owned horses RPC PASS; entries=%d nextCursor=%s selectionAvailable=%s gameplayAvailable=false')
        :format(#v.items, tostring(v.nextCursor), tostring(v.selectionAvailable)))
    for _, item in ipairs(v.items) do Print(item) end
end)
Command('BccStablesOwnedHorseInspect', function(args)
    assert(#args == 1 and Uuid(args[1]), 'Supply exactly one horseId UUID.')
    local v = Rpc('stables.horses.get.v1', { horseId = args[1]:lower() })
    assert(Validate(v) and v.horseId == args[1]:lower(), 'invalid_result')
    print('[bcc-stables] owned horse RPC PASS'); Print(v)
end)
local function Selection(v)
    assert(type(v) == 'table' and type(v.revision) == 'number' and v.revision % 1 == 0 and v.revision >= 0
        and type(v.selected) == 'boolean' and type(v.available) == 'boolean' and v.gameplayAvailable == false,
        'invalid_result')
    if v.available then
        assert(v.selected and Validate(v.horse), 'invalid_result')
    else
        assert(v.horse == nil, 'invalid_result')
    end
    print(('[bcc-stables] selection RPC PASS; revision=%d selected=%s available=%s horseId=%s gameplayAvailable=false')
        :format(
            v.revision, tostring(v.selected), tostring(v.available), tostring(v.horse and v.horse.horseId)))
end
local function Expected(v)
    local n = tonumber(v); assert(n and n % 1 == 0 and n >= 0 and n <= 9007199254740991,
        'Supply integer expectedRevision from selection inspection.')
    return n
end
Command('BccStablesSelectionInspect', function(args)
    assert(#args == 0, 'No arguments accepted.')
    Selection(Rpc('stables.horses.selection.get.v1', {}))
end)
Command('BccStablesSelectHorse', function(args)
    assert(#args == 2 and Uuid(args[1]), 'BccStablesSelectHorse <horseId> <expectedRevision>')
    Selection(Rpc('stables.horses.selection.set.v1', { horseId = args[1]:lower(), expectedRevision = Expected(args[2]) }))
end)
Command('BccStablesSelectionClear', function(args)
    assert(#args == 1, 'BccStablesSelectionClear <expectedRevision>')
    Selection(Rpc('stables.horses.selection.clear.v1', { expectedRevision = Expected(args[1]) }))
end)
local function CallRevision(state,revision)
    local allowed={prepared={[0]=true},submitting={[1]=true},active={[2]=true},cleanup_pending={[3]=true},
        released={[1]=true,[4]=true,[5]=true},reconciliation_required={[2]=true,[3]=true,[4]=true}}
    return allowed[state] and allowed[state][revision]==true
end
local function Call(v)
    assert(type(v)=='table' and v.entitySpawning==false and v.gameplayAvailable==false
        and ({empty=true,prepared=true,submitting=true,active=true,cleanup_pending=true,released=true,reconciliation_required=true})[v.state],'invalid_result')
    if v.state~='empty' then
        assert(Uuid(v.generationId) and Uuid(v.horseId) and Uuid(v.assetId) and type(v.modelKey)=='string'
            and type(v.sessionCurrent)=='boolean' and type(v.revision)=='number' and v.revision%1==0
            and CallRevision(v.state,v.revision),'invalid_result')
    end
    print(('[bcc-stables] call preparation RPC PASS; state=%s generationId=%s horseId=%s revision=%s sessionCurrent=%s entitySpawning=false'):format(
        v.state,tostring(v.generationId),tostring(v.horseId),tostring(v.revision),tostring(v.sessionCurrent)))
end
Command('BccStablesCallPrepare',function(args)
    assert(#args==1,'BccStablesCallPrepare <expectedSelectionRevision>')
    Call(Rpc('stables.horses.call.prepare.v1',{expectedSelectionRevision=Expected(args[1])}))
end)
Command('BccStablesCallInspect',function(args)
    assert(#args<=1 and (not args[1] or Uuid(args[1])),'BccStablesCallInspect [generationId]')
    Call(Rpc('stables.horses.call.get.v1',args[1] and {generationId=args[1]:lower()} or {}))
end)
Command('BccStablesCallAbort',function(args)
    assert(#args==1 and Uuid(args[1]),'BccStablesCallAbort <generationId>')
    Call(Rpc('stables.horses.call.abort.v1',{generationId=args[1]:lower()}))
end)
