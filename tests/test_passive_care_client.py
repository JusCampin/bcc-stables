"""Native action identity, actual animation observations and bounded cleanup."""
import unittest
from lupa.lua54 import LuaRuntime
from test_feather_boundary import ROOT
from test_call_repository import GEN,HORSE


class WorldCareClientTest(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            Config={worldCare={enabled=true},bonding={showXpMessage=true},controls={rest=1,standOrWake=2,drink=3,sleep=4,wallow=5}}
            Stables={Client={},Horse={}};events={};threads={};clock=0;calls={};clears=0;animations={};source=65535
            local C=Stables.Client
            C.Uuid=function(v) return type(v)=='string' and #v==36 end
            C.Text=function(k) return k end;C.Notify=function() end;C.Rpc=function(a,p) calls[#calls+1]={action=a,p=p};return {ok=true} end
            RegisterNetEvent=function(n,fn) events[n]=fn end;AddEventHandler=function(n,fn) events[n]=fn end
            CreateThread=function(fn) threads[#threads+1]=coroutine.create(fn) end
            Wait=function(ms) coroutine.yield(ms) end;GetGameTimer=function() return clock end
            function Step(ms)
                clock=clock+(ms or 100)
                for _,co in ipairs(threads) do
                    if coroutine.status(co)~='dead' then local ok,err=coroutine.resume(co);assert(ok,err) end
                end
            end
            state={bccStablesGeneration="'''+GEN+'''",bccStablesObserver="'''+HORSE+'''",bccStablesCoreRevision=4}
            Entity=function() return {state=state} end
            NetworkGetEntityFromNetworkId=function(n) return n end;NetworkGetNetworkIdFromEntity=function(n) return n end
            DoesEntityExist=function(e) return e==100 or e==10 end
            IsEntityDead=function(e) return e==10 and ownerDead==true end
            NetworkHasControlOfEntity=function() return not noControl end
            GetEntityModel=function() return 1 end;GetHashKey=function() return 1 end
            IsPedOnMount=function() return mounted==true end;GetRiderOfMount=function() return mounted and 10 or 0 end
            IsEntityInWater=function() return water~=false end
            RequestAnimDict=function() end;HasAnimDictLoaded=function() return true end;RemoveAnimDict=function() end
            GetEntityCoords=function() return {x=0,y=0,z=0} end;GetEntityRotation=GetEntityCoords
            GetAnimDuration=function() return 0.2 end
            TaskPlayAnimAdvanced=function(e,d,n,...) animations[#animations+1]={dict=d,name=n,flags=({...})[10]};playingDict=d;playingName=n end
            TaskPlayAnim=TaskPlayAnimAdvanced
            IsEntityPlayingAnim=function(e,d,n) return not interrupted and playingDict==d and playingName==n end
            ClearPedTasks=function() clears=clears+1;playingDict=nil end
            IsControlJustPressed=function(_,key) return key==pressed end
            prompts={};nextPrompt=0;flags={};targeted=true
            PlayerId=function() return 0 end;IsPlayerFreeAiming=function() return freeAim==true end
            GetRandomIntInRange=function() return 99 end;CreateVarString=function(_,_,text) return text end
            UiPromptRegisterBegin=function() nextPrompt=nextPrompt+1;prompts[nextPrompt]={};return nextPrompt end
            UiPromptSetControlAction=function(h,v) prompts[h].control=v end
            UiPromptSetText=function(h,v) prompts[h].text=v end
            UiPromptSetStandardMode=function() end;UiPromptRegisterEnd=function() end
            UiPromptSetGroup=function(h,v) prompts[h].group=v end
            UiPromptSetEnabled=function(h,v) prompts[h].enabled=v end
            UiPromptSetVisible=function(h,v) prompts[h].visible=v end
            UiPromptHasStandardModeCompleted=function(h) return prompts[h].control==pressed end
            UiPromptSetActiveGroupThisFrame=function(group) shownGroup=group end
            UiPromptDelete=function(h) prompts[h]=nil end
            GetCurrentResourceName=function() return 'bcc-stables' end
            PlayerPedId=function() return 10 end;IsNuiFocused=function() return focus==true end
            DisableControlAction=function() mountDisabled=true end
            IsDisabledControlJustPressed=function() return mountPressed==true end
            Citizen={ResultAsInteger=function() return 0 end,InvokeNative=function(hash,e,attribute,value)
                if hash==0xAC5045AB7F1A34FD then return led==true end
                if hash==0x36731AC041289BB1 then return attribute==0 and 27 or 13 end
                if hash==0x1913FE4CBF41C463 then flags[attribute]=value;return end
                if hash==0x27F89FDC16688A7A then return targeted end
                if hash==0xB796970BD125FCE8 then return 77 end
                if hash==0x2F385ECC5200938D then prompts[e].ordering=attribute;return end
                if hash==0x92DB0739813C5186 then mounts=(mounts or 0)+1;return end
                error('Unexpected native mutation')
            end}
            p={generationId="'''+GEN+'''",observerId="'''+HORSE+'''",sequence=1,sample=1,
                netId=100,targetNet=10,modelKey='morgan',action='rest'}
            Stables.Horse.GetActive=function() return {entity=100,generationId=p.generationId} end
        ''')
        self.lua.execute((ROOT/'client/horse/passive_care.lua').read_text(encoding='utf-8'))
    def test_original_entry_loop_exit_and_observed_depleted_cores(self):
        self.lua.execute("events['bcc-stables:world:start'](p);Step(0);Step(250);events['bcc-stables:world:sample'](p);Step(0)")
        calls=self.lua.globals().calls
        self.assertEqual(calls[1].action,'world_sample');self.assertTrue(calls[1].p.loop)
        self.assertTrue(calls[1].p.playing);self.assertEqual(calls[1].p.healthCore,27);self.assertEqual(calls[1].p.staminaCore,13)
        self.lua.execute("events['bcc-stables:world:stop'](p);Step(100)")
        self.assertEqual(self.lua.globals().animations[3].name,'exit')
        self.assertEqual(self.lua.globals().clears,0)
        self.lua.execute('Step(250)');self.assertEqual(self.lua.globals().clears,1)
    def test_spoofed_stale_or_uncontrolled_action_cannot_start(self):
        for setup in ('source=1','source=65535;state.bccStablesGeneration="wrong"','state.bccStablesGeneration=p.generationId;noControl=true'):
            self.lua.execute(setup+";events['bcc-stables:world:start'](p);Step(0)")
        self.assertEqual(len(self.lua.globals().animations),0)
    def test_mounting_cancels_without_clearing_rider_tasks(self):
        self.lua.execute("events['bcc-stables:world:start'](p);Step(0);Step(250);mounted=true;Step(100)")
        self.assertEqual(self.lua.globals().clears,0)
    def test_owner_death_exits_and_resource_stop_clears_owned_animation(self):
        self.lua.execute("events['bcc-stables:world:start'](p);Step(0);Step(250);ownerDead=true;Step(100);Step(100)")
        self.assertEqual(self.lua.globals().clears,1)
        self.assertEqual(self.lua.globals().animations[3].name,'exit')
        self.assertFalse(self.lua.globals().flags[301]);self.assertFalse(self.lua.globals().flags[412])
    def test_input_uses_existing_route_and_no_client_reward_fields(self):
        self.lua.execute('pressed=1;Stables.HorseWorldCare.Input({entity=100,generationId=p.generationId});Step(0)')
        p=self.lua.globals().calls[1].p
        self.assertEqual(p.action,'rest');self.assertEqual(list(p.keys()),['action'])
    def test_interrupted_animation_is_reported_not_credited(self):
        self.lua.execute("events['bcc-stables:world:start'](p);Step(0);Step(250);interrupted=true;events['bcc-stables:world:sample'](p);Step(0);Step(600)")
        self.assertFalse(self.lua.globals().calls[1].p.playing)
    def test_stop_before_start_fences_delayed_animation_and_orphan_worker_expires(self):
        self.lua.execute("events['bcc-stables:world:stop'](p);events['bcc-stables:world:start'](p);Step(0)")
        self.assertEqual(len(self.lua.globals().animations),0)
        self.lua.execute("p.sequence=2;events['bcc-stables:world:start'](p);Step(0);Step(250);Step(11000);Step(100)")
        self.lua.execute('Step(250)');self.assertEqual(self.lua.globals().clears,1)
    def test_zero_duration_uses_original_fallback_and_long_entry_is_not_truncated(self):
        self.lua.execute("GetAnimDuration=function() return 0 end;events['bcc-stables:world:start'](p);Step(0);Step(1000)")
        self.assertEqual(len(self.lua.globals().animations),1)
        self.lua.execute('Step(1600)');self.assertEqual(len(self.lua.globals().animations),2)
        self.lua.execute("p.sequence=2;GetAnimDuration=function() return 12 end;events['bcc-stables:world:start'](p);Step(0);Step(10000)")
        self.assertEqual(self.lua.globals().animations[len(self.lua.globals().animations)].name,'enter')
    def test_cancel_entry_uses_quick_exit_and_never_clears_before_it(self):
        self.lua.execute("events['bcc-stables:world:start'](p);Step(0);events['bcc-stables:world:stop'](p);Step(0)")
        self.assertEqual(self.lua.globals().animations[2].name,'quick_exit')
        self.assertEqual(self.lua.globals().clears,0)
    def test_prompts_require_target_and_disable_drinking_without_water(self):
        self.lua.execute('targeted=false;pressed=1;Stables.HorseWorldCare.Input(Stables.Horse.GetActive());Step(0)')
        self.assertEqual(len(self.lua.globals().calls),0);self.assertEqual(len(self.lua.globals().prompts),0)
        self.lua.execute('targeted=true;pressed=nil;water=false;Stables.HorseWorldCare.Input(Stables.Horse.GetActive())')
        prompts=list(self.lua.globals().prompts.values())
        self.assertEqual(len(prompts),4);self.assertTrue(all(p.group==77 for p in prompts))
        self.assertFalse(next(p for p in prompts if p.control==3).enabled)
        self.lua.execute('Stables.HorseWorldCare.Hide()')
        self.assertTrue(all(not p.visible for p in prompts))
    def test_remote_owner_mount_waits_for_exact_confirmed_exit_without_extra_prompt(self):
        self.lua.execute("targeted=false;events['bcc-stables:world:owner_state']({generationId=p.generationId,sequence=2,action='sleep'});mountPressed=true;Stables.HorseWorldCare.Input(Stables.Horse.GetActive());Step(0)")
        self.assertEqual(len(self.lua.globals().prompts),0)
        self.assertIsNone(self.lua.globals().mounts)
        self.lua.execute("events['bcc-stables:world:ended']({generationId=p.generationId,sequence=1,completed=true});Step(100)")
        self.assertIsNone(self.lua.globals().mounts)
        self.lua.execute("events['bcc-stables:world:ended']({generationId=p.generationId,sequence=2,completed=true});Step(100)")
        self.assertEqual(self.lua.globals().mounts,1)
    def test_timed_out_exit_or_player_death_cannot_automount(self):
        self.lua.execute("events['bcc-stables:world:owner_state']({generationId=p.generationId,sequence=2,action='sleep'});mountPressed=true;Stables.HorseWorldCare.Input(Stables.Horse.GetActive());Step(0)")
        self.lua.execute("events['bcc-stables:world:ended']({generationId=p.generationId,sequence=2,completed=false});Step(100)")
        self.assertIsNone(self.lua.globals().mounts)
        self.lua.execute("events['bcc-stables:world:owner_state']({generationId=p.generationId,sequence=3,action='sleep'});Stables.HorseWorldCare.Input(Stables.Horse.GetActive());Step(0);ownerDead=true;events['bcc-stables:world:ended']({generationId=p.generationId,sequence=3,completed=true});Step(100)")
        self.assertIsNone(self.lua.globals().mounts)
    def test_drink_preloads_loop_and_keeps_initial_verified_water_context(self):
        self.lua.execute("""
            p.action='drink';requested={};RequestAnimDict=function(d) requested[d]=true end
            local play=TaskPlayAnimAdvanced
            TaskPlayAnimAdvanced=function(e,d,n,...)
                if n=='enter' then assert(requested['amb_creature_mammal@world_horse_drink_ground@idle']) end
                play(e,d,n,...)
            end
            events['bcc-stables:world:start'](p);Step(0);water=false;Step(250)
            events['bcc-stables:world:sample'](p);Step(0)
        """)
        self.assertTrue(self.lua.globals().calls[1].p.water)
        self.assertTrue(self.lua.globals().calls[1].p.loop)
        self.assertTrue(self.lua.globals().calls[1].p.playing)
    def test_transitions_hold_final_pose_and_entry_handoff_uses_frame_precision(self):
        self.lua.execute("events['bcc-stables:world:start'](p);Step(0);Step(150)")
        self.assertEqual(self.lua.globals().animations[1].flags,2)
        self.lua.execute('Step(50)');self.assertEqual(len(self.lua.globals().animations),2)
        self.lua.execute("events['bcc-stables:world:stop'](p);Step(0)")
        self.assertEqual(self.lua.globals().animations[3].flags,2)
        self.assertEqual(self.lua.globals().clears,0)
    def test_full_prompt_group_uses_original_bindings_without_sort_overrides(self):
        self.lua.execute('pressed=1;Stables.HorseWorldCare.Input(Stables.Horse.GetActive());Step(0)')
        prompts=list(self.lua.globals().prompts.values())
        self.assertEqual(len(prompts),4)
        self.assertEqual([p.control for p in prompts],[3,1,4,5])
        self.assertTrue(all(p.ordering is None for p in prompts))
