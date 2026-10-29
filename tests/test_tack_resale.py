"""Real Stables sale SQL/Lua with durable Inventory/Economy provider doubles."""
import unittest
import test_tack as tack_tests
from test_call_repository import HORSE, CHAR
from test_feather_boundary import ROOT

class ResaleTest(unittest.TestCase):
    def setUp(self):
        self.h=tack_tests.TackTest();self.h.setUp()
        self.lua=self.h.lua;self.db=self.h.db
        def plain(value):
            if hasattr(value,'items'):
                fields=dict(value.items())
                if fields and set(fields)==set(range(1,len(fields)+1)): return [plain(fields[n]) for n in range(1,len(fields)+1)]
                return {k:plain(v) for k,v in fields.items()}
            return value
        self.h.h.python=plain
        self.db.executescript("CREATE TABLE fs_tack_sales(operation_id TEXT PRIMARY KEY,character_id TEXT,state TEXT,record_json TEXT,updated_at TEXT DEFAULT CURRENT_TIMESTAMP);")
        self.lua.execute("""
            Config.tack.resaleEnabled=true;Config.tack.resalePercent=50
            exports['feather-economy'].GetSystemAccount=function(_,p) return {ok=true,value={accountId=session.sessionId,accountType=p.accountType,currency=p.currency,status='open'}} end
            retiredReceipts={};payoutReceipts={};retirements=0;credits=0;earned={dollars=0,gold=0}
            exports['feather-economy'].CheckIssue=function(_,q)
                if not q.amount then return {ok=false,code='authorization_denied',message='Invalid preflight'} end
                if payoutDenied then return {ok=false,code='authorization_denied',message='Denied'} end
                return {ok=true,value={allowed=true,sourceAccountId=session.sessionId}}
            end
            exports['feather-economy'].Issue=function(_,q)
                if failPayout or failGold and q.currency=='gold' then return {ok=false,code='timeout',message='Pending'} end
                local r=payoutReceipts[q.idempotencyKey]
                if not r then
                    credits=credits+1;earned[q.currency]=earned[q.currency]+q.amount
                    r={transactionId=q.referenceId,operation='issue',currency=q.currency,amount=q.amount,fromAccountId=session.sessionId,
                        toAccountId=q.accountId,reasonCode=q.reasonCode,referenceType=q.referenceType,referenceId=q.referenceId,sourceResource='bcc-stables'}
                    payoutReceipts[q.idempotencyKey]=r
                end
                if losePayout then losePayout=false;return {ok=false,code='timeout',message='Lost'} end
                return {ok=true,value=r}
            end
            exports['feather-inventory'].RetireCharacterCollectionItemsOnce=function(_,q)
                if not q.characterId then return {ok=false,code='invalid_input'} end
                if beforeRetire then beforeRetire(q);beforeRetire=nil end
                local r=retiredReceipts[q.operationId]
                if not r then
                    local ids={}
                    for _,item in ipairs(q.items) do
                        if not pieces[item.instanceId] or pieces[item.instanceId].revision~=item.revision then return {ok=false,code='collection_conflict'} end
                        ids[item.instanceId]=true
                    end
                    for slot,id in pairs(equipmentRows) do
                        if (ids[id] or q.equipment[slot]~=nil) and q.equipment[slot]~=id then return {ok=false,code='collection_conflict'} end
                    end
                    for slot,id in pairs(q.equipment) do if (equipmentRows[slot] or 0)~=id then return {ok=false,code='collection_conflict'} end end
                    for id in pairs(ids) do
                        local allowed=guards.destroy(pieces[id],{resource='bcc-stables',reason='collection_retirement'})
                        if not allowed then return {ok=false,code='denied'} end
                    end
                    for slot,id in pairs(equipmentRows) do if ids[id] then equipmentRows[slot]=nil end end
                    for id in pairs(ids) do pieces[id]=nil end
                    retirements=retirements+1
                    r={operationId=q.operationId,characterId=q.characterId,count=#q.items,retired=true}
                    retiredReceipts[q.operationId]=r
                end
                if loseRetire then loseRetire=false;return {ok=false,code='timeout'} end
                return {ok=true,value=r}
            end
        """)
        self.lua.execute((ROOT/'server/tack/resale.lua').read_text(encoding='utf-8'))
        self.sale=self.lua.globals().Stables.TackResale
        self.assertTrue(self.sale.Start().ok)
    def tearDown(self): self.h.tearDown()
    def quote(self,id): return self.sale.Quote(self.lua.globals().session,'valentine',self.lua.table_from({'instanceId':id}),self.lua.globals().Authorize)
    def confirm(self,q): return self.sale.Confirm(self.lua.globals().session,'valentine',self.lua.table_from({'operationId':q.operationId,'dollars':q.totals.dollars,'gold':q.totals.gold}),self.lua.globals().Authorize)
    def test_loose_piece_sale_and_replay_pay_and_remove_once(self):
        id=self.h.buy().instanceId
        self.lua.globals().pieces[id].metadata.condition=60
        q=self.quote(id);self.assertTrue(q.ok)
        self.assertEqual(q.value.totals.dollars,300)
        self.assertEqual(self.confirm(q.value).value.state,'sold')
        self.assertEqual(self.confirm(q.value).value.state,'sold')
        self.assertEqual(self.lua.globals().retirements,1);self.assertEqual(self.lua.globals().credits,1)
        self.assertIsNone(self.lua.globals().pieces[id])
    def test_parked_assembly_sale_includes_parts_but_not_saddlecloth(self):
        id=self.h.buy().instanceId;self.assertTrue(self.h.equip(id).ok)
        for slot in ('stirrups','saddle_horn','saddlecloth'):
            self.h.catalog=self.lua.globals().Tack.CatalogBySlot[slot][1].id
            piece=self.h.buy().instanceId;self.assertTrue(self.h.equip(piece,slot=slot).ok)
        self.assertTrue(self.h.equip(0,expected=id).ok)
        q=self.quote(id);self.assertTrue(q.ok);self.assertEqual(len(q.value['items']),3)
        self.assertEqual(q.value.totals.dollars,1500)
        self.assertTrue(self.confirm(q.value).ok)
        self.assertEqual(len(list(self.lua.globals().pieces.items())),1)
        self.assertEqual(self.lua.globals().pieces[104].definition.name,'horse_saddlecloth')
    def test_fitted_saddle_or_component_refused_and_policy_denial_keeps_items(self):
        id=self.h.buy().instanceId;self.h.equip(id)
        self.assertEqual(self.quote(id).code,'tack_sale_fitted')
        self.h.equip(0,expected=id);self.lua.globals().payoutDenied=True
        self.assertEqual(self.quote(id).code,'tack_sale_payout_unavailable')
        self.assertIsNotNone(self.lua.globals().pieces[id]);self.assertEqual(self.lua.globals().credits,0)
    def test_changed_condition_or_policy_refuses_quote_before_removal(self):
        id=self.h.buy().instanceId;q=self.quote(id).value
        self.lua.globals().pieces[id].metadata.condition=20
        self.assertEqual(self.confirm(q).code,'tack_conflict')
        self.lua.execute('Config.tack.resalePercent=20')
        self.assertEqual(self.confirm(q).code,'quote_expired')
        self.assertEqual(self.lua.globals().retirements,0)
    def test_lost_retirement_and_payout_replies_recover_without_duplicates(self):
        id=self.h.buy().instanceId;q=self.quote(id).value
        self.lua.globals().loseRetire=True;self.assertFalse(self.confirm(q).ok)
        self.lua.globals().losePayout=True;self.assertFalse(self.confirm(q).ok)
        self.assertTrue(self.confirm(q).ok)
        self.assertEqual(self.lua.globals().retirements,1);self.assertEqual(self.lua.globals().credits,1)
    def test_restart_recovers_removed_items_pending_payout(self):
        id=self.h.buy().instanceId;q=self.quote(id).value
        self.lua.globals().failPayout=True;self.assertFalse(self.confirm(q).ok)
        self.lua.execute((ROOT/'server/tack/resale.lua').read_text(encoding='utf-8'))
        self.sale=self.lua.globals().Stables.TackResale;self.sale.Start()
        self.lua.globals().failPayout=False;self.sale.Tick()
        self.assertEqual(self.db.execute('SELECT state FROM fs_tack_sales').fetchone()[0],'sold')
        self.assertEqual(self.lua.globals().retirements,1);self.assertEqual(self.lua.globals().credits,1)
    def test_assembly_change_after_confirmation_is_fenced_without_payout(self):
        id=self.h.buy().instanceId;q=self.quote(id).value
        self.lua.execute(f"beforeRetire=function() equipmentRows['tack_horn_{id}']=999 end")
        self.assertFalse(self.confirm(q).ok)
        self.assertIsNotNone(self.lua.globals().pieces[id]);self.assertEqual(self.lua.globals().credits,0)
        self.assertEqual(self.db.execute('SELECT state FROM fs_tack_sales').fetchone()[0],'cancelled')
    def test_mixed_currency_assembly_recovers_partial_payout_without_duplicate_cash(self):
        id=self.h.buy().instanceId;self.h.equip(id)
        catalog=self.lua.globals().Tack.CatalogBySlot.saddle_horn[1].id
        offer=self.h.tack.Quote(self.lua.globals().session,'valentine',self.lua.table_from({'catalogId':catalog,'currency':'gold'}),self.lua.globals().Authorize)
        self.assertTrue(offer.ok)
        horn=self.h.confirm(offer.value).value.instanceId;self.assertTrue(self.h.equip(horn,slot='saddle_horn').ok)
        self.h.equip(0,expected=id)
        q=self.quote(id).value
        self.assertEqual(q.totals.dollars,500);self.assertEqual(q.totals.gold,50)
        self.lua.globals().failGold=True
        self.assertFalse(self.confirm(q).ok)
        self.assertEqual(self.lua.globals().earned.dollars,500);self.assertEqual(self.lua.globals().earned.gold,0)
        self.lua.globals().failGold=False;self.assertTrue(self.confirm(q).ok)
        self.assertEqual(self.lua.globals().earned.dollars,500);self.assertEqual(self.lua.globals().earned.gold,50)
        self.assertEqual(self.lua.globals().retirements,1);self.assertEqual(self.lua.globals().credits,2)
    def test_expired_or_tampered_quote_and_stale_session_leave_piece_untouched(self):
        id=self.h.buy().instanceId;q=self.quote(id).value
        forged=self.lua.table_from({'operationId':q.operationId,'dollars':q.totals.dollars+1,'gold':q.totals.gold})
        self.assertEqual(self.sale.Confirm(self.lua.globals().session,'valentine',forged,self.lua.globals().Authorize).code,'price_conflict')
        self.lua.globals().current=False;self.assertFalse(self.confirm(q).ok)
        self.lua.globals().current=True;self.lua.execute('local now=os.time();os.time=function() return now+1000 end')
        self.assertEqual(self.confirm(q).code,'quote_expired')
        self.assertEqual(self.lua.globals().retirements,0);self.assertEqual(self.lua.globals().credits,0)
        self.assertIsNotNone(self.lua.globals().pieces[id])

    def test_free_tack_has_no_sale_value(self):
        self.lua.execute('Tack.CatalogBySlot.saddle[1].currency=4')
        self.assertEqual(self.quote(self.h.buy().instanceId).code,'tack_sale_no_value')

if __name__=='__main__':unittest.main()
