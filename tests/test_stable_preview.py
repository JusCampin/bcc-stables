"""Local preview identity, cancellation and presentation cleanup."""
import unittest
from lupa.lua54 import LuaRuntime
from test_feather_boundary import ROOT


class PreviewTest(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            Stables={}; Config={preview={camera={distance=3.25}}}
            StableLocations={valentine={horse={coords={x=0,y=0,z=0},heading=0}}}
            valid=true;loaded=true;now=0;created=0;deleted=0;frozen=false;radar=true;camera=false
            GetGameTimer=function() return now end
            GetHashKey=function() return 123 end
            IsModelValid=function() return true end
            RequestModel=function() end
            HasModelLoaded=function() return loaded end
            workers={};heading=0;headingWrites=0;threadCount=0
            CreateThread=function(fn)
                local co=coroutine.create(fn);workers[#workers+1]=co;threadCount=threadCount+1
                assert(coroutine.resume(co))
            end
            Wait=function(ms)
                if coroutine.isyieldable() then coroutine.yield() else now=now+100;valid=false end
            end
            function Frame(ms)
                now=now+ms
                for _,co in ipairs(workers) do if coroutine.status(co)~='dead' then assert(coroutine.resume(co)) end end
            end
            GetEntityHeading=function() return heading end
            SetEntityHeading=function(entity,value) heading=value;headingWrites=headingWrites+1 end
            SetModelAsNoLongerNeeded=function() end
            IsRadarHidden=function() return not radar end
            PlayerPedId=function() return 1 end
            CreatePed=function(model,x,y,z,heading,networked)
                assert(networked==false);created=created+1;return 100+created
            end
            DoesEntityExist=function() return true end
            DeleteEntity=function() deleted=deleted+1 end
            cleaned={};dirty={};sexValues={}
            GetEntityModel=function() return 123 end
            Citizen={InvokeNative=function(hash,entity,expression,value)
                if hash==0x5653AB26C82938CF then sexValues[#sexValues+1]=value end
                if hash==0x6585D955A68452A5 then cleaned[entity]=(cleaned[entity] or 0)+1;dirty[entity]=false end
            end}
            SetEntityInvincible=function() end
            alphas={};resets=0
            SetEntityAlpha=function(entity,value) alphas[entity]=value end
            ResetEntityAlpha=function(entity) alphas[entity]=255;resets=resets+1 end
            SetBlockingOfNonTemporaryEvents=function() end
            FreezeEntityPosition=function(entity,value) if entity==1 then frozen=value end end
            DoesCamExist=function() return camera end
            CreateCam=function() camera=true;return 5 end
            SetCamCoord=function() end;PointCamAtCoord=function() end;SetCamFov=function() end;SetCamActive=function() end
            RenderScriptCams=function() end
            DestroyCam=function() camera=false end
            DisplayRadar=function(value) radar=value end
            IsCurrent=function() return valid end
        ''')
        self.lua.execute((ROOT/'client/ui/preview.lua').read_text())

    def show(self):
        self.lua.execute("Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent);Frame(200)")

    def test_local_only_preview_and_complete_cleanup(self):
        self.show()
        self.assertFalse(self.lua.globals().frozen)
        self.assertFalse(self.lua.globals().radar)
        self.lua.execute('Stables.Preview.Clear()')
        self.assertFalse(self.lua.globals().frozen)
        self.assertTrue(self.lua.globals().radar)
        self.assertFalse(self.lua.globals().camera)
        self.assertEqual(self.lua.globals().deleted,1)

    def test_close_restores_radar_even_if_native_hidden_readback_is_stale(self):
        self.lua.execute("IsRadarHidden=function() return true end")
        self.lua.execute("Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-a');Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-b');Stables.Preview.Clear(true)")
        self.assertTrue(self.lua.globals().radar)
        self.assertFalse(self.lua.globals().camera)

    def test_preview_saved_sex_and_live_switch_reuse_same_entity(self):
        self.lua.execute("Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-a','female')")
        self.assertEqual(self.lua.globals().sexValues[1],1)
        self.lua.execute("Stables.Preview.SetGender('male')")
        self.assertEqual(list(self.lua.globals().sexValues.values())[-1],0)
        self.assertEqual(self.lua.globals().created,1)
        self.lua.execute('Frame(300);Frame(700)')
        self.assertEqual(list(self.lua.globals().sexValues.values())[-1],0)

    def test_preview_cleans_spawn_and_delayed_dirt_without_permanent_worker(self):
        self.lua.execute("Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-a')")
        self.assertEqual(self.lua.globals().cleaned[101],1)
        self.lua.execute('dirty[101]=true;Frame(300)')
        self.assertFalse(self.lua.globals().dirty[101])
        self.lua.execute('dirty[101]=true;Frame(700)')
        self.assertFalse(self.lua.globals().dirty[101])
        self.assertEqual(self.lua.globals().cleaned[101],3)
        self.lua.execute('Frame(1000);Frame(1000)')
        self.assertEqual(self.lua.globals().cleaned[101],3)

    def test_delayed_cleaning_does_not_touch_replaced_or_closed_preview(self):
        self.lua.execute("Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-a');Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-b');Frame(300)")
        self.assertEqual(self.lua.globals().cleaned[101],1)
        self.assertEqual(self.lua.globals().cleaned[102],2)
        self.lua.execute('Stables.Preview.Clear();Frame(1000)')
        self.assertEqual(self.lua.globals().cleaned[102],2)

    def test_same_horse_reuses_entity_and_preserves_motion_and_rotation(self):
        self.lua.execute("Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-a');Stables.Preview.Rotate(1);Frame(50)")
        heading=self.lua.globals().heading
        self.lua.execute("Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-a')")
        self.assertEqual(self.lua.globals().created,1)
        self.assertEqual(self.lua.globals().deleted,0)
        self.assertEqual(self.lua.globals().heading,heading)
        self.lua.execute('Frame(50)')
        self.assertGreater(self.lua.globals().heading,heading)

    def test_another_horse_with_same_model_replaces_preview(self):
        self.lua.execute("Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-a');Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-b');Frame(200)")
        self.assertEqual(self.lua.globals().created,2)
        self.assertEqual(self.lua.globals().deleted,1)

    def test_stale_model_load_never_creates_preview(self):
        self.lua.globals().loaded=False
        self.show()
        self.assertEqual(self.lua.globals().created,0)
        self.assertFalse(self.lua.globals().frozen)

    def test_cleanup_preserves_existing_freeze(self):
        self.lua.globals().frozen=True
        self.show()
        self.lua.execute('Stables.Preview.Clear()')
        self.assertTrue(self.lua.globals().frozen)

    def test_replacement_keeps_only_one_preview(self):
        self.show();self.show()
        self.assertEqual(self.lua.globals().created,2)
        self.assertEqual(self.lua.globals().deleted,1)
        self.lua.execute('Stables.Preview.Clear();Stables.Preview.Clear()')
        self.assertEqual(self.lua.globals().deleted,2)

    def test_rotation_toggles_reverses_and_stops_without_extra_workers(self):
        self.show()
        baseline=self.lua.globals().threadCount
        self.lua.execute('Stables.Preview.Rotate(1);Frame(100);Stables.Preview.Rotate(-1);Frame(100)')
        self.assertAlmostEqual(self.lua.globals().heading,0)
        self.assertEqual(self.lua.globals().threadCount,baseline+1)
        self.lua.execute('Stables.Preview.Rotate(-1);Frame(100)')
        self.assertEqual(self.lua.globals().headingWrites,2)
        self.lua.execute('Stables.Preview.Rotate(1);Frame(100)')
        self.assertEqual(self.lua.globals().threadCount,baseline+2)
        self.assertAlmostEqual(self.lua.globals().heading,3.5)

    def test_rotation_rate_is_time_based_and_long_frame_is_bounded(self):
        self.show()
        self.lua.execute('Stables.Preview.Rotate(1);for i=1,10 do Frame(10) end')
        self.assertAlmostEqual(self.lua.globals().heading,3.5)
        self.lua.execute('Frame(1000)')
        self.assertAlmostEqual(self.lua.globals().heading,7)

    def test_cleared_or_replaced_preview_receives_no_late_rotation(self):
        self.show()
        self.lua.execute('Stables.Preview.Rotate(1);Frame(50)')
        writes=self.lua.globals().headingWrites
        self.show()
        self.lua.execute('Frame(50)')
        self.assertEqual(self.lua.globals().headingWrites,writes)
        self.lua.execute('Stables.Preview.Rotate(1);Stables.Preview.Clear();Frame(50)')
        self.assertEqual(self.lua.globals().headingWrites,writes)

    def test_dissolve_in_and_out_then_delete(self):
        self.lua.execute("Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-a')")
        self.assertEqual(self.lua.globals().alphas[101],0)
        self.lua.execute('Frame(90)')
        self.assertGreater(self.lua.globals().alphas[101],0)
        self.assertLess(self.lua.globals().alphas[101],255)
        self.lua.execute('Frame(90);Stables.Preview.Clear(true)')
        self.assertEqual(self.lua.globals().alphas[101],255)
        self.assertEqual(self.lua.globals().deleted,0)
        self.assertFalse(self.lua.globals().camera)
        self.assertTrue(self.lua.globals().radar)
        self.lua.execute('Frame(90)')
        self.assertLess(self.lua.globals().alphas[101],255)
        self.lua.execute('Frame(90)')
        self.assertEqual(self.lua.globals().deleted,1)

    def test_resource_cleanup_cancels_pending_dissolves_immediately(self):
        self.show()
        self.lua.execute('Stables.Preview.Clear(true);Stables.Preview.Clear();Frame(200)')
        self.assertEqual(self.lua.globals().deleted,1)


if __name__=='__main__':
    unittest.main()
