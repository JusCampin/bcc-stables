# Feather integration progress

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
