extends SceneTree

const SaveGameServiceRef = preload("res://scripts/simulation/save_game_service.gd")
const ReachabilityQueryRef = preload("res://scripts/world/reachability_query.gd")

var _main: Node
var _world_state: Node
var _chunk_manager: ChunkManager
var _manager: ColonistManager

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("M41 validation failed: %s" % message)
	quit(1)

func _assert(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false

func _is_valid_zone_cell(cell: Vector2i) -> bool:
	if not _chunk_manager.is_cell_loaded(cell):
		return false
	var tile: Dictionary = _chunk_manager.get_effective_tile_info(cell)
	var terrain: String = String(tile.get("terrain", ""))
	return bool(tile.get("walkable", false)) and terrain != "WATER" and terrain != "ROCK_WALL" and not bool(tile.get("mineable", false)) and _world_state.get_construction_site_at_cell(cell).is_empty() and not _chunk_manager.is_cell_blocked_by_resource(cell)

func _find_valid_cell(origin: Vector2i, excluded: Array[Vector2i] = [], required_origins: Array[Vector2i] = []) -> Vector2i:
	for radius in range(64):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var cell := origin + Vector2i(x, y)
				if cell in excluded or not _is_valid_zone_cell(cell) or _world_state.is_cell_in_stockpile_zone(cell):
					continue
				var reachable := true
				for required_origin: Vector2i in required_origins:
					if not bool(ReachabilityQueryRef.find_path(_chunk_manager, _world_state, required_origin, cell).get("reachable", false)):
						reachable = false
						break
				if reachable:
					return cell
	return Vector2i(2147483647, 2147483647)

func _find_valid_building_origin(building_id: String, origin: Vector2i) -> Vector2i:
	for radius in range(64):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := origin + Vector2i(x, y)
				if bool(_world_state.validate_construction_placement(building_id, candidate).get("ok", false)):
					return candidate
	return Vector2i(2147483647, 2147483647)

func _get_item(item_id: String) -> Dictionary:
	for item: Dictionary in _world_state.get_ground_items():
		if String(item.get("item_id", "")) == item_id:
			return item
	return {}

func _find_resource() -> Dictionary:
	var resources: Array[Dictionary] = _chunk_manager.get_loaded_resources_in_cell_rect(Rect2i(Vector2i(-4096, -4096), Vector2i(8192, 8192)))
	return resources[0] if not resources.is_empty() else {}

func _prepare_worker(worker: Colonist) -> void:
	worker.set_process(false)
	worker.move_speed = 1000.0
	worker.warmth = 100.0
	worker.shelter = 100.0
	worker.hunger = 100.0
	worker.set_work_priority("Construct", 0)
	worker.set_work_priority("Harvest", 0)
	worker.set_work_priority("Haul", 1)
	worker._enter_idle()

func _run_until_item_picked_up(worker: Colonist, item_id: String) -> bool:
	for _step in range(1200):
		worker._process(0.05)
		if _get_item(item_id).is_empty() and not worker.get_carried_item().is_empty():
			return true
	return false

func _run() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_main)
	for _frame in range(120):
		await process_frame
	_world_state = _main.get("_world_state")
	_chunk_manager = _main.get_node("ChunkManager") as ChunkManager
	_manager = _main.get_node("ChunkManager/GameplayYSort/ColonistManager") as ColonistManager
	_manager.set_process(false)
	var worker: Colonist
	for child: Node in _manager.get_children():
		if child is Colonist:
			child.set_process(false)
			if worker == null:
				worker = child as Colonist
	if not _assert(worker != null, "no colonist available"):
		return
	_world_state.get_time_state().import_state({"current_day": 1, "current_minutes": 600.0, "paused": true})

	var zone_cell: Vector2i = _find_valid_cell(worker.current_cell + Vector2i(8, 0), [], [worker.current_cell])
	var item_cell: Vector2i = _find_valid_cell(worker.current_cell + Vector2i(-8, 0), [zone_cell], [worker.current_cell, zone_cell])
	if not _assert(zone_cell.x != 2147483647 and item_cell.x != 2147483647, "could not find zone/item cells"):
		return
	var zone_result: Dictionary = _world_state.request_create_stockpile_zone([zone_cell])
	if not _assert(bool(zone_result.get("ok", false)), "stockpile zone creation failed"):
		return
	var first_item_result: Dictionary = _world_state.create_ground_item("wood", 5, item_cell)
	var first_item_id: String = String(first_item_result.get("item_id", ""))
	if not _assert(bool(first_item_result.get("ok", false)), "ground item creation failed"):
		return

	worker.set_work_priority("Haul", 0)
	if not _assert(worker.get_work_priority("Haul") == 0 and worker.collect_available_jobs().filter(func(job: Dictionary) -> bool: return String(job.get("job_type", "")) == Colonist.JOB_TYPE_HAUL).is_empty(), "disabled Haul produced a candidate"):
		return
	_prepare_worker(worker)
	if not _assert(worker._try_start_prioritized_work() and worker.get_activity_name() == "moving_to_haul_item", "enabled Haul did not start"):
		return
	var reservation: Dictionary = _world_state.get_haul_item_reservation(first_item_id)
	if not _assert(String(reservation.get("reserved_by_colonist_id", "")) == worker.colonist_id and reservation.get("destination_cell", Vector2i.ZERO) == zone_cell, "item/destination reservation was incorrect"):
		return
	var storage_summary: Dictionary = _world_state.get_resource_stockpile().get_storage_reservation_summary()
	if not _assert(int(storage_summary.get("reserved", 0)) == 5, "haul did not reserve destination capacity"):
		return
	if not _assert(_run_until_item_picked_up(worker, first_item_id), "pickup did not remove ground item/create carried payload"):
		return
	if not _assert(bool(_world_state.get_haul_item_reservation(first_item_id).get("picked_up", false)), "WorldState did not record pickup state"):
		return
	for _step in range(1200):
		worker._process(0.05)
		if worker.get_activity_name() == "idle" and worker.get_haul_item_id().is_empty():
			break
	if not _assert(_world_state.get_resource_total("wood") == 5 and worker.get_carried_item().is_empty(), "deposit did not increase stored Wood and clear carrying"):
		return
	if not _assert(int(_world_state.get_resource_stockpile().get_storage_reservation_summary().get("count", -1)) == 0, "deposit left capacity reserved"):
		return

	_world_state.add_resource("wood", 95)
	var blocked_item: Dictionary = _world_state.create_ground_item("stone", 1, item_cell)
	var blocked_id: String = String(blocked_item.get("item_id", ""))
	if not _assert(_world_state.get_stored_resource_total() == _world_state.get_storage_capacity(), "stockpile was not filled for capacity test"):
		return
	if not _assert(_world_state.get_available_haul_item(worker.colonist_id).is_empty() and not bool(_world_state.reserve_haul_item(blocked_id, worker.colonist_id).get("ok", false)), "full capacity allowed a haul reservation"):
		return

	var campfire_cell: Vector2i = _find_valid_building_origin("campfire", zone_cell + Vector2i(8, 0))
	var campfire_place: Dictionary = _world_state.request_place_construction("campfire", campfire_cell)
	var campfire_id := "campfire:%d:%d" % [campfire_cell.x, campfire_cell.y]
	var campfire_progress: Dictionary = _world_state.request_progress_construction(campfire_id, 10.0)
	if not _assert(bool(campfire_place.get("ok", false)) and bool(campfire_progress.get("completed", false)) and _world_state.get_resource_total("wood") == 95, "construction did not consume existing stockpile Wood"):
		return

	var abandon_cell: Vector2i = _find_valid_cell(item_cell + Vector2i(1, 0), [zone_cell, item_cell], [worker.current_cell, zone_cell])
	if not _assert(abandon_cell.x != 2147483647, "could not find reachable abandonment item cell"):
		return
	var abandon_item: Dictionary = _world_state.create_ground_item("stone", 2, abandon_cell)
	var abandon_id: String = String(abandon_item.get("item_id", ""))
	_prepare_worker(worker)
	if not _assert(worker._try_start_prioritized_work(), "could not start pre-pickup abandonment haul"):
		return
	var active_item_id: String = worker.get_haul_item_id()
	worker._finish_haul_job("validation_abandon_before_pickup")
	if not _assert(not _get_item(active_item_id).is_empty() and _world_state.get_haul_item_reservation(active_item_id).is_empty() and int(_world_state.get_resource_stockpile().get_storage_reservation_summary().get("count", -1)) == 0, "pre-pickup abandonment did not release item/capacity"):
		return

	# Ensure the next selected item is picked up, then abandon it and verify a replacement drop at the current cell.
	_prepare_worker(worker)
	if not _assert(worker._try_start_prioritized_work(), "could not start post-pickup abandonment haul"):
		return
	var carried_source_id: String = worker.get_haul_item_id()
	if not _assert(_run_until_item_picked_up(worker, carried_source_id), "could not reach post-pickup abandonment state"):
		return
	var carried_data: Dictionary = worker.get_carried_item()
	var drop_cell: Vector2i = worker.current_cell
	worker._finish_haul_job("validation_abandon_after_pickup")
	var found_drop: bool = false
	for item: Dictionary in _world_state.get_ground_items():
		if item.get("cell", Vector2i.ZERO) == drop_cell and String(item.get("resource_type", "")) == String(carried_data.get("resource_type", "")) and int(item.get("amount", 0)) == int(carried_data.get("amount", 0)):
			found_drop = true
	if not _assert(found_drop and _world_state.get_haul_item_reservation(carried_source_id).is_empty(), "post-pickup abandonment did not drop/release"):
		return

	# Save mid-carry: export restores the payload as a ground item while all transient reservations clear on load.
	_prepare_worker(worker)
	if not _assert(worker._try_start_prioritized_work(), "no item available for mid-carry save/load test"):
		return
	var save_item_id: String = worker.get_haul_item_id()
	if not _assert(_run_until_item_picked_up(worker, save_item_id), "could not reach mid-carry save state"):
		return
	var save_service := SaveGameServiceRef.new()
	var save_data: Dictionary = save_service.build_save_data(_main.get_node("WorldGenerator"), _world_state, _chunk_manager, _manager)
	var load_result: Dictionary = save_service.apply_save_data(save_data, _main.get_node("WorldGenerator"), _world_state, _chunk_manager, _manager)
	if not _assert(bool(load_result.get("ok", false)), "save/load failed: %s" % load_result.get("reason", "unknown")):
		return
	if not _assert(not _get_item(save_item_id).is_empty() and _world_state.get_haul_item_reservation(save_item_id).is_empty() and int(_world_state.get_resource_stockpile().get_storage_reservation_summary().get("count", -1)) == 0, "load did not restore carried item/clear haul reservations"):
		return
	if not _assert(_world_state.get_stockpile_zones().size() == 1, "stockpile zone did not persist"):
		return

	_manager.set_process(false)
	var restored_worker: Colonist
	for child: Node in _manager.get_children():
		if child is Colonist:
			child.set_process(false)
			if restored_worker == null:
				restored_worker = child as Colonist
	if not _assert(restored_worker != null, "no restored colonist"):
		return

	# Harvesting remains independent of storage capacity and produces another ground item.
	var resource: Dictionary = _find_resource()
	if not _assert(not resource.is_empty(), "no harvest resource available"):
		return
	var resource_id: String = String(resource.get("resource_id", ""))
	var designation: Dictionary = _world_state.request_designate_harvest(resource_id)
	restored_worker.move_speed = 1000.0
	restored_worker.warmth = 100.0
	restored_worker.shelter = 100.0
	restored_worker.hunger = 100.0
	restored_worker.set_work_priority("Construct", 0)
	restored_worker.set_work_priority("Haul", 0)
	restored_worker.set_work_priority("Harvest", 1)
	restored_worker._enter_idle()
	var item_count_before_harvest: int = _world_state.get_ground_items().size()
	if not _assert(bool(designation.get("ok", false)) and restored_worker._try_start_prioritized_work(), "harvest regression job did not start"):
		return
	for _step in range(1200):
		restored_worker._process(0.05)
		if not _world_state.has_harvest_order_for_resource(resource_id):
			break
	if not _assert(_chunk_manager.is_resource_depleted(resource_id) and _world_state.get_ground_items().size() == item_count_before_harvest + 1, "harvest no longer produced a ground item"):
		return

	# Stored Food alone is edible.
	_world_state.get_time_state().import_state({"current_day": 1, "current_minutes": 600.0, "paused": true})
	_world_state.add_resource("food", 1)
	restored_worker.set_work_priority("Harvest", 0)
	restored_worker.hunger = 10.0
	restored_worker._enter_idle()
	restored_worker._pause_timer = 0.0
	restored_worker._process_idle(0.1)
	if not _assert(restored_worker.get_activity_name() == "eating", "eating regression check failed"):
		return

	# Complete a Cabin from existing stored Wood and verify both need-seeking paths.
	var cabin_cell: Vector2i = _find_valid_building_origin("cabin", campfire_cell + Vector2i(12, 0))
	var cabin_place: Dictionary = _world_state.request_place_construction("cabin", cabin_cell)
	var cabin_id := "cabin:%d:%d" % [cabin_cell.x, cabin_cell.y]
	var cabin_progress: Dictionary = _world_state.request_progress_construction(cabin_id, 30.0)
	if not _assert(bool(cabin_place.get("ok", false)) and bool(cabin_progress.get("completed", false)), "Cabin construction regression failed"):
		return
	_world_state.get_time_state().import_state({"current_day": 1, "current_minutes": 1200.0, "paused": true})
	restored_worker.hunger = 100.0
	restored_worker.warmth = 10.0
	restored_worker.shelter = 100.0
	restored_worker._enter_idle()
	restored_worker._pause_timer = 0.0
	restored_worker._process_idle(0.1)
	if not _assert(restored_worker.get_activity_name() == "seeking_warmth", "warmth-seeking regression failed"):
		return
	restored_worker.warmth = 100.0
	restored_worker.shelter = 10.0
	restored_worker._enter_idle()
	restored_worker._pause_timer = 0.0
	restored_worker._process_idle(0.1)
	if not _assert(restored_worker.get_activity_name() == "seeking_shelter", "shelter-seeking regression failed"):
		return

	print("M41 validation passed: priority, reserve, pickup, deposit, capacity, abandonment/drop, save/load, harvest, construction, eating, warmth, shelter, zones")
	quit(0)
