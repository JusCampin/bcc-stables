"""Whistle authority, replay, handoff and native-worker tests."""
import unittest
import test_horse_controller as server_fixture
import test_client_horse as client_fixture
from test_feather_boundary import ROOT
from test_call_repository import GEN


class WhistleServerTest(unittest.TestCase):
    def setUp(self):
        self.fixture=server_fixture.HorseControllerTest('test_call_bind_store_normal_flow')
        self.fixture.setUp()
        self.fixture.call_and_bind()
        self.lua=self.fixture.lua
        self.lua.execute((ROOT/'server/horse/whistle.lua').read_text(encoding='utf-8-sig'))
        self.whistle=self.lua.globals().Stables.Whistle

    def tearDown(self):
        self.fixture.tearDown()

    def request(self,mode):
        return self.whistle.Request(3,self.lua.table_from({'mode':mode}))

    def ticket(self,sequence=1):
        return self.lua.table_from({'generationId':GEN,'sequence':sequence})

    def flee(self):
        self.lua.execute('Config={stable={fleeEnabled=true}};autoOccupancy=true')
        return self.fixture.controller.Store(3,None,GEN,True)

    def test_flee_waits_ten_seconds_and_reserves_generation_before_cleanup(self):
        result=self.flee();self.assertTrue(result.ok);self.assertEqual(result.value.state,'fleeing')
        self.assertEqual(self.lua.globals().deleteCount,0)
        self.assertEqual(self.whistle.Claim(3,self.ticket()).value.mode,'flee')
        self.assertFalse(self.request('approach').ok)
        self.assertEqual(self.fixture.controller.Call(3).code,'cleanup_pending')
        self.lua.execute('time=9500');self.fixture.controller.Tick()
        self.assertEqual(self.lua.globals().deleteCount,0)
        self.lua.execute('time=10000');self.fixture.controller.Tick()
        self.assertEqual(self.lua.globals().deleteCount,1)
        self.assertEqual(self.fixture.case.scalar('SELECT COUNT(*) FROM fs_call_slots'),0)

    def test_repeated_flee_does_not_extend_deadline_and_disabled_flee_keeps_horse(self):
        self.lua.execute('Config={stable={fleeEnabled=false}};autoOccupancy=true')
        denied=self.fixture.controller.Store(3,None,GEN,True)
        self.assertEqual(denied.code,'flee_disabled');self.assertEqual(self.lua.globals().deleteCount,0)
        self.assertTrue(self.flee().ok)
        self.lua.execute('time=4000')
        self.assertTrue(self.fixture.controller.Store(3,None,GEN,True).ok)
        self.assertEqual(self.fixture.controller.MovementRecord(self.lua.globals().session).flee.endsAt,10000)

    def test_flee_migration_keeps_original_deadline(self):
        self.assertTrue(self.flee().ok);self.assertTrue(self.whistle.Claim(3,self.ticket()).ok)
        self.lua.execute('time=4000;entities[100].owner=4');self.fixture.controller.Tick()
        moved=self.whistle.Claim(4,self.ticket(2));self.assertTrue(moved.ok)
        self.assertEqual(moved.value.mode,'flee');self.assertEqual(moved.value.remainingMs,6000)

    def test_flee_rechecks_rider_before_deletion_and_retains_occupied_horse(self):
        self.assertTrue(self.flee().ok);self.whistle.Claim(3,self.ticket())
        self.lua.execute('occupied=true;time=10000');self.fixture.controller.Tick()
        self.assertEqual(self.lua.globals().deleteCount,0)
        self.assertEqual(self.fixture.case.scalar('SELECT state FROM fs_call_leases'),'active')
        self.assertIsNone(self.fixture.controller.MovementRecord(self.lua.globals().session).flee)

    def test_flee_cleans_up_at_original_distance_threshold(self):
        self.assertTrue(self.flee().ok);self.whistle.Claim(3,self.ticket())
        self.lua.execute('entities[100].coords.x=201;time=500');self.fixture.controller.Tick()
        self.assertEqual(self.lua.globals().deleteCount,1)

    def test_approach_ticket_claim_once(self):
        self.assertTrue(self.request('approach')['ok'])
        claimed=self.whistle.Claim(3,self.ticket())
        self.assertTrue(claimed['ok'])
        self.assertEqual(claimed['value']['mode'],'approach')
        self.assertEqual(self.whistle.Claim(3,self.ticket())['code'],'stale_movement')

    def test_only_current_simulator_can_claim(self):
        self.lua.execute('entities[100].owner=4')
        self.assertEqual(self.request('approach')['value']['networkOwner'],4)
        self.assertFalse(self.whistle.Claim(3,self.ticket())['ok'])
        self.assertTrue(self.whistle.Claim(4,self.ticket())['ok'])

    def test_long_whistle_toggles_follow_stop(self):
        self.assertEqual(self.request('toggle_follow')['value']['mode'],'follow')
        self.assertTrue(self.whistle.Claim(3,self.ticket())['ok'])
        self.assertEqual(self.request('toggle_follow')['value']['mode'],'stop')
        self.assertFalse(self.whistle.Done(3,self.ticket())['ok'])
        self.assertEqual(self.whistle.Claim(3,self.ticket(2))['value']['mode'],'stop')

    def test_follow_handoff_invalidates_old_worker(self):
        self.request('toggle_follow')
        self.whistle.Claim(3,self.ticket())
        self.lua.execute('entities[100].owner=4')
        self.fixture.controller.Tick()
        self.assertFalse(self.whistle.Done(3,self.ticket())['ok'])
        self.assertEqual(self.whistle.Claim(4,self.ticket(2))['value']['mode'],'follow')

    def test_follow_renews_without_expiring_normal_intent(self):
        self.request('toggle_follow')
        self.whistle.Claim(3,self.ticket())
        self.lua.execute('time=25000')
        self.fixture.controller.Tick()
        self.assertTrue(self.whistle.Claim(3,self.ticket(2))['ok'])

    def test_store_cancels_movement_ticket(self):
        self.request('toggle_follow')
        self.lua.execute('autoOccupancy=true')
        self.assertTrue(self.fixture.controller.Store(3)['ok'])
        self.assertFalse(self.whistle.Claim(3,self.ticket())['ok'])

    def test_ticket_expires_and_foreign_character_cannot_request(self):
        self.request('approach')
        self.lua.execute('time=5001')
        self.assertFalse(self.whistle.Claim(3,self.ticket())['ok'])
        self.assertFalse(self.whistle.Request(4,self.lua.table_from({'mode':'approach'}))['ok'])

    def test_owner_change_after_request_refuses_claim(self):
        self.request('approach')
        self.lua.execute('asset.owner.holderId=row.horse_id')
        self.assertFalse(self.whistle.Claim(3,self.ticket())['ok'])

    def test_short_whistle_relocates_through_same_call_lifecycle(self):
        # This fixture already has a bound horse; arrange a fresh generation ID
        # and a far owner without rebuilding the live observer.
        previous=self.lua.globals().DB.one
        self.lua.globals().DB['one']=lambda sql,*args: self.lua.table_from({
            'generation_id':'641d1d56-d0cf-11f1-9ad4-e0d55eaa2deb',
            'observer_id':'3ed76477-ce80-11f1-9ad4-e0d55eaa2dec'}) if sql.startswith('SELECT UUID()') else previous(sql,*args)
        self.lua.execute('entities[1].coords.x=200; autoOccupancy=true')
        result=self.request('approach')
        self.assertTrue(result['ok'])
        self.assertTrue(result['value']['relocated'])
        self.assertEqual(self.lua.globals().createCount,2)
        self.assertFalse(self.lua.globals().entities[100]['exists'])


class WhistleClientTest(unittest.TestCase):
    def setUp(self):
        self.fixture=client_fixture.ClientHorseTest('test_ready_rideable_and_condition_restored')
        self.fixture.setUp()
        self.lua=self.fixture.lua
        self.lua.execute('''
            CreateFromServer()
            tasks,clears=0,0
            entities[10]={exists=true,model=99,netId=10,coords={x=0,y=0,z=0}}
            IsEntityDead=function() return dead==true end
            IsPedDeadOrDying=function() return false end
            NetworkGetEntityFromNetworkId=function(id) return id==55 and 100 or id==10 and 10 or 0 end
            ClearPedTasks=function() clears=clears+1 end
            TaskGoToEntity=function() tasks=tasks+1 end
            local native=Citizen.InvokeNative
            Citizen.InvokeNative=function(hash,...)
                if hash==0x304AE42E357B8C7E then tasks=tasks+1; return end
                if hash==0xA85E614430EFF816 then return 1327216456 end
                if hash==0x57EC5FA4D4D6AFCA then return true end
                return native(hash,...)
            end
            GetHashKey=function(name) return name=='WHISTLEHORSESHORT' and 501 or name=='WHISTLEHORSELONG' and 502 or 101 end
            IsNuiFocused=function() return focused==true end
            GetNumberOfEvents=function() return 1 end
            IsControlPressed=function() return pressed==true end
            jobs={}
            CreateThread=function(fn) jobs[#jobs+1]=fn end
            exports['feather-core'].CallRPC=function(_,name,p,callback)
                if name:find('movement_claim',1,true) then
                    callback({ok=true,value={generationId=p.generationId,sequence=p.sequence,observerId=spec.observerId,
                        netId=55,targetNet=10,modelKey=spec.modelKey,mode=mode or 'approach',remainingMs=100}})
                else callback({ok=true,value=true}) end
            end
        ''')
        self.lua.execute((ROOT/'client/core/dataview.lua').read_text(encoding='utf-8-sig'))
        self.lua.execute((ROOT/'client/horse/whistle.lua').read_text(encoding='utf-8-sig'))

    def execute(self):
        self.lua.execute("source=65535; handlers['bcc-stables:movement:execute']({generationId=spec.generationId,sequence=1}); jobs[#jobs]()")

    def test_flee_uses_original_native_parameters_only_on_current_simulator(self):
        self.lua.execute("""
            mode='flee'
            SetPedKeepTask=function(horse,value) assert(horse==100 and value);kept=true end
            local native=Citizen.InvokeNative
            Citizen.InvokeNative=function(hash,...)
                if hash==0x22B0D0E37CCB840D then
                    local horse,target,distance,duration,flags,speed=...
                    assert(horse==100 and target==10 and distance==100.0 and duration==100 and flags==6 and speed==3.0)
                    fleeTasks=(fleeTasks or 0)+1;return
                end
                return native(hash,...)
            end
        """)
        self.execute();self.assertEqual(self.lua.globals().fleeTasks,1);self.assertTrue(self.lua.globals().kept)

    def test_approach_executes_then_stops_at_approved_distance(self):
        self.execute()
        self.assertEqual(self.lua.globals().tasks,1)
        self.assertGreater(self.lua.globals().clears,0)

    def test_occupied_horse_receives_no_task(self):
        self.lua.execute('mounted=true')
        self.execute()
        self.assertEqual(self.lua.globals().tasks,0)
        self.assertEqual(self.lua.globals().clears,0)

    def test_changed_horse_receives_no_task(self):
        self.lua.execute('entities[100].state.bccStablesObserver="other"')
        self.execute()
        self.assertEqual(self.lua.globals().tasks,0)

    def test_menu_focus_does_not_cancel_follow_worker(self):
        self.lua.execute('focused=true; mode="follow"')
        self.execute()
        self.assertEqual(self.lua.globals().tasks,1)

    def test_listener_distinguishes_short_long_and_focus(self):
        self.lua.execute('''
            CreateEventDataBuffer=function() return {Buffer=function() return '' end,
                GetInt32=function(_,offset) return offset==0 and 10 or eventKind end} end
            requested={}
            Stables.Horse.Whistle=function(mode) requested[#requested+1]=mode end
            Wait=function(ms) if ms==0 then coroutine.yield() else clock=clock+ms end end
            eventKind=501
            listener=coroutine.create(jobs[1]); assert(coroutine.resume(listener)); assert(coroutine.resume(listener))
            clock=clock+1500; eventKind=502; assert(coroutine.resume(listener))
            clock=clock+1500; focused=true; assert(coroutine.resume(listener))
        ''')
        self.assertEqual(self.lua.globals().requested[1],'approach')
        self.assertEqual(self.lua.globals().requested[2],'toggle_follow')
        self.assertEqual(len(self.lua.globals().requested),2)

    def test_listener_initializes_with_actual_buffer_module(self):
        self.lua.execute('''
            assert(DataView==nil)
            local create=CreateEventDataBuffer
            CreateEventDataBuffer=function(size) actualBuffer=create(size); return actualBuffer end
            Wait=function(ms) if ms==0 then coroutine.yield() else clock=clock+ms end end
            listener=coroutine.create(jobs[1])
            assert(coroutine.resume(listener))
            assert(actualBuffer.length==16 and actualBuffer:GetInt32(0)==0)
            assert(coroutine.resume(listener))
            assert(coroutine.status(listener)=='suspended')
        ''')

    def test_held_whistle_with_short_native_event_requests_follow_once(self):
        self.lua.execute('''
            CreateEventDataBuffer=function() return {Buffer=function() return '' end,
                GetInt32=function(_,offset) return offset==0 and 10 or 501 end} end
            requested={}; Stables.Horse.Whistle=function(mode) requested[#requested+1]=mode end
            Wait=function(ms) if ms==0 then coroutine.yield() else clock=clock+ms end end
            pressed=true
            listener=coroutine.create(jobs[1]); assert(coroutine.resume(listener)); assert(coroutine.resume(listener))
            assert(#requested==0)
            clock=clock+800; pressed=false; assert(coroutine.resume(listener))
            assert(#requested==1 and requested[1]=='toggle_follow')
            assert(coroutine.resume(listener)); assert(#requested==1)
        ''')

    def test_quick_release_with_short_native_event_requests_approach(self):
        self.lua.execute('''
            CreateEventDataBuffer=function() return {Buffer=function() return '' end,
                GetInt32=function(_,offset) return offset==0 and 10 or 501 end} end
            requested={}; Stables.Horse.Whistle=function(mode) requested[#requested+1]=mode end
            Wait=function(ms) if ms==0 then coroutine.yield() else clock=clock+ms end end
            pressed=true
            listener=coroutine.create(jobs[1]); assert(coroutine.resume(listener)); assert(coroutine.resume(listener))
            clock=clock+100; pressed=false; assert(coroutine.resume(listener))
            assert(#requested==1 and requested[1]=='approach')
        ''')

    def test_long_event_during_hold_does_not_toggle_twice_on_release(self):
        self.lua.execute('''
            CreateEventDataBuffer=function() return {Buffer=function() return '' end,
                GetInt32=function(_,offset) return offset==0 and 10 or eventKind end} end
            requested={}; Stables.Horse.Whistle=function(mode) requested[#requested+1]=mode end
            Wait=function(ms) if ms==0 then coroutine.yield() else clock=clock+ms end end
            pressed=true; eventKind=501
            listener=coroutine.create(jobs[1]); assert(coroutine.resume(listener)); assert(coroutine.resume(listener))
            clock=clock+700; eventKind=502; assert(coroutine.resume(listener))
            assert(#requested==1 and requested[1]=='toggle_follow')
            clock=clock+2000; assert(coroutine.resume(listener))
            pressed=false; assert(coroutine.resume(listener)); assert(#requested==1)
        ''')

    def test_release_classifies_pending_event_without_second_native_event(self):
        self.lua.execute('''
            CreateEventDataBuffer=function() return {Buffer=function() return '' end,
                GetInt32=function(_,offset) return offset==0 and 10 or 501 end} end
            requested={}; Stables.Horse.Whistle=function(mode) requested[#requested+1]=mode end
            Wait=function(ms) if ms==0 then coroutine.yield() else clock=clock+ms end end
            pressed=true
            listener=coroutine.create(jobs[1]); assert(coroutine.resume(listener)); assert(coroutine.resume(listener))
            GetNumberOfEvents=function() return 0 end
            clock=clock+800; pressed=false; assert(coroutine.resume(listener))
            assert(#requested==1 and requested[1]=='toggle_follow')
        ''')

    def test_streamed_out_bound_horse_whistles_existing_call(self):
        self.lua.execute('''
            entities[100].exists=false
            assert(Stables.Horse.GetActive()==nil and Stables.Horse.HasBoundHorse())
            spawnRequests=0
            Stables.Horse.Call=function() spawnRequests=spawnRequests+1 end
            exports['feather-core'].CallRPC=function(_,name,p,callback)
                movementRoute=name; movementMode=p.mode; callback({ok=true,value=true})
            end
            Stables.Horse.Whistle('toggle_follow'); jobs[#jobs]()
        ''')
        self.assertEqual(self.lua.globals().spawnRequests,0)
        self.assertEqual(self.lua.globals().movementRoute,'stables.horses.call.whistle.v1')
        self.assertEqual(self.lua.globals().movementMode,'toggle_follow')

    def test_stored_horse_whistle_can_still_request_spawn(self):
        self.lua.execute('''
            source=65535; handlers['bcc-stables:call:cancel'](spec.generationId)
            assert(not Stables.Horse.HasBoundHorse())
            spawnRequests=0; Stables.Horse.Call=function() spawnRequests=spawnRequests+1 end
            Stables.Horse.Whistle('approach')
        ''')
        self.assertEqual(self.lua.globals().spawnRequests,1)


if __name__=='__main__':
    unittest.main()
