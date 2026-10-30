"""Native Cargo completion, exact target, eligibility and saddlebag animation."""
import unittest
from lupa.lua54 import LuaRuntime
from test_feather_boundary import ROOT

class BagPromptTest(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            Config={saddlebags={enabled=true}};active={entity=11,generationId='one'};distance=1;onFoot=true
            events={};clock=0
            Stables={Client={Text=function(k) return k end,Message=function() end,
                Rpc=function(action,p)
                    assert(action=='saddlebags' and next(p)==nil);opens=(opens or 0)+1
                    if changed then active.generationId='two' end
                    return {ok=not refused}
                end},Horse={Flee=function(generation) stores=(stores or 0)+1;storedGeneration=generation end,GetActive=function() if not active then return nil end;local copy={};for k,v in pairs(active) do copy[k]=v end;return copy end}}
            CreateThread=function(fn) thread=coroutine.create(fn) end
            Wait=function(ms) coroutine.yield(ms) end
            GetHashKey=function(s) return s=='EVENT_PLAYER_PROMPT_TRIGGERED' and 123 or 456 end
            PlayerPedId=function() return 22 end;IsEntityDead=function() return false end
            IsPedOnFoot=function() return onFoot end;IsNuiFocused=function() return focus==true end
            GetEntityCoords=function(e) return {x=e==11 and 0 or distance,y=0,z=0} end
            GetNumberOfEvents=function() return #events end
            CreateEventDataBuffer=function(size)
                assert(size==80)
                return {Buffer=function(self) return self end,GetInt32=function(self,offset) return self[offset] end}
            end
            Citizen={InvokeNative=function(hash,a,b,c,d,e)
                if hash==0xA85E614430EFF816 then return events[b+1].hash or 123 end
                if hash==0x57EC5FA4D4D6AFCA then
                    assert(d==10);local event=events[b+1]
                    if event.malformed then return false end
                    c[0]=event.kind;c[16]=event.entity;return true
                end
                if hash==0xCD181A959CFDD7F4 then
                    assert(a==22 and b==11 and c==456 and d==0 and e==true)
                    animations=(animations or 0)+1
                end
            end}
            function Step() local ok,ms=coroutine.resume(thread);assert(ok,ms);events={};return ms end
        """)
        self.lua.execute((ROOT/'client/horse/target_menu.lua').read_text(encoding='utf-8'))
    def test_initial_key_press_does_not_open_but_completed_cargo_does_once(self):
        g=self.lua.globals();self.lua.execute('active.saddlebag=186;pressed=true')
        self.assertEqual(g.Step(),0);self.assertIsNone(g.opens)
        self.lua.execute('events={{kind=28,entity=11},{kind=28,entity=11}}')
        self.assertEqual(g.Step(),500);self.assertEqual(g.opens,1);self.assertEqual(g.animations,1)
        self.assertEqual(g.Step(),0);self.assertEqual(g.opens,1)
    def test_other_prompt_other_horse_and_malformed_payload_do_not_open(self):
        self.lua.execute('active.saddlebag=186;events={{kind=35,entity=11},{kind=28,entity=99},{kind=28,entity=11,malformed=true}}')
        self.assertEqual(self.lua.globals().Step(),0);self.assertIsNone(self.lua.globals().opens)
    def test_menu_mount_removed_or_distant_horse_ignore_completion(self):
        g=self.lua.globals()
        for change in ('active={entity=11};','active={entity=11,saddlebag=186};focus=true;','focus=false;onFoot=false;','onFoot=true;active=nil;','active={entity=11,saddlebag=186};distance=4;'):
            self.lua.execute(change+'events={{kind=28,entity=11}}')
            self.assertIn(g.Step(),(0,500));self.assertIsNone(g.opens)
    def test_changed_generation_after_authorization_never_animates_replacement(self):
        self.lua.execute("active.saddlebag=186;changed=true;events={{kind=28,entity=11}}")
        g=self.lua.globals();g.Step();self.assertEqual(g.opens,1);self.assertIsNone(g.animations)

    def test_native_flee_uses_current_generation_without_requiring_saddlebags(self):
        self.lua.execute("Config.stable={fleeEnabled=true};Config.saddlebags.enabled=false;events={{kind=33,entity=11},{kind=33,entity=11}}")
        g=self.lua.globals();g.Step();self.assertEqual(g.stores,1);self.assertEqual(g.storedGeneration,'one')
        self.assertIsNone(g.opens);self.assertIsNone(g.animations)
    def test_disabled_flee_or_foreign_target_never_stores(self):
        g=self.lua.globals();self.lua.execute('events={{kind=33,entity=11}}');g.Step();self.assertIsNone(g.stores)
        self.lua.execute("events={{kind=33,entity=99}}")
        g.Step();self.assertIsNone(g.stores)

    def test_server_refusal_never_starts_animation(self):
        self.lua.execute('active.saddlebag=186;refused=true;events={{kind=28,entity=11}}')
        g=self.lua.globals();g.Step();self.assertEqual(g.opens,1);self.assertIsNone(g.animations)

if __name__=='__main__':unittest.main()
