class_name ExperimentalPrototypeBuildingService
extends RefCounted

## Purpose: Validate and atomically apply cell-based snapshot building requests.
## Ownership: Owns mutation rules; the supplied plan remains the authoritative data owner.
## Integration: The snapshot controller sends all plan changes through these request methods.

const InteriorResolver := preload("res://experimental/procedural_building_research/prototype_interior_resolver.gd")


func request_set_wall_cells(plan: RefCounted, requested: Array[Vector2i], location: RefCounted) -> Dictionary:
	var normalized := _normalize(requested)
	var validation := _validate_buildable(normalized, location)
	if not validation.valid:
		return validation
	plan.wall_cells = normalized
	_remove_floors_under_walls(plan)
	_remove_orphaned_openings(plan)
	plan.status = "accepted" if not plan.wall_cells.is_empty() else "empty"
	return {"valid": true, "reason": "Wall cells replaced.", "cell_count": plan.wall_cells.size()}


func request_add_wall_cells(plan: RefCounted, requested: Array[Vector2i], location: RefCounted) -> Dictionary:
	var additions := _normalize(requested)
	var validation := _validate_buildable(additions, location)
	if not validation.valid:
		return validation
	var combined: Array[Vector2i] = plan.wall_cells.duplicate()
	combined.append_array(additions)
	plan.wall_cells = _normalize(combined)
	_remove_floors_under_walls(plan)
	plan.status = "accepted" if not plan.wall_cells.is_empty() else "empty"
	return {"valid": true, "reason": "Wall cells added.", "cell_count": plan.wall_cells.size()}


func request_remove_wall_cells(plan: RefCounted, requested: Array[Vector2i], location: RefCounted) -> Dictionary:
	var removals := _normalize(requested)
	var validation := _validate_in_bounds(removals, location)
	if not validation.valid:
		return validation
	var removal_set := _cell_set(removals)
	var retained: Array[Vector2i] = []
	for cell: Vector2i in plan.wall_cells:
		if not removal_set.has(cell):
			retained.append(cell)
	plan.wall_cells = retained
	_remove_orphaned_openings(plan)
	plan.status = "accepted" if not plan.wall_cells.is_empty() or not plan.floor_cells.is_empty() else "empty"
	return {"valid": true, "reason": "Wall cells removed.", "cell_count": plan.wall_cells.size()}


func request_fill_interior_floors(plan: RefCounted, seed: Vector2i, location: RefCounted) -> Dictionary:
	var resolved: Dictionary = InteriorResolver.new().resolve(seed, location.bounds, plan.wall_cells)
	if not resolved.valid:
		return resolved
	var combined: Array[Vector2i] = plan.floor_cells.duplicate()
	combined.append_array(resolved.cells)
	plan.floor_cells = _normalize(combined)
	plan.status = "accepted"
	return {"valid": true, "reason": "Enclosed floor region filled.", "cells": resolved.cells, "cell_count": resolved.cells.size()}


func request_remove_floor_cells(plan: RefCounted, requested: Array[Vector2i], location: RefCounted) -> Dictionary:
	var removals := _normalize(requested)
	var validation := _validate_in_bounds(removals, location)
	if not validation.valid:
		return validation
	var removal_set := _cell_set(removals)
	var retained: Array[Vector2i] = []
	for cell: Vector2i in plan.floor_cells:
		if not removal_set.has(cell):
			retained.append(cell)
	plan.floor_cells = retained
	return {"valid": true, "reason": "Floor cells removed.", "cell_count": plan.floor_cells.size()}


func request_set_opening(plan: RefCounted, cell: Vector2i, kind: StringName) -> Dictionary:
	if kind != &"door" and kind != &"window":
		return {"valid": false, "reason": "Opening kind must be door or window."}
	var orientation := classify_opening_orientation(plan.wall_cells, cell)
	if not orientation.valid:
		return orientation
	var replacement := {
		"cell": cell,
		"kind": String(kind),
		"orientation_group": String(orientation.orientation_group),
	}
	plan.openings[cell] = replacement
	return {"valid": true, "reason": "%s placed." % String(kind).capitalize(), "opening": replacement.duplicate(true)}


func request_remove_opening(plan: RefCounted, cell: Vector2i) -> Dictionary:
	if not plan.openings.has(cell):
		return {"valid": false, "reason": "There is no opening at that cell."}
	plan.openings.erase(cell)
	return {"valid": true, "reason": "Opening removed; wall remains."}


func classify_opening_orientation(wall_cells: Array[Vector2i], cell: Vector2i) -> Dictionary:
	# Orientation groups describe grid connectivity, not the projected visual art plane.
	var walls := _cell_set(wall_cells)
	if not walls.has(cell):
		return {"valid": false, "reason": "Openings can only replace an existing wall cell."}
	var north := walls.has(cell + Vector2i.UP)
	var east := walls.has(cell + Vector2i.RIGHT)
	var south := walls.has(cell + Vector2i.DOWN)
	var west := walls.has(cell + Vector2i.LEFT)
	if east and west and not north and not south:
		return {"valid": true, "orientation_group": &"east_west"}
	if north and south and not east and not west:
		return {"valid": true, "orientation_group": &"north_south"}
	return {"valid": false, "reason": "Openings require a non-corner straight wall cell."}


func _validate_buildable(cells: Array[Vector2i], location: RefCounted) -> Dictionary:
	for cell: Vector2i in cells:
		if not location.contains_cell(cell):
			return {"valid": false, "reason": "A wall cell is outside the snapshot."}
		if not location.is_buildable(cell):
			return {"valid": false, "reason": "A wall cell is on non-buildable terrain."}
	return {"valid": true, "reason": "Cells are buildable."}


func _validate_in_bounds(cells: Array[Vector2i], location: RefCounted) -> Dictionary:
	for cell: Vector2i in cells:
		if not location.contains_cell(cell):
			return {"valid": false, "reason": "A requested cell is outside the snapshot."}
	return {"valid": true, "reason": "Cells are inside the snapshot."}


func _remove_floors_under_walls(plan: RefCounted) -> void:
	var walls := _cell_set(plan.wall_cells)
	var retained: Array[Vector2i] = []
	for cell: Vector2i in plan.floor_cells:
		if not walls.has(cell):
			retained.append(cell)
	plan.floor_cells = retained


func _remove_orphaned_openings(plan: RefCounted) -> void:
	var walls := _cell_set(plan.wall_cells)
	for cell: Vector2i in plan.openings.keys():
		if not walls.has(cell):
			plan.openings.erase(cell)


func _normalize(cells: Array[Vector2i]) -> Array[Vector2i]:
	var unique := _cell_set(cells)
	var normalized: Array[Vector2i] = []
	for cell: Vector2i in unique:
		normalized.append(cell)
	normalized.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return normalized


func _cell_set(cells: Array[Vector2i]) -> Dictionary:
	var result: Dictionary = {}
	for cell: Vector2i in cells:
		result[cell] = true
	return result
