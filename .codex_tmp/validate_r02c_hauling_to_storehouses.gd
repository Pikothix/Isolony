extends SceneTree

## Purpose: Validate R02C Storehouse-backed hauling.
## Responsibility: Exercise storage-component destination selection, capacity reservation, deposit, aggregate reads, cleanup, save exclusions, and legacy zone fallback.
## Assumption: Direct WorldState calls are used to isolate the simulation contract from colonist timing.

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
	push_error("R02C hauling validation failed: %s" % message)
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
	_freeze_scene(_main, _chunk_manager, _colonist_manager)

	if not _validate_storehouse_hauling():
		return
	if not _validate_capacity_cleanup_and_save_boundary():
		return
	if not await _validate_legacy_zone_fallback():
		return
	print("R02C validation passed: Storehouse hauling, component capacity, aggregate totals, cleanup, save boundary, and legacy fallback")
	quit(0)


func _validate_storehouse_hauling() -> bool:
	var first_origin: Vector2i = _complete_storehouse(Vector2i.ZERO)
	var second_origin: Vector2i = _complete_storehouse(first_origin + Vector2i(8, 0), _footprint_cells("storehouse", first_origin))
	if not _require(first_origin != INVALID_CELL and second_origin != INVALID_CELL, "could not complete two Storehouses"):
		return false
	var components: Array[Dictionary] = _world_state.get_storage_components()
	if not _require(components.size() == 2, "completed Storehouses did not expose two components"):
		return false

	var item_cell: Vector2i = _find_valid_item_cell(second_origin + Vector2i(0, 4))
	if not _require(item_cell != INVALID_CELL, "could not find item cell near second Storehouse"):
		return false
	var item_result: Dictionary = _world_state.create_ground_item("wood", 6, item_cell)
	if not _require(bool(item_result.get("ok", false)), "could not create Storehouse haul item"):
		return false
	var item_id: String = String(item_result.get("item_id", ""))
	var aggregate_before: int = _world_state.get_resource_total("wood")
	var reserve_result: Dictionary = _world_state.reserve_haul_item(item_id, "r02c_worker")
	if not _require(bool(reserve_result.get("ok", false)), "Storehouse haul reservation failed: %s" % String(reserve_result.get("reason", "unknown"))):
		return false
	if not _require(String(reserve_result.get("destination_kind", "")) == "storage_component", "haul did not prefer Storehouse storage"):
		return false
	var storage_id: String = String(reserve_result.get("storage_id", ""))
	var summary: Dictionary = _world_state.get_storage_component_reservation_summary(storage_id)
	if not _require(int(summary.get("reserved", 0)) == 6 and int(summary.get("count", 0)) == 1, "Storehouse capacity was not reserved against the component"):
		return false
	var pickup_result: Dictionary = _world_state.request_pickup_ground_item(item_id, "r02c_worker")
	if not _require(bool(pickup_result.get("ok", false)) and _get_item(item_id).is_empty(), "pickup did not remove ground item"):
		return false
	var deposit_result: Dictionary = _world_state.request_deposit_carried_item("r02c_worker", pickup_result.get("item", {}), reserve_result.get("destination_cell", Vector2i.ZERO))
	if not _require(bool(deposit_result.get("ok", false)), "Storehouse deposit failed: %s" % String(deposit_result.get("reason", "unknown"))):
		return false
	var component: Dictionary = _world_state.get_storage_component(storage_id)
	if not _require(int((component.get("contents", {}) as Dictionary).get("wood", 0)) == 6, "Storehouse contents did not increase after deposit"):
		return false
	if not _require(_get_item(item_id).is_empty(), "ground item survived deposit"):
		return false
	if not _require(_world_state.get_resource_total("wood") == aggregate_before + 6, "aggregate get_resource_total did not include Storehouse contents"):
		return false
	if not _require(_world_state.get_resource_stockpile().get_total("wood") == aggregate_before, "Storehouse deposit also wrote ResourceStockpile"):
		return false

	var near_second_cell: Vector2i = _find_valid_item_cell(item_cell + Vector2i(1, 0), [item_cell])
	if not _require(near_second_cell != INVALID_CELL, "could not find deterministic destination item cell"):
		return false
	var near_second_item: Dictionary = _world_state.create_ground_item("stone", 2, near_second_cell)
	if not _require(bool(near_second_item.get("ok", false)), "could not create deterministic destination item"):
		return false
	var deterministic_reserve: Dictionary = _world_state.reserve_haul_item(String(near_second_item.get("item_id", "")), "r02c_worker_2")
	if not _require(bool(deterministic_reserve.get("ok", false)), "deterministic Storehouse reserve failed"):
		return false
	if not _require(String(deterministic_reserve.get("storage_id", "")) == storage_id, "nearest reachable Storehouse destination was not deterministic"):
		return false
	_world_state.release_haul_item(String(near_second_item.get("item_id", "")), "r02c_worker_2", "r02c_done")
	return true


func _validate_capacity_cleanup_and_save_boundary() -> bool:
	var storage_id: String = String(_world_state.get_storage_components()[0].get("storage_id", ""))
	var free_capacity: int = int(_world_state.get_storage_component(storage_id).get("available", 0))
	if not _require(free_capacity > 0, "no free capacity for cleanup test"):
		return false
	var item_cell: Vector2i = _find_valid_item_cell(Vector2i(12, 12))
	var cleanup_item: Dictionary = _world_state.create_ground_item("stone", 3, item_cell)
	if not _require(bool(cleanup_item.get("ok", false)), "could not create cleanup item"):
		return false
	var cleanup_id: String = String(cleanup_item.get("item_id", ""))
	var cleanup_reserve: Dictionary = _world_state.reserve_haul_item(cleanup_id, "r02c_cleanup")
	var cleanup_storage_id: String = String(cleanup_reserve.get("storage_id", ""))
	if not _require(bool(cleanup_reserve.get("ok", false)) and int(_world_state.get_storage_component_reservation_summary(cleanup_storage_id).get("reserved", 0)) >= 3, "cleanup reservation was not stored on component"):
		return false
	_world_state.release_haul_item(cleanup_id, "r02c_cleanup", "validation_cleanup")
	if not _require(int(_world_state.get_storage_component_reservation_summary(cleanup_storage_id).get("reserved", 0)) == 0, "release did not clear component capacity reservation"):
		return false

	var full_origin: Vector2i = _complete_storehouse(Vector2i(24, 0))
	if not _require(full_origin != INVALID_CELL, "could not complete full-capacity Storehouse"):
		return false
	var fill_cell: Vector2i = _find_valid_item_cell(full_origin + Vector2i(0, 4))
	if not _require(fill_cell != INVALID_CELL, "could not find Storehouse fill item cell"):
		return false
	var fill_item: Dictionary = _world_state.create_ground_item("food", 100, fill_cell)
	var fill_reserve: Dictionary = _world_state.reserve_haul_item(String(fill_item.get("item_id", "")), "r02c_fill")
	var full_storage_id: String = String(fill_reserve.get("storage_id", ""))
	var fill_pickup: Dictionary = _world_state.request_pickup_ground_item(String(fill_item.get("item_id", "")), "r02c_fill")
	var fill_deposit: Dictionary = _world_state.request_deposit_carried_item("r02c_fill", fill_pickup.get("item", {}), fill_reserve.get("destination_cell", Vector2i.ZERO))
	if not _require(bool(fill_item.get("ok", false)) and bool(fill_reserve.get("ok", false)) and bool(fill_pickup.get("ok", false)) and bool(fill_deposit.get("ok", false)), "could not fill Storehouse component"):
		return false
	if not _require(int(_world_state.get_storage_component(full_storage_id).get("available", -1)) == 0, "filled Storehouse still reports capacity"):
		return false
	var too_large_cell: Vector2i = _find_valid_item_cell(fill_cell + Vector2i(1, 0), [fill_cell])
	if not _require(too_large_cell != INVALID_CELL, "could not find over-capacity item cell"):
		return false
	var too_large_item: Dictionary = _world_state.create_ground_item("food", 101, too_large_cell)
	var too_large_reserve: Dictionary = _world_state.reserve_haul_item(String(too_large_item.get("item_id", "")), "r02c_over_capacity")
	if not _require(not bool(too_large_reserve.get("ok", false)), "over-capacity item was accepted by Storehouse storage"):
		return false

	var save_service := SaveGameServiceRef.new()
	var save_data: Dictionary = save_service.build_save_data(_main.get_node("WorldGenerator"), _world_state, _chunk_manager, _colonist_manager)
	if not _require(int(save_data.get("version", -1)) == 2, "R02C changed save version"):
		return false
	if not _require(not _contains_key_recursive(save_data, "storage_component_reservations") and not _contains_key_recursive(save_data, "storage_reservation_id"), "save exported transient haul reservation data"):
		return false
	if not _require(_contains_key_recursive(save_data, "storage_contents"), "save did not persist Storehouse contents"):
		return false
	return true


func _validate_legacy_zone_fallback() -> bool:
	var legacy_main: Node = MainScene.instantiate()
	root.add_child(legacy_main)
	await _wait_frames(160)
	var legacy_world_state: Node = legacy_main.get("_world_state")
	var legacy_chunk_manager: ChunkManager = legacy_main.get_node("ChunkManager") as ChunkManager
	var legacy_colonist_manager: ColonistManager = legacy_main.get_node("ChunkManager/GameplayYSort/ColonistManager") as ColonistManager
	_freeze_scene(legacy_main, legacy_chunk_manager, legacy_colonist_manager)
	var zone_cell: Vector2i = _find_valid_item_cell_for(legacy_world_state, legacy_chunk_manager, Vector2i.ZERO)
	var item_cell: Vector2i = _find_valid_item_cell_for(legacy_world_state, legacy_chunk_manager, zone_cell + Vector2i(3, 0), [zone_cell])
	if not _require(zone_cell != INVALID_CELL and item_cell != INVALID_CELL, "could not find legacy fallback cells"):
		return false
	var zone_result: Dictionary = legacy_world_state.request_create_stockpile_zone([zone_cell])
	var item_result: Dictionary = legacy_world_state.create_ground_item("wood", 5, item_cell)
	if not _require(bool(zone_result.get("ok", false)) and bool(item_result.get("ok", false)), "could not create legacy fallback fixture"):
		return false
	var reserve_result: Dictionary = legacy_world_state.reserve_haul_item(String(item_result.get("item_id", "")), "legacy_worker")
	if not _require(bool(reserve_result.get("ok", false)) and String(reserve_result.get("destination_kind", "")) == "legacy_stockpile_zone", "legacy stockpile-zone fallback was not used without Storehouse"):
		return false
	var pickup_result: Dictionary = legacy_world_state.request_pickup_ground_item(String(item_result.get("item_id", "")), "legacy_worker")
	var deposit_result: Dictionary = legacy_world_state.request_deposit_carried_item("legacy_worker", pickup_result.get("item", {}), reserve_result.get("destination_cell", Vector2i.ZERO))
	if not _require(bool(deposit_result.get("ok", false)), "legacy stockpile-zone deposit failed"):
		return false
	if not _require(legacy_world_state.get_resource_total("wood") == 5 and legacy_world_state.get_storage_components().is_empty(), "legacy fallback duplicated resources into storage components"):
		return false
	return true


func _complete_storehouse(origin_hint: Vector2i, excluded: Array[Vector2i] = []) -> Vector2i:
	var origin: Vector2i = _find_valid_building_origin("storehouse", origin_hint, excluded)
	if origin == INVALID_CELL:
		return INVALID_CELL
	if not bool(_world_state.add_resource("wood", 30).get("ok", false)):
		return INVALID_CELL
	if not bool(_world_state.add_resource("stone", 10).get("ok", false)):
		return INVALID_CELL
	var place: Dictionary = _world_state.request_place_construction("storehouse", origin)
	var site_id: String = "storehouse:%d:%d" % [origin.x, origin.y]
	var progress: Dictionary = _world_state.request_progress_construction(site_id, 50.0)
	return origin if bool(place.get("ok", false)) and bool(progress.get("completed", false)) else INVALID_CELL


func _freeze_scene(main: Node, chunk_manager: ChunkManager, colonist_manager: ColonistManager) -> void:
	main.set_process(false)
	chunk_manager.set_process(false)
	for child: Node in colonist_manager.get_children():
		if child is Colonist:
			child.set_process(false)


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _get_item(item_id: String) -> Dictionary:
	for item: Dictionary in _world_state.get_ground_items():
		if String(item.get("item_id", "")) == item_id:
			return item
	return {}


func _find_valid_building_origin(building_id: String, origin: Vector2i, excluded: Array[Vector2i] = []) -> Vector2i:
	for radius in range(96):
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


func _find_valid_item_cell(origin: Vector2i, excluded: Array[Vector2i] = []) -> Vector2i:
	return _find_valid_item_cell_for(_world_state, _chunk_manager, origin, excluded)


func _find_valid_item_cell_for(world_state: Node, chunk_manager: ChunkManager, origin: Vector2i, excluded: Array[Vector2i] = []) -> Vector2i:
	for radius in range(96):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var cell := origin + Vector2i(x, y)
				if cell in excluded or not chunk_manager.is_cell_loaded(cell):
					continue
				var tile: Dictionary = chunk_manager.get_effective_tile_info(cell)
				var terrain: String = String(tile.get("terrain", ""))
				if bool(tile.get("walkable", false)) and terrain != "WATER" and terrain != "ROCK_WALL" and not bool(tile.get("mineable", false)) and world_state.get_construction_site_at_cell(cell).is_empty() and not world_state.is_cell_in_stockpile_zone(cell) and not chunk_manager.is_cell_blocked_by_resource(cell):
					return cell
	return INVALID_CELL


func _contains_key_recursive(value: Variant, key_name: String) -> bool:
	if value is Dictionary:
		for key: Variant in (value as Dictionary).keys():
			if String(key) == key_name:
				return true
			if _contains_key_recursive((value as Dictionary)[key], key_name):
				return true
	elif value is Array:
		for entry: Variant in value:
			if _contains_key_recursive(entry, key_name):
				return true
	return false
