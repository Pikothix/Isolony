extends SceneTree

## Purpose: Validate the version-2 authoritative save contract through a fresh Main scene.
## Responsibility: Build representative state through current APIs, round-trip it, and verify transient exclusions.
## Assumption: Direct colonist field setup is test-only because current owned position/needs fields have no public setters.

const MainScene = preload("res://scenes/Main.tscn")
const SaveGameServiceRef = preload("res://scripts/simulation/save_game_service.gd")

const INVALID_CELL := Vector2i(2147483647, 2147483647)
const FLOAT_TOLERANCE := 0.0001

var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("S1 save contract validation failed: %s" % message)
	quit(1)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _run() -> void:
	var source: Node = MainScene.instantiate()
	var source_generator: WorldGenerator = source.get_node("WorldGenerator") as WorldGenerator
	_configure_source_generation(source_generator)
	root.add_child(source)
	await _wait_frames(160)
	if _failed:
		return

	var source_world_state: Node = source.get("_world_state")
	var source_chunk_manager: ChunkManager = source.get_node("ChunkManager") as ChunkManager
	var source_colonist_manager: ColonistManager = source.get_node("ChunkManager/GameplayYSort/ColonistManager") as ColonistManager
	_freeze_scene(source, source_chunk_manager, source_colonist_manager)
	var setup: Dictionary = _build_representative_state(source, source_generator, source_world_state, source_chunk_manager, source_colonist_manager)
	if _failed:
		return

	var save_service := SaveGameServiceRef.new()
	var source_save: Dictionary = save_service.build_save_data(source_generator, source_world_state, source_chunk_manager, source_colonist_manager)
	if not _require(_save_contains_no_objects(source_save), "save data contains a Node, Resource, or other Object"):
		return
	if not _require(not _contains_forbidden_save_key(source_save), "save data contains transient/projection/cache keys"):
		return

	var target: Node = MainScene.instantiate()
	root.add_child(target)
	var target_world_state: Node = target.get("_world_state")
	var target_chunk_manager: ChunkManager = target.get_node("ChunkManager") as ChunkManager
	var target_colonist_manager: ColonistManager = target.get_node("ChunkManager/GameplayYSort/ColonistManager") as ColonistManager
	_freeze_scene(target, target_chunk_manager, target_colonist_manager)
	if not _require(source != target, "round trip did not use a distinct Main instance"):
		return

	var load_result: Dictionary = save_service.apply_save_data(
		source_save,
		target.get_node("WorldGenerator"),
		target_world_state,
		target_chunk_manager,
		target_colonist_manager
	)
	if not _require(bool(load_result.get("ok", false)), "fresh-scene load failed: %s" % String(load_result.get("reason", "unknown"))):
		return
	_freeze_scene(target, target_chunk_manager, target_colonist_manager)

	var target_save: Dictionary = save_service.build_save_data(
		target.get_node("WorldGenerator"),
		target_world_state,
		target_chunk_manager,
		target_colonist_manager
	)
	var normalized_source: Variant = _normalize_value(source_save, "$")
	var normalized_target: Variant = _normalize_value(target_save, "$")
	if not _compare_values(normalized_source, normalized_target, "$"):
		return

	if not _verify_representative_state(target_world_state, target_chunk_manager, target_colonist_manager, setup):
		return
	if not _verify_transient_state_reset(target, target_world_state, target_colonist_manager, setup):
		return
	if not _run_negative_contract_checks(save_service, source_save):
		return

	print("S1 SAVE CONTRACT VALIDATION PASSED: fresh-scene authoritative round trip, transient reset, and malformed-save checks")
	quit(0)


func _configure_source_generation(generator: WorldGenerator) -> void:
	## Configure before entering the tree so every source chunk uses the saved generation state.
	generator.seed = 24681357
	generator.terrain_scale = 1.25
	generator.landmass_scale = 12.5
	generator.water_max = 0.44
	generator.coast_max = 0.50
	generator.stone_min = 0.76
	generator.dry_max = 0.27
	generator.wet_min = 0.70
	generator.saturated_min = 0.84


func _wait_frames(frame_count: int) -> void:
	for _frame in range(frame_count):
		await process_frame


func _freeze_scene(main: Node, chunk_manager: ChunkManager, colonist_manager: ColonistManager) -> void:
	main.set_process(false)
	chunk_manager.set_process(false)
	colonist_manager.set_process(false)
	for child: Node in colonist_manager.get_children():
		if child is Colonist:
			child.set_process(false)


func _build_representative_state(main: Node, generator: WorldGenerator, world_state: Node, chunk_manager: ChunkManager, colonist_manager: ColonistManager) -> Dictionary:
	var colonists: Array[Colonist] = _get_colonists(colonist_manager)
	if not _require(colonists.size() >= 3, "representative setup requires at least three colonists"):
		return {}
	var worker: Colonist = colonists[0]
	var harvest_reservation_worker: Colonist = colonists[1]
	var construction_reservation_worker: Colonist = colonists[2]

	var time_result: Dictionary = world_state.get_time_state().import_state({
		"current_day": 7,
		"current_minutes": 1325.5,
		"day_length_minutes": 17.0,
		"time_scale": 2.5,
		"paused": true,
	})
	if not _require(bool(time_result.get("ok", false)), "could not configure representative time state"):
		return {}

	if not _add_resource(world_state, "wood", 80):
		return {}
	if not _add_resource(world_state, "stone", 15):
		return {}
	if not _add_resource(world_state, "food", 5):
		return {}

	var campfire_id: String = _place_and_complete(world_state, "campfire", worker.current_cell + Vector2i(7, 0))
	var cabin_id: String = _place_and_complete(world_state, "cabin", worker.current_cell + Vector2i(-7, 0))
	var storehouse_id: String = _place_and_complete(world_state, "storehouse", worker.current_cell + Vector2i(0, 8))
	if _failed:
		return {}
	if not _require(not campfire_id.is_empty() and not cabin_id.is_empty() and not storehouse_id.is_empty(), "completed building setup failed"):
		return {}
	if not _require(world_state.get_storage_capacity() == 200, "completed Storehouse did not derive capacity 200 in source"):
		return {}

	if not _add_resource(world_state, "wood", 11):
		return {}
	if not _add_resource(world_state, "stone", 7):
		return {}
	if not _add_resource(world_state, "food", 9):
		return {}
	if not _deposit_storehouse_resource(world_state, chunk_manager, "wood", 20, worker.current_cell + Vector2i(0, 10)):
		return {}

	var incomplete_origin: Vector2i = _find_building_origin(world_state, "cabin", worker.current_cell + Vector2i(10, 10))
	if not _require(incomplete_origin != INVALID_CELL, "could not find an incomplete-site origin"):
		return {}
	var incomplete_place: Dictionary = world_state.request_place_construction("cabin", incomplete_origin)
	if not _require(bool(incomplete_place.get("ok", false)), "could not place incomplete Cabin"):
		return {}
	var incomplete_id := "cabin:%d:%d" % [incomplete_origin.x, incomplete_origin.y]
	var construction_reservation: Dictionary = world_state.reserve_construction_site(construction_reservation_worker.colonist_id, incomplete_id)
	if not _require(bool(construction_reservation.get("ok", false)), "could not create transient construction reservation"):
		return {}

	var manual_cell: Vector2i = _find_clean_loaded_cell(world_state, chunk_manager, worker.current_cell + Vector2i(3, -10), [])
	if not _require(manual_cell != INVALID_CELL, "could not find manual-tile cell"):
		return {}
	var manual_result: Dictionary = chunk_manager.request_place_manual_tile(manual_cell, "STONE")
	if not _require(bool(manual_result.get("ok", false)), "manual tile override failed"):
		return {}

	var zone_cell: Vector2i = _find_clean_loaded_cell(world_state, chunk_manager, worker.current_cell + Vector2i(-10, 8), [manual_cell])
	if not _require(zone_cell != INVALID_CELL, "could not find stockpile-zone cell"):
		return {}
	var zone_result: Dictionary = world_state.request_create_stockpile_zone([zone_cell])
	if not _require(bool(zone_result.get("ok", false)), "stockpile-zone creation failed"):
		return {}

	var item_cell: Vector2i = _find_clean_loaded_cell(world_state, chunk_manager, worker.current_cell + Vector2i(10, -8), [manual_cell, zone_cell])
	var carry_destination: Dictionary = world_state.call("_find_storage_component_haul_destination", worker.current_cell, 4)
	var carry_cell: Vector2i = carry_destination.get("cell", INVALID_CELL) if bool(carry_destination.get("ok", false)) else INVALID_CELL
	if not _require(item_cell != INVALID_CELL and carry_cell != INVALID_CELL, "could not find ground-item cells"):
		return {}
	var ground_item_result: Dictionary = world_state.create_ground_item("stone", 3, item_cell)
	var carry_item_result: Dictionary = world_state.create_ground_item("wood", 4, carry_cell)
	if not _require(bool(ground_item_result.get("ok", false)) and bool(carry_item_result.get("ok", false)), "ground-item creation failed"):
		return {}

	var resources: Array[Dictionary] = chunk_manager.get_loaded_resources_in_cell_rect(Rect2i(Vector2i(-4096, -4096), Vector2i(8192, 8192)))
	if not _require(resources.size() >= 3, "representative setup requires at least three loaded resources"):
		return {}

	var depleted_resource_id: String = String(resources[0].get("resource_id", ""))
	var depletion_designation: Dictionary = world_state.request_designate_harvest(depleted_resource_id)
	var depletion_order_id: String = String(depletion_designation.get("order_id", ""))
	if not _require(bool(depletion_designation.get("ok", false)), "depletion-order designation failed"):
		return {}
	if not _require(bool(world_state.reserve_harvest_order(depletion_order_id, worker.colonist_id).get("ok", false)), "depletion-order reservation failed"):
		return {}
	if not _require(bool(world_state.request_complete_harvest_order(depletion_order_id, worker.colonist_id).get("ok", false)), "resource depletion failed"):
		return {}

	var unreserved_resource_id: String = String(resources[1].get("resource_id", ""))
	var unreserved_order: Dictionary = world_state.request_designate_harvest(unreserved_resource_id)
	if not _require(bool(unreserved_order.get("ok", false)), "unreserved harvest-order designation failed"):
		return {}
	var unreserved_order_id: String = String(unreserved_order.get("order_id", ""))

	var reserved_resource_id: String = String(resources[2].get("resource_id", ""))
	var reserved_order: Dictionary = world_state.request_designate_harvest(reserved_resource_id)
	var reserved_order_id: String = String(reserved_order.get("order_id", ""))
	if not _require(bool(reserved_order.get("ok", false)), "reserved harvest-order designation failed"):
		return {}
	if not _require(bool(world_state.reserve_harvest_order(reserved_order_id, harvest_reservation_worker.colonist_id).get("ok", false)), "transient harvest reservation failed"):
		return {}

	## These are authoritative Colonist-owned fields without public setters; direct assignment is test-only.
	worker.set_nickname("S1 Round Trip")
	worker.rest = 73.25
	worker.warmth = 64.5
	worker.shelter = 82.75
	worker.hunger = 41.125
	worker.set_work_priority("Construct", 0)
	worker.set_work_priority("Harvest", 0)
	worker.set_work_priority("Haul", 1)
	worker.move_speed = 1000.0
	worker.current_cell = carry_cell
	worker.global_position = chunk_manager.get_cell_world_position(carry_cell)
	worker._enter_idle()

	var carry_item_id: String = String(carry_item_result.get("item_id", ""))
	var haul_reservation: Dictionary = world_state.reserve_haul_item(carry_item_id, worker.colonist_id)
	if not _require(bool(haul_reservation.get("ok", false)), "transient haul reservation failed"):
		return {}
	var haul_job := {
		"job_type": Colonist.JOB_TYPE_HAUL,
		"priority": 1,
		"target_id": carry_item_id,
		"target_cell": carry_cell,
		"destination_cell": haul_reservation.get("destination_cell", zone_cell),
		"reservation_result": haul_reservation,
	}
	if not _require(worker.start_job(haul_job), "could not start representative haul job"):
		return {}
	if not _require(_run_until_item_picked_up(worker, world_state, carry_item_id), "could not reach in-flight carried-item state"):
		return {}

	main.call("_set_selected_colonist", worker)
	main.call("_set_harvest_mode", true)
	main.call("_begin_area_drag", Vector2(128.0, 128.0))
	if not _require(String(main.call("get_control_mode_name")) == "harvest" and bool(main.get("is_dragging_harvest_area")), "source transient UI mode/drag setup failed"):
		return {}

	if not _require(world_state.get_construction_reservation(incomplete_id) == construction_reservation_worker.colonist_id, "source construction reservation missing before save"):
		return {}
	if not _require(int(world_state.get_construction_material_reservation_summary(incomplete_id).get("count", 0)) > 0, "source construction material reservation missing before save"):
		return {}
	if not _require(world_state.get_harvest_order_reservation(reserved_order_id) == harvest_reservation_worker.colonist_id, "source harvest reservation missing before save"):
		return {}
	if not _require(not world_state.get_haul_item_reservation(carry_item_id).is_empty(), "source haul reservation missing before save"):
		return {}
	var haul_destination_kind: String = String(haul_reservation.get("destination_kind", ""))
	var haul_storage_id: String = String(haul_reservation.get("storage_id", ""))
	var reserved_haul_capacity: int = world_state.get_resource_stockpile().get_reserved_storage_amount()
	if haul_destination_kind == "storage_component":
		reserved_haul_capacity = int(world_state.get_storage_component_reservation_summary(haul_storage_id).get("reserved", 0))
	if not _require(reserved_haul_capacity == 4, "source capacity reservation missing before save"):
		return {}

	return {
		"generator_seed": generator.seed,
		"manual_cell": manual_cell,
		"depleted_resource_id": depleted_resource_id,
		"incomplete_id": incomplete_id,
		"campfire_id": campfire_id,
		"cabin_id": cabin_id,
		"storehouse_id": storehouse_id,
		"unreserved_order_id": unreserved_order_id,
		"reserved_order_id": reserved_order_id,
		"zone_id": String(zone_result.get("zone_id", "")),
		"ground_item_id": String(ground_item_result.get("item_id", "")),
		"carry_item_id": carry_item_id,
		"worker_id": worker.colonist_id,
		"source_worker_activity": worker.get_activity_name(),
	}


func _add_resource(world_state: Node, resource_type: String, amount: int) -> bool:
	var result: Dictionary = world_state.add_resource(resource_type, amount)
	return _require(bool(result.get("ok", false)), "could not add %d %s: %s" % [amount, resource_type, String(result.get("reason", "unknown"))])


func _deposit_storehouse_resource(world_state: Node, chunk_manager: ChunkManager, resource_type: String, amount: int, origin: Vector2i) -> bool:
	var item_cell: Vector2i = _find_clean_loaded_cell(world_state, chunk_manager, origin, [])
	if not _require(item_cell != INVALID_CELL, "could not find Storehouse seed item cell"):
		return false
	var item_result: Dictionary = world_state.create_ground_item(resource_type, amount, item_cell)
	if not _require(bool(item_result.get("ok", false)), "could not create Storehouse seed item"):
		return false
	var item_id: String = String(item_result.get("item_id", ""))
	var reservation: Dictionary = world_state.reserve_haul_item(item_id, "s1_storage_seed")
	if not _require(bool(reservation.get("ok", false)) and String(reservation.get("destination_kind", "")) == "storage_component", "could not reserve Storehouse seed haul"):
		return false
	var pickup: Dictionary = world_state.request_pickup_ground_item(item_id, "s1_storage_seed")
	var deposit: Dictionary = world_state.request_deposit_carried_item("s1_storage_seed", pickup.get("item", {}), reservation.get("destination_cell", Vector2i.ZERO))
	return _require(bool(pickup.get("ok", false)) and bool(deposit.get("ok", false)), "could not deposit Storehouse seed resource")


func _place_and_complete(world_state: Node, building_id: String, search_origin: Vector2i) -> String:
	var origin: Vector2i = _find_building_origin(world_state, building_id, search_origin)
	if not _require(origin != INVALID_CELL, "could not find placement for %s" % building_id):
		return ""
	var placement: Dictionary = world_state.request_place_construction(building_id, origin)
	if not _require(bool(placement.get("ok", false)), "%s placement failed: %s" % [building_id, String(placement.get("reason", "unknown"))]):
		return ""
	var site_id := "%s:%d:%d" % [building_id, origin.x, origin.y]
	var site: Dictionary = world_state.get_construction_site(site_id)
	var progress: Dictionary = world_state.request_progress_construction(site_id, float(site.get("build_time", 0.0)))
	if not _require(bool(progress.get("completed", false)), "%s completion failed: %s" % [building_id, String(progress.get("reason", "unknown"))]):
		return ""
	return site_id


func _find_building_origin(world_state: Node, building_id: String, origin: Vector2i) -> Vector2i:
	for radius in range(64):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := origin + Vector2i(x, y)
				if bool(world_state.validate_construction_placement(building_id, candidate).get("ok", false)):
					return candidate
	return INVALID_CELL


func _find_clean_loaded_cell(world_state: Node, chunk_manager: ChunkManager, origin: Vector2i, excluded: Array[Vector2i]) -> Vector2i:
	for radius in range(64):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var cell := origin + Vector2i(x, y)
				if cell in excluded or not chunk_manager.is_cell_loaded(cell):
					continue
				var tile: Dictionary = chunk_manager.get_effective_tile_info(cell)
				var terrain: String = String(tile.get("terrain", ""))
				if not bool(tile.get("walkable", false)) or terrain == "WATER" or terrain == "ROCK_WALL" or bool(tile.get("mineable", false)):
					continue
				if chunk_manager.is_cell_blocked_by_resource(cell) or not world_state.get_construction_site_at_cell(cell).is_empty() or world_state.is_cell_in_stockpile_zone(cell):
					continue
				return cell
	return INVALID_CELL


func _run_until_item_picked_up(worker: Colonist, world_state: Node, item_id: String) -> bool:
	for _step in range(1200):
		worker._process(0.05)
		if world_state.get_haul_item_reservation(item_id).get("picked_up", false) and not worker.get_carried_item().is_empty():
			return true
	return false


func _get_colonists(manager: ColonistManager) -> Array[Colonist]:
	var colonists: Array[Colonist] = []
	for child: Node in manager.get_children():
		if child is Colonist and not child.is_queued_for_deletion():
			colonists.append(child as Colonist)
	colonists.sort_custom(func(first: Colonist, second: Colonist) -> bool:
		return first.colonist_id < second.colonist_id
	)
	return colonists


func _find_colonist(manager: ColonistManager, colonist_id: String) -> Colonist:
	for colonist: Colonist in _get_colonists(manager):
		if colonist.colonist_id == colonist_id:
			return colonist
	return null


func _verify_representative_state(world_state: Node, chunk_manager: ChunkManager, colonist_manager: ColonistManager, setup: Dictionary) -> bool:
	if not _require(world_state.get_storage_capacity() == 200, "target Storehouse capacity was not re-derived as 200"):
		return false
	for building_key: String in ["campfire_id", "cabin_id", "storehouse_id"]:
		var site: Dictionary = world_state.get_construction_site(String(setup[building_key]))
		if not _require(bool(site.get("completed", false)), "target missing completed building: %s" % building_key):
			return false
	var incomplete: Dictionary = world_state.get_construction_site(String(setup["incomplete_id"]))
	if not _require(not incomplete.is_empty() and not bool(incomplete.get("completed", true)), "target incomplete site was not preserved"):
		return false
	if not _require(chunk_manager.has_manual_tile_override(setup["manual_cell"]), "target manual tile override missing"):
		return false
	if not _require(chunk_manager.is_resource_depleted(String(setup["depleted_resource_id"])), "target depleted resource id missing"):
		return false
	if not _require(not world_state.get_harvest_order(String(setup["unreserved_order_id"])).is_empty(), "target unreserved harvest order missing"):
		return false
	if not _require(world_state.get_stockpile_zones().size() == 1, "target stockpile zone missing"):
		return false
	var item_ids: Dictionary = {}
	for item: Dictionary in world_state.get_ground_items():
		item_ids[String(item.get("item_id", ""))] = true
	if not _require(item_ids.has(String(setup["ground_item_id"])), "target representative ground item missing"):
		return false
	if not _require(item_ids.has(String(setup["carry_item_id"])), "in-flight carried item was not normalized back to a ground item"):
		return false
	var worker: Colonist = _find_colonist(colonist_manager, String(setup["worker_id"]))
	if not _require(worker != null, "target representative colonist missing"):
		return false
	if not _require(worker.nickname == "S1 Round Trip", "target colonist identity did not round-trip"):
		return false
	if not _require(not worker.get_skills().is_empty() and not worker.get_traits().is_empty() and not worker.get_relationships().is_empty(), "target colonist skills/traits/relationships were not representative"):
		return false
	if not _require(worker.get_work_priority("Construct") == 0 and worker.get_work_priority("Harvest") == 0 and worker.get_work_priority("Haul") == 1, "target colonist work priorities did not round-trip"):
		return false
	return true


func _verify_transient_state_reset(main: Node, world_state: Node, colonist_manager: ColonistManager, setup: Dictionary) -> bool:
	var incomplete_id: String = String(setup["incomplete_id"])
	var reserved_order_id: String = String(setup["reserved_order_id"])
	var carry_item_id: String = String(setup["carry_item_id"])
	if not _require(world_state.get_construction_reservation_summary().get("count", -1) == 0, "construction reservations survived load"):
		return false
	if not _require(not world_state.get_resource_stockpile().has_resource_reservation("construction:%s" % incomplete_id), "construction resource earmark survived load"):
		return false
	if not _require(world_state.get_construction_material_reservation_summary().get("count", -1) == 0, "construction material reservations survived load"):
		return false
	if not _require(world_state.get_harvest_order_reservation(reserved_order_id).is_empty(), "harvest reservation survived load"):
		return false
	if not _require(world_state.get_haul_item_reservation(carry_item_id).is_empty(), "haul reservation survived load"):
		return false
	if not _require(world_state.get_resource_stockpile().get_storage_reservation_summary().get("count", -1) == 0, "capacity reservation survived load"):
		return false
	if not _require(world_state.get_storage_component_reservation_summary().get("count", -1) == 0, "storage component capacity reservation survived load"):
		return false
	var worker: Colonist = _find_colonist(colonist_manager, String(setup["worker_id"]))
	if not _require(worker != null and worker.get_activity_name() == "idle", "colonist activity did not reset to idle"):
		return false
	if not _require(worker.get_carried_item().is_empty() and worker.get_haul_item_id().is_empty(), "carried-item activity survived load"):
		return false
	if not _require(worker.target_cell == worker.current_cell, "colonist movement target survived load"):
		return false
	if not _require(main.get("_selected_colonist") == null and not main.get_node("CanvasLayer/ColonistInfoPanel").visible, "UI selection survived load"):
		return false
	if not _require(String(main.call("get_control_mode_name")) == "normal", "build/harvest/stockpile mode survived load"):
		return false
	if not _require(not bool(main.get("is_dragging_harvest_area")) and not bool(main.get("is_dragging_stockpile_area")), "area drag state survived load"):
		return false
	var area_preview: Node2D = main.get("_area_drag_preview") as Node2D
	var placement_preview: Node2D = main.get("_placement_preview") as Node2D
	if not _require(area_preview != null and not area_preview.visible and placement_preview != null and not placement_preview.visible, "transient preview remained visible after load"):
		return false
	var indicator: CanvasItem = worker.get_node_or_null("SelectionIndicator") as CanvasItem
	if not _require(indicator == null or not indicator.visible, "colonist selection projection survived load"):
		return false
	return true


func _run_negative_contract_checks(save_service: RefCounted, valid_save: Dictionary) -> bool:
	var unsupported: Dictionary = valid_save.duplicate(true)
	unsupported["version"] = 999
	if not _expect_rejected(save_service, unsupported, "unsupported_version"):
		return false

	for required_section: String in ["world", "time", "stockpile", "deltas", "colonists"]:
		var missing_section: Dictionary = valid_save.duplicate(true)
		missing_section.erase(required_section)
		if not _expect_rejected(save_service, missing_section, "missing_%s" % required_section):
			return false

	var malformed_colonists: Dictionary = valid_save.duplicate(true)
	malformed_colonists["colonists"] = [{"colonist_id": ""}]
	if not _expect_rejected(save_service, malformed_colonists, "colonists_invalid_or_duplicate_colonist_id"):
		return false

	var invalid_world: Dictionary = valid_save.duplicate(true)
	var world_data: Dictionary = (invalid_world["world"] as Dictionary).duplicate(true)
	world_data["generation_config"] = "invalid"
	invalid_world["world"] = world_data
	if not _expect_rejected(save_service, invalid_world, "invalid_world_generation_config"):
		return false
	return true


func _expect_rejected(save_service: RefCounted, save_data: Dictionary, expected_reason: String) -> bool:
	var candidate: Node = MainScene.instantiate()
	root.add_child(candidate)
	var candidate_chunk_manager: ChunkManager = candidate.get_node("ChunkManager") as ChunkManager
	var candidate_colonist_manager: ColonistManager = candidate.get_node("ChunkManager/GameplayYSort/ColonistManager") as ColonistManager
	_freeze_scene(candidate, candidate_chunk_manager, candidate_colonist_manager)
	var result: Dictionary = save_service.apply_save_data(
		save_data,
		candidate.get_node("WorldGenerator"),
		candidate.get("_world_state"),
		candidate_chunk_manager,
		candidate_colonist_manager
	)
	root.remove_child(candidate)
	candidate.free()
	if not _require(not bool(result.get("ok", false)), "malformed save was accepted; expected %s" % expected_reason):
		return false
	return _require(String(result.get("reason", "")) == expected_reason, "malformed save reason mismatch: expected=%s actual=%s" % [expected_reason, String(result.get("reason", ""))])


func _normalize_value(value: Variant, path: String) -> Variant:
	if value is Dictionary:
		var normalized_dictionary: Dictionary = {}
		var keys: Array = (value as Dictionary).keys()
		keys.sort_custom(func(first: Variant, second: Variant) -> bool:
			return String(first) < String(second)
		)
		for key: Variant in keys:
			normalized_dictionary[key] = _normalize_value((value as Dictionary)[key], "%s.%s" % [path, String(key)])
		return normalized_dictionary
	if value is Array:
		var normalized_array: Array = []
		for index in range((value as Array).size()):
			normalized_array.append(_normalize_value((value as Array)[index], "%s[%d]" % [path, index]))
		if _array_order_is_not_authoritative(path):
			normalized_array.sort_custom(func(first: Variant, second: Variant) -> bool:
				return JSON.stringify(first) < JSON.stringify(second)
			)
		return normalized_array
	return value


func _array_order_is_not_authoritative(path: String) -> bool:
	return (
		path in [
			"$.deltas.manual_tiles",
			"$.deltas.depleted_resources",
			"$.deltas.construction_sites",
			"$.deltas.harvest_orders",
			"$.deltas.stockpile_zones",
			"$.deltas.ground_items",
			"$.colonists",
		]
		or (path.contains("$.deltas.construction_sites[") and path.ends_with(".occupied_cells"))
		or (path.contains("$.deltas.stockpile_zones[") and path.ends_with(".cells"))
		or (path.contains("$.colonists[") and path.ends_with(".relationships"))
	)


func _compare_values(expected: Variant, actual: Variant, path: String) -> bool:
	if _is_number(expected) and _is_number(actual):
		if absf(float(expected) - float(actual)) <= FLOAT_TOLERANCE:
			return true
		_fail("numeric mismatch at %s: expected=%s actual=%s" % [path, str(expected), str(actual)])
		return false
	if typeof(expected) != typeof(actual):
		_fail("type mismatch at %s: expected_type=%d actual_type=%d" % [path, typeof(expected), typeof(actual)])
		return false
	if expected is Dictionary:
		var expected_dictionary: Dictionary = expected
		var actual_dictionary: Dictionary = actual
		if expected_dictionary.size() != actual_dictionary.size():
			_fail("dictionary size mismatch at %s: expected=%d actual=%d" % [path, expected_dictionary.size(), actual_dictionary.size()])
			return false
		for key: Variant in expected_dictionary.keys():
			if not actual_dictionary.has(key):
				_fail("missing key at %s.%s" % [path, String(key)])
				return false
			if not _compare_values(expected_dictionary[key], actual_dictionary[key], "%s.%s" % [path, String(key)]):
				return false
		return true
	if expected is Array:
		var expected_array: Array = expected
		var actual_array: Array = actual
		if expected_array.size() != actual_array.size():
			_fail("array size mismatch at %s: expected=%d actual=%d" % [path, expected_array.size(), actual_array.size()])
			return false
		for index in range(expected_array.size()):
			if not _compare_values(expected_array[index], actual_array[index], "%s[%d]" % [path, index]):
				return false
		return true
	if expected != actual:
		_fail("value mismatch at %s: expected=%s actual=%s" % [path, str(expected), str(actual)])
		return false
	return true


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _save_contains_no_objects(value: Variant) -> bool:
	if value is Object:
		return false
	if value is Dictionary:
		for entry: Variant in (value as Dictionary).values():
			if not _save_contains_no_objects(entry):
				return false
	elif value is Array:
		for entry: Variant in value:
			if not _save_contains_no_objects(entry):
				return false
	return true


func _contains_forbidden_save_key(value: Variant) -> bool:
	const FORBIDDEN_KEYS := [
		"resource_nodes",
		"construction_nodes",
		"stockpile_zone_nodes",
		"ground_item_nodes",
		"pending_resource_spawns",
		"texture_cache",
		"cache_hits",
		"cache_misses",
		"selected_colonist",
		"placement_mode",
		"harvest_mode",
		"stockpile_mode",
		"drag_start_cell",
		"drag_current_cell",
		"target_cell",
		"current_path",
		"path_index",
		"activity",
		"carried_item",
		"reservation_result",
	]
	if value is Dictionary:
		for key: Variant in (value as Dictionary).keys():
			if String(key) in FORBIDDEN_KEYS:
				return true
			if _contains_forbidden_save_key((value as Dictionary)[key]):
				return true
	elif value is Array:
		for entry: Variant in value:
			if _contains_forbidden_save_key(entry):
				return true
	return false
