class_name ExperimentalBuildingLayout
extends RefCounted

## Purpose: Own authored input for the isolated topology experiment.
## Ownership: Owns occupied cells, room IDs, explicit interior walls/openings, and roof regions.
## Responsibility: Validate authored data without deriving presentation topology.
## Integration: Read only by the experiment-local topology resolver.

const DOOR := &"door"
const WINDOW := &"window"

var layout_id: StringName
var occupied_cells: Array[Vector2i] = []
var rooms: Dictionary = {}
var interior_wall_edges: Array[Dictionary] = []
var openings: Array[Dictionary] = []
var roof_regions: Array[Dictionary] = []


func _init(id: StringName = &"") -> void:
	layout_id = id


func add_cell(cell: Vector2i, room_id: StringName) -> void:
	assert(not occupied_cells.has(cell), "Duplicate occupied cell: %s" % cell)
	occupied_cells.append(cell)
	rooms[cell] = room_id


func add_interior_wall_edge(start: Vector2i, end: Vector2i) -> void:
	var edge := normalize_edge(start, end)
	assert(_is_unit_edge(edge[0], edge[1]), "Interior walls must span one grid edge")
	assert(not has_interior_wall_edge(edge[0], edge[1]), "Duplicate interior wall edge")
	interior_wall_edges.append({"start": edge[0], "end": edge[1], "key": edge_key(edge[0], edge[1])})


func add_opening(start: Vector2i, end: Vector2i, kind: StringName) -> void:
	assert(kind == DOOR or kind == WINDOW, "Unsupported opening kind")
	var edge := normalize_edge(start, end)
	assert(_is_unit_edge(edge[0], edge[1]), "Openings must span one grid edge")
	assert(get_opening(edge[0], edge[1]).is_empty(), "Only one opening is supported per edge")
	openings.append({"start": edge[0], "end": edge[1], "key": edge_key(edge[0], edge[1]), "kind": kind})


func add_roof_region(cells: Array[Vector2i], roof_type: StringName, ridge_axis: StringName = &"x") -> void:
	assert(roof_type in [&"flat", &"gable"], "Unsupported roof type")
	assert(ridge_axis in [&"x", &"y"], "Ridge axis must be x or y")
	for cell in cells:
		assert(occupied_cells.has(cell), "Roof cell is outside the footprint: %s" % cell)
	roof_regions.append({"cells": cells.duplicate(), "type": roof_type, "ridge_axis": ridge_axis})


func has_interior_wall_edge(start: Vector2i, end: Vector2i) -> bool:
	var key := edge_key(start, end)
	for edge: Dictionary in interior_wall_edges:
		if edge.key == key:
			return true
	return false


func get_opening(start: Vector2i, end: Vector2i) -> Dictionary:
	var key := edge_key(start, end)
	for opening: Dictionary in openings:
		if opening.key == key:
			return opening
	return {}


func validate() -> bool:
	if occupied_cells.is_empty() or rooms.size() != occupied_cells.size():
		return false
	for edge: Dictionary in interior_wall_edges:
		if not _interior_edge_separates_occupied_cells(edge.start, edge.end):
			return false
	for opening: Dictionary in openings:
		if not _is_unit_edge(opening.start, opening.end):
			return false
	for region: Dictionary in roof_regions:
		for cell: Vector2i in region.cells:
			if not occupied_cells.has(cell):
				return false
	return true


func normalize_edge(start: Vector2i, end: Vector2i) -> Array:
	return [start, end] if start.x < end.x or (start.x == end.x and start.y < end.y) else [end, start]


func edge_key(start: Vector2i, end: Vector2i) -> StringName:
	var edge := normalize_edge(start, end)
	return StringName("%d,%d:%d,%d" % [edge[0].x, edge[0].y, edge[1].x, edge[1].y])


func _interior_edge_separates_occupied_cells(start: Vector2i, end: Vector2i) -> bool:
	if start.y == end.y:
		return occupied_cells.has(Vector2i(start.x, start.y - 1)) and occupied_cells.has(Vector2i(start.x, start.y))
	return occupied_cells.has(Vector2i(start.x - 1, start.y)) and occupied_cells.has(Vector2i(start.x, start.y))


func _is_unit_edge(start: Vector2i, end: Vector2i) -> bool:
	return absi(end.x - start.x) + absi(end.y - start.y) == 1
