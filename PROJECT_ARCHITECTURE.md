# Active Project Architecture

## Purpose and Scope

This document describes the configured windowed-colony game. It answers how the active project works and where authority resides.

The dormant streamed-world implementation is indexed near the end and is not part of the active runtime. Historical decisions remain in ADRs.

## Runtime Composition

```text
project.godot
  → scenes/Main.tscn
	→ Main (scripts/main.gd)
	  ├─ WindowedColonyState
	  │   ├─ LocationRegistry
	  │   ├─ ScoutingCoordinator
	  │   ├─ LocationTravelCoordinator
	  │   ├─ LocationConstructionCoordinator
	  │   ├─ LocationConstructionState
	  │   ├─ LocationTraversalResolver
	  │   └─ LocationProductionTracker
	  └─ Desktop
		  ├─ WindowLayer
		  │   └─ DesktopWindow instances
		  │       └─ optional JobLocationView/application content
		  └─ DesktopShell
```

The active root is a `Control` desktop, not a streamed map.

## Architectural Rules

1. Simulation owns mutable gameplay state.
2. Presentation reads defensive snapshots and translates input into requests.
3. Requests validate before mutation.
4. Invalid actions do not partially mutate authority.
5. Rendering, window lifetime, focus, and visibility never determine simulation lifetime.
6. Persistence exports authoritative owner state and reconstructs transient execution/presentation.

The common flow is:

```text
UI or simulation decision
  → request
  → owner validation
  → authoritative mutation
  → result/signals
  → presentation refresh
```

## Owner Map

### `WindowedColonyState`

File: `scripts/simulation/windowed_colony_state.gd`

Owns:

- game phase (`MAIN_MENU`, `LOCATION_EVALUATION`, `SETTLED`);
- game seed;
- `_simulation_time` and time scale;
- the three authoritative colonist dictionaries;
- identity, skills, traits, roles, needs, location/cell, carried payload;
- local work decision priority;
- movement/work execution coordination;
- scouting/travel/presence transitions;
- simulation-level request routing;
- save export/import orchestration.

It does not own generated location contents or structural/building records directly. Those remain delegated owners.

Current pressure: it coordinates needs, roles, movement, work, mobility, construction, and persistence. New features should extend focused owners rather than further centralize state.

### `LocationRegistry`

File: `scripts/simulation/location_registry.gd`

Owns:

- stable location identity and display metadata;
- deterministic `Vector2i` network position;
- lifecycle and claim metadata;
- generated `32 × 32` terrain and 93 resource records;
- spawn, entry/exit, and camp-storage cells;
- colonist presence membership;
- physical Wood/Stone/Food piles;
- pile reservation, pickup, merge/deposit, and resource totals;
- local material reservations for construction;
- authoritative consumable-Food eligibility and consumption.

Resources never move between locations. A deposit changes a pile or building inside the same location.

Known inconsistency: a remote entry-cell Food pile remains `stored = false` and therefore appears under loose summaries, while the registry's consumable query accepts it.

### `ScoutingCoordinator`

File: `scripts/simulation/scouting_coordinator.gd`

Owns:

- one scouting record per active scout;
- origin, search type, sequence, deterministic discovery seed;
- skill-scaled duration and elapsed progress.

`WindowedColonyState` owns removal from presence and commits discovery/return.

### `LocationTravelCoordinator`

File: `scripts/simulation/location_travel_coordinator.gd`

Owns:

- traveller and endpoints;
- Euclidean network distance;
- duration clamped to 25–90 seconds;
- elapsed progress and departure time.

It does not move resources. `WindowedColonyState` commits presence removal and arrival at the destination entry cell.

### `LocationConstructionCoordinator`

File: `scripts/simulation/location_construction_coordinator.gd`

Owns the standalone-building record model currently used for Supply Caches:

- placement validation and occupied cells;
- planned/under-construction/completed state;
- cost, material reservation, consumption status;
- worker assignment and progress;
- completed formal storage contents and capacity;
- building export/import;
- derived enclosure projections used by inspection.

The active UI exposes Supply Cache placement only. Other `BuildingDefinition` entries are shared/dormant definitions, not active windowed building effects.

### `LocationConstructionState`

File: `scripts/simulation/location_construction_state.gd`

Owns structural cell construction:

- designated floor/wall/door/window sites;
- requirements and prerequisite relationships;
- resource reservation ids and consumption status;
- Construction worker reservation;
- progress and required work;
- completed floor cells;
- completed wall cells with optional door/window fixture;
- structural export/import and derived occupancy indices.

Normal lifecycle:

```text
designation
  → availability and traversal validation
  → worker reserves site and local materials
  → first valid progress consumes reserved materials
  → progress reaches requirement
  → completed structural record replaces site
```

The active location view cannot debug-complete a site. `request_debug_complete_construction()` remains an explicit validator helper and deliberately bypasses the ordinary lifecycle.

Roof-shaped persistence fields exist, but the roof definition is marked deferred and roof placement is not active.

### `LocationTraversalResolver`

File: `scripts/simulation/location_traversal_resolver.gd`

Owns authoritative local traversal queries:

- cell passability;
- paths and path cost;
- interaction/work-cell reachability;
- completed wall/door/window effects on traversal.

Presentation does not authorize movement.

### `SaveGameService`

File: `scripts/simulation/save_game_service.gd`

Active responsibilities:

- validate the `windowed_colony` document;
- encode/decode Godot vectors for JSON;
- read/write the active file;
- retain version-3 compatibility while current version is 4.

It also retains separate legacy streamed-world save functions. Those functions do not make the legacy game active.

### `LocationProductionTracker`

File: `scripts/simulation/location_production_tracker.gd`

Owns bounded transient observations of completed authoritative gathering:

- location id;
- Wood, Stone, or Food identity;
- positive produced amount;
- authoritative simulation completion time.

`WindowedColonyState._advance_gather()` records an event only after source completion creates or merges the physical output pile. Hauling, deposits, consumption, construction, reservations, intent, and partial work never record production.

The tracker prunes to a rolling 60-second window and a conservative per-location event cap. It owns no resource mutation API, node reference, or saved state.

## Simulation Loop

`WindowedColonyState.advance_simulation(frame_delta)` computes:

```text
delta = max(frame_delta, 0) × time_scale
```

When settled and nonzero:

1. advance `_simulation_time`;
2. advance scouting;
3. advance travel;
4. audit Supply Cache assignments;
5. decay Hunger and Rest;
6. skip local decision execution for away colonists;
7. continue Eating or Sleeping;
8. apply critical Hunger handling;
9. otherwise apply Rest;
10. otherwise advance the exclusive role.

Pause and `1×`, `2×`, `4×` use this common delta. There is no active day/night gameplay system.

## Production Analytics

`WindowedColonyState.get_location_production_summary()` constructs a defensive read-only projection from:

- recent event totals from `LocationProductionTracker`;
- loose/stored piles from `LocationRegistry`;
- formal Supply Cache contents from `LocationConstructionCoordinator`;
- carried payloads and roles from present authoritative colonist records.

The result reports each resource's recent amount, historical per-minute rate, stored, loose, and carried amount; role counts; and `producing`, `idle`, or `no_workers`.

Open windows are not required for event collection. `Main` presents the summary in a compact location accordion, refreshes on relevant state changes and authoritative clock ticks, skips suspended windows, and refreshes immediately on restore/reopen.

## Colonist Work and Needs

### Roles

Roles are exclusive policy values on colonist records:

- Woodcutting;
- Mining;
- Foraging;
- Hauling;
- Construction;
- Scout while scouting;
- Unassigned.

Harvesting is automatic role-driven selection. There is no active player harvest-designation owner.

### Gathering

The state selects compatible reachable resources deterministically, moves the colonist to an interaction cell, advances skill/trait-scaled work, mutates the registry resource record, and creates a loose pile at the source cell.

- Woodcutting: tree and fruit tree → Wood.
- Mining: rock → Stone.
- Foraging: berry bush, fruit bush, or unharvested fruit tree → Food.

Fruit harvesting does not destroy a fruit tree's Wood output. There is no regrowth.

### Hauling

The hauler:

1. selects a compatible unreserved loose pile;
2. reserves up to capacity 8;
3. optionally reserves Supply Cache capacity;
4. moves to and picks up the reserved amount;
5. carries it to the destination;
6. deposits through the registry or building coordinator.

Cancellation restores carried resources to the origin pile/cell. No cross-location cargo exists.

### Hunger

At Hunger `25` or below:

1. attempt to consume one registry-eligible Food;
2. on success, enter one-second Eating and later add `30` Hunger;
3. on failure, set transient `hunger_recovery`;
4. suppress repeated impossible consumption until eligible Food exists;
5. allow Foraging to gather Food or Hauling to move only Food;
6. block unrelated work.

Hunger recovery is runtime-only.

### Rest

At Rest `20` or below, when Hunger has not taken priority, the colonist begins `Sleeping on ground`. Rest recovers at the existing rate until it reaches `80`, then ordinary decisions resume.

Beds, shelter sleep, schedules, health consequences, and death are not active.

## Locations, Scouting, Travel, and Claims

`BoundedLocationGenerator` produces deterministic `32 × 32` locations, three spawn cells, one camp cell, and 93 resources. Search type changes the fixed mix.

Lifecycle:

- `HOME`: primary settlement at `(0, 0)`;
- `DISCOVERED`: temporary discovery result;
- `RETAINED`: kept in the network;
- `DEPLETED`: supported lifecycle ordering/status;
- `DISCARDED`: no longer active.

Claiming is separate from lifecycle. A remote claim requires a retained non-home location and a physically present colonist. Claimed remotes are outposts, not additional primary settlements.

A colonist must be exactly one of:

- present in one location;
- scouting;
- travelling.

## Construction Systems

### Structural pieces

| Piece | Placement | Cost | Work |
|---|---|---:|---:|
| Floor | valid floor cell | 1 Wood | 2 |
| Wall | valid structure cell | 2 Wood | 4 |
| Door | fixture on completed plain wall, `axis_x`/`axis_y` | 3 Wood | 5 |
| Window | fixture on completed plain wall, `axis_x`/`axis_y` | 2 Wood | 4 |

Door/window completion preserves the authoritative wall and writes fixture metadata.

### Supply Cache

| Property | Value |
|---|---|
| Footprint | `1 × 1` |
| Cost | 20 Wood |
| Required work | 25 |
| Capacity | 100 total Wood/Stone/Food |
| Active location rule | claimed location |

The Supply Cache remains a separate building owner from structural cell construction.

### Other building definitions

`campfire`, `cabin`, and `storehouse` remain in `BuildingDefinition`. Their legacy warmth, shelter, or storage metadata is not connected to active windowed gameplay, and the current windowed UI does not expose their placement.

## Desktop and Presentation

### `Main`

File: `scripts/main.gd`

Owns:

- live `DesktopWindow` collection;
- application/location lookup dictionaries;
- window creation and cleanup;
- focus and z-order routing;
- taskbar registration coordination;
- location view creation;
- request translation and projected labels.

### `DesktopShell`

File: `scripts/desktop/desktop_shell.gd`

Owns:

- Start menu visibility;
- taskbar window buttons;
- active taskbar entry;
- time controls and taskbar clock projection.

### `DesktopWindow`

File: `scripts/desktop/desktop_window.gd`

Owns:

- normal position and size;
- maximized state and restore rectangle;
- title-bar controls;
- bounded drag behavior;
- lifecycle request signals;
- focused/inactive title presentation.

### `JobLocationView`

File: `scripts/presentation/job_location_view.gd`

Owns:

- terrain/resource/pile/building/structure/colonist projection;
- pan and zoom;
- construction previews;
- pointer and keyboard translation;
- rendering-suspension state.

Minimize suspends subscribed projection updates. Restore rebuilds dynamic projection from current authoritative snapshots. Close frees it; reopen creates a fresh instance.

No presentation state is authoritative or saved. Already-maximized windows are not dynamically refitted after later viewport resize.

## Persistence Architecture

Current active document:

```text
schema: windowed_colony
version: 4
path: user://windowed_colony_v3.json
accepted versions: 3, 4
```

`WindowedColonyState.export_save_data()` gathers normalized owner exports. Import validates the document, stages a registry, building coordinator, structural owner, roster, scouting records, and travel records, then replaces active owners after successful staging.

Version 3 loads with an empty structural-construction section. Version 4 requires it.

Persisted:

- settled phase, seed, time, scale;
- full location records, terrain/resources, lifecycle, claims, presence, piles;
- Supply Cache records, progress, consumed status, contents;
- structural sites/progress/consumed status and completed structures;
- colonist identity, skills, traits, role, needs, location/cell;
- scouting sequence and active scouting/travel records.

Reconstructed:

- local work choice, targets, paths, interpolation, activity;
- all worker/material/pile/capacity reservations;
- Hunger recovery and need activity timers;
- recent production-event history and derived rates;
- structural and building visual indices;
- windows, taskbar, focus, geometry, pan/zoom, suspension, caches.

Limitations:

- single slot;
- filename still says `v3`;
- direct non-atomic replacement write;
- carried payload makes validation reject the save;
- only settled saves are accepted;
- validation does not prove every possible hostile/corrupt relationship;
- failure reporting is limited.

See `docs/SAVE_BOUNDARY.md` for the focused contract.

## Active, Legacy, and Experimental Boundaries

| Status | Content |
|---|---|
| Active production | Windowed main scene, state, desktop, location network, work/needs, production summaries, Supply Cache, structural construction, traversal, active save |
| Active shared | Bounded generator reuse of world generation/terrain/prop helpers; procedural resource visual cache; building definitions |
| Compatibility | Version-3 windowed load, retained legacy save functions, deferred roof-shaped persistence data |
| Dormant legacy | `scenes/legacy/WorldMapMain.tscn`, `scripts/legacy/`, `WorldState`, `ChunkManager`, node `Colonist`/`ColonistManager`, `ResourceStockpile`, legacy UI/effects |
| Experimental | Procedural-building and procedural-creature research |
| Debug | Focused validators, galleries, explicit debug construction completion |

Legacy and experimental code must not become an active owner through convenience reuse.

## Extension Constraints

- Preserve explicit owner boundaries.
- Add focused services rather than expanding `WindowedColonyState` without need.
- Summaries must read simulation; they must not become alternate production authority.
- Functional workplaces must remain location/building-owned.
- Bulk/offline progress requires a deterministic bulk-simulation contract first.
- Window visibility must never affect production.
- Do not introduce cross-location resource transfer implicitly.
- Do not treat legacy effects or stores as active windowed systems.

## Current Risks

- Coordinator breadth in `WindowedColonyState`.
- Presentation breadth in `JobLocationView`.
- No explicit work designation/priorities beyond exclusive role.
- No durable progression or longer-term economic analytics beyond recent throughput.
- Remote entry-cell Food classification mismatch.
- Frame-stepped local movement/work is unsuitable for one large offline delta.
- Full-record saves may grow materially.
- Non-atomic save writes and carried-payload rejection.
- Transitional standalone-building model.
- No general notification/error presentation boundary.
- No dynamic refit of maximized windows after viewport resize.

## Roadmap Boundary

The intended direction is a Melvor-style idle colony manager with multiple live authoritative locations.

**I01 — Location production summaries** is implemented as a live, transient analytics projection. Forecasting, net production, automation, global dashboards, and offline progress remain outside the active architecture.
