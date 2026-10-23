# BCC Stables — Feather development

Guarded purchase admission/payment, canonical registration, stored fulfillment,
manual outbox, owned reads and durable selection have controlled live acceptance.
Core/Assets/Economy integrate through public APIs. Native dispatch/bind/store has
controlled multiplayer, ownership migration, isolation, replay and cleanup acceptance.

Schema 6 adds audited process-end recovery; migration, controlled bound-generation
release/replay, replacement-slot isolation and fresh preparation passed live. Schema 5 and its runtime process identity/dispatch receipts passed live checks.
Console-only recovery refuses same-process uncertainty, missing evidence and live
observers. It performs no entity lookup or deletion. Released revision 5 distinguishes
process-end recovery from ordinary observed cleanup. See
[native recovery](../../feather-scripts/gameplay-resource-docs/bcc-stables/NATIVE_RECOVERY.md).

Registrations now include twenty-seven RPC routes and three session subscriptions.
Purchase, proof, selection and call switches default off; controlled server tests
retain selection/call/native switches enabled. Purchase UI and riding/follow/tack
remain unavailable. Offline suite: 612/612 cases.

Selected-horse call/current store controls use Core RPC; controlled call/bind,
store/pending/disappearance and repeated empty store passed live. Use `BccStablesHorseCall` and `BccStablesHorseStore` without IDs.
See [call controls](../../feather-scripts/gameplay-resource-docs/bcc-stables/HORSE_CALL_CONTROLS.md).

See the authoritative [master plan](../../feather-scripts/gameplay-resource-docs/bcc-stables/BCC_STABLES_MASTER_PLAN.md),
[owned horse reads](../../feather-scripts/gameplay-resource-docs/bcc-stables/OWNED_HORSE_READS.md),
[stored fulfillment](../../feather-scripts/gameplay-resource-docs/bcc-stables/STORED_FULFILLMENT.md)
and [outbox delivery](../../feather-scripts/gameplay-resource-docs/bcc-stables/OUTBOX_DELIVERY.md).

See [horse selection](../../feather-scripts/gameplay-resource-docs/bcc-stables/HORSE_SELECTION.md) for revision-checked set/get/clear contracts and deployment gates.

Durable call preparation/get/abort is implemented behind callPreparation=false;
the single-use submission claim now feeds a gated native dispatch/bind/store bridge.
See [native calls](../../feather-scripts/gameplay-resource-docs/bcc-stables/NATIVE_CALLS.md) for deployment and live gates. Internal binding/cleanup persistence is documented in
[entity persistence](../../feather-scripts/gameplay-resource-docs/bcc-stables/CALL_ENTITY_PERSISTENCE.md). See
[call preparation](../../feather-scripts/gameplay-resource-docs/bcc-stables/CALL_PREPARATION.md)
for accepted migration/generation gates and remaining native lifecycle work.

New RedM stables resource built from scratch for the current Feather Framework.
The resource folder and export identity are `bcc-stables`.

## Branches and status

- `main` contains the current VORP version until the Feather Framework release.
- `feather` contains the new Feather build, with no backward compatibility.

This branch is an early development build, not a playable release. Code migrations manage nine domain tables plus the migration ledger. Controlled
purchase, financial, canonical, projection and outbox proofs retain durable audit
records; live failure/race/session and physical gameplay gates remain open.

## Authoritative plan

The master plan lives in the sibling `gameplay-resource-docs` repository at
`bcc-stables/BCC_STABLES_MASTER_PLAN.md`.

Shared workspace location:
`C:/coding/feather-scripts/gameplay-resource-docs/bcc-stables/BCC_STABLES_MASTER_PLAN.md`.

Phase 0 is in progress. The Core foundation has offline Lua 5.4 coverage; entity
ownership, native behavior and interrupted settlement recovery remain open.
Implementation status and acceptance evidence belong in the master plan.

## Integration direction

Use Core session, RPC, event, policy, locale and notification APIs, plus Feather
Assets, Economy, Inventory, MySQL, Routing, Toolkit and Menu v2 for their domain services.
Assets owns canonical horse identity, model, provenance, status and ownership.
Stables owns horse gameplay and coordinates purchase workflows. Do not add VORP/RSG
bridges, old BCC API aliases or legacy database imports.

## Run the foundation

Current checkpoint: server-only `config/catalog.lua`, validated against Economy
currency precision, and bounded character-required `stables.catalog.get.v1` RPC.
The frozen read-only catalogue starts with Morgan - Bay at 10000 dollars base
units (100.00 at current precision=2), a configurable development default.
Prices are display data, not purchase quotes. Quotes, purchases and spawning stay
unavailable. Capability `catalogRead=1`; status `checks.catalog` reports revision
and entry count, with two routes when entity proof is off. Offline suite: 257/257.

Upload `fxmanifest.lua`, `config/catalog.lua`, `server/catalog.lua`,
`server/economy.lua`, `server/foundation.lua` and `client/catalog.lua`. Keep every
proof flag false. Server console: `refresh`, `restart bcc-stables`,
`BccStablesStatus`, `BccStablesContractSmokeTest`. F8 while a character is selected:
`BccStablesCatalogSmokeTest`. Expect revision=1, entries=1,
purchasesAvailable=false and Morgan - Bay dollars 100.00. No money, assets or
native entities are created. Details: gameplay-resource-docs/bcc-stables/CATALOG.md.

Current checkpoint: opt-in paidLinkProof=false covers real one-base-unit payment,
durable Assets registration/link, restart inspection and fully linked cancellation.
Linked cleanup saves an immutable retirement plan before calling Assets; verifies
the exact retirement receipt and terminal current state before any refund. Any
prepared/submitted intent, owner/revision mismatch or fulfilled horse refuses this
path. No physical horse or gameplay purchase path is enabled. Offline: 240/240.
See gameplay-resource-docs/bcc-stables/PAID_LINK_PROOF.md for the eight upload files,
flag settings, exact commands and remaining uncertain-registration constraints.

Current checkpoint: durable compensation only for paid operations whose Assets
registration was never prepared. FenceUnregistered checks for absent registration
and fulfillment artifacts under the same locks as preparation, then saves a
versioned fence. RefundUnregistered verifies the original journal and the full
Economy reversal journal before terminal refund/capacity release. Any existing
registration intent blocks this path; post-submission refunds remain unavailable.

Optional paymentProof=false enables a console-only, one-base-unit real-payment
test when explicitly set true. BccStablesPaymentProof run <serverPlayerId> 1
charges the selected character's existing dollars wallet; inspect/refund take the
printed character UUID. No Assets registration, entity or account provisioning.
Exact instructions are in gameplay-resource-docs/bcc-stables/PAYMENT_PROOF.md.
Offline suite: 220/220. Live payment/fence/refund recovery remains pending.

Current checkpoint: required Economy Contract 1 consumer and internal payment
receipt recovery. Startup checks trusted transaction reads; status includes
checks.economy with paymentsEnabled=false. BccStablesEconomySmokeTest is read-only.
The internal Payments.Pay method has no gameplay route or worker; only the opt-in
payment proof invokes it. It saves intent before posting, replays the same transfer key,
validates a committed two-entry journal and records paid without fulfilling a
horse or refunding. See gameplay-resource-docs/bcc-stables/PAYMENT_RECOVERY.md.
Current offline suite: 220/220. Live financial recovery remains pending.

Upload fxmanifest.lua, server/economy.lua (new), server/payments.lua (new),
server/foundation.lua and server/main.lua for this checkpoint. Keep all three
proof flags false. Ensure feather-economy, run refresh before restart bcc-stables,
then BccStablesStatus and BccStablesEconomySmokeTest. No new schema/framework edit.

The opt-in `assetProof=false` setting controls a separate console-only canonical
Assets proof. See gameplay-resource-docs/bcc-stables/ASSETS_CONTRACT_PROOF.md.
It registers one deterministic test asset per character, checks replay/conflict
and receipt recovery, then explicitly retires it. It spawns no entity, fabricates
no payment and does not invoke the paid purchase coordinator. Retirement retains
the canonical record and audit. Current offline suite: 179/179.

This proof needs Admin's explicit bcc-stables / assets.asset.manage service grant
under the feather-assets broker. That action covers asset management through
Assets' own caller/manager checks; ownership transfer remains ungranted. Proof
configuration stays false by default; registrationEnabled=false still describes
the disabled gameplay registration path.

Current Assets checkpoint: migration 002 adds durable registration intents and
canonical asset links in `fs_asset_registrations`; migration 001 is unchanged.
The internal coordinator persists intent before submission, recovers the same
Assets request ID and checks receipt/current facts before recording a historical
link. No command/RPC/startup worker invokes it; mutation policy and live recovery
remain pending. Fulfillment/refunds remain blocked. Offline suite: 165/165.

Startup validates Assets Contract 1, the enabled horse
type and Stables' trusted read access. `BccStablesAssetsSmokeTest` is a read-only
server-console check. `BccStablesStatus` includes `checks.assets` with
`registrationEnabled=false`; no asset mutation is enabled. Assets loss latches
foundation failure until Stables is restarted after its dependencies are ready.
The authoritative `ASSETS_INTEGRATION.md` documents the remaining saga/fence design.

For this checkpoint upload `fxmanifest.lua`, `server/migrations.lua`,
`server/assets.lua`, `server/asset_registration.lua` (new) and
`server/repository_proof.lua`. Keep both
proof flags false. Run server-console `ensure feather-assets`, `refresh`, then
`restart bcc-stables` before the diagnostics below. Status should report
schemaVersion=2/applied=1 on the first upgrade (then applied=0 after restart).
Run server-console `BccStablesPersistenceSmokeTest`: expect 9/9, including both
migration checksums and fs_asset_registrations. The Assets smoke remains read-only.

Start the current Feather Core and its own dependencies first. This build only
requires `feather-core`, `feather-mysql`, `feather-assets` and `feather-economy`; other gameplay dependencies will be added with their
corresponding implementations. Keep the folder name `bcc-stables`.

Enabling the entity proof additionally requires `feather-toolkit` for bounded
client model loading. It adds no production horse capability.

After copying this build, run in the server console:

```text
refresh
ensure bcc-stables
BccStablesStatus
BccStablesContractSmokeTest
```

Expected: `state=ready`, `reason=foundation_only` in the JSON status and `6/6
passed` in the server smoke test. These describe foundation readiness, not horse
gameplay readiness. With a current Feather character selected, run in F8:

```text
BccStablesClientSmokeTest
```

Expected: `session RPC PASS; gameplayAvailable=false`. Before character selection,
the route should fail with `character_required`. It does not spawn or grant a horse.
The two diagnostic commands are read-only; server commands require the console.

For the unresolved rejection-response investigation, run at character selection:

```text
BccStablesRpcCompare
```

Stay at character selection until `compare done` prints. The command sends the
same session request through Core's callback and async exports, spaces requests
past the rate window, and prints only return counts/types/error codes. It runs
against unmodified Core; do not deploy the earlier experimental Core arity patch.
Repeat while playing only after capturing the selection result. Missing results
are not counted as successful rejection. This command is read-only as well.

Core restart invalidates sessions and registrations. Use a controlled full
framework/server restart after Core updates; Stables fails closed and does not
attempt to reconstruct sessions. Run `refresh` before restarting after script or
manifest additions.

## API and tests

Server exports `GetCapabilities()`, `GetHealth()` and `AwaitReady(timeoutMs)` return
Core-style result envelopes. `AwaitReady` accepts an integer from 0 to 60000 ms;
default is 30000. `config.lua` sets the bounded Core startup wait.

The only RPC is `stables.session.check.v1`, accepting an empty object and requiring
a current character. It derives identity through Core and rejects stale request
contexts. The session route is rate-limited to two calls per two seconds.

The smoke test uses Core's callback `CallRPC` export and captures the response
locally with a bounded wait. Live comparison confirmed that this path delivers
`character_required`, while `CallRPCAsync` returned zero values for the same
no-character request. Core remains unmodified; the async export is used only
by the comparison command to track the unresolved framework transport issue.

## Disposable horse-native proof

On a development server, set `entityProof.enabled = true` in `config.lua`.
Use `entityProof.spawnMode = 'client_lease'` for the next experiment. The earlier
`server_rpc` attempt timed out; it is retained only as an explicit research mode.
Start `feather-toolkit` before Stables. After copying all new scripts and the
manifest, run server-console `refresh`, then `restart bcc-stables`.

If a previous server-RPC fixture is still `cleanup_pending` with no observable
entity, use a full server restart for the next test. A resource restart alone
does not establish what happened to that unresolved native request.

With an active character outdoors in the default world, use server console:

```text
BccStablesProof spawn <player-server-id> [lifetimeSeconds]
BccStablesProof inspect
BccStablesProof clear
BccStablesProof inspect
```

Lifetime defaults to 300 seconds; optionally supply an integer from 60 to 900.
For migration testing use `BccStablesProof spawn 2 600`. Inspection includes
elapsed/remaining seconds, bounded owner history sampled once per second, and
a terminal `lastCleanup` snapshot with reason and age. Snapshots are lost on
resource restart or replaced by the next cleanup; brief owner changes may be missed.

Wait for the client proof report before inspecting. The fixture is one frozen,
invincible Morgan horse approximately three metres east of the player. It has no
ownership record, inventory, price, mount assignment or progression. This is a
selected creation experiment; a returned handle is not accepted as proof of
correct RedM rendering/network behavior. There is no automatic mode fallback.

Only server console can begin a lease. Clients may acknowledge only that current
lease. Client-lease mode returns a server-chosen spawn position and accepts one
new network entity only after checking its creation event, script metadata, model,
lease marker, owner, bucket and proximity. The client cannot select a model or
bind a preexisting horse. Inspection reports server net ID/owner/script/bucket
plus separate untrusted client observations.

Live RedM returned no script-name metadata for an otherwise matching horse.
Absent/empty metadata is permitted only with all the other lease checks intact;
an explicit different resource name is rejected. This is a development proof,
not production anti-cheat acceptance. Native boolean `1`/`0` results are normalized.
Normal clear, logout, disconnect, default-world exit, five-minute expiry and
resource stop request cleanup. A spawn that never becomes observable remains
reserved for late cleanup, rather than allowing another spawn. Deletion pending
or identity-loss errors are not cleanup passes; inspect before continuing.

Binding refusals now print a `diagnostic=4` snapshot of the individual server
checks before client cleanup removes the candidate. `inspect` retains the last
failure even after the lease expires; it does not treat a snapshot as authority.

Disable the proof again after testing. Native appearance, migration, late join,
restart/orphan cleanup and cancellation behavior require actual live acceptance.

Run offline tests with Python and the `lupa` Lua 5.4 binding available:

```text
python tests/run.py
```

These tests use an isolated fake Core boundary and parse the runtime entry points.
They do not replace FXServer, CFX callback transport or multiplayer/native testing.

## License

See [LICENSE.md](LICENSE.md). Preserve existing attribution and license notices.

The proof now hides/holds the horse while collision loads, applies grounding and
idle reset, then settles before final freeze/reveal. Client output includes
`collisionLoaded` and `settled`; the corresponding report fields are required,
so deploy both proof scripts together. A successful binding and visible model
alone do not establish normal placement/pose.

## Optional route-change proof

With Feather Routing started, an active fixture and its character in the default
world, run server-console `BccStablesProof route_test`. It checks Routing Contract
1 and existing membership, creates an owned route through Routing, briefly joins
the lease source for three seconds, then deletes the route to return the player.
The normal Stables lifecycle monitor should remove the horse for route_changed.
Output separates nativeJoined, fixtureCleared, returnedToDefault and sessionCurrent.
Inspect afterwards for the terminal cleanup snapshot; pending deletion is not a
completed pass. Keep another observer beside the horse to confirm removal.
Routing is optional for other proof commands; no Core/Routing changes are needed.
If owned-route deletion fails, use the opaque ID printed in the error with
`BccStablesProof route_return <routeId>` to retry through Routing. Do not restart
before capturing cleanup diagnostics. This test is console-only and exposes no
new client RPC. All 76 offline tests pass. Live route-change cleanup and player restoration passed; nearby observer confirmed visual disappearance.
## Fixture replay diagnostics

After inspecting an active reported fixture, its owner can run F8
`BccStablesProofReplay duplicate`: both prepared and bind should reject conflict.
After cleanup, F8 `BccStablesProofReplay stale` reuses the last retired identity:
both routes should reject stale_proof while an active character is selected.
The retired record survives normal character handoff but is lost on resource
restart. Both commands use Core callback RPC and never execute spawn/initialization
from the result. Inspect server state before/after; unexpected success is FAIL.
Wait for each command to finish before another action. These diagnostics do not
prove network-ID reuse protection or in-flight session replacement. Suite passes
79/79 offline cases; live duplicate/stale replay rejection and subsequent console cleanup passed.
## Unfinished-spawn cancellation diagnostic

F8 `BccStablesProofHold` arms a one-use ten-second pause before the next client
fixture bind. Arm on the same client whose server source ID receives the console
spawn. On the binding-paused message, log out to character selection within ten
seconds. After twelve seconds inspect on the server, then inspect again fifteen
seconds later: expect empty with session cleanup and no late fixture. Capture the
client's paused-spawn-cancelled message. The unbound horse is hidden/frozen and
not yet initialized. `BccStablesProofHold cancel` disarms an unused pause. Normal
binding resumes if no cancellation occurs. No new server RPC or Core changes.
82 offline tests pass. Live pending-bind logout cancellation passed: client skipped bind/report, server cleared session_leaving and later inspections remained empty.
## Purchase-operation foundation

server/operations.lua implements pure horse-purchase rules: immutable server terms,
stable Economy request keys, original-bound payment/refund validation, creation
fencing before compensation and terminal/reconciliation replay refusal. It makes
no external calls or persistent changes. Expected revision checking is a rule;
SQL locks/CAS and a repository still need implementation before concurrency or
restart recovery is provided. Gameplay/purchases remain unavailable.

The authoritative PURCHASE_OPERATION_SCHEMA.md in gameplay-resource-docs records
the proposed owned tables and transaction boundaries; no schema is auto-installed
by this slice. Stables still requires Core only (Toolkit for the optional native
proof). Server-console BccStablesOperationSmokeTest should pass 6/6 with no DB,
payment or horse mutations. The complete offline suite passes 94 cases.

Deploy fxmanifest.lua and server/operations.lua together, run server-console
refresh before restart bcc-stables, then run BccStablesOperationSmokeTest and
BccStablesContractSmokeTest. Both should pass 6/6. No config change required.
## Persistence foundation (current)

Stables now requires feather-mysql as well as Core. Startup imports its DB library,
waits for readiness and applies the owned 001_purchase_foundation migration before
registering routes. This creates fs_schema_migrations, fs_character_stables,
fs_operations, fs_horses, fs_horse_history and fs_outbox. Pending DDL intent can
resume; checksum drift, unknown versions, untracked preexisting domain tables and
missing applied tables fail closed. No tables are dropped or legacy data imported.
Do not edit an applied migration; add a new migration for later schema changes.

Internal Repository.Reserve/Get/Advance provide saved operation snapshots,
character-row capacity serialization, immutable-term replay/conflict checks,
revision CAS and uncertain-operation retention. Preliminary local horse fulfillment
has been removed: fulfilled/compensation_pending/refunded advances now return
assets_settlement_unavailable until Assets-backed settlement exists. The pure rule
model remains preliminary; its local horse/fence evidence is not production
authorization. These functions expose no purchase export/RPC. Receipt content must originate from
a trusted Economy service result, never a client-supplied receipt. The outbox is
stored but not dispatched. No payment/recovery worker or paid gameplay is enabled.
Database loss latches failure until dependency-order restart. Schema readiness is
visible in BccStablesStatus; ownedHorseLimit defaults to 3 (integer 1..100).

Deploy fxmanifest.lua, config.lua (merge ownedHorseLimit and retain proof settings),
server/operations.lua, server/migrations.lua, server/persistence.lua,
server/repository.lua, server/foundation.lua and server/main.lua. Run server-console
refresh before restart bcc-stables because new scripts/import/dependency were added.
Then BccStablesPersistenceSmokeTest should pass 7/7, BccStablesOperationSmokeTest
6/6 and BccStablesContractSmokeTest 6/6. Restart Stables again: status should show
schemaVersion=1/applied=0, persistence smoke 7/7. On F8 of a client with an active
character, BccStablesClientSmokeTest should pass with gameplayAvailable=false.
Startup writes schema/ledger; smoke tests create no player/horse/purchase records.
The suite passes 117 offline cases with modeled SQL/CFX; live SQL/restart/row-lock
concurrency and financial recovery acceptance remain pending. No manual SQL needed.
Live checkpoint, 2026-10-22: initial schemaVersion=1/applied=1 and persistence
smoke 7/7 passed. After explicit Stables restart, applied=0 and persistence 7/7
passed again. Operation/foundation smoke both passed 6/6; client session RPC passed
with gameplayAvailable=false. Entity proof was disabled. Repository write/race/
recovery and actual financial/item delivery acceptance remain pending.
## Isolated repository SQL proof

Temporary config repositoryProof=true enables console-only
BccStablesRepositoryProof run/inspect/clear. Keep entityProof.enabled=false.
The fixture uses a fixed synthetic character and exact proof.repository terms;
it never uses a server player ID or F8, submits money or creates owned/native
horses. Run races the final capacity slot, tests replay/conflict/rollback and
retains an unpaid intent for restart inspection. Cleanup rechecks known payloads
under locks and refuses receipts or unexpected horse/history/outbox data.

Deploy fxmanifest.lua, config.lua, server/repository.lua and
server/repository_proof.lua; run refresh before restart bcc-stables. With
ownedHorseLimit=3, run BccStablesRepositoryProof run and wait for run_complete.
Expect one admission/one capacity refusal and retained rows=3/reserved=2/
paymentPending=1. Restart Stables and inspect the same retained data, then clear
and inspect empty. Set repositoryProof=false and restart after confirmed cleanup.
Do not enable payment workers with leftover proof reservations. Schema migration
001 is unchanged. All 127 offline cases pass; live proof acceptance is pending.
Full procedure and limits are in authoritative REPOSITORY_SQL_PROOF.md.
Live repository proof accepted, 2026-10-22: two overlapping requests produced one
admission/one capacity refusal; replay/conflict, synthetic-row rollback, stale
revision and unsafe cancellation refusal passed. Three reservations (two reserved,
one unpaid pending intent) survived explicit Stables restart. Exact cleanup
removed three operations and subsequent inspect was empty. No funds/items/owned
horses were created. Set repositoryProof=false and restart after cleanup. Full
server restart and actual financial/fulfillment recovery remain pending.


Controlled route-change testing now has console-only native route_test/route_return
helpers through Feather Routing. Deployment/live acceptance pending; no schema or
RPC change. Keep current test switches/selected Morgan across remaining tests,
with an empty call slot between gates. See the native calls document.


Console-only BccStablesNative drain now supports controlled pre-restart cleanup
and blocks dispatch until restart, preserving selection/configuration. Live
acceptance is pending; arbitrary restart/crash reconciliation remains separate.
