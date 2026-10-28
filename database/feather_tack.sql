-- Optional Feather tack feature. Idempotent; rerun when adding categories.
-- Does not alter the existing schema-11 migration ledger or legacy VORP tables.
CREATE TABLE IF NOT EXISTS fs_tack_orders (
    operation_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    character_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    state ENUM('reserved','payment_pending','paid','fulfilled','cancelled') NOT NULL,
    record_json LONGTEXT NOT NULL,
    payment_transaction_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
    instance_id BIGINT UNSIGNED NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY fs_tack_payment (payment_transaction_id),
    UNIQUE KEY fs_tack_instance (instance_id),
    KEY fs_tack_recovery (state,updated_at),
    KEY fs_tack_character (character_id,state)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
-- Inventory owns the actual piece; catalog/style/condition are instance metadata.
-- Existing definitions are preserved. Startup refuses an incompatible definition.
INSERT INTO categories (name) VALUES ('Stables') ON DUPLICATE KEY UPDATE name=VALUES(name);
INSERT INTO items (name,display_name,description,max_quantity,max_stack_size,weight,usable,category_id,type,instance_mode)
SELECT seed.name,seed.label,seed.description,50,1,seed.weight,0,c.id,'item_item','unique'
FROM (
    SELECT 'horse_saddle' AS name,'Horse Saddle' AS label,'A saddle owned by your character.' AS description,1.00 AS weight
    UNION ALL SELECT 'horse_saddlecloth','Saddlecloth','A saddlecloth owned by your character.',0.25
    UNION ALL SELECT 'horse_stirrups','Stirrups','Stirrups owned by your character.',0.50
    UNION ALL SELECT 'horse_saddle_horn','Saddle Horn','A saddle horn owned by your character.',0.25
) seed JOIN categories c ON c.name='Stables' WHERE 1=1
ON DUPLICATE KEY UPDATE name=VALUES(name);
