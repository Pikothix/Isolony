class_name ExperimentalPrototypeInteriorResolver
extends RefCounted

## Purpose: Resolve one enclosed non-wall region inside fixed snapshot bounds.
## Ownership: Owns deterministic flood-fill computation only; owns no plan or rendering state.
## Integration: Called by PrototypeBuildingService before an atomic floor mutation.

const NEIGHBORS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


func resolve(seed: Vector2i, bounds: Rect2i, wall_cells: Array[Vector2i]) -> Dictionary:
	if not bounds.has_point(seed):
		return {"valid": false, "reason": "The floor seed is outside the snapshot.", "cells": []}
	var walls := _cell_set(wall_cells)
	if walls.has(seed):
		return {"valid": false, "reason": "Floor fill cannot start on a wall.", "cells": []}
	var visited: Dictionary = {seed: true}
	var frontier: Array[Vector2i] = [seed]
	var cells: Array[Vector2i] = []
	var touches_boundary := false
	var index := 0
	while index < frontier.size():
		var current := frontier[index]
		index += 1
		cells.append(current)
		if current.x == bounds.position.x or current.y == bounds.position.y or current.x == bounds.end.x - 1 or current.y == bounds.end.y - 1:
			touches_boundary = true
		for offset: Vector2i in NEIGHBORS:
			var neighbor := current + offset
			if bounds.has_point(neighbor) and not walls.has(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				frontier.append(neighbor)
	if touches_boundary:
		return {"valid": false, "reason": "The selected region is open to the snapshot boundary.", "cells": []}
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return {"valid": true, "reason": "Enclosed floor region resolved.", "cells": cells}


func _cell_set(cells: Array[Vector2i]) -> Dictionary:
	var result: Dictionary = {}
	for cell: Vector2i in cells:
		result[cell] = true
	return result
