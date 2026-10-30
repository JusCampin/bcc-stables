"""Actual trade/admission SQL with isolated, receipt-backed provider doubles."""
import unittest
import test_checkout as checkout
from test_feather_boundary import ROOT
from test_call_repository import CHAR

BUYER='77777777-7777-4777-8777-777777777777'


class HorseTradeTest(unittest.TestCase):
    def setUp(self):
        self.h=checkout.CheckoutTest();self.h.setUp();self.lua,self.db=self.h.lua,self.h.db
        def plain(value):
            if hasattr(value,'items'):
                fields=dict(value.items())
                if fields and set(fields)==set(range(1,len(fields)+1)): return [plain(fields[n]) for n in range(1,len(fields)+1)]
                return {k:plain(v) for k,v in fields.items()}
            return value
        self.h.python=plain
        purchase=self.h.quote().value;self.assertTrue(self.h.confirm(purchase).ok);self.horse=purchase.horseId
        self.lua.globals().horseId=self.horse
        self.db.executescript('''CREATE TABLE fs_horse_trades(operation_id TEXT PRIMARY KEY,horse_id TEXT,seller_character_id TEXT,buyer_character_id TEXT,state TEXT,record_json TEXT,payment_transaction_id TEXT,created_at TEXT DEFAULT CURRENT_TIMESTAMP,updated_at TEXT DEFAULT CURRENT_TIMESTAMP);''')
        self.db.execute('INSERT INTO fs_character_stables(character_id) VALUES(?)',(BUYER,));self.db.commit()
        original=self.h.sql
        self.h.sql=lambda sql:original(sql.replace('UTC_TIMESTAMP()-INTERVAL 180 SECOND',"datetime('now','-180 seconds')"))
        self.lua.execute('''
            Config.sales={tradingEnabled=true};Config.tack={enabled=true,tradingEnabled=false}
            now=1000;os.time=function() return now end
            buyer={source=9,characterId="'''+BUYER+'''",sessionId=session.sessionId,accountId=session.accountId,state='ready'}
            sellerMenu={session=session,site='valentine',token=session.sessionId};buyerMenu={session=buyer,site='valentine',token=buyer.characterId}
            exports['feather-core'].IsSessionCurrent=function(_,src,sid,cid)
                return current and (src==session.source and cid==session.characterId or src==buyer.source and cid==buyer.characterId) and sid==session.sessionId
            end
            Stables.StableMenu={CharacterName=function(cid) return cid==session.characterId and 'John Doe' or 'Jane Doe' end,
                TradePair=function(s,src)
                    if pairGone then return nil end
                    if s==sellerMenu and src==buyer.source then return buyerMenu end
                    if s==buyerMenu and src==session.source then return sellerMenu end
                end,TradePlayers=function() return {{source=buyer.source,name='Jane Doe'}} end}
            package={items={{instanceId=101,revision=2,catalogId='saddle-a',slot='saddle',condition=90,maximum=100,contents=0},
                {instanceId=102,revision=3,catalogId='bag-a',slot='saddlebag',condition=80,maximum=100,contents=1,
                contentsRevision='apples-v1',contentItems={{itemName='consumable_apple',quantity=5}}}},equipment={}}
            package.equipment['tack_saddle_'..horseId]=101;package.equipment['tack_bag_'..horseId]=102
            released=0;custody=0;ownership=0;credits=0;refunds=0;charges=0;ownedReceipts={};itemReceipts={};creditReceipts={}
            Stables.Tack={Enabled=function() return true end,CheckTradeProvider=function() return {ok=true,value=true} end,
                HorseTradeSnapshot=function() return {ok=true,value=package} end,
                ReleaseSoldHorse=function() released=released+1;return {ok=true,value=true} end,
                TransferTrade=function(q)
                    local receipt=itemReceipts[q.id]
                    if not receipt then
                        if inventoryFull then return {ok=false,code='collection_full',message='Full'} end
                        custody=custody+1;receipt={operationId='stables.horse.trade:'..q.id,characterId=q.seller.characterId,
                            recipientCharacterId=q.buyer.characterId,transferred=true,count=#q.items};itemReceipts[q.id]=receipt
                    end
                    if loseItems then loseItems=false;return {ok=false,code='timeout',message='Lost'} end
                    return {ok=true,value=receipt}
                end}
            exports['feather-assets'].TransferOwnership=function(_,p)
                local receipt=ownedReceipts[p.requestId]
                if not receipt then
                    local a=assets[p.assetId]
                    if refuseOwner or a.revision~=p.expectedRevision then return {ok=false,code='revision_conflict',message='Changed'} end
                    assert(a.owner.holderId==p.fromHolderId and p.toHolderId==buyer.characterId)
                    ownership=ownership+1;a.revision=a.revision+1;a.owner={holderType='character',holderId=p.toHolderId,interestId=p.toHolderId}
                    receipt=a;ownedReceipts[p.requestId]=receipt
                end
                if loseOwner then loseOwner=false;return {ok=false,code='timeout',message='Lost'} end
                return {ok=true,value=receipt}
            end
            exports['feather-economy'].GetSystemAccount=function(_,p) return {ok=true,value={accountId=session.sessionId,accountType=p.accountType,currency=p.currency,status='open'}} end
            exports['feather-economy'].CheckIssue=function(_,p)
                if denyPayout then return {ok=false,code='authorization_denied',message='Denied'} end
                return {ok=true,value={allowed=true,sourceAccountId=session.sessionId}}
            end
            local transfer=exports['feather-economy'].Transfer
            exports['feather-economy'].Transfer=function(self,p)
                if paymentUnavailable then return {ok=false,code='timeout',message='Unavailable'} end
                local result=transfer(self,p);if result.ok then result.value.operation='transfer' end;return result
            end
            exports['feather-economy'].Issue=function(_,p)
                local receipt=creditReceipts[p.idempotencyKey]
                if not receipt then
                    credits=credits+1;receipt={transactionId=p.referenceId,operation='issue',currency=p.currency,amount=p.amount,
                        fromAccountId=session.sessionId,toAccountId=p.accountId,sourceResource='bcc-stables',reasonCode=p.reasonCode,referenceType=p.referenceType,referenceId=p.referenceId}
                    creditReceipts[p.idempotencyKey]=receipt
                end
                if loseCredit then loseCredit=false;return {ok=false,code='timeout',message='Lost'} end
                return {ok=true,value=receipt}
            end
            exports['feather-economy'].ReversePayment=function(_,p)
                if not refundReceipt then
                    refunds=refunds+1;refundReceipt={transactionId=terms.id,operation='reversal',currency=terms.currency,amount=terms.amount,
                        fromAccountId=terms.sinkAccount,toAccountId=terms.buyerWallet,sourceResource='bcc-stables',reasonCode='stables.horse_trade_refund',referenceType='economy_transaction',referenceId=p.transactionId}
                end
                return {ok=true,value=refundReceipt}
            end
        ''')
        self.lua.execute((ROOT/'server/tack/trade.lua').read_text(encoding='utf-8'))
        self.load()

    def load(self):
        self.lua.execute((ROOT/'server/horse/trade.lua').read_text(encoding='utf-8'))
        self.trade=self.lua.globals().Stables.HorseTrade;self.assertTrue(self.trade.Start().ok)

    def tearDown(self): self.h.tearDown()
    def draft(self,amount=500,include=True):
        r=self.trade.Offer(self.lua.globals().sellerMenu,self.h.table(dict(horseId=self.horse,recipientSource=9,amount=amount,currency='dollars',includeTack=include)))
        self.assertTrue(r.ok,r.code)
        row=self.db.execute('SELECT record_json FROM fs_horse_trades WHERE operation_id=?',(r.value.operationId,)).fetchone()
        self.lua.globals().terms=self.lua.globals().json.decode(row[0]);return r.value
    def respond(self,q,seller=False,**changes):
        p=dict(operationId=q.operationId,accept=True,amount=q.amount,currency=q.currency,includeTack=q.includeTack);p.update(changes)
        return self.trade.Respond(self.lua.globals().sellerMenu if seller else self.lua.globals().buyerMenu,self.h.table(p))
    def send(self,q):
        result=self.respond(q,True);self.assertTrue(result.ok,result.code)
    def availability(self): return self.db.execute('SELECT availability FROM fs_horses').fetchone()[0]

    def test_paid_package_and_replay_keep_horse_identity_and_original_history(self):
        q=self.draft();self.send(q);self.assertEqual(self.respond(q).value.state,'completed')
        self.assertEqual(self.respond(q).value.state,'completed')
        self.assertEqual((self.lua.globals().ownership,self.lua.globals().custody,self.lua.globals().charges,self.lua.globals().credits),(1,1,1,1))
        self.assertEqual(tuple(self.db.execute('SELECT owner_character_id,availability FROM fs_horses').fetchone()),(BUYER,'stored'))
        self.assertEqual(self.db.execute('SELECT character_id FROM fs_operations').fetchone()[0],CHAR)
        owned=self.lua.globals().Stables.OwnedRepository.ReadOwned(self.lua.globals().buyer,self.horse)
        self.assertTrue(owned.ok,owned.code);self.assertEqual(owned.value.horseId,self.horse)
        self.assertEqual(owned.value.condition.healthCore,100)

    def test_gold_preflight_denial_is_diagnostic_and_creates_no_offer(self):
        self.lua.execute("deniedLogs={};print=function(message) deniedLogs[#deniedLogs+1]=message end;denyPayout=true")
        result=self.trade.Offer(self.lua.globals().sellerMenu,self.h.table(dict(horseId=self.horse,recipientSource=9,amount=2000,currency='gold',includeTack=True)))
        self.assertEqual(result.code,'horse_trade_payment_unavailable')
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM fs_horse_trades').fetchone()[0],0)
        self.assertEqual(self.lua.globals().charges,0);self.assertEqual(self.lua.globals().ownership,0)
        message=self.lua.globals().deniedLogs[1]
        self.assertIn('currency=gold',message);self.assertIn('reason=stables.horse_trade_sale',message)
        self.assertIn('code=authorization_denied',message)

    def test_free_horse_without_tack_skips_money_and_keeps_items(self):
        q=self.draft(0,False);self.assertEqual(len(q['items']),0);self.send(q)
        self.assertEqual(self.respond(q).value.state,'completed')
        self.assertEqual(self.lua.globals().custody,0);self.assertEqual(self.lua.globals().charges,0)
        self.assertEqual(self.lua.globals().credits,0);self.assertGreater(self.lua.globals().released,0)

    def test_saved_bonding_stays_with_original_horse_after_trade(self):
        from test_bonding import SCHEMA, CONFIG
        self.db.executescript(SCHEMA)
        self.db.execute('INSERT INTO fs_horse_bonding(horse_id,xp,revision) VALUES(?,125,3)',(self.horse,));self.db.commit()
        self.lua.execute(CONFIG+";Stables.HorseController={};exports['feather-core'].RegisterRpc=function() return {ok=true,value=true} end")
        self.lua.execute((ROOT/'server/horse/bonding.lua').read_text(encoding='utf-8'))
        self.assertTrue(self.lua.globals().Stables.Bonding.Start().ok)
        q=self.draft(0,False);self.send(q);self.assertEqual(self.respond(q).value.state,'completed')
        owned=self.lua.globals().Stables.OwnedRepository.ReadOwned(self.lua.globals().buyer,self.horse)
        self.assertTrue(owned.ok,owned.code);self.assertEqual(owned.value.bonding.xp,125)
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM fs_horse_bonding').fetchone()[0],1)

    def test_changed_contents_same_count_and_changed_equipment_refuse(self):
        q=self.draft();self.send(q)
        self.lua.globals().package['items'][2].contentsRevision='different-items-same-slot'
        self.assertEqual(self.respond(q).code,'horse_trade_changed')
        self.assertEqual(self.lua.globals().charges,0);self.assertEqual(self.availability(),'stored')

    def test_recipient_limits_and_expiry(self):
        q=self.draft();self.send(q);self.lua.globals().Config.horseLimits.player=0
        self.assertEqual(self.respond(q).code,'horse_trade_busy_or_limit')
        self.lua.globals().Config.horseLimits.player=5;self.lua.globals().now=1181
        self.assertEqual(self.respond(q).code,'quote_expired');self.assertEqual(self.lua.globals().charges,0)

    def test_checkbox_terms_and_unsent_draft_cannot_be_accepted(self):
        q=self.draft();self.assertEqual(self.respond(q).code,'not_found');self.send(q)
        self.assertEqual(self.respond(q,includeTack=False).code,'quote_expired')

    def test_lost_ownership_ack_replays_once_after_restart(self):
        q=self.draft();self.send(q);self.lua.globals().loseOwner=True
        self.assertFalse(self.respond(q).ok);self.assertEqual(self.availability(),'trading')
        self.load();self.trade.Tick()
        self.assertEqual(self.availability(),'stored');self.assertEqual(self.lua.globals().ownership,1)
        self.assertEqual(self.lua.globals().credits,1);self.assertEqual(self.lua.globals().refunds,0)

    def test_lost_buyer_debit_ack_recovers_once(self):
        q=self.draft();self.send(q);self.lua.globals().losePayment=True
        self.assertFalse(self.respond(q).ok);self.assertEqual(self.lua.globals().charges,1)
        self.assertEqual(self.lua.globals().ownership,0)
        self.load();self.trade.Tick()
        self.assertEqual(self.lua.globals().charges,1);self.assertEqual(self.availability(),'stored')

    def test_final_projection_rollback_replays_receipts_without_new_money(self):
        q=self.draft();self.send(q)
        self.db.executescript("CREATE TRIGGER refuse_complete BEFORE UPDATE OF state ON fs_horse_trades WHEN NEW.state='completed' BEGIN SELECT RAISE(ABORT,'injected'); END;")
        self.assertFalse(self.respond(q).ok);self.assertEqual(self.availability(),'trading')
        self.assertEqual(self.lua.globals().credits,1)
        self.db.execute('DROP TRIGGER refuse_complete');self.db.commit();self.load();self.trade.Tick()
        self.assertEqual(self.availability(),'stored');self.assertEqual(self.lua.globals().credits,1)
        self.assertEqual(self.lua.globals().custody,1);self.assertEqual(self.lua.globals().ownership,1)

    def test_lost_inventory_or_credit_ack_never_refunds_success(self):
        q=self.draft();self.send(q);self.lua.globals().loseItems=True;self.lua.globals().loseCredit=True
        self.assertFalse(self.respond(q).ok);self.trade.Tick();self.trade.Tick()
        self.assertEqual(self.availability(),'stored');self.assertEqual(self.lua.globals().custody,1)
        self.assertEqual(self.lua.globals().credits,1);self.assertEqual(self.lua.globals().refunds,0)

    def test_definite_ownership_refusal_refunds_original_debit(self):
        q=self.draft();self.send(q);self.lua.globals().refuseOwner=True
        self.assertFalse(self.respond(q).ok);self.trade.Tick();self.trade.Tick()
        self.assertEqual(self.availability(),'stored');self.assertEqual(self.lua.globals().refunds,1)
        self.assertEqual(self.lua.globals().credits,0);self.assertEqual(self.lua.globals().custody,0)

    def test_inventory_full_after_ownership_stays_reserved_until_recovery(self):
        q=self.draft();self.send(q);self.lua.globals().inventoryFull=True
        self.assertFalse(self.respond(q).ok);self.assertEqual(self.availability(),'trading')
        self.assertEqual(self.lua.globals().credits,0)
        self.lua.globals().inventoryFull=False;self.lua.globals().current=False
        self.load();self.trade.Tick();self.assertEqual(self.availability(),'stored')

    def test_accepted_incoming_reserves_capacity_against_checkout(self):
        q=self.draft();self.send(q);self.lua.globals().paymentUnavailable=True
        self.assertFalse(self.respond(q).ok)
        self.assertEqual(self.trade.IncomingCount(self.lua.globals().DB,BUYER),1)
        self.lua.globals().Config.horseLimits.player=1
        p=self.h.table(dict(modelKey='a_c_horse_morgan_bay',name='Another',gender='male',currency='dollars'))
        buyer=self.lua.globals().buyer
        quote=self.h.checkout.Quote(buyer,'valentine',p,self.lua.globals().Authorize)
        self.assertTrue(quote.ok)
        result=self.h.checkout.Confirm(buyer,'valentine',self.h.table(dict(operationId=quote.value.operationId,amount=quote.value.amount,currency=quote.value.currency)),self.lua.globals().Authorize)
        self.assertEqual(result.code,'horse_limit')
