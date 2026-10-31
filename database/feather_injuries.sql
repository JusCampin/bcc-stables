-- Existing schema 11 and feather_items.sql are prerequisites. This changes only
-- the established reviver definition's Use flag, not items owned by players.
UPDATE items SET usable=1
WHERE name='consumable_horse_reviver' AND type='item_item' AND instance_mode='stack';
SELECT name,type,instance_mode,usable FROM items WHERE name='consumable_horse_reviver';
