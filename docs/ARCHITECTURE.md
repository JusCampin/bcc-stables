# BCC Horses architecture

> **Historical VORP architecture below.** It is not the active Feather contract.
> The release target is one `bcc-stables` resource consolidating abilities,
> trading and training as internal modules. Do not start their separate resources
> or load the legacy numeric-ID exports alongside the current runtime.
> See [current integration](FEATHER_INTEGRATION.md) and
> [the repository-wide audit](FEATHER_REFACTOR_AUDIT.md).

## Current Feather boundaries

Tack collection access is independent of owning/selecting a horse. An omitted
horseId reads only the character's Inventory collection and returns no equipped
horse loadout. The UI uses its existing local-only preview lifecycle for a labelled
Morgan Bay display horse when no owned selection exists; display identity never
crosses an ownership/mutation RPC. Equip remains owned-horse-only. Parked assembly
part removal can omit horseId but cannot affect tack assigned to an actual horse.
Purchases/resale/trades retain their provider/consent contracts. No starter grant.
325 Stables tests pass; no-horse recipient live preview/inspection pending.

Player tack trades use two explicit menu consent stages followed by durable
provider receipts. Independently attested private preview routes at the same
stable authorize proximity; equal preview bucket IDs are not required. Inventory
moves existing instances/parked anchors between collections atomically and keeps
purchase provenance unchanged. Stables coordinates free handovers or buyer debit,
custody transfer and seller payout through fs_tack_trades. Unknown replies replay;
only certain custody refusal refunds an exact captured payment. Accepted settlement
survives session/resource loss; unaccepted offers cannot cross menu sessions.
317 Stables/30 Inventory transaction tests and existing Lua regressions pass;
live player trade acceptance remains pending. See deployment/test gate in
FEATHER_INTEGRATION.md. Existing resale/storage acceptance is unchanged.

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
one-instance/one-slot uniqueness. Stables stores `fs_tack_orders` and `fs_tack_sales` for durable
quotes, purchase delivery and resale coordination; no duplicate tack inventory/loadout
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
implemented and reported working live on 2026-10-28. Single-piece and saddle assembly
buy-back also passed controlled live testing; player trading remains pending.
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
Resale quotes freeze original paid price, current item revision/condition, fitted
assembly membership, original currencies and payout accounts. Fitted tack is refused;
a parked saddle includes its horn/stirrups, while saddlecloths remain independent.
Inventory's durable exact-instance retirement receipt atomically verifies custody,
revisions and expected equipment (including empty attachment anchors), removes the
assembly and stores the historical result. It pays no money. Stables then requests
idempotent per-currency Economy Issue payouts. Interrupted/partial payment remains
owed and resumes through the existing bounded checkout worker; no replacement item
is granted as compensation. CheckIssue reuses Economy's supply authorization without
posting, verifying the player's wallet and system source before surrender. Admin's
service grant authenticates the Economy broker/Stables principal, and Economy admits
only configured issue reasons. Client players gain no direct issue grant. New RPCs
use the existing stable menu session, localized quote/confirmation and same-operation
retry. Item pricing never comes from the client. Component fitting now includes a
parent item/assignment comparison in its provider batch to fence concurrent changes.
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

All thirteen original tack categories share the existing PieceSlots policy and catalog. needsSaddle marks independent saddle-dependent horse assignments; requiresSaddle marks anchored horn/stirrup assembly parts. Equipment discovery now reads every non-assembly PieceOrder category. No new provider contracts or database tables.

## Saddlebag storage - ready for live acceptance

Storage belongs to the saddlebag unique Inventory instance, not a horse/character.
Uses normal Inventory container/UI/slot/weight transactions with defaults 50 slots,
250 weight in Config.saddlebags. No saddlebag item recreation or content copying
on equip, horse store/recall, or player transfer. NPC buy-back requires empty bags.
Player trade summaries and confirmations disclose occupied storage slots; the
recipient receives the same bag and all contents. Content count participates in
trade-term rechecks. Existing saddle styles 19/27/47/48 removed, per owner confirmation
that none are owned; the remaining original style labels are not renumbered.

Inventory adds scoped RegisterCollectionStorage/GetCollectionStorage/
OpenCollectionStorage exports. TrustedCharacterCollections stables.tack.v1 policy
must include storageItems={horse_saddlebag=true}. The provider lazily creates the
normal container and durably maps its ID in inventory_collection_storage. Core
current character, locked item custody and the current Stables bound-horse predicate
are rechecked for reads/mutations, including after the normal open-session shortcut.
The predicate checks current generation/session, exact equipped bag, bucket/proximity
and active call; opening additionally uses the existing network-owner occupancy
check. Thus no network-control assumption on the owner's client. Closing/storing,
relocating, ownership changes, provider stop or leaving range denies subsequent
operations; the Inventory UI closes within the existing new one-second check of
actively opened item containers. No all-bag/world polling and no new proof commands.
Saddlebag policy remains registered for trade/sale inspection when opening is disabled.
Ordinary carried/collection/storage APIs otherwise retain their established behavior.

Native PP_HORSE_ITEMS=28/PP_MODE_HIDE=1 is hidden for this bound horse; a localized
bag-only prompt uses INPUT_OPEN_SATCHEL_HORSE_MENU (B), within three metres on foot.
Native horse-weapons prompt types are untouched. Prompt sleeps 500ms away/in menus
and checks each frame only beside an eligible bag-equipped horse. Native prompt
suppression/coexistence still needs live confirmation.
Enum reference: https://github.com/Halen84/RDR3-Native-Flags-And-Enums/tree/main/ePromptType

Offline: 341 Stables tests; 37 Inventory transaction tests and complete Inventory
Lua regression/syntax suite pass. Tests cover lazy same-container registration,
capacity settings, stacked-row slot disclosure, current custody/live predicate,
resource/session changes, empty-only retirement with receipt rollback, content
persistence across ownership changes, source-only prompt requests, bag-only UI,
nonempty sale quote refusal and trade consent disclosure. Live RedM prompt behavior,
50-slot/250-weight limit display/enforcement and multiplayer filled-bag transfer
remain pending. Existing Inventory capacity tests pass, but no new live capacity
claim is made. No new version bump; no commit/push/PR publication in this task.

Live saddlebag storage acceptance (2026-10-29): user confirmed all requested checks working, including capacity, content persistence/store-recall and moving bags between horses, nonempty resale refusal, filled-bag trade disclosure/recipient access, and no-bag/horse-weapons behavior. No live concurrency fault injection claimed.

Native Cargo prompt update: custom UiPrompt registration/group/deletion removed. Bound horse PP_HORSE_ITEMS=28 hide flag now follows absence of its equipped saddlebag; existing native INPUT_OPEN_SATCHEL_HORSE_MENU input (normal and disabled-control path) opens the same source-only server RPC. Current horse/proximity/on-foot/NUI gates and server Inventory authorization unchanged. Native horse-weapons prompt types untouched. Fifteen horse-client and two cargo-input regression tests pass; native Cargo visibility/input change pending live confirmation. Copy client/horse/controller.lua and client/horse/saddlebags.lua only. Store active horse/close menus, restart bcc-stables; no refresh/config/SQL/provider restart.

## Native horse target-menu Flee - ready for live test (2026-10-29)

Shared Cargo event reader renamed client/horse/target_menu.lua; manifest replaces
client/horse/saddlebags.lua, avoiding a second frame/event loop. Completed
EVENT_PLAYER_PROMPT_TRIGGERED type 33 for the exact active horse dispatches
H.Store(currentGeneration). Works without saddlebags and respects existing
Config.stable.fleeEnabled. Native Flee visibility follows that flag independently
of Cargo. Cargo completion/animation unchanged. No new RPC or diagnostic command.

The existing store_current RPC accepts an optional exact generation fence;
empty normal command calls remain compatible. Client rejects a changed local
horse before releasing lead; server rejects stale generation before care/occupancy/
cleanup. Existing Store handles lead release, current simulator occupancy,
saved condition, movement/care cancellation, Inventory access revocation and
confirmed disappearance. No separate flee persistence or deletion path.

Offline: all 351 Stables tests pass, including Flee without bags, disabled/foreign
prompt refusal, one intent for duplicate same-frame events, exact generation
payload validation, stale-generation retention and normal confirmed Store.
Live native Flee/cleanup is pending. Expected player behavior: complete Flee in
the native target menu; horse stores/clears, then whistle recalls exactly one.
This update requests safe dismissal through Store; it adds no delayed/out-of-view
runaway despawn policy.

Required runtime copy:
C:/coding/bcc-feather-scripts/bcc-stables/fxmanifest.lua -> bcc-stables/fxmanifest.lua
C:/coding/bcc-feather-scripts/bcc-stables/client/horse/controller.lua -> bcc-stables/client/horse/controller.lua
C:/coding/bcc-feather-scripts/bcc-stables/client/horse/target_menu.lua -> bcc-stables/client/horse/target_menu.lua
C:/coding/bcc-feather-scripts/bcc-stables/server/horse/controller.lua -> bcc-stables/server/horse/controller.lua
Existing setting: Config.stable.fleeEnabled=true (server config/settings.lua);
no new configuration, SQL or Inventory/provider changes. Close Inventory, run
BccStablesHorseStore in player F8 and confirm disappearance; copy files, then
server console refresh followed by restart bcc-stables. Refresh is needed for
the renamed script/manifest entry. Do not separately load the old saddlebags reader.
Test whistle call, target horse, complete native Flee, confirm disappearance;
whistle to recall one horse, verify native Cargo hold/animation still works if
bags equipped. Finish with player F8 BccStablesHorseStore and disappearance.
Docs/tests do not need copying.

## Original run-away Flee restored - ready for live test (2026-10-29)

User confirmed target-menu Flee safely stored/removed the horse, then requested
original run-away behavior before disappearance. PP_HORSE_FLEE now sends a
flee=true generation-fenced intent through existing store_current (normal empty
Store commands remain immediate). Store checks the current simulator for occupancy
and captures condition first, then marks a ten-second flee reservation and issues
an existing movement ticket to the current network owner. Native execution uses
original TaskSmartFleePed 0x22B0D0E37CCB840D with distance 100.0, remaining duration
up to 10000ms, flags 6 and speed 3.0, plus SetPedKeepTask(true), from preserved
client/horse/return.lua. No new polling thread/RPC/table; uses existing movement
claim/cancel/replay fences and controller tick. Owner migration reissues with only
the original deadline's remaining time. Repeated Flee does not extend the deadline.

During fleeing: call/whistle replacement, care and bag access refuse; existing
bag views lose live access. At ten seconds or >200m separation (500ms checks),
Store rechecks occupancy, captures current cores and performs its original
confirmed cleanup. A new rider retains the horse and cancels dismissal; unknown
occupancy retries at one second without deleting it. Stop/logout still use existing
safe cleanup. Saved condition, ownership and bag contents remain provider-owned.

Offline: full 357 Stables tests pass, including exact native args, simulator
execution, no early deletion/new generation, ten-second/200m cleanup, mid-flight
owner migration with fixed deadline, disabled/repeated Flee, and rider retention.
Native run-away presentation still awaits live confirmation. Earlier immediate
Flee was live accepted; this entry supersedes its no-delay behavior only.

Required copy, all under C:/coding/bcc-feather-scripts/bcc-stables, to matching
server bcc-stables paths: client/horse/controller.lua, client/horse/target_menu.lua,
client/horse/whistle.lua, server/horse/controller.lua, server/horse/whistle.lua,
server/horse/saddlebags.lua, server/horse/feeding.lua. Player F8 BccStablesHorseStore,
confirm disappearance and close Inventory. Copy, then server restart bcc-stables.
No refresh/manifest/config/SQL/Inventory change for this update. Recall with
whistle, target Flee, verify run-away then disappearance, recall exactly one and
finish player F8 BccStablesHorseStore. Network-owner-2 presentation can be checked
with the existing two-player setup when available, without a new proof command.


## 2026-10-29 - Stable horse buy-back ready for live testing

Implemented behind Config.sales.enabled (default false), with the existing
Config.sales.purchasedHorsePriceMultiplier=0.70 and original whole-currency
ceil rounding. This applies to catalog purchased horses, not wild/tamed sales.
Stats & Details offers currency selection where the catalog permits it, review,
then exact horse/name/price confirmation. No new test/proof command is required.

Install database/feather_horse_sales.sql in the existing Feather database. It adds
fs_horse_sales without changing the schema-11 ledger. Confirmed admission uses the
character lock and changes stored -> selling, blocking call/tack/care reuse.
Inventory's atomic equipment batch parks the saddle with its fitted horn/stirrups
and clears all other horse assignments. Items, condition and saddlebag contents
remain with the character. No tack item is destroyed or paid for again.
Assets.RetireAsset ends canonical ownership; Economy.Issue pays once with the
persisted sale identity. Existing checkout recovery resumes confirmed intentions
while offline and even after sales are disabled. Lost replies retain the same
identities. A definite retirement revision conflict cancels and restores stored
availability, leaving tack safely in storage. Historical horse/registration/
purchase records remain; terminal local availability=sold is excluded from the
purchase capacity count, and only that horse's selection is cleared.

Uses existing scoped stables.horse_sale Issue reason and assets.asset.manage
service grants. No Inventory, Assets or Economy implementation/config change is
needed if current reviewed provider configuration is already deployed.
BccStablesStatus now includes horseSales enabled/recoveryAvailable/pending.
Pending retirement/payout remains reserved rather than creating a new sale.

Validation: 372 isolated automated tests pass, including sale replay, competing
quotes, expired/changed terms, current calls, asset CAS conflict, offline/restart
recovery, lost retirement/payout acknowledgements, final SQL rollback, freeing
horse capacity, retained tack assembly/bag item, and menu review/confirmation.
Actual provider/native multiplayer acceptance remains pending. Test using a
horse intended for sale; successful confirmation permanently ends its ownership.

Deploy required runtime files to the same relative paths in server resource
bcc-stables: fxmanifest.lua; client/core/locale.lua; client/ui/stable.lua;
server/core/boot.lua; server/horse/checkout.lua; server/horse/resale.lua;
server/tack/feather.lua; server/ui/stable.lua.
Merge Config.sales.enabled=true into the server config/settings.lua; retain the
existing multiplier. Execute database/feather_horse_sales.sql once, then server
console refresh, restart bcc-stables, BccStablesStatus. A refresh is required
because the manifest adds server/horse/resale.lua. No full server restart.
Live test: open stable -> My Horses -> Stats & Details -> Review Horse Sale;
verify price/currency and confirm. Check exactly one payout, horse absent,
tack/filled bags retained, saddle assembly reusable on another horse, and another
purchase allowed at the horse limit. Refresh/reopen must not pay again.
Documentation and tests are not deployment files.


## 2026-10-29 - Player horse trades with optional equipped package

Implemented, awaiting live acceptance. Config.sales.tradingEnabled defaults false.
Stats & Details -> Trade Horse uses the shared Trades tab (tack offers remain
available). One unchecked-by-default checkbox includes ALL equipped tack and bag
contents. Total entered price covers horse + included package; zero is a free
handover. Both players review horse/name, condition of each piece, character names,
price and terms, then explicitly consent. Each bag's actual named contents and
quantities appear in an initially collapsed accordion with its occupied-slot count.
Lists use one text element per bag, avoiding one component per stored unit.
Offers expire three minutes after creation. Equipment revisions/assignments and
bag contents fingerprint are checked again before acceptance; same-count content
changes invalidate an offer. Without the checkbox, all tack is released to the
seller's existing stable collection, retaining fitted saddle assemblies/contents.

A sorted character-admission transaction reserves the stored horse as trading and
reserves recipient horse capacity. Checkout counts accepted incoming horses too.
Existing tack trade payment/capture/refund helpers are shared, with separate exact
horse trade reason codes and receipt namespaces. Assets.TransferOwnership moves
the same horse/asset, using expected revision and expected seller; Inventory's
existing atomic collection transfer moves included original instances and their
assignments. Bags retain their existing attached container. No new item, horse,
container or copy of contents is granted during handover. Original purchase and
asset-registration provenance stay with the original purchaser; current canonical
Assets owner and Stables current-owner projection authorize calls/roster afterward.
Saved condition stays attached to the same horse. The seller's selected horse is
cleared only if it is this horse, and an empty recipient selection adopts it.

Confirmed settlement resumes through the existing checkout worker, including
offline. Unknown debit/ownership/item/payout replies retain the same receipt keys.
Definite ownership CAS refusal refunds the exact original debit before releasing
reservation. Once ownership transferred, an Inventory problem retains a reserved,
unusable horse and pending trade for recovery; it never refunds a possibly
committed handover or reports completion. If recipient collection fills during
settlement, freeing capacity permits recovery; payout waits for package transfer.
BccStablesStatus includes horseTrades pending/recovery status. No extra proof or
operator settlement commands were added.

Database: run database/feather_horse_trades.sql in the existing Feather database;
no schema-11 ledger modification. New server/horse/trade.lua is in fxmanifest.lua.
Provider changes: Inventory GetCollectionStorage supports snapshot=true, returning
contentsVersion=1, named grouped quantities and a deterministic 64-bit revision
fingerprint covering every content instance ID, item, slot, revision and metadata.
Only opt-in snapshots read full contents; ordinary access/count behavior is kept.
Economy config adds exact horse_trade_payment reversal scope and horse_trade_sale
Issue reason. Admin service policy adds assets.ownership.transfer for broker
feather-assets -> principal bcc-stables; no player permission/wildcard added.

Validation: 389 Stables tests pass, including 12 horse-trade settlement cases,
received-horse call/bind preserving original provenance, all-13-slot package,
checkbox false preservation, recipient review and collapsed contents. Inventory's
38 Python tests and full Lua suite pass, including same-count contents changes.
Economy full Lua suite passes. Admin 8 scoped asset-policy cases, payout scope
checks and 19 wallet tests pass. Live provider/native multiplayer acceptance is
pending; no claim of cross-provider ACID or MariaDB concurrency certification.
Version bumps, commits, pushes and PRs were not performed.

User previously confirmed the dedicated stable horse-sales page looks good.


2026-10-29: Optional saved bonding uses one fs_horse_bonding row per horse, the existing controller tick, simulator-scoped observations and atomic care settlement. No idle sampling RPC, separate permanent monitor, XP-from-client API or permanent stat/core writer. Owned SQL joins XP in its existing statement. Full policy/limits/deployment/live gate are in FEATHER_INTEGRATION.md; 409 tests pass and live bonding acceptance is pending.


2026-10-30: Permanent progression now extends the saved bonding service behind statRewardsEnabled. One nullable versioned JSON field pins starting ranks, interval, cap and applied level; XP/level/cursor share existing transactions. Initial bind initializes once, normal owned reads join saved progression, and current native simulators apply ranks while preserving observed depleted cores. The worker/RPC/manifest remain unchanged. 421 tests pass; live stat application/persistence is pending. See FEATHER_INTEGRATION.md for exact deployment and live gate.


2026-10-30 commit preparation: the working tree since d3583b6 includes unique-piece saddlebag storage/native Cargo access, original-native Flee followed by safe cleanup, stable horse buy-back, free/paid player horse trades with optional equipped tack and bag contents, saved bonding XP and capped permanent stat rewards. All 421 automated Stables checks passed. User confirmed baseline progression reward/display/restart persistence and final disappearance; see the integration log for separate unverified native/migration gates. README now reflects those live results. Include the new runtime, SQL and test files alongside tracked changes; no version bump, staging, commit or push was performed.
