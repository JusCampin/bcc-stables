# BCC Horses architecture

> **Historical VORP architecture below.** It is not the active Feather contract.
> The release target is one `bcc-stables` resource consolidating abilities,
> trading and training as internal modules. Do not start their separate resources
> or load the legacy numeric-ID exports alongside the current runtime.
> See [current integration](FEATHER_INTEGRATION.md) and
> [the repository-wide audit](FEATHER_REFACTOR_AUDIT.md).

## Current Feather boundaries

Tack ownership is character-scoped, not horse-scoped. Each purchased piece has its
own durable identity and belongs to the character independently of any horse.
Horse loadouts reference those owned pieces; a piece may be equipped on at most
one horse at a time. Moving it between owned horses changes the equipment
assignment, preserves its identity/condition, and does not purchase it again.
Unequipping retains the piece in the character's tack collection. Horse ownership
must never serve as tack ownership, and tack purchases must not be modeled as
per-horse appearance unlocks. The four-category tack flow implements this through
Inventory unique items and generic equipment slots (`horse_<horse UUID>`), behind
`Config.tack.enabled`. Inventory owns both item and assignment persistence, with
one-instance/one-slot uniqueness. Stables stores only `fs_tack_orders` for durable
quotes, payment and item-delivery recovery; no duplicate tack inventory/loadout
table is introduced. `database/feather_tack.sql` installs that optional table and
the non-weapon unique `horse_saddle`, `horse_saddlecloth`, `horse_stirrups` and
`horse_saddle_horn` definitions; the base migration ledger stays11.

The Horse Tack top tab browses the selected horse's preserved four-category catalog through
the same menu route and local preview. Existing `shared/tack.lua` catalog IDs and
`client/tack/controller.lua` component natives are reused. Catalog selection is local presentation;
explicit checkout adds a piece to My Tack, and Equip assigns it separately.
Leaving the page restores saved equipment; close deletes the
preview and clears component tracking. Saddle removal also clears implicit horn
and stirrup components from presets; explicitly selected pieces are reapplied in
loadout order. Four bounded production menu actions handle collection, quote,
confirmation and equipment; recovery shares the existing checkout worker.
Equipment admission holds the Stables character/call lock, uses Inventory's
data-only revision fence and atomic assignment API, and reads assignments after
uncertain replies. No provider SQL or CFX transaction handle crosses resources.
Synchronous Inventory guards hold pending/equipped pieces, with locked equipment
snapshots protecting move/destroy after restart. Normal recall validates owned
pieces and restores native components. Preview rendering/cleanup passed live;
purchase, moving between horses, saved recall and final cleanup passed the
controlled live test.
Saddlecloths are independent. Custom stirrups/horns attach to a saddle instance
using generic Inventory equipment anchors tack_stir_<instance> / tack_horn_<instance>.
The saddle retains its normal horse_<UUID> assignment while fitted and parks in
tack_saddle_<instance> while unequipped, preserving the assembled unit. Replacing
a saddle parks the old assembly; moving the parent changes the effective horse
of its parts without rewriting them. Remove from Saddle detaches an individual
part. Parent/part condition and identity never change during these operations.
Inventory owns these relationships; no duplicate Stables loadout or assembly table.
Its additive CAS batch API atomically changes declared source/destination/parking
slots, checks ownership and guards, and refuses stale assignments. Legacy per-horse
parts are converted per saddle with the parent slot in the same expected batch.
Saddle Default restores fixed included parts (Stirrup 1 and Saddle Horn 1) without deleting the owned item.
Existing saddle equipment slots and saddle.v1 order/grant receipts remain compatible.
All four categories passed the requested live checks. Assembly movement, breakdown and native recall
also passed the requested live gate on 2026-10-28. Private stable custody is now
implemented and reported working live on 2026-10-28; sale and trade remain pending.
Inventory's inventory_character_collections mapping owns one private container per
resource/purpose/character. Stables uses stables.tack.v1 at every stable. Containers
have no carried character_id, generic owner/public access or client open path. Only
configured caller/purpose/item definitions can be read, adopted, granted or equipped.
Existing eligible carried pieces transfer in bounded batches in one transaction;
IDs, metadata and equipment assignments remain unchanged, while row_revision bumps
once for the custody move. No item is recreated. Collection grants use the existing
unique receipt with an optional payload-bound collectionKey; old carried grant
fingerprints remain unchanged and their historical deliveries are adopted. Stables
keeps immutable order custody terms and uses only data-based scoped exports. Other
resources retain their carried-only item/equipment contracts. Capacity is collection
slots (default 500), separate from carried weight/slots; food/brushes stay carried.
Collection readiness is part of Inventory startup; its optional mapping table is
created there. A location/identity mismatch refuses access instead of recreating
contents. No extra Stables schema, custody table, worker or proof command is added.
Legacy VORP tack services remain unloaded.

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
session and uses shared configured prices/base stats. Catalog presentation and one
paid purchase path are live-confirmed. Saved condition is restored. Feeding is
opt-in through Inventory usable items; the server reserves the exact clicked
instance, snapshots per-food effects, consumes through a durable receipt and
commits the saved benefit once. Current-simulator core depletion is checkpointed
before feeding and normal Store; native readings can only lower saved cores.
Applied-care revisions protect benefits awaiting native delivery. Its callback returns before the animation to
release Inventory's active-use guard. No Feed prompt, idle frame reader or item
search is needed. Brushing shares that pipeline with durable Inventory tool wear and exact-horse cleaning;
live acceptance is pending. Horse containers, tack, progression, aging/death,
training and abilities remain unloaded. Horses remain invincible pending lifecycle integration.
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
