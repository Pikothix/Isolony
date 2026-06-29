extends RefCounted
class_name ReachabilityQuery

## Purpose: Answer bounded reachability questions across the currently loaded cell world.
## Responsibility: Build transient orthogonal cell paths from ChunkManager/WorldState read APIs without owning game state.
## Assumptions: W1 has no diagonal movement, path cache, asynchronous search, or traversal outside loaded chunks.

const DEFAULT_MAX_VISITED_CELLS := 4096
const ORTHOGONAL_NEIGHBOURS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.UP,
]


static func find_path(chunk_manager: ChunkManager, world_state: Node, start_cell: Vector2i, target_cell: Vector2i, options: Dictionary = {}) -> Dictionary:
	if chunk_manager == null or world_state == null:
		return _build_result(false, false, [], "query_context_unavailable", 0)
	if not chunk_manager.is_cell_loaded(start_cell):
		return _build_result(false, false, [], "start_not_loaded", 0)
	if not chunk_manager.is_cell_loaded(target_cell):
		return _build_result(false, false, [], "target_not_loaded", 0)
	if start_cell == target_cell:
		return _build_result(true, true, [], "reachable", 1)
	if not is_cell_traversable(chunk_manager, world_state, target_cell, start_cell, target_cell, options):
		return _build_result(false, false, [], "target_unreachable", 1)

	var max_visited_cells: int = maxi(int(options.get("max_visited_cells", DEFAULT_MAX_VISITED_CELLS)), 1)
	var frontier: Array[Vector2i] = [start_cell]
	var frontier_index: int = 0
	var came_from: Dictionary = {start_cell: start_cell}
	while frontier_index < frontier.size() and came_from.size() < max_visited_cells:
		var current: Vector2i = frontier[frontier_index]
		frontier_index += 1
		for offset: Vector2i in ORTHOGONAL_NEIGHBOURS:
			var next_cell: Vector2i = current + offset
			if came_from.has(next_cell):
				continue
			if not is_cell_traversable(chunk_manager, world_state, next_cell, start_cell, target_cell, options):
				continue
			if came_from.size() >= max_visited_cells:
				return _build_result(false, false, [], "search_limit_reached", came_from.size())
			came_from[next_cell] = current
			if next_cell == target_cell:
				return _build_result(true, true, _reconstruct_path(came_from, start_cell, target_cell), "reachable", came_from.size())
			frontier.append(next_cell)

	var reason := "search_limit_reached" if came_from.size() >= max_visited_cells else "target_unreachable"
	return _build_result(false, false, [], reason, came_from.size())


static func is_cell_traversable(chunk_manager: ChunkManager, world_state: Node, cell: Vector2i, start_cell: Vector2i, target_cell: Vector2i, options: Dictionary = {}) -> bool:
	if cell == start_cell:
		return chunk_manager.is_cell_loaded(cell)
	if not chunk_manager.is_cell_loaded(cell):
		return false
	var tile_info: Dictionary = chunk_manager.get_effective_tile_info(cell)
	var terrain_name: String = String(tile_info.get("terrain", ""))
	if not bool(tile_info.get("walkable", false)) or terrain_name == "WATER" or terrain_name == "ROCK_WALL" or bool(tile_info.get("mineable", false)):
		return false

	var is_target: bool = cell == target_cell
	var construction: Dictionary = world_state.get_construction_site_at_cell(cell)
	if not construction.is_empty() and not (is_target and bool(options.get("allow_target_construction", false))):
		return false
	if chunk_manager.is_cell_blocked_by_resource(cell) and not (is_target and bool(options.get("allow_target_resource", false))):
		return false
	return true


static func _reconstruct_path(came_from: Dictionary, start_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
	## Paths contain ordered steps after start_cell; same-cell paths are empty.
	var reversed_path: Array[Vector2i] = []
	var current: Vector2i = target_cell
	while current != start_cell:
		reversed_path.append(current)
		if not came_from.has(current):
			return []
		current = came_from[current]
	reversed_path.reverse()
	return reversed_path


static func _build_result(ok: bool, reachable: bool, path: Array[Vector2i], reason: String, visited_cells: int) -> Dictionary:
	return {
		"ok": ok,
		"reachable": reachable,
		"path": path.duplicate(),
		"reason": reason,
		"visited_cells": visited_cells,
	}
