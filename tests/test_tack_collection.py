"""Character tack access without creating or assigning a real horse."""
import unittest
import test_tack as tack
from test_call_repository import HORSE


class CollectionOnlyTest(unittest.TestCase):
    def setUp(self):
        self.h=tack.TackTest();self.h.setUp()
        self.lua=self.h.lua;self.db=self.h.db;self.tack=self.h.tack

    def tearDown(self):self.h.tearDown()

    def test_no_horse_collection_lists_items_without_ownership_lookup_or_loadout(self):
        item=self.h.buy().instanceId
        self.db.execute('DELETE FROM fs_horses');self.db.execute('DELETE FROM fs_character_stables');self.db.commit()
        self.lua.execute("Stables.OwnedRepository.ReadOwned=function() error('No horse lookup allowed') end")
        result=self.tack.Shop(self.lua.globals().session,None)
        self.assertTrue(result.ok);self.assertEqual(result.value.owned[1].instanceId,item)
        self.assertEqual(len(result.value.loadout),0)
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM fs_horses').fetchone()[0],0)
        self.assertIsNone(self.db.execute('SELECT selected_horse_id FROM fs_character_stables').fetchone()[0])

    def test_explicit_foreign_or_fake_horse_still_refused(self):
        self.lua.globals().foreignHorse=True
        self.assertEqual(self.tack.Shop(self.lua.globals().session,HORSE).code,'horse_not_owned')
        self.assertEqual(self.tack.Shop(self.lua.globals().session,'tack-display').code,'invalid_input')
        self.assertTrue(self.tack.Shop(self.lua.globals().session,None).ok)

    def test_parked_assembly_can_be_separated_without_a_horse(self):
        saddle=self.h.buy().instanceId;self.assertTrue(self.h.equip(saddle).ok)
        self.h.catalog=self.lua.globals().Tack.CatalogBySlot.saddle_horn[1].id
        horn=self.h.buy().instanceId;self.assertTrue(self.h.equip(horn,slot='saddle_horn').ok)
        self.assertTrue(self.h.equip(0,expected=saddle).ok)
        self.db.execute('DELETE FROM fs_horses');self.db.commit()
        self.lua.globals().foreignHorse=True
        spec=self.lua.table_from(dict(slot='saddle_horn',instanceId=horn,expectedInstanceId=horn,itemRevision=0,detach=True,fromSaddleId=saddle))
        result=self.tack.Equip(self.lua.globals().session,spec,self.lua.globals().Authorize)
        self.assertTrue(result.ok)
        self.assertIsNone(self.lua.globals().equipmentRows['tack_horn_'+str(saddle)])
        self.assertEqual(self.lua.globals().grants,2)

    def test_display_cannot_be_equipped_or_detach_from_a_real_horse(self):
        saddle=self.h.buy().instanceId;self.h.equip(saddle)
        self.h.catalog=self.lua.globals().Tack.CatalogBySlot.saddle_horn[1].id
        horn=self.h.buy().instanceId;self.h.equip(horn,slot='saddle_horn')
        p=dict(slot='saddle_horn',instanceId=horn,expectedInstanceId=horn,itemRevision=0,fromSaddleId=saddle)
        self.assertEqual(self.tack.Equip(self.lua.globals().session,self.lua.table_from(p),self.lua.globals().Authorize).code,'invalid_input')
        p['detach']=True
        self.assertEqual(self.tack.Equip(self.lua.globals().session,self.lua.table_from(p),self.lua.globals().Authorize).code,'tack_conflict')
        self.assertEqual(self.lua.globals().equipmentRows['tack_horn_'+str(saddle)],horn)


if __name__=='__main__':unittest.main()
