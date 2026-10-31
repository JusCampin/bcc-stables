"""Actual injury/care SQL; mocked Inventory receipts and network simulator."""
import unittest
import test_feeding as fixture
import test_call_repository as lifecycle
import test_horse_controller as controller_fixture
from test_feather_boundary import ROOT


class InjuryTest(unittest.TestCase):
    def setUp(self):
        self.f=fixture.FeedingTest();self.f.setUp()
        self.lua=self.f.lua;self.db=self.f.f.db
        self.lua.execute('''
            Config.death={enabled=true,writheEnabled=true,persistentWrithe=true,permanentDeath=false,reviveHealth=25,reviveStamina=25}
            Config.items.reviver='consumable_horse_reviver'
            r.horse.biologicalState='alive';r.horse.projectionRevision=0
            Stables.HorseController.CheckCareOccupancy=function(_,_,allowMounted)
                if occupied then return false,'care_occupied' end
                return true,nil,observeCore()
            end
            local api=exports['feather-inventory'].initiate()
            local get=api.GetItemForCharacter
            api.GetItemForCharacter=function(...)
                local result=get(...)
                if result.ok and reviver then result.value.definition.name=Config.items.reviver end
                return result
            end
            api.Inventory.GetInventoryItems=function(id)
                assert(id==1)
                return {ok=true,value=missingReviver and {} or {{id=1,name=Config.items.reviver}}}
            end
        ''')
        self.lua.execute((ROOT/'server/horse/injuries.lua').read_text())
        self.i=self.lua.globals().Stables.Injuries
        self.authorize=self.lua.eval('function() return current and not missing end')

    def tearDown(self):self.f.tearDown()
    def state(self):return tuple(self.db.execute('SELECT biological_state,revision FROM fs_horses').fetchone())
    def down(self):return self.i.Down(self.lua.globals().r,self.authorize)
    def revive(self):
        self.lua.execute('reviver=true')
        return self.f.p.Request(3,self.f.f.table({'instanceId':1,'definitionId':3,'expectedRevision':2,
            'food':'consumable_horse_reviver','action':'revive'}))

    def test_injury_persists_once_and_reviver_consumes_once(self):
        self.assertTrue(self.down()['ok']);down=self.state()
        self.assertEqual(down[0],'downed');self.assertTrue(self.down()['ok']);self.assertEqual(self.state(),down)
        self.i.Tick(self.lua.globals().r)
        v=self.revive();self.assertTrue(v['ok'],str(v));self.assertEqual(v['value']['action'],'revive')
        self.assertEqual(self.f.saved(),(95,85,1));self.assertEqual(self.state(),('alive',down[1]+1))
        self.assertTrue(self.f.p.Settle(self.f.operation(),True)['ok'])
        self.assertEqual(self.lua.globals().consumptions,1)

    def test_walk_away_cancels_and_keeps_injury(self):
        self.down();self.lua.execute('walkAway=true')
        v=self.revive();self.assertTrue(v['ok']);self.assertEqual(v['value']['state'],'cancelled')
        self.assertEqual(self.state()[0],'downed');self.assertEqual(self.lua.globals().consumptions,0)

    def test_native_prompt_selects_and_consumes_owned_reviver_on_server(self):
        self.down();self.lua.execute('reviver=true')
        self.assertTrue(self.f.p.Revive(3,self.f.f.table({'generationId':self.lua.globals().r.id}))['ok'])
        self.assertEqual(self.state()[0],'alive');self.assertEqual(self.lua.globals().consumptions,1)

    def test_native_prompt_without_item_or_with_stale_call_cannot_consume(self):
        self.down();self.lua.execute('missingReviver=true;reviver=true')
        self.f.p.Revive(3,self.f.f.table({'generationId':self.lua.globals().r.id}))
        self.assertEqual(self.state()[0],'downed');self.assertEqual(self.lua.globals().consumptions,0)
        self.assertEqual(self.lua.globals().events[len(self.lua.globals().events)].p.code,'care_food_missing')
        self.lua.execute('missingReviver=false')
        self.f.p.Revive(3,self.f.f.table({'generationId':'641d1d56-d0cf-11f1-9ad4-e0d55eaa2deb'}))
        self.assertEqual(self.lua.globals().consumptions,0)

    def test_native_prompt_rpc_never_accepts_client_item_selection(self):
        self.lua.execute("exports['feather-core'].RegisterRpc=function(_,name,fn,options) if name=='stables.horses.call.revive.v1' then reviveValidation=options.validatePayload end;return {ok=true} end")
        self.assertTrue(self.f.p.Start()['ok'])
        validate=self.lua.globals().reviveValidation
        self.assertTrue(validate(self.f.f.table({'generationId':self.lua.globals().r.id})))
        self.assertFalse(validate(self.f.f.table({'generationId':self.lua.globals().r.id,'instanceId':999})))

    def test_registered_revive_handler_uses_core_payload_source_order(self):
        self.down();self.lua.execute('''
            reviver=true
            exports['feather-core'].RegisterRpc=function(_,name,fn)
                if name=='stables.horses.call.revive.v1' then reviveHandler=fn end
                return {ok=true}
            end
        ''')
        self.assertTrue(self.f.p.Start()['ok'])
        result=self.lua.globals().reviveHandler(self.f.f.table({'generationId':self.lua.globals().r.id}),3)
        self.assertTrue(result['ok']);self.assertEqual(self.state()[0],'alive')
        self.assertEqual(self.lua.globals().consumptions,1)

    def test_registered_injury_handler_uses_core_payload_source_order(self):
        self.lua.execute('''
            exports['feather-core'].RegisterRpc=function(_,name,fn)
                if name=='stables.horses.call.injury.v1' then injuryHandler=fn end
                return {ok=true}
            end
        ''')
        self.assertTrue(self.i.Start()['ok']);self.i.Tick(self.lua.globals().r)
        g=self.lua.globals()
        p=self.f.f.table({'generationId':g.r.id,'observerId':g.r.observerId,'sequence':g.r.injurySequence})
        self.assertTrue(g.injuryHandler(p,3)['ok']);self.assertEqual(self.state()[0],'downed')

    def test_healthy_horse_refuses_reviver_and_downed_refuses_food(self):
        self.assertFalse(self.revive()['ok']);self.down()
        self.assertFalse(self.f.feed()['ok']);self.assertEqual(self.lua.globals().consumptions,0)

    def test_lost_inventory_reply_recovers_biological_state_and_benefit_once(self):
        self.down();self.lua.execute('loseConsume=true')
        self.assertFalse(self.revive()['ok']);self.assertEqual(self.state()[0],'downed')
        self.f.load();self.f.p.Tick();self.f.p.Tick()
        self.assertEqual(self.state()[0],'alive');self.assertEqual(self.f.saved(),(95,85,1))
        self.assertEqual(self.lua.globals().consumptions,1)

    def test_benefit_rollback_cannot_partially_revive(self):
        self.down();original=self.f.f.execute
        def fail(sql,*args):
            if 'INSERT INTO fs_care_effects' in sql:raise RuntimeError('rollback')
            return original(sql,*args)
        self.lua.globals().DB.exec=fail
        self.assertFalse(self.revive()['ok']);self.assertEqual(self.state()[0],'downed')
        self.assertEqual(self.f.saved(),(70,60,0))
        self.lua.globals().DB.exec=original;self.f.p.Tick()
        self.assertEqual(self.state()[0],'alive');self.assertEqual(self.f.saved(),(95,85,1))

    def test_terminal_receipt_cannot_revive_later_injury(self):
        self.down();self.assertTrue(self.revive()['ok']);operation=self.f.operation()
        self.lua.execute('reviver=false');self.assertTrue(self.down()['ok']);later=self.state()
        self.assertTrue(self.f.p.Settle(operation,True)['ok']);self.assertEqual(self.state(),later)
        self.assertEqual(self.lua.globals().consumptions,1)

    def test_lost_down_commit_acknowledgement_retries_without_second_transition(self):
        self.f.f.lost_commit=True
        self.assertFalse(self.down()['ok']);saved=self.state();self.assertEqual(saved[0],'downed')
        self.assertTrue(self.down()['ok']);self.assertEqual(self.state(),saved)

    def test_report_rejects_foreign_owner_and_stale_ticket(self):
        self.i.Tick(self.lua.globals().r);g=self.lua.globals()
        p=self.f.f.table({'generationId':g.r.id,'observerId':g.r.observerId,'sequence':g.r.injurySequence})
        self.assertFalse(self.i.Report(2,p)['ok']);p['sequence']=99
        self.assertFalse(self.i.Report(3,p)['ok']);self.assertEqual(self.state()[0],'alive')
        p['sequence']=g.r.injurySequence;self.assertTrue(self.i.Report(3,p)['ok'])

    def test_restart_read_keeps_downed_state_and_condition(self):
        self.down()
        v=self.lua.globals().Stables.OwnedRepository.ReadSelected(self.lua.globals().session)
        self.assertTrue(v['ok']);self.assertEqual(v['value']['biologicalState'],'downed')
        self.assertEqual(v['value']['condition']['healthCore'],70)

    def test_only_recovery_policy_can_be_enabled(self):
        self.lua.execute('Config.death.permanentDeath=true')
        self.assertEqual(self.i.Start()['code'],'invalid_injury_policy')

    def test_pending_consumed_food_can_settle_while_injury_remains(self):
        self.lua.execute('loseConsume=true')
        self.assertFalse(self.f.feed()['ok']);self.assertTrue(self.down()['ok'])
        self.f.p.Tick()
        self.assertEqual(self.state()[0],'downed');self.assertEqual(self.f.saved(),(90,80,1))
        self.assertEqual(self.lua.globals().consumptions,1)


class InjuryLifecycleTest(unittest.TestCase):
    def test_store_and_new_reservation_preserve_injury(self):
        f=lifecycle.CallRepositoryTest();f.setUp()
        try:
            f.lua.execute('Stables.Injuries={Enabled=function() return true end}')
            f.db.execute("UPDATE fs_horses SET biological_state='downed'");f.db.commit()
            self.assertTrue(f.reserve()['ok']);self.assertTrue(f.bind()['ok'])
            self.assertTrue(f.repo.BeginCleanup(lifecycle.CHAR,lifecycle.GEN)['ok']);self.assertTrue(f.finish()['ok'])
            saved=f.one('SELECT * FROM fs_horses')
            self.assertEqual(saved.biological_state,'downed');self.assertEqual(saved.availability,'stored')
            f.lua.globals().horse.projectionRevision=saved.revision
            self.assertTrue(f.repo.Reserve(f.lua.globals().session,f.lua.globals().horse,
                '641d1d56-d0cf-11f1-9ad4-e0d55eaa2deb',lifecycle.EPOCH)['ok'])
            self.assertEqual(f.one('SELECT biological_state FROM fs_horses').biological_state,'downed')
        finally:f.tearDown()

    def test_store_persists_late_lethal_observation_before_delete(self):
        f=controller_fixture.HorseControllerTest();f.setUp()
        try:
            f.call_and_bind()
            f.lua.execute('''
                Config={death={enabled=true}};GetGameTimer=function() return time end
                local trigger=TriggerClientEvent
                TriggerClientEvent=function(name,source,p)
                    if name=='bcc-stables:call:store_check' then
                        return Stables.HorseController.OccupancyResult(source,{generationId=p.generationId,
                            sequence=p.sequence,occupied=false,injured=true})
                    end
                    return trigger(name,source,p)
                end
            ''')
            f.lua.execute((ROOT/'server/horse/injuries.lua').read_text())
            self.assertTrue(f.controller.Store(3)['ok'])
            self.assertEqual(f.case.scalar('SELECT biological_state FROM fs_horses'),'downed')
            self.assertEqual(f.lua.globals().deleteCount,1)
        finally:f.tearDown()


if __name__=='__main__':unittest.main()
