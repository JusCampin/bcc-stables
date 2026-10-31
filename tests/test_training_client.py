"""Current-simulator course observations and native presentation protocol."""
import unittest
import test_bonding_client as fixture
from test_feather_boundary import ROOT
from test_call_repository import GEN,HORSE


class TrainingClientTest(unittest.TestCase):
    def setUp(self):
        self.f=fixture.BondingClientTest();self.f.setUp();self.lua=self.f.lua
        self.lua.execute('''
            Config.training={enabled=true};threads={}
            AddEventHandler=function(name,fn) events[name]=fn end
            PlayerPedId=function() return 10 end
            CreateThread=function(fn) threads[#threads+1]=fn end
            Stables.Horse.GetActive=function() return {generationId=state.bccStablesGeneration,entity=100} end
            p={id="'''+HORSE+'''",generationId="'''+GEN+'''",observerId="'''+HORSE+'''",netId=100,
                modelKey='a_c_horse_morgan_bay',targetNet=10,sequence=1}
        ''')
        self.lua.execute((ROOT/'client/horse/training.lua').read_text())

    def test_mounted_owner_observation_uses_exact_call_and_has_no_reward_fields(self):
        self.lua.execute("mounted=true;events['bcc-stables:training:sample'](p);threads[#threads]()")
        call=self.lua.globals().calls[1]
        self.assertEqual(call.action,'training_sample');self.assertEqual(call.p.mode,'riding')
        self.assertTrue(call.p.alive);self.assertIsNone(call.p.xp);self.assertIsNone(call.p.index)

    def test_wrong_entity_or_uncontrolled_simulator_never_replies(self):
        self.lua.execute("noControl=true;events['bcc-stables:training:sample'](p);noControl=false;state.bccStablesObserver='wrong';events['bcc-stables:training:sample'](p)")
        self.assertEqual(len(self.lua.globals().calls),0)

    def test_leading_observation_matches_owner_and_bound_horse(self):
        self.lua.execute('''
            local native=Citizen.InvokeNative
            Citizen.InvokeNative=function(hash,...)
                if hash==0xEFC4303DDC6E60D3 then return true end
                if hash==0xED1F514AF4732258 then return 100 end
                return native(hash,...)
            end
            events['bcc-stables:training:sample'](p);threads[#threads]()
        ''')
        self.assertEqual(self.lua.globals().calls[1].p.mode,'leading')

    def test_marker_uses_server_progress_and_stops_when_horse_is_lost(self):
        self.lua.execute('''
            markers=0
            GetGroundZFor_3dCoord=function(x,y,z) assert(x==1 and y==2);return true,1 end
            DrawMarker=function(_,x,y,z) assert(x==1 and y==2 and math.abs(z-1.03)<0.001);markers=markers+1 end
            Wait=function(ms) coroutine.yield(ms) end
            p.points={{x=1,y=2,z=3}};p.index=1;p.remainingMs=30000;p.radius=2.5;p.mode='leading'
            events['bcc-stables:training:progress'](p)
            co=coroutine.create(threads[2]);assert(coroutine.resume(co))
            Stables.Horse.GetActive=function() return nil end
            assert(coroutine.resume(co));assert(markers==1)
        ''')

    def test_disabled_feature_starts_no_idle_native_loops(self):
        self.lua.execute('Config.training.enabled=false;threads[1]();threads[2]()')
        self.assertEqual(len(self.lua.globals().calls),0)


if __name__=='__main__':unittest.main()
