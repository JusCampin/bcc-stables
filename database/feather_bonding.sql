-- Optional saved bonding XP. Horse identity survives sale/trade/recall.
-- Existing horses without a row start at zero; no legacy XP is imported.
CREATE TABLE IF NOT EXISTS fs_horse_bonding (
    horse_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    xp BIGINT UNSIGNED NOT NULL DEFAULT 0,
    revision BIGINT UNSIGNED NOT NULL DEFAULT 0,
    training_json LONGTEXT NULL,
    travel_generation CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
    travel_sequence BIGINT UNSIGNED NOT NULL DEFAULT 0,
    last_feed_at BIGINT UNSIGNED NOT NULL DEFAULT 0,
    last_brush_at BIGINT UNSIGNED NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
