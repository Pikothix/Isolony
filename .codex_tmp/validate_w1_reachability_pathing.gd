extends SceneTree

## Purpose: Validate W1 loaded-cell reachability and transient colonist path following.
## Responsibility: Exercise path rules, reachable movement, unreachable job filtering, need seeking, and save exclusions.
## Assumption: Manual WATER/ROCK_WALL overrides create deterministic barriers only in this disposable validation scene.

const MainScene = preload("res://scenes/Main.tscn")
const ReachabilityQueryRef = preload("res://scripts/world/reachability_query.gd")
const SaveGameServiceRef = preload("res://scripts/simulation/save_game_service.gd")

const INVALID_CELL := Vector2i(2147483647, 2147483647)

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
	push_error("W1 reachability validation failed: %s" % message)
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
	_freeze_runtime()
	var colonists: Array[Colonist] = _get_colonists()
	if not _require(not colonists.is_empty(), "no colonist available"):
		return
	_worker = colonists[0]
	_set_worker_priorities(false, false, false)

	if not _test_basic_reachability_and_blocked_terrain():
		return
	if not _test_construction_and_resource_occupancy():
		return
	if not _test_stockpile_zone_non_blocking():
		return
	if not _test_colonist_follows_multi_cell_path():
		return
	if not _test_unreachable_jobs_are_not_reserved():
		return
	if not _test_need_seeking_requires_reachability():
		return
	if not _test_path_import_and_save_exclusion():
		return

	print("W1 REACHABILITY VALIDATION PASSED: loaded-cell BFS, occupancy rules, transient path following, unreachable job filtering, needs, and save exclusion")
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


func _set_worker_priorities(construct_enabled: bool, harvest_enabled: bool, haul_enabled: bool) -> void:
	_worker.set_work_priority("Construct", 1 if construct_enabled else 0)
	_worker.set_work_priority("Harvest", 1 if harvest_enabled else 0)
	_worker.set_work_priority("Haul", 1 if haul_enabled else 0)


func _test_basic_reachability_and_blocked_terrain() -> bool:
	var open_cluster: Vector2i = _find_open_cluster(_worker.current_cell, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(0, 1), Vector2i(0, -1)])
	if not _require(open_cluster != INVALID_CELL, "could not find basic reachability cells"):
		return false
	var start: Vector2i = open_cluster
	var target: Vector2i = open_cluster + Vector2i(3, 0)
	var reachable: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, start, target)
	if not _require(bool(reachable.get("reachable", false)) and (reachable.get("path", []) as Array).size() >= 3, "walkable loaded cells were not reachable"):
		return false

	var ring_target: Vector2i = _find_open_cluster(open_cluster + Vector2i(8, 0), [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i(2, 0)])
	if not _require(ring_target != INVALID_CELL, "could not find WATER barrier cluster"):
		return false
	if not _require(_create_water_ring(ring_target), "could not create WATER barrier"):
		return false
	var ring_result: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, ring_target + Vector2i(2, 0), ring_target)
	if not _require(not bool(ring_result.get("reachable", true)), "WATER ring did not make target unreachable"):
		return false

	var cliff_target: Vector2i = _find_open_cluster(open_cluster + Vector2i(-8, 0), [Vector2i.ZERO, Vector2i.RIGHT])
	if not _require(cliff_target != INVALID_CELL, "could not find ROCK_WALL test cell"):
		return false
	var cliff_override: Dictionary = _chunk_manager.request_place_manual_tile(cliff_target, "ROCK_WALL")
	if not _require(bool(cliff_override.get("ok", false)), "could not create ROCK_WALL override"):
		return false
	var cliff_result: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, cliff_target + Vector2i.RIGHT, cliff_target)
	return _require(not bool(cliff_result.get("reachable", true)), "ROCK_WALL target was reachable")


func _test_construction_and_resource_occupancy() -> bool:
	var center: Vector2i = _find_placeable_cluster(_worker.current_cell + Vector2i(0, 10), "campfire", [Vector2i.ZERO, Vector2i(-2, 0), Vector2i(2, 0)])
	if not _require(center != INVALID_CELL, "could not find construction occupancy cluster"):
		return false
	var placement: Dictionary = _world_state.request_place_construction("campfire", center)
	if not _require(bool(placement.get("ok", false)), "could not place construction occupancy site"):
		return false
	var around_site: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, center + Vector2i(-2, 0), center + Vector2i(2, 0))
	if not _require(bool(around_site.get("reachable", false)) and center not in around_site.get("path", []), "path did not avoid construction footprint"):
		return false
	var to_site: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, center + Vector2i(-2, 0), center, {"allow_target_construction": true})
	if not _require(bool(to_site.get("reachable", false)) and (to_site.get("path", []) as Array).back() == center, "construction target exception failed"):
		return false
	var site_id := "campfire:%d:%d" % [center.x, center.y]
	if not _require(bool(_world_state.request_cancel_construction(site_id).get("ok", false)), "could not remove construction occupancy site"):
		return false

	var resources: Array[Dictionary] = _chunk_manager.get_loaded_resources_in_cell_rect(Rect2i(Vector2i(-4096, -4096), Vector2i(8192, 8192)))
	var resource: Dictionary = _find_resource_with_loaded_neighbours(resources, {})
	if not _require(not resource.is_empty(), "no resource available for occupancy test"):
		return false
	var resource_cell: Vector2i = resource.get("cell", INVALID_CELL)
	var resource_start: Vector2i = _find_reachable_open_cell(resource_cell, 3)
	if not _require(resource_start != INVALID_CELL, "could not find resource path start"):
		return false
	var blocked_resource: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, resource_start, resource_cell)
	if not _require(not bool(blocked_resource.get("reachable", true)), "resource cell was traversable without target exception"):
		return false
	var target_resource: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, resource_start, resource_cell, {"allow_target_resource": true})
	return _require(bool(target_resource.get("reachable", false)) and (target_resource.get("path", []) as Array).back() == resource_cell, "resource target exception failed")


func _test_stockpile_zone_non_blocking() -> bool:
	var zone_cell: Vector2i = _find_open_cluster(_worker.current_cell + Vector2i(-10, -8), [Vector2i.ZERO, Vector2i(-3, 0)])
	if not _require(zone_cell != INVALID_CELL, "could not find stockpile reachability cell"):
		return false
	var zone_result: Dictionary = _world_state.request_create_stockpile_zone([zone_cell])
	if not _require(bool(zone_result.get("ok", false)), "could not create stockpile zone"):
		return false
	var path_result: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, zone_cell + Vector2i(-3, 0), zone_cell)
	var reachable: bool = bool(path_result.get("reachable", false)) and (path_result.get("path", []) as Array).back() == zone_cell
	_world_state.request_remove_stockpile_zone(String(zone_result.get("zone_id", "")))
	return _require(reachable, "stockpile zone blocked traversal")


func _test_colonist_follows_multi_cell_path() -> bool:
	var start: Vector2i = _find_open_cluster(_worker.current_cell + Vector2i(8, 8), [Vector2i.ZERO])
	if not _require(start != INVALID_CELL, "could not find movement start"):
		return false
	_set_worker_cell(start)
	var site_cell: Vector2i = _find_reachable_building_origin(start, "campfire", 4)
	if not _require(site_cell != INVALID_CELL, "could not find multi-cell construction target"):
		return false
	if not _require(bool(_world_state.add_resource("wood", 10).get("ok", false)), "could not fund movement construction"):
		return false
	if not _require(bool(_world_state.request_place_construction("campfire", site_cell).get("ok", false)), "could not place movement construction"):
		return false
	_set_worker_priorities(true, false, false)
	var candidates: Array[Dictionary] = _worker.collect_available_jobs()
	var job: Dictionary = _worker.choose_best_job(candidates)
	if not _require(not job.is_empty() and _worker.start_job(job), "reachable construction job did not start"):
		return false
	if not _require(_worker.get_current_path().size() >= 4, "construction movement did not receive a multi-cell path"):
		return false
	_worker.move_speed = 1000.0
	var visited: Dictionary = {_worker.current_cell: true}
	for _step in range(240):
		_worker._process(0.02)
		visited[_worker.current_cell] = true
		if _worker.get_activity_name() == "constructing":
			break
	if not _require(_worker.get_activity_name() == "constructing", "colonist did not finish the cell path to construction"):
		return false
	if not _require(visited.size() >= 4, "colonist skipped intermediate path cells"):
		return false
	var site_id := "campfire:%d:%d" % [site_cell.x, site_cell.y]
	_worker._finish_construction_job("w1_validation_complete")
	_world_state.request_cancel_construction(site_id)
	_set_worker_priorities(false, false, false)
	return true


func _test_unreachable_jobs_are_not_reserved() -> bool:
	if not _test_unreachable_construction():
		return false
	if not _test_unreachable_harvest():
		return false
	return _test_unreachable_haul()


func _test_unreachable_construction() -> bool:
	var site_cell: Vector2i = _find_placeable_cluster(_worker.current_cell + Vector2i(12, 0), "campfire", [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP])
	if not _require(site_cell != INVALID_CELL, "could not find unreachable construction site"):
		return false
	if not _require(bool(_world_state.request_place_construction("campfire", site_cell).get("ok", false)), "could not place unreachable construction site"):
		return false
	if not _require(_create_water_ring(site_cell), "could not block construction site"):
		return false
	_set_worker_priorities(true, false, false)
	var jobs: Array[Dictionary] = _worker.collect_available_jobs()
	var has_construct: bool = jobs.any(func(job: Dictionary) -> bool: return String(job.get("job_type", "")) == Colonist.JOB_TYPE_CONSTRUCT)
	var site_id := "campfire:%d:%d" % [site_cell.x, site_cell.y]
	var valid: bool = not has_construct and _world_state.get_construction_reservation(site_id).is_empty()
	_world_state.request_cancel_construction(site_id)
	_set_worker_priorities(false, false, false)
	return _require(valid, "unreachable construction job was offered or reserved")


func _test_unreachable_harvest() -> bool:
	var resources: Array[Dictionary] = _chunk_manager.get_loaded_resources_in_cell_rect(Rect2i(Vector2i(-4096, -4096), Vector2i(8192, 8192)))
	var resource: Dictionary = _find_resource_with_loaded_neighbours(resources, {})
	if not _require(not resource.is_empty(), "no resource available for unreachable harvest"):
		return false
	var resource_cell: Vector2i = resource.get("cell", INVALID_CELL)
	if not _require(_create_water_ring(resource_cell), "could not block harvest resource"):
		return false
	var designation: Dictionary = _world_state.request_designate_harvest(String(resource.get("resource_id", "")))
	if not _require(bool(designation.get("ok", false)), "could not designate unreachable harvest"):
		return false
	_set_worker_priorities(false, true, false)
	var jobs: Array[Dictionary] = _worker.collect_available_jobs()
	var has_harvest: bool = jobs.any(func(job: Dictionary) -> bool: return String(job.get("job_type", "")) == Colonist.JOB_TYPE_HARVEST)
	var order_id: String = String(designation.get("order_id", ""))
	var valid: bool = not has_harvest and _world_state.get_harvest_order_reservation(order_id).is_empty()
	_world_state.request_cancel_harvest_order(order_id)
	_set_worker_priorities(false, false, false)
	return _require(valid, "unreachable harvest job was offered or reserved")


func _test_unreachable_haul() -> bool:
	var item_cell: Vector2i = _find_open_cluster(_worker.current_cell + Vector2i(-12, 0), [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP])
	var zone_cell: Vector2i = _find_open_cluster(_worker.current_cell + Vector2i(-8, 10), [Vector2i.ZERO])
	if not _require(item_cell != INVALID_CELL and zone_cell != INVALID_CELL, "could not find unreachable haul cells"):
		return false
	var zone_result: Dictionary = _world_state.request_create_stockpile_zone([zone_cell])
	var item_result: Dictionary = _world_state.create_ground_item("stone", 2, item_cell)
	if not _require(bool(zone_result.get("ok", false)) and bool(item_result.get("ok", false)), "could not create unreachable haul state"):
		return false
	if not _require(_create_water_ring(item_cell), "could not block haul item"):
		return false
	_set_worker_priorities(false, false, true)
	var jobs: Array[Dictionary] = _worker.collect_available_jobs()
	var has_haul: bool = jobs.any(func(job: Dictionary) -> bool: return String(job.get("job_type", "")) == Colonist.JOB_TYPE_HAUL)
	var item_id: String = String(item_result.get("item_id", ""))
	var valid: bool = not has_haul and _world_state.get_haul_item_reservation(item_id).is_empty()
	_world_state.remove_ground_item(item_id)
	_world_state.request_remove_stockpile_zone(String(zone_result.get("zone_id", "")))
	_set_worker_priorities(false, false, false)
	return _require(valid, "unreachable haul job was offered or reserved")


func _test_need_seeking_requires_reachability() -> bool:
	var campfire_cell: Vector2i = _find_reachable_building_origin(_worker.current_cell, "campfire", 3)
	if not _require(campfire_cell != INVALID_CELL, "could not find Campfire for need seeking"):
		return false
	if not _require(bool(_world_state.add_resource("wood", 5).get("ok", false)), "could not fund need-seeking Campfire"):
		return false
	if not _require(bool(_world_state.request_place_construction("campfire", campfire_cell).get("ok", false)), "could not place need-seeking Campfire"):
		return false
	var campfire_id := "campfire:%d:%d" % [campfire_cell.x, campfire_cell.y]
	if not _require(bool(_world_state.request_progress_construction(campfire_id, 10.0).get("completed", false)), "could not complete need-seeking Campfire"):
		return false
	_world_state.get_time_state().import_state({"current_day": 1, "current_minutes": 1200.0, "paused": true})

	var reachable_start: Vector2i = _find_reachable_open_cell(campfire_cell, 6)
	if not _require(reachable_start != INVALID_CELL and Vector2(reachable_start - campfire_cell).length() > 3.0, "could not find reachable need start"):
		return false
	_set_worker_cell(reachable_start)
	_worker.warmth = 10.0
	_worker.shelter = 100.0
	var started: bool = _worker._try_seek_warmth()
	if not _require(started and _worker.get_activity_name() == "seeking_warmth" and _worker.has_active_path(), "reachable warmth seeking did not start with a path"):
		return false
	_worker._enter_idle()

	var blocked_start: Vector2i = _find_open_cluster(campfire_cell + Vector2i(10, 10), [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP])
	if not _require(blocked_start != INVALID_CELL and Vector2(blocked_start - campfire_cell).length() > 3.0, "could not find unreachable need start"):
		return false
	_set_worker_cell(blocked_start)
	if not _require(_create_water_ring(blocked_start), "could not block need-seeking colonist"):
		return false
	_worker.warmth = 10.0
	_worker.shelter = 100.0
	var blocked_started: bool = _worker._try_seek_warmth()
	return _require(not blocked_started and _worker.get_activity_name() == "idle" and not _worker.has_active_path(), "unreachable warmth seeking started")


func _test_path_import_and_save_exclusion() -> bool:
	var start: Vector2i = _find_open_cluster(_worker.current_cell + Vector2i(4, -10), [Vector2i.ZERO])
	if not _require(start != INVALID_CELL, "could not find path reset start"):
		return false
	_set_worker_cell(start)
	var target: Vector2i = _find_reachable_open_cell(start, 4)
	if not _require(target != INVALID_CELL, "could not find path reset target"):
		return false
	var path_result: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, start, target)
	_worker._apply_path(path_result, target)
	_worker.set("_activity", Colonist.Activity.WANDERING)
	if not _require(_worker.has_active_path(), "test colonist did not receive a transient path"):
		return false
	var record: Dictionary = _worker.export_state()
	if not _require(not _contains_key_recursive(record, "current_path") and not _contains_key_recursive(record, "path_index"), "colonist export contains transient path state"):
		return false
	var import_result: Dictionary = _worker.import_state(record)
	if not _require(bool(import_result.get("ok", false)) and _worker.get_activity_name() == "idle" and _worker.get_current_path().is_empty() and _worker.target_cell == _worker.current_cell, "colonist import did not clear path state"):
		return false
	var save_service := SaveGameServiceRef.new()
	var save_data: Dictionary = save_service.build_save_data(_main.get_node("WorldGenerator"), _world_state, _chunk_manager, _manager)
	return _require(not _contains_key_recursive(save_data, "current_path") and not _contains_key_recursive(save_data, "path_index"), "save export contains transient path state")


func _find_open_cluster(origin: Vector2i, offsets: Array[Vector2i]) -> Vector2i:
	for radius in range(48):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := origin + Vector2i(x, y)
				var valid: bool = true
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
				var valid: bool = true
				for offset: Vector2i in offsets:
					if offset != Vector2i.ZERO and not _is_open_cell(candidate + offset):
						valid = false
						break
				if valid:
					return candidate
	return INVALID_CELL


func _find_reachable_building_origin(start: Vector2i, building_id: String, minimum_steps: int) -> Vector2i:
	for radius in range(minimum_steps, 40):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := start + Vector2i(x, y)
				if not bool(_world_state.validate_construction_placement(building_id, candidate).get("ok", false)):
					continue
				var path: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, start, candidate)
				if bool(path.get("reachable", false)) and (path.get("path", []) as Array).size() >= minimum_steps:
					return candidate
	return INVALID_CELL


func _find_reachable_open_cell(origin: Vector2i, minimum_steps: int) -> Vector2i:
	for radius in range(minimum_steps, 40):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := origin + Vector2i(x, y)
				if not _is_open_cell(candidate):
					continue
				var path: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, origin, candidate)
				if bool(path.get("reachable", false)) and (path.get("path", []) as Array).size() >= minimum_steps:
					return candidate
	return INVALID_CELL


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


func _find_resource_with_loaded_neighbours(resources: Array[Dictionary], excluded_ids: Dictionary) -> Dictionary:
	for resource: Dictionary in resources:
		var resource_id: String = String(resource.get("resource_id", ""))
		var cell: Vector2i = resource.get("cell", INVALID_CELL)
		if excluded_ids.has(resource_id):
			continue
		var neighbours_loaded: bool = true
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			if not _chunk_manager.is_cell_loaded(cell + offset):
				neighbours_loaded = false
				break
		if neighbours_loaded:
			return resource
	return {}


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
