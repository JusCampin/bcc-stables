"""Real sale SQL/Lua, isolated SQLite and durable provider receipts; no live assets."""
import unittest
import test_checkout as checkout_tests
import test_tack as tack_tests
from test_feather_boundary import ROOT
from test_call_repository import HORSE, CHAR


class HorseResaleTest(unittest.TestCase):
    def setUp(self):
        self.h=checkout_tests.CheckoutTest();self.h.setUp()
        self.lua,self.db=self.h.lua,self.h.db
        purchase=self.h.quote().value
        self.assertTrue(self.h.confirm(purchase).ok)
        self.horse=purchase.horseId
        self.db.executescript('CREATE TABLE fs_horse_sales(operation_id TEXT PRIMARY KEY,character_id TEXT,horse_id TEXT,state TEXT,record_json TEXT,updated_at TEXT DEFAULT CURRENT_TIMESTAMP);')
        self.lua.execute('''
            Config.sales={enabled=true,purchasedHorsePriceMultiplier=0.70}
            detachments=0;retirements=0;credits=0;retired={};paid={};now=1000
            os.time=function() return now end
            Stables.Tack={Enabled=function() return true end,ReleaseSoldHorse=function()
                if detachDenied then return {ok=false,code='tack_pending'} end
                detachments=detachments+1;return {ok=true,value=true}
            end}
            exports['feather-economy'].GetSystemAccount=function(_,p) return {ok=true,value={accountId=session.sessionId,accountType=p.accountType,currency=p.currency,status='open'}} end
            exports['feather-economy'].CheckIssue=function(_,p)
                if payoutDenied then return {ok=false,code='authorization_denied',message='Denied'} end
                return {ok=true,value={allowed=true,sourceAccountId=session.sessionId}}
            end
            exports['feather-assets'].RetireAsset=function(_,p)
                local a=retired[p.requestId]
                if not a then
                    a=assets[p.assetId]
                    if a.revision~=p.expectedRevision then return {ok=false,code='revision_conflict',message='Changed'} end
                    a.status='retired';a.owner=nil;a.revision=a.revision+1
                    retired[p.requestId]=a;retirements=retirements+1
                end
                if loseRetire then loseRetire=false;return {ok=false,code='timeout',message='Reply unavailable'} end
                return {ok=true,value=a}
            end
            exports['feather-economy'].Issue=function(_,p)
                if payoutUnavailable then return {ok=false,code='timeout',message='Reply unavailable'} end
                local receipt=paid[p.idempotencyKey]
                if not receipt then
                    credits=credits+1
                    receipt={transactionId=p.referenceId,operation='issue',amount=p.amount,currency=p.currency,
                        fromAccountId=session.sessionId,toAccountId=p.accountId,reasonCode=p.reasonCode,
                        referenceType=p.referenceType,referenceId=p.referenceId,sourceResource='bcc-stables'}
                    paid[p.idempotencyKey]=receipt
                end
                if loseIssue then loseIssue=false;return {ok=false,code='timeout',message='Reply unavailable'} end
                return {ok=true,value=receipt}
            end
        ''')
        self.load()

    def load(self):
        self.lua.execute((ROOT/'server/horse/resale.lua').read_text(encoding='utf-8'))
        self.sale=self.lua.globals().Stables.HorseResale
        self.assertTrue(self.sale.Start().ok)

    def tearDown(self): self.h.tearDown()
    def quote(self):
        return self.sale.Quote(self.lua.globals().session,'valentine',self.h.table({'horseId':self.horse,'currency':'dollars'}),self.lua.globals().Authorize)
    def confirm(self,q,**changes):
        return self.sale.Confirm(self.lua.globals().session,'valentine',self.h.table({'operationId':q.operationId,'amount':q.amount,'currency':q.currency,**changes}),self.lua.globals().Authorize)
    def availability(self): return self.db.execute('SELECT availability FROM fs_horses WHERE horse_id=?',(self.horse,)).fetchone()[0]

    def test_original_price_rounding_sale_and_replay(self):
        q=self.quote().value
        self.assertEqual(q.amount,5300)  # ceil(75 * .70), original whole-dollar rule
        self.assertEqual(self.confirm(q).value.state,'sold')
        self.assertEqual(self.confirm(q).value.state,'sold')
        self.assertEqual(self.availability(),'sold')
        self.assertEqual(self.lua.globals().credits,1);self.assertEqual(self.lua.globals().retirements,1)
        self.assertIsNone(self.db.execute('SELECT selected_horse_id FROM fs_character_stables').fetchone()[0])
        self.assertEqual(self.h.count('fs_horses'),1)  # historical record retained

    def test_live_call_and_changed_revision_refuse_without_retirement(self):
        q=self.quote().value
        self.db.execute('INSERT INTO fs_call_slots VALUES (?,?)',(CHAR,HORSE));self.db.commit()
        self.assertEqual(self.confirm(q).code,'horse_busy')
        self.assertEqual(self.availability(),'stored');self.assertEqual(self.lua.globals().credits,0)
        self.db.execute('DELETE FROM fs_call_slots');self.db.execute('UPDATE fs_horses SET revision=revision+1');self.db.commit()
        self.assertEqual(self.confirm(q).code,'revision_conflict')

    def test_changed_terms_expiry_and_policy_do_not_reserve(self):
        q=self.quote().value
        self.assertEqual(self.confirm(q,amount=q.amount+1).code,'price_conflict')
        self.lua.globals().payoutDenied=True
        self.assertEqual(self.confirm(q).code,'horse_sale_payout_unavailable')
        self.lua.globals().payoutDenied=False;self.lua.globals().now=1061
        self.assertEqual(self.confirm(q).code,'quote_expired');self.assertEqual(self.availability(),'stored')

    def test_lost_retirement_ack_recovers_same_asset_and_payment(self):
        q=self.quote().value;self.lua.globals().loseRetire=True
        self.assertFalse(self.confirm(q).ok);self.assertEqual(self.availability(),'selling')
        self.assertEqual(self.lua.globals().credits,0)
        self.load();self.sale.Tick()
        self.assertEqual(self.availability(),'sold');self.assertEqual(self.lua.globals().credits,1)
        self.assertEqual(self.lua.globals().retirements,1)

    def test_lost_payout_ack_offline_recovery_does_not_credit_twice(self):
        q=self.quote().value;self.lua.globals().loseIssue=True
        self.assertFalse(self.confirm(q).ok);self.assertEqual(self.lua.globals().credits,1)
        self.lua.globals().current=False;self.load();self.sale.Tick()
        self.assertEqual(self.availability(),'sold');self.assertEqual(self.lua.globals().credits,1)

    def test_tack_failure_retains_reservation_without_retiring(self):
        q=self.quote().value;self.lua.globals().detachDenied=True
        self.assertFalse(self.confirm(q).ok);self.assertEqual(self.availability(),'selling')
        self.assertEqual(self.lua.globals().retirements,0)
        self.lua.globals().detachDenied=False;self.sale.Tick()
        self.assertEqual(self.availability(),'sold')

    def test_two_quotes_only_one_can_sell(self):
        first,second=self.quote().value,self.quote().value
        self.assertTrue(self.confirm(first).ok);self.assertFalse(self.confirm(second).ok)
        self.assertEqual(self.lua.globals().credits,1)

    def test_gold_quote_and_invalid_currency(self):
        quote=self.sale.Quote(self.lua.globals().session,'valentine',self.h.table({'horseId':self.horse,'currency':'gold'}),self.lua.globals().Authorize)
        self.assertTrue(quote.ok);self.assertEqual(quote.value.amount,300)
        self.assertTrue(self.confirm(quote.value).ok)

    def test_definite_revision_conflict_restores_stored_without_payment(self):
        q=self.quote().value;self.lua.globals().detachDenied=True
        self.assertFalse(self.confirm(q).ok)
        self.lua.globals().assets[self.horse].revision=2
        self.lua.globals().detachDenied=False;self.sale.Tick()
        self.assertEqual(self.availability(),'stored');self.assertEqual(self.lua.globals().credits,0)
        self.assertEqual(self.db.execute('SELECT state FROM fs_horse_sales').fetchone()[0],'cancelled')

    def test_sold_horse_frees_purchase_capacity(self):
        self.lua.globals().Config.horseLimits.player=1
        q=self.quote().value;self.assertTrue(self.confirm(q).ok)
        purchase=self.h.quote().value;self.assertTrue(self.h.confirm(purchase).ok)

    def test_recovery_finishes_confirmed_sale_when_feature_disabled(self):
        q=self.quote().value;self.lua.globals().payoutUnavailable=True
        self.assertFalse(self.confirm(q).ok)
        self.lua.globals().Config.sales.enabled=False
        self.lua.globals().payoutUnavailable=False;self.load();self.sale.Tick()
        self.assertEqual(self.availability(),'sold');self.assertEqual(self.lua.globals().credits,1)

    def test_failed_reservation_commit_does_not_retire_or_pay(self):
        q=self.quote().value;self.h.lost_commit=True
        # The injected exception occurs after commit: the same persisted intent
        # must be recoverable even though the caller did not get an acknowledgement.
        with self.assertRaises(Exception): self.confirm(q)
        self.assertEqual(self.lua.globals().retirements,0)
        self.sale.Tick();self.assertEqual(self.availability(),'sold')

    def test_finalization_rollback_recovers_without_second_payout(self):
        q=self.quote().value
        self.db.executescript("CREATE TRIGGER refuse_sale BEFORE UPDATE OF state ON fs_horse_sales WHEN NEW.state='sold' BEGIN SELECT RAISE(ABORT,'injected'); END;")
        self.assertFalse(self.confirm(q).ok)
        self.assertEqual(self.availability(),'selling');self.assertEqual(self.lua.globals().credits,1)
        self.db.execute('DROP TRIGGER refuse_sale');self.db.commit()
        self.load();self.sale.Tick()
        self.assertEqual(self.availability(),'sold');self.assertEqual(self.lua.globals().credits,1)


class HorseSaleTackTest(unittest.TestCase):
    def test_equipped_trade_snapshot_covers_all_categories_and_bag_contents(self):
        h=tack_tests.TackTest();h.setUp()
        try:
            h.lua.execute("Stables.Saddlebags={Summary=function() return {ok=true,value={itemCount=1,contentsVersion=1,contentsRevision='bag-r1',contents={{itemName='apple',quantity=5}}}} end}")
            for slot in h.lua.globals().Tack.PieceOrder.values():
                h.catalog=h.lua.globals().Tack.CatalogBySlot[slot][1].id
                item=h.buy().instanceId;self.assertTrue(h.equip(item,slot=slot).ok,slot)
            snapshot=h.tack.HorseTradeSnapshot(h.lua.globals().session,HORSE)
            self.assertTrue(snapshot.ok,snapshot.code);self.assertEqual(len(snapshot.value['items']),13)
            bag=next(i for i in snapshot.value['items'].values() if i.slot=='saddlebag')
            self.assertEqual(bag.contentsRevision,'bag-r1');self.assertEqual(bag.contentItems[1].quantity,5)
            self.assertEqual(len(list(snapshot.value.equipment.items())),13)
            # The acceptance snapshot reads immutable order evidence through the
            # caller's Stables transaction, not an unrelated DB connection.
            h.h.inside=True
            try:
                fenced=h.tack.HorseTradeSnapshot(h.lua.globals().session,HORSE,h.lua.globals().DB)
                self.assertTrue(fenced.ok,fenced.code)
            finally: h.h.inside=False
        finally: h.tearDown()

    def test_release_parks_assembly_and_keeps_every_item_and_bag_contents(self):
        h=tack_tests.TackTest();h.setUp()
        try:
            saddle=h.buy().instanceId;self.assertTrue(h.equip(saddle).ok)
            ids={'saddle':saddle}
            for slot in ('stirrups','saddle_horn','saddlecloth','saddlebag'):
                h.catalog=h.lua.globals().Tack.CatalogBySlot[slot][1].id
                ids[slot]=h.buy().instanceId;self.assertTrue(h.equip(ids[slot],slot=slot).ok)
            h.lua.globals().pieces[ids['saddlebag']].metadata.contents='untouched'
            self.assertTrue(h.tack.ReleaseSoldHorse(CHAR,HORSE).ok)
            self.assertTrue(h.tack.ReleaseSoldHorse(CHAR,HORSE).ok)
            rows=dict(h.lua.globals().equipmentRows.items())
            self.assertEqual(rows['tack_saddle_'+str(saddle)],saddle)
            self.assertEqual(rows['tack_stir_'+str(saddle)],ids['stirrups'])
            self.assertEqual(rows['tack_horn_'+str(saddle)],ids['saddle_horn'])
            self.assertFalse(any(HORSE in slot for slot in rows))
            self.assertEqual(len(list(h.lua.globals().pieces.items())),5)
            self.assertEqual(h.lua.globals().pieces[ids['saddlebag']].metadata.contents,'untouched')
        finally: h.tearDown()
