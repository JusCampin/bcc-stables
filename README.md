# bcc-horses

> `bcc-horses` is the required core for the modular BCC horse ecosystem. Optional care,
> training, tack, lifecycle, custom-coat, breeding, and ability resources integrate through
> its public exports and lifecycle events. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

Implemented optional resources currently include `bcc-horse-training`,
`bcc-horse-abilities`, and `bcc-horse-trading`.

## Description

Embark on an adventure through the untamed wilderness of the Old West with bcc-horses! Here, your trusty steed awaits, ready to be personalized with unique mane styles, tail variations, coat colors, and stylish accessories. Groom, feed, and clean your horse to keep them at peak performance.

## Features

- **Horse Management**: Buy and sell horses through the stables using cash and/or gold.
- **Ownership Limits**: Maximum owned horses can be set separately for players and trainers in the config.
- **Inventory Management**: Individual inventory size for each horse model.
- **Customization**: Choose horse gender at purchase and use oil lanterns from inventory to equip a lantern to your horse.
- **Owned Tack**: Purchased tack belongs to the character, can be moved between owned horses, and retains its own durability value.
- **Shop Hours**: Set individually for each stable or disable to keep the stable open.
- **Blips**: Colored and changeable per stable location, reflecting if the stable is open, closed, or job-locked.
- **Access Control**: Stable access can be limited by job and job grade.
- **Horse Return**: Return horse at stable (when open) or using the flee button in the horse menu.
- **Care and Maintenance**: Feed and water your horse to increase health and stamina. Brushing your horse will clean it and give a slight increase in health and stamina.
- **Stat System**: Each horse breed has base stats (speed, acceleration, handling, health, stamina) on a 1-10 scale, stored as JSON in the database. Stats increase through the level-up system.
- **Data Persistence**: Horse stats (health, stamina, speed, acceleration, handling) are saved as a JSON object in the `stats` column. Health and stamina core values are derived from these stats on spawn and saved back on despawn.
- **Cooldown**: Configurable cooldown time for selling tamed horses.
- **NPC Spawns**: Distance-based NPC spawns.
- **Progression System**: Ordinary care and riding actions award bonding/stat XP.
- **Optional Professional Training**: Paid player-to-player sessions are supplied by the separate `bcc-horse-training` resource.
- **Config Options**: Only trainers can buy horses from a stable (set per stable).
- **Revival**: Revive your downed horse using the horse reviver item.
- **Looting**: Allow player horse looting.
- **Death Management**: Horse death behavior configured in `config/settings.lua`.

## Horse Training

### XP & Bonding System

Gain XP by riding, feeding, watering, and brushing your horse. As XP accumulates, the horse progresses through bonding levels (0-4) which unlock new abilities and tricks. XP also drives the stat leveling system for permanent stat upgrades.

#### Bonding Levels

- **Level 1**: Horse can drink from rivers and lakes.
- **Level 2**:
  - Horse can rest. *(Future update will regain stamina)*
  - Shocking events disabled for a calmer horse.
  - Trick: **Rear-Up** by pressing `left-ctrl` + `space`
- **Level 3**:
  - Horse can sleep. *(Future update will regain health and stamina)*
  - Gunshot flee response disabled.
  - Trick: **Skid/Slide** by pressing `left-ctrl`
- **Level 4**:
  - Horse can wallow.
  - Trick: **Dance** by pressing `space`
  - Trick: **Side-Pass** by pressing `space` + `A` or `D`

#### Stat Leveling System

- Every `xpPerLevel` XP (default: 1000), the horse gains a level and one stat increases by 1.
- Stats cycle in order: **Health → Stamina → Handling → Acceleration → Speed** (repeats every 5 levels).
- Stat upgrades are permanent and saved to the database.
- XP continues to accumulate even after reaching max bonding level — stat upgrades are independent of bonding.

### Health & Stamina System

- Health and stamina are derived from the horse's `health` and `stamina` stats (1-10 scale), scaled to 0-100 core values on spawn (`stat * 10`).
- **Boosts** (from feeding, watering, brushing) use `EnableAttributeCoreOverpower` to temporarily exceed the horse's natural maximum with a gold-core visual effect. Boosts decay naturally and are **not** saved to the database.
- On despawn/return/flee, current core values are read, converted back to the 1-10 scale, and saved in the `stats` JSON column.
- The separate `health` and `stamina` database columns have been removed — all stat data is stored in the `stats` JSON column.

## Horse Taming

- Tame wild horses and return to a trainer area to sell or register your tamed horse.
  - If you want to keep the tame and have room in your stable, pay a registration fee, and it will be added to your stable.
- Job check if Trainer job is required.
- If the player does not have the Trainer job, the tamed horse can be given to a trainer to sell or register.

## Horse Trading

- While leading your horse, approach another player, and a trade prompt will appear.
- Tack is character-owned, so equipped tack is returned to the sender's inventory when a horse is traded.

## Horse Tack

Tack settings live in `config/tack/catalog.lua`, with each component category in its own `config/tack/categories/<category>.lua` file. Currency is configured once for the entire tack shop:

```lua
TackConfig = {
    currency = TackCurrency.EITHER,
}
```

- `TackCurrency.CASH`: cash only
- `TackCurrency.GOLD`: gold only
- `TackCurrency.EITHER`: the player chooses cash or gold at checkout
- `TackCurrency.FREE`: no charge

Components contain explicit display labels and both possible prices:

```lua
{ label = 'Saddlecloth 1', hash = '0x127E0412', cashPrice = 10, goldPrice = 1 }
```

Purchased pieces are stored in `bcc_horse_tack_items`; equipped slots are stored in `bcc_horse_tack_loadouts`. Durability is persisted but is not consumed in this release. The service layer supports unequipped item transfers, while player-facing tack trading is reserved for a later UI.

## Tips

- **Whistling**: A short whistle will call your horse. A long one will set your horse to follow you. A second whistle or mounting your horse will cancel following.
- **Horse Info**: Press `Q` in the horse prompts to view standard horse info.

## Commands

- `/horseRespawn`: Respawn your horse while bypassing the distance check.
- `/horseInfo`: View more detailed horse info than the standard **Show Info** display.
- `/horseSetWild`: *Dev Mode Only* - Set a tamed horse wild to test taming.
- `/horseWrithe`: *Dev Mode Only* - Set horse to writhe state to test reviving.

## Configuration

### Horse Catalog (`config/horse_catalog.lua`)

Each horse breed includes base stats on a 0-9 configuration scale. The UI displays these values as 1-10:

```lua
stats = { speed = 5, acceleration = 4, handling = 3, health = 6, stamina = 7 }
```

These base stats are used on initial spawn and can be increased through the level-up system.

### Care Boosts (`config/care.lua`)

Boost values are additive on top of the current core value (0-100). When the boost would exceed the horse's natural maximum, `EnableAttributeCoreOverpower` is used to create a temporary gold-core effect that decays naturally. Boosts are **not** saved to the database.

```lua
Config.care.boosts = {
    brush = { health = 10, stamina = 10 },
    feed = { health = 20, stamina = 20 },
    drink = { health = 20, stamina = 20 },
}
```

### XP & Leveling (`config/training.lua`)

```lua
Config.training.xpPerLevel = 1000
Config.training.xpRewards = {
    brush = 1,
    pat = 1,
    feed = 1,
    drink = 1,
    riding = 5,
    leading = 5,
}
Config.training.showXpMessage = true
Config.training.showLevelUpMessage = true
```

## Dependencies

- [vorp_core](https://github.com/VORPCORE/vorp-core-lua)
- [vorp_inventory](https://github.com/VORPCORE/vorp_inventory-lua)
- [bcc-utils](https://github.com/BryceCanyonCounty/bcc-utils)
- [feather-menu](https://github.com/FeatherFramework/feather-menu/releases)

## Installation

1. Make sure dependencies are installed/updated and ensured before this script.
2. Download the latest release `bcc-horses.zip` at [/releases/latest](https://github.com/BryceCanyonCounty/bcc-horses/releases/latest).
3. Add the `bcc-horses` folder to your resources folder.
4. Add `ensure bcc-horses` to your `server.cfg`.
5. Run the included database file `database/schema.sql`.
6. Add images from `assets/inventory` to: `...\vorp_inventory\html\img\items`.
7. Restart the server.

The `stats` JSON column stores progression ranks. Current health and stamina core percentages are stored separately in `current_health` and `current_stamina`.

## Credits

- lrp_stables
- [ByteSizd](https://github.com/AndrewR3K) - Vue Boilerplate for RedM
- [SavSin](https://github.com/DavFount) - UI conversion to VueJS
- Stephenlikewhoa
- [Dokoboe](https://github.com/dokoboe)

## GitHub

- [bcc-horses](https://github.com/BryceCanyonCounty/bcc-horses)
