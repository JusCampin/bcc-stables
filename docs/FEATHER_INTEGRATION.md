# Feather integration progress

## Stable tack storage accepted live - 2026-10-28

Maintainer reports storage all seems to be working. This accepts the requested
storage test flow at the reported level; no individual piece IDs, balances or
condition values were supplied. Do not invent additional measurements or claim
live fault/concurrency testing.282 Stables tests,17 provider transaction tests
and the Inventory Lua suite remain separate offline evidence. No repeat deployment
or basic storage test is needed. Stable shop resale and nearby-player trading are
next; neither is implemented yet.

## Stable tack storage ready for live test - 2026-10-28

The private character collection is now implemented. Existing eligible tack moves
out of carried Inventory on first tack access/recall, with original item IDs,
metadata/condition, equipment anchors and assemblies intact. Custody changes increment
row revisions once. Repeated access does not move/revise again. New paid tack orders
snapshot collectionKey and grant directly into storage; old order/grant payloads and
receipts remain compatible, adopting historical carried deliveries without regrant.
The same collection is available from every stable. Food/brushes remain carried.

Inventory owns one private container and mapping per caller/purpose/character. The
configured bcc-stables / stables.tack.v1 policy allows four established tack item names
and a stablesTackOrder marker, default 500 collection slots. Generic client open/read/
insert/remove/manage is refused; ordinary carried-item APIs remain unchanged. Scoped
collection reads and equipment rederive ownership. Migration uses locked rows,
existing instance-change holds and bounded UPDATE batches in one transaction; rollback
retains the originals. Stables adds no duplicate item/custody table or new worker.

282 Stables tests,17 Inventory provider transaction tests and the existing full
Inventory Lua suite pass;80 runtime Lua files parse. Coverage includes adoption,
unchanged condition/assemblies, unrelated/foreign-item exclusion, limits/rollback,
scoped item/equipment reads, restart, direct grants with full carried inventory,
old/new receipt replay and private ACL refusal. Native/CFX/MariaDB live acceptance
is pending. No shop resale or player trading yet.

Required runtime copies (source -> relative server resource destination):

- `C:/coding/bcc-feather-scripts/bcc-stables/server/tack/feather.lua` -> `bcc-stables/server/tack/feather.lua`
- `C:/coding/bcc-feather-scripts/bcc-stables/client/core/locale.lua` -> `bcc-stables/client/core/locale.lua`
- `C:/coding/bcc-feather-scripts/bcc-stables/client/ui/stable.lua` -> `bcc-stables/client/ui/stable.lua`
- `C:/coding/feather-scripts/feather-inventory/server/services/character_collections.lua` -> `feather-inventory/server/services/character_collections.lua`
- `C:/coding/feather-scripts/feather-inventory/server/services/api.lua` -> `feather-inventory/server/services/api.lua`
- `C:/coding/feather-scripts/feather-inventory/server/services/equipment.lua` -> `feather-inventory/server/services/equipment.lua`
- `C:/coding/feather-scripts/feather-inventory/server/services/grants_once.lua` -> `feather-inventory/server/services/grants_once.lua`
- `C:/coding/feather-scripts/feather-inventory/server/services/instances.lua` -> `feather-inventory/server/services/instances.lua`
- `C:/coding/feather-scripts/feather-inventory/server/services/inventory_access.lua` -> `feather-inventory/server/services/inventory_access.lua`

Required config merge: the TrustedCharacterCollections block from
C:/coding/feather-scripts/feather-inventory/config.lua into server
feather-inventory/config.lua, preserving all other settings and allowlists.
Keep existing tack, commerce, care and unique-grant settings. Inventory creates
inventory_character_collections during startup; no manual SQL or Stables migration.

Before replacing files, note an existing assembly's piece IDs/condition in Horse
Tack. Close menus; if a horse is active, player F8 BccStablesHorseStore and wait for
disappearance. After copying/config merge, server console in order:
refresh; restart feather-inventory; restart bcc-stables; BccStablesStatus.
Refresh is required for the newly added service under the existing script glob;
no manifest copy or full-server restart. Documentation/tests remain local.

Live gate: open Horse Tack, verify same pieces/condition/assembly and absence of
those tack pieces from carried Inventory (default I key; food/brushes remain).
Equip/take out/store and confirm disappearance. Reopen stable, verify persistence,
and buy one inexpensive tack piece: exactly one charge/item, delivered to My Tack
without a carried entry. Finish with no active horse. Sale/trade follows acceptance.

## Saddle assemblies accepted live - 2026-10-28

Maintainer confirms all requested assembly checks worked correctly: saddle moves
carry fitted horn/stirrups, replacement preserves the previous assembly, unequip/
re-equip preserves attachments, individual components detach/refit, native recall
restores equipment, and final Store removes the horse. No additional IDs, balances
or condition values were provided.277 offline Stables tests and four provider
transaction tests remain separate evidence for injected failures; those cases
were not independently accepted live. No repeat deployment or assembly test needed.
Dedicated character-owned stable tack storage is next; tack still occupies carried
Inventory space. Selling/trading follows the custody model.

## Saddle assemblies ready; stable storage next - 2026-10-27

Maintainer confirmed all four previous tack-category checks worked. New assembly
behavior is implemented and offline-tested, awaiting live acceptance: a saddle
carries fitted horn/stirrups through equip, move, replacement and unequip; old
assemblies remain together in the collection. Remove from Saddle releases each
individual component. Saddlecloths stay separate. Preview applies an assembly in
one component update, retaining saved restore state. Character ownership, item IDs,
metadata/condition and receipts are unchanged. No repurchase or new item is needed.

Inventory persists attachments as generic equipment slots keyed by parent instance;
parked saddle slots protect unequipped assemblies with existing locked move/destroy
guards. Its additive SetEquipmentBatchForCharacter uses one transaction, expected
source/destination IDs, ownership locks and instance-change guards. Existing single
slot APIs are unchanged. Per-horse legacy components convert per saddle under an
atomic parent/part comparison; lost replies are inspected on the next read.
277 Stables tests, four new real-Lua/SQLite provider tests and the existing complete
Inventory Lua suite pass. MariaDB/CFX/native concurrency remains a live gate.

This is the first test gate, not completed dedicated storage: items still occupy
carried Inventory. Stable-only character custody requires provider reads/grants/
capacity/equipment ownership to recognize dedicated containers (current character
item APIs explicitly require inventory.character_id). Implement this after assembly
acceptance; shop resale/player trading follow custody. Do not hide UI rows while
leaving items charged to carried capacity or introduce a duplicate ownership table.

Required runtime copies, to matching paths inside each server resource:

- `C:/coding/bcc-feather-scripts/bcc-stables/shared/tack.lua` -> `bcc-stables/shared/tack.lua`
- `C:/coding/bcc-feather-scripts/bcc-stables/server/tack/feather.lua` -> `bcc-stables/server/tack/feather.lua`
- `C:/coding/bcc-feather-scripts/bcc-stables/server/ui/stable.lua` -> `bcc-stables/server/ui/stable.lua`
- `C:/coding/bcc-feather-scripts/bcc-stables/client/core/locale.lua` -> `bcc-stables/client/core/locale.lua`
- `C:/coding/bcc-feather-scripts/bcc-stables/client/ui/preview.lua` -> `bcc-stables/client/ui/preview.lua`
- `C:/coding/bcc-feather-scripts/bcc-stables/client/ui/stable.lua` -> `bcc-stables/client/ui/stable.lua`
- `C:/coding/feather-scripts/feather-inventory/server/services/equipment.lua` -> `feather-inventory/server/services/equipment.lua`
- `C:/coding/feather-scripts/feather-inventory/server/services/api.lua` -> `feather-inventory/server/services/api.lua`
- `C:/coding/feather-scripts/feather-inventory/server/services/instances.lua` -> `feather-inventory/server/services/instances.lua`

Close stable menus; if a horse is active, player F8 BccStablesHorseStore and wait
for disappearance before replacing files. Server console in order:
restart feather-inventory; restart bcc-stables; BccStablesStatus.
No manifest/script-list change, refresh, SQL, config or full-server restart required.
Documentation/tests are optional local development files, not runtime copies.

Live gate: use existing saddled horses and pieces. Move a fitted saddle to another
owned horse; confirm horn/stirrups travel and the destination's previous assembly
remains intact. Unequip/re-equip that saddle and verify parts stay linked. Remove
one part through its category and refit it independently. Take out to verify native
restoration, then player F8 BccStablesHorseStore and confirm disappearance. No repeat
purchase is needed. Stop at this gate before dedicated storage implementation.

## Stable saddle default parts - 2026-10-27

Saddle presets no longer choose implicit horn/stirrup visuals: shared Tack.SaddleDefaults
selects Stirrup 1 and Saddle Horn 1 when no owned upgrade is assigned. Preview and
recall use the same map; upgrades override defaults and no saddle means no default
parts. These are included visuals, not new owned items.271 offline tests pass; native
refresh/recall appearance pending live test. Copy shared/tack.lua and
client/tack/controller.lua to matching bcc-stables server paths, store active horse
and await disappearance, then restart bcc-stables. No refresh/SQL/config required.

## Additional tack categories ready for live testing - 2026-10-27

Saddlecloths (66), stirrups (54) and saddle horns (67) reuse the saddle purchase,
receipt, equipment, preview and recall flow. Character ownership and item condition
are preserved when moving pieces. My Tack filters by category. Saddlecloths are
independent; custom horns/stirrups require a saddle. Unequip these dependents before
removing/moving their parent saddle. Saddle Default restores preset parts while
retaining the custom item. Existing saddle.v1 receipts and horse_<UUID> assignments
remain compatible; new orders snapshot category/item name as tack.v1.

270 offline tests pass, including all categories, independent moves, parent guards,
full-loadout restoration, idempotent seeds and old receipt compatibility. New-category
native rendering and paid live acceptance remain pending; saddles are already accepted.
No Inventory/Economy changes, new worker or migration-ledger change.

Required runtime copies (absolute local source -> relative server resource destination):

- `C:/coding/bcc-feather-scripts/bcc-stables/fxmanifest.lua` -> `bcc-stables/fxmanifest.lua`
- `C:/coding/bcc-feather-scripts/bcc-stables/config/tack/categories/saddlecloths.lua` -> `bcc-stables/config/tack/categories/saddlecloths.lua`
- `C:/coding/bcc-feather-scripts/bcc-stables/config/tack/categories/stirrups.lua` -> `bcc-stables/config/tack/categories/stirrups.lua`
- `C:/coding/bcc-feather-scripts/bcc-stables/config/tack/categories/saddle_horns.lua` -> `bcc-stables/config/tack/categories/saddle_horns.lua`
- `C:/coding/bcc-feather-scripts/bcc-stables/shared/tack.lua` -> `bcc-stables/shared/tack.lua`
- `C:/coding/bcc-feather-scripts/bcc-stables/server/tack/feather.lua` -> `bcc-stables/server/tack/feather.lua`
- `C:/coding/bcc-feather-scripts/bcc-stables/server/ui/stable.lua` -> `bcc-stables/server/ui/stable.lua`
- `C:/coding/bcc-feather-scripts/bcc-stables/client/core/locale.lua` -> `bcc-stables/client/core/locale.lua`
- `C:/coding/bcc-feather-scripts/bcc-stables/client/tack/controller.lua` -> `bcc-stables/client/tack/controller.lua`
- `C:/coding/bcc-feather-scripts/bcc-stables/client/ui/preview.lua` -> `bcc-stables/client/ui/preview.lua`
- `C:/coding/bcc-feather-scripts/bcc-stables/client/ui/stable.lua` -> `bcc-stables/client/ui/stable.lua`

Run `C:/coding/bcc-feather-scripts/bcc-stables/database/feather_tack.sql` in the
existing Feather database using your database client. It inserts only missing item
definitions and preserves existing pieces. Keep existing tack/commerce enablement and
Inventory unique-grant trust. No configuration changes or provider restart required.

Before deployment, close the stable menu and, only if a horse is active, run
`BccStablesHorseStore` in player F8 and wait for disappearance. After copies/SQL,
server console in order: `refresh`, `restart bcc-stables`, `BccStablesStatus`.
Refresh is required for the three newly loaded catalog scripts. No full server restart.
Documentation/tests remain local and are optional deployment files.

Live test: on a saddled horse buy/equip one piece from each new category, verify all
appear together, close/take out and verify recall. Store and wait for disappearance.
Move the same pieces to another owned saddled horse, checking no repurchase and
correct source/destination appearances. Check Saddle Default and parent-removal
refusal. Finish with `BccStablesHorseStore` and confirmed disappearance.

## Character-owned saddle flow accepted live - 2026-10-27

Maintainer confirms all steps in the requested saddle test worked correctly:
one purchase charge and one character-owned piece, explicit equip on horse A,
saved saddle visible on recall, Store, moving the same piece to owned horse B
without another charge, removal from A and restoration on B, and final Store
with disappearance. This accepts the controlled purchase/equip/move/recall/cleanup
flow. No detailed numeric item/horse IDs, balances or condition revisions were
provided; do not invent them. Offline259 tests remain the evidence for injected
lost replies, revision races and restart cases; those were not separately tested
live here. No repeated saddle test or deployment is needed. Other tack categories
and passive equipment wear remain future work.

## Character-owned saddle checkout/equipment ready - 2026-10-27

The Horse Tack tab now offers Browse Saddles and My Saddles. Catalog review ->
explicit quoted confirmation charges Economy once and delivers one character-owned
unique Inventory piece. Buying does not auto-equip. Equip/Unequip moves the same
piece between stored owned horses, preserves item identity/metadata/condition and
removes the prior assignment without another purchase. Cross-horse moves require
confirmation. Inventory generic equipment slots horse_<horse UUID> are authoritative;
there is no second Stables item or loadout table. Normal preview/recall reads and
validates equipment and restores components. Preview experiments restore saved
gear on leaving. Existing native association/riding/care is retained.

One optional fs_tack_orders table stores immutable saddle quote/payment/delivery
terms. Existing Economy Transfer and Inventory GrantCharacterUniqueItemOnce receipts
recover lost replies without another debit/item. Recovery uses the existing bounded
checkout worker, rotating stalled orders and remaining idle when none are pending.
Existing base schema11 ledger is unchanged. Equipment uses Inventory's data-only
MutateItem read/revision fence, then its atomic generic equipment API while holding
Stables' character/call admission lock. Provider transaction handles never cross
CFX, and no Inventory/Economy SQL is read or written directly. Synchronous guards
block item moves/destruction while equipped, and block pending metadata changes;
move/destroy use Inventory's locked equipment snapshots even after resource restart.
Uncertain assignment outcomes are read back. A resource stop unregisters guards;
recall revalidates actual ownership, so stale/foreign/deleted pieces never produce
a native copy. Stopping Inventory also stops physical calls and closes stable menus; restart
Stables after restarting Inventory to rebind its API/guards.

Startup checks Inventory readiness/capability, configured condition key/range,
active unique saddle definition and opt-in grant authorization before admitting
checkout. The authorization check submits an invalid empty payload, which the
verified provider rejects before receipt SQL; no item/operation is created.
Known inventory capacity failure refuses before payment. A capacity race after
payment leaves the original paid order pending until delivery is possible; no
invented refund or replacement operation is created. Status includes bounded tack
recovery summaries. Tack condition starts at Inventory's configured maximum;
passive equipment wear/trading between characters are not added in this slice.

259 offline tests pass: purchase replay and payment/delivery lost replies, reload
recovery, source/destination/ownership/revision/movement guards, capacity refusal,
free policy, character collection retention, explicit cross-horse moves, saved
preview restoration and physical-bind application. Provider behavior is doubled
and SQL admission/order tests use SQLite: native/CFX/MariaDB paid-saddle acceptance
remains pending. No new proof command or Inventory source change is required.

Required runtime copies (same relative resource paths):
- `C:\coding\bcc-feather-scripts\bcc-stables\fxmanifest.lua` -> `bcc-stables/fxmanifest.lua`
- `C:\coding\bcc-feather-scripts\bcc-stables\client\core\locale.lua` -> `bcc-stables/client/core/locale.lua`
- `C:\coding\bcc-feather-scripts\bcc-stables\client\horse\controller.lua` -> `bcc-stables/client/horse/controller.lua`
- `C:\coding\bcc-feather-scripts\bcc-stables\client\ui\preview.lua` -> `bcc-stables/client/ui/preview.lua`
- `C:\coding\bcc-feather-scripts\bcc-stables\client\ui\stable.lua` -> `bcc-stables/client/ui/stable.lua`
- `C:\coding\bcc-feather-scripts\bcc-stables\server\core\boot.lua` -> `bcc-stables/server/core/boot.lua`
- `C:\coding\bcc-feather-scripts\bcc-stables\server\horse\controller.lua` -> `bcc-stables/server/horse/controller.lua`
- `C:\coding\bcc-feather-scripts\bcc-stables\server\horse\checkout.lua` -> `bcc-stables/server/horse/checkout.lua`
- `C:\coding\bcc-feather-scripts\bcc-stables\server\ui\stable.lua` -> `bcc-stables/server/ui/stable.lua`
- `C:\coding\bcc-feather-scripts\bcc-stables\server\tack\feather.lua` -> `bcc-stables/server/tack/feather.lua`

Required configuration: merge Config.tack.enabled=true from
C:/coding/bcc-feather-scripts/bcc-stables/config/settings.lua into the server's
bcc-stables/config/settings.lua; keep commerce.purchasesEnabled=true for paid
checkout and preserve current care/other settings. In feather-inventory/config.lua
ensure Config.TrustedUniqueGrantCallers['bcc-stables']=true after its existing
initializer (provider source reference C:/coding/feather-scripts/feather-inventory/config.lua).
Do not overwrite that config wholesale. If this already matches, no Inventory
restart is needed. Economy's existing trusted Stables transaction/account access
and stables.tack_purchase/stables_order scope are reused; no Economy change.

Database client: run C:/coding/bcc-feather-scripts/bcc-stables/database/feather_tack.sql
against the existing Feather database before enabling tack. This creates the one
optional order table and inserts a missing unique horse_saddle definition without
altering existing definitions. It does not run VORP SQL or automatically change
schema11 evidence. SQL is an installation input; docs/tests stay local.

Commands, in order: close the current stable menu; if an active horse exists,
player F8 BccStablesHorseStore and wait for disappearance. After copies/SQL/config,
server console stop bcc-stables, then restart feather-inventory ONLY if its config
changed; then refresh (new server manifest entry), start bcc-stables, BccStablesStatus. Expect ready,
features.tack=true and tack.ready=true. No full server restart or UI build.

First live gate: select horse A in My Horses, Horse Tack -> Browse Saddles ->
choose one -> review/confirm purchase. Verify one charge and one piece in My
Saddles. Equip, close and take out A through the normal menu; verify appearance.
Store A, reopen, select owned horse B, choose the SAME piece in My Saddles and
confirm its move (no second purchase/charge). Verify A no longer wears it and B
recalls wearing it. Finish by storing B and confirming disappearance. Stop here
for this test; other tack categories and passive durability are later work.

## Tack ownership requirement clarified - 2026-10-27

Maintainer explicitly confirms characters own tack independently of horses.
Purchased pieces must have stable identity/condition; horse loadouts reference
them, with at most one equipped horse per piece. Moving between owned horses
changes assignment without repurchasing; unequipping preserves character
ownership. Preserve the original character-owned design when adapting checkout
and loadout persistence to Feather. Do not implement horse-bound cosmetic unlocks.
This is a planning clarification; no runtime/deployment/test change.

## Saddle cleanup live-confirmed - 2026-10-27

Maintainer reports saddles are working after the preset horn/stirrup cleanup and
Horse Tack top-tab update. Saddle preview/cleanup accepted at this reported scope;
no separate detailed tab/locale/empty-selection result was supplied. Offline239
tests remain the automated coverage. No repeat saddle-preview test or deployment
is needed. Tack purchases, character-owned equipment and saved loadouts remain
next implementation work; preview choices do not persist or charge currency.

## Saddle attachments cleanup and Tack tab - 2026-10-27

Maintainer confirmed the previous missing helpers came from an omitted manifest
upload. Live saddle browsing now renders, but No Saddle left preset horn/stirrups.
The preserved appearance helper now removes both dependent categories whenever a
saddle is removed/replaced, including presets whose parts never had individual
loadout entries. Full loadout application still reapplies explicitly chosen parts.
Other component categories are preserved. Native cleanup retest remains pending.

Horse Tack is now the third top tab, for the selected stored horse, with fresh
owned-read validation. Removed the Details button. No selection produces guidance
to select a horse in My Horses; expired selection/active horse is refused. Tabs
share the same route and preview and are bounded to three anchors/one active page.
Back returns to My Horses; leaving Tack clears temporary saddle components.
239 tests pass, including dependency cleanup, explicit-part reapplication, top-tab
navigation, empty selection and preserved preview identity.

Copy runtime files C:\coding\bcc-feather-scripts\bcc-stables\client\tack\controller.lua,
C:\coding\bcc-feather-scripts\bcc-stables\client\ui\stable.lua and
C:\coding\bcc-feather-scripts\bcc-stables\client\core\locale.lua to server resource
paths bcc-stables/client/tack/controller.lua, bcc-stables/client/ui/stable.lua and
bcc-stables/client/core/locale.lua respectively. Server console: restart bcc-stables.
No manifest/new-script change, refresh, SQL, config/provider change or full restart.
Docs/tests stay local. Open stable, select an owned horse in My Horses, then use
the Horse Tack top tab. Cycle saddles -> No Saddle and verify saddle/horn/stirrups
are all gone; repeat while switching tabs and confirm the same clean preview.

## Tack helper loading failure contained - 2026-10-27

Live client reported both Tack and HorseAppearance globals missing. Root cause in
the deployed resource is not established; the local manifest order is correct.
Added an executable manifest-order regression proving the catalog179 and appearance
helper initialize before preview. Ordinary preview/cleanup no longer depend on
optional tack work when no saddle is selected; missing helpers refuse the tack
page with a localized loading message while preserving Details/close. 236 tests
pass, including missing-helper preview cleanup and menu refusal. Native saddle
rendering remains pending. Recopy the eight runtime files listed below to matching
server paths, then server console: stop bcc-stables; refresh; start bcc-stables.
Check startup for any script-load errors before opening the normal stable menu.
No SQL/config/provider changes or full server restart required.

## Saddle catalog preview ready for live test - 2026-10-27

Audited the preserved catalog, component helper, tack session, service and
repository alongside current Feather owned reads, checkout and menu lifecycle.
The legacy numeric-character tack tables/callback/payment/refund flow cannot be
loaded into the UUID/Assets/receipt runtime. First production UI slice reuses the
179 original saddles, stable catalog IDs, prices, component apply/remove natives
and current menu/preview. Owned stored-horse Details -> Horse Tack offers arrows,
No Saddle, position counter, catalog price and existing smooth rotation. No saddle
purchase, ownership grant or saved equipment is claimed. No new test command.

The exact preview identity/model is required; duplicate selection avoids native
work. Back/tab navigation removes the temporary saddle, close/stop deletes the
preview and resets helper tracking, and bounded metaped follow-ups reapply the
chosen saddle. Language changes retain selection through Core/settings, with
English fallback. No server route, idle loop, SQL/config enablement or provider
change. Existing schema11 remains untouched. Offline tests cover stale identity,
same preview reuse, removal, delayed variation, navigation and locale behavior;
actual saddle appearance remains a live gate.

Runtime source root: C:\coding\bcc-feather-scripts\bcc-stables. Copy these exact
paths to the same relative paths in the server bcc-stables resource:
fxmanifest.lua; config/tack/catalog.lua; config/tack/categories/saddles.lua;
shared/tack.lua; client/tack/controller.lua; client/core/locale.lua;
client/ui/preview.lua; client/ui/stable.lua. Preserve any existing custom tack
currency/catalog prices. Documentation/tests stay local. Server console: refresh,
then restart bcc-stables (manifest script list changed; no full server restart).
Open the stable through its normal interaction, expand an owned horse, choose
Stats & Details -> Horse Tack. Cycle several saddles, rotate, choose No Saddle,
then Back and switch to Browse Horses to verify no saddle carries over. Close
normally and verify input/radar return and no preview remains. No F8/SQL command
or test purchase is required for this slice. Stop here for native presentation
acceptance before adapting tack purchases and persistent equipment.

## Final-use brushing accepted live - 2026-10-27

A separate brush granted with condition1 reported worn out after completed
Inventory-use brushing. Saved health remained100; stamina83 ->93, revision7 ->8.
Maintainer confirmed physical horse disappearance after Store. This accepts the
live final-use result and saved benefit; concurrent/lost-reply/restart wear cases
remain covered by automated simulations rather than this manual run. The report
does not separately confirm the original98-condition brush or inspect item removal.
No runtime change or repeat brushing cycle is required.

## Mounted brushing accepted live - 2026-10-27

Maintainer confirmed brushing worked while mounted on their own horse. Logs show
brush condition99 ->98/100 and saved health100/stamina73 ->83 revision7. The call
restored the prior100/73 revision6 first. This accepts mounted native presentation
and one condition-point wear with the configured +10 capped core benefit. Maintainer subsequently confirmed physical disappearance after the final
Store, completing the mounted-brushing cycle. No new runtime/config/deployment or repeat mounted
brush test is needed. Offline suite remains227 tests.


## Brushing live acceptance and mounted-owner permission - 2026-10-27

Maintainer reports brushing worked: walking away cancelled, mounted attempt was
refused under the previous rule, completed dismounted brush reported99/100 and
saved health100/stamina73 revision6 (from100/63 revision5). Store was requested;
final disappearance has not yet been explicitly confirmed for this cycle.
Maintainer requested that brushing also be allowed from their own saddle.

Both server care observations now use the existing owner-mounted permission for
brush as well as food. Client animation eligibility matches that rule. Foreign
riders, another mount, leading and scripted follow/approach remain refused.
Store still requires dismounting. The brush occupancy message no longer tells
the owner to dismount. Original native brush animation is unchanged; its mounted
presentation needs live confirmation. 227 offline tests pass, including both
server care checks allowing owner-mounted use and mounted brush initiation.
No Inventory, configuration, SQL, manifest or receipt changes.

Required runtime sources -> destinations relative to server resources:
- C:\coding\bcc-feather-scripts\bcc-stables\server\horse\feeding.lua -> bcc-stables/server/horse/feeding.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\horse\feeding.lua -> bcc-stables/client/horse/feeding.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\core\locale.lua -> bcc-stables/client/core/locale.lua
Docs/tests stay local. No refresh needed. Confirm the previously stored horse
has disappeared; if still out, dismount and player F8 BccStablesHorseStore first.
After copying, server console restart bcc-stables. Player F8 BccStablesHorseCall;
mount your own horse, Inventory I -> right-click brush -> Use; stay near for five
seconds. Verify mounted animation, one condition point spent and capped +10/+10
saved cores. Dismount; player F8 BccStablesHorseStore; confirm disappearance.
No need to repeat the already-accepted walk-away cancellation check.


## Inventory condition convention correction - 2026-10-27

Maintainer correctly identified existing Inventory condition support. The new
wear receipt wrapper is needed for durable once-only wear/cancellation/recovery,
not a replacement condition system. Corrected the initially separate durability
metadata field: wear now uses Config.Condition.Key (default condition), respects
Config.Condition.Max and preserves other metadata. The advertised ready contract
includes conditionKey/conditionMaximum so Stables validates against the same
provider convention. Existing GetCondition/SetCondition/AdjustCondition APIs are
unchanged. No separate condition table or durability metadata system is added.
227 Stables tests and full Inventory suite pass, now20 receipt cases including a
custom condition-key regression. Wear/native/live brush acceptance remains pending.
Runtime correction affects the same two files already in the brush handoff:
C:\coding\feather-scripts\feather-inventory\server\services\consumption_once.lua
and C:\coding\bcc-feather-scripts\bcc-stables\server\horse\feeding.lua. No
additional deployment request is made by this explanatory checkpoint.


## Inventory brushing and Feather item definitions - 2026-10-27, ready for test

Brushing reuses the feeding module's exact-item Inventory callback, one-character
queue, current simulator eligibility, core depletion checkpoint, five-second
animation/cancellation, existing schema-11 reservation/effect/recovery and saved
condition delivery. No new Stables runtime module, frame worker or proof command.
Original Interaction_Brush/p_brushHorse02x is used. Brushing requires dismounting;
feeding still allows the owner in the saddle. A committed brush delivery cleans
dirt, damage decals and blood only on the exact controlled horse. Full cores
still permit cleaning, with the configured wear. Defaults: +10/+10 core points,
maximum brush durability100, cost1; these reuse Config.items.brush durability
settings. Config.brushing.enabled defaults false. No XP/progression added.

Inventory's existing consumption receipt service now also offers durable tool
wear (GetConsumptionContract.durableWear1; WearCharacterItemOnce,
InspectCharacterItemWear, CancelCharacterItemWear). It uses the SAME receipt
schema and ordered receipt/item transaction, with separate wear fingerprints and
immutable wear/max terms. Existing consumption requests/results are unchanged.
A tool uses Inventory's configured condition key (default metadata.condition),
defaulting to the configured maximum when absent,
preserves unrelated metadata, and wears once. Final use atomically removes the
broken instance and commits a used receipt. Cancellation-first wears nothing;
consumed/used outcomes win over later cancellation. Stables records the validated
receipt with its terminal local effect for replayed durability/break reporting.
Provider policy remains per-caller/purpose/item default deny. No new provider
migration, service file or manifest entry is needed. Existing stack/unique ordinary
tools are supported, but differing durability needs independent slots; fresh
horsebrush definitions have max_stack_size1. Split old multi-brush stacks before
use rather than mutating every brush or silently migrating owned inventory.

Added database/feather_items.sql for the Feather categories/items schema. It
idempotently inserts missing horsebrush, haycube/carrot/apple, oil_lantern,
consumable_horse_reviver and diamond definitions with established names. Existing
definitions/owned instances are preserved. Lantern/reviver/diamond are seeded
unusable because their gameplay is still unloaded. This does not activate them.
Never run the VORP database/schema.sql on Feather; the new file has no horse DDL.

227 Stables offline tests pass; Inventory's full Lua suite passes (79 runtime
files parse,19 receipt cases including8 wear cases). Coverage includes wear once,
metadata preservation, break/reload replay, cancellation, lost replies, rollback,
per-policy binding, guard/exhaustion refusal, zero-wear policy, Stables recovery,
full-core cleaning, mounted refusal and exact native cleaning. SQL seed insert/
idempotency/non-overwrite semantics pass on SQLite; actual MariaDB seed and wear
metadata/removal acceptance are pending. No stage/commit/push performed.

Required runtime sources -> destinations relative to server resources:
- C:\coding\feather-scripts\feather-inventory\server\services\consumption_once.lua -> feather-inventory/server/services/consumption_once.lua
- C:\coding\feather-scripts\feather-inventory\server\services\api.lua -> feather-inventory/server/services/api.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\horse\controller.lua -> bcc-stables/client/horse/controller.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\horse\feeding.lua -> bcc-stables/client/horse/feeding.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\core\locale.lua -> bcc-stables/client/core/locale.lua
- C:\coding\bcc-feather-scripts\bcc-stables\server\horse\controller.lua -> bcc-stables/server/horse/controller.lua
- C:\coding\bcc-feather-scripts\bcc-stables\server\horse\feeding.lua -> bcc-stables/server/horse/feeding.lua

Merge Config.brushing from local C:\coding\bcc-feather-scripts\bcc-stables\config\settings.lua
into deployed bcc-stables/config/settings.lua, set enabled=true and keep health10/
stamina10. Preserve existing feeding/commerce settings. Existing Config.items.brush
keeps name horsebrush, durabilityEnabled=true, maximumDurability100 and wear1.
In deployed feather-inventory/config.lua, preserve the feeding purpose and add:

```lua
Config.TrustedConsumptionCallers['bcc-stables']['stables.brush.v1'] = { horsebrush = true }
```

Run C:\coding\bcc-feather-scripts\bcc-stables\database\feather_items.sql in the SQL
client connected to the Feather server database, once. Read the result set to
verify definitions; it does not overwrite pre-existing settings. It can be opened
locally in the database client; copying it to the resource is not required. No
manual receipt-table migration, refresh, frontend build or full server restart.
Docs/tests remain local. Existing manifests already load all changed runtime files.

Before copying/restarting, if horse out: dismount; player F8 BccStablesHorseStore;
confirm disappearance. Server console stop bcc-stables. After copying/settings/SQL,
server console in order: restart feather-inventory; ensure bcc-stables;
BccStablesStatus. Expected ready/care=true. Inventory restart loads its API/policy.

Test with ONE horsebrush in its own Inventory slot. If needed and existing DevMode
and staff ACE already permit it, player F8 AddItems horsebrush 1. Otherwise obtain
one through the existing authorized admin grant UI; do not change ACE/DevMode just
for this test. Player F8 BccStablesHorseCall. Dismount, stop leading/following,
stand beside it, open Inventory I -> right-click brush -> Use. First move away
before five seconds: cancelled, brush durability unchanged. Repeat while staying
beside it: animation/clean coat, one wear (new brush99/100), +10/+10 saved cores
capped100. Cores already full still permit cleaning/wear. Dismount before storing;
F8 BccStablesHorseStore and confirm disappearance; BccStablesHorseCall to verify
saved condition. Finish BccStablesHorseStore and confirm disappearance. Native
brush presentation, real-item metadata wear and cancellation remain live gates.


## Live feeding and depletion acceptance - 2026-10-27

Maintainer confirmed walking away cancels feeding with no inventory loss. Live
logs show successful feeding at health100/stamina43 revision4; normal Store and
recall restored exactly100/43 revision4. Another feed raised stamina43 ->63
revision5 (health stayed100), demonstrating the configured capped +20 benefit
rather than the former stale-full refusal. Maintainer subsequently confirmed physical disappearance after the final Store,
completing cleanup acceptance for this feeding/cancellation/store-recall cycle.
The provided evidence does not explicitly identify mounted feeding presentation
or a non-owner network simulator for these successful interactions; those gates
remain separate. No additional runtime/configuration or repeated successful test
is required to record these results. Offline suite remains217 tests from the
preceding implementation checkpoint.


## Native core depletion checkpoints - 2026-10-27, ready for retest

Live feeding reported 90/80 -> 100/100 revision2 and refused further feeding as
full. After riding until stamina appeared depleted, food still refused and Store/
recall restored 100/100. Saved condition had only changed through feeding; the
refactor lacked native-depletion capture. This is a missing state integration,
not a new food policy or an Inventory receipt failure. Mounted food presentation
and exact quantity/cancellation still require their separate live confirmation.

Existing current-simulator occupancy replies now include bounded native health/
stamina core readings and the last applied condition revision. Care captures
before calculating its immutable food terms; normal Store saves before cleanup
and retains the active horse if saving is unconfirmed. The same exact server
observer/generation/current simulator/current session checks bind both readings.
One short Stables transaction locks its stable/projection/condition rows and saves
only decreases, with a condition revision increment only when values change.
Native claims cannot grant free increases; committed care remains the increase
path. Ownership is re-read through Assets outside the transaction. Uninitialized
horses are not silently initialized. Pending care terms are preserved until their
receipt resolves, rather than overwriting the reserved before/after condition.

Client sets a replicated applied-core revision after spawn restoration and after
native care application. If a recorded benefit has not reached the simulator,
checkpointing reissues its saved condition and asks for retry instead of treating
old native values as depletion. The latest care effect revision also protects
benefits recovered after lost replies. Existing schema/indexes/receipt contract
are unchanged. This adds action-boundary checkpoints, not an idle SQL/native loop
or periodic crash recovery: abrupt termination still restores the last durable
condition. Attribute-core values are distinct from the outer attribute bars.

217 offline tests pass, including saved-full/native-stamina5 feeding to25,
checkpoint/readback of stamina7, no native-only increases, simulator-change
refusal, recovered-benefit protection, native reply fields, and failed Store
checkpoint retaining the live horse. Live depletion/feeding/recall retest pending.

Required runtime sources -> destinations relative to server resources:
- C:\coding\bcc-feather-scripts\bcc-stables\client\horse\controller.lua -> bcc-stables/client/horse/controller.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\horse\feeding.lua -> bcc-stables/client/horse/feeding.lua
- C:\coding\bcc-feather-scripts\bcc-stables\server\horse\controller.lua -> bcc-stables/server/horse/controller.lua
- C:\coding\bcc-feather-scripts\bcc-stables\server\horse\feeding.lua -> bcc-stables/server/horse/feeding.lua
No manifest/config/SQL/Inventory change or refresh required. Docs/tests stay local.
Before copying/restarting: dismount; player F8 BccStablesHorseStore; confirm gone.
After copying, server console restart bcc-stables. Player F8 BccStablesHorseCall;
ride until the stamina core drops, dismount; BccStablesHorseStore, confirm gone;
BccStablesHorseCall. The restored saved stamina should remain low. Mount your
horse and use an apple from Inventory (I -> right-click apple -> Use), stay nearby
for five seconds. Expect one apple consumed and +20 stamina capped at100 rather
than already-full rejection. Dismount; BccStablesHorseStore; confirm gone. No need
to initialize or reset the existing 100/100 record; the native observation fixes it.


## Mounted feeding and explicit care observations - 2026-10-27

Inventory callback deployment/startup accepted ready/care=true, and use reached
Stables, but generic care_ineligible refused even beside the active horse.
Maintainer clarified that feeding must also work from their own saddle.
The new eligibility code no longer assumes server GetEntityHealth is a reliable
RedM life observation; it uses current-simulator life facts as the earlier care
implementation did. This was a potential false refusal, not a proven diagnosis
from the prior generic message. Server observer/session/route/distance and fresh
canonical ownership/reservation checks remain in place.

The existing simulator occupancy ticket now carries a care flag and the owner's
server-captured ped network ID. It returns ownerAlive/horseAlive and care occupancy
under the same exact generation/observer/control checks. The owner as rider is
allowed for care; another rider, leading or the owner riding a different horse is
refused. Life fields are mandatory on care replies; missing/stale/wrong-simulator
facts fail closed. Store uses the original all-riders-blocked policy unchanged.
Client animation eligibility mirrors the owner's saddle permission. Server life
checks are not repeated through unreliable GetEntityHealth during the animation;
client monitoring and the final current-simulator observation protect that phase.

Refusals now distinguish not-ready horse, cancelled interaction, scripted
follow/approach movement, distance (with observed metres), unavailable simulator
observation, life state and other-rider/leading occupancy. Existing per-recipient
localization applies. No new diagnostic command, route, table or provider code.
211 offline tests pass including owner-mounted animation initiation, distinct
Store/care occupancy, foreign riders, simulator migration, mandatory life reports
and rejection details. Native mounted animation/live feeding remain pending;
passing simulations do not certify that presentation.

Required runtime source -> destination relative to server resources:
- C:\coding\bcc-feather-scripts\bcc-stables\client\horse\controller.lua -> bcc-stables/client/horse/controller.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\horse\feeding.lua -> bcc-stables/client/horse/feeding.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\core\locale.lua -> bcc-stables/client/core/locale.lua
- C:\coding\bcc-feather-scripts\bcc-stables\server\horse\controller.lua -> bcc-stables/server/horse/controller.lua
- C:\coding\bcc-feather-scripts\bcc-stables\server\horse\feeding.lua -> bcc-stables/server/horse/feeding.lua

No manifest/config/SQL/Inventory changes or refresh required; docs/tests stay
local. Dismount, player F8 BccStablesHorseStore, confirm disappearance before
copying/restarting. After copying, server console restart bcc-stables. Player F8
BccStablesHorseCall; use the original Morgan with saved90/80, stand nearby and
use an apple from Inventory (I -> right-click apple -> Use). If refused, send the
new exact message. If it begins, move away during five seconds and verify no food
used. Then mount your own horse, open Inventory and Use the apple; verify the
mounted feeding presentation completes, one apple consumed and saved condition
improves. Store still requires dismount: dismount, F8 BccStablesHorseStore; confirm
disappearance; BccStablesHorseCall to check saved values. Finish by storing and
confirm disappearance. Do not repeat a successful feed if saved cores are full.


## Inventory-driven feeding - 2026-10-27, ready for live test

Supersedes the Feed-prompt approach and all prompt inspection/testing below.
Maintainer chose item use to preserve lock-on prompt space and support distinct
food effects. The custom Feed prompt, target-group tracking, inspection command,
client food selection and idle/frame worker have been removed. Feeding starts
only through Inventory's server-side RegisterUsableItem callback. Existing horse
prompts are unchanged; the engine Feed entry is hidden, as in original Horses.
Brushing/durability is the next care step and remains unimplemented in this runtime.

Config.feeding.foods is the authority for each food's health/stamina benefit.
Defaults remain 20/20 for all three established keys; server owners can vary each
entry without editing Inventory definitions. Config.items.food remains legacy
configuration and is not a second registry in this feeding implementation.
Committed pending benefits retain the saved before/after amounts across changes.
Existing receipt, slot, target and condition tables are unchanged (schema 11).

The Inventory callback captures the current session and exact joined item id,
definition id, name and row revision. It closes Inventory and enqueues one worker
per character, then RETURNS so Inventory releases its active-use removal guard.
After one scheduler tick, the worker revalidates the captured session and fresh
GetItemForCharacter instance; it never searches for or substitutes another unit.
The usual five-second acknowledgement/cancellation/receipt/recovery path follows.
Inventory is allowed up to two seconds to release NUI focus before animation.
No asynchronous presentation callback or SQL lock spans the Inventory callback.
No Inventory transaction, active-use-token bypass or provider modification added.
Registration conflicts fail startup rather than replace another resource's use.
New feed admissions are not exposed through the client RPC; only exact existing
operation acknowledgement/cancellation/recovery is accepted. Pending work still
recovers while new feeding is disabled. New server results contain codes and are
translated per recipient on the client, using settings/Core and English fallback;
optional Feather Notify shows them on-screen, with F8 logging retained.

204 offline tests pass (26 feeding tests), including exact-instance callback
capture, guard-release deferral, immediate duplicate-use fencing, revision change
refusal, session change/source reuse, custom food effects and immutable recovery,
plus cancellation/lost replies/SQL rollback/native identity protections. These
are SQL/provider/native simulations, not live CFX/MariaDB item-use acceptance.
No commit, staging, migration or Inventory runtime/config change was performed.

Required runtime sources -> destinations relative to server resources:
- C:\coding\bcc-feather-scripts\bcc-stables\client\horse\feeding.lua -> bcc-stables/client/horse/feeding.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\horse\controller.lua -> bcc-stables/client/horse/controller.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\core\locale.lua -> bcc-stables/client/core/locale.lua
- C:\coding\bcc-feather-scripts\bcc-stables\server\horse\feeding.lua -> bcc-stables/server/horse/feeding.lua
- C:\coding\bcc-feather-scripts\bcc-stables\server\core\boot.lua -> bcc-stables/server/core/boot.lua

Configuration source C:\coding\bcc-feather-scripts\bcc-stables\config\settings.lua
-> merge only the feeding block into bcc-stables/config/settings.lua, preserving
server commerce and other settings; set enabled=true:

```lua
feeding = {
    enabled = true,
    foods = {
        consumable_haycube = { health = 20, stamina = 20 },
        consumable_carrots = { health = 20, stamina = 20 },
        consumable_apple = { health = 20, stamina = 20 },
    },
},
```

Keep the previously enabled feather-inventory/config.lua
Config.TrustedConsumptionCallers['bcc-stables']['stables.care.v1'] allowlist for
these three foods. Do not overwrite that configuration or remove policy for
unresolved receipts. It needs no edit/restart for this update. Existing Stables
manifest already loads these feeding files and Inventory dependency: no refresh
or SQL/full server restart required. Docs/tests stay local.

Before copying/restarting with a horse out, player F8: BccStablesHorseStore;
confirm disappearance. After copying/merging settings, server console in order:

```text
restart bcc-stables
BccStablesStatus
```

Expect ready/care=true. Use an initialized horse with saved condition below 100
(the original Morgan previously had 90/80). If all saved cores are full, report
that rather than resetting data. Player F8 BccStablesHorseCall; dismount and stop
leading/following beside the horse. Press I (Inventory's current default; use the
configured inventory key if customized), right-click an apple and choose Use.
Inventory should close and the feeding animation begin. First move away during
five seconds: no food consumed, saved cores unchanged. Return and use the apple
again, stay beside it: one exact apple consumed, saved effects applied once and
notification shown. Player F8 BccStablesHorseStore; confirm disappearance; then
BccStablesHorseCall and verify the saved condition line. Finish with
BccStablesHorseStore and confirm disappearance. No Feed prompt or feed command is
expected. Brush use is intentionally not part of this feeding acceptance test.


## Feed target observation - 2026-10-27, runtime evidence needed

Feed is still missing with no client errors. Live status confirms a matching
active physical call, ownerSource/networkOwner=2, care=true. The group changes
alone did not establish the cause. Client now uses GetPlayerTargetEntity's typed
BOOL/entity output (also used in the original horse info card) and requires that
entity to match this horse. Existing BccStablesHorseFeed gains a read-only inspect
argument showing client configuration, local horse/bound state, worker timestamp,
registered handle/group, visibility/enablement and last matching target sample.
It does not consume food, call a server RPC or add a separate proof command. Last
target/group samples persist when F8 takes focus; string sampling is bounded to
500ms. Nineteen feeding tests pass, including inspection without invoking Feed.
Native UI is not claimed fixed without runtime evidence.

Only C:\coding\bcc-feather-scripts\bcc-stables\client\horse\feeding.lua needs
copying to resource-relative bcc-stables/client/horse/feeding.lua. Docs/tests stay
local. Player F8 BccStablesHorseStore and confirm disappearance before restart;
after copying, server console restart bcc-stables; player F8 BccStablesHorseCall.
Right-click the nearby dismounted horse for two seconds. If Feed is missing,
player F8 BccStablesHorseFeed inspect and send its exact output. No refresh,
configuration, SQL or Inventory changes.

Native association remains in client/horse/controller.lua ready():
0xD2CB0FB0FDCB473D(r.player,r.entity) when the saddle slot is empty; clear() only
clears a slot it wrote when it still points at the exact same horse.


## Original horse-prompt comparison - 2026-10-27, retest pending

Feed remained missing after the first prompt-lifecycle correction. Compared the
preserved original client/horse/prompts.lua, client/horse/spawn.lua and
server/horse/interactions.lua. Original feeding hides the engine Feed prompt and
starts Interaction_Food from a usable Inventory food item; its scripted horse
prompts obtain the target group through InvokeNative(0xB796970BD125FCE8,horse)
without ResultAsLong or a zero-group exclusion. The new Feed entry now uses that
exact group call and accepts numeric zero. The original interaction animation and
new receipt-backed consumption remain unchanged; this is not a claim that the
original had a working scripted Feed button. Eighteen feeding tests pass, now
asserting native argument count and zero-group binding. Live visibility remains
unverified. Previous diagnosis of registration timing alone was insufficient.

Required upload: C:\coding\bcc-feather-scripts\bcc-stables\client\horse\feeding.lua
-> bcc-stables/client/horse/feeding.lua (relative to server resources). No refresh,
config, Inventory or SQL changes. Docs/tests stay local. Player F8 if a horse is
out: BccStablesHorseStore; confirm disappearance. After copying, server console:
restart bcc-stables. Player F8: BccStablesHorseCall; wait for ready, stand beside
it dismounted and right-click. If Feed is still absent, supply player F8 errors
and server-console BccStablesStatus taken with this called horse present, rather
than adding another diagnostic command or changing configuration.


## Feed prompt lock-on correction - 2026-10-27, ready for retest

Server care readiness passed live, but Feed was missing. Client registered its
prompt before target lock-on and never rebound its target group. It now registers
only in a nonzero live group, visibly before RegisterEnd as in the legacy horse
prompts, and tracks group changes without rebuilding the prompt. The new coroutine
regression covers no target, first lock-on, changed group and target release.
196 offline tests pass; actual native prompt visibility remains pending.

Copy C:\coding\bcc-feather-scripts\bcc-stables\client\horse\feeding.lua to
bcc-stables/client/horse/feeding.lua (relative to server resources). Docs/tests
stay local. No manifest/config/SQL/provider changes or refresh required. If a
horse is out: player F8 BccStablesHorseStore; confirm disappearance. Server console:
restart bcc-stables. Player F8: BccStablesHorseCall; dismount, stand beside the
horse and right-click to lock on. Verify Feed/R appears. Do not consume food yet
if only checking visibility; cancellation/success/restoration tests follow.


## Feeding refactor - 2026-10-27, ready for live testing

Checkout expiration and confirmation cancellation passed live: unchanged balance
and roster. Insufficient funds was skipped because the balance is too high;
offline coverage remains. No repeat paid purchase is needed for these checks.

Feeding now uses one client and one server module, the preserved BCC food
interaction and a scripted Feed (R) entry in the native horse lock-on group.
The engine Feed entry is hidden only after its replacement is registered; other
horse prompts are unchanged. The command BccStablesHorseFeed [foodName] uses the
same normal path. No new proof commands, migration, provider code or generic
transaction framework. Config.feeding.enabled defaults false; food keys remain
consumable_haycube, consumable_carrots and consumable_apple.

The server validates the current observed living horse, canonical Assets owner,
distance, movement and current simulator occupancy. Existing schema-11 care
operation/slot/target rows reserve a precise ordinary item instance and immutable
before/after condition. No provider calls run inside the Stables SQL transaction.
The animation must acknowledge initiation; the five seconds start at that
acknowledgement. Distance/session/lifecycle interruption or missing/failed
animation cancels the same Inventory receipt. Mounted/led horses refuse care.
Store during feeding requests cancellation and can be retried after it finishes;
follow/approach requests refuse while the interaction is active.

Inventory ConsumeCharacterItemOnce owns removal. A matching terminal receipt
commits the capped 20/20 saved benefit, effect row and released care slot in one
local transaction. Unknown replies retain the exact operation. The client retains
its animated operation for retry; a bounded five-operation recovery pass every
10 seconds while work is pending cancels the SAME provider receipt, applying an already-consumed
benefit once even after restart/offline departure. Recovery does not consume a
second item and never adopts old archived care record formats. Disabling new
feeding does not disable owed-benefit recovery. Keep Inventory's caller policy
for unresolved receipts. Failed/mismatched evidence stays reserved for inspection.

Normal completion sends absolute saved condition to the current network owner,
guarded by generation/observer/model and monotonic revision. Native application
is best effort, not claimed as confirmed: an unavailable/migrated simulator or
recovered uncertain delivery restores saved values on the next call. This slice
does not persist native riding decay, add XP or brush durability. Already-full
saved condition refuses without consumption. Existing uninitialized horses are
not silently reset; newly purchased horses already have condition 100/100.

195 offline tests pass (17 new feeding cases), including SQL rollback, lost
receipt reply, reload recovery/cancellation, same-operation retry, foreign receipt
refusal, capped conditions, occupancy/session/distance guards and client stale
projection fences. SQLite/provider/native simulations do not certify actual
MariaDB concurrent lock scheduling, CFX prompts or feeding animation. Live test
is pending. No commit/staging performed.

Required runtime sources -> destinations relative to the server resource root:
- C:\coding\bcc-feather-scripts\bcc-stables\fxmanifest.lua -> bcc-stables/fxmanifest.lua
- C:\coding\bcc-feather-scripts\bcc-stables\config\settings.lua -> bcc-stables/config/settings.lua (merge feeding only; preserve deployed commerce settings)
- C:\coding\bcc-feather-scripts\bcc-stables\client\core\feather.lua -> bcc-stables/client/core/feather.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\core\locale.lua -> bcc-stables/client/core/locale.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\horse\controller.lua -> bcc-stables/client/horse/controller.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\horse\feeding.lua -> bcc-stables/client/horse/feeding.lua (new)
- C:\coding\bcc-feather-scripts\bcc-stables\server\core\boot.lua -> bcc-stables/server/core/boot.lua
- C:\coding\bcc-feather-scripts\bcc-stables\server\horse\controller.lua -> bcc-stables/server/horse/controller.lua
- C:\coding\bcc-feather-scripts\bcc-stables\server\horse\whistle.lua -> bcc-stables/server/horse/whistle.lua
- C:\coding\bcc-feather-scripts\bcc-stables\server\horse\feeding.lua -> bcc-stables/server/horse/feeding.lua (new)

Set Config.feeding.enabled=true in the deployed Stables settings. Merge into
deployed feather-inventory/config.lua (do not replace other caller entries):

```lua
Config.TrustedConsumptionCallers['bcc-stables'] = {
    ['stables.care.v1'] = {
        consumable_haycube = true,
        consumable_carrots = true,
        consumable_apple = true,
    },
}
```

The existing Config.TrustedConsumptionCallers table must be initialized first.
If this caller/purpose already exists, merge the food keys rather than removing
other entries. No Inventory runtime files changed. Optional docs/tests remain
local. No SQL or full server restart.

Before uploading/restarting with a horse out, player F8: BccStablesHorseStore;
confirm disappearance, then server console: stop bcc-stables. After copying and
merging settings, server console in order:

```text
refresh
restart feather-inventory
ensure bcc-stables
BccStablesStatus
```

Refresh is required for the manifest/new scripts/dependency. Inventory restart
loads its caller policy and may stop dependents. Expected Stables state ready,
care=true. At Valentine press L; select an already initialized horse whose saved
condition is below 100 (the previous Morgan was 90/80); check Stats & Details.
If all horses are fully fed, stop and report that instead of resetting data.
Carry an apple and note the quantity. Close the menu, player F8 BccStablesHorseCall
or whistle. Dismount, stop following/leading, stand beside it, right-click the
horse and press Feed/R; move away during five seconds. Expected cancellation,
unchanged item count and saved condition. Return and feed again, stay beside it;
one allowed food is consumed and saved cores increase by 20 capped at 100.
Automatic choice follows Config.items.food order; use player F8
BccStablesHorseFeed consumable_apple to explicitly choose an apple if carrying
several allowed foods. Player F8 BccStablesHorseStore; confirm disappearance;
BccStablesHorseCall. The saved-condition line must show the same new values.
Finish with BccStablesHorseStore and confirm disappearance. Native lock-on entry,
animation, cancellation and saved-core reapplication are the live gate.

## End-of-session commit preparation - 2026-10-26

Maintainer confirmed sex appearance and header-driven selected status now work.
The current session also confirmed menu appearance/input, clean previews and one
live paid purchase followed by call/riding/store. This closes the immediately
preceding appearance/selection retest, not the entire financial fault matrix.
Gold, insufficient funds/capacity/expiry and provider/restart fault behavior have
offline coverage; full live checkout fault/concurrency acceptance remains pending.

Current scope is the full Feather refactor on branch feather: manifest/provider
boundaries, existing schema-11 reads/lifecycle, guarded call/store/recovery,
whistle/follow/relocation, Menu v2 tabs/roster/details/rename/catalog/previews,
per-player settings locale with English fallback, and public paid checkout with
same-key recovery. Restricted/free checkout and automatic paid-order refunds,
care/tack/progression/training/trading/abilities remain disabled or deferred.
Checkout remains false by default; preserve server configuration when deploying.
178 offline tests pass. No staging, commits or push performed. Include all new
manifest-loaded runtime files, shared locale, tests and integration/audit notes;
the modified preserved legacy files carry the bcc-stables/StableLocations rename.
No deployment or commands are needed just to prepare the commit.

## Sex appearance and header selection - 2026-10-26, ready for live test

Maintainer completed a live purchase, called/rode/stored the new horse, and found
preview sex not reflected and header expansion not changing selection. Physical
sex code existed, but ran before async initialization finished; it now applies
before reveal after settling. Preview Show receives saved canonical gender, with
same-entity SetGender updates for checkout choices, explicit male reset and
bounded initialization reapplication. Sex changes use the preserved expression
41611/UpdatePedVariation natives, keep the coat/entity, and clean delayed dirt.
Roster exposes only validated male/female metadata. Old uninitialized sex stays
unrecorded; no invented metadata or migration.

Opening an unselected stored horse header now uses the existing authoritative
select route, renders returned selection markers/revisions, then previews it.
Collapsing/reopening the selected horse does not mutate selection or spawn it.
178 offline tests pass, including two-horse marker transition, preview male/female
switch without respawn, canonical sex propagation and physical timing before
reveal. Native appearance and selection persistence need the live retest.

Required runtime sources -> destination relative to server resources:
- C:\coding\bcc-feather-scripts\bcc-stables\client\ui\stable.lua -> bcc-stables/client/ui/stable.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\ui\preview.lua -> bcc-stables/client/ui/preview.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\horse\controller.lua -> bcc-stables/client/horse/controller.lua
- C:\coding\bcc-feather-scripts\bcc-stables\server\ui\stable.lua -> bcc-stables/server/ui/stable.lua
Server console after copying: restart bcc-stables. No refresh, SQL/config/provider
changes; docs/tests stay local. If a horse is out, first player F8
BccStablesHorseStore and confirm disappearance. Press L, switch stored horse
headers, verify selected markers move and remain after close/reopen. Inspect the
already purchased female preview, then Take Out; check appearance/riding. Dismount,
player F8 BccStablesHorseStore. Checkout sex selector can be tested then Back
without another purchase. Do not pay again just to test appearance.

## Public paid checkout - 2026-10-26, ready for live test

Maintainer confirmed clean previews. Public cash/gold horse checkout is now behind
Config.commerce.purchasesEnabled (false by default). Catalog Purchase opens a
name/sex/currency form, Review obtains a durable 60-second server quote, then the
Menu v2 confirmation displays the exact saved amount. Prices come only from the
server catalog, converted to precision-2 integer units. Client amount/currency
acknowledgement must match; the stable token, route, distance, current character,
public access policy and player capacity are checked before payment admission.

The single internal server/horse/checkout.lua module uses existing schema-11
fs_operations, fs_asset_registrations, fs_horses, history, outbox and condition
rows. No DDL, new migration, provider SQL or old VORP purchase handler is loaded.
It isolates checkout_v1 JSON records using checkout.v1: fingerprints; legacy/proof
operations are not adopted. Reserved quotes never auto-charge. Confirmed
payment_pending/paid orders retry in bounded batches every 10 seconds, with the
same Economy payment and Assets registration keys after lost replies/restarts,
including offline buyers. Registration is checked against a fresh canonical
Assets read. Local projection/history/outbox/condition/fulfillment/selection
writes commit together. Name and sex are canonical asset metadata. New condition
starts at 100/100; selection changes only if no physical call/care operation is
active. Female physical appearance reuses the preserved initialization natives.

Insufficient funds cancels without ownership. Unknown replies retain the same
quote for retry. Pending purchases fence a new confirmed order for the character.
Disabling purchases blocks new admission; already confirmed work still recovers.
BccStablesStatus reports commerce and up to ten pending checkout IDs/states.
Paid registration/ownership conflicts remain audited and pending; automatic
refund/cancellation of a paid order is NOT implemented. The durable purchased
outbox is written, but the broader legacy outbox dispatcher remains unloaded.

First path limits: positive-price, public a_c_horse_* catalog entries; job/trainer/
hours restrictions fail closed. Trainer capacity overrides await job integration;
uses Config.horseLimits.player and alive local projections plus paid/pending
reservations under the stable-row lock. Free checkout cannot fit the current
amount>0 constraint and remains disabled, as do mule/donkey purchases. Do not run
legacy install SQL. Existing Economy readers/transactors and Assets reader/manager
plus Admin assets.asset.manage service grant already list bcc-stables in local
provider configs; preserve those deployed grants.

174 offline tests pass, including isolated real SQL with provider doubles:
cash/gold precision, ownership reader compatibility, insufficient funds, changed/
expired quotes, capacity, restricted/stale/foreign requests, lost payment/asset
replies, offline restart recovery, atomic rollback, lost commit acknowledgement,
no duplicate grant/charge, and active-call selection fencing. New checkout,
confirmation, pending and completion menu definitions pass the actual Menu v2
validator. These do not certify live MariaDB locking/provider transactions;
first live purchase is pending.

Required runtime source root: C:\coding\bcc-feather-scripts\bcc-stables\
Copy these files to identical relative paths under server resource bcc-stables/:
- fxmanifest.lua
- client/core/locale.lua
- client/ui/stable.lua
- client/horse/controller.lua
- server/horse/checkout.lua (new)
- server/horse/owned_repository.lua
- server/horse/controller.lua
- server/ui/stable.lua
- server/core/boot.lua
Config source C:\coding\bcc-feather-scripts\bcc-stables\config\settings.lua:
merge commerce={purchasesEnabled=true} into the server Config table at
bcc-stables/config/settings.lua for testing; preserve other server settings.
No other provider runtime files needed. Docs/tests remain local. No database step.

Commands in order:
1. If a horse is out, player F8: BccStablesHorseStore; confirm disappearance.
2. After copying/configuring, server console: refresh (new script/dependency).
3. Server console: ensure feather-economy
4. Server console: restart bcc-stables
5. Server console: BccStablesStatus (ready, commerce=true, purchases.pending empty).
6. Player UI: L at Valentine -> Browse Horses -> Morgan -> Bay -> Purchase Horse.
   Choose a unique name, female, Cash -> Review Purchase -> Confirm Purchase.
   First cancel the dialog and check no charge/horse, then confirm once.
   Default Bay price is $55.00 (or 3.00 gold); server configuration is authoritative.
7. Check one wallet debit and one new selected roster horse, name/sex/condition
   in Details. Close/reopen: purchase persists. Take Out, ride, dismount, then
   player F8 BccStablesHorseStore and confirm disappearance.
8. Server console BccStablesStatus: no pending checkout. Stop and paste any error
   before starting another purchase. Unknown results must retry the same purchase.

## Clean coat previews - 2026-10-26, ready for live test

Maintainer confirmed menu appearance/behavior. Preview horses now reuse the
preserved appearance-cleaning natives for environment dirt, damage decals and
blood: immediately after initialization, then at 300 ms and approximately 1 s.
Delayed passes verify the same active preview, current session, entity and model;
replacement/close cancels them. No permanent/per-frame cleaning loop and no
physical horse/condition changes. 158 offline tests pass; delayed visual dirt
reapplication needs live confirmation.
Required runtime source C:\coding\bcc-feather-scripts\bcc-stables\client\ui\preview.lua
-> bcc-stables/client/ui/preview.lua relative to server resources. Server console:
restart bcc-stables. No refresh, SQL/config or Menu v2 changes; docs/tests stay
local. Press L at Valentine, inspect owned preview and several catalog coats for
at least a few seconds, including light coats; switch coats and close/reopen.

## Selected marker color - 2026-10-26, ready for live test

Selection markers now use Menu v2's muted/subheading color (Valentine Stable tan),
with the name kept white. Stables passes a selected boolean, keeping labels plain
text. 156 Stables/75 browser tests pass; UI rebuilt. Required runtime sources:
- C:\coding\bcc-feather-scripts\bcc-stables\client\ui\stable.lua -> bcc-stables/client/ui/stable.lua
- C:\coding\feather-scripts\feather-menu-v2\client\validation.lua -> feather-menu-v2/client/validation.lua
- C:\coding\feather-scripts\feather-menu-v2\ui\ -> feather-menu-v2/ui/ (complete folder)
Destinations relative to server resources. Server console: refresh; restart
feather-menu-v2; ensure bcc-stables. Refresh registers rebuilt assets. No SQL/config
changes; docs/tests stay local. Press L, check selected markers match subheading
color on idle/hover/expanded horse headers; names stay normal text color.

## Rename rows, compact horse status and radar restore - 2026-10-26

Ready for live test. Selected roster names use < Horse Name >; stored horses
have no repeated status suffix. Active and unavailable statuses remain explicit
and localized. Rename pairs Save/Refresh and Back/Close. Preview cleanup now
explicitly shows the radar on close, errors, swaps and resource stop, removing
hidden-state snapshots that could retain a hidden radar. 156 offline tests pass,
including stale radar readback during preview replacement and compact labels.

Required runtime sources -> destination relative to server resources:
- C:\coding\bcc-feather-scripts\bcc-stables\client\ui\stable.lua -> bcc-stables/client/ui/stable.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\ui\preview.lua -> bcc-stables/client/ui/preview.lua
Server console: restart bcc-stables. No refresh, SQL/config or provider changes;
docs/tests stay local. Press L, inspect selected name markers, open Details/Rename
and check paired rows. Switch previews/catalog coats, close via button and reopen/
close via X/Escape: radar and normal input must return. If a physical horse is out
before deployment, player F8 BccStablesHorseStore and confirm disappearance first.

## Compact footers and rename entry - 2026-10-26, ready for live test

Catalog coat pages pair Back/Close. Owned Stats & Details pairs Rename/Refresh
and Back/Close below the rotation row. My Horses dropdown no longer repeats
Rename; renaming starts in Details and Save/Back returns there. Removed the
unused roster rename-origin branch. 154 tests pass, including rename callbacks,
validation, saved roster/details names and preview reuse.
Required runtime source C:\coding\bcc-feather-scripts\bcc-stables\client\ui\stable.lua
-> bcc-stables/client/ui/stable.lua relative to server resources. Server console:
restart bcc-stables. No refresh, SQL/config or Menu v2 changes; docs/tests stay
local. Press L, verify dropdown actions, Details footer pairs, Rename save/cancel
return to Details, and catalog coat Back/Close row.

## Stable tabs and coat position - 2026-10-26, ready for live test

Uses existing Menu v2 controlled tabs: My Horses and Browse Horses, including
roster Details/Rename and catalog coats. Replaces duplicate Browse/My Horses
navigation buttons. Switching tabs restores the selected catalog coat or owned
preview inside the same stable route/token. Busy actions fence tab switching.
Two constant navigation targets plus one replaceable active page keep page count
bounded at three. Labels follow live player language. Coat selector shows a
localized 1 of N counter, updated with each coat. Purchases remain unavailable.
154 offline tests pass; actual Menu v2 element/navigation validation passes with
existing target pages through tab/back transitions. Live tab appearance pending.

Required runtime sources -> destination relative to server resources:
- C:\coding\bcc-feather-scripts\bcc-stables\client\ui\stable.lua -> bcc-stables/client/ui/stable.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\core\locale.lua -> bcc-stables/client/core/locale.lua
Server console: restart bcc-stables. Existing Lua files only; no refresh, Menu v2
update, SQL or config steps. Docs/tests stay local. Press L at Valentine, switch
tabs, choose Morgan and cycle all five coats (counter wraps), return to My Horses,
then back to Browse Horses to verify coat restoration. Check Details/Rename/Back
keep My Horses active and Close releases input. If a horse is out before copying,
player F8 BccStablesHorseStore; confirm disappearance before restarting.

## Horse catalog browsing - 2026-10-26, ready for live test

Added Browse Horses to My Horses. Uses the preserved trader design's BreedsOrder
and alphabetically sorted coats. A coat selector shows catalog cash/gold/free
prices and explicitly labeled base performance; paired rotation controls reuse
the existing local preview/camera/fade lifecycle. Same-coat selection reuses the
preview; switching back restores the owned preview (or clears it for an empty
roster). The coat selector is disabled while loading. Failed previews clear the
previous model instead of displaying it under the wrong coat. Language changes
rerender the catalog without reloading the model. Close/resource/session cleanup
continues through the existing preview session.

This is browsing only: no purchase handler, payment, asset mutation, SQL write,
new RPC, schema/config/manifest/dependency change. All configured catalog coats
are browsable; displayed prices do not establish job/trainer eligibility or a
purchase quote. Authoritative purchase policy, confirmation and Economy/Assets
fulfillment remain the next slice. Commerce stays disabled. No legacy modules
were loaded. Shared base-stat rendering avoids duplicating the owned detail UI.

152 offline tests pass. All 25 breeds/122 coat-page definitions passed the actual
Menu v2 validator using local preview mocks. Real model rendering, framing and
input acceptance require the following live check.

Required runtime sources -> destinations relative to server resources:
- C:\coding\bcc-feather-scripts\bcc-stables\client\ui\stable.lua -> bcc-stables/client/ui/stable.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\core\locale.lua -> bcc-stables/client/core/locale.lua
Optional docs/tests stay local. No provider UI files needed for this slice.
Server console after copying: restart bcc-stables. No refresh needed (existing
Lua files only); no database/config steps or full server restart.
At Valentine press L, choose Browse Horses, select Morgan, change coats, inspect
prices/base stats and rotation toggles. Back returns to breeds; My Horses restores
the owned preview. Close restores gameplay/input. Check another breed and reopening.
Purchases must remain unavailable. If a physical horse is out before deployment,
player F8: BccStablesHorseStore; confirm disappearance before the resource restart.

## Shared corner spinner - 2026-10-26, ready for live test

Menu v2 now delays the shared loading spinner beside the close X by 250 ms.
No spinners inside ordinary buttons; Rename keeps Saving for its server request.
Accordion headers highlight on hover. 74 browser tests/build pass.
Required runtime source C:\coding\feather-scripts\feather-menu-v2\ui\ ->
feather-menu-v2/ui/ relative to server resources (complete folder). Server console:
refresh; restart feather-menu-v2; ensure bcc-stables. No SQL/config steps, no Stables
runtime files changed. Docs/tests stay local. Test quick clicks, Rename Save and
header hover at Valentine using L.

## Shared UI feedback - 2026-10-26, ready for live test

User confirmed navigation glyphs and paired footer working. Menu v2 now has a
brief pressed highlight, arrow hover/press feedback, acknowledgement spinner and
repeat-click suppression. Optional busy/busyLabel spans longer consumer requests;
busy is also enforced by Lua. Inputs, textareas and numbers support linked inline
errors. Buttons accept localized confirm strings for a modal confirmation with
Cancel initially focused, keyboard/controller scope, inert background and page/
menu exit cancellation. Confirmation remains a consumer opt-in; no destructive
Stables flow is invented. Reduced-motion preferences disable movement/spinner.

Rename uses Saving feedback for its full server request and errors below the name
field. Existing server validation, revision/ownership checks and close lifecycle
remain. 144 Stables tests, 73 browser tests, 72/41 Menu Lua assertions, lint and
build pass. Live feedback/rename checks pending; confirmation has automated UI
coverage and is available for future destructive actions.

Required sources -> destinations relative to server resources:
- C:\coding\feather-scripts\feather-menu-v2\client\main.lua -> feather-menu-v2/client/main.lua
- C:\coding\feather-scripts\feather-menu-v2\client\validation.lua -> feather-menu-v2/client/validation.lua
- C:\coding\feather-scripts\feather-menu-v2\ui\ -> feather-menu-v2/ui/ (complete built folder)
- C:\coding\bcc-feather-scripts\bcc-stables\client\core\locale.lua -> bcc-stables/client/core/locale.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\ui\stable.lua -> bcc-stables/client/ui/stable.lua
Server console: refresh; restart feather-menu-v2; ensure bcc-stables.
Refresh registers rebuilt assets. No SQL/config changes; docs/tests stay local.
Press L at Valentine. Check arrow hover (also Character/Admin), pressed buttons,
Rename blank-name inline error, then valid Save with spinner/Saving feedback and
repeat-click refusal, roster update, Back/Close input restoration.

## Navigation symbols and paired footer - 2026-10-26, ready for live test

RDRLino remaps navigation punctuation to game icons. Selector/page arrows, close,
accordion arrows and dropdown indicators now explicitly use Arial; labels keep
the selected menu font. Stables uses existing footer row grouping for Rotate
Left/Right and, on the roster, Refresh/Close. No new layout API or scripts.
143 Stables tests and 69 browser tests pass; production UI rebuilt. Live visual
verification remains pending (Character selector, Admin arrows, Stables footer).

Required runtime sources -> destination relative to server resources:
- C:\coding\feather-scripts\feather-menu-v2\ui\ -> feather-menu-v2/ui/ (complete built folder)
- C:\coding\bcc-feather-scripts\bcc-stables\client\ui\stable.lua -> bcc-stables/client/ui/stable.lua
Server console: refresh; restart feather-menu-v2; ensure bcc-stables.
Refresh registers new hashed UI assets. No SQL/config steps. Docs/tests stay local.
Press L at Valentine; verify two footer rows, rotation toggle behavior and Close.

## Default font and centered horse header - 2026-10-26, ready for live test

Menu v2 now defaults to legacy RDRLino for every resource without an explicit font.
The horse name/status is the centered expandable header; no extra Horse Actions
row. Its opt-in accordion callback preserves preview selection/reuse. Admin's
existing local accordion behavior is unchanged. Offline checks: 142 Stables tests,
69 browser tests, 68/40 Menu Lua assertions; lint and build pass. Live checks pending.

Required sources -> destination relative to server resources:
- C:\coding\bcc-feather-scripts\bcc-stables\client\ui\stable.lua -> bcc-stables/client/ui/stable.lua
- C:\coding\feather-scripts\feather-menu-v2\client\validation.lua -> feather-menu-v2/client/validation.lua
- C:\coding\feather-scripts\feather-menu-v2\ui\ -> feather-menu-v2/ui/ (complete built folder)

Server console in order: refresh; restart feather-menu-v2; ensure bcc-stables.
Refresh registers rebuilt hashed UI assets. No database/config changes. Docs/tests
stay local. Press L at Valentine: expand/collapse the centered horse header, verify
one action group and unchanged preview, then test Details, Rename, Back and Close.
Other menus using the default should show RDRLino; explicit font choices still win.

## Menu organization and fonts - 2026-10-26, ready for live test

User confirmed all rename checks passed. Horse Actions and detail information now
use Menu v2 accordions. Rename errors say "Enter a valid horse name." without
repeating the existing help. Menu v2 supplies consistent button spacing and eight
legacy fonts through theme.fontFamily; rdr selects RDRLino. Stables retains its
current default font. 142 Stables tests pass; Menu v2 has 68 passing browser tests,
64/40 Lua assertions, a successful build and verified runtime ZIP. New presentation
changes still require live testing.

Required runtime sources -> destinations relative to server resources:
- C:\coding\bcc-feather-scripts\bcc-stables\client\core\locale.lua -> bcc-stables/client/core/locale.lua
- C:\coding\bcc-feather-scripts\bcc-stables\client\ui\stable.lua -> bcc-stables/client/ui/stable.lua
- C:\coding\feather-scripts\feather-menu-v2\client\validation.lua -> feather-menu-v2/client/validation.lua
- C:\coding\feather-scripts\feather-menu-v2\ui\ -> feather-menu-v2/ui/ (complete built folder, including fonts)

Server console, in order: refresh; restart feather-menu-v2; ensure bcc-stables.
Refresh registers the new built font assets. No database/configuration changes or
full server restart required. Documentation, tests and web sources stay local.
At Valentine, press L, expand the horse, test action/details accordions and rename
validation; check button spacing in Stables and Admin. Font selection is optional
per resource via theme={fontFamily='rdr'} in menu initialization.

## Horse rename - 2026-10-26, ready for live test

User confirmed the preceding menu/preview/fade/placement slice working. Rename is
available from the expanded stored-horse entry and Details. The form supports
Save, Back/Cancel, Refresh after conflict, localized errors and the settings/Core
language contract. It trims surrounding whitespace and accepts 1-100 UTF-8
characters (up to 400 bytes); controls, line separators, <, > and ~ are refused.
Successful saves update roster/details without rebuilding or repositioning the
preview. Closing during an outstanding save cannot update a closed/new menu;
reopening reads the actual canonical outcome.

The canonical name is Assets metadata.name. Stables uses UpdateAssetMetadata with
expectedRevision and a stable stables.rename:assetId:revision receipt key, preserving
all other metadata, the horse UUID, selection and saved condition. Ownership and
current session are rechecked. Same-name readback is a no-op (including recovery
after a lost acknowledgement); stale revisions refuse writes. No new Stables
table, migration, duplicate name field, direct Assets SQL or separate rename journal.
The existing bcc-stables Assets manager/reader access and assets.asset.manage
service policy are used; no provider code or access grants were changed.

Roster pagination now follows Assets' canonical owned-horse page (10 entries).
One list call plus one bounded Stables join supplies names and projections,
instead of a serial name lookup per horse. Other managers' horses are filtered;
Next follows the provider cursor even if a page has no Stables entries. Details
and mutations still independently validate fresh canonical identity/provenance.

141 offline tests pass: Unicode/trim/invalid names, metadata preservation, owner and
revision refusal, lost reply readback, stale-session outcomes, cancel/save/errors,
language change, late UI replies and canonical roster refresh. New form/initialization
specs also passed the actual Menu v2 validator. Live provider mutation and reopen
persistence remain pending; mocked provider tests are not live certification.

Required runtime files (absolute source -> destination relative to server resources):

| Local source | Relative server destination |
|---|---|
| `C:\coding\bcc-feather-scripts\bcc-stables\client\core\locale.lua` | `bcc-stables/client/core/locale.lua` |
| `C:\coding\bcc-feather-scripts\bcc-stables\client\ui\stable.lua` | `bcc-stables/client/ui/stable.lua` |
| `C:\coding\bcc-feather-scripts\bcc-stables\server\horse\owned_repository.lua` | `bcc-stables/server/horse/owned_repository.lua` |
| `C:\coding\bcc-feather-scripts\bcc-stables\server\ui\stable.lua` | `bcc-stables/server/ui/stable.lua` |

Server console: `restart bcc-stables`. No refresh (existing files/manifest), SQL,
configuration or provider restart. Docs/tests stay local and are optional review
material, not required uploads.

At Valentine press L, expand Morgan and choose Rename Horse. Enter a name and Save
Name. Verify the roster and Details show it without reloading the preview; close
and reopen to confirm persistence. Try editing then Back without Save (unchanged),
and a blank or invalid name (refused without losing the form). No horse spawn or
condition reset is required for this test.

## Preview reuse and fade transitions - 2026-10-26

Opening a selected horse and then expanding/collapsing its roster entry now reuses
the same preview. Identity includes menu token, site, horse UUID and model; two
different horses with the same coat still replace each other. A valid displayed
preview skips the redundant preview RPC and native setup, preserving natural
motion, position and toggle rotation. Details still performs its fresh ownership
and saved-condition read.

Restored the original short alpha-fade style for preview entry, replacement and
closing (180ms). The new preview starts hidden; replacement retires the old clone
after fade-out. Closing releases the camera/input immediately while the local
clone finishes fading. Resource/dependency-stop cleanup removes active and retiring
clones synchronously. Reusing the same horse does not replay the effect.

129 offline tests pass, including same-horse reuse, same-model/different-horse
replacement, fade progress and cancellation. Live motion/fade acceptance pending.
This change needs client/ui/stable.lua and client/ui/preview.lua only. If the prior
Menu v2 3% anchor update is still undeployed, deploy these together:

| Local source | Destination relative to server resources |
|---|---|
| `C:\coding\bcc-feather-scripts\bcc-stables\client\ui\stable.lua` | `bcc-stables/client/ui/stable.lua` |
| `C:\coding\bcc-feather-scripts\bcc-stables\client\ui\preview.lua` | `bcc-stables/client/ui/preview.lua` |
| `C:\coding\feather-scripts\feather-menu-v2\client\validation.lua` | `feather-menu-v2/client/validation.lua` |
| `C:\coding\feather-scripts\feather-menu-v2\ui\` | `feather-menu-v2/ui/` |

Combined server-console commands: refresh; restart feather-menu-v2; ensure
bcc-stables. Refresh picks up the earlier rebuilt hashed UI assets. If that
provider update is already deployed, copy only the two Stables client files and
run restart bcc-stables; no refresh needed. No SQL/config/provider code changes
beyond the prior anchor update. Docs/tests stay local.

Press L at Valentine, let Morgan appear, then expand/collapse/re-expand its entry:
the existing horse should keep moving naturally without reloading or resetting.
Check smooth rotation remains, 3% edge placement stays fixed, and close/reopen
fades cleanly. With another owned horse, switching should fade between clones.

## Preview collapse and reusable menu anchor - 2026-10-26

Collapsing an expanded horse entry now leaves the current preview/camera intact.
Only preview replacement or full menu cleanup deletes it. Stables initializes
Menu v2 with position={x='3%',y='3%',anchor='top-left'}, persistPosition=false.
This is a public Menu v2 initialization option for all resources, not a Stables
special case. Default center placement remains compatible; dragging is independent.
The top edge remains fixed when roster/details content height changes.

Verification: 124 Stables tests; 66 Menu v2 browser tests; Lua validation/runtime
54/40 assertions; frontend build completed. Lint had zero errors and existing
formatting warnings. New compiled UI assets are built locally. Live retest pending.

Required runtime copy (destination relative to server resources):

| Local source | Relative server destination |
|---|---|
| `C:\coding\bcc-feather-scripts\bcc-stables\client\ui\stable.lua` | `bcc-stables/client/ui/stable.lua` |
| `C:\coding\feather-scripts\feather-menu-v2\client\validation.lua` | `feather-menu-v2/client/validation.lua` |
| `C:\coding\feather-scripts\feather-menu-v2\ui\` | `feather-menu-v2/ui/` |

Upload the compiled ui folder, not web source or node_modules. Docs/tests remain
local review files. Server-console commands in order:

```text
refresh
restart feather-menu-v2
ensure bcc-stables
```

Refresh is needed for the newly built hashed UI assets; Stables script list is
unchanged. No SQL/config changes or full FXServer restart. Press L at Valentine,
expand/collapse Morgan and verify preview remains. Open/back out of Stats & Details
and check the top/left margins stay at 3% as height changes. Close and reopen to
verify initial position resets; closing still restores camera/input normally.

## Horse details - 2026-10-26, ready for live test

User confirmed toggled rotation smooth and working. The expanded roster now has
Stats & Details: breed/coat, freshly verified ownership, selection/availability,
saved health/stamina percentages and explicitly labelled catalog base performance.
The five catalog ranks use the original 0-9 to displayed 1-10 conversion; they are
not claimed to be saved training upgrades. Missing condition displays Not recorded
instead of inventing 100%; zero remains zero. No live native core sampling or
condition mutation occurs here.

Details reuses the existing menu_preview ownership/condition read: no new route,
SQL, schema or provider integration. Refresh re-reads the same horse. Back keeps
the preview/session and stops rotation; navigation disposes old pages without
closing Routing or spawning a physical horse. Language changes rebuild the active
details page in place through the existing settings/Core translation contract,
with English fallback. The roster expand/collapse nil-toggle was also corrected.

122 offline tests pass, including saved/absent/zero cores, read-only detail
navigation, locale updates, pending-close cancellation and page lifetime. The
roster/details/back element specs also passed the actual local Menu v2 validator.
Visual layout remains a live test, not established by these mocks.

Required upload (absolute source -> destination relative to server resources):

| Local source | Relative server destination |
|---|---|
| `C:\coding\bcc-feather-scripts\bcc-stables\client\core\locale.lua` | `bcc-stables/client/core/locale.lua` |
| `C:\coding\bcc-feather-scripts\bcc-stables\client\ui\stable.lua` | `bcc-stables/client/ui/stable.lua` |
| `C:\coding\bcc-feather-scripts\bcc-stables\client\ui\preview.lua` | `bcc-stables/client/ui/preview.lua` |

Server console: `restart bcc-stables`. No refresh (existing files only), provider
restart, config change or SQL. Docs and tests remain local; they are optional
review material, not required uploads.

At Valentine's stable entrance press L, expand Morgan and choose Stats & Details.
Check breed/coat, Owned by you, Selected/Stored, saved cores and catalog base stats.
Test refresh, both rotation toggles, Back to the expanded roster, and reopen
details repeatedly. Verify Close/Escape restores camera/input; opening details
must not take out a horse or change selection. Test another Settings language
when convenient; missing new translations use English.

## Menu v2 roster slice - 2026-10-26, ready for first live test

Live follow-up: user confirmed menu features functional after the RedM freeze
helper correction. Rotation then changed from 15-degree click steps to toggled,
frame-time-based movement at 35 degrees/second. Same direction toggles off;
opposite direction reverses. One worker runs only while rotating, and stops on
preview replacement/cleanup. Long frames are bounded to prevent sudden jumps.
Toggle rotation was subsequently confirmed smooth and working. Original upload:
`C:\coding\bcc-feather-scripts\bcc-stables\client\ui\preview.lua` to the relative
server destination `bcc-stables/client/ui/preview.lua`, then server-console
`restart bcc-stables`. No refresh, SQL, configuration or provider changes.

The manifest additionally loads catalog/location/translation data, client locale,
preview and stable-menu modules, and server/ui/stable.lua. Locations now use
StableLocations; no old init/main/menu handlers are enabled. Language selection
comes from feather-settings through Core's locale API, with English fallback for
missing files/keys and updates on Core's language-change event. Config.locale was
removed. Existing legacy translations remain data, not a second language selector.

The first paged UUID roster supports selected/stored status, expandable selection
and Take Out, local model preview, rotation, refresh and close. Selection checks
fresh Assets ownership, revision and physical/care fences. Listing projections
alone never authorizes a spawn. Names/gender/tack previews, trader, sale and care
UI remain subsequent work. No diagnostic controls or raw UUID labels are shown.

Opening stores a current physical horse and confirms slot release before entering
a private Routing preview; occupied/unresolved horses refuse entry. Calls are
blocked during the menu session. Closing releases preview, camera, radar and
focus; player freeze state is untouched. The server deletes its route before Take Out calls the
normal horse flow. Session heartbeats do no SQL. A lost opening reply expires in
20 seconds; lost close/heartbeat expires within 30 seconds. Entry currently refuses
configured job/hour restrictions pending authoritative policy integration. Default
locations have those restrictions off. NPC/blip presentation is not yet enabled.

Automated checks cover isolated selection SQL, occupied entry, stale session/owner,
revision conflicts, lost commit reply, local-only preview, cancellation, cleanup,
callback/page lifetime and locale fallback/updates. Visual layout, native camera
placement and live Routing/Core behavior still need the first live check.

### Required runtime copy

Copy these absolute source paths to the relative destinations below. `<resources>`
means the server's actual resources directory. The folders include preserved
runtime source; the manifest controls which modules run. Do not copy .git/tests/docs.

| Local source | Relative server destination |
|---|---|
| `C:\coding\bcc-feather-scripts\bcc-stables\fxmanifest.lua` | `<resources>/bcc-stables/fxmanifest.lua` |
| `C:\coding\bcc-feather-scripts\bcc-stables\config\` | `<resources>/bcc-stables/config/` |
| `C:\coding\bcc-feather-scripts\bcc-stables\shared\` | `<resources>/bcc-stables/shared/` |
| `C:\coding\bcc-feather-scripts\bcc-stables\locales\` | `<resources>/bcc-stables/locales/` |
| `C:\coding\bcc-feather-scripts\bcc-stables\client\` | `<resources>/bcc-stables/client/` |
| `C:\coding\bcc-feather-scripts\bcc-stables\server\` | `<resources>/bcc-stables/server/` |

Docs and tests are optional local review files, not runtime uploads. No provider
code changes, SQL, config toggles or full FXServer restart are required. Existing
Core registration/Assets read permissions for bcc-stables remain required.

### Commands and test actions

Run `refresh` in the server console because scripts/manifest/dependencies changed.
Start only dependencies that are not already running (skip their start lines when
already started), then restart Stables and check status:

```text
refresh
start feather-routing
start feather-menu-v2
start feather-settings
restart bcc-stables
BccStablesStatus
```

Expected: ready/schema11, menus=true, care=false, commerce=false.

1. As the Morgan owner, dismount/release leading and stand at Valentine's stable
   entry `(-367.87, 784.27, 115.95)`. Press L. If a horse is out, verify it is stored
   before the private preview appears.
2. Check roster/status, preview, both rotation controls and Refresh. Test Close
   and Escape; camera/radar/input should restore.
3. Open again, expand Morgan, select if needed, then Take Out. Verify the menu and
   preview close and one rideable horse appears in the normal world.
4. Owner F8: `BccStablesHorseStore`; confirm disappearance. Reopen with L and check
   stored status. With multiple horses, verify selection persists across refresh.
5. Choose another language through feather-settings and reopen. Existing translated
   keys follow that language; missing files/new keys use English.

Earlier sections below retain implementation/test history. Use this current
upload list and commands for this slice, not the historical handoffs below.

First live menu attempt reached preview but failed because IsEntityPositionFrozen
is unavailable on the RedM client. Removed the redundant player freeze handling:
Menu v2 already captures input, and preview code now leaves existing player freeze
state untouched. Only the local preview horse is frozen. Regression tests run
without that global and preserve an externally frozen player. Retest pending.
Correction upload: only client/ui/preview.lua from this repo to the matching
server resource path; server console restart bcc-stables. No refresh, provider
restart, SQL or config changes are required for this correction.

The server database remains the previous Feather Stables database (`fs_*`, schema
11 at the last reported startup). No import, reset or VORP schema installation is
needed for the existing test horse. Do not execute `database/schema.sql` against
that database: it belongs to the VORP gameplay baseline.

## Implemented

- `server/core/feather.lua`: current UUID character sessions and Feather result
  handling, with session checks after yielding provider operations.
- `server/horse/owned_repository.lua`: read the existing selected horse and its
  fulfilled purchase/linked registration in one statement; check fresh canonical
  Assets ownership, model and provenance before returning identity data.
- `tests/test_feather_boundary.py`: offline rejection/identity tests using Lua 5.4.
- `server/horse/call_repository.lua`: transactional reservation, single-use bind,
  cleanup intent and confirmed release using the existing lease/slot/binding,
  process-receipt and runtime-event tables. Pending care blocks new calls;
  cleanup interrupts native care delivery while preserving consumption records.
- `tests/test_call_repository.py`: real isolated SQL transactions test partial
  writes, lost commit replies, duplicate calls, stale sessions, care fences and
  old cleanup replay after a replacement reserves its slot.
- `server/horse/controller.lua`: server-created observation records, bounded bind
  timeout, identity checks, current-simulator occupancy checks, logout/route cleanup
  and the existing Core call/bind/store route names. Reused handles and copied
  markers cannot substitute for an observed creation.
- The controller stops synchronously without SQL. Its exact observed deletion
  requests remain in a nonpersistent process-local convar. Startup and the worker
  observe disappearance of those old handles and finish their SQL releases;
  they never delete an entity from a saved handle or network ID. Missing evidence
  remains fenced; a different process epoch permits audited recovery.
- `tests/test_horse_controller.py`: native simulations exercise the real SQL
  repository, including network-owner migration, occupied refusal, logout during
  creation, ordinary stop/start and full process recovery.
- `client/core/feather.lua` and `client/horse/controller.lua`: bounded Core RPC,
  server-authorized creation, grounded initialization, saved-condition restoration,
  riding/native Lead association, simulator occupancy reporting and local cleanup.
  A single-use accept check refuses expired spawn instructions before CreatePed.
- `server/core/boot.lua`: read-only validation of the existing migration ledger
  and its original checksums. No automatic schema install, import or reset.
- `tests/test_client_horse.py` and `tests/test_boot.py`: client cancellation/replay,
  association preservation, schema refusal and all manifest files. One protocol
  test connects separate client/server Lua runtimes to the real SQL repository.

The owned-horse reader performs SELECT only. The call repository writes lifecycle
state but does not operate entities. Its bind/release observations must come from
the server's native controller, never a client assertion. Dependent writes remain
ordered in one transaction; batches avoid separate bridge calls for each write.
Neither module changes schema, selection, saved condition or canonical ownership.

## Activation

The manifest now loads this Feather-only integration. VORP handlers and oxmysql
are not loaded. Dependencies are feather-core, feather-mysql, feather-assets and
feather-toolkit. Existing provider access for the resource name bcc-stables remains
necessary; the earlier test setup already granted its Core and Assets access.

Call, riding, native leading, whistle approach/follow and store are enabled. The horse remains
invincible for this slice. Stable menus, commerce, care actions, progression,
tack, training and abilities are not loaded yet. Their
baseline files remain in the repository for integration; this is not a full
gameplay release. Calling while the horse is nearby returns horse_busy;
calling or short-whistling beyond 100m now requests guarded relocation.

Server controller installation registers lifecycle events and a PrepareShutdown
export; it adds no self-restart commands or ACE requirements.
Do not configure or persist the reserved bcc_stables_process_epoch_v1 or
bcc_stables_stop_proofs_v1 convars. They are runtime evidence, not server settings.

## First live check

Start with the horse stored in the previous runtime. Deploy this resource as
bcc-stables; do not run bcc-stables-old or the standalone horse addons. No SQL or
configuration toggles are needed for this check.

Because the manifest and script list changed, run these in the server console:

```text
refresh
restart bcc-stables
BccStablesStatus
```

Expect state=ready and features.call=true. A schema/provider failure leaves calls
disabled; report its code instead of resetting the database.

Then in the owning player's F8 console:

```text
BccStablesHorseCall
```

Expect exactly one grounded, visible horse and the horse-ready message. Mount,
ride briefly and dismount. Use the normal right-click Lead prompt and release it
with the normal controls. BccStablesHorseLead is also a normal toggle command.
Finally:

```text
BccStablesHorseStore
```

Expect disappearance. A pending deletion can complete on the server's next tick;
there is no need to repeat a spawn request. Test restart with an active horse only
after this basic flow passes.

The 95 offline test methods pass on Lua 5.4, isolated SQLite and simulated natives.
These cover transaction/controller/protocol behavior, not MariaDB row locking or
actual RedM natives. The first live check passed: one grounded horse spawned;
riding, native leading/release and store disappearance were confirmed. The first
store returned cleanup_pending while deletion completed; its client message now
describes this as pending instead of refused. Active-horse restart remains the
next live check. Its first run exposed delayed deletion during resource stop:
the original stop handler discarded its observation before deletion completed,
leaving horse_busy after restart. The handler now retains pending deletion
evidence and the regression test delays completion until after restart.

A generation already fenced by the previous handler has no retained receipt to
recover in the same process. A full FXServer restart allows the existing audited
process-end recovery to release that generation without guessing entity identity.
After deploying the fix and that one-time recovery, repeat ordinary resource
restart testing; no manual database reset or new configuration is required.

Ordinary restart followed by another call has now passed live, as has the final
store/disappearance. The basic lifecycle test group is complete.

## Whistle integration check

The server issues short-lived, single-use movement tickets to the horse's current
network owner. Short whistle requests approach; long whistle toggles follow/stop.
Follow renews its 30-second native lease while intent remains valid, including
handoff to another simulator. Store, logout, death/occupancy observations and
stale identity stop execution. No NUI/keyboard-focus gate terminates follow.

Approach retains speed 2.0, native stopping range 10.2 and arrival cleanup at 10m.
Follow retains offset (2,-3), speed 2.0 and stopping range 3.0 from the working
Horses settings. Short whistle beyond 100m now uses guarded relocation; long
whistle remains a follow/stop intent and does not relocate.
With no local active horse, whistling calls the selected horse when
Config.stable.whistleAnywhere is true.

The input reader checks the frame-scoped native event queue every frame while
the player is alive and NUI has no focus. Movement workers check every 50ms;
server handoff/renewal uses the existing 500ms controller tick. There are no
global horse scans, per-frame SQL reads or additional proof commands.

Deploy, refresh and restart bcc-stables (new scripts changed the manifest).
Call the horse, move 15-25m away, short-whistle to approach; long-whistle to follow
and long-whistle again to stop. Allow about two seconds between whistles, then
store normally. After this passes, verify the same behavior with a second player
holding network ownership. No configuration changes are required.

The first owner-controlled whistle test and store passed live. During the
second-player test, held whistles arrived as approach. Input classification now
waits for release of a preliminary short event and recognizes a hold of at least
600ms as follow/stop; native long events still work directly. One held gesture
cannot toggle twice. Actual native whistle events from the owning ped remain
required, and the original input mapping is unchanged. Recheck this with the
second player after deploying the client fix.

The held-whistle correction and subsequent store disappearance passed live.
Network-owner attribution remains unverified. BccStablesStatus now includes a
read-only calls.liveCalls list with ownerSource, networkOwner, generationId,
netId, phase and identityMatches. It makes no SQL writes or control requests.
Confirm identityMatches=true and networkOwner equal to the second player's current
server ID (different from ownerSource), then test approach and follow/stop.

Deployment for this status extension: copy server/core/boot.lua and
server/horse/controller.lua from this repository to the matching paths in the
server's bcc-stables resource. No new scripts or manifest changes were made, so
only restart bcc-stables is required; refresh is not needed. Call with
BccStablesHorseCall in the owner's F8 console and run BccStablesStatus in the
server console before whistling and during follow. Finish with
BccStablesHorseStore in the owner's F8 console and confirm disappearance.

The live status confirmed ownerSource=1, networkOwner=2 and identityMatches=true.
The next whistle attempt produced horse_busy from the spawn fallback. Whistles
now use the captured bound-call identity even when the owner's local entity
handle is unavailable after streaming. Server authority still chooses and checks
the current simulator. A stored/cancelled call can still whistle-spawn normally.
Copy client/horse/controller.lua and client/horse/whistle.lua to matching paths
in the server resource, then restart bcc-stables; no refresh or SQL/config change
is required. Reverify ownership before repeating the whistle test.

The ownerSource=1/networkOwner=2 approach, follow/stop and final store test passed
live with matching identity. The delegated whistle test group is complete.

## Distance relocation check

Call or short whistle beyond 100m shares the existing store occupancy check and
confirmed cleanup. Only after the exact old generation releases its slot is the
same selected horse read again and reserved under a new generation. Changed
selection/session/ownership, a rider/leader, uncertain deletion or pending care
prevents replacement. Distance is rechecked after the occupancy response. Nearby
calls do not delete the horse, and overlapping calls cannot create duplicates.

Replacement uses ordinary spawn/bind, including saved-condition restoration and
native riding/leading/whistle association. If deletion exceeds the bounded wait,
cleanup returns pending and no replacement is requested. The owner reported both
call-triggered and short-whistle relocation passing live: the original vanished,
one replacement appeared, and the final store removed it.

Deployment: copy server/horse/controller.lua, server/horse/whistle.lua,
client/horse/controller.lua and client/horse/whistle.lua to matching paths in the
server bcc-stables folder. No manifest, new files, config or SQL changes: restart
bcc-stables only, without refresh. In owner F8, BccStablesHorseCall; move over 100m
away on foot or by teleport while player 2 watches the original horse. Run
BccStablesHorseCall again and verify old disappearance followed by one nearby,
rideable, whistle-responsive replacement. Then move over 100m away again and
repeat with a short whistle. Finish with BccStablesHorseStore in owner F8 and
confirm disappearance. BccStablesStatus in the server console shows generationId
and netId for comparison before/after.
