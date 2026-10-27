# BCC Horses architecture

> **Historical VORP architecture below.** It is not the active Feather contract.
> The release target is one `bcc-stables` resource consolidating abilities,
> trading and training as internal modules. Do not start their separate resources
> or load the legacy numeric-ID exports alongside the current runtime.
> See [current integration](FEATHER_INTEGRATION.md) and
> [the repository-wide audit](FEATHER_REFACTOR_AUDIT.md).

## Current Feather boundaries

Core owns current character/session identity; Assets owns canonical horse
ownership. Stables owns selection, saved gameplay projections and physical call
generations in the existing schema-11 tables. The owned repository reads identity
and fresh Assets ownership; it does not authorize spawning by itself. The call
repository owns transactional lifecycle writes, and the server horse controller
owns observed creation, binding, occupancy, cleanup, confirmed disappearance and
restart reconciliation. Client presentation and whistle task execution operate
under that generation; network ownership may migrate without transferring the
horse to another character.

Economy and Inventory will own currency/item/container operations through supported
provider contracts and receipts. Menu v2 will own rendering/focus; Stables will
own menu sessions, preview entities/camera and authorized gameplay actions.
Preview routing must be coordinated with physical cleanup. Share these boundaries
across internal care, tack, progression, trading, training and abilities modules;
do not create self-export calls or independent horse registries for each feature.

Localization uses each player's selected language from `feather-settings`, across
all Feather and BCC resources. Resources may own translation dictionaries, but
must not independently choose a language through `Config.locale` or an equivalent
resource setting. Use the supported settings contract, including language changes,
and localize server-originated messages for the individual recipient. The legacy
locale configuration below/in preserved source is awaiting replacement.
If the requested language's localization file is missing, fall back to English.

Call/ride/native leading, whistle approach/follow/stop, store and guarded
distance relocation are active. Menu v2 roster/selection/local preview, details, rename and presentation have
been manually confirmed. Read-only catalog browsing now reuses the same preview
session, uses shared configured prices/base stats and is awaiting live testing. Saved condition is restored; care,
inventory, tack, progression, aging/death, training and abilities
remain unloaded source. Horses remain invincible pending lifecycle integration.
Public paid checkout is implemented behind Config.commerce.purchasesEnabled,
with durable same-key Economy/Assets recovery and atomic local fulfillment in the
existing schema. Free/job/trainer checkout and automatic paid-order refunds remain
unimplemented. server/horse/checkout.lua is the internal coordinator; providers
are called outside SQL transactions. It does not revive legacy purchase modules.
Boot validates the existing migration ledger and does not install/reset tables.

Location data now uses `StableLocations`, separate from runtime `Stables`.
Legacy unloaded modules still using the old location namespace require adaptation.
Preserve gameplay/data deliberately;
replace old authority boundaries rather than enabling old init/main files.

## Preserved legacy design (reference only)

`bcc-stables` is the required horse platform. It owns horse identity, ownership, spawning,
selection, progression, stable access, and the authoritative `bcc_player_horses` row.

## Feature resources

- `bcc-horse-care`: grooming, feeding, drinking, grazing, rest, sleep, wallowing, and cleanliness.
- `bcc-horse-training`: paid trainer sessions and per-trainer daily XP limits. Exercises,
  reports, and certifications can be added there without expanding the core.
- `bcc-horse-tack`: tack ownership, catalogs, loadouts, presets, durability, and trading.
- `bcc-horse-lifecycle`: aging, injuries, retirement, and natural death.
- `bcc-horse-coats`: custom coat catalogs, ownership, genetics metadata, and appearance application.
- `bcc-horse-breeding`: breeding eligibility, lineage, pregnancy, foals, traits, and inheritance.
- `bcc-horse-abilities`: flaming hooves and future optional special effects. It owns ability
  items, durability, cooldowns, temporary effects, and ability-specific configuration.
- `bcc-horse-trading`: player-to-player proposals and consent. The feature owns its prompt
  and handshake session, while core performs the authoritative ownership transfer.

Feature resources must validate horses through `bcc-stables` exports and must not directly
change ownership, selection, XP, core stats, or death state in `bcc_player_horses`.

## Client exports

- `GetActiveHorse()` returns the active entity and its current horse metadata.
- `IsActiveHorse(horseId)` checks the active horse, optionally by database ID.
- `ReturnActiveHorse()` sends the active horse away through the core return flow.
- `AcquireInteractionLock(featureName)` reserves horse interaction control for one feature.
- `ReleaseInteractionLock(featureName)` releases that interaction reservation.

## Server exports

- `GetHorse(horseId)` returns an authoritative horse row.
- `GetOwnedHorse(source, horseId)` validates ownership for the source's active character.
- `GetHorseOwner(horseId)` returns the owning character ID.
- `ValidateOwnedHorse(source, horseId, netId)` validates ownership and the spawned entity.
- `IsHorseNearby(source, horseId, distance)` validates proximity to a spawned horse.
- `AddHorseXp(source, horseId, amount, reason)` securely awards XP to that player's living
  horse. This export is server-only and is the supported progression integration point.
- `GetHorseLimit(source)` returns the character's current stable capacity.
- `TransferHorse(senderSource, recipientSource, horseId)` performs a validated ownership
  transfer after an external feature establishes consent.

## Lifecycle events

Client-local events:

- `bcc-stables:client:horseSpawned`
- `bcc-stables:client:horseReturned`

Server-local events:

- `bcc-stables:server:horseCreated`
- `bcc-stables:server:horseSelected`
- `bcc-stables:server:horseRemoved`
- `bcc-stables:server:horseOwnerChanged`
- `bcc-stables:server:xpAwarded`

## Custom coats and breeding

Custom coat assets and catalog metadata belong to `bcc-horse-coats`. The core should store
only a stable coat identifier on the horse record once that feature is implemented.

Breeding belongs to `bcc-horse-breeding`. It should own lineage and pregnancy tables, use
core exports for parent ownership and availability, and request foal creation through a
dedicated core export rather than inserting directly into `bcc_player_horses`.
