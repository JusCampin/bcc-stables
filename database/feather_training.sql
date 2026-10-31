-- Optional professional NPC training. Existing schema 11 and saved bonding
-- are prerequisites; do not modify the original migration ledger.
CREATE TABLE IF NOT EXISTS fs_training_sessions (
    operation_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    character_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    horse_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    state VARCHAR(24) NOT NULL,
    training_day CHAR(10) NOT NULL,
    earned_xp INT UNSIGNED NOT NULL DEFAULT 0,
    payment_transaction_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
    record_json LONGTEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY fs_training_character_state(character_id,state),
    KEY fs_training_horse_day(horse_id,training_day,state)
) ENGINE=InnoDB;
