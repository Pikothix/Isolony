extends SceneTree

const WorldStateScript = preload("res://scripts/simulation/world_state.gd")

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("M22 validation failed: %s" % message)
	quit(1)

func _find_valid_origin(world_state: Node, building_id: String, origin: Vector2i) -> Vector2i:
	for radius in range(0, 48):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := origin + Vector2i(x, y)
				if bool(world_state.validate_construction_placement(building_id, candidate).get("ok", false)):
					return candidate
	return Vector2i(2147483647, 2147483647)

func _complete_building(world_state: Node, building_id: String, cell: Vector2i, wood: int, work: float) -> String:
	world_state.add_resource("wood", wood)
	var placement: Dictionary = world_state.request_place_construction(building_id, cell)
	if not bool(placement.get("ok", false)):
		return ""
	var site_id := "%s:%d:%d" % [building_id, cell.x, cell.y]
	var progress: Dictionary = world_state.request_progress_construction(site_id, work)
	return site_id if bool(progress.get("completed", false)) else ""

func _move_colonist_to(colonist: Node, chunk_manager: Node, cell: Vector2i) -> void:
	colonist.current_cell = cell
	colonist.target_cell = cell
	colonist.global_position = chunk_manager.get_cell_world_position(cell) + Vector2(0, -6)

func _run() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	for _frame in range(40):
		await process_frame
	var world_state: Node = main.get("_world_state")
	var chunk_manager: Node = main.get_node("ChunkManager")
	var manager: Node = main.get_node("ChunkManager/GameplayYSort/ColonistManager")
	manager.set_process(false)
	var colonist: Node
	for child: Node in manager.get_children():
		if child.has_method("get_needs_state"):
			child.set_process(false)
			if colonist == null:
				colonist = child
	if colonist == null:
		_fail("no colonist available")
		return
	var campfire_cell: Vector2i = _find_valid_origin(world_state, "campfire", colonist.current_cell + Vector2i(8, 0))
	if _complete_building(world_state, "campfire", campfire_cell, 5, 10.0).is_empty():
		_fail("could not complete Campfire")
		return
	var cabin_cell: Vector2i = _find_valid_origin(world_state, "cabin", campfire_cell + Vector2i(14, 0))
	if _complete_building(world_state, "cabin", cabin_cell, 20, 30.0).is_empty():
		_fail("could not complete Cabin")
		return
	var warm_target: Dictionary = world_state.get_nearest_warmed_cell(colonist.current_cell)
	var shelter_target: Dictionary = world_state.get_nearest_sheltered_cell(colonist.current_cell)
	if not bool(warm_target.get("ok", false)) or not world_state.is_cell_warmed(warm_target.get("cell", Vector2i.ZERO)):
		_fail("nearest warmed target was unavailable or outside warmth")
		return
	if not bool(shelter_target.get("ok", false)) or not world_state.is_cell_sheltered(shelter_target.get("cell", Vector2i.ZERO)):
		_fail("nearest sheltered target was unavailable or outside shelter")
		return
	world_state.get_time_state().import_state({"current_day": 1, "current_minutes": 1200.0, "paused": true})
	colonist.warmth = 35.0
	colonist.shelter = 45.0
	colonist._enter_idle()
	colonist._pause_timer = 0.0
	colonist._process_idle(0.1)
	if colonist.get_activity_name() != "seeking_warmth":
		_fail("lower Warmth did not outrank Shelter")
		return
	if not world_state.is_cell_warmed(colonist.target_cell):
		_fail("warmth activity target was not warmed")
		return
	for _step in range(2400):
		colonist._process(0.1)
		if colonist.warmth >= colonist.need_seek_recovery_threshold:
			break
	if colonist.warmth < colonist.need_seek_recovery_threshold or not world_state.is_cell_warmed(colonist.current_cell):
		_fail("Warmth did not recover while seeking")
		return
	var shelter_start := cabin_cell + Vector2i(7, 0)
	_move_colonist_to(colonist, chunk_manager, shelter_start)
	colonist.warmth = 100.0
	colonist.shelter = 35.0
	colonist._enter_idle()
	colonist._pause_timer = 0.0
	colonist._process_idle(0.1)
	if colonist.get_activity_name() != "seeking_shelter" or not world_state.is_cell_sheltered(colonist.target_cell):
		_fail("Shelter activity or target was invalid")
		return
	for _step in range(3000):
		colonist._process(0.1)
		if colonist.shelter >= colonist.need_seek_recovery_threshold:
			break
	if colonist.shelter < colonist.need_seek_recovery_threshold or not world_state.is_cell_sheltered(colonist.current_cell):
		_fail("Shelter did not recover while seeking")
		return
	var empty_world: Node = WorldStateScript.new()
	main.add_child(empty_world)
	empty_world.set_placement_query(chunk_manager)
	empty_world.get_time_state().import_state({"current_day": 1, "current_minutes": 1200.0, "paused": true})
	colonist.world_state = empty_world
	colonist.warmth = 10.0
	colonist.shelter = 100.0
	colonist._enter_idle()
	colonist._pause_timer = 0.0
	colonist._process_idle(0.1)
	if colonist.get_activity_name() != "wandering":
		_fail("missing effect target did not fall back to wandering")
		return
	colonist.world_state = world_state
	colonist.warmth = 100.0
	colonist.shelter = 100.0
	var work_cell: Vector2i = _find_valid_origin(world_state, "campfire", cabin_cell + Vector2i(10, 5))
	world_state.add_resource("wood", 5)
	world_state.request_place_construction("campfire", work_cell)
	var work_id := "campfire:%d:%d" % [work_cell.x, work_cell.y]
	colonist._enter_idle()
	if not colonist._try_start_construction_job():
		_fail("construction discovery regressed")
		return
	for _step in range(400):
		colonist._process(0.1)
		if bool(world_state.get_construction_site(work_id).get("completed", false)):
			break
	if not bool(world_state.get_construction_site(work_id).get("completed", false)):
		_fail("construction completion regressed")
		return
	print("M22 validation passed: targets, priority, movement, recovery, fallback, construction")
	quit(0)
