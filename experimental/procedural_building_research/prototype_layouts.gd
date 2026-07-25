class_name ExperimentalBuildingPrototypeLayouts
extends RefCounted

## Purpose: Provide switchable authored inputs for topology research and validation.
## Ownership: Creates fresh experiment-local BuildingLayout instances on every request.
## Integration: Used only by the prototype renderer and its focused validation script.

const Layout := preload("res://experimental/procedural_building_research/building_layout.gd")
const NAMES := [&"rectangle", &"l_shape", &"two_room", &"east_door_calibration"]


static func create(index: int) -> ExperimentalBuildingLayout:
	match posmod(index, NAMES.size()):
		0: return _rectangle()
		1: return _l_shape()
		2: return _two_room()
		_: return _east_door_calibration()


static func _rectangle() -> ExperimentalBuildingLayout:
	var layout := Layout.new(&"rectangle_5x4")
	_add_rectangle_cells(layout, Rect2i(0, 0, 5, 4), &"main")
	layout.add_opening(Vector2i(2, 4), Vector2i(3, 4), Layout.DOOR)
	layout.add_opening(Vector2i(5, 1), Vector2i(5, 2), Layout.WINDOW)
	layout.add_roof_region(layout.occupied_cells, &"gable", &"y")
	return layout


static func _l_shape() -> ExperimentalBuildingLayout:
	var layout := Layout.new(&"l_shape")
	_add_rectangle_cells(layout, Rect2i(0, 0, 3, 4), &"workroom")
	_add_rectangle_cells(layout, Rect2i(3, 2, 2, 2), &"store")
	layout.add_opening(Vector2i(1, 4), Vector2i(2, 4), Layout.DOOR)
	layout.add_opening(Vector2i(3, 0), Vector2i(3, 1), Layout.WINDOW)
	var west_roof: Array[Vector2i] = []
	var east_roof: Array[Vector2i] = []
	for cell: Vector2i in layout.occupied_cells:
		(west_roof if cell.x < 3 else east_roof).append(cell)
	layout.add_roof_region(west_roof, &"gable", &"y")
	layout.add_roof_region(east_roof, &"flat")
	return layout


static func _two_room() -> ExperimentalBuildingLayout:
	var layout := Layout.new(&"two_room_rectangle")
	for y in range(4):
		for x in range(6):
			layout.add_cell(Vector2i(x, y), &"west_room" if x < 3 else &"east_room")
	for y in range(4):
		layout.add_interior_wall_edge(Vector2i(3, y), Vector2i(3, y + 1))
	layout.add_opening(Vector2i(3, 2), Vector2i(3, 3), Layout.DOOR)
	layout.add_opening(Vector2i(1, 4), Vector2i(2, 4), Layout.DOOR)
	layout.add_opening(Vector2i(6, 1), Vector2i(6, 2), Layout.WINDOW)
	layout.add_roof_region(layout.occupied_cells, &"gable", &"y")
	return layout


static func _east_door_calibration() -> ExperimentalBuildingLayout:
	var layout := Layout.new(&"east_door_calibration")
	_add_rectangle_cells(layout, Rect2i(0, 0, 4, 4), &"main")
	layout.add_opening(Vector2i(4, 1), Vector2i(4, 2), Layout.DOOR)
	return layout


static func _add_rectangle_cells(layout: ExperimentalBuildingLayout, bounds: Rect2i, room_id: StringName) -> void:
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			layout.add_cell(Vector2i(x, y), room_id)
