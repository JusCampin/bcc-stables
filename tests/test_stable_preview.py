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
            cleaned={};dirty={};sexValues={};components={};removals={}
            GetEntityModel=function() return 123 end
            Citizen={InvokeNative=function(hash,entity,expression,value)
                if hash==0xD3A7B003ED343FD9 then components[#components+1]={entity=entity,hash=expression} end
                if hash==0xD710A5007C2AC539 then removals[#removals+1]={entity=entity,category=expression} end
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
        for path in ('config/tack/catalog.lua', 'config/tack/categories/saddles.lua','config/tack/categories/saddlecloths.lua','config/tack/categories/stirrups.lua','config/tack/categories/saddle_horns.lua','config/tack/categories/saddle_bags.lua','config/tack/categories/bedrolls.lua','config/tack/categories/bridles.lua','config/tack/categories/holsters.lua','config/tack/categories/horseshoes.lua','config/tack/categories/masks.lua','config/tack/categories/manes.lua','config/tack/categories/tails.lua','config/tack/categories/mustaches.lua',
                     'shared/tack.lua', 'client/tack/controller.lua', 'client/ui/preview.lua'):
            self.lua.execute((ROOT/path).read_text())

    def show(self):
        self.lua.execute("Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent);Frame(200)")

    def test_saddle_selection_reuses_preview_and_rejects_stale_identity(self):
        self.lua.execute("""
            Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-a')
            saddle=Tack.CatalogBySlot.saddle[1].id
            assert(Stables.Preview.SetSaddle('token','valentine','horse-a',saddle))
            assert(Stables.Preview.SetSaddle('token','valentine','horse-a',saddle))
            assert(not Stables.Preview.SetSaddle('old','valentine','horse-a',saddle))
            assert(not Stables.Preview.SetSaddle('token','valentine','other',saddle))
            assert(not Stables.Preview.SetSaddle('token','valentine','horse-a','invalid'))
        """)
        self.assertEqual(self.lua.globals().created,1)
        self.assertEqual(len(self.lua.globals().components),3)

        self.assertEqual(self.lua.globals().components[1].entity,101)
        self.lua.execute("assert(Stables.Preview.SetSaddle('token','valentine','horse-a',nil))")
        self.assertEqual(len(self.lua.globals().removals),8)
        self.assertEqual(self.lua.globals().removals[4].category,0xBAA7E618)
        self.assertEqual(self.lua.globals().removals[5].category,0x05447332)
        self.assertEqual(self.lua.globals().removals[6].category,0xDA6DADCA)
        self.lua.execute("GetEntityModel=function() return 999 end;assert(not Stables.Preview.SetSaddle('token','valentine','horse-a',saddle))")
        self.assertEqual(len(self.lua.globals().components),3)

    def test_missing_tack_helpers_do_not_break_ordinary_preview_or_cleanup(self):
        self.lua.execute("Tack=nil;HorseAppearance=nil")
        self.show()
        self.lua.execute("Frame(300);Frame(700);assert(not Stables.Preview.CanPreviewTack());assert(not Stables.Preview.SetSaddle('token','valentine','horse-a','invalid'));Stables.Preview.Clear()")
        self.assertEqual(self.lua.globals().deleted,1)
        self.assertTrue(self.lua.globals().radar)

    def test_saddle_survives_delayed_gender_updates_and_cleanup_forgets_entity(self):
        self.lua.execute("""
            Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-a','female')
            saddle=Tack.CatalogBySlot.saddle[1].id
            Stables.Preview.SetSaddle('token','valentine','horse-a',saddle)
            Frame(300);Frame(700)
        """)
        self.assertEqual(len(self.lua.globals().components),9)
        self.lua.execute("Stables.Preview.Clear();Frame(1000);HorseAppearance.applyLoadout(101,{})")
        self.assertEqual(len(self.lua.globals().removals),13)
        self.assertEqual(self.lua.globals().deleted,1)

    def test_saved_saddle_restores_after_temporary_selection(self):
        self.lua.execute("""
            saved=Tack.CatalogBySlot.saddle[1].id
            Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-a','female',{saddle={catalogId=saved}})
            Stables.Preview.SetSaddle('token','valentine','horse-a',Tack.CatalogBySlot.saddle[2].id)
            Stables.Preview.RestoreTack('token','valentine','horse-a')
        """)
        self.assertEqual(self.lua.globals().components[7].hash,self.lua.globals().Tack.CatalogBySlot.saddle[1].hash)
        self.assertEqual(self.lua.globals().created,1)

    def test_swapping_saddle_clears_implicit_parts_and_reapplies_explicit_choices(self):
        self.lua.execute("""
            HorseAppearance.applyLoadout(101,{saddle={catalogId=Tack.CatalogBySlot.saddle[1].id}})
            Tack.Catalog.test_stirrup={id='test_stirrup',slot='stirrups',hash=1234}
            Tack.Catalog.test_horn={id='test_horn',slot='saddle_horn',hash=5678}
            HorseAppearance.applyLoadout(101,{saddle={catalogId=Tack.CatalogBySlot.saddle[2].id},
                stirrups={catalogId='test_stirrup'},saddle_horn={catalogId='test_horn'}})
        """)
        self.assertEqual(self.lua.globals().components[5].hash,1234)
        self.assertEqual(self.lua.globals().components[6].hash,5678)
        removed=[v.category for v in self.lua.globals().removals.values()]
        self.assertEqual(removed.count(0x05447332),3)
        self.assertEqual(removed.count(0xDA6DADCA),3)

    def test_assembly_preview_applies_once_restores_and_invalid_parts_are_atomic(self):
        self.lua.execute("""
            Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-a','male',
                {saddle={catalogId=Tack.CatalogBySlot.saddle[1].id}})
            local parts={stirrups={catalogId=Tack.CatalogBySlot.stirrups[2].id},saddle_horn={catalogId=Tack.CatalogBySlot.saddle_horn[2].id}}
            before=#components
            assert(Stables.Preview.SetAssembly('token','valentine','horse-a',Tack.CatalogBySlot.saddle[2].id,parts))
            assert(#components==before+3)
            assert(components[#components-1].hash==Tack.CatalogBySlot.stirrups[2].hash)
            before=#components
            assert(Stables.Preview.SetAssembly('token','valentine','horse-a',Tack.CatalogBySlot.saddle[2].id,parts))
            assert(#components==before)
            parts.saddle_horn.catalogId='invalid'
            assert(not Stables.Preview.SetAssembly('token','valentine','horse-a',Tack.CatalogBySlot.saddle[1].id,parts))
            assert(#components==before)
            Stables.Preview.RestoreTack('token','valentine','horse-a')
            assert(components[#components-2].hash==Tack.CatalogBySlot.saddle[1].hash)
        """)

    def test_default_parts_are_stable_and_custom_parts_override_them(self):
        self.lua.execute("""
            for n=1,3 do
                HorseAppearance.applyLoadout(101,{saddle={catalogId=Tack.CatalogBySlot.saddle[n].id}})
                assert(components[#components-1].hash==0x03B3AB08)
                assert(components[#components].hash==0x107D9598)
            end
            HorseAppearance.applyLoadout(101,{})
            before=#components
            HorseAppearance.applyLoadout(101,{})
            assert(#components==before)
        """)

    def test_complete_loadout_applies_in_order_and_category_changes_reuse_entity(self):
        self.lua.execute("""
            saved={}
            for _,slot in ipairs(Tack.PieceOrder) do saved[slot]={catalogId=Tack.CatalogBySlot[slot][1].id} end
            Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-a','male',saved)
        """)
        for index,slot in enumerate(('saddlecloth','saddle','stirrups','saddlebag','mane','tail','saddle_horn','bedroll','mask','mustache','holster','bridle','horseshoes'),1):
            self.assertEqual(self.lua.globals().components[index].hash,self.lua.globals().Tack.CatalogBySlot[slot][1].hash)
        self.lua.execute("Stables.Preview.SetTack('token','valentine','horse-a','saddlecloth',Tack.CatalogBySlot.saddlecloth[2].id);Stables.Preview.RestoreTack('token','valentine','horse-a')")
        self.assertEqual(self.lua.globals().created,1)
        self.assertEqual(self.lua.globals().components[27].hash,self.lua.globals().Tack.CatalogBySlot.saddlecloth[1].hash)

    def test_tail_and_saddlecloth_have_distinct_removal_categories(self):
        self.lua.execute("""
            assert(Tack.GetSlot('tail').category==0xA63CAE10)
            assert(Tack.GetSlot('tail').category~=Tack.GetSlot('saddlecloth').category)
            Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-a')
            for _,slot in ipairs({'saddlebag','bedroll','holster'}) do
                assert(not Stables.Preview.SetTack('token','valentine','horse-a',slot,Tack.CatalogBySlot[slot][1].id))
            end
        """)

    def test_parentless_dependent_preview_is_refused_and_clearing_parent_removes_parts(self):
        self.lua.execute("""
            Stables.Preview.Show('token','valentine','a_c_horse_morgan_bay',IsCurrent,'horse-a')
            assert(not Stables.Preview.SetTack('token','valentine','horse-a','stirrups',Tack.CatalogBySlot.stirrups[1].id))
            Stables.Preview.SetTack('token','valentine','horse-a','saddle',Tack.CatalogBySlot.saddle[1].id)
            Stables.Preview.SetTack('token','valentine','horse-a','stirrups',Tack.CatalogBySlot.stirrups[1].id)
            Stables.Preview.SetTack('token','valentine','horse-a','saddle_horn',Tack.CatalogBySlot.saddle_horn[1].id)
            before=#components
            Stables.Preview.SetTack('token','valentine','horse-a','saddle',nil)
        """)
        self.assertEqual(len(self.lua.globals().components),self.lua.globals().before)

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
