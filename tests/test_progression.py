"""Permanent rewards use the existing XP transactions and retain depleted cores."""
import unittest
import json
import test_bonding as bonding
import test_bonding_client as native
import test_call_repository as calls
from test_feather_boundary import ROOT


class ProgressionTest(unittest.TestCase):
    def setUp(self):
        self.h=bonding.BondingTest();self.h.setUp();self.lua,self.db=self.h.lua,self.h.db
        self.lua.execute('''Config.bonding.statRewardsEnabled=true;Config.bonding.xpPerLevel=1000;Config.bonding.maxStatBonus=2
            Horses.BreedCatalog.Morgan.colors.a_c_horse_morgan_bay.stats={health=1,stamina=2,handling=2,acceleration=1,speed=2}''')
        self.assertTrue(self.h.g.Start().ok)
    def tearDown(self): self.h.tearDown()
    def initialize(self,xp=0):
        self.db.execute('INSERT OR IGNORE INTO fs_horse_bonding(horse_id,xp) VALUES(?,?)',(self.h.horse,xp));self.db.commit()
        result=[]
        self.h.h.transaction(lambda tx: result.append(self.h.g.EnsureStats(tx,self.h.horse,'a_c_horse_morgan_bay')) or result[-1].ok)
        self.assertTrue(result[0].ok,result[0].code)
        return result[0].value
    def test_order_cap_and_old_xp_backfill_once(self):
        value=self.initialize(3000)
        self.assertEqual(dict(value.training.ranks),dict(health=2,stamina=3,handling=3,acceleration=1,speed=2))
        self.assertEqual(value.levelsGained,3)
        again=self.initialize();self.assertEqual(again.revision,value.revision)
        self.assertEqual(again.levelsGained,0)
        self.assertFalse(self.h.g.NeedsStats(again))
    def test_pinned_catalog_and_config_survive_reload(self):
        self.initialize(1000)
        self.lua.execute('''Config.bonding.xpPerLevel=1;Config.bonding.maxStatBonus=9
            Horses.BreedCatalog.Morgan.colors.a_c_horse_morgan_bay.stats.health=8''')
        self.h.load()
        value=self.initialize()
        self.assertEqual(value.training.base.health,1)
        self.assertEqual(value.training.xpPerLevel,1000);self.assertEqual(value.training.maxBonus,2)
        owned=self.lua.globals().Stables.OwnedRepository.ReadSelected(self.lua.globals().session)
        self.assertTrue(owned.ok,owned.code);self.assertEqual(owned.value.bonding.training.ranks.health,2)
    def test_native_caps_skip_full_stats_and_large_xp_is_bounded(self):
        self.lua.execute('Horses.BreedCatalog.Morgan.colors.a_c_horse_morgan_bay.stats.health=9')
        value=self.initialize(1000);self.assertEqual(value.training.ranks.health,9);self.assertEqual(value.training.ranks.stamina,3)
        self.db.execute('UPDATE fs_horse_bonding SET xp=1000000000');self.db.commit()
        value=self.initialize();self.assertEqual(value.training.level,8)
        self.assertEqual(dict(value.training.ranks),dict(health=9,stamina=4,handling=4,acceleration=3,speed=4))
        self.assertFalse(self.h.g.NeedsStats(value))
    def test_travel_level_and_lost_commit_replay_are_one_update(self):
        self.initialize(990)
        self.h.ride(32);self.h.h.lost_commit=True;self.h.tick()
        value=self.h.g.Read(self.h.horse).value
        self.assertEqual(value.xp,1000);self.assertEqual(value.training.ranks.health,2)
        revision=value.revision
        self.h.ride(4)
        self.assertEqual(self.h.g.Read(self.h.horse).value.revision,revision)
    def test_care_xp_and_stat_change_roll_back_together(self):
        self.initialize(995)
        q=self.h.h.table(dict(horseId=self.h.horse,characterId=self.lua.globals().session.characterId,
            action='feed',bondingReward=5,bondingAt=1000,bondingCooldown=60))
        self.h.h.transaction(lambda tx: (self.h.g.Care(tx,q),False)[1])
        self.assertEqual(self.h.g.Read(self.h.horse).value.xp,995)
        results=[]
        self.h.h.transaction(lambda tx: results.append(self.h.g.Care(tx,q)) or results[-1].ok)
        self.assertEqual(results[0].value.training.ranks.health,2)
        self.assertEqual(results[0].value.levelsGained,1)
        self.h.h.transaction(lambda tx: self.h.g.Care(tx,q).ok)
        self.assertEqual(self.h.g.Read(self.h.horse).value.xp,1000)
    def test_corrupt_training_is_refused_without_overwriting(self):
        self.initialize()
        self.db.execute("UPDATE fs_horse_bonding SET training_json='{}'");self.db.commit()
        self.assertFalse(self.h.g.Read(self.h.horse).ok)
        self.assertEqual(self.db.execute('SELECT training_json FROM fs_horse_bonding').fetchone()[0],'{}')


class ProgressionNativeTest(unittest.TestCase):
    def setUp(self):
        self.h=native.BondingClientTest();self.h.setUp();self.lua=self.h.lua
        self.lua.execute('''Config.bonding.statRewardsEnabled=true
            packet.bonding.training={ranks={health=2,stamina=2,handling=2,acceleration=1,speed=2}}
            cores={[0]=27,[1]=13};rankWrites=0;local invoke=Citizen.InvokeNative
            Citizen.InvokeNative=function(hash,...)
                local a={...}
                if hash==0x36731AC041289BB1 then return cores[a[2]] end
                if hash==0x5DA12E025D47D4E5 then rankWrites=rankWrites+1;cores[0]=100;cores[1]=100 end
                if hash==0xC6258F41D86676E0 then cores[a[2]]=a[3] end
                return invoke(hash,...)
            end''')
    def test_rank_change_restores_actual_depleted_cores_and_unchanged_packet_skips_rank_writes(self):
        self.lua.execute('assert(Stables.HorseBonding.Apply(r,packet.bonding));assert(Stables.HorseBonding.Apply(r,packet.bonding))')
        self.assertEqual(self.lua.globals().rankWrites,5)
        self.assertEqual(self.lua.globals().cores[0],27);self.assertEqual(self.lua.globals().cores[1],13)
        self.lua.execute('packet.bonding.training.ranks.stamina=3;assert(Stables.HorseBonding.Apply(r,packet.bonding))')
        self.assertEqual(self.lua.globals().rankWrites,10);self.assertEqual(self.lua.globals().cores[1],13)
    def test_invalid_rank_or_unknown_core_refuses_all_rank_writes(self):
        self.lua.execute('packet.bonding.training.ranks.speed=10;assert(not Stables.HorseBonding.Apply(r,packet.bonding))')
        self.lua.execute('packet.bonding.training.ranks.speed=2;cores[1]=nil;assert(not Stables.HorseBonding.Apply(r,packet.bonding))')
        self.assertEqual(self.lua.globals().rankWrites,0)


class ProgressionBindTest(unittest.TestCase):
    def setUp(self):
        self.h=calls.CallRepositoryTest();self.h.setUp()
        self.h.db.executescript(bonding.SCHEMA)
        self.h.lua.globals().DB.exec=lambda sql,*args:self.h.write(sql.replace('INSERT IGNORE','INSERT OR IGNORE'),*args)
        self.h.lua.globals().json=self.h.lua.table_from({'encode':lambda v:json.dumps(self.plain(v)),
            'decode':lambda s:self.h.lua.table_from(json.loads(s),recursive=True)})
        self.h.lua.execute('''Config={bonding={enabled=true,statRewardsEnabled=true,xpPerLevel=1000,maxStatBonus=2}}
            Horses={ModelToBreedMap={a_c_horse_morgan_bay={breed='Morgan'}},
                BreedCatalog={Morgan={colors={a_c_horse_morgan_bay={stats={health=1,stamina=2,handling=2,acceleration=1,speed=2}}}}}}''')
        self.h.lua.execute((ROOT/'server/horse/bonding.lua').read_text(encoding='utf-8'))
        self.assertTrue(self.h.reserve().ok)
    def tearDown(self): self.h.tearDown()
    def plain(self,value):
        return {k:self.plain(v) for k,v in value.items()} if hasattr(value,'items') else value
    def bind(self,cleanup=False):
        g=self.h.lua.globals()
        return self.h.repo.Bind(g.session,calls.GEN,g.observation,cleanup,True)
    def test_stat_initialization_commits_inside_bind_and_cleanup_skips_it(self):
        result=self.bind();self.assertTrue(result.ok,result.code)
        self.assertEqual(result.value.bonding.training.base.health,1)
        self.assertEqual(self.h.scalar('SELECT COUNT(*) FROM fs_horse_bonding'),1)
    def test_failed_binding_rolls_back_stat_initialization_with_projection(self):
        self.h.db.execute("CREATE TRIGGER refuse_binding BEFORE INSERT ON fs_call_bindings BEGIN SELECT RAISE(ABORT,'injected'); END;")
        self.h.db.commit()
        self.assertFalse(self.bind().ok)
        self.assertEqual(self.h.scalar('SELECT COUNT(*) FROM fs_horse_bonding'),0)
        self.assertEqual(self.h.scalar('SELECT availability FROM fs_horses'),'stored')
    def test_cleanup_binding_does_not_initialize_training(self):
        result=self.bind(True);self.assertTrue(result.ok,result.code)
        self.assertEqual(self.h.scalar('SELECT COUNT(*) FROM fs_horse_bonding'),0)
