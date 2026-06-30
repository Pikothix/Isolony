extends SceneTree

## Purpose: Validate bounded loose-item delivery into construction sites.
## Responsibility: Exercise delivery selection, reservation, movement, exact-once consumption, source priority, and save exclusion.
## Assumption: Wood fixtures use complete stacks no larger than the site's outstanding Wood requirement.

const MainScene = preload("res://scenes/Main.tscn")
const ReachabilityQueryRef = preload("res://scripts/world/reachability_query.gd")
const SaveGameServiceRef = preload("res://scripts/simulation/save_game_service.gd")
const INVALID_CELL := Vector2i(2147483647, 2147483647)
const DELIVERY_RADIUS := 12

var _failed: bool = false
var _main: Node
var _world_state: Node
var _chunk_manager: ChunkManager
var _manager: ColonistManager
var _worker: Colonist
var _second_worker: Colonist


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("J03 construction material delivery validation failed: %s" % message)
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
	_manager = _main.get_node("ChunkManager/GameplayYSort/ColonistManager") as ColonistManager
	var colonists: Array[Colonist] = _get_colonists()
	if not _require(_world_state != null and colonists.size() >= 2, "Main scene did not initialize delivery workers"):
		return
	_worker = colonists[0]
	_second_worker = colonists[1]
	_freeze_scene(colonists)
	_prepare_worker(_worker)
	_prepare_worker(_second_worker)

	if not _validate_nearby_delivery_and_exact_once():
		return
	if not _validate_bounded_and_reachable_selection():
		return
	if not _validate_exclusive_reservation_and_save_exclusion():
		return
	if not _validate_bootstrap_and_storehouse_priority():
		return

	print("J03 validation passed: bounded reachable loose delivery, exclusive reservation, exact-once consumption, Storehouse priority, bootstrap, and save exclusion")
	quit(0)


func _validate_nearby_delivery_and_exact_once() -> bool:
	var site: Dictionary = _place_site("campfire", _worker.current_cell + Vector2i(8, 0))
	if site.is_empty():
		return false
	var site_id: String = String(site.get("site_id", ""))
	var origin: Vector2i = site.get("origin_cell", INVALID_CELL)
	var item_cell: Vector2i = _find_reachable_delivery_cell(origin, origin + Vector2i(-4, 0))
	if not _require(item_cell != INVALID_CELL, "could not find nearby Wood delivery cell"):
		return false
	var item_result: Dictionary = _world_state.create_ground_item("wood", 5, item_cell)
	if not _require(bool(item_result.get("ok", false)), "could not create nearby loose Wood"):
		return false
	var item_id: String = String(item_result.get("item_id", ""))
	_worker._enter_idle()
	_worker.set("_pause_timer", 0.0)
	if not _require(_worker._try_start_prioritized_work() and _worker.get_construction_delivery_item_id() == item_id, "worker did not choose nearby loose Wood delivery"):
		return false
	for _step in range(1200):
		_worker._process(0.02)
		var delivered: int = int((_world_state.get_construction_site(site_id).get("delivered_resources", {}) as Dictionary).get("wood", 0))
		if delivered == 5 and _worker.get_construction_delivery_item_id().is_empty():
			break
	var delivered_site: Dictionary = _world_state.get_construction_site(site_id)
	if not _require(int((delivered_site.get("delivered_resources", {}) as Dictionary).get("wood", 0)) == 5 and _find_ground_item(item_id).is_empty(), "pickup/delivery did not transfer loose Wood into the site"):
		return false
	if not _require(_world_state.get_resource_stockpile().get_total("wood") == 0, "loose delivery changed legacy Wood"):
		return false

	var reservation: Dictionary = _world_state.reserve_construction_site(_worker.colonist_id, site_id)
	var first_progress: Dictionary = _world_state.request_progress_construction(site_id, 1.0, _worker.colonist_id)
	var after_first: Dictionary = _world_state.get_construction_site(site_id)
	var second_progress: Dictionary = _world_state.request_progress_construction(site_id, 1.0, _worker.colonist_id)
	var after_second: Dictionary = _world_state.get_construction_site(site_id)
	if not _require(bool(reservation.get("ok", false)) and bool(first_progress.get("ok", false)) and bool(second_progress.get("ok", false)), "delivered-material construction could not progress"):
		return false
	if not _require(bool(after_first.get("resources_consumed", false)) and int((after_first.get("consumed_resources", {}) as Dictionary).get("wood", 0)) == 5 and int((after_second.get("consumed_resources", {}) as Dictionary).get("wood", 0)) == 5, "delivered Wood was not consumed exactly once"):
		return false
	if not _require(int((after_second.get("delivered_resources", {}) as Dictionary).get("wood", 0)) == 5 and _world_state.get_resource_stockpile().get_total("wood") == 0, "later progress duplicated or respent delivered Wood"):
		return false
	var completion: Dictionary = _world_state.request_progress_construction(site_id, 20.0, _worker.colonist_id)
	return _require(bool(completion.get("completed", false)), "loose-funded Campfire did not complete")


func _validate_bounded_and_reachable_selection() -> bool:
	var far_site: Dictionary = _place_site("campfire", _worker.current_cell + Vector2i(18, 8))
	if far_site.is_empty():
		return false
	var far_origin: Vector2i = far_site.get("origin_cell", INVALID_CELL)
	var far_cell: Vector2i = _find_far_open_cell(far_origin)
	if not _require(far_cell != INVALID_CELL, "could not find far loose-item fixture"):
		return false
	var far_item: Dictionary = _world_state.create_ground_item("wood", 5, far_cell)
	var far_item_id: String = String(far_item.get("item_id", ""))
	if not _require(bool(far_item.get("ok", false)) and not _delivery_candidates_include(String(far_site.get("site_id", "")), far_item_id), "far loose Wood outside bounded radius was considered"):
		return false
	_world_state.remove_ground_item(far_item_id)
	_world_state.request_cancel_construction(String(far_site.get("site_id", "")))

	var blocked_site: Dictionary = _place_site("campfire", _worker.current_cell + Vector2i(-14, 8))
	if blocked_site.is_empty():
		return false
	var blocked_origin: Vector2i = blocked_site.get("origin_cell", INVALID_CELL)
	var blocked_cell: Vector2i = _find_open_cluster_cell(blocked_origin + Vector2i(5, 0))
	if not _require(blocked_cell != INVALID_CELL, "could not find unreachable loose-item fixture"):
		return false
	var blocked_item: Dictionary = _world_state.create_ground_item("wood", 5, blocked_cell)
	var blocked_item_id: String = String(blocked_item.get("item_id", ""))
	if not _require(bool(blocked_item.get("ok", false)) and _create_water_ring(blocked_cell), "could not isolate unreachable loose Wood"):
		return false
	var jobs: Array[Dictionary] = _worker.collect_available_jobs()
	for job: Dictionary in jobs:
		if String(job.get("target_id", "")) == blocked_item_id:
			return _require(false, "unreachable loose Wood produced a delivery job")
	_world_state.remove_ground_item(blocked_item_id)
	_world_state.request_cancel_construction(String(blocked_site.get("site_id", "")))
	return true


func _validate_exclusive_reservation_and_save_exclusion() -> bool:
	var site: Dictionary = _place_site("campfire", _worker.current_cell + Vector2i(10, -10))
	if site.is_empty():
		return false
	var origin: Vector2i = site.get("origin_cell", INVALID_CELL)
	var item_cell: Vector2i = _find_reachable_delivery_cell(origin, origin + Vector2i(3, 0))
	if not _require(item_cell != INVALID_CELL, "could not find reservation fixture cell"):
		return false
	var item: Dictionary = _world_state.create_ground_item("wood", 5, item_cell)
	var item_id: String = String(item.get("item_id", ""))
	var site_id: String = String(site.get("site_id", ""))
	var first: Dictionary = _world_state.reserve_construction_material_delivery(site_id, item_id, _worker.colonist_id)
	var second: Dictionary = _world_state.reserve_construction_material_delivery(site_id, item_id, _second_worker.colonist_id)
	if not _require(bool(first.get("ok", false)) and not bool(second.get("ok", false)), "reserved loose item could be claimed twice"):
		return false
	var premature_progress: Dictionary = _world_state.request_progress_construction(site_id, 1.0)
	if not _require(not bool(premature_progress.get("ok", false)) and String(premature_progress.get("reason", "")) == "material_delivery_pending", "construction progressed while material delivery was pending"):
		return false
	if not _require(not bool(_world_state.reserve_haul_item(item_id, _second_worker.colonist_id).get("ok", false)), "ordinary Haul claimed construction-reserved material"):
		return false
	var save_service := SaveGameServiceRef.new()
	var save_data: Dictionary = save_service.build_save_data(_main.get_node("WorldGenerator"), _world_state, _chunk_manager, _manager)
	for forbidden_key: String in ["construction_delivery_reservations", "construction_delivery_item_id", "reserved_by_colonist_id"]:
		if not _require(not _contains_key_recursive(save_data, forbidden_key), "save persisted transient delivery field %s" % forbidden_key):
			return false
	_world_state.release_construction_material_delivery(item_id, _worker.colonist_id, "validation_cleanup")
	_world_state.remove_ground_item(item_id)
	_world_state.request_cancel_construction(site_id)
	return true


func _validate_bootstrap_and_storehouse_priority() -> bool:
	if not _require(_world_state.get_storage_components().is_empty(), "bootstrap fixture unexpectedly has storage"):
		return false
	if not _require(bool(_world_state.add_resource("wood", 30).get("ok", false)) and bool(_world_state.add_resource("stone", 10).get("ok", false)), "could not seed first Storehouse bootstrap"):
		return false
	var storehouse: Dictionary = _place_site("storehouse", _worker.current_cell + Vector2i(0, 16))
	if storehouse.is_empty():
		return false
	var storehouse_id: String = String(storehouse.get("site_id", ""))
	var bootstrap: Dictionary = _world_state.request_progress_construction(storehouse_id, 50.0)
	if not _require(bool(bootstrap.get("completed", false)) and _world_state.get_storage_components().size() == 1, "first Storehouse no longer bootstraps from legacy resources"):
		return false
	var component: Dictionary = _world_state.get_storage_components()[0]
	var storage_id: String = String(component.get("storage_id", ""))
	if not _deposit_to_storage(storage_id, "wood", 5):
		return false

	var site: Dictionary = _place_site("campfire", storehouse.get("origin_cell", Vector2i.ZERO) + Vector2i(8, 0))
	if site.is_empty():
		return false
	var origin: Vector2i = site.get("origin_cell", INVALID_CELL)
	var loose_cell: Vector2i = _find_reachable_delivery_cell(origin, origin + Vector2i(3, 0))
	var loose_item: Dictionary = _world_state.create_ground_item("wood", 5, loose_cell)
	var loose_id: String = String(loose_item.get("item_id", ""))
	var site_id: String = String(site.get("site_id", ""))
	if not _require(loose_cell != INVALID_CELL and bool(loose_item.get("ok", false)) and not _delivery_candidates_include(site_id, loose_id), "loose Wood displaced fully available Storehouse contents"):
		return false
	var reservation: Dictionary = _world_state.reserve_construction_site(_worker.colonist_id, site_id)
	var progress: Dictionary = _world_state.request_progress_construction(site_id, 1.0, _worker.colonist_id)
	var component_after: Dictionary = _world_state.get_storage_component(storage_id)
	if not _require(bool(reservation.get("ok", false)) and bool(progress.get("ok", false)) and int((component_after.get("contents", {}) as Dictionary).get("wood", 0)) == 0 and not _find_ground_item(loose_id).is_empty(), "construction did not prefer Storehouse Wood"):
		return false
	_world_state.request_progress_construction(site_id, 20.0, _worker.colonist_id)
	_world_state.remove_ground_item(loose_id)
	return true


func _place_site(building_id: String, hint: Vector2i) -> Dictionary:
	var origin: Vector2i = _find_building_origin(building_id, hint)
	if not _require(origin != INVALID_CELL, "could not find %s origin" % building_id):
		return {}
	var result: Dictionary = _world_state.request_place_construction(building_id, origin)
	if not _require(bool(result.get("ok", false)), "could not place %s" % building_id):
		return {}
	var site_id := "%s:%d:%d" % [building_id, origin.x, origin.y]
	return _world_state.get_construction_site(site_id)


func _find_building_origin(building_id: String, hint: Vector2i) -> Vector2i:
	for radius in range(64):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := hint + Vector2i(x, y)
				if bool(_world_state.validate_construction_placement(building_id, candidate).get("ok", false)):
					return candidate
	return INVALID_CELL


func _find_reachable_delivery_cell(site_origin: Vector2i, hint: Vector2i) -> Vector2i:
	for radius in range(DELIVERY_RADIUS):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := hint + Vector2i(x, y)
				if not _is_open_cell(candidate) or maxi(absi(candidate.x - site_origin.x), absi(candidate.y - site_origin.y)) > DELIVERY_RADIUS:
					continue
				var pickup: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, _worker.current_cell, candidate)
				var delivery: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, candidate, site_origin, {"allow_target_construction": true})
				if bool(pickup.get("reachable", false)) and bool(delivery.get("reachable", false)):
					return candidate
	return INVALID_CELL


func _find_far_open_cell(origin: Vector2i) -> Vector2i:
	for radius in range(DELIVERY_RADIUS + 1, DELIVERY_RADIUS + 20):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := origin + Vector2i(x, y)
				if maxi(absi(x), absi(y)) > DELIVERY_RADIUS and _is_open_cell(candidate):
					return candidate
	return INVALID_CELL


func _find_open_cluster_cell(hint: Vector2i) -> Vector2i:
	for radius in range(32):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := hint + Vector2i(x, y)
				var valid: bool = true
				for offset: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
					if not _is_open_cell(candidate + offset):
						valid = false
						break
				if valid:
					return candidate
	return INVALID_CELL


func _create_water_ring(center: Vector2i) -> bool:
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		if not bool(_chunk_manager.request_place_manual_tile(center + offset, "WATER").get("ok", false)):
			return false
	return true


func _is_open_cell(cell: Vector2i) -> bool:
	if not _chunk_manager.is_cell_loaded(cell):
		return false
	var tile: Dictionary = _chunk_manager.get_effective_tile_info(cell)
	var terrain: String = String(tile.get("terrain", ""))
	return bool(tile.get("walkable", false)) and terrain != "WATER" and terrain != "ROCK_WALL" and not bool(tile.get("mineable", false)) and not _chunk_manager.is_cell_blocked_by_resource(cell) and _world_state.get_construction_site_at_cell(cell).is_empty() and not _world_state.is_cell_in_stockpile_zone(cell)


func _delivery_candidates_include(site_id: String, item_id: String) -> bool:
	for delivery: Dictionary in _world_state.get_available_construction_material_deliveries(64):
		if String(delivery.get("site_id", "")) == site_id and String(delivery.get("item_id", "")) == item_id:
			return true
	return false


func _deposit_to_storage(storage_id: String, resource_type: String, amount: int) -> bool:
	var component: Dictionary = _world_state.get_storage_component(storage_id)
	var item_cell: Vector2i = INVALID_CELL
	var occupied: Array = component.get("occupied_cells", [])
	for occupied_cell: Vector2i in occupied:
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var candidate: Vector2i = occupied_cell + offset
			if not occupied.has(candidate) and _is_open_cell(candidate):
				item_cell = candidate
				break
		if item_cell != INVALID_CELL:
			break
	if not _require(item_cell != INVALID_CELL, "could not find Storehouse access cell"):
		return false
	var item: Dictionary = _world_state.create_ground_item(resource_type, amount, item_cell)
	var item_id: String = String(item.get("item_id", ""))
	var reservation: Dictionary = _world_state.reserve_haul_item(item_id, "j03_storage_seed")
	var pickup: Dictionary = _world_state.request_pickup_ground_item(item_id, "j03_storage_seed")
	var deposit: Dictionary = _world_state.request_deposit_carried_item("j03_storage_seed", pickup.get("item", {}), reservation.get("destination_cell", Vector2i.ZERO))
	return _require(bool(item.get("ok", false)) and bool(reservation.get("ok", false)) and String(reservation.get("storage_id", "")) == storage_id and bool(pickup.get("ok", false)) and bool(deposit.get("ok", false)), "could not seed Storehouse contents")


func _find_ground_item(item_id: String) -> Dictionary:
	for item: Dictionary in _world_state.get_ground_items():
		if String(item.get("item_id", "")) == item_id:
			return item
	return {}


func _prepare_worker(worker: Colonist) -> void:
	worker.move_speed = 1000.0
	worker.rest = 100.0
	worker.warmth = 100.0
	worker.shelter = 100.0
	worker.hunger = 100.0
	for work_type: String in Colonist.WORK_TYPES:
		worker.set_work_priority(work_type, 0)
	worker.set_work_priority("Construct", 1)
	worker._enter_idle()
	worker.set("_pause_timer", 0.0)
	_world_state.get_time_state().import_state({"current_day": 1, "current_minutes": 600.0, "paused": true})


func _get_colonists() -> Array[Colonist]:
	var colonists: Array[Colonist] = []
	for child: Node in _manager.get_children():
		if child is Colonist and not child.is_queued_for_deletion():
			colonists.append(child as Colonist)
	colonists.sort_custom(func(first: Colonist, second: Colonist) -> bool:
		return first.colonist_id < second.colonist_id
	)
	return colonists


func _freeze_scene(colonists: Array[Colonist]) -> void:
	_main.set_process(false)
	_chunk_manager.set_process(false)
	_manager.set_process(false)
	for colonist: Colonist in colonists:
		colonist.set_process(false)


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
