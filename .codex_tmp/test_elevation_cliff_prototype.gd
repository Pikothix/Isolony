extends SceneTree

const MainScene = preload("res://scenes/Main.tscn")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Node = MainScene.instantiate()
	root.add_child(main)
	await _wait_frames(90)

	var chunk_manager: Node = main.get_node("ChunkManager")
	var world_generator: Node = main.get_node("WorldGenerator")
	var camera: Camera2D = main.get_node("Camera2D")

	_assert(_chunk_elevations_match(world_generator, Vector2i.ZERO), "same chunk produced different elevation values")
	var rock_wall_cell: Vector2i = _find_rock_wall_cell(world_generator)
	_assert(rock_wall_cell != Vector2i(2147483647, 2147483647), "no ROCK_WALL cell found in deterministic search area")
	var rock_wall_info: Dictionary = world_generator.get_tile_info(rock_wall_cell)
	_assert(int(rock_wall_info.get("elevation", -1)) == 2, "ROCK_WALL elevation was not 2")
	_assert(not bool(rock_wall_info.get("walkable", true)), "ROCK_WALL was walkable")
	_assert(bool(rock_wall_info.get("mineable", false)), "ROCK_WALL was not mineable")
	_assert(world_generator.get_cell_elevation(rock_wall_cell) == 2, "WorldGenerator elevation query mismatch")
	_assert(world_generator.is_cell_mineable(rock_wall_cell), "WorldGenerator mineable query mismatch")

	var resource: Node = _find_resource_node(chunk_manager)
	_assert(resource != null, "no resource node spawned for unload/reload validation")
	var resource_id: String = String(resource.resource_id)
	var resource_cell: Vector2i = resource.cell
	var chunk_coord: Vector2i = _cell_to_chunk(resource_cell)
	var elevation_cell: Vector2i = _first_cell_in_chunk(world_generator, chunk_coord)
	var elevation_before: int = chunk_manager.get_cell_elevation(elevation_cell)

	var manual_cell: Vector2i = resource_cell + Vector2i(1, 0)
	if _cell_to_chunk(manual_cell) != chunk_coord:
		manual_cell = resource_cell
	var place_result: Dictionary = chunk_manager.request_place_manual_tile(manual_cell, "STONE")
	_assert(bool(place_result.get("ok", false)), "manual placement failed: %s" % place_result.get("reason", "unknown"))
	var harvest_result: Dictionary = chunk_manager.request_harvest_resource(resource_id)
	_assert(bool(harvest_result.get("ok", false)), "harvest failed: %s" % harvest_result.get("reason", "unknown"))
	await process_frame

	camera.global_position = chunk_manager.get_cell_world_position(resource_cell + Vector2i(WorldGenerator.CHUNK_SIZE * 8, 0))
	await _wait_until(func() -> bool: return not chunk_manager.is_cell_loaded(resource_cell), 180, "chunk did not unload")
	_assert(chunk_manager.has_manual_tile_override(manual_cell), "manual override was erased by unload")
	_assert(chunk_manager.is_resource_depleted(resource_id), "depleted resource id was erased by unload")

	camera.global_position = chunk_manager.get_cell_world_position(resource_cell)
	await _wait_until(func() -> bool: return chunk_manager.is_cell_loaded(resource_cell), 180, "chunk did not reload")
	await _wait_frames(40)

	_assert(chunk_manager.get_cell_elevation(elevation_cell) == elevation_before, "elevation changed after unload/reload")
	_assert(chunk_manager.has_manual_tile_override(manual_cell), "manual override missing after reload")
	_assert(_find_resource_by_id(chunk_manager, resource_id) == null, "depleted resource respawned after reload")

	print("ELEVATION_CLIFF_PROTOTYPE_VALIDATION_OK")
	quit(0)

func _chunk_elevations_match(world_generator: Node, chunk_coord: Vector2i) -> bool:
	var first: Dictionary = world_generator.generate_chunk(chunk_coord)
	var second: Dictionary = world_generator.generate_chunk(chunk_coord)
	var first_tiles: Array = first.get("tiles", [])
	var second_tiles: Array = second.get("tiles", [])
	if first_tiles.size() != second_tiles.size():
		return false
	for index in range(first_tiles.size()):
		if int(first_tiles[index].get("elevation", -1)) != int(second_tiles[index].get("elevation", -2)):
			return false
	return true

func _find_rock_wall_cell(world_generator: Node) -> Vector2i:
	for chunk_y in range(-8, 9):
		for chunk_x in range(-8, 9):
			var chunk_data: Dictionary = world_generator.generate_chunk(Vector2i(chunk_x, chunk_y))
			for tile_info: Dictionary in chunk_data.get("tiles", []):
				if String(tile_info.get("terrain", "")) == "ROCK_WALL":
					return tile_info.get("cell", Vector2i(2147483647, 2147483647))
	return Vector2i(2147483647, 2147483647)

func _first_cell_in_chunk(world_generator: Node, chunk_coord: Vector2i) -> Vector2i:
	var chunk_data: Dictionary = world_generator.generate_chunk(chunk_coord)
	var tiles: Array = chunk_data.get("tiles", [])
	if tiles.is_empty():
		return chunk_coord * WorldGenerator.CHUNK_SIZE
	return tiles[0].get("cell", chunk_coord * WorldGenerator.CHUNK_SIZE)

func _find_resource_node(chunk_manager: Node) -> Node:
	for child: Node in chunk_manager.get_node("GameplayYSort/ResourceRoot").get_children():
		if child is ResourceNode and not String(child.resource_id).is_empty():
			return child
	return null

func _find_resource_by_id(chunk_manager: Node, resource_id: String) -> Node:
	for child: Node in chunk_manager.get_node("GameplayYSort/ResourceRoot").get_children():
		if child is ResourceNode and String(child.resource_id) == resource_id:
			return child
	return null

func _cell_to_chunk(cell: Vector2i) -> Vector2i:
	return Vector2i(int(floor(float(cell.x) / float(WorldGenerator.CHUNK_SIZE))), int(floor(float(cell.y) / float(WorldGenerator.CHUNK_SIZE))))

func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame

func _wait_until(predicate: Callable, max_frames: int, failure_message: String) -> void:
	for _i in range(max_frames):
		if bool(predicate.call()):
			return
		await process_frame
	_assert(false, failure_message)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
