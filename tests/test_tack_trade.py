"""Trade consent/recovery with real Stables SQL and receipt-backed providers.

Inventory's actual identity-preserving transaction has its own SQL tests.
"""
import unittest
import test_tack_resale as resale
from test_feather_boundary import ROOT

BUYER='77777777-7777-4777-8777-777777777777'


class TradeTest(unittest.TestCase):
    def setUp(self):
        self.base=resale.ResaleTest();self.base.setUp()
        self.h=self.base.h;self.lua=self.h.lua;self.db=self.h.db
        self.id=self.h.buy().instanceId
        self.db.executescript('CREATE TABLE fs_tack_trades(operation_id TEXT PRIMARY KEY,seller_character_id TEXT,buyer_character_id TEXT,state TEXT,record_json TEXT,payment_transaction_id TEXT,created_at TEXT DEFAULT CURRENT_TIMESTAMP,updated_at TEXT DEFAULT CURRENT_TIMESTAMP)')
        self.db.execute('INSERT INTO fs_character_stables(character_id) VALUES (?)',(BUYER,));self.db.commit()
        original=self.h.h.sql
        self.h.h.sql=lambda sql:original(sql.replace('UTC_TIMESTAMP()-INTERVAL 180 SECOND',"datetime('now','-180 seconds')"))
        self.lua.execute('''
            Config.tack.tradingEnabled=true
            buyer={source=9,characterId="'''+BUYER+'''",sessionId=session.sessionId,accountId=session.accountId,state='ready'}
            sellerMenu={session=session,site='valentine',token=session.sessionId}
            buyerMenu={session=buyer,site='valentine',token=buyer.characterId}
            Stables.StableMenu={CharacterName=function(id) return id==session.characterId and 'John Doe' or 'Jane Doe' end,TradePair=function(s,source)
                if pairGone then return nil end
                if s==sellerMenu and source==buyer.source then return buyerMenu end
                if s==buyerMenu and source==session.source then return sellerMenu end
            end,TradePlayers=function() return {{source=9}} end}
            exports['feather-inventory'].TransferCharacterCollectionItemsOnce=function(_,q)
                if not q.characterId then return {ok=false,code='invalid_input'} end
                if not transferReceipt then
                    if transferRefused then return {ok=false,code='collection_full'} end
                    for _,i in ipairs(q.items) do if not pieces[i.instanceId] or pieces[i.instanceId].revision~=i.revision then return {ok=false,code='collection_conflict'} end end
                    transfers=transfers+1
                    transferReceipt={transferred=true,operationId=q.operationId,characterId=q.characterId,recipientCharacterId=q.recipientCharacterId,count=#q.items}
                    for _,i in ipairs(q.items) do pieces[i.instanceId].inventoryId=299;pieces[i.instanceId].revision=i.revision+1 end
                end
                if loseTransfer then loseTransfer=false;return {ok=false,code='timeout'} end
                return {ok=true,value=transferReceipt}
            end
            transfers=0;refunds=0;charges=0;credits=0;earned={dollars=0,gold=0};receipts={};payoutReceipts={}
            local payment=exports['feather-economy'].Transfer
            exports['feather-economy'].Transfer=function(self,p)
                local r=payment(self,p)
                if r.ok then r.value.operation='transfer' end
                return r
            end
            exports['feather-economy'].ReversePayment=function(_,p)
                if not refundReceipt then
                    refunds=refunds+1
                    local q=tradeTerms
                    refundReceipt={transactionId=q.id,operation='reversal',currency=q.currency,amount=q.amount,
                        fromAccountId=q.sinkAccount,toAccountId=q.buyerWallet,sourceResource='bcc-stables',reasonCode='stables.tack_trade_refund',
                        referenceType='economy_transaction',referenceId=p.transactionId}
                end
                if loseRefund then loseRefund=false;return {ok=false,code='timeout',message='Lost'} end
                return {ok=true,value=refundReceipt}
            end
        ''')
        self.lua.execute((ROOT/'server/tack/trade.lua').read_text(encoding='utf-8'))
        self.trade=self.lua.globals().Stables.TackTrade
        self.assertTrue(self.trade.Start().ok)

    def tearDown(self):self.base.tearDown()

    def draft(self,amount=500,currency='dollars'):
        g=self.lua.globals()
        result=self.trade.Offer(g.sellerMenu,self.h.h.table(dict(instanceId=self.id,recipientSource=9,amount=amount,currency=currency)))
        if result.ok:
            row=self.db.execute('SELECT record_json FROM fs_tack_trades WHERE operation_id=?',(result.value.operationId,)).fetchone()
            g.tradeTerms=g.json.decode(row[0])
        return result

    def respond(self,q,seller=False,accept=True,**changes):
        g=self.lua.globals()
        p=dict(operationId=q.operationId,amount=q.amount,currency=q.currency,accept=accept,**changes)
        return self.trade.Respond(g.sellerMenu if seller else g.buyerMenu,self.h.h.table(p))

    def offered(self,amount=500,currency='dollars'):
        draft=self.draft(amount,currency);self.assertTrue(draft.ok)
        sent=self.respond(draft.value,seller=True);self.assertTrue(sent.ok);self.assertEqual(sent.value.state,'offered')
        self.assertEqual(self.lua.globals().charges,0);return sent.value

    def test_paid_trade_both_consents_and_replay_once(self):
        q=self.offered();done=self.respond(q)
        self.assertTrue(done.ok);self.assertEqual(done.value.state,'completed')
        self.assertTrue(self.respond(q).ok)
        g=self.lua.globals();self.assertEqual((g.charges,g.transfers,g.credits,g.refunds),(1,1,1,0))
        self.assertEqual(g.earned.dollars,500)

    def test_coordination_can_take_two_minutes_before_acceptance(self):
        q=self.offered()
        self.lua.execute('local now=os.time();os.time=function() return now+120 end')
        self.assertEqual(self.respond(q).value.state,'completed')
        self.assertEqual(self.lua.globals().charges,1)

    def test_unaccepted_offer_expires_after_three_minutes_without_debit(self):
        q=self.offered()
        self.lua.execute('local now=os.time();os.time=function() return now+181 end')
        self.assertEqual(self.respond(q).code,'quote_expired')
        g=self.lua.globals();self.assertEqual((g.charges,g.transfers,g.credits),(0,0,0))

    def test_free_trade_skips_economy_even_when_payout_disabled(self):
        self.lua.globals().payoutDenied=True
        q=self.offered(0);self.assertEqual(self.respond(q).value.state,'completed')
        g=self.lua.globals();self.assertEqual((g.charges,g.transfers,g.credits,g.refunds),(0,1,0,0))

    def test_buyer_cannot_accept_unsent_draft(self):
        q=self.draft().value;self.assertEqual(self.respond(q).code,'not_found')
        self.assertEqual(self.lua.globals().charges,0)

    def test_decline_and_session_change_do_not_charge(self):
        q=self.offered();self.assertEqual(self.respond(q,accept=False).value.state,'cancelled')
        self.assertEqual(self.lua.globals().charges,0)
        q=self.offered();self.lua.globals().pairGone=True
        self.assertEqual(self.respond(q).code,'quote_expired');self.assertEqual(self.lua.globals().charges,0)

    def test_insufficient_funds_cancels_without_moving(self):
        q=self.offered();self.lua.globals().balance=0
        self.assertEqual(self.respond(q).code,'insufficient_funds')
        self.assertEqual(self.lua.globals().transfers,0)
        self.assertEqual(self.respond(q).value.state,'cancelled')

    def test_lost_debit_reply_retries_same_payment(self):
        q=self.offered();self.lua.globals().losePayment=True
        self.assertFalse(self.respond(q).ok)
        self.assertEqual(self.trade.Resume(q.operationId).value.state,'completed')
        self.assertEqual(self.lua.globals().charges,1)

    def test_lost_inventory_reply_never_refunds_committed_transfer(self):
        q=self.offered();self.lua.globals().loseTransfer=True
        self.assertFalse(self.respond(q).ok)
        self.assertEqual(self.trade.Resume(q.operationId).value.state,'completed')
        g=self.lua.globals();self.assertEqual((g.transfers,g.refunds,g.credits),(1,0,1))

    def test_certain_inventory_refusal_refunds_exact_debit_once(self):
        q=self.offered();self.lua.globals().transferRefused=True
        self.assertFalse(self.respond(q).ok)
        self.lua.globals().loseRefund=True;self.assertFalse(self.trade.Resume(q.operationId).ok)
        self.assertEqual(self.trade.Resume(q.operationId).value.state,'cancelled')
        g=self.lua.globals();self.assertEqual((g.charges,g.transfers,g.credits,g.refunds),(1,0,0,1))

    def test_lost_seller_credit_reply_replays_once(self):
        q=self.offered(currency='gold');self.lua.globals().losePayout=True
        self.assertFalse(self.respond(q).ok)
        self.assertEqual(self.trade.Resume(q.operationId).value.state,'completed')
        self.assertEqual(self.lua.globals().credits,1);self.assertEqual(self.lua.globals().earned.gold,500)

    def test_changed_price_or_item_cannot_be_accepted(self):
        q=self.offered();p=self.h.h.table(dict(operationId=q.operationId,amount=q.amount+1,currency=q.currency,accept=True))
        self.assertEqual(self.trade.Respond(self.lua.globals().buyerMenu,p).code,'price_conflict')
        self.lua.globals().pieces[self.id].revision=100
        self.assertEqual(self.respond(q).code,'tack_conflict');self.assertEqual(self.lua.globals().charges,0)

    def test_restart_resumes_frozen_accepted_trade_without_live_participants(self):
        q=self.offered();self.lua.globals().loseTransfer=True
        self.assertFalse(self.respond(q).ok)
        self.lua.globals().pairGone=True
        self.lua.execute((ROOT/'server/tack/trade.lua').read_text(encoding='utf-8'))
        self.trade=self.lua.globals().Stables.TackTrade;self.assertTrue(self.trade.Start().ok)
        self.assertEqual(self.trade.Resume(q.operationId).value.state,'completed')
        self.assertEqual(self.lua.globals().charges,1);self.assertEqual(self.lua.globals().transfers,1)

    def test_received_item_retains_original_purchase_provenance(self):
        q=self.offered(0);self.assertTrue(self.respond(q).ok)
        self.lua.execute('''
            local original=exports['feather-core'].IsSessionCurrent
            exports['feather-core'].IsSessionCurrent=function(self,source,sid,cid)
                return source==buyer.source and sid==buyer.sessionId and cid==buyer.characterId or original(self,source,sid,cid)
            end
            exports['feather-inventory'].GetCharacterCollection=function(_,p)
                return {ok=true,value={id=p.characterId==buyer.characterId and 299 or 199}}
            end
            exports['feather-inventory'].GetCharacterCollectionItem=function(_,p)
                local item=pieces[p.instanceId]
                if not item or item.inventoryId~=(p.characterId==buyer.characterId and 299 or 199) then return {ok=false,code='not_found'} end
                return {ok=true,value=item}
            end
        ''')
        g=self.lua.globals()
        result=g.Stables.Tack.SaleSnapshot(g.buyer,self.id)
        self.assertTrue(result.ok);self.assertEqual(result.value['items'][1].instanceId,self.id)
        shop=g.Stables.Tack.Shop(g.buyer,self.h.lua.globals().session.characterId)
        self.assertTrue(shop.ok);self.assertEqual(shop.value.owned[1].instanceId,self.id)
        self.assertFalse(g.Stables.Tack.SaleSnapshot(g.session,self.id).ok)


if __name__=='__main__':unittest.main()
