# Active Windowed-Colony Save Boundary

## Status

This document describes the configured windowed-colony save. The dormant streamed-world version-2 format is summarized only under Legacy Compatibility.

## Current Contract

| Property | Value |
|---|---|
| Schema | `windowed_colony` |
| Current version | `4` |
| Accepted versions | `3`, `4` |
| File path | `user://windowed_colony_v3.json` |
| Slots | One |
| Save coordinator | `WindowedColonyState` |
| Validation/file service | `SaveGameService` |

The `v3` filename is a historical mismatch; the document written today is version 4.

Only `SETTLED` documents pass active validation. Main-menu and location-evaluation state are not persisted through the normal request.

## Export Ownership

`WindowedColonyState.export_save_data()` assembles owner exports:

```text
WindowedColonyState
  ├─ LocationRegistry.export_state()
  ├─ LocationConstructionCoordinator.export_state()
  ├─ LocationConstructionState.export_state()
  ├─ colonist records
  ├─ ScoutingCoordinator snapshots
  └─ LocationTravelCoordinator snapshots
```

The document stores complete bounded-location records, not only regeneration deltas.

## Persisted Authoritative State

### Simulation root

- schema and version;
- `SETTLED` phase;
- game seed;
- `_simulation_time`;
- time scale;
- primary settlement id;
- scouting sequence.

### Locations and resources

For every location:

- stable id, name, type, seed;
- deterministic abstract `world_position`;
- lifecycle/discovery state;
- claim metadata and primary-settlement flags;
- generation configuration;
- `32 × 32` map size;
- complete terrain records;
- complete generated resource records, including depletion and fruit-harvest state;
- spawn, entry, exit, and camp-storage cells;
- presence membership;
- complete physical pile records;
- next pile sequence.

Pile worker reservations are cleared from the exported copy.

### Supply Cache/building authority

From `LocationConstructionCoordinator`:

- stable building instance id;
- location and building definition id;
- origin and occupied cells;
- planned/under-construction/completed state;
- progress and required work;
- cost and material-consumed state;
- formal storage contents and capacity;
- next building sequence.

Worker assignment, material reservation ids, capacity reservations, and derived enclosure records are reconstructed.

### Structural construction

From `LocationConstructionState`:

- next structural-site sequence;
- incomplete floor/wall/door/window sites;
- cell, piece kind, orientation, requirements and prerequisites;
- material-consumed state;
- build progress and requirement;
- completed-site identity;
- completed floor records;
- completed wall records and door/window fixture metadata;
- compatibility-shaped completed roof records.

Worker reservations and resource reservation ownership are cleared on export/import. Roof placement remains deferred even though the persistence shape accepts roof records.

### Colonists

Exactly three records:

- stable id and display name;
- skills and traits;
- Hunger and Rest;
- current location;
- role;
- authoritative cell and visual cell;
- carried payload shape.

Current validation rejects any record whose carried amount is greater than zero.

### Mobility

- active scouting records, including origin, search type, discovery seed, duration and elapsed progress;
- active travel records, including endpoints, distance, duration, elapsed progress and departure time.

Validation enforces that each colonist is exactly one of present, scouting, or travelling.

## Reconstructed and Transient State

The following are deliberately not saved:

- active local target selection;
- activity text and eating/sleeping activity state;
- movement path, path index, interpolation and repath timer;
- gathering/hauling work progress outside persisted construction progress;
- pile reservations and reservation owners;
- carried-haul destination/capacity reservations in a valid save;
- Supply Cache worker/material/capacity assignments;
- structural worker/material reservation ownership;
- transient Hunger recovery;
- recent production events, rolling rates, and projected production status;
- open windows and application lookup dictionaries;
- taskbar entries and active focus;
- window position, size, minimized/maximized state and restore rectangle;
- location rendering suspension;
- pan, zoom, hover, construction preview and selection;
- TileMaps, sprites, procedural texture caches and other render nodes;
- presentation-only travel connector state.

On import, colonists are reconstructed idle with saved roles and needs. Local work and needs are re-evaluated. Reservations are rediscovered through normal owner APIs.
`LocationProductionTracker` is recreated empty, so current resource totals and roles are immediately available while recent rates repopulate only from new completed gathering.

## Import Validation and Ordering

`SaveGameService.validate_windowed_colony_data()` first checks:

- schema and accepted version;
- settled phase;
- required top-level owner sections;
- three unique colonists and valid roles;
- unique locations and primary settlement at world origin;
- claim metadata;
- exclusive presence/scouting/travel membership;
- valid mobility progress;
- no unresolved carried payload;
- version-4 structural section presence.

`WindowedColonyState.import_save_data()` then:

1. imports into a staged `LocationRegistry`;
2. imports a staged `LocationConstructionCoordinator` against that registry;
3. configures staged traversal and structural owners;
4. imports structural construction;
5. reconstructs staged colonist runtime records;
6. replaces active owners only after staging succeeds;
7. restores scouting/travel records;
8. emits replacement and presentation-refresh signals.

This provides owner-level staged replacement for the active windowed stack. It is not a general guarantee that every hostile same-version document relationship has been exhaustively proven.

## Version Compatibility

### Version 4

Current format. Requires `structural_construction`.

### Version 3

Accepted compatibility format. A missing structural section is interpreted as empty structural state. Claims and Supply Cache records remain supported.

### Versions 1 and 2

Historical active-windowed formats are not accepted by the current validator.

### Legacy streamed-world version 2

`SaveGameService` retains separate functions for the dormant streamed-world architecture. That document contains legacy `WorldState`, `ChunkManager`, `ColonistManager`, `ResourceStockpile`, world-space, construction, mining, interiors, and other streamed-world records.

It is not accepted by `load_windowed_colony()` and must not be described as the active save.

## File I/O and Failure Behaviour

The active save:

- validates before writing;
- opens the target path with `FileAccess.WRITE`;
- writes JSON directly to the final file;
- does not use a temporary file plus atomic rename;
- reads and parses the same single path;
- returns structured failure reasons to `Main`.

User-facing feedback remains limited, especially for save failures triggered outside the main menu.

## Known Limitations

- Single slot only.
- Version-4 content uses a `v3` filename.
- Direct writes are non-atomic and can leave the slot vulnerable to interruption.
- A save request fails while a colonist carries resources.
- Only settled games can be saved/loaded.
- Complete terrain/resource records increase file size as location count grows.
- Validation is strong around owner identity and mobility exclusivity but is not complete hostile-document verification.
- No migration path exists for active versions 1 or 2.
- No desktop/presentation restoration is intended.
- No offline-progress timestamp or bulk-simulation state exists.

## Extension Rules

- Add new persisted fields through the authoritative owner.
- Keep worker claims, reservations, paths, projections, and UI state transient unless a future requirement proves otherwise.
- Do not serialize summaries as alternate authority when they can be derived.
- Do not reuse the dormant legacy schema for active windowed features.
- Offline progress requires a deterministic bulk-simulation contract before adding timestamps or elapsed-away calculations.
