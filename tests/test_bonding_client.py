"""Native bonding restoration, current simulator observation and generation fences."""
import unittest
from lupa.lua54 import LuaRuntime
from test_feather_boundary import ROOT
from test_call_repository import HORSE,GEN


class BondingClientTest(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            Config={bonding={enabled=true,showXpMessage=true}};events={};writes={};calls={};messages={};source=65535;clock=0
            Stables={Client={},Horse={}};local C=Stables.Client
            C.Uuid=function(v) return type(v)=='string' and #v==36 end
            C.Text=function(key,...) return key..':'..table.concat({...},',') end
            C.Message=function(message) messages[#messages+1]=message end
            C.Rpc=function(action,p) calls[#calls+1]={action=action,p=p};return {ok=true} end
            CreateThread=function(fn) fn() end;Wait=function(ms) clock=clock+ms end
            GetGameTimer=function() return clock end
            RegisterNetEvent=function(name,fn) events[name]=fn end
            DoesEntityExist=function(e) return e==10 or e==100 end
            NetworkHasControlOfEntity=function() return not noControl end
            NetworkGetEntityFromNetworkId=function(n) return n end
            NetworkGetNetworkIdFromEntity=function(n) return n end
            GetEntityModel=function() return 123 end;GetHashKey=function() return 123 end
            IsEntityDead=function() return dead==true end;IsPedDeadOrDying=function() return dead==true end
            IsPedOnMount=function() return mounted==true end
            GetMount=function() return mounted and 100 or 0 end
            GetRiderOfMount=function() return mounted and 10 or 0 end
            state={bccStablesGeneration="'''+GEN+'''",bccStablesObserver="'''+HORSE+'''"}
            Entity=function() return {state=state} end
            thresholdReads=0
            Citizen={ResultAsInteger=function() return 0 end,InvokeNative=function(hash,...)
                local a={...}
                if hash==0x94A7F191DB49A44D then thresholdReads=thresholdReads+1;return a[3]*50 end
                if hash==0xEFC4303DDC6E60D3 then return leading==true end
                if hash==0xED1F514AF4732258 then return leading and 100 or 0 end
                writes[#writes+1]={hash=hash,args=a}
            end}
            r={entity=100,id="'''+HORSE+'''",generationId="'''+GEN+'''",modelKey='a_c_horse_morgan_bay'}
            Stables.Horse.GetActive=function() return r end
            packet={generationId=r.generationId,observerId="'''+HORSE+'''",netId=100,modelKey=r.modelKey,targetNet=10,sequence=1,bonding={xp=125,revision=3}}
        ''')
        self.lua.execute((ROOT/'client/horse/bonding.lua').read_text(encoding='utf-8'))
    def test_restores_absolute_bonding_and_unlock_flags_without_writing_cores(self):
        self.lua.execute("assert(Stables.HorseBonding.Apply(r,packet.bonding))")
        writes=list(self.lua.globals().writes.values())
        self.assertEqual(writes[0].hash,0x09A59688C26D88DF)
        self.assertEqual(tuple(writes[0].args.values()),(100,7,125))
        self.assertEqual(tuple(writes[1].args.values()),(100,113,True))
        self.assertEqual(tuple(writes[2].args.values()),(100,312,False))
        self.assertFalse(any(w.hash==0xC6258F41D86676E0 or w.hash==0x5DA12E025D47D4E5 for w in writes))
        self.lua.execute('Stables.HorseBonding.Describe(r.modelKey,125)')
        self.assertEqual(self.lua.globals().thresholdReads,4)
    def test_observer_reports_only_current_riding_or_leading_and_no_xp_amount(self):
        self.lua.execute("mounted=true;events['bcc-stables:bonding:observe'](packet)")
        p=self.lua.globals().calls[1].p
        self.assertEqual(p.mode,'riding');self.assertIsNone(p.amount)
        self.lua.execute("mounted=false;leading=true;events['bcc-stables:bonding:observe'](packet)")
        self.assertEqual(self.lua.globals().calls[2].p.mode,'leading')
    def test_foreign_event_wrong_identity_and_missing_control_do_not_mutate_or_report(self):
        for setup in ("source=1", "source=65535;state.bccStablesGeneration='wrong'", "state.bccStablesGeneration=r.generationId;noControl=true"):
            self.lua.execute(setup+";events['bcc-stables:bonding:observe'](packet)")
        self.assertEqual(len(self.lua.globals().calls),0);self.assertEqual(len(self.lua.globals().writes),0)
    def test_expired_owner_notification_does_not_target_a_replacement_horse(self):
        self.lua.execute("events['bcc-stables:bonding:earned']({generationId=r.generationId,horseId=r.id,amount=10,reason='riding',xp=125})")
        self.assertEqual(len(self.lua.globals().messages),1)
        self.lua.execute("r.generationId='replacement';events['bcc-stables:bonding:earned']({generationId=packet.generationId,horseId=r.id,amount=10,reason='riding',xp=125})")
        self.assertEqual(len(self.lua.globals().messages),1)
