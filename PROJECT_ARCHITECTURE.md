# Project Architecture

This document is a concise map of the current Godot colony sim prototype. It distinguishes current implementation from known risks and planned future direction. No gameplay system changes are implied by this document.

## Current Implementation

- `project.godot` targets Godot `4.7` feature tags and runs `res://scenes/Main.tscn`.
- No autoloads are currently configured.
- `Main.tscn` wires `Main`, `WorldGenerator`, `ChunkManager`, `TerrainLayer`, `GameplayYSort`, `StockpileZoneRoot`, `GroundItemRoot`, `ResourceRoot`, `ConstructionRoot`, `ColonistManager`, `Camera2D`, and UI nodes including `BottomToolbar` and `ArchitectMenu`.
- Terrain and tree/rock/Berry Bush props are streamed around the camera by `ChunkManager`.
- Generated tile info includes deterministic elevation and a placeholder `ROCK_WALL` cliff terrain for elevation `2`.
- Colonists are generated or restored by `ColonistManager`; `Colonist` nodes own persistent identity, position, needs, skills, traits, relationships, and work priorities alongside transient activity.
- Compatibility resource counts live in `ResourceStockpile`, while hauled Storehouse contents live in `WorldState` storage components. Aggregate read APIs combine both.
- Clock/day-night state lives in `TimeState`, owned by `WorldState`. Its pause and scale values affect clock advancement only, not all colonist simulation.
- Minimal save/load serialization exists through a non-autoload `SaveGameService`. It has no production UI or gameplay caller; current limits are documented in `docs/SAVE_BOUNDARY.md`.
- Campfire/Cabin/Storehouse lifecycle, completed light/warmth/shelter coverage, and Storehouse capacity derivation are simulation-authoritative; `ChunkManager` only streams replaceable visuals.
- Legacy stockpile zones remain authoritative loadable `WorldState` records with streamed overlays and optional compatibility hauling fallback, but are no longer player-creatable through active controls.
- Completed harvests create authoritative physical ground-item records; abstract stockpile totals change only through explicit stored-resource APIs.

## Scene And Node Ownership

- `Main` (`scripts/main.gd`): scene coordination, dependency injection, resource/time UI, transient control/area-drag ownership, colonist selection, manual Move input translation, and construction/harvest/zone request routing.
- `WorldState` (`scripts/simulation/world_state.gd`): authoritative construction/storage components/material deliveries/harvest orders, stockpile zones, and ground items; bounded deterministic availability snapshots; effect queries; completed-Storehouse capacity derivation; and validated stockpile requests.
- `ResourceStockpile` (`scripts/simulation/resource_stockpile.gd`): legacy abstract stored totals/shared capacity, generic capacity reservation support, no-storage construction/eating bootstrap mutations, and notifications.
- `TimeState` (`scripts/simulation/time_state.gd`): authoritative runtime clock, day/night phase, clock-only pause/scale controls, and time/phase notifications. Colonist movement, work, and needs continue from their own process delta.
- `SaveGameService` (`scripts/simulation/save_game_service.gd`): non-autoload version `2` coordinator for world/chunk/colonist export and ordered import, currently used only by debug or validation code.
- `WorldGenerator` (`scripts/world/world_generator.gd`): climate noise, direct elevation/terrain classification, tile info construction through `TerrainConfig`, chunk data generation, and resource spawn planning.
- `ChunkManager` (`scripts/world/chunk_manager.gd`): chunk/resource lifecycle for trees, rocks, and Berry Bushes; live resource indexes; authoritative depletion deltas; resource snapshot/commit integration; placement queries; and construction/stockpile-zone/ground-item projection.
- `ReachabilityQuery` (`scripts/world/reachability_query.gd`): stateless, bounded orthogonal BFS over currently loaded cells. It reads effective terrain/resource occupancy from `ChunkManager` and construction occupancy from `WorldState`; it owns no authoritative state, cache, or projection.
- `ResourceNode` (`scripts/entities/resource_node.gd`): loaded resource interaction and visual host. It carries the live resource id, type, yield, and cell consumed by `ChunkManager` harvest snapshots. It emits designation intent and does not mutate stockpile, order, construction, or depletion state itself.
- `StockpileZoneVisual` (`scripts/world/stockpile_zone_visual.gd`): presentation-only marker for one loaded authoritative zone cell.
- `GroundItemVisual` (`scripts/world/ground_item_visual.gd`): presentation-only resource-type/amount placeholder for one loaded authoritative ground item.
- `ResourceVisualDefinition` (`scripts/world/props/resource_visual_definition.gd`): presentation-only resource scene/icon paths, procedural profile ids, and placeholder ids keyed by resource kind.
- `BuildingDefinition` (`scripts/buildings/building_definition.gd`): Campfire/Cabin/Storehouse registry including footprints, costs, work, effects, Architect ordering, visual profile ids, optional scene/icon paths, and placeholder palettes.
- `ConstructionSiteVisual` (`scripts/buildings/construction_site_visual.gd`): definition-configured preview/effect wrapper, optional external scene host, and fallback procedural placeholders; never authoritative.
- `TerrainConfig` (`scripts/world/terrain_config.gd`): terrain atlas, display, walkability, mineability, placement, and resource support metadata.
- `TerrainLayer`: tile rendering for ground terrain.
- `GameplayYSort`: shared Y-sort branch for resource nodes and colonists.
- `StockpileZoneRoot`: parent for loaded stockpile-zone cell projections.
- `GroundItemRoot`: parent for loaded physical-item projections.
- `ResourceRoot`: parent for streamed `ResourceNode` instances.
- `ConstructionRoot`: parent for construction-site projections belonging to loaded chunks.
- `ColonistManager` (`scripts/entities/colonist_manager.gd`): population export/replacement, stable-id relationship resolution, deterministic new-population generation, hit queries, dependency injection, and stale-reservation audit.
- `ColonistTraitRegistry` (`scripts/entities/colonist_trait_registry.gd`): static trait metadata, conflict exclusions, and bounded modifier values.
- `Colonist` (`scripts/entities/colonist.gd`): authoritative persistent identity/position/needs/skills/traits/relationships/work priorities plus transient player Move commands, construction/material-delivery/harvest/haul/eating/need-seeking activity, current cell path, and cleanup.
- `Camera2D` (`scripts/camera_controller.gd`): camera movement and zoom.
- UI nodes: resource counter label, selected tile panel, read-only selected colonist info panel, request-only bottom toolbar, and transient Architect submenu.

## Bottom Toolbar And Architect UI Flow

1. `BottomToolbar` emits a building id, Harvest-mode request, or Cancel request; it owns no simulation records and exposes no stockpile-zone action.
2. Architect toggles the sibling `ArchitectMenu`. The script generates one button per stable id returned by `BuildingDefinition.get_building_ids()`, using definition display/icon/cost/footprint metadata.
3. Selecting a building closes the submenu, emits its stable id, and enters the existing placement mode. `Main` actively exposes Normal/Build/Harvest modes and projects the current mode back into the toolbar label.
4. Harvest mode supports a `ResourceNode` single-click release or a Main-owned click-drag rectangle. Main observes press/motion, displays a transient cell-aligned polygon, and consumes only releases reaching the six-pixel drag threshold.
5. `ChunkManager.get_loaded_resources_in_cell_rect()` returns read-only metadata for loaded tracked nodes. Main submits every returned resource id separately through the existing `WorldState.request_designate_harvest()` authority and records result counts.
6. Cancel, Escape, right-click, or leaving an area mode clears transient drag/preview state and disables harvest-click intent.
7. Keyboard shortcuts remain alternate input into active `Main` methods; `Z` has no stockpile-mode action. No toolbar/menu state, selected button, UI mode, drag state, preview geometry, or result label enters save data.

## Stockpile Zone Flow

1. No active `Main`, toolbar, or keyboard path creates zones. Dormant control helpers and the validated request API remain only for compatibility.
2. `WorldState` validates non-empty loaded cells against `ChunkManager` terrain queries, rejects water/non-walkable/mineable cliff cells, construction occupancy, and existing zone overlap, then assigns a stable `stockpile_NNNN` id.
3. Zone records contain `zone_id`, cells, enabled state, and label. A cell index answers membership and preserves overlap invariants; construction placement also rejects indexed zone cells.
4. Zone signals tell `ChunkManager` to add/remove blue `StockpileZoneVisual` projections for loaded cells. Chunk unload deletes projections only; generation queries the authoritative records and recreates them.
5. `SaveGameService` stores zones in `deltas.stockpile_zones`. Import restores construction first, then zones, and emits replacement so loaded overlays rebuild.
6. Zones do not own capacity or items. They remain a temporary legacy Haul fallback only while no completed Storehouse storage component exists; shared legacy capacity and deposit mutation remain in `ResourceStockpile`/`WorldState` for that compatibility path.

## Asset Replacement Flow

1. Gameplay ids select authoritative definitions; visual profile ids and scene/icon paths are presentation fields inside those definitions.
2. `ConstructionSiteVisual` receives visual metadata from `BuildingDefinition`, draws the matching fallback profile, or instantiates the configured state-specific `Node2D` scene.
3. `BottomToolbar` generates Architect buttons from the same definitions and emits only stable building ids.
4. Resource spawn data keeps its stable kind/type/yield/cell. `ResourceVisualDefinition` resolves the default scene and procedural profile without entering resource state or save data.
5. `PropVisualConfig`, tree/rock profile scripts, and `ProcSpriteCache` remain an isolated procedural presentation pipeline. Berry Bush and colonist placeholder art remain replaceable scene-local children.
6. Rendered nodes, palettes, icons, external visual scenes, and generated textures are excluded from persistence. See `docs/ASSET_REPLACEMENT.md` for replacement contracts.

## World Generation Flow

1. `ChunkManager` computes the camera-centered chunk window.
2. Missing chunks are queued, sorted by distance, and generated over multiple frames.
3. `WorldGenerator.generate_chunk()` visits each cell in the chunk.
4. `WorldGenerator.sample_climate()` samples deterministic height, moisture, terrain detail, and landmass noise.
5. `WorldGenerator._classify_elevation()` assigns generated elevation `0`, `1`, or `2`.
6. `WorldGenerator._classify_terrain()` directly chooses the terrain name; elevation `2` becomes `ROCK_WALL`.
7. `TerrainConfig` supplies atlas tile variants, walkability, and mineability through query helpers.
8. `PropSpawnHelpers.build_resource_spawn()` checks terrain support and deterministic density rolls for tree, rock, or Berry Bush spawn data.
9. `ChunkManager` writes terrain tiles immediately and spawns resource nodes immediately or through staged batches.
10. `PropVisualConfig` and the procgen profile scripts provide deterministic procedural sprite settings.
11. Manual tile overrides and depleted resource ids are stored outside loaded chunk dictionaries and reapplied/skipped during chunk generation.

Generated-resource authority is divided across deterministic spawn data, `ChunkManager`'s live index and depletion set, and the loaded `ResourceNode` record. The live node is therefore more than a visual projection during harvest validation, even though it does not authorize stockpile or order mutations.

There are no separate `biome_config.gd`, `biome_resolver.gd`, or `region_registry.gd` files in the current repository. Biome-like terrain selection is currently embedded in `world_generator.gd`, with terrain metadata in `terrain_config.gd`.

## Resource Harvesting Flow

1. `WorldGenerator` and `PropSpawnHelpers` produce tree/rock/Berry Bush spawn records as part of chunk generation.
2. `ChunkManager` instantiates `Tree.tscn`, `Rock.tscn`, or `BerryBush.tscn` under `ResourceRoot`.
3. Each spawned scene uses `scripts/entities/resource_node.gd`. `ChunkManager` assigns the deterministic resource id/type/yield/cell to that loaded node and tracks it in `_resource_index`.
4. `ResourceNode` emits designation intent for an unconsumed left-button release; it does not mutate stockpile, orders, construction, or depletion state. Main consumes area-drag releases, preventing the same gesture from also becoming a single click.
5. For area input, `ChunkManager` returns defensive metadata for currently loaded resources inside the inclusive cell rectangle. For every single or area request, it builds the read-only live-resource snapshot from the indexed `ResourceNode` and supplies that snapshot to `WorldState.request_designate_harvest()`.
6. `WorldState` owns active order records and transient reservation owner ids. Order signals drive the optional marker projection on loaded `ResourceNode` instances.
7. Idle colonists consider critical needs, eating, and construction before claiming an available harvest order. Claiming reserves only the authoritative order; stored capacity is irrelevant until a later Haul job deposits the item.
8. Completion prevalidates the worker, live resource snapshot, and deterministic pending item record before mutation.
9. `ChunkManager.commit_harvest_resource()` records depletion/removes loaded source tracking. WorldState then publishes the prepared ground item and removes the completed order without changing `ResourceStockpile`.
10. A failed preflight or depletion commit changes none of those owners. Active orders save as intent; worker reservations and colonist activity remain transient.

## Physical Ground Item Flow

1. `WorldState` owns stable records with item id, resource type, amount, cell, and enabled state. It exposes create/remove/list and cell-rectangle queries.
2. Harvest completion prepares the next unique item record before source mutation. Successful depletion is followed by a guaranteed record commit and add signal; invalid input never partially depletes or drops.
3. `ChunkManager` projects enabled records in loaded chunks through `GroundItemVisual`. Unload removes nodes only, while chunk generation and replacement signals recreate them.
4. `SaveGameService` stores authoritative records in `deltas.ground_items`; visual nodes are excluded.
5. Items have no collision-based resource interaction and cannot be harvested. Haul may carry/deposit one complete item; stacking merge/split, filters, direct consumption, and decay do not exist.

## Hauling Flow

1. Haul uses the general Colonist candidate interface and is disabled by default. The info panel can enable/cycle its priority without owning policy.
2. `WorldState.get_available_haul_item()` considers enabled loaded items, treating items inside enabled zones as already stored only while no Storehouse component exists, then selects a valid loaded deposit cell adjacent to a completed Storehouse with enough component capacity.
3. If no Storehouse component exists, the same query can fall back to a valid loaded stockpile-zone cell with enough `ResourceStockpile` compatibility capacity. Once any component exists, a full or unavailable Storehouse produces no Haul candidate instead of falling back to a zone.
4. `reserve_haul_item()` reserves the complete item amount against the selected Storehouse component or legacy stockpile capacity and records the worker, destination kind, destination cell, item snapshot, pickup cell, and pickup state transiently.
5. Colonist movement reaches the item, `request_pickup_ground_item()` removes the ground record/projection, then movement continues to the reserved destination cell.
6. `request_deposit_carried_item()` revalidates owner, item, destination, selected storage owner, and capacity. Storehouse deposits consume the component reservation and add the complete amount to component contents. Legacy stockpile-zone deposits consume the `ResourceStockpile` capacity reservation and add the complete amount to compatibility totals.
7. Cancellation before pickup leaves the item and releases capacity. After pickup, the colonist drops an equivalent item at its current cell; stale-owner cleanup falls back to the pickup cell.
8. Assignment requires a loaded-cell path to the item and from the item to the proposed destination. The route to the destination is recomputed after pickup; failure uses the existing drop-and-release cleanup. No filtering, partial carrying, multiple carried items, Storehouse-to-Storehouse hauling, or off-screen routing exists.

## Reachability And Colonist Movement Flow

1. `ReachabilityQuery.find_path()` runs a synchronous orthogonal BFS through currently loaded cells, capped at 4,096 visited cells by default. Returned paths exclude the start cell and include the target.
2. Effective non-walkable, water, `ROCK_WALL`, and mineable cells are blocked. Construction footprints and generated resources are blocked except for an explicitly allowed job target. Stockpile zones and ground items are non-blocking.
3. `ChunkManager` remains the source for loaded/effective terrain and generated-resource occupancy. `WorldState` remains the source for construction occupancy and all job/reservation mutation. The query helper owns no authoritative state.
4. Each `Colonist` owns only its transient player command, manual destination, current path, and index. Manual Move, wandering, construction, harvest, haul pickup/deposit, warmth, and shelter movement advance cell by cell through the existing world-position conversion.
5. `Main` converts a selected-colonist Normal-mode right click into a destination cell. The colonist validates reachability before mutation, then replaces any previous Move and abandons active work through existing reservation/item cleanup.
6. While Move is active, autonomous idle/job selection does not run. Deselecting or selecting another colonist does not alter the command.
7. A step that becomes invalid fails the activity safely. Manual Move clears and resumes idle AI; job movement releases its authoritative reservations, and haul cleanup restores a carried item according to existing drop rules.
8. Paths and player commands are cleared on idle, completion, failure, and import. They are not serialized.

## Berry Bush Flow

1. `TerrainConfig.BERRY_BUSH_TERRAINS` allows bushes on Grass, Dark Dirt, and Mud.
2. After tree/rock selection fails, `PropSpawnHelpers` uses salt `211` for a separate deterministic bush roll. Base density is `0.055`, with Dark Dirt at `0.9×` and Mud at `1.15×`.
3. A spawn record uses scene key `berry_bush`, resource type `food`, and yield 6. `ChunkManager` derives the stable id `berry_bush:x:y` exactly like existing props.
4. `BerryBush.tscn` supplies a placeholder polygon/collision visual while shared `ResourceNode` emits designation intent.
5. Valid order completion adds `food` through the `WorldState` transaction and records the stable id in generic depletion state.
6. Version `2` remains backward compatible: stockpile export/import includes `food`, world deltas include depleted Berry Bush ids, and active intent may include the bush order.

## Manual Tile Placement Flow

1. `Main` submits selected terrain placement through `ChunkManager.request_place_manual_tile(cell, terrain_name)`.
2. `ChunkManager` validates loaded-cell availability, known terrain names, and valid atlas coordinates before mutating state.
3. Placement returns a result dictionary with `ok`, `reason`, `cell`, and `terrain_name`.
4. Failed placement requests do not update manual overrides, loaded chunk lookup, or terrain visuals.

## Elevation Flow

1. `WorldGenerator.sample_climate()` produces deterministic height and terrain detail values.
2. `WorldGenerator._classify_elevation()` maps those values to elevation `0`, `1`, or `2`.
3. Tile info stores `elevation`, `walkable`, and `mineable`.
4. Elevation `2` is rendered as `ROCK_WALL` using existing stone atlas tiles, is non-walkable, and is marked mineable.
5. `ChunkManager.get_effective_tile_info(cell)` returns loaded/manual-effective tile metadata; `get_cell_elevation(cell)` and `is_cell_mineable(cell)` expose focused queries.

## Construction Placement Flow

1. `Main` toggles generic building-placement mode with `B`; building buttons or keys `1` through `3` select Campfire, Cabin, or Storehouse. It asks `WorldState` to validate the selected building at the mouse cell for preview coloring.
2. On left-click, `Main` calls `WorldState.request_place_construction(selected_building_id, cell)`.
3. `WorldState` resolves the `BuildingDefinition`, builds its footprint, and reads loaded-cell, effective-terrain, and generated-resource occupancy through `ChunkManager` queries.
4. Unknown definitions, invalid footprints, unloaded/non-walkable/blocked terrain, resources, and existing construction occupancy are rejected without mutation.
5. A valid request creates the authoritative incomplete site record and occupied-cell index in `WorldState`.
6. `ChunkManager` receives the site signal and spawns a placeholder under `ConstructionRoot` only if its origin chunk is loaded.
7. Chunk unload deletes the placeholder node only. Chunk reload reads current `WorldState` records and recreates the visual.

## Storehouse Storage Component Flow

1. `WorldState` derives storage component records from completed Storehouse construction records.
2. Each component is linked to one placed building instance by construction site id, building id, origin cell, occupied cells, and definition storage capacity.
3. Incomplete Storehouses and non-storage buildings do not produce components.
4. Storehouse hauling writes item amounts into component contents and reserves per-component capacity. Worker construction and eating consume component contents once storage exists; legacy totals remain a no-storage bootstrap fallback.
5. Aggregate resource read APIs and the resource UI include both `ResourceStockpile` totals and Storehouse component contents.
6. Components are rebuilt when construction completion or construction import refreshes storage capacity. They are not saved as a separate top-level version-2 section; completed construction records remain the persistence source and carry additive `storage_contents`.
7. Public component APIs return defensive snapshots only. UI and rendering own no component state.
8. `Main` keeps only the transient selected storage id. It resolves completed-building clicks through `get_construction_site_at_cell()`, matches the component by construction site id, and refreshes the read-only `StorageInspectorPanel` from defensive `WorldState` snapshots.

## Construction Completion Flow

1. With the cursor over a site, `Main` submits its remaining build amount through `WorldState.request_progress_construction()` when `C` is pressed.
2. `WorldState` rejects unknown/completed sites, missing definitions, invalid amounts, and invalid required build amounts before mutation.
3. On first worker progress, `WorldState` consumes the site's Storehouse allocation; the direct debug/bootstrap path without a worker reservation may spend only currently available legacy stock.
4. Missing allocations or insufficient reserved component contents leave totals, reservation state, consumed-resource state, and progress unchanged.
5. Successful first progress records the full consumed cost; later progress does not spend it again.
6. Reaching the definition's build amount marks the record completed and signals `ChunkManager` to update its projection.

## Colonist Construction Work Flow

1. `WorldState` evaluates construction sources in order: available Storehouse contents, loose matching ground-item stacks within a 12-cell site radius, then legacy totals only when no Storehouse exists.
2. Ground-item lookup uses a simulation-owned cell index and loaded cells inside the bounded rectangle; it does not scan all map items. Delivery candidates exclude disabled, ordinary-Haul-reserved, construction-delivery-reserved, mismatched, oversized, and out-of-radius items.
3. A Construct worker requires a path to the item and then to the construction origin before reserving one site-item pair. Pickup removes the authoritative ground item; delivery adds the complete stack to the site's authoritative `delivered_resources`.
4. Storehouse contents that can cover the complete outstanding cost suppress delivery candidates. If Storehouse contents are insufficient, loose delivery covers only the deficit. With no Storehouse, reachable loose delivery precedes legacy bootstrap spending.
5. Once delivered plus stored/bootstrap sources cover the cost, `reserve_construction_site()` allocates only the undelivered remainder and assigns the site worker. Competing reservations fail without mutation.
6. Before construction, the colonist requires a path to the site's origin with the construction target exception. At the origin it submits `get_effective_construction_work_rate() * delta` through `request_progress_construction(site_id, amount, colonist_id)`.
7. The first valid progress tick consumes the reserved undelivered remainder and marks the complete required cost consumed. Delivered materials and stored allocations cannot be consumed twice; later ticks only add build progress.
8. Delivery abandonment releases an unpicked item or restores a picked item. Path invalidation and manual Move reuse the same cleanup. Cancellation restores delivered resources if construction has not consumed them.
6. Releasing work before first progress releases the allocations and restores availability. Completion clears the worker reservation and returns the colonist to idle.
7. Construction enters this focused activity through the shared Colonist candidate selector while retaining its separate WorldState authority.

## Construction Reservation Cleanup Flow

1. Colonists call `release_construction_reservation()` when work fails, ownership/site validation fails, travel times out, or work is abandoned.
2. `_exit_tree()` calls `release_all_reservations_for_colonist()` so normal despawn/deletion cannot retain work or material allocations.
3. `ColonistManager` reports non-deleting colonist ids and calls `cleanup_stale_construction_reservations()` every two seconds as a safety net.
4. `WorldState` treats missing owners, missing sites, and completed sites as stale and releases their worker reservations.
5. If associated material allocations still exist, cleanup releases them and restores availability. If construction already consumed them, component contents remain spent.
6. Cleanup never changes construction progress, completion, or consumed-resource records.

## Construction Cancellation Flow

1. `Main` resolves the site under the cursor and calls `WorldState.request_cancel_construction(site_id)` when `X` is pressed.
2. `WorldState` rejects empty ids, unknown sites, and completed Campfires before mutation.
3. Valid cancellation releases the worker reservation and any still-unconsumed Storehouse material allocations.
4. Consumed resources are not refunded; cancellation only removes the unfinished record and its occupied-cell mappings.
5. `construction_site_cancelled` tells `ChunkManager` to remove the matching loaded projection. Rendering does not authorize removal.
6. Colonists moving to the site detect lost reservation ownership; constructing colonists detect the missing site. Both return to idle through their existing failure path.
7. Because the authoritative record is erased, subsequent save exports omit it and chunk reload cannot recreate it.

## Completed Building Effect Flow

1. Campfire effect metadata lives in `BuildingDefinition`: light radius 4, warmth radius 3, and `light`/`warmth` tags.
2. `WorldState.get_completed_building_effects()` scans authoritative construction records and emits definition-derived sources only for completed buildings.
3. `get_effects_at_cell()` performs cell-distance coverage checks; focused `is_cell_lit()` and `is_cell_warmed()` queries expose the result.
4. Incomplete and cancelled sites provide no source. Effects remain queryable while their origin chunk is unloaded because authority is independent of projections.
5. `ChunkManager` supplies completed visuals with definition radii. Warmth is always marked; light glow is shown at night by asking `WorldState` for presentation phase.
6. Day/night changes only reconfigure loaded visual projections and never change completed-building authority.

## Cabin Construction And Shelter Flow

1. In build mode, `1` selects Campfire and `2` selects Cabin; `Main` still submits generic building-id placement requests to `WorldState`.
2. Cabin definition specifies id `cabin`, 2×2 footprint, 20 wood, 30 work, shelter radius 2, capacity 2, and the `shelter` tag.
3. Generic placement expands the 2×2 footprint and validates/tracks all four cells. Generic stockpile reservation and colonist work consume Cabin cost and progress its larger build amount.
4. `ChunkManager` configures the projection from the building definition. The shared visual draws a four-cell scaffold while incomplete and a cabin placeholder when completed.
5. Completed effect records include optional shelter radius/capacity. `get_shelter_sources()`, `get_shelter_at_cell()`, and `is_cell_sheltered()` expose focused authoritative queries.
6. Campfires have no shelter metadata and therefore never appear as shelter sources. Incomplete Cabins provide no effect.
7. Save/load stores the existing generic construction record; shelter authority and visuals are re-derived from the `cabin` definition.

## Storehouse And Storage Capacity Flow

1. Build-mode key `3` selects Storehouse: 3×2 footprint, 30 Wood/10 Stone, 50 work, and +100 shared storage capacity.
2. Existing generic placement, occupancy, reservation, construction, cancellation, projection, streaming, and save flows process the definition without a separate building system.
3. `WorldState._refresh_storage_capacity()` starts from `ResourceStockpile.BASE_STORAGE_CAPACITY` (100) and adds definition metadata only for completed authoritative Storehouse records.
4. Completion and construction-state import refresh the stockpile limit. Chunk unload only removes projections and cannot change capacity.
5. `ResourceStockpile` computes available compatibility storage from capacity minus compatibility totals and legacy capacity reservations; harvest itself creates none because output first remains on the ground.
6. Storehouse Haul reserves the full item amount on one storage component at assignment, consumes that reservation at deposit, and then adds the full amount to component contents. Legacy zone Haul keeps the previous `ResourceStockpile` reservation/deposit path only in worlds with no completed storage component.
7. Existing/imported totals remain lossless even if over capacity.
8. The resource panel reads aggregate stored and capacity values from `WorldState`; signals only trigger presentation refresh.
9. Version `2` stores completed construction records, stockpile totals, and additive Storehouse `storage_contents`, not derived capacity. Load imports totals without deletion and re-derives capacity and components from Storehouses.

## Time Flow

1. `Main._process(delta)` calls `WorldState.advance_time(delta)`.
2. `WorldState` delegates to `TimeState.advance(delta)`.
3. `TimeState` updates the simulation clock and emits time/phase signals.
4. `WorldState` forwards those signals for presentation.
5. `Main` updates the existing UI label with the current time and day/night phase.
6. `TimeState.paused` and `time_scale` do not pause or scale `Colonist._process()`. Colonist movement, needs, and work continue from raw frame delta.

## Colonist Needs Flow

1. Each colonist updates its own Rest, Warmth, Shelter, and Hunger values during its simulation process and clamps them from 0 to 100.
2. The colonist converts its world position to the current map cell and asks `WorldState.is_night()`, `is_cell_warmed(cell)`, and `is_cell_sheltered(cell)` for environmental state.
3. Night reduces Rest using `get_effective_night_rest_decay_rate()`; Night Owl halves that decay. Warmth/Shelter keep their existing environment rules. Hunger declines by `hunger_decay_rate * delta` during both day and night and recovers only through successful eating.
4. `WorldState` remains the environmental authority: Campfire warmth and Cabin shelter are derived from completed construction records and definitions, not from visual nodes.
5. The overhead `R/W/S/H` label, selected-colonist panel, and manager summary expose values without owning or authorizing state changes.
6. At night, idle decision-making checks Warmth and Shelter thresholds before construction and wandering. The lower qualifying need wins, with Warmth winning ties.
7. `WorldState.get_nearest_warmed_cell()` and `get_nearest_sheltered_cell()` scan completed effect sources for the nearest loaded, walkable, resource-free, construction-free covered cell. `Colonist` then requires a `ReachabilityQuery` path before entering need-seeking.
8. `seeking_warmth` and `seeking_shelter` follow the transient cell path, hold position while the chosen effect recovers the need to 80, and safely return to ordinary idle selection if the source disappears, the route becomes blocked, or no reachable cell exists.
9. Hunger below 60 triggers stored-Food eating only from idle. Active movement/construction remains uninterrupted. Need values persist in version `2`; eating activity does not.

## Colonist Eating Flow

1. Idle selection checks warmth/shelter seeking first, eating second, normal jobs third, and wandering last.
2. Below Hunger 60, `Colonist` calls `WorldState.request_consume_food(colonist_id, 1)`.
3. `WorldState` validates the request and atomically deducts available `food` from stable-id-ordered Storehouse components. If no storage component exists, it delegates to legacy `ResourceStockpile` totals for bootstrap compatibility.
4. Success emits the normal stockpile signal, decreases the Food UI by one, restores 25 Hunger, and enters `eating` for 0.75 seconds.
5. After each delay, eating repeats while Hunger is below 85. It exits to idle at the target or immediately when Food is unavailable. Failure leaves Food and Hunger unchanged.
6. Eating does not move the colonist and does not interrupt wandering, warmth/shelter seeking, construction travel, or construction work. Those activities reconsider Hunger only after returning idle.
7. Eating state/timer is transient. Version `2` retains Hunger and resulting Food totals, then imported idle colonists make a fresh decision.

## Save/Load Flow

1. Debug or validation code creates `SaveGameService`; it is not an autoload and is not wired to a menu.
2. `SaveGameService.build_save_data()` asks `WorldGenerator`, `WorldState`, `ChunkManager`, and `ColonistManager` for authoritative state.
3. Version `2` includes world/time/stockpile/deltas, active harvest intent, and persistent colonist records.
4. Load validates version `2`, then restores generator config, `WorldState`, chunk deltas, and finally the colonist population.
5. `WorldState` import clears construction/resource/harvest reservations before old colonists are removed. After depletion ids load, orders targeting depleted resources are discarded. Imported colonists resume idle without job or movement-target state.
6. `ColonistManager` restores all nodes before resolving relationship target names from stable ids, then emits `population_replaced` so `Main` clears selection.
7. Version `1` is rejected without migration. Live world seed/config changes still do not fully regenerate already-loaded chunks.

## Colonist Identity And Selection Flow

1. `ColonistManager` allocates a unique spawn-order runtime id and deterministic first/last name before initializing each colonist.
2. The `Colonist` node owns its id, first name, last name, optional nickname, activity, and needs. `set_nickname()` is its current nickname mutation API.
3. On an ordinary left-click, `Main` asks `ColonistManager` for the nearest live colonist within the small visual hit radius.
4. `Main` clears the previous marker, applies the new marker, and passes the selected node to the colonist info panel. A terrain click passes `null`, hides the panel, and continues the existing manual terrain placement flow.
5. The colonist info panel reads and formats the selected node's identity/activity/needs/relationships/traits/skills each frame. It owns no colonist state and ignores mouse input.
6. Selection and panel projection remain transient. Version `2` saves colonist identity but `Main` clears selection after population replacement.

## Colonist Skills Flow

1. `ColonistManager` generates all eleven supported skill records from the colonist's spawn index before initialization.
2. Generation gives every skill a deterministic 0–9 base, then assigns one distinct major specialty at level 9–16 and one minor specialty at level 6–12.
3. `Colonist._set_initial_skills()` normalizes the input, guarantees the complete skill list, clamps levels to 0–20 and XP to non-negative values, and rejects unknown passion values back to `none`.
4. `Colonist.get_skills()` returns a deep copy, while focused level/passion accessors provide UI-safe reads.
5. The info panel formats the ordered list using no marker for `none`, `+` for `minor`, and `++` for `major`.
6. Skills do not affect construction or other gameplay and do not gain XP. Their level/XP/passion records persist in version `2`.

## Colonist Traits Flow

1. `ColonistTraitRegistry` defines the eight supported traits, descriptions, exclusions, and optional modifier dictionaries.
2. `ColonistManager` selects one to three trait ids deterministically from spawn order and skips duplicates or registry conflicts.
3. `Colonist` resolves ids to owned runtime records and independently rejects invalid, duplicate, or conflicting initialization input.
4. `get_traits()` returns deep copies; `has_trait()` and `get_trait_display_names()` expose focused reads for systems and presentation.
5. A single modifier-product helper resolves effective values. Hard Worker applies `1.25` and Lazy `0.75` to construction rate; Night Owl applies `0.5` to night Rest decay. Other traits currently have no modifiers.
6. The info panel displays names only. Version `2` saves trait ids and reconstructs definitions/modifiers from the registry.

## Colonist Relationships Flow

1. `ColonistManager` first spawns and initializes the complete colonist population so stable ids and display names are available.
2. With at least two colonists, indices 0 and 1 receive reciprocal `partner` links. With at least four, indices 2 and 3 receive reciprocal `sibling` links.
3. The `Colonist` relationship API supports `parent`, `child`, `sibling`, and `partner`, while rejecting invalid types, self-links, empty targets, and duplicate target links.
4. Parent/child links are not generated because the current model has no age data.
5. `get_relationships()` returns deep copies; the info panel formats each link as `Type: Target Name` and displays `None` for an empty list.
6. Relationships are static and have no simulation effects. Version `2` saves relation type/target id and re-resolves target names after population restoration.

## Persistent Colonist Load Flow

1. Each `Colonist` exports identity, current cell/exact position, Rest/Warmth/Shelter/Hunger, skills, trait ids, and relationship type/target-id records.
2. `ColonistManager` validates unique non-empty ids before clearing the current population.
3. It instantiates and imports every colonist with existing scene/dependencies, resetting activity, construction/harvest/haul assignment, carried payload, movement target, and selection to idle defaults.
4. A second pass resolves saved relationship target ids against the restored population. Missing/invalid targets are skipped.
5. The manager advances its runtime-id counter beyond restored generated ids and emits `population_replaced`; `Main` clears any selected-node reference and panel state.
6. Work priorities restore with each colonist record. No activity (including eating), worker/resource reservation, movement target, debug label, or UI state is serialized.

## Colonist Work Priority Flow

1. `Colonist` owns a normalized dictionary covering Construct, Harvest, Haul, Mine, Farm, Cook, Craft, Doctor, Research, and Guard. `0` disables work; `1` through `4` are enabled from highest to lowest priority.
2. Construct and Harvest default to `2`. Implemented Haul defaults to `0`, preserving older behavior until the player enables it; unimplemented types also remain `0`.
3. Idle selection checks warmth/shelter and eating before work. `WorldState` exposes up to 16 currently valid, unreserved records per implemented work type in stable-id order. These list queries do not mutate reservations or storage capacity.
4. `collect_available_jobs()` checks every returned record and emits enabled, currently reachable construction, harvest, and haul candidates in that source order. Haul validates both route legs from the proposed non-mutating destination.
5. Each candidate contains `job_type`, numeric `priority`, `target_id`, `target_cell`, and an initially empty `reservation_result`. Candidates are transient Colonist data and are not authoritative records.
6. `choose_best_job()` attempts authoritative reservation in ascending numeric priority order. Equal priorities retain collection order, so construction wins ties and stable-id order breaks ties within one work type. Failed reservations are skipped; only a successfully reserved candidate can be selected.
7. Haul availability computes a proposed destination without reserving capacity. `reserve_haul_item()` recomputes the destination and revalidates capacity immediately before mutation.
8. `start_job()` validates the reservation and route, then translates the candidate into focused construction, harvest, or hauling activity and transient path fields. A failed or newly unreachable start releases the WorldState reservation immediately.
9. `WorldState` remains authoritative for availability, reservations, pickup/deposit, progress, and completion through separate focused APIs. There is no shared job board.
10. The info panel reads a defensive priority copy and calls `set_work_priority()` for Construct, Harvest, and Haul buttons. It never retains a separate simulation value.
11. Colonist export includes the priority dictionary but excludes candidate lists/current jobs. Missing dictionaries in older version-2 records normalize to defaults, so `SaveGameService.SAVE_VERSION` remains `2`; activity and reservations still reset on import and work is rediscovered.

## Current Tuning Entry Points

- `scripts/world/world_generator.gd`: seed, terrain/climate tuning, chunk size, and tree/rock/Berry Bush density constants.
- `scripts/world/terrain_config.gd`: terrain tile variants, walkability/mineability, and terrain support queries for tree/rock/berry spawning.
- `scripts/world/props/prop_spawn_helpers.gd`: terrain-specific tree/rock/berry density multipliers and deterministic spawn rolls.
- `scripts/world/chunk_manager.gd`: load radius, chunks per frame, staged resource spawning, procedural sprite toggles, variant caps, and sprite sizes.
- `scripts/world/props/prop_visual_config.gd`: resource visual configuration derived from spawn data and procgen profiles.
- `scripts/world/props/prop_prewarm_config.gd`: procedural sprite prewarm requests.
- `scripts/procgen/tree_profiles.gd` and `scripts/procgen/rock_profiles.gd`: active procedural tree/rock archetypes, terrain tags, and size tiers.

## Known Architectural Risks

- Effect queries currently scan completed Campfire/Cabin records directly; a spatial index may be required if building counts become large.
- Terrain classification remains in `WorldGenerator`, while terrain metadata access for placement, preview, walkability, and prop support is centralized in `TerrainConfig`.
- Elevation is generated state only; mined/altered elevation is not implemented and would need player-delta persistence.
- Loaded `ResourceNode` identity/type/yield/cell fields participate in authoritative harvest validation. Harvest work is unavailable when the matching resource is not loaded/indexed, even though base spawn data is deterministic.
- Harvest designation starts from either a `ResourceNode` click or Main's transient area tool, while worker assignment, completion, depletion, and item creation are owned by `WorldState`/`ChunkManager`. The area query and shared job-candidate interface do not unify those authoritative transactions.
- Stockpile zones currently store explicit cell arrays and render one node per loaded cell. Large or numerous zones may eventually need compact rectangle/run storage and batched rendering.
- Manual tile overrides and depleted resource ids are saved through `ChunkManager`, but still live outside `WorldState`.
- Save/load is minimal; version `2` includes colonist persistence, but no menus, full scene reload, migration, general jobs, weather, or seasons exist.
- `ChunkManager` owns several responsibilities at once: streaming, terrain writes, resource lifecycle, staged spawning, and procedural cache prewarm.
- Scene-level exported overrides in `Main.tscn` are part of the real runtime baseline and can differ from script defaults.
- `TimeState` pause/scale controls only the clock; it is not a full simulation pause/speed authority for colonists.
- Camera zoom allows a script minimum of `0`, while `Main.tscn` overrides the script maximum from `2.0` to `200.0`. Reaching zero makes camera movement divide by `zoom.x`, and the scene/script tuning ranges are materially inconsistent.
- Harvest completion coordinates `ChunkManager` depletion and WorldState item creation after complete preflight. Future asynchronous/concurrent mutation would require an explicit transaction/rollback boundary.
- `SaveGameService.apply_save_data()` mutates owners in load order and cannot roll back earlier imports if a later owner rejects its data. A future user-facing load path should validate or stage the complete document before committing replacements.
- Reachability is synchronous, bounded to loaded cells, and recomputed without a cache. Each idle decision can evaluate up to 16 candidates per work type, including two paths per haul candidate; work beyond that stable-id-ordered window is deferred.

## Planned Future Direction

- Expand `WorldState` only when storage, jobs, persistence, or multiplayer authority need a concrete simulation owner.
- Decide whether terrain classification rules should eventually move behind a dedicated terrain resolver or remain in `WorldGenerator`.
- Follow `docs/SAVE_BOUNDARY.md` before expanding persistence beyond the current minimal state.
- Extend the candidate collector only when a concrete new work type is approved; keep focused authoritative reservation/completion APIs until shared semantics justify a broader job system.
- Split `ChunkManager` only when there is a concrete need, such as persistent chunk state, streaming scalability, or multiplayer authority.

## Intentional Constraints For Near-Term Tasks

- Do not assume missing biome split files exist.
- Do not introduce autoloads unless a task explicitly calls for that architectural change.
- Do not treat save/load as complete beyond the current minimal version `2` foundation.
- Keep world generation changes scoped to `WorldGenerator`, `TerrainConfig`, and prop helper entry points unless a task explicitly approves broader restructuring.
- Treat `Main.tscn` exported values as part of the baseline when auditing behavior.
