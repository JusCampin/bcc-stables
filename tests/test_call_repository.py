"""Exercise lifecycle transactions with real SQL on an isolated SQLite database.

SQLite checks atomic writes/constraints; it does not certify MariaDB row locking
or the native observer. No connection to the game server is made.
"""
import sqlite3
import unittest

from test_feather_boundary import FIXTURE, ROOT
from lupa.lua54 import LuaRuntime

CHAR = 'e5e9955d-c29e-11f1-9ae2-e0d55eaa2deb'
HORSE = 'cd6d38f3-ce7f-11f1-9ad4-e0d55eaa2deb'
ASSET = '3ed76477-ce80-11f1-9ad4-e0d55eaa2deb'
GEN = '2448f362-cf06-11f1-9ad4-e0d55eaa2deb'
EPOCH = '003d020d-cfeb-11f1-9ad4-e0d55eaa2deb'

SCHEMA = '''
CREATE TABLE fs_character_stables(character_id TEXT PRIMARY KEY, selected_horse_id TEXT, revision INTEGER);
CREATE TABLE fs_operations(operation_id TEXT PRIMARY KEY, character_id TEXT, horse_id TEXT, state TEXT);
CREATE TABLE fs_horses(horse_id TEXT PRIMARY KEY, owner_character_id TEXT, origin_operation_id TEXT,
 biological_state TEXT, availability TEXT, revision INTEGER);
CREATE TABLE fs_asset_registrations(operation_id TEXT PRIMARY KEY, character_id TEXT, horse_id TEXT,
 asset_id TEXT, model_key TEXT, state TEXT);
CREATE TABLE fs_call_leases(generation_id TEXT PRIMARY KEY, character_id TEXT, horse_id TEXT,
 operation_id TEXT, asset_id TEXT, model_key TEXT, session_id TEXT, source_id INTEGER,
 selection_revision INTEGER, state TEXT, revision INTEGER);
CREATE TABLE fs_call_slots(character_id TEXT PRIMARY KEY, horse_id TEXT UNIQUE, generation_id TEXT UNIQUE
 REFERENCES fs_call_leases(generation_id));
CREATE TABLE fs_call_process_epochs(generation_id TEXT PRIMARY KEY REFERENCES fs_call_leases(generation_id),process_epoch TEXT);
CREATE TABLE fs_call_recoveries(generation_id TEXT PRIMARY KEY REFERENCES fs_call_leases(generation_id),
 original_epoch TEXT, resolved_epoch TEXT, prior_revision INTEGER, prior_reason TEXT,
 CHECK(original_epoch<>resolved_epoch));
CREATE TABLE fs_call_bindings(generation_id TEXT PRIMARY KEY REFERENCES fs_call_leases(generation_id),
 observer_id TEXT, network_id INTEGER, initial_owner INTEGER, routing_bucket INTEGER,
 state TEXT DEFAULT 'bound', revision INTEGER DEFAULT 0, reason TEXT);
CREATE TABLE fs_horse_runtime_events(event_id TEXT PRIMARY KEY, horse_id TEXT,
 generation_id TEXT REFERENCES fs_call_leases(generation_id), from_availability TEXT,
 to_availability TEXT, prior_revision INTEGER, revision INTEGER, reason TEXT,
 UNIQUE(horse_id, revision), UNIQUE(generation_id,to_availability), CHECK(revision=prior_revision+1));
CREATE TABLE fs_care_operations(operation_id TEXT PRIMARY KEY, character_id TEXT, state TEXT);
CREATE TABLE fs_care_targets(operation_id TEXT PRIMARY KEY, generation_id TEXT, interrupted INTEGER DEFAULT 0,
 interrupt_reason TEXT, revision INTEGER DEFAULT 0);
CREATE TABLE fs_care_dispatches(operation_id TEXT PRIMARY KEY, state TEXT);
CREATE TABLE fs_horse_condition(horse_id TEXT PRIMARY KEY,health_core INTEGER,stamina_core INTEGER,
 policy_revision INTEGER,revision INTEGER);
'''


class CallRepositoryTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FIXTURE)
        self.lua.execute('GetConvar=function() return "' + EPOCH + '" end')
        self.db = sqlite3.connect(':memory:')
        self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA foreign_keys=ON')
        self.db.executescript(SCHEMA)
        self.db.execute('INSERT INTO fs_character_stables VALUES (?,?,19)', (CHAR, HORSE))
        self.db.execute("INSERT INTO fs_operations VALUES (?,?,?,'fulfilled')", (HORSE, CHAR, HORSE))
        self.db.execute("INSERT INTO fs_horses VALUES (?,?,?,'alive','stored',146)", (HORSE, CHAR, HORSE))
        self.db.execute("INSERT INTO fs_asset_registrations VALUES (?,?,?,?,?,'linked')",
                        (HORSE, CHAR, HORSE, ASSET, 'a_c_horse_morgan_bay'))
        self.db.commit()
        self.write_count = 0
        self.fail_at = None
        self.lose_commit_reply = False
        self.stale_on_write = False
        self.lua.globals().DB = self.lua.table_from({'one': self.one, 'exec': self.write,
            'batch': self.batch, 'transaction': self.transaction})
        self.lua.execute('DB.stmt=function(sql, ...) return {sql=sql,params=table.pack(...)} end')
        for path in ('server/core/feather.lua', 'server/horse/call_repository.lua'):
            self.lua.execute((ROOT / path).read_text(encoding='utf-8-sig'))
        self.lua.execute('''
            horse = {selected=true,horseId=row.horse_id,assetId=row.asset_id,operationId=row.origin_operation_id,
                modelKey=row.model_key,selectionRevision=19,projectionRevision=146}
            observation = {generationId="''' + GEN + '''",observerId=row.asset_id,netId=55,
                initialOwner=3,bucket=0,modelKey=row.model_key,disappeared=true}
        ''')
        self.repo = self.lua.globals().Stables.CallRepository

    def tearDown(self):
        self.db.close()

    def one(self, sql, *params):
        row = self.db.execute(sql.replace(' FOR UPDATE', ''), params).fetchone()
        return self.lua.table_from(dict(row)) if row else None

    def write(self, sql, *params):
        self.write_count += 1
        if self.fail_at == self.write_count:
            raise RuntimeError('injected write failure')
        affected = self.db.execute(sql, params).rowcount
        if self.stale_on_write:
            self.lua.globals().current = False
        return affected

    def batch(self, statements):
        results = []
        for index in range(1, len(statements)+1):
            statement = statements[index]
            sql, params = statement['sql'], statement['params']
            args = [params[i] for i in range(1, params['n']+1)]
            if sql.startswith('SELECT'):
                row = self.one(sql, *args)
                results.append(self.lua.table_from([row] if row else []))
            else:
                results.append(self.lua.table_from({'affectedRows': self.write(sql, *args)}))
        return self.lua.table_from(results)

    def transaction(self, body):
        self.db.execute('BEGIN')
        try:
            commit = body(self.lua.globals().DB)
            if commit is True:
                self.db.commit()
                if self.lose_commit_reply:
                    raise RuntimeError('injected lost commit reply')
            else:
                self.db.rollback()
            return commit
        except BaseException:
            self.db.rollback()
            raise

    def reserve(self):
        return self.repo.Reserve(self.lua.globals().session, self.lua.globals().horse, GEN, EPOCH)

    def test_transferred_horse_calls_with_original_purchase_provenance(self):
        buyer='77777777-7777-4777-8777-777777777777'
        self.db.execute('UPDATE fs_character_stables SET character_id=?',(buyer,))
        self.db.execute('UPDATE fs_horses SET owner_character_id=?',(buyer,));self.db.commit()
        self.lua.globals().session.characterId=buyer
        self.lua.execute("exports['feather-core'].IsSessionCurrent=function() return true end")
        self.assertTrue(self.reserve().ok)
        self.assertTrue(self.bind().ok)

    def bind(self):
        return self.repo.Bind(self.lua.globals().session, GEN, self.lua.globals().observation)

    def finish(self):
        return self.repo.FinishCleanup(CHAR, GEN, self.lua.globals().observation)

    def scalar(self, sql):
        return self.db.execute(sql).fetchone()[0]

    def test_complete_lifecycle_and_idempotent_cleanup(self):
        self.assertTrue(self.reserve()['ok'])
        self.assertEqual(self.scalar('SELECT state FROM fs_call_leases'), 'submitting')
        self.assertTrue(self.bind()['ok'])
        self.assertEqual(self.scalar('SELECT availability FROM fs_horses'), 'active')
        self.assertEqual(self.bind()['code'], 'binding_conflict')
        self.assertTrue(self.repo.BeginCleanup(CHAR, GEN)['ok'])
        self.assertTrue(self.repo.BeginCleanup(CHAR, GEN)['ok'])
        self.assertTrue(self.finish()['ok'])
        self.assertTrue(self.finish()['ok'])
        self.assertEqual(self.scalar('SELECT revision FROM fs_horses'), 148)
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM fs_horse_runtime_events'), 2)
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM fs_call_slots'), 0)

    def test_unreleased_call_fences_duplicate_spawn(self):
        self.assertTrue(self.reserve()['ok'])
        self.assertEqual(self.reserve()['code'], 'horse_busy')
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM fs_call_leases'), 1)

    def test_changed_selection_and_projection_refused(self):
        self.db.execute('UPDATE fs_character_stables SET revision=20')
        self.db.commit()
        self.assertEqual(self.reserve()['code'], 'selection_changed')
        self.db.execute('UPDATE fs_character_stables SET revision=19')
        self.db.execute('UPDATE fs_horses SET revision=147')
        self.db.commit()
        self.assertEqual(self.reserve()['code'], 'call_reconciliation_required')

    def test_pending_care_fences_call(self):
        self.db.execute("INSERT INTO fs_care_operations VALUES ('pending',?,'consumed')", (CHAR,))
        self.db.commit()
        self.assertEqual(self.reserve()['code'], 'horse_care_busy')

    def test_partial_reservation_rolls_back(self):
        self.fail_at = 3  # epoch receipt; lease and slot have already been written
        self.assertEqual(self.reserve()['code'], 'call_outcome_unknown')
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM fs_call_slots'), 0)
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM fs_call_leases'), 0)

    def test_lost_commit_reply_retains_fence(self):
        self.lose_commit_reply = True
        self.assertEqual(self.reserve()['code'], 'call_outcome_unknown')
        self.lose_commit_reply = False
        self.assertEqual(self.reserve()['code'], 'horse_busy')
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM fs_call_slots'), 1)

    def test_session_changed_mid_transaction_rolls_back(self):
        self.stale_on_write = True
        self.assertEqual(self.reserve()['code'], 'session_stale')
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM fs_call_slots'), 0)

    def test_wrong_observer_cannot_release(self):
        self.reserve()
        self.bind()
        self.repo.BeginCleanup(CHAR, GEN)
        self.lua.execute('observation.observerId=row.horse_id')
        self.assertEqual(self.finish()['code'], 'cleanup_unverified')
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM fs_call_slots'), 1)
        self.assertEqual(self.scalar('SELECT availability FROM fs_horses'), 'active')

    def test_release_requires_saved_cleanup_intent(self):
        self.reserve()
        self.bind()
        self.assertEqual(self.finish()['code'], 'cleanup_not_pending')

    def test_cleanup_interrupts_care_without_erasing_receipt(self):
        self.reserve()
        self.bind()
        self.db.execute("INSERT INTO fs_care_operations VALUES ('pending',?,'consumed')", (CHAR,))
        self.db.execute("INSERT INTO fs_care_targets(operation_id,generation_id) VALUES ('pending',?)", (GEN,))
        self.db.commit()
        self.assertTrue(self.repo.BeginCleanup(CHAR, GEN)['ok'])
        self.assertTrue(self.finish()['ok'])
        self.assertEqual(self.scalar('SELECT interrupted FROM fs_care_targets'), 1)
        self.assertEqual(self.scalar('SELECT state FROM fs_care_operations'), 'consumed')
        self.assertEqual(self.reserve()['code'], 'horse_care_busy')

    def test_binding_failure_rolls_back_projection_and_event(self):
        self.reserve()
        self.fail_at = self.write_count + 3  # after runtime event + projection update
        self.assertEqual(self.bind()['code'], 'call_outcome_unknown')
        self.assertEqual(self.scalar('SELECT availability FROM fs_horses'), 'stored')
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM fs_horse_runtime_events'), 0)
        self.assertEqual(self.scalar('SELECT state FROM fs_call_leases'), 'submitting')

    def test_replayed_old_cleanup_does_not_clear_replacement_slot(self):
        self.reserve()
        self.bind()
        self.repo.BeginCleanup(CHAR, GEN)
        self.finish()
        self.lua.execute('horse.projectionRevision=148')
        replacement = '641d1d56-d0cf-11f1-9ad4-e0d55eaa2deb'
        self.assertTrue(self.repo.Reserve(self.lua.globals().session, self.lua.globals().horse,
                                         replacement, EPOCH)['ok'])
        self.assertTrue(self.finish()['ok'])
        self.assertEqual(self.scalar('SELECT generation_id FROM fs_call_slots'), replacement)

    def test_orphan_unreleased_lease_blocks_new_call(self):
        self.reserve()
        self.db.execute('DELETE FROM fs_call_slots')
        self.db.commit()
        self.assertEqual(self.reserve()['code'], 'horse_busy')

    def test_lost_process_evidence_refuses_binding(self):
        self.reserve()
        self.db.execute('DELETE FROM fs_call_process_epochs')
        self.db.commit()
        self.assertEqual(self.bind()['code'], 'call_reconciliation_required')

    def test_claimed_care_projection_blocks_binding(self):
        self.reserve()
        self.db.execute("INSERT INTO fs_care_targets(operation_id,generation_id) VALUES ('delivery',?)", (GEN,))
        self.db.execute("INSERT INTO fs_care_dispatches VALUES ('delivery','claimed')")
        self.db.commit()
        self.assertEqual(self.bind()['code'], 'care_projection_busy')
        self.assertEqual(self.scalar('SELECT availability FROM fs_horses'), 'stored')

    def test_same_process_recovery_refused(self):
        self.reserve()
        self.bind()
        self.assertTrue(self.repo.Reconcile(CHAR, GEN, 'restart_lost_observation')['ok'])
        self.assertEqual(self.repo.RecoverProcessEnded(CHAR, GEN, EPOCH)['code'], 'process_still_current')
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM fs_call_slots'), 1)

    def test_new_process_recovers_once_without_entity_mutation(self):
        self.reserve()
        self.bind()
        self.repo.Reconcile(CHAR, GEN, 'restart_lost_observation')
        new_epoch = '641d1d56-d0cf-11f1-9ad4-e0d55eaa2deb'
        self.lua.execute('GetConvar=function() return "' + new_epoch + '" end')
        self.assertTrue(self.repo.RecoverProcessEnded(CHAR, GEN, new_epoch)['ok'])
        self.assertTrue(self.repo.RecoverProcessEnded(CHAR, GEN, new_epoch)['ok'])
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM fs_call_recoveries'), 1)
        self.assertEqual(self.scalar('SELECT revision FROM fs_horses'), 148)
        self.assertEqual(self.scalar('SELECT state FROM fs_call_bindings'), 'cleared')

    def test_new_process_can_recover_unbound_submission(self):
        self.reserve()
        self.repo.Reconcile(CHAR, GEN, 'submission_unknown')
        new_epoch = '641d1d56-d0cf-11f1-9ad4-e0d55eaa2deb'
        self.lua.execute('GetConvar=function() return "' + new_epoch + '" end')
        self.assertTrue(self.repo.RecoverProcessEnded(CHAR, GEN, new_epoch)['ok'])
        self.assertEqual(self.scalar('SELECT revision FROM fs_horses'), 146)
        self.assertEqual(self.scalar('SELECT COUNT(*) FROM fs_call_bindings'), 0)

    def test_cleanup_can_bind_observed_candidate_after_session_exit(self):
        self.reserve()
        self.lua.execute('current=false')
        self.assertTrue(self.repo.Bind(self.lua.globals().session,GEN,self.lua.globals().observation,True)['ok'])
        self.assertTrue(self.repo.BeginCleanup(CHAR,GEN)['ok'])
        self.assertTrue(self.finish()['ok'])


if __name__ == '__main__':
    unittest.main()
