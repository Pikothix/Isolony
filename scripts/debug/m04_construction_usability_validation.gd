extends SceneTree

const Registry = preload("res://scripts/simulation/location_registry.gd")
const Authority = preload("res://scripts/simulation/location_construction_state.gd")
const State = preload("res://scripts/simulation/windowed_colony_state.gd")

var _failures: Array[String] = []

func _init() -> void:
	_run_status_and_cancellation_checks()
	_run_job_selection_flow()
	if _failures.is_empty(): print("M04_CONSTRUCTION_USABILITY_VALIDATION PASS"); quit(0)
	else:
		for failure: String in _failures: push_error(failure)
		print("M04_CONSTRUCTION_USABILITY_VALIDATION FAIL count=", _failures.size()); quit(1)

func _run_status_and_cancellation_checks() -> void:
	var registry := Registry.new(); var home: Dictionary = registry.create_starting_location(40404); var home_id := String(home.location_id)
	for resource: Dictionary in home.resources: resource.depleted = true
	var authority := Authority.new(); authority.configure(registry)
	var origin := _find_walkable_region(home, Vector2i(12, 9))
	_expect(origin != Vector2i(-1, -1), "M04 walkable region found")
	if origin == Vector2i(-1, -1): return
	_expect_ok(registry.create_or_merge_pile(home_id, "wood", 30, Vector2i(home.camp_storage_cell), true), "M04 wood supply created")

	var wall_cell := origin + Vector2i(3, 2)
	var wall := _designate_cell(authority, home_id, "wall", wall_cell)
	_expect_ok(authority.request_debug_complete_construction(home_id, wall), "isolated wall completes")
	var door_cell := wall_cell
	var door := _designate_conversion(authority, home_id, "door", door_cell)
	var door_site := authority.get_construction_site(home_id, door)
	_expect(door_site.prerequisite_site_ids.is_empty() and String(door_site.expected_base_kind) == "wall", "door installation records its expected wall base without a second job dependency")
	_expect(String(door_site.orientation_axis) == "axis_x", "door uses deterministic orientation")
	_expect(String(authority.get_construction_site_status(home_id, door, "worker", origin).availability_reason) == "available", "wall conversion is available")
	_expect_ok(authority.reserve_construction_site(home_id, door, "worker", origin), "door reserves normally")
	var reserved := authority.get_construction_site_status(home_id, door, "other_worker", origin)
	_expect(String(reserved.availability_reason) == "reserved_by_other" and String(reserved.reserved_by_colonist_id) == "worker", "reserved status exposes worker ID")
	_expect_ok(authority.request_progress_construction(home_id, door, "worker", 1.0), "door begins construction")
	var active := authority.get_construction_site_status(home_id, door, "worker", origin)
	_expect(String(active.status) == "under_construction" and is_equal_approx(float(active.progress), 1.0), "under-construction status exposes progress")
	var defensive := active; defensive.prerequisite_site_ids.append("corrupt"); defensive.missing_resources.wood = 99
	_expect(authority.get_construction_site_status(home_id, door, "worker", origin).prerequisite_site_ids.is_empty(), "status reads are defensive")
	_expect_ok(authority.request_debug_complete_construction(home_id, door), "door constructs on its cell")
	_expect(authority.get_construction_site(home_id, door).is_empty() and String(authority.get_location_completed_structures(home_id).structure_cells[door_cell].kind) == "wall" and String(authority.get_location_completed_structures(home_id).structure_cells[door_cell].fixture_kind) == "door", "completed door fixture projects on its wall cell")
	_expect_reason(authority.request_cancel_construction(home_id, door), "unknown_construction_site", "completed structure cannot be cancelled as a site")

	var cancellation_cell := origin + Vector2i(3, 5)
	var cancellation_wall := _designate_cell(authority, home_id, "wall", cancellation_cell)
	_expect_ok(authority.request_debug_complete_construction(home_id, cancellation_wall), "window cancellation source wall completes")
	var cancellable_window := _designate_conversion(authority, home_id, "window", cancellation_cell)
	_expect_ok(authority.request_cancel_construction(home_id, cancellable_window), "window cancellation succeeds")
	_expect(String(authority.get_location_completed_structures(home_id).structure_cells[cancellation_cell].kind) == "wall", "window cancellation preserves its completed wall")

	var active_wall := _designate_cell(authority, home_id, "wall", origin + Vector2i(8, 5))
	var cancelled := authority.request_cancel_construction(home_id, active_wall)
	_expect_ok(cancelled, "active wall cancellation succeeds")
	_expect(cancelled.cancelled_site_ids == [active_wall], "wall cancellation reports only the requested independent site")

	var unreachable_site := _designate_cell(authority, home_id, "wall", origin + Vector2i(0, 7))
	var saved_traversal: RefCounted = authority.get("_traversal"); authority.set("_traversal", null)
	_expect(String(authority.get_construction_site_status(home_id, unreachable_site, "worker", origin).availability_reason) == "unreachable", "unreachable site reports unreachable")
	authority.set("_traversal", saved_traversal)

	var missing_site := _designate_cell(authority, home_id, "wall", origin + Vector2i(0, 8))
	registry.get_record(home_id).piles.clear()
	var missing := authority.get_construction_site_status(home_id, missing_site, "worker", origin)
	_expect(String(missing.availability_reason) == "missing_resources" and int(missing.missing_resources.wood) == 2, "missing-resource status reports exact deficit")

func _run_job_selection_flow() -> void:
	var state := State.new(); root.add_child(state)
	_expect_ok(state.request_new_game(50505), "M04 job game starts")
	_expect_ok(state.request_settle_starting_location(), "M04 job home settles")
	var registry: RefCounted = state.get("_registry"); var home_id := State.LOCATION_ID; var home: Dictionary = registry.get_record(home_id)
	for resource: Dictionary in home.resources: resource.depleted = true
	var origin := _find_walkable_region(home, Vector2i(5, 5)); _expect(origin != Vector2i(-1, -1), "M04 job region found")
	if origin == Vector2i(-1, -1): state.queue_free(); return
	_expect_ok(registry.create_or_merge_pile(home_id, "wood", 9, Vector2i(home.camp_storage_cell), true), "M04 job resources created")
	var wall_cell := origin + Vector2i(2, 2)
	var wall := _designate_cell(state.get("_location_construction"), home_id, "wall", wall_cell)
	var colonist_id := state.get_colonist_ids()[0]
	_expect_ok(state.request_set_colonist_role(colonist_id, State.ROLE_CONSTRUCTION), "construction worker assigned")
	for _step in range(1200):
		state.advance_simulation(0.25)
		if state.get_construction_site(home_id, wall).is_empty(): break
	_expect(state.get_construction_site(home_id, wall).is_empty(), "job flow completes isolated wall")
	var door_cell := wall_cell
	var opening_result := state.request_designate_construction(home_id, "door", [{"cell": door_cell, "orientation_axis": "axis_x"}]); _expect_ok(opening_result, "job door conversion designated on completed wall")
	var opening := String(opening_result.get("site_ids", [""])[0])
	for _step in range(1200):
		state.advance_simulation(0.25)
		if state.get_construction_site(home_id, opening).is_empty(): break
	_expect(state.get_construction_site(home_id, opening).is_empty() and String(state.get_location_completed_structures(home_id).structure_cells[door_cell].kind) == "wall" and String(state.get_location_completed_structures(home_id).structure_cells[door_cell].fixture_kind) == "door", "job flow installs door fixture on retained wall")
	_expect_ok(registry.create_or_merge_pile(home_id, "wood", 1, Vector2i(home.camp_storage_cell), true), "UI cancellation resource created")
	var cancel_cell := origin + Vector2i(0, 4); var cancellable := state.request_designate_construction(home_id, "floor", [cancel_cell]); _expect_ok(cancellable, "UI-route cancellable site designated")
	state.advance_simulation(0.01)
	_expect(String(state.get_colonist_snapshot(colonist_id).target_id) == String(cancellable.site_ids[0]), "worker reserves UI-route cancellation target")
	var cancellation := state.request_cancel_construction(home_id, String(cancellable.site_ids[0])); _expect_ok(cancellation, "UI cancellation route reaches authority")
	_expect(String(state.get_colonist_snapshot(colonist_id).target_id).is_empty(), "UI cancellation clears transient worker execution")
	var reservation_released := true
	for pile: Dictionary in registry.get_pile_snapshots(home_id):
		if not String(pile.reservation_owner_id).is_empty(): reservation_released = false
	_expect(reservation_released, "UI cancellation releases unconsumed resource reservation")
	state.queue_free()

func _designate_cell(authority: RefCounted, location_id: String, kind: String, cell: Vector2i) -> String:
	var result: Dictionary = authority.request_designate_construction(location_id, kind, [cell]); _expect_ok(result, "designate %s at %s" % [kind, cell])
	return String(result.get("site_ids", [""])[0])

func _designate_conversion(authority: RefCounted, location_id: String, kind: String, cell: Vector2i, orientation_axis := "axis_x") -> String:
	var result: Dictionary = authority.request_designate_construction(location_id, kind, [{"cell": cell, "orientation_axis": orientation_axis}]); _expect_ok(result, "designate %s conversion at %s" % [kind, cell])
	return String(result.get("site_ids", [""])[0])

func _find_walkable_region(location: Dictionary, size: Vector2i) -> Vector2i:
	var walkable: Dictionary = {}
	for terrain: Dictionary in location.terrain: if bool(terrain.get("walkable", false)): walkable[Vector2i(terrain.cell)] = true
	for y in range(int(location.map_size.y) - size.y):
		for x in range(int(location.map_size.x) - size.x):
			var valid := true
			for oy in range(size.y):
				for ox in range(size.x):
					if not walkable.has(Vector2i(x + ox, y + oy)): valid = false; break
				if not valid: break
			if valid: return Vector2i(x, y)
	return Vector2i(-1, -1)

func _expect_ok(result: Dictionary, label: String) -> void: _expect(bool(result.get("ok", false)), "%s: %s" % [label, result.get("reason", "missing result")])
func _expect_reason(result: Dictionary, reason: String, label: String) -> void: _expect(not bool(result.get("ok", false)) and String(result.get("reason", "")) == reason, "%s: expected %s, got %s" % [label, reason, result])
func _expect(condition: bool, label: String) -> void:
	if not condition: _failures.append(label)
