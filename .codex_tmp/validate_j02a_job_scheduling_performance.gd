extends SceneTree

## Purpose: Validate bounded, throttled colonist job scheduling under a large harvest queue.
## Responsibility: Measure Colonist-owned transient counters without changing gameplay authority.
## Assumption: WATER rings are disposable validation-only barriers in this isolated scene.

const MainScene = preload("res://scenes/Main.tscn")
const ReachabilityQueryRef = preload("res://scripts/world/reachability_query.gd")
const SaveGameServiceRef = preload("res://scripts/simulation/save_game_service.gd")

const INVALID_CELL := Vector2i(2147483647, 2147483647)
const MINIMUM_HARVEST_ORDERS := 20
const TARGET_HARVEST_ORDERS := 40

var _failed: bool = false
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
	push_error("J02A job scheduling performance validation failed: %s" % message)
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
	if not _require(_world_state != null and _chunk_manager != null and _manager != null, "Main scene did not load simulation owners"):
		return
	_freeze_runtime()
	var colonists: Array[Colonist] = _get_colonists()
	if not _require(not colonists.is_empty(), "Main scene did not spawn a colonist"):
		return
	_worker = colonists[0]
	for colonist: Colonist in colonists:
		colonist.set_work_priority("Construct", 0)
		colonist.set_work_priority("Harvest", 0)
		colonist.set_work_priority("Haul", 0)

	if not _test_idle_evaluation_cooldown():
		return
	var fixture: Dictionary = _create_large_harvest_fixture()
	if fixture.is_empty() or _failed:
		return
	if not _test_bounded_reachable_selection(fixture):
		return
	if not _test_transient_save_boundary():
		return

	print("J02A VALIDATION PASSED: cooldown throttling, bounded harvest path checks, unreachable skipping, reachable claim, counters, and save exclusion")
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


func _test_idle_evaluation_cooldown() -> bool:
	_worker.reset_job_scheduling_debug_counters()
	_worker.set("_job_evaluation_cooldown_remaining", 0.0)
	_worker.set("_pause_timer", 0.0)
	_worker._process_idle(0.0)
	var first: Dictionary = _worker.get_job_scheduling_debug_counters()
	if not _require(int(first.get("job_evaluations_attempted", 0)) == 1, "first idle scheduling evaluation was not recorded"):
		return false
	for _frame in range(10):
		_worker.set("_pause_timer", 0.0)
		_worker._process_idle(0.01)
	var throttled: Dictionary = _worker.get_job_scheduling_debug_counters()
	if not _require(int(throttled.get("job_evaluations_attempted", 0)) == 1, "idle colonist evaluated jobs every frame during cooldown"):
		return false
	_worker.set("_pause_timer", 0.0)
	_worker._process_idle(float(throttled.get("cooldown_interval", 0.0)))
	var resumed: Dictionary = _worker.get_job_scheduling_debug_counters()
	return _require(int(resumed.get("job_evaluations_attempted", 0)) == 2, "job evaluation did not resume after cooldown")


func _create_large_harvest_fixture() -> Dictionary:
	var resources: Array[Dictionary] = _chunk_manager.get_loaded_resources_in_cell_rect(Rect2i(Vector2i(-4096, -4096), Vector2i(8192, 8192)))
	resources.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return String(first.get("resource_id", "")) < String(second.get("resource_id", ""))
	)
	var pair: Array[Dictionary] = _find_reachable_resource_pair(resources)
	if not _require(pair.size() == 2, "could not find two reachable harvest resources"):
		return {}
	var blocked: Dictionary = pair[0]
	var reachable: Dictionary = pair[1]
	var blocked_id: String = String(blocked.get("resource_id", ""))
	var reachable_id: String = String(reachable.get("resource_id", ""))
	var designated_ids: Dictionary = {}
	for resource: Dictionary in [blocked, reachable]:
		var result: Dictionary = _world_state.request_designate_harvest(String(resource.get("resource_id", "")))
		if not _require(bool(result.get("ok", false)), "could not designate required harvest fixture resource"):
			return {}
		designated_ids[String(resource.get("resource_id", ""))] = String(result.get("order_id", ""))
	for resource: Dictionary in resources:
		var resource_id: String = String(resource.get("resource_id", ""))
		if designated_ids.size() >= TARGET_HARVEST_ORDERS:
			break
		if designated_ids.has(resource_id) or resource_id < reachable_id:
			continue
		var result: Dictionary = _world_state.request_designate_harvest(resource_id)
		if bool(result.get("ok", false)):
			designated_ids[resource_id] = String(result.get("order_id", ""))
	if not _require(designated_ids.size() >= MINIMUM_HARVEST_ORDERS, "not enough loaded resources for a large harvest queue"):
		return {}
	if not _require(_create_water_ring(blocked.get("cell", INVALID_CELL)), "could not isolate the first harvest candidate"):
		return {}
	var reachable_path: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, _worker.current_cell, reachable.get("cell", INVALID_CELL), {"allow_target_resource": true})
	if not _require(bool(reachable_path.get("reachable", false)), "reachable harvest fixture was blocked by isolation setup"):
		return {}
	return {
		"blocked_order_id": designated_ids[blocked_id],
		"reachable_order_id": designated_ids[reachable_id],
		"designation_count": designated_ids.size(),
	}


func _test_bounded_reachable_selection(fixture: Dictionary) -> bool:
	_worker.set_work_priority("Harvest", 1)
	_worker.reset_job_scheduling_debug_counters()
	var jobs: Array[Dictionary] = _worker.collect_available_jobs()
	var counters: Dictionary = _worker.get_job_scheduling_debug_counters()
	if not _require(jobs.size() == 1 and String(jobs[0].get("job_type", "")) == Colonist.JOB_TYPE_HARVEST, "harvest decision did not stop at the first reachable candidate"):
		return false
	if not _require(String(jobs[0].get("target_id", "")) == String(fixture.get("reachable_order_id", "")), "unreachable first harvest candidate was not skipped"):
		return false
	if not _require(int(counters.get("path_queries_failed", 0)) >= 1 and int(counters.get("path_queries_succeeded", 0)) >= 1, "path counters did not record unreachable and reachable candidates"):
		return false
	if not _require(int(counters.get("candidates_considered", 0)) == 2 and int(counters.get("path_queries_requested", 0)) == 2, "one decision did not stop after the first reachable harvest candidate"):
		return false
	if not _require(int(counters.get("path_queries_requested", 0)) < int(fixture.get("designation_count", 0)), "one decision path-queried the full harvest queue"):
		return false
	var selected: Dictionary = _worker.choose_best_job(jobs)
	if not _require(not selected.is_empty() and _worker.start_job(selected), "colonist could not claim the reachable harvest job"):
		return false
	if not _require(_world_state.get_harvest_order_reservation(String(fixture.get("blocked_order_id", ""))).is_empty(), "unreachable harvest candidate was reserved"):
		return false
	counters = _worker.get_job_scheduling_debug_counters()
	if not _require(int(counters.get("reservations_attempted", 0)) == 1 and int(counters.get("reservations_succeeded", 0)) == 1, "reservation counters did not record the claimed job"):
		return false
	_worker._finish_harvest_job("j02a_validation_cleanup")
	return true


func _test_transient_save_boundary() -> bool:
	var colonist_record: Dictionary = _worker.export_state()
	var save_service := SaveGameServiceRef.new()
	var save_data: Dictionary = save_service.build_save_data(_main.get_node("WorldGenerator"), _world_state, _chunk_manager, _manager)
	for forbidden_key: String in [
		"job_scheduling_counters",
		"job_evaluation_cooldown_remaining",
		"job_evaluations_attempted",
		"path_queries_requested",
		"reservations_attempted",
	]:
		if not _require(not _contains_key_recursive(colonist_record, forbidden_key), "colonist export contains transient %s" % forbidden_key):
			return false
		if not _require(not _contains_key_recursive(save_data, forbidden_key), "save export contains transient %s" % forbidden_key):
			return false
	return true


func _find_reachable_resource_pair(resources: Array[Dictionary]) -> Array[Dictionary]:
	for first_index in range(resources.size()):
		var first: Dictionary = resources[first_index]
		var first_cell: Vector2i = first.get("cell", INVALID_CELL)
		if not _has_loaded_cardinals(first_cell) or not _is_resource_reachable(first_cell):
			continue
		for second_index in range(first_index + 1, resources.size()):
			var second: Dictionary = resources[second_index]
			var second_cell: Vector2i = second.get("cell", INVALID_CELL)
			if first_cell.distance_squared_to(second_cell) < 144:
				continue
			if _has_loaded_cardinals(second_cell) and _is_resource_reachable(second_cell):
				return [first, second]
	return []


func _is_resource_reachable(cell: Vector2i) -> bool:
	var path: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, _worker.current_cell, cell, {"allow_target_resource": true})
	return bool(path.get("reachable", false))


func _has_loaded_cardinals(cell: Vector2i) -> bool:
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		if not _chunk_manager.is_cell_loaded(cell + offset):
			return false
	return true


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
