"""SQL shape check using SQLite; not MariaDB/MySQL isolation acceptance."""
import sqlite3
from lupa.lua54 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
m = lua.execute("return assert(loadfile('tests/fixtures/snapshot_services.lua'))()()")
sql, specs = m.q.QuerySpec()
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

def check():
    packed = m.pack()[1]
    db = sqlite3.connect(':memory:')
    created, inserted = set(), set()
    for name, fields in specs:
        table = names[name]
        if table not in created:
            db.execute('CREATE TABLE ' + table + ' (' + ','.join('`' + f + '`' for f in fields) + ')')
            created.add(table)
        values = tuple(packed[name + '__' + field] for field in fields)
        if values[0] is None or (table, values) in inserted:
            continue
        inserted.add((table, values))
        db.execute('INSERT INTO ' + table + ' VALUES (' + ','.join('?' for _ in fields) + ')', values)
    cursor = db.execute(sql, (m.t.operationId, m.t.characterId))
    records = [dict(zip((d[0] for d in cursor.description), row)) for row in cursor.fetchall()]
    assert len(records) == 1
    rows = lua.table_from([lua.table_from(r) for r in records])
    decoded = m.q.Decode(m.t.operationId, m.t.characterId, rows)
    reference = m.reference()
    assert decoded.ok == reference.ok, (decoded.code, reference.code)
    if decoded.ok:
        assert decoded.value.horse.availability == reference.value.horse.availability
        assert decoded.value.horse.projectionRevision == reference.value.horse.projectionRevision
    else:
        assert decoded.code == reference.code
    db.close()

check()
m.prepare(); check()
assert m.bind().ok; check()
assert m.store().ok; check()
m.prepare(); check()
assert m.bind().ok; check()
print('SQLite snapshot SQL shape: 6 lifecycle cases; real database EXPLAIN/isolation still pending.')
