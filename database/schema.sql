CREATE TABLE IF NOT EXISTS `bcc_player_horses` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `charid` INT(11) NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `model` VARCHAR(100) NOT NULL,
  `gender` ENUM('male', 'female') NOT NULL DEFAULT 'male',
  `is_selected` TINYINT(1) NOT NULL DEFAULT 0,
  `is_dead` TINYINT(1) NOT NULL DEFAULT 0,
  `is_writhing` TINYINT(1) NOT NULL DEFAULT 0,
  `captured` TINYINT(1) NOT NULL DEFAULT 0,
  `xp` INT(11) NOT NULL DEFAULT 0,
  `training_levels_applied` INT UNSIGNED NOT NULL DEFAULT 0,
  `stats` TEXT NOT NULL DEFAULT '{}',
  `current_health` TINYINT UNSIGNED NOT NULL DEFAULT 100,
  `current_stamina` TINYINT UNSIGNED NOT NULL DEFAULT 100,
  `born_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `natural_death_at` DATETIME DEFAULT NULL,
  `aging_initialized` TINYINT(1) NOT NULL DEFAULT 0,
  `aging_exempt` TINYINT(1) NOT NULL DEFAULT 0,
  `died_at` DATETIME DEFAULT NULL,
  `death_cause` VARCHAR(32) DEFAULT NULL,
  PRIMARY KEY (`id`),
  INDEX `idx_character_horses` (`charid`, `is_dead`),
  INDEX `idx_horse_natural_death` (`is_dead`, `aging_exempt`, `natural_death_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bcc_horse_tack_items` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `charid` INT(11) NOT NULL,
  `catalog_id` VARCHAR(100) NOT NULL,
  `durability` TINYINT UNSIGNED NOT NULL DEFAULT 100,
  `acquisition_token` CHAR(36) DEFAULT NULL,
  `acquired_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_tack_acquisition_token` (`acquisition_token`),
  INDEX `idx_tack_character_catalog` (`charid`, `catalog_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bcc_horse_tack_loadouts` (
  `horse_id` INT(11) NOT NULL,
  `slot` VARCHAR(32) NOT NULL,
  `tack_item_id` BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (`horse_id`, `slot`),
  UNIQUE KEY `uq_equipped_tack_item` (`tack_item_id`),
  CONSTRAINT `fk_tack_loadout_horse`
    FOREIGN KEY (`horse_id`) REFERENCES `bcc_player_horses` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_tack_loadout_item`
    FOREIGN KEY (`tack_item_id`) REFERENCES `bcc_horse_tack_items` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `items`(`item`, `label`, `limit`, `can_remove`, `type`, `usable`, `desc`)
VALUES
  ('oil_lantern', 'Oil Lantern', 1, 1, 'item_standard', 1, 'A portable light source.'),
  ('consumable_horse_reviver', 'Horse Reviver', 3, 1, 'item_standard', 1, 'Curative compound for injured horse.'),
  ('consumable_haycube', 'Haycube', 10, 1, 'item_standard', 1, 'A compact cube of hay.'),
  ('horsebrush', 'Horse Brush', 5, 1, 'item_standard', 1, 'A brush used for grooming horses.'),
  ('consumable_apple', 'Apple', 10, 1, 'item_standard', 1, 'A juicy and delicious fruit.'),
  ('consumable_carrots', 'Carrots', 10, 1, 'item_standard', 1, 'An orange root vegetable commonly used in cooking.'),
  ('diamond', 'Diamond', 20, 1, 'item_standard', 1, 'A precious gemstone known for its brilliance and value.')
ON DUPLICATE KEY UPDATE
  `label`=VALUES(`label`),
  `limit`=VALUES(`limit`),
  `can_remove`=VALUES(`can_remove`),
  `type`=VALUES(`type`),
  `usable`=VALUES(`usable`),
  `desc`=VALUES(`desc`);
