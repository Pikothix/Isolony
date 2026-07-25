extends Node2D
class_name LightingOverlay

## Purpose: Project authoritative ambient light into a cheap world-only darkness pass.
## Responsibility: Draw one loaded-area darkness rect; source glows and per-cell light remain opt-in diagnostics.
## Assumption: This presentation slice has no occlusion; WorldState/LightingState remain authoritative for gameplay light.

const MAX_LIGHT_LEVEL := 15
const MAX_DARKNESS_ALPHA := 0.72
const DARKNESS_COLOR := Color(0.015, 0.025, 0.07)
const GLOW_COLOR := Color(1.0, 0.62, 0.16)

var _terrain_layer: TileMapLayer
var _world_state: Node
var _cell_visual_world_position: Callable
var _world_space_id := ""
var _loaded_cell_bounds := Rect2i()
var _cells: Array[Vector2i] = []
var _light_levels: Dictionary = {}
var _ambient_light_level := MAX_LIGHT_LEVEL
var _light_sources: Array[Dictionary] = []
var _loaded_area := Rect2()
var _draw_per_cell_light_debug := false
var _draw_light_source_glows := false
var _profile_enabled := false
var _profile_redraw_count := 0
var _profile_rebuild_count := 0
var _profile_rebuild_usec := 0
var _profile_draw_count := 0
var _profile_draw_usec := 0
var _profile_draw_calls := 0
var _profile_polygons := 0
var _profile_circles := 0
var _profile_cells_drawn := 0
var _profile_light_queries := 0


func configure(terrain_layer: TileMapLayer, world_state: Node, world_space_id: String, loaded_cell_bounds: Rect2i, debug_cells: Array[Vector2i] = [], draw_per_cell_light_debug: bool = false, draw_light_source_glows: bool = false, profile_enabled: bool = false, cell_visual_world_position: Callable = Callable()) -> void:
	## The caller invokes this for possible invalidations. A visual redraw happens only
	## when the projected state actually changes.
	_profile_enabled = profile_enabled
	var next_ambient_light_level := MAX_LIGHT_LEVEL
	if world_state != null:
		next_ambient_light_level = world_state.get_ambient_light_level(world_space_id)
	var next_light_sources: Array[Dictionary] = []
	if draw_light_source_glows and world_state != null:
		for effect: Dictionary in world_state.get_completed_building_effects(world_space_id):
			if float(effect.get("light_radius", 0.0)) > 0.0:
				next_light_sources.append(effect.duplicate(true))
	var next_cells: Array[Vector2i] = []
	if draw_per_cell_light_debug:
		next_cells.assign(debug_cells)
	var state_changed := _terrain_layer != terrain_layer \
		or _world_state != world_state \
		or _cell_visual_world_position != cell_visual_world_position \
		or _world_space_id != world_space_id \
		or _loaded_cell_bounds != loaded_cell_bounds \
		or _ambient_light_level != next_ambient_light_level \
		or _draw_per_cell_light_debug != draw_per_cell_light_debug \
		or _draw_light_source_glows != draw_light_source_glows \
		or _light_sources != next_light_sources
	if draw_per_cell_light_debug and _cells != next_cells:
		state_changed = true
	if not state_changed:
		return
	var started_usec: int = Time.get_ticks_usec() if _profile_enabled else 0
	_terrain_layer = terrain_layer
	_world_state = world_state
	_cell_visual_world_position = cell_visual_world_position
	_world_space_id = world_space_id
	_loaded_cell_bounds = loaded_cell_bounds
	_cells = next_cells
	_draw_per_cell_light_debug = draw_per_cell_light_debug
	_draw_light_source_glows = draw_light_source_glows
	_ambient_light_level = next_ambient_light_level
	_light_sources = next_light_sources
	_light_levels.clear()
	_loaded_area = _build_loaded_area()
	if _world_state != null and _draw_per_cell_light_debug:
		for cell: Vector2i in _cells:
			_light_levels[cell] = _world_state.get_light_level(cell, _world_space_id)
	if _profile_enabled:
		_profile_rebuild_count += 1
		_profile_rebuild_usec += Time.get_ticks_usec() - started_usec
		_profile_light_queries += _cells.size() if _draw_per_cell_light_debug else 0
		_profile_redraw_count += 1
	queue_redraw()


func consume_profile_stats() -> Dictionary:
	var stats := {
		"redraw_count": _profile_redraw_count,
		"rebuild_count": _profile_rebuild_count,
		"rebuild_ms": float(_profile_rebuild_usec) / 1000.0,
		"draw_count": _profile_draw_count,
		"draw_ms": float(_profile_draw_usec) / 1000.0,
		"draw_calls": _profile_draw_calls,
		"polygons": _profile_polygons,
		"circles": _profile_circles,
		"cells_drawn": _profile_cells_drawn,
		"light_queries": _profile_light_queries,
	}
	_profile_redraw_count = 0
	_profile_rebuild_count = 0
	_profile_rebuild_usec = 0
	_profile_draw_count = 0
	_profile_draw_usec = 0
	_profile_draw_calls = 0
	_profile_polygons = 0
	_profile_circles = 0
	_profile_cells_drawn = 0
	_profile_light_queries = 0
	return stats


func _draw() -> void:
	var started_usec: int = Time.get_ticks_usec() if _profile_enabled else 0
	if _terrain_layer == null or _world_state == null or _world_space_id.is_empty():
		return
	if _draw_per_cell_light_debug:
		_draw_per_cell_darkness()
	else:
		_draw_ambient_darkness_and_glows()
	if _profile_enabled:
		_profile_draw_count += 1
		_profile_draw_usec += Time.get_ticks_usec() - started_usec
		_profile_cells_drawn += _cells.size() if _draw_per_cell_light_debug else 1


func _draw_ambient_darkness_and_glows() -> void:
	var darkness_alpha := (1.0 - float(_ambient_light_level) / float(MAX_LIGHT_LEVEL)) * MAX_DARKNESS_ALPHA
	if darkness_alpha <= 0.001 or _loaded_area.size == Vector2.ZERO:
		return
	draw_rect(_loaded_area, Color(DARKNESS_COLOR, darkness_alpha), true)
	if _profile_enabled:
		_profile_draw_calls += 1
	if not _draw_light_source_glows:
		return
	for effect: Dictionary in _light_sources:
		var origin_cell: Vector2i = effect.get("origin_cell", Vector2i.ZERO)
		var radius_cells := maxf(float(effect.get("light_radius", 0.0)), 0.0)
		if radius_cells <= 0.0:
			continue
		var center: Vector2 = _get_cell_visual_position(origin_cell)
		var glow_radius := radius_cells * _get_cell_visual_radius()
		draw_circle(center, glow_radius, Color(GLOW_COLOR, 0.20))
		draw_circle(center, glow_radius * 0.52, Color(GLOW_COLOR, 0.30))
		if _profile_enabled:
			_profile_draw_calls += 2
			_profile_circles += 2


func _draw_per_cell_darkness() -> void:
	var map_origin: Vector2 = _terrain_layer.map_to_local(Vector2i.ZERO)
	var step_x: Vector2 = _terrain_layer.map_to_local(Vector2i.RIGHT) - map_origin
	var step_y: Vector2 = _terrain_layer.map_to_local(Vector2i.DOWN) - map_origin
	var horizontal_corner: Vector2 = (step_x - step_y) * 0.5
	var vertical_corner: Vector2 = (step_x + step_y) * 0.5
	for cell: Vector2i in _cells:
		var light_level: int = int(_light_levels.get(cell, 0))
		var darkness_alpha := (1.0 - float(light_level) / float(MAX_LIGHT_LEVEL)) * MAX_DARKNESS_ALPHA
		if darkness_alpha <= 0.001:
			continue
		var center: Vector2 = _get_cell_visual_position(cell)
		var diamond := PackedVector2Array([center - vertical_corner, center + horizontal_corner, center + vertical_corner, center - horizontal_corner])
		draw_colored_polygon(diamond, Color(DARKNESS_COLOR, darkness_alpha))
		if _profile_enabled:
			_profile_draw_calls += 1
			_profile_polygons += 1


func _build_loaded_area() -> Rect2:
	if _terrain_layer == null or _loaded_cell_bounds.size.x <= 0 or _loaded_cell_bounds.size.y <= 0:
		return Rect2()
	var first_cell := _loaded_cell_bounds.position
	var last_cell := _loaded_cell_bounds.end - Vector2i.ONE
	var corners: Array[Vector2i] = [
		first_cell,
		Vector2i(last_cell.x, first_cell.y),
		Vector2i(first_cell.x, last_cell.y),
		last_cell,
	]
	var bounds := Rect2(_terrain_layer.map_to_local(corners[0]), Vector2.ZERO)
	for cell: Vector2i in corners:
		bounds = bounds.expand(_terrain_layer.map_to_local(cell))
	var padding := Vector2(_get_cell_visual_radius() * 2.0, _get_cell_visual_radius() * 2.0)
	return Rect2(bounds.position - padding, bounds.size + padding * 2.0)


func _get_cell_visual_radius() -> float:
	var origin: Vector2 = _terrain_layer.map_to_local(Vector2i.ZERO)
	var step_x: Vector2 = _terrain_layer.map_to_local(Vector2i.RIGHT) - origin
	var step_y: Vector2 = _terrain_layer.map_to_local(Vector2i.DOWN) - origin
	return maxf(step_x.length(), step_y.length()) * 0.5


func _get_cell_visual_position(cell: Vector2i) -> Vector2:
	if _cell_visual_world_position.is_valid():
		return to_local(_cell_visual_world_position.call(cell))
	return _terrain_layer.map_to_local(cell)
