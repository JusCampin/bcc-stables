"""Server-timed world care, real condition/XP SQL and simulator ticket fences."""
import unittest
import test_feeding as feeding
import test_bonding as bonding
from test_feather_boundary import ROOT


class WorldCareTest(unittest.TestCase):
    def setUp(self):
        self.h=feeding.FeedingTest();self.h.setUp();self.lua=self.h.lua;self.db=self.h.f.db
        self.db.executescript(bonding.SCHEMA)
        self.db.execute('ALTER TABLE fs_horse_bonding ADD COLUMN last_drink_at INTEGER DEFAULT 0')
        self.db.execute('INSERT INTO fs_horse_bonding(horse_id,xp) VALUES(?,3000)',(self.h.horse,));self.db.commit()
        self.lua.execute(bonding.CONFIG+'''
            Config.worldCare={enabled=true,drinkXp=5,actions={
                drink={minimumXp=50,health=20,stamina=20,seconds=15},
                rest={minimumXp=350,health=5,stamina=5,seconds=5},
                sleep={minimumXp=1150,health=10,stamina=10,seconds=5},
                wallow={minimumXp=2450,health=0,stamina=0,seconds=8}}}
            routes={};GetPlayerRoutingBucket=function() return 0 end
            NetworkGetNetworkIdFromEntity=function(e) return e end
            exports['feather-core'].RegisterRpc=function(_,name,fn,spec) routes[name]={fn=fn,spec=spec};return {ok=true} end
        ''')
        for path in ('server/horse/bonding.lua','server/horse/passive_care.lua'):
            self.lua.execute((ROOT/path).read_text(encoding='utf-8'))
        self.w=self.lua.globals().Stables.WorldCare;self.g=self.lua.globals().Stables.Bonding
        self.assertTrue(self.g.Start().ok);self.assertTrue(self.w.Start().ok)
    def tearDown(self): self.h.tearDown()
    def start(self,action='rest'):
        r=self.lua.globals().r
        if r.worldExit:self.assertTrue(self.w.ExitResult(self.lua.globals().simulator or 3,self.h.f.table(dict(generationId=r.id,sequence=r.worldExit.sequence))).ok)
        result=self.w.Request(3,self.h.f.table(dict(action=action)));self.assertTrue(result.ok,result.code)
        return self.lua.globals().r.worldCare
    def sample(self,advance=2000,**overrides):
        g=self.lua.globals();g.clock+=advance;self.w.Tick(g.r)
        t=g.r.worldCare
        if not t or not t.sample:return None
        health,stamina,revision=self.db.execute('SELECT health_core,stamina_core,revision FROM fs_horse_condition').fetchone()
        p=dict(generationId=g.r.id,sequence=t.sample.sequence,eligible=True,playing=True,water=True,loop=True,
            healthCore=health,staminaCore=stamina,appliedRevision=revision)
        p.update(overrides);self.last=p
        return self.w.Result(g.simulator or 3,self.h.f.table(p))
    def condition(self):return tuple(self.db.execute('SELECT health_core,stamina_core FROM fs_horse_condition').fetchone())
    def test_rest_has_no_early_reward_and_commits_saved_cores_without_xp(self):
        self.start();self.sample();self.sample();self.sample()
        self.assertEqual(self.condition(),(70,60))
        self.assertTrue(self.sample().ok);self.assertEqual(self.condition(),(75,65))
        self.assertEqual(self.g.Read(self.h.horse).value.xp,3000)
        self.assertFalse(self.w.Result(3,self.h.f.table(self.last)).ok)
        self.assertEqual(self.condition(),(75,65))
    def test_drink_stops_after_one_reward_and_persists_xp_cooldown(self):
        self.start('drink')
        for _ in range(9):self.sample()
        self.assertEqual(self.condition(),(90,80));self.assertIsNone(self.lua.globals().r.worldCare)
        self.assertEqual(self.g.Read(self.h.horse).value.xp,3005)
        self.start('drink')
        for _ in range(9):self.sample()
        self.assertEqual(self.condition(),(100,100));self.assertEqual(self.g.Read(self.h.horse).value.xp,3005)
    def test_entry_time_does_not_count_and_stop_has_no_reward(self):
        self.start();self.sample(loop=False);self.sample(loop=False);self.sample(loop=False)
        self.sample();self.assertEqual(self.condition(),(70,60))
        self.w.Request(3,self.h.f.table(dict(action='stop')))
        self.assertIsNone(self.lua.globals().r.worldCare)
        self.assertEqual(self.condition(),(70,60))
    def test_low_bonding_no_condition_and_busy_horse_refuse(self):
        self.db.execute('UPDATE fs_horse_bonding SET xp=60');self.db.commit()
        self.assertEqual(self.w.Request(3,self.h.f.table(dict(action='sleep'))).code,'world_care_locked')
        self.lua.execute('r.care={}')
        self.assertFalse(self.w.Request(3,self.h.f.table(dict(action='drink'))).ok)
    def test_wrong_simulator_water_or_animation_cannot_award(self):
        self.start('drink');self.lua.globals().clock=2000;self.w.Tick(self.lua.globals().r)
        t=self.lua.globals().r.worldCare
        p=dict(generationId=self.lua.globals().r.id,sequence=t.sample.sequence,eligible=True,playing=True,water=True,loop=True,
            healthCore=70,staminaCore=60,appliedRevision=0)
        self.assertFalse(self.w.Result(9,self.h.f.table(p)).ok)
        p['water']=False;self.assertTrue(self.w.Result(3,self.h.f.table(p)).ok)
        self.assertIsNone(self.lua.globals().r.worldCare);self.assertEqual(self.condition(),(70,60))
        self.start();self.sample();self.sample(playing=False);self.assertIsNone(self.lua.globals().r.worldCare)
    def test_migration_distance_and_missing_observations_stop_without_benefit(self):
        for change in ('simulator=9','far=true','clock=11000'):
            self.lua.execute('simulator=nil;far=false;clock=0');self.start();self.lua.execute(change)
            self.w.Tick(self.lua.globals().r)
            self.assertIsNone(self.lua.globals().r.worldCare)
            self.assertEqual(self.condition(),(70,60))
    def test_unknown_commit_stops_and_fences_stale_native_depletion(self):
        self.start();self.sample();self.sample();self.sample()
        original=self.lua.globals().DB.transaction;count=[0]
        def lose_second_commit(fn):
            count[0]+=1
            if count[0]==2:self.h.f.lost_commit=True
            return original(fn)
        self.lua.globals().DB.transaction=lose_second_commit
        self.sample()
        self.assertIsNone(self.lua.globals().r.worldCare)
        self.assertEqual(self.condition(),(75,65))
        self.assertEqual(self.lua.globals().r.requiredConditionRevision,1)
    def test_world_benefit_and_drink_xp_roll_back_together(self):
        self.db.execute("CREATE TRIGGER fail_xp BEFORE UPDATE ON fs_horse_bonding BEGIN SELECT RAISE(ABORT,'injected'); END;");self.db.commit()
        self.start('drink')
        for _ in range(9):self.sample()
        self.assertEqual(self.condition(),(70,60));self.assertEqual(self.g.Read(self.h.horse).value.xp,3000)
    def test_rpc_rejects_client_reward_totals(self):
        spec=self.lua.globals().routes['stables.horses.call.world_care.v1'].spec
        self.assertTrue(spec.validatePayload(self.h.f.table(dict(action='rest'))))
        self.assertFalse(spec.validatePayload(self.h.f.table(dict(action='rest',xp=1000))))
    def test_full_rest_and_animation_only_wallow_do_not_keep_querying_sql(self):
        self.db.execute('UPDATE fs_horse_condition SET health_core=100,stamina_core=100');self.db.commit()
        self.start()
        for _ in range(4):self.sample()
        self.assertTrue(self.lua.globals().r.worldCare.full)
        original=self.lua.globals().DB.one
        def refuse_query(*args):raise AssertionError('No SQL while full')
        self.lua.globals().DB.one=refuse_query
        for _ in range(4):self.sample()
        self.assertIsNotNone(self.lua.globals().r.worldCare)
        self.lua.globals().DB.one=original
        self.w.Request(3,self.h.f.table(dict(action='stop')));self.start('wallow')
        self.lua.globals().DB.one=refuse_query
        for _ in range(6):self.sample()
        self.assertIsNone(self.lua.globals().r.worldCare)
    def test_startup_loading_and_long_entry_never_award_early(self):
        self.start()
        self.sample(playing=False,loop=False)
        self.assertIsNotNone(self.lua.globals().r.worldCare)
        for _ in range(6):self.sample(loop=False)
        self.assertEqual(self.condition(),(70,60))
        self.assertIsNotNone(self.lua.globals().r.worldCare)
        for _ in range(4):self.sample()
        self.assertEqual(self.condition(),(75,65))
    def test_entry_root_shift_becomes_loop_anchor_but_later_movement_cancels(self):
        self.lua.execute('horseX=0;GetEntityCoords=function(e) return {x=e==100 and horseX or 0,y=0,z=0} end')
        self.start();self.lua.globals().horseX=2;self.sample(loop=False);self.sample()
        self.assertIsNotNone(self.lua.globals().r.worldCare)
        self.lua.globals().horseX=0;self.sample()
        self.assertIsNone(self.lua.globals().r.worldCare);self.assertEqual(self.condition(),(70,60))
    def test_whistle_waits_for_current_simulator_exit_then_runs_normal_approach(self):
        self.lua.execute('Stables.HorseController.IsDistant=function() return false end;DoesEntityExist=function(e) return e==10 or e==100 end')
        self.lua.execute((ROOT/'server/horse/whistle.lua').read_text(encoding='utf-8'))
        self.start()
        result=self.lua.globals().Stables.Whistle.Request(3,self.h.f.table(dict(mode='approach')))
        self.assertTrue(result.ok);self.assertTrue(result.value.waking)
        r=self.lua.globals().r
        self.assertIsNone(r.movement);self.assertIsNotNone(r.worldExit)
        p=self.h.f.table(dict(generationId=r.id,sequence=r.worldExit.sequence))
        self.assertFalse(self.w.ExitResult(9,p).ok)
        self.assertTrue(self.w.ExitResult(3,p).ok)
        self.assertEqual(r.movement.mode,'approach')
        self.assertFalse(self.w.ExitResult(3,p).ok)
    def test_exit_timeout_cannot_authorize_automatic_mount(self):
        self.start();self.w.Stop(self.lua.globals().r)
        self.lua.globals().clock=31000;self.w.Tick(self.lua.globals().r)
        self.assertIsNone(self.lua.globals().r.worldExit)
        ended=[e for e in self.lua.globals().events.values() if e['name']=='bcc-stables:world:ended']
        self.assertTrue(ended);self.assertFalse(ended[-1].p.completed)
