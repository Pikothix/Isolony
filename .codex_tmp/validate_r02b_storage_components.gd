extends SceneTree

## Purpose: Validate R02B Storehouse storage components without changing active stockpile gameplay.
## Responsibility: Exercise completed-building component derivation, defensive snapshots, save/load reconstruction, and unchanged ResourceStockpile paths.
## Assumption: Direct WorldState calls are acceptable here because this is a focused simulation contract validator.

const MainScene = preload("res://scenes/Main.tscn")
const SaveGameServiceRef = preload("res://scripts/simulation/save_game_service.gd")
const BuildingDefinitionRef = preload("res://scripts/buildings/building_definition.gd")

const INVALID_CELL := Vector2i(2147483647, 2147483647)

var _main: Node
var _world_state: Node
var _chunk_manager: ChunkManager
var _colonist_manager: ColonistManager


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error("R02B storage component validation failed: %s" % message)
	quit(1)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _run() -> void:
	_main = MainScene.instantiate()
	root.add_child(_main)
	await _wait_frames(160)
	_world_state = _main.get("_world_state")
	_chunk_manager = _main.get_node("ChunkManager") as ChunkManager
	_colonist_manager = _main.get_node("ChunkManager/GameplayYSort/ColonistManager") as ColonistManager
	_freeze_scene()

	if not _validate_component_lifecycle():
		return
	if not _validate_existing_aggregate_paths():
		return
	if not await _validate_save_load_reconstruction():
		return
	print("R02B validation passed: Storehouse storage components, defensive snapshots, version-2 load reconstruction, and unchanged stockpile gameplay")
	quit(0)


func _validate_component_lifecycle() -> bool:
	if not _require(_world_state.get_storage_components().is_empty(), "new scene unexpectedly has storage components"):
		return false
	if not _require(bool(_world_state.add_resource("wood", 30).get("ok", false)), "could not add initial Wood"):
		return false
	if not _require(bool(_world_state.add_resource("stone", 10).get("ok", false)), "could not add initial Stone"):
		return false
	var first_origin: Vector2i = _find_valid_building_origin("storehouse", Vector2i.ZERO)
	var second_origin: Vector2i = _find_valid_building_origin("storehouse", first_origin + Vector2i(5, 0), _footprint_cells("storehouse", first_origin))
	if not _require(first_origin != INVALID_CELL and second_origin != INVALID_CELL, "could not find Storehouse origins"):
		return false

	var first_place: Dictionary = _world_state.request_place_construction("storehouse", first_origin)
	if not _require(bool(first_place.get("ok", false)), "could not place first Storehouse"):
		return false
	if not _require(_world_state.get_storage_components().is_empty(), "incomplete Storehouse created storage component"):
		return false
	var first_id: String = "storehouse:%d:%d" % [first_origin.x, first_origin.y]
	var first_progress: Dictionary = _world_state.request_progress_construction(first_id, 50.0)
	if not _require(bool(first_progress.get("completed", false)), "first Storehouse did not complete"):
		return false
	var first_components: Array[Dictionary] = _world_state.get_storage_components()
	if not _require(first_components.size() == 1, "completed Storehouse did not create exactly one component"):
		return false
	var first_component: Dictionary = first_components[0]
	var expected_capacity: int = int(BuildingDefinitionRef.get_definition("storehouse").get("storage_capacity", 0))
	if not _require(String(first_component.get("construction_site_id", "")) == first_id, "component is not linked to first site id"):
		return false
	if not _require(String(first_component.get("building_id", "")) == "storehouse", "component building id mismatch"):
		return false
	if not _require(int(first_component.get("capacity", 0)) == expected_capacity, "component capacity does not match BuildingDefinition"):
		return false
	if not _require((first_component.get("contents", {}) as Dictionary).is_empty(), "R02B component contents should start empty"):
		return false

	var storage_id: String = String(first_component.get("storage_id", ""))
	first_component["capacity"] = 1
	(first_component.get("contents", {}) as Dictionary)["wood"] = 999
	(first_component.get("occupied_cells", []) as Array).clear()
	var refetched: Dictionary = _world_state.get_storage_component(storage_id)
	if not _require(int(refetched.get("capacity", 0)) == expected_capacity, "storage component snapshot was mutable"):
		return false
	if not _require((refetched.get("contents", {}) as Dictionary).is_empty(), "storage component contents snapshot was mutable"):
		return false
	if not _require((refetched.get("occupied_cells", []) as Array).size() == _footprint_cells("storehouse", first_origin).size(), "storage component occupied cells snapshot was mutable"):
		return false

	if not _require(bool(_world_state.add_resource("wood", 30).get("ok", false)), "could not add second Storehouse Wood"):
		return false
	if not _require(bool(_world_state.add_resource("stone", 10).get("ok", false)), "could not add second Storehouse Stone"):
		return false
	var second_place: Dictionary = _world_state.request_place_construction("storehouse", second_origin)
	var second_id: String = "storehouse:%d:%d" % [second_origin.x, second_origin.y]
	var second_progress: Dictionary = _world_state.request_progress_construction(second_id, 50.0)
	if not _require(bool(second_place.get("ok", false)) and bool(second_progress.get("completed", false)), "second Storehouse did not complete"):
		return false
	var all_components: Array[Dictionary] = _world_state.get_storage_components_for_building("storehouse")
	if not _require(all_components.size() == 2, "multiple completed Storehouses did not create distinct components"):
		return false
	if not _require(_world_state.get_total_storage_component_capacity() == expected_capacity * 2, "total component capacity mismatch"):
		return false
	if not _require(_world_state.get_storage_components_for_building("campfire").is_empty(), "non-storage building returned storage components"):
		return false
	return true


func _validate_existing_aggregate_paths() -> bool:
	if not _require(bool(_world_state.add_resource("wood", 20).get("ok", false)), "could not add Wood for compatibility checks"):
		return false
	var wood_before_construction: int = _world_state.get_resource_total("wood")
	var campfire_origin: Vector2i = _find_valid_building_origin("campfire", Vector2i(10, 0))
	if not _require(campfire_origin != INVALID_CELL, "could not find Campfire origin"):
		return false
	var campfire_place: Dictionary = _world_state.request_place_construction("campfire", campfire_origin)
	var campfire_id: String = "campfire:%d:%d" % [campfire_origin.x, campfire_origin.y]
	var campfire_progress: Dictionary = _world_state.request_progress_construction(campfire_id, 10.0)
	if not _require(bool(campfire_place.get("ok", false)) and bool(campfire_progress.get("completed", false)), "Campfire construction global path failed"):
		return false
	if not _require(_world_state.get_resource_total("wood") == wood_before_construction - 5, "construction no longer consumes ResourceStockpile Wood"):
		return false

	var zone_cell: Vector2i = _find_valid_zone_cell(Vector2i(0, 8))
	var item_cell: Vector2i = _find_valid_zone_cell(zone_cell + Vector2i(3, 0), [zone_cell])
	if not _require(zone_cell != INVALID_CELL and item_cell != INVALID_CELL, "could not find haul cells"):
		return false
	var zone_result: Dictionary = _world_state.request_create_stockpile_zone([zone_cell])
	var item_result: Dictionary = _world_state.create_ground_item("wood", 5, item_cell)
	if not _require(bool(zone_result.get("ok", false)) and bool(item_result.get("ok", false)), "could not create haul fixture"):
		return false
	var item_id: String = String(item_result.get("item_id", ""))
	var reserve_result: Dictionary = _world_state.reserve_haul_item(item_id, "r02b_validator")
	var pickup_result: Dictionary = _world_state.request_pickup_ground_item(item_id, "r02b_validator")
	var destination: Vector2i = reserve_result.get("destination_cell", Vector2i.ZERO)
	var wood_before_deposit: int = _world_state.get_resource_total("wood")
	var deposit_result: Dictionary = _world_state.request_deposit_carried_item("r02b_validator", pickup_result.get("item", {}), destination)
	if not _require(bool(reserve_result.get("ok", false)) and bool(pickup_result.get("ok", false)) and bool(deposit_result.get("ok", false)), "haul compatibility path failed"):
		return false
	if not _require(_world_state.get_resource_total("wood") == wood_before_deposit + 5, "haul deposit no longer updates aggregate Wood"):
		return false
	var component_after_deposit: Dictionary = _world_state.get_storage_component(String(reserve_result.get("storage_id", "")))
	if not _require(int((component_after_deposit.get("contents", {}) as Dictionary).get("wood", 0)) == 5, "haul deposit did not write Storehouse component contents"):
		return false
	return true


func _validate_save_load_reconstruction() -> bool:
	var save_service := SaveGameServiceRef.new()
	var source_save: Dictionary = save_service.build_save_data(_main.get_node("WorldGenerator"), _world_state, _chunk_manager, _colonist_manager)
	if not _require(int(source_save.get("version", -1)) == 2, "R02B changed save version"):
		return false
	if not _require(not source_save.has("storage_components") and not (source_save.get("deltas", {}) as Dictionary).has("storage_components"), "R02B wrote storage components into save data"):
		return false

	var target: Node = MainScene.instantiate()
	root.add_child(target)
	await _wait_frames(20)
	var target_world_state: Node = target.get("_world_state")
	var target_chunk_manager: ChunkManager = target.get_node("ChunkManager") as ChunkManager
	var target_colonist_manager: ColonistManager = target.get_node("ChunkManager/GameplayYSort/ColonistManager") as ColonistManager
	target.set_process(false)
	target_chunk_manager.set_process(false)
	for child: Node in target_colonist_manager.get_children():
		if child is Colonist:
			child.set_process(false)

	var load_result: Dictionary = save_service.apply_save_data(
		source_save,
		target.get_node("WorldGenerator"),
		target_world_state,
		target_chunk_manager,
		target_colonist_manager
	)
	if not _require(bool(load_result.get("ok", false)), "save load failed: %s" % String(load_result.get("reason", "unknown"))):
		return false
	var source_components: Array[Dictionary] = _world_state.get_storage_components()
	var target_components: Array[Dictionary] = target_world_state.get_storage_components()
	if not _require(target_components.size() == source_components.size(), "load did not reconstruct storage components from construction records"):
		return false
	if not _require(target_world_state.get_total_storage_component_capacity() == _world_state.get_total_storage_component_capacity(), "loaded storage component capacity mismatch"):
		return false
	return true


func _freeze_scene() -> void:
	_main.set_process(false)
	_chunk_manager.set_process(false)
	for child: Node in _colonist_manager.get_children():
		if child is Colonist:
			child.set_process(false)


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _find_valid_building_origin(building_id: String, origin: Vector2i, excluded: Array[Vector2i] = []) -> Vector2i:
	for radius in range(80):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := origin + Vector2i(x, y)
				if _footprint_overlaps(candidate, BuildingDefinitionRef.get_definition(building_id).get("footprint", Vector2i.ONE), excluded):
					continue
				if bool(_world_state.validate_construction_placement(building_id, candidate).get("ok", false)):
					return candidate
	return INVALID_CELL

func _footprint_cells(building_id: String, origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var footprint: Vector2i = BuildingDefinitionRef.get_definition(building_id).get("footprint", Vector2i.ONE)
	for y in range(footprint.y):
		for x in range(footprint.x):
			cells.append(origin + Vector2i(x, y))
	return cells


func _footprint_overlaps(origin: Vector2i, footprint: Vector2i, excluded: Array[Vector2i]) -> bool:
	for y in range(footprint.y):
		for x in range(footprint.x):
			if origin + Vector2i(x, y) in excluded:
				return true
	return false


func _find_valid_zone_cell(origin: Vector2i, excluded: Array[Vector2i] = []) -> Vector2i:
	for radius in range(80):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var cell := origin + Vector2i(x, y)
				if cell in excluded or _world_state.is_cell_in_stockpile_zone(cell):
					continue
				if not _chunk_manager.is_cell_loaded(cell):
					continue
				var tile: Dictionary = _chunk_manager.get_effective_tile_info(cell)
				var terrain: String = String(tile.get("terrain", ""))
				if bool(tile.get("walkable", false)) and terrain != "WATER" and terrain != "ROCK_WALL" and not bool(tile.get("mineable", false)) and _world_state.get_construction_site_at_cell(cell).is_empty() and not _chunk_manager.is_cell_blocked_by_resource(cell):
					return cell
	return INVALID_CELL
