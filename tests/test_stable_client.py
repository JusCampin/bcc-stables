"""Menu callback/language lifecycle; provider/native mocks, not visual QA."""
import unittest
from lupa.lua54 import LuaRuntime
from test_feather_boundary import ROOT
from test_call_repository import HORSE, GEN


class StableClientTest(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            Config={commerce={purchasesEnabled=false}};Stables={Client={},Horse={},Preview={}}; Locales={en_lang={shopPrompt='Open Stable'},fr_lang={shopPrompt='Écurie'}}
            lang='en_us'; dictionaries={}; events={}; threads={}; pages={}; callbacks={}; labels={}; calls={}; specs={}
            nextId=0; previews=0; clears=0; horseCalls=0; destroyed=0; closeDuringPreview=false
            CreateThread=function(fn) threads[#threads+1]=fn end
            AddEventHandler=function(name,fn) events[name]=fn end
            RegisterNetEvent=AddEventHandler
            exports={['feather-core']={
                RegisterLocale=function(_,lang,values) dictionaries[lang]=values;return {ok=true,value={}} end,
                TranslateLocale=function(_,source,key,...)
                    local dict=dictionaries[lang]
                    return {ok=true,value=dict and (dict[key] and string.format(dict[key],...) or 'Translation ['..lang..']['..key..'] does not exist') or 'Locale ['..lang..'] does not exist'}
                end
            }}
            local function ok(value) return {ok=true,value=value or {}} end
            local function id() nextId=nextId+1;return tostring(nextId) end
            local menu={}
            exports['feather-menu-v2']=menu
            menu.AwaitReady=function() return ok() end
            menu.CreateMenu=function(_,spec) menuSpec=spec;menuId=id();return ok({menuId=menuId}) end
            menu.CreatePage=function(_,mid,spec) local key=id();pages[key]={};return ok({pageId=key}) end
            menu.AddElement=function(_,mid,page,kind,spec,fn)
                assert(pages[page]);pages[page][spec.key]=fn;labels[spec.key]=spec.label or spec.value
                specs[spec.key]=spec
                local eid=id();specIds=specIds or {};specIds[eid]=spec;return ok({elementId=eid})
            end
            menu.UpdateElement=function(_,mid,page,eid,changes) for k,v in pairs(changes) do specIds[eid][k]=v end;return ok() end
            menu.ConfigureNavigation=function(_,mid,spec,fn) navigation=spec;navCallback=fn;return ok() end
            menu.RegisterMenuLifecycle=function(_,mid,fn) callbacks[mid]=fn;return ok() end
            menu.NavigateToPage=function(_,mid,page) activePage=page;return ok() end
            menu.DestroyPage=function(_,mid,page) pages[page]=nil;return ok() end
            menu.OpenMenu=function() return ok() end
            menu.CloseMenu=function(_,mid) callbacks[mid]({event='closed'});return ok() end
            menu.DestroyMenu=function(_,mid) destroyed=destroyed+1;callbacks[mid]({event='closed'});return ok() end
            Stables.Client.Message=function(message) lastMessage=message end
            Stables.Preview.Clear=function() clears=clears+1;shown=nil end
            Stables.Preview.Show=function(token,site,model,isCurrent,horseId,gender)
                assert(isCurrent(token));previews=previews+1
                shown={token=token,site=site,model=model,horseId=horseId,gender=gender}
            end
            Stables.Preview.IsShowing=function(token,site,horseId,model)
                return shown~=nil and shown.token==token and shown.site==site and shown.model==model and shown.horseId==horseId
            end
            Stables.Preview.SetGender=function(value) previewGender=value end
            Stables.Preview.Rotate=function() end
            Stables.Preview.StopRotation=function() rotationStopped=true end
            Stables.Horse.Call=function() horseCalls=horseCalls+1;calls[#calls+1]='horse_call' end
            PlayerPedId=function() return 10 end
            IsPedDeadOrDying=function() return false end
            StableLocations={valentine={shop={name='Valentine Stable'}}}
            Horses={ModelToBreedMap={a_c_horse_morgan_bay={breed='Morgan'}},BreedCatalog={Morgan={colors={a_c_horse_morgan_bay={color='Bay',stats={speed=2,acceleration=1,handling=2,health=2,stamina=3}}}}}}
            function RunJobs()
                -- The first queued thread is the continuous native prompt loop.
                while #threads>1 do table.remove(threads,2)() end
            end
            function Tab(key) local index=key=='roster' and 1 or 2;navCallback({toPageId=navigation.pages[index].pageId}) end
            function Click(key) assert(pages[activePage][key],key);pages[activePage][key]() end
        ''')
        self.lua.globals().data=self.lua.table_from({'token':GEN,'site':'valentine','entries':[
            {'horseId':HORSE,'modelKey':'a_c_horse_morgan_bay','availability':'stored','selected':True,'selectionRevision':19}
        ]},recursive=True)
        self.lua.execute('''
            detail={horseId=data.entries[1].horseId,modelKey='a_c_horse_morgan_bay',selected=true,
                availability='stored',assetRevision=1,condition={healthCore=90,staminaCore=80,revision=1}}
            Stables.Client.Rpc=function(action,p)
                calls[#calls+1]=action
                if action=='menu_preview' and closeDuringPreview then callbacks[menuId]({event='closed'}) end
                if action=='menu_preview' then return {ok=true,value=detail} end
                if action=='menu_select' then
                    for _,row in ipairs(data.entries) do row.selected=row.horseId==p.horseId;row.selectionRevision=row.selectionRevision+1 end
                    detail.selected=detail.horseId==p.horseId
                    return {ok=true,value=data}
                end
                if action=='menu_rename' then
                    if renameFailure then return {ok=false,code=renameFailure} end
                    detail.name=p.name;detail.assetRevision=detail.assetRevision+1
                    if closeDuringRename then callbacks[menuId]({event='closed'}) end
                    return {ok=true,value=detail}
                end
                return {ok=true,value=data}
            end
        ''')
        for path in ['client/core/locale.lua','client/ui/stable.lua']:
            self.lua.execute((ROOT/path).read_text(encoding='utf-8'))

    def open(self):
        self.lua.execute("Stables.StableUI.Open('valentine');RunJobs()")

    def catalog(self):
        self.lua.execute("""
            Horses.BreedsOrder={'Morgan'}
            local colors=Horses.BreedCatalog.Morgan.colors
            colors.a_c_horse_morgan_bay.currency=3
            colors.a_c_horse_morgan_bay.cashPrice=75
            colors.a_c_horse_morgan_bay.goldPrice=3
            colors.a_c_horse_morgan_palomino={color='Palomino',currency=2,goldPrice=4,stats={speed=3,acceleration=2,handling=1,health=4,stamina=5}}
        """)
        self.open()
        self.lua.execute("Tab('catalog');Click('breed-1');RunJobs()")

    def test_catalog_coats_prices_and_stats_are_read_only(self):
        self.catalog()
        labels=self.lua.globals().labels
        self.assertEqual(labels['catalog-price'],'Catalog Price: $75.00 or 3.00 gold')
        self.assertEqual(labels['stat-speed'],'Speed: 3/10')
        self.assertEqual(self.lua.globals().shown.horseId,'catalog:a_c_horse_morgan_bay')
        self.lua.execute("pages[activePage]['catalog-coat']({value='a_c_horse_morgan_palomino'});RunJobs()")
        self.assertEqual(labels['catalog-price'],'Catalog Price: 4.00 gold')
        self.assertEqual(labels['stat-speed'],'Speed: 4/10')
        self.assertEqual(self.lua.globals().shown.model,'a_c_horse_morgan_palomino')
        self.assertEqual(self.lua.globals().horseCalls,0)
        self.assertFalse(any(call in ('menu_select','menu_rename','horse_call') for call in self.lua.globals().calls.values()))

    def test_catalog_same_coat_reuses_preview_and_back_restores_owned_identity(self):
        self.catalog()
        previews=self.lua.globals().previews
        self.lua.execute("pages[activePage]['catalog-coat']({value='a_c_horse_morgan_bay'});RunJobs()")
        self.assertEqual(self.lua.globals().previews,previews)
        self.lua.execute("Click('catalog-back');Click('breed-1');RunJobs()")
        self.assertEqual(self.lua.globals().previews,previews)
        self.lua.execute("Tab('roster');RunJobs()")
        self.assertEqual(self.lua.globals().shown.horseId,HORSE)
        self.assertEqual(len(list(self.lua.globals().pages.items())),3)

    def test_catalog_loading_fences_coat_changes_and_failure_clears_old_preview(self):
        self.catalog()
        self.lua.execute("pages[activePage]['catalog-coat']({value='a_c_horse_morgan_palomino'})")
        self.assertTrue(self.lua.globals().specs['catalog-coat']['disabled'])
        self.lua.execute("pages[activePage]['catalog-coat']({value='a_c_horse_morgan_bay'})")
        self.assertEqual(self.lua.globals().specs['catalog-coat']['value'],'a_c_horse_morgan_palomino')
        self.lua.execute("Stables.Preview.Show=function() end;RunJobs()")
        self.assertFalse(self.lua.globals().specs['catalog-coat']['disabled'])
        self.assertIsNone(self.lua.globals().shown)
        self.assertEqual(self.lua.globals().lastMessage,'This horse preview could not be loaded.')

    def test_tabs_keep_session_restore_coat_and_show_position(self):
        self.catalog()
        self.assertEqual(self.lua.globals().labels['catalog-position'],'1 of 2')
        self.lua.execute("pages[activePage]['catalog-coat']({value='a_c_horse_morgan_palomino'});RunJobs()")
        self.assertEqual(self.lua.globals().labels['catalog-position'],'2 of 2')
        self.lua.execute("Tab('roster');RunJobs();Tab('catalog');RunJobs()")
        self.assertEqual(self.lua.globals().specs['catalog-coat']['value'],'a_c_horse_morgan_palomino')
        self.assertEqual(self.lua.globals().shown.horseId,'catalog:a_c_horse_morgan_palomino')
        self.assertEqual(list(self.lua.globals().calls.values()).count('menu_open'),1)
        self.assertEqual(len(list(self.lua.globals().pages.items())),3)
        self.assertTrue(self.lua.globals().navigation['controlled'])

    def test_tabs_localize_and_replace_duplicate_navigation_buttons(self):
        self.open()
        self.assertIsNone(self.lua.globals().pages[self.lua.globals().activePage]['browse-catalog'])
        self.lua.execute("dictionaries.fr_fr.stables_menu_title='Mes chevaux';dictionaries.fr_fr.stables_menu_browseCatalog='Catalogue';lang='fr_fr';events['feather-core:locale:changed']()")
        nav=self.lua.globals().navigation
        self.assertEqual(nav.pages[1].label,'Mes chevaux')
        self.assertEqual(nav.pages[2].label,'Catalogue')

    def test_catalog_all_currency_modes_and_unset_price(self):
        self.catalog()
        for currency,expected in [(1,'$75.00'),(2,'3.00 gold'),(3,'$75.00 or 3.00 gold'),(4,'Free'),(9,'Unknown')]:
            self.lua.execute(f"Horses.BreedCatalog.Morgan.colors.a_c_horse_morgan_bay.currency={currency};pages[activePage]['catalog-coat']({{value='a_c_horse_morgan_bay'}});RunJobs()")
            self.assertEqual(self.lua.globals().labels['catalog-price'],'Catalog Price: '+expected)
        self.lua.execute("Horses.BreedCatalog.Morgan.colors.a_c_horse_morgan_bay.currency=1;Horses.BreedCatalog.Morgan.colors.a_c_horse_morgan_bay.cashPrice=nil;pages[activePage]['catalog-coat']({value='a_c_horse_morgan_bay'});RunJobs()")
        self.assertEqual(self.lua.globals().labels['catalog-price'],'Catalog Price: Unknown')

    def test_catalog_language_change_keeps_current_coat_without_reloading(self):
        self.catalog()
        before=self.lua.globals().previews
        self.lua.execute("dictionaries.fr_fr.stables_menu_catalog='Catalogue';lang='fr_fr';events['feather-core:locale:changed']()")
        self.assertEqual(self.lua.globals().labels['title'],'Catalogue')
        self.assertEqual(self.lua.globals().specs['catalog-coat']['value'],'a_c_horse_morgan_bay')
        self.assertEqual(self.lua.globals().previews,before)
        self.assertEqual(len(list(self.lua.globals().pages.items())),3)

    def test_catalog_empty_and_return_to_empty_roster_clear_preview(self):
        self.lua.execute("Horses.BreedsOrder={};data.entries={}")
        self.open()
        self.lua.execute("Tab('catalog')")
        self.assertEqual(self.lua.globals().labels['catalog-empty'],'No horses are available to browse.')
        self.lua.execute("Tab('roster')")
        self.assertIsNone(self.lua.globals().shown)

    def test_catalog_uses_actual_breed_order_and_sorts_coats(self):
        self.lua.execute((ROOT/'config/horse_catalog.lua').read_text(encoding='utf-8'))
        self.open()
        self.lua.execute("Tab('catalog')")
        self.assertEqual(self.lua.globals().labels['breed-1'],'American Paint')
        self.assertEqual(self.lua.globals().labels['breed-25'],'Other')
        self.lua.execute("Click('breed-16');RunJobs()")
        options=list(self.lua.globals().specs['catalog-coat']['options'].values())
        self.assertEqual([o.label for o in options],sorted([o.label for o in options],key=str.lower))
        self.assertEqual(len(options),5)

    def test_catalog_close_during_model_loading_cleans_session(self):
        self.catalog()
        self.lua.execute("Stables.Preview.Show=function() callbacks[menuId]({event='closed'}) end;pages[activePage]['catalog-coat']({value='a_c_horse_morgan_palomino'});RunJobs()")
        self.assertEqual(self.lua.globals().destroyed,1)
        self.assertIsNone(self.lua.globals().shown)
        self.assertIn('menu_close',list(self.lua.globals().calls.values()))

    def checkout_form(self):
        self.catalog()
        self.lua.execute("""
            Config.commerce.purchasesEnabled=true
            local original=Stables.Client.Rpc
            Stables.Client.Rpc=function(action,p)
                if action=='menu_purchase_quote' then
                    calls[#calls+1]=action
                    quoted={operationId=data.token,horseId=data.entries[1].horseId,name=p.name,gender=p.gender,currency=p.currency,amount=7500,state='reserved'}
                    return {ok=true,value=quoted}
                end
                if action=='menu_purchase_confirm' then
                    calls[#calls+1]=action;confirmedId=p.operationId
                    if purchaseFailure then return {ok=false,code=purchaseFailure} end
                    data.entries[1].name=quoted.name
                    return {ok=true,value={state='fulfilled',horseId=data.entries[1].horseId}}
                end
                return original(action,p)
            end
            pages[activePage]['catalog-coat']({value='a_c_horse_morgan_bay'});RunJobs();Click('purchase')
        """)

    def test_checkout_reviews_exact_quote_and_success_refreshes_roster(self):
        self.checkout_form()
        self.lua.execute("pages[activePage]['purchase-name']({value='Willow'});pages[activePage]['purchase-gender']({value='female'});Click('purchase-submit');RunJobs()")
        self.assertTrue(self.lua.globals().specs['purchase-name']['disabled'])
        self.assertIn('$75.00',self.lua.globals().specs['purchase-submit']['confirm']['message'])
        self.assertIn('Willow',self.lua.globals().specs['purchase-submit']['confirm']['message'])
        self.assertEqual(self.lua.globals().quoted.gender,'female')
        self.lua.execute("Click('purchase-submit');RunJobs()")
        self.assertEqual(self.lua.globals().labels['title'],'My Horses')
        self.assertEqual(self.lua.globals().confirmedId,GEN)
        self.assertEqual(self.lua.globals().horseCalls,0)

    def test_checkout_unknown_outcome_keeps_same_quote_on_retry(self):
        self.checkout_form()
        self.lua.execute("pages[activePage]['purchase-name']({value='Willow'});Click('purchase-submit');RunJobs();purchaseFailure='purchase_pending';Click('purchase-submit');RunJobs()")
        self.assertIn('processing',self.lua.globals().labels['purchase-error'])
        self.lua.execute("Click('purchase-refresh');purchaseFailure=nil;Click('purchase-submit');RunJobs()")
        self.assertEqual(list(self.lua.globals().calls.values()).count('menu_purchase_quote'),1)
        self.assertEqual(list(self.lua.globals().calls.values()).count('menu_purchase_confirm'),2)

    def test_opening_another_stored_header_commits_selection_once(self):
        self.lua.execute("data.entries[1].selected=false;data.entries[2]={horseId=data.token,modelKey='a_c_horse_morgan_bay',availability='stored',selected=true,selectionRevision=19}")
        self.open()
        self.lua.execute("Click('horse-1');RunJobs()")
        self.assertTrue(self.lua.globals().specs['horse-1']['selected'])
        self.assertFalse(self.lua.globals().specs['horse-2']['selected'])
        self.assertEqual(list(self.lua.globals().calls.values()).count('menu_select'),1)
        self.lua.execute("Click('horse-1');Click('horse-1');RunJobs()")
        self.assertEqual(list(self.lua.globals().calls.values()).count('menu_select'),1)
        self.assertEqual(self.lua.globals().horseCalls,0)

    def test_owned_preview_receives_saved_sex_and_checkout_updates_it(self):
        self.lua.execute("detail.gender='female'")
        self.open()
        self.assertEqual(self.lua.globals().shown.gender,'female')
        self.lua.execute("Click('close');RunJobs()")
        self.checkout_form()
        self.lua.execute("pages[activePage]['purchase-gender']({value='female'})")
        self.assertEqual(self.lua.globals().previewGender,'female')
        self.lua.execute("pages[activePage]['purchase-gender']({value='male'})")
        self.assertEqual(self.lua.globals().previewGender,'male')

    def test_take_out_closes_before_call_and_does_not_accumulate_pages(self):
        self.open()
        self.lua.execute("Click('horse-1');RunJobs();Click('horse-1-select');RunJobs()")
        calls=list(self.lua.globals().calls.values())
        self.assertLess(calls.index('menu_close'),calls.index('horse_call'))
        self.assertEqual(self.lua.globals().horseCalls,1)
        self.assertEqual(self.lua.globals().destroyed,1)

    def test_escape_during_pending_preview_cleans_without_late_show(self):
        self.lua.globals().closeDuringPreview=True
        self.open()
        self.assertEqual(self.lua.globals().previews,0)
        self.assertEqual(self.lua.globals().destroyed,1)
        self.assertIn('menu_close',list(self.lua.globals().calls.values()))

    def test_missing_language_file_and_missing_key_fall_back_to_english(self):
        self.lua.globals().lang='es'
        self.assertEqual(self.lua.globals().Stables.Client.Text('shopPrompt'),'Open Stable')
        self.lua.globals().lang='fr_fr'
        self.assertEqual(self.lua.globals().Stables.Client.Text('shopPrompt'),'Écurie')
        self.assertEqual(self.lua.globals().Stables.Client.Text('menu_title'),'My Horses')

    def test_language_change_updates_open_menu_without_leaking_pages(self):
        self.open()
        self.lua.execute("dictionaries.fr_fr.stables_menu_title='Mes chevaux';lang='fr_fr';events['feather-core:locale:changed']()")
        self.assertEqual(self.lua.globals().labels['title'],'Mes chevaux')
        self.assertEqual(len(list(self.lua.globals().pages.items())),3)

    def details(self):
        self.open()
        self.lua.execute("Click('horse-1');RunJobs();Click('horse-1-details');RunJobs()")

    def test_details_show_saved_condition_and_catalog_stats_separately(self):
        self.details()
        labels=self.lua.globals().labels
        self.assertEqual(labels['breed'],'Breed: Morgan')
        self.assertEqual(labels['coat'],'Coat: Bay')
        self.assertEqual(labels['ownership'],'Ownership: Owned by you')
        self.assertEqual(labels['selection'],'Selection: Selected')
        self.assertEqual(labels['status'],'Status: Stored')
        self.assertEqual(labels['health-core'],'Health Core: 90%')
        self.assertEqual(labels['stamina-core'],'Stamina Core: 80%')
        self.assertEqual(labels['stats-title'],'Catalog Base Performance')
        self.assertEqual(labels['stat-speed'],'Speed: 3/10')
        self.assertFalse(any(call in ('menu_select','horse_call') for call in self.lua.globals().calls.values()))

    def test_details_refresh_preserves_zero_and_does_not_invent_missing_condition(self):
        self.details()
        self.lua.execute("detail.condition.healthCore=0;Click('refresh');RunJobs()")
        self.assertEqual(self.lua.globals().labels['health-core'],'Health Core: 0%')
        self.lua.execute("detail.condition=nil;detail.selected=false;Click('refresh');RunJobs()")
        self.assertEqual(self.lua.globals().labels['health-core'],'Health Core: Not recorded')
        self.assertEqual(self.lua.globals().labels['stamina-core'],'Stamina Core: Not recorded')
        self.assertEqual(self.lua.globals().labels['selection'],'Selection: Not selected')

    def test_details_back_keeps_preview_session_and_discards_old_page(self):
        self.details()
        previews=self.lua.globals().previews
        self.lua.execute("Click('back')")
        self.assertEqual(self.lua.globals().labels['title'],'My Horses')
        self.assertTrue(self.lua.globals().rotationStopped)
        self.assertEqual(len(list(self.lua.globals().pages.items())),3)
        self.assertEqual(self.lua.globals().previews,previews)
        self.assertNotIn('menu_close',list(self.lua.globals().calls.values()))

    def test_language_change_stays_on_details(self):
        self.details()
        self.lua.execute("dictionaries.fr_fr.stables_menu_details='Détails';lang='fr_fr';events['feather-core:locale:changed']()")
        self.assertEqual(self.lua.globals().labels['title'],'Détails')
        self.assertEqual(len(list(self.lua.globals().pages.items())),3)

    def test_horse_actions_and_details_use_existing_accordion_sections(self):
        self.open()
        self.lua.execute("Click('horse-1');RunJobs()")
        self.assertTrue(self.lua.globals().specs['horse-1']['value'])
        self.assertEqual(self.lua.globals().specs['horse-1']['labelAlign'],'center')
        self.assertTrue(self.lua.globals().specs['horse-1']['notify'])
        self.assertIsNone(self.lua.globals().specs['horse-1-actions'])
        self.assertIsNone(self.lua.globals().specs['horse-1-rename'])
        self.lua.execute("Click('horse-1-details');RunJobs()")
        self.assertEqual(self.lua.globals().specs['ownership']['section'],'information')
        self.assertEqual(self.lua.globals().specs['health-core']['section'],'condition-title')
        self.assertEqual(self.lua.globals().specs['stat-speed']['section'],'stats-title')
        self.assertFalse(self.lua.globals().specs['stats-title']['value'])

    def test_close_during_details_read_discards_late_page(self):
        self.open()
        self.lua.execute("Click('horse-1');RunJobs();closeDuringPreview=true;Click('horse-1-details');RunJobs()")
        self.assertEqual(self.lua.globals().destroyed,1)
        self.assertEqual(self.lua.globals().horseCalls,0)
        self.assertIn('menu_close',list(self.lua.globals().calls.values()))

    def test_roster_entry_can_collapse(self):
        self.open()
        self.lua.execute("Click('horse-1');RunJobs();Click('horse-1')")
        self.assertIsNone(self.lua.globals().pages[self.lua.globals().activePage]['horse-1-details'])

    def test_collapsing_roster_keeps_preview_and_camera(self):
        self.open()
        self.lua.execute("Click('horse-1');RunJobs()")
        before=self.lua.globals().clears
        previews=self.lua.globals().previews
        self.lua.execute("Click('horse-1')")
        self.assertEqual(self.lua.globals().clears,before)
        self.assertEqual(self.lua.globals().previews,previews)

    def test_expanding_displayed_horse_reuses_preview_without_another_read(self):
        self.open()
        previews=self.lua.globals().previews
        reads=list(self.lua.globals().calls.values()).count('menu_preview')
        self.lua.execute("Click('horse-1');RunJobs();Click('horse-1');Click('horse-1');RunJobs()")
        self.assertEqual(self.lua.globals().previews,previews)
        self.assertEqual(list(self.lua.globals().calls.values()).count('menu_preview'),reads)

    def test_roster_header_marks_selection_without_repeating_stored(self):
        self.lua.execute("data.entries[1].name='Willow'")
        self.open()
        self.assertEqual(self.lua.globals().labels['horse-1'],'Willow')
        self.assertTrue(self.lua.globals().specs['horse-1']['selected'])
        self.lua.execute("data.entries[1].selected=false;Click('refresh');RunJobs()")
        self.assertEqual(self.lua.globals().labels['horse-1'],'Willow')
        self.lua.execute("data.entries[1].selected=true;data.entries[1].availability='active';Click('refresh');RunJobs()")
        self.assertEqual(self.lua.globals().labels['horse-1'],'Willow · Active')
        self.lua.execute("data.entries[1].availability='reconciliation_required';Click('refresh');RunJobs()")
        self.assertEqual(self.lua.globals().labels['horse-1'],'Willow · Unavailable')

    def test_roster_footer_pairs_rotation_and_final_actions(self):
        self.open()
        specs=self.lua.globals().specs
        self.assertEqual(specs['left']['row'],'rotation')
        self.assertEqual(specs['right']['row'],'rotation')
        self.assertEqual(specs['refresh']['row'],'actions')
        self.assertEqual(specs['close']['row'],'actions')

    def test_stable_uses_top_left_anchor_and_ignores_old_drag_position(self):
        self.open()
        spec=self.lua.globals().menuSpec
        self.assertEqual(spec.position.x,'3%')
        self.assertEqual(spec.position.y,'3%')
        self.assertEqual(spec.position.anchor,'top-left')
        self.assertFalse(spec.persistPosition)

    def rename(self):
        self.open()
        self.lua.execute("Click('horse-1');RunJobs();Click('horse-1-details');RunJobs();Click('rename');RunJobs()")

    def test_rename_updates_roster_and_details_without_reloading_preview(self):
        self.rename()
        previews=self.lua.globals().previews
        self.lua.execute("pages[activePage]['horse-name']({value='Willow'});Click('save-name');RunJobs()")
        self.assertEqual(self.lua.globals().labels['horse'],'Willow')
        self.lua.execute("Click('back')")
        self.assertEqual(self.lua.globals().labels['horse-1'],'Willow')
        self.lua.execute("Click('horse-1-details');RunJobs()")
        self.assertEqual(self.lua.globals().labels['horse'],'Willow')
        self.assertEqual(self.lua.globals().previews,previews)

    def test_cancel_rename_does_not_send_mutation(self):
        self.rename()
        self.lua.execute("pages[activePage]['horse-name']({value='Willow'});Click('back')")
        self.assertNotIn('menu_rename',list(self.lua.globals().calls.values()))

    def test_refused_rename_keeps_draft_and_shows_localized_error(self):
        self.rename()
        self.lua.execute("renameFailure='invalid_name';pages[activePage]['horse-name']({value='<bad>'});Click('save-name');RunJobs()")
        self.assertEqual(self.lua.globals().labels['title'],'Rename Horse')
        self.assertIn('valid horse name',self.lua.globals().specs['horse-name']['error'])
        self.assertEqual(self.lua.globals().specs['horse-name']['error'],'Enter a valid horse name.')
        self.lua.execute("renameFailure=nil;pages[activePage]['horse-name']({value='Willow'});Click('save-name');RunJobs()")
        self.assertEqual(self.lua.globals().labels['horse'],'Willow')

    def test_close_during_rename_discards_late_ui_update(self):
        self.rename()
        self.lua.execute("closeDuringRename=true;pages[activePage]['horse-name']({value='Willow'});Click('save-name');RunJobs()")
        self.assertEqual(self.lua.globals().destroyed,1)
        self.assertEqual(self.lua.globals().horseCalls,0)

    def test_rename_save_stays_busy_until_server_result(self):
        self.rename()
        specs=self.lua.globals().specs
        self.assertEqual(specs['save-name']['row'],specs['refresh']['row'])
        self.assertEqual(specs['back']['row'],specs['close']['row'])
        self.lua.execute("Click('save-name')")
        self.assertTrue(self.lua.globals().specs['save-name']['busy'])
        self.assertEqual(self.lua.globals().specs['save-name']['busyLabel'],'Saving…')
        self.lua.execute("Click('save-name');RunJobs()")
        self.assertEqual(list(self.lua.globals().calls.values()).count('menu_rename'),1)

    def test_language_change_keeps_rename_page_and_draft(self):
        self.rename()
        self.lua.execute("pages[activePage]['horse-name']({value='Willow'});dictionaries.fr_fr.stables_menu_rename='Renommer';lang='fr_fr';events['feather-core:locale:changed']()")
        self.assertEqual(self.lua.globals().labels['title'],'Renommer')
        self.lua.execute("Click('save-name');RunJobs()")
        self.assertEqual(self.lua.globals().labels['horse'],'Willow')


if __name__=='__main__':
    unittest.main()
