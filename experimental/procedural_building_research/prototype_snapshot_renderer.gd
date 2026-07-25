class_name ExperimentalPrototypeSnapshotRenderer
extends Node2D

## Purpose: Present snapshot terrain, transient designation, and accepted plan results.
## Ownership: Owns disposable TileMap layers and preview rendering; owns no plan state.
## Integration: Receives an authoritative cell plan and writes exactly one tile per visible cell.

const VisualStyles := preload("res://experimental/procedural_building_research/prototype_visual_styles.gd")
const TILE_HALF := Vector2(16.0, 8.0)
const BUILDING_WALL_VISUAL_OFFSET := Vector2(0.0, TILE_HALF.y)

var _location: RefCounted
var _preview_cells: Array[Vector2i] = []
var _hovered_cell := Vector2i(-999, -999)
var _visual_style: Resource
var _floor_layer: TileMapLayer
var _wall_layer: TileMapLayer
var _opening_layer: TileMapLayer
var _roof_layer: TileMapLayer


func configure(location: RefCounted) -> void:
	_location = location
	_visual_style = VisualStyles.create_snapshot_cell_style()
	queue_redraw()


func set_preview(cells: Array[Vector2i], hovered_cell: Vector2i) -> void:
	_preview_cells = cells.duplicate()
	_hovered_cell = hovered_cell
	queue_redraw()


func render_plan(plan: RefCounted) -> void:
	_clear_building_layers()
	_floor_layer = _new_layer("BuildingFloorLayer", 0)
	var floor_definition: Resource = _visual_style.resolve(&"floor").definition
	for cell: Vector2i in plan.floor_cells:
		_floor_layer.set_cell(cell, floor_definition.tile_source_id, floor_definition.atlas_coordinates, floor_definition.alternative_tile_id)
	_wall_layer = _new_layer("BuildingWallLayer", 1)
	# The wall atlas pivot is one half-tile above its ground-contact baseline.
	_wall_layer.position += BUILDING_WALL_VISUAL_OFFSET
	var wall_definition: Resource = _visual_style.resolve(&"wall").definition
	for cell: Vector2i in plan.wall_cells:
		_wall_layer.set_cell(cell, wall_definition.tile_source_id, wall_definition.atlas_coordinates, wall_definition.alternative_tile_id)
	_opening_layer = _new_layer("BuildingOpeningLayer", 2)
	# Openings are decorative wall overlays and therefore share the wall baseline.
	_opening_layer.position += BUILDING_WALL_VISUAL_OFFSET
	for cell: Vector2i in plan.openings:
		var opening: Dictionary = plan.openings[cell]
		var semantic := StringName("%s_%s" % [opening.kind, opening.orientation_group])
		var definition: Resource = _visual_style.resolve(semantic).definition
		_opening_layer.set_cell(cell, definition.tile_source_id, definition.atlas_coordinates, definition.alternative_tile_id)
	_roof_layer = _new_layer("BuildingRoofLayer", 3)
	_roof_layer.visible = false


func screen_to_cell(screen_position: Vector2) -> Vector2i:
	var local := to_local(screen_position)
	var grid := Vector2((local.x / TILE_HALF.x + local.y / TILE_HALF.y) * 0.5, (local.y / TILE_HALF.y - local.x / TILE_HALF.x) * 0.5)
	return Vector2i(floori(grid.x), floori(grid.y))


func rendered_floor_count() -> int:
	return _floor_layer.get_used_cells().size() if is_instance_valid(_floor_layer) else 0


func rendered_wall_count() -> int:
	return _wall_layer.get_used_cells().size() if is_instance_valid(_wall_layer) else 0


func rendered_opening_count() -> int:
	return _opening_layer.get_used_cells().size() if is_instance_valid(_opening_layer) else 0


func rendered_roof_count() -> int:
	return _roof_layer.get_used_cells().size() if is_instance_valid(_roof_layer) else 0


func rendered_atlas(layer_kind: StringName, cell: Vector2i) -> Vector2i:
	var layer: TileMapLayer
	match layer_kind:
		&"floor": layer = _floor_layer
		&"wall": layer = _wall_layer
		&"opening": layer = _opening_layer
		_: return Vector2i(-1, -1)
	return layer.get_cell_atlas_coords(cell) if is_instance_valid(layer) else Vector2i(-1, -1)


func rendered_layer_position(layer_kind: StringName) -> Vector2:
	var layer: TileMapLayer
	match layer_kind:
		&"floor": layer = _floor_layer
		&"wall": layer = _wall_layer
		&"opening": layer = _opening_layer
		_: return Vector2.INF
	return layer.position if is_instance_valid(layer) else Vector2.INF


func preview_count() -> int:
	return _preview_cells.size()


func cell_center_screen(cell: Vector2i) -> Vector2:
	return to_global(_grid_to_screen(Vector2(cell) + Vector2(0.5, 0.5)))


func _draw() -> void:
	if _location == null:
		return
	for cell: Vector2i in _location.terrain_cells:
		_draw_diamond(cell, Color("53694e"), Color("718267"))
	for cell: Vector2i in _preview_cells:
		_draw_diamond(cell, Color(0.25, 0.72, 0.88, 0.48), Color(0.65, 0.92, 1.0, 0.9))
	if _location.contains_cell(_hovered_cell):
		_draw_diamond(_hovered_cell, Color(0.95, 0.9, 0.4, 0.18), Color(1.0, 0.95, 0.55, 0.95))


func _draw_diamond(cell: Vector2i, fill: Color, outline: Color) -> void:
	var center := _grid_to_screen(Vector2(cell) + Vector2(0.5, 0.5))
	var points := PackedVector2Array([center + Vector2(0, -8), center + Vector2(16, 0), center + Vector2(0, 8), center + Vector2(-16, 0)])
	draw_colored_polygon(points, fill)
	points.append(points[0])
	draw_polyline(points, outline, 1.0)


func _grid_to_screen(grid: Vector2) -> Vector2:
	return Vector2((grid.x - grid.y) * TILE_HALF.x, (grid.x + grid.y) * TILE_HALF.y)


func _new_layer(layer_name: String, z: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	# Definitions remain the atlas authority; all experiment modules currently share this TileSet.
	layer.tile_set = _visual_style.resolve(&"floor").definition.tile_set
	layer.z_index = z
	layer.position = -layer.map_to_local(Vector2i.ZERO)
	add_child(layer)
	return layer


func _clear_building_layers() -> void:
	if is_instance_valid(_floor_layer):
		_floor_layer.queue_free()
	if is_instance_valid(_wall_layer):
		_wall_layer.queue_free()
	if is_instance_valid(_opening_layer):
		_opening_layer.queue_free()
	if is_instance_valid(_roof_layer):
		_roof_layer.queue_free()
	_floor_layer = null
	_wall_layer = null
	_opening_layer = null
	_roof_layer = null
