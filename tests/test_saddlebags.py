"""Saddlebag storage uses bound horse identity, current custody and existing UI."""
import unittest
from lupa.lua54 import LuaRuntime
from test_feather_boundary import ROOT

class SaddlebagsTest(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            Config={saddlebags={enabled=true,slots=50,maxWeight=250}}
            live=true;distance=1;occupied=false
            session={characterId='owner',source=3}
            horse={entity=11,tack={saddlebag={instanceId=186}}}
            Stables={Tack={Enabled=function() return true end},Feather={}}
            local F=Stables.Feather
            F.Ok=function(v) return {ok=true,value=v} end
            F.Error=function(c,m) return {ok=false,code=c,message=m} end
            F.RequireSession=function(src) return live and src==3 and F.Ok(session) or F.Error('session_stale') end
            F.Call=function(resource,method,name,fn,opts) handler=fn;return F.Ok(true) end
            Stables.HorseController={MovementRecord=function(s) return live and horse or nil end,
                CheckCareOccupancy=function(s,r,mounted) assert(mounted==false);return not occupied end}
            GetPlayerPed=function() return 22 end;DoesEntityExist=function() return true end
            GetEntityCoords=function(e) return {x=e==11 and 0 or distance,y=0,z=0} end
            exports={['feather-inventory']={
                RegisterCollectionStorage=function(_,p) registration=p;return F.Ok(true) end,
                OpenCollectionStorage=function(_,p) opens=(opens or 0)+1;opened=p;return F.Ok(true) end,
                GetCollectionStorage=function(_,p) return F.Ok({itemCount=2}) end}}
        """)
        self.lua.execute((ROOT/'server/horse/saddlebags.lua').read_text(encoding='utf-8'))
        self.assertTrue(self.lua.globals().Stables.Saddlebags.Start().ok)
    def test_defaults_and_live_access_ignore_network_owner(self):
        g=self.lua.globals();self.assertEqual(g.registration.slots,50);self.assertEqual(g.registration.maxWeight,250)
        self.assertTrue(g.registration.validate(3,186,'read'))
        self.assertFalse(g.registration.validate(3,999,'read'))
        self.assertTrue(g.handler(self.lua.table(),3).ok)
        self.assertEqual(g.opened.instanceId,186);self.assertEqual(g.opened.characterId,'owner')
        self.lua.execute('distance=4');self.assertFalse(g.registration.validate(3,186,'read'))
        self.assertFalse(g.handler(self.lua.table(),3).ok);self.assertEqual(g.opens,1)
    def test_stale_removed_occupied_and_care_refuse(self):
        g=self.lua.globals()
        for change,restore in [('live=false','live=true'),('horse.tack.saddlebag=nil','horse.tack.saddlebag={instanceId=186}'),('occupied=true','occupied=false'),('horse.care={}','horse.care=nil')]:
            self.lua.execute(change);self.assertFalse(g.handler(self.lua.table(),3).ok);self.lua.execute(restore)
        self.assertIsNone(g.opens)
    def test_disabled_open_preserves_summary_for_trade_disclosure(self):
        self.lua.execute('Config.saddlebags.enabled=false')
        g=self.lua.globals();self.assertFalse(g.registration.validate(3,186,'read'))
        self.assertEqual(g.Stables.Saddlebags.Summary(g.session,186).value.itemCount,2)
    def test_registration_failure_keeps_original_export_error(self):
        self.lua.execute("exports['feather-inventory'].RegisterCollectionStorage=function() error('No such export RegisterCollectionStorage') end")
        result=self.lua.globals().Stables.Saddlebags.Start()
        self.assertFalse(result.ok)
        self.assertIn('No such export RegisterCollectionStorage',result.message)

    def test_registration_refusal_keeps_provider_code_and_message(self):
        self.lua.execute("exports['feather-inventory'].RegisterCollectionStorage=function() return {ok=false,error={code='invalid_input',message='Storage item is not trusted'}} end")
        result=self.lua.globals().Stables.Saddlebags.Start()
        self.assertEqual(result.code,'invalid_input')
        self.assertIn('Storage item is not trusted',result.message)

    def test_removed_saddle_styles_are_absent(self):
        self.lua.execute((ROOT/'config/tack/catalog.lua').read_text(encoding='utf-8'))
        self.lua.execute((ROOT/'config/tack/categories/saddles.lua').read_text(encoding='utf-8'))
        labels={row.label for row in self.lua.globals().HorseComp.Saddles.values()}
        for number in (19,27,47,48):self.assertNotIn('Saddle '+str(number),labels)

if __name__=='__main__':unittest.main()
