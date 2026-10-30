-- Optional stable horse buy-back. Leaves the schema-11 ledger and horse history intact.
CREATE TABLE IF NOT EXISTS fs_horse_sales (
    operation_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    character_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    horse_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    state VARCHAR(24) NOT NULL,
    record_json LONGTEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY fs_horse_sales_recovery(state,updated_at),
    KEY fs_horse_sales_horse(horse_id,state)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
