"""Native-controller simulations backed by the actual lifecycle SQL repository."""
import json
import unittest

from lupa.lua54 import lua_type
import test_call_repository as lifecycle


def plain(value):
    if lua_type(value) != 'table':
        return value
    keys = list(value.keys())
    if keys and set(keys) == set(range(1, len(keys)+1)):
        return [plain(value[i]) for i in range(1, len(keys)+1)]
    return {str(key): plain(value[key]) for key in keys}


NATIVES = r'''
time, deleteCount, autoOccupancy, deleteDeferred = 0, 0, false, false
convars={bcc_stables_process_epoch_v1="''' + lifecycle.EPOCH + r'''"}
GetConvar=function(key,fallback) return convars[key] or fallback end
SetConvar=function(key,value) convars[key]=value end
GetGameTimer=function() return time end
Wait=function(ms) time=time+ms; if waitHook then waitHook() end end
GetCurrentResourceName=function() return 'bcc-stables' end
GetPlayerRoutingBucket=function() return 0 end
GetPlayerPed=function() return 1 end
entities={ [1]={exists=true,coords={x=0,y=0,z=0},netId=1,owner=3,model=1,state={}} }
DoesEntityExist=function(e) return entities[e] and entities[e].exists==true or false end
NetworkGetEntityFromNetworkId=function(id)
    for e,v in pairs(entities) do if v.netId==id and v.exists then return e end end
    return 0
end
NetworkGetNetworkIdFromEntity=function(e) return entities[e].netId end
NetworkGetEntityOwner=function(e) return entities[e].owner end
GetEntityModel=function(e) return entities[e].model end
GetHashKey=function() return 101 end
GetEntityRoutingBucket=function() return 0 end
GetEntityScript=function() return 'bcc-stables' end
GetEntityCoords=function(e) return entities[e].coords end
GetEntityHeading=function() return 0 end
Entity=function(e) return entities[e] end
DeleteEntity=function(e)
    deleteCount=deleteCount+1
    if not deleteDeferred then entities[e].exists=false end
end
TriggerClientEvent=function(name,source,p)
    if name=='bcc-stables:call:create' then sent=p; createCount=(createCount or 0)+1 end
    if name=='bcc-stables:call:store_check' and autoOccupancy then
        local reply={generationId=p.generationId,sequence=p.sequence,occupied=occupied==true}
        if p.care and not omitCareLife then reply.ownerAlive=not careOwnerDead;reply.horseAlive=not careHorseDead end
        if p.condition then reply.healthCore=70;reply.staminaCore=60;reply.appliedRevision=0 end
        Stables.HorseController.OccupancyResult(source,reply)
    end
end
function SpawnCandidate(observed)
    entities[100]={exists=true,coords={x=3,y=0,z=0},netId=55,owner=3,model=101,
        state={bccStablesGeneration=sent.generationId,bccStablesObserver=sent.observerId}}
    if observed then Stables.HorseController.EntityCreated(100) end
end
'''


class HorseControllerTest(unittest.TestCase):
    def setUp(self):
        self.case = lifecycle.CallRepositoryTest('test_complete_lifecycle_and_idempotent_cleanup')
        self.case.setUp()
        self.lua, self.db = self.case.lua, self.case.db
        self.db.execute('ALTER TABLE fs_asset_registrations ADD COLUMN asset_revision INTEGER DEFAULT 1')
        self.db.execute('ALTER TABLE fs_asset_registrations ADD COLUMN request_id TEXT')
        self.db.execute('UPDATE fs_asset_registrations SET request_id=?', ('stables.register:'+lifecycle.HORSE,))
        self.db.commit()
        db = self.lua.globals().DB
        db['query'] = self.query
        db['value'] = lambda *_: lifecycle.EPOCH
        def one(sql, *params):
            if sql.startswith('SELECT UUID()'):
                return self.lua.table_from({'generation_id': lifecycle.GEN, 'observer_id': lifecycle.ASSET})
            return self.case.one(sql, *params)
        db['one'] = one
        self.lua.globals().json = self.lua.table_from({
            'encode': lambda value: json.dumps(plain(value)),
            'decode': lambda text: self.lua.table_from(json.loads(text), recursive=True),
        })
        self.lua.execute(NATIVES)
        self.lua.execute((lifecycle.ROOT/'server/horse/owned_repository.lua').read_text(encoding='utf-8-sig'))
        self.reload()
        self.assertTrue(self.controller.Start()['ok'])

    def tearDown(self):
        self.case.tearDown()

    def query(self, sql, *params):
        rows = self.db.execute(sql, params).fetchall()
        return self.lua.table_from([self.lua.table_from(dict(row)) for row in rows])

    def reload(self):
        self.lua.execute((lifecycle.ROOT/'server/horse/controller.lua').read_text(encoding='utf-8-sig'))
        self.controller = self.lua.globals().Stables.HorseController

    def call_and_bind(self):
        self.assertTrue(self.controller.Call(3)['ok'])
        self.accept()
        self.lua.execute('SpawnCandidate(true)')
        payload=self.lua.table_from({'generationId': lifecycle.GEN, 'netId': 55})
        self.assertTrue(self.controller.Bind(3,payload)['ok'])

    def accept(self):
        return self.controller.Accept(3,self.lua.table_from({'generationId':lifecycle.GEN,'observerId':lifecycle.ASSET}))

    def prepare_relocation(self):
        self.call_and_bind()
        self.lua.execute('entities[1].coords.x=200; autoOccupancy=true')
        previous=self.lua.globals().DB.one
        new_id='641d1d56-d0cf-11f1-9ad4-e0d55eaa2deb'
        observer='3ed76477-ce80-11f1-9ad4-e0d55eaa2dec'
        def one(sql,*params):
            if sql.startswith('SELECT UUID()'):
                return self.lua.table_from({'generation_id':new_id,'observer_id':observer})
            return previous(sql,*params)
        self.lua.globals().DB['one']=one
        return new_id,observer

    def test_call_bind_store_normal_flow(self):
        self.call_and_bind()
        self.lua.execute('autoOccupancy=true')
        self.assertTrue(self.controller.Store(3)['ok'])
        self.assertEqual(self.case.scalar('SELECT COUNT(*) FROM fs_call_slots'), 0)
        self.assertEqual(self.lua.globals().createCount, 1)
        self.assertEqual(self.lua.globals().deleteCount, 1)

    def test_target_menu_store_refuses_an_old_generation_and_keeps_current_horse(self):
        self.call_and_bind();self.lua.execute('autoOccupancy=true')
        result=self.controller.Store(3,None,'77777777-7777-4777-8777-777777777777')
        self.assertEqual(result.code,'stale_call')
        self.assertEqual(self.lua.globals().deleteCount,0)
        self.assertEqual(self.case.scalar('SELECT state FROM fs_call_leases'),'active')
        self.assertTrue(self.controller.Store(3,None,self.lua.globals().sent.generationId).ok)
        self.assertEqual(self.lua.globals().deleteCount,1)

    def test_care_observation_uses_current_simulator_and_requires_life_facts(self):
        self.call_and_bind();self.lua.execute('autoOccupancy=true;entities[100].owner=4')
        session=self.lua.globals().session
        record=self.controller.MovementRecord(session)
        self.assertTrue(self.controller.CheckCareOccupancy(session,record))
        self.lua.execute('omitCareLife=true')
        self.assertEqual(self.controller.CheckCareOccupancy(session,record),(False,'care_observation_unknown'))
        self.assertIsNone(record['storeCheck'])

    def test_care_observation_distinguishes_dead_and_occupied(self):
        self.call_and_bind();self.lua.execute('autoOccupancy=true;careHorseDead=true')
        session=self.lua.globals().session;record=self.controller.MovementRecord(session)
        self.assertEqual(self.controller.CheckCareOccupancy(session,record),(False,'care_life'))
        self.lua.execute('careHorseDead=false;occupied=true')
        self.assertEqual(self.controller.CheckCareOccupancy(session,record),(False,'care_occupied'))

    def test_failed_condition_checkpoint_retains_active_horse(self):
        self.call_and_bind()
        self.lua.execute('''
            autoOccupancy=true
            Stables.Feeding={Capture=function(session,r,cores,authorize)
                assert(cores.staminaCore==60 and authorize())
                return {ok=false,code='care_pending',message='Save failed'}
            end}
        ''')
        self.assertEqual(self.controller.Store(3)['code'],'care_pending')
        self.assertEqual(self.lua.globals().deleteCount,0)
        self.assertEqual(self.case.scalar('SELECT state FROM fs_call_leases'),'active')

    def test_existing_entity_with_copied_markers_cannot_bind(self):
        self.controller.Call(3)
        self.accept()
        self.lua.execute('SpawnCandidate(false)')
        reply=self.controller.Bind(3,self.lua.table_from({'generationId': lifecycle.GEN,'netId':55}))
        self.assertEqual(reply['code'], 'entity_not_observed')
        self.assertEqual(self.case.scalar('SELECT state FROM fs_call_leases'), 'submitting')
        self.assertEqual(self.lua.globals().deleteCount, 0)

    def test_network_owner_migration_allows_store_via_current_simulator(self):
        self.call_and_bind()
        self.lua.execute('entities[100].owner=4; autoOccupancy=true')
        self.assertTrue(self.controller.Store(3)['ok'])
        self.assertEqual(self.lua.globals().deleteCount, 1)

    def test_occupied_horse_retained(self):
        self.call_and_bind()
        self.lua.execute('autoOccupancy=true; occupied=true')
        self.assertEqual(self.controller.Store(3)['code'], 'horse_occupied')
        self.assertEqual(self.lua.globals().deleteCount, 0)
        self.assertEqual(self.case.scalar('SELECT state FROM fs_call_leases'), 'active')

    def test_reused_entity_handle_is_never_deleted(self):
        self.call_and_bind()
        self.lua.execute('Stables.HorseController.EntityCreated(100)')
        self.controller.Tick()
        self.assertEqual(self.lua.globals().deleteCount, 0)
        self.assertEqual(self.case.scalar('SELECT state FROM fs_call_leases'), 'reconciliation_required')

    def test_logout_cleans_observed_unbound_candidate(self):
        self.controller.Call(3)
        self.accept()
        self.lua.execute('SpawnCandidate(true); current=false')
        self.controller.Tick()
        self.assertEqual(self.lua.globals().deleteCount, 1)
        self.assertEqual(self.case.scalar('SELECT state FROM fs_call_leases'), 'released')

    def test_stop_does_no_sql_and_start_finishes_confirmed_cleanup(self):
        self.call_and_bind()
        before=self.case.write_count
        self.controller.Stop()
        self.assertEqual(self.case.write_count, before)
        self.assertEqual(self.lua.globals().deleteCount, 1)
        self.reload()
        self.assertTrue(self.controller.Start()['ok'])
        self.assertEqual(self.case.scalar('SELECT state FROM fs_call_leases'), 'released')
        self.assertEqual(self.case.scalar('SELECT availability FROM fs_horses'), 'stored')

    def test_delayed_stop_deletion_finishes_after_restart(self):
        self.call_and_bind()
        self.lua.execute('deleteDeferred=true')
        self.controller.Stop()
        self.reload()
        self.assertTrue(self.controller.Start()['ok'])
        self.assertEqual(self.case.scalar('SELECT state FROM fs_call_leases'), 'active')
        self.assertEqual(self.case.scalar('SELECT COUNT(*) FROM fs_call_slots'), 1)
        self.assertEqual(self.lua.globals().deleteCount, 1)  # startup does not delete from saved net ID
        self.lua.execute('entities[100].exists=false')
        self.controller.Tick()
        self.assertEqual(self.case.scalar('SELECT state FROM fs_call_leases'),'released')
        self.assertEqual(self.case.scalar('SELECT COUNT(*) FROM fs_call_slots'),0)
        self.assertEqual(self.lua.globals().deleteCount,1)

    def test_reused_pending_stop_handle_does_not_delete_replacement(self):
        self.call_and_bind()
        self.lua.execute('deleteDeferred=true')
        self.controller.Stop()
        self.lua.execute('entities[100].netId=99; entities[100].model=999; entities[100].state={}')
        self.reload()
        self.assertTrue(self.controller.Start()['ok'])
        self.controller.Tick()
        self.assertEqual(self.lua.globals().deleteCount,1)
        self.assertTrue(self.lua.globals().entities[100]['exists'])
        self.assertEqual(self.case.scalar('SELECT COUNT(*) FROM fs_call_slots'),1)

    def test_full_process_restart_recovers_without_native_deletion(self):
        self.call_and_bind()
        self.lua.execute('convars.bcc_stables_process_epoch_v1="641d1d56-d0cf-11f1-9ad4-e0d55eaa2deb"; entities[100].exists=false')
        self.reload()
        self.assertTrue(self.controller.Start()['ok'])
        self.assertEqual(self.case.scalar('SELECT state FROM fs_call_leases'), 'released')
        self.assertEqual(self.case.scalar('SELECT COUNT(*) FROM fs_call_recoveries'), 1)
        self.assertEqual(self.lua.globals().deleteCount, 0)

    def test_timeout_retains_unobserved_submission(self):
        self.controller.Call(3)
        self.lua.execute('time=30001')
        self.controller.Tick()
        self.assertEqual(self.case.scalar('SELECT state FROM fs_call_leases'), 'reconciliation_required')
        self.assertEqual(self.lua.globals().deleteCount, 0)

    def test_failed_restart_cleanup_preserves_proof_for_later_retry(self):
        self.call_and_bind()
        self.controller.Stop()
        self.case.fail_at=self.case.write_count+1
        self.reload()
        self.assertTrue(self.controller.Start()['ok'])
        self.assertEqual(self.case.scalar('SELECT state FROM fs_call_leases'), 'active')
        self.controller.Stop()  # must not overwrite the retained proof with an empty journal
        self.case.fail_at=None
        self.reload()
        self.assertTrue(self.controller.Start()['ok'])
        self.assertEqual(self.case.scalar('SELECT state FROM fs_call_leases'), 'released')

    def test_foreign_simulator_cannot_answer_occupancy_ticket(self):
        self.call_and_bind()
        self.lua.execute('''
            waitHook=function()
                foreignReply=Stables.HorseController.OccupancyResult(4,{generationId=sent.generationId,sequence=1,occupied=false})
            end
        ''')
        self.assertEqual(self.controller.Store(3)['code'],'occupancy_unknown')
        self.assertFalse(self.lua.globals().foreignReply['ok'])
        self.assertEqual(self.lua.globals().deleteCount,0)

    def test_lost_startup_commit_reply_does_not_leak_stop_proof(self):
        self.call_and_bind()
        self.controller.Stop()
        self.case.lose_commit_reply=True
        self.reload()
        self.assertTrue(self.controller.Start()['ok'])
        self.case.lose_commit_reply=False
        self.controller.Stop()
        self.reload()
        self.assertTrue(self.controller.Start()['ok'])
        self.assertEqual(self.case.scalar('SELECT state FROM fs_call_leases'),'released')
        encoded=self.lua.globals().convars['bcc_stables_stop_proofs_v1']
        self.assertFalse(json.loads(encoded)['entries'])

    def test_install_registers_only_player_routes_and_lifecycle_handlers(self):
        self.lua.execute('''
            handlers={}; routes={}; exported={}
            AddEventHandler=function(name,handler) handlers[name]=handler end
            CreateThread=function(handler) worker=handler end
            setmetatable(exports,{__call=function(_,name,handler) exported[name]=handler end})
            exports['feather-core'].RegisterRpc=function(_,name,handler,options)
                routes[name]={handler=handler,options=options}
                return {ok=true,value=true}
            end
        ''')
        self.assertTrue(self.controller.Install()['ok'])
        self.lua.execute('''
            assert(handlers.entityCreated and handlers.onResourceStop and handlers.playerDropped)
            handlers.onResourceStop('feather-inventory')
            assert(not Stables.HorseController.Status().running)
            assert(exported.PrepareShutdown)
            local request=routes['stables.horses.call.request.v1'].options
            assert(request.requireCharacter and request.validatePayload({}) and not request.validatePayload({characterId='spoof'}))
            local store=routes['stables.horses.call.store_current.v1'].options.validatePayload
            assert(store({}) and store({generationId=row.horse_id}))
            assert(not store({generationId='bad'}) and not store({generationId=row.horse_id,characterId='spoof'}))
            local bind=routes['stables.horses.call.bind.v1'].options.validatePayload
            assert(bind({generationId=sent and sent.generationId or row.horse_id,netId=55}))
            assert(not bind({generationId=row.horse_id,netId=55,characterId='spoof'}))
        ''')

    def test_accept_permission_is_single_use(self):
        self.assertTrue(self.controller.Call(3)['ok'])
        self.assertTrue(self.accept()['ok'])
        self.assertEqual(self.accept()['code'],'stale_call')

    def test_old_instruction_cannot_be_accepted_after_restart(self):
        self.controller.Call(3)
        self.controller.Stop()
        self.reload()
        self.controller.Start()
        self.assertEqual(self.accept()['code'],'stale_call')
        self.assertEqual(self.lua.globals().deleteCount,0)

    def test_stop_records_already_observed_disappearance(self):
        self.call_and_bind()
        self.lua.execute('entities[100].exists=false')  # client stop cleanup reached the server first
        self.controller.Stop()
        self.reload()
        self.assertTrue(self.controller.Start()['ok'])
        self.assertEqual(self.case.scalar('SELECT state FROM fs_call_leases'),'released')

    def test_condition_delivered_after_authorized_bind(self):
        self.db.execute('INSERT INTO fs_horse_condition VALUES (?,90,80,1,1)',(lifecycle.HORSE,))
        self.db.commit()
        self.controller.Call(3)
        self.accept()
        self.lua.execute('SpawnCandidate(true)')
        bound=self.controller.Bind(3,self.lua.table_from({'generationId':lifecycle.GEN,'netId':55}))
        self.assertTrue(bound['ok'])
        self.assertEqual(bound['value']['condition']['healthCore'],90)
        self.assertEqual(bound['value']['condition']['staminaCore'],80)

    def test_status_observes_migration_without_mutating_call(self):
        self.call_and_bind()
        writes=self.case.write_count
        first=self.controller.Status()['liveCalls'][1]
        self.assertEqual(first['ownerSource'],3)
        self.assertEqual(first['networkOwner'],3)
        self.lua.execute('entities[100].owner=4')
        second=self.controller.Status()['liveCalls'][1]
        self.assertEqual(second['ownerSource'],3)
        self.assertEqual(second['networkOwner'],4)
        self.assertTrue(second['identityMatches'])
        self.assertEqual(self.case.write_count,writes)
        self.assertEqual(self.lua.globals().createCount,1)
        self.assertEqual(self.lua.globals().deleteCount,0)

    def test_status_does_not_attribute_reused_entity_to_horse(self):
        self.call_and_bind()
        self.lua.execute('entities[100].state={}; entities[100].owner=4')
        entry=self.controller.Status()['liveCalls'][1]
        self.assertFalse(entry['identityMatches'])
        self.assertIsNone(entry['networkOwner'])

    def test_relocation_releases_original_before_one_replacement(self):
        new_id,observer=self.prepare_relocation()
        self.db.execute('INSERT INTO fs_horse_condition VALUES (?,90,80,1,1)',(lifecycle.HORSE,))
        self.db.commit()
        result=self.controller.Call(3)
        self.assertTrue(result['ok'])
        self.assertTrue(result['value']['relocated'])
        self.assertEqual(result['value']['generationId'],new_id)
        self.assertEqual(self.lua.globals().createCount,2)
        self.assertFalse(self.lua.globals().entities[100]['exists'])
        self.assertEqual(self.db.execute('SELECT state FROM fs_call_leases WHERE generation_id=?',(lifecycle.GEN,)).fetchone()[0],'released')
        self.assertEqual(self.case.scalar('SELECT generation_id FROM fs_call_slots'),new_id)
        self.assertTrue(self.controller.Accept(3,self.lua.table_from({'generationId':new_id,'observerId':observer}))['ok'])
        self.lua.execute('''
            entities[101]={exists=true,coords={x=203,y=0,z=0},netId=56,owner=3,model=101,state={
                bccStablesGeneration=sent.generationId,bccStablesObserver=sent.observerId}}
            Stables.HorseController.EntityCreated(101)
        ''')
        bound=self.controller.Bind(3,self.lua.table_from({'generationId':new_id,'netId':56}))
        self.assertTrue(bound['ok'])
        self.assertEqual(bound['value']['condition']['healthCore'],90)
        self.assertEqual(bound['value']['condition']['staminaCore'],80)
        self.assertFalse(self.controller.Call(3)['ok'])
        self.assertEqual(self.lua.globals().createCount,2)

    def test_relocation_waits_for_delayed_disappearance(self):
        self.prepare_relocation()
        self.lua.execute('''
            deleteDeferred=true
            waitHook=function()
                assert(createCount==1)
                if time>=200 then entities[100].exists=false end
            end
        ''')
        self.assertTrue(self.controller.Call(3)['ok'])
        self.assertEqual(self.lua.globals().createCount,2)

    def test_relocation_unknown_deletion_never_spawns_replacement(self):
        self.prepare_relocation()
        self.lua.execute('deleteDeferred=true')
        self.assertEqual(self.controller.Call(3)['code'],'cleanup_pending')
        self.assertEqual(self.lua.globals().createCount,1)
        self.assertEqual(self.case.scalar('SELECT COUNT(*) FROM fs_call_slots'),1)

    def test_relocation_refuses_occupied_horse(self):
        self.prepare_relocation()
        self.lua.execute('occupied=true')
        self.assertEqual(self.controller.Call(3)['code'],'horse_occupied')
        self.assertEqual(self.lua.globals().createCount,1)
        self.assertEqual(self.lua.globals().deleteCount,0)

    def test_relocation_rechecks_session_before_replacement(self):
        self.prepare_relocation()
        self.lua.execute('''
            deleteDeferred=true
            waitHook=function() entities[100].exists=false; current=false end
        ''')
        self.assertFalse(self.controller.Call(3)['ok'])
        self.assertEqual(self.lua.globals().createCount,1)
        self.assertEqual(self.case.scalar('SELECT COUNT(*) FROM fs_call_slots'),0)

    def test_relocation_refuses_changed_canonical_owner_before_cleanup(self):
        self.prepare_relocation()
        self.lua.execute('asset.owner.holderId=row.horse_id')
        self.assertFalse(self.controller.Call(3)['ok'])
        self.assertEqual(self.lua.globals().deleteCount,0)

    def test_nearby_call_does_not_delete_current_horse(self):
        self.call_and_bind()
        self.assertEqual(self.controller.Call(3)['code'],'horse_busy')
        self.assertEqual(self.lua.globals().deleteCount,0)

    def test_relocation_distance_rechecked_after_occupancy_reply(self):
        self.prepare_relocation()
        self.lua.execute('''
            local emit=TriggerClientEvent
            TriggerClientEvent=function(name,source,payload)
                if name=='bcc-stables:call:store_check' then entities[1].coords.x=0 end
                return emit(name,source,payload)
            end
        ''')
        self.assertEqual(self.controller.Call(3)['code'],'horse_nearby')
        self.assertEqual(self.lua.globals().deleteCount,0)
        self.assertEqual(self.lua.globals().createCount,1)


if __name__ == '__main__':
    unittest.main()
