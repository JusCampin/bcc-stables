"""Boot validation and manifest coverage; provider/natives remain isolated."""
import re
import unittest

from lupa.lua54 import LuaRuntime
from test_feather_boundary import ROOT

LEDGER = {
    '001_purchase_foundation':'9472f124', '002_asset_registration':'1c0b2c99',
    '003_call_generations':'34c7cb42', '004_call_bindings':'7b75a419',
    '005_call_process_epochs':'568acc4d', '006_call_recoveries':'b50d161a',
    '007_horse_runtime_projection':'f07263eb', '008_call_horse_state_index':'cc1af751',
    '009_horse_care_foundation':'185c1b14', '010_active_care_targets':'00e0cc8f',
    '011_care_projection_dispatches':'d793ddb4',
}


class BootTest(unittest.TestCase):
    def boot(self, corrupt=False, missing=False):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''
            Stables={}; public={}; handlers={}; installed=false
            RegisterCommand=function() end
            AddEventHandler=function(name,handler) handlers[name]=handler end
            CreateThread=function(fn) boot=fn end
            GetResourceState=function() return 'started' end
            GetCurrentResourceName=function() return 'bcc-stables' end
            json={encode=function() return '{}' end}
            exports=setmetatable({
                ['feather-core']={AwaitReady=function() return {ok=true,value={state='ready'}} end,
                    GetCapabilities=function() return {ok=true,value={contract=1,state='ready'}} end},
                ['feather-assets']={AwaitReady=function() return {ok=true,value={state='ready'}} end,
                    GetCapabilities=function() return {ok=true,value={contract=1,state='ready'}} end}
            },{__call=function(_,name,fn) public[name]=fn end})
            DB={awaitReady=function() return true end,query=function(sql)
                assert(sql=='SELECT id,checksum,state FROM fs_schema_migrations')
                return ledger
            end}
        ''')
        ledger=[{'id':key,'checksum':'fnv1a32:'+value,'state':'applied'} for key,value in LEDGER.items()]
        if corrupt:
            ledger[-1]['checksum']='edited'
        if missing:
            ledger.pop()
        lua.globals().ledger=lua.table_from(ledger,recursive=True)
        lua.execute((ROOT/'server/core/feather.lua').read_text(encoding='utf-8-sig'))
        lua.execute("Stables.HorseController={Install=function() installed=true; return {ok=true,value=true} end}")
        lua.execute((ROOT/'server/core/boot.lua').read_text(encoding='utf-8-sig'))
        lua.globals().boot()
        return lua

    def test_existing_schema_starts_without_migrations(self):
        lua=self.boot()
        self.assertTrue(lua.globals().installed)
        self.assertEqual(lua.globals().public.GetHealth()['value']['state'],'ready')

    def test_mismatched_ledger_refuses_runtime_without_writes(self):
        lua=self.boot(corrupt=True)
        self.assertFalse(lua.globals().installed)
        self.assertEqual(lua.globals().public.GetHealth()['value']['code'],'schema_incompatible')

    def test_incomplete_schema_refuses_runtime(self):
        lua=self.boot(missing=True)
        self.assertFalse(lua.globals().installed)

    def test_manifest_files_exist_and_compile(self):
        manifest=(ROOT/'fxmanifest.lua').read_text(encoding='utf-8-sig')
        self.assertNotIn('vorp',manifest.lower())
        self.assertNotIn('oxmysql',manifest.lower())
        lua=LuaRuntime()
        for section in ('shared_scripts','client_scripts','server_scripts'):
            body=re.search(section+r'\s*\{([^}]+)\}',manifest,re.S).group(1)
            for path in re.findall(r"'([^']+)'",body):
                if path.startswith('@'):
                    continue
                with self.subTest(path=path):
                    self.assertTrue((ROOT/path).is_file())
                    lua.compile((ROOT/path).read_text(encoding='utf-8-sig'),name=path)


if __name__=='__main__':
    unittest.main()
