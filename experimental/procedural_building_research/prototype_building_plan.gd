class_name ExperimentalPrototypeBuildingPlan
extends RefCounted

## Purpose: Own the single authoritative mutable cell-based plan in the snapshot experiment.
## Ownership: Owns plan identity, wall cells, floor cells, openings, and status.
## Integration: Mutated only by ExperimentalPrototypeBuildingService after whole-request validation.

var plan_id: String = "prototype_building_1"
var wall_cells: Array[Vector2i] = []
var floor_cells: Array[Vector2i] = []
var openings: Dictionary = {}
var status: String = "empty"


func clear() -> void:
	wall_cells.clear()
	floor_cells.clear()
	openings.clear()
	status = "empty"


func snapshot() -> Dictionary:
	return {
		"plan_id": plan_id,
		"wall_cells": wall_cells.duplicate(),
		"floor_cells": floor_cells.duplicate(),
		"openings": openings.duplicate(true),
		"status": status,
	}
