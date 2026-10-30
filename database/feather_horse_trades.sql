-- Optional player horse trades; no changes to the original purchase ledger.
CREATE TABLE IF NOT EXISTS fs_horse_trades (
    operation_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    horse_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    seller_character_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    buyer_character_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    state VARCHAR(24) NOT NULL,
    record_json LONGTEXT NOT NULL,
    payment_transaction_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY fs_horse_trade_recovery(state,updated_at),
    KEY fs_horse_trade_buyer(buyer_character_id,state),
    KEY fs_horse_trade_seller(seller_character_id,state),
    KEY fs_horse_trade_horse(horse_id,state)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
