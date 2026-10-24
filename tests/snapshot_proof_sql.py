"""Run the proof's actual Lua orchestration with separate SQLite WAL connections.
This verifies SQL shape/coordination/cleanup, not MariaDB isolation or locking.
"""
import sqlite3
import tempfile
from pathlib import Path
from lupa.lua54 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
m = lua.execute("return assert(loadfile('tests/fixtures/snapshot_services.lua'))()()")
_, specs = m.q.QuerySpec()
names = {
    'stable': 'fs_character_stables', 'operation': 'fs_operations',
    'registration': 'fs_asset_registrations', 'horse': 'fs_horses',
    'history': 'fs_horse_history', 'outbox': 'fs_outbox', 'event': 'fs_horse_runtime_events',
    'slot': 'fs_call_slots', 'previousLease': 'fs_call_leases', 'currentLease': 'fs_call_leases',
    'previousBinding': 'fs_call_bindings', 'currentBinding': 'fs_call_bindings',
    'previousAudit': 'fs_call_recoveries', 'currentAudit': 'fs_call_recoveries',
    'previousEpoch': 'fs_call_process_epochs', 'currentEpoch': 'fs_call_process_epochs',
}
specs = [(s.name, list(s.fields.values())) for s in specs.values()]
with tempfile.TemporaryDirectory(prefix='stables-snapshot-', dir=Path.cwd()) as temp:
    path = str(Path(temp) / 'proof.sqlite')
    initial = sqlite3.connect(path, isolation_level=None)
    initial.execute('PRAGMA journal_mode=WAL')
    created = set()
    defaults = {'revision': '0', 'kind': "'horse_purchase'", 'availability': "'stored'", 'biological_state': "'alive'",
                'delivered': '0', 'state': "'bound'"}
    for name, fields in specs:
        table = names[name]
        if table in created:
            continue
        created.add(table)
        if name == 'stable':
            fields = fields + ['selected_horse_id']
        columns = []
        for i, field in enumerate(fields):
            column = '`' + field + '`'
            if i == 0:
                column += ' PRIMARY KEY'
            elif field in defaults:
                column += ' DEFAULT ' + defaults[field]
            columns.append(column)
        initial.execute('CREATE TABLE ' + table + ' (' + ','.join(columns) + ')')
    initial.close()
    connections = {}
    def connection(task):
        if task not in connections:
            connections[task] = sqlite3.connect(path, isolation_level=None, timeout=1)
        return connections[task]
    def execute(task, method, sql, params):
        conn = connection(task)
        values = [params[i] for i in range(1, int(params.n) + 1)]
        if sql == 'SELECT CONNECTION_ID()':
            return list(connections).index(task) + 1
        if sql.startswith('SHOW VARIABLES'):
            return lua.table_from([lua.table_from({'Variable_name': 'autocommit', 'Value': 'ON'}),
                                   lua.table_from({'Variable_name': 'transaction_isolation', 'Value': 'REPEATABLE-READ'})])
        if 'information_schema.TABLES' in sql:
            return lua.table_from([lua.table_from({'TABLE_NAME': table, 'ENGINE': 'InnoDB'}) for table in created])
        sql = sql.replace(' FOR UPDATE', '')
        cur = conn.execute(sql, values)
        if method == 'exec':
            return cur.rowcount
        data = cur.fetchall()
        if method == 'value':
            return data[0][0] if data else None
        records = [lua.table_from(dict(zip((d[0] for d in cur.description), row))) for row in data]
        return (records[0] if records else None) if method == 'one' else lua.table_from(records)
    m.env.proofExecute = execute
    m.env.proofBegin = lambda task: connection(task).execute('BEGIN') and None
    m.env.proofCommit = lambda task: connection(task).commit()
    m.env.proofRollback = lambda task: connection(task).rollback()
    lua.execute("""
        local e=...
        local queue,commands,logs={}, {}, {}; local clock=0
        e.proofCommands=commands; e.proofLogs=logs
        e.GetGameTimer=function() return clock end
        e.Wait=function() coroutine.yield() end
        e.CreateThread=function(fn) queue[#queue+1]=coroutine.create(fn) end
        e.RegisterCommand=function(name,fn) commands[name]=fn end
        e.print=function(msg) logs[#logs+1]=msg end
        local function task() return tostring(coroutine.running()) end
        local db={stmt=e.DB.stmt}
        for _,name in ipairs({'one','query','value','exec'}) do
            db[name]=function(sql,...) return e.proofExecute(task(),name,sql,table.pack(...)) end
        end
        db.batch=function(statements)
            local rows={}
            for i,statement in ipairs(statements) do
                local p=statement.params; local row=db.one(statement.sql,table.unpack(p,1,p.n or #p))
                rows[i]=row and {row} or {}
            end
            return rows
        end
        db.transaction=function(body)
            local id=task(); e.proofBegin(id)
            local ok,result=pcall(body,db)
            if ok and result==true then e.proofCommit(id) else e.proofRollback(id) end
            if not ok then error(result,0) end
            return result==true
        end
        e.DB=db
        e.proofDrain=function()
            for step=1,2000 do
                local active=false
                for _,thread in ipairs(queue) do
                    if coroutine.status(thread)~='dead' then
                        active=true; local ok,err=coroutine.resume(thread); assert(ok,err)
                    end
                end
                clock=clock+10
                if not active then return end
            end
            error('proof scheduler did not finish')
        end
        assert(loadfile('server/snapshot_proof.lua','t',e))()
    """, m.env)
    try:
        command = m.env.proofCommands.BccStablesSnapshotProof
        command(1, lua.table_from(['run']))
        assert len(m.env.proofLogs) == 0
        command(0, lua.table_from(['run']))
        m.env.proofDrain()
        last = m.env.proofLogs[len(m.env.proofLogs)]
        result = m.env.json.decode(last.split('] ', 1)[1])
        assert result.ok, result.message
        assert result.value.commitSnapshots and result.value.recoverySnapshot and result.value.rollbackSnapshot
        assert result.value.separateConnections and result.value.cleared
        assert len(connections) >= 2
        for conn in connections.values():
            for table in created:
                assert conn.execute('SELECT COUNT(*) FROM ' + table).fetchone()[0] == 0, table
            conn.close()
    finally:
        for conn in connections.values():
            conn.close()
print('SQLite WAL snapshot proof: commit/recovery/rollback isolation and cleanup passed; MariaDB acceptance pending.')
