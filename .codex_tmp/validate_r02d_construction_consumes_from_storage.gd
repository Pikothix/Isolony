extends SceneTree

## Purpose: Validate construction material reservation and consumption from Storehouse components.
## Responsibility: Exercise WorldState allocation, release, consume-once, completion, and save exclusions.
## Assumption: Direct unowned progress is used only to bootstrap completed Storehouses for this fixture.

const MainScene = preload("res://scenes/Main.tscn")
const SaveGameServiceRef = preload("res://scripts/simulation/save_game_service.gd")

const INVALID_CELL := Vector2i(2147483647, 2147483647)

var _failed: bool = false
var _main: Node
var _world_state: Node
var _chunk_manager: ChunkManager
var _colonist_manager: ColonistManager


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("R02D construction storage validation failed: %s" % message)
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

	var first_origin: Vector2i = _complete_first_storehouse_by_worker(Vector2i.ZERO)
	var second_origin: Vector2i = _complete_storehouse(first_origin + Vector2i(10, 0), _footprint_cells("storehouse", first_origin))
	if not _require(first_origin != INVALID_CELL and second_origin != INVALID_CELL, "could not bootstrap two Storehouses"):
		return
	var components: Array[Dictionary] = _world_state.get_storage_components()
	if not _require(components.size() == 2, "Storehouse components were not created"):
		return
	var first_storage_id: String = String(components[0].get("storage_id", ""))
	var second_storage_id: String = String(components[1].get("storage_id", ""))
	if not _require(bool(_world_state.add_resource("wood", 5).get("ok", false)), "could not seed legacy post-bootstrap Wood"):
		return
	var legacy_wood_after_bootstrap: int = _world_state.get_resource_stockpile().get_total("wood")

	var campfire_origin: Vector2i = _find_valid_building_origin("campfire", second_origin + Vector2i(8, 0))
	if not _require(campfire_origin != INVALID_CELL, "could not place Campfire fixture"):
		return
	var place_result: Dictionary = _world_state.request_place_construction("campfire", campfire_origin)
	var site_id := "campfire:%d:%d" % [campfire_origin.x, campfire_origin.y]
	if not _require(bool(place_result.get("ok", false)), "Campfire placement failed"):
		return
	if not _require(not bool(_world_state.reserve_construction_site("r02d_worker", site_id).get("ok", false)), "construction reserved without Storehouse materials"):
		return
	if not _require(_world_state.get_resource_stockpile().get_total("wood") == legacy_wood_after_bootstrap, "failed Storehouse-backed reservation changed legacy resources"):
		return

	if not _deposit_to_storage(first_storage_id, "wood", 3, "r02d_seed_first"):
		return
	if not _deposit_to_storage(second_storage_id, "wood", 2, "r02d_seed_second"):
		return
	if not _require(_world_state.get_available_storage_resource_total("wood") == 5, "Storehouse Wood availability did not include both components"):
		return
	var aggregate_before: int = _world_state.get_resource_total("wood")

	var first_reservation: Dictionary = _world_state.reserve_construction_site("r02d_worker", site_id)
	if not _require(bool(first_reservation.get("ok", false)), "construction could not reserve Storehouse materials"):
		return
	var summary: Dictionary = _world_state.get_construction_material_reservation_summary(site_id)
	var allocations: Array = summary.get("allocations", [])
	if not _require(allocations.size() == 2 and _sum_allocations(allocations, "wood") == 5, "construction cost was not split across two Storehouses"):
		return
	for allocation_value: Variant in allocations:
		var allocation: Dictionary = allocation_value
		if not _require(String(allocation.get("construction_site_id", "")) == site_id and not String(allocation.get("storage_id", "")).is_empty() and String(allocation.get("resource_type", "")) == "wood" and int(allocation.get("amount", 0)) > 0, "construction allocation record is incomplete"):
			return
	if not _require(_world_state.get_available_storage_resource_total("wood") == 0 and _world_state.get_resource_total("wood") == aggregate_before, "reservation did not reduce availability without consuming resources"):
		return

	var release_result: Dictionary = _world_state.release_construction_reservation(site_id, "r02d_worker", "r02d_abandon")
	if not _require(bool(release_result.get("ok", false)) and _world_state.get_available_storage_resource_total("wood") == 5, "abandoning construction did not release materials"):
		return
	if not _require(_world_state.get_resource_total("wood") == aggregate_before, "abandoning construction changed physical resources"):
		return

	if not _require(bool(_world_state.reserve_construction_site("r02d_worker", site_id).get("ok", false)), "construction could not reserve after release"):
		return
	var first_progress: Dictionary = _world_state.request_progress_construction(site_id, 1.0, "r02d_worker")
	if not _require(bool(first_progress.get("ok", false)) and bool(first_progress.get("resources_consumed", false)), "first construction progress did not consume reserved materials"):
		return
	if not _require(_world_state.get_resource_total("wood") == aggregate_before - 5 and _world_state.get_construction_material_reservation_summary(site_id).get("count", -1) == 0, "first progress did not consume exactly the reservation"):
		return
	if not _require(_world_state.get_resource_stockpile().get_total("wood") == legacy_wood_after_bootstrap, "Storehouse construction consumed legacy Wood after bootstrap"):
		return
	var total_after_first_progress: int = _world_state.get_resource_total("wood")
	var second_progress: Dictionary = _world_state.request_progress_construction(site_id, 1.0, "r02d_worker")
	if not _require(bool(second_progress.get("ok", false)) and _world_state.get_resource_total("wood") == total_after_first_progress, "later progress consumed construction materials again"):
		return
	var completion: Dictionary = _world_state.request_progress_construction(site_id, 100.0, "r02d_worker")
	if not _require(bool(completion.get("completed", false)) and bool(_world_state.get_construction_site(site_id).get("resources_consumed", false)), "construction did not complete after Storehouse consumption"):
		return

	if not _deposit_to_storage(first_storage_id, "wood", 5, "r02d_save_seed"):
		return
	var save_origin: Vector2i = _find_valid_building_origin("campfire", campfire_origin + Vector2i(4, 0))
	var save_site_id := "campfire:%d:%d" % [save_origin.x, save_origin.y]
	if not _require(save_origin != INVALID_CELL and bool(_world_state.request_place_construction("campfire", save_origin).get("ok", false)), "could not place save-boundary construction"):
		return
	if not _require(bool(_world_state.reserve_construction_site("r02d_save_worker", save_site_id).get("ok", false)), "could not create save-boundary material reservation"):
		return
	if not _require(int(_world_state.get_construction_material_reservation_summary(save_site_id).get("count", 0)) > 0, "save-boundary reservation was not present before export"):
		return
	var save_service := SaveGameServiceRef.new()
	var save_data: Dictionary = save_service.build_save_data(_main.get_node("WorldGenerator"), _world_state, _chunk_manager, _colonist_manager)
	if not _require(not _contains_key_recursive(save_data, "construction_material_reservations"), "save persisted transient construction material reservations"):
		return
	var saved_completed_site: Dictionary = _find_saved_construction_site(save_data, site_id)
	if not _require(bool(saved_completed_site.get("completed", false)) and bool(saved_completed_site.get("resources_consumed", false)), "save did not retain completed consumed construction state"):
		return

	print("R02D validation passed: multi-Storehouse reservation, release, consume-once, completion, aggregate totals, and save exclusion")
	quit(0)


func _complete_storehouse(origin_hint: Vector2i, excluded: Array[Vector2i] = []) -> Vector2i:
	var origin: Vector2i = _find_valid_building_origin("storehouse", origin_hint, excluded)
	if origin == INVALID_CELL:
		return INVALID_CELL
	if not bool(_world_state.add_resource("wood", 30).get("ok", false)) or not bool(_world_state.add_resource("stone", 10).get("ok", false)):
		return INVALID_CELL
	var placement: Dictionary = _world_state.request_place_construction("storehouse", origin)
	var site_id := "storehouse:%d:%d" % [origin.x, origin.y]
	var progress: Dictionary = _world_state.request_progress_construction(site_id, 50.0)
	return origin if bool(placement.get("ok", false)) and bool(progress.get("completed", false)) else INVALID_CELL


func _complete_first_storehouse_by_worker(origin_hint: Vector2i) -> Vector2i:
	if not _require(_world_state.get_storage_components().is_empty(), "bootstrap fixture already had storage"):
		return INVALID_CELL
	var origin: Vector2i = _find_valid_building_origin("storehouse", origin_hint)
	if origin == INVALID_CELL:
		return INVALID_CELL
	if not bool(_world_state.add_resource("wood", 30).get("ok", false)) or not bool(_world_state.add_resource("stone", 10).get("ok", false)):
		return INVALID_CELL
	var wood_before: int = _world_state.get_resource_stockpile().get_total("wood")
	var stone_before: int = _world_state.get_resource_stockpile().get_total("stone")
	var placement: Dictionary = _world_state.request_place_construction("storehouse", origin)
	var site_id := "storehouse:%d:%d" % [origin.x, origin.y]
	var reservation: Dictionary = _world_state.reserve_construction_site("r02d_bootstrap_worker", site_id)
	var reservation_id := "construction:%s" % site_id
	if not _require(bool(placement.get("ok", false)) and bool(reservation.get("ok", false)), "worker could not reserve first Storehouse from legacy resources"):
		return INVALID_CELL
	if not _require(_world_state.get_resource_stockpile().has_resource_reservation(reservation_id) and _world_state.get_construction_material_reservation_summary(site_id).get("count", -1) == 0, "first Storehouse did not use legacy bootstrap reservation"):
		return INVALID_CELL
	var progress: Dictionary = _world_state.request_progress_construction(site_id, 50.0, "r02d_bootstrap_worker")
	if not _require(bool(progress.get("completed", false)), "worker could not complete first Storehouse"):
		return INVALID_CELL
	if not _require(_world_state.get_resource_stockpile().get_total("wood") == wood_before - 30 and _world_state.get_resource_stockpile().get_total("stone") == stone_before - 10, "bootstrap construction did not consume exact legacy cost"):
		return INVALID_CELL
	if not _require(not _world_state.get_resource_stockpile().has_resource_reservation(reservation_id) and _world_state.get_storage_components().size() == 1, "bootstrap completion left a reservation or failed to create storage"):
		return INVALID_CELL
	return origin


func _deposit_to_storage(storage_id: String, resource_type: String, amount: int, worker_id: String) -> bool:
	var component: Dictionary = _world_state.get_storage_component(storage_id)
	var item_cell: Vector2i = _find_storage_access_cell(component)
	if not _require(item_cell != INVALID_CELL, "could not find access cell for %s" % storage_id):
		return false
	var item_result: Dictionary = _world_state.create_ground_item(resource_type, amount, item_cell)
	if not _require(bool(item_result.get("ok", false)), "could not create Storehouse seed item"):
		return false
	var item_id: String = String(item_result.get("item_id", ""))
	var reservation: Dictionary = _world_state.reserve_haul_item(item_id, worker_id)
	if not _require(bool(reservation.get("ok", false)) and String(reservation.get("storage_id", "")) == storage_id, "seed haul selected the wrong Storehouse"):
		return false
	var pickup: Dictionary = _world_state.request_pickup_ground_item(item_id, worker_id)
	var deposit: Dictionary = _world_state.request_deposit_carried_item(worker_id, pickup.get("item", {}), reservation.get("destination_cell", Vector2i.ZERO))
	return _require(bool(pickup.get("ok", false)) and bool(deposit.get("ok", false)), "could not deposit Storehouse seed item")


func _find_storage_access_cell(component: Dictionary) -> Vector2i:
	var occupied: Array = component.get("occupied_cells", [])
	var candidates: Array[Vector2i] = []
	for occupied_cell: Vector2i in occupied:
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var cell: Vector2i = occupied_cell + offset
			if not occupied.has(cell) and not candidates.has(cell):
				candidates.append(cell)
	candidates.sort_custom(func(first: Vector2i, second: Vector2i) -> bool:
		return first.y < second.y if first.y != second.y else first.x < second.x
	)
	for cell: Vector2i in candidates:
		if not _chunk_manager.is_cell_loaded(cell):
			continue
		var tile: Dictionary = _chunk_manager.get_effective_tile_info(cell)
		var terrain: String = String(tile.get("terrain", ""))
		if bool(tile.get("walkable", false)) and terrain != "WATER" and terrain != "ROCK_WALL" and not bool(tile.get("mineable", false)) and _world_state.get_construction_site_at_cell(cell).is_empty():
			return cell
	return INVALID_CELL


func _find_valid_building_origin(building_id: String, hint: Vector2i, excluded: Array[Vector2i] = []) -> Vector2i:
	for radius in range(64):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := hint + Vector2i(x, y)
				var occupied: Array[Vector2i] = _footprint_cells(building_id, candidate)
				var overlaps: bool = false
				for cell: Vector2i in occupied:
					if excluded.has(cell):
						overlaps = true
						break
				if not overlaps and bool(_world_state.validate_construction_placement(building_id, candidate).get("ok", false)):
					return candidate
	return INVALID_CELL


func _footprint_cells(building_id: String, origin: Vector2i) -> Array[Vector2i]:
	var footprint: Vector2i = BuildingDefinition.get_definition(building_id).get("footprint", Vector2i.ONE)
	var cells: Array[Vector2i] = []
	for y in range(footprint.y):
		for x in range(footprint.x):
			cells.append(origin + Vector2i(x, y))
	return cells


func _sum_allocations(allocations: Array, resource_type: String) -> int:
	var total: int = 0
	for allocation_value: Variant in allocations:
		var allocation: Dictionary = allocation_value
		if String(allocation.get("resource_type", "")) == resource_type:
			total += int(allocation.get("amount", 0))
	return total


func _find_saved_construction_site(save_data: Dictionary, site_id: String) -> Dictionary:
	var deltas: Dictionary = save_data.get("deltas", {})
	for site_value: Variant in deltas.get("construction_sites", []):
		var site: Dictionary = site_value
		if String(site.get("site_id", "")) == site_id:
			return site
	return {}


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
