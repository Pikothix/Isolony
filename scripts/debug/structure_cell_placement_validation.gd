extends SceneTree

const MainScene = preload("res://scenes/Main.tscn")
const LocationView = preload("res://scripts/presentation/job_location_view.gd")
const VisualConfig = preload("res://scripts/presentation/location_construction_visual_config.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_visual_contract_checks()
	var main: Control = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	_expect_ok(main.colony_state.request_new_game(24681357), "new game starts")
	await process_frame
	var view: Control = main.get("_location_widgets")["starting_location"].view
	var location: Dictionary = main.colony_state.get_location_snapshot("starting_location")
	var cell := _find_valid_horizontal_run(main.colony_state, location, 3)
	_expect(cell != Vector2i(-1, -1), "valid three-cell wall run found")
	if cell != Vector2i(-1, -1):
		await _run_cell_placement_checks(main, view, location, cell)
	if _failures.is_empty():
		print("STRUCTURE_CELL_PLACEMENT_VALIDATION PASS")
		quit(0)
	else:
		for failure: String in _failures: push_error(failure)
		print("STRUCTURE_CELL_PLACEMENT_VALIDATION FAIL count=", _failures.size())
		quit(1)


func _run_cell_placement_checks(main: Control, view: Control, location: Dictionary, cell: Vector2i) -> void:
	main.call("_set_active_construction_tool", "wall")
	var center: Vector2 = view.debug_cell_to_view_position(cell)
	for offset: Vector2 in [Vector2.ZERO, Vector2(-5, 0), Vector2(5, 0), Vector2(0, -2), Vector2(0, 2)]:
		view.call("_refresh_pointer_target", center + offset, "wall")
		var resolved: Dictionary = view.get("_resolved_placement_target")
		_expect(Vector2i(resolved.get("target_cell", Vector2i(-1, -1))) == cell, "pointer position inside diamond keeps one target cell")
		_expect(not resolved.has("segment") and resolved.get("targets", []) == [cell], "resolved target contains only cell identity")
	var neighbour := cell + Vector2i.RIGHT
	_expect(bool(main.colony_state.validate_construction_designation("starting_location", "wall", [neighbour]).ok), "adjacent structure fixture is valid")
	var neighbour_center: Vector2 = view.debug_cell_to_view_position(neighbour)
	var transitions: Array[Vector2i] = []
	for step in range(21):
		var sampled: Vector2i = view.debug_view_position_to_cell(center.lerp(neighbour_center, float(step) / 20.0))
		if transitions.is_empty() or transitions[-1] != sampled: transitions.append(sampled)
	_expect(transitions == [cell, neighbour], "crossing one TileMap boundary changes target exactly once")

	view.call("_refresh_pointer_target", center, "wall")
	var shown: Dictionary = view.get("_resolved_placement_target").duplicate(true)
	_send_left_click(view, center)
	var sites: Array[Dictionary] = main.colony_state.get_location_construction_sites("starting_location")
	_expect(sites.size() == 1 and Vector2i(sites[0].cell) == Vector2i(shown.target_cell), "submission uses the exact previewed target cell")
	_expect(not sites[0].has("segment_id") and not sites[0].has("side") and not sites[0].has("adjacent_cells"), "authoritative site has no segment identity")
	var authority: RefCounted = main.colony_state.get("_location_construction")
	_expect(String((authority.get("_locations") as Dictionary)["starting_location"].structure_site_cells.get(cell, "")) == String(sites[0].site_id), "active structure occupancy is indexed by cell")
	var site_id := String(sites[0].site_id)
	view.set("_hovered_construction_site_id", site_id)
	var site_before_enter: Dictionary = main.colony_state.get_construction_site("starting_location", site_id)
	var completed_before_enter: Dictionary = main.colony_state.get_location_completed_structures("starting_location")
	var piles_before_enter: Array = main.colony_state.get_location_snapshot("starting_location").piles
	var save_before_enter: Dictionary = main.colony_state.export_save_data()
	var path_before_enter: Dictionary = main.colony_state.find_path("starting_location", Vector2i(location.spawn_cells[0]), cell)
	_send_enter(view)
	_expect(main.colony_state.get_construction_site("starting_location", site_id) == site_before_enter, "production Enter does not mutate construction progress, materials, or worker reservation")
	_expect(main.colony_state.get_location_completed_structures("starting_location") == completed_before_enter, "production Enter does not complete structural state")
	_expect(main.colony_state.get_location_snapshot("starting_location").piles == piles_before_enter, "production Enter does not mutate material quantities or reservations")
	_expect(main.colony_state.find_path("starting_location", Vector2i(location.spawn_cells[0]), cell) == path_before_enter, "production Enter does not mutate traversal state")
	_expect(main.colony_state.export_save_data() == save_before_enter, "production Enter does not mutate save authority")
	_expect_ok(main.colony_state.request_debug_complete_construction("starting_location", site_id), "wall completes")
	var completed: Dictionary = main.colony_state.get_location_completed_structures("starting_location")
	_expect(completed.structure_cells.has(cell) and String(completed.structure_cells[cell].kind) == "wall", "completed wall owns one structure cell")
	_expect(not (authority.get("_locations") as Dictionary)["starting_location"].structure_site_cells.has(cell), "completion clears the active cell-occupancy index")
	_expect_reason(main.colony_state.request_designate_construction("starting_location", "wall", [cell]), "structure_cell_occupied", "wall cannot stack on occupied structure cell")
	main.call("_set_active_construction_tool", "door")
	view.call("_refresh_pointer_target", center, "door")
	var door_preview: Dictionary = view.get("_resolved_placement_target").duplicate(true)
	_expect(bool(door_preview.valid) and String(door_preview.orientation_axis) == "axis_x", "completed wall previews a valid door conversion")
	view.call("_rotate_construction_orientation", "door")
	var rotated_preview: Dictionary = view.get("_resolved_placement_target").duplicate(true)
	_expect(Vector2i(rotated_preview.target_cell) == cell and String(rotated_preview.orientation_axis) == "axis_y", "rotation changes orientation without changing the preview cell")
	_send_left_click(view, center)
	var conversion_sites: Array[Dictionary] = main.colony_state.get_location_construction_sites("starting_location")
	_expect(conversion_sites.size() == 1 and Vector2i(conversion_sites[0].cell) == cell and String(conversion_sites[0].orientation_axis) == "axis_y", "submission consumes the exact preview cell and orientation")
	_expect(String(main.colony_state.get_location_completed_structures("starting_location").structure_cells[cell].kind) == "wall", "fixture installation site preserves source wall occupancy")
	_expect(String((authority.get("_locations") as Dictionary)["starting_location"].fixture_site_cells.get(cell, "")) == String(conversion_sites[0].site_id) and not (authority.get("_locations") as Dictionary)["starting_location"].structure_site_cells.has(cell), "fixture site uses its own cell index")
	_expect_reason(main.colony_state.request_designate_construction("starting_location", "window", [{"cell": cell, "orientation_axis": "axis_x"}]), "fixture_cell_occupied", "active fixture installation rejects another fixture")
	var cell_key := "%d_%d" % [cell.x, cell.y]
	_expect(((view.get("_construction_depth_nodes") as Dictionary)[cell_key] as Node).get_child_count() == 2, "active fixture presentation layers ghost over retained wall")
	_expect_ok(main.colony_state.request_cancel_construction("starting_location", String(conversion_sites[0].site_id)), "door fixture installation cancels")
	_expect(String(main.colony_state.get_location_completed_structures("starting_location").structure_cells[cell].kind) == "wall" and main.colony_state.get_wall_fixture_at_cell("starting_location", cell).is_empty(), "cancelled fixture installation preserves plain wall")
	_expect(((view.get("_construction_depth_nodes") as Dictionary)[cell_key] as Node).get_child_count() == 1, "cancellation restores one plain-wall visual part")
	var completed_door: Dictionary = main.colony_state.request_designate_construction("starting_location", "door", [{"cell": cell, "orientation_axis": "axis_y"}]); _expect_ok(completed_door, "door fixture redesignates")
	_expect_ok(main.colony_state.request_debug_complete_construction("starting_location", String(completed_door.site_ids[0])), "door fixture completes")
	_expect(String(main.colony_state.get_structure_at_cell("starting_location", cell).kind) == "wall" and String(main.colony_state.get_wall_fixture_at_cell("starting_location", cell).kind) == "door", "completed door retains authoritative wall")
	_expect(((view.get("_construction_depth_nodes") as Dictionary)[cell_key] as Node).get_child_count() == 2, "completed door renders wall base plus fixture overlay")
	_expect_ok(main.colony_state.request_remove_wall_fixture("starting_location", cell), "completed door fixture removes")
	_expect(((view.get("_construction_depth_nodes") as Dictionary)[cell_key] as Node).get_child_count() == 1, "fixture removal restores plain wall visual")

	_expect_reason(main.colony_state.request_designate_construction("starting_location", "door", [{"cell": neighbour, "orientation_axis": "axis_x"}]), "compatible_wall_required", "empty adjacent cell rejects door")
	var neighbour_wall: Dictionary = main.colony_state.request_designate_construction("starting_location", "wall", [neighbour]); _expect_ok(neighbour_wall, "window source wall designates")
	_expect_ok(main.colony_state.request_debug_complete_construction("starting_location", String(neighbour_wall.site_ids[0])), "window source wall completes")
	var window_result: Dictionary = main.colony_state.request_designate_construction("starting_location", "window", [{"cell": neighbour, "orientation_axis": "axis_y"}]); _expect_ok(window_result, "completed wall accepts window conversion")
	_expect_ok(main.colony_state.request_debug_complete_construction("starting_location", String(window_result.site_ids[0])), "window conversion completes")
	var completed_window: Dictionary = main.colony_state.get_location_completed_structures("starting_location").structure_cells[neighbour]
	_expect(String(completed_window.kind) == "wall" and String(completed_window.fixture_kind) == "window", "window installation retains one wall base record with one fixture")
	_expect_reason(main.colony_state.request_designate_construction("starting_location", "door", [{"cell": neighbour, "orientation_axis": "axis_x"}]), "fixture_cell_occupied", "window fixture rejects door installation")
	var third := neighbour + Vector2i.RIGHT
	var third_wall: Dictionary = main.colony_state.request_designate_construction("starting_location", "wall", [third]); _expect_ok(third_wall, "third adjacent wall designates")
	_expect_ok(main.colony_state.request_debug_complete_construction("starting_location", String(third_wall.site_ids[0])), "third adjacent wall completes")
	var cache_cell: Vector2i = _find_valid_structure_cell(main.colony_state, location, [cell, neighbour])
	var colonist_id := String(location.colonist_presence_ids[0])
	_expect_ok(main.colony_state.request_place_building(colonist_id, "starting_location", "supply_cache", cache_cell), "supply cache fixture places")
	_expect_reason(main.colony_state.request_designate_construction("starting_location", "door", [{"cell": cache_cell, "orientation_axis": "axis_x"}]), "cell_occupied_by_building", "supply cache cell rejects door conversion")
	var before_invalid: Array[Dictionary] = main.colony_state.get_location_construction_sites("starting_location")
	var piles_before: Array = main.colony_state.get_location_snapshot("starting_location").piles
	_expect_reason(main.colony_state.request_designate_construction("starting_location", "wall", [Vector2i(-1, -1)]), "cell_out_of_bounds", "invalid structure request rejects")
	_expect(main.colony_state.get_location_construction_sites("starting_location") == before_invalid, "invalid request does not mutate construction records")
	_expect(main.colony_state.get_location_snapshot("starting_location").piles == piles_before, "invalid request does not mutate resources")

	_expect_ok(main.colony_state.request_designate_construction("starting_location", "floor", [cell]), "floor may coexist beneath completed structure")
	completed = main.colony_state.get_location_completed_structures("starting_location")
	_expect(completed.structure_cells.has(cell), "floor designation preserves structure occupancy")
	_expect_reason(main.colony_state.validate_building_placement("starting_location", "supply_cache", cell), "construction_cell_occupied", "supply cache cannot overlap construction occupancy")

	var rebuilt: Control = LocationView.new()
	rebuilt.configure(main.colony_state, "starting_location", Callable(main, "get_active_construction_tool"))
	root.add_child(rebuilt)
	var wall_index: TileMapLayer = rebuilt.get("_construction_wall_layer")
	_expect(wall_index.get_cell_atlas_coords(cell) == VisualConfig.WALL, "new view reconstructs wall at the authoritative cell")
	var opening_index: TileMapLayer = rebuilt.get("_construction_opening_layer")
	_expect(opening_index.get_cell_atlas_coords(neighbour) == VisualConfig.atlas_for("window", "axis_y"), "new view reconstructs window fixture orientation")
	_expect((rebuilt.get("_construction_depth_nodes") as Dictionary).has("%d_%d" % [cell.x, cell.y]), "depth visual reconstructs by cell identity")
	var rebuilt_nodes: Dictionary = rebuilt.get("_construction_depth_nodes")
	_expect((rebuilt_nodes["%d_%d" % [cell.x, cell.y]] as Node).get_child_count() == 1 and (rebuilt_nodes["%d_%d" % [neighbour.x, neighbour.y]] as Node).get_child_count() == 2 and (rebuilt_nodes["%d_%d" % [third.x, third.y]] as Node).get_child_count() == 1, "wall/window-fixture/wall run retains wall body in every cell")
	_expect_ok(main.colony_state.request_remove_wall_fixture("starting_location", neighbour), "reconstructed window fixture removes")
	_expect(opening_index.get_cell_source_id(neighbour) == -1 and (rebuilt.get("_construction_depth_nodes")["%d_%d" % [neighbour.x, neighbour.y]] as Node).get_child_count() == 1, "fixture removal reconstructs centre as plain wall")


func _run_visual_contract_checks() -> void:
	var plain: Dictionary = VisualConfig.resolve_structure_visual("wall")
	_expect(String(plain.mode) == "base" and plain.parts.size() == 1 and String(plain.parts[0].kind) == "wall", "plain wall resolves to one wall visual")
	for fixture_kind: String in ["door", "window"]:
		for orientation: String in ["axis_x", "axis_y"]:
			var layered: Dictionary = VisualConfig.resolve_structure_visual("wall", fixture_kind, orientation)
			_expect(String(layered.mode) == "layered" and layered.parts.size() == 2, "%s %s uses layered wall-fixture strategy" % [fixture_kind, orientation])
			_expect(String(layered.parts[0].kind) == "wall" and String(layered.parts[1].kind) == fixture_kind, "%s %s never resolves fixture-only" % [fixture_kind, orientation])
			_expect(Vector2i(layered.base_tile) == VisualConfig.WALL and Vector2i(layered.fixture_tile) == VisualConfig.atlas_for(fixture_kind, orientation), "%s %s resolves calibrated atlas tiles" % [fixture_kind, orientation])


func _find_valid_structure_cell(state: Node, location: Dictionary, excluded: Array[Vector2i] = []) -> Vector2i:
	for tile: Dictionary in location.terrain:
		var cell := Vector2i(tile.cell)
		if cell in excluded: continue
		if bool(state.validate_construction_designation("starting_location", "wall", [cell]).ok): return cell
	return Vector2i(-1, -1)


func _find_valid_horizontal_run(state: Node, location: Dictionary, length: int) -> Vector2i:
	for tile: Dictionary in location.terrain:
		var start := Vector2i(tile.cell)
		var valid := true
		for offset in range(length):
			if not bool(state.validate_construction_designation("starting_location", "wall", [start + Vector2i(offset, 0)]).ok): valid = false; break
		if valid: return start
	return Vector2i(-1, -1)


func _send_left_click(view: Control, position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.position = position
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	view.call("_on_gui_input", press)


func _send_enter(view: Control) -> void:
	var press := InputEventKey.new()
	press.keycode = KEY_ENTER
	press.pressed = true
	view.call("_on_gui_input", press)


func _expect_ok(result: Dictionary, label: String) -> void:
	_expect(bool(result.get("ok", false)), "%s: %s" % [label, result.get("reason", "missing result")])


func _expect_reason(result: Dictionary, reason: String, label: String) -> void:
	_expect(not bool(result.get("ok", false)) and String(result.get("reason", "")) == reason, "%s: expected %s, got %s" % [label, reason, result])


func _expect(condition: bool, label: String) -> void:
	if not condition: _failures.append(label)
