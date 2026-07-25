extends SceneTree

const State = preload("res://scripts/simulation/windowed_colony_state.gd")
const JobLocationView = preload("res://scripts/presentation/job_location_view.gd")

var _failures: Array[String] = []

func _init() -> void: _run.call_deferred()

func _run() -> void:
	var state := _flat_state(73031)
	_test_traversal_rules(state)
	_test_paths()
	_test_movement_and_repath()
	_test_construction_reachability()
	await _test_input_projection()
	if _failures.is_empty(): print("LOCATION_TRAVERSAL_VALIDATION PASS"); quit(0)
	else:
		for failure: String in _failures: push_error(failure)
		print("LOCATION_TRAVERSAL_VALIDATION FAIL count=", _failures.size()); quit(1)

func _flat_state(seed_value: int) -> WindowedColonyState:
	var state := State.new(); _expect_ok(state.request_new_game(seed_value), "new game starts"); _expect_ok(state.request_settle_starting_location(), "home settles")
	var location: Dictionary = (state.get("_registry") as RefCounted).get_record(State.LOCATION_ID)
	location.map_size = Vector2i(7, 7); location.terrain = []
	for y in range(7):
		for x in range(7): location.terrain.append({"cell": Vector2i(x, y), "terrain": "GRASS", "walkable": true, "atlas_coords": Vector2i.ZERO})
	location.resources = []; location.piles = []
	var colonists: Dictionary = state.get("_colonists"); var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]; var index := 0
	for id: String in state.get_colonist_ids(): colonists[id].cell = cells[index]; colonists[id].visual_cell = Vector2(cells[index]); index += 1
	return state

func _test_traversal_rules(state: WindowedColonyState) -> void:
	var id := State.LOCATION_ID; var registry: RefCounted = state.get("_registry"); var location: Dictionary = registry.get_record(id); var traversal: RefCounted = state.get("_traversal")
	_expect(state.is_cell_traversable(id, Vector2i(2, 2)), "ordinary ground traversable")
	_set_terrain(location, Vector2i(2, 2), "WATER", false); _expect(not state.is_cell_traversable(id, Vector2i(2, 2)), "water blocked")
	_set_terrain(location, Vector2i(2, 2), "GRASS", true)
	location.resources = [{"resource_id": "tree_test", "resource_kind": "tree", "cell": Vector2i(1, 4), "depleted": false}]
	_expect(not state.is_cell_traversable(id, Vector2i(1, 4)), "tree blocked"); location.resources = []
	_expect(not state.is_cell_traversable(id, Vector2i(-1, 0)), "out of bounds blocked")
	_complete_cell_piece(state, "floor", Vector2i(1, 1)); _expect(state.is_cell_traversable(id, Vector2i(1, 1)), "floor does not affect traversal")
	_complete_cell_piece(state, "wall", Vector2i(3, 2))
	_expect(not state.is_cell_traversable(id, Vector2i(3, 2)), "completed wall blocks its occupied cell")
	_complete_cell_piece(state, "door", Vector2i(4, 2)); _expect(state.is_cell_traversable(id, Vector2i(4, 2)), "completed door cell remains passable")
	_complete_cell_piece(state, "window", Vector2i(5, 2))
	_expect(not state.is_cell_traversable(id, Vector2i(5, 2)), "completed window blocks its occupied cell")
	_complete_cell_piece(state, "wall", Vector2i(2, 5))
	var conversion := state.request_designate_construction(id, "door", [{"cell": Vector2i(2, 5), "orientation_axis": "axis_y"}]); _expect_ok(conversion, "door conversion designated for traversal transition")
	_expect(not state.is_cell_traversable(id, Vector2i(2, 5)), "door conversion remains wall-blocked before completion")
	_expect_ok(state.request_cancel_construction(id, String(conversion.site_ids[0])), "door conversion cancellation succeeds")
	_expect(not state.is_cell_traversable(id, Vector2i(2, 5)), "cancelled conversion leaves wall blocking intact")
	conversion = state.request_designate_construction(id, "door", [{"cell": Vector2i(2, 5), "orientation_axis": "axis_x"}]); _expect_ok(conversion, "door conversion redesignated")
	_expect_ok(state.request_debug_complete_construction(id, String(conversion.site_ids[0])), "door conversion completes")
	_expect(state.is_cell_traversable(id, Vector2i(2, 5)), "completed door conversion becomes passable")
	_expect_ok(state.request_remove_wall_fixture(id, Vector2i(2, 5)), "door fixture removal succeeds")
	_expect(not state.is_cell_traversable(id, Vector2i(2, 5)), "door fixture removal restores plain-wall blocking")
	_expect(traversal.can_traverse_edge(id, Vector2i(2, 2), Vector2i(2, 3)), "construction no longer owns edge traversal identity")
	var buildings: RefCounted = state.get("_construction")
	buildings.set("_buildings", {"blocker": {"building_instance_id": "blocker", "location_id": id, "building_id": "supply_cache", "origin_cell": Vector2i(6, 6), "occupied_cells": [Vector2i(6, 6)], "state": "COMPLETED"}})
	_expect(not state.is_cell_traversable(id, Vector2i(6, 6)), "completed non-passable building blocked")
	location.piles = [{"pile_id": "pile", "cell": Vector2i(5, 6), "enabled": true, "amount": 1}]; _expect(state.is_cell_traversable(id, Vector2i(5, 6)), "loose pile walkable")

func _test_paths() -> void:
	var state := _flat_state(73032); var id := State.LOCATION_ID
	var straight := state.find_path(id, Vector2i(0, 3), Vector2i(6, 3)); _expect_ok(straight, "straight path succeeds"); _expect(_orthogonal(straight.path), "straight path contains no diagonal steps")
	_complete_cell_piece(state, "wall", Vector2i(3, 3))
	var around := state.find_path(id, Vector2i(0, 3), Vector2i(6, 3)); _expect_ok(around, "path around one wall cell succeeds"); _expect(around.path.size() > straight.path.size(), "path detours around blocked structure cell")
	_clear_construction(state)
	for y in range(7): if y != 3: _complete_cell_piece(state, "wall", Vector2i(3, y))
	_complete_cell_piece(state, "door", Vector2i(3, 3))
	var through_door := state.find_path(id, Vector2i(0, 3), Vector2i(6, 3)); _expect_ok(through_door, "wall line with door has path"); _expect(Vector2i(3, 3) in through_door.path, "wall-line path uses door cell")
	_expect(through_door.path == state.find_path(id, Vector2i(0, 3), Vector2i(6, 3)).path, "repeated path is deterministic")
	_clear_construction(state)
	for y in range(7): _complete_cell_piece(state, "wall", Vector2i(3, y))
	_expect_reason(state.find_path(id, Vector2i(0, 3), Vector2i(6, 3)), "no_path", "sealed structure wall returns no path")

func _test_movement_and_repath() -> void:
	var state := _flat_state(73033); var colonist_id := state.get_colonist_ids()[0]; var colonist: Dictionary = (state.get("_colonists") as Dictionary)[colonist_id]
	colonist.cell = Vector2i.ZERO; colonist.visual_cell = Vector2.ZERO
	state.call("_move_toward", colonist, Vector2i(6, 0), 0.1)
	var next_cell := Vector2i(colonist.movement_path[1]); _complete_cell_piece(state, "wall", next_cell)
	state.call("_move_toward", colonist, Vector2i(6, 0), 0.1)
	_expect(Vector2i(colonist.cell) == Vector2i.ZERO, "blocked next edge is not crossed")
	_expect(String(colonist.movement_failure_reason) == "next_cell_blocked", "blocked next edge invalidates path")
	for _step in range(20): state.call("_move_toward", colonist, Vector2i(6, 0), 0.7)
	_expect(Vector2i(colonist.cell) == Vector2i(6, 0), "colonist repaths around new wall cell")

func _test_construction_reachability() -> void:
	var state := _flat_state(73034); var id := State.LOCATION_ID; var colonist_id := state.get_colonist_ids()[0]
	var colonist: Dictionary = (state.get("_colonists") as Dictionary)[colonist_id]; colonist.cell = Vector2i.ZERO
	var structure_cell := Vector2i(5, 5)
	var designation := state.request_designate_construction(id, "wall", [structure_cell]); _expect_ok(designation, "structure site designated")
	var site_id := String(designation.site_ids[0]); (state.get("_registry") as RefCounted).create_or_merge_pile(id, "wood", 2, Vector2i(0, 1), true)
	var resolved: Dictionary = (state.get("_location_construction") as RefCounted).resolve_construction_work_cell(id, site_id, Vector2i.ZERO, colonist_id)
	_expect_ok(resolved, "reachable structure work cell resolves")
	var chosen_path := state.find_path(id, Vector2i.ZERO, Vector2i(resolved.work_cell), colonist_id)
	_expect(is_equal_approx(float(resolved.path_cost), float(chosen_path.cost)), "work cell selected by authoritative path cost")
	var reserved := state.reserve_construction_site(id, site_id, colonist_id); _expect_ok(reserved, "reachable structure site reserves"); _expect(Vector2i(reserved.work_cell) == Vector2i(resolved.work_cell), "reservation preserves reachable work cell")

func _test_input_projection() -> void:
	var state := _flat_state(73035); var wall := Vector2i(3, 3); _complete_cell_piece(state, "wall", wall); root.add_child(state)
	var view := JobLocationView.new(); view.size = Vector2(640, 420); root.add_child(view); view.configure(state, State.LOCATION_ID, func() -> String: return "floor")
	await process_frame
	for cell: Vector2i in [wall + Vector2i.UP, wall + Vector2i.LEFT]:
		var view_position: Vector2 = view.debug_cell_to_view_position(cell); _expect(view.debug_view_position_to_cell(view_position) == cell, "terrain cell %s remains selectable beside raised wall" % cell)
	view.queue_free(); state.queue_free()

func _complete_cell_piece(state: WindowedColonyState, kind: String, cell: Vector2i) -> void:
	if kind in ["door", "window"] and not state.get_location_completed_structures(State.LOCATION_ID).structure_cells.has(cell):
		_complete_cell_piece(state, "wall", cell)
	var target: Variant = {"cell": cell, "orientation_axis": "axis_x"} if kind in ["door", "window"] else cell
	var designation := state.request_designate_construction(State.LOCATION_ID, kind, [target]); _expect_ok(designation, "%s designation at %s" % [kind, cell])
	if bool(designation.get("ok", false)): _expect_ok(state.request_debug_complete_construction(State.LOCATION_ID, String(designation.site_ids[0])), "%s completion at %s" % [kind, cell])
func _clear_construction(state: WindowedColonyState) -> void: (state.get("_location_construction") as RefCounted).set("_locations", {})
func _set_terrain(location: Dictionary, cell: Vector2i, kind: String, walkable: bool) -> void:
	for terrain: Dictionary in location.terrain:
		if Vector2i(terrain.cell) == cell: terrain.terrain = kind; terrain.walkable = walkable; return
func _orthogonal(path: Array) -> bool:
	for index in range(1, path.size()):
		var delta: Vector2i = Vector2i(path[index]) - Vector2i(path[index - 1])
		if absi(delta.x) + absi(delta.y) != 1: return false
	return true
func _expect_ok(result: Dictionary, label: String) -> void: _expect(bool(result.get("ok", false)), "%s: %s" % [label, result.get("reason", "missing result")])
func _expect_reason(result: Dictionary, reason: String, label: String) -> void: _expect(not bool(result.get("ok", false)) and String(result.get("reason", "")) == reason, "%s: expected %s, got %s" % [label, reason, result])
func _expect(condition: bool, label: String) -> void:
	if not condition: _failures.append(label)
