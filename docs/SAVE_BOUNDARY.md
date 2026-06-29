# Save/Load Boundary

This document defines the save/load boundary. It separates authoritative simulation state from generated, visual, UI, cache, and temporary runtime state.

A minimal, non-autoload save/load foundation exists in `scripts/simulation/save_game_service.gd`. It serializes a versioned dictionary/JSON file and delegates import/export to current state owners. It does not provide menus, slots, autosave, full scene reload, migration, or persistence for future systems.

## Purpose

Save/load should store only the minimum state needed to reconstruct the player's simulation. The generated base world should come from deterministic seed/config values, while player changes should be stored as deltas.

This boundary exists so future Codex tasks do not accidentally persist rendered tiles, procedural textures, UI selections, or streaming queues as authoritative game state.

## Authoritative State To Save

- World seed and relevant generation config:
  - `WorldGenerator.seed`
  - generation-affecting exported values such as terrain scale, landmass scale, and climate thresholds
  - constants that affect generation if they become configurable or versioned
  - generated elevation model inputs; do not save generated elevation per cell
- Manual tile overrides:
  - cell coordinate
  - terrain name
  - enough version/context data to validate the terrain name against `TerrainConfig`
- Depleted or harvested resource identities:
  - stable `resource_id`
  - cell
  - resource kind/type where needed for migration or validation
  - this should be saved as a depletion delta against regenerated base spawns, not as rendered node state
  - Berry Bush ids use `berry_bush:x:y` and follow the same no-regrowth depletion rule as trees and rocks
- Player-authored stockpile zones:
  - stable `zone_id`
  - explicit member cells
  - enabled state and optional label
  - no overlay geometry, item contents, filters, or hauling state
- Physical ground items:
  - stable `item_id`
  - resource type and positive amount
  - world cell and enabled state
  - no visual-node, haul reservation, carrying activity, filter, decay, or path state
- `ResourceStockpile` totals:
  - resource type keys, currently including `wood`, `stone`, and `food`
  - integer totals
  - totals may legally exceed current derived capacity after import; they are not truncated
- Persistent colonist records:
  - stable colonist id, first/last name, and nickname
  - current cell and exact world position
  - Rest, Warmth, Shelter, and Hunger values
  - skill level/XP/passion records
  - trait ids, with definitions re-derived from the registry
  - relationship type and stable target colonist id
- Buildings and construction state when implemented:
  - building id/type
  - occupied cells
  - construction progress
  - ownership/contents only when those systems exist
- `TimeState` simulation time:
  - current tick/day/time
  - deterministic scheduler state if future systems depend on it

## State Not To Save

- `TileMapLayer` rendered cells that can be regenerated from seed/config plus manual tile deltas.
- Generated elevation values that can be regenerated from seed/config.
- Procedural sprite textures or `ProcSpriteCache` contents.
- Staged resource spawn queues such as `_pending_resource_spawns`.
- Loaded chunk dictionaries that only mirror the active streaming window.
- UI selected tile state.
- UI labels or panel contents.
- Camera position, unless later treated as a user preference rather than simulation state.
- Transient input state.
- Construction/harvest job candidates, reservation results, worker reservations, and colonist idle/wandering/work/need-seeking/eating activity state. Work and needs are re-evaluated from restored authoritative values.
- `ResourceStockpile` reservation ids and earmarked costs. Only actual totals are saved.
- Temporary debug artifacts or `.codex_tmp` files.
- Procedural visual config that can be re-derived from seed, cell, resource kind, and current visual settings.
- Building/resource visual profile ids, scene/icon paths, placeholder palettes, scene-local sprites, and external visual instances. These come from presentation definitions documented in `docs/ASSET_REPLACEMENT.md`.
- Building effect radii/tags and glow/warmth projection nodes; these derive from definitions plus completed building records.
- Shared storage capacity; base capacity is code-backed and Storehouse bonuses derive from completed construction records plus `BuildingDefinition`.
- Colonist activity, construction/harvest/haul assignment, carried payload, work/capacity reservation, movement target, pause timer, environmental status flags, and overhead need labels.
- Selected colonist references, selection markers, and colonist info panel contents.
- Stockpile/harvest drag start/current cells, mode flags, preview polygons, result summaries, and `StockpileZoneVisual` nodes.
- `GroundItemVisual` nodes, labels, colors, and other reconstructible item presentation.

## Generated Base World Versus Player Deltas

The base terrain, base elevation, and base resource spawns should be regenerated from world seed and generation config. Save data should store only changes made after generation.

Examples:

- Manual terrain edits are deltas keyed by cell.
- Future mined cliffs/elevation edits should be deltas keyed by cell, not saved copies of generated elevation.
- Harvested trees/rocks are depletion deltas keyed by stable resource identity.
- Stockpile totals are simulation state and should be saved directly.

Do not serialize every loaded tile or every currently visible resource node. Those are runtime projections of seed/config plus deltas.

## Current Implementation

Version `2` save data currently includes:

- `world`: `WorldGenerator.seed` plus generation-affecting exported config values.
- `time`: `TimeState` day, minutes, day length, time scale, and paused flag.
- `stockpile`: abstract stored `ResourceStockpile` totals by resource type. Harvested output remains outside these totals as ground items.
- `deltas.manual_tiles`: manual terrain overrides as cell coordinates plus terrain names.
- `deltas.depleted_resources`: harvested tree, rock, and Berry Bush ids tracked by `ChunkManager`.
- `deltas.construction_sites`: authoritative `WorldState` construction records, including building id, origin/occupied cells, required and consumed resources, progress, build time, and completion flag.
- `deltas.harvest_orders`: active `WorldState` harvest intent containing order/resource ids, resource type, yield, and cell. Worker reservation is excluded.
- `deltas.stockpile_zones`: authoritative `WorldState` zone records containing zone id, explicit cells, enabled state, and label.
- `deltas.ground_items`: authoritative `WorldState` physical-item records containing item id, resource type, amount, cell, and enabled state.
- `colonists`: authoritative identity, position, Rest/Warmth/Shelter/Hunger, skills, trait ids, and relationship target ids.

Loading validates version `2`, applies world generator seed/config, imports `WorldState` time/stockpile/construction/harvest-order/stockpile-zone/ground-item state, imports `ChunkManager` world deltas, discards orders whose resource id is depleted, then asks `ColonistManager` to replace the population. Rendered cells/nodes, item visuals, designation markers, zone overlays, and placement previews remain excluded.

Build/order panel state is also excluded. Normal/Build/Harvest/Stockpile mode, selected building button, area/placement previews, result summaries, Cancel-button state, mode labels, and keyboard/UI focus are transient presentation/control state owned by `Main` and reconstructed from runtime input rather than save data.

`Colonist.export_state()` stores relationship target ids without cached display names. After every colonist is recreated, `ColonistManager` resolves names from restored ids; missing targets are skipped. Imported colonists resume idle at their saved positions and rediscover needs/work through existing runtime behavior.

Per-colonist work priorities are authoritative colonist record data and are saved as the complete work-type/value dictionary. Values normalize to `0` through `4`; records without this additive field receive the current defaults (Construct/Harvest `2`, future work types disabled). This remains compatible with save version `2` and does not require a version increment.

Hunger remains inside the version-2 colonist `needs` dictionary. Eating spends the already-persistent `food` stockpile total, so no schema change is required. Eating state/timers are not exported; imports resume idle and may decide to eat again from restored Hunger and Food values.

Version `1` saves are rejected as unsupported. There is no migration layer; version `2` is the deliberate schema boundary introduced by Milestone 27.

Live load is intentionally limited. Applying a different seed/config rebuilds generator noise for future generation, but already-loaded chunks are not fully regenerated in-place. Manual overrides are reapplied to loaded chunk visuals, and loaded depleted resources are removed when their ids match the imported depletion set.

During normal streaming, manual tile overrides and depleted resource ids are stored outside loaded chunk dictionaries. Unloading a chunk clears rendered cells and visible nodes, but does not clear those deltas. When the chunk streams back in, base terrain/resources are regenerated from seed/config and player deltas are applied on top.

Stockpile-zone records are owned by `WorldState`, independently of loaded chunks. `ChunkManager` deletes only their per-cell overlay nodes on unload and recreates enabled zone cells from authoritative records when chunks load or zones are replaced. Missing `deltas.stockpile_zones` defaults to an empty list for older version-2 saves, so this additive field does not increment the save version.

Ground-item records are also owned by `WorldState`, independently of chunk streaming. Chunk unload removes only item visuals; generation and ground-item replacement signals recreate enabled projections for loaded cells. Missing `deltas.ground_items` defaults to an empty list for older version-2 saves, so save version `2` remains additive-compatible.

Haul reservations, destination assignments, storage-capacity earmarks, carried payload state, and hauling activities are transient and are not serialized as such. `export_ground_items()` includes an in-flight carried payload as its original item id at the pickup cell; loading therefore abandons the carry and restores a ground item instead of losing the resource. Unpicked reserved items remain ordinary ground-item records. WorldState/ResourceStockpile imports clear haul and capacity reservations, and colonists resume idle.

Construction records are owned by `WorldState`, independently of loaded chunks. They retain consumed resources, progress, and completion. `ChunkManager` deletes only projected nodes on unload and recreates incomplete or completed placeholders from authoritative records when a chunk loads. Importing construction state replaces the authoritative set and refreshes projections for currently loaded chunks.

Cancelling an incomplete site removes its authoritative record, so it is absent from later `deltas.construction_sites` exports and cannot be reconstructed after load. Cancellation releases unconsumed earmarks but does not refund totals already consumed into construction progress. Completed Campfires reject cancellation and remain within the save boundary.

Completed-building effect state is not serialized separately. Campfire light/warmth and Cabin shelter radius/capacity/tags come from `BuildingDefinition`, while source position/existence comes from saved completed construction records. Loading or chunk streaming reconstructs visual indicators and authoritative coverage queries from those inputs. Future fuel, room state, occupancy, or dynamic effect state would require an explicit save-boundary change.

Storehouse capacity is also not serialized separately. `ResourceStockpile` provides base capacity 100, while `WorldState` adds `storage_capacity` metadata from saved completed Storehouse records after construction import. Saved stockpile totals import unchanged even if they exceed the re-derived limit; new additions are rejected until capacity is available.

Construction resource earmarks, harvest/haul workers, haul storage-capacity reservations, carried-item state, and transient job candidates are deliberately excluded from version `2` saves. Harvest creates no capacity reservation; Haul creates one transient reservation per claimed item. `ResourceStockpile.import_state()` clears reservations, WorldState restores orders/items without workers, and `Colonist.import_state()` resets all work/movement targets to idle. Restored colonists rediscover work. None of these paths refund resources already consumed into saved construction progress.

The selected panel's current focus, button focus/hover state, and formatted priority text are UI-only and are not saved. Only the values owned by each `Colonist` persist.

Harvest completion is saved through its authoritative results: the stable resource id enters `deltas.depleted_resources`, the new item enters `deltas.ground_items`, the completed order is absent, and stored totals remain unchanged. Incomplete orders persist as intent and restore without workers. Version `2` remains unchanged because both additive arrays default empty for older version-2 documents.

## Remaining Blockers And Risks

- Stable resource depletion identities need review. Current ids are derived from resource scene key and cell, which is adequate for the current one-resource-per-cell model but may not survive future multi-resource cells or resource regeneration rules.
- Manual tile overrides persist through the minimal save foundation, but still live in `ChunkManager` rather than a broader world-delta owner.
- `WorldState` owns `ResourceStockpile`, `TimeState`, construction sites, harvest orders, stockpile zones, and ground items, while `ColonistManager`/`Colonist` own persistent colonist records; terrain/resource deltas and chunks remain outside both.
- Colonist records persist directly through scene-node owners rather than a separate data-model class. Off-map colonists or death/recruitment may eventually require separation.
- `Colonist` has a minimal transient selector for construction/harvest/haul candidates, while `WorldState` retains focused authoritative transactions. Basic one-item hauling exists, but there is no shared job board, inventory UI, filtering, partial stack handling, or delivery planning.
- Save schema versioning exists only as a single integer version check; no migration policy exists yet.

## Suggested Future Format

Use a simple, versioned, structured save document. The current service writes this shape as JSON when asked by validation/debug code.

High-level shape:

```gdscript
{
	"version": 2,
	"world": {
		"seed": 184729,
		"generation_config": {}
	},
	"deltas": {
		"manual_tiles": [],
		"depleted_resources": [],
		"construction_sites": [],
		"harvest_orders": [],
		"stockpile_zones": [],
		"ground_items": []
	},
	"time": {},
	"stockpile": {},
	"colonists": []
}
```

Keep generated data out of the save. Include enough schema/version information to reject incompatible saves clearly.

## Near-Term Sequencing

Recommended order:

1. Keep persistence calls behind `SaveGameService`; do not make it an autoload without an explicit architecture decision.
2. Add a deliberate reload/rebuild flow before treating seed/config changes as fully live-loadable.
3. Decide whether resource ids are stable enough for long-term depletion saves.
4. Move world deltas under `WorldState` or an equivalent simulation root when broader persistence needs it.
5. Add a migration policy before compatibility with version `1` or any future schema is required.
