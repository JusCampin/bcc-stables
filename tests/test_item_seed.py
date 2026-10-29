"""Definition insert semantics on SQLite; MariaDB syntax acceptance is live pending."""
import sqlite3
import unittest
from test_feather_boundary import ROOT


class ItemSeedTest(unittest.TestCase):
    def test_tack_seed_preserves_existing_definitions_and_uses_unique_instances(self):
        db=sqlite3.connect(':memory:')
        db.executescript('''CREATE TABLE categories(id INTEGER PRIMARY KEY,name TEXT UNIQUE);
          CREATE TABLE items(id INTEGER PRIMARY KEY,name TEXT UNIQUE,display_name TEXT,description TEXT,
          max_quantity INTEGER,max_stack_size INTEGER,weight REAL,usable INTEGER,category_id INTEGER,
          type TEXT,instance_mode TEXT);''')
        source=(ROOT/'database/feather_tack.sql').read_text(encoding='utf-8')
        sql=source[source.index('INSERT INTO categories'):source.index('-- Durable resale')]
        sql=sql.replace('ON DUPLICATE KEY UPDATE name=VALUES(name)','ON CONFLICT(name) DO NOTHING')
        db.executescript(sql);db.executescript(sql)
        self.assertEqual(db.execute("SELECT instance_mode,max_stack_size FROM items WHERE name='horse_saddle'").fetchone(),('unique',1))
        self.assertEqual({r[0] for r in db.execute('SELECT name FROM items')},
            {'horse_bridle', 'horse_mustache', 'horse_horseshoes', 'horse_tail', 'horse_saddle', 'horse_stirrups', 'horse_saddlebag', 'horse_mask', 'horse_mane', 'horse_saddlecloth', 'horse_saddle_horn', 'horse_bedroll', 'horse_holster'})
        self.assertEqual(db.execute("SELECT COUNT(*) FROM items WHERE instance_mode='unique' AND max_stack_size=1").fetchone()[0],13)
        db.execute("UPDATE items SET display_name='Custom Saddle',weight=2.5");db.commit();db.executescript(sql)
        self.assertEqual(db.execute('SELECT display_name,weight FROM items').fetchone(),('Custom Saddle',2.5))
        self.assertNotIn('CREATE TABLE IF NOT EXISTS fs_tack_loadouts',source)
        db.close()

    def test_feather_seed_inserts_established_items_and_preserves_existing_definitions(self):
        db=sqlite3.connect(':memory:')
        db.executescript('''CREATE TABLE categories(id INTEGER PRIMARY KEY,name TEXT UNIQUE);
          CREATE TABLE items(id INTEGER PRIMARY KEY,name TEXT UNIQUE,display_name TEXT,description TEXT,
          max_quantity INTEGER,max_stack_size INTEGER,weight REAL,usable INTEGER,category_id INTEGER REFERENCES categories(id),
          type TEXT CHECK(type='item_item'),instance_mode TEXT CHECK(instance_mode IN ('stack','unique')));
          INSERT INTO categories VALUES(9,'Existing');
          INSERT INTO items(name,display_name,weight,category_id,type,instance_mode) VALUES('consumable_apple','Custom Apple',9.99,9,'item_item','stack');''')
        sql=(ROOT/'database/feather_items.sql').read_text(encoding='utf-8')
        sql=sql.replace('START TRANSACTION','BEGIN').replace('ON DUPLICATE KEY UPDATE name=VALUES(name)','ON CONFLICT(name) DO NOTHING')
        db.executescript(sql);db.executescript(sql)
        names={row[0] for row in db.execute('SELECT name FROM items')}
        self.assertEqual(names,{'horsebrush','consumable_haycube','consumable_carrots','consumable_apple',
                               'oil_lantern','consumable_horse_reviver','diamond'})
        self.assertEqual(db.execute("SELECT max_stack_size FROM items WHERE name='horsebrush'").fetchone()[0],1)
        self.assertEqual(db.execute("SELECT display_name,weight,category_id FROM items WHERE name='consumable_apple'").fetchone(),('Custom Apple',9.99,9))
        self.assertEqual(db.execute("SELECT usable FROM items WHERE name='consumable_horse_reviver'").fetchone()[0],0)
        db.close()
