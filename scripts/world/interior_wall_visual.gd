extends Node2D
class_name InteriorWallVisual

## Purpose: Render raised presentation faces for interior wall cells.
## Responsibility: Convert read-only cave wall cells into transient per-cell stacked wall geometry that can Y-sort against actors.
## Assumption: Simulation terrain remains elevation zero and non-mineable for the first interior slice.

var _wall_height: float = 14.0


func configure(terrain_layer: TileMapLayer, wall_cells: Array[Vector2i], wall_height: float = 14.0) -> void:
	_wall_height = maxf(wall_height, 1.0)
	_clear_wall_nodes()
	var map_origin: Vector2 = terrain_layer.map_to_local(Vector2i.ZERO)
	var step_x: Vector2 = terrain_layer.map_to_local(Vector2i.RIGHT) - map_origin
	var step_y: Vector2 = terrain_layer.map_to_local(Vector2i.DOWN) - map_origin
	var horizontal_corner: Vector2 = (step_x - step_y) * 0.5
	var vertical_corner: Vector2 = (step_x + step_y) * 0.5
	for cell: Vector2i in wall_cells:
		var center: Vector2 = terrain_layer.map_to_local(cell)
		var wall_visual := InteriorWallCellVisual.new()
		wall_visual.name = "InteriorWall_%d_%d" % [cell.x, cell.y]
		wall_visual.position = center
		wall_visual.configure(horizontal_corner, vertical_corner, _wall_height)
		add_child(wall_visual)


func _clear_wall_nodes() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()


class InteriorWallCellVisual:
	extends Node2D

	var _top: Vector2
	var _right: Vector2
	var _bottom: Vector2
	var _left: Vector2
	var _base_bottom: Vector2
	var _base_left: Vector2
	var _base_right: Vector2


	func configure(horizontal_corner: Vector2, vertical_corner: Vector2, wall_height: float) -> void:
		var rise := Vector2(0, wall_height)
		_top = -vertical_corner - rise
		_right = horizontal_corner - rise
		_bottom = vertical_corner - rise
		_left = -horizontal_corner - rise
		_base_bottom = vertical_corner
		_base_left = -horizontal_corner
		_base_right = horizontal_corner
		queue_redraw()


	func _draw() -> void:
		draw_polygon(PackedVector2Array([_left, _bottom, _base_bottom, _base_left]), PackedColorArray([Color("34313a")]))
		draw_polygon(PackedVector2Array([_right, _bottom, _base_bottom, _base_right]), PackedColorArray([Color("27252d")]))
		draw_polygon(PackedVector2Array([_top, _right, _bottom, _left]), PackedColorArray([Color("605b68")]))
		draw_polyline(PackedVector2Array([_top, _right, _bottom, _left, _top]), Color("8c8494"), 1.5, true)
