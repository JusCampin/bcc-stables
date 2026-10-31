import unittest
from lupa.lua54 import LuaRuntime
from test_feather_boundary import ROOT
import test_bonding_client as bonding


class XpNotificationsTest(unittest.TestCase):
    def test_shared_notify_keeps_console_and_presents_optional_notification(self):
        lua=LuaRuntime();lua.execute('''prints=0;shown=0;print=function() prints=prints+1 end
            GetResourceState=function() return 'started' end
            exports={['feather-notify']={ShowNotification=function(_,p) assert(p.style=='right' and p.duration==4000);shown=shown+1 end}}''')
        lua.execute((ROOT/'client/core/feather.lua').read_text(encoding='utf-8'))
        lua.execute("Stables.Client.Notify('XP');exports['feather-notify'].ShowNotification=function() error('offline') end;Stables.Client.Notify('XP')")
        self.assertEqual(lua.globals().shown,1);self.assertEqual(lua.globals().prints,2)
    def test_travel_and_level_notifications_honor_separate_toggles(self):
        h=bonding.BondingClientTest();h.setUp();lua=h.lua
        lua.execute('''shown={};Stables.Client.Notify=function(s) shown[#shown+1]=s end
            earned={generationId=r.generationId,horseId=r.id,reason='riding',amount=10,xp=1000,training={level=1},levelsGained=1}
            events['bcc-stables:bonding:earned'](earned)''')
        self.assertEqual(len(lua.globals().shown),2)
        lua.execute("Config.bonding.showXpMessage=false;events['bcc-stables:bonding:earned'](earned)")
        self.assertEqual(len(lua.globals().shown),3)
        lua.execute("Config.bonding.showLevelUpMessage=false;events['bcc-stables:bonding:earned'](earned)")
        self.assertEqual(len(lua.globals().shown),3)
