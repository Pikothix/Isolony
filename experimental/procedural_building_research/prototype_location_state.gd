class_name ExperimentalPrototypeLocationState
extends RefCounted

## Purpose: Own the bounded terrain data for the snapshot building experiment.
## Ownership: Owns fixed terrain cells and buildability; owns no plan or visuals.

var bounds: Rect2i
var terrain_cells: Array[Vector2i] = []


func _init(snapshot_bounds: Rect2i = Rect2i(0, 0, 12, 10)) -> void:
	bounds = snapshot_bounds
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			terrain_cells.append(Vector2i(x, y))


func contains_cell(cell: Vector2i) -> bool:
	return bounds.has_point(cell)


func is_buildable(cell: Vector2i) -> bool:
	return contains_cell(cell)
