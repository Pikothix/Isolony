# Current Baseline

This document records the current repository baseline. It describes the current implementation only; it is not a redesign spec and does not imply future systems already exist.

## Project Overview

- Godot project: `Iso Colony`.
- Engine feature tags in `project.godot`: `4.7` and `Forward Plus`.
- Main scene: `res://scenes/Main.tscn`.
- Autoloads: none detected in `project.godot`.
- Current prototype focus: deterministic isometric terrain, staged wood/stone/berry resources, physical ground items and hauling, Campfire/Cabin/Storehouse construction and effects, persistent colonist records and work priorities, stockpile zones, and debug UI.

## Current Scene Structure

`scenes/Main.tscn` wires the live scene as:

- `Main` (`scripts/main.gd`)
- `WorldState` (runtime-created by `Main`, `scripts/simulation/world_state.gd`)
  - `ResourceStockpile` (`scripts/simulation/resource_stockpile.gd`)
  - `TimeState` (`scripts/simulation/time_state.gd`)
- `WorldGenerator` (`scripts/world/world_generator.gd`)
- `ChunkManager` (`scripts/world/chunk_manager.gd`)
  - `TerrainLayer` (`TileMapLayer`)
  - `GameplayYSort`
	- `StockpileZoneRoot`
	- `GroundItemRoot`
	- `ResourceRoot`
	- `ConstructionRoot`
	- `ColonistManager` (`scripts/entities/colonist_manager.gd`)
- `Camera2D` (`scripts/camera_controller.gd`)
- `CanvasLayer`
  - resource counter label
  - selected tile panel (`scripts/ui/selected_tile_panel.gd`)
  - `ArchitectMenu`
  - `BottomToolbar` (`scripts/ui/bottom_toolbar.gd`)
  - selected colonist info panel (`scripts/ui/colonist_info_panel.gd`)

Scene-level values currently override some script defaults, including:

- `WorldGenerator.landmass_scale = 16.0`
- `WorldGenerator.water_max = 0.465`
- `ChunkManager.procedural_tree_large_size = 72`
- `ChunkManager.procedural_rock_small_size = 48`
- `ChunkManager.procedural_rock_medium_size = 48`
- `ChunkManager.procedural_rock_large_size = 48`
- `ColonistManager.colonist_count = 12`

## Current System Ownership

- `scripts/main.gd`: scene coordination, dependency injection, resource/time UI, transient Normal/Build/Harvest/Stockpile mode ownership, colonist selection, and request routing.
- `scripts/simulation/world_state.gd`: authoritative construction/storage-component/harvest-order/stockpile-zone/ground-item lifecycle, bounded deterministic availability snapshots, completed-building effects/storage-capacity derivation, and validated stockpile coordination.
- `scripts/simulation/time_state.gd`: clock time, day/night phase, clock labels, clock scaling, clock pause state, and time/phase signals. Its pause/scale values do not pause or scale all colonist simulation.
- `scripts/simulation/resource_stockpile.gd`: abstract stored totals/capacity, construction resource earmarks, haul storage-capacity reservations, atomic mutations, and notifications.
- `scripts/world/world_generator.gd`: deterministic noise setup, climate sampling, elevation classification, terrain classification, tile info creation, walkability lookup, chunk data generation, and resource spawn planning calls.
- `scripts/world/terrain_config.gd`: terrain definitions, tile atlas coordinates, display names, selectable placement terrain entries, walkability, mineability, and terrain support queries for trees, rocks, and berry bushes.
- `scripts/world/chunk_manager.gd`: chunk/resource streaming, terrain mutation, live generated-resource indexes, tree/rock/berry depletion tracking, harvest snapshot/commit integration, and construction/stockpile-zone/ground-item visual projection.
- `scripts/world/reachability_query.gd`: stateless, bounded orthogonal BFS over currently loaded cells. It reads effective terrain and resource occupancy from `ChunkManager` plus construction occupancy from `WorldState`; it owns no simulation state or cache.
- `scripts/world/stockpile_zone_visual.gd`: reconstructible presentation-only marker for one loaded stockpile-zone cell.
- `scripts/world/ground_item_visual.gd`: reconstructible presentation-only placeholder for one physical resource item and amount.
- `scripts/world/props/prop_spawn_helpers.gd`: deterministic tree/rock/berry spawn rolls and terrain-specific density multipliers.
- `scripts/world/props/prop_visual_config.gd`: deterministic procedural visual configuration for spawned tree and rock nodes.
- `scripts/world/props/resource_visual_definition.gd`: replaceable resource scene/icon paths, procedural profile ids, and placeholder visual ids keyed by stable resource kind.
- `scripts/world/props/prop_prewarm_config.gd`: procedural sprite prewarm request construction.
- `scripts/entities/resource_node.gd`: shared tree/rock/berry interaction, live resource id/type/yield/cell fields used by `ChunkManager` harvest validation, optional procedural sprite application, and harvest request emission. It does not own stockpile totals, orders, or depletion state, but is not purely presentation while loaded.
- `scripts/procgen/proc_sprite_cache.gd`: presentation-only static texture cache and cache statistics. This is hidden global process state, but it carries no simulation authority and is excluded from saves.
- `scripts/entities/colonist_manager.gd`: colonist population export/replacement, stable-id relationship resolution, deterministic new-population generation, hit queries, `WorldState` injection, and stale-reservation audits.
- `scripts/entities/colonist_trait_registry.gd`: trait definitions, descriptions, exclusions, and centralized modifier values.
- `scripts/entities/colonist.gd`: authoritative persistent identity, position, needs, skills, traits, relationships, and per-work-type priorities plus transient construction/harvest/haul activity, current cell path, and cleanup.
- `scripts/ui/colonist_info_panel.gd`: selected-colonist state projection plus request-only Construct/Harvest/Haul priority cycling; it owns no colonist state.
- `scripts/ui/selected_tile_panel.gd`: selected terrain preview and label display using `TerrainConfig` metadata.
- `scripts/ui/bottom_toolbar.gd`: request-only bottom toolbar, transient Architect submenu, `BuildingDefinition`-generated building buttons, Harvest/Stockpile compatibility actions, current-mode projection, and Cancel button.
- `scripts/buildings/building_definition.gd`: Campfire, Cabin, and Storehouse footprint/cost/build/effect metadata plus deterministic Architect presentation order.
- `scripts/buildings/construction_site_visual.gd`: definition-configured previews/effect overlays, optional external scene host, and fallback scaffolds/completed placeholders.

## World Generation And Chunk Streaming Flow

1. `ChunkManager` tracks the camera chunk and queues nearby chunk coordinates using `load_radius`.
2. Each frame, `ChunkManager` generates up to `chunks_per_frame` queued chunks.
3. `WorldGenerator.generate_chunk()` walks the chunk cells using `WorldGenerator.CHUNK_SIZE`.
4. For each cell, `WorldGenerator` samples height, moisture, terrain detail, and landmass noise.
5. `WorldGenerator` classifies generated elevation: `0` low/normal, `1` raised, `2` cliff/high rock.
6. `WorldGenerator._classify_terrain()` directly resolves terrain names such as `WATER`, `GRASS`, `STONE`, `MUD`, and `ROCK_WALL`.
7. `WorldGenerator` looks up tile variants, walkability, and mineability from `TerrainConfig.TERRAIN_DEFS`.
8. `PropSpawnHelpers.build_resource_spawn()` may emit a deterministic tree, rock, or Berry Bush spawn record for walkable terrain.
9. `ChunkManager` writes terrain tiles to `TerrainLayer`, applying any in-memory manual tile override for loaded cells.
10. `ChunkManager` spawns resources immediately or through `_pending_resource_spawns`, depending on `stage_resource_spawning`.
11. `ChunkManager` unloads distant chunk tiles and resource nodes when they move beyond the streaming radius. Manual tile overrides and depleted resource ids are kept outside loaded chunk data, so unloading a chunk does not erase those deltas.

## Manual Tile Placement Flow

1. `Main` converts the mouse position to a terrain cell and calls `ChunkManager.request_place_manual_tile(cell, terrain_name)`.
2. `ChunkManager` validates that the cell is loaded, the terrain name is known, and the terrain can produce atlas coordinates.
3. Failed requests return `{ok = false, reason = ...}` and do not mutate manual overrides, loaded chunk lookup, or `TerrainLayer`.
4. Successful requests update `_manual_tile_overrides`, update the loaded chunk `tile_lookup`, update `TerrainLayer`, and return `{ok = true, reason = "placed"}`.
5. When a chunk reloads, generated base tiles are rebuilt from seed/config and matching manual overrides are applied as deltas.

## Resource Harvesting Flow

1. Resource spawn records are created by `PropSpawnHelpers` during chunk generation.
2. `ChunkManager` instantiates `Tree.tscn`, `Rock.tscn`, or `BerryBush.tscn` as a `ResourceNode`.
3. `ChunkManager` configures resource id, cell, resource type, yield amount, position, and procedural visual settings.
4. `ResourceNode` listens for an unconsumed left-button release on its `Area2D`, preserving exact single-resource designation.
5. While loaded, its id/type/yield/cell fields are indexed by `ChunkManager` and form the live snapshot used to validate designation and completion. Deterministic spawn data and `ChunkManager` depletion state remain the reconstructible world inputs; the node does not mutate orders, depletion, or stockpile totals itself.
6. Main also supports harvest-area drags. It previews an inclusive cell rectangle, asks `ChunkManager` for currently loaded tracked resources inside it, and submits each stable id independently through `WorldState.request_designate_harvest()`.
7. Designation does not add resources or deplete/remove the node. A yellow marker is a reconstructible projection of `WorldState` order state.
8. After critical warmth/shelter and eating checks, an idle colonist may reserve an available, loaded order. Harvest assignment does not depend on abstract storage capacity and reserves only the order for that worker.
9. `WorldState.request_complete_harvest_order()` validates the order, reservation owner, current resource identity/type/yield/cell, and a complete pending ground-item record before mutation.
10. `ChunkManager.commit_harvest_resource()` records depletion and removes loaded source tracking. WorldState then publishes one ground item with the same resource type, yield amount, and cell, and clears the completed order.
11. Harvest never adds directly to `ResourceStockpile`; it requires no free storage capacity and creates no harvest-yield storage-capacity reservation.
12. Any preflight or depletion failure leaves stockpile totals, ground items, depletion, order state, and the resource visual unchanged.
13. Successful depletion remains in `_depleted_resource_ids`, so chunk generation and staged spawns skip that stable id.
14. A `GroundItemVisual` signal projection appears for loaded item cells; the resource counter remains unchanged.

## Berry Bush Food Source

Berry Bushes are deterministic generated resources on Grass, Dark Dirt, and Mud. Trees/rocks retain first occupancy priority; eligible remaining cells use a separate salted bush roll with base density `0.055`, adjusted to `0.9×` on Dark Dirt and `1.15×` on Mud. Each bush uses the `berry_bush:x:y` stable id format and yields 6 `food`.

`BerryBush.tscn` is a simple green polygon bush with red berry accents and the shared `ResourceNode` interaction. Rendering remains replaceable and non-authoritative. Completing its order creates a physical Berries/Food item; abstract Food does not change.

Harvest records enter the existing `_depleted_resource_ids` set, so the same bush is skipped during staged spawn, chunk regeneration, and loaded-node reconciliation. Hungry colonists consume only abstract stored Food; ground Berries become edible only after a Haul job deposits them.

## Physical Ground Items

`WorldState` owns ground-item records containing stable `item_id`, `resource_type`, positive `amount`, `cell`, and enabled state. Public creation/removal and defensive list/rectangle queries operate on those records. Harvest prebuilds a valid deterministic item record before asking `ChunkManager` to deplete the source, then commits that prepared record synchronously after successful depletion. Invalid completion cannot create an item or remove its source.

`ChunkManager` listens for ground-item add/remove/replace signals and projects enabled items under `GroundItemRoot`. Brown Wood, grey Stone, and red Berries placeholders include an amount label. Chunk unload deletes only projections; chunk generation and import rebuild them from WorldState. Ground items are not `ResourceNode` instances and cannot be designated for harvest.

Ground items persist in `deltas.ground_items`, while visuals remain transient. Hauling can remove and deposit one complete item, but there is no stack merge/split, filter, spoilage, direct ground consumption, or debug collection path.

## Hauling Jobs

Haul is implemented through the existing Colonist job-candidate flow but remains disabled by default (`0`) to preserve older player work policies. The selected-colonist panel exposes a Haul priority button. Enabled idle colonists consider construction, harvest, then haul for equal priorities after urgent needs and eating.

`WorldState` owns transient haul reservations keyed by item id. A successful reservation chooses the nearest valid loaded cell in any enabled stockpile zone, reserves the item's complete amount against `ResourceStockpile` capacity, and assigns one colonist. Items already inside enabled zones, unloaded items/destinations, reserved items, and items that do not fit available capacity are unavailable.

The colonist enters `moving_to_haul_item`, picks up the complete item, briefly enters `carrying_item`, moves through `moving_to_stockpile`, then enters `depositing`. Deposit validates the same item, owner, destination, zone membership, and capacity reservation before consuming capacity and adding the full amount to stored totals. No partial carrying exists.

Abandonment before pickup releases item/capacity reservations. Abandonment after pickup drops an equivalent new ground item at the colonist's current cell; stale-owner cleanup restores it at the pickup cell when no live position is available. Haul reservation, destination, carried payload, and activities are transient. Save snapshots represent an in-flight payload as its original ground item at the pickup cell, so load clears carrying without losing resources.

## Inventory Ownership Issue

Inventory is intentionally split. Abstract stored counts live in `ResourceStockpile`; physical ground items live as separate `WorldState` records. `Main` only displays stored totals, so harvested drops do not change the resource counter.

The stockpile has a shared base capacity of 100 across Wood, Stone, Food, and any future generic resource key. Resource additions are rejected atomically when the requested full amount exceeds available capacity; no partial clamp occurs. Harvest drops are outside storage and reserve no capacity. Existing/imported totals are never deleted if capacity falls below the stored amount.

Near-term risk: future storage, jobs, save/load, multiplayer, or multiple resource owners will need more simulation state moved under `WorldState`.

## Time Simulation

`WorldState` owns `TimeState`. `Main` advances clock time from `_process(delta)` and updates the existing UI label from `WorldState` time signals. Time is simulation-owned; UI only displays the current label and day/night phase.

`TimeState.paused` and `time_scale` currently affect only clock advancement. Colonist movement, work, and need changes continue using their own process `delta`, so these values are not yet a full simulation pause or speed authority.

Time currently drives day/night-dependent needs and presentation. Seasons, schedules, weather, and broader lighting authority are not implemented.

## Terrain Metadata Duplication Issue

Terrain metadata currently exists in more than one place:

- `TerrainConfig.TERRAIN_DEFS` defines atlas tiles and walkability.
- `TerrainConfig.TREE_TERRAINS`, `ROCK_TERRAINS`, and `BERRY_BUSH_TERRAINS` define resource support.
- `WorldGenerator._classify_terrain()` embeds terrain classification rules.

Manual placement choices, display labels, preview atlas coordinates, walkability, and prop support query `TerrainConfig`. Classification rules currently remain in `WorldGenerator`.

Near-term risk: terrain additions can still drift if `WorldGenerator._classify_terrain()` outputs a terrain name not registered in `TerrainConfig`.

## Elevation And Cliff Prototype

Generated tile info now includes `elevation`, `mineable`, and elevation-aware `walkable` values. Elevation is derived from generated climate/height data and is not saved per cell.

- `0`: low/normal ground.
- `1`: raised ground; currently rendered with the base terrain and remains walkable when the terrain is walkable.
- `2`: cliff/high rock; currently classified as `ROCK_WALL`, uses existing stone atlas tiles as a placeholder, is non-walkable, and is marked mineable for future mining work.

`ChunkManager.get_effective_tile_info(cell)`, `get_cell_elevation(cell)`, and `is_cell_mineable(cell)` expose generated/manual-effective tile metadata without making `TerrainLayer` authoritative.

## Save/Load Status

A minimal, non-autoload save/load foundation exists in `scripts/simulation/save_game_service.gd`. Version `2` serializes world seed/config, `TimeState`, `ResourceStockpile`, manual tile overrides, depleted resource ids, construction sites, harvest orders, stockpile zones, physical ground items, and persistent colonist records including work priorities.

There is no production caller for `SaveGameService`: it is currently instantiated only by debug or validation code. There is no save/load menu, slot system, autosave, migration policy, or full scene reload flow. Loading seed/config updates `WorldGenerator` for future generation, but already-loaded chunks are not fully regenerated in-place. The persistence boundary and exclusions are documented in `docs/SAVE_BOUNDARY.md`.

Manual tile overrides and depleted resource ids are applied during normal chunk generation, so they survive runtime unload/reload as long as the current in-memory delta dictionaries remain present or are restored from save data.

## Campfire Construction Placement

The bottom toolbar's Architect tab toggles a submenu above the toolbar. Its building buttons are generated from `BuildingDefinition`; choosing Campfire closes the submenu and enters placement mode directly. `B` remains the build-mode shortcut. The mouse cell displays a green valid or red invalid diamond. Left-click submits a placement request; toolbar Cancel, right-click, or Escape returns to Normal Selection. Campfire sites are 1x1, require 5 wood, and have a build-time value of 10.

Hover a placed site and press `C` to submit one debug progress request for its remaining build amount. On first valid progress, `WorldState` consumes an existing site earmark or atomically spends unreserved available wood. If resources are insufficient, neither stockpile totals nor site progress change. A funded site completes immediately through this debug action and changes to the completed Campfire placeholder visual.

Hover an incomplete site and press `X` to request cancellation. `WorldState` rejects empty/unknown ids and completed Campfires. Valid cancellation releases the worker reservation and any unconsumed earmark, clears occupied cells, removes the authoritative record, and signals `ChunkManager` to remove the loaded visual. Resources already consumed by partial work are not refunded.

`WorldState` owns construction-site records and occupied-cell state. It validates definitions, loaded cells, effective terrain walkability, blocked terrain, generated resource occupancy, and other construction occupancy before mutation. `ChunkManager` reads that state only to spawn and remove placeholder visuals as chunks stream.

Construction records are included in version `2` save data at `deltas.construction_sites`, including consumed resources, progress, and completion. Records survive chunk unload because they are not stored in loaded chunk dictionaries; incomplete or completed visuals are recreated from `WorldState` when the origin chunk reloads or construction state is imported.

Cancelled records are removed before export and therefore cannot reappear through save/load. Completed Campfires remain saved and cannot currently be cancelled or demolished.

## Campfire Effect Foundation

The Campfire definition provides a light radius of 4 cells and warmth radius of 3 cells. `WorldState.get_completed_building_effects()` derives sources from completed construction records and current definitions. `get_effects_at_cell()`, `is_cell_lit()`, and `is_cell_warmed()` expose authoritative queries. Incomplete or cancelled sites never contribute effects.

The completed Campfire projection draws a transparent isometric warmth marker. Its light glow/radius is shown only at night by presentation code asking `WorldState.is_night()`. These drawings are not authoritative and are reconstructed with the completed projection after chunk reload.

Effect radii and visuals are not saved. Save data retains only the completed Campfire record; load and chunk reconstruction re-read effect metadata from `BuildingDefinition`. There is no fuel, needs integration, weather response, fire spread, or heat grid.

## Cabin Building And Shelter

The generated Cabin Architect button enters Cabin placement directly. Existing `B`, then `1` for Campfire or `2` for Cabin remains available. The preview displays every footprint cell and uses the existing green/red validation. Outside build mode, `1` and `2` retain the earlier terrain-selection behavior.

Cabin is defined as a 2×2 building costing 20 wood with 30 work required. Placement validates all four cells for loading, terrain walkability, blocked resources, and construction occupancy. All four cells remain indexed as occupied after completion. Colonists use the same resource reservation, movement, timed work, cancellation, and cleanup flows as Campfires.

Incomplete Cabins display a four-cell foundation/scaffold placeholder. Completed Cabins display a simple cabin placeholder plus a shelter-radius marker. Cabin shelter radius is 2 cells with capacity 2. `WorldState.get_shelter_sources()`, `get_shelter_at_cell()`, and `is_cell_sheltered()` derive authority only from completed Cabin records and definition metadata.

Cabin records use the existing construction save format. Shelter metadata/visuals are not serialized; save/load and chunk reload reconstruct them from the completed `cabin` record and `BuildingDefinition`.

## Storehouse Building And Storage Capacity

The generated Storehouse Architect button enters Storehouse placement directly; build-mode key `3` remains available. It has id `storehouse`, display name `Storehouse`, a 3×2 footprint, cost 30 Wood plus 10 Stone, build requirement 50, and `storage_capacity = 100`. Generic footprint validation, occupied-cell indexing, resource reservation, timed colonist work, cancellation, chunk projection, and construction persistence are reused unchanged.

## Build And Order Controls

`Main` owns one transient control mode: Normal Selection, Build with the selected definition, Harvest Designation, or Stockpile Zone. Harvest and Stockpile modes reuse the same transient drag cells, six-pixel threshold, and placeholder rectangle preview. `BottomToolbar` emits requests only and renders `Main`'s mode label; it owns no construction, harvest, resource, or zone state.

Architect building buttons select the corresponding `BuildingDefinition` id, close the submenu, and show the existing placement preview. Harvest Designation supports exact single-resource clicks and click-drag cell rectangles. Stockpile Zone mode uses `Z` or its toolbar button and commits the inclusive cell rectangle on release, including a one-cell click. Toolbar Cancel, Escape, or right-click leaves the active tool and clears the preview. Existing `B`, `H`, `Z`, `1`, `2`, `3`, `C`, and `X` controls remain available.

`ChunkManager.get_loaded_resources_in_cell_rect()` returns defensive metadata for currently loaded, tracked resource nodes inside an inclusive cell rectangle without mutating them. Main submits each returned id independently to `WorldState`, counts designated/already-ordered/invalid/depleted results, and shows a compact last-area summary. Existing orders and invalid results are skipped without aborting the remaining rectangle.

Current mode, selected building, Architect submenu visibility, generated-button state, drag/result state, preview state, and toolbar labels are UI/control state only. They are not included in version `2` saves and never authorize construction, harvest completion, or zone membership. Successful area harvest requests persist through `deltas.harvest_orders`; successful stockpile zones persist separately through `deltas.stockpile_zones`.

## Stockpile Zones

`WorldState` owns each zone record with stable `zone_id`, explicit `cells`, `enabled`, and `label` fields plus an authoritative cell-to-zone index. Creation validates the whole request before mutation: the list must be non-empty, every cell must be loaded, walkable, non-water, non-cliff/non-mineable terrain, outside construction footprints, and outside existing zones. Duplicate input cells normalize to one cell; overlap with another zone rejects the complete request. Construction placement also rejects zone cells so the non-overlap invariant remains true.

`ChunkManager` listens for zone add/remove/replace signals and creates one blue placeholder marker per enabled zone cell in loaded chunks. Unloading deletes only those marker nodes. Chunk generation and save import query `WorldState` and recreate them, so overlays are never authoritative.

Zones provide valid Haul destination cells but have no individual capacity, filters, item ownership, or per-resource rules. Shared capacity remains in `ResourceStockpile`. Version `2` stores zone records additively; older version-2 data without `deltas.stockpile_zones` restores an empty zone set.

## Asset And Definition Boundary

Building definitions expose construction/completed visual ids, optional state-specific `Node2D` scene paths, optional icon paths, and fallback placeholder palettes. `ConstructionSiteVisual` dispatches on presentation profile ids rather than gameplay building ids and hosts an external scene when configured. Empty paths preserve the current procedural Campfire/Cabin/Storehouse drawings.

Generated resource art metadata is centralized in `ResourceVisualDefinition`: tree, rock, and Berry Bush kinds resolve default scene paths, icon paths, procedural profile ids, and placeholder ids there. `ChunkManager` retains optional scene overrides but the live `Main.tscn` uses registry defaults. `PropVisualConfig` selects tree/rock generation from the visual profile rather than treating resource kind itself as the rendering strategy.

The Architect submenu reads building order, display names, costs, footprints, and optional icons from `BuildingDefinition`. Colonist gameplay reads only optional `SelectionIndicator`/`NeedsLabel` presentation children; body sprite/polygon replacement remains scene-local. Detailed replacement contracts and intentionally retained placeholders are documented in `docs/ASSET_REPLACEMENT.md`.

No authoritative construction, resource, colonist, stockpile, need, depletion, or order state contains scene appearance, icon, palette, or generated texture data.

Incomplete Storehouses draw a footprint scaffold. Completed Storehouses draw a simple warehouse placeholder. Visuals are projections only; `WorldState` derives capacity by summing the base 100 plus `storage_capacity` metadata from every completed authoritative Storehouse record. Chunk unload therefore cannot affect capacity.

`WorldState` also derives one preparatory storage component record for each completed Storehouse. Each component is linked to the completed construction site id, building id, origin, occupied cells, and definition capacity, with empty contents in the current milestone. These records are read-only snapshots for future building-owned storage work; hauling, construction, eating, and the resource UI still use `ResourceStockpile` as the active gameplay storage authority.

`ResourceStockpile` owns stored totals, the current shared limit, construction earmarks, and haul-deposit capacity reservations. Harvest itself reserves no capacity because output remains physical; Haul reserves the full item amount when claiming work. The resource panel displays stored/capacity values; reserved haul capacity and ground items are excluded from the stored count.

Version `2` saves no derived capacity or storage-component field. Completed Storehouse construction records persist normally, and capacity plus empty storage components are re-derived after load. Stockpile import accepts saved over-capacity totals without deleting them; later additions remain rejected until spending or more Storehouses creates room.

## Colonist Construction Work

Idle colonists with enabled Construct work query `WorldState` for funded, incomplete, loaded construction sites. `WorldState` owns one worker reservation per site, while `ResourceStockpile` atomically earmarks that site's full cost. A second site is not affordable while the same resources are earmarked. Before reservation, the colonist requires a loaded-cell path to the origin, allowing the occupied target cell only for that construction job. It then follows the transient cell path and submits `construction_work_rate * delta` progress until completion.

The first successful work tick consumes the site's reserved resources and clears the resource earmark; subsequent ticks only add progress. Releasing work before consumption releases both worker and resource reservations, restoring availability. Completion clears the worker reservation. Ordinary spending also uses available rather than earmarked totals. The debug `C` action remains available but is not required.

Worker reservations, resource earmarks, and colonist activity are transient and not saved. Loading stockpile/construction state clears them, restoring `available = total`, after which colonists rediscover and reserve incomplete funded work.

Reservation cleanup is simulation-owned. Colonists release their current work when progress fails, the site disappears, ownership is lost, travel exceeds 30 seconds, or the colonist exits the tree. `ColonistManager` reports active colonist ids and asks `WorldState` to audit reservations every two seconds as a fallback for missing workers. Cleanup releases an unconsumed resource earmark but never restores resources already consumed by construction.

`WorldState.release_all_reservations_for_colonist()` supports lifecycle cleanup, while `cleanup_stale_construction_reservations()` removes reservations whose owner is inactive or whose site is missing/completed. `get_construction_reservation_summary()` exposes read-only validation/debug information.

## Colonist Needs Foundation

Each colonist owns runtime Rest, Warmth, Shelter, and Hunger values clamped from 0 to 100. At night Rest declines slowly. Warmth and Shelter respond to completed Campfire/Cabin coverage, while daytime provides their existing slow recovery. Hunger declines continuously at `0.04` per process-second during day and night and never recovers automatically.

Needs are inspectable through a compact `R/W/S/H` label above each colonist, the selected-colonist panel, `Colonist.get_needs_state()`, and manager summaries. UI remains presentation-only. Hunger now drives eating but reaching zero still has no health, death, or mood effect.

At night, an idle colonist seeks Warmth below 60 or Shelter below 60 before accepting construction or random wandering. When both qualify, the lower value wins, with Warmth winning ties. `WorldState.get_nearest_warmed_cell()` and `get_nearest_sheltered_cell()` choose the nearest loaded, walkable, unblocked effect-covered cell derived from completed buildings. Need seeking begins only when `ReachabilityQuery` returns a loaded-cell path; the colonist follows it and waits in range until the need reaches 80. If no valid reachable target exists, normal work/wandering selection continues safely.

Existing `moving_to_construction` and `constructing` activity is not interrupted by needs. Need seeking is reconsidered at the next idle decision, so current need behavior does not add reservation abandonment during active construction.

## Colonist Eating Behaviour

When an idle colonist has Hunger below 60, it asks `WorldState.request_consume_food(colonist_id, 1)` for one Food. `WorldState` validates the colonist id/amount and delegates to `ResourceStockpile.request_spend_resources()`, so unavailable or reserved Food cannot be double-spent. A successful unit restores 25 Hunger and enters the visible `eating` activity for 0.75 seconds. The colonist takes another unit after that delay while below the target of 85, stopping at the target, at 100, or when Food is unavailable.

Idle priority is warmth/shelter seeking, then eating, then normal job selection, then wandering. Existing wandering, need-seeking, travel, construction, and harvesting are not interrupted; hunger is reconsidered on the next idle decision. Failed Food requests do not change Hunger, Food, activity, jobs, or reservations.

Eating activity/timers are transient and excluded from version `2`. Hunger and the already-spent stored Food total persist, and imported colonists resume idle so low Hunger can request Food again. Physical ground Food cannot be eaten until hauled into storage; there is no cooking, meals, dining, starvation damage, or mood effect.

Colonist Rest/Warmth/Shelter/Hunger values are included in version `2` records. Existing version-2 records without Hunger import it as 100. Seeking activity remains transient; restored colonists resume idle and re-evaluate needs normally.

## Colonist Identity And Selection

`ColonistManager` assigns every spawned colonist a unique spawn-order id (`colonist_0001`, etc.) and deterministic first/last name from small built-in name lists. `Colonist` owns `colonist_id`, `first_name`, `last_name`, and `nickname` for the lifetime of that runtime instance. `set_nickname(value)` trims and updates the authoritative runtime nickname.

Outside building-placement mode, clicking within a colonist's visual area selects the nearest colonist, displays a simple bottom-left panel, and shows a small selection diamond. The panel reads identity, activity, Rest/Warmth/Shelter/Hunger, relationships, traits, and skills. Clicking terrain clears selection. The panel and marker are presentation only.

Colonist ids, names, nicknames, current cells, exact world positions, and needs persist in version `2`. Selection remains UI-only and is cleared when `ColonistManager` replaces the population during load.

## Colonist Skills Foundation

Each `Colonist` owns runtime records for Construction, Mining, Plants, Cooking, Crafting, Animals, Medicine, Research, Shooting, Melee, and Social. Every record has a clamped level from 0 to 20, non-negative XP initialized to 0, and a passion value of `none`, `minor`, or `major`. `get_skills()` returns a defensive deep copy; `get_skill_level()` and `get_skill_passion()` expose focused read-only queries.

`ColonistManager` deterministically generates skills from spawn order. General levels vary from 0 to 9, with one major-passion specialty raised to 9–16 and one distinct minor-passion specialty raised to 6–12. This provides varied but bounded starting profiles without adding a random persistence dependency.

The selected-colonist panel displays all skills in the supported order. `+` marks minor passion and `++` marks major passion. The panel reads colonist accessors and owns no skill state. Skills are display-only: Construction level does not modify the existing `construction_work_rate`, and there is no XP gain or progression yet.

Skill levels, XP, and passions persist in version `2` colonist records. XP gain/progression remains unimplemented.

## Colonist Traits Foundation

Each `Colonist` owns one to three runtime trait records containing `id`, `display_name`, `description`, and a `modifiers` dictionary. The initial registry contains Hard Worker, Lazy, Night Owl, Brave, Coward, Fast Learner, Kind, and Greedy. `get_traits()` returns defensive copies, while `has_trait()` and `get_trait_display_names()` provide focused reads.

`ColonistManager` generates traits deterministically from spawn order. Registry exclusions prevent Hard Worker with Lazy and Brave with Coward. Invalid, duplicate, or conflicting initialization data is also rejected when the colonist normalizes its records.

Hard Worker multiplies the existing construction work rate by 1.25, Lazy multiplies it by 0.75, and Night Owl multiplies night Rest decay by 0.5. Modifier values are defined in the trait registry and combined through one inspectable modifier-product helper. Brave, Coward, Fast Learner, Kind, and Greedy are display-only; skill XP and mood/relationship systems do not exist yet.

The selected-colonist panel displays trait names above the compact skill list and owns no trait data. Version `2` stores trait ids and rebuilds full records from the current registry during import.

## Colonist Relationships

Each `Colonist` owns runtime relationship records containing `relation_type`, `target_colonist_id`, and `target_display_name`. Supported types are `parent`, `child`, `sibling`, and `partner`. `add_relationship()` rejects invalid types, empty targets, self-links, and duplicate target links; `get_relationships()` returns defensive copies and `has_relationship_with()` provides a focused query.

After the fixed population is fully spawned, `ColonistManager` deterministically links the first two colonists as reciprocal partners and the next two as reciprocal siblings when enough colonists exist. Parent/child generation is deferred because no age model exists. Other colonists have no relationships.

The selected-colonist panel shows a Relationships section with relation labels and target names, or `None` when the selected colonist has no links. Version `2` stores relation type plus stable target id; display names are resolved after the full population is restored and missing targets are skipped.

## Persistent Colonist Records

`Colonist.export_state()` serializes identity, cell/exact world position, Rest/Warmth/Shelter/Hunger, complete skill records, trait ids, relationship type/target-id pairs, and work priorities. `Colonist.import_state()` clamps needs, supplies compatible defaults, and resets transient activity, construction/harvest/haul assignments, carried payload, movement target, current path/index, and selection.

`ColonistManager.export_colonist_records()` exports the live population. Import validates unique non-empty ids, replaces existing nodes, restores each individual, resolves relationship names from the completed id map, updates the future runtime-id counter, and emits `population_replaced`. `Main` responds by clearing selection and the info panel.

`SaveGameService` version `2` restores world generation, `WorldState`, and chunk deltas before colonists. Version `1` saves are rejected because no migration system exists. Worker/resource reservations, current activity/jobs, movement targets, cell paths/path indices, debug labels, and UI selection are intentionally absent.

## Colonist Work Priorities

Each colonist owns one priority value for Construct, Harvest, Haul, Mine, Farm, Cook, Craft, Doctor, Research, and Guard. Values use `0` for disabled and `1` through `4` for enabled work, with `1` highest. Construct and Harvest default to `2`; implemented Haul defaults disabled (`0`), as do unimplemented future work types.

Idle decision-making retains the established need order: warmth/shelter seeking, then eating, then enabled work. `WorldState` exposes stable-id-ordered, non-mutating availability snapshots bounded to 16 results per implemented work type. `collect_available_jobs()` evaluates each result and projects only reachable construction sites, harvest orders, and haulable items into transient candidates. Haul requires both a path to the item and a path from the item to its proposed zone destination. `choose_best_job()` tries lower numeric priorities first and uses construction, harvest, then haul as the equal-priority source order. Only an authoritative successful reservation can be selected; start-time revalidation immediately releases a reservation if the path has become invalid.

Candidates contain `job_type`, `priority`, `target_id`, `target_cell`, and `reservation_result`; haul candidates also carry the proposed destination. They are a small Colonist-owned selection boundary, not authoritative job records or a general job board. Availability does not reserve work or storage. Haul reservation recomputes its destination and revalidates capacity before mutation. Disabled work types are not queried, and WorldState retains focused construction/harvest/haul authority.

The selected-colonist panel displays the complete matrix. Construct, Harvest, and Haul buttons cycle `0 -> 1 -> 2 -> 3 -> 4 -> 0` through the colonist API; the panel stores no priority authority. Priorities persist in version `2`. Current activity, job assignment, carried item, and reservations remain transient.

## Current Playable Loop

The implemented loop supports deterministic Wood/Stone/Food resource generation, harvest designation and worker completion, physical ground-item creation, optional hauling into player-authored stockpile zones, Campfire/Cabin/Storehouse placement and completion, derived light/warmth/shelter/storage effects, colonist need seeking and stored-Food consumption, chunk unload/reload reconstruction, and version `2` state serialization through the helper service.

Harvest output remains physical and does not require free abstract storage capacity. Capacity is checked only when a Haul job reserves and deposits an item. Loaded-cell reachability and transient orthogonal paths are implemented; off-screen routing, asynchronous/cached navigation, shelter occupancy enforcement, farming, combat, weather, save migration, and a production save/load flow are not implemented.

## Known Architectural Risks

- `Main` creates and wires `WorldState`; `WorldState` owns construction reservations and its `ResourceStockpile` owns resource earmarks.
- Terrain classification still lives in `WorldGenerator`, while terrain metadata queries live in `TerrainConfig`.
- Elevation classification is an early deterministic prototype and does not yet support slopes, cliff faces, mining deltas, or pathfinding-aware elevation transitions.
- Manual tile overrides can be exported/imported by `ChunkManager`, but still live outside `WorldState`.
- The general job layer is intentionally limited to transient candidate selection inside `Colonist`; construction and harvesting still have separate authoritative reservation/completion APIs, and there is no shared job board.
- Scene-level exported values materially affect the baseline and must be checked before changing defaults in scripts.
- Chunk streaming and prop lifecycle are centralized in `ChunkManager`; this is simple now but may need narrower responsibilities later.
- Loaded `ResourceNode` records participate in live harvest validation. Off-screen or unloaded resources cannot currently supply valid work snapshots even though their base spawn is deterministic.
- `TimeState` pause/scale controls only clock advancement; colonist needs, work, and movement are still driven by raw process delta.
- `SaveGameService` is a non-autoload helper service with no production caller; no project-wide simulation autoload state exists.
- `ProcSpriteCache` is static hidden global state, but it is presentation-only, reconstructible, and excluded from persistence.
- `ReachabilityQuery` performs a synchronous BFS bounded to 4,096 visited loaded cells for every requested path. It has no cache, async execution, off-screen routing, diagonal movement, or terrain-cost model.
- Candidate collection can run up to 16 construction paths, 16 harvest paths, and two path queries for each of 16 haul items per idle decision. The bound prevents an unbounded scan but can defer valid work beyond the first 16 stable-id-ordered available records.
- Newly generated runtime ids remain spawn-order based, while loaded version `2` records preserve their saved stable ids.
- Skill generation is likewise tied to spawn order; there are no XP thresholds, decay, learning, or gameplay modifiers yet.
- Trait generation is tied to spawn order, and only construction speed and night Rest loss currently consume trait modifiers.
- Relationships are static spawn-order links with no ages, opinions, social simulation, events, or dynamic changes.
- Save import is ordered but not transactional: a failure in a later import stage can leave earlier owners already replaced. Current version `2` data is validated per owner, but future migration or user-facing load flows should stage validation before mutation.

## Planned Future Direction

These are documentation notes for future review, not implemented systems:

- Expand `WorldState` ownership only when a concrete simulation or persistence boundary requires it.
- Decide whether terrain classification rules should eventually move behind a dedicated terrain resolver or remain in `WorldGenerator`.
- Keep save/load changes aligned with `docs/SAVE_BOUNDARY.md`.
- Decide whether harvesting should remain click-driven on `ResourceNode` or move behind a job/interaction system.
- Revisit `ChunkManager` responsibilities if chunk streaming, resource persistence, and multiplayer authority grow.

## Main Files To Inspect First

- Project settings: `project.godot`
- Main scene: `scenes/Main.tscn`
- Root scene script: `scripts/main.gd`
- Simulation root: `scripts/simulation/world_state.gd`
- Resource totals: `scripts/simulation/resource_stockpile.gd`
- Time state: `scripts/simulation/time_state.gd`
- Save service: `scripts/simulation/save_game_service.gd`
- World generation: `scripts/world/world_generator.gd`
- Terrain metadata: `scripts/world/terrain_config.gd`
- Chunk streaming: `scripts/world/chunk_manager.gd`
- Reachability queries: `scripts/world/reachability_query.gd`
- Prop spawn rules: `scripts/world/props/prop_spawn_helpers.gd`
- Prop visuals: `scripts/world/props/prop_visual_config.gd`
- Prop prewarm: `scripts/world/props/prop_prewarm_config.gd`
- Resource interaction: `scripts/entities/resource_node.gd`
- Colonist spawning: `scripts/entities/colonist_manager.gd`
- Colonist records and transient path following: `scripts/entities/colonist.gd`
- Selected tile UI: `scripts/ui/selected_tile_panel.gd`
- Architecture notes: `PROJECT_ARCHITECTURE.md`
- Save boundary: `docs/SAVE_BOUNDARY.md`
- Asset replacement guide: `docs/ASSET_REPLACEMENT.md`
