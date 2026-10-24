-- Immutable once applied. Later schema changes belong in a new migration.
Stables.Migrations = {
    { id = '001_purchase_foundation', tables = {
        { name = 'fs_character_stables', sql = [[CREATE TABLE IF NOT EXISTS `fs_character_stables` (
            `character_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `selected_horse_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
            `revision` BIGINT UNSIGNED NOT NULL DEFAULT 0,
            PRIMARY KEY (`character_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]] },
        { name = 'fs_operations', sql = [[CREATE TABLE IF NOT EXISTS `fs_operations` (
            `operation_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `kind` VARCHAR(32) NOT NULL DEFAULT 'horse_purchase',
            `character_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `horse_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `quote_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `catalog_id` VARCHAR(64) NOT NULL,
            `catalog_revision` BIGINT UNSIGNED NOT NULL,
            `currency` VARCHAR(32) NOT NULL,
            `amount` BIGINT UNSIGNED NOT NULL,
            `wallet_account_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `sink_account_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `payment_key` VARCHAR(128) NOT NULL,
            `fingerprint` VARCHAR(768) NOT NULL,
            `state` VARCHAR(32) NOT NULL,
            `revision` BIGINT UNSIGNED NOT NULL,
            `payment_transaction_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
            `refund_transaction_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
            `record_json` LONGTEXT NOT NULL,
            `next_attempt_at` TIMESTAMP NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`operation_id`),
            UNIQUE KEY `fs_operation_horse` (`horse_id`),
            UNIQUE KEY `fs_payment_key` (`payment_key`),
            UNIQUE KEY `fs_payment_transaction` (`payment_transaction_id`),
            UNIQUE KEY `fs_refund_transaction` (`refund_transaction_id`),
            KEY `fs_operation_character` (`character_id`,`state`),
            KEY `fs_operation_retry` (`state`,`next_attempt_at`,`operation_id`),
            CHECK (`kind` = 'horse_purchase'),
            CHECK (`amount` BETWEEN 1 AND 9007199254740991),
            CHECK (`catalog_revision` BETWEEN 1 AND 9007199254740991),
            CHECK (`revision` <= 9007199254740991),
            CHECK (`state` IN ('reserved','payment_pending','paid','fulfilled','compensation_pending','refunded','cancelled','reconciliation_required')),
            CHECK (JSON_VALID(`record_json`))
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]] },
        { name = 'fs_horses', sql = [[CREATE TABLE IF NOT EXISTS `fs_horses` (
            `horse_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `owner_character_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `origin_operation_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `catalog_id` VARCHAR(64) NOT NULL,
            `catalog_revision` BIGINT UNSIGNED NOT NULL,
            `biological_state` VARCHAR(16) NOT NULL DEFAULT 'alive',
            `availability` VARCHAR(24) NOT NULL DEFAULT 'stored',
            `revision` BIGINT UNSIGNED NOT NULL DEFAULT 0,
            `acquired_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`horse_id`),
            UNIQUE KEY `fs_horse_origin` (`origin_operation_id`),
            KEY `fs_horse_owner` (`owner_character_id`,`availability`),
            CONSTRAINT `fs_horse_operation` FOREIGN KEY (`origin_operation_id`) REFERENCES `fs_operations` (`operation_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]] },
        { name = 'fs_horse_history', sql = [[CREATE TABLE IF NOT EXISTS `fs_horse_history` (
            `event_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `horse_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `operation_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `event_kind` VARCHAR(48) NOT NULL,
            `facts_json` LONGTEXT NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`event_id`),
            UNIQUE KEY `fs_history_operation` (`operation_id`,`event_kind`),
            CHECK (JSON_VALID(`facts_json`))
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]] },
        { name = 'fs_outbox', sql = [[CREATE TABLE IF NOT EXISTS `fs_outbox` (
            `event_id` VARCHAR(100) NOT NULL,
            `operation_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `event_name` VARCHAR(100) NOT NULL,
            `payload_json` LONGTEXT NOT NULL,
            `delivered` TINYINT UNSIGNED NOT NULL DEFAULT 0,
            `attempts` INT UNSIGNED NOT NULL DEFAULT 0,
            `next_attempt_at` TIMESTAMP NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`event_id`),
            UNIQUE KEY `fs_outbox_operation` (`operation_id`,`event_name`),
            KEY `fs_outbox_pending` (`delivered`,`next_attempt_at`),
            CHECK (JSON_VALID(`payload_json`))
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]] },
    } },
    { id = '002_asset_registration', tables = {
        { name = 'fs_asset_registrations', sql = [[CREATE TABLE IF NOT EXISTS `fs_asset_registrations` (
            `operation_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `character_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `horse_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `request_id` VARCHAR(128) NOT NULL,
            `model_key` VARCHAR(100) NOT NULL,
            `fingerprint` VARCHAR(900) NOT NULL,
            `request_json` LONGTEXT NOT NULL,
            `state` VARCHAR(24) NOT NULL DEFAULT 'prepared',
            `asset_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
            `asset_revision` BIGINT UNSIGNED NULL,
            `revision` BIGINT UNSIGNED NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`operation_id`),
            UNIQUE KEY `fs_asset_request` (`request_id`),
            UNIQUE KEY `fs_asset_local_horse` (`horse_id`),
            UNIQUE KEY `fs_asset_identity` (`asset_id`),
            CONSTRAINT `fs_asset_operation` FOREIGN KEY (`operation_id`) REFERENCES `fs_operations` (`operation_id`),
            CHECK (`state` IN ('prepared','submitted','linked')),
            CHECK (`revision` <= 9007199254740991),
            CHECK ((`state` = 'linked' AND `asset_id` IS NOT NULL AND `asset_revision` IS NOT NULL AND `asset_revision` >= 1)
                OR (`state` <> 'linked' AND `asset_id` IS NULL AND `asset_revision` IS NULL)),
            CHECK (JSON_VALID(`request_json`))
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]] },
    } },
    { id = '003_call_generations', tables = {
        { name = 'fs_call_leases', sql = [[CREATE TABLE IF NOT EXISTS `fs_call_leases` (
            `generation_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `character_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `horse_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `operation_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `asset_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `model_key` VARCHAR(100) NOT NULL,
            `session_id` VARCHAR(128) NOT NULL,
            `source_id` INT UNSIGNED NOT NULL,
            `selection_revision` BIGINT UNSIGNED NOT NULL,
            `state` VARCHAR(32) NOT NULL DEFAULT 'prepared',
            `revision` BIGINT UNSIGNED NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`generation_id`), KEY `fs_call_character` (`character_id`,`state`),
            CONSTRAINT `fs_call_operation` FOREIGN KEY (`operation_id`) REFERENCES `fs_operations` (`operation_id`),
            CONSTRAINT `fs_call_horse` FOREIGN KEY (`horse_id`) REFERENCES `fs_horses` (`horse_id`),
            CHECK (`state` IN ('prepared','submitting','active','cleanup_pending','released','reconciliation_required')),
            CHECK (`selection_revision` <= 9007199254740991), CHECK (`revision` <= 9007199254740991)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]] },
        { name = 'fs_call_slots', sql = [[CREATE TABLE IF NOT EXISTS `fs_call_slots` (
            `character_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `horse_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `generation_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            PRIMARY KEY (`character_id`), UNIQUE KEY `fs_call_slot_horse` (`horse_id`),
            UNIQUE KEY `fs_call_slot_generation` (`generation_id`),
            CONSTRAINT `fs_call_slot_lease` FOREIGN KEY (`generation_id`) REFERENCES `fs_call_leases` (`generation_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]] },
    } },
    { id = '004_call_bindings', tables = {
        { name = 'fs_call_bindings', sql = [[CREATE TABLE IF NOT EXISTS `fs_call_bindings` (
            `generation_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `observer_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `network_id` INT UNSIGNED NOT NULL,
            `initial_owner` INT UNSIGNED NOT NULL,
            `routing_bucket` INT UNSIGNED NOT NULL,
            `state` VARCHAR(32) NOT NULL DEFAULT 'bound',
            `revision` BIGINT UNSIGNED NOT NULL DEFAULT 0,
            `reason` VARCHAR(48) NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`generation_id`),
            CONSTRAINT `fs_binding_generation` FOREIGN KEY (`generation_id`) REFERENCES `fs_call_leases` (`generation_id`),
            CHECK (`network_id` > 0 AND `network_id` <= 2147483647),
            CHECK (`initial_owner` > 0), CHECK (`routing_bucket` = 0),
            CHECK (`state` IN ('bound','cleanup_pending','cleared','reconciliation_required')),
            CHECK (`revision` <= 2)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]] },
    } },

    { id = '005_call_process_epochs', tables = {
        { name = 'fs_call_process_epochs', sql = [[CREATE TABLE IF NOT EXISTS `fs_call_process_epochs` (
            `generation_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `process_epoch` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`generation_id`),
            CONSTRAINT `fs_call_epoch_generation` FOREIGN KEY (`generation_id`) REFERENCES `fs_call_leases` (`generation_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]] },
    } },

    { id = '006_call_recoveries', tables = {
        { name = 'fs_call_recoveries', sql = [[CREATE TABLE IF NOT EXISTS `fs_call_recoveries` (
            `generation_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `original_epoch` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `resolved_epoch` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `prior_revision` INT UNSIGNED NOT NULL,
            `prior_reason` VARCHAR(48) NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`generation_id`),
            CONSTRAINT `fs_recovery_generation` FOREIGN KEY (`generation_id`) REFERENCES `fs_call_leases` (`generation_id`),
            CHECK (`original_epoch` <> `resolved_epoch`),
            CHECK ((`prior_revision` = 2 AND `prior_reason` IS NULL) OR
                (`prior_revision` IN (3,4) AND `prior_reason` IS NOT NULL AND
                `prior_reason` IN ('restart_lost_observation','identity_lost','submission_unknown','cleanup_unknown')))
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]] },
    } },

    { id = '007_horse_runtime_projection', tables = {
        { name = 'fs_horse_runtime_events', sql = [[CREATE TABLE IF NOT EXISTS `fs_horse_runtime_events` (
            `event_id` VARCHAR(100) NOT NULL,
            `horse_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `generation_id` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            `from_availability` VARCHAR(24) NOT NULL,
            `to_availability` VARCHAR(24) NOT NULL,
            `prior_revision` BIGINT UNSIGNED NOT NULL,
            `revision` BIGINT UNSIGNED NOT NULL,
            `reason` VARCHAR(32) NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`event_id`), UNIQUE KEY `fs_runtime_horse_revision` (`horse_id`,`revision`),
            UNIQUE KEY `fs_runtime_generation_state` (`generation_id`,`to_availability`),
            CONSTRAINT `fs_runtime_horse` FOREIGN KEY (`horse_id`) REFERENCES `fs_horses` (`horse_id`),
            CONSTRAINT `fs_runtime_generation` FOREIGN KEY (`generation_id`) REFERENCES `fs_call_leases` (`generation_id`),
            CHECK (`revision` = `prior_revision` + 1 AND `revision` <= 9007199254740991),
            CHECK ((`from_availability` = 'stored' AND `to_availability` = 'active' AND `reason` = 'bound') OR
                (`from_availability` = 'active' AND `to_availability` = 'stored' AND `reason` IN ('observed_cleanup','process_ended')))
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin]] },
    } },

    { id='008_call_horse_state_index', tables={}, indexes={
        {table='fs_call_leases',name='fs_call_horse_state',columns={'horse_id','state'}}
    } },
}
