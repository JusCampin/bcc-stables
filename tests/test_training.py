"""Production course/payment/XP SQL on SQLite; simulator/Economy are doubles."""
import unittest
import test_bonding as fixture
from test_feather_boundary import ROOT


class TrainingTest(unittest.TestCase):
    def setUp(self):
        self.f=fixture.BondingTest();self.f.setUp();self.lua=self.f.lua;self.db=self.f.db
        self.db.executescript('''CREATE TABLE fs_training_sessions(operation_id TEXT PRIMARY KEY,character_id TEXT,horse_id TEXT,
            state TEXT,training_day TEXT,earned_xp INTEGER DEFAULT 0,payment_transaction_id TEXT,record_json TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP);
            CREATE TABLE fs_care_slots(horse_id TEXT PRIMARY KEY,operation_id TEXT);''')
        self.lua.execute('''
            vector3=function(x,y,z) return {x=x,y=y,z=z} end
            vector4=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end
            Config.training={enabled=true,price=3500,currency='dollars',dailyHorseXpLimit=1000,
                courses={leading={laps=1,secondsPerLap=120,minimumSeconds=15,radius=2.5,xp=75},
                riding={laps=2,secondsPerLap=150,minimumSeconds=30,radius=3.5,xp=112}}}
            pos={x=-381.129,y=765.596,z=116.077};threads={}
            GetEntityCoords=function(e) return {x=pos.x+(e==10 and far and 20 or 0),y=pos.y,z=pos.z} end
            CreateThread=function(fn) threads[#threads+1]=fn end
            exports['feather-economy'].AwaitReady=function() return {ok=true,value=true} end
            exports['feather-economy'].GetCurrency=function() return {ok=true,value={precision=2}} end
            balance=100000;charges=0;paymentCalls=0;receipts={}
        ''')
        for file in ('config/training_locations.lua','shared/training.lua','server/horse/training.lua'):
            self.lua.execute((ROOT/file).read_text())
        self.t=self.lua.globals().Stables.Training
        original_sql=self.f.h.sql
        self.f.h.sql=lambda s: ("SELECT name AS TABLE_NAME FROM sqlite_master WHERE type='table' AND name='fs_training_sessions'"
            if 'information_schema.TABLES' in s else original_sql(s))
        self.assertTrue(self.t.Start().ok)
        self.lua.execute('CreateThread=function(fn) fn() end')

    def tearDown(self):self.f.tearDown()
    def request(self,mode='leading'):
        return self.t.Request(3,self.f.h.table({'site':'valentine','mode':mode}))
    def complete(self,mode='leading'):
        self.assertTrue(self.request(mode).ok)
        g=self.lua.globals();q=g.r.training;identity=q.id
        for i in range(1,len(q.points)+1):
            point=q.points[i];g.pos=point;g.clock+=3000
            self.t.Tick(g.r)
            ticket=q.sample;self.assertIsNotNone(ticket)
            result=self.t.Sample(g.owner,self.f.h.table({'id':q.id,'sequence':ticket.sequence,'mode':mode,'alive':True}))
            self.assertTrue(result.ok)
        return identity
    def row(self):return self.db.execute('SELECT * FROM fs_training_sessions').fetchone()

    def test_completed_leading_course_pays_and_awards_once(self):
        identity=self.complete();g=self.lua.globals()
        self.assertEqual(self.row()['state'],'completed');self.assertEqual(g.charges,1)
        self.assertEqual(g.balance,96500);self.assertEqual(self.f.xp(),75)
        self.assertTrue(self.t.Settle(identity).ok);self.assertEqual(g.charges,1);self.assertEqual(self.f.xp(),75)

    def test_cancellation_costs_nothing_and_releases_admission(self):
        self.assertTrue(self.request().ok);self.assertFalse(self.t.Clear(self.lua.globals().session.characterId))
        self.t.Cancel(self.lua.globals().r)
        self.assertEqual(self.row()['state'],'cancelled');self.assertEqual(self.lua.globals().charges,0)
        self.assertTrue(self.t.Clear(self.lua.globals().session.characterId));self.assertEqual(self.f.xp(),0)

    def test_lost_payment_reply_reuses_receipt_and_recovers_xp(self):
        self.lua.execute('losePayment=true')
        identity=self.complete();self.assertEqual(self.row()['state'],'payment_pending')
        self.assertEqual(self.f.xp(),0);self.assertEqual(self.lua.globals().charges,1)
        self.assertTrue(self.t.Settle(identity).ok);self.assertEqual(self.f.xp(),75)
        self.assertEqual(self.lua.globals().charges,1)

    def test_xp_failure_rolls_back_terminal_receipt_and_recovers_without_repayment(self):
        original=self.f.h.execute
        def fail(sql,*args):
            if sql.startswith('UPDATE fs_horse_bonding'):raise RuntimeError('XP write failed')
            return original(sql,*args)
        self.lua.globals().DB.exec=fail
        identity=self.complete();self.assertEqual(self.row()['state'],'paid')
        self.assertEqual(self.f.xp(),0);self.assertEqual(self.lua.globals().charges,1)
        self.lua.globals().DB.exec=original
        self.assertTrue(self.t.Settle(identity).ok);self.assertEqual(self.f.xp(),75)
        self.assertEqual(self.lua.globals().charges,1)

    def test_insufficient_funds_awards_nothing(self):
        self.lua.execute('balance=0');self.complete()
        self.assertEqual(self.row()['state'],'cancelled');self.assertEqual(self.f.xp(),0)
        self.assertEqual(self.lua.globals().charges,0)

    def test_wrong_simulator_stale_sequence_and_wrong_mode_cannot_advance(self):
        self.request();g=self.lua.globals();q=g.r.training;g.pos=q.points[1];g.clock=3000
        self.t.Tick(g.r)
        p=self.f.h.table({'id':q.id,'sequence':q.sample.sequence,'mode':'leading','alive':True})
        self.assertFalse(self.t.Sample(9,p).ok);self.assertEqual(q.index,1)
        p['mode']='riding';self.assertTrue(self.t.Sample(3,p).ok);self.assertEqual(q.index,1)
        self.assertFalse(self.t.Sample(3,p).ok);self.assertEqual(self.f.xp(),0)

    def test_teleport_and_boundary_departure_cancel_without_fee(self):
        self.request();g=self.lua.globals();self.t.Tick(g.r)
        g.clock+=500;g.pos=self.f.h.table({'x':0,'y':0,'z':0});self.t.Tick(g.r)
        self.assertEqual(self.row()['state'],'cancelled');self.assertEqual(g.charges,0)

    def test_travel_xp_is_suppressed_during_course(self):
        self.request();g=self.lua.globals()
        for _ in range(40):self.f.tick()
        self.assertEqual(self.f.xp(),0);self.assertEqual(g.charges,0)

    def test_restart_cancels_unfinished_but_recovers_paid_completion(self):
        self.lua.execute('losePayment=true');self.complete()
        self.lua.execute("CreateThread=function(fn) threads[#threads+1]=fn end")
        self.lua.execute((ROOT/'server/horse/training.lua').read_text())
        t=self.lua.globals().Stables.Training;self.assertTrue(t.Start().ok)
        self.assertEqual(self.row()['state'],'completed');self.assertEqual(self.f.xp(),75)
        self.assertEqual(self.lua.globals().charges,1)

    def test_restart_cancels_unfinished_course_without_fee(self):
        self.request()
        self.lua.execute('CreateThread=function(fn) threads[#threads+1]=fn end')
        self.lua.execute((ROOT/'server/horse/training.lua').read_text())
        self.assertTrue(self.lua.globals().Stables.Training.Start().ok)
        self.assertEqual(self.row()['state'],'cancelled');self.assertEqual(self.f.xp(),0)
        self.assertEqual(self.lua.globals().charges,0)

    def test_owed_course_xp_settles_after_injury_without_reviving_horse(self):
        self.lua.execute('losePayment=true');identity=self.complete()
        self.db.execute("UPDATE fs_horses SET biological_state='downed'");self.db.commit()
        self.assertTrue(self.t.Settle(identity).ok);self.assertEqual(self.f.xp(),75)
        self.assertEqual(self.db.execute('SELECT biological_state FROM fs_horses').fetchone()[0],'downed')

    def test_disabling_new_courses_does_not_discard_pending_paid_reward(self):
        self.lua.execute('losePayment=true');self.complete()
        self.lua.execute('Config.training.enabled=false;CreateThread=function(fn) threads[#threads+1]=fn end')
        self.lua.execute((ROOT/'server/horse/training.lua').read_text())
        self.assertTrue(self.lua.globals().Stables.Training.Start().ok)
        self.assertEqual(self.row()['state'],'completed');self.assertEqual(self.f.xp(),75)
        self.assertEqual(self.lua.globals().charges,1)

    def test_xp_commit_reply_loss_cannot_duplicate_payment_or_reward(self):
        original=self.f.h.execute
        def lose(sql,*args):
            result=original(sql,*args)
            if sql.startswith("UPDATE fs_training_sessions SET state='completed'"):self.f.h.lost_commit=True
            return result
        self.lua.globals().DB.exec=lose
        identity=self.complete();self.lua.globals().DB.exec=original
        self.assertEqual(self.row()['state'],'completed');self.assertEqual(self.f.xp(),75)
        self.assertTrue(self.t.Settle(identity).ok);self.assertEqual(self.f.xp(),75)
        self.assertEqual(self.lua.globals().charges,1)

    def test_permanent_stats_advance_through_existing_progression(self):
        self.lua.execute('''Config.bonding.statRewardsEnabled=true;Config.bonding.xpPerLevel=50;Config.bonding.maxStatBonus=2
            Horses.BreedCatalog.Morgan.colors.a_c_horse_morgan_bay.stats={health=1,stamina=2,handling=2,acceleration=1,speed=2}''')
        self.assertTrue(self.f.g.Start().ok);self.complete()
        saved=self.f.g.Read(self.f.horse).value
        self.assertEqual(saved.xp,75);self.assertEqual(saved.training.level,1)
        self.assertEqual(saved.training.ranks.health,2)

    def test_riding_course_uses_all_laps_before_paying(self):
        self.complete('riding');self.assertEqual(self.row()['state'],'completed')
        self.assertEqual(self.f.xp(),112);self.assertEqual(self.lua.globals().charges,1)

    def test_daily_cap_reserves_remaining_reward_before_payment(self):
        self.lua.execute('Config.training.dailyHorseXpLimit=40')
        self.complete();self.assertEqual(self.f.xp(),40)
        self.lua.execute('pos={x=-381.129,y=765.596,z=116.077}')
        self.assertEqual(self.request().code,'training_daily_limit')
        self.assertEqual(self.f.xp(),40);self.assertEqual(self.lua.globals().charges,1)

    def test_registered_rpc_rejects_client_rewards_and_checkpoint_numbers(self):
        g=self.lua.globals();validate=g.routes['stables.horses.call.training_sample.v1'].spec.validatePayload
        p={'id':self.f.horse,'sequence':1,'mode':'leading','alive':True}
        self.assertTrue(validate(self.f.h.table(p)));self.assertFalse(validate(self.f.h.table(dict(p,xp=1000))))
        self.assertFalse(validate(self.f.h.table(dict(p,index=99))))

    def test_simulator_migration_replaces_observation_without_resetting_deadline(self):
        self.request();g=self.lua.globals();q=g.r.training;original_end=q.endsAt
        g.pos=q.points[1];g.clock=3000;self.t.Tick(g.r);old=q.sample.sequence
        g.owner=4;g.clock=4000;self.t.Tick(g.r)
        self.assertEqual(q.sample.owner,4);self.assertGreater(q.sample.sequence,old);self.assertEqual(q.endsAt,original_end)
        reply={'id':q.id,'sequence':old,'mode':'leading','alive':True}
        self.assertFalse(self.t.Sample(3,self.f.h.table(reply)).ok)
        reply['sequence']=q.sample.sequence
        self.assertTrue(self.t.Sample(4,self.f.h.table(reply)).ok);self.assertEqual(q.index,2)

    def test_disconnect_after_verified_final_checkpoint_preserves_completed_obligation(self):
        self.lua.execute('CreateThread=function(fn) threads[#threads+1]=fn end')
        self.complete();g=self.lua.globals()
        self.assertTrue(g.r.training.verified);g.r.cancelled=True;g.current=False
        self.t.Cancel(g.r)
        g.threads[len(g.threads)]()
        self.assertEqual(self.row()['state'],'completed');self.assertEqual(self.f.xp(),75)
        self.assertEqual(g.charges,1)

    def sample_at(self,position,elapsed=1000):
        g=self.lua.globals();g.pos=position;g.clock+=elapsed;self.t.Tick(g.r)
        q=g.r.training
        if q and q.sample:
            return self.t.Sample(g.owner,self.f.h.table({'id':q.id,'sequence':q.sample.sequence,'mode':'leading','alive':True}))

    def test_course_remains_active_beyond_thirty_seconds(self):
        self.request();g=self.lua.globals();point=g.r.training.points[1]
        for _ in range(40):self.sample_at(point)
        self.assertEqual(self.row()['state'],'active');self.assertIsNotNone(g.r.training)
        self.assertEqual(g.charges,0)

    def test_ground_height_difference_does_not_block_horizontal_checkpoint(self):
        self.request();g=self.lua.globals();q=g.r.training;p=q.points[1]
        ground=self.f.h.table({'x':p.x,'y':p.y,'z':p.z-4})
        self.sample_at(ground,3000);self.assertEqual(q.index,2)
        point=q.points[2];far_below=self.f.h.table({'x':point.x,'y':point.y,'z':point.z-20})
        self.sample_at(far_below,3000);self.assertEqual(q.index,2)

    def test_brief_boundary_turn_is_tolerated_but_sustained_departure_cancels(self):
        self.request();g=self.lua.globals();q=g.r.training
        self.sample_at(q.points[1],3000);self.sample_at(q.points[2],3000)
        outside=self.f.h.table({'x':-379,'y':777,'z':116})
        self.sample_at(outside);self.assertEqual(self.row()['state'],'active')
        self.sample_at(q.points[2]);self.assertIsNone(q.outsideSince)
        for _ in range(4):self.sample_at(outside)
        self.assertEqual(self.row()['state'],'cancelled');self.assertEqual(g.charges,0)
        ended=g.events[len(g.events)]
        self.assertEqual(ended.p.result.code,'training_boundary')


if __name__=='__main__':unittest.main()
