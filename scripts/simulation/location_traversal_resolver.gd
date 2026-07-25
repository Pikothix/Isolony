extends RefCounted
class_name LocationTraversalResolver

const BuildingDefinition = preload("res://scripts/buildings/building_definition.gd")
const COMPLETED_BUILDING_STATE := "COMPLETED"
const BLOCKING_RESOURCE_KINDS := ["tree", "fruit_tree", "rock"]
const NEIGHBOUR_OFFSETS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var _registry: RefCounted
var _construction: RefCounted
var _buildings: RefCounted

## Purpose: Provide the single simulation-side traversal answer for bounded locations.
## Ownership: Reads authoritative terrain, resource, construction, and building state;
## it owns traversal rules and deterministic path search, but never actor movement.
## Determinism: A* expands north, east, south, then west and breaks equal scores
## by Manhattan distance followed by insertion sequence.
func configure(registry: RefCounted, construction: RefCounted, buildings: RefCounted) -> void:
	_registry = registry
	_construction = construction
	_buildings = buildings


func is_cell_traversable(location_id: String, cell: Vector2i, _actor_id := "") -> bool:
	if _registry == null or not _registry.has(location_id): return false
	var location: Dictionary = _registry.get_record(location_id)
	if not bool(location.get("claimed", false)): return false
	if not Rect2i(Vector2i.ZERO, Vector2i(location.get("map_size", Vector2i.ZERO))).has_point(cell): return false
	var terrain := _terrain_at(location, cell)
	if terrain.is_empty() or not bool(terrain.get("walkable", false)): return false
	for resource: Dictionary in location.get("resources", []):
		if Vector2i(resource.get("cell", Vector2i(-1, -1))) == cell and not bool(resource.get("depleted", false)) and String(resource.get("resource_kind", "")) in BLOCKING_RESOURCE_KINDS:
			return false
	if _completed_building_blocks(location_id, cell): return false
	if _structure_blocks_cell(location_id, cell): return false
	return true

func can_traverse_edge(location_id: String, first: Vector2i, second: Vector2i) -> bool:
	return absi(first.x - second.x) + absi(first.y - second.y) == 1


func get_traversal_cost(location_id: String, cell: Vector2i, actor_id := "") -> float:
	return 1.0 if is_cell_traversable(location_id, cell, actor_id) else INF


func find_path(location_id: String, start: Vector2i, goal: Vector2i, actor_id := "") -> Dictionary:
	var context := _validate_path_context(location_id, start, goal, actor_id)
	if not bool(context.ok): return context
	if start == goal: return {"ok": true, "reason": "path_found", "path": [start], "cost": 0.0}
	var open: Array[Dictionary] = []
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0.0}
	var sequence := 0
	open.append(_open_entry(start, 0.0, goal, sequence))
	while not open.is_empty():
		open.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(float(a.f), float(b.f)): return float(a.f) < float(b.f)
			if int(a.h) != int(b.h): return int(a.h) < int(b.h)
			return int(a.sequence) < int(b.sequence))
		var current_entry: Dictionary = open.pop_front()
		var current := Vector2i(current_entry.cell)
		if float(current_entry.g) > float(g_score.get(current, INF)): continue
		if current == goal:
			var path := _reconstruct_path(came_from, current)
			return {"ok": true, "reason": "path_found", "path": path.duplicate(), "cost": float(g_score[current])}
		for offset: Vector2i in NEIGHBOUR_OFFSETS:
			var neighbour := current + offset
			if not is_cell_traversable(location_id, neighbour, actor_id): continue
			if not can_traverse_edge(location_id, current, neighbour): continue
			var tentative := float(g_score[current]) + get_traversal_cost(location_id, neighbour, actor_id)
			if tentative >= float(g_score.get(neighbour, INF)): continue
			came_from[neighbour] = current
			g_score[neighbour] = tentative
			sequence += 1
			open.append(_open_entry(neighbour, tentative, goal, sequence))
	return _result(false, "no_path")


func _validate_path_context(location_id: String, start: Vector2i, goal: Vector2i, actor_id: String) -> Dictionary:
	if _registry == null or not _registry.has(location_id): return _result(false, "unknown_location")
	var location: Dictionary = _registry.get_record(location_id)
	if not bool(location.get("claimed", false)): return _result(false, "unclaimed_location")
	var bounds := Rect2i(Vector2i.ZERO, Vector2i(location.get("map_size", Vector2i.ZERO)))
	if not bounds.has_point(start): return _result(false, "start_out_of_bounds")
	if not bounds.has_point(goal): return _result(false, "goal_out_of_bounds")
	if start != goal and not is_cell_traversable(location_id, goal, actor_id): return _result(false, "blocked_goal")
	return _result(true, "valid")


func _open_entry(cell: Vector2i, g: float, goal: Vector2i, sequence: int) -> Dictionary:
	var h := absi(goal.x - cell.x) + absi(goal.y - cell.y)
	return {"cell": cell, "g": g, "h": h, "f": g + float(h), "sequence": sequence}


func _reconstruct_path(came_from: Dictionary, goal: Vector2i) -> Array[Vector2i]:
	var reversed: Array[Vector2i] = [goal]
	var current := goal
	while came_from.has(current):
		current = Vector2i(came_from[current])
		reversed.append(current)
	reversed.reverse()
	return reversed


func _terrain_at(location: Dictionary, cell: Vector2i) -> Dictionary:
	for terrain: Dictionary in location.get("terrain", []):
		if Vector2i(terrain.get("cell", Vector2i(-1, -1))) == cell: return terrain
	return {}


func _completed_building_blocks(location_id: String, cell: Vector2i) -> bool:
	if _buildings == null: return false
	for building: Dictionary in _buildings.get_building_snapshots(location_id):
		if bool(building.get("derived_enclosure", false)): continue
		if String(building.get("state", "")) != COMPLETED_BUILDING_STATE or cell not in building.get("occupied_cells", []): continue
		var definition := BuildingDefinition.get_definition(String(building.get("building_id", "")))
		return not bool(definition.get("passable", false))
	return false


func _structure_blocks_cell(location_id: String, cell: Vector2i) -> bool:
	if _construction == null: return false
	var completed: Dictionary = _construction.get_location_completed_structures(location_id)
	var structure: Dictionary = completed.get("structure_cells", {}).get(cell, {})
	if not structure.is_empty():
		if String(structure.get("kind", "")) != "wall": return true
		return String(structure.get("fixture_kind", "")) != "door"
	for site: Dictionary in _construction.get_location_construction_sites(location_id):
		if Vector2i(site.get("cell", Vector2i(-1, -1))) != cell: continue
		if String(site.get("piece_kind", "")) != "wall": continue
		if bool(site.get("resources_consumed", false)) or float(site.get("build_progress", 0.0)) > 0.0: return true
	return false


func _result(ok: bool, reason: String) -> Dictionary:
	return {"ok": ok, "reason": reason, "path": [], "cost": 0.0}
