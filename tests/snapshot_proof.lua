local base=assert(loadfile('tests/fixtures/snapshot_services.lua'))()
local count=0
local function test(name,fn) local ok,err=pcall(fn); assert(ok,name..': '..tostring(err)); count=count+1; print('PASS snapshot proof '..name) end
local function fixture()
    local m=base(); m.commands={}; m.env.RegisterCommand=function(name,fn) m.commands[name]=fn end
    assert(loadfile('server/snapshot_proof.lua','t',m.env))(); m.proof=m.S.SnapshotProof; return m
end
test('synthetic definitions are isolated valid immutable local evidence',function()
    local m=fixture(); local d=m.proof.Definition(); assert(m.S.Operations.Validate(d.record).ok)
    assert(d.record.terms.characterId:match('^bccf') and d.record.terms.horseId~=m.t.horseId and d.assetId~=m.asset.assetId)
    assert(d.record.terms.catalogId=='proof.snapshot' and d.request.holderId==d.record.terms.characterId)
    d.record.terms.amount=99; assert(m.proof.Definition().record.terms.amount==1)
end)
test('cleanup count guard refuses extra missing and uncertain fixture records',function()
    local m=fixture(); local c={stable=1,operation=1,horse=1,registration=1,history=1,outbox=1,lease=0,slot=0,event=0,binding=0,epoch=0,recovery=0}
    assert(m.proof.ValidateCounts(c,0)); c.operation=2; assert(not m.proof.ValidateCounts(c,0))
    c.operation=1; c.horse=nil; assert(not m.proof.ValidateCounts(c,0))
    assert(not m.proof.ValidateCounts(c,3))
end)
test('unsupported isolation and autocommit modes refuse the proof',function()
    local m=fixture(); local rows={{Variable_name='autocommit',Value='ON'},{Variable_name='transaction_isolation',Value='REPEATABLE-READ'}}
    assert(m.proof.ValidateEnvironment(rows)); rows[2].Value='READ-COMMITTED'; assert(m.proof.ValidateEnvironment(rows))
    rows[2].Value='READ-UNCOMMITTED'; assert(not m.proof.ValidateEnvironment(rows))
    rows[2].Value='REPEATABLE-READ'; rows[1].Value='OFF'; assert(not m.proof.ValidateEnvironment(rows))
end)
test('console proof refuses player callers and malformed invocations before threads or SQL',function()
    local m=fixture(); m.env.CreateThread=function() error('unexpected thread') end
    m.env.DB.query=function() error('unexpected query') end
    m.commands.BccStablesSnapshotProof(1,{'run'})
    m.commands.BccStablesSnapshotProof(0,{'run','extra'})
    m.commands.BccStablesSnapshotProof(0,{})
end)
print(count..'/'..count..' snapshot proof guard cases passed; target database concurrency still requires live run.')
