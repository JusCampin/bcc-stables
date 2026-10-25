"""Execute real care repository/proof DML on SQLite, not MariaDB lock acceptance."""
import json
import re
import sqlite3
from pathlib import Path
from lupa.lua54 import LuaRuntime, lua_type

lua = LuaRuntime(unpack_returned_tuples=True)
db = sqlite3.connect(':memory:', isolation_level=None)
db.execute('PRAGMA foreign_keys=ON')
# Minimal compatible fixture schema; migration9 itself still needs MariaDB smoke.
schemas = {
    'fs_character_stables': 'character_id TEXT PRIMARY KEY,selected_horse_id TEXT,revision INTEGER NOT NULL DEFAULT 0',
    'fs_operations': '''operation_id TEXT PRIMARY KEY,kind TEXT DEFAULT 'horse_purchase',character_id TEXT,horse_id TEXT,
        quote_id TEXT,catalog_id TEXT,catalog_revision INTEGER,currency TEXT,amount INTEGER,wallet_account_id TEXT,
        sink_account_id TEXT,payment_key TEXT,fingerprint TEXT,state TEXT,revision INTEGER,record_json TEXT,
        payment_transaction_id TEXT,refund_transaction_id TEXT''',
    'fs_horses': '''horse_id TEXT PRIMARY KEY,owner_character_id TEXT,origin_operation_id TEXT REFERENCES fs_operations(operation_id),
        catalog_id TEXT,catalog_revision INTEGER,biological_state TEXT DEFAULT 'alive',availability TEXT DEFAULT 'stored',revision INTEGER DEFAULT 0''',
    'fs_horse_condition': '''horse_id TEXT PRIMARY KEY REFERENCES fs_horses(horse_id),health_core INTEGER CHECK(health_core BETWEEN 0 AND 100),
        stamina_core INTEGER CHECK(stamina_core BETWEEN 0 AND 100),policy_revision INTEGER,revision INTEGER''',
    'fs_care_operations': '''operation_id TEXT PRIMARY KEY,horse_id TEXT REFERENCES fs_horses(horse_id),character_id TEXT,
        fingerprint TEXT,record_json TEXT,state TEXT,revision INTEGER''',
    'fs_care_slots': '''horse_id TEXT PRIMARY KEY REFERENCES fs_horses(horse_id),operation_id TEXT UNIQUE REFERENCES fs_care_operations(operation_id)''',
    'fs_care_effects': '''operation_id TEXT PRIMARY KEY REFERENCES fs_care_operations(operation_id),horse_id TEXT REFERENCES fs_horses(horse_id),
        condition_revision INTEGER,UNIQUE(horse_id,condition_revision)''',
    'fs_call_slots': 'character_id TEXT,horse_id TEXT,generation_id TEXT',
    'fs_call_leases': 'horse_id TEXT,character_id TEXT,generation_id TEXT,state TEXT',
    'fs_horse_history': 'horse_id TEXT,operation_id TEXT',
    'fs_outbox': 'operation_id TEXT',
    'fs_asset_registrations': 'operation_id TEXT,horse_id TEXT',
}
for table, columns in schemas.items():
    db.execute(f'CREATE TABLE {table} ({columns})')

def plain(value):
    if lua_type(value) != 'table':
        return value
    keys = list(value.keys())
    if keys and set(keys) == set(range(1, len(keys) + 1)):
        return [plain(value[i]) for i in range(1, len(keys) + 1)]
    return {k: plain(v) for k, v in value.items()}

calls = 0
def query(sql, *params):
    global calls
    calls += 1
    sql = re.sub(r'\s+FOR UPDATE\b', '', sql)
    cursor = db.execute(sql, params)
    if cursor.description:
        names = [d[0] for d in cursor.description]
        return lua.table_from([lua.table_from(dict(zip(names, row))) for row in cursor.fetchall()])
    return cursor.rowcount

def one(sql, *params):
    rows = query(sql, *params)
    return rows[1] if len(rows) else None

def value(sql, *params):
    row = one(sql, *params)
    return next(iter(row.values())) if row is not None else None

transactions = {'committed': 0, 'rolled_back': 0}
tx = lua.table_from({'one': one, 'value': value, 'exec': query, 'query': query})
def transaction(body):
    db.execute('BEGIN')
    try:
        committed = body(tx) is True
        db.execute('COMMIT' if committed else 'ROLLBACK')
        transactions['committed' if committed else 'rolled_back'] += 1
        return committed
    except Exception:
        db.execute('ROLLBACK')
        transactions['rolled_back'] += 1
        raise

lua.globals().DB = lua.table_from({'one': one, 'value': value, 'exec': query, 'query': query, 'transaction': transaction})
lua.globals().json = lua.table_from({'encode': lambda v: json.dumps(plain(v), sort_keys=True),
                                   'decode': lambda v: lua.table_from(json.loads(v), recursive=True)})
output = []
lua.globals().print = output.append
lua.globals().GetCurrentResourceName = lambda: 'bcc-stables'
lua.globals().LoadResourceFile = lambda resource, path: Path(path).read_text(encoding='utf-8')
lua.execute('commands={}; RegisterCommand=function(name,fn) commands[name]=fn end; CreateThread=function(fn) fn() end')
for file in ('shared/contracts.lua', 'server/operations.lua', 'server/care_operations.lua'):
    lua.execute(Path(file).read_text(encoding='utf-8'))
lua.execute("Stables.Foundation={RequireReady=function() return Stables.Ok(true) end}; Stables.Persistence={DatabaseError=function() return Stables.Err('database_error','unknown') end}")
for file in ('server/repository.lua', 'server/care_repository.lua', 'server/call_repository.lua', 'server/care_proof.lua'):
    lua.execute(Path(file).read_text(encoding='utf-8'))
assert lua.globals().Stables.CareRepository.Start().ok
command = lua.globals().commands.BccStablesCareProof
command(1, lua.table_from(['run']))
command(0, lua.table_from(['invalid']))
assert calls == 1, 'refused invocation must not touch fixture SQL'
command(0, lua.table_from(['run']))
result = json.loads(output[-1].split('] ', 1)[1])
assert result['ok'], result
assert all(result['value'].values()), result
assert transactions['rolled_back'] >= 2, transactions
for table in schemas:
    assert db.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0] == 0, table
# Occupied synthetic namespace must remain untouched on another run.
character = 'bccd0001-0000-4000-8000-000000000001'
db.execute('INSERT INTO fs_character_stables(character_id,revision) VALUES (?,7)', (character,))
command(0, lua.table_from(['run']))
result = json.loads(output[-1].split('] ', 1)[1])
assert not result['ok'] and 'namespace occupied' in result['message'], result
assert db.execute('SELECT revision FROM fs_character_stables').fetchone()[0] == 7
db.execute('DELETE FROM fs_character_stables')

# Execute the new two-resource bridge control flow against real SQL. Inventory
# item methods below are a SQL adapter; production Inventory guards have their
# own suite/live proof and are not claimed by this harness.
inventory = Path('../../feather-scripts/feather-inventory').resolve()
if inventory.is_dir():
    for table, columns in {
        'categories': 'id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT UNIQUE',
        'items': '''id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT UNIQUE,display_name TEXT,max_quantity INTEGER,
            max_stack_size INTEGER,weight INTEGER,usable INTEGER,category_id INTEGER REFERENCES categories(id),
            type TEXT,instance_mode TEXT,archived_at TEXT''',
        'inventory': '''id INTEGER PRIMARY KEY AUTOINCREMENT,uuid TEXT UNIQUE,name TEXT,max_weight INTEGER,max_slots INTEGER,character_id TEXT UNIQUE''',
        'inventory_items': '''id INTEGER PRIMARY KEY AUTOINCREMENT,inventory_id INTEGER REFERENCES inventory(id),
            item_id INTEGER REFERENCES items(id),metadata TEXT,row_revision INTEGER DEFAULT 0''',
    }.items():
        db.execute(f'CREATE TABLE {table} ({columns})')
    def inventory_raw(sql, params=None):
        sql = re.sub(r'\s+ENGINE=InnoDB.*$', '', sql, flags=re.S)
        sql = sql.replace('INSERT IGNORE', 'INSERT OR IGNORE')
        result = query(sql, *(list(params.values()) if params is not None else []))
        return lua.table_from({'affectedRows': result}) if isinstance(result, int) else result
    def inventory_db_query(sql, *params):
        if sql.startswith('SHOW FULL COLUMNS'):
            return lua.table_from([lua.table_from({'Field': k, 'Type': v, 'Null': 'YES' if k == 'result_json' else 'NO', 'Collation': 'utf8mb4_bin'})
                for k, v in {'source_resource': 'varchar(100)', 'operation_id': 'char(36)', 'request_fingerprint': 'varchar(700)', 'result_json': 'longtext', 'created_at': 'timestamp'}.items()])
        if 'information_schema.TABLES' in sql:
            return lua.table_from([lua.table_from({'ENGINE': 'InnoDB'})])
        if sql.startswith('SHOW INDEX'):
            return lua.table_from([lua.table_from({'Key_name': 'PRIMARY', 'Seq_in_index': i, 'Column_name': name})
                for i, name in enumerate(('source_resource', 'operation_id'), 1)])
        return query(sql, *params)
    inv = lua.eval('setmetatable({}, {__index=_G})')
    inv._G = inv
    inv.Config = lua.table_from({'DevMode': True, 'TrustedConsumptionCallers': lua.table_from({})})
    inv.InventoryReadiness = lua.table_from({'state': 'ready'})
    inv.DB = lua.table_from({'exec': lambda sql, *p: query(re.sub(r'\s+ENGINE=InnoDB.*$', '', sql, flags=re.S), *p),
                             'one': one, 'query': inventory_db_query})
    inv.GetCurrentResourceName = lambda: 'feather-inventory'
    inv.LoadResourceFile = lambda resource, path: (inventory / path).read_text(encoding='utf-8')
    for file in ('server/helpers/result.lua', 'server/helpers/character_identity.lua'):
        lua.eval('function(source,env) assert(load(source,"@inventory-test","t",env))() end')((inventory / file).read_text(encoding='utf-8'), inv)
    inv._raw = inventory_raw
    inv._transaction = transaction
    lua.eval('''function(env) assert(load([[
        TransactionAPI={Transaction=function(context,body)
            local result
            local committed=_transaction(function()
                local tx={query=_raw}
                function tx:GetItemForUpdate(id)
                    local row=_raw('SELECT ii.id,ii.inventory_id,ii.row_revision,i.id AS definition_id,i.name,i.type,i.instance_mode FROM inventory_items ii JOIN items i ON i.id=ii.item_id WHERE ii.id=?',{id})[1]
                    if not row then return Result.Err('not_found','absent') end
                    return Result.Ok({id=row.id,inventoryId=row.inventory_id,revision=row.row_revision,
                        definition={id=row.definition_id,name=row.name,type=row.type,instanceMode=row.instance_mode}})
                end
                function tx:RemoveInstances(inv,definition,ids)
                    assert(#ids==1)
                    local changed=_raw('DELETE FROM inventory_items WHERE id=? AND inventory_id=? AND item_id=?',{ids[1],inv,definition})
                    assert(changed.affectedRows==1); return Result.Ok(ids)
                end
                function tx:AddQuantity(inv,definition,n,metadata)
                    assert(n==1)
                    local row=_raw('INSERT INTO inventory_items (inventory_id,item_id,metadata) VALUES (?,?,?) RETURNING id',{inv,definition,json.encode(metadata)})[1]
                    return Result.Ok({row.id})
                end
                result=body(tx); return result.ok==true
            end)
            return result or Result.Err('internal','no result')
        end}
    ]],"@inventory-sql-adapter","t",env))() end''')(inv)
    for file in ('server/services/consumption_once.lua', 'server/services/stables_care_proof.lua'):
        lua.eval('function(source,env) assert(load(source,"@inventory-real-service","t",env))() end')((inventory / file).read_text(encoding='utf-8'), inv)
    inv.ConsumptionOnceAPI.Start()
    provider = lua.table_from({})
    def inspect(_self, request):
        handled = inv.StablesCareConsumptionProof.TryInspect(request, 'bcc-stables')
        if isinstance(handled, tuple) and handled[0]:
            return handled[1]
        return inv.ConsumptionOnceAPI.Inspect(request, 'bcc-stables')
    provider.GetConsumptionContract = lambda _self: inv.ConsumptionOnceAPI.Contract()
    provider.StablesCareProofFixture = lambda _self, action: inv.StablesCareConsumptionProof.Step(action, 'bcc-stables')
    provider.InspectCharacterConsumption = inspect
    lua.globals().exports = lua.table_from({'feather-inventory': provider})
    lua.globals().GetResourceState = lambda resource: 'started'
    for file in ('server/care_inventory.lua', 'server/care_bridge_proof.lua'):
        lua.execute(Path(file).read_text(encoding='utf-8'))
    bridge = lua.globals().commands.BccStablesCareBridgeProof
    bridge(0, lua.table_from(['run']))
    result = json.loads(output[-1].split('] ', 1)[1])
    assert result['ok'], result
    assert all(result['value'].values()), result
    for table in (*schemas, 'inventory_items', 'inventory', 'items', 'categories', 'inventory_consumption_receipts'):
        assert db.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0] == 0, table
    assert db.execute('SELECT phase FROM inventory_stables_care_proof').fetchone()[0] == 'cleared'
    assert not list(inv.Config.TrustedConsumptionCallers.keys())
    print('SQLite care bridge: real receipt service + care adapter/repository/proof flow passed; Inventory item-method SQL adapter, actual CFX/MariaDB acceptance pending.')
else:
    print('SKIP care bridge SQL fixture: sibling feather-inventory checkout unavailable.')
db.close()
print('SQLite care proof DML: real repository atomic effect/rollback/lost-reply/replay/cancellation/pending fence/cleanup passed; MariaDB acceptance pending.')
