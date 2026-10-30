"""Saved XP, bounded native observations and care commit/replay; no live horses."""
import unittest
import test_checkout as checkout
import test_feeding as feeding
from test_feather_boundary import ROOT

SCHEMA='''CREATE TABLE fs_horse_bonding(horse_id TEXT PRIMARY KEY,xp INTEGER DEFAULT 0,revision INTEGER DEFAULT 0,
travel_generation TEXT,travel_sequence INTEGER DEFAULT 0,last_feed_at INTEGER DEFAULT 0,last_brush_at INTEGER DEFAULT 0,training_json TEXT);'''
CONFIG="Config.bonding={enabled=true,showXpMessage=true,careCooldownSeconds=60,xpRewards={riding=10,leading=10,feed=5,brush=5}}"


class BondingTest(unittest.TestCase):
    def setUp(self):
        self.h=checkout.CheckoutTest();self.h.setUp();self.lua,self.db=self.h.lua,self.h.db
        purchase=self.h.quote().value;self.assertTrue(self.h.confirm(purchase).ok);self.horse=purchase.horseId
        self.db.executescript(SCHEMA)
        self.db.execute("UPDATE fs_horses SET availability='active'")
        self.db.execute('INSERT INTO fs_call_slots VALUES(?,?)',(self.lua.globals().session.characterId,self.horse));self.db.commit()
        self.lua.globals().horseId=self.horse
        self.lua.execute(CONFIG+'''
            clock=0;x=0;owner=3;events={};routes={}
            GetGameTimer=function() return clock end
            GetPlayerPed=function() return 10 end;GetPlayerRoutingBucket=function() return 0 end
            GetEntityCoords=function(e) return {x=x+(e==10 and far and 10 or 0),y=0,z=0} end
            NetworkGetEntityOwner=function() return owner end
            NetworkGetNetworkIdFromEntity=function(e) return e end
            DoesEntityExist=function(e) return e~=0 end
            TriggerClientEvent=function(name,source,p) events[#events+1]={name=name,source=source,p=p} end
            CreateThread=function(fn) fn() end
            exports['feather-core'].RegisterRpc=function(_,name,fn,spec) routes[name]={fn=fn,spec=spec};return {ok=true,value=true} end
            r={id=horseId,observerId=horseId,entity=100,netId=100,session=session,
                horse={horseId=horseId,assetId=horseId,modelKey='a_c_horse_morgan_bay'},bonding={xp=0,revision=0}}
            Stables.HorseController={MovementRecord=function(s) return current and not r.cancelled and not r.busy and s.characterId==session.characterId and r or nil end}
        ''')
        self.load()

    def load(self):
        self.lua.execute((ROOT/'server/horse/bonding.lua').read_text(encoding='utf-8'))
        self.g=self.lua.globals().Stables.Bonding;self.assertTrue(self.g.Start().ok)
    def tearDown(self): self.h.tearDown()
    def tick(self,mode='riding',dx=4,source=None,alive=True):
        g=self.lua.globals();g.clock+=2000;g.x+=dx;self.g.Tick(g.r)
        t=g.r.bondingTicket
        if t:
            return self.g.Sample(g.owner if source is None else source,self.h.table(dict(generationId=g.r.id,sequence=t.sequence,mode=mode,alive=alive)))
    def ride(self,ticks=34,mode='riding'):
        for _ in range(ticks): self.tick(mode)
    def xp(self): return self.g.Read(self.horse).value.xp

    def test_original_riding_cadence_awards_server_amount_and_persists(self):
        self.ride(31);self.assertEqual(self.xp(),0)
        self.ride(2);self.assertEqual(self.xp(),10)
        self.load();self.assertEqual(self.xp(),10)
        owned=self.lua.globals().Stables.OwnedRepository.ReadSelected(self.lua.globals().session)
        self.assertTrue(owned.ok,owned.code);self.assertEqual(owned.value.bonding.xp,10)

    def test_leading_has_shorter_milestone_and_no_idle_rpc_poll(self):
        for _ in range(20): self.tick(dx=0)
        self.assertEqual(len(self.lua.globals().events),1)
        self.assertEqual(self.xp(),0)
        self.ride(18,'leading');self.assertEqual(self.xp(),10)

    def test_wrong_simulator_and_replayed_sequence_cannot_award(self):
        self.tick();self.tick(source=9)
        t=self.lua.globals().r.bondingTicket
        p=self.h.table(dict(generationId=self.horse,sequence=t.sequence,mode='riding',alive=True))
        self.assertTrue(self.g.Sample(3,p).ok)
        self.assertFalse(self.g.Sample(3,p).ok);self.assertEqual(self.xp(),0)

    def test_observation_route_rejects_client_supplied_xp(self):
        spec=self.lua.globals().routes['stables.horses.call.bonding_sample.v1'].spec
        p=dict(generationId=self.horse,sequence=1,mode='riding',alive=True)
        self.assertTrue(spec.validatePayload(self.h.table(p)))
        self.assertFalse(spec.validatePayload(self.h.table(dict(p,amount=1000000))))

    def test_stationary_teleported_distant_dead_and_idle_modes_never_award(self):
        for mode,dx,far,alive in [('riding',0,False,True),('riding',1000,False,True),('riding',4,True,True),('riding',4,False,False),('idle',4,False,True)]:
            self.lua.globals().far=far
            for _ in range(35): self.tick(mode,dx,alive=alive)
            self.assertEqual(self.xp(),0)

    def test_lost_commit_ack_retries_same_travel_receipt(self):
        self.ride(32);self.h.lost_commit=True;self.tick()
        self.assertEqual(self.xp(),10)
        self.ride(4);self.assertEqual(self.xp(),10)
        self.assertIsNone(self.lua.globals().r.bondingReward)

    def test_native_owner_migration_keeps_owner_character_and_requires_new_samples(self):
        self.ride(10);self.lua.globals().owner=9
        self.ride(27)
        self.assertEqual(self.xp(),10)
        self.assertTrue(any(e.source==9 for e in self.lua.globals().events.values()))

    def test_cleanup_and_foreign_projection_fence_pending_reward(self):
        self.ride(32)
        self.db.execute("UPDATE fs_horses SET availability='stored'");self.db.commit()
        self.tick();self.assertEqual(self.xp(),0)
        self.lua.globals().r.cancelled=True;self.g.Forget(self.lua.globals().r)
        self.assertFalse(self.g.Sample(3,self.h.table(dict(generationId=self.horse,sequence=32,mode='riding',alive=True))).ok)

    def test_care_cooldown_is_per_horse_action_and_xp_does_not_touch_cores(self):
        g=self.lua.globals()
        self.db.execute('UPDATE fs_horse_condition SET health_core=27,stamina_core=13');self.db.commit()
        def care(action,at):
            q=self.h.table(dict(horseId=self.horse,characterId=g.session.characterId,action=action,bondingReward=5,bondingAt=at,bondingCooldown=60))
            output=[]
            self.h.transaction(lambda tx: output.append(self.g.Care(tx,q)) or output[-1].ok)
            return output[0].value
        self.assertEqual(care('feed',1000).amount,5)
        self.assertEqual(care('feed',1005).amount,0)
        self.assertEqual(care('brush',1005).amount,5)
        self.assertEqual(care('feed',1060).amount,5)
        self.assertEqual(self.xp(),15)
        self.assertEqual(tuple(self.db.execute('SELECT health_core,stamina_core FROM fs_horse_condition').fetchone()),(27,13))

    def test_disabled_feature_adds_no_schema_probe_or_sample_route(self):
        self.lua.execute("Config.bonding.enabled=false;routes={};DB.query=function() error('disabled feature queried DB') end")
        self.load()
        self.assertEqual(len(list(self.lua.globals().routes.items())),0)


class CareBondingTest(unittest.TestCase):
    def setUp(self):
        self.h=feeding.FeedingTest();self.h.setUp();self.lua=self.h.lua;self.db=self.h.f.db
        self.db.executescript(SCHEMA)
        self.lua.execute(CONFIG+";os.time=function() return 1000 end;exports['feather-core'].RegisterRpc=function() return {ok=true,value=true} end")
        self.lua.execute((ROOT/'server/horse/bonding.lua').read_text(encoding='utf-8'))
        self.g=self.lua.globals().Stables.Bonding;self.assertTrue(self.g.Start().ok)
    def tearDown(self): self.h.tearDown()
    def test_successful_care_and_replay_award_once(self):
        result=self.h.feed();self.assertTrue(result.ok,result.code)
        self.assertEqual(result.value.bonding.xp,5)
        self.assertTrue(self.h.p.Settle(self.h.operation(),True).ok)
        self.assertEqual(self.g.Read(self.h.horse).value.xp,5)
        self.assertEqual(self.h.saved(),(90,80,1))
    def test_cancelled_care_has_no_xp_or_consumption(self):
        self.lua.globals().walkAway=True
        self.assertTrue(self.h.feed().ok)
        self.assertEqual(self.g.Read(self.h.horse).value.xp,0)
        self.assertEqual(self.lua.globals().consumptions,0)
    def test_failed_care_commit_rolls_xp_back_then_recovers_once(self):
        self.db.executescript("CREATE TRIGGER refuse_care BEFORE UPDATE OF state ON fs_care_operations WHEN NEW.state='applied' BEGIN SELECT RAISE(ABORT,'injected'); END;")
        self.assertFalse(self.h.feed().ok)
        self.assertEqual(self.g.Read(self.h.horse).value.xp,0)
        self.assertEqual(self.lua.globals().consumptions,1)
        self.db.execute('DROP TRIGGER refuse_care');self.db.commit()
        self.assertTrue(self.h.p.Settle(self.h.operation(),False).ok)
        self.assertTrue(self.h.p.Settle(self.h.operation(),False).ok)
        self.assertEqual(self.g.Read(self.h.horse).value.xp,5)
        self.assertEqual(self.lua.globals().consumptions,1)
