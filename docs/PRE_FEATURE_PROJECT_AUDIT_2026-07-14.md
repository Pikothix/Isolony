# Pre-Feature Project Audit

Date: 2026-07-14

Classification: Documentation / Architecture Audit / Performance Investigation

## Executive Verdict

The repository parses under Godot 4.7 and both the configured windowed main scene and the retained legacy streamed-world scene start headlessly. The configured game is the windowed colony in `scenes/Main.tscn`; the streamed chunk world is retained in `scenes/legacy/WorldMapMain.tscn` and is not instantiated by the active main scene.

The project is not yet safe to treat as a clean pre-feature baseline. Of the two audited active-windowed simulation defects, A-01 is resolved by Windowed Colony Save Version 4; A-02 remains open:

1. Resolved: floor, wall, door, and window construction authority now persists through owner-level structural export/import in Windowed Colony Save Version 4.
2. A Supply Cache worker assignment has no runtime release/reassignment path. If the assigned colonist changes role, starts scouting, or travels after construction begins, the incomplete building can remain permanently assigned and unavailable to other workers.

The older streamed-world simulation has explicit authority and balanced transaction paths for the audited resource flows, subject to its already-documented temporary split resource authority and non-transactional live loader. The active windowed simulation also keeps presentation out of authority and balances its ordinary pile/haul and cell-construction transactions. The blockers are missing lifecycle/persistence integration, not visual ownership.

## Scope And Runtime Topology

Two simulation stacks coexist intentionally:

| Stack | Entry point | Status | Persistence |
|---|---|---|---|
| Windowed bounded-location colony | `scenes/Main.tscn`, configured in `project.godot` | Active game | Separate `windowed_colony` schema, version 4 |
| Streamed infinite/chunk world | `scenes/legacy/WorldMapMain.tscn` | Retained legacy game/prototype | Legacy schema, version 2 |

They share definitions and selected generation/presentation helpers, but do not share runtime simulation records. This prevents duplicate live authority. It also means a validator or architecture statement must identify which stack it covers; passing a legacy validator does not validate the configured game.

## Findings

### A-01 — High — Active cell-construction state is lost on save/load

Status (2026-07-14): Resolved. Version 4 adds owner-level `LocationConstructionState.export_state()` / `import_state()`, complete staged validation, derived-index reconstruction, and focused structural persistence validation. Historical version 3 documents load with explicitly empty authored structural state.

`LocationConstructionState` owns authoritative construction sites, progress, worker reservations, completed floors/walls, and wall fixtures. `WindowedColonyState.export_save_data()` exports only `LocationConstructionCoordinator.export_state()` under `location_construction`; that coordinator owns placed Supply Cache building records, not the newer cell-construction owner. `import_save_data()` then creates a fresh empty `LocationConstructionState`.

Consequences:

- Designated floor/wall/door/window sites disappear after load.
- Consumed resources and partial work in those sites disappear with the site.
- Completed floors, walls, doors, and windows disappear.
- Traversal changes caused by structures disappear.
- Derived presentation correctly reconstructs the empty imported authority, so the loss can look like a rendering issue even though it is persistence loss.

Evidence: `scripts/simulation/windowed_colony_state.gd:572-587`; `scripts/simulation/location_construction_state.gd` has no export/import boundary.

Required follow-up: extend the versioned windowed save contract through the existing `LocationConstructionState` owner. Do not move these records into UI, presentation, or `LocationConstructionCoordinator` merely to serialize them.

### A-02 — High — Supply Cache construction can retain a stale worker forever

Resolved 2026-07-14: Supply Cache assignment is now explicit before local construction travel, the colonist task references the exact building id, all activity cancellation/removal paths release through `LocationConstructionCoordinator`, and an exact-task validity audit clears only provably stale ownership. Assignment and unconsumed material-reservation ids remain transient across save/load; consumed materials and progress are unchanged by release.

At audit time, `LocationConstructionCoordinator.advance_worker()` assigned `assigned_worker_id`, consumed reserved local materials on first work, and cleared the assignment only on completion or import. `WindowedColonyState._cancel_activity()` released cell-construction and haul reservations but did not notify the Supply Cache coordinator. Candidate selection excluded buildings assigned to another colonist.

The failing case was a colonist role change, scouting departure, or travel departure calling `_cancel_activity()`: the incomplete Supply Cache remained assigned, its already-consumed materials remained in the site as intended, and no other construction colonist could resume it.

This is a reservation-lifecycle failure rather than a refund-rule issue. P05 explicitly defers building cancellation/refunds, but ordinary worker abandonment still needs a release or reassignment path.

Evidence: `scripts/simulation/location_construction_coordinator.gd:48-67`; `scripts/simulation/windowed_colony_state.gd:295`; `scripts/simulation/windowed_colony_state.gd:468-476`.

Required follow-up: add a focused coordinator-owned worker-release operation and invoke it from existing activity/lifecycle cleanup. Preserve consumed-resource state and building ownership.

### A-03 — Medium — WorldSpace validator and import policy disagree

Status (2026-07-14): Resolved as an implementation defect. Missing legacy `world_space_id` fields continue to default to `surface`, supported interior ids remain valid when backed by incoming `WorldState` interior records, and explicit empty or unsupported ids now reject in `SaveGameService` before any legacy load owner mutates. `ColonistManager` repeats the check before population replacement, and direct `Colonist.import_state()` enforces the same owner contract. The focused validator now covers legacy defaulting, supported-interior preservation and round trip, unsupported-id rejection without mutation, save-service preflight, and manager preflight atomicity.

At audit time, `world_space_phase1_validation.gd` failed because it required a direct `Colonist.import_state()` call with `world_space_id = "cave"` to reject with `unsupported_world_space_id`. The colonist and manager import helpers instead normalized an unsupported id to `surface`. This was also inconsistent with `docs/SAVE_BOUNDARY.md`, which says unsupported non-surface values are rejected unless backed by an interior.

The current full legacy load validates spatial WorldSpaces earlier in `WorldState`, reducing normal save-path exposure. The direct owner contract and its validator nevertheless disagree, and silent normalization can conceal corrupt identity if the owner is used independently.

Evidence: `scripts/debug/world_space_phase1_validation.gd:54-67`; `scripts/entities/colonist.gd:538-595`; `scripts/entities/colonist_manager.gd:224-229`.

Required follow-up: the architect should choose reject-versus-normalize semantics, then align owner import, manager import, documentation, and validation.

### A-04 — Medium — Cliff-rim validator is stale and can return a false-green exit

`cliff_rim_projection_validation.gd` preloads the active `scenes/Main.tscn`, casts its root to `Node2D`, and expects a `ChunkManager` child. The active scene is now a `Control`-rooted windowed game with no `ChunkManager`. The run emitted `Required object "rp_child" is null` at the attempted `add_child`, printed no PASS marker, yet exited 0 when bounded by `--quit-after`.

This validator currently provides no cliff-rim coverage and cannot be judged by process exit alone.

Evidence: `scripts/debug/cliff_rim_projection_validation.gd:7-18`; `scenes/Main.tscn`.

Required follow-up: point the validator at the retained legacy scene or a focused fixture, and ensure setup failures call `quit(1)`.

### A-05 — Medium — Legacy live load remains non-transactional

Legacy `SaveGameService.apply_save_data()` preflights top-level structure but then mutates generator, `WorldState`, `ChunkManager`, and colonists sequentially. A later owner failure leaves earlier owners replaced. A changed seed/config also does not rebuild already-loaded chunks immediately. This is accurately documented and is not a new regression, but it remains a blocker to treating live load as production-safe.

Evidence: `scripts/simulation/save_game_service.gd:52-85`; `docs/SAVE_BOUNDARY.md`.

The active windowed loader is materially safer: registry, Supply Cache construction, and colonists are staged before replacement. Its missing cell-construction section is A-01.

### A-06 — Medium — Remote entry piles have conflicting storage semantics

Remote hauling consolidates output at the remote entry cell with `stored = false`. Resource summaries therefore report it as loose, and the location ADR says entry-cell consolidation is not settlement storage. `LocationRegistry.consume_stored()`, however, treats any enabled remote entry-cell pile as eligible stored inventory. A hungry remote colonist can consume Food that the authoritative record and UI classify as loose.

There is still one pile owner and one mutation path, so this is not duplicated quantity authority. It is a semantic authority mismatch between classification, UI reads, and consumption rules.

Evidence: `scripts/simulation/location_registry.gd:114-120`; `scripts/simulation/windowed_colony_state.gd:338-364`; `docs/ADR_SCOUTING_TRAVEL_AND_LOCATION_NETWORK.md`.

Required follow-up: explicitly decide whether remote entry consolidation is consumable temporary storage. Make the record flag, totals, UI language, ADR, and consumption predicate agree.

### A-07 — Low — Windowed saving deliberately rejects in-flight payloads

Version 3 validation rejects any colonist with a carried amount greater than zero. A save request during the post-pickup haul phase fails rather than persisting or reconstructing the payload. This prevents duplication/loss, but it is a user-visible availability restriction and differs from legacy version 2, which reconstructs carried items at their pickup cell.

Evidence: `scripts/simulation/save_game_service.gd:180-184`; `scripts/simulation/windowed_colony_state.gd:572-576`.

No balance defect was found in this rule. It should remain explicit in UI/documentation until a different persistence contract is approved.

## Ownership Audit

### Active windowed game

| Data | Owner / modifier | Readers / projection | Saved |
|---|---|---|---|
| Game phase, seed, time, roster, needs, roles, carried payload coordination | `WindowedColonyState` | `main.gd`, location/colonist windows | Mostly; carried payload is rejected |
| Location identity, terrain/resources, lifecycle, presence, physical piles and pile reservations | `LocationRegistry` | coordinator, traversal, UI, location view | Yes, excluding reservation map semantics |
| Scouting records | `ScoutingCoordinator` | state and route UI | Yes |
| Travel records | `LocationTravelCoordinator` | state and route UI | Yes |
| Supply Cache records, contents, capacity and capacity reservations | `LocationConstructionCoordinator` | state, traversal, location view, inspector | Building/content state yes; reservations no |
| Floor/wall/fixture sites and completed structure cells | `LocationConstructionState` | state, traversal, location view | **No — blocker A-01** |
| Traversability and paths | `LocationTraversalResolver` | state/colonist coordination | Derived, correctly not saved |
| Windows, pan/zoom, hover, previews, sprites and labels | Presentation/UI scripts | Player only | Correctly not saved |

The simulation remains authoritative, UI requests actions, and presentation reconstructs state. No visual node was found mutating authoritative resource, construction, travel, or need data.

### Retained streamed-world stack

| Data | Owner / modifier | Important boundary |
|---|---|---|
| Construction, storage components, orders, zones, items, interiors, connections, time coordination | `WorldState` | Simulation authority; presentation reacts to signals |
| Compatibility totals and generic reservations | `ResourceStockpile`, owned by `WorldState` | Bootstrap/legacy path subordinate to storage components |
| Generated base rules | `WorldGenerator`, `TerrainConfig` | Deterministic reconstruction inputs |
| Loaded chunks, manual tile/depletion deltas and live resource index | `ChunkManager` | Broad accepted owner; resource authority remains temporarily split |
| Population lifecycle | `ColonistManager` | Imports/replaces colonist nodes and audits stale reservations |
| Persistent individual colonist state and transient job execution | Each `Colonist` | Requests mutations from `WorldState` |
| UI and projections | Legacy main, panels, visual nodes | Read/request only |

The known split between deterministic resource data, `ChunkManager`, and loaded `ResourceNode` remains the largest legacy ownership compromise. It is documented, bounded, and not duplicated with the active windowed stack at runtime.

## Resource And Reservation Balance

### Active windowed pile hauling

| Transition | Quantity/reservation result | Audit result |
|---|---|---|
| Gather success | Resource delta is marked; exact yield is merged into one location-owned pile | Balanced |
| Reserve before pickup | Pile owner/amount and optional Supply Cache capacity are earmarked | Balanced |
| Cancel/failure before pickup | Capacity and pile reservations are released; pile amount is unchanged | Balanced |
| Pickup | Exact reserved amount leaves the pile and enters colonist carried payload | Balanced |
| Cancel/failure after pickup | Capacity is released and exact carried amount is recreated/merged at the original cell | Balanced |
| Deposit to Supply Cache | Capacity reservation is consumed and exact payload enters building contents | Balanced |
| Deposit to home camp/remote entry fallback | Exact payload is merged into a location pile | Balanced, subject to semantic finding A-06 |
| Save during carry | Save is rejected before write/import | Safe but restrictive |
| Load | Pile/capacity reservations reset and colonists resume idle | Balanced for accepted documents |

The ordinary haul code keeps quantity in exactly one of pile amount, carried payload, or completed storage contents. No duplicate quantity mutation was found.

### Active cell construction

| Transition | Result | Audit result |
|---|---|---|
| Reservation | Site and complete cost reserve atomically | Balanced; validated |
| Invalid progress | No progress or resource spend | Balanced; validated |
| First valid progress | Reserved resources consumed once | Balanced; validated |
| Later progress | No repeated spend | Balanced; validated |
| Release before first progress | Full availability restored | Balanced; validated |
| Reassignment after consumption | No second cost | Balanced; validated |
| Cancel before consumption | Reservation released | Balanced; validated |
| Cancel after consumption | No refund, per current rule | Balanced and documented |
| Save/load | Entire owner omitted | **Not balanced across persistence; A-01** |

### Active Supply Cache construction

Placement is validated before mutation. Full local cost is reserved and consumed atomically on first worker progress, and storage capacity is derived only from completed enabled records. Import clears transient worker/material/capacity reservations. Cancellation/refunds are intentionally deferred. Worker abandonment/reassignment is not balanced because of A-02.

### Retained streamed-world transactions

- Harvest completion prepares the item before committing depletion, then commits the ground item and removes intent. Failed preflight or depletion commit does not publish a partial item.
- Haul reservation binds worker, item snapshot, destination, and storage capacity. Pickup, deposit, release, drop, and stale-owner cleanup retain the item or restore it at a deterministic cell.
- Legacy save exports an in-flight carried payload as the original ground item and clears transient haul/capacity reservations on import.
- Construction reserves delivered plus stored/bootstrap inputs without double counting, consumes the undelivered allocation once on first valid progress, releases unconsumed allocations on cancellation/failure, and intentionally does not refund consumed work materials.
- Storehouse contents are authoritative once a storage component exists; legacy `ResourceStockpile` remains an explicit bootstrap/save-compatibility service rather than a parallel normal-game store.

The focused Phase 2 validation passed construction placement/completion, harvest reservation/completion, stockpile-zone indexing, haul reservation/pickup/deposit, and WorldSpace scoping. Complete hostile-document or rollback behavior is not covered and remains A-05.

## Save/Load Audit

### Windowed version 3 / current version 4

Strengths:

- Separate schema and filename from legacy saves.
- Whole-document validation before replacing active owners.
- Registry and Supply Cache coordinator imports are staged.
- Presence membership and scouting/travel exclusivity are validated.
- Supply Cache contents and claim metadata round-trip in the focused validator.
- Unresolved carried payloads are rejected, preventing silent loss or duplication.

Gaps:

- Version 3 cell construction was absent (A-01); version 4 resolves this with a staged owner-level section.
- Validation is structural rather than exhaustive for terrain, pile fields, role need ranges, building fields, and coordinator record internals.
- Save availability during hauling is not surfaced by the audit harness as a UI contract.
- `docs/SAVE_BOUNDARY.md` retains historical version sections and now documents the version 4 cell-construction owner and compatibility behavior.

### Legacy version 2

The saved boundary covers generator state, time, compatibility totals, construction/storage contents, harvest/mining intent and results, zones, ground items, interiors, connections, chunk deltas, and persistent colonist records. Transient jobs, paths, reservations, previews, and projections are correctly omitted or reconstructed. Remaining risks are the non-transactional apply order, mixed loaded chunks after generation changes, code-backed content compatibility without a separate content version, and limited hostile-data validation.

## Performance Investigation

No tuning was changed. Findings distinguish measured current cost from scaling risk.

### Measured legacy streaming sample

Existing current profile logs in `.codex_tmp/chunk_profile.log` show the first five sampled chunk loads at approximately 6.1–9.5 ms each. Generation accounted for roughly 4.3–6.1 ms and tile writes roughly 1.8–2.7 ms. One elevation-stack sample reached about 2.1 ms. The first sampled resource `add_child`/visual refresh cost was about 4.3/4.2 ms; later samples were usually much smaller. The staged pending resource queue reached 76 in the captured five-chunk sample.

This supports the existing staged-spawn design. It does not establish full-frame performance under long camera travel, dense loaded radii, lighting debug, or many colonists.

### Active bounded-location scaling risks

1. `LocationTraversalResolver.find_path()` sorts the whole open array on every A* expansion.
2. Each traversability query linearly scans the 1,024 terrain records, up to 93 generated resources, building snapshots, construction snapshots, and completed structures. A path expansion calls traversal more than once per neighbor.
3. Construction pointer validation repeats linear terrain/resource/site scans on mouse motion and across every floor-drag target.
4. `main.gd` rebuilds the locations list on every broad `state_changed` signal. With three colonists and few locations this is bounded; it scales with later location/roster growth.
5. The active simulation currently has exactly three colonists and fixed 32×32 maps, so these are future-feature scaling risks rather than demonstrated present stalls.

Before materially increasing colonists, map size, or simultaneous location construction, profile these paths with representative content. Do not optimize them solely from this static audit.

## Validation Results

Environment: Godot 4.7 stable, headless, project-local application data paths.

| Validation | Result |
|---|---|
| Full editor import/parse | PASS, exit 0 |
| Configured `scenes/Main.tscn` startup | PASS, exit 0 |
| Retained `scenes/legacy/WorldMapMain.tscn` startup | PASS, exit 0 |
| `windowed_colony_validation.gd` | PASS, 29 checks |
| `p04_scouting_travel_validation.gd` | PASS, 21 checks |
| `p05_claiming_building_validation.gd` | PASS, 21 checks |
| `location_construction_validation.gd` | PASS |
| `location_construction_work_validation.gd` | PASS |
| `m04_construction_usability_validation.gd` | PASS |
| `location_traversal_validation.gd` | PASS |
| `building_inspector_validation.gd` | PASS |
| `desktop_shell_validation.gd` | PASS, 40 checks |
| `world_space_phase2_validation.gd` | PASS |
| `connection_framework_validation.gd` | PASS |
| `structure_cell_placement_validation.gd` | PASS |
| `world_space_phase1_validation.gd` | PASS after unsupported WorldSpace import repair (A-03) |
| `cliff_rim_projection_validation.gd` | **INVALID**, stale scene/root assumption and false-green exit risk (A-04) |

Repeated headless runs also reported Windows root-certificate-store access errors. These did not affect exit status or local gameplay checks. Several validation scripts reported ObjectDB/resource leaks at process exit; these are primarily harness cleanup defects, but they reduce the usefulness of leak output for detecting runtime lifecycle regressions.

## Documentation Consistency

The architecture documents correctly describe most legacy and P02–P05 ownership decisions. Current top-level sections still begin with the legacy `Main.tscn` node structure even though `project.godot` now points to the windowed scene and the legacy scene moved under `scenes/legacy`. Later appendices describe the active architecture, but the document reads as two simultaneous “current” baselines.

The save document contains sequential historical windowed version sections. Version 4 now covers `LocationConstructionState` separately from the version 3 Supply Cache section.

Recommended documentation follow-up after the blockers are resolved:

- State the active entry point first and label the streamed world as retained legacy.
- Keep separate ownership tables and save contracts for the two stacks.
- Completed: increment the Windowed schema to version 4 for cell construction and document version 3 compatibility.
- Completed: retain the documented WorldSpace rejection policy while allowing only `WorldState`-backed interior ids.

## Pre-Feature Gate

Active construction persistence is now covered by the version 4 focused validator. Features that depend on reliable remote Supply Cache labor remain gated on A-02.

A safe next audit-fix sequence is:

1. Define the versioned persistence contract for `LocationConstructionState` without changing ownership.
2. Add round-trip validation for designated, reserved, partially built, completed, and fixture-converted cells, including resource totals.
3. Add Supply Cache worker release/reassignment validation for role change, scouting, travel, and load.
4. Repair the cliff-rim harness; the WorldSpace policy mismatch is resolved.
5. Re-run the targeted suite and `git diff --check` before declaring the baseline feature-ready.

No gameplay fix, tuning change, refactor, file move, or ownership change was made by this audit.
