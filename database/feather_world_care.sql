-- Install after feather_bonding.sql, before enabling Config.worldCare.
ALTER TABLE fs_horse_bonding ADD COLUMN IF NOT EXISTS last_drink_at BIGINT UNSIGNED NOT NULL DEFAULT 0;
