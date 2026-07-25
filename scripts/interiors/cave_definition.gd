extends RefCounted
class_name CaveDefinition

## Purpose: Code-backed definitions for cave/interior templates.
## Responsibility: Provide immutable floor, wall, entrance, and display metadata for simulation-owned interior instances.
## Assumption: The first vertical slice uses one handcrafted read-only cave template; generated or mined cave cells will need explicit design approval.

const BASIC_CAVE := "basic_cave"
const FIRST_SEALED_CAVE_CANDIDATE := "sealed_cave_0001"
const FIRST_CAVE_INTERIOR_ID := "cave_0001"
const FIRST_CAVE_WORLD_SPACE_ID := "cave_0001"
const FIRST_CAVE_CONNECTION_ID := "surface_cave_0001_connection"
const CAVE_CONNECTION_TYPE := "cave_entrance"

const DEFINITIONS := {
	BASIC_CAVE: {
		"id": BASIC_CAVE,
		"display_name": "Mine",
		"entrance_cell": Vector2i(8, 8),
		"room_rect": Rect2i(Vector2i.ZERO, Vector2i(16, 16)),
	}
}

const SEALED_CAVE_CANDIDATES := {
	FIRST_SEALED_CAVE_CANDIDATE: {
		"candidate_id": FIRST_SEALED_CAVE_CANDIDATE,
		"interior_id": FIRST_CAVE_INTERIOR_ID,
		"interior_type": BASIC_CAVE,
		"world_space_id": FIRST_CAVE_WORLD_SPACE_ID,
		"connection_id": FIRST_CAVE_CONNECTION_ID,
		"connection_type": CAVE_CONNECTION_TYPE,
		"surface_search_origin": Vector2i.ZERO,
		"surface_search_radius": 96,
		"interior_entrance_cell": Vector2i(8, 8),
		"display_label": "Sealed Mine",
	}
}


static func has_definition(interior_type: String) -> bool:
	return DEFINITIONS.has(interior_type)


static func get_definition(interior_type: String) -> Dictionary:
	if not has_definition(interior_type):
		return {}
	return DEFINITIONS[interior_type].duplicate(true)


static func get_display_name(interior_type: String) -> String:
	var definition: Dictionary = get_definition(interior_type)
	return String(definition.get("display_name", interior_type.capitalize()))


static func get_entrance_cell(interior_type: String) -> Vector2i:
	var definition: Dictionary = get_definition(interior_type)
	return definition.get("entrance_cell", Vector2i.ZERO)

static func has_sealed_cave_candidate(candidate_id: String) -> bool:
	return SEALED_CAVE_CANDIDATES.has(candidate_id)


static func get_sealed_cave_candidate(candidate_id: String) -> Dictionary:
	if not has_sealed_cave_candidate(candidate_id):
		return {}
	return SEALED_CAVE_CANDIDATES[candidate_id].duplicate(true)


static func get_floor_cells(interior_type: String) -> Array[Vector2i]:
	var definition: Dictionary = get_definition(interior_type)
	var cells: Array[Vector2i] = []
	if definition.is_empty():
		return cells
	var room_rect: Rect2i = definition.get("room_rect", Rect2i())
	for y in range(room_rect.position.y, room_rect.end.y):
		for x in range(room_rect.position.x, room_rect.end.x):
			var cell := Vector2i(x, y)
			if _is_basic_cave_floor(cell):
				cells.append(cell)
	return cells


static func get_wall_cells(interior_type: String) -> Array[Vector2i]:
	var definition: Dictionary = get_definition(interior_type)
	var cells: Array[Vector2i] = []
	if definition.is_empty():
		return cells
	var room_rect: Rect2i = definition.get("room_rect", Rect2i())
	for y in range(room_rect.position.y, room_rect.end.y):
		for x in range(room_rect.position.x, room_rect.end.x):
			var cell := Vector2i(x, y)
			if _is_basic_cave_wall(cell, room_rect):
				cells.append(cell)
	return cells


static func has_cell(interior_type: String, cell: Vector2i) -> bool:
	var definition: Dictionary = get_definition(interior_type)
	if definition.is_empty():
		return false
	var room_rect: Rect2i = definition.get("room_rect", Rect2i())
	return room_rect.has_point(cell) and (_is_basic_cave_floor(cell) or _is_basic_cave_wall(cell, room_rect))


static func is_floor_cell(interior_type: String, cell: Vector2i) -> bool:
	return has_definition(interior_type) and _is_basic_cave_floor(cell)


static func is_wall_cell(interior_type: String, cell: Vector2i) -> bool:
	var definition: Dictionary = get_definition(interior_type)
	return not definition.is_empty() and _is_basic_cave_wall(cell, definition.get("room_rect", Rect2i()))


static func _is_basic_cave_floor(cell: Vector2i) -> bool:
	if Rect2i(6, 6, 5, 5).has_point(cell) and cell not in [Vector2i(6, 6), Vector2i(10, 6), Vector2i(6, 10), Vector2i(10, 10)]:
		return true
	if cell.y == 8 and cell.x >= 3 and cell.x <= 5:
		return true
	if Rect2i(1, 6, 3, 5).has_point(cell) and cell not in [Vector2i(1, 6), Vector2i(1, 10)]:
		return true
	if cell.x == 8 and cell.y >= 3 and cell.y <= 5:
		return true
	if Rect2i(5, 1, 6, 3).has_point(cell) and cell not in [Vector2i(5, 1), Vector2i(10, 1), Vector2i(5, 3)]:
		return true
	if cell.y == 2 and cell.x >= 11 and cell.x <= 13:
		return true
	if cell.y == 8 and cell.x >= 11 and cell.x <= 12:
		return true
	if Rect2i(12, 5, 3, 6).has_point(cell) and cell not in [Vector2i(12, 5), Vector2i(14, 5), Vector2i(14, 10)]:
		return true
	if cell.x == 8 and cell.y >= 11 and cell.y <= 14:
		return true
	if cell.y == 13 and cell.x >= 9 and cell.x <= 13:
		return true
	if Rect2i(11, 12, 3, 3).has_point(cell) and cell != Vector2i(13, 12):
		return true
	return false


static func _is_basic_cave_wall(cell: Vector2i, room_rect: Rect2i) -> bool:
	if not room_rect.has_point(cell) or _is_basic_cave_floor(cell):
		return false
	for y_offset in range(-1, 2):
		for x_offset in range(-1, 2):
			if x_offset == 0 and y_offset == 0:
				continue
			if _is_basic_cave_floor(cell + Vector2i(x_offset, y_offset)):
				return true
	return false
