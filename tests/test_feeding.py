"""Real Stables SQL on SQLite; Inventory receipts and native transport are doubles."""
import unittest
import test_checkout as checkout_fixture
import test_client_horse as client_fixture
from test_feather_boundary import ROOT


class FeedingTest(unittest.TestCase):
    def setUp(self):
        self.f=checkout_fixture.CheckoutTest();self.f.setUp()
        self.lua=self.f.lua
        q=self.f.quote()['value'];self.assertTrue(self.f.confirm(q)['ok'])
        self.horse=q['horseId']
        self.f.db.executescript('''
            DROP TABLE fs_care_operations;
            CREATE TABLE fs_care_operations(operation_id TEXT PRIMARY KEY,horse_id TEXT,character_id TEXT,
              fingerprint TEXT,record_json TEXT,state TEXT CHECK(state IN ('prepared','applied','cancelled','consumed_effect_pending')),
              revision INTEGER CHECK(revision<=2),created_at TEXT DEFAULT CURRENT_TIMESTAMP);
            CREATE TABLE fs_care_slots(horse_id TEXT PRIMARY KEY,operation_id TEXT UNIQUE REFERENCES fs_care_operations(operation_id));
            CREATE TABLE fs_care_effects(operation_id TEXT PRIMARY KEY,horse_id TEXT,condition_revision INTEGER,UNIQUE(horse_id,condition_revision));
            CREATE TABLE fs_call_leases(generation_id TEXT PRIMARY KEY,state TEXT);
            CREATE TABLE fs_care_targets(operation_id TEXT PRIMARY KEY,generation_id TEXT,observer_id TEXT,network_id INTEGER,
              source_id INTEGER,session_id TEXT,interrupted INTEGER DEFAULT 0,revision INTEGER DEFAULT 0,interrupt_reason TEXT);
        ''')
        self.f.db.execute("UPDATE fs_horses SET availability='active'")
        self.f.db.execute('UPDATE fs_horse_condition SET health_core=70,stamina_core=60')
        self.f.db.execute("INSERT INTO fs_call_slots VALUES (?,?)",(self.lua.globals().session.characterId,self.horse))
        self.f.db.execute("INSERT INTO fs_call_leases VALUES (?,'active')",(self.horse,));self.f.db.commit()
        self.lua.globals().horseId=self.horse
        self.lua.globals().observeCore=self.observe_core
        self.lua.execute('''
            Config.feeding={enabled=true,foods={consumable_apple={health=20,stamina=20},
                consumable_carrots={health=20,stamina=20},consumable_haycube={health=20,stamina=20}}}
            Config.items={food={'consumable_apple','consumable_carrots','consumable_haycube'}}
            Config.items.brush={name='horsebrush',durabilityEnabled=true,maximumDurability=100,durabilityUsedPerAction=1}
            Config.brushing={enabled=false,health=10,stamina=10}
            clock=0;far=false;occupied=false;itemsLeft=2;consumptions=0;itemAvailable=true;receipt=nil;events={}
            r={id=horseId,observerId=horseId,entity=100,netId=55,session=session,
               horse={horseId=horseId,assetId=horseId,modelKey='a_c_horse_morgan_bay'}}
            GetGameTimer=function() return clock end
            Wait=function(ms) clock=clock+ms;if walkAway and clock>=1000 then far=true end end
            GetPlayerPed=function() return 10 end
            GetEntityHealth=function() return dead and 0 or 100 end
            GetEntityCoords=function(e) return {x=e==10 and far and 10 or 0,y=0,z=0} end
            NetworkGetEntityOwner=function() return simulator or 3 end
            Stables.HorseController={MovementRecord=function(s) return current and not missing and s.characterId==session.characterId and r or nil end,
                CheckCareOccupancy=function(session,record,allowMounted)
                    assert(allowMounted~=false,'Both food and brush care permit the owner in the saddle')
                    if dead then return false,'care_life' end
                    if occupied then return false,'care_occupied' end
                    return true,nil,observeCore()
                end}
            TriggerClientEvent=function(name,target,p)
                events[#events+1]={name=name,target=target,p=p}
                if name=='bcc-stables:feed:animate' and not noAck then
                    Stables.Feeding.Request(3,{operationId=p.operationId,started=not animationFailure})
                end
            end
            RegisterCommand=function() end;CreateThread=function(fn) worker=fn end
            GetCurrentResourceName=function() return 'bcc-stables' end
            callbacks={};closeCount=0
            local api={
              Items={RegisterUsableItem=function(name,callback,owner)
                assert(owner=='bcc-stables')
                if registrationConflict then return {ok=false,error={code='conflict'}} end
                callbacks[name]=callback;return {ok=true}
              end},
              GetCharacterInventory=function() return {ok=true,value={id=1}} end,
              Inventory={CloseInventory=function() closeCount=closeCount+1;return {ok=true} end},
              GetItemForCharacter=function(character,id)
                lookedUp=id
                if not itemAvailable or id~=1 then return {ok=false,error={code='not_found'}} end
                return {ok=true,value={id=1,revision=itemRevision or 2,
                  definition={id=3,name=toolMode and 'horsebrush' or 'consumable_apple',type='item_item',instanceMode='stack'}}}
              end}
            local function terminal(p,consume,wear)
                if not receipt then
                    receipt={contractVersion=1,sourceResource='bcc-stables',state=consume and (wear and 'used' or 'consumed') or 'cancelled',inventoryId=consume and 1 or 0}
                    for k,v in pairs(p) do receipt[k]=v end
                    if consume and wear then
                        wears=(wears or 0)+1
                        brushDurability=math.max(0,(brushDurability or 100)-p.wear)
                        receipt.remainingDurability=brushDurability;receipt.broken=brushDurability==0
                    elseif consume then itemsLeft=itemsLeft-1;consumptions=consumptions+1 end
                end
                if loseConsume and consume then loseConsume=false;error('lost reply') end
                if wrongReceipt then receipt.characterId=horseId end
                return {ok=true,value=receipt}
            end
            exports['feather-inventory']={
                initiate=function() return api end,
                GetConsumptionContract=function() return {contractVersion=1,ready=true,durableConsumption=1,durableWear=1,conditionKey='condition',conditionMaximum=100} end,
                ConsumeCharacterItemOnce=function(_,p) assert(not activeUse,'Inventory use guard is still held');return terminal(p,true) end,
                CancelCharacterConsumption=function(_,p) return terminal(p,false) end,
                WearCharacterItemOnce=function(_,p) assert(not activeUse);return terminal(p,true,true) end,
                CancelCharacterItemWear=function(_,p) return terminal(p,false,true) end}
        ''')
        self.load()

    def load(self):
        self.lua.execute((ROOT/'server/horse/feeding.lua').read_text(encoding='utf-8'))
        self.p=self.lua.globals().Stables.Feeding

    def observe_core(self):
        row=self.f.db.execute('SELECT health_core,stamina_core,revision FROM fs_horse_condition').fetchone()
        g=self.lua.globals()
        return self.f.table({'healthCore':g.nativeHealth if g.nativeHealth is not None else (row[0] if row else 0),
            'staminaCore':g.nativeStamina if g.nativeStamina is not None else (row[1] if row else 0),
            'appliedRevision':g.nativeApplied if g.nativeApplied is not None else (g.r.requiredConditionRevision or 0),
            'owner':g.simulator or 3,'observedAt':g.clock})

    def tearDown(self):self.f.tearDown()
    def feed(self):return self.p.Request(3,self.f.table({'instanceId':1,'definitionId':3,'expectedRevision':2,'food':'consumable_apple'}))
    def saved(self):return tuple(self.f.db.execute('SELECT health_core,stamina_core,revision FROM fs_horse_condition').fetchone())
    def operation(self):return self.f.db.execute('SELECT operation_id FROM fs_care_operations').fetchone()[0]

    def test_feed_consumes_one_commits_once_and_routes_saved_values_to_simulator(self):
        self.lua.execute('simulator=2')
        v=self.feed();self.assertTrue(v['ok']);self.assertEqual(v['value']['state'],'applied')
        self.assertEqual(self.saved(),(90,80,1));self.assertEqual(self.lua.globals().itemsLeft,1)
        self.assertTrue(self.p.Settle(self.operation(),True)['ok'])
        self.assertEqual(self.lua.globals().consumptions,1)
        self.assertEqual(self.f.count('fs_care_effects'),1);self.assertEqual(self.f.count('fs_care_slots'),0)
        event=self.lua.globals().events[2];self.assertEqual(event['target'],2)
        self.assertEqual(event['p']['condition']['healthCore'],90)
        restored=self.lua.globals().Stables.OwnedRepository.ReadSelected(self.lua.globals().session)
        self.assertEqual(restored['value']['condition']['revision'],1)
        self.assertGreaterEqual(self.lua.globals().clock,5000)

    def test_moving_away_cancels_without_consuming_or_changing_condition(self):
        self.lua.execute('walkAway=true')
        v=self.feed();self.assertTrue(v['ok']);self.assertEqual(v['value']['state'],'cancelled')
        self.assertEqual(self.saved(),(70,60,0));self.assertEqual(self.lua.globals().itemsLeft,2)

    def test_no_animation_ack_or_failed_animation_cancels(self):
        for flag in ('noAck','animationFailure'):
            with self.subTest(flag=flag):
                self.lua.execute(flag+'=true;receipt=nil')
                v=self.feed();self.assertTrue(v['ok']);self.assertEqual(v['value']['state'],'cancelled')
                self.lua.execute(flag+'=false')
        self.assertEqual(self.lua.globals().consumptions,0)

    def test_lost_consumption_reply_recovers_after_reload_without_reconsuming(self):
        self.lua.execute('loseConsume=true')
        self.assertFalse(self.feed()['ok']);self.assertEqual(self.saved(),(70,60,0))
        self.assertEqual(self.lua.globals().itemsLeft,1)
        self.load();self.p.Tick();self.p.Tick()
        self.assertEqual(self.saved(),(90,80,1));self.assertEqual(self.lua.globals().consumptions,1)

    def test_database_rollback_after_consumption_is_recovered_once(self):
        original=self.f.execute
        def fail(sql,*args):
            if 'INSERT INTO fs_care_effects' in sql:raise RuntimeError('rollback')
            return original(sql,*args)
        self.lua.globals().DB.exec=fail
        self.assertFalse(self.feed()['ok']);self.assertEqual(self.saved(),(70,60,0))
        self.lua.globals().DB.exec=original
        self.p.Tick();self.assertEqual(self.saved(),(90,80,1));self.assertEqual(self.lua.globals().consumptions,1)

    def test_restart_before_consumption_cancels_original_prepared_receipt(self):
        self.lua.execute('''
            exports['feather-inventory'].CancelCharacterConsumption=function() error('offline') end
            walkAway=true
        ''')
        self.assertFalse(self.feed()['ok'])
        self.lua.execute('''
            exports['feather-inventory'].CancelCharacterConsumption=function(_,p)
                local v={contractVersion=1,sourceResource='bcc-stables',inventoryId=0,state='cancelled'}
                for k,value in pairs(p) do v[k]=value end;return {ok=true,value=v}
            end
        ''')
        self.load();self.p.Tick()
        self.assertEqual(self.f.db.execute('SELECT state FROM fs_care_operations').fetchone()[0],'cancelled')
        self.assertEqual(self.saved(),(70,60,0));self.assertEqual(self.lua.globals().itemsLeft,2)

    def test_foreign_receipt_is_retained_without_benefit(self):
        self.lua.execute('wrongReceipt=true')
        self.assertFalse(self.feed()['ok']);self.p.Tick()
        self.assertEqual(self.saved(),(70,60,0));self.assertEqual(self.f.count('fs_care_slots'),1)

    def test_occupied_distant_dead_or_missing_horse_refuses_before_item_use(self):
        for flag in ('occupied','far','dead','missing'):
            with self.subTest(flag=flag):
                self.lua.execute(flag+'=true');self.assertFalse(self.feed()['ok']);self.lua.execute(flag+'=false')
        self.assertEqual(self.f.count('fs_care_operations'),0);self.assertEqual(self.lua.globals().consumptions,0)

    def test_full_missing_uninitialized_or_disabled_refuses_without_reservation(self):
        self.f.db.execute('UPDATE fs_horse_condition SET health_core=100,stamina_core=100');self.f.db.commit()
        self.assertEqual(self.feed()['code'],'care_full')
        self.f.db.execute('UPDATE fs_horse_condition SET health_core=70');self.f.db.commit()
        self.lua.execute('itemAvailable=false');self.assertEqual(self.feed()['code'],'care_food_missing')
        self.lua.execute('itemAvailable=true;Config.feeding.enabled=false');self.assertEqual(self.feed()['code'],'care_disabled')
        self.lua.execute('Config.feeding.enabled=true')
        self.f.db.execute('DELETE FROM fs_horse_condition');self.f.db.commit()
        self.assertEqual(self.feed()['code'],'care_uninitialized')
        self.assertEqual(self.f.count('fs_care_operations'),0)

    def test_existing_pending_operation_fences_new_receipt(self):
        self.lua.execute('loseConsume=true')
        self.assertFalse(self.feed()['ok']);self.assertFalse(self.feed()['ok'])
        self.assertEqual(self.f.count('fs_care_operations'),1);self.assertEqual(self.lua.globals().consumptions,1)

    def test_routes_reject_arbitrary_item_and_spoofed_fields(self):
        self.lua.execute("exports['feather-core'].RegisterRpc=function(_,name,fn,options) validation=options.validatePayload;return {ok=true} end")
        self.assertTrue(self.p.Start()['ok'])
        validate=self.lua.globals().validation
        self.assertFalse(validate(self.f.table({'food':'invented'})))
        self.assertFalse(validate(self.f.table({'health':100})))
        self.assertFalse(validate(self.f.table({'food':'consumable_apple'})))
        self.assertFalse(validate(self.lua.table()))
        self.assertTrue(validate(self.f.table({'operationId':self.horse,'started':True})))

    def test_client_retry_recovers_exact_operation_without_another_consume(self):
        self.lua.execute('loseConsume=true')
        self.assertFalse(self.feed()['ok'])
        result=self.p.Request(3,self.f.table({'operationId':self.operation()}))
        self.assertTrue(result['ok']);self.assertEqual(result['value']['state'],'applied')
        self.assertEqual(self.lua.globals().consumptions,1)

    def test_gains_cap_at_one_hundred(self):
        self.f.db.execute('UPDATE fs_horse_condition SET health_core=95,stamina_core=99');self.f.db.commit()
        self.assertTrue(self.feed()['ok']);self.assertEqual(self.saved(),(100,100,1))

    def test_lost_reservation_commit_reply_cancels_without_consumption(self):
        original=self.f.execute
        def lose_reservation(sql,*args):
            if 'INSERT INTO fs_care_operations' in sql:self.f.lost_commit=True
            return original(sql,*args)
        self.lua.globals().DB.exec=lose_reservation
        self.assertFalse(self.feed()['ok']);self.assertEqual(self.f.count('fs_care_operations'),1)
        self.load();self.p.Tick()
        self.assertEqual(self.lua.globals().consumptions,0);self.assertEqual(self.saved(),(70,60,0))
        self.assertEqual(self.f.db.execute('SELECT state FROM fs_care_operations').fetchone()[0],'cancelled')

    def register_items(self):
        self.lua.execute("exports['feather-core'].RegisterRpc=function() return {ok=true} end")
        return self.p.Start()

    def use(self):
        return self.lua.globals().callbacks.consumable_apple(self.f.table({'id':1,'item_id':3,'row_revision':2,'name':'consumable_apple'}),3)

    def test_inventory_use_returns_before_consumption_then_uses_exact_instance(self):
        self.assertTrue(self.register_items()['ok'])
        self.lua.execute('activeUse=true')
        queued=self.use();self.assertTrue(queued['value']['queued'])
        self.assertEqual(self.lua.globals().consumptions,0);self.assertEqual(self.lua.globals().closeCount,1)
        self.lua.execute('activeUse=false;worker()')
        self.assertEqual(self.lua.globals().lookedUp,1);self.assertEqual(self.saved(),(90,80,1))
        self.assertEqual(self.lua.globals().receipt.instanceId,1)
        self.assertEqual(self.lua.globals().events[3]['name'],'bcc-stables:feed:result')

    def test_duplicate_inventory_use_is_fenced_before_worker_starts(self):
        self.register_items();self.use()
        queued_worker=self.lua.globals().worker
        self.assertFalse(self.use()['value'])
        queued_worker();self.assertEqual(self.lua.globals().consumptions,1)

    def test_item_moved_or_revision_changed_before_worker_never_substitutes_food(self):
        self.register_items();self.use();self.lua.execute('itemRevision=3;worker()')
        self.assertEqual(self.lua.globals().consumptions,0);self.assertEqual(self.f.count('fs_care_operations'),0)
        self.assertEqual(self.lua.globals().lookedUp,1)

    def test_character_change_before_queued_use_does_not_feed_or_notify_reused_source(self):
        self.register_items();self.use();self.lua.execute('current=false;worker()')
        self.assertEqual(self.lua.globals().consumptions,0);self.assertEqual(len(self.lua.globals().events),0)

    def test_each_food_policy_defines_its_saved_effect(self):
        self.lua.execute('Config.feeding.foods.consumable_apple={health=3,stamina=7}')
        self.assertTrue(self.feed()['ok']);self.assertEqual(self.saved(),(73,67,1))

    def test_policy_change_does_not_change_an_already_consumed_recovery_benefit(self):
        self.lua.execute('loseConsume=true')
        self.assertFalse(self.feed()['ok'])
        self.lua.execute('Config.feeding.foods={}')
        self.load();self.p.Tick();self.assertEqual(self.saved(),(90,80,1))

    def test_existing_item_owner_conflict_is_not_overwritten(self):
        self.lua.execute('registrationConflict=true')
        self.assertEqual(self.register_items()['code'],'food_registration_conflict')

    def test_server_health_native_is_not_used_as_a_care_life_observation(self):
        self.lua.execute("GetEntityHealth=function() error('Life belongs to the current simulator observation') end")
        self.assertTrue(self.feed()['ok'])

    def test_distance_movement_and_life_rejections_are_distinct(self):
        self.lua.execute('far=true')
        result=self.feed();self.assertEqual(result['code'],'care_too_far');self.assertEqual(result['distance'],10)
        self.lua.execute('far=false;r.movement={}')
        self.assertEqual(self.feed()['code'],'care_moving')
        self.lua.execute('r.movement=nil;dead=true')
        self.assertEqual(self.feed()['code'],'care_life')

    def test_full_saved_horse_with_depleted_live_stamina_can_be_fed_again(self):
        self.f.db.execute('UPDATE fs_horse_condition SET health_core=100,stamina_core=100');self.f.db.commit()
        self.lua.execute('nativeHealth=100;nativeStamina=5')
        result=self.feed()
        self.assertTrue(result['ok']);self.assertEqual(self.saved(),(100,25,2))
        self.assertEqual(self.lua.globals().consumptions,1)

    def test_store_checkpoint_persists_depletion_and_reader_restores_saved_value(self):
        self.lua.execute('nativeStamina=7')
        g=self.lua.globals()
        result=self.p.Capture(g.session,g.r,self.observe_core(),g.Authorize)
        self.assertTrue(result['ok']);self.assertEqual(self.saved(),(70,7,1))
        restored=g.Stables.OwnedRepository.ReadSelected(g.session)
        self.assertEqual(restored['value']['condition']['staminaCore'],7)
        self.assertEqual(self.lua.globals().consumptions,0)

    def test_native_increases_cannot_raise_saved_cores_or_revision(self):
        self.lua.execute('nativeHealth=100;nativeStamina=100')
        g=self.lua.globals()
        self.assertTrue(self.p.Capture(g.session,g.r,self.observe_core(),g.Authorize)['ok'])
        self.assertEqual(self.saved(),(70,60,0))

    def test_checkpoint_is_refused_after_simulator_changes(self):
        self.lua.execute('nativeStamina=7')
        observed=self.observe_core();g=self.lua.globals()
        self.lua.execute('simulator=4')
        self.assertFalse(self.p.Capture(g.session,g.r,observed,g.Authorize)['ok'])
        self.assertEqual(self.saved(),(70,60,0))

    def test_recovered_food_benefit_is_not_erased_by_old_native_values(self):
        self.lua.execute('loseConsume=true')
        self.assertFalse(self.feed()['ok'])
        self.load();self.p.Tick();self.assertEqual(self.saved(),(90,80,1))
        self.lua.execute('nativeHealth=70;nativeStamina=60;nativeApplied=0')
        g=self.lua.globals()
        self.assertFalse(self.p.Capture(g.session,g.r,self.observe_core(),g.Authorize)['ok'])
        self.assertEqual(self.saved(),(90,80,1))
        self.assertEqual(g.events[len(g.events)]['name'],'bcc-stables:feed:condition')

    def brush(self):
        self.lua.execute('toolMode=true;Config.brushing.enabled=true')
        return self.p.Request(3,self.f.table({'instanceId':1,'definitionId':3,'expectedRevision':2,'food':'horsebrush','action':'brush'}))

    def test_brush_wears_once_and_applies_saved_benefit_and_clean_instruction(self):
        result=self.brush();self.assertTrue(result['ok']);self.assertEqual(result['value']['remainingDurability'],99)
        self.assertEqual(self.saved(),(80,70,1));self.assertEqual(self.lua.globals().wears,1)
        self.assertEqual(self.lua.globals().events[2]['p']['action'],'brush')
        self.assertTrue(self.p.Settle(self.operation(),True)['ok']);self.assertEqual(self.lua.globals().wears,1)

    def test_brush_cancellation_preserves_durability_and_condition(self):
        self.lua.execute('walkAway=true')
        self.assertEqual(self.brush()['value']['state'],'cancelled')
        self.assertIsNone(self.lua.globals().wears);self.assertEqual(self.saved(),(70,60,0))

    def test_brushing_full_cores_still_cleans_and_wears_brush(self):
        self.f.db.execute('UPDATE fs_horse_condition SET health_core=100,stamina_core=100');self.f.db.commit()
        self.assertTrue(self.brush()['ok']);self.assertEqual(self.saved(),(100,100,1));self.assertEqual(self.lua.globals().wears,1)

    def test_lost_wear_reply_recovers_same_operation_after_reload(self):
        self.lua.execute('loseConsume=true')
        self.assertFalse(self.brush()['ok']);self.assertEqual(self.saved(),(70,60,0))
        self.load();self.p.Tick();self.p.Tick()
        self.assertEqual(self.saved(),(80,70,1));self.assertEqual(self.lua.globals().wears,1)

    def test_final_brush_use_reports_break_and_still_applies_once(self):
        self.lua.execute('brushDurability=1')
        result=self.brush();self.assertTrue(result['value']['broken']);self.assertEqual(self.saved(),(80,70,1))

    def test_inventory_brush_callback_uses_same_queue_and_does_not_consume_food(self):
        self.lua.execute('Config.brushing.enabled=true;toolMode=true')
        self.assertTrue(self.register_items()['ok'])
        self.lua.globals().callbacks.horsebrush(self.f.table({'id':1,'item_id':3,'row_revision':2,'name':'horsebrush'}),3)
        self.lua.globals().worker()
        self.assertEqual(self.lua.globals().wears,1);self.assertEqual(self.lua.globals().itemsLeft,2)

    def test_brush_works_with_feeding_disabled(self):
        self.lua.execute('Config.feeding.enabled=false')
        self.assertTrue(self.brush()['ok'])


class FeedingClientTest(unittest.TestCase):
    def setUp(self):
        self.f=client_fixture.ClientHorseTest();self.f.setUp();self.lua=self.f.lua
        self.lua.execute('''
            CreateFromServer()
            CreateThread=function(fn) promptWorker=fn end
            IsEntityDead=function() return false end
            IsPedDeadOrDying=function() return false end
            GetMount=function() return 100 end
            IsNuiFocused=function() return false end
            ClearPedTasks=function() end
            Stables.Client.Text=function(key) return key end
            entities[10]={coords={x=3,y=0,z=0},exists=true}
            local native=Citizen.InvokeNative
            Citizen.InvokeNative=function(hash,e,index,...)
                if hash==0x36731AC041289BB1 then return cores[index] end
                return native(hash,e,index,...)
            end
        ''')
        self.lua.execute((ROOT/'client/horse/feeding.lua').read_text(encoding='utf-8'))
        self.lua.execute('CreateThread=function(fn) fn() end')

    def project(self,revision=2,health=100):
        self.lua.globals().newRevision=revision;self.lua.globals().newHealth=health
        self.lua.execute('''
            handlers['bcc-stables:feed:condition']({generationId=spec.generationId,observerId=spec.observerId,
                netId=55,modelKey=spec.modelKey,condition={healthCore=newHealth,staminaCore=100,revision=newRevision}})
        ''')

    def test_projection_is_absolute_and_refuses_old_revisions(self):
        self.lua.execute('source=65535');self.project()
        self.assertEqual(self.lua.globals().cores[0],100)
        self.project(1,10);self.assertEqual(self.lua.globals().cores[0],100)

    def test_item_care_has_no_prompt_worker_command_or_client_food_selection(self):
        self.assertIsNone(self.lua.globals().promptWorker)
        self.assertIsNone(self.lua.globals().commands.BccStablesHorseFeed)
        self.assertIsNone(self.lua.globals().Stables.Horse.Feed)

    def test_inventory_close_releases_focus_before_animation_ack(self):
        self.lua.execute('''
            focused=true;acks={}
            IsNuiFocused=function() return focused end
            Wait=function(ms) clock=clock+ms;if clock>=50 then focused=false end end
            Stables.Client.Rpc=function(action,p) acks[#acks+1]=p;return {ok=true} end
            source=65535
            handlers['bcc-stables:feed:animate']({operationId=spec.horseId,generationId=spec.generationId,netId=55})
        ''')
        self.assertTrue(self.lua.globals().acks[1]['started'])
        self.assertGreaterEqual(self.lua.globals().clock,5050)

    def test_movement_cancels_inventory_started_animation(self):
        self.lua.execute('''
            acks={}
            Stables.Client.Rpc=function(action,p) acks[#acks+1]=p;return {ok=true} end
            Wait=function(ms) clock=clock+ms;if clock>=1000 then entities[10].coords.x=100 end end
            source=65535
            handlers['bcc-stables:feed:animate']({operationId=spec.horseId,generationId=spec.generationId,netId=55})
        ''')
        self.assertTrue(self.lua.globals().acks[2]['cancel'])

    def test_owner_can_start_feeding_from_the_saddle(self):
        self.lua.execute('''
            mounted=true;acks={}
            Stables.Client.Rpc=function(action,p) acks[#acks+1]=p;return {ok=true} end
            source=65535
            handlers['bcc-stables:feed:animate']({operationId=spec.horseId,generationId=spec.generationId,netId=55})
        ''')
        self.assertTrue(self.lua.globals().acks[1]['started'])

    def test_brush_uses_original_animation_and_allows_owner_mounted_start(self):
        self.lua.execute('''
            hashes={};acks={}
            GetHashKey=function(name) hashes[name]=true;return 101 end
            Stables.Client.Rpc=function(action,p) acks[#acks+1]=p;return {ok=true} end
            source=65535
            brushSpec={operationId=spec.horseId,generationId=spec.generationId,netId=55,action='brush'}
            handlers['bcc-stables:feed:animate'](brushSpec)
        ''')
        self.assertTrue(self.lua.globals().acks[1]['started'])
        self.assertTrue(self.lua.globals().hashes.Interaction_Brush)
        self.assertTrue(self.lua.globals().hashes.p_brushHorse02x)
        self.lua.execute("mounted=true;handlers['bcc-stables:feed:animate'](brushSpec)")
        self.assertTrue(self.lua.globals().acks[2]['started'])

    def test_committed_brush_instruction_cleans_only_the_matching_horse(self):
        self.lua.execute('''
            cleaned=0
            local native=Citizen.InvokeNative
            Citizen.InvokeNative=function(hash,...)
                if hash==0x6585D955A68452A5 or hash==0x523C79AEEFCC4A2A or hash==0x8FE22675A5A45817 then cleaned=cleaned+1;return end
                return native(hash,...)
            end
            source=65535
            handlers['bcc-stables:feed:condition']({generationId=spec.generationId,observerId=spec.observerId,
                netId=55,modelKey=spec.modelKey,action='brush',condition={healthCore=100,staminaCore=100,revision=2}})
        ''')
        self.assertEqual(self.lua.globals().cleaned,3)

    def care_occupancy(self,care=True):
        self.lua.globals().careMode=care
        self.lua.execute('''
            entities[10].netId=10
            local resolve=NetworkGetEntityFromNetworkId
            NetworkGetEntityFromNetworkId=function(id) if id==10 then return 10 end;return resolve(id) end
            Stables.Client.Rpc=function(action,p) occupancyReply=p;return {ok=true} end
            source=65535
            handlers['bcc-stables:call:store_check']({generationId=spec.generationId,observerId=spec.observerId,
                netId=55,modelKey=spec.modelKey,sequence=1,care=careMode,targetNet=10,condition=true})
        ''')
        return self.lua.globals().occupancyReply

    def test_care_allows_owner_rider_but_store_still_refuses_any_rider(self):
        self.lua.execute('mounted=true')
        reply=self.care_occupancy()
        self.assertFalse(reply['occupied']);self.assertTrue(reply['ownerAlive']);self.assertTrue(reply['horseAlive'])
        self.assertEqual(reply['healthCore'],90);self.assertEqual(reply['staminaCore'],80);self.assertEqual(reply['appliedRevision'],1)
        self.assertTrue(self.care_occupancy(False)['occupied'])

    def test_care_simulator_refuses_foreign_rider_and_reports_dead_owner(self):
        self.lua.execute('GetRiderOfMount=function() return 99 end')
        self.assertTrue(self.care_occupancy()['occupied'])
        self.lua.execute('GetRiderOfMount=function() return 0 end;IsEntityDead=function(e) return e==10 end')
        self.assertFalse(self.care_occupancy()['ownerAlive'])

    def test_foreign_or_retired_generation_and_noncontroller_cannot_project(self):
        self.lua.execute('source=3');self.project();self.assertEqual(self.lua.globals().cores[0],90)
        self.lua.execute('source=65535;NetworkHasControlOfEntity=function() return false end')
        self.project();self.assertEqual(self.lua.globals().cores[0],90)
        self.lua.execute('NetworkHasControlOfEntity=function() return true end;entities[100].state.bccStablesGeneration="other"')
        self.project();self.assertEqual(self.lua.globals().cores[0],90)



if __name__=='__main__':unittest.main()
