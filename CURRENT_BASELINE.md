# Current Project Baseline

## Status

This document is the concise authority for what the project implements today.

The active game is a Windows 95-style desktop shell containing deterministic bounded colony-location windows. Colonists, locations, resources, needs, work, travel, buildings, and construction are authoritative simulation records independent of open presentation windows.

The streamed infinite-world prototype remains in the repository as dormant legacy code. It is not the configured game and must not be expanded unless a task explicitly reactivates it.

## Active Runtime

```text
project.godot
  → scenes/Main.tscn
	→ scripts/main.gd
	  → WindowedColonyState
	  → DesktopShell
	  → DesktopWindow instances
	  → JobLocationView projections
```

`project.godot` configures `res://scenes/Main.tscn`. The active scene does not instantiate legacy `WorldState`, `ChunkManager`, `ColonistManager`, node-based `Colonist`, or `ResourceStockpile`.

## Implemented Player Loop

1. Start a new game or load the single active save slot.
2. Inspect and settle the deterministic home location.
3. Assign each colonist one exclusive role: Woodcutting, Mining, Foraging, Hauling, Construction, or Unassigned.
4. Colonists automatically select compatible local work. Active harvesting is role-driven, not player-designation-driven.
5. Gathering marks authoritative resource records harvested/depleted and creates physical location-owned piles.
6. Haulers reserve, pick up, carry, and deposit piles into home camp storage, remote entry-cell consolidation, or completed Supply Cache capacity.
7. Colonists consume eligible Food when critically hungry.
8. If no eligible Food exists, transient Hunger recovery permits only Food-producing Foraging or loose-Food Hauling; unrelated work remains blocked.
9. Low Rest triggers ground sleep until Rest reaches its current target.
10. Scouts discover deterministic Woodland, Rocky, Forage-Rich, or General locations.
11. Retained locations remain authoritative whether or not their windows are open. Colonists may travel between them.
12. A retained remote with a present colonist may be claimed as an outpost.
13. Claimed applicable locations may construct a Supply Cache.
14. Floors, walls, doors, and windows may be designated and completed by Construction workers.
15. Location windows may be minimized or closed without stopping simulation.
16. Save/load restores authoritative state and reconstructs transient work and presentation.
17. Each location window projects recent completed gathering, current resource placement, worker roles, and a conservative production status.

The game currently has no durable progression goal, upgrades, earned automation, or offline-progress contract.

## Active Ownership

| Owner | Active responsibility |
|---|---|
| `WindowedColonyState` | Phase, seed, `_simulation_time`, time scale, authoritative colonist dictionaries, roles, needs, work coordination, request routing, save orchestration |
| `LocationRegistry` | Bounded locations, generated terrain/resources, lifecycle and claims, presence, physical piles, resource reservations/pickup, camp/entry storage semantics, Food eligibility and consumption |
| `ScoutingCoordinator` | Scouting records, duration, progress, discovery seed |
| `LocationTravelCoordinator` | Abstract routes, distance, duration, progress, departure records |
| `LocationConstructionCoordinator` | Supply Cache placement, building records, material/worker assignment, progress, formal storage, persistence |
| `LocationConstructionState` | Structural floor/wall/door/window sites, material reservation/consumption, worker reservation, progress, completed structure records, persistence |
| `LocationTraversalResolver` | Local paths, traversal validity, completed-structure passability |
| `LocationProductionTracker` | Bounded transient history of completed gathering events and recent per-location throughput |
| `SaveGameService` | Active windowed document validation and file I/O; separate retained legacy save support |
| `main.gd`, `DesktopShell`, `DesktopWindow` | Presentation lifecycle, taskbar, focus, window geometry, request translation |
| `JobLocationView` | Reconstructible location projection, pan/zoom, construction preview and input translation |

Simulation is authoritative. Presentation reads defensive snapshots and sends requests.

## Locations and Resources

- Every generated location is a deterministic `32 × 32` map containing terrain, three spawn cells, one entry/exit cell, a camp-storage cell, and 93 generated resource records.
- Resource identities are stable coordinate-derived ids such as `tree:x:y`.
- Location types bias the fixed resource mix without changing location dimensions.
- Lifecycle values are `HOME`, `DISCOVERED`, `RETAINED`, `DEPLETED`, and `DISCARDED`; claiming is separate metadata.
- A colonist is exactly one of present in one location, scouting, or travelling.
- Resources never transfer between locations. Remote production remains remote.
- Gathering creates loose physical piles. Hauling uses authoritative pile reservation, pickup, carry, and deposit.
- Home deposits without formal storage use the home camp cell. Remote fallback deposits consolidate at the entry cell.
- Completed Supply Caches provide 100 units of local Wood/Stone/Food capacity.

Known inconsistency: remote entry-cell Food is reported as loose by summaries while `LocationRegistry` currently considers it eligible for consumption. This is unresolved follow-up work.

## Production Summaries

Location production summaries are read-only analytics projections:

- only completed authoritative gathering records gross Wood, Stone, or Food production;
- hauling, deposits, eating, reservations, and construction consumption do not count as production;
- the tracker retains a bounded rolling 60-simulation-second event history per location;
- displayed rates are historical recent throughput, not forecasts or resource grants;
- stored, loose, and carried values are read from current authoritative state;
- role counts use authoritative location presence and colonist records;
- status is conservatively `Producing`, `Idle`, or `No workers`;
- tracking continues without an open location window;
- recent history resets on load and new game and is not saved.

The known remote entry-cell Food classification remains visible as loose even though it is consumable.

## Needs

Hunger and Rest are mutable values inside authoritative colonist records owned by `WindowedColonyState`.

- Hunger decays by the common scaled simulation delta.
- At Hunger `25` or below, a colonist attempts to consume one eligible Food.
- Successful eating consumes exactly one Food and restores `30` Hunger after the current one-second eating activity.
- Failed eating enters transient Hunger recovery. Impossible consumption is not retried until the registry reports eligible Food.
- A Foraging colonist may gather Food-producing resources during recovery.
- A Hauling colonist may haul only loose Food during recovery.
- Other roles and unrelated work remain blocked while critically hungry.
- At Rest `20` or below, a colonist sleeps on the ground and recovers toward `80`.
- Hunger has deterministic priority over starting Rest recovery.

Hunger recovery state, eating activity, sleeping activity, targets, and timers are transient and are not saved. Beds, schedules, meals, health damage, death, and mood are not implemented.

## Construction

### Structural construction

`LocationConstructionState` owns floors, walls, doors, and windows.

| Piece | Cost | Required work |
|---|---:|---:|
| Floor | 1 Wood | 2 |
| Wall | 2 Wood | 4 |
| Door fixture | 3 Wood | 5 |
| Window fixture | 2 Wood | 4 |

Normal completion requires valid placement, available and reserved local materials, a Construction-role worker reservation, material consumption on initial work, and sufficient ordinary progress. The active location view has no Enter-to-complete command. `request_debug_complete_construction()` remains only as explicit debug/validator setup.

Roof definition and save-shaped roof records exist for compatibility, but roof placement is deferred and is not active player functionality.

### Supply Cache

`LocationConstructionCoordinator` separately owns the active Supply Cache:

- `1 × 1` footprint;
- cost: `20 Wood`;
- required work: `25`;
- valid only at claimed locations through the active placement flow;
- transient worker/material assignment;
- material consumption on first work;
- 100 units of shared local Wood/Stone/Food capacity after completion;
- authoritative building contents and progress persist.

`campfire`, `cabin`, and `storehouse` definitions remain in the shared definition registry, but the active windowed UI exposes only Supply Cache placement and their legacy warmth/shelter/storage effects are not active windowed gameplay.

Experimental procedural-building research under `experimental/procedural_building_research/` is isolated from production authority.

## Time

`WindowedColonyState._simulation_time` is the active authoritative clock.

- Supported scales are pause, `1×`, `2×`, and `4×`.
- Active scouting, travel, needs, movement, gathering, hauling, and construction receive the same scaled delta.
- One simulation second projects as one displayed minute.
- The taskbar clock is presentation only.
- No active day/night gameplay effects exist.
- Closing or minimizing windows does not alter time advancement.

Legacy `TimeState` is not the active clock.

## Desktop Lifecycle

The desktop shell is presentation architecture, not an operating-system economy.

- Taskbar and Start menu own no simulation state.
- `Main` owns live window tracking, lookup cleanup, lifecycle routing, focus, and z-order.
- `DesktopWindow` owns draggable normal geometry and maximize/restore geometry.
- Minimizing a location suspends its projection only; simulation continues.
- Restoring refreshes the location view from current authoritative state.
- Closing removes taskbar records, lookups, focus references, and live-window tracking, then frees presentation.
- Reopening creates a fresh projection from authority.
- Window focus, position, size, open state, minimized/maximized state, taskbar entries, rendering suspension, pan, and zoom are not saved.

Already-maximized windows do not dynamically refit after a later viewport resize.

## Active Save Boundary

| Property | Current value |
|---|---|
| Schema | `windowed_colony` |
| Current version | `4` |
| Accepted versions | `3`, `4` |
| Path | `user://windowed_colony_v3.json` |
| Slots | One |

The version/path mismatch is historical and remains unresolved.

Persisted state includes the settled phase, seed, simulation time/scale, primary settlement id, full generated location records, terrain/resources, piles, claims, presence, Supply Cache records and contents, structural construction, colonist identity/role/needs/location, scouting sequence, active scouting, and active travel.

Reconstructed/transient state includes active local work, movement paths/interpolation, targets, progress timers outside persisted owner progress, worker/material/capacity reservations, Hunger recovery, presentation windows, geometry, focus, taskbar state, rendering suspension, pan/zoom, and visual caches.
Recent production-event history and derived rates are also transient and restart empty after load.

Current limitations:

- writes replace the target file directly rather than using an atomic temporary-file swap;
- saves are rejected while any colonist carries a non-empty payload;
- validation is owner-focused rather than a complete hostile-document proof;
- only the `SETTLED` phase is accepted;
- user-facing save/load failure feedback is limited;
- complete location records increase save size.

## Active, Legacy, and Experimental Index

| Classification | Systems |
|---|---|
| Active production | `scenes/Main.tscn`, `scripts/main.gd`, `WindowedColonyState`, `LocationProductionTracker`, desktop shell/windows, location registry/coordinators, structural construction, traversal, Supply Cache, `JobLocationView`, windowed save |
| Active shared infrastructure | Bounded generation reuse of `WorldGenerator`, `TerrainConfig`, prop spawn helpers, procedural resource visual configuration/cache, building definitions |
| Active compatibility | Windowed version-3 load compatibility; roof-shaped structural persistence fields; retained legacy save functions inside `SaveGameService` |
| Dormant legacy | `scenes/legacy/WorldMapMain.tscn`, `scripts/legacy/`, legacy `WorldState`, `ChunkManager`, node-based `Colonist`/`ColonistManager`, `ResourceStockpile`, old streamed-world UI and building effects |
| Experimental | `experimental/procedural_building_research/`, `experimental/procedural_creature_research/` |
| Debug/validation | `scripts/debug/`, explicit construction debug completion, gallery and focused validator scenes |
| Unused/stale | Validators or overlays tied only to the old streamed-world scene; they must not be treated as active coverage |

Dormant legacy systems must not be extended for active gameplay unless a task explicitly reactivates them.

## Completed Foundation

- F01: failed eating no longer permanently locks Food-producing work.
- F02: production Enter input no longer bypasses structural construction authority.
- F03: minimize/restore/maximize/close/focus/taskbar lifecycle is complete and presentation-only.

These are implemented foundations, not active defect entries.

## Current Risks and Limitations

- `WindowedColonyState` coordinates many active systems and is under growing responsibility pressure.
- `JobLocationView` remains a broad presentation class.
- Role-driven harvesting has no explicit work designation or priority layer.
- There is no durable progression goal or deeper economic differentiation beyond recent location throughput.
- Remote entry-cell Food classification conflicts with consumption eligibility.
- Local movement/progress is stepped simulation and is not safe to replace with one large offline delta.
- Full location records increase save size.
- Save replacement is non-atomic.
- Save requests fail during carried payloads.
- Standalone-building authority is transitional: Supply Cache is active while other definitions are not connected.
- There is no offline simulation contract or general user-facing notification system.
- Already-maximized windows do not refit dynamically after viewport resize.

## Immediate Roadmap Boundary

The intended direction is a Melvor-style idle colony-management game in which live colony simulations continue authoritatively across multiple location windows.

Near-term principles:

- visible simulation remains authoritative;
- idle summaries project simulation rather than replace it;
- worker and location decisions matter more than manual clicking;
- locations become economically distinct;
- buildings become functional workplaces;
- automation is earned;
- offline progress waits for a bulk-simulation contract;
- operating-system breakout remains later narrative progression.

**I01 — Location production summaries** is now implemented as a transient read-only projection over live authoritative gathering. Offline progress and production forecasting remain deferred.
