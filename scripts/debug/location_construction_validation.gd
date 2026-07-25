extends SceneTree

const Registry = preload("res://scripts/simulation/location_registry.gd")
const Authority = preload("res://scripts/simulation/location_construction_state.gd")

var _failures: Array[String] = []

func _init() -> void:
	var registry := Registry.new()
	var home: Dictionary = registry.create_starting_location(24681357)
	_expect(not home.is_empty(), "starting location generated")
	var remote: Dictionary = registry.create_discovered_location(Registry.STARTING_LOCATION_ID, "general", 1, 97531, Vector2i(3, 2))
	_expect(not remote.is_empty(), "remote location generated")
	var authority := Authority.new(); authority.configure(registry)
	var region := _find_walkable_region(home, Vector2i(15, 12))
	_expect(region != Vector2i(-1, -1), "large walkable validation region found")
	if region != Vector2i(-1, -1): _run_authority_checks(registry, authority, home, remote, region)
	_run_resource_work_checks()
	if _failures.is_empty(): print("LOCATION_CONSTRUCTION_VALIDATION PASS"); quit(0)
	else:
		for failure: String in _failures: push_error(failure)
		print("LOCATION_CONSTRUCTION_VALIDATION FAIL count=", _failures.size()); quit(1)

func _run_authority_checks(registry: RefCounted, authority: RefCounted, home: Dictionary, remote: Dictionary, origin: Vector2i) -> void:
	var home_id := String(home.location_id); var remote_id := String(remote.location_id)
	var resource_cell := Vector2i(home.resources[0].cell)
	_expect_reason(authority.request_designate_construction(home_id, "wall", [resource_cell]), "resource_blocked", "active resource cell rejects")
	for resource: Dictionary in registry.get_record(home_id).resources: resource.depleted = true
	_expect_ok(authority.request_designate_construction(home_id, "wall", [origin]), "claimed location accepts wall")
	_expect_reason(authority.request_designate_construction(remote_id, "wall", [origin]), "unclaimed_location", "unclaimed location rejects")
	_expect_reason(authority.request_designate_construction("missing", "wall", [origin]), "unknown_location", "unknown location rejects")
	_expect_reason(authority.request_designate_construction(home_id, "wall", [origin]), "structure_cell_occupied", "duplicate wall rejects")
	_expect_reason(authority.request_designate_construction(home_id, "wall", [Vector2i(-1, 0)]), "cell_out_of_bounds", "out of bounds rejects")
	var invalid_terrain := _find_non_walkable(home)
	if invalid_terrain != Vector2i(-1, -1): _expect_reason(authority.request_designate_construction(home_id, "wall", [invalid_terrain]), "terrain_not_buildable", "invalid terrain rejects")
	var before: int = authority.get_location_construction_sites(home_id).size()
	_expect(not bool(authority.request_designate_construction(home_id, "wall", [origin + Vector2i(1, 0), Vector2i(-1, 0)]).ok), "invalid multi-cell request rejects")
	_expect(authority.get_location_construction_sites(home_id).size() == before, "invalid multi-cell request is atomic")
	var first_id := String(authority.get_location_construction_sites(home_id)[0].site_id)
	_expect_ok(authority.request_cancel_construction(home_id, first_id), "cancellation succeeds")
	_expect(authority.get_location_construction_sites(home_id).is_empty(), "cancellation removes site")

	_expect_ok(registry.retain(remote_id), "remote retained")
	_expect_ok(registry.add_presence(remote_id, "tester"), "remote presence added")
	_expect_ok(registry.claim(remote_id, "tester", 0.0), "remote claimed")
	_expect_ok(authority.request_designate_construction(remote_id, "floor", [_first_walkable(remote)]), "second claimed location accepts")
	_expect(authority.get_location_construction_sites(home_id).is_empty(), "construction does not leak between locations")

	var wall_cell := origin + Vector2i(2, 0)
	var wall_site := _designate_one(authority, home_id, "wall", wall_cell)
	_expect_ok(authority.request_debug_complete_construction(home_id, wall_site), "wall completion succeeds")
	var completed: Dictionary = authority.get_location_completed_structures(home_id)
	_expect(completed.structure_cells.has(wall_cell) and String(completed.structure_cells[wall_cell].kind) == "wall", "wall completion creates full-cell structure")
	_expect_ok(authority.request_designate_construction(home_id, "floor", [wall_cell]), "floor may coexist beneath a structure")
	var floor_same_site := ""
	for site: Dictionary in authority.get_location_construction_sites(home_id): if String(site.piece_kind) == "floor" and Vector2i(site.cell) == wall_cell: floor_same_site = String(site.site_id)
	if not floor_same_site.is_empty(): _expect_ok(authority.request_cancel_construction(home_id, floor_same_site), "coexisting floor fixture cancelled")
	var floor_cell := origin + Vector2i(3, 0)
	var floor_site := _designate_one(authority, home_id, "floor", floor_cell)
	_expect_reason(authority.request_designate_construction(home_id, "floor", [floor_cell]), "duplicate_construction_site", "duplicate floor rejects")
	_expect_ok(authority.request_debug_complete_construction(home_id, floor_site), "floor completion succeeds")
	_expect(authority.get_location_completed_structures(home_id).floor_cells.has(floor_cell), "floor completion creates floor")

	var opening_cell := origin + Vector2i(4, 3)
	_expect_reason(authority.request_designate_construction(home_id, "door", [_conversion_target(opening_cell)]), "compatible_wall_required", "empty cell rejects door conversion")
	_expect_reason(authority.request_designate_construction(home_id, "window", [_conversion_target(opening_cell)]), "compatible_wall_required", "empty cell rejects window conversion")
	_expect_reason(authority.request_designate_construction(home_id, "door", [{"cell": opening_cell}]), "unsupported_orientation", "door conversion requires an orientation")
	_expect_reason(authority.request_designate_construction(home_id, "door", [{"cell": opening_cell, "orientation_axis": "diagonal"}]), "unsupported_orientation", "unsupported door orientation rejects")
	_expect_reason(authority.request_designate_construction(home_id, "door", [_conversion_target(floor_cell)]), "compatible_wall_required", "floor-only cell rejects door conversion")
	var invalid_sites_before: Array[Dictionary] = authority.get_location_construction_sites(home_id)
	var invalid_completed_before: Dictionary = authority.get_location_completed_structures(home_id)
	var invalid_piles_before: Array = registry.get_pile_snapshots(home_id)
	_expect_reason(authority.request_designate_construction(home_id, "door", [_conversion_target(opening_cell)]), "compatible_wall_required", "invalid conversion rejects")
	_expect(authority.get_location_construction_sites(home_id) == invalid_sites_before and authority.get_location_completed_structures(home_id) == invalid_completed_before and registry.get_pile_snapshots(home_id) == invalid_piles_before, "invalid conversion does not mutate sites, structures, or resources")
	var opening_wall := _designate_one(authority, home_id, "wall", opening_cell)
	_expect_ok(authority.request_debug_complete_construction(home_id, opening_wall), "door source wall completes")
	var door_result: Dictionary = authority.request_designate_construction(home_id, "door", [_conversion_target(opening_cell, "axis_y")])
	_expect_ok(door_result, "completed wall accepts door conversion")
	var door := String(door_result.get("site_ids", [""])[0])
	_expect(authority.get_construction_site(home_id, door).required_resources == {"wood": 3} and is_equal_approx(float(authority.get_construction_site(home_id, door).build_required), 5.0), "door exposes static cost and work")
	_expect(String(authority.get_construction_site(home_id, door).orientation_axis) == "axis_y", "door site preserves submitted orientation")
	_expect(String(authority.get_location_completed_structures(home_id).structure_cells[opening_cell].kind) == "wall", "source wall remains authoritative during conversion")
	_expect_reason(authority.request_designate_construction(home_id, "window", [_conversion_target(opening_cell)]), "fixture_cell_occupied", "active fixture installation rejects a second fixture site")
	_expect_ok(authority.request_debug_complete_construction(home_id, door), "door completion succeeds")
	_expect_reason(authority.request_debug_complete_construction(home_id, door), "unknown_construction_site", "completed site cannot complete twice")
	completed = authority.get_location_completed_structures(home_id)
	_expect(completed.structure_cells.has(opening_cell) and String(completed.structure_cells[opening_cell].kind) == "wall" and String(completed.structure_cells[opening_cell].fixture_kind) == "door" and String(completed.structure_cells[opening_cell].fixture_orientation) == "axis_y", "door completion mutates the retained wall fixture in place")
	_expect(authority.get_wall_fixture_at_cell(home_id, opening_cell) == {"cell": opening_cell, "kind": "door", "orientation": "axis_y"}, "fixture query reports door separately from its wall")
	_expect_reason(authority.request_designate_construction(home_id, "window", [_conversion_target(opening_cell)]), "fixture_cell_occupied", "door fixture rejects window installation")
	_expect_reason(authority.request_designate_construction(home_id, "door", [_conversion_target(opening_cell)]), "fixture_cell_occupied", "door fixture rejects another installation")
	_expect_reason(authority.request_remove_completed_structure(home_id, opening_cell), "wall_fixture_present", "wall containing fixture requires fixture removal first")
	_expect_ok(authority.request_remove_wall_fixture(home_id, opening_cell), "door fixture removal succeeds")
	_expect(String(authority.get_structure_at_cell(home_id, opening_cell).kind) == "wall" and authority.get_wall_fixture_at_cell(home_id, opening_cell).is_empty(), "fixture removal preserves the plain wall")

	var window_cell := origin + Vector2i(5, 3)
	var window_wall := _designate_one(authority, home_id, "wall", window_cell)
	_expect_ok(authority.request_debug_complete_construction(home_id, window_wall), "window source wall completes")
	var window_result: Dictionary = authority.request_designate_construction(home_id, "window", [_conversion_target(window_cell)])
	_expect_ok(window_result, "completed wall accepts window conversion")
	var window_site := String(window_result.get("site_ids", [""])[0])
	_expect_reason(authority.request_remove_completed_structure(home_id, window_cell), "fixture_installation_active", "source wall cannot be removed during fixture installation")
	_expect_ok(authority.request_cancel_construction(home_id, window_site), "window conversion cancellation succeeds")
	_expect(String(authority.get_location_completed_structures(home_id).structure_cells[window_cell].kind) == "wall", "conversion cancellation preserves the source wall")
	var stale_preview: Dictionary = authority.validate_designation(home_id, "window", [_conversion_target(window_cell)])
	_expect_ok(stale_preview, "window preview validates while source wall exists")
	_expect_ok(authority.request_remove_completed_structure(home_id, window_cell), "source wall may change before submission")
	_expect_reason(authority.request_designate_construction(home_id, "window", [_conversion_target(window_cell)]), "compatible_wall_required", "stale preview revalidates and rejects without a source wall")
	window_wall = _designate_one(authority, home_id, "wall", window_cell)
	_expect_ok(authority.request_debug_complete_construction(home_id, window_wall), "replacement window source wall completes")
	window_result = authority.request_designate_construction(home_id, "window", [_conversion_target(window_cell, "axis_y")])
	_expect_ok(window_result, "window fixture installation designates")
	_expect_ok(authority.request_debug_complete_construction(home_id, String(window_result.site_ids[0])), "window fixture installation completes")
	var completed_window: Dictionary = authority.get_structure_at_cell(home_id, window_cell)
	_expect(String(completed_window.kind) == "wall" and String(completed_window.fixture_kind) == "window" and String(completed_window.fixture_orientation) == "axis_y", "window completion preserves wall base and stores fixture orientation")

	var site_snapshot: Array[Dictionary] = authority.get_location_construction_sites(remote_id); site_snapshot[0].piece_kind = "wall"
	_expect(String(authority.get_location_construction_sites(remote_id)[0].piece_kind) == "floor", "site reads are defensive")
	var completed_snapshot: Dictionary = authority.get_location_completed_structures(home_id); completed_snapshot.structure_cells.clear()
	_expect(not authority.get_location_completed_structures(home_id).structure_cells.is_empty(), "completed structure reads are defensive")

func _run_resource_work_checks() -> void:
	var registry := Registry.new(); var home: Dictionary = registry.create_starting_location(13579); var home_id := String(home.location_id)
	for resource: Dictionary in registry.get_record(home_id).resources: resource.depleted = true
	var authority := Authority.new(); authority.configure(registry)
	var origin := _find_walkable_region(home, Vector2i(6, 6))
	_expect(origin != Vector2i(-1, -1), "construction work region found")
	if origin == Vector2i(-1, -1): return
	_expect_ok(registry.create_or_merge_pile(home_id, "wood", 3, Vector2i(home.camp_storage_cell), true), "local wood supply created")
	var first := _designate_one(authority, home_id, "wall", origin)
	var first_snapshot := authority.get_construction_site(home_id, first)
	_expect(first_snapshot.required_resources == {"wood": 2} and is_equal_approx(float(first_snapshot.build_required), 4.0), "wall exposes static cost and work")
	var second := _designate_one(authority, home_id, "wall", origin + Vector2i.RIGHT)
	var first_reservation := authority.reserve_construction_site(home_id, first, "worker_a", origin + Vector2i(0, 2))
	_expect_ok(first_reservation, "site and full cost reserve atomically")
	_expect_reason(authority.reserve_construction_site(home_id, first, "worker_b", origin), "construction_site_reserved", "competing worker cannot reserve site")
	_expect(not bool(authority.get_available_construction_site(home_id, "worker_b", origin).ok), "reserved resources cannot be overcommitted")
	_expect_reason(authority.reserve_construction_site(home_id, second, "worker_b", origin), "insufficient_local_resources", "second site reports insufficient resources")
	_expect_ok(authority.release_construction_site_reservation(home_id, first, "worker_a", "test"), "pre-work release succeeds")
	_expect_ok(authority.reserve_construction_site(home_id, second, "worker_b", origin), "released resources become available")
	var before_invalid := authority.get_construction_site(home_id, second)
	_expect_reason(authority.request_progress_construction(home_id, second, "worker_b", -1.0), "invalid_work_amount", "invalid work rejects")
	var after_invalid := authority.get_construction_site(home_id, second)
	_expect(is_equal_approx(float(before_invalid.build_progress), float(after_invalid.build_progress)) and not bool(after_invalid.resources_consumed), "invalid work neither spends nor progresses")
	_expect_ok(authority.request_progress_construction(home_id, second, "worker_b", 1.0), "first valid work consumes reservation")
	var pile_after_first := registry.get_pile_snapshots(home_id)[0]
	_expect(int(pile_after_first.amount) == 1 and bool(authority.get_construction_site(home_id, second).resources_consumed), "resources consumed exactly once on first work")
	_expect_ok(authority.request_progress_construction(home_id, second, "worker_b", 1.0), "later work progresses")
	_expect(int(registry.get_pile_snapshots(home_id)[0].amount) == 1, "later work does not spend again")
	_expect_ok(authority.release_construction_site_reservation(home_id, second, "worker_b", "interrupted"), "consumed site worker can release")
	_expect_ok(authority.reserve_construction_site(home_id, second, "worker_c", origin), "consumed site can be reassigned without another cost")
	_expect_ok(authority.request_progress_construction(home_id, second, "worker_c", 2.0), "reassigned worker completes site")
	_expect(authority.get_location_completed_structures(home_id).structure_cells.has(origin + Vector2i.RIGHT), "authoritative work completion creates wall structure cell")
	_expect_reason(authority.request_progress_construction(home_id, second, "worker_c", 1.0), "unknown_construction_site", "completed site cannot complete twice")
	_expect_ok(registry.create_or_merge_pile(home_id, "wood", 2, Vector2i(home.camp_storage_cell), true), "stale cleanup supply created")
	var stale := _designate_one(authority, home_id, "wall", origin + Vector2i(2, 0))
	_expect_ok(authority.reserve_construction_site(home_id, stale, "removed_worker", origin), "stale worker reserves")
	var cleanup := authority.cleanup_stale_construction_reservations(home_id, ["worker_c"])
	_expect(String(stale) in cleanup.released_site_ids and String(authority.get_construction_site(home_id, stale).reserved_by_colonist_id).is_empty(), "stale worker cleanup releases site and resources")
	var cancelled := _designate_one(authority, home_id, "wall", origin + Vector2i(3, 0))
	_expect_ok(authority.reserve_construction_site(home_id, cancelled, "worker_d", origin), "cancelled site reserves")
	_expect_ok(authority.request_cancel_construction(home_id, cancelled), "pre-work cancellation succeeds")
	_expect(bool(registry.can_reserve_local_resources(home_id, {"wood": 3})), "pre-work cancellation restores full resource availability")
	var floor := _designate_one(authority, home_id, "floor", origin + Vector2i(0, 2))
	var floor_snapshot := authority.get_construction_site(home_id, floor)
	_expect(floor_snapshot.required_resources == {"wood": 1} and is_equal_approx(float(floor_snapshot.build_required), 2.0), "floor exposes static cost and work")
	_expect(Vector2i(authority.resolve_construction_work_cell(home_id, floor, origin).work_cell) == Vector2i(floor_snapshot.cell), "floor work cell is the site cell")
	_expect_ok(authority.reserve_construction_site(home_id, floor, "worker_e", origin), "floor reserves")
	_expect_ok(authority.request_progress_construction(home_id, floor, "worker_e", 0.5), "floor consumes on first work")
	var amount_after_consumption := int(registry.get_pile_snapshots(home_id)[0].amount)
	_expect_ok(authority.request_cancel_construction(home_id, floor), "consumed construction may use existing cancellation rule")
	_expect(int(registry.get_pile_snapshots(home_id)[0].amount) == amount_after_consumption, "cancellation after consumption does not refund")

func _designate_one(authority: RefCounted, location_id: String, kind: String, cell: Vector2i) -> String:
	var result: Dictionary = authority.request_designate_construction(location_id, kind, [cell])
	_expect_ok(result, "designate %s at %s" % [kind, cell])
	return String(result.get("site_ids", [""])[0])

func _conversion_target(cell: Vector2i, orientation_axis := "axis_x") -> Dictionary:
	return {"cell": cell, "orientation_axis": orientation_axis}

func _complete_walls(authority: RefCounted, location_id: String, cells: Array[Vector2i]) -> void:
	for cell: Vector2i in cells:
		var site_id := _designate_one(authority, location_id, "wall", cell)
		_expect_ok(authority.request_debug_complete_construction(location_id, site_id), "complete wall at %s" % cell)

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

func _first_walkable(location: Dictionary) -> Vector2i:
	var blocked: Dictionary = {}; for resource: Dictionary in location.resources: if not bool(resource.get("depleted", false)): blocked[Vector2i(resource.cell)] = true
	for terrain: Dictionary in location.terrain: if bool(terrain.get("walkable", false)) and not blocked.has(Vector2i(terrain.cell)): return Vector2i(terrain.cell)
	return Vector2i(-1, -1)

func _find_non_walkable(location: Dictionary) -> Vector2i:
	for terrain: Dictionary in location.terrain: if not bool(terrain.get("walkable", false)): return Vector2i(terrain.cell)
	return Vector2i(-1, -1)

func _expect_ok(result: Dictionary, label: String) -> void: _expect(bool(result.get("ok", false)), "%s: %s" % [label, result.get("reason", "missing result")])
func _expect_reason(result: Dictionary, reason: String, label: String) -> void: _expect(not bool(result.get("ok", false)) and String(result.get("reason", "")) == reason, "%s: expected %s, got %s" % [label, reason, result])
func _expect(condition: bool, label: String) -> void:
	if not condition: _failures.append(label)
