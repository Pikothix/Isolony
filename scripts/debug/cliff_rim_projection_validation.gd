extends SceneTree

## Purpose: Compare shader elevation-texture edge inputs against the CPU cliff-rim predicate.
## Responsibility: Cover equal-elevation E1 plateaus and genuine E1/E2 downward boundaries.
## Assumption: This diagnostic reads presentation state only and never changes terrain or simulation rules.

const MainScene = preload("res://scenes/Main.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node2D = MainScene.instantiate() as Node2D
	root.add_child(main)
	for _frame in range(48):
		await process_frame
	var chunk_manager: ChunkManager = main.get_node("ChunkManager") as ChunkManager
	chunk_manager.set_shader_cliff_rims_enabled(true)
	var plateau_cell: Vector2i = Vector2i(2147483647, 2147483647)
	var e1_boundary_cell: Vector2i = Vector2i(2147483647, 2147483647)
	var e2_boundary_cell: Vector2i = Vector2i(2147483647, 2147483647)
	var false_plateau_fragment: Dictionary = {}
	for y in range(-48, 49):
		for x in range(-48, 49):
			var cell := Vector2i(x, y)
			if not chunk_manager.is_cell_loaded(cell, ChunkManager.SURFACE_WORLD_SPACE_ID):
				continue
			var comparison: Dictionary = chunk_manager.get_cliff_rim_debug_comparison(cell)
			var elevation: int = int(comparison.get("cpu_elevation", 0))
			if elevation > 0:
				_check(bool(comparison.get("matches", false)), "shader/CPU edge inputs differed at %s: %s" % [cell, comparison])
			var exposed: Array = comparison.get("cpu_exposed_directions", [])
			var neighbours: Dictionary = comparison.get("cpu_neighbours", {})
			if elevation == 1 and exposed.is_empty() and _all_neighbours_equal(neighbours, 1):
				plateau_cell = cell
				if false_plateau_fragment.is_empty():
					for sample_position: Vector2 in _get_top_edge_sample_positions(chunk_manager, cell, elevation):
						var fragment_debug: Dictionary = chunk_manager.get_cliff_rim_fragment_debug(sample_position)
						_check(_shader_cells_match_godot(fragment_debug), "shader cell projection differed from TileMapLayer at %s: %s" % [sample_position, fragment_debug])
						if float((fragment_debug.get("shader_fragment", {}) as Dictionary).get("coverage", 0.0)) > 0.001:
							false_plateau_fragment = fragment_debug
							break
			elif elevation == 1 and not exposed.is_empty() and _cell_has_live_rim_coverage(chunk_manager, cell, elevation):
				e1_boundary_cell = cell
			elif elevation == 2 and not exposed.is_empty() and _cell_has_live_rim_coverage(chunk_manager, cell, elevation):
				e2_boundary_cell = cell
	_check(plateau_cell.x != 2147483647, "no loaded equal-neighbour E1 plateau cell was found")
	_check(e1_boundary_cell.x != 2147483647, "no loaded E1 downward boundary was found")
	_check(e2_boundary_cell.x != 2147483647, "no loaded E2 downward boundary was found")
	_check(false_plateau_fragment.is_empty(), "live equal-neighbour E1 top received shader coverage: %s" % false_plateau_fragment)
	if plateau_cell.x != 2147483647:
		var plateau: Dictionary = chunk_manager.get_cliff_rim_debug_comparison(plateau_cell)
		_check((plateau.get("shader_exposed_directions", []) as Array).is_empty(), "equal-neighbour E1 plateau exposed a shader rim")
	if e1_boundary_cell.x != 2147483647:
		var e1_boundary: Dictionary = chunk_manager.get_cliff_rim_debug_comparison(e1_boundary_cell)
		_check(not (e1_boundary.get("shader_exposed_directions", []) as Array).is_empty(), "true E1 boundary lost its shader rim")
	if e2_boundary_cell.x != 2147483647:
		var e2_boundary: Dictionary = chunk_manager.get_cliff_rim_debug_comparison(e2_boundary_cell)
		_check(not (e2_boundary.get("shader_exposed_directions", []) as Array).is_empty(), "true E2 boundary lost its shader rim")
	chunk_manager.set_shader_cliff_rims_enabled(false)
	_check(not chunk_manager.is_shader_cliff_rims_enabled(), "chunk boundary mesh rims did not enable")
	var mesh_root: CanvasItem = chunk_manager.get_node("TerrainVisualRoot/ChunkBoundaryMeshRoot") as CanvasItem
	_check(mesh_root.visible, "chunk boundary mesh root remained hidden")

	main.queue_free()
	await process_frame
	if _failures.is_empty():
		print("CLIFF_RIM_PROJECTION_VALIDATION: PASS plateau=%s e1_boundary=%s e2_boundary=%s" % [plateau_cell, e1_boundary_cell, e2_boundary_cell])
		quit(0)
		return
	for failure: String in _failures:
		push_error("CLIFF_RIM_PROJECTION_VALIDATION: %s" % failure)
	quit(1)


func _all_neighbours_equal(neighbours: Dictionary, elevation: int) -> bool:
	for value: Variant in neighbours.values():
		if int(value) != elevation:
			return false
	return neighbours.size() == 4


func _get_top_edge_sample_positions(chunk_manager: ChunkManager, cell: Vector2i, elevation: int) -> Array[Vector2]:
	var top_center_local: Vector2 = CellRenderInfo.get_visible_top_center(chunk_manager.terrain_layer.map_to_local(cell), elevation)
	var top := top_center_local + Vector2(0.0, -CellRenderInfo.TOP_DIAMOND_HALF_SIZE.y)
	var right := top_center_local + Vector2(CellRenderInfo.TOP_DIAMOND_HALF_SIZE.x, 0.0)
	var bottom := top_center_local + Vector2(0.0, CellRenderInfo.TOP_DIAMOND_HALF_SIZE.y)
	var left := top_center_local + Vector2(-CellRenderInfo.TOP_DIAMOND_HALF_SIZE.x, 0.0)
	var rim_offset := Vector2(0.0, chunk_manager.cliff_rim_vertical_offset)
	return [
		chunk_manager.terrain_layer.to_global((top + right) * 0.5 + rim_offset),
		chunk_manager.terrain_layer.to_global((right + bottom) * 0.5 + rim_offset),
		chunk_manager.terrain_layer.to_global((bottom + left) * 0.5 + rim_offset),
		chunk_manager.terrain_layer.to_global((left + top) * 0.5 + rim_offset),
	]


func _cell_has_live_rim_coverage(chunk_manager: ChunkManager, cell: Vector2i, elevation: int) -> bool:
	for sample_position: Vector2 in _get_top_edge_sample_positions(chunk_manager, cell, elevation):
		var fragment_debug: Dictionary = chunk_manager.get_cliff_rim_fragment_debug(sample_position)
		if float((fragment_debug.get("shader_fragment", {}) as Dictionary).get("coverage", 0.0)) > 0.001:
			return true
	return false


func _shader_cells_match_godot(fragment_debug: Dictionary) -> bool:
	var godot_cells: Dictionary = fragment_debug.get("godot_cells_by_elevation", {})
	var shader_fragment: Dictionary = fragment_debug.get("shader_fragment", {})
	for candidate_value: Variant in shader_fragment.get("candidates", []):
		var candidate: Dictionary = candidate_value
		var elevation_level: int = int(candidate.get("elevation_level", 0))
		if candidate.get("derived_cell", Vector2i.ZERO) != godot_cells.get(elevation_level, Vector2i.ZERO):
			return false
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
