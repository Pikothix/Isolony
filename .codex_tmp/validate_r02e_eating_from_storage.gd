extends SceneTree

## Purpose: Validate Storehouse-backed eating with no-storage legacy bootstrap compatibility.
## Responsibility: Exercise atomic Food consumption, unchanged hunger behavior, aggregate reads, and save exclusions.
## Assumption: Eating remains abstract and does not path to the selected storage component.

const MainScene = preload("res://scenes/Main.tscn")
const WorldStateScript = preload("res://scripts/simulation/world_state.gd")
const SaveGameServiceRef = preload("res://scripts/simulation/save_game_service.gd")

const INVALID_CELL := Vector2i(2147483647, 2147483647)

var _failed: bool = false
var _main: Node
var _world_state: Node
var _chunk_manager: ChunkManager
var _colonist_manager: ColonistManager
var _worker: Colonist


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("R02E eating storage validation failed: %s" % message)
	quit(1)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _run() -> void:
	_main = MainScene.instantiate()
	root.add_child(_main)
	for _frame in range(160):
		await process_frame
	_world_state = _main.get("_world_state")
	_chunk_manager = _main.get_node("ChunkManager") as ChunkManager
	_colonist_manager = _main.get_node("ChunkManager/GameplayYSort/ColonistManager") as ColonistManager
	_freeze_scene()
	var colonists: Array[Colonist] = _get_colonists()
	if not _require(not colonists.is_empty(), "Main scene did not spawn a colonist"):
		return
	_worker = colonists[0]

	if not _require(bool(_world_state.add_resource("food", 2).get("ok", false)), "could not seed legacy Food"):
		return
	var legacy_food: int = _world_state.get_resource_stockpile().get_total("food")
	var storehouse_origin: Vector2i = _complete_storehouse(Vector2i.ZERO)
	if not _require(storehouse_origin != INVALID_CELL, "could not complete Storehouse fixture"):
		return
	var components: Array[Dictionary] = _world_state.get_storage_components()
	if not _require(components.size() == 1, "Storehouse component was not created"):
		return
	var storage_id: String = String(components[0].get("storage_id", ""))
	if not _deposit_to_storage(storage_id, "food", 3):
		return
	var aggregate_before: int = _world_state.get_resource_total("food")
	if not _require(aggregate_before == legacy_food + 3, "aggregate Food did not include Storehouse contents"):
		return

	_prepare_worker_to_eat()
	_worker._process_idle(0.0)
	var component_after_bite: Dictionary = _world_state.get_storage_component(storage_id)
	if not _require(_worker.get_activity_name() == "eating" and is_equal_approx(_worker.hunger, 35.0), "colonist eating flow did not restore Hunger as before"):
		return
	if not _require(int((component_after_bite.get("contents", {}) as Dictionary).get("food", 0)) == 2, "Storehouse Food did not decrease by exactly one"):
		return
	if not _require(_world_state.get_resource_stockpile().get_total("food") == legacy_food and _world_state.get_resource_total("food") == aggregate_before - 1, "Storehouse eating changed legacy Food or aggregate totals incorrectly"):
		return

	var colonist_export: Dictionary = _worker.export_state()
	var save_service := SaveGameServiceRef.new()
	var save_data: Dictionary = save_service.build_save_data(_main.get_node("WorldGenerator"), _world_state, _chunk_manager, _colonist_manager)
	for forbidden_key: String in ["activity", "eating_timer"]:
		if not _require(not _contains_key_recursive(colonist_export, forbidden_key) and not _contains_key_recursive(save_data, forbidden_key), "save/export persisted transient %s" % forbidden_key):
			return

	var before_atomic_failure: int = _world_state.get_resource_total("food")
	var atomic_failure: Dictionary = _world_state.request_consume_food("r02e_atomic", 3)
	if not _require(not bool(atomic_failure.get("ok", false)) and _world_state.get_resource_total("food") == before_atomic_failure, "insufficient Storehouse Food was partially consumed"):
		return
	if not _require(_world_state.get_resource_stockpile().get_total("food") == legacy_food, "failed Storehouse consumption used legacy Food"):
		return

	var drain: Dictionary = _world_state.request_consume_food("r02e_drain", 2)
	if not _require(bool(drain.get("ok", false)) and _world_state.get_resource_total("food") == legacy_food, "could not consume remaining Storehouse Food"):
		return
	_prepare_worker_to_eat()
	_worker._process_idle(0.0)
	if not _require(not is_equal_approx(_worker.hunger, 35.0) and _world_state.get_resource_stockpile().get_total("food") == legacy_food, "empty Storehouse incorrectly fell back to legacy Food"):
		return

	if not _validate_no_storage_legacy_fallback():
		return
	print("R02E validation passed: Storehouse Food eating, atomic failure, legacy isolation/fallback, Hunger, aggregate totals, and save exclusion")
	quit(0)


func _prepare_worker_to_eat() -> void:
	_worker.set_work_priority("Construct", 0)
	_worker.set_work_priority("Harvest", 0)
	_worker.set_work_priority("Haul", 0)
	_worker.rest = 100.0
	_worker.warmth = 100.0
	_worker.shelter = 100.0
	_worker.hunger = 10.0
	_worker._enter_idle()
	_worker.set("_pause_timer", 0.0)


func _validate_no_storage_legacy_fallback() -> bool:
	var legacy_world_state: Node = WorldStateScript.new()
	root.add_child(legacy_world_state)
	if not _require(legacy_world_state.get_storage_components().is_empty(), "legacy fallback fixture unexpectedly has storage"):
		return false
	if not _require(bool(legacy_world_state.add_resource("food", 2).get("ok", false)), "could not seed fallback Food"):
		return false
	var result: Dictionary = legacy_world_state.request_consume_food("r02e_legacy", 1)
	return _require(bool(result.get("ok", false)) and legacy_world_state.get_resource_total("food") == 1, "no-storage legacy Food fallback failed")


func _complete_storehouse(origin_hint: Vector2i) -> Vector2i:
	var origin: Vector2i = _find_valid_building_origin("storehouse", origin_hint)
	if origin == INVALID_CELL:
		return INVALID_CELL
	if not bool(_world_state.add_resource("wood", 30).get("ok", false)) or not bool(_world_state.add_resource("stone", 10).get("ok", false)):
		return INVALID_CELL
	var placement: Dictionary = _world_state.request_place_construction("storehouse", origin)
	var site_id := "storehouse:%d:%d" % [origin.x, origin.y]
	var progress: Dictionary = _world_state.request_progress_construction(site_id, 50.0)
	return origin if bool(placement.get("ok", false)) and bool(progress.get("completed", false)) else INVALID_CELL


func _deposit_to_storage(storage_id: String, resource_type: String, amount: int) -> bool:
	var component: Dictionary = _world_state.get_storage_component(storage_id)
	var item_cell: Vector2i = _find_storage_access_cell(component)
	if not _require(item_cell != INVALID_CELL, "could not find Storehouse access cell"):
		return false
	var item_result: Dictionary = _world_state.create_ground_item(resource_type, amount, item_cell)
	if not _require(bool(item_result.get("ok", false)), "could not create Food ground item"):
		return false
	var item_id: String = String(item_result.get("item_id", ""))
	var reservation: Dictionary = _world_state.reserve_haul_item(item_id, "r02e_seed")
	var pickup: Dictionary = _world_state.request_pickup_ground_item(item_id, "r02e_seed")
	var deposit: Dictionary = _world_state.request_deposit_carried_item("r02e_seed", pickup.get("item", {}), reservation.get("destination_cell", Vector2i.ZERO))
	return _require(bool(reservation.get("ok", false)) and String(reservation.get("storage_id", "")) == storage_id and bool(pickup.get("ok", false)) and bool(deposit.get("ok", false)), "could not haul Food into Storehouse")


func _find_storage_access_cell(component: Dictionary) -> Vector2i:
	var occupied: Array = component.get("occupied_cells", [])
	for occupied_cell: Vector2i in occupied:
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var cell: Vector2i = occupied_cell + offset
			if occupied.has(cell) or not _chunk_manager.is_cell_loaded(cell):
				continue
			var tile: Dictionary = _chunk_manager.get_effective_tile_info(cell)
			var terrain: String = String(tile.get("terrain", ""))
			if bool(tile.get("walkable", false)) and terrain != "WATER" and terrain != "ROCK_WALL" and not bool(tile.get("mineable", false)) and _world_state.get_construction_site_at_cell(cell).is_empty():
				return cell
	return INVALID_CELL


func _find_valid_building_origin(building_id: String, hint: Vector2i) -> Vector2i:
	for radius in range(64):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := hint + Vector2i(x, y)
				if bool(_world_state.validate_construction_placement(building_id, candidate).get("ok", false)):
					return candidate
	return INVALID_CELL


func _get_colonists() -> Array[Colonist]:
	var colonists: Array[Colonist] = []
	for child: Node in _colonist_manager.get_children():
		if child is Colonist and not child.is_queued_for_deletion():
			colonists.append(child as Colonist)
	colonists.sort_custom(func(first: Colonist, second: Colonist) -> bool:
		return first.colonist_id < second.colonist_id
	)
	return colonists


func _freeze_scene() -> void:
	_main.set_process(false)
	_chunk_manager.set_process(false)
	_colonist_manager.set_process(false)
	for child: Node in _colonist_manager.get_children():
		if child is Colonist:
			child.set_process(false)


func _contains_key_recursive(value: Variant, target_key: String) -> bool:
	if value is Dictionary:
		for key: Variant in (value as Dictionary).keys():
			if String(key) == target_key or _contains_key_recursive((value as Dictionary)[key], target_key):
				return true
	elif value is Array:
		for entry: Variant in value:
			if _contains_key_recursive(entry, target_key):
				return true
	return false
