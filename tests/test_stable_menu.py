"""Menu authority/routing tests with isolated SQL; no live game/providers."""
import unittest

import test_call_repository as call_tests
from test_call_repository import CHAR, HORSE, GEN
from test_feather_boundary import ROOT


class StableMenuTest(unittest.TestCase):
    def setUp(self):
        self.h = call_tests.CallRepositoryTest('test_complete_lifecycle_and_idempotent_cleanup')
        self.h.setUp()
        self.lua = self.h.lua
        self.h.db.create_function('UUID', 0, lambda: GEN)
        self.h.db.commit()
        def query(sql, *params):
            return self.lua.table_from([
                self.lua.table_from(dict(row)) for row in self.h.db.execute(sql, params).fetchall()
            ])
        self.lua.globals().DB.query = query
        self.lua.execute('''
            now=0; bucket=0; routeId=nil; joined=0; deleted=0; occupied=false; closedEvents=0
            GetGameTimer=function() return now end
            Wait=function(ms) now=now+ms end
            GetPlayerPed=function() return 1 end
            DoesEntityExist=function() return true end
            GetEntityCoords=function() return {x=0,y=0,z=0} end
            GetPlayerRoutingBucket=function() return bucket end
            GetCurrentResourceName=function() return 'bcc-stables' end
            TriggerClientEvent=function() closedEvents=closedEvents+1 end
            StableLocations={valentine={npc={coords={x=0,y=0,z=0}},shop={jobsEnabled=false,hours={active=false}}}}
            Stables.HorseController={HasPhysicalCall=function() return false end,
                Store=function() return {ok=false,code='horse_occupied',message='Occupied'} end}
            Stables.OwnedRepository={ReadOwned=function(session,id)
                if not current then return {ok=false,code='session_stale',message='Changed'} end
                if id~=horse.horseId or foreign then return {ok=false,code='horse_not_owned',message='Not owned'} end
                return {ok=true,value={horseId=id,modelKey='a_c_horse_morgan_bay',selectionRevision=19}}
            end,NormalizeName=function(value) return value end}
            exports['feather-assets'].ListAssetsByHolder=function(_,request)
                assert(request.holderId==session.characterId and request.limit==10 and request.includeMetadata)
                return {ok=true,value={items={asset}}}
            end
            exports['feather-routing']={
                CreateRoute=function(_,spec) routeId='route'; return {ok=true,value={routeId=routeId}} end,
                JoinRoute=function() bucket=123;joined=joined+1;return {ok=true,value={}} end,
                GetPlayerRoute=function() return {ok=true,value={routeId=routeId}} end,
                DeleteRoute=function() bucket=0;routeId=nil;deleted=deleted+1;return {ok=true,value={}} end
            }
        ''')
        self.lua.execute((ROOT/'server/ui/stable.lua').read_text())
        self.menu = self.lua.globals().Stables.StableMenu

    def tearDown(self):
        self.h.tearDown()

    def payload(self, **extra):
        return self.lua.table_from({'token': GEN, **extra})

    def open(self):
        return self.menu.Open(3, self.lua.table_from({'site': 'valentine'}))

    def test_roster_uuid_and_close_restore_route(self):
        result = self.open()
        self.assertTrue(result['ok'])
        row = result['value']['entries'][1]
        self.assertEqual(row['horseId'], HORSE)
        self.assertTrue(row['selected'])
        self.assertEqual(self.lua.globals().bucket, 123)
        self.assertTrue(self.menu.Request(3, self.payload(), 'close')['ok'])
        self.assertEqual(self.lua.globals().bucket, 0)
        self.assertFalse(self.menu.IsOpen(3))

    def test_roster_uses_fresh_canonical_names_without_local_name_writes(self):
        self.lua.execute("asset.metadata.name='Willow'")
        self.assertEqual(self.open()['value']['entries'][1]['name'],'Willow')
        self.lua.execute("asset.metadata.name='Étoile'")
        refreshed=self.menu.Request(3,self.payload(),'roster')
        self.assertEqual(refreshed['value']['entries'][1]['name'],'Étoile')
        self.assertEqual(self.h.write_count,0)

    def test_asset_list_failure_does_not_become_empty_roster(self):
        self.lua.execute("exports['feather-assets'].ListAssetsByHolder=function() return {ok=false,code='policy_unavailable',message='Unavailable'} end")
        self.assertEqual(self.open()['code'],'policy_unavailable')
        self.assertFalse(self.menu.IsOpen(3))
        self.assertEqual(self.lua.globals().bucket,0)

    def test_occupied_horse_prevents_preview_route(self):
        self.h.reserve()
        result = self.open()
        self.assertEqual(result['code'], 'horse_occupied')
        self.assertEqual(self.lua.globals().joined, 0)
        self.assertFalse(self.menu.IsOpen(3))

    def test_preview_rechecks_ownership_and_session(self):
        self.open()
        self.lua.globals().foreign = True
        result = self.menu.Request(3, self.payload(horseId=HORSE), 'preview')
        self.assertEqual(result['code'], 'horse_not_owned')
        self.lua.globals().current = False
        self.menu.Tick()
        self.assertEqual(self.lua.globals().bucket, 0)

    def test_changed_selection_revision_does_not_write(self):
        self.open()
        result = self.menu.Request(3, self.payload(horseId=HORSE, revision=18), 'select')
        self.assertEqual(result['code'], 'selection_conflict')
        self.assertEqual(self.h.db.execute('SELECT revision FROM fs_character_stables').fetchone()[0], 19)

    def test_selection_change_persists_once(self):
        self.h.db.execute('UPDATE fs_character_stables SET selected_horse_id=NULL')
        self.h.db.commit()
        self.open()
        result = self.menu.Request(3, self.payload(horseId=HORSE, revision=19), 'select')
        self.assertTrue(result['ok'])
        self.assertEqual(tuple(self.h.db.execute('SELECT selected_horse_id,revision FROM fs_character_stables').fetchone()), (HORSE, 20))
        self.assertEqual(self.menu.Request(3, self.payload(horseId=HORSE, revision=19), 'select')['code'], 'selection_conflict')

    def test_care_blocks_selection_without_changing_preference(self):
        self.open()
        self.h.db.execute("INSERT INTO fs_care_operations VALUES (?,?,'consumed')", (GEN, CHAR))
        self.h.db.commit()
        result = self.menu.Request(3, self.payload(horseId=HORSE, revision=19), 'select')
        self.assertEqual(result['code'], 'selection_conflict')
        self.assertEqual(self.h.db.execute('SELECT revision FROM fs_character_stables').fetchone()[0], 19)

    def test_lost_selection_commit_reply_requires_refresh(self):
        self.open()
        self.h.lose_commit_reply = True
        result = self.menu.Request(3, self.payload(horseId=HORSE, revision=19), 'select')
        self.assertEqual(result['code'], 'menu_outcome_unknown')
        self.assertTrue(self.menu.Request(3, self.payload(), 'roster')['ok'])

    def test_expired_or_wrong_token_cannot_mutate(self):
        self.open()
        self.assertEqual(self.menu.Request(3, self.lua.table_from({'token': HORSE}), 'close')['code'], 'session_stale')
        self.lua.globals().now = 21000
        self.menu.Tick()
        self.assertFalse(self.menu.IsOpen(3))
        self.assertEqual(self.lua.globals().bucket, 0)


if __name__ == '__main__':
    unittest.main()
