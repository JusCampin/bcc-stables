"""Native protocol simulation; actual animation/physics require the live test."""
import unittest
import test_client_horse as fixture
from test_feather_boundary import ROOT


class InjuryClientTest(unittest.TestCase):
    def setUp(self):
        self.f=fixture.ClientHorseTest();self.f.setUp();self.lua=self.f.lua
        self.lua.execute('''
            CreateFromServer()
            Config.death.enabled=true
            Stables.Client.Text=function(key) return key end
            health=500;writhe=false;controlled=true;dead=false;writheCount=0;resurrections=0;reports=0;flags={}
            GetEntityHealth=function() return health end;GetEntityMaxHealth=function() return 500 end
            IsEntityDead=function() return dead end
            SetEntityHealth=function(_,n) health=n end
            NetworkHasControlOfEntity=function() return controlled end
            SetEntityInvincible=function(_,v) invincible=v end
            local native=Citizen.InvokeNative
            Citizen.InvokeNative=function(hash,a,b,c,...)
                if hash==0xDEB6D52126E7D640 then return writhe end
                if hash==0x71BC8E838B9C6035 then resurrections=resurrections+1;dead=false;return end
                if hash==0x8C038A39C4A4B6D6 then writhe=true;writheCount=writheCount+1;return end
                if hash==0x1913FE4CBF41C463 then flags[b]=c;return end
                return native(hash,a,b,c,...)
            end
            ClearPedTasksImmediately=function() writhe=false end
            ClearPedTasks=function() softClears=(softClears or 0)+1;writhe=false end
            Stables.Client.Rpc=function(route,p)
                if route=='revive' then revives=(revives or 0)+1;return {ok=true} end
                assert(route=='injury');reports=reports+1;return {ok=true}
            end
            Wait=function(ms) clock=clock+ms;coroutine.yield() end
            CreateThread=function(fn) local co=coroutine.create(fn);assert(coroutine.resume(co));worker=co end
            function Step() assert(coroutine.resume(worker)) end
            function State(state,seq,recovered)
                source=65535
                handlers['bcc-stables:injury:state']({generationId=spec.generationId,observerId=spec.observerId,
                    netId=55,modelKey=spec.modelKey,state=state,sequence=seq,revision=seq,recovered=recovered and 1 or nil})
            end
        ''')
        self.lua.execute((ROOT/'client/horse/injuries.lua').read_text())

    def test_alive_enables_damage_then_lethal_damage_only_reports(self):
        self.lua.execute("State('alive',1,false);Step();dead=true;health=0;Step()")
        g=self.lua.globals();self.assertTrue(g.invincible);self.assertEqual(g.resurrections,0)
        self.assertTrue(g.Stables.HorseInjuries.Blocked(g.spec.generationId));self.assertEqual(g.reports,1)

    def test_downed_restores_writhe_once_and_prevents_mount_and_lead(self):
        self.lua.execute("dead=true;State('downed',1,false);Step();Step()")
        g=self.lua.globals();self.assertEqual(g.writheCount,1);self.assertEqual(g.health,150)
        self.assertTrue(g.flags[136]);self.assertFalse(g.flags[297]);self.assertTrue(g.invincible)
        self.assertFalse(g.Stables.Horse.Lead())

    def test_native_revive_does_not_become_committed_recovery(self):
        self.lua.execute("State('downed',1,false);Step();State('reviving',2,false);writhe=false;health=500;Step()")
        g=self.lua.globals();self.assertTrue(g.flags[136]);self.assertEqual(g.writheCount,1)
        self.lua.execute("State('downed',3,false);Step()")
        self.assertEqual(g.writheCount,2);self.assertEqual(g.health,150)

    def test_committed_recovery_is_applied_once_and_later_damage_is_not_healed(self):
        self.lua.execute("State('downed',1,false);Step();State('alive',2,true);Step();Step()")
        g=self.lua.globals();self.assertEqual(g.resurrections,0);self.assertEqual(g.health,500)
        self.assertFalse(g.flags[136]);self.assertFalse(g.invincible)
        self.lua.execute('dead=true;health=0;Step()')
        self.assertEqual(g.resurrections,0);self.assertEqual(g.health,0)

    def test_completed_native_revive_is_not_reset_at_commit(self):
        self.lua.execute("State('downed',1,false);Step();writhe=false;State('alive',2,true);Step()")
        g=self.lua.globals()
        self.assertEqual(g.resurrections,0);self.assertIsNone(g.softClears)
        self.assertFalse(g.flags[136]);self.assertEqual(g.health,500)

    def test_remote_simulator_without_local_control_never_mutates(self):
        self.lua.execute("controlled=false;dead=true;State('downed',1,false);Step()")
        g=self.lua.globals();self.assertEqual(g.resurrections,0);self.assertEqual(g.writheCount,0)
        self.lua.execute('controlled=true;Step()');self.assertEqual(g.writheCount,1)

    def test_old_state_packet_cannot_cancel_current_injury(self):
        self.lua.execute("State('downed',2,false);Step();State('alive',1,true);Step()")
        g=self.lua.globals();self.assertTrue(g.flags[136]);self.assertEqual(g.resurrections,0)

    def test_native_prompt_requires_current_target_and_completed_input(self):
        self.lua.execute('''
            State('downed',1,false)
            local native=Citizen.InvokeNative
            Citizen.InvokeNative=function(hash,...)
                if hash==0x756C7B4C43DF0422 then return promptVisible end
                if hash==0x351F74ED6177EBE7 then return target end
                if hash==0x91AEF906BCA88877 then return pressed end
                return native(hash,...)
            end
            IsControlJustPressed=function() return false end
            target=100;promptVisible=false;pressed=true
            local I=Stables.HorseInjuries;local r=Stables.Horse.GetActive()
            I.Input(r);assert(not revives)
            promptVisible=true;target=999;I.Input(r);assert(not revives)
            target=100;pressed=false;I.Input(r);assert(not revives)
            pressed=true;I.Input(r);assert(revives==1)
        ''')


if __name__=='__main__':unittest.main()
