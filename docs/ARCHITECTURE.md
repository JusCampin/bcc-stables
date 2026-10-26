# BCC Horses architecture

`bcc-horses` is the required horse platform. It owns horse identity, ownership, spawning,
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

Feature resources must validate horses through `bcc-horses` exports and must not directly
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

- `bcc-horses:client:horseSpawned`
- `bcc-horses:client:horseReturned`

Server-local events:

- `bcc-horses:server:horseCreated`
- `bcc-horses:server:horseSelected`
- `bcc-horses:server:horseRemoved`
- `bcc-horses:server:horseOwnerChanged`
- `bcc-horses:server:xpAwarded`

## Custom coats and breeding

Custom coat assets and catalog metadata belong to `bcc-horse-coats`. The core should store
only a stable coat identifier on the horse record once that feature is implemented.

Breeding belongs to `bcc-horse-breeding`. It should own lineage and pregnancy tables, use
core exports for parent ownership and availability, and request foal creation through a
dedicated core export rather than inserting directly into `bcc_player_horses`.
