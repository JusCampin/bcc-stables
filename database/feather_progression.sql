-- Run after feather_bonding.sql on existing installations. Safe to run again.
ALTER TABLE fs_horse_bonding ADD COLUMN IF NOT EXISTS training_json LONGTEXT NULL;
