# Procedural Building Asset Research

Status: audit completed before prototype implementation.

## Scope and evidence

This report audits `res://4_Generic_Buildings_16x16.png` as supplied. The upload is one 512 x 3200 RGBA PNG plus Godot's generated texture import metadata. It is not a module pack: there are no source scenes, TileSet, region definitions, names per part, pivot markers, collision shapes, sockets, or authored adjacency rules.

The sheet title implies a 16 x 16 base unit. Its dimensions divide into a nominal 32-column by 200-row grid, and much of the artwork aligns to 16-pixel increments. Individual drawings frequently span several base cells and include irregular transparent margins, however, so the PNG cannot safely be sliced into uniform 16 x 16 gameplay tiles without a manually-authored region catalogue.

The project's world projection is a 32 x 16 isometric diamond. The uploaded buildings are predominantly straight-on/side-on pixel-art facades and top-down roof/floor plates, not four-direction isometric wall modules. This is the main compatibility limitation.

## Organisation and naming

- One vertically organised atlas contains several visual families: tan shop/house facades; brown interiors and shelving; red/white civic or apartment facades; recoloured red/white and blue/yellow facade families; grey industrial buildings; loose industrial parts and signage; and assembled examples.
- Large black/transparent gaps and example compositions separate families visually, but there is no machine-readable grouping.
- Repeated facade strips are arranged near related corners, doors, roof pieces, and decorations. Some one-floor variants are explicitly labelled in pixels; an `EXAMPLES` label separates composed examples.
- Naming consistency cannot be evaluated below the file level because no pieces have names. The only filename, `4_Generic_Buildings_16x16.png`, communicates theme and nominal unit but not licence, projection, palette family, module role, orientation, footprint, or compatibility.
- A production-ready import would require stable IDs for every selected rectangle and explicit tags; atlas coordinates must not become gameplay identifiers.

## Available visual pieces

The following are visually present, but counts are approximate because several drawings may be examples rather than intended reusable modules.

### Walls and facades

- Repeating straight facade bays in tan, red/white, blue, yellow, and grey industrial palettes.
- Blank wall bays, window bays, shop-window bays, door bays, and multi-storey stacked bays.
- Narrow side/end strips and several wide facade assemblies.
- Red/white convex exterior-corner/tower treatments and narrow side elevations.
- Grey industrial front walls, arched windows, shutters/garage panels, and rooftop/parapet assemblies.

These are elevation sprites rather than orientation-complete isometric walls. A repeated bay can vary width, but there is no demonstrated north/east/south/west set.

### Corners

- Several exterior convex facade corners are visible, especially in the red/white family.
- Narrow edge/end treatments exist for some families.
- No reliable complete set of four directional outside corners is identifiable.
- No clear concave/inside corner set is present.

### Roofs

- Gabled roof fronts and small dormer-like roof pieces.
- Flat roof plates and parapet/edge treatments in red/white and grey families.
- Several complete roof assemblies and example roof compositions.
- Small rooftop industrial details, vents, fans, tanks, pipes, and railings.

The sheet does not demonstrate a complete rule set for arbitrary roof polygons. Most roof art is authored for particular facade widths or composed examples.

### Doors and windows

- Multiple single and double doors, arched entrances, shop doors, industrial doors/shutters, and small detached door sprites.
- Many window variants: single, paired, wide shop windows, arched windows, curtained/display windows, and palette/style variations.
- Door/window modules are not consistently supplied for every wall family and orientation.

### Floors

- Large tan top/floor plates and brown interior room plates.
- Flat grey roof/floor-like plates.
- Some narrow edge strips and corner borders.

The distinction between walkable interior floor, roof surface, and example backing plate is not encoded. There is no complete autotile/terrain set for arbitrary floor outlines.

### Decorative pieces

- Shelves, stocked displays, counters, wall pictures, small furniture/fixtures, plants, planters, trees, benches, signs, awnings, hanging lines/banners, roof fans/vents, pipes, ladders/stairs, railings, utility objects, and a hardware-shop sign.
- Decorations are useful as authored overlays but lack sockets, depth/y-sort origins, and compatibility metadata.

## Pivots, atlas layout, and scale

- PNG textures do not carry Godot node pivots. The generated `.import` file defines texture filtering/compression only and supplies no regions or anchors.
- Visual baselines differ across pieces. Transparent padding is inconsistent enough that `Sprite2D.centered = true` would not produce a common construction anchor.
- Production use requires an explicit per-region anchor (normally ground/baseline centre or a named wall socket) and draw-order class.
- Nominal art unit: 16 x 16 px. Common pieces occupy 16 x 16 multiples, while tall facades, roofs, corners, and examples span many cells.
- Project simulation/render grid: 32 x 16 px isometric diamonds. A 16 px art unit does not by itself establish a compatible world tile; mapping would need to be authored and visually tested.
- Godot imports the source with nearest-neighbour project filtering, no mipmaps, lossless compression, and alpha-border fixing, which is suitable for pixel art.

## Research questions

### 1. Arbitrary rectangular buildings

Only in a constrained 2D facade prototype. Straight bays can repeat and selected corner/end/roof pieces can cap a rectangle-like elevation. The asset does not contain a verified four-facing isometric module set, complete anchors, or width-independent roofs, so it cannot currently generate arbitrary rectangular buildings that sit correctly on the colony world's isometric grid.

### 2. Irregular footprints

Not robustly. L-, T-, U-, courtyard, stepped, or concave footprints require inside corners, junctions, exposed end caps, and roof transitions not demonstrably present. Large authored assemblies can depict a few irregular silhouettes, but choosing among precomposed silhouettes is not arbitrary procedural generation.

### 3. Rooms, interior walls, roofs, and size

- Multiple rooms: the data model could support them, but the sheet does not provide a complete orientation/junction set for interior partitions.
- Interior walls: some cutaway/interior-looking walls and decor exist, but no complete straight/corner/T/cross/end set with consistent anchors is identifiable.
- Roof layouts: simple authored gables or flat rectangular plates are possible; arbitrary hips, valleys, ridges, concave transitions, and penetrations are not.
- Variable size: repeatable facade bays support limited width and storey variation. Depth and four-direction world footprints are not solved by the art.

### 4. Generation form

For production, use a hybrid: authoritative tile/cell data for footprint, rooms, walls, occupancy, and navigation; a scene-graph visual generator that instantiates or pools atlas-backed module scenes; optional TileMapLayer rendering for truly uniform floors/walls where a complete isometric TileSet exists. Do not treat scene nodes or atlas cells as simulation authority.

This particular sheet is best consumed through curated `AtlasTexture` regions wrapped in small visual module scenes/resources. It is not ready for purely tile-based generation because piece bounds, anchors, orientations, and adjacency are not encoded.

### 5. Required data

Suggested conceptual flow (not implemented by this prototype):

`BuildingDefinition -> authoritative footprint -> room/cell layout -> wall-edge graph -> openings -> roof graph -> non-authoritative visual recipe -> visual generator`

Minimum production data:

- Stable building/variant ID and deterministic generation seed/version.
- Footprint cells or polygon, origin, rotation, levels, entrances, and occupied cells.
- Room IDs by cell, room purpose, interior/exterior boundary edges, and connectivity.
- Wall-edge records with grid edge, facing, level, material/style, junction mask, and opening reference.
- Door/window records with edge, offset, width, facing, state, and gameplay connection where applicable.
- Roof topology: covered cells/polygons, roof type, pitch/style, ridge/valley/edge graph, height, penetrations, and hidden/cutaway state.
- Visual style/palette plus module catalogue entries containing atlas region, logical span, facing, anchor/pivot, sockets, z/y-sort origin, compatibility tags, and fallback ID.
- Interior floor/wall visual recipe, furniture sockets/clearance, occlusion/cutaway rules, and render level.
- Save schema should store authoritative generated results (or seed + immutable generator version where exact regeneration is guaranteed), not scene-node paths or transient visual nodes.

## Missing modular artwork / metadata

For an arbitrary, four-facing, isometric production system, artwork or verified variants are required for every supported material/style:

- Four directional straight exterior walls: blank, window, door, wide door, and damaged states.
- Four outside corner orientations with consistent sockets.
- Four inside/concave corner orientations.
- Wall end caps for both ends/facings.
- T-junctions for every branch orientation and cross-junctions.
- Interior-wall straight, corner, inside corner, T, cross, end-cap, doorway, and transition pieces.
- Exterior-to-interior wall transitions and thickness reveals around openings.
- Foundation/plinth edges, outside corners, inside corners, steps, and terrain-height transitions.
- Floor center, four edges, four outside corners, four inside corners, doorway thresholds, and material transitions.
- Roof field tiles; eaves for all facings; outside and inside eave corners; ridges and ridge ends; hips; valleys; gable ends; flat-roof parapet straights/corners/caps; wall-to-roof transitions; roof-level/height transitions; dormer/vent/chimney penetrations; and cutaway/hidden-roof variants.
- Multi-storey base, middle, top, corner, and setback transitions for each facing.
- Consistent door and window families for each wall style/facing, including closed/open frames if state is shown.
- Occluded/back-face or cutaway variants suitable for isometric interior visibility.
- Construction, damaged, repaired, ruined, snow/weather, and other simulation-required condition variants (if those states will be visualised).
- Explicit shadows or shadowless variants consistent with the project's lighting direction.

Metadata also missing: licence/source, region catalogue, semantic names, per-piece pixel bounds, grid span, facing, anchors, sockets, adjacency masks, draw order, collision/occlusion, palette/material tags, and intended assembled examples versus reusable modules.

Additional artwork is therefore required for full project suitability. Reprojecting the existing facade art into the project's isometric view is substantial new art work, not merely atlas configuration.

## Architecture options

### A. TileMap layers

Best for dense uniform floors and wall-edge visuals once a complete isometric terrain set exists. Efficient batching, compact cell storage, and easy chunk updates are strengths. Weaknesses are awkward multi-cell facades, per-piece anchors, stateful doors, storeys, roof occlusion, and decorations. The uploaded sheet is not uniform enough to use directly as a TileSet.

### B. PackedScenes

Best for doors, interactive/stateful modules, authored entrances, special roof objects, and decorated prefabs. Strong encapsulation and inspector workflow; higher node/memory cost and poor fit if every wall cell becomes a unique scene. PackedScenes alone also tempt accidental scene-as-authority design.

### C. Scene graph composed from modules

Recommended visual layer. A renderer consumes an authoritative immutable snapshot/visual recipe and composes curated atlas-backed modules, using MultiMesh/batching or TileMapLayer internally where scale requires it. It handles anchors, variable spans, cutaway state, decorations, and interactive PackedScene exceptions while preserving rendering separation. Its cost is a required module catalogue and deterministic adjacency resolver.

### D. Runtime mesh generation

Useful for large continuous 3D/extruded geometry, custom UVs, or very high module counts. It offers batching and arbitrary shapes but adds UV, sorting, collision, editor, and pixel-art seam complexity. For these 2D sprites it has the highest implementation cost and does not manufacture missing orientations or transitions. Not recommended as the primary approach.

## Recommended production integration

Keep the current simulation authoritative. A future simulation-owned building instance should store footprint, rooms, wall/opening topology, construction/condition state, and stable generation inputs/results. Validation and actions mutate that state first and emit results/events. A presentation-owned building visual system reads snapshots/events and generates disposable visuals; deleting or rebuilding the visual tree must never change gameplay.

Persistence should serialize authoritative building topology, room/opening/furniture state, generator schema version, and stable content IDs. It should not serialize AtlasTexture coordinates, Sprite2D nodes, or render caches. Load reconstructs simulation first, then asks presentation to rebuild.

Interiors should be a simulation-owned world-space/room model referenced by stable IDs. The renderer may hide roofs and near walls or switch module sets based on active interior visibility without owning occupancy. Future furniture belongs to authoritative placement/occupancy data with definition IDs and transforms; visual furniture scenes are projections attached to sockets only after placement validation.

The existing `BuildingDefinition` can eventually reference a production visual-style/recipe ID, but this experiment must not modify or integrate with it. A separate architectural task should define the authoritative topology schema before production code is added.

## Suitability conclusion

Suitable for: visual research, UI illustrations, authored facade props, side-view/cutaway scenes, decoration extraction, and a constrained atlas-region prototype.

Not suitable as delivered for: arbitrary procedural buildings in the current isometric world, irregular footprints, complete interiors, or rule-driven roofs.

Conditional long-term value: selected decorations and facade motifs may be reusable after licensing is confirmed, regions/anchors are catalogued, and project-matching isometric modules are newly authored. The sheet is a useful style reference and parts library, not a production-ready procedural building kit.

## Prototype implementation and limits

`ProceduralBuildingPrototype.tscn` and `procedural_building_prototype.gd` are fully contained in this research folder. The script hard-codes a 5 x 4 footprint and derives 20 floor cells, four perimeter wall runs, four corner markers, one omitted south-wall bay as a doorway, and an optional gabled roof. `include_roof` and `include_doorway` are inspector toggles; dimensions intentionally remain constants.

The prototype uses clearly-labelled geometric placeholder modules. This is a research result rather than a substitute art system: applying unlabelled facade atlas rectangles would conceal the missing isometric orientations, anchors, and adjacency metadata identified above. No runtime atlas extraction, region catalogue, or production-facing abstraction has been added.

There is no dependency in either direction between this folder and `WorldState`, construction, `BuildingDefinition`, saves, interiors, gameplay scenes, or UI. The prototype creates non-authoritative draw geometry only.

## Topology prototype extension

The current workspace still contains only `4_Generic_Buildings_16x16.png` and its generated texture import metadata as candidate building art. No separate newly uploaded wall, roof, floor, door, window, or corner textures/scenes were found. The available categories, projection/orientation gaps, anchors, nominal 16 px atlas unit, 32 x 16 project cell, naming limitations, and missing variants therefore remain as audited above.

`building_layout.gd` now provides an experiment-local topology container with authored occupied cells, a room ID per cell, explicit unit wall edges classified as exterior or interior, door/window openings attached to wall edges, and optional flat/gable roof regions. It validates duplicate cells/edges, edge length, opening-to-wall references, and roof coverage. This is prototype data, not a production `Resource`, gameplay definition, or persistence schema.

The visual sample is no longer a rectangle derived from width/depth constants. Its default input is a 16-cell L-shaped footprint with two rooms, one exterior door, one window, and two roof regions. Exterior edges and corners are now resolved from those cells as described below. The renderer retains geometric placeholders because the atlas still lacks verified isometric regions, orientations, and anchors.

Ownership remains local and one-way: the experiment creates its own layout, the renderer reads it, and neither object reads or mutates production state. Corners are disposable visual results derived from exterior edge incidence; they are not authoritative topology.

## Topology resolution completion

Authored `BuildingLayout` input is now limited to occupied cells, cell-to-room IDs, explicit interior wall edges, explicit openings, and optional roof regions. Standard exterior perimeter walls are no longer authored. `building_topology_resolver.gd` examines each occupied cell's four cardinal neighbours and emits an exterior edge only where the neighbour is unoccupied.

Every wall/opening edge uses a canonical identity: its endpoints are ordered lexicographically by x and then y and encoded as `start_x,start_y:end_x,end_y`. Resolver dictionaries are keyed by that identity, so shared/perimeter edges cannot be emitted twice. Explicit interior walls are also normalized and must separate two occupied cells. Openings resolve against either a derived exterior edge or an explicit interior edge; an interior door therefore replaces one resolved divider segment rather than adding another wall.

Corners are classified from the four occupancy quadrants around each perimeter vertex. One occupied quadrant produces an outer corner whose direction names the corner relative to that cell. Three occupied quadrants produce an inner/concave corner directed toward the missing quadrant. The L-shaped test footprint resolves five outer corners and one `inner_corner_north_east` record.

Three fresh authored layouts are switchable with keys 1-3 or the scene's starting-layout property:

- 5 x 4 rectangle: 20 cells, 18 derived exterior edges, four outer corners.
- L shape: 16 cells, 18 unique derived exterior edges, five outer corners, one inner corner.
- 6 x 4 two-room rectangle: 24 cells, 20 exterior edges, four explicit divider edges, one interior doorway, one exterior doorway, and one exterior window.

The renderer consumes only resolved semantic records. Requested IDs currently include `floor`, cardinal exterior walls, axis-aligned interior walls, cardinal doors/windows, directional outer/inner corners, `roof_fill`, `roof_edge`, and `roof_ridge`. The current placeholder catalogue intentionally lacks concave-corner, interior-door, and roof-edge art. Missing IDs log once and render magenta semantic fallbacks; diagnostics list unique requested, resolved, and missing/fallback IDs.

Gabled roof resolution remains intentionally constrained to authored rectangular regions. Flat authored regions are accepted. A non-rectangular gabled region is marked unsupported and logged rather than passed to a general roof solver. The L footprint uses one rectangular gabled region plus one rectangular flat region.

## Visual style and authored module contract

Visual selection is now separated from topology rendering. `building_visual_module_definition.gd` defines one stable semantic-to-asset contract and `building_visual_style.gd` owns a validated catalogue of those definitions. `prototype_visual_styles.gd` contains the current authored research mapping; replacing placeholders with verified art is confined to that style data rather than the resolver or layout code.

Each module definition records:

- stable semantic ID and renderer-facing visual kind;
- source kind: geometric placeholder, whole texture, atlas region, or `PackedScene`;
- texture/scene reference and atlas rectangle where applicable;
- explicit pixel anchor aligned to the semantic topology origin;
- logical cell span, facing, z offset, and compatibility tags.

Validation rejects empty IDs/kinds, non-positive spans, texture sources without textures, atlas sources without a texture and positive region, and scene sources without a `PackedScene`. A style rejects duplicate semantic IDs and requires a valid explicit fallback definition.

The renderer asks the active `BuildingVisualStyle` to resolve every semantic request. Placeholder definitions retain the current geometric research drawing. Texture and atlas definitions create disposable `Sprite2D` children; `PackedScene` definitions instantiate disposable scene children. Their authored anchor and z offset are applied relative to the resolved cell, edge, vertex, or roof-region origin. Layout/style changes clear these children before regeneration.

The current `research_placeholder` style maps floors, all cardinal exterior walls/doors/windows, both interior-wall axes, all outer-corner directions, roof fill, and roof ridge. Concave corners, interior openings, and roof edges intentionally remain unmapped until matching artwork exists, so they continue through the explicit magenta fallback and one-time missing-ID diagnostics.

## First uploaded modular asset catalogue

Four new RGBA pixel-art sheets were inspected at native resolution. They use a 32 x 16 isometric floor diamond, so `authored_test_style` declares a native visual projection half-cell of `(16, 8)` and an explicit integer display scale of 2. This produces a readable 64 x 32 displayed cell without stretching assets as an implicit alignment fix. This is style metadata only; layouts and resolved topology are unchanged. `research_placeholder` retains its original `(32, 16)` research scale, display scale 1, and mappings.

Anchor convention for this batch:

- floor: centre of the 32 x 16 top diamond;
- wall/door: midpoint of the ground-contact edge;
- corner: topology vertex (no uploaded corner was reliable enough to map);
- all listed `anchor_offset` corrections are `(0, 0)`; source-specific alignment is represented by `pixel_anchor`.

### Reliable and conditionally reliable mappings

| Semantic ID | Source | Source size | Atlas region | Facing | Span | Pixel anchor | Z | Confidence | Interpretation |
|---|---|---:|---:|---|---:|---:|---:|---|---|
| `floor` | `floor layers with outlines.png` | 512 x 1536 | `(0, 0, 32, 32)` | none | 1 x 1 | `(16, 8)` | -10 | High | First outlined brown floor tile; 32 x 16 top with a three-pixel outlined thickness. |
| `exterior_wall_north` | `walls type 1.png` | 512 x 768 | `(0, 512, 32, 32)` | north | 1 edge | `(24, 20)` | 0 | Medium | Plain low red-brick down-right edge module. |
| `exterior_wall_south` | `walls type 1.png` | 512 x 768 | `(0, 512, 32, 32)` | south | 1 edge | `(24, 20)` | 2 | Medium | Same parallel-axis module; explicit front-axis order. |
| `exterior_wall_east` | `walls type 1.png` | 512 x 768 | `(0, 544, 32, 32)` | east | 1 edge | `(8, 28)` | 2 | Medium | Plain low red-brick up-right edge; explicit front-axis order. |
| `exterior_wall_west` | `walls type 1.png` | 512 x 768 | `(0, 544, 32, 32)` | west | 1 edge | `(8, 28)` | 0 | Medium | Same parallel-axis module; no distinct opposite-face variant supplied. |
| `door_south` | `single door right 1.png` | 160 x 64 | `(0, 0, 32, 64)` | south | 1 edge | `(24, 60)` | 3 | High | First closed down-right door state. |
| `door_east` | `single door right 1 opposite.png` | 160 x 64 | `(0, 0, 32, 64)` | east | 1 edge | `(8, 60)` | 3 | High | First closed up-right door state. |

The selected wall family is the first plain low red-brick pair at y rows 512 and 544. Nearby columns add end caps and pale trim, while other sheet sections contain taller, multi-level, railing, junction, and combined-corner assemblies. Mixing those variants would create inconsistent height and trim, so they are deliberately excluded.

Both door sheets contain five progressively different visual states across 32-pixel slots. Only the first clearly closed state is mapped. The two sheets reliably cover the two projected edge axes, but they do not prove inward/outward versions for every compass-facing wall; north and west doors therefore remain fallback rather than being guessed.

### Uncertain or unsupported pieces

- `walls type 1.png` contains multiple combined outer/inner corners, end caps, junctions, trim families, railings, and taller wall arrangements. Their boundaries and intended adjacency are not encoded. Mapping a combined wall-and-corner assembly as a corner overlay would duplicate adjacent resolved wall modules, so all four outer corners remain fallback.
- No separate directional window sheet was uploaded. Window-like glazing inside the door state is part of that door artwork and is not a reusable window module. All four window semantics remain fallback.
- No authored interior-wall, interior-door, roof-fill, roof-edge, or roof-ridge module was identified in this batch.
- The floor sheet contains many material/outline rows plus stair and boundary assemblies near its bottom. Only its first uniform tile is used; no variation, stairs, or transitions are mapped.

### Authored style behavior

`authored_test_style` maps seven semantic IDs: the floor, four exterior wall directions, south door, and east door. It uses atlas regions directly and never rotates or stretches source pixels. Missing corners, windows, north/west doors, roofs, and interior modules use the existing magenta placeholder fallback and remain visible in diagnostics. Key `4` switches between `research_placeholder` and `authored_test_style`; keys `1`-`3` continue to switch layouts. Style changes rebuild disposable visual children without changing resolved cell/edge/corner counts.

## Authored module calibration

The five distinct mapped regions were measured pixel-by-pixel. Atlas rectangles were confirmed correct and each contains exactly one logical module:

| Module | Atlas rectangle | Visible content bounds | Transparent padding | Native ground/topology socket |
|---|---:|---:|---|---:|
| Floor | `(0, 0, 32, 32)` | local `(0, 0)-(32, 18)` | 14 empty bottom rows | top-diamond centre `(16, 8)` |
| Wall axis A | `(0, 512, 32, 32)` | local `(16, 1)-(32, 24)` | 16 px left; 8 px bottom | ground edge `(16,16)-(32,24)`, midpoint `(24,20)` |
| Wall axis B | `(0, 544, 32, 32)` | local `(0, 9)-(16, 32)` | 16 px right; 9 px top | ground edge `(0,32)-(16,24)`, midpoint `(8,28)` |
| South door | `(0, 0, 32, 64)` | local `(16, 25)-(32, 64)` | 16 px left; 25 px top | ground edge `(16,56)-(32,64)`, midpoint `(24,60)` |
| East door | `(0, 0, 32, 64)` | local `(0, 25)-(16, 64)` | 16 px right; 25 px top | ground edge `(0,64)-(16,56)`, midpoint `(8,60)` |

The pre-calibration anchors already represented the correct geometric sockets and therefore remain unchanged. Visible-pixel centre averages are half-pixel values, but they are not the construction sockets: the sockets lie on pixel boundaries at the integer coordinates above. `anchor_offset` remains `(0,0)` for every module.

The fragmentation/readability correction is an explicit style-wide 2x integer display scale. Both topology projection and authored sprite instances use that scale, keeping the native 32 x 16 relationship intact while matching the prototype's previous readable 64 x 32 display footprint. No individual sprite is non-uniformly scaled and no renderer direction branch applies alignment offsets.

Z order is metadata-driven: floor `-10`; rear north/west walls `0`; front south/east walls `2`; south/east doors `3`. A door request replaces its resolved wall request, so the z-order does not conceal an overlapping wall segment.

`asset_calibration_debug` is an exported renderer toggle and defaults off. When enabled, every authored atlas instance displays its topology anchor, final sprite origin, scaled source-region rectangle, semantic ID, pixel anchor, and world position. These overlays are disposable visual children and do not affect module placement.

The 5 x 4 rectangle is now the default calibration layout. Validation records exactly 20 floor instances, 16 authored wall instances, one authored south door, one window fallback, and no duplicate authored module for the replaced door edge. The L and two-room layouts retain their previous topology counts; remaining visible breaks are attributable to fallback corners/windows/roof/interior modules rather than calibrated floor/wall/door placement.

## Authored fallback presentation

The large magenta area covering the authored interior was identified as the missing `roof_fill` fallback, not the floor. The generic fallback emitted one solid elevated magenta diamond for every covered roof cell; because those fallbacks were drawn above atlas-backed floor children, they obscured all 20 valid rectangle floor instances.

`authored_test_style` now declares roof presentation unsupported. The renderer records `roof_fill`, `roof_edge`, and `roof_ridge` as missing and logs each once for that style, but emits no roof fallback geometry. `research_placeholder` retains roof fill/ridge rendering and its existing roof-edge diagnostic.

The authored style also requests compact missing geometry:

- Missing outer/inner corners use a small ring/cross marker at the topology vertex plus the semantic ID, rather than a full-height corner post.
- Missing doors/windows use a labelled gap marker on the opening edge. No solid wall panel is drawn beneath a missing opening.
- Missing interior or other wall modules use a low edge line with short posts and a semantic label, keeping the floor readable.
- The calibration overlay remains a separate optional mode and defaults off.

Runtime diagnostics now contain unique missing IDs, suppressed visual IDs, and the selected fallback presentation per semantic ID. The scene label shows a compact missing-ID list. Missing-ID warnings are keyed by `style_id:semantic_id`, so each ID logs once per style even when layouts or styles are switched repeatedly.

## Validation record

- Godot 4.7 headless editor parse completed with exit code 0.
- The isolated prototype scene opened headlessly with exit code 0.
- Runtime marker confirmed generation of footprint `(5, 4)`, 20 floors, 17 walls after the doorway omission, four corners, one doorway, and a roof.
- Godot also reported existing invalid atlas-coordinate errors while importing the already-modified production `TerrainIso` TileSet. They are unrelated to, and were not changed for, this experiment.
- `git diff --check` passed for the experimental folder.
- Default L-layout runtime marker: 16 occupied cells, 18 derived exterior edges, five outer corners, one inner corner, and two roof regions.
- Resolver validation covers rectangle/L/two-room perimeter counts, edge uniqueness, concave-corner direction, one-time interior divider edges, interior doorway replacement, layout-switch cleanup, and semantic fallback diagnostics.
- Visual-style validation covers mapped and fallback lookup, invalid atlas metadata, and one `PackedScene` module instance per requested floor cell.
- Uploaded-style validation covers all seven atlas mappings, explicit fallback for uncertain categories, unchanged topology across a style switch, authored instance creation, and clearing authored instances when returning to the placeholder style.
- Calibration validation covers native cell/display scale, exact floor/wall/door sockets, explicit floor/rear/front/door z ordering, per-layout authored instance counts, one floor request per occupied cell, and one door request replacing its south wall edge.
- Fallback-presentation validation confirms roof semantics remain reported but visually suppressed in all authored layouts, window fallbacks are non-solid opening markers, corner fallbacks are compact markers, and placeholder roof/full-geometry policy remains enabled.

## Calibrated TileSet import

The saved calibration scene is `res://node_2d.tscn`. It contains an embedded TileSet equivalent to the external catalogue at `res://building_modules.tres`; `authored_test_style` references the external catalogue read-only so its saved atlas extents and texture origins remain the visual source of truth. Neither resource is modified by this experiment.

The TileSet uses isometric tile shape `1`, layout `5`, and a 32 x 16 tile size. Source `0` uses `res://experimental/procedural_building_research/walls type 1.png` (512 x 768); every selected wall tile occupies one 32 x 16 atlas column by two rows, giving a 32 x 32 texture region, alternative ID `0`, and texture origin `(0, 8)`. Source `2` uses `res://experimental/procedural_building_research/floor layers with outlines.png` (512 x 1536); floor `(1,10)` also occupies 1 x 2 atlas cells (32 x 32), alternative `0`, with texture origin `(0,-8)`. The selected tiles have no transform flags, material override, or modulate override in the saved resource.

The prototype projection is `screen = ((x-y)*16, (x+y)*8)`. Therefore cell delta `(0,-1)` reaches the top-right diamond edge (North), `(1,0)` the bottom-right edge (East), `(0,1)` the bottom-left edge (South), and `(-1,0)` the top-left edge (West). This matches the supplied provisional convention, so no topology semantic direction is renamed or silently translated.

The wall art is consumed as a presentation-only vertex connection catalogue, using `N=1`, `E=2`, `S=4`, and `W=8`:

| Mask | Semantic | Source | Atlas | Region | Origin | Alternative |
|---:|---|---:|---:|---:|---:|---:|
| 1 | `wall_connection_n` | 0 | `(1,0)` | 32 x 32 | `(0,8)` | 0 |
| 2 | `wall_connection_e` | 0 | `(2,2)` | 32 x 32 | `(0,8)` | 0 |
| 4 | `wall_connection_s` | 0 | `(1,4)` | 32 x 32 | `(0,8)` | 0 |
| 8 | `wall_connection_w` | 0 | `(0,2)` | 32 x 32 | `(0,8)` | 0 |
| 5 | `wall_connection_ns` | 0 | `(1,6)` | 32 x 32 | `(0,8)` | 0 |
| 10 | `wall_connection_we` | 0 | `(3,2)` | 32 x 32 | `(0,8)` | 0 |
| 9 | `wall_connection_nw` | 0 | `(0,0)` | 32 x 32 | `(0,8)` | 0 |
| 3 | `wall_connection_ne` | 0 | `(2,0)` | 32 x 32 | `(0,8)` | 0 |
| 12 | `wall_connection_sw` | 0 | `(0,4)` | 32 x 32 | `(0,8)` | 0 |
| 6 | `wall_connection_se` | 0 | `(2,4)` | 32 x 32 | `(0,8)` | 0 |
| 11 | `wall_connection_nwe` | 0 | `(3,0)` | 32 x 32 | `(0,8)` | 0 |
| 14 | `wall_connection_swe` | 0 | `(3,4)` | 32 x 32 | `(0,8)` | 0 |
| 13 | `wall_connection_nsw` | 0 | `(0,6)` | 32 x 32 | `(0,8)` | 0 |
| 7 | `wall_connection_sne` | 0 | `(2,6)` | 32 x 32 | `(0,8)` | 0 |
| 15 | `wall_connection_nsew` | 0 | `(3,6)` | 32 x 32 | `(0,8)` | 0 |

The reported `WE`/`SWE` duplication was not present in the saved TileSet: `WE` is `(3,2)`, while `SWE` is `(3,4)`. They are distinct calibrated tiles.

The renderer places floors and wall junctions through two disposable `TileMapLayer` nodes. Godot applies each tile's saved texture origin directly. A layer-level isometric map-origin correction aligns floor map cells to topology cell centres and wall map cells to topology vertices; there are no per-direction renderer offsets. Openings remove their edge from the visual wall graph, producing cap masks at both ends, then the existing door/window semantic request occupies the gap. This adapter reads resolved topology but never modifies or replaces `BuildingLayout` or `BuildingTopologyResolver` ownership.

The current remaining authored-style fallbacks are north/west doors, all windows, and the interior doorway. Roof semantics remain diagnosed and visually suppressed. Wall straight, end, corner, T, and cross junctions now come from the TileSet catalogue, including the L-footprint concave junction. The existing manual south/east door atlas modules remain unchanged pending calibrated TileSet door entries.

## Wall-direction mapping correction

The first connection adapter incorrectly built visual masks from the tangent between each normalized edge's topology vertices. For example, the northwest rectangle vertex has outgoing topology segments toward East and South, so the adapter requested `SE`; however, the calibrated TileSet catalogue describes the resolved wall facings meeting there, which are North and West. The same error made an endpoint on a south-facing wall request an east/west terminal depending on normalized endpoint order.

The adapter now combines resolved edge-facing semantics at each vertex. Exterior edges contribute their existing `north`, `east`, `south`, or `west` direction. Explicit interior axes contribute both visual face normals: `east_west` contributes N+S, while `north_south` contributes E+W. Openings are still removed before contributions are accumulated. This yields N/E/S/W along rectangle sides, matching two-direction corners, NE at the L-shape concavity, and NWE/SWE junctions where the two-room divider meets the perimeter. The mask-to-atlas table, TileSet resource, origins, placement transform, topology resolver, and floor mapping did not require changes.

Optional `tile_module_debug` output now includes the topology vertex, every contributing edge key/kind/direction, its cell-facing deltas and compass names, the combined mask, selected semantic ID, source/atlas/alternative IDs, TileSet origin, map coordinate, and final world position. It remains disabled by default.

## Two-course wall calibration

The wall connection tiles are half-height courses. The saved calibration scene contains a second wall `TileMapLayer` at position `(0,-16)`, establishing an authoritative 16-pixel upward offset for the upper course. `authored_test_style` therefore declares two courses for every `wall_connection_*` module, with course offset `(0,-16)` and an explicit z step of `1`.

Topology still emits one connection record per wall vertex. Presentation places the same source ID, atlas coordinate, alternative ID, and map coordinate into shared lower and upper wall layers. The lower layer retains the calibrated topology-vertex transform; the upper layer differs only by the style metadata offset. Godot continues to apply the saved TileSet texture origin `(0,8)` independently to both tiles.

Door openings remain absent from the wall graph, so neither course places a hidden wall segment beneath a door. The current full-height south/east door sprites retain their native pixel anchors and add `anchor_offset=(0,-8)`, which produces the same positive eight-pixel visual-origin displacement as the wall TileSet without editing the source textures or `building_modules.tres`. Their resolved anchors are now `(24,52)` and `(8,52)` respectively. Window and unavailable-door fallbacks remain opening markers and likewise do not restore either wall course.
