extends Node2D
class_name ChunkManager

const ProcSpriteCache = preload("res://scripts/procgen/proc_sprite_cache.gd")
const PropPrewarmConfig = preload("res://scripts/world/props/prop_prewarm_config.gd")
const PropVisualConfig = preload("res://scripts/world/props/prop_visual_config.gd")
const ResourceVisualDefinitionRef = preload("res://scripts/world/props/resource_visual_definition.gd")
const TerrainConfigRef = preload("res://scripts/world/terrain_config.gd")
const ConstructionSiteVisualScript = preload("res://scripts/buildings/construction_site_visual.gd")
const StockpileZoneVisualScript = preload("res://scripts/world/stockpile_zone_visual.gd")
const GroundItemVisualScript = preload("res://scripts/world/ground_item_visual.gd")
const BuildingDefinitionRef = preload("res://scripts/buildings/building_definition.gd")

signal chunk_generated(chunk_coord: Vector2i)
signal chunk_unloaded(chunk_coord: Vector2i)

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
@export_range(1, 128, 1) var resource_spawns_per_frame: int = 10
@export var procedural_cache_debug: bool = false

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var stockpile_zone_root: Node2D = $GameplayYSort/StockpileZoneRoot
@onready var ground_item_root: Node2D = $GameplayYSort/GroundItemRoot
@onready var resource_root: Node2D = $GameplayYSort/ResourceRoot
@onready var construction_root: Node2D = $GameplayYSort/ConstructionRoot

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

func _ready() -> void:
	_world_generator = get_node(world_generator_path) as WorldGenerator
	_camera = get_node(camera_path) as Camera2D
	_wander_rng.randomize()
	ProcSpriteCache.set_debug_logging(procedural_cache_debug)
	_prewarm_procedural_cache()
	_update_streaming(true)

func _process(_delta: float) -> void:
	_update_streaming(false)
	for _i in range(chunks_per_frame):
		if _pending_chunks.is_empty():
			break
		_generate_chunk(_pending_chunks.pop_front())
	_process_pending_resource_spawns()

func get_cell_world_position(cell: Vector2i) -> Vector2:
	return terrain_layer.to_global(terrain_layer.map_to_local(cell))

func world_to_cell(world_position: Vector2) -> Vector2i:
	return terrain_layer.local_to_map(terrain_layer.to_local(world_position))

func is_cell_loaded(cell: Vector2i) -> bool:
	return _loaded_chunks.has(_cell_to_chunk(cell))

func is_cell_blocked_by_resource(cell: Vector2i) -> bool:
	var chunk_coord: Vector2i = _cell_to_chunk(cell)
	if not _loaded_chunks.has(chunk_coord):
		return false
	for spawn_data: Dictionary in _loaded_chunks[chunk_coord].get("resource_spawns", []):
		if spawn_data.get("cell", Vector2i.ZERO) == cell and not _is_resource_depleted(spawn_data):
			return true
	return false

func set_world_state(world_state: Node) -> void:
	if _world_state != null:
		if _world_state.construction_site_added.is_connected(_on_construction_site_added):
			_world_state.construction_site_added.disconnect(_on_construction_site_added)
		if _world_state.construction_site_changed.is_connected(_on_construction_site_changed):
			_world_state.construction_site_changed.disconnect(_on_construction_site_changed)
		if _world_state.construction_site_cancelled.is_connected(_on_construction_site_cancelled):
			_world_state.construction_site_cancelled.disconnect(_on_construction_site_cancelled)
		if _world_state.day_phase_changed.is_connected(_on_building_effect_day_phase_changed):
			_world_state.day_phase_changed.disconnect(_on_building_effect_day_phase_changed)
		if _world_state.construction_sites_replaced.is_connected(_on_construction_sites_replaced):
			_world_state.construction_sites_replaced.disconnect(_on_construction_sites_replaced)
		if _world_state.harvest_order_added.is_connected(_on_harvest_order_added):
			_world_state.harvest_order_added.disconnect(_on_harvest_order_added)
		if _world_state.harvest_order_removed.is_connected(_on_harvest_order_removed):
			_world_state.harvest_order_removed.disconnect(_on_harvest_order_removed)
		if _world_state.harvest_orders_replaced.is_connected(_on_harvest_orders_replaced):
			_world_state.harvest_orders_replaced.disconnect(_on_harvest_orders_replaced)
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
		return
	_world_state.construction_site_added.connect(_on_construction_site_added)
	_world_state.construction_site_changed.connect(_on_construction_site_changed)
	_world_state.construction_site_cancelled.connect(_on_construction_site_cancelled)
	_world_state.construction_sites_replaced.connect(_on_construction_sites_replaced)
	_world_state.day_phase_changed.connect(_on_building_effect_day_phase_changed)
	_world_state.harvest_order_added.connect(_on_harvest_order_added)
	_world_state.harvest_order_removed.connect(_on_harvest_order_removed)
	_world_state.harvest_orders_replaced.connect(_on_harvest_orders_replaced)
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

func set_harvest_designation_input_enabled(enabled: bool) -> void:
	## Main owns the transient control mode; this only gates presentation-originated click intent.
	_harvest_designation_input_enabled = enabled

func is_harvest_designation_input_enabled() -> bool:
	return _harvest_designation_input_enabled

func get_effective_tile_info(cell: Vector2i) -> Dictionary:
	var chunk_coord: Vector2i = _cell_to_chunk(cell)
	if _loaded_chunks.has(chunk_coord):
		var tile_lookup: Dictionary = _loaded_chunks[chunk_coord].get("tile_lookup", {})
		if tile_lookup.has(cell):
			return tile_lookup[cell].duplicate()
	return _manual_tile_overrides.get(cell, _world_generator.get_tile_info(cell)).duplicate()

func get_cell_elevation(cell: Vector2i) -> int:
	return int(get_effective_tile_info(cell).get("elevation", 0))

func is_cell_mineable(cell: Vector2i) -> bool:
	return bool(get_effective_tile_info(cell).get("mineable", false))

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
	terrain_layer.set_cell(tile_info.cell, tile_info.source_id, tile_info.atlas_coords)
	var tile_lookup: Dictionary = _loaded_chunks[chunk_coord].get("tile_lookup", {})
	tile_lookup[cell] = tile_info
	_loaded_chunks[chunk_coord]["tile_lookup"] = tile_lookup
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

func get_random_walkable_cell_near(origin: Vector2i, radius: int, attempts: int = 32) -> Vector2i:
	for _i in range(attempts):
		var candidate: Vector2i = origin + Vector2i(_wander_rng.randi_range(-radius, radius), _wander_rng.randi_range(-radius, radius))
		if _world_generator.is_cell_walkable(candidate):
			return candidate
	for step in range(1, radius * 2):
		for offset_x in range(-step, step + 1):
			for offset_y in range(-step, step + 1):
				var candidate: Vector2i = origin + Vector2i(offset_x, offset_y)
				if _world_generator.is_cell_walkable(candidate):
					return candidate
	return origin

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
		_last_center_chunk = center_chunk
		_queue_chunks_around(center_chunk)
		_sort_pending(center_chunk)
		_unload_far_chunks(center_chunk)

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
	var chunk_data: Dictionary = _world_generator.generate_chunk(chunk_coord)
	var tile_lookup: Dictionary = {}
	for tile_info: Dictionary in chunk_data.tiles:
		var final_tile_info: Dictionary = _manual_tile_overrides.get(tile_info.cell, tile_info)
		terrain_layer.set_cell(final_tile_info.cell, final_tile_info.source_id, final_tile_info.atlas_coords)
		tile_lookup[final_tile_info.cell] = final_tile_info
	var resource_nodes: Array[Node] = []
	_loaded_chunks[chunk_coord] = {
		"resource_nodes": resource_nodes,
		"construction_nodes": [],
		"stockpile_zone_nodes": [],
		"ground_item_nodes": [],
		"resource_spawns": chunk_data.resources,
		"tiles": chunk_data.tiles,
		"tile_lookup": tile_lookup,
	}
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
	chunk_generated.emit(chunk_coord)

func _spawn_construction_visuals_for_chunk(chunk_coord: Vector2i) -> void:
	if _world_state == null or not _loaded_chunks.has(chunk_coord):
		return
	for site: Dictionary in _world_state.get_construction_sites():
		var origin_cell: Vector2i = site.get("origin_cell", Vector2i.ZERO)
		if _cell_to_chunk(origin_cell) == chunk_coord:
			_spawn_construction_visual(site, chunk_coord)

func _spawn_stockpile_zone_visuals_for_chunk(chunk_coord: Vector2i) -> void:
	if _world_state == null or not _loaded_chunks.has(chunk_coord):
		return
	for zone: Dictionary in _world_state.get_stockpile_zones():
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
	visual.position = terrain_layer.map_to_local(cell)
	var x_step: Vector2 = terrain_layer.map_to_local(cell + Vector2i.RIGHT) - terrain_layer.map_to_local(cell)
	var y_step: Vector2 = terrain_layer.map_to_local(cell + Vector2i.DOWN) - terrain_layer.map_to_local(cell)
	visual.configure(x_step, y_step)
	stockpile_zone_root.add_child(visual)
	_loaded_chunks[chunk_coord]["stockpile_zone_nodes"].append(visual)

func _on_stockpile_zone_added(zone: Dictionary) -> void:
	if not bool(zone.get("enabled", true)):
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
	for item: Dictionary in _world_state.get_ground_items():
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
	visual.position = terrain_layer.map_to_local(cell) + Vector2(0, -5)
	visual.call("configure", String(item.get("resource_type", "")), int(item.get("amount", 0)))
	ground_item_root.add_child(visual)
	_loaded_chunks[chunk_coord]["ground_item_nodes"].append(visual)

func _on_ground_item_added(item: Dictionary) -> void:
	if not bool(item.get("enabled", true)):
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
	visual.position = terrain_layer.map_to_local(site.get("origin_cell", Vector2i.ZERO)) + Vector2(0, -4)
	_configure_construction_visual(visual, site)
	construction_root.add_child(visual)
	_loaded_chunks[chunk_coord]["construction_nodes"].append(visual)

func _on_construction_site_added(site: Dictionary) -> void:
	var origin_cell: Vector2i = site.get("origin_cell", Vector2i.ZERO)
	var chunk_coord: Vector2i = _cell_to_chunk(origin_cell)
	if _loaded_chunks.has(chunk_coord):
		_spawn_construction_visual(site, chunk_coord)

func _on_construction_site_changed(site: Dictionary) -> void:
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
	var show_light_glow: bool = completed and _world_state != null and _world_state.is_night()
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
		visual_metadata.get("placeholder_palette", {})
	)

func _on_building_effect_day_phase_changed(_is_daytime: bool) -> void:
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

func _build_resource_node(spawn_data: Dictionary, chunk_coord: Vector2i) -> ResourceNode:
	var scene: PackedScene = _select_resource_scene(spawn_data.scene)
	if scene == null:
		return null
	var resource: ResourceNode = scene.instantiate() as ResourceNode
	resource.resource_id = _build_resource_id(spawn_data)
	resource.cell = spawn_data.cell
	resource.position = terrain_layer.map_to_local(spawn_data.cell) + Vector2(0, -8)
	resource.resource_type = spawn_data.resource_type
	resource.yield_amount = spawn_data.amount
	_configure_resource_visual(resource, spawn_data, chunk_coord)
	if _world_state != null:
		resource.set_harvest_designated(_world_state.has_harvest_order_for_resource(resource.resource_id))
	resource.harvest_requested.connect(_on_resource_harvest_requested)
	return resource

func _process_pending_resource_spawns() -> void:
	if _pending_resource_spawns.is_empty():
		return
	var remaining: int = resource_spawns_per_frame if stage_resource_spawning else _pending_resource_spawns.size()
	while remaining > 0 and not _pending_resource_spawns.is_empty():
		var job: Dictionary = _pending_resource_spawns.pop_front()
		var chunk_coord: Vector2i = job["chunk_coord"]
		if not _loaded_chunks.has(chunk_coord):
			remaining -= 1
			continue
		if _is_resource_depleted(job["spawn_data"]):
			remaining -= 1
			continue
		var resource: ResourceNode = _build_resource_node(job["spawn_data"], chunk_coord)
		if resource != null:
			resource_root.add_child(resource)
			_loaded_chunks[chunk_coord]["resource_nodes"].append(resource)
			_track_resource_node(resource, chunk_coord)
		remaining -= 1

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
			var final_tile_info: Dictionary = _manual_tile_overrides.get(tile_info.cell, tile_info)
			terrain_layer.set_cell(final_tile_info.cell, final_tile_info.source_id, final_tile_info.atlas_coords)
			tile_lookup[final_tile_info.cell] = final_tile_info
		_loaded_chunks[chunk_key]["tile_lookup"] = tile_lookup

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
	resource.procedural_sprite_kind = String(visual_config["procedural_sprite_kind"])
	resource.procedural_seed = int(visual_config["procedural_seed"])
	resource.procedural_variant_cap = int(visual_config["procedural_variant_cap"])
	resource.procedural_terrain_tag = String(visual_config["procedural_terrain_tag"])
	resource.procedural_size_tier = String(visual_config["procedural_size_tier"])
	resource.procedural_sprite_size = int(visual_config["procedural_sprite_size"])
	resource.procedural_archetype = String(visual_config["procedural_archetype"])

func _unload_far_chunks(center_chunk: Vector2i) -> void:
	var max_distance: int = load_radius + 1
	var to_remove: Array[Vector2i] = []
	for chunk_coord: Variant in _loaded_chunks.keys():
		var chunk_key: Vector2i = chunk_coord
		if max(abs(chunk_key.x - center_chunk.x), abs(chunk_key.y - center_chunk.y)) > max_distance:
			to_remove.append(chunk_key)
	for chunk_coord: Vector2i in to_remove:
		_clear_chunk_tiles(chunk_coord)
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
