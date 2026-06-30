extends SceneTree

## Purpose: Validate J1 bounded multi-candidate availability and reachable job selection.
## Responsibility: Exercise real WorldState construction, harvest, haul, reservation, priority, and export boundaries.
## Assumption: WATER rings are disposable validation-only barriers in this isolated scene.

const MainScene = preload("res://scenes/Main.tscn")
const ReachabilityQueryRef = preload("res://scripts/world/reachability_query.gd")
const SaveGameServiceRef = preload("res://scripts/simulation/save_game_service.gd")

const INVALID_CELL := Vector2i(2147483647, 2147483647)

var _failed := false
var _main: Node
var _world_state: Node
var _chunk_manager: ChunkManager
var _manager: ColonistManager
var _worker: Colonist


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("J1 reachable candidate validation failed: %s" % message)
	quit(1)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _run() -> void:
	_main = MainScene.instantiate()
	root.add_child(_main)
	for _frame in range(180):
		await process_frame
	_world_state = _main.get("_world_state")
	_chunk_manager = _main.get_node("ChunkManager") as ChunkManager
	_manager = _main.get_node("ChunkManager/GameplayYSort/ColonistManager") as ColonistManager
	_freeze_runtime()
	var colonists: Array[Colonist] = _get_colonists()
	if not _require(not colonists.is_empty(), "no colonist available"):
		return
	_worker = colonists[0]
	var worker_cell: Vector2i = _find_open_cluster(_worker.current_cell, [Vector2i.ZERO])
	if not _require(worker_cell != INVALID_CELL, "no open worker cell"):
		return
	_set_worker_cell(worker_cell)
	_set_priorities(0, 0, 0)
	if not _require(bool(_world_state.add_resource("wood", 60).get("ok", false)), "could not seed Wood"):
		return
	if not _require(bool(_world_state.add_resource("stone", 30).get("ok", false)), "could not seed Stone"):
		return
	if not _bootstrap_construction_storage():
		return

	if not _test_construction_alternative():
		return
	if not _test_harvest_alternative():
		return
	if not _test_haul_alternative():
		return
	if not _test_post_reservation_unreachable_release():
		return
	if not _test_priority_and_source_order():
		return
	if not _test_transient_export_boundary():
		return

	print("J1 REACHABLE CANDIDATE VALIDATION PASSED: bounded deterministic lists, reachable alternatives, reservation release, priority/source order, and save exclusion")
	quit(0)


func _freeze_runtime() -> void:
	_main.set_process(false)
	_chunk_manager.set_process(false)
	_manager.set_process(false)
	for colonist: Colonist in _get_colonists():
		colonist.set_process(false)


func _get_colonists() -> Array[Colonist]:
	var colonists: Array[Colonist] = []
	for child: Node in _manager.get_children():
		if child is Colonist and not child.is_queued_for_deletion():
			colonists.append(child as Colonist)
	colonists.sort_custom(func(first: Colonist, second: Colonist) -> bool:
		return first.colonist_id < second.colonist_id
	)
	return colonists


func _set_worker_cell(cell: Vector2i) -> void:
	_worker.current_cell = cell
	_worker.target_cell = cell
	_worker.global_position = _chunk_manager.get_cell_world_position(cell) + Vector2(0, -6)
	_worker._enter_idle()


func _set_priorities(construct_priority: int, harvest_priority: int, haul_priority: int) -> void:
	_worker.set_work_priority("Construct", construct_priority)
	_worker.set_work_priority("Harvest", harvest_priority)
	_worker.set_work_priority("Haul", haul_priority)


func _bootstrap_construction_storage() -> bool:
	var origin: Vector2i = _find_reachable_building_origin(_worker.current_cell + Vector2i(0, 14), "storehouse", 3)
	if not _require(origin != INVALID_CELL, "could not place construction-storage fixture"):
		return false
	var placement: Dictionary = _world_state.request_place_construction("storehouse", origin)
	var site_id := "storehouse:%d:%d" % [origin.x, origin.y]
	var progress: Dictionary = _world_state.request_progress_construction(site_id, 50.0)
	if not _require(bool(placement.get("ok", false)) and bool(progress.get("completed", false)), "could not complete construction-storage fixture"):
		return false
	var item_cell: Vector2i = _find_reachable_open_cell(_worker.current_cell + Vector2i(4, 4), _worker.current_cell)
	var item_result: Dictionary = _world_state.create_ground_item("wood", 5, item_cell)
	if not _require(item_cell != INVALID_CELL and bool(item_result.get("ok", false)), "could not create construction-storage seed item"):
		return false
	var item_id: String = String(item_result.get("item_id", ""))
	var reservation: Dictionary = _world_state.reserve_haul_item(item_id, "j1_storage_seed")
	var pickup: Dictionary = _world_state.request_pickup_ground_item(item_id, "j1_storage_seed")
	var deposit: Dictionary = _world_state.request_deposit_carried_item("j1_storage_seed", pickup.get("item", {}), reservation.get("destination_cell", Vector2i.ZERO))
	return _require(bool(reservation.get("ok", false)) and bool(pickup.get("ok", false)) and bool(deposit.get("ok", false)), "could not seed Storehouse construction materials")


func _test_construction_alternative() -> bool:
	var first_cell: Vector2i = _find_reachable_placeable_cluster(_worker.current_cell + Vector2i(-14, 0), "campfire", {})
	var second_cell: Vector2i = _find_reachable_placeable_cluster(_worker.current_cell + Vector2i(14, 0), "campfire", {first_cell: true})
	if not _require(first_cell != INVALID_CELL and second_cell != INVALID_CELL, "could not find construction candidate cells"):
		return false
	var first_place: Dictionary = _world_state.request_place_construction("campfire", first_cell)
	var second_place: Dictionary = _world_state.request_place_construction("campfire", second_cell)
	if not _require(bool(first_place.get("ok", false)) and bool(second_place.get("ok", false)), "could not place construction candidates"):
		return false
	var candidates: Array[Dictionary] = [
		{"site_id": "campfire:%d:%d" % [first_cell.x, first_cell.y], "cell": first_cell},
		{"site_id": "campfire:%d:%d" % [second_cell.x, second_cell.y], "cell": second_cell},
	]
	candidates.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return String(first.get("site_id", "")) < String(second.get("site_id", ""))
	)
	var blocked_id: String = String(candidates[0].get("site_id", ""))
	var blocked_cell: Vector2i = candidates[0].get("cell", INVALID_CELL)
	var reachable_id: String = String(candidates[1].get("site_id", ""))
	var reachable_cell: Vector2i = candidates[1].get("cell", INVALID_CELL)
	if not _require(_create_water_ring(blocked_cell), "could not isolate first construction candidate"):
		return false
	var reachable_path: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, _worker.current_cell, reachable_cell, {"allow_target_construction": true})
	if not _require(bool(reachable_path.get("reachable", false)), "second construction candidate became unreachable during fixture setup"):
		return false
	var available: Array[Dictionary] = _world_state.get_available_construction_sites(16)
	if not _require(available.size() >= 2 and String(available[0].get("site_id", "")) == blocked_id, "construction candidates were not deterministic or complete"):
		return false
	if not _require(_world_state.get_available_construction_sites(1).size() == 1 and _world_state.get_available_construction_sites(0).is_empty(), "construction candidate limit was not enforced"):
		return false
	_set_priorities(1, 0, 0)
	var jobs: Array[Dictionary] = _worker.collect_available_jobs()
	var construction_jobs: Array[Dictionary] = jobs.filter(func(job: Dictionary) -> bool: return String(job.get("job_type", "")) == Colonist.JOB_TYPE_CONSTRUCT)
	if not _require(construction_jobs.size() == 1 and String(construction_jobs[0].get("target_id", "")) == reachable_id, "reachable construction alternative was not selected"):
		return false
	var selected: Dictionary = _worker.choose_best_job(jobs)
	if not _require(String(selected.get("target_id", "")) == reachable_id, "construction reservation did not choose reachable alternative"):
		return false
	if not _require(_world_state.get_construction_reservation(blocked_id).is_empty() and _world_state.get_construction_reservation(reachable_id) == _worker.colonist_id, "unreachable construction was reserved"):
		return false
	_worker._release_job_candidate_reservation(selected, "j1_construction_complete")
	_world_state.request_cancel_construction(blocked_id)
	_world_state.request_cancel_construction(reachable_id)
	_set_priorities(0, 0, 0)
	return true


func _test_harvest_alternative() -> bool:
	var pair: Array[Dictionary] = _find_reachable_resource_pair()
	if not _require(pair.size() == 2, "could not find two reachable resources"):
		return false
	pair.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return String(first.get("resource_id", "")) < String(second.get("resource_id", ""))
	)
	var blocked_resource: Dictionary = pair[0]
	var reachable_resource: Dictionary = pair[1]
	var blocked_designation: Dictionary = _world_state.request_designate_harvest(String(blocked_resource.get("resource_id", "")))
	var reachable_designation: Dictionary = _world_state.request_designate_harvest(String(reachable_resource.get("resource_id", "")))
	if not _require(bool(blocked_designation.get("ok", false)) and bool(reachable_designation.get("ok", false)), "could not designate harvest candidates"):
		return false
	if not _require(_create_water_ring(blocked_resource.get("cell", INVALID_CELL)), "could not isolate first harvest candidate"):
		return false
	var blocked_id: String = String(blocked_designation.get("order_id", ""))
	var reachable_id: String = String(reachable_designation.get("order_id", ""))
	var available: Array[Dictionary] = _world_state.get_available_harvest_orders(16)
	if not _require(available.size() >= 2 and String(available[0].get("order_id", "")) == blocked_id, "harvest candidates were not deterministic or complete"):
		return false
	if not _require(_world_state.get_available_harvest_orders(1).size() == 1 and _world_state.get_available_harvest_orders(0).is_empty(), "harvest candidate limit was not enforced"):
		return false
	_set_priorities(0, 1, 0)
	var jobs: Array[Dictionary] = _worker.collect_available_jobs()
	var harvest_jobs: Array[Dictionary] = jobs.filter(func(job: Dictionary) -> bool: return String(job.get("job_type", "")) == Colonist.JOB_TYPE_HARVEST)
	if not _require(harvest_jobs.size() == 1 and String(harvest_jobs[0].get("target_id", "")) == reachable_id, "reachable harvest alternative was not selected"):
		return false
	var selected: Dictionary = _worker.choose_best_job(jobs)
	if not _require(String(selected.get("target_id", "")) == reachable_id, "harvest reservation did not choose reachable alternative"):
		return false
	if not _require(_world_state.get_harvest_order_reservation(blocked_id).is_empty() and _world_state.get_harvest_order_reservation(reachable_id) == _worker.colonist_id, "unreachable harvest was reserved"):
		return false
	_worker._release_job_candidate_reservation(selected, "j1_harvest_complete")
	_world_state.request_cancel_harvest_order(blocked_id)
	_world_state.request_cancel_harvest_order(reachable_id)
	_set_priorities(0, 0, 0)
	return true


func _test_haul_alternative() -> bool:
	var zone_cell: Vector2i = _find_reachable_open_cell(_worker.current_cell + Vector2i(8, 10), _worker.current_cell, 3)
	if not _require(zone_cell != INVALID_CELL, "could not find haul destination"):
		return false
	var zone_result: Dictionary = _world_state.request_create_stockpile_zone([zone_cell])
	if not _require(bool(zone_result.get("ok", false)), "could not create haul destination"):
		return false
	var blocked_cell: Vector2i = _find_open_cluster(_worker.current_cell + Vector2i(-14, 10), [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP])
	var reachable_cell: Vector2i = _find_reachable_storage_access_cell(_worker.current_cell + Vector2i(4, 6))
	if not _require(blocked_cell != INVALID_CELL and reachable_cell != INVALID_CELL, "could not find haul item cells"):
		return false
	var blocked_item: Dictionary = _world_state.create_ground_item("stone", 1, blocked_cell)
	var reachable_item: Dictionary = _world_state.create_ground_item("stone", 1, reachable_cell)
	if not _require(bool(blocked_item.get("ok", false)) and bool(reachable_item.get("ok", false)), "could not create haul candidates"):
		return false
	if not _require(_create_water_ring(blocked_cell), "could not isolate first haul candidate"):
		return false
	var blocked_id: String = String(blocked_item.get("item_id", ""))
	var reachable_id: String = String(reachable_item.get("item_id", ""))
	var available: Array[Dictionary] = _world_state.get_available_haul_items(_worker.colonist_id, 16)
	if not _require(available.size() >= 2 and String(available[0].get("item_id", "")) == blocked_id, "haul candidates were not deterministic or complete"):
		return false
	if not _require(_world_state.get_available_haul_items(_worker.colonist_id, 1).size() == 1 and _world_state.get_available_haul_items(_worker.colonist_id, 0).is_empty(), "haul candidate limit was not enforced"):
		return false
	_set_priorities(0, 0, 1)
	var jobs: Array[Dictionary] = _worker.collect_available_jobs()
	var haul_jobs: Array[Dictionary] = jobs.filter(func(job: Dictionary) -> bool: return String(job.get("job_type", "")) == Colonist.JOB_TYPE_HAUL)
	if not _require(haul_jobs.size() == 1 and String(haul_jobs[0].get("target_id", "")) == reachable_id, "reachable haul alternative was not selected"):
		return false
	var selected: Dictionary = _worker.choose_best_job(jobs)
	if not _require(String(selected.get("target_id", "")) == reachable_id, "haul reservation did not choose reachable alternative"):
		return false
	if not _require(_world_state.get_haul_item_reservation(blocked_id).is_empty() and not _world_state.get_haul_item_reservation(reachable_id).is_empty(), "unreachable haul item was reserved"):
		return false
	_worker._release_job_candidate_reservation(selected, "j1_haul_complete")
	_world_state.remove_ground_item(blocked_id)
	_world_state.remove_ground_item(reachable_id)
	_world_state.request_remove_stockpile_zone(String(zone_result.get("zone_id", "")))
	_set_priorities(0, 0, 0)
	return true


func _test_post_reservation_unreachable_release() -> bool:
	var site_cell: Vector2i = _find_placeable_cluster(_worker.current_cell + Vector2i(0, -12), "campfire", [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP])
	if not _require(site_cell != INVALID_CELL, "could not find revalidation construction cell"):
		return false
	if not _require(bool(_world_state.request_place_construction("campfire", site_cell).get("ok", false)), "could not place revalidation site"):
		return false
	var site_id := "campfire:%d:%d" % [site_cell.x, site_cell.y]
	_set_priorities(1, 0, 0)
	var selected: Dictionary = _worker.choose_best_job(_worker.collect_available_jobs())
	if not _require(String(selected.get("target_id", "")) == site_id and _world_state.get_construction_reservation(site_id) == _worker.colonist_id, "could not reserve revalidation site"):
		return false
	if not _require(_create_water_ring(site_cell), "could not invalidate reserved construction route"):
		return false
	if not _require(not _worker.start_job(selected), "job started after route became unreachable"):
		return false
	if not _require(_world_state.get_construction_reservation(site_id).is_empty(), "unreachable post-reservation job was not released"):
		return false
	_world_state.request_cancel_construction(site_id)
	_set_priorities(0, 0, 0)
	return true


func _test_priority_and_source_order() -> bool:
	var site_cell: Vector2i = _find_reachable_building_origin(_worker.current_cell + Vector2i(10, -10), "campfire", 3)
	var resource: Dictionary = _find_reachable_resource({})
	var zone_cell: Vector2i = _find_reachable_open_cell(_worker.current_cell + Vector2i(-8, -10), _worker.current_cell, 3)
	if not _require(site_cell != INVALID_CELL and not resource.is_empty() and zone_cell != INVALID_CELL, "could not find priority candidates"):
		return false
	var site_place: Dictionary = _world_state.request_place_construction("campfire", site_cell)
	var designation: Dictionary = _world_state.request_designate_harvest(String(resource.get("resource_id", "")))
	var zone_result: Dictionary = _world_state.request_create_stockpile_zone([zone_cell])
	var item_cell: Vector2i = _find_reachable_storage_access_cell(_worker.current_cell + Vector2i(-4, -6))
	if not _require(item_cell != INVALID_CELL, "could not find priority haul item cell"):
		return false
	var item_result: Dictionary = _world_state.create_ground_item("wood", 1, item_cell)
	if not _require(bool(site_place.get("ok", false)) and bool(designation.get("ok", false)) and bool(zone_result.get("ok", false)) and bool(item_result.get("ok", false)), "could not create priority candidates"):
		return false
	var site_id := "campfire:%d:%d" % [site_cell.x, site_cell.y]
	var order_id: String = String(designation.get("order_id", ""))
	var item_id: String = String(item_result.get("item_id", ""))

	_set_priorities(3, 1, 2)
	var priority_job: Dictionary = _worker.choose_best_job(_worker.collect_available_jobs())
	if not _require(String(priority_job.get("job_type", "")) == Colonist.JOB_TYPE_HARVEST, "lower numeric priority did not win"):
		return false
	_worker._release_job_candidate_reservation(priority_job, "j1_priority_complete")

	_set_priorities(2, 2, 2)
	var equal_job: Dictionary = _worker.choose_best_job(_worker.collect_available_jobs())
	if not _require(String(equal_job.get("job_type", "")) == Colonist.JOB_TYPE_CONSTRUCT, "equal priority did not preserve construction-first source order"):
		return false
	_worker._release_job_candidate_reservation(equal_job, "j1_equal_priority_complete")

	_world_state.request_cancel_construction(site_id)
	_world_state.request_cancel_harvest_order(order_id)
	_world_state.remove_ground_item(item_id)
	_world_state.request_remove_stockpile_zone(String(zone_result.get("zone_id", "")))
	_set_priorities(0, 0, 0)
	return true


func _test_transient_export_boundary() -> bool:
	var colonist_record: Dictionary = _worker.export_state()
	var save_service := SaveGameServiceRef.new()
	var save_data: Dictionary = save_service.build_save_data(_main.get_node("WorldGenerator"), _world_state, _chunk_manager, _manager)
	for forbidden_key: String in ["job_type", "reservation_result", "current_path", "path_index"]:
		if not _require(not _contains_key_recursive(colonist_record, forbidden_key), "colonist export contains transient %s" % forbidden_key):
			return false
		if not _require(not _contains_key_recursive(save_data, forbidden_key), "save export contains transient %s" % forbidden_key):
			return false
	return true


func _find_open_cluster(origin: Vector2i, offsets: Array[Vector2i]) -> Vector2i:
	for radius in range(48):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := origin + Vector2i(x, y)
				var valid := true
				for offset: Vector2i in offsets:
					if not _is_open_cell(candidate + offset):
						valid = false
						break
				if valid:
					return candidate
	return INVALID_CELL


func _find_placeable_cluster(origin: Vector2i, building_id: String, offsets: Array[Vector2i]) -> Vector2i:
	for radius in range(48):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := origin + Vector2i(x, y)
				if not bool(_world_state.validate_construction_placement(building_id, candidate).get("ok", false)):
					continue
				var valid := true
				for offset: Vector2i in offsets:
					if offset != Vector2i.ZERO and not _is_open_cell(candidate + offset):
						valid = false
						break
				if valid:
					return candidate
	return INVALID_CELL


func _find_reachable_building_origin(origin: Vector2i, building_id: String, minimum_steps: int) -> Vector2i:
	for radius in range(48):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := origin + Vector2i(x, y)
				if not bool(_world_state.validate_construction_placement(building_id, candidate).get("ok", false)):
					continue
				var path: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, _worker.current_cell, candidate)
				if bool(path.get("reachable", false)) and (path.get("path", []) as Array).size() >= minimum_steps:
					return candidate
	return INVALID_CELL


func _find_reachable_placeable_cluster(origin: Vector2i, building_id: String, excluded_cells: Dictionary) -> Vector2i:
	for radius in range(48):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := origin + Vector2i(x, y)
				if excluded_cells.has(candidate) or not bool(_world_state.validate_construction_placement(building_id, candidate).get("ok", false)):
					continue
				if not _has_open_cardinals(candidate):
					continue
				var path: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, _worker.current_cell, candidate)
				if bool(path.get("reachable", false)):
					return candidate
	return INVALID_CELL


func _find_reachable_open_cell(origin: Vector2i, from_cell: Vector2i, minimum_steps: int = 1) -> Vector2i:
	for radius in range(48):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := origin + Vector2i(x, y)
				if not _is_open_cell(candidate):
					continue
				var path: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, from_cell, candidate)
				if bool(path.get("reachable", false)) and (path.get("path", []) as Array).size() >= minimum_steps:
					return candidate
	return INVALID_CELL


func _find_haul_item_cell(origin: Vector2i, destination: Vector2i) -> Vector2i:
	for radius in range(48):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := origin + Vector2i(x, y)
				if not _is_open_cell(candidate):
					continue
				var pickup: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, _worker.current_cell, candidate)
				var deposit: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, candidate, destination)
				if bool(pickup.get("reachable", false)) and bool(deposit.get("reachable", false)):
					return candidate
	return INVALID_CELL


func _find_reachable_storage_access_cell(origin: Vector2i) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for component: Dictionary in _world_state.get_storage_components():
		var occupied: Array = component.get("occupied_cells", [])
		for occupied_cell: Vector2i in occupied:
			for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
				var cell: Vector2i = occupied_cell + offset
				if not occupied.has(cell) and not candidates.has(cell):
					candidates.append(cell)
	candidates.sort_custom(func(first: Vector2i, second: Vector2i) -> bool:
		var first_distance: int = first.distance_squared_to(origin)
		var second_distance: int = second.distance_squared_to(origin)
		return first_distance < second_distance if first_distance != second_distance else (first.y < second.y if first.y != second.y else first.x < second.x)
	)
	for candidate: Vector2i in candidates:
		if not _is_open_cell(candidate):
			continue
		var path: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, _worker.current_cell, candidate)
		if bool(path.get("reachable", false)):
			return candidate
	return INVALID_CELL


func _find_reachable_resource(excluded_ids: Dictionary) -> Dictionary:
	var resources: Array[Dictionary] = _chunk_manager.get_loaded_resources_in_cell_rect(Rect2i(Vector2i(-4096, -4096), Vector2i(8192, 8192)))
	resources.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return String(first.get("resource_id", "")) < String(second.get("resource_id", ""))
	)
	for resource: Dictionary in resources:
		var resource_id: String = String(resource.get("resource_id", ""))
		var cell: Vector2i = resource.get("cell", INVALID_CELL)
		if excluded_ids.has(resource_id) or not _has_open_cardinals(cell):
			continue
		var path: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, _worker.current_cell, cell, {"allow_target_resource": true})
		if bool(path.get("reachable", false)):
			return resource
	return {}


func _find_reachable_resource_pair() -> Array[Dictionary]:
	var first: Dictionary = _find_reachable_resource({})
	if first.is_empty():
		return []
	var excluded := {String(first.get("resource_id", "")): true}
	var resources: Array[Dictionary] = _chunk_manager.get_loaded_resources_in_cell_rect(Rect2i(Vector2i(-4096, -4096), Vector2i(8192, 8192)))
	resources.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("resource_id", "")) < String(right.get("resource_id", ""))
	)
	for second: Dictionary in resources:
		var resource_id: String = String(second.get("resource_id", ""))
		var cell: Vector2i = second.get("cell", INVALID_CELL)
		if excluded.has(resource_id) or Vector2i(first.get("cell", INVALID_CELL)).distance_squared_to(cell) < 144 or not _has_open_cardinals(cell):
			continue
		var path: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, _worker.current_cell, cell, {"allow_target_resource": true})
		if bool(path.get("reachable", false)):
			return [first, second]
	return []


func _has_open_cardinals(cell: Vector2i) -> bool:
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		if not _is_open_cell(cell + offset):
			return false
	return true


func _is_open_cell(cell: Vector2i) -> bool:
	if not _chunk_manager.is_cell_loaded(cell):
		return false
	var tile: Dictionary = _chunk_manager.get_effective_tile_info(cell)
	var terrain: String = String(tile.get("terrain", ""))
	return (
		bool(tile.get("walkable", false))
		and terrain != "WATER"
		and terrain != "ROCK_WALL"
		and not bool(tile.get("mineable", false))
		and not _chunk_manager.is_cell_blocked_by_resource(cell)
		and _world_state.get_construction_site_at_cell(cell).is_empty()
		and not _world_state.is_cell_in_stockpile_zone(cell)
	)


func _create_water_ring(center: Vector2i) -> bool:
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var result: Dictionary = _chunk_manager.request_place_manual_tile(center + offset, "WATER")
		if not bool(result.get("ok", false)):
			return false
	return true


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
