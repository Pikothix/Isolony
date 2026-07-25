extends Node2D
class_name ChunkManager

## Purpose: Stream and render the one transiently active WorldSpace around the camera.
## Responsibility: Own loaded presentation projections and local terrain queries, while generators and WorldState retain their respective authority.
## Assumption: Only one WorldSpace is rendered at a time; non-surface terrain is reconstructed from simulation-owned interior records.

const ProcSpriteCache = preload("res://scripts/procgen/proc_sprite_cache.gd")
const PropPrewarmConfig = preload("res://scripts/world/props/prop_prewarm_config.gd")
const PropVisualConfig = preload("res://scripts/world/props/prop_visual_config.gd")
const ResourceVisualDefinitionRef = preload("res://scripts/world/props/resource_visual_definition.gd")
const TerrainConfigRef = preload("res://scripts/world/terrain_config.gd")
const ConstructionSiteVisualScript = preload("res://scripts/buildings/construction_site_visual.gd")
const StockpileZoneVisualScript = preload("res://scripts/world/stockpile_zone_visual.gd")
const GroundItemVisualScript = preload("res://scripts/world/ground_item_visual.gd")
const ElevationStackVisualScript = preload("res://scripts/world/elevation_cliff_visual.gd")
const ElevationEdgeVariantResolverRef = preload("res://scripts/world/elevation_edge_variant_resolver.gd")
const ChunkBoundaryMeshRendererScript = preload("res://scripts/world/chunk_boundary_mesh_renderer.gd")
const ShaderCliffRimOverlayScript = preload("res://scripts/world/shader_cliff_rim_overlay.gd")
const CellRenderInfoRef = preload("res://scripts/world/cell_render_info.gd")
const BuildingDefinitionRef = preload("res://scripts/buildings/building_definition.gd")
const InteriorTerrainSourceRef = preload("res://scripts/interiors/interior_terrain_source.gd")
const ConnectionMarkerVisualScript = preload("res://scripts/world/connection_marker_visual.gd")
const InteriorWallVisualScript = preload("res://scripts/world/interior_wall_visual.gd")
const LightingOverlayScript = preload("res://scripts/world/lighting_overlay.gd")

const SURFACE_WORLD_SPACE_ID := "surface"
const DEBUG_ELEVATION_PICK_RADIUS := 2
enum ShaderRimDirectionMode {
	ALL,
	TOP_ONLY,
	BOTTOM_ONLY,
	NONE,
}

const CLIFF_RIM_NEIGHBOURS := {
	"north": Vector2i.UP,
	"east": Vector2i.RIGHT,
	"south": Vector2i.DOWN,
	"west": Vector2i.LEFT,
}
const CLIFF_RIM_VISIBLE_DIRECTIONS := {
	"east": true,
	"south": true,
}

signal chunk_generated(chunk_coord: Vector2i)
signal chunk_unloaded(chunk_coord: Vector2i)
signal resource_inspection_requested(inspection_data: Dictionary)
signal active_world_space_changed(world_space_id: String)

@export_range(1, 6, 1) var load_radius: int = 2
@export_range(1, 6, 1) var chunks_per_frame: int = 1
@export var world_generator_path: NodePath = NodePath("../WorldGenerator")
@export var camera_path: NodePath = NodePath("../Camera2D")
@export var tree_scene: PackedScene
@export var rock_scene: PackedScene
@export var berry_bush_scene: PackedScene
@export var use_procedural_tree_sprites: bool = true
@export var use_procedural_rock_sprites: bool = true
@export_range(0, 256, 1) var procedural_tree_variant_cap: int = 18
@export_range(0, 256, 1) var procedural_rock_variant_cap: int = 12
@export_range(12, 72, 1) var procedural_tree_large_size: int = 30
@export_range(8, 48, 1) var procedural_rock_small_size: int = 14
@export_range(8, 48, 1) var procedural_rock_medium_size: int = 18
@export_range(8, 48, 1) var procedural_rock_large_size: int = 22
@export var prewarm_procedural_variants: bool = true
@export var stage_resource_spawning: bool = true
@export_range(1, 128, 1) var resource_spawns_per_frame: int = 4
## Soft frame budget for staged resource construction. One resource is always
## allowed through so an individually expensive scene cannot starve the queue.
@export_range(0.1, 16.0, 0.1) var resource_spawn_time_budget_ms: float = 1.5
@export var procedural_cache_debug: bool = false
@export var chunk_profile_debug: bool = false
@export_range(1, 256, 1) var chunk_profile_summary_interval: int = 16
@export var streaming_lifecycle_profile_debug: bool = false
@export var lighting_profile_debug: bool = false
@export_range(0.5, 10.0, 0.5) var lighting_profile_summary_interval: float = 1.0
@export var draw_per_cell_light_debug: bool = false
@export var draw_light_source_glows_experimental: bool = false
@export var draw_building_effect_radii_debug: bool = false
@export var show_ground_item_amount_labels_debug: bool = false
@export var cliff_rim_color: Color = Color(0.12, 0.09, 0.05, 1.0)
@export_range(0.0, 1.0, 0.05) var cliff_rim_alpha: float = 0.65
@export_range(0.25, 4.0, 0.25) var cliff_rim_width: float = 1.0
@export_range(-4.0, 4.0, 0.25) var cliff_rim_vertical_offset: float = -0.5
@export var enable_cliff_face_overlay: bool = false
@export var shader_cliff_rims_enabled: bool = false
@export_enum("All", "Top Only", "Bottom Only", "None") var shader_cliff_rim_direction_mode: int = ShaderRimDirectionMode.ALL
@export_range(128, 512, 64) var shader_cliff_rim_texture_size: int = 256
@export_range(0.0, 3.0, 0.1) var shader_cliff_rim_softness: float = 0.75
@export var shader_cliff_rim_debug_elevation: bool = false

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var terrain_visual_root: Node2D = $TerrainVisualRoot
@onready var debug_elevation_root: Node2D = $DebugElevationRoot
@onready var debug_elevation_level_label: Label = $DebugElevationRoot/ElevationLevelLabel
@onready var gameplay_y_sort_root: Node2D = $GameplayYSort
@onready var stockpile_zone_root: Node2D = $GameplayYSort/StockpileZoneRoot
@onready var ground_item_root: Node2D = $GameplayYSort/GroundItemRoot
@onready var resource_root: Node2D = $GameplayYSort/ResourceRoot
@onready var construction_root: Node2D = $GameplayYSort/ConstructionRoot
@onready var _colonist_manager: ColonistManager = $GameplayYSort/ColonistManager

var _world_generator: WorldGenerator
var _camera: Camera2D
var _loaded_chunks: Dictionary = {}
var _manual_tile_overrides: Dictionary = {}
var _depleted_resource_ids: Dictionary = {}
var _resource_index: Dictionary = {}
var _queued_chunk_keys: Dictionary = {}
var _pending_chunks: Array[Vector2i] = []
var _pending_resource_spawns: Array[Dictionary] = []
var _last_center_chunk: Vector2i = Vector2i(999999, 999999)
var _wander_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _world_state: Node
var _harvest_designation_input_enabled: bool = false
var _elevation_visual: Node2D
var _chunk_boundary_mesh_root: Node2D
var _chunk_boundary_mesh_renderers: Dictionary = {}
var _shader_cliff_rim_visual: Node2D
var _debug_elevation_preview: Node2D
var _debug_elevation_preview_cell: Vector2i = Vector2i(999999, 999999)
var _debug_elevation_markers_by_chunk: Dictionary = {}
var _active_world_space_id: String = SURFACE_WORLD_SPACE_ID
var _connection_root: Node2D
var _connection_markers: Array[Node2D] = []
var _interior_wall_visual: Node2D
var _lighting_overlay: Node2D
var _chunk_profile_load_stats: Dictionary = {}
var _chunk_profile_resource_stats: Dictionary = {}
var _lighting_refresh_queued := false
var _lighting_signal_count := 0
var _day_phase_signal_count := 0
var _lighting_profile_elapsed := 0.0
var _applied_draw_per_cell_light_debug := false
var _applied_draw_light_source_glows_experimental := false
var _applied_draw_building_effect_radii_debug := false
var _applied_show_ground_item_amount_labels_debug := false
var _applied_lighting_profile_debug := false

func _ready() -> void:
	_world_generator = get_node(world_generator_path) as WorldGenerator
	_camera = get_node(camera_path) as Camera2D
	_wander_rng.randomize()
	_elevation_visual = ElevationStackVisualScript.new() as Node2D
	_elevation_visual.name = "WorldElevationVisual"
	terrain_visual_root.add_child(_elevation_visual)
	_chunk_boundary_mesh_root = Node2D.new()
	_chunk_boundary_mesh_root.name = "ChunkBoundaryMeshRoot"
	terrain_visual_root.add_child(_chunk_boundary_mesh_root)
	_shader_cliff_rim_visual = ShaderCliffRimOverlayScript.new() as Node2D
	_shader_cliff_rim_visual.name = "ShaderCliffRimOverlay"
	terrain_visual_root.add_child(_shader_cliff_rim_visual)
	var map_origin: Vector2 = terrain_layer.map_to_local(Vector2i.ZERO)
	var map_step_x: Vector2 = terrain_layer.map_to_local(Vector2i.RIGHT) - map_origin
	var map_step_y: Vector2 = terrain_layer.map_to_local(Vector2i.DOWN) - map_origin
	_shader_cliff_rim_visual.call(
		"configure",
		shader_cliff_rim_texture_size,
		map_origin,
		map_step_x,
		map_step_y,
		cliff_rim_color,
		cliff_rim_alpha,
		cliff_rim_width,
		cliff_rim_vertical_offset,
		shader_cliff_rim_softness,
		shader_cliff_rim_direction_mode,
		shader_cliff_rim_debug_elevation
	)
	_chunk_boundary_mesh_root.visible = enable_cliff_face_overlay and not shader_cliff_rims_enabled
	_shader_cliff_rim_visual.visible = shader_cliff_rims_enabled
	_interior_wall_visual = InteriorWallVisualScript.new() as Node2D
	_interior_wall_visual.name = "InteriorWallVisual"
	_interior_wall_visual.y_sort_enabled = true
	var empty_wall_cells: Array[Vector2i] = []
	_interior_wall_visual.call("configure", terrain_layer, empty_wall_cells)
	_interior_wall_visual.visible = false
	gameplay_y_sort_root.add_child(_interior_wall_visual)
	_connection_root = Node2D.new()
	_connection_root.name = "ConnectionRoot"
	gameplay_y_sort_root.add_child(_connection_root)
	_lighting_overlay = LightingOverlayScript.new() as Node2D
	_lighting_overlay.name = "LightingOverlay"
	_lighting_overlay.z_as_relative = false
	_lighting_overlay.z_index = 100
	add_child(_lighting_overlay)
	_refresh_lighting_projection()
	ProcSpriteCache.set_debug_logging(procedural_cache_debug)
	_prewarm_procedural_cache()
	_update_streaming(true)

func _process(_delta: float) -> void:
	_sync_lighting_presentation_flags()
	_sync_ground_item_label_visibility()
	_update_streaming(false)
	for _i in range(chunks_per_frame):
		if _pending_chunks.is_empty():
			break
		_generate_chunk(_pending_chunks.pop_front())
	_process_pending_resource_spawns()
	_report_lighting_profile(_delta)


func set_draw_per_cell_light_debug_enabled(enabled: bool) -> void:
	draw_per_cell_light_debug = enabled
	_sync_lighting_presentation_flags()


func set_light_source_glows_experimental_enabled(enabled: bool) -> void:
	draw_light_source_glows_experimental = enabled
	_sync_lighting_presentation_flags()


func set_building_effect_radii_debug_enabled(enabled: bool) -> void:
	draw_building_effect_radii_debug = enabled
	_sync_lighting_presentation_flags()


func set_ground_item_amount_labels_debug_enabled(enabled: bool) -> void:
	show_ground_item_amount_labels_debug = enabled
	_sync_ground_item_label_visibility()


func _sync_lighting_presentation_flags() -> void:
	var overlay_debug_changed := _applied_draw_per_cell_light_debug != draw_per_cell_light_debug \
		or _applied_draw_light_source_glows_experimental != draw_light_source_glows_experimental
	if overlay_debug_changed:
		_applied_draw_per_cell_light_debug = draw_per_cell_light_debug
		_applied_draw_light_source_glows_experimental = draw_light_source_glows_experimental
		_queue_lighting_projection_refresh()
	if _applied_lighting_profile_debug != lighting_profile_debug:
		_applied_lighting_profile_debug = lighting_profile_debug
		_refresh_lighting_projection()
	if _applied_draw_building_effect_radii_debug == draw_building_effect_radii_debug:
		return
	_applied_draw_building_effect_radii_debug = draw_building_effect_radii_debug
	_refresh_construction_effect_visuals()


func _sync_ground_item_label_visibility() -> void:
	if _applied_show_ground_item_amount_labels_debug == show_ground_item_amount_labels_debug:
		return
	_applied_show_ground_item_amount_labels_debug = show_ground_item_amount_labels_debug
	for chunk_data_value: Variant in _loaded_chunks.values():
		var chunk_data: Dictionary = chunk_data_value
		for node: Node in chunk_data.get("ground_item_nodes", []):
			if is_instance_valid(node) and node.has_method("set_amount_label_visible"):
				node.call("set_amount_label_visible", show_ground_item_amount_labels_debug)


func set_shader_cliff_rims_enabled(enabled: bool) -> void:
	## Runtime presentation switch. Rebuild only the renderer becoming active,
	## because inactive streaming caches are intentionally not maintained.
	if shader_cliff_rims_enabled == enabled:
		return
	shader_cliff_rims_enabled = enabled
	if _shader_cliff_rim_visual != null:
		_shader_cliff_rim_visual.visible = enabled
	if _chunk_boundary_mesh_root != null:
		_chunk_boundary_mesh_root.visible = enable_cliff_face_overlay and not enabled
	_refresh_cliff_edge_rims()

func is_shader_cliff_rims_enabled() -> bool:
	return shader_cliff_rims_enabled

func set_shader_cliff_rim_direction_mode(direction_mode: int) -> void:
	shader_cliff_rim_direction_mode = clampi(direction_mode, ShaderRimDirectionMode.ALL, ShaderRimDirectionMode.NONE)
	if _shader_cliff_rim_visual != null:
		_shader_cliff_rim_visual.call("set_direction_mode", shader_cliff_rim_direction_mode)

func get_shader_cliff_rim_direction_mode() -> int:
	return shader_cliff_rim_direction_mode

func get_cliff_rim_debug_comparison(cell: Vector2i) -> Dictionary:
	## Compare the shader texture's exact inputs with the CPU fallback predicate.
	var cpu_elevations: Dictionary = {}
	var shader_elevations: Dictionary = {}
	var shader_loaded_mask: Dictionary = {}
	var cpu_exposed: Array[String] = []
	var current_elevation: int = _get_effective_elevation_for_rim(cell)
	for direction_name: String in CLIFF_RIM_NEIGHBOURS:
		var neighbour: Vector2i = cell + (CLIFF_RIM_NEIGHBOURS[direction_name] as Vector2i)
		var neighbour_elevation: int = _get_effective_elevation_for_rim(neighbour)
		cpu_elevations[direction_name] = neighbour_elevation
		shader_elevations[direction_name] = int(_shader_cliff_rim_visual.call("get_debug_elevation_at_cell", neighbour))
		shader_loaded_mask[direction_name] = bool(_shader_cliff_rim_visual.call("get_debug_loaded_at_cell", neighbour))
		if current_elevation > neighbour_elevation:
			cpu_exposed.append(direction_name)
	var shader_current: int = int(_shader_cliff_rim_visual.call("get_debug_elevation_at_cell", cell))
	var shader_exposed: Array[String] = []
	shader_exposed.assign(_shader_cliff_rim_visual.call("get_debug_exposed_directions", cell))
	cpu_exposed.sort()
	shader_exposed.sort()
	return {
		"cell": cell,
		"cpu_elevation": current_elevation,
		"shader_elevation": shader_current,
		"cpu_neighbours": cpu_elevations,
		"shader_neighbours": shader_elevations,
		"shader_loaded_mask": {
			"current": bool(_shader_cliff_rim_visual.call("get_debug_loaded_at_cell", cell)),
			"neighbours": shader_loaded_mask,
		},
		"cpu_exposed_directions": cpu_exposed,
		"shader_exposed_directions": shader_exposed,
		"matches": current_elevation == shader_current and cpu_elevations == shader_elevations and cpu_exposed == shader_exposed,
	}

func get_cliff_rim_fragment_debug(world_position: Vector2) -> Dictionary:
	## Live-scene projection diagnostic for a rendered world position under the mouse.
	var local_position: Vector2 = _shader_cliff_rim_visual.to_local(world_position)
	var flat_cell: Vector2i = world_to_cell(world_position)
	var visible_cell: Vector2i = get_debug_elevation_cell_at_world_position(world_position)
	var terrain_local_position: Vector2 = terrain_layer.to_local(world_position)
	var godot_cells_by_elevation: Dictionary = {}
	for elevation_level in range(0, 3):
		var top_offset := Vector2(0.0, -16.0 * elevation_level - 8.0 + cliff_rim_vertical_offset)
		godot_cells_by_elevation[elevation_level] = terrain_layer.local_to_map(terrain_local_position - top_offset)
	return {
		"world_position": world_position,
		"flat_world_to_cell": flat_cell,
		"visible_top_cell": visible_cell,
		"visible_cell_comparison": get_cliff_rim_debug_comparison(visible_cell),
		"godot_cells_by_elevation": godot_cells_by_elevation,
		"shader_fragment": _shader_cliff_rim_visual.call("get_debug_fragment_analysis", local_position),
	}

func set_shader_cliff_rim_debug_elevation(enabled: bool) -> void:
	shader_cliff_rim_debug_elevation = enabled
	if _shader_cliff_rim_visual != null:
		_shader_cliff_rim_visual.call("set_debug_elevation", enabled)

func is_shader_cliff_rim_debug_elevation_enabled() -> bool:
	return shader_cliff_rim_debug_elevation

func get_cell_world_position(cell: Vector2i) -> Vector2:
	return terrain_layer.to_global(terrain_layer.map_to_local(cell))


func get_cell_visual_world_position(cell: Vector2i, world_space_id: String = "") -> Vector2:
	## Presentation anchor for visuals that sit on a terrain top. Simulation remains
	## authoritative for the cell/elevation; CellRenderInfo owns their projection.
	var resolved_world_space_id := world_space_id if not world_space_id.is_empty() else _active_world_space_id
	var map_position := terrain_layer.map_to_local(cell)
	var elevation := get_cell_elevation(cell, resolved_world_space_id)
	return terrain_layer.to_global(CellRenderInfoRef.get_visible_top_center(map_position, elevation))


func world_to_cell(world_position: Vector2) -> Vector2i:
	return terrain_layer.local_to_map(terrain_layer.to_local(world_position))

func get_visible_terrain_cell_at_world_position(world_position: Vector2, world_space_id: String = SURFACE_WORLD_SPACE_ID) -> Vector2i:
	## Presentation-aware picking for elevated cells; callers must still validate intent with simulation authorities.
	var local_position: Vector2 = terrain_layer.to_local(world_position)
	var flat_cell: Vector2i = terrain_layer.local_to_map(local_position)
	var cells: Array[Vector2i] = _resolve_visible_terrain_cells(local_position, flat_cell, world_space_id)
	return cells[0] if not cells.is_empty() else flat_cell

func get_visible_terrain_cells_at_world_position(world_position: Vector2, world_space_id: String = SURFACE_WORLD_SPACE_ID) -> Array[Vector2i]:
	## Returns all projected terrain cells under the pointer, ordered from strongest visible hit to weakest fallback.
	var local_position: Vector2 = terrain_layer.to_local(world_position)
	var flat_cell: Vector2i = terrain_layer.local_to_map(local_position)
	return _resolve_visible_terrain_cells(local_position, flat_cell, world_space_id)

func get_hover_inspection_snapshot(world_position: Vector2) -> Dictionary:
	## Compact read-only tile snapshot for Main's HUD. Terrain/resource data is
	## loaded projection only; simulation-owned records come from WorldState.
	var world_space_id: String = _active_world_space_id
	var candidates: Array[Vector2i] = get_visible_terrain_cells_at_world_position(world_position, world_space_id)
	var cell: Vector2i = candidates[0] if not candidates.is_empty() else world_to_cell(world_position)
	var tile_info: Dictionary = get_effective_tile_info(cell, world_space_id)
	var terrain_id: String = String(tile_info.get("terrain", ""))
	var authority: Dictionary = {}
	if _world_state != null and _world_state.has_method("get_cell_authority_snapshot"):
		authority = _world_state.call("get_cell_authority_snapshot", cell, world_space_id)
	return {
		"ok": not tile_info.is_empty(),
		"world_space_id": world_space_id,
		"cell": cell,
		"loaded": is_cell_loaded(cell, world_space_id),
		"terrain_id": terrain_id,
		"terrain_name": TerrainConfigRef.get_display_name(terrain_id) if TerrainConfigRef.has_terrain(terrain_id) else terrain_id,
		"elevation": int(tile_info.get("elevation", 0)),
		"walkable": bool(tile_info.get("walkable", false)),
		"mineable": bool(tile_info.get("mineable", false)),
		"resource_node": _get_loaded_resource_snapshot_at_cell(cell, world_space_id),
		"authority": authority,
	}

func get_active_world_space_id() -> String:
	return _active_world_space_id

func is_world_space_supported(world_space_id: String) -> bool:
	if world_space_id == SURFACE_WORLD_SPACE_ID:
		return true
	return _world_state != null and not _get_interior_for_world_space(world_space_id).is_empty()

func set_active_world_space_id(world_space_id: String) -> bool:
	## Discard every active projection before loading the destination WorldSpace.
	if not is_world_space_supported(world_space_id):
		return false
	if world_space_id == _active_world_space_id:
		return true
	_clear_active_world_space_projections()
	_active_world_space_id = world_space_id
	_last_center_chunk = Vector2i(999999, 999999)
	_refresh_interior_wall_visual()
	_update_streaming(true)
	_refresh_connection_markers()
	_refresh_lighting_projection()
	active_world_space_changed.emit(_active_world_space_id)
	return true

func get_loaded_chunk_world_space_ids() -> Array[String]:
	## Read-only validation snapshot; one active WorldSpace should own every loaded projection.
	var world_space_ids: Array[String] = []
	for chunk_value: Variant in _loaded_chunks.values():
		var world_space_id: String = String((chunk_value as Dictionary).get("world_space_id", ""))
		if not world_space_id.is_empty() and world_space_id not in world_space_ids:
			world_space_ids.append(world_space_id)
	world_space_ids.sort()
	return world_space_ids

func _clear_active_world_space_projections() -> void:
	_pending_chunks.clear()
	_queued_chunk_keys.clear()
	_pending_resource_spawns.clear()
	_resource_index.clear()
	_clear_connection_markers()
	if _interior_wall_visual != null:
		var empty_wall_cells: Array[Vector2i] = []
		_interior_wall_visual.call("configure", terrain_layer, empty_wall_cells)
		_interior_wall_visual.visible = false
	terrain_layer.clear()
	_refresh_lighting_projection()
	for projection_root: Node in [resource_root, construction_root, stockpile_zone_root, ground_item_root]:
		for child: Node in projection_root.get_children():
			projection_root.remove_child(child)
			child.queue_free()
	for chunk_coord_value: Variant in _debug_elevation_markers_by_chunk.keys():
		_remove_debug_elevation_markers_for_chunk(chunk_coord_value as Vector2i)
	_clear_debug_elevation_preview()
	_loaded_chunks.clear()
	if _elevation_visual != null and is_instance_valid(_elevation_visual):
		_elevation_visual.call("configure_chunks", terrain_layer.tile_set, {})
	_clear_cliff_face_mesh_renderers()
	if _shader_cliff_rim_visual != null and is_instance_valid(_shader_cliff_rim_visual):
		_shader_cliff_rim_visual.call("clear")

func get_debug_elevation_cell_at_world_position(world_position: Vector2) -> Vector2i:
	## Debug tooling shares the same presentation-aware pick used for terrain context actions.
	var local_position: Vector2 = terrain_layer.to_local(world_position)
	var flat_cell: Vector2i = terrain_layer.local_to_map(local_position)
	var cells: Array[Vector2i] = _resolve_visible_terrain_cells(local_position, flat_cell, _active_world_space_id)
	return cells[0] if not cells.is_empty() else flat_cell

func _resolve_visible_terrain_cells(local_position: Vector2, flat_cell: Vector2i, world_space_id: String) -> Array[Vector2i]:
	var hits: Array[Dictionary] = []
	for y in range(flat_cell.y - DEBUG_ELEVATION_PICK_RADIUS, flat_cell.y + DEBUG_ELEVATION_PICK_RADIUS + 1):
		for x in range(flat_cell.x - DEBUG_ELEVATION_PICK_RADIUS, flat_cell.x + DEBUG_ELEVATION_PICK_RADIUS + 1):
			var candidate := Vector2i(x, y)
			if not is_cell_loaded(candidate, world_space_id):
				continue
			var elevation: int = clampi(get_cell_elevation(candidate, world_space_id), 0, 2)
			var hit: Dictionary = _get_visible_cell_hit(local_position, candidate, elevation, world_space_id)
			if hit.is_empty():
				continue
			hit["cell"] = candidate
			hits.append(hit)
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var elevation_a: int = int(a.get("elevation", 0))
		var elevation_b: int = int(b.get("elevation", 0))
		if elevation_a != elevation_b:
			return elevation_a > elevation_b
		var level_a: int = int(a.get("hit_level", 0))
		var level_b: int = int(b.get("hit_level", 0))
		if level_a != level_b:
			return level_a > level_b
		return float(a.get("distance_squared", 0.0)) < float(b.get("distance_squared", 0.0))
	)
	var cells: Array[Vector2i] = []
	for hit: Dictionary in hits:
		var cell: Vector2i = hit.get("cell", flat_cell)
		if cell not in cells:
			cells.append(cell)
	if flat_cell not in cells:
		cells.append(flat_cell)
	return cells

func _get_visible_cell_hit(local_position: Vector2, cell: Vector2i, elevation: int, world_space_id: String) -> Dictionary:
	# Test each rendered block level so clicks on cliff faces resolve to the raised cell instead of the flat base cell.
	for level in range(elevation, -1, -1):
		var top_center: Vector2 = CellRenderInfoRef.get_visible_top_center(terrain_layer.map_to_local(cell), level)
		if CellRenderInfoRef.contains_visible_top(local_position, top_center):
			return {
				"elevation": elevation,
				"hit_level": level,
				"distance_squared": local_position.distance_squared_to(top_center),
			}
	var elevated_top_center: Vector2 = CellRenderInfoRef.get_visible_top_center(terrain_layer.map_to_local(cell), elevation)
	for direction_name_value: Variant in CLIFF_RIM_NEIGHBOURS.keys():
		var direction_name: String = String(direction_name_value)
		var neighbour_cell: Vector2i = cell + CLIFF_RIM_NEIGHBOURS[direction_name]
		var neighbour_elevation: int = clampi(get_cell_elevation(neighbour_cell, world_space_id), 0, 2)
		if elevation <= neighbour_elevation:
			continue
		var face_polygon: PackedVector2Array = _build_cliff_face_polygon(elevated_top_center, direction_name, elevation - neighbour_elevation)
		if face_polygon.size() >= 3 and Geometry2D.is_point_in_polygon(local_position, face_polygon):
			return {
				"elevation": elevation,
				"hit_level": elevation,
				"distance_squared": local_position.distance_squared_to(elevated_top_center),
			}
	return {}

func is_cell_loaded(cell: Vector2i, world_space_id: String = SURFACE_WORLD_SPACE_ID) -> bool:
	if not is_world_space_supported(world_space_id) or world_space_id != _active_world_space_id:
		return false
	return _loaded_chunks.has(_cell_to_chunk(cell))

func is_cell_blocked_by_resource(cell: Vector2i, world_space_id: String = SURFACE_WORLD_SPACE_ID) -> bool:
	if not is_world_space_supported(world_space_id) or world_space_id != _active_world_space_id:
		return false
	var chunk_coord: Vector2i = _cell_to_chunk(cell)
	if not _loaded_chunks.has(chunk_coord):
		return false
	for spawn_data: Dictionary in _loaded_chunks[chunk_coord].get("resource_spawns", []):
		if spawn_data.get("cell", Vector2i.ZERO) == cell and not _is_resource_depleted(spawn_data):
			return true
	return false

func set_world_state(world_state: Node) -> void:
	if _world_state != null:
		if _world_state.connection_added.is_connected(_on_connection_added):
			_world_state.connection_added.disconnect(_on_connection_added)
		if _world_state.connection_removed.is_connected(_on_connection_removed):
			_world_state.connection_removed.disconnect(_on_connection_removed)
		if _world_state.connections_replaced.is_connected(_on_connections_replaced):
			_world_state.connections_replaced.disconnect(_on_connections_replaced)
		if _world_state.interior_added.is_connected(_on_interior_added):
			_world_state.interior_added.disconnect(_on_interior_added)
		if _world_state.interiors_replaced.is_connected(_on_interiors_replaced):
			_world_state.interiors_replaced.disconnect(_on_interiors_replaced)
		if _world_state.construction_site_added.is_connected(_on_construction_site_added):
			_world_state.construction_site_added.disconnect(_on_construction_site_added)
		if _world_state.construction_site_changed.is_connected(_on_construction_site_changed):
			_world_state.construction_site_changed.disconnect(_on_construction_site_changed)
		if _world_state.construction_site_cancelled.is_connected(_on_construction_site_cancelled):
			_world_state.construction_site_cancelled.disconnect(_on_construction_site_cancelled)
		if _world_state.day_phase_changed.is_connected(_on_building_effect_day_phase_changed):
			_world_state.day_phase_changed.disconnect(_on_building_effect_day_phase_changed)
		if _world_state.lighting_changed.is_connected(_on_lighting_changed):
			_world_state.lighting_changed.disconnect(_on_lighting_changed)
		if _world_state.construction_sites_replaced.is_connected(_on_construction_sites_replaced):
			_world_state.construction_sites_replaced.disconnect(_on_construction_sites_replaced)
		if _world_state.harvest_order_added.is_connected(_on_harvest_order_added):
			_world_state.harvest_order_added.disconnect(_on_harvest_order_added)
		if _world_state.harvest_order_removed.is_connected(_on_harvest_order_removed):
			_world_state.harvest_order_removed.disconnect(_on_harvest_order_removed)
		if _world_state.harvest_orders_replaced.is_connected(_on_harvest_orders_replaced):
			_world_state.harvest_orders_replaced.disconnect(_on_harvest_orders_replaced)
		if _world_state.mined_terrain_delta_added.is_connected(_on_mined_terrain_delta_added):
			_world_state.mined_terrain_delta_added.disconnect(_on_mined_terrain_delta_added)
		if _world_state.mined_terrain_deltas_replaced.is_connected(_on_mined_terrain_deltas_replaced):
			_world_state.mined_terrain_deltas_replaced.disconnect(_on_mined_terrain_deltas_replaced)
		if _world_state.stockpile_zone_added.is_connected(_on_stockpile_zone_added):
			_world_state.stockpile_zone_added.disconnect(_on_stockpile_zone_added)
		if _world_state.stockpile_zone_removed.is_connected(_on_stockpile_zone_removed):
			_world_state.stockpile_zone_removed.disconnect(_on_stockpile_zone_removed)
		if _world_state.stockpile_zones_replaced.is_connected(_on_stockpile_zones_replaced):
			_world_state.stockpile_zones_replaced.disconnect(_on_stockpile_zones_replaced)
		if _world_state.ground_item_added.is_connected(_on_ground_item_added):
			_world_state.ground_item_added.disconnect(_on_ground_item_added)
		if _world_state.ground_item_removed.is_connected(_on_ground_item_removed):
			_world_state.ground_item_removed.disconnect(_on_ground_item_removed)
		if _world_state.ground_items_replaced.is_connected(_on_ground_items_replaced):
			_world_state.ground_items_replaced.disconnect(_on_ground_items_replaced)
	_world_state = world_state
	if _world_state == null:
		_clear_connection_markers()
		return
	_world_state.connection_added.connect(_on_connection_added)
	_world_state.connection_removed.connect(_on_connection_removed)
	_world_state.connections_replaced.connect(_on_connections_replaced)
	_world_state.interior_added.connect(_on_interior_added)
	_world_state.interiors_replaced.connect(_on_interiors_replaced)
	_world_state.construction_site_added.connect(_on_construction_site_added)
	_world_state.construction_site_changed.connect(_on_construction_site_changed)
	_world_state.construction_site_cancelled.connect(_on_construction_site_cancelled)
	_world_state.construction_sites_replaced.connect(_on_construction_sites_replaced)
	_world_state.day_phase_changed.connect(_on_building_effect_day_phase_changed)
	_world_state.lighting_changed.connect(_on_lighting_changed)
	_world_state.harvest_order_added.connect(_on_harvest_order_added)
	_world_state.harvest_order_removed.connect(_on_harvest_order_removed)
	_world_state.harvest_orders_replaced.connect(_on_harvest_orders_replaced)
	_world_state.mined_terrain_delta_added.connect(_on_mined_terrain_delta_added)
	_world_state.mined_terrain_deltas_replaced.connect(_on_mined_terrain_deltas_replaced)
	_world_state.stockpile_zone_added.connect(_on_stockpile_zone_added)
	_world_state.stockpile_zone_removed.connect(_on_stockpile_zone_removed)
	_world_state.stockpile_zones_replaced.connect(_on_stockpile_zones_replaced)
	_world_state.ground_item_added.connect(_on_ground_item_added)
	_world_state.ground_item_removed.connect(_on_ground_item_removed)
	_world_state.ground_items_replaced.connect(_on_ground_items_replaced)
	_on_construction_sites_replaced()
	_on_harvest_orders_replaced()
	_on_stockpile_zones_replaced()
	_on_ground_items_replaced()
	_refresh_connection_markers()
	_refresh_lighting_projection()

func get_connection_marker_at_world_position(world_position: Vector2) -> Dictionary:
	var closest: Node2D
	var closest_distance_squared: float = INF
	for marker: Node2D in _connection_markers:
		if not is_instance_valid(marker) or not bool(marker.call("contains_world_position", world_position)):
			continue
		var marker_world_position: Vector2 = marker.call("get_visual_world_position")
		var distance_squared: float = marker_world_position.distance_squared_to(world_position)
		if distance_squared < closest_distance_squared:
			closest = marker
			closest_distance_squared = distance_squared
	return closest.call("get_context_snapshot") if closest != null else {}

func get_connection_marker_count() -> int:
	return _connection_markers.size()

func get_connection_marker_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for marker: Node2D in _connection_markers:
		if not is_instance_valid(marker):
			continue
		var snapshot: Dictionary = marker.call("get_context_snapshot")
		snapshot["world_position"] = marker.call("get_visual_world_position")
		snapshot["tile_anchor_world_position"] = marker.call("get_tile_anchor_world_position")
		snapshots.append(snapshot)
	return snapshots

func _refresh_connection_markers() -> void:
	_clear_connection_markers()
	if _world_state == null or _connection_root == null:
		return
	for connection: Dictionary in _world_state.get_connections_for_world_space(_active_world_space_id):
		if not bool(connection.get("enabled", false)):
			continue
		var endpoint_cell: Vector2i
		var action_label: String
		var is_cave_exit: bool = _is_interior_world_space(_active_world_space_id)
		if String(connection.get("from_world_space_id", "")) == _active_world_space_id:
			endpoint_cell = connection.get("from_cell", Vector2i.ZERO)
			action_label = "Exit Mine" if is_cave_exit else "Enter Mine"
		elif bool(connection.get("bidirectional", false)) and String(connection.get("to_world_space_id", "")) == _active_world_space_id:
			endpoint_cell = connection.get("to_cell", Vector2i.ZERO)
			action_label = "Exit Mine" if is_cave_exit else "Enter Mine"
		else:
			continue
		if not is_cell_loaded(endpoint_cell, _active_world_space_id):
			continue
		var marker: Node2D = ConnectionMarkerVisualScript.new() as Node2D
		marker.name = "ConnectionMarker_%s" % String(connection.get("connection_id", "unknown"))
		marker.call("configure", terrain_layer.tile_set, String(connection.get("connection_id", "")), _active_world_space_id, endpoint_cell, get_cell_elevation(endpoint_cell, _active_world_space_id), action_label, is_cave_exit, _get_connection_endpoint_facing(connection, endpoint_cell))
		_connection_root.add_child(marker)
		_connection_markers.append(marker)

func _get_connection_endpoint_facing(connection: Dictionary, endpoint_cell: Vector2i) -> String:
	## Presentation-only facing derived from the other authoritative connection endpoint.
	var other_cell: Vector2i = connection.get("to_cell", Vector2i.ZERO)
	if endpoint_cell == other_cell:
		other_cell = connection.get("from_cell", Vector2i.ZERO)
	var offset := other_cell - endpoint_cell
	if abs(offset.x) >= abs(offset.y):
		return "east" if offset.x >= 0 else "west"
	return "south" if offset.y >= 0 else "north"

func _clear_connection_markers() -> void:
	for marker: Node2D in _connection_markers:
		if not is_instance_valid(marker):
			continue
		if marker.get_parent() != null:
			marker.get_parent().remove_child(marker)
		marker.queue_free()
	_connection_markers.clear()

func _refresh_interior_wall_visual() -> void:
	if _interior_wall_visual == null:
		return
	var interior: Dictionary = _get_interior_for_world_space(_active_world_space_id)
	if interior.is_empty():
		_interior_wall_visual.visible = false
		var empty_wall_cells: Array[Vector2i] = []
		_interior_wall_visual.call("configure", terrain_layer, empty_wall_cells)
		return
	_interior_wall_visual.call("configure", terrain_layer, InteriorTerrainSourceRef.get_wall_cells(interior))
	_interior_wall_visual.visible = true

func _on_connection_added(_connection: Dictionary) -> void:
	_refresh_connection_markers()

func _on_connection_removed(_connection_id: String) -> void:
	_refresh_connection_markers()

func _on_connections_replaced() -> void:
	_refresh_connection_markers()

func _on_interior_added(_interior: Dictionary) -> void:
	_refresh_interior_wall_visual()
	_refresh_connection_markers()

func _on_interiors_replaced() -> void:
	_refresh_interior_wall_visual()
	_refresh_connection_markers()

func _on_mined_terrain_delta_added(delta: Dictionary) -> void:
	_apply_mined_terrain_delta_projection(delta)

func _on_mined_terrain_deltas_replaced() -> void:
	if _active_world_space_id != SURFACE_WORLD_SPACE_ID:
		return
	for chunk_coord_value: Variant in _loaded_chunks.keys():
		var chunk_coord: Vector2i = chunk_coord_value
		var tile_lookup: Dictionary = _loaded_chunks[chunk_coord].get("tile_lookup", {})
		for tile_info_value: Variant in (_loaded_chunks[chunk_coord].get("tiles", []) as Array):
			var tile_info: Dictionary = tile_info_value
			tile_lookup[tile_info.cell] = _resolve_surface_projected_tile_info(tile_info)
		_loaded_chunks[chunk_coord]["tile_lookup"] = tile_lookup
	_refresh_elevation_visuals()

func _apply_mined_terrain_delta_projection(delta: Dictionary) -> void:
	if _active_world_space_id != SURFACE_WORLD_SPACE_ID:
		return
	var world_space_id: String = String(delta.get("world_space_id", SURFACE_WORLD_SPACE_ID))
	if world_space_id != SURFACE_WORLD_SPACE_ID:
		return
	var cell: Vector2i = delta.get("cell", Vector2i.ZERO)
	var chunk_coord: Vector2i = _cell_to_chunk(cell)
	if not _loaded_chunks.has(chunk_coord):
		return
	var tile_info: Dictionary = _build_tile_info_for_mined_delta(delta)
	if tile_info.is_empty():
		return
	var tile_lookup: Dictionary = _loaded_chunks[chunk_coord].get("tile_lookup", {})
	tile_lookup[cell] = tile_info
	_loaded_chunks[chunk_coord]["tile_lookup"] = tile_lookup
	_refresh_terrain_visuals_near_cell(cell)

func _get_interior_for_world_space(world_space_id: String) -> Dictionary:
	if _world_state == null:
		return {}
	return _world_state.get_interior_for_world_space(world_space_id)

func _is_interior_world_space(world_space_id: String) -> bool:
	return not _get_interior_for_world_space(world_space_id).is_empty()

func set_harvest_designation_input_enabled(enabled: bool) -> void:
	## Main owns the transient control mode; this only gates presentation-originated click intent.
	_harvest_designation_input_enabled = enabled

func is_harvest_designation_input_enabled() -> bool:
	return _harvest_designation_input_enabled

func get_effective_tile_info(cell: Vector2i, world_space_id: String = SURFACE_WORLD_SPACE_ID) -> Dictionary:
	if not is_world_space_supported(world_space_id) or world_space_id != _active_world_space_id:
		return {}
	var chunk_coord: Vector2i = _cell_to_chunk(cell)
	if _loaded_chunks.has(chunk_coord):
		var tile_lookup: Dictionary = _loaded_chunks[chunk_coord].get("tile_lookup", {})
		if tile_lookup.has(cell):
			return tile_lookup[cell].duplicate()
	var interior: Dictionary = _get_interior_for_world_space(world_space_id)
	if not interior.is_empty():
		return InteriorTerrainSourceRef.get_tile_info(interior, cell)
	var mined_tile_info: Dictionary = _build_mined_terrain_tile_info(cell, world_space_id)
	if not mined_tile_info.is_empty():
		return mined_tile_info
	return _manual_tile_overrides.get(cell, _world_generator.get_tile_info(cell)).duplicate()

func get_surface_effective_tile_info(cell: Vector2i) -> Dictionary:
	## Read-only import/validation query for surface terrain deltas; independent of the currently rendered WorldSpace.
	var mined_tile_info: Dictionary = _build_mined_terrain_tile_info(cell, SURFACE_WORLD_SPACE_ID)
	if not mined_tile_info.is_empty():
		return mined_tile_info
	return _manual_tile_overrides.get(cell, _world_generator.get_tile_info(cell)).duplicate()

func get_cell_elevation(cell: Vector2i, world_space_id: String = SURFACE_WORLD_SPACE_ID) -> int:
	return int(get_effective_tile_info(cell, world_space_id).get("elevation", 0))

func can_move_between_cells(from_cell: Vector2i, to_cell: Vector2i, world_space_id: String = SURFACE_WORLD_SPACE_ID) -> bool:
	## Authoritative local transition rule shared by path queries and live movement.
	## Rendering geometry and collision shapes deliberately do not participate.
	if not is_world_space_supported(world_space_id):
		return false
	if abs(to_cell.x - from_cell.x) + abs(to_cell.y - from_cell.y) != 1:
		return false
	if not is_cell_loaded(from_cell, world_space_id) or not is_cell_loaded(to_cell, world_space_id):
		return false
	var from_info: Dictionary = get_effective_tile_info(from_cell, world_space_id)
	var target_info: Dictionary = get_effective_tile_info(to_cell, world_space_id)
	return bool(target_info.get("walkable", false)) and int(target_info.get("elevation", 0)) == int(from_info.get("elevation", 0))

func get_move_block_reason(from_cell: Vector2i, to_cell: Vector2i) -> String:
	## Debug-only explanation kept off the hot pathfinding loop.
	if can_move_between_cells(from_cell, to_cell):
		return ""
	if abs(to_cell.x - from_cell.x) + abs(to_cell.y - from_cell.y) != 1:
		return "cells_not_adjacent"
	if not is_cell_loaded(from_cell):
		return "from_cell_not_loaded"
	if not is_cell_loaded(to_cell):
		return "to_cell_not_loaded"
	var target_info: Dictionary = get_effective_tile_info(to_cell)
	if not bool(target_info.get("walkable", false)):
		return "to_cell_not_walkable"
	if int(target_info.get("elevation", 0)) != get_cell_elevation(from_cell):
		return "elevation_transition_blocked"
	return "movement_blocked"

func set_debug_elevation_preview(cell: Vector2i, visible: bool) -> void:
	## Debug projection only: this never writes terrain metadata or simulation state.
	if visible and is_cell_loaded(cell) and _debug_elevation_preview != null and is_instance_valid(_debug_elevation_preview) and cell == _debug_elevation_preview_cell:
		return
	_clear_debug_elevation_preview()
	debug_elevation_level_label.visible = false
	if not visible or not is_cell_loaded(cell):
		return
	var actual_elevation: int = clampi(get_cell_elevation(cell), 0, 2)
	_debug_elevation_preview = _create_debug_elevation_visual(cell, actual_elevation, 0.32)
	_debug_elevation_preview_cell = cell
	_debug_elevation_preview.name = "DebugElevationPreview"
	debug_elevation_root.add_child(_debug_elevation_preview)
	debug_elevation_level_label.text = "E%d" % actual_elevation
	var render_info: Dictionary = CellRenderInfoRef.build(get_effective_tile_info(cell), terrain_layer.map_to_local(cell))
	debug_elevation_level_label.position = render_info.get("top_position", terrain_layer.map_to_local(cell)) + CellRenderInfoRef.TOP_DIAMOND_OFFSET + Vector2(10.0, -10.0)
	debug_elevation_level_label.visible = true

func place_debug_elevation_marker(cell: Vector2i, solid: bool) -> bool:
	if not is_cell_loaded(cell):
		return false
	var actual_elevation: int = clampi(get_cell_elevation(cell), 0, 2)
	var chunk_coord: Vector2i = _cell_to_chunk(cell)
	var markers: Array = _debug_elevation_markers_by_chunk.get(chunk_coord, [])
	for index in range(markers.size() - 1, -1, -1):
		var existing: Node = markers[index]
		if not is_instance_valid(existing) or existing.get_meta("cell", Vector2i(999999, 999999)) == cell:
			markers.remove_at(index)
			if is_instance_valid(existing):
				if existing.get_parent() == debug_elevation_root:
					debug_elevation_root.remove_child(existing)
				existing.queue_free()
	var visual: Node2D = _create_debug_elevation_visual(cell, actual_elevation, 1.0 if solid else 0.48)
	visual.name = "DebugElevationSolid_%d_%d" % [cell.x, cell.y] if solid else "DebugElevationTranslucent_%d_%d" % [cell.x, cell.y]
	visual.set_meta("cell", cell)
	visual.set_meta("chunk_coord", chunk_coord)
	debug_elevation_root.add_child(visual)
	markers.append(visual)
	_debug_elevation_markers_by_chunk[chunk_coord] = markers
	return true

func clear_debug_elevation_preview() -> void:
	_clear_debug_elevation_preview()
	debug_elevation_level_label.visible = false

func _create_debug_elevation_visual(cell: Vector2i, actual_elevation: int, alpha: float) -> Node2D:
	var tile_info: Dictionary = get_effective_tile_info(cell)
	## E0 still receives a one-level marker so alignment can be inspected without changing its reported level.
	tile_info["elevation"] = maxi(actual_elevation, 1)
	var marker := CanvasGroup.new()
	marker.modulate = Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))
	marker.set_meta("cell", cell)
	var visual: Node2D = ElevationStackVisualScript.new() as Node2D
	var render_infos: Array[Dictionary] = [CellRenderInfoRef.build(tile_info, terrain_layer.map_to_local(cell))]
	visual.call("configure", terrain_layer.tile_set, render_infos)
	marker.add_child(visual)
	return marker

func _clear_debug_elevation_preview() -> void:
	if _debug_elevation_preview == null or not is_instance_valid(_debug_elevation_preview):
		_debug_elevation_preview = null
		_debug_elevation_preview_cell = Vector2i(999999, 999999)
		return
	if _debug_elevation_preview.get_parent() == debug_elevation_root:
		debug_elevation_root.remove_child(_debug_elevation_preview)
	_debug_elevation_preview.queue_free()
	_debug_elevation_preview = null
	_debug_elevation_preview_cell = Vector2i(999999, 999999)

func is_cell_mineable(cell: Vector2i) -> bool:
	return bool(get_effective_tile_info(cell).get("mineable", false))

func is_loaded_surface_rock_wall(cell: Vector2i) -> bool:
	if _active_world_space_id != SURFACE_WORLD_SPACE_ID or not is_cell_loaded(cell, SURFACE_WORLD_SPACE_ID):
		return false
	var tile_info: Dictionary = get_effective_tile_info(cell, SURFACE_WORLD_SPACE_ID)
	return String(tile_info.get("terrain", "")) == "ROCK_WALL" and bool(tile_info.get("mineable", false))

func has_manual_tile_override(cell: Vector2i) -> bool:
	return _manual_tile_overrides.has(cell)

func is_resource_depleted(resource_id: String) -> bool:
	return not resource_id.is_empty() and _depleted_resource_ids.has(resource_id)

func get_chunk_delta_summary(chunk_coord: Vector2i) -> Dictionary:
	var manual_count: int = 0
	for cell: Variant in _manual_tile_overrides.keys():
		if _cell_to_chunk(cell) == chunk_coord:
			manual_count += 1
	var depleted_count: int = 0
	var chunk_origin: Vector2i = chunk_coord * WorldGenerator.CHUNK_SIZE
	for resource_id: Variant in _depleted_resource_ids.keys():
		var resource_cell: Vector2i = _parse_resource_id_cell(String(resource_id))
		if resource_cell.x >= chunk_origin.x and resource_cell.y >= chunk_origin.y and resource_cell.x < chunk_origin.x + WorldGenerator.CHUNK_SIZE and resource_cell.y < chunk_origin.y + WorldGenerator.CHUNK_SIZE:
			depleted_count += 1
	return {
		"chunk_coord": chunk_coord,
		"manual_tile_overrides": manual_count,
		"depleted_resources": depleted_count,
	}

func request_place_manual_tile(cell: Vector2i, terrain_name: String) -> Dictionary:
	if _active_world_space_id != SURFACE_WORLD_SPACE_ID:
		return _build_manual_placement_result(false, "unsupported_world_space_id", cell, terrain_name)
	var chunk_coord: Vector2i = _cell_to_chunk(cell)
	if not _loaded_chunks.has(chunk_coord):
		return _build_manual_placement_result(false, "cell_not_loaded", cell, terrain_name)
	if terrain_name.is_empty():
		return _build_manual_placement_result(false, "empty_terrain_name", cell, terrain_name)
	if not TerrainConfigRef.has_terrain(terrain_name):
		return _build_manual_placement_result(false, "unknown_terrain", cell, terrain_name)
	if TerrainConfigRef.get_atlas_coords(terrain_name) == TerrainConfigRef.INVALID_ATLAS_COORDS:
		return _build_manual_placement_result(false, "invalid_atlas_coords", cell, terrain_name)
	var tile_info: Dictionary = _world_generator.build_tile_info_for_terrain(cell, terrain_name)
	if tile_info.is_empty():
		return _build_manual_placement_result(false, "tile_info_unavailable", cell, terrain_name)
	_manual_tile_overrides[cell] = tile_info
	var tile_lookup: Dictionary = _loaded_chunks[chunk_coord].get("tile_lookup", {})
	tile_lookup[cell] = tile_info
	_loaded_chunks[chunk_coord]["tile_lookup"] = tile_lookup
	_refresh_terrain_visuals_near_cell(cell)
	return _build_manual_placement_result(true, "placed", cell, terrain_name)

func place_manual_tile(cell: Vector2i, terrain_name: String) -> bool:
	return bool(request_place_manual_tile(cell, terrain_name).get("ok", false))

func _build_manual_placement_result(ok: bool, reason: String, cell: Vector2i, terrain_name: String) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"cell": cell,
		"terrain_name": terrain_name,
	}

func get_random_walkable_cell_near(origin: Vector2i, radius: int, attempts: int = 32, require_loaded_same_elevation: bool = true, world_space_id: String = SURFACE_WORLD_SPACE_ID) -> Vector2i:
	## Movement callers receive loaded candidates on the origin elevation. Initial
	## population placement opts out because it runs before streaming is populated.
	if require_loaded_same_elevation and not is_cell_loaded(origin, world_space_id):
		return origin
	for _i in range(attempts):
		var candidate: Vector2i = origin + Vector2i(_wander_rng.randi_range(-radius, radius), _wander_rng.randi_range(-radius, radius))
		if _is_random_walkable_candidate(origin, candidate, require_loaded_same_elevation, world_space_id):
			return candidate
	for step in range(1, radius * 2):
		for offset_x in range(-step, step + 1):
			for offset_y in range(-step, step + 1):
				var candidate: Vector2i = origin + Vector2i(offset_x, offset_y)
				if _is_random_walkable_candidate(origin, candidate, require_loaded_same_elevation, world_space_id):
					return candidate
	return origin

func _is_random_walkable_candidate(origin: Vector2i, candidate: Vector2i, require_loaded_same_elevation: bool, world_space_id: String) -> bool:
	var tile_info: Dictionary = get_effective_tile_info(candidate, world_space_id)
	if not bool(tile_info.get("walkable", false)):
		return false
	if not require_loaded_same_elevation:
		return true
	return is_cell_loaded(candidate, world_space_id) and int(tile_info.get("elevation", 0)) == get_cell_elevation(origin, world_space_id)

func _prewarm_procedural_cache() -> void:
	if not prewarm_procedural_variants:
		return
	if use_procedural_tree_sprites and procedural_tree_variant_cap > 0:
		var tree_request: Dictionary = PropPrewarmConfig.get_tree_request(procedural_tree_variant_cap, procedural_tree_large_size)
		ProcSpriteCache.prewarm(String(tree_request["kind"]), int(tree_request["variant_cap"]), tree_request["archetypes"], tree_request["terrain_tags"], tree_request["size_tiers"], tree_request["size_map"])
	if use_procedural_rock_sprites and procedural_rock_variant_cap > 0:
		var rock_request: Dictionary = PropPrewarmConfig.get_rock_request(procedural_rock_variant_cap, procedural_rock_small_size, procedural_rock_medium_size, procedural_rock_large_size)
		ProcSpriteCache.prewarm(String(rock_request["kind"]), int(rock_request["variant_cap"]), rock_request["archetypes"], rock_request["terrain_tags"], rock_request["size_tiers"], rock_request["size_map"])
	if procedural_cache_debug:
		print("ProcSpriteCache stats ", ProcSpriteCache.get_stats())

func _update_streaming(force_sort: bool) -> void:
	var center_chunk: Vector2i = _get_camera_chunk()
	if center_chunk != _last_center_chunk or force_sort:
		var profile_start_usec: int = Time.get_ticks_usec() if streaming_lifecycle_profile_debug else 0
		_last_center_chunk = center_chunk
		_prune_pending_chunks(center_chunk)
		var prune_end_usec: int = Time.get_ticks_usec() if streaming_lifecycle_profile_debug else 0
		_queue_chunks_around(center_chunk)
		var queue_end_usec: int = Time.get_ticks_usec() if streaming_lifecycle_profile_debug else 0
		_sort_pending(center_chunk)
		var sort_end_usec: int = Time.get_ticks_usec() if streaming_lifecycle_profile_debug else 0
		_unload_far_chunks(center_chunk)
		if streaming_lifecycle_profile_debug:
			var unload_end_usec := Time.get_ticks_usec()
			var snapshot := get_streaming_lifecycle_debug_snapshot()
			print(
				"STREAM_LIFECYCLE_PROFILE center=%s prune_ms=%.3f queue_ms=%.3f sort_ms=%.3f unload_ms=%.3f total_ms=%.3f loaded_chunks=%d loaded_cells=%d resource_nodes=%d pending_chunks=%d stale_pending=%d pending_resources=%d stale_resource_jobs=%d proc_cache=%d elevation_chunks=%d elevation_cells=%d shader_chunks=%d shader_slots=%d boundary_mesh_chunks=%d boundary_mesh_segments=%d stale_visual_chunks=%d manual_overrides=%d depleted_ids=%d" % [
					center_chunk,
					_usec_to_msec(prune_end_usec - profile_start_usec),
					_usec_to_msec(queue_end_usec - prune_end_usec),
					_usec_to_msec(sort_end_usec - queue_end_usec),
					_usec_to_msec(unload_end_usec - sort_end_usec),
					_usec_to_msec(unload_end_usec - profile_start_usec),
					int(snapshot["loaded_chunks"]), int(snapshot["loaded_cells"]), int(snapshot["resource_nodes"]),
					int(snapshot["pending_chunks"]), int(snapshot["stale_pending_chunks"]), int(snapshot["pending_resource_spawns"]),
					int(snapshot["stale_resource_spawns"]), int(snapshot["procedural_cache"]), int(snapshot["elevation_chunks"]),
					int(snapshot["elevation_cells"]), int(snapshot["shader_chunks"]), int(snapshot["shader_slots"]),
					int(snapshot["boundary_mesh_chunks"]), int(snapshot["boundary_mesh_segments"]), int(snapshot["stale_visual_chunks"]),
					int(snapshot["manual_overrides"]), int(snapshot["depleted_resource_ids"]),
				]
			)

func _prune_pending_chunks(center_chunk: Vector2i) -> void:
	## Streaming intent is camera-local. Coordinates left behind before generation
	## are discarded instead of becoming an ever-growing exploration history.
	var retained: Array[Vector2i] = []
	_queued_chunk_keys.clear()
	for chunk_coord: Vector2i in _pending_chunks:
		if _loaded_chunks.has(chunk_coord):
			continue
		if maxi(abs(chunk_coord.x - center_chunk.x), abs(chunk_coord.y - center_chunk.y)) > load_radius:
			continue
		retained.append(chunk_coord)
		_queued_chunk_keys[chunk_coord] = true
	_pending_chunks = retained

func _get_camera_chunk() -> Vector2i:
	var center_cell: Vector2i = world_to_cell(_camera.global_position)
	return _cell_to_chunk(center_cell)

func _cell_to_chunk(cell: Vector2i) -> Vector2i:
	return Vector2i(int(floor(float(cell.x) / float(WorldGenerator.CHUNK_SIZE))), int(floor(float(cell.y) / float(WorldGenerator.CHUNK_SIZE))))

func _queue_chunks_around(center_chunk: Vector2i) -> void:
	for y in range(center_chunk.y - load_radius, center_chunk.y + load_radius + 1):
		for x in range(center_chunk.x - load_radius, center_chunk.x + load_radius + 1):
			var chunk_coord: Vector2i = Vector2i(x, y)
			if _loaded_chunks.has(chunk_coord) or _queued_chunk_keys.has(chunk_coord):
				continue
			_queued_chunk_keys[chunk_coord] = true
			_pending_chunks.append(chunk_coord)

func _sort_pending(center_chunk: Vector2i) -> void:
	_pending_chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(center_chunk) < b.distance_squared_to(center_chunk)
	)

func _generate_chunk(chunk_coord: Vector2i) -> void:
	_queued_chunk_keys.erase(chunk_coord)
	if _loaded_chunks.has(chunk_coord):
		return
	# A final guard prevents a coordinate dequeued under an older camera center
	# from generating after it is no longer part of the desired loaded region.
	if maxi(abs(chunk_coord.x - _last_center_chunk.x), abs(chunk_coord.y - _last_center_chunk.y)) > load_radius:
		return
	var profile_start_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
	var active_interior: Dictionary = _get_interior_for_world_space(_active_world_space_id)
	var chunk_data: Dictionary = InteriorTerrainSourceRef.generate_chunk(active_interior, chunk_coord, WorldGenerator.CHUNK_SIZE) if not active_interior.is_empty() else _world_generator.generate_chunk(chunk_coord)
	var generation_end_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
	var tile_lookup: Dictionary = {}
	for tile_info: Dictionary in chunk_data.tiles:
		var final_tile_info: Dictionary = _resolve_surface_projected_tile_info(tile_info) if _active_world_space_id == SURFACE_WORLD_SPACE_ID else tile_info
		tile_lookup[final_tile_info.cell] = final_tile_info
	var resource_nodes: Array[Node] = []
	_loaded_chunks[chunk_coord] = {
		"world_space_id": _active_world_space_id,
		"resource_nodes": resource_nodes,
		"construction_nodes": [],
		"stockpile_zone_nodes": [],
		"ground_item_nodes": [],
		"resource_spawns": chunk_data.resources,
		"tiles": chunk_data.tiles,
		"tile_lookup": tile_lookup,
	}
	_refresh_terrain_tiles_for_loaded_chunk(chunk_coord)
	_refresh_neighbour_terrain_variant_edges_for_loaded_chunk(chunk_coord)
	var tile_write_end_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
	var elevation_start_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
	_refresh_elevation_stack_visual_chunks([chunk_coord])
	var elevation_end_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
	var shader_profile: Dictionary = {}
	if shader_cliff_rims_enabled:
		shader_profile = _refresh_shader_cliff_rim_chunk(chunk_coord)
	else:
		_refresh_cliff_edge_rims_for_loaded_chunk(chunk_coord)
	var rim_end_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
	if stage_resource_spawning:
		for spawn_data: Dictionary in chunk_data.resources:
			if _is_resource_depleted(spawn_data):
				continue
			_pending_resource_spawns.append({"chunk_coord": chunk_coord, "spawn_data": spawn_data})
	else:
		for spawn_data: Dictionary in chunk_data.resources:
			if _is_resource_depleted(spawn_data):
				continue
			var resource: ResourceNode = _build_resource_node(spawn_data, chunk_coord)
			if resource == null:
				continue
			resource_root.add_child(resource)
			resource_nodes.append(resource)
			_track_resource_node(resource, chunk_coord)
	_spawn_construction_visuals_for_chunk(chunk_coord)
	_spawn_stockpile_zone_visuals_for_chunk(chunk_coord)
	_spawn_ground_item_visuals_for_chunk(chunk_coord)
	_refresh_connection_markers()
	_refresh_lighting_projection()
	chunk_generated.emit(chunk_coord)
	if chunk_profile_debug:
		var profile_end_usec := Time.get_ticks_usec()
		_record_chunk_load_profile({
			"generation": generation_end_usec - profile_start_usec,
			"tile_writes": tile_write_end_usec - generation_end_usec,
			"elevation_stack": elevation_end_usec - elevation_start_usec,
			"elevation_texture": int(shader_profile.get("texture_usec", 0)),
			"shader_overlay": int(shader_profile.get("overlay_usec", 0)),
			"boundary_mesh": rim_end_usec - elevation_end_usec if not shader_cliff_rims_enabled else 0,
			"resource_setup": profile_end_usec - rim_end_usec,
			"total": profile_end_usec - profile_start_usec,
		})
		print(
			"CHUNK_PROFILE load=%s generation_ms=%.3f tile_writes_ms=%.3f elevation_stack_ms=%.3f elevation_texture_ms=%.3f shader_overlay_ms=%.3f boundary_mesh_ms=%.3f cliff_rims_ms=%.3f resource_setup_ms=%.3f total_ms=%.3f loaded_chunks=%d" % [
				chunk_coord,
				_usec_to_msec(generation_end_usec - profile_start_usec),
				_usec_to_msec(tile_write_end_usec - generation_end_usec),
				_usec_to_msec(elevation_end_usec - elevation_start_usec),
				_usec_to_msec(int(shader_profile.get("texture_usec", 0))),
				_usec_to_msec(int(shader_profile.get("overlay_usec", 0))),
				_usec_to_msec(rim_end_usec - elevation_end_usec) if not shader_cliff_rims_enabled else 0.0,
				_usec_to_msec(rim_end_usec - elevation_end_usec),
				_usec_to_msec(profile_end_usec - rim_end_usec),
				_usec_to_msec(profile_end_usec - profile_start_usec),
				_loaded_chunks.size(),
			]
		)

func _refresh_elevation_visuals() -> void:
	_refresh_cliff_edge_rims()
	_refresh_terrain_tiles_for_loaded_chunks()
	_refresh_elevation_stack_visuals()

func _refresh_elevation_stack_visuals() -> void:
	## Explicit full rebuild path; ordinary streaming uses per-chunk updates.
	if _elevation_visual == null or not is_instance_valid(_elevation_visual):
		return
	var render_infos_by_chunk: Dictionary = {}
	for chunk_coord_value: Variant in _loaded_chunks:
		var chunk_coord: Vector2i = chunk_coord_value
		render_infos_by_chunk[chunk_coord] = _build_elevation_render_infos_for_chunk(chunk_coord)
	_elevation_visual.call("configure_chunks", terrain_layer.tile_set, render_infos_by_chunk)

func _refresh_elevation_stack_visual_chunks(chunk_coords: Array) -> void:
	if _elevation_visual == null or not is_instance_valid(_elevation_visual):
		return
	for chunk_coord_value: Variant in chunk_coords:
		var chunk_coord: Vector2i = chunk_coord_value
		if not _loaded_chunks.has(chunk_coord):
			_elevation_visual.call("remove_chunk", chunk_coord)
			continue
		_elevation_visual.call(
			"configure_chunk",
			terrain_layer.tile_set,
			chunk_coord,
			_build_elevation_render_infos_for_chunk(chunk_coord)
		)

func _refresh_terrain_tiles_for_loaded_chunks() -> void:
	for chunk_coord_value: Variant in _loaded_chunks.keys():
		var chunk_coord: Vector2i = chunk_coord_value
		_refresh_terrain_tiles_for_loaded_chunk(chunk_coord)

func _refresh_terrain_tiles_for_loaded_chunk(chunk_coord: Vector2i) -> void:
	if not _loaded_chunks.has(chunk_coord):
		return
	var tile_lookup: Dictionary = _loaded_chunks[chunk_coord].get("tile_lookup", {})
	for tile_info_value: Variant in tile_lookup.values():
		var tile_info: Dictionary = tile_info_value as Dictionary
		_write_terrain_visual_tile(tile_info)

func _refresh_neighbour_terrain_variant_edges_for_loaded_chunk(chunk_coord: Vector2i) -> void:
	## A newly loaded chunk can affect north/west edge variants in adjacent
	## loaded chunks without changing their terrain authority.
	for neighbour_offset in [Vector2i.DOWN, Vector2i.RIGHT]:
		var neighbour_chunk: Vector2i = chunk_coord + neighbour_offset
		if _loaded_chunks.has(neighbour_chunk):
			_refresh_terrain_tiles_for_loaded_chunk(neighbour_chunk)

func _refresh_terrain_variant_tiles_near_cell(cell: Vector2i) -> void:
	## The edited cell and its east/south neighbours are the only loaded cells
	## whose north/west edge variant can change from this cell's terrain data.
	for affected_cell in [cell, cell + Vector2i.RIGHT, cell + Vector2i.DOWN]:
		if not is_cell_loaded(affected_cell):
			continue
		var chunk_coord: Vector2i = _cell_to_chunk(affected_cell)
		var tile_lookup: Dictionary = _loaded_chunks[chunk_coord].get("tile_lookup", {})
		if tile_lookup.has(affected_cell):
			_write_terrain_visual_tile(tile_lookup[affected_cell] as Dictionary)

func _write_terrain_visual_tile(tile_info: Dictionary) -> void:
	var cell: Vector2i = tile_info.get("cell", Vector2i.ZERO)
	var variant_key: String = _get_elevation_edge_variant_key_for_cell(cell)
	var terrain_name: String = String(tile_info.get("terrain", ""))
	var flat_atlas_coords: Vector2i = tile_info.get("atlas_coords", TerrainConfigRef.INVALID_ATLAS_COORDS)
	var visual_atlas_coords: Vector2i = TerrainConfigRef.get_visual_atlas_coords(terrain_name, variant_key, flat_atlas_coords)
	terrain_layer.set_cell(cell, int(tile_info.get("source_id", -1)), visual_atlas_coords)

func _resolve_surface_projected_tile_info(base_tile_info: Dictionary) -> Dictionary:
	var cell: Vector2i = base_tile_info.get("cell", Vector2i.ZERO)
	var mined_tile_info: Dictionary = _build_mined_terrain_tile_info(cell, SURFACE_WORLD_SPACE_ID)
	if not mined_tile_info.is_empty():
		return mined_tile_info
	return _manual_tile_overrides.get(cell, base_tile_info).duplicate()

func _build_mined_terrain_tile_info(cell: Vector2i, world_space_id: String = SURFACE_WORLD_SPACE_ID) -> Dictionary:
	if _world_state == null or world_space_id != SURFACE_WORLD_SPACE_ID:
		return {}
	if not _world_state.has_mined_terrain_delta(cell, world_space_id):
		return {}
	return _build_tile_info_for_mined_delta(_world_state.get_mined_terrain_delta(cell, world_space_id))

func _build_tile_info_for_mined_delta(delta: Dictionary) -> Dictionary:
	var cell: Vector2i = delta.get("cell", Vector2i.ZERO)
	var terrain_name: String = String(delta.get("to_terrain", "STONE"))
	if not TerrainConfigRef.has_terrain(terrain_name):
		return {}
	var tile_info: Dictionary = _world_generator.build_tile_info_for_terrain(cell, terrain_name)
	return tile_info.duplicate()

func _get_elevation_edge_variant_key_for_cell(cell: Vector2i) -> String:
	var elevation: int = _get_effective_elevation_for_rim(cell)
	if elevation <= 0:
		return ElevationEdgeVariantResolverRef.VARIANT_FLAT
	var mask: int = 0
	if elevation > _get_effective_elevation_for_rim(cell + Vector2i.UP):
		mask |= ElevationEdgeVariantResolverRef.MASK_NORTH
	if elevation > _get_effective_elevation_for_rim(cell + Vector2i.LEFT):
		mask |= ElevationEdgeVariantResolverRef.MASK_WEST
	return ElevationEdgeVariantResolverRef.get_variant_key(mask)

func _build_elevation_render_infos_for_chunk(chunk_coord: Vector2i) -> Array[Dictionary]:
	var render_infos: Array[Dictionary] = []
	if not _loaded_chunks.has(chunk_coord):
		return render_infos
	var tile_lookup: Dictionary = _loaded_chunks[chunk_coord].get("tile_lookup", {})
	for tile_info_value: Variant in tile_lookup.values():
		var tile_info: Dictionary = tile_info_value as Dictionary
		if int(tile_info.get("elevation", 0)) <= 0:
			continue
		var cell: Vector2i = tile_info.get("cell", Vector2i.ZERO)
		render_infos.append(CellRenderInfoRef.build(tile_info, terrain_layer.map_to_local(cell)))
	return render_infos

func _refresh_cliff_edge_rims() -> void:
	## Explicit full rebuild path; streaming uses boundary-aware cell updates below.
	if shader_cliff_rims_enabled:
		_clear_cliff_face_mesh_renderers()
		_refresh_shader_cliff_rims()
		return
	if not enable_cliff_face_overlay:
		_clear_cliff_face_mesh_renderers()
		return
	if _chunk_boundary_mesh_root == null or not is_instance_valid(_chunk_boundary_mesh_root):
		return
	_clear_cliff_face_mesh_renderers()
	for chunk_coord_value: Variant in _loaded_chunks.keys():
		var chunk_coord: Vector2i = chunk_coord_value
		_configure_chunk_boundary_mesh_renderer(chunk_coord, _build_cliff_edge_rim_segments_for_chunk(chunk_coord))

func _refresh_shader_cliff_rims() -> void:
	## Explicit global texture rebuild for restore/import/debug paths.
	if _shader_cliff_rim_visual == null or not is_instance_valid(_shader_cliff_rim_visual):
		return
	_shader_cliff_rim_visual.call("clear")
	for chunk_coord_value: Variant in _loaded_chunks:
		var chunk_coord: Vector2i = chunk_coord_value
		_shader_cliff_rim_visual.call("update_chunk", chunk_coord, _build_shader_elevations_for_chunk(chunk_coord), _get_shader_loaded_cells_for_chunk(chunk_coord))
	_update_shader_cliff_rim_bounds()

func _refresh_shader_cliff_rim_chunk(chunk_coord: Vector2i) -> Dictionary:
	if _shader_cliff_rim_visual == null or not is_instance_valid(_shader_cliff_rim_visual):
		return {}
	var texture_start_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
	if not _loaded_chunks.has(chunk_coord):
		_shader_cliff_rim_visual.call("remove_chunk", chunk_coord)
	else:
		_shader_cliff_rim_visual.call("update_chunk", chunk_coord, _build_shader_elevations_for_chunk(chunk_coord), _get_shader_loaded_cells_for_chunk(chunk_coord))
	var texture_end_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
	_update_shader_cliff_rim_bounds()
	var overlay_end_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
	return {
		"texture_usec": texture_end_usec - texture_start_usec,
		"overlay_usec": overlay_end_usec - texture_end_usec,
	}

func _refresh_shader_cliff_rim_cell(cell: Vector2i) -> void:
	if _shader_cliff_rim_visual == null or not is_instance_valid(_shader_cliff_rim_visual) or not is_cell_loaded(cell):
		return
	_shader_cliff_rim_visual.call("update_cell", _cell_to_chunk(cell), cell, get_cell_elevation(cell))

func _build_shader_elevations_for_chunk(chunk_coord: Vector2i) -> Dictionary:
	## Include the four-neighbour sampling halo so streamed edges do not decode as elevation zero.
	var elevations_by_cell: Dictionary = {}
	if not _loaded_chunks.has(chunk_coord):
		return elevations_by_cell
	var origin: Vector2i = chunk_coord * WorldGenerator.CHUNK_SIZE
	for y in range(origin.y - 1, origin.y + WorldGenerator.CHUNK_SIZE + 1):
		for x in range(origin.x - 1, origin.x + WorldGenerator.CHUNK_SIZE + 1):
			var cell := Vector2i(x, y)
			elevations_by_cell[cell] = _get_effective_elevation_for_rim(cell)
	return elevations_by_cell

func _get_shader_loaded_cells_for_chunk(chunk_coord: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not _loaded_chunks.has(chunk_coord):
		return cells
	for cell_value: Variant in (_loaded_chunks[chunk_coord].get("tile_lookup", {}) as Dictionary).keys():
		cells.append(cell_value as Vector2i)
	return cells

func _refresh_shader_halos_after_unload(unloaded_chunks: Array[Vector2i]) -> void:
	var affected_loaded_chunks: Dictionary = {}
	for unloaded_chunk: Vector2i in unloaded_chunks:
		for y_offset in range(-1, 2):
			for x_offset in range(-1, 2):
				if x_offset == 0 and y_offset == 0:
					continue
				var neighbour_chunk: Vector2i = unloaded_chunk + Vector2i(x_offset, y_offset)
				if _loaded_chunks.has(neighbour_chunk):
					affected_loaded_chunks[neighbour_chunk] = true
	for chunk_coord_value: Variant in affected_loaded_chunks.keys():
		var chunk_coord: Vector2i = chunk_coord_value
		_shader_cliff_rim_visual.call("update_chunk", chunk_coord, _build_shader_elevations_for_chunk(chunk_coord), _get_shader_loaded_cells_for_chunk(chunk_coord))

func _update_shader_cliff_rim_bounds() -> void:
	if _shader_cliff_rim_visual == null or not is_instance_valid(_shader_cliff_rim_visual) or _loaded_chunks.is_empty():
		return
	var min_chunk := Vector2i(2147483647, 2147483647)
	var max_chunk := Vector2i(-2147483648, -2147483648)
	for chunk_coord_value: Variant in _loaded_chunks:
		var chunk_coord: Vector2i = chunk_coord_value
		min_chunk.x = mini(min_chunk.x, chunk_coord.x)
		min_chunk.y = mini(min_chunk.y, chunk_coord.y)
		max_chunk.x = maxi(max_chunk.x, chunk_coord.x)
		max_chunk.y = maxi(max_chunk.y, chunk_coord.y)
	var min_cell: Vector2i = min_chunk * WorldGenerator.CHUNK_SIZE
	var max_cell: Vector2i = (max_chunk + Vector2i.ONE) * WorldGenerator.CHUNK_SIZE - Vector2i.ONE
	var corner_cells: Array[Vector2i] = [
		min_cell,
		Vector2i(max_cell.x, min_cell.y),
		max_cell,
		Vector2i(min_cell.x, max_cell.y),
	]
	var world_min := Vector2(INF, INF)
	var world_max := Vector2(-INF, -INF)
	for corner_cell: Vector2i in corner_cells:
		var world_position: Vector2 = terrain_layer.map_to_local(corner_cell)
		world_min.x = minf(world_min.x, world_position.x)
		world_min.y = minf(world_min.y, world_position.y)
		world_max.x = maxf(world_max.x, world_position.x)
		world_max.y = maxf(world_max.y, world_position.y)
	var world_rect := Rect2(world_min, world_max - world_min).grow(64.0)
	_shader_cliff_rim_visual.call("set_overlay_bounds", world_rect, min_cell, max_cell)

func _refresh_cliff_edge_rims_for_loaded_chunk(chunk_coord: Vector2i) -> void:
	## Build the new chunk in full, then touch only adjacent strips in existing neighbours.
	if not enable_cliff_face_overlay:
		_remove_cliff_face_mesh_renderer(chunk_coord)
		return
	if _chunk_boundary_mesh_root == null or not is_instance_valid(_chunk_boundary_mesh_root):
		return
	if not _loaded_chunks.has(chunk_coord):
		_remove_cliff_face_mesh_renderer(chunk_coord)
		return
	_configure_chunk_boundary_mesh_renderer(chunk_coord, _build_cliff_edge_rim_segments_for_chunk(chunk_coord))
	var neighbour_boundary_cells: Array[Vector2i] = []
	for neighbour_offset_value: Variant in CLIFF_RIM_NEIGHBOURS.values():
		var neighbour_offset: Vector2i = neighbour_offset_value
		var neighbour_chunk: Vector2i = chunk_coord + neighbour_offset
		if not _loaded_chunks.has(neighbour_chunk):
			continue
		neighbour_boundary_cells.append_array(_get_chunk_boundary_cells(neighbour_chunk, -neighbour_offset))
	_refresh_cliff_edge_rim_cells(neighbour_boundary_cells)

func _refresh_cliff_edge_rims_for_unloaded_chunks(chunk_coords: Array[Vector2i]) -> void:
	if not enable_cliff_face_overlay:
		for chunk_coord: Vector2i in chunk_coords:
			_remove_cliff_face_mesh_renderer(chunk_coord)
		return
	if _chunk_boundary_mesh_root == null or not is_instance_valid(_chunk_boundary_mesh_root):
		return
	var neighbour_boundary_cells: Array[Vector2i] = []
	for chunk_coord: Vector2i in chunk_coords:
		_remove_cliff_face_mesh_renderer(chunk_coord)
		for neighbour_offset_value: Variant in CLIFF_RIM_NEIGHBOURS.values():
			var neighbour_offset: Vector2i = neighbour_offset_value
			var neighbour_chunk: Vector2i = chunk_coord + neighbour_offset
			if not _loaded_chunks.has(neighbour_chunk):
				continue
			neighbour_boundary_cells.append_array(_get_chunk_boundary_cells(neighbour_chunk, -neighbour_offset))
	_refresh_cliff_edge_rim_cells(neighbour_boundary_cells)

func _refresh_cliff_edge_rim_cells(cells: Array[Vector2i]) -> void:
	## Cell ownership makes replacement idempotent and prevents overlapping duplicate segments.
	if not enable_cliff_face_overlay:
		return
	if _chunk_boundary_mesh_root == null or not is_instance_valid(_chunk_boundary_mesh_root):
		return
	var unique_cells: Dictionary = {}
	for cell: Vector2i in cells:
		if is_cell_loaded(cell):
			unique_cells[cell] = true
	var cells_by_chunk: Dictionary = {}
	for cell_value: Variant in unique_cells:
		var cell: Vector2i = cell_value
		var chunk_coord: Vector2i = _cell_to_chunk(cell)
		if not cells_by_chunk.has(chunk_coord):
			cells_by_chunk[chunk_coord] = []
		(cells_by_chunk[chunk_coord] as Array).append(cell)
	for chunk_coord_value: Variant in cells_by_chunk:
		var chunk_coord: Vector2i = chunk_coord_value
		var chunk_cells: Array[Vector2i] = []
		chunk_cells.assign(cells_by_chunk[chunk_coord])
		_configure_chunk_boundary_mesh_renderer_cells(chunk_coord, _build_cliff_edge_rim_segments_for_cells(chunk_cells))

func _configure_chunk_boundary_mesh_renderer(chunk_coord: Vector2i, segments_by_cell: Dictionary) -> void:
	if _chunk_boundary_mesh_root == null or not is_instance_valid(_chunk_boundary_mesh_root):
		return
	var renderer: ChunkBoundaryMeshRenderer = _get_or_create_chunk_boundary_mesh_renderer(chunk_coord)
	renderer.configure(chunk_coord, segments_by_cell, cliff_rim_color, cliff_rim_alpha, cliff_rim_width, cliff_rim_vertical_offset)

func _configure_chunk_boundary_mesh_renderer_cells(chunk_coord: Vector2i, segments_by_cell: Dictionary) -> void:
	if _chunk_boundary_mesh_root == null or not is_instance_valid(_chunk_boundary_mesh_root):
		return
	var renderer: ChunkBoundaryMeshRenderer = _get_or_create_chunk_boundary_mesh_renderer(chunk_coord)
	renderer.configure_cells(segments_by_cell, cliff_rim_color, cliff_rim_alpha, cliff_rim_width, cliff_rim_vertical_offset)

func _get_or_create_chunk_boundary_mesh_renderer(chunk_coord: Vector2i) -> ChunkBoundaryMeshRenderer:
	if _chunk_boundary_mesh_renderers.has(chunk_coord):
		var existing: ChunkBoundaryMeshRenderer = _chunk_boundary_mesh_renderers[chunk_coord] as ChunkBoundaryMeshRenderer
		if existing != null and is_instance_valid(existing):
			return existing
	var renderer: ChunkBoundaryMeshRenderer = ChunkBoundaryMeshRendererScript.new() as ChunkBoundaryMeshRenderer
	renderer.name = "ChunkBoundaryMesh_%d_%d" % [chunk_coord.x, chunk_coord.y]
	_chunk_boundary_mesh_renderers[chunk_coord] = renderer
	_chunk_boundary_mesh_root.add_child(renderer)
	return renderer

func _remove_cliff_face_mesh_renderer(chunk_coord: Vector2i) -> void:
	if not _chunk_boundary_mesh_renderers.has(chunk_coord):
		return
	var renderer: Node = _chunk_boundary_mesh_renderers[chunk_coord] as Node
	_chunk_boundary_mesh_renderers.erase(chunk_coord)
	if renderer == null or not is_instance_valid(renderer):
		return
	renderer.queue_free()

func _clear_cliff_face_mesh_renderers() -> void:
	for renderer_value: Variant in _chunk_boundary_mesh_renderers.values():
		var renderer: Node = renderer_value as Node
		if renderer != null and is_instance_valid(renderer):
			renderer.queue_free()
	_chunk_boundary_mesh_renderers.clear()

func _build_cliff_edge_rim_segments_for_chunk(chunk_coord: Vector2i) -> Dictionary:
	if not _loaded_chunks.has(chunk_coord):
		return {}
	var tile_lookup: Dictionary = _loaded_chunks[chunk_coord].get("tile_lookup", {})
	var cells: Array[Vector2i] = []
	for cell_value: Variant in tile_lookup:
		cells.append(cell_value as Vector2i)
	return _build_cliff_edge_rim_segments_for_cells(cells)

func _build_cliff_edge_rim_segments_for_cells(cells: Array[Vector2i]) -> Dictionary:
	var segments_by_cell: Dictionary = {}
	for cell: Vector2i in cells:
		if not is_cell_loaded(cell):
			continue
		var elevation: int = _get_effective_elevation_for_rim(cell)
		var top_center: Vector2 = CellRenderInfoRef.get_visible_top_center(terrain_layer.map_to_local(cell), elevation)
		var segments_by_direction: Dictionary = {}
		for direction_name: String in CLIFF_RIM_NEIGHBOURS:
			if not _is_cliff_rim_direction_visible(direction_name):
				continue
			var neighbour_offset: Vector2i = CLIFF_RIM_NEIGHBOURS[direction_name]
			var neighbour_elevation: int = _get_effective_elevation_for_rim(cell + neighbour_offset)
			if elevation <= neighbour_elevation:
				continue
			segments_by_direction[direction_name] = _build_cliff_face_polygon(top_center, direction_name, elevation - neighbour_elevation)
		segments_by_cell[cell] = segments_by_direction
	return segments_by_cell

func _is_cliff_rim_direction_visible(direction_name: String) -> bool:
	## Conservative fixed-camera helper: filled faces are only readable on the
	## front-facing isometric edges. North/west drops need real cliff assets
	## before they can be drawn without false wall bands.
	return bool(CLIFF_RIM_VISIBLE_DIRECTIONS.get(direction_name, false))

func _get_effective_elevation_for_rim(cell: Vector2i) -> int:
	var chunk_coord: Vector2i = _cell_to_chunk(cell)
	if _loaded_chunks.has(chunk_coord):
		var tile_lookup: Dictionary = _loaded_chunks[chunk_coord].get("tile_lookup", {})
		if tile_lookup.has(cell):
			return int((tile_lookup[cell] as Dictionary).get("elevation", 0))
	var active_interior: Dictionary = _get_interior_for_world_space(_active_world_space_id)
	if not active_interior.is_empty():
		return int(InteriorTerrainSourceRef.get_tile_info(active_interior, cell).get("elevation", 0))
	var mined_tile_info: Dictionary = _build_mined_terrain_tile_info(cell, SURFACE_WORLD_SPACE_ID)
	if not mined_tile_info.is_empty():
		return int(mined_tile_info.get("elevation", 0))
	return int(_manual_tile_overrides.get(cell, _world_generator.get_tile_info(cell)).get("elevation", 0))

func _get_chunk_boundary_cells(chunk_coord: Vector2i, boundary_direction: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var origin: Vector2i = chunk_coord * WorldGenerator.CHUNK_SIZE
	if boundary_direction == Vector2i.UP or boundary_direction == Vector2i.DOWN:
		var y: int = origin.y if boundary_direction == Vector2i.UP else origin.y + WorldGenerator.CHUNK_SIZE - 1
		for x_offset in range(WorldGenerator.CHUNK_SIZE):
			cells.append(Vector2i(origin.x + x_offset, y))
	else:
		var x: int = origin.x if boundary_direction == Vector2i.LEFT else origin.x + WorldGenerator.CHUNK_SIZE - 1
		for y_offset in range(WorldGenerator.CHUNK_SIZE):
			cells.append(Vector2i(x, origin.y + y_offset))
	return cells

func _build_cliff_rim_segment(top_center: Vector2, direction_name: String) -> PackedVector2Array:
	var half_size: Vector2 = CellRenderInfoRef.TOP_DIAMOND_HALF_SIZE
	var top := top_center + Vector2(0.0, -half_size.y)
	var right := top_center + Vector2(half_size.x, 0.0)
	var bottom := top_center + Vector2(0.0, half_size.y)
	var left := top_center + Vector2(-half_size.x, 0.0)
	match direction_name:
		"north":
			## Preserve the original north/back-facing top-to-right rim.
			return PackedVector2Array([top, right])
		"east":
			return PackedVector2Array([right, bottom])
		"south":
			return PackedVector2Array([bottom, left])
		"west":
			return PackedVector2Array([left, top])
	push_error("Unsupported cliff rim direction: %s" % direction_name)
	return PackedVector2Array()

func _build_cliff_face_polygon(top_center: Vector2, direction_name: String, elevation_delta: int) -> PackedVector2Array:
	## Presentation-only vertical face: the top edge is taken from the raised cell,
	## and the lower edge is projected down by the exact elevation delta.
	var top_edge: PackedVector2Array = _build_cliff_rim_segment(top_center, direction_name)
	if top_edge.size() != 2:
		return PackedVector2Array()
	var face_drop: Vector2 = -CellRenderInfoRef.BLOCK_LAYER_OFFSET * maxi(elevation_delta, 1)
	return PackedVector2Array([
		top_edge[0],
		top_edge[1],
		top_edge[1] + face_drop,
		top_edge[0] + face_drop,
	])

func _refresh_terrain_visuals_near_cell(cell: Vector2i) -> void:
	var chunk_coord: Vector2i = _cell_to_chunk(cell)
	if _loaded_chunks.has(chunk_coord):
		_refresh_elevation_stack_visual_chunks([chunk_coord])
		_refresh_terrain_variant_tiles_near_cell(cell)
		if shader_cliff_rims_enabled:
			_refresh_shader_cliff_rim_cell(cell)
		else:
			var affected_cells: Array[Vector2i] = [cell]
			for neighbour_offset_value: Variant in CLIFF_RIM_NEIGHBOURS.values():
				affected_cells.append(cell + (neighbour_offset_value as Vector2i))
			_refresh_cliff_edge_rim_cells(affected_cells)

func _remove_debug_elevation_markers_for_chunk(chunk_coord: Vector2i) -> void:
	if _debug_elevation_preview != null and is_instance_valid(_debug_elevation_preview) and _cell_to_chunk(_debug_elevation_preview.get_meta("cell", Vector2i.ZERO)) == chunk_coord:
		clear_debug_elevation_preview()
	for node: Node in _debug_elevation_markers_by_chunk.get(chunk_coord, []):
		if not is_instance_valid(node):
			continue
		if node.get_parent() == debug_elevation_root:
			debug_elevation_root.remove_child(node)
		node.queue_free()
	_debug_elevation_markers_by_chunk.erase(chunk_coord)

func _spawn_construction_visuals_for_chunk(chunk_coord: Vector2i) -> void:
	if _world_state == null or not _loaded_chunks.has(chunk_coord):
		return
	for site: Dictionary in _world_state.get_construction_sites(_active_world_space_id):
		var origin_cell: Vector2i = site.get("origin_cell", Vector2i.ZERO)
		if _cell_to_chunk(origin_cell) == chunk_coord:
			_spawn_construction_visual(site, chunk_coord)

func _spawn_stockpile_zone_visuals_for_chunk(chunk_coord: Vector2i) -> void:
	if _world_state == null or not _loaded_chunks.has(chunk_coord):
		return
	for zone: Dictionary in _world_state.get_stockpile_zones(_active_world_space_id):
		if not bool(zone.get("enabled", true)):
			continue
		for cell: Vector2i in zone.get("cells", []):
			if _cell_to_chunk(cell) == chunk_coord:
				_spawn_stockpile_zone_visual(String(zone.get("zone_id", "")), cell, chunk_coord)

func _spawn_stockpile_zone_visual(zone_id: String, cell: Vector2i, chunk_coord: Vector2i) -> void:
	if not _loaded_chunks.has(chunk_coord):
		return
	for existing: Node in _loaded_chunks[chunk_coord].get("stockpile_zone_nodes", []):
		if is_instance_valid(existing) and String(existing.get_meta("zone_id", "")) == zone_id and existing.get_meta("cell", Vector2i.ZERO) == cell:
			return
	var visual: Node2D = StockpileZoneVisualScript.new() as Node2D
	visual.name = "StockpileZone_%s_%d_%d" % [zone_id, cell.x, cell.y]
	visual.set_meta("zone_id", zone_id)
	visual.set_meta("cell", cell)
	var x_step: Vector2 = terrain_layer.map_to_local(cell + Vector2i.RIGHT) - terrain_layer.map_to_local(cell)
	var y_step: Vector2 = terrain_layer.map_to_local(cell + Vector2i.DOWN) - terrain_layer.map_to_local(cell)
	visual.configure(x_step, y_step)
	stockpile_zone_root.add_child(visual)
	visual.global_position = get_cell_visual_world_position(cell)
	_loaded_chunks[chunk_coord]["stockpile_zone_nodes"].append(visual)

func _on_stockpile_zone_added(zone: Dictionary) -> void:
	if not bool(zone.get("enabled", true)) or String(zone.get("world_space_id", SURFACE_WORLD_SPACE_ID)) != _active_world_space_id:
		return
	var zone_id: String = String(zone.get("zone_id", ""))
	for cell: Vector2i in zone.get("cells", []):
		var chunk_coord: Vector2i = _cell_to_chunk(cell)
		if _loaded_chunks.has(chunk_coord):
			_spawn_stockpile_zone_visual(zone_id, cell, chunk_coord)

func _on_stockpile_zone_removed(zone_id: String) -> void:
	for chunk_coord_value: Variant in _loaded_chunks.keys():
		_remove_stockpile_zone_visuals_from_chunk(chunk_coord_value, zone_id)

func _on_stockpile_zones_replaced() -> void:
	for chunk_coord_value: Variant in _loaded_chunks.keys():
		var chunk_coord: Vector2i = chunk_coord_value
		_remove_stockpile_zone_visuals_from_chunk(chunk_coord)
		_spawn_stockpile_zone_visuals_for_chunk(chunk_coord)

func _remove_stockpile_zone_visuals_from_chunk(chunk_coord: Vector2i, zone_id: String = "") -> void:
	if not _loaded_chunks.has(chunk_coord):
		return
	var nodes: Array = _loaded_chunks[chunk_coord].get("stockpile_zone_nodes", [])
	for index in range(nodes.size() - 1, -1, -1):
		var node: Node = nodes[index]
		if not zone_id.is_empty() and is_instance_valid(node) and String(node.get_meta("zone_id", "")) != zone_id:
			continue
		nodes.remove_at(index)
		if is_instance_valid(node):
			node.queue_free()
	_loaded_chunks[chunk_coord]["stockpile_zone_nodes"] = nodes

func _spawn_ground_item_visuals_for_chunk(chunk_coord: Vector2i) -> void:
	if _world_state == null or not _loaded_chunks.has(chunk_coord):
		return
	for item: Dictionary in _world_state.get_ground_items(_active_world_space_id):
		if bool(item.get("enabled", true)) and _cell_to_chunk(item.get("cell", Vector2i.ZERO)) == chunk_coord:
			_spawn_ground_item_visual(item, chunk_coord)

func _spawn_ground_item_visual(item: Dictionary, chunk_coord: Vector2i) -> void:
	if not _loaded_chunks.has(chunk_coord):
		return
	var item_id: String = String(item.get("item_id", ""))
	for existing: Node in _loaded_chunks[chunk_coord].get("ground_item_nodes", []):
		if is_instance_valid(existing) and String(existing.get_meta("item_id", "")) == item_id:
			return
	var visual: Node2D = GroundItemVisualScript.new() as Node2D
	var cell: Vector2i = item.get("cell", Vector2i.ZERO)
	visual.name = "GroundItem_%s" % item_id
	visual.set_meta("item_id", item_id)
	visual.call("configure", String(item.get("resource_type", "")), int(item.get("amount", 0)), show_ground_item_amount_labels_debug)
	ground_item_root.add_child(visual)
	visual.global_position = get_cell_visual_world_position(cell)
	_loaded_chunks[chunk_coord]["ground_item_nodes"].append(visual)

func _on_ground_item_added(item: Dictionary) -> void:
	if not bool(item.get("enabled", true)) or String(item.get("world_space_id", SURFACE_WORLD_SPACE_ID)) != _active_world_space_id:
		return
	var chunk_coord: Vector2i = _cell_to_chunk(item.get("cell", Vector2i.ZERO))
	if _loaded_chunks.has(chunk_coord):
		_spawn_ground_item_visual(item, chunk_coord)

func _on_ground_item_removed(item_id: String) -> void:
	for chunk_coord_value: Variant in _loaded_chunks.keys():
		_remove_ground_item_visuals_from_chunk(chunk_coord_value, item_id)

func _on_ground_items_replaced() -> void:
	for chunk_coord_value: Variant in _loaded_chunks.keys():
		var chunk_coord: Vector2i = chunk_coord_value
		_remove_ground_item_visuals_from_chunk(chunk_coord)
		_spawn_ground_item_visuals_for_chunk(chunk_coord)

func _remove_ground_item_visuals_from_chunk(chunk_coord: Vector2i, item_id: String = "") -> void:
	if not _loaded_chunks.has(chunk_coord):
		return
	var nodes: Array = _loaded_chunks[chunk_coord].get("ground_item_nodes", [])
	for index in range(nodes.size() - 1, -1, -1):
		var node: Node = nodes[index]
		if not item_id.is_empty() and is_instance_valid(node) and String(node.get_meta("item_id", "")) != item_id:
			continue
		nodes.remove_at(index)
		if is_instance_valid(node):
			node.queue_free()
	_loaded_chunks[chunk_coord]["ground_item_nodes"] = nodes

func _spawn_construction_visual(site: Dictionary, chunk_coord: Vector2i) -> void:
	if not _loaded_chunks.has(chunk_coord):
		return
	var visual: Node2D = ConstructionSiteVisualScript.new()
	var completed: bool = bool(site.get("completed", false))
	var building_id: String = String(site.get("building_id", "building"))
	visual.name = "%s_%s_%s" % ["Completed" if completed else "ConstructionSite", building_id.capitalize(), String(site.get("site_id", "unknown"))]
	visual.set_meta("site_id", String(site.get("site_id", "")))
	_configure_construction_visual(visual, site)
	construction_root.add_child(visual)
	visual.global_position = get_cell_visual_world_position(site.get("origin_cell", Vector2i.ZERO))
	_loaded_chunks[chunk_coord]["construction_nodes"].append(visual)

func _on_construction_site_added(site: Dictionary) -> void:
	if String(site.get("world_space_id", SURFACE_WORLD_SPACE_ID)) != _active_world_space_id:
		return
	var origin_cell: Vector2i = site.get("origin_cell", Vector2i.ZERO)
	var chunk_coord: Vector2i = _cell_to_chunk(origin_cell)
	if _loaded_chunks.has(chunk_coord):
		_spawn_construction_visual(site, chunk_coord)

func _on_construction_site_changed(site: Dictionary) -> void:
	if String(site.get("world_space_id", SURFACE_WORLD_SPACE_ID)) != _active_world_space_id:
		return
	var origin_cell: Vector2i = site.get("origin_cell", Vector2i.ZERO)
	var chunk_coord: Vector2i = _cell_to_chunk(origin_cell)
	if not _loaded_chunks.has(chunk_coord):
		return
	var site_id: String = String(site.get("site_id", ""))
	for node: Node in _loaded_chunks[chunk_coord].get("construction_nodes", []):
		if is_instance_valid(node) and String(node.get_meta("site_id", "")) == site_id:
			var completed: bool = bool(site.get("completed", false))
			var building_id: String = String(site.get("building_id", "building"))
			node.name = "%s_%s_%s" % ["Completed" if completed else "ConstructionSite", building_id.capitalize(), site_id]
			_configure_construction_visual(node, site)
			return
	_spawn_construction_visual(site, chunk_coord)

func _on_construction_site_cancelled(site_id: String, site: Dictionary) -> void:
	if String(site.get("world_space_id", SURFACE_WORLD_SPACE_ID)) != _active_world_space_id:
		return
	var origin_cell: Vector2i = site.get("origin_cell", Vector2i.ZERO)
	var chunk_coord: Vector2i = _cell_to_chunk(origin_cell)
	if not _loaded_chunks.has(chunk_coord):
		return
	var construction_nodes: Array = _loaded_chunks[chunk_coord].get("construction_nodes", [])
	for index in range(construction_nodes.size() - 1, -1, -1):
		var node: Node = construction_nodes[index]
		if not is_instance_valid(node) or String(node.get_meta("site_id", "")) != site_id:
			continue
		construction_nodes.remove_at(index)
		if node.get_parent() == construction_root:
			construction_root.remove_child(node)
		node.queue_free()
	_loaded_chunks[chunk_coord]["construction_nodes"] = construction_nodes

func _configure_construction_visual(visual: Node, site: Dictionary) -> void:
	var completed: bool = bool(site.get("completed", false))
	var definition: Dictionary = BuildingDefinitionRef.get_definition(String(site.get("building_id", "")))
	var building_id: String = String(site.get("building_id", ""))
	var footprint: Vector2i = definition.get("footprint", Vector2i.ONE)
	var light_radius: float = float(definition.get("light_radius", 0.0)) if completed else 0.0
	var warmth_radius: float = float(definition.get("warmth_radius", 0.0)) if completed else 0.0
	var shelter_radius: float = float(definition.get("shelter_radius", 0.0)) if completed else 0.0
	var shelter_capacity: int = int(definition.get("shelter_capacity", 0)) if completed else 0
	var show_light_glow: bool = draw_building_effect_radii_debug and completed and _world_state != null and _world_state.is_night()
	var visual_metadata: Dictionary = BuildingDefinitionRef.get_visual_metadata(building_id)
	visual.configure_building_site(
		building_id,
		completed,
		footprint,
		light_radius,
		warmth_radius,
		shelter_radius,
		shelter_capacity,
		show_light_glow,
		String(visual_metadata.get("construction_visual_id", "generic_scaffold")),
		String(visual_metadata.get("completed_visual_id", "generic_placeholder")),
		String(visual_metadata.get("construction_scene_path", "")),
		String(visual_metadata.get("completed_scene_path", "")),
		visual_metadata.get("placeholder_palette", {}),
		draw_building_effect_radii_debug
	)

func _on_building_effect_day_phase_changed(_is_daytime: bool) -> void:
	_day_phase_signal_count += 1
	_queue_lighting_projection_refresh()
	if draw_building_effect_radii_debug:
		_refresh_construction_effect_visuals()


func _refresh_construction_effect_visuals() -> void:
	if _world_state == null:
		return
	for chunk_coord: Variant in _loaded_chunks.keys():
		var chunk_key: Vector2i = chunk_coord
		for node: Node in _loaded_chunks[chunk_key].get("construction_nodes", []):
			if not is_instance_valid(node):
				continue
			var site: Dictionary = _world_state.get_construction_site(String(node.get_meta("site_id", "")))
			if not site.is_empty():
				_configure_construction_visual(node, site)

func _on_lighting_changed(world_space_id: String) -> void:
	if world_space_id == _active_world_space_id:
		_lighting_signal_count += 1
		if draw_per_cell_light_debug or draw_light_source_glows_experimental:
			_queue_lighting_projection_refresh()


func _queue_lighting_projection_refresh() -> void:
	## Signals can arrive in bursts during construction/import; presentation needs only the final authoritative state.
	if _lighting_refresh_queued:
		return
	_lighting_refresh_queued = true
	call_deferred("_refresh_queued_lighting_projection")


func _refresh_queued_lighting_projection() -> void:
	_lighting_refresh_queued = false
	_refresh_lighting_projection()

func _refresh_lighting_projection() -> void:
	if _lighting_overlay == null or not is_instance_valid(_lighting_overlay):
		return
	var loaded_cell_bounds := _get_active_loaded_cell_bounds()
	var debug_cells: Array[Vector2i] = []
	if draw_per_cell_light_debug:
		debug_cells.assign(_get_active_loaded_cells())
	_lighting_overlay.call("configure", terrain_layer, _world_state, _active_world_space_id, loaded_cell_bounds, debug_cells, draw_per_cell_light_debug, draw_light_source_glows_experimental, lighting_profile_debug, get_cell_visual_world_position)


func _get_active_loaded_cell_bounds() -> Rect2i:
	## Normal ambient rendering only needs the loaded rectangle, not a cell-sized light field.
	var has_bounds := false
	var minimum := Vector2i.ZERO
	var maximum := Vector2i.ZERO
	var chunk_size := Vector2i(WorldGenerator.CHUNK_SIZE, WorldGenerator.CHUNK_SIZE)
	for chunk_coord_value: Variant in _loaded_chunks.keys():
		var chunk_coord: Vector2i = chunk_coord_value
		var chunk_data: Dictionary = _loaded_chunks[chunk_coord]
		if String(chunk_data.get("world_space_id", "")) != _active_world_space_id:
			continue
		var origin := chunk_coord * WorldGenerator.CHUNK_SIZE
		var chunk_end := origin + chunk_size
		if not has_bounds:
			minimum = origin
			maximum = chunk_end
			has_bounds = true
			continue
		minimum = Vector2i(mini(minimum.x, origin.x), mini(minimum.y, origin.y))
		maximum = Vector2i(maxi(maximum.x, chunk_end.x), maxi(maximum.y, chunk_end.y))
	return Rect2i(minimum, maximum - minimum) if has_bounds else Rect2i()


func _get_active_loaded_cells() -> Array[Vector2i]:
	## Per-cell collection remains isolated to the explicit diagnostic path.
	var cells: Array[Vector2i] = []
	for chunk_data_value: Variant in _loaded_chunks.values():
		var chunk_data: Dictionary = chunk_data_value
		if String(chunk_data.get("world_space_id", "")) != _active_world_space_id:
			continue
		for cell_value: Variant in (chunk_data.get("tile_lookup", {}) as Dictionary).keys():
			cells.append(cell_value as Vector2i)
	cells.sort_custom(func(first: Vector2i, second: Vector2i) -> bool:
		return first.x < second.x if first.x != second.x else first.y < second.y
	)
	return cells


func _get_visible_ground_item_label_count() -> int:
	var count := 0
	for chunk_data_value: Variant in _loaded_chunks.values():
		var chunk_data: Dictionary = chunk_data_value
		for node: Node in chunk_data.get("ground_item_nodes", []):
			if is_instance_valid(node) and node.has_method("is_amount_label_visible") and bool(node.call("is_amount_label_visible")):
				count += 1
	return count


func _report_lighting_profile(frame_delta: float) -> void:
	if not lighting_profile_debug or _lighting_overlay == null:
		return
	_lighting_profile_elapsed += maxf(frame_delta, 0.0)
	if _lighting_profile_elapsed < lighting_profile_summary_interval:
		return
	var stats: Dictionary = _lighting_overlay.call("consume_profile_stats") as Dictionary
	var ground_item_labels := _get_visible_ground_item_label_count()
	var colonist_needs_labels := _colonist_manager.get_visible_needs_label_count() if _colonist_manager != null else 0
	print("LIGHTING_PROFILE seconds=%.2f day_phase_signals=%d lighting_signals=%d redraws=%d rebuilds=%d rebuild_ms=%.3f draws=%d draw_ms=%.3f draw_calls=%d polygons=%d circles=%d cells_drawn=%d light_queries=%d ground_item_labels=%d colonist_needs_labels=%d" % [_lighting_profile_elapsed, _day_phase_signal_count, _lighting_signal_count, int(stats.get("redraw_count", 0)), int(stats.get("rebuild_count", 0)), float(stats.get("rebuild_ms", 0.0)), int(stats.get("draw_count", 0)), float(stats.get("draw_ms", 0.0)), int(stats.get("draw_calls", 0)), int(stats.get("polygons", 0)), int(stats.get("circles", 0)), int(stats.get("cells_drawn", 0)), int(stats.get("light_queries", 0)), ground_item_labels, colonist_needs_labels])
	_lighting_profile_elapsed = 0.0
	_lighting_signal_count = 0
	_day_phase_signal_count = 0

func _on_construction_sites_replaced() -> void:
	for chunk_coord: Variant in _loaded_chunks.keys():
		var chunk_key: Vector2i = chunk_coord
		for node: Node in _loaded_chunks[chunk_key].get("construction_nodes", []):
			if is_instance_valid(node):
				if node.get_parent() == construction_root:
					construction_root.remove_child(node)
				node.queue_free()
		_loaded_chunks[chunk_key]["construction_nodes"] = []
		_spawn_construction_visuals_for_chunk(chunk_key)

func _build_resource_node(spawn_data: Dictionary, chunk_coord: Vector2i, profile_timings: Dictionary = {}) -> ResourceNode:
	var scene: PackedScene = _select_resource_scene(spawn_data.scene)
	if scene == null:
		return null
	var instantiate_start_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
	var resource: ResourceNode = scene.instantiate() as ResourceNode
	var instantiate_end_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
	resource.resource_id = _build_resource_id(spawn_data)
	resource.cell = spawn_data.cell
	resource.elevation = get_cell_elevation(spawn_data.cell)
	resource.position = CellRenderInfoRef.get_visible_top_center(
		terrain_layer.map_to_local(spawn_data.cell),
		resource.elevation
	)
	resource.resource_type = spawn_data.resource_type
	resource.yield_amount = spawn_data.amount
	var base_config_end_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
	_configure_resource_visual(resource, spawn_data, chunk_coord)
	var visual_config_end_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
	if _world_state != null:
		resource.set_harvest_designated(_world_state.has_harvest_order_for_resource(resource.resource_id))
	resource.harvest_requested.connect(_on_resource_harvest_requested)
	resource.inspection_requested.connect(_on_resource_inspection_requested)
	resource.profile_ready_timing = chunk_profile_debug
	if chunk_profile_debug:
		var config_end_usec := Time.get_ticks_usec()
		profile_timings["instantiate_usec"] = instantiate_end_usec - instantiate_start_usec
		profile_timings["node_config_usec"] = (base_config_end_usec - instantiate_end_usec) + (config_end_usec - visual_config_end_usec)
		profile_timings["procedural_config_usec"] = visual_config_end_usec - base_config_end_usec
	return resource

func _process_pending_resource_spawns() -> void:
	if _pending_resource_spawns.is_empty():
		return
	var batch_start_usec: int = Time.get_ticks_usec()
	var profile_start_usec: int = batch_start_usec if chunk_profile_debug else 0
	var budget_usec: int = roundi(resource_spawn_time_budget_ms * 1000.0) if stage_resource_spawning else 0
	var processed_count: int = 0
	var dequeued_count: int = 0
	var instantiate_usec: int = 0
	var node_config_usec: int = 0
	var procedural_config_usec: int = 0
	var add_child_usec: int = 0
	var visual_refresh_usec: int = 0
	var ready_total_usec: int = 0
	var tracking_usec: int = 0
	var remaining: int = resource_spawns_per_frame if stage_resource_spawning else _pending_resource_spawns.size()
	while remaining > 0 and not _pending_resource_spawns.is_empty():
		# Check after at least one dequeue so stale jobs cannot block the queue and
		# a single resource whose cost exceeds the soft budget still makes progress.
		if stage_resource_spawning and processed_count > 0 and Time.get_ticks_usec() - batch_start_usec >= budget_usec:
			break
		var job: Dictionary = _pending_resource_spawns.pop_front()
		dequeued_count += 1
		var chunk_coord: Vector2i = job["chunk_coord"]
		if not _loaded_chunks.has(chunk_coord):
			remaining -= 1
			continue
		if _is_resource_depleted(job["spawn_data"]):
			remaining -= 1
			continue
		var resource_timings: Dictionary = {}
		var resource: ResourceNode = _build_resource_node(job["spawn_data"], chunk_coord, resource_timings)
		if resource != null:
			var add_child_start_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
			resource_root.add_child(resource)
			var add_child_end_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
			_loaded_chunks[chunk_coord]["resource_nodes"].append(resource)
			_track_resource_node(resource, chunk_coord)
			if chunk_profile_debug:
				var tracking_end_usec := Time.get_ticks_usec()
				instantiate_usec += int(resource_timings.get("instantiate_usec", 0))
				node_config_usec += int(resource_timings.get("node_config_usec", 0))
				procedural_config_usec += int(resource_timings.get("procedural_config_usec", 0))
				add_child_usec += add_child_end_usec - add_child_start_usec
				visual_refresh_usec += resource.profile_visual_refresh_usec
				ready_total_usec += resource.profile_ready_total_usec
				tracking_usec += tracking_end_usec - add_child_end_usec
		processed_count += 1
		remaining -= 1
	if chunk_profile_debug:
		var profile_end_usec := Time.get_ticks_usec()
		var tree_collision_usec: int = maxi(add_child_usec - ready_total_usec, 0)
		_record_resource_spawn_profile({
			"instantiate": instantiate_usec,
			"node_config": node_config_usec,
			"procedural_config": procedural_config_usec,
			"add_child": add_child_usec,
			"visual_refresh": visual_refresh_usec,
			"tree_collision": tree_collision_usec,
			"tracking": tracking_usec,
			"total": profile_end_usec - profile_start_usec,
		}, processed_count)
		print(
			"RESOURCE_PROFILE count=%d dequeued=%d instantiate_ms=%.3f node_config_ms=%.3f procedural_config_ms=%.3f add_child_ms=%.3f visual_refresh_ms=%.3f tree_collision_ms=%.3f tracking_ms=%.3f total_ms=%.3f pending=%d" % [
				processed_count,
				dequeued_count,
				_usec_to_msec(instantiate_usec),
				_usec_to_msec(node_config_usec),
				_usec_to_msec(procedural_config_usec),
				_usec_to_msec(add_child_usec),
				_usec_to_msec(visual_refresh_usec),
				_usec_to_msec(tree_collision_usec),
				_usec_to_msec(tracking_usec),
				_usec_to_msec(profile_end_usec - profile_start_usec),
				_pending_resource_spawns.size(),
			]
		)

func _usec_to_msec(usec: int) -> float:
	return float(usec) / 1000.0

func _record_chunk_load_profile(stage_usecs: Dictionary) -> void:
	## Opt-in aggregate profiler for chunk-load hitch audits. It is intentionally
	## guarded by chunk_profile_debug so normal gameplay does not retain samples
	## or emit logs.
	_record_profile_stage_set(_chunk_profile_load_stats, stage_usecs, 1)
	var count: int = int(_chunk_profile_load_stats.get("_count", 0))
	if count > 0 and count % chunk_profile_summary_interval == 0:
		_print_profile_summary("CHUNK_PROFILE_SUMMARY", _chunk_profile_load_stats)

func _record_resource_spawn_profile(stage_usecs: Dictionary, processed_count: int) -> void:
	if processed_count <= 0:
		return
	_record_profile_stage_set(_chunk_profile_resource_stats, stage_usecs, processed_count)
	var count: int = int(_chunk_profile_resource_stats.get("_count", 0))
	if count > 0 and count % chunk_profile_summary_interval == 0:
		_print_profile_summary("RESOURCE_PROFILE_SUMMARY", _chunk_profile_resource_stats)

func _record_profile_stage_set(stats: Dictionary, stage_usecs: Dictionary, sample_count: int) -> void:
	stats["_count"] = int(stats.get("_count", 0)) + sample_count
	for stage_name_value: Variant in stage_usecs.keys():
		var stage_name: String = String(stage_name_value)
		var usec: int = int(stage_usecs[stage_name_value])
		var stage_stats: Dictionary = stats.get(stage_name, {"total_usec": 0, "max_usec": 0})
		stage_stats["total_usec"] = int(stage_stats.get("total_usec", 0)) + usec
		stage_stats["max_usec"] = maxi(int(stage_stats.get("max_usec", 0)), usec)
		stats[stage_name] = stage_stats

func _print_profile_summary(label: String, stats: Dictionary) -> void:
	var count: int = int(stats.get("_count", 0))
	if count <= 0:
		return
	var parts: Array[String] = [label, "samples=%d" % count]
	for stage_name_value: Variant in stats.keys():
		var stage_name: String = String(stage_name_value)
		if stage_name.begins_with("_"):
			continue
		var stage_stats: Dictionary = stats[stage_name_value]
		var average_usec: int = roundi(float(int(stage_stats.get("total_usec", 0))) / float(count))
		parts.append("%s_avg_ms=%.3f" % [stage_name, _usec_to_msec(average_usec)])
		parts.append("%s_max_ms=%.3f" % [stage_name, _usec_to_msec(int(stage_stats.get("max_usec", 0)))])
	print(" ".join(parts))

func get_streaming_lifecycle_debug_snapshot() -> Dictionary:
	## Bounded, read-only diagnostics. No samples or explored-chunk history are retained.
	var center_chunk: Vector2i = _get_camera_chunk()
	var loaded_cells: int = 0
	var resource_nodes: int = 0
	var stale_loaded_chunks: int = 0
	for chunk_coord_value: Variant in _loaded_chunks:
		var chunk_coord: Vector2i = chunk_coord_value
		var chunk_data: Dictionary = _loaded_chunks[chunk_coord]
		loaded_cells += (chunk_data.get("tile_lookup", {}) as Dictionary).size()
		resource_nodes += (chunk_data.get("resource_nodes", []) as Array).size()
		if maxi(abs(chunk_coord.x - center_chunk.x), abs(chunk_coord.y - center_chunk.y)) > load_radius + 1:
			stale_loaded_chunks += 1

	var stale_pending_chunks: int = 0
	for chunk_coord: Vector2i in _pending_chunks:
		if maxi(abs(chunk_coord.x - center_chunk.x), abs(chunk_coord.y - center_chunk.y)) > load_radius:
			stale_pending_chunks += 1
	var stale_resource_spawns: int = 0
	for entry: Dictionary in _pending_resource_spawns:
		if not _loaded_chunks.has(entry.get("chunk_coord", Vector2i.ZERO)):
			stale_resource_spawns += 1

	var elevation_chunks: Dictionary = _elevation_visual.get("_cells_by_chunk") if _elevation_visual != null else {}
	var elevation_cells: int = 0
	for offsets_value: Variant in elevation_chunks.values():
		for cells_value: Variant in (offsets_value as Dictionary).values():
			elevation_cells += (cells_value as Dictionary).size()
	var shader_chunks: Dictionary = _shader_cliff_rim_visual.get("_cells_by_chunk") if _shader_cliff_rim_visual != null else {}
	var shader_slots: Dictionary = _shader_cliff_rim_visual.get("_slot_owner") if _shader_cliff_rim_visual != null else {}
	var boundary_mesh_segments: int = 0
	var boundary_mesh_vertices: int = 0
	var boundary_mesh_draw_calls: int = 0
	for renderer_value: Variant in _chunk_boundary_mesh_renderers.values():
		var renderer: ChunkBoundaryMeshRenderer = renderer_value as ChunkBoundaryMeshRenderer
		if renderer == null or not is_instance_valid(renderer):
			continue
		boundary_mesh_segments += renderer.get_segment_count()
		boundary_mesh_vertices += renderer.get_vertex_count()
		boundary_mesh_draw_calls += renderer.get_draw_call_count()
	var stale_visual_chunks: int = _count_stale_cache_chunks(elevation_chunks) + _count_stale_cache_chunks(shader_chunks) + _count_stale_cache_chunks(_chunk_boundary_mesh_renderers)
	return {
		"loaded_chunks": _loaded_chunks.size(),
		"stale_loaded_chunks": stale_loaded_chunks,
		"loaded_cells": loaded_cells,
		"resource_nodes": resource_nodes,
		"resource_index": _resource_index.size(),
		"pending_chunks": _pending_chunks.size(),
		"queued_chunk_keys": _queued_chunk_keys.size(),
		"stale_pending_chunks": stale_pending_chunks,
		"pending_resource_spawns": _pending_resource_spawns.size(),
		"stale_resource_spawns": stale_resource_spawns,
		"procedural_cache": ProcSpriteCache.get_cache_size(),
		"elevation_chunks": elevation_chunks.size(),
		"elevation_cells": elevation_cells,
		"shader_chunks": shader_chunks.size(),
		"shader_slots": shader_slots.size(),
		"boundary_mesh_chunks": _chunk_boundary_mesh_renderers.size(),
		"boundary_mesh_segments": boundary_mesh_segments,
		"boundary_mesh_vertices": boundary_mesh_vertices,
		"boundary_mesh_draw_calls": boundary_mesh_draw_calls,
		"stale_visual_chunks": stale_visual_chunks,
		"manual_overrides": _manual_tile_overrides.size(),
		"depleted_resource_ids": _depleted_resource_ids.size(),
	}

func _count_stale_cache_chunks(cache: Dictionary) -> int:
	var stale: int = 0
	for chunk_coord: Variant in cache:
		if not _loaded_chunks.has(chunk_coord):
			stale += 1
	return stale

func get_harvest_resource_snapshot(resource_id: String) -> Dictionary:
	## Read-only integration point used by WorldState before designation or completion.
	if resource_id.is_empty():
		return _build_harvest_result(false, "empty_resource_id", resource_id, "", 0, Vector2i.ZERO)
	if is_resource_depleted(resource_id):
		return _build_harvest_result(false, "resource_depleted", resource_id, "", 0, Vector2i.ZERO)
	if not _resource_index.has(resource_id):
		return _build_harvest_result(false, "resource_not_loaded", resource_id, "", 0, Vector2i.ZERO)
	var entry: Dictionary = _resource_index[resource_id]
	var resource: ResourceNode = entry.get("node") as ResourceNode
	var chunk_coord: Vector2i = entry.get("chunk_coord", Vector2i.ZERO)
	if resource == null or not is_instance_valid(resource):
		return _build_harvest_result(false, "resource_node_invalid", resource_id, "", 0, Vector2i.ZERO)
	if not _loaded_chunks.has(chunk_coord):
		return _build_harvest_result(false, "chunk_not_loaded", resource_id, resource.resource_type, resource.yield_amount, resource.cell)
	var resource_nodes: Array = _loaded_chunks[chunk_coord].get("resource_nodes", [])
	if not resource_nodes.has(resource):
		return _build_harvest_result(false, "resource_not_tracked_in_chunk", resource_id, resource.resource_type, resource.yield_amount, resource.cell)
	if resource.resource_type.is_empty():
		return _build_harvest_result(false, "empty_resource_type", resource_id, resource.resource_type, resource.yield_amount, resource.cell)
	if resource.yield_amount <= 0:
		return _build_harvest_result(false, "invalid_yield_amount", resource_id, resource.resource_type, resource.yield_amount, resource.cell)
	return _build_harvest_result(true, "valid", resource_id, resource.resource_type, resource.yield_amount, resource.cell)

func get_loaded_resources_in_cell_rect(cell_rect: Rect2i) -> Array[Dictionary]:
	## Read-only projection for area tools. Returned records cannot mutate tracked ResourceNode state.
	var resources: Array[Dictionary] = []
	if cell_rect.size.x <= 0 or cell_rect.size.y <= 0:
		return resources
	for entry_value: Variant in _resource_index.values():
		var entry: Dictionary = entry_value
		var resource: ResourceNode = entry.get("node") as ResourceNode
		var chunk_coord: Vector2i = entry.get("chunk_coord", Vector2i.ZERO)
		if resource == null or not is_instance_valid(resource) or not _loaded_chunks.has(chunk_coord):
			continue
		var resource_nodes: Array = _loaded_chunks[chunk_coord].get("resource_nodes", [])
		if not resource_nodes.has(resource):
			continue
		if not cell_rect.has_point(resource.cell):
			continue
		resources.append({
			"resource_id": resource.resource_id,
			"cell": resource.cell,
			"resource_type": resource.resource_type,
			"yield_amount": resource.yield_amount,
		})
	resources.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return String(first.get("resource_id", "")) < String(second.get("resource_id", ""))
	)
	return resources

func _get_loaded_resource_snapshot_at_cell(cell: Vector2i, world_space_id: String) -> Dictionary:
	if world_space_id != SURFACE_WORLD_SPACE_ID:
		return {}
	for entry_value: Variant in _resource_index.values():
		var entry: Dictionary = entry_value
		var resource: ResourceNode = entry.get("node") as ResourceNode
		var chunk_coord: Vector2i = entry.get("chunk_coord", Vector2i.ZERO)
		if resource == null or not is_instance_valid(resource) or not _loaded_chunks.has(chunk_coord):
			continue
		if resource.cell != cell:
			continue
		var inspection: Dictionary = resource.get_inspection_data()
		inspection["resource_id"] = resource.resource_id
		return inspection
	return {}

func commit_harvest_resource(resource_id: String) -> Dictionary:
	## Called only by WorldState after all order and stockpile validation succeeds.
	var snapshot: Dictionary = get_harvest_resource_snapshot(resource_id)
	if not bool(snapshot.get("ok", false)):
		return snapshot
	var entry: Dictionary = _resource_index[resource_id]
	var resource: ResourceNode = entry.get("node") as ResourceNode
	var chunk_coord: Vector2i = entry.get("chunk_coord", Vector2i.ZERO)
	var resource_nodes: Array = _loaded_chunks[chunk_coord].get("resource_nodes", [])
	resource_nodes.erase(resource)
	_loaded_chunks[chunk_coord]["resource_nodes"] = resource_nodes
	_resource_index.erase(resource_id)
	_depleted_resource_ids[resource_id] = true
	resource.queue_free()
	return _build_harvest_result(true, "depleted", resource_id, String(snapshot.get("resource_type", "")), int(snapshot.get("yield_amount", 0)), snapshot.get("cell", Vector2i.ZERO))

func export_world_deltas() -> Dictionary:
	return {
		"manual_tiles": export_manual_tile_overrides(),
		"depleted_resources": export_depleted_resource_ids(),
	}

func import_world_deltas(deltas: Dictionary) -> Dictionary:
	var manual_result: Dictionary = import_manual_tile_overrides(deltas.get("manual_tiles", []))
	if not bool(manual_result.get("ok", false)):
		return _build_delta_result(false, "manual_tiles_%s" % String(manual_result.get("reason", "failed")))
	var depleted_result: Dictionary = import_depleted_resource_ids(deltas.get("depleted_resources", []))
	if not bool(depleted_result.get("ok", false)):
		return _build_delta_result(false, "depleted_resources_%s" % String(depleted_result.get("reason", "failed")))
	return _build_delta_result(true, "imported")

func export_manual_tile_overrides() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for cell: Variant in _manual_tile_overrides.keys():
		var typed_cell: Vector2i = cell
		var tile_info: Dictionary = _manual_tile_overrides[cell]
		entries.append({
			"cell": {"x": typed_cell.x, "y": typed_cell.y},
			"terrain": String(tile_info.get("terrain", "")),
		})
	return entries

func import_manual_tile_overrides(entries: Array) -> Dictionary:
	var imported_overrides: Dictionary = {}
	for entry: Variant in entries:
		if not entry is Dictionary:
			return _build_delta_result(false, "invalid_manual_tile_entry")
		var entry_dict: Dictionary = entry
		var cell_data: Dictionary = entry_dict.get("cell", {})
		var terrain_name: String = String(entry_dict.get("terrain", ""))
		var cell: Vector2i = Vector2i(int(cell_data.get("x", 0)), int(cell_data.get("y", 0)))
		if terrain_name.is_empty():
			return _build_delta_result(false, "empty_terrain_name")
		if not TerrainConfigRef.has_terrain(terrain_name):
			return _build_delta_result(false, "unknown_terrain")
		var tile_info: Dictionary = _world_generator.build_tile_info_for_terrain(cell, terrain_name)
		if tile_info.is_empty():
			return _build_delta_result(false, "tile_info_unavailable")
		imported_overrides[cell] = tile_info
	_manual_tile_overrides = imported_overrides
	_apply_manual_overrides_to_loaded_chunks()
	return _build_delta_result(true, "imported")

func export_depleted_resource_ids() -> Array[String]:
	var ids: Array[String] = []
	for resource_id: Variant in _depleted_resource_ids.keys():
		ids.append(String(resource_id))
	return ids

func import_depleted_resource_ids(resource_ids: Array) -> Dictionary:
	var imported_ids: Dictionary = {}
	for resource_id: Variant in resource_ids:
		var id_text: String = String(resource_id)
		if id_text.is_empty():
			return _build_delta_result(false, "empty_resource_id")
		imported_ids[id_text] = true
	_depleted_resource_ids = imported_ids
	_remove_loaded_depleted_resources()
	return _build_delta_result(true, "imported")

func _build_resource_id(spawn_data: Dictionary) -> String:
	var cell: Vector2i = spawn_data.cell
	return "%s:%d:%d" % [String(spawn_data.scene), cell.x, cell.y]

func _parse_resource_id_cell(resource_id: String) -> Vector2i:
	var parts: PackedStringArray = resource_id.split(":")
	if parts.size() != 3:
		return Vector2i(2147483647, 2147483647)
	return Vector2i(int(parts[1]), int(parts[2]))

func _is_resource_depleted(spawn_data: Dictionary) -> bool:
	return is_resource_depleted(_build_resource_id(spawn_data))

func _track_resource_node(resource: ResourceNode, chunk_coord: Vector2i) -> void:
	if resource.resource_id.is_empty():
		push_warning("ChunkManager could not track resource with empty id.")
		return
	_resource_index[resource.resource_id] = {
		"node": resource,
		"chunk_coord": chunk_coord,
	}

func _build_harvest_result(ok: bool, reason: String, resource_id: String, resource_type: String, yield_amount: int, cell: Vector2i) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"resource_id": resource_id,
		"resource_type": resource_type,
		"yield_amount": yield_amount,
		"cell": cell,
	}

func _build_delta_result(ok: bool, reason: String) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
	}

func _apply_manual_overrides_to_loaded_chunks() -> void:
	for chunk_coord: Variant in _loaded_chunks.keys():
		var chunk_key: Vector2i = chunk_coord
		var tile_lookup: Dictionary = _loaded_chunks[chunk_key].get("tile_lookup", {})
		for tile_info: Dictionary in _loaded_chunks[chunk_key].get("tiles", []):
			var final_tile_info: Dictionary = _resolve_surface_projected_tile_info(tile_info)
			tile_lookup[final_tile_info.cell] = final_tile_info
		_loaded_chunks[chunk_key]["tile_lookup"] = tile_lookup
	_refresh_elevation_visuals()

func _remove_loaded_depleted_resources() -> void:
	for chunk_coord: Variant in _loaded_chunks.keys():
		var chunk_key: Vector2i = chunk_coord
		var resource_nodes: Array = _loaded_chunks[chunk_key].get("resource_nodes", [])
		for index in range(resource_nodes.size() - 1, -1, -1):
			var node: Node = resource_nodes[index]
			if not is_instance_valid(node) or not node is ResourceNode:
				continue
			var resource: ResourceNode = node as ResourceNode
			if not _depleted_resource_ids.has(resource.resource_id):
				continue
			resource_nodes.remove_at(index)
			_resource_index.erase(resource.resource_id)
			resource.queue_free()
		_loaded_chunks[chunk_key]["resource_nodes"] = resource_nodes

func _select_resource_scene(scene_key: String) -> PackedScene:
	## Scene exports remain convenient overrides; the registry supplies replaceable defaults.
	if scene_key == "tree":
		if tree_scene != null:
			return tree_scene
	if scene_key == "rock":
		if rock_scene != null:
			return rock_scene
	if scene_key == "berry_bush":
		if berry_bush_scene != null:
			return berry_bush_scene
	var definition: Dictionary = ResourceVisualDefinitionRef.get_definition(scene_key)
	var scene_path: String = String(definition.get("scene_path", ""))
	if scene_path.is_empty():
		return null
	var resource: Resource = load(scene_path)
	return resource as PackedScene if resource is PackedScene else null

func _configure_resource_visual(resource: ResourceNode, spawn_data: Dictionary, chunk_coord: Vector2i) -> void:
	var visual_config: Dictionary = PropVisualConfig.build_resource_visual_config(
		spawn_data,
		chunk_coord,
		WorldGenerator.CHUNK_SIZE,
		_world_generator.seed,
		use_procedural_tree_sprites,
		use_procedural_rock_sprites,
		procedural_tree_variant_cap,
		procedural_rock_variant_cap,
		procedural_tree_large_size,
		procedural_rock_small_size,
		procedural_rock_medium_size,
		procedural_rock_large_size
	)
	resource.use_procedural_sprite = bool(visual_config["use_procedural_sprite"])
	resource.visual_definition_id = String(visual_config.get("visual_definition_id", ""))
	resource.placeholder_visual_id = String(visual_config.get("placeholder_visual_id", ""))
	resource.visual_variant_config = visual_config.get("visual_variant", {}).duplicate(true)
	resource.procedural_sprite_kind = String(visual_config["procedural_sprite_kind"])
	resource.procedural_seed = int(visual_config["procedural_seed"])
	resource.procedural_variant_cap = int(visual_config["procedural_variant_cap"])
	resource.procedural_terrain_tag = String(visual_config["procedural_terrain_tag"])
	resource.procedural_size_tier = String(visual_config["procedural_size_tier"])
	resource.procedural_sprite_size = int(visual_config["procedural_sprite_size"])
	resource.procedural_archetype = String(visual_config["procedural_archetype"])

func _unload_far_chunks(center_chunk: Vector2i) -> void:
	var profile_start_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
	var max_distance: int = load_radius + 1
	var to_remove: Array[Vector2i] = []
	for chunk_coord: Variant in _loaded_chunks.keys():
		var chunk_key: Vector2i = chunk_coord
		if max(abs(chunk_key.x - center_chunk.x), abs(chunk_key.y - center_chunk.y)) > max_distance:
			to_remove.append(chunk_key)
	for chunk_coord: Vector2i in to_remove:
		_clear_chunk_tiles(chunk_coord)
		_remove_debug_elevation_markers_for_chunk(chunk_coord)
		for node: Node in _loaded_chunks[chunk_coord]["resource_nodes"]:
			if is_instance_valid(node):
				if node is ResourceNode:
					_resource_index.erase((node as ResourceNode).resource_id)
				node.queue_free()
		for node: Node in _loaded_chunks[chunk_coord].get("construction_nodes", []):
			if is_instance_valid(node):
				node.queue_free()
		for node: Node in _loaded_chunks[chunk_coord].get("stockpile_zone_nodes", []):
			if is_instance_valid(node):
				node.queue_free()
		for node: Node in _loaded_chunks[chunk_coord].get("ground_item_nodes", []):
			if is_instance_valid(node):
				node.queue_free()
		_pending_resource_spawns = _pending_resource_spawns.filter(func(entry: Dictionary) -> bool:
			return entry["chunk_coord"] != chunk_coord
		)
		_loaded_chunks.erase(chunk_coord)
		chunk_unloaded.emit(chunk_coord)
	if not to_remove.is_empty():
		_refresh_connection_markers()
		_refresh_lighting_projection()
		var cleanup_end_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
		_refresh_elevation_stack_visual_chunks(to_remove)
		_refresh_terrain_tiles_for_loaded_chunks()
		var elevation_end_usec: int = Time.get_ticks_usec() if chunk_profile_debug else 0
		var texture_end_usec: int = elevation_end_usec
		var overlay_end_usec: int = elevation_end_usec
		if shader_cliff_rims_enabled:
			for chunk_coord: Vector2i in to_remove:
				_shader_cliff_rim_visual.call("remove_chunk", chunk_coord)
			_refresh_shader_halos_after_unload(to_remove)
			texture_end_usec = Time.get_ticks_usec() if chunk_profile_debug else 0
			_update_shader_cliff_rim_bounds()
			overlay_end_usec = Time.get_ticks_usec() if chunk_profile_debug else 0
		else:
			_refresh_cliff_edge_rims_for_unloaded_chunks(to_remove)
			overlay_end_usec = Time.get_ticks_usec() if chunk_profile_debug else 0
		if chunk_profile_debug:
			var profile_end_usec := Time.get_ticks_usec()
			print(
				"CHUNK_PROFILE unload_count=%d cleanup_ms=%.3f elevation_stack_ms=%.3f elevation_texture_ms=%.3f shader_overlay_ms=%.3f boundary_mesh_ms=%.3f cliff_rims_ms=%.3f total_ms=%.3f loaded_chunks=%d" % [
					to_remove.size(),
					_usec_to_msec(cleanup_end_usec - profile_start_usec),
					_usec_to_msec(elevation_end_usec - cleanup_end_usec),
					_usec_to_msec(texture_end_usec - elevation_end_usec) if shader_cliff_rims_enabled else 0.0,
					_usec_to_msec(overlay_end_usec - texture_end_usec) if shader_cliff_rims_enabled else 0.0,
					_usec_to_msec(overlay_end_usec - elevation_end_usec) if not shader_cliff_rims_enabled else 0.0,
					_usec_to_msec(profile_end_usec - elevation_end_usec),
					_usec_to_msec(profile_end_usec - profile_start_usec),
					_loaded_chunks.size(),
				]
			)

func _clear_chunk_tiles(chunk_coord: Vector2i) -> void:
	var origin: Vector2i = chunk_coord * WorldGenerator.CHUNK_SIZE
	for y in range(WorldGenerator.CHUNK_SIZE):
		for x in range(WorldGenerator.CHUNK_SIZE):
			terrain_layer.erase_cell(origin + Vector2i(x, y))

func _on_resource_harvest_requested(resource_id: String) -> void:
	if not _harvest_designation_input_enabled:
		return
	if _world_state == null:
		push_warning("Resource harvest designation failed: world_state_unavailable")
		return
	var result: Dictionary = _world_state.request_designate_harvest(resource_id)
	if not bool(result.get("ok", false)):
		push_warning("Resource harvest designation failed: %s" % String(result.get("reason", "unknown")))


func _on_resource_inspection_requested(inspection_data: Dictionary) -> void:
	## Relay a defensive presentation snapshot; Main owns transient UI selection.
	resource_inspection_requested.emit(inspection_data.duplicate(true))

func _on_harvest_order_added(order: Dictionary) -> void:
	_set_resource_harvest_designated(String(order.get("resource_id", "")), true)

func _on_harvest_order_removed(_order_id: String, resource_id: String) -> void:
	_set_resource_harvest_designated(resource_id, false)

func _on_harvest_orders_replaced() -> void:
	for entry: Variant in _resource_index.values():
		var resource: ResourceNode = (entry as Dictionary).get("node") as ResourceNode
		if resource != null and is_instance_valid(resource):
			resource.set_harvest_designated(_world_state != null and _world_state.has_harvest_order_for_resource(resource.resource_id))

func _set_resource_harvest_designated(resource_id: String, designated: bool) -> void:
	if not _resource_index.has(resource_id):
		return
	var resource: ResourceNode = (_resource_index[resource_id] as Dictionary).get("node") as ResourceNode
	if resource != null and is_instance_valid(resource):
		resource.set_harvest_designated(designated)
