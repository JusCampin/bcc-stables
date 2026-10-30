"""Trade review, recipient consent and locale navigation callbacks."""
import unittest
import test_stable_client as stable
from test_call_repository import GEN


class TradeClientTest(unittest.TestCase):
    def setUp(self):
        self.h=stable.StableClientTest();self.h.setUp();self.lua=self.h.lua
        self.lua.execute('''
            PlayerId=function() return 1 end;GetPlayerServerId=function() return localSource or 1 end
            local base=Stables.Client.Rpc
            tradeData={available=true,players={{source=2}},offers={}}
            tradeQuote={operationId="'''+GEN+'''",state='draft',sellerSource=1,buyerSource=2,amount=500,currency='dollars',
                items={{instanceId=186,catalogId='saddle_7',condition=80,maximum=100}}}
            tradeQuote.items[1].catalogId=Tack.CatalogBySlot.saddle[7].id
            Stables.Client.Rpc=function(action,p)
                if action=='menu_tack_trade_list' then return {ok=true,value=tradeData} end
                if action=='menu_tack_trade_offer' then offered=p;return {ok=true,value=tradeQuote} end
                if action=='menu_tack_trade_respond' then
                    responded=p;tradeQuote.state=localSource==2 and 'completed' or 'offered'
                    return {ok=true,value=tradeQuote}
                end
                return base(action,p)
            end
            function TradeTab() navCallback({toPageId=navigation.pages[4].pageId});RunJobs() end
        ''')

    def test_recipient_without_horses_can_review_accept_exact_offer(self):
        self.lua.execute("data.entries={};localSource=2;tradeQuote.state='offered';tradeData.offers={tradeQuote}")
        self.h.open();self.lua.execute("TradeTab()")
        g=self.lua.globals()
        self.assertIn('Piece 186',g.labels['trade-items-1'])
        self.assertIn('Accept',g.labels['trade-accept-1'])
        self.assertIn('5.00',g.specs['trade-accept-1'].confirm.message)
        self.lua.execute("Click('trade-accept-1');RunJobs()")
        self.assertEqual(g.responded.operationId,GEN);self.assertEqual(g.responded.amount,500)
        self.assertEqual(g.labels['trade-state-1'],'Trade completed.')

    def test_sender_reviews_frozen_item_list_before_sending(self):
        self.lua.execute("tradeData.offers={tradeQuote}")
        self.h.open();self.lua.execute("TradeTab()")
        g=self.lua.globals()
        self.assertIn('Piece 186',g.specs['trade-accept-1'].confirm.message)
        self.assertEqual(g.labels['trade-accept-1'],'Send Offer')
        self.assertIsNone(g.responded)
        self.lua.execute("Click('trade-accept-1');RunJobs()")
        self.assertTrue(g.responded.accept)
        self.assertNotIn('trade-accept-1',list(g.pages[g.activePage].keys()))

    def test_language_change_keeps_trade_page_and_fallback(self):
        self.h.open();self.lua.execute("TradeTab();lang='missing';events['feather-core:locale:changed']()")
        self.assertEqual(self.lua.globals().labels.title,'Tack Trades')
        self.assertEqual(len(list(self.lua.globals().pages.items())),5)

    def test_summary_and_confirmation_show_both_character_names(self):
        self.lua.execute("tradeQuote.sellerName='John Doe';tradeQuote.buyerName='Jane Doe';tradeData.offers={tradeQuote}")
        self.h.open();self.lua.execute('TradeTab()')
        g=self.lua.globals()
        self.assertIn('John Doe (Player 1) to Jane Doe (Player 2)',g.labels['trade-party-1'])
        self.assertIn('John Doe (Player 1) to Jane Doe (Player 2)',g.specs['trade-accept-1'].confirm.message)

    def test_trade_discloses_included_storage_contents_before_consent(self):
        self.lua.execute("tradeQuote.items[1].contents=3;tradeData.offers={tradeQuote}")
        self.h.open();self.lua.execute('TradeTab()')
        g=self.lua.globals()
        self.assertIn('3 occupied slots',g.labels['trade-items-1'])
        self.assertIn('Contents transfer',g.specs['trade-accept-1'].confirm.message)

    def test_disabled_trade_page_explains_configuration(self):
        self.lua.execute('tradeData.available=false')
        self.h.open();self.lua.execute('TradeTab()')
        self.assertEqual(self.lua.globals().labels['trade-disabled'],'Player tack trades are disabled.')

    def begin_offer(self):
        self.lua.execute('''
            tackShop={available=true,trades=true,storage='stable',owned={{instanceId=186,revision=0,
                catalogId=Tack.CatalogBySlot.saddle[7].id,condition=80}},loadout={},conditionMaximum=100}
        ''')
        self.h.tack()
        self.lua.execute("pages[activePage]['tack-owned']({value='186'});Click('tack-trade');RunJobs()")

    def test_recipient_name_is_display_only_and_missing_name_falls_back(self):
        self.lua.execute("tradeData.players={{source=2,name='Jane Doe'},{source=3}}")
        self.begin_offer()
        options=self.lua.globals().specs['trade-player'].options
        self.assertEqual(options[1].label,'Jane Doe (Player 2)')
        self.assertEqual(options[1].value,'2')
        self.assertEqual(options[2].label,'Player 3')
        self.lua.execute("Click('trade-review');RunJobs()")
        self.assertEqual(self.lua.globals().offered.recipientSource,2)

    def test_refresh_finds_later_recipient_without_discarding_selected_piece(self):
        self.lua.execute('tradeData.players={}')
        self.begin_offer()
        g=self.lua.globals()
        self.assertIn('five metres',g.labels['trade-no-player'])
        self.lua.execute("tradeData.players={{source=2}};Click('refresh');RunJobs()")
        self.assertIn('trade-review',list(g.pages[g.activePage].keys()))
        self.lua.execute("Click('trade-review');RunJobs()")
        self.assertEqual(g.offered.instanceId,186)
        self.assertEqual(g.offered.recipientSource,2)

    def test_refresh_retains_price_currency_and_updates_unavailable_recipient(self):
        self.begin_offer()
        self.lua.execute("""
            pages[activePage]['trade-price']({value='12.34'})
            pages[activePage]['trade-currency']({value='gold'})
            tradeData.players={{source=3}};Click('refresh');RunJobs()
        """)
        g=self.lua.globals()
        self.assertEqual(g.specs['trade-price'].value,'12.34')
        self.assertEqual(g.specs['trade-currency'].value,'gold')
        self.assertEqual(g.specs['trade-player'].value,'3')
        self.lua.execute("Click('trade-review');RunJobs()")
        self.assertEqual(g.offered.amount,1234);self.assertEqual(g.offered.currency,'gold')


if __name__=='__main__':unittest.main()
