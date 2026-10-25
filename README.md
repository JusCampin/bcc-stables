# BCC Stables — Feather development

New RedM Stables resource for Feather Framework, developed on the `feather` branch.
`main` retains the earlier VORP resource until the Feather release; this branch has
no compatibility bridge or legacy database import. Resource version remains0.1.0-dev.

## Current checkpoint — 2026-10-25

Schema9,35 Core RPC routes and3 session subscriptions. The full offline suite passes
998 cases plus SQL snapshot/care/bridge harnesses. Controlled live tests cover
purchase/registration/fulfillment foundations, stored/active lifecycle, recovery,
call/store, riding, short-whistle approach, renewable long-whistle Follow/Stop,
native leading, safe distant replacement, ownership delegation and My Horses UI.
This remains a gated development resource; gameplayAvailable=false is intentional.

The selected Morgan's last explicit readback is stored projectionRevision146 /
Asset revision1 with an empty call slot. Live care target observation passed with
owner and delegated simulators, mounted/leading refusals and re-eligibility after
release. No repeat ownership-transfer setup is needed for that checkpoint.

Care policy1 preserves consumable_haycube/consumable_carrots/consumable_apple,
20/20 capped feed gains and5second interaction. Feeding stays disabled. Existing
horses remain uninitialized; the pure100/100 new-horse seed is not automatically
applied. Active care reservations, interruption handling, committed native core
projection and actual food-definition/initialization integration remain next.
No normal Call/Store/eligibility probe consumes food or writes horse condition.

## Runtime and dependencies

Required: feather-core, feather-mysql, feather-assets and feather-economy. Native
model loading uses feather-toolkit; My Horses loads feather-menu-v2 optionally.
Inventory's durable consumption contract is optional until care integration;
Routing supports explicit native routing proofs. Use public framework APIs:
Assets owns canonical identity/model/status/ownership, Economy owns money, and
Inventory owns item instances and durable consumption receipts.

Deploy complete resource files, preserve server-specific config.lua settings,
then run server-console refresh before restart bcc-stables when scripts/manifest
change. Managed migrations are additive and checksum-guarded; never edit applied
migrations, drop receipt history or delete a fence to retry a value-bearing action.
Schema9 adds empty condition/care journal/slot/effect tables without backfilling horses.

Repo defaults keep purchase, selection, native and proof flags disabled. Controlled
server tests retain selection/call/nativeBehavior and manual outbox settings.
config/care.lua remains enabled=false; setting true is currently refused. Keep
Inventory TrustedConsumptionCallers empty until production care gates pass.

## Player controls

- BccStablesMenu: optional My Horses page, selection, current Call/Store and refresh.
- BccStablesHorseCall: call selected horse, approach nearby current horse or replace
  a distant horse only after confirmed old-entity cleanup.
- BccStablesHorseStore: current-generation cleanup; mounted/unknown occupancy refuses.
- Short whistle approaches; long whistle toggles normal Follow using validated
  current-simulator delegation and bounded renewable tasks.
- Lead through the native horse interaction panel; BccStablesHorseLead is also an
  explicit toggle. Store releases only the exact owner's matching lead/reference.
- BccStablesConditionInspect reads native cores only; BccStablesCareEligibilityProof
  observes the live target without granting feeding or mutating cores/items.

Commands/menus resolve current sessions/selection/ownership server-side. A saved
net ID is never sufficient entity authority. Cleanup uncertainty retains durable
fences; local pending status is not a successful economic outcome.

## Validation and limits

Live acceptance includes guarded call/store replay, native owner migration,
physical disappearance/slot cleanup, mounted/leading occupancy, distant replacement
isolation, menu focus/session ownership, schema upgrades and controlled receipt
recovery. MariaDB care proofs exercised atomic effect/rollback/lost-reply replay,
cancellation and retained consumed-pending fences. The combined Inventory proof
consumed only one isolated disposable item, recovered its receipt and applied
one synthetic local benefit; both domains' fixtures were cleared.

Care target checks use fresh server/canonical identity and a short one-use report
from the current simulator. No idle care polling or control request is added;
reports remain observations, not anti-cheat truth or reusable feed permission.
The pending-care cache assumes one active Stables writer process. Once care is
used, an indexed fence lookup remains sticky until restart; no unsafe cache clear.

Follow migration during an already-running task remains deferred; owner-death
interruption causality remains unverified. Full process-crash/session interruption
coverage, active care lifecycle integration, condition/death gameplay, brush wear,
tack/training/cargo and full purchase UI remain open. Invincibility is retained.
Do not infer those gates from controlled proofs or advertise full horse gameplay.

## Tests

Run tests/run.py with Python and optional lupa Lua5.4. Tests include actual Menu v2
schema validation when the sibling repo is present, modeled CFX/provider/lifecycle
failures and SQLite SQL-shape/transaction harnesses. The Inventory bridge harness
explicitly skips when its sibling checkout is absent. SQLite does not replace
MariaDB lock/isolation or actual native/CFX acceptance.

## Authoritative documentation

The sibling gameplay-resource-docs repository owns the roadmap and detailed
implementation/live evidence. Current checkpoint supersedes historical notes.

- [Master plan](../../feather-scripts/gameplay-resource-docs/bcc-stables/BCC_STABLES_MASTER_PLAN.md)
- [Call controls](../../feather-scripts/gameplay-resource-docs/bcc-stables/HORSE_CALL_CONTROLS.md)
- [My Horses menu](../../feather-scripts/gameplay-resource-docs/bcc-stables/OWNED_HORSE_MENU.md)
- [Normal Follow](../../feather-scripts/gameplay-resource-docs/bcc-stables/NORMAL_FOLLOW_CONTROLS.md)
- [Native leading](../../feather-scripts/gameplay-resource-docs/bcc-stables/NATIVE_LEADING_PROOF.md)
- [Distant calls](../../feather-scripts/gameplay-resource-docs/bcc-stables/AUTOMATIC_DISTANT_CALLS.md)
- [Care policy](../../feather-scripts/gameplay-resource-docs/bcc-stables/HORSE_CARE_POLICY.md)
- [Care repository](../../feather-scripts/gameplay-resource-docs/bcc-stables/HORSE_CARE_REPOSITORY.md)
- [Care bridge proof](../../feather-scripts/gameplay-resource-docs/bcc-stables/HORSE_CARE_BRIDGE_PROOF.md)
- [Care target proof](../../feather-scripts/gameplay-resource-docs/bcc-stables/HORSE_CARE_TARGET_PROOF.md)
