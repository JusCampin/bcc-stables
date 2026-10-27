# Feather Stables refactor audit

Initial audit: 2026-10-25. Repository-wide follow-up: 2026-10-26.
Scope: source review, not runtime certification. The initial inventory/status
below is historical; see the follow-up for the current loading boundary.

## Decision

Refactor the existing gameplay in `bcc-stables`. Consolidate abilities, trading and professional training into that resource. Keep their configuration switches, but remove their separate manifests, startup requirements and cross-resource calls from the resulting implementation. Do not delete the source resources until consolidation is verified.

The baseline contains useful, established gameplay. Its VORP and oxmysql integration is not a suitable Feather authority or persistence boundary. Preserve native presentation and policies; replace those boundaries rather than mechanically renaming exports.

No runtime code, configuration, database or Git staging was changed during this audit. The existing 37 modified Stables files were left alone. Their diff totals 121 insertions and 121 deletions and includes the user's resource namespace changes.

## Inventory and scope

| Source | Indexed text files | Lines | Role |
|---|---:|---:|---|
| bcc-stables | 86 | 14,203 | Gameplay baseline, rich catalogs, tack, care, lifecycle, menus |
| bcc-horse-abilities | 5 | 264 | Optional item ability and effects |
| bcc-horse-trading | 5 | 273 | Consent-based horse gifting/ownership transfer |
| bcc-horse-training | 8 | 1,511 | Paid player/NPC training courses and daily limits |
| bcc-stables-old | 115 | 21,256 | Previous Feather implementation and substantial test coverage; selective reference only |

Counts include documentation, configuration and license text; they are not executable-code counts. Files were indexed for functions, events, exports, loops and database calls. Manifests, schemas and critical value/authority flows were inspected directly. This is not a claim that every line of the archived rewrite was manually reviewed or that its tests validate this baseline.

The baseline manifest still requires vorp_core, vorp_inventory, oxmysql, bcc-utils and the earlier feather-menu interface. All three addons still depend on/call bcc-horses. The rename alone cannot produce a working consolidated resource.

## Preserve versus replace

| Area | Preserve | Refactor |
|---|---|---|
| Horse spawning and controls | Catalog/model data, metaped initialization, grounding, animations, whistle/lead/flee feel | Session-bound server ownership, observed entity identity, network-owner task routing, deletion confirmation |
| Stables UI | Pages, labels, previews, stable locations and user flows | Feather menu v2 API, focus cleanup, server-authorized actions |
| Care | Feed/brush/drink animations, item keys and native interaction settings | Inventory consumption/durability confirmation, saved condition and cancellation |
| Tack | Catalog, slots, native application, owned-item/loadout distinction | Payment receipts, atomic loadout writes, transfer policy |
| Progression | Bonding/stat policies and configurable XP rates | Authoritative rewards and saved stats; shared progression entry point |
| Lifecycle | Existing death, revive and aging options | Trusted observations, persistent transitions, restart reconciliation |
| Trading | Proposal, recipient consent, distance rules | Session identities, atomic capacity/ownership change, old-entity cleanup |
| Professional training | Courses, geometry, NPCs, marker/UI behavior and scoring policies | Session validation, checkpoint eligibility, daily cap, payment/reward operation |
| Abilities | Optional effects and duration/cooldown policy | One implementation, server-derived bonding, confirmed item mutation and identity-safe cleanup |

Trading currently transfers a horse without charging a price. Preserve that behavior; a paid marketplace is additional scope.

## Priority findings

### 1. Identity and database compatibility must come first

`database/schema.sql` uses integer character identifiers. `server/core/helpers.lua` converts VORP character identifiers to numbers. Feather character identifiers are UUIDs. The SQL also inserts definitions directly into VORP's items table. It must not be applied to Feather Inventory.

Keep existing tables/data intact. Choose and document explicit legacy horse ID to canonical Assets UUID mappings. Use Feather-owned APIs for canonical ownership, currency and inventory; keep only Stables-owned projections and gameplay state in Stables tables. Never infer ownership mappings from horse names, models or reused network IDs. Preserve existing item keys.

The old Feather fs_* schema already represents a different model. Do not load both persistence implementations or blindly replace either dataset. Migration/import should be an explicit supported path, separate from normal resource startup.

### 2. Value flows can partially complete

- `server/horse/purchase.lua:105`: horse insertion precedes currency removal. A successful insertion does not prove payment succeeded.
- `server/horse/sale.lua`: deletion and currency award are separate operations. Recovery cannot currently establish a once-only payout.
- `server/tack/service.lua`: charge precedes loadout replacement; an immediate compensating refund does not cover a crash or unknown provider response.
- `bcc-horse-training/server/main.lua:413`: XP is awarded before daily-limit recording and currency movement at lines 424-425.
- `server/core/api.lua:87`: transfer checks capacity outside its write transaction and treats transaction success as success without requiring the conditional ownership update to affect a row.

Use durable operation IDs and existing provider receipts for these workflows. A local SQL transaction cannot make a separate provider call atomic. Keep explicit recovery only where it answers a real unknown outcome; do not duplicate provider journals throughout every read path.

### 3. Client claims exceed their proper authority

- Abilities trust client bonding at `bcc-horse-abilities/server/main.lua:81`; the baseline duplicates this at `server/horse/interactions.lua:118-137`.
- `server/horse/progression.lua` accepts client stat allocations if their total does not exceed saved totals. This permits redistribution without the corresponding authorized progression. XP reason/cooldown checks alone do not prove riding or care occurred.
- `bcc-horse-training/server/main.lua:454` accepts a client `correctInteraction` flag. Its checkpoint handler verifies rider proximity to the horse but does not itself verify the current checkpoint coordinates; the periodic field/course checks do not replace that check.
- Base entity validation relies heavily on `state.myHorseId`, without a server-observed creation identity/generation. A matching state field alone is insufficient provenance.
- Food removal in `server/horse/inventory.lua` is a separate event from the care effect. Durable item helpers in `server/horse/interactions.lua:13` do not verify inventory mutation outcomes before approving effects.

Clients should request actions and report presentation outcomes. The server derives permissions, prices, ownership, rewards and eligibility from trusted state and observations.

### 4. Source IDs are not session identities

Trade proposals and training sessions retain source IDs across asynchronous consent/course work. Capture both character and session identity, and revalidate after waits/provider calls and before committing results. A connected source can change character; a disconnected source can later be reused. Delivery queues and world-care reservations need the same bounded lifetime and session cleanup rules.

### 5. Restart and entity lifecycle need one owner

`client/core/main.lua:491` already has onResourceStop cleanup. `client/horse/return.lua` saves asynchronously, deletes locally and clears active state without a server-confirmed disappearance boundary. Entity existence checks alone do not prove that a delayed worker still owns the same horse generation.

Use one server registry for the active physical horse and one client controller for its presentation. Store/flee/relocate/death/transfer/shutdown must use the same cleanup path. Cancel workers and native associations when that generation ends.

Normal resource stop handlers should perform immediate local cleanup. They cannot be the only durable save mechanism: asynchronous SQL/network work is not guaranteed to finish during stop or abrupt process death. Persist important state during play, support graceful shutdown when time exists, and reconcile stale physical records on startup without acting on an unrelated reused net ID. Server owners should use normal start/stop/restart operations; do not make self-restart commands or new ACE permissions the required operational path.

### 6. Avoid carrying performance costs forward

`server/core/api.lua:53`, horse inventory and training perform GetAllPeds scans to locate a known horse. Training can repeat that scan every second alongside another proximity lookup. Replace repeated global searches with the validated active entity registry and bounded lookup/revalidation.

Keep frame polling only for active native input/prompt work that requires it. Idle proximity discovery can sleep adaptively; periodic lifecycle/care work should share bounded scheduling. End every worker on session/generation change. Query snapshots and batched transactions from the earlier Feather work are useful where they eliminate actual round trips; do not assume this refactor inherits its measured timings.

The horse inventory open path also permits owners to bypass the proximity check applied to shared access. Make intended remote-access policy explicit and enforce it consistently through the Inventory provider.

## Consolidated structure

Keep the current client/core, client/horse, client/ui, client/tack and matching server organization. Move addon functionality into internal abilities, trading and training modules and their configuration. Do not introduce self-export calls where ordinary internal calls suffice.

Use a small set of shared boundaries: current session/permissions, horse ownership and repository access, active entity lifecycle, progression, and provider-backed value operations. Extend these when needed rather than adding an independent lock table, horse locator, character lookup and journal for each feature.

Deduplicate flaming hooves between the base and addon. Consolidate trainer job/capacity/reward settings rather than maintaining conflicting base and addon policies. Update docs/ARCHITECTURE.md and README: their separate-addon design no longer describes the requested release.

Framework destinations: Feather Core for current sessions/RPC; Assets for canonical horse ownership; Economy for currency operations; Inventory for item use, durability and horse containers; MySQL for Stables-owned data; menu v2 for menus. Toolkit, Notify and job/access providers should be used through their supported contracts. Verify exact capabilities during implementation rather than inventing a compatibility API or directly querying their tables.

## What to reuse from bcc-stables-old

Retain the archived resource as reference. Evaluate its provider adapters, single-statement ownership snapshot, receipt-backed consumption/payment handling, generation identity, network-owner delegation, condition persistence and relevant transaction/replay tests individually.

Do not copy its complete runtime, diagnostic commands or proof fixtures into the new baseline. Working legacy native behavior should remain the presentation baseline. Existing old tests cover the old implementation; migrate only tests that protect retained contracts and invariants.

## Implementation order and review gates

1. Establish the identity/schema mapping and minimal Feather integration; consolidate resource loading and internal interfaces. Preserve native behavior. Gate: boot, one horse call/ride/lead/native menu/store, character exit and ordinary resource restart.
2. Complete purchase, sale, selection, inventory access, tack and gift transfer through supported providers. Gate: actual successful flow plus cancellation/retry/unknown-outcome and capacity/session checks where relevant.
3. Integrate care and saved condition using Inventory's consumption system. Gate: one item/effect, cancelled care consumes nothing, saved condition survives store/call.
4. Integrate professional training and abilities through the shared progression/item/payment boundaries. Gate: valid completion plus refused invalid checkpoint/session/replay and once-only reward/payment.
5. Finish configuration/docs/import guidance and consolidated release checks. Remove obsolete integration surfaces after their replacements are verified.

Build complete player workflows at each gate. Keep most failure testing automated and isolated; request live tests only for native behavior or provider integration that cannot be established locally. Do not add permanent proof commands for each implementation step.

## Initial audit status (2026-10-25)

Audit complete enough to begin the first integration slice. No code has been ported or certified against Feather in this pass. Live deployment, SQL migration, source-resource removal and commits have not been performed.

## Original Feather Menu review (2026-10-26)

Read the preserved `client/ui/menu.lua`, all 13 `client/ui/pages/*.lua` files,
client/server preview-instance handling, roster/selection helpers, stable entry
prompts and tack-session preview/checkout handling. Also read the original
feather-menu registration, open, close and page-routing implementation. This
review precedes Menu v2 implementation; the original UI is the behavior reference,
not the small read-only menu from the archived Feather rewrite.

### Flow to preserve

- Stable entry first retrieves the roster, enters private preview, establishes a
  camera and opens **My Horses**. The selected horse is previewed automatically.
- Roster entries expand/collapse. Expanding an entry selects it, previews its
  appearance and exposes **Take Out / Return / Switch**, **Stats & Details**,
  **Tack Shop**, **Rename** and **Sell**. Footer controls provide rotation and
  access to the trader. Preserve the empty-roster route to purchasing.
- The trader shows accessible breeds, then alphabetically sorted coats with
  expandable **Stats & Details** and **Purchase Selection** actions. The purchase
  page shows coat, price/currency, gender and name, followed by confirmation.
  Cash-only, gold-only, either-currency and free entries have distinct behavior.
- Naming serves purchase, captured-horse registration and rename, with pending
  guards and a roster refresh after success. Sale has a confirmation page with
  horse identity, origin, calculated payout and a currency choice when supported.
- Tack starts from the selected preview horse. Categories lead to component
  selectors with **Shop Catalog / Owned Tack**, an explicit none option, live
  appearance changes, name/price/durability, current-loadout review and checkout.
  Checkout distinguishes new purchases from owned items and compatible currency.
  Back/close cancels the uncommitted preview and restores the original loadout.
- Wild-horse management is a separate contextual entry for a mounted/led captured
  horse, with sale/cooldown handling or registration leading to naming.
- Active-horse information is a separate menu: performance/cores, training XP,
  bonding overview and four bonding-level pages. It also displays aging details
  and an ability timer when enabled. It is distinct from catalog/roster details.

### Presentation and preview behavior

Keep the left-positioned, draggable menu, resolution-dependent width, scrollable
content and header/content/footer structure. Preserve gray/gold headings,
success/danger actions, localization, back navigation and the preview camera's
configured side, distance, FOV, offset and rotation behavior.

Previews are local non-networked peds, separate from the real active horse. They
include gender and tack appearance, delayed appearance cleanup, loading feedback,
fade-in, stale-request rejection and cached roster previews. Closing stops
rotation, cancels tack preview, invalidates outstanding preview requests, deletes
preview peds, destroys the camera, restores radar and exits preview routing.
Menu focus/cursor release is owned by the menu provider. Page navigation within
the same stable menu must not run the full close/cleanup sequence.

### Migration constraints and defects not to reproduce

1. **Preview routing and horse lifecycle must be coordinated.** The old UI moves
   the player to `bucketBase + source`. The new controller cleans a live horse
   when its owner leaves the default world. Copying preview entry unchanged would
   therefore clean the real horse simply by opening the menu. Use a supported,
   explicit preview transition and verify return to gameplay before call/switch;
   do not rely on the old fixed 450ms delay or silently weaken route checks.
2. **UUID identities replace numeric assumptions.** Roster, expanded-entry,
   detail, rename, sale and tack code repeatedly use tonumber(horse.id). Adapt
   these to existing Feather horse UUIDs without changing saved ownership data.
3. **Separate preference from physical availability.** The original roster labels
   is_selected as `(Active)`. The new UI should preserve the selection affordance
   while accurately distinguishing selected, stored, active and cleanup states.
   Persisted selection must be acknowledged before the UI claims it succeeded.
4. **Preserve user flows, not old authority.** Client job filters and displayed
   prices remain presentation; Core/Assets/Economy/Inventory-backed server actions
   must authorize mutations. Never remove a captured entity before its accepted
   sale/registration outcome is known, as the old wild-sale UI currently does.
5. **Scope asynchronous UI results.** Closing/back navigation can invalidate tack
   state while checkout is awaiting a callback; the old callback then indexes
   state.pending. Use captured menu/session identity and reconcile committed
   results without updating a closed or different horse's page. Fix the rename
   refresh callback that currently discards its supplied roster-opening function.
6. **Do not accumulate pages/callbacks on every rebuild.** The old builders reuse
   page IDs through RegisterPage, which replaces registrations while incrementing
   counters. Use Menu v2 page/element lifecycle deliberately, preserving values
   and disposing obsolete callbacks. Do not route by closing/reopening the entire
   stable session or carry VORP callbacks into a compatibility shim.

The intended port keeps this navigation and preview experience while replacing
framework integration and unsafe asynchronous boundaries. This review made no
runtime or manifest changes and requires no server deployment or commands.

## Repository-wide follow-up (2026-10-26)

### Coverage and loading boundary

Reviewed the Stables client/server systems, shared helpers, menu pages,
configuration/catalogs, locales, SQL, manifests, documentation and test
organization, plus abilities, trading and training source resources. This builds
on the initial audit and preceding implementation reviews of active Feather
code. Repeated catalog/translation/location data was also loaded and inspected
programmatically in isolated Lua; no game code or database mutations were run.
Binary inventory artwork was inventoried, not treated as source code. The archive
`bcc-stables-old` remains a selectively reviewed reference, not a second complete
manual review. This is not line-by-line certification or a fresh live test of
every feature. Offline native mocks and isolated SQL do not certify RedM or
MariaDB behavior.

Before these documentation edits, Stables had 105 text files / 17,635 lines and
five binary files, excluding Git internals/Python caches. Abilities had five text
files / 264 lines; trading five / 273; training eight / 1,511. Counts include tests,
catalogs and docs, not just runtime code.

The active manifest loads settings, Feather client/server boundaries, the event
buffer, owned/call repositories, horse controllers/whistle and boot. It does not
load the old init/main/helpers/API modules, menus, catalogs, locales, tack, care,
inventory, commerce, progression, aging, death or addons. Call/ride/native lead,
delegated whistle approach/follow/stop, store and distance relocation are enabled.
Two-player whistle and distance replacement/store passed reported live testing.
Invincibility remains while lifecycle gameplay is unported. Condition restoration
does not mean new care effects or periodic condition saving are implemented.
Boot requires the exact existing schema-11 ledger, not a fresh-install mechanism.

**Namespace collision before menus:** `Stables` is now the runtime namespace,
but `config/stable_locations.lua` assigns `Stables = { ...locations... }`.
Separate location data before loading it; load-order tricks would erase runtime
modules or leave consumers reading the wrong table.

The current owned reader recognizes linked stable-purchase provenance and
`a_c_horse_*` models. Captured registration and the catalog's donkey/mule models
need explicit supported admission/provenance before menus offer them.

### System map and notes for subsequent work

| Area | Preserve | Integration notes |
|---|---|---|
| Core main/helpers/init/commands/API | Stable hours/jobs, streamed NPCs/blips, roster helpers and commands | Replace numeric-ID/global interfaces; never enable their old spawn/save/stop loops beside the current controller. |
| Spawn/return | Metaped setup, delivery motion, native association and control settings | Retain already ported behavior. Do not restore blind net-ID rebinding, local-only deletion or loss of identity during stream-out. |
| Interactions/world care/prompts | Brush/feed/drink, rest/sleep/wallow transitions, deferred mounting, trough/hay context and bonding gates | These share condition, XP and interaction state. Integrate one coordinated flow rather than independent reward handlers. |
| Progression | Travel rewards, bonding unlocks, cyclic permanent stat awards and level reconciliation | Client stat totals allow redistribution. Legacy SaveHorseStats defaults cores to 100 when unavailable/dead; copying it could refill saved condition. Use one authoritative write boundary. |
| Inventory | Saddlebag policy, model capacity, shared/loot rules, item restrictions | Owner access bypasses shared-access proximity checks; saddlebag eligibility is client-side. Use Inventory access checks and the observed horse, not GetAllPeds/state fields. |
| Death/revive/aging | Writhe, revive, permanent-death options and lifespan presentation | Revive updates horse state before unchecked item removal. Client death claims are insufficient. Use shared cleanup and canonical Assets lifecycle. |
| Tack | Catalog IDs, owned instances, previews, currency choice, loadouts and appearance | Serialize equip/transfer across horses, verify conditional writes, use provider payment receipts and retain sender-owned tack on gifts. |
| Delivery/cooldowns/world reservations | Queued spawn point, care-spot exclusion and cooldown policies | Capture Core session identity, bound outstanding requests, recheck at grant and clean on session change. Persist only where policy requires it. |
| Features/info card | Name tags, breed notices, water cleaning and native information display | Keep presentation separate from ownership. Dispose bindings safely; avoid a separate permanent frame loop for every feature. |
| Abilities | Effect duration, warning, golden cores, fear flags, rear animation and durability | Base/addon flaming hooves are duplicates. Keep one internal module, server-derived bonding and generation-safe effects. Base settings currently omit its flamingHooves block. |
| Trading | Leading-based gift proposal, explicit consent and sender tack retention | Capture both sessions; capacity and conditional ownership writes need a common fence. Physical cleanup belongs in the supported transfer flow. This is gifting, not priced trading. |
| Training | Player/NPC menus, surveyed polygons, routes, laps, markers, timing and scoring | Validate checkpoint coordinates and actual riding/leading server-side. Existing handler trusts a boolean and omits checkpoint distance. XP/cap recording/payment currently complete separately. |

Care and lifecycle details:

- Feeding removes the item at animation start and grants rewards later; brush and
  lantern durability is charged before client proximity/completion checks. Retain
  animations, replace the split with Inventory-backed outcomes/cancellation.
- Rest/sleep regeneration saves every reward tick alongside another periodic save
  loop. Use one condition policy and bounded scheduling instead of both writers.
- World-care reservation requests accept client model/coordinates without proving
  the actual nearby object. Arbitrary coordinates must not authorize benefits.
  A client timeout can leave the server reservation until expiry.
- Aging initialization mutates existing legacy rows automatically on load. Config
  enables aging, seven real days/year, adult/senior/elderly thresholds 2/3/5 years.
  Agree existing-horse policy before enabling it. SQL wall-clock dates differ from
  the in-game shop clock and client millisecond timers.
- Trainer/job eligibility is duplicated across progression, purchasing, taming and
  professional training. Consolidate policy and fresh server job checks.
- Training scans all peds every second. Use the observed record; retain frame work
  only for native input and visible markers/prompts. Sessions must end on character,
  ownership, generation or lifecycle changes as well as disconnect.

### Data and documentation findings

- **25 breeds / 122 models:** catalog/model-to-breed mappings agree; checked
  currencies, nonnegative prices/capacities and all five stat ranges were valid.
  This does not prove native model availability.
- **1,010 tack entries / 13 categories:** no duplicate component hashes within a
  category. Preserve slot/hash catalog IDs. Tail and saddlecloth both use category
  hash `0x17CEB41A` in shared/tack.lua; verify native clear-slot behavior before
  changing this or carrying it forward.
- **Nine stables; seven training grounds.** All training grounds are configured
  and enabled with polygons and leading/riding routes. Preserve surveys/tolerances;
  generated fallback routes still require field validation.
- English has 137 keys; each other locale has 81 and lacks 56 English keys.
  Literal `_U` calls reference missing English keys `horseOccupied`, `lanternDesc`,
  `minute`, `renamedHorse`, `second`, `seconds`. The helper returns a nonempty error
  string, so `_U(key) or fallback` does not actually provide a fallback. Fix this
  centrally when localization is enabled. For Stables and every Feather/BCC
  resource, resolve each player's selected language through `feather-settings`;
  individual resources no longer select language through `Config.locale` or
  another resource-wide language setting. Keep translation dictionaries local
  where appropriate, but use the supported settings contract for language
  selection and changes. Resolve server-originated messages for their recipient,
  not once globally for all players. Verify the provider API before implementation.
  If the requested language's localization file is missing, fall back to English.
- README health/stamina prose contradicts source/SQL: progression ranks differ
  from current_health/current_stamina core percentages. Rest/sleep regeneration
  also exists despite its "future update" wording. Rewrite each historical feature
  description when its final implementation is enabled.
- Legacy base/training SQL targets integer VORP identities/tables. Neither is an
  install/upgrade script for the existing Feather database. Preserve item keys,
  artwork and license/credits. Do not ship addon manifests or test fixtures as
  consolidation dependencies.

### Next boundary and process

Proceed with Menu v2 using the original UI flow above. First separate location
data from the runtime namespace and coordinate menu-session/preview routing with
physical cleanup. Implement actual UUID roster/selection/call/store behavior
before exposing commerce, tack or care actions. Preserve the rich menu design;
do not reactivate legacy net handlers wholesale.

Reuse current session/ownership boundaries, physical controller and provider
receipts. Avoid parallel horse registries, compatibility layers, proof-command
families and dispatch frameworks per feature. Re-read the affected implementation
when editing; these notes preserve cross-system context, not replace review.
No runtime, manifest, config, SQL, staging or commits changed in this review.
No server copy, restart or live commands are required for these notes.
