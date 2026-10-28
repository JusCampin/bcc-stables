-- Feather Inventory definitions only. Requires its existing items/categories
-- tables. Do NOT run the legacy VORP database/schema.sql on a Feather server.
-- Idempotent: existing definitions/owned instances are not overwritten.
START TRANSACTION;
INSERT INTO categories (name) VALUES ('Stables') ON DUPLICATE KEY UPDATE name=VALUES(name);
INSERT INTO items (name, display_name, description, max_quantity, max_stack_size, weight, usable, category_id, type, instance_mode)
SELECT seed.name, seed.label, seed.description, seed.quantity, seed.stack_size, seed.weight, seed.usable, c.id, 'item_item', 'stack'
FROM (
    SELECT 'horsebrush' AS name,'Horse Brush' AS label,'A brush used for grooming horses.' AS description, 5 AS quantity, 1 AS stack_size, 0.50 AS weight, 1 AS usable
    UNION ALL SELECT 'consumable_haycube', 'Haycube', 'A compact cube of hay.', 10, 10, 0.25, 1
    UNION ALL SELECT 'consumable_carrots', 'Carrots', 'Carrots for feeding horses.', 10, 10, 0.20, 1
    UNION ALL SELECT 'consumable_apple', 'Apple', 'An apple for feeding horses.', 10, 10, 0.20, 1
    UNION ALL SELECT 'oil_lantern', 'Oil Lantern', 'A portable light source.', 1, 1, 1.00, 0
    UNION ALL SELECT 'consumable_horse_reviver', 'Horse Reviver', 'Curative compound for an injured horse.', 3, 3, 0.50, 0
    UNION ALL SELECT 'diamond', 'Diamond', 'A precious gemstone.', 20, 10, 0.05, 0
) seed JOIN categories c ON c.name='Stables' WHERE 1=1
ON DUPLICATE KEY UPDATE name=VALUES(name);
COMMIT;
-- Brush units need independent slots for different durability metadata. Fresh
-- brushes use max_stack_size=1; split existing multi-brush stacks before use.
-- Lantern/reviver/diamond are defined for preserved configuration, but their
-- gameplay remains disabled. Registering a definition does not enable its use.
SELECT name, type, instance_mode, max_stack_size, usable FROM items WHERE name IN
('horsebrush', 'consumable_haycube', 'consumable_carrots', 'consumable_apple', 'oil_lantern', 'consumable_horse_reviver', 'diamond');
