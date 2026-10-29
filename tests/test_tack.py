"""Real tack Lua + SQLite purchase/admission locks; Inventory API doubles.

No player items/funds are touched. Live CFX/MariaDB races remain a runtime gate.
"""
import unittest
import test_checkout as checkout_tests
from test_call_repository import CHAR, HORSE
from test_feather_boundary import ROOT

SECOND='22222222-2222-4222-8222-222222222222'
SCHEMA='''
CREATE TABLE fs_tack_orders(operation_id TEXT PRIMARY KEY,character_id TEXT,state TEXT,record_json TEXT,
 payment_transaction_id TEXT UNIQUE,instance_id INTEGER UNIQUE,
 updated_at TEXT DEFAULT CURRENT_TIMESTAMP);

'''


class TackTest(unittest.TestCase):
    def setUp(self):
        self.h=checkout_tests.CheckoutTest()
        self.h.setUp()
        self.lua=self.h.lua;self.db=self.h.db
        self.db.executescript(SCHEMA)
        self.db.execute('INSERT INTO fs_character_stables(character_id) VALUES (?)',(CHAR,))
        for horse in (HORSE,SECOND):
            self.db.execute("INSERT INTO fs_horses(horse_id,owner_character_id,biological_state,availability) VALUES (?,?,'alive','stored')",(horse,CHAR))
        self.db.commit()
        self.lua.execute('''
            Config.tack={enabled=true}
            pieces={};deliveries={};equipmentRows={};grants=0;guards={};handlers={}
            AddEventHandler=function(name,fn) handlers[name]=fn end
            GetCurrentResourceName=function() return 'bcc-stables' end
            api={Items={},Inventory={},Guards={}}
            api.Items.GetDefinitions=function() return {ok=true,value={{id=7,name='horse_saddle',type='item_item',instance_mode='unique',max_stack_size=1},
                {id=8,name='horse_saddlecloth',type='item_item',instance_mode='unique',max_stack_size=1},
                {id=9,name='horse_stirrups',type='item_item',instance_mode='unique',max_stack_size=1},
                {id=10,name='horse_saddle_horn',type='item_item',instance_mode='unique',max_stack_size=1},{id=11,name='horse_saddlebag',type='item_item',instance_mode='unique',max_stack_size=1},{id=12,name='horse_bedroll',type='item_item',instance_mode='unique',max_stack_size=1},{id=13,name='horse_bridle',type='item_item',instance_mode='unique',max_stack_size=1},{id=14,name='horse_holster',type='item_item',instance_mode='unique',max_stack_size=1},{id=15,name='horse_horseshoes',type='item_item',instance_mode='unique',max_stack_size=1},{id=16,name='horse_mask',type='item_item',instance_mode='unique',max_stack_size=1},{id=17,name='horse_mane',type='item_item',instance_mode='unique',max_stack_size=1},{id=18,name='horse_tail',type='item_item',instance_mode='unique',max_stack_size=1},{id=19,name='horse_mustache',type='item_item',instance_mode='unique',max_stack_size=1}}} end
            api.GetCharacterInventory=function() return {ok=true,value={id=99}} end
            api.Inventory.GetInventoryItems=function(inventoryId)
                local rows={}
                for _,i in pairs(pieces) do if i.inventoryId==inventoryId then rows[#rows+1]={id=i.id,name=i.definition.name,row_revision=i.revision,metadata=i.metadata} end end
                return {ok=true,value=rows}
            end
            api.Inventory.InventoryCanHoldById=function() return {ok=true,value={accepted=not fullInventory}} end
            api.GetItemForCharacter=function(_,id)
                local i=pieces[id]
                return i and i.inventoryId==99 and {ok=true,value=i} or {ok=false,code='not_found',message='Absent'}
            end
            api.GetCapabilities=function() return {ok=true,value={features={durableUniqueCharacterGrants=true,privateCharacterCollections=true}}} end
            api.MutateItem=function(_,spec)
                if fenceHook then fenceHook() end
                local i=pieces[spec.itemInstanceId]
                if not i or i.revision~=spec.expectedRevision then return {ok=false,error={code='conflict',message='Changed'}} end
                return {ok=true,value={itemInstanceId=i.id,inventoryId=i.inventoryId,revision=i.revision}}
            end
            api.GetEquippedForCharacter=function()
                local copy={};for k,v in pairs(equipmentRows) do copy[k]=v end
                return {ok=true,value=copy}
            end
            api.SetEquippedForCharacter=function(character,slot,id)
                local old=equipmentRows[slot]
                for _,piece in ipairs({id or 0,old or 0}) do
                    if piece>0 and not guards.change(piece,{operation='equipment_write'}) then return {ok=false,error={code='denied',message='Held'}} end
                end
                if id and (not pieces[id] or pieces[id].inventoryId~=99) then return {ok=false,error={code='denied',message='Foreign'}} end
                if old then pieces[old].equipmentSnapshot.equipped=false end
                for k,v in pairs(equipmentRows) do if v==id then equipmentRows[k]=nil end end
                equipmentRows[slot]=id
                if id then pieces[id].equipmentSnapshot.equipped=true end
                if loseEquipReply then loseEquipReply=false;return {ok=false,error={code='timeout',message='Lost'}} end
                return {ok=true,value={instanceId=id,slot=slot}}
            end
            api.SetEquipmentBatchForCharacter=function(character,changes)
                if batchHook then batchHook(changes) end
                local desired={};local touched={}
                for _,c in ipairs(changes) do
                    if (equipmentRows[c.slot] or 0)~=c.expected then return {ok=false,code='conflict'} end
                    touched[c.slot]=true
                    for _,id in ipairs({c.expected,c.instanceId}) do
                        if id>0 and (not pieces[id] or pieces[id].inventoryId~=199 or not guards.change(id,{operation='equipment_write'})) then return {ok=false,code='denied'} end
                    end
                    if c.instanceId>0 then desired[c.instanceId]=true end
                end
                for key,id in pairs(equipmentRows) do if desired[id] and not touched[key] then return {ok=false,code='conflict'} end end
                for _,c in ipairs(changes) do equipmentRows[c.slot]=nil end
                for _,c in ipairs(changes) do if c.instanceId>0 then equipmentRows[c.slot]=c.instanceId end end
                for _,item in pairs(pieces) do item.equipmentSnapshot.equipped=false end
                for _,id in pairs(equipmentRows) do pieces[id].equipmentSnapshot.equipped=true end
                if loseEquipReply then loseEquipReply=false;return {ok=false,code='timeout'} end
                return {ok=true,value={changed=true}}
            end
            api.Guards.RegisterMoveGuard=function(_,fn) guards.move=fn;return {ok=true,value=true} end
            api.Guards.RegisterDestroyGuard=function(_,fn) guards.destroy=fn;return {ok=true,value=true} end
            api.Guards.RegisterInstanceChangeGuard=function(_,fn) guards.change=fn;return {ok=true,value=true} end
            api.Guards.UnregisterMoveGuard=function() guards.move=nil end
            api.Guards.UnregisterDestroyGuard=function() guards.destroy=nil end
            api.Guards.UnregisterInstanceChangeGuard=function() guards.change=nil end
            exports['feather-inventory']={
                initiate=function() return api end,
                AwaitReady=function() return {ok=true,value=true} end,
                GetConsumptionContract=function() return {ready=true,conditionKey='condition',conditionMaximum=100} end,
                GetCharacterCollection=function(_,request)
                    if not request.characterId then return {ok=false,code='invalid_input'} end
                    if collectionUnavailable then return {ok=false,code='collection_unavailable'} end
                    if request.adopt then
                        for _,item in pairs(pieces) do if item.inventoryId==99 and item.metadata.stablesTackOrder then
                            item.inventoryId=199;item.revision=item.revision+1
                        end end
                    end
                    return {ok=true,value={id=199,maxItems=500}}
                end,
                GetCharacterCollectionItem=function(_,request)
                    local item=pieces[request.instanceId]
                    return item and item.inventoryId==199 and {ok=true,value=item} or {ok=false,code='not_found'}
                end,
                SetCharacterCollectionEquipment=function(_,request) return api.SetEquipmentBatchForCharacter(request.characterId,request.changes) end,
                GrantCharacterUniqueItemOnce=function(_,request)
                    if not request.grantId then return {ok=false,error={code='invalid_input',message='Validation only'}} end
                    grantRequest=request
                    local r=deliveries[request.grantId]
                    if not r then
                        grants=grants+1
                        r={grantId=request.grantId,characterId=request.characterId,definitionId=request.definitionId,itemName=request.itemName,
                            instanceId=100+grants,revision=0,delivered=true,cancelled=false}
                        deliveries[request.grantId]=r
                        pieces[r.instanceId]={id=r.instanceId,revision=0,inventoryId=request.collectionKey and 199 or 99,metadata=request.metadata,equipmentSnapshot={equipped=false},
                            definition={id=request.definitionId,name=request.itemName,type='item_item',instanceMode='unique'}}
                    end
                    if loseGrant then loseGrant=false;return {ok=false,code='timeout',message='Lost'} end
                    return {ok=true,value=r}
                end
            }
            Stables.OwnedRepository.ReadOwned=function(_,id)
                if foreignHorse then return {ok=false,code='horse_not_owned',message='Foreign'} end
                return {ok=true,value={horseId=id,availability=activeHorse and 'active' or 'stored'}}
            end
            Stables.Checkout.Enabled=function() return Config.commerce.purchasesEnabled end
        ''')
        for path in ('config/tack/catalog.lua','config/tack/categories/saddles.lua','config/tack/categories/saddlecloths.lua','config/tack/categories/stirrups.lua','config/tack/categories/saddle_horns.lua','config/tack/categories/saddle_bags.lua','config/tack/categories/bedrolls.lua','config/tack/categories/bridles.lua','config/tack/categories/holsters.lua','config/tack/categories/horseshoes.lua','config/tack/categories/masks.lua','config/tack/categories/manes.lua','config/tack/categories/tails.lua','config/tack/categories/mustaches.lua','shared/tack.lua','server/tack/feather.lua'):
            self.lua.execute((ROOT/path).read_text(encoding='utf-8'))
        self.tack=self.lua.globals().Stables.Tack
        self.assertTrue(self.tack.Start()['ok'])
        self.catalog=self.lua.globals().Tack.CatalogBySlot.saddle[1].id
        self.lost_commit=False

    def tearDown(self): self.h.tearDown()

    def quote(self):
        return self.tack.Quote(self.lua.globals().session,'valentine',self.h.table({'catalogId':self.catalog,'currency':'dollars'}),self.lua.globals().Authorize)

    def confirm(self,q):
        return self.tack.Confirm(self.lua.globals().session,'valentine',self.h.table({'operationId':q.operationId,'amount':q.amount,'currency':q.currency}),self.lua.globals().Authorize)

    def buy(self):
        q=self.quote();self.assertTrue(q['ok'])
        v=self.confirm(q['value']);self.assertTrue(v['ok'])
        return v['value']

    def equip(self,piece,horse=HORSE,expected=0,source=None,revision=None,slot='saddle'):
        if self.lost_commit:self.lua.globals().loseEquipReply=True;self.lost_commit=False
        if revision is None: revision=self.lua.globals().pieces[piece].revision if piece>0 else 0
        p={'horseId':horse,'slot':slot,'instanceId':piece,'expectedInstanceId':expected,'itemRevision':revision}
        if source:p['fromHorseId']=source
        for key,id in self.lua.globals().equipmentRows.items():
            if id==piece and (key.startswith('tack_stir_') or key.startswith('tack_horn_')): p['fromSaddleId']=int(key.rsplit('_',1)[1])
        return self.tack.Equip(self.lua.globals().session,self.h.table(p),self.lua.globals().Authorize)

    def test_purchase_replay_grants_character_piece_once_and_does_not_equip(self):
        q=self.quote()['value'];v=self.confirm(q)
        self.assertEqual(v['value']['state'],'fulfilled')
        self.assertTrue(self.confirm(q)['ok'])
        self.assertEqual(self.lua.globals().charges,1)
        self.assertEqual(self.lua.globals().grants,1)
        self.assertEqual(len(list(self.lua.globals().equipmentRows.items())),0)
        shop=self.tack.Shop(self.lua.globals().session,HORSE)['value']
        self.assertEqual(len(shop.owned),1)
        self.assertEqual(shop.owned[1].instanceId,v['value']['instanceId'])

    def test_move_preserves_piece_condition_and_exclusive_assignment(self):
        piece=self.buy().instanceId
        self.lua.execute(f'pieces[{piece}].metadata.condition=67')
        self.assertTrue(self.equip(piece)['ok'])
        self.assertFalse(self.lua.globals().guards.move(self.lua.globals().pieces[piece])[0])
        self.assertFalse(self.lua.globals().guards.change(piece)[0])
        self.assertTrue(self.equip(piece,SECOND,source=HORSE)['ok'])
        self.assertEqual(dict(self.lua.globals().equipmentRows.items()),{'horse_'+SECOND:piece})
        self.assertEqual(self.lua.globals().pieces[piece].metadata.condition,67)
        self.assertEqual(self.lua.globals().charges,1)
        self.assertEqual(self.tack.Loadout(self.lua.globals().session,SECOND)['value']['saddle']['catalogId'],self.catalog)
        self.assertTrue(self.equip(0,SECOND,expected=piece)['ok'])
        self.assertFalse(self.lua.globals().guards.move(self.lua.globals().pieces[piece])[0])
        self.assertEqual(len(self.tack.Shop(self.lua.globals().session,SECOND)['value']['owned']),1)

    def test_lost_payment_and_grant_reply_resume_without_duplicate_debit_or_piece(self):
        q=self.quote()['value'];self.lua.globals().losePayment=True
        self.assertFalse(self.confirm(q)['ok'])
        self.lua.globals().loseGrant=True
        self.assertFalse(self.confirm(q)['ok'])
        self.assertTrue(self.confirm(q)['ok'])
        self.assertEqual(self.lua.globals().charges,1)
        self.assertEqual(self.lua.globals().grants,1)

    def test_equipment_lost_commit_reply_refreshes_guard_and_replay_is_safe(self):
        piece=self.buy().instanceId;self.lost_commit=True
        self.assertFalse(self.equip(piece)['ok'])
        self.assertFalse(self.lua.globals().guards.destroy(self.lua.globals().pieces[piece])[0])
        self.assertTrue(self.equip(piece)['ok'])
        self.assertEqual(len(list(self.lua.globals().equipmentRows.items())),1)

    def test_foreign_item_stale_revision_and_active_horse_refused(self):
        piece=self.buy().instanceId
        self.lua.execute(f'pieces[{piece}].inventoryId=77')
        self.assertFalse(self.equip(piece)['ok'])
        self.lua.execute(f'pieces[{piece}].inventoryId=199')
        self.assertFalse(self.equip(piece,revision=2)['ok'])
        self.lua.globals().activeHorse=True
        self.assertFalse(self.equip(piece)['ok'])
        self.assertEqual(len(list(self.lua.globals().equipmentRows.items())),0)

    def test_insufficient_funds_and_expired_price_do_not_deliver(self):
        q=self.quote()['value'];self.lua.globals().balance=0
        self.assertFalse(self.confirm(q)['ok'])
        self.assertEqual(self.lua.globals().grants,0)
        q=self.quote()['value']
        self.lua.execute('Tack.CatalogBySlot.saddle[1].cashPrice=11')
        self.assertEqual(self.confirm(q)['code'],'quote_expired')

    def test_restart_restores_holds_and_pending_fulfillment(self):
        piece=self.buy().instanceId;self.assertTrue(self.equip(piece)['ok'])
        self.lua.execute((ROOT/'server/tack/feather.lua').read_text(encoding='utf-8'))
        self.tack=self.lua.globals().Stables.Tack
        self.assertTrue(self.tack.Start()['ok'])
        self.assertFalse(self.lua.globals().guards.move(self.lua.globals().pieces[piece])[0])
        self.assertEqual(self.tack.Loadout(self.lua.globals().session,HORSE)['value']['saddle']['instanceId'],piece)

    def test_pending_grant_is_recovered_after_module_reload(self):
        q=self.quote()['value'];self.lua.globals().loseGrant=True
        self.assertFalse(self.confirm(q)['ok'])
        self.lua.execute((ROOT/'server/tack/feather.lua').read_text(encoding='utf-8'))
        self.tack=self.lua.globals().Stables.Tack
        self.assertTrue(self.tack.Start()['ok']);self.tack.Tick()
        self.assertEqual(self.db.execute('SELECT state FROM fs_tack_orders').fetchone()[0],'fulfilled')
        self.assertEqual(self.lua.globals().charges,1)
        self.assertEqual(self.lua.globals().grants,1)

    def test_trust_preflight_refuses_before_payment_or_grant(self):
        self.lua.execute("exports['feather-inventory'].GrantCharacterUniqueItemOnce=function() return {ok=false,error={code='authorization_denied',message='Not trusted'}} end")
        self.assertEqual(self.tack.Start()['code'],'tack_grant_not_trusted')
        self.assertFalse(self.quote()['ok'])
        self.assertEqual(self.lua.globals().charges,0)
        self.assertEqual(self.lua.globals().grants,0)

    def test_revision_race_before_fence_prevents_assignment(self):
        piece=self.buy().instanceId
        self.lua.execute(f'fenceHook=function() pieces[{piece}].revision=1 end')
        self.assertFalse(self.equip(piece)['ok'])
        self.assertEqual(len(list(self.lua.globals().equipmentRows.items())),0)

    def test_stale_source_and_destination_cannot_steal_assignment(self):
        piece=self.buy().instanceId
        self.assertTrue(self.equip(piece)['ok'])
        self.assertEqual(self.equip(piece,SECOND)['code'],'tack_conflict')
        self.assertEqual(dict(self.lua.globals().equipmentRows.items()),{'horse_'+HORSE:piece})
        second=self.buy().instanceId
        self.assertEqual(self.equip(second)['code'],'tack_conflict')
        self.assertEqual(dict(self.lua.globals().equipmentRows.items()),{'horse_'+HORSE:piece})

    def test_free_policy_delivers_without_currency_transfer(self):
        self.lua.execute('Tack.CatalogBySlot.saddle[1].currency=4')
        self.assertEqual(self.buy().amount,0)
        self.assertEqual(self.lua.globals().charges,0)
        self.assertEqual(self.lua.globals().grants,1)

    def test_known_full_inventory_refuses_before_charging(self):
        q=self.quote()['value'];self.lua.globals().fullInventory=True
        self.assertEqual(self.confirm(q)['code'],'tack_inventory_full')
        self.assertEqual(self.quote()['code'],'tack_inventory_full')
        self.assertEqual(self.lua.globals().charges,0)

    def test_movement_guard_checks_persisted_equipment_snapshot_after_restart(self):
        piece=self.buy().instanceId;self.assertTrue(self.equip(piece)['ok'])
        self.lua.execute((ROOT/'server/tack/feather.lua').read_text(encoding='utf-8'))
        self.tack=self.lua.globals().Stables.Tack;self.assertTrue(self.tack.Start()['ok'])
        self.assertFalse(self.lua.globals().guards.move(self.lua.globals().pieces[piece])[0])
        self.lua.globals().pieces[piece].equipmentSnapshot=None
        self.assertFalse(self.lua.globals().guards.move(self.lua.globals().pieces[piece])[0])

    def test_remaining_categories_purchase_equip_move_and_unequip(self):
        saddle_a=self.buy().instanceId;self.assertTrue(self.equip(saddle_a).ok)
        saddle_b=self.buy().instanceId;self.assertTrue(self.equip(saddle_b,SECOND).ok)
        for slot in ('saddlebag','bedroll','bridle','holster','horseshoes','mask','mane','tail','mustache'):
            with self.subTest(slot=slot):
                self.catalog=self.lua.globals().Tack.CatalogBySlot[slot][1].id
                piece=self.buy().instanceId
                self.assertTrue(self.equip(piece,slot=slot).ok)
                self.assertEqual(self.tack.Loadout(self.lua.globals().session,HORSE).value[slot].instanceId,piece)
                self.assertTrue(self.equip(piece,SECOND,source=HORSE,slot=slot).ok)
                self.assertIsNone(self.tack.Loadout(self.lua.globals().session,HORSE).value[slot])
                self.assertTrue(self.equip(0,SECOND,expected=piece,slot=slot).ok)
                self.assertIsNone(self.tack.Loadout(self.lua.globals().session,SECOND).value[slot])

    def test_independent_saddle_accessories_require_saddle_and_fence_removal(self):
        for slot in ('saddlebag','bedroll','holster'):
            self.catalog=self.lua.globals().Tack.CatalogBySlot[slot][1].id
            piece=self.buy().instanceId
            self.assertEqual(self.equip(piece,slot=slot).code,'tack_saddle_required')
            self.catalog=self.lua.globals().Tack.CatalogBySlot.saddle[1].id
            saddle=self.buy().instanceId;self.assertTrue(self.equip(saddle).ok)
            self.assertTrue(self.equip(piece,slot=slot).ok)
            self.assertEqual(self.equip(0,expected=saddle).code,'tack_dependents_equipped')
            self.assertEqual(self.equip(saddle,SECOND,source=HORSE).code,'tack_dependents_equipped')
            self.assertTrue(self.equip(0,expected=piece,slot=slot).ok)
            self.assertTrue(self.equip(0,expected=saddle).ok)

    def test_each_new_category_moves_same_piece_preserving_other_horse_equipment(self):
        saddle_a=self.buy().instanceId;self.assertTrue(self.equip(saddle_a)['ok'])
        saddle_b=self.buy().instanceId;self.assertTrue(self.equip(saddle_b,SECOND)['ok'])
        pieces={}
        for slot in ('saddlecloth','stirrups','saddle_horn'):
            with self.subTest(slot=slot):
                self.catalog=self.lua.globals().Tack.CatalogBySlot[slot][1].id
                piece=self.buy().instanceId;pieces[slot]=piece
                self.lua.globals().pieces[piece].metadata.condition=67
                self.assertTrue(self.equip(piece,slot=slot)['ok'])
                self.assertEqual(self.tack.Loadout(self.lua.globals().session,HORSE)['value'][slot]['instanceId'],piece)
        charges=self.lua.globals().charges
        for slot,piece in pieces.items():
            self.assertTrue(self.equip(piece,SECOND,source=HORSE,slot=slot)['ok'])
            self.assertEqual(self.lua.globals().pieces[piece].metadata.condition,67)
        a=self.tack.Loadout(self.lua.globals().session,HORSE)['value']
        b=self.tack.Loadout(self.lua.globals().session,SECOND)['value']
        self.assertEqual(list(a.keys()),['saddle'])
        self.assertEqual(a.saddle.instanceId,saddle_a)
        self.assertEqual(b.saddle.instanceId,saddle_b)
        self.assertEqual(set(b.keys()),{'saddle','saddlecloth','stirrups','saddle_horn'})
        self.assertEqual(self.lua.globals().charges,charges)
        self.assertTrue(all(len(slot)<=50 for slot in self.lua.globals().equipmentRows.keys()))

    def test_stirrups_and_horn_require_parent_but_cloth_is_independent(self):
        for slot in ('stirrups','saddle_horn'):
            self.catalog=self.lua.globals().Tack.CatalogBySlot[slot][1].id
            piece=self.buy().instanceId
            self.assertEqual(self.equip(piece,slot=slot)['code'],'tack_saddle_required')
        self.catalog=self.lua.globals().Tack.CatalogBySlot.saddlecloth[1].id
        piece=self.buy().instanceId;self.assertTrue(self.equip(piece,slot='saddlecloth')['ok'])
        self.assertEqual(set(self.tack.Loadout(self.lua.globals().session,HORSE)['value'].keys()),{'saddlecloth'})

    def test_assembly_moves_unequips_and_replaces_as_a_unit(self):
        saddle=self.buy().instanceId;self.assertTrue(self.equip(saddle)['ok'])
        parts={}
        for slot in ('stirrups','saddle_horn'):
            self.catalog=self.lua.globals().Tack.CatalogBySlot[slot][1].id
            part=self.buy().instanceId;parts[slot]=part
            self.assertTrue(self.equip(part,slot=slot)['ok'])
        self.assertTrue(self.equip(saddle,SECOND,source=HORSE)['ok'])
        load=self.tack.Loadout(self.lua.globals().session,SECOND)['value']
        for slot,id in parts.items(): self.assertEqual(load[slot].instanceId,id)
        self.assertTrue(self.equip(0,SECOND,expected=saddle)['ok'])
        self.assertFalse(list(self.tack.Loadout(self.lua.globals().session,SECOND)['value'].keys()))
        self.assertTrue(self.equip(saddle)['ok'])
        for slot,id in parts.items(): self.assertEqual(self.tack.Loadout(self.lua.globals().session,HORSE)['value'][slot].instanceId,id)
        self.catalog=self.lua.globals().Tack.CatalogBySlot.saddle[1].id
        other=self.buy().instanceId
        self.assertTrue(self.equip(other,expected=saddle)['ok'])
        self.assertEqual(set(self.tack.Loadout(self.lua.globals().session,HORSE)['value'].keys()),{'saddle'})
        self.assertTrue(self.equip(saddle,SECOND)['ok'])
        self.assertEqual(set(self.tack.Loadout(self.lua.globals().session,SECOND)['value'].keys()),{'saddle','stirrups','saddle_horn'})
        self.assertEqual(self.lua.globals().charges,4)

    def test_detach_component_from_unequipped_assembly_and_legacy_assignment_conversion(self):
        saddle=self.buy().instanceId;self.assertTrue(self.equip(saddle)['ok'])
        self.catalog=self.lua.globals().Tack.CatalogBySlot.stirrups[1].id
        part=self.buy().instanceId
        self.lua.execute(f"equipmentRows['horse_stir_{HORSE}']={part}")
        self.assertEqual(self.tack.Loadout(self.lua.globals().session,HORSE)['value'].stirrups.instanceId,part)
        self.assertIsNone(self.lua.globals().equipmentRows['horse_stir_'+HORSE])
        self.assertEqual(self.lua.globals().equipmentRows['tack_stir_'+str(saddle)],part)
        self.assertTrue(self.equip(0,expected=saddle)['ok'])
        spec=self.lua.table_from(dict(horseId=HORSE,slot='stirrups',instanceId=part,expectedInstanceId=part,itemRevision=0,detach=True,fromSaddleId=saddle))
        self.assertTrue(self.tack.Equip(self.lua.globals().session,spec,self.lua.globals().Authorize)['ok'])
        self.assertIsNone(self.lua.globals().equipmentRows['tack_stir_'+str(saddle)])
        self.assertTrue(self.lua.globals().guards.move(self.lua.globals().pieces[part]))

    def test_assembly_conversion_lost_reply_and_restart_keep_identity(self):
        saddle=self.buy().instanceId;self.assertTrue(self.equip(saddle)['ok'])
        self.catalog=self.lua.globals().Tack.CatalogBySlot.saddle_horn[1].id
        part=self.buy().instanceId
        self.lua.execute(f"equipmentRows['horse_horn_{HORSE}']={part};loseEquipReply=true")
        self.assertFalse(self.tack.Loadout(self.lua.globals().session,HORSE)['ok'])
        self.assertEqual(self.tack.Loadout(self.lua.globals().session,HORSE)['value'].saddle_horn.instanceId,part)
        self.assertTrue(self.equip(0,expected=saddle)['ok'])
        self.lua.execute((ROOT/'server/tack/feather.lua').read_text(encoding='utf-8'))
        self.tack=self.lua.globals().Stables.Tack;self.assertTrue(self.tack.Start()['ok'])
        self.assertFalse(self.lua.globals().guards.move(self.lua.globals().pieces[saddle])[0])
        self.assertFalse(self.lua.globals().guards.destroy(self.lua.globals().pieces[part])[0])
        self.assertTrue(self.equip(saddle,SECOND)['ok'])
        self.assertEqual(self.tack.Loadout(self.lua.globals().session,SECOND)['value'].saddle_horn.instanceId,part)
        self.assertEqual(self.lua.globals().grants,2)

    def test_batch_refusal_keeps_entire_saddle_assignment_and_parts(self):
        saddle=self.buy().instanceId;self.assertTrue(self.equip(saddle)['ok'])
        self.catalog=self.lua.globals().Tack.CatalogBySlot.stirrups[1].id
        part=self.buy().instanceId;self.assertTrue(self.equip(part,slot='stirrups')['ok'])
        before=dict(self.lua.globals().equipmentRows.items())
        self.lua.execute("api.SetEquipmentBatchForCharacter=function() return {ok=false,code='denied'} end")
        self.assertFalse(self.equip(saddle,SECOND,source=HORSE)['ok'])
        self.assertEqual(dict(self.lua.globals().equipmentRows.items()),before)
        self.assertFalse(self.lua.globals().guards.change(saddle)[0])

    def test_stale_detach_from_different_saddle_is_refused(self):
        saddle=self.buy().instanceId;self.assertTrue(self.equip(saddle)['ok'])
        self.catalog=self.lua.globals().Tack.CatalogBySlot.stirrups[1].id
        part=self.buy().instanceId;self.assertTrue(self.equip(part,slot='stirrups')['ok'])
        spec=self.lua.table_from(dict(horseId=HORSE,slot='stirrups',instanceId=part,expectedInstanceId=part,
            itemRevision=0,detach=True,fromSaddleId=saddle+1,fromHorseId=HORSE))
        self.assertEqual(self.tack.Equip(self.lua.globals().session,spec,self.lua.globals().Authorize)['code'],'tack_conflict')
        self.assertEqual(self.tack.Loadout(self.lua.globals().session,HORSE)['value'].stirrups.instanceId,part)

    def test_old_carried_piece_adopts_once_preserving_condition_and_equipment(self):
        saddle=self.buy().instanceId;self.assertTrue(self.equip(saddle)['ok'])
        self.lua.execute(f'pieces[{saddle}].inventoryId=99;pieces[{saddle}].metadata.condition=37')
        before=self.lua.globals().pieces[saddle].revision
        shop=self.tack.Shop(self.lua.globals().session,HORSE)
        self.assertTrue(shop['ok']);self.assertEqual(shop['value']['storage'],'stable')
        self.assertEqual(self.lua.globals().pieces[saddle].inventoryId,199)
        self.assertEqual(self.lua.globals().pieces[saddle].revision,before+1)
        self.assertEqual(self.lua.globals().pieces[saddle].metadata.condition,37)
        self.assertEqual(shop['value'].loadout.saddle,saddle)
        self.assertTrue(self.tack.Shop(self.lua.globals().session,HORSE)['ok'])
        self.assertEqual(self.lua.globals().pieces[saddle].revision,before+1)

    def test_new_grant_targets_storage_and_old_pending_order_keeps_original_payload(self):
        import json
        piece=self.buy().instanceId
        self.assertEqual(self.lua.globals().grantRequest.collectionKey,'stables.tack.v1')
        self.assertEqual(self.lua.globals().pieces[piece].inventoryId,199)
        q=self.quote()['value']
        row=self.db.execute('SELECT record_json FROM fs_tack_orders WHERE operation_id=?',(q.operationId,)).fetchone()[0]
        terms=json.loads(row);terms.pop('collectionKey')
        self.db.execute('UPDATE fs_tack_orders SET record_json=? WHERE operation_id=?',(json.dumps(terms),q.operationId));self.db.commit()
        self.lua.globals().loseGrant=True
        self.assertFalse(self.confirm(q)['ok'])
        self.assertTrue(self.confirm(q)['ok'])
        self.assertIsNone(self.lua.globals().grantRequest.collectionKey)
        self.assertEqual(self.lua.globals().pieces[102].inventoryId,199)
        self.assertEqual(self.lua.globals().grants,2)
        self.assertEqual(self.lua.globals().charges,2)

    def test_untrusted_collection_policy_refuses_startup_without_payment(self):
        self.lua.execute("exports['feather-inventory'].GetCharacterCollection=function() return {ok=false,code='authorization_denied'} end")
        self.assertEqual(self.tack.Start()['code'],'tack_collection_not_trusted')
        self.assertEqual(self.lua.globals().charges,0)
        self.assertEqual(self.lua.globals().grants,0)

    def test_collection_unavailable_refuses_before_payment(self):
        self.lua.globals().collectionUnavailable=True
        self.assertFalse(self.quote()['ok'])
        self.assertEqual(self.lua.globals().charges,0)
        self.assertEqual(self.lua.globals().grants,0)

    def test_component_fit_fences_parent_moved_after_snapshot(self):
        saddle=self.buy().instanceId;self.assertTrue(self.equip(saddle)['ok'])
        self.catalog=self.lua.globals().Tack.CatalogBySlot.stirrups[1].id
        component=self.buy().instanceId
        self.lua.execute(f"batchHook=function() equipmentRows['horse_{HORSE}']=nil;equipmentRows['tack_saddle_{saddle}']={saddle};batchHook=nil end")
        self.assertFalse(self.equip(component,slot='stirrups')['ok'])
        self.assertIsNone(self.lua.globals().equipmentRows['tack_stir_'+str(saddle)])
        self.assertIsNotNone(self.lua.globals().pieces[component])

    def test_old_saddle_receipt_and_slot_remain_compatible(self):
        import json
        q=self.quote()['value']
        row=self.db.execute('SELECT record_json FROM fs_tack_orders').fetchone()[0]
        terms=json.loads(row);terms['kind']='saddle.v1';terms.pop('slot');terms.pop('itemName')
        self.db.execute('UPDATE fs_tack_orders SET record_json=?',(json.dumps(terms),));self.db.commit()
        self.lua.globals().loseGrant=True
        self.assertFalse(self.confirm(q)['ok'])
        self.assertTrue(self.confirm(q)['ok'])
        item=self.lua.globals().pieces[101]
        self.assertEqual(set(item.metadata.keys()),{'stablesTackOrder','stablesTackCatalog','condition'})
        self.assertTrue(self.equip(101)['ok'])
        self.assertEqual(self.lua.globals().equipmentRows['horse_'+HORSE],101)
        self.assertEqual(self.lua.globals().grants,1)
        self.assertEqual(self.lua.globals().charges,1)

    def test_item_cannot_equip_in_another_category(self):
        piece=self.buy().instanceId
        self.assertEqual(self.equip(piece,slot='saddlecloth')['code'],'tack_item_unavailable')
        self.assertEqual(len(list(self.lua.globals().equipmentRows.items())),0)


if __name__=='__main__':unittest.main()
