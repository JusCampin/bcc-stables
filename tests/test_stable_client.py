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
            Stables.Preview.CanPreviewTack=function() return true end
            Stables.Preview.SetSaddle=function(token,site,horseId,value)
                assert(shown and shown.token==token and shown.site==site and shown.horseId==horseId)
                if previewSaddle~=value then saddleWrites=(saddleWrites or 0)+1 end
                previewSaddle=value;return true
            end
            Stables.Preview.SetTack=function(token,site,horseId,slot,value)
                if slot=='saddle' then return Stables.Preview.SetSaddle(token,site,horseId,value) end
                previewOther=previewOther or {};previewOther[slot]=value;return true
            end
            Stables.Preview.SetAssembly=function(token,site,horseId,catalog,parts)
                Stables.Preview.SetSaddle(token,site,horseId,catalog)
                previewOther=previewOther or {}
                for _,slot in ipairs({'stirrups','saddle_horn'}) do previewOther[slot]=parts[slot] and parts[slot].catalogId end
                return true
            end
            Stables.Preview.SetSavedTack=function(token,site,horseId,loadout)
                savedLoadout=loadout;previewOther={}
                for slot,item in pairs(loadout or {}) do if slot~='saddle' then previewOther[slot]=item.catalogId end end
                savedSaddle=loadout and loadout.saddle and loadout.saddle.catalogId
                return Stables.Preview.SetSaddle(token,site,horseId,savedSaddle)
            end
            Stables.Preview.RestoreTack=function(token,site,horseId)
                previewOther={}
                for slot,item in pairs(savedLoadout or {}) do if slot~='saddle' then previewOther[slot]=item.catalogId end end
                return Stables.Preview.SetSaddle(token,site,horseId,savedSaddle)
            end
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
            function Tab(key) local index=key=='roster' and 1 or key=='catalog' and 2 or 3;navCallback({toPageId=navigation.pages[index].pageId}) end
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
                if action=='menu_tack_shop' then return {ok=true,value=tackShop or {available=false,owned={},loadout={}}} end
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
        for path in ['config/tack/catalog.lua','config/tack/categories/saddles.lua','config/tack/categories/saddlecloths.lua','config/tack/categories/stirrups.lua','config/tack/categories/saddle_horns.lua','shared/tack.lua',
                     'client/core/locale.lua','client/ui/stable.lua']:
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

    def tack(self):
        self.open()
        self.lua.execute("Tab('tack');RunJobs()")

    def test_saddle_catalog_is_local_only_reuses_preview_and_restores_on_back(self):
        self.tack()
        g=self.lua.globals()
        self.assertEqual(len(g.specs['tack-saddle']['options']),180)
        self.assertEqual(g.labels['tack-position'],'1 of 180')
        self.assertIn('Preview only',g.labels['tack-notice'])
        previews=g.previews
        self.lua.execute("saddle=Tack.CatalogBySlot.saddle[1].id;pages[activePage]['tack-saddle']({value=saddle})")
        self.assertEqual(g.previewSaddle,g.saddle)
        self.assertEqual(g.labels['tack-position'],'2 of 180')
        self.assertEqual(g.labels['tack-price'],'Catalog Price: $10.00 or 1.00 gold')
        self.lua.execute("pages[activePage]['tack-saddle']({value=saddle});Click('tack-back')")
        self.assertIsNone(g.previewSaddle)
        self.assertEqual(g.previews,previews)
        self.assertEqual(g.labels['title'],'My Horses')
        self.assertEqual(len(list(g.pages.items())),4)
        self.assertFalse(any('purchase' in c or c=='menu_select' for c in g.calls.values()))

    def test_saddle_preview_clears_on_tabs_and_ignores_destroyed_page_callbacks(self):
        self.tack()
        self.lua.execute("""
            stale=pages[activePage]['tack-saddle']
            saddle=Tack.CatalogBySlot.saddle[2].id
            stale({value=saddle});Tab('catalog');RunJobs()
            writes=saddleWrites
            stale({value=saddle})
        """)
        g=self.lua.globals()
        self.assertIsNone(g.previewSaddle)
        self.assertEqual(g.saddleWrites,g.writes)
        self.assertEqual(len(list(g.pages.items())),4)

    def test_locale_change_keeps_saddle_choice_and_missing_language_falls_back(self):
        self.tack()
        self.lua.execute("""
            saddle=Tack.CatalogBySlot.saddle[3].id
            pages[activePage]['tack-saddle']({value=saddle})
            lang='missing';events['feather-core:locale:changed']()
        """)
        g=self.lua.globals()
        self.assertEqual(g.specs['tack-saddle']['value'],g.saddle)
        self.assertEqual(g.labels['title'],'Horse Tack')
        self.assertEqual(g.labels['tack-position'],'4 of 180')
        self.assertEqual(g.saddleWrites,1)

    def test_tack_is_a_top_tab_for_selected_horse_without_details_button(self):
        self.tack()
        g=self.lua.globals()
        self.assertEqual(g.navigation.pages[3].label,'Horse Tack')
        self.lua.execute("Tab('roster');Click('horse-1');RunJobs();Click('horse-1-details');RunJobs()")
        self.assertIsNone(g.pages[g.activePage]['tack'])
        self.lua.execute("Tab('catalog');Tab('tack');RunJobs()")
        self.assertEqual(g.shown.horseId,HORSE)
        self.assertEqual(g.labels['title'],'Horse Tack')

    def test_tack_tab_without_selection_gives_guidance_without_preview(self):
        self.lua.execute("data.entries[1].selected=false;detail.selected=false")
        self.open()
        self.lua.execute("Tab('tack');RunJobs()")
        self.assertIn('Select a stored horse',self.lua.globals().labels['tack-empty'])
        self.assertIsNone(self.lua.globals().shown)
        self.lua.execute("Tab('roster');Click('horse-1');RunJobs();Tab('tack');RunJobs()")
        self.assertEqual(self.lua.globals().labels['title'],'Horse Tack')
        self.assertIsNotNone(self.lua.globals().specs['tack-saddle'])

    def paid_tack(self):
        self.lua.execute('''
            tackShop={available=true,purchases=true,owned={},loadout={},conditionMaximum=100}
            local original=Stables.Client.Rpc
            Stables.Client.Rpc=function(action,p)
                if action=='menu_tack_quote' then
                    tackQuote={operationId=data.token,catalogId=p.catalogId,amount=1000,currency=p.currency,state='reserved'}
                    quoteCalls=(quoteCalls or 0)+1;return {ok=true,value=tackQuote}
                end
                if action=='menu_tack_confirm' then
                    confirmedTack=p.operationId
                    if tackFailure then return {ok=false,code=tackFailure} end
                    tackShop.owned[#tackShop.owned+1]={instanceId=101,revision=0,catalogId=tackQuote.catalogId,condition=100}
                    return {ok=true,value={state='fulfilled',instanceId=101}}
                end
                if action=='menu_tack_equip' then
                    equipRequest=p;tackShop.loadout[p.slot or 'saddle']=p.instanceId>0 and p.instanceId or nil
                    for _,item in ipairs(tackShop.owned) do if item.instanceId==p.instanceId then item.horseId=p.horseId end end
                    return {ok=true,value=tackShop}
                end
                return original(action,p)
            end
        ''')
        self.tack()
        self.lua.execute("pages[activePage]['tack-saddle']({value=Tack.CatalogBySlot.saddle[1].id})")

    def test_tack_purchase_then_separate_equip_and_unequip_preserve_collection(self):
        self.paid_tack()
        g=self.lua.globals()
        self.lua.execute("Click('tack-purchase');RunJobs()")
        self.assertIn('$10.00',g.specs['tack-purchase']['confirm']['message'])
        self.lua.execute("Click('tack-purchase');RunJobs()")
        self.assertEqual(g.specs['tack-owned']['value'],'101')
        self.assertIsNone(g.tackShop.loadout.saddle)
        self.lua.execute("Click('tack-equip');RunJobs();Tab('roster')")
        self.assertEqual(g.equipRequest.instanceId,101)
        self.assertEqual(g.previewSaddle,g.tackQuote.catalogId)
        self.lua.execute("Tab('tack');RunJobs();pages[activePage]['tack-owned']({value='none'});Click('tack-equip');RunJobs()")
        self.assertIsNone(g.tackShop.loadout.saddle)
        self.assertEqual(len(g.tackShop.owned),1)

    def test_tack_pending_quote_keeps_same_purchase_after_refresh(self):
        self.paid_tack()
        self.lua.execute("Click('tack-purchase');RunJobs();tackFailure='tack_pending';Click('tack-purchase');RunJobs();Click('tack-refresh');RunJobs();tackFailure=nil;Click('tack-purchase');RunJobs()")
        self.assertEqual(self.lua.globals().quoteCalls,1)
        self.assertEqual(self.lua.globals().confirmedTack,GEN)

    def test_tack_category_catalog_counts_and_localized_labels(self):
        self.tack()
        self.assertEqual(len(self.lua.globals().specs['tack-category']['options']),4)
        for slot,count,label in [('saddlecloth',67,'Saddlecloths'),('stirrups',55,'Stirrups'),('saddle_horn',68,'Saddle Horns')]:
            self.lua.execute(f"pages[activePage]['tack-category']({{value='{slot}'}})")
            self.assertEqual(len(self.lua.globals().specs['tack-saddle']['options']),count)
            self.assertEqual(self.lua.globals().specs['tack-saddle']['label'],label)
        self.lua.execute("lang='missing';events['feather-core:locale:changed']()")
        self.assertEqual(self.lua.globals().specs['tack-category']['value'],'saddle_horn')

    def buy_new_category(self,slot):
        self.paid_tack()
        self.lua.execute("""
            tackShop.owned={{instanceId=100,revision=0,catalogId=Tack.CatalogBySlot.saddle[1].id,condition=100,horseId=detail.horseId}}
            tackShop.loadout.saddle=100
            Click('tack-refresh');RunJobs()
        """)
        self.lua.execute(f"pages[activePage]['tack-category']({{value='{slot}'}});pages[activePage]['tack-saddle']({{value=Tack.CatalogBySlot['{slot}'][1].id}})")
        self.lua.execute("Click('tack-purchase');RunJobs();Click('tack-purchase');RunJobs()")
        self.assertEqual(self.lua.globals().specs['tack-category']['value'],slot)
        self.assertEqual(len(self.lua.globals().specs['tack-owned']['options']),2)
        self.assertFalse(self.lua.globals().specs['tack-equip']['disabled'])
        self.lua.execute("Click('tack-equip');RunJobs();Tab('roster')")
        self.assertEqual(self.lua.globals().equipRequest.slot,slot)
        self.assertEqual(self.lua.globals().tackShop.loadout[slot],101)
        self.assertIsNotNone(self.lua.globals().previewSaddle)
        self.assertEqual(self.lua.globals().previewOther[slot],self.lua.globals().Tack.CatalogBySlot[slot][1].id)

    def test_saddlecloth_purchase_equip_uses_its_own_slot(self): self.buy_new_category('saddlecloth')
    def test_stirrup_purchase_equip_uses_its_own_slot(self): self.buy_new_category('stirrups')
    def test_horn_purchase_equip_uses_its_own_slot(self): self.buy_new_category('saddle_horn')

    def test_equipped_piece_move_has_confirmation_and_explicit_source(self):
        self.lua.execute("""
            tackShop={available=true,purchases=true,loadout={},owned={{instanceId=101,revision=4,
                catalogId=Tack.CatalogBySlot.saddle[1].id,condition=67,horseId='22222222-2222-4222-8222-222222222222'}}}
            local original=Stables.Client.Rpc
            Stables.Client.Rpc=function(action,p)
                if action=='menu_tack_equip' then equipRequest=p;return {ok=false,code='tack_conflict'} end
                return original(action,p)
            end
        """)
        self.tack()
        self.lua.execute("pages[activePage]['tack-owned']({value='101'})")
        self.assertIn('Move this tack',self.lua.globals().specs['tack-equip']['confirm']['message'])
        self.lua.execute("Click('tack-equip');RunJobs()")
        self.assertEqual(self.lua.globals().equipRequest.fromHorseId,'22222222-2222-4222-8222-222222222222')
        self.assertIn('Refresh',self.lua.globals().labels['tack-error'])

    def test_owned_assembly_preview_uses_its_parts_and_detach_carries_source_anchor(self):
        self.lua.execute("""
            tackShop={available=true,purchases=true,loadout={},owned={
                {instanceId=101,slot='saddle',revision=0,catalogId=Tack.CatalogBySlot.saddle[1].id,condition=100},
                {instanceId=102,slot='stirrups',revision=2,catalogId=Tack.CatalogBySlot.stirrups[2].id,condition=75,saddleId=101}}}
            local original=Stables.Client.Rpc
            Stables.Client.Rpc=function(action,p)
                if action=='menu_tack_equip' then equipRequest=p;return {ok=false,code='tack_conflict'} end
                return original(action,p)
            end
        """)
        self.tack()
        self.lua.execute("pages[activePage]['tack-owned']({value='101'})")
        self.assertEqual(self.lua.globals().previewOther.stirrups,self.lua.globals().Tack.CatalogBySlot.stirrups[2].id)
        self.lua.execute("pages[activePage]['tack-category']({value='stirrups'});pages[activePage]['tack-owned']({value='102'});Click('tack-detach');RunJobs()")
        self.assertTrue(self.lua.globals().equipRequest.detach)
        self.assertEqual(self.lua.globals().equipRequest.fromSaddleId,101)
        self.assertEqual(self.lua.globals().equipRequest.expectedInstanceId,102)

    def test_stable_collection_explains_shared_storage(self):
        self.lua.execute("tackShop={available=true,purchases=true,storage='stable',loadout={},owned={}}")
        self.tack()
        self.assertIn('available at every stable',self.lua.globals().labels['tack-storage'])

    def test_active_horse_cannot_enter_saddle_browser(self):
        self.open()
        self.lua.execute("detail.availability='active';Tab('tack');RunJobs()")
        self.assertIn('Select a stored horse',self.lua.globals().labels['tack-empty'])
        self.assertIsNone(self.lua.globals().previewSaddle)

    def test_missing_tack_scripts_preserve_details_and_report_loading_problem(self):
        self.open()
        self.lua.execute("Click('horse-1');RunJobs();Click('horse-1-details');RunJobs();Stables.Preview.CanPreviewTack=function() return false end;Tack=nil;HorseAppearance=nil;Tab('tack');RunJobs()")
        self.assertEqual(self.lua.globals().labels['title'],'Stats & Details')
        self.assertIn('Tack scripts are not loaded',self.lua.globals().lastMessage)
        self.lua.execute("Click('close');RunJobs()")
        self.assertEqual(self.lua.globals().destroyed,1)

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
        self.assertEqual(len(list(self.lua.globals().pages.items())),4)

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
        self.assertEqual(len(list(self.lua.globals().pages.items())),4)
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
        self.assertEqual(len(list(self.lua.globals().pages.items())),4)

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
        self.assertEqual(len(list(self.lua.globals().pages.items())),4)

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
        self.assertEqual(len(list(self.lua.globals().pages.items())),4)
        self.assertEqual(self.lua.globals().previews,previews)
        self.assertNotIn('menu_close',list(self.lua.globals().calls.values()))

    def test_language_change_stays_on_details(self):
        self.details()
        self.lua.execute("dictionaries.fr_fr.stables_menu_details='Détails';lang='fr_fr';events['feather-core:locale:changed']()")
        self.assertEqual(self.lua.globals().labels['title'],'Détails')
        self.assertEqual(len(list(self.lua.globals().pages.items())),4)

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
