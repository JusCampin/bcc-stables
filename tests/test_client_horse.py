"""Client protocol/native simulations; these cannot certify RedM native behavior."""
import unittest

from lupa.lua54 import LuaRuntime
from test_feather_boundary import ROOT

CLIENT = r'''
handlers,commands,public={}, {}, {}
clock,createCount,reveals,deleteCount=0,0,0,0
saddle,mount,leadingHorse=0,0,0
cores={}; entities={};sexValues={};sexAppliedAt=nil
GetResourceState=function() return 'started' end
GetGameTimer=function() return clock end
Wait=function(ms) clock=clock+ms; if waitHook then waitHook() end end
GetCurrentResourceName=function() return 'bcc-stables' end
PlayerId=function() return 3 end
PlayerPedId=function() return 10 end
GetHashKey=function() return 101 end
DoesEntityExist=function(e) return entities[e] and entities[e].exists==true or false end
GetEntityModel=function(e) return entities[e].model end
NetworkGetNetworkIdFromEntity=function(e) return entities[e].netId end
NetworkGetEntityFromNetworkId=function(id) return id==55 and 100 or 0 end
NetworkGetEntityIsNetworked=function() return true end
NetworkHasControlOfEntity=function() return true end
CreatePed=function(hash,x,y,z,heading)
    createCount=createCount+1
    local state={}; state.set=function(self,key,value) self[key]=value end
    entities[100]={exists=true,model=hash,netId=55,state=state,coords={x=x,y=y,z=z},frozen=false}
    return 100
end
Entity=function(e) return entities[e] end
GetEntityCoords=function(e) return entities[e].coords end
SetEntityAsMissionEntity=function() end
SetEntityVisible=function(e,value) entities[e].visible=value; if value then reveals=reveals+1 end end
FreezeEntityPosition=function(e,value) entities[e].frozen=value end
SetEntityInvincible=function() end
SetBlockingOfNonTemporaryEvents=function() end
SetModelAsNoLongerNeeded=function() end
HasCollisionLoadedAroundEntity=function() return true end
ClearPedTasksImmediately=function() end
TaskStandStill=function() end
IsEntityInAir=function() return false end
IsPedFalling=function() return false end
IsPedOnMount=function() return mounted==true end
GetRiderOfMount=function(_,flag) assert(type(flag)=='boolean'); return mounted and 10 or 0 end
DeleteEntity=function(e) entities[e].exists=false; deleteCount=deleteCount+1 end
Citizen={ResultAsInteger=function() return 0 end,InvokeNative=function(hash,a,b,c)
    if hash==0x5653AB26C82938CF then sexValues[#sexValues+1]=c;sexAppliedAt=clock;return end
    if hash==0xB48050D326E9A2F3 then return saddle end
    if hash==0x46FA0AE18F4C7FA9 then return mount end
    if hash==0xD2CB0FB0FDCB473D then saddle=b; if b~=0 then mount=b end; return end
    if hash==0x8FBF9EDB378CCB8C then mount=b; return end
    if hash==0xEFC4303DDC6E60D3 then return leadingHorse~=0 end
    if hash==0xED1F514AF4732258 then return leadingHorse end
    if hash==0xED27560703F37258 then leadingHorse=0; return end
    if hash==0xAC5045AB7F1A34FD then return leadingHorse==a end
    if hash==0xC6258F41D86676E0 then cores[b]=c; return end
    return 0
end}
RegisterNetEvent=function(name,handler) handlers[name]=handler end
RegisterCommand=function(name,handler) commands[name]=handler end
AddEventHandler=function(name,handler) handlers[name]=handler end
CreateThread=function(handler) handler() end
exports=setmetatable({
    ['feather-toolkit']={LoadModel=function()
        if cancelModelLoad then source=65535; handlers['bcc-stables:call:cancel'](spec.generationId) end
        return {ok=true,value={hash=101}}
    end},
    ['feather-core']={CallRPC=function(_,name,p,callback)
        if name:find('.accept.',1,true) then
            if refuseAccept then callback({ok=false,code='stale_call'}); return end
            callback({ok=true,value={generationId=p.generationId}})
        elseif name:find('.bind.',1,true) then
            if cancelDuringBind then
                pendingCallback=callback
                waitHook=function()
                    source=65535; handlers['bcc-stables:call:cancel'](spec.generationId)
                    callback({ok=true,value={generationId=p.generationId,horseId=spec.horseId,netId=55,state='active'}})
                    waitHook=nil
                end
            elseif refuseBind then callback({ok=false,code='call_outcome_unknown'})
            else callback({ok=true,value={generationId=p.generationId,horseId=spec.horseId,netId=55,state='active',
                condition={healthCore=90,staminaCore=80,revision=1}}}) end
        elseif name:find('.store_check_result.',1,true) then occupancy=p.occupied; callback({ok=true,value=true})
        else callback({ok=true,value={state='released'}}) end
    end}
},{__call=function(_,name,handler) public[name]=handler end})
spec={generationId='2448f362-cf06-11f1-9ad4-e0d55eaa2deb',
    observerId='3ed76477-ce80-11f1-9ad4-e0d55eaa2deb',horseId='cd6d38f3-ce7f-11f1-9ad4-e0d55eaa2deb',
    modelKey='a_c_horse_morgan_bay',position={x=3,y=0,z=0,heading=0}}
function CreateFromServer() source=65535; handlers['bcc-stables:call:create'](spec) end
'''


class ClientHorseTest(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(CLIENT)
        for path in ('config/settings.lua','client/core/feather.lua','client/horse/controller.lua'):
            self.lua.execute((ROOT/path).read_text(encoding='utf-8-sig'))

    def test_ready_rideable_and_condition_restored(self):
        self.lua.execute('CreateFromServer()')
        self.assertEqual(self.lua.globals().createCount,1)
        self.assertEqual(self.lua.globals().reveals,1)
        self.assertFalse(self.lua.globals().entities[100]['frozen'])
        self.assertEqual(self.lua.globals().cores[0],90)
        self.assertEqual(self.lua.globals().cores[1],80)
        self.assertIsNotNone(self.lua.globals().public.GetActiveHorse())

    def test_saved_tack_applies_on_bound_physical_horse(self):
        self.lua.execute('''
            HorseAppearance={applyLoadout=function(entity,loadout)
                assert(entity==100 and loadout.saddle.catalogId=='saved-saddle')
                tackApplied=true;return true
            end,resetTracking=function() end}
            local call=exports['feather-core'].CallRPC
            exports['feather-core'].CallRPC=function(self,route,p,callback)
                call(self,route,p,function(result)
                    if route:find('.bind.',1,true) then result.value.tack={saddle={catalogId='saved-saddle'}} end
                    callback(result)
                end)
            end
            CreateFromServer()
        ''')
        self.assertTrue(self.lua.globals().tackApplied)
        self.assertEqual(self.lua.globals().reveals,1)

    def test_saved_sex_applies_after_settling_before_reveal(self):
        self.lua.execute("spec.gender='female';CreateFromServer()")
        self.assertEqual(self.lua.globals().sexValues[1],1)
        self.assertGreaterEqual(self.lua.globals().sexAppliedAt,750)
        self.assertEqual(self.lua.globals().reveals,1)

    def test_local_event_cannot_spawn(self):
        self.lua.execute("source=3; handlers['bcc-stables:call:create'](spec)")
        self.assertEqual(self.lua.globals().createCount,0)

    def test_expired_server_instruction_refused_before_create(self):
        self.lua.execute('refuseAccept=true; CreateFromServer()')
        self.assertEqual(self.lua.globals().createCount,0)

    def test_cancel_during_model_load_prevents_creation(self):
        self.lua.execute('cancelModelLoad=true; CreateFromServer()')
        self.assertEqual(self.lua.globals().createCount,0)

    def test_unknown_bind_outcome_never_reveals_horse(self):
        self.lua.execute('refuseBind=true; CreateFromServer()')
        self.assertEqual(self.lua.globals().createCount,1)
        self.assertEqual(self.lua.globals().reveals,0)
        self.assertIsNone(self.lua.globals().public.GetActiveHorse())

    def test_cancel_during_bind_prevents_late_reveal(self):
        self.lua.execute('cancelDuringBind=true; CreateFromServer()')
        self.assertEqual(self.lua.globals().reveals,0)
        self.assertIsNone(self.lua.globals().public.GetActiveHorse())

    def test_retired_generation_is_not_replayed(self):
        self.lua.execute("source=65535; handlers['bcc-stables:call:cancel'](spec.generationId); CreateFromServer()")
        self.assertEqual(self.lua.globals().createCount,0)

    def test_cancel_clears_only_our_links_without_deleting(self):
        self.lua.execute("CreateFromServer(); source=65535; handlers['bcc-stables:call:cancel'](spec.generationId)")
        self.assertEqual(self.lua.globals().saddle,0)
        self.assertEqual(self.lua.globals().mount,0)
        self.assertEqual(self.lua.globals().deleteCount,0)

    def test_stop_preserves_foreign_associations(self):
        self.lua.execute("CreateFromServer(); saddle=200; mount=200; handlers.onResourceStop('bcc-stables')")
        self.assertEqual(self.lua.globals().saddle,200)
        self.assertEqual(self.lua.globals().mount,200)
        self.assertEqual(self.lua.globals().deleteCount,1)

    def test_occupancy_reply_works_on_simulator_without_active_owner_record(self):
        self.lua.execute('''
            CreateFromServer()
            source=65535
            handlers['bcc-stables:call:store_check']({generationId=spec.generationId,observerId=spec.observerId,
                netId=55,sequence=1,modelKey=spec.modelKey})
        ''')
        self.assertFalse(self.lua.globals().occupancy)
        self.lua.execute('''
            mounted=true
            handlers['bcc-stables:call:store_check']({generationId=spec.generationId,observerId=spec.observerId,
                netId=55,sequence=2,modelKey=spec.modelKey})
        ''')
        self.assertTrue(self.lua.globals().occupancy)

    def test_rpc_ignores_replies_after_timeout(self):
        self.lua.execute('''
            exports['feather-core'].CallRPC=function(_,name,p,callback) late=callback end
            result=Stables.Client.Rpc('request',{})
            late({ok=true,value={state='submitting'}})
        ''')
        self.assertFalse(self.lua.globals().result['ok'])
        self.assertEqual(self.lua.globals().result['code'],'timeout')

    def test_client_and_server_execute_complete_protocol_with_real_sql(self):
        import test_horse_controller as server_fixture
        server=server_fixture.HorseControllerTest('test_call_bind_store_normal_flow')
        server.setUp()
        try:
            server.db.execute('INSERT INTO fs_horse_condition VALUES (?,90,80,1,1)',
                              ('cd6d38f3-ce7f-11f1-9ad4-e0d55eaa2deb',))
            server.db.commit()
            original_create=self.lua.globals().CreatePed
            original_delete=server.lua.globals().DeleteEntity

            def create(*args):
                entity=original_create(*args)
                server.lua.execute('''
                    entities[100]={exists=true,coords={x=3,y=0,z=0},netId=55,owner=3,model=101,state={}}
                    Stables.HorseController.EntityCreated(100)
                ''')
                state=self.lua.globals().entities[100]['state']
                def set_state(owner,key,value,*_):
                    owner[key]=value
                    server.lua.globals().entities[100]['state'][key]=value
                state['set']=set_state
                return entity

            def delete(entity):
                original_delete(entity)
                self.lua.globals().entities[entity]['exists']=False

            def emit(name,source,payload):
                handler=self.lua.globals().handlers[name]
                if handler:
                    self.lua.globals().source=65535
                    converted=server_fixture.plain(payload)
                    if isinstance(converted,dict): converted=self.lua.table_from(converted,recursive=True)
                    handler(converted)

            def rpc(_,name,payload,callback,*__):
                action=name.split('.')[-2]
                p=server.lua.table_from(server_fixture.plain(payload),recursive=True)
                method={'request':'Call','accept':'Accept','bind':'Bind','store_current':'Store',
                        'store_check_result':'OccupancyResult'}[action]
                result=getattr(server.controller,method)(3) if method in ('Call','Store') else getattr(server.controller,method)(3,p)
                callback(self.lua.table_from(server_fixture.plain(result),recursive=True))

            self.lua.globals().CreatePed=create
            server.lua.globals().DeleteEntity=delete
            server.lua.globals().TriggerClientEvent=emit
            self.lua.globals().exports['feather-core']['CallRPC']=rpc
            self.lua.globals().Stables.Horse.Call()
            self.assertEqual(server.case.scalar('SELECT state FROM fs_call_leases'),'active')
            self.assertIsNotNone(self.lua.globals().Stables.Horse.GetActive())
            self.assertEqual(self.lua.globals().cores[0],90)
            self.lua.globals().Stables.Horse.Store()
            self.assertEqual(server.case.scalar('SELECT state FROM fs_call_leases'),'released')
            self.assertEqual(server.case.scalar('SELECT availability FROM fs_horses'),'stored')
            self.assertEqual(self.lua.globals().saddle,0)
            self.assertIsNone(self.lua.globals().Stables.Horse.GetActive())
        finally:
            server.tearDown()


if __name__=='__main__':
    unittest.main()
