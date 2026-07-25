extends Node2D

## Purpose: Render resolved semantic topology for the isolated building experiment.
## Ownership: Owns only the active authored layout, disposable resolution, and diagnostics.
## Responsibility: Request semantic placeholder modules; never derive authoritative topology.
## Integration: None outside this experiment. Keys 1-3 switch the research layouts.

const Layouts := preload("res://experimental/procedural_building_research/prototype_layouts.gd")
const Resolver := preload("res://experimental/procedural_building_research/building_topology_resolver.gd")
const VisualStyles := preload("res://experimental/procedural_building_research/prototype_visual_styles.gd")
const VisualModule := preload("res://experimental/procedural_building_research/building_visual_module_definition.gd")
const CalibrationOverlay := preload("res://experimental/procedural_building_research/module_calibration_overlay.gd")
const WallConnectionAdapter := preload("res://experimental/procedural_building_research/building_wall_connection_adapter.gd")
const WALL_HEIGHT := 42.0
const FALLBACK_COLOR := Color("ff3fa4")

@export_enum("5x4 Rectangle", "L Shape", "Two Room Rectangle", "East Door Calibration") var starting_layout := 0
@export_enum("Research Placeholder", "Authored Test Style") var starting_style := 0
@export var include_roof := true
@export var asset_calibration_debug := false
@export var tile_module_debug := false

var _layout: ExperimentalBuildingLayout
var _resolved: Dictionary = {}
var _visual_style: Resource
var _current_layout_index := 0
var _requested_modules: Dictionary = {}
var _resolved_modules: Dictionary = {}
var _resolved_module_counts: Dictionary = {}
var _missing_modules: Dictionary = {}
var _suppressed_modules: Dictionary = {}
var _fallback_presentations: Dictionary = {}
var _missing_logged: Dictionary = {}
var _placeholder_requests: Array[Dictionary] = []
var _tile_layers: Dictionary = {}
var _tile_module_diagnostics: Dictionary = {}
var _floor_projection: Dictionary = {}

@onready var _generated_visuals: Node2D = $GeneratedVisuals
@onready var _research_label: Label = $ResearchLabel


func _ready() -> void:
	_visual_style = VisualStyles.create_placeholder_style() if starting_style == 0 else VisualStyles.create_authored_test_style()
	set_layout(starting_layout)


func set_layout(index: int) -> void:
	_current_layout_index = posmod(index, Layouts.NAMES.size())
	_clear_generated_visuals()
	_requested_modules.clear()
	_resolved_modules.clear()
	_resolved_module_counts.clear()
	_missing_modules.clear()
	_suppressed_modules.clear()
	_fallback_presentations.clear()
	_floor_projection.clear()
	_layout = Layouts.create(_current_layout_index)
	_resolved = Resolver.new().resolve(_layout)
	_rebuild_visual_modules()
	_update_research_label()
	queue_redraw()
	print("PROTOTYPE_TOPOLOGY_RESOLVED %s" % get_generation_summary())
	var diagnostic_callback := Callable(self, "_print_diagnostic_summary")
	if not get_tree().process_frame.is_connected(diagnostic_callback):
		get_tree().process_frame.connect(diagnostic_callback, CONNECT_ONE_SHOT)


func set_visual_style(style: Resource) -> void:
	assert(style != null and style.validate(), "Prototype visual style is invalid")
	_visual_style = style
	_clear_generated_visuals()
	_requested_modules.clear()
	_resolved_modules.clear()
	_resolved_module_counts.clear()
	_missing_modules.clear()
	_suppressed_modules.clear()
	_fallback_presentations.clear()
	_floor_projection.clear()
	if not _resolved.is_empty():
		_rebuild_visual_modules()
		_update_research_label()
		queue_redraw()


func set_style_by_index(index: int) -> void:
	set_visual_style(VisualStyles.create_placeholder_style() if posmod(index, 2) == 0 else VisualStyles.create_authored_test_style())
	_update_research_label()


func _update_research_label() -> void:
	if not is_instance_valid(_research_label) or _layout == null or _visual_style == null:
		return
	var missing_ids := PackedStringArray()
	for semantic_id: StringName in _missing_modules:
		missing_ids.append(String(semantic_id))
	_research_label.text = "ISOLATED PROCEDURAL BUILDING RESEARCH\n%s - %s - keys 1/2/3 layout, 4 style, 5 east-door calibration\nmissing: %s" % [_layout.layout_id, _visual_style.style_id, ", ".join(missing_ids)]


func get_generation_summary() -> Dictionary:
	return {
		"layout": _resolved.get("layout_id", &""),
		"occupied_cells": _resolved.get("occupied_cells", []).size(),
		"exterior_edges": _resolved.get("exterior_edges", []).size(),
		"interior_edges": _resolved.get("interior_edges", []).size(),
		"outer_corners": _corner_count(&"outer"),
		"inner_corners": _corner_count(&"inner"),
		"generated_visual_nodes": _generated_visuals.get_child_count() if is_instance_valid(_generated_visuals) else 0,
	}


func get_diagnostic_summary() -> Dictionary:
	return {
		"visual_style": _visual_style.style_id if _visual_style != null else &"",
		"requested_modules": _requested_modules.keys(),
		"resolved_modules": _resolved_modules.keys(),
		"resolved_instance_counts": _resolved_module_counts.duplicate(),
		"missing_fallback_modules": _missing_modules.keys(),
		"suppressed_visual_modules": _suppressed_modules.keys(),
		"fallback_presentations": _fallback_presentations.duplicate(),
		"tile_set_modules": _tile_module_diagnostics.duplicate(true),
		"floor_projection": _floor_projection.duplicate(true),
	}


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode >= KEY_1 and key_event.keycode <= KEY_3:
		set_layout(key_event.keycode - KEY_1)
	elif key_event.keycode == KEY_4:
		set_style_by_index(1 if _visual_style.style_id == &"research_placeholder" else 0)
	elif key_event.keycode == KEY_5:
		set_layout(3)


func _draw() -> void:
	for request: Dictionary in _placeholder_requests:
		_draw_placeholder_module(request.definition, request.data)


func _rebuild_visual_modules() -> void:
	_placeholder_requests.clear()
	var requests: Array[Dictionary] = []
	for cell: Vector2i in _resolved.occupied_cells:
		var room_id: StringName = _resolved.rooms[cell]
		requests.append({"semantic_id": _visual_style.floor_module_for_room(room_id), "data": {"cell": cell, "room": room_id}})
	if _visual_style.use_wall_connection_masks:
		for connection: Dictionary in WallConnectionAdapter.new().resolve(_resolved):
			requests.append({"semantic_id": connection.semantic_id, "data": connection})
		for edge: Dictionary in _resolved.exterior_edges + _resolved.interior_edges:
			if _resolved.openings_by_edge.has(edge.key):
				requests.append(_edge_request(edge))
	else:
		for edge: Dictionary in _resolved.exterior_edges:
			requests.append(_edge_request(edge))
		for edge: Dictionary in _resolved.interior_edges:
			requests.append(_edge_request(edge))
		for corner: Dictionary in _resolved.corners:
			requests.append({"semantic_id": StringName("%s_corner_%s" % [corner.kind, corner.direction]), "data": corner})
	if include_roof:
		_append_roof_requests(requests)
	for request: Dictionary in requests:
		_resolve_visual_request(request.semantic_id, request.data)
	if tile_module_debug:
		print("FLOOR_PROJECTION layout=%s occupied=%d placed=%d missing=%d" % [_resolved.layout_id, _resolved.occupied_cells.size(), _floor_projection.size(), _resolved.occupied_cells.size() - _floor_projection.size()])


func _edge_request(edge: Dictionary) -> Dictionary:
	var opening: Dictionary = _resolved.openings_by_edge.get(edge.key, {})
	var semantic_id: StringName
	if not opening.is_empty():
		if edge.kind == &"exterior":
			semantic_id = StringName("%s_%s" % [opening.kind, edge.direction])
		else:
			semantic_id = StringName("%s_interior_%s" % [opening.kind, edge.direction])
	else:
		semantic_id = StringName("%s_wall_%s" % [edge.kind, edge.direction])
	return {"semantic_id": semantic_id, "data": {"edge": edge, "opening": opening}}


func _append_roof_requests(requests: Array[Dictionary]) -> void:
	if not _visual_style.render_roofs:
		_record_suppressed(&"roof_fill")
		_record_suppressed(&"roof_edge")
		for region: Dictionary in _resolved.roof_regions:
			if region.type == &"gable":
				_record_suppressed(&"roof_ridge")
		return
	for region: Dictionary in _resolved.roof_regions:
		if not region.supported:
			requests.append({"semantic_id": region.diagnostic, "data": {"region": region}})
			continue
		for cell: Vector2i in region.cells:
			requests.append({"semantic_id": &"roof_fill", "data": {"cell": cell, "region": region}})
		requests.append({"semantic_id": &"roof_edge", "data": {"region": region}})
		if region.type == &"gable":
			requests.append({"semantic_id": &"roof_ridge", "data": {"region": region}})


func _resolve_visual_request(semantic_id: StringName, data: Dictionary) -> void:
	_requested_modules[semantic_id] = true
	var module_resolution: Dictionary = _visual_style.resolve(semantic_id)
	var definition: Resource = module_resolution.definition
	if module_resolution.used_fallback:
		_record_missing(semantic_id)
		data = data.duplicate()
		data["missing_semantic_id"] = semantic_id
		_fallback_presentations[semantic_id] = _fallback_presentation_for(data)
	else:
		_resolved_modules[module_resolution.resolved_id] = true
		_resolved_module_counts[module_resolution.resolved_id] = _resolved_module_counts.get(module_resolution.resolved_id, 0) + 1
	if definition.source_kind == VisualModule.PLACEHOLDER:
		_placeholder_requests.append({"definition": definition, "data": data})
	elif definition.source_kind == VisualModule.TILE_SET:
		_place_tileset_module(definition, data)
	else:
		_instantiate_authored_module(definition, data)


func _record_missing(semantic_id: StringName) -> void:
	_missing_modules[semantic_id] = true
	var log_key := StringName("%s:%s" % [_visual_style.style_id, semantic_id])
	if _missing_logged.has(log_key):
		return
	_missing_logged[log_key] = true
	push_warning("PROTOTYPE_MISSING_MODULE %s [%s]; using fallback" % [semantic_id, _visual_style.style_id])


func _record_suppressed(semantic_id: StringName) -> void:
	_suppressed_modules[semantic_id] = true
	_fallback_presentations[semantic_id] = &"suppressed"


func _fallback_presentation_for(data: Dictionary) -> StringName:
	if data.has("vertex") and _visual_style.compact_missing_geometry:
		return &"small_corner_marker"
	if data.has("edge") and not (data.get("opening", {}) as Dictionary).is_empty():
		return &"opening_marker"
	if data.has("edge") and _visual_style.compact_missing_geometry:
		return &"compact_wall_marker"
	return &"geometric_fallback"


func _instantiate_authored_module(definition: Resource, data: Dictionary) -> void:
	var instance: Node
	if definition.source_kind == VisualModule.PACKED_SCENE:
		instance = definition.packed_scene.instantiate()
	else:
		var sprite := Sprite2D.new()
		sprite.texture = definition.texture
		sprite.centered = false
		if definition.source_kind == VisualModule.ATLAS_REGION:
			sprite.region_enabled = true
			sprite.region_rect = definition.atlas_region
		instance = sprite
	_generated_visuals.add_child(instance)
	var scale_factor: float = _visual_style.display_scale
	if instance is Node2D:
		(instance as Node2D).scale = Vector2.ONE * scale_factor
		(instance as Node2D).position = _module_origin(data) - definition.resolved_anchor() * scale_factor
	if instance is CanvasItem:
		(instance as CanvasItem).z_index = definition.z_offset
	if asset_calibration_debug and definition.source_kind == VisualModule.ATLAS_REGION:
		var overlay := CalibrationOverlay.new()
		_generated_visuals.add_child(overlay)
		overlay.configure(definition.semantic_id, _module_origin(data), (instance as Node2D).position, Vector2(definition.atlas_region.size), definition.resolved_anchor(), scale_factor)


func _place_tileset_module(definition: Resource, data: Dictionary) -> void:
	var placement_kind := &"cell" if data.has("cell") else (&"edge" if data.has("edge") else &"vertex")
	var map_coordinate: Vector2i = data.cell if placement_kind == &"cell" else (data.edge.start if placement_kind == &"edge" else data.vertex)
	var atlas_source := definition.tile_set.get_source(definition.tile_source_id) as TileSetAtlasSource
	var tile_data := atlas_source.get_tile_data(definition.atlas_coordinates, definition.alternative_tile_id)
	var layer_key := "%s:%s:%s" % [definition.tile_set.resource_path, definition.z_offset, placement_kind]
	var layer: TileMapLayer = _tile_layers.get(layer_key)
	if layer == null:
		layer = TileMapLayer.new()
		layer.name = "TileModules_%s_z%s" % [placement_kind, definition.z_offset]
		layer.tile_set = definition.tile_set
		layer.z_index = definition.z_offset
		layer.scale = Vector2.ONE * _visual_style.display_scale
		# The authored TileSet calibrates floor and boundary modules to one shared map lattice.
		layer.position = -layer.map_to_local(Vector2i.ZERO) * _visual_style.display_scale
		_generated_visuals.add_child(layer)
		_tile_layers[layer_key] = layer
	layer.set_cell(map_coordinate, definition.tile_source_id, definition.atlas_coordinates, definition.alternative_tile_id)
	if definition.visual_kind == &"floor":
		_floor_projection[map_coordinate] = {
			"room_id": data.get("room", &""),
			"semantic_id": definition.semantic_id,
			"source_id": definition.tile_source_id,
			"atlas_coordinates": definition.atlas_coordinates,
			"alternative_tile_id": definition.alternative_tile_id,
			"texture_origin": tile_data.texture_origin,
			"world_position": layer.position + layer.map_to_local(map_coordinate) * layer.scale,
		}
	if tile_module_debug:
		print("PROTOTYPE_TILE_MODULE vertex=%s contributions=%s mask=%s semantic=%s source=%s atlas=%s alternative=%s origin=%s map=%s world=%s" % [data.get("vertex", data.get("cell", Vector2i.ZERO)), data.get("contributions", []), definition.connection_mask, definition.semantic_id, definition.tile_source_id, definition.atlas_coordinates, definition.alternative_tile_id, tile_data.texture_origin, map_coordinate, layer.position + layer.map_to_local(map_coordinate) * layer.scale])
	_tile_module_diagnostics[definition.semantic_id] = {
		"source_id": definition.tile_source_id,
		"atlas_coordinates": definition.atlas_coordinates,
		"alternative_tile_id": definition.alternative_tile_id,
		"texture_origin": tile_data.texture_origin,
		"connection_mask": definition.connection_mask,
	}


func _draw_placeholder_module(definition: Resource, data: Dictionary) -> void:
	match definition.visual_kind:
		&"floor": _draw_floor(data)
		&"exterior_wall": _draw_wall(data.edge, Color("a85645"))
		&"interior_wall": _draw_wall(data.edge, Color("7c6a61"))
		&"door": _draw_door(data.edge, Color("f1d5b0"))
		&"window": _draw_window_wall(data.edge)
		&"outer_corner": _draw_corner(data, Color("f1d5b0"))
		&"roof_fill": _draw_roof_fill(data)
		&"roof_ridge": _draw_roof_ridge(data.region)
		_: _draw_fallback(data)


func _module_origin(data: Dictionary) -> Vector2:
	if data.has("cell"):
		return _grid_to_screen(Vector2(data.cell) + Vector2(0.5, 0.5))
	if data.has("edge"):
		return _grid_to_screen(Vector2(data.edge.start))
	if data.has("vertex"):
		return _grid_to_screen(Vector2(data.vertex))
	if data.has("region") and not data.region.cells.is_empty():
		return _grid_to_screen(Vector2(data.region.cells[0]) + Vector2(0.5, 0.5))
	return Vector2.ZERO


func _draw_floor(data: Dictionary) -> void:
	var center := _grid_to_screen(Vector2(data.cell) + Vector2(0.5, 0.5))
	var diamond := _diamond(center)
	var color := Color("8d7659") if data.room in [&"main", &"workroom", &"west_room"] else Color("6f7f69")
	draw_colored_polygon(diamond, color)
	draw_polyline(_closed(diamond), Color("4c4035"), 1.0)


func _draw_wall(edge: Dictionary, color: Color) -> void:
	var points := _wall_points(edge)
	draw_colored_polygon(points, color)
	draw_polyline(_closed(points), Color("4e2c28"), 2.0)


func _draw_door(edge: Dictionary, color: Color) -> void:
	var start := _grid_to_screen(Vector2(edge.start))
	var end := _grid_to_screen(Vector2(edge.end))
	draw_line(start, end, Color("d4b27a"), 4.0)
	draw_line(start, start + Vector2.UP * WALL_HEIGHT, color, 3.0)
	draw_line(end, end + Vector2.UP * WALL_HEIGHT, color, 3.0)


func _draw_window_wall(edge: Dictionary) -> void:
	_draw_wall(edge, Color("a85645"))
	var start := _grid_to_screen(Vector2(edge.start))
	var end := _grid_to_screen(Vector2(edge.end))
	var along := end - start
	var lower_left := start + along * 0.31 + Vector2.UP * 13.0
	var lower_right := start + along * 0.69 + Vector2.UP * 13.0
	var points := PackedVector2Array([lower_left, lower_right, lower_right + Vector2.UP * 14.0, lower_left + Vector2.UP * 14.0])
	draw_colored_polygon(points, Color("9fc3ca"))
	draw_polyline(_closed(points), Color("eee1c8"), 2.0)


func _draw_corner(data: Dictionary, color: Color) -> void:
	var base := _grid_to_screen(Vector2(data.vertex))
	draw_line(base, base + Vector2.UP * (WALL_HEIGHT + 3.0), color, 5.0)


func _draw_roof_fill(data: Dictionary) -> void:
	var center := _grid_to_screen(Vector2(data.cell) + Vector2(0.5, 0.5)) + Vector2.UP * (WALL_HEIGHT + 5.0)
	var diamond := _diamond(center)
	draw_colored_polygon(diamond, Color("c7c9d3", 0.82))
	draw_polyline(_closed(diamond), Color("666878"), 1.5)


func _draw_roof_ridge(region: Dictionary) -> void:
	var min_cell: Vector2i = region.cells[0]
	var max_cell: Vector2i = region.cells[0]
	for cell: Vector2i in region.cells:
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
	var start_grid: Vector2
	var end_grid: Vector2
	if region.ridge_axis == &"x":
		start_grid = Vector2(min_cell.x, (min_cell.y + max_cell.y + 1) * 0.5)
		end_grid = Vector2(max_cell.x + 1, start_grid.y)
	else:
		start_grid = Vector2((min_cell.x + max_cell.x + 1) * 0.5, min_cell.y)
		end_grid = Vector2(start_grid.x, max_cell.y + 1)
	var height_offset := Vector2.UP * (WALL_HEIGHT + 10.0)
	draw_line(_grid_to_screen(start_grid) + height_offset, _grid_to_screen(end_grid) + height_offset, Color("f4f2f5"), 3.0)


func _draw_fallback(data: Dictionary) -> void:
	if data.has("vertex"):
		if _visual_style.compact_missing_geometry:
			_draw_missing_corner_marker(data)
		else:
			_draw_corner(data, FALLBACK_COLOR)
	elif data.has("edge"):
		var opening: Dictionary = data.get("opening", {})
		if not opening.is_empty():
			_draw_missing_opening_marker(data.edge, opening.kind, data.get("missing_semantic_id", &"missing_opening"))
		elif _visual_style.compact_missing_geometry:
			_draw_missing_wall_marker(data.edge, data.get("missing_semantic_id", &"missing_wall"))
		else:
			_draw_wall(data.edge, FALLBACK_COLOR)
	elif data.has("cell"):
		var center := _grid_to_screen(Vector2(data.cell) + Vector2(0.5, 0.5)) + Vector2.UP * (WALL_HEIGHT + 5.0)
		var diamond := _diamond(center)
		draw_colored_polygon(diamond, Color(FALLBACK_COLOR, 0.7))
		draw_polyline(_closed(diamond), FALLBACK_COLOR, 1.5)
	elif data.has("region"):
		var region: Dictionary = data.region
		for cell: Vector2i in region.cells:
			var center := _grid_to_screen(Vector2(cell) + Vector2(0.5, 0.5)) + Vector2.UP * (WALL_HEIGHT + 7.0)
			draw_circle(center, 3.0, FALLBACK_COLOR)


func _draw_missing_corner_marker(data: Dictionary) -> void:
	var point := _grid_to_screen(Vector2(data.vertex))
	draw_circle(point, 4.0, FALLBACK_COLOR, false, 2.0)
	draw_line(point + Vector2(-4, -4), point + Vector2(4, 4), FALLBACK_COLOR, 1.5)
	draw_line(point + Vector2(-4, 4), point + Vector2(4, -4), FALLBACK_COLOR, 1.5)
	var corner_code := "%s-%s" % ["I" if data.kind == &"inner" else "O", _direction_code(data.direction)]
	_draw_missing_label(point, StringName(corner_code))


func _draw_missing_opening_marker(edge: Dictionary, opening_kind: StringName, _semantic_id: StringName) -> void:
	var start := _grid_to_screen(Vector2(edge.start))
	var end := _grid_to_screen(Vector2(edge.end))
	var midpoint := (start + end) * 0.5
	draw_line(start, start.lerp(end, 0.3), FALLBACK_COLOR, 3.0)
	draw_line(end.lerp(start, 0.3), end, FALLBACK_COLOR, 3.0)
	if opening_kind == ExperimentalBuildingLayout.DOOR:
		draw_line(midpoint + Vector2(-4, 0), midpoint + Vector2(-4, -12), FALLBACK_COLOR, 2.0)
		draw_line(midpoint + Vector2(4, 0), midpoint + Vector2(4, -12), FALLBACK_COLOR, 2.0)
	else:
		draw_rect(Rect2(midpoint + Vector2(-5, -10), Vector2(10, 7)), FALLBACK_COLOR, false, 2.0)
	_draw_missing_label(midpoint, &"D?" if opening_kind == ExperimentalBuildingLayout.DOOR else &"W?")


func _draw_missing_wall_marker(edge: Dictionary, _semantic_id: StringName) -> void:
	var start := _grid_to_screen(Vector2(edge.start))
	var end := _grid_to_screen(Vector2(edge.end))
	draw_line(start, end, FALLBACK_COLOR, 2.0)
	draw_line(start, start + Vector2.UP * 8.0, FALLBACK_COLOR, 1.5)
	draw_line(end, end + Vector2.UP * 8.0, FALLBACK_COLOR, 1.5)
	_draw_missing_label((start + end) * 0.5, &"IW?" if edge.kind == &"interior" else &"W?")


func _draw_missing_label(point: Vector2, semantic_id: StringName) -> void:
	draw_string(ThemeDB.fallback_font, point + Vector2(4, -4), String(semantic_id), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, FALLBACK_COLOR)


func _direction_code(direction: StringName) -> String:
	return "".join(Array(String(direction).split("_")).map(func(part: String) -> String: return part.left(1).to_upper()))


func _wall_points(edge: Dictionary) -> PackedVector2Array:
	var start := _grid_to_screen(Vector2(edge.start))
	var end := _grid_to_screen(Vector2(edge.end))
	return PackedVector2Array([start, end, end + Vector2.UP * WALL_HEIGHT, start + Vector2.UP * WALL_HEIGHT])


func _corner_count(kind: StringName) -> int:
	var count := 0
	for corner: Dictionary in _resolved.get("corners", []):
		count += 1 if corner.kind == kind else 0
	return count


func _clear_generated_visuals() -> void:
	_tile_layers.clear()
	_tile_module_diagnostics.clear()
	if not is_instance_valid(_generated_visuals):
		return
	for child: Node in _generated_visuals.get_children():
		_generated_visuals.remove_child(child)
		child.queue_free()


func _print_diagnostic_summary() -> void:
	print("PROTOTYPE_MODULE_DIAGNOSTICS %s" % get_diagnostic_summary())


func _diamond(center: Vector2) -> PackedVector2Array:
	var cell_half: Vector2 = _visual_style.cell_half * _visual_style.display_scale
	return PackedVector2Array([center + Vector2(0.0, -cell_half.y), center + Vector2(cell_half.x, 0.0), center + Vector2(0.0, cell_half.y), center + Vector2(-cell_half.x, 0.0)])


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	closed.append(points[0])
	return closed


func _grid_to_screen(cell: Vector2) -> Vector2:
	var cell_half: Vector2 = _visual_style.cell_half * _visual_style.display_scale
	return Vector2((cell.x - cell.y) * cell_half.x, (cell.x + cell.y) * cell_half.y)
