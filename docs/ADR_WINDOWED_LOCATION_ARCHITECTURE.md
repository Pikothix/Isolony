# ADR: Windowed Persistent Location Architecture

## Status

Accepted for P02.

## Context

The windowed prototype previously created a new 14×14 gathering record for every Wood or Stone assignment. A job window projected the record, but the prototype had no retained-location browser, explicit lifecycle, reopen/discard contract, bounded legacy-style terrain, or assignment-to-existing flow. The full legacy `ChunkManager` also owns camera streaming and multiple unrelated world projections, making it unsuitable as a per-window dependency.

## Decision

Locations are persistent authoritative bounded worlds. `LocationRegistry` owns retained identity, generated base records, runtime depletion, local inventory, lifecycle, and assignment membership. Windows are presentation only and locations never depend on a live renderer.

Generated base and runtime deltas are separate. A base is derived deterministically from location seed, bounded configuration, terrain rules, and resource spawn rules. Mutable depletion ids, inventory, lifecycle, assignment, and names are retained as runtime state.

Bounded generation reuses `WorldGenerator`, `TerrainConfig`, and `PropSpawnHelpers` directly for a fixed 32×32 region. It does not embed `ChunkManager`, camera-centred streaming, legacy `WorldState`, construction, stockpile zones, ground items, main-world input, or legacy save flows. Procedural tree and rock presentation reuses `PropVisualConfig` and `ProcSpriteCache` without making textures authoritative.

Inter-location travel may remain abstract while gathering within a location is cell-based. The haul coordinator owns exact source, destination, resource, amount, phase, progress, and carried payload. Presentation may draw connectors only when endpoints are visible; window geometry never supplies authoritative route data.

Future camps, buildings, construction, physical stockpiles, and settlements belong to locations and must remain independent of window lifetime. They are not introduced by this decision.

## Consequences

Closing a location presentation frees its renderer and leaves simulation state intact. Reopening reconstructs equivalent terrain and resources, including depletion and local inventory. Several retained locations require no live scene trees. Minimise suspends view redraw work, and cached procedural textures are reused.

`WindowedColonyState` remains a coordination owner but no longer stores or generates retained locations directly. It still has significant breadth across colonists, gathering, hauling, expedition inventory, and time; further splitting should occur only when a requested milestone establishes a clear new ownership boundary.

The bounded adapter applies small Woodland/Rocky terrain biases after shared climate sampling. This creates coupling to the public behavior of `WorldGenerator.build_tile_info_for_terrain()` and `PropSpawnHelpers`, but introduces no coupling to legacy streaming. Location persistence remains in-memory and is intentionally outside the production save schema for P02.

## P02.1 Amendment: Atlas Projection And Physical Piles

Location terrain presentation uses a bounded `TileMapLayer` backed by `TerrainIso.tres`. Semantic terrain records remain registry-owned generated base state and are resolved through `TerrainConfig`; atlas nodes and cells are reconstructible presentation. Elevation-specific art is reused only through existing lookup behavior, with generated flat atlas coordinates as fallback. No new cliff/masking system is introduced.

Gathering output is no longer an independently mutable aggregate inventory. `LocationRegistry` owns stable physical piles and their reservation state. Snapshot `local_inventory` values are derived sums for compatibility. Gathering merges same-type output only at the same harvested resource cell.

Hauling physically enters the source location, walks to its reserved pile, performs one validated pickup, walks back to a deterministic walkable edge cell, then travels abstractly to the expedition. Base capacity is eight. Before-pickup interruption releases the reservation without moving resources; after-pickup interruption returns the exact payload to its original pile and cell before clearing carry state. The invariant is all pile amounts plus all carried amounts plus expedition totals. Destination-side physical storage remains deferred.

Presentation is event-driven after initial reconstruction. Terrain and resource sets build once per opening; focused events update depletion, individual piles, and colonist motion/carry visuals. Minimise suspends the view and close removes it. A small active-haul snapshot remains polled by the desktop connector because connector animation is presentation-only and bounded by the number of haulers.

Profiling established that the old renderer repeated a roughly 2.089 ms deep snapshot and 7.351 ms cached resource pass per visible frame for a 1,024-cell/226-resource location, in addition to rebuilding polygon terrain. The corrected view performed one snapshot/terrain/resource build on open and retained `1/1/1` counts through 500 simulation ticks. The measured one-time open cost was approximately 403 ms on the validation environment, so initial construction of several resource-dense views remains a concrete performance risk.
# P03 Reorientation

The earlier disposable woodland/rocky job-location interpretation is superseded for active gameplay by one authoritative starting location. Roles are colony policy applied to colonists currently present at that location; they do not create locations. Physical output and camp storage remain owned by `LocationRegistry`. Multi-location discovery and inter-location hauling are not active P03 systems.
# P04 amendment

P04 activates multiple persistent bounded locations. `LocationRegistry` now owns their network metadata and presence; focused scouting and travel coordinators own long-running mobility records. Euclidean `Vector2i` world distance is authoritative. Windows remain reconstructible projections, and route overlays consume but never mutate progress. Remote piles remain local and entry-cell consolidation is not settlement storage.
# P05 amendment

Claiming and local buildings remain independent of window lifetime. Closed claimed locations are simulation-only. Open location views reconstruct Supply Cache sites from coordinator snapshots and receive focused building changes; placement previews are transient and never mutate simulation before confirmation.
