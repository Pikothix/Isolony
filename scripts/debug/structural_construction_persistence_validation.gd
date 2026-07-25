extends SceneTree

const Registry = preload("res://scripts/simulation/location_registry.gd")
const Authority = preload("res://scripts/simulation/location_construction_state.gd")
const SaveService = preload("res://scripts/simulation/save_game_service.gd")

var _failures: Array[String] = []
var _checks := 0

func _init() -> void:
	var registry := Registry.new(); var home: Dictionary = registry.create_starting_location(13579); var home_id := String(home.location_id)
	for resource: Dictionary in registry.get_record(home_id).resources: resource.depleted = true
	registry.create_or_merge_pile(home_id, "wood", 100, Vector2i(home.camp_storage_cell), true)
	var remote: Dictionary = registry.create_discovered_location(home_id, "general", 1, 24680, Vector2i(3, 2)); var remote_id := String(remote.location_id)
	_expect_ok(registry.retain(remote_id), "remote retained"); _expect_ok(registry.add_presence(remote_id, "remote_worker"), "remote presence added"); _expect_ok(registry.claim(remote_id, "remote_worker", 0.0), "remote claimed")
	for resource: Dictionary in registry.get_record(remote_id).resources: resource.depleted = true
	var authority := Authority.new(); authority.configure(registry)
	var origin := _find_walkable_region(home, Vector2i(8, 8)); _check(origin != Vector2i(-1, -1), "walkable test region exists")
	if origin == Vector2i(-1, -1): _finish(); return

	var completed_floor := _designate(authority, home_id, "floor", origin)
	var completed_wall := _complete(authority, home_id, "wall", origin + Vector2i.RIGHT)
	var door_wall := _complete(authority, home_id, "wall", origin + Vector2i(2, 0))
	var completed_door := _designate_target(authority, home_id, "door", {"cell": origin + Vector2i(2, 0), "orientation_axis": "axis_x"})
	var window_wall := _complete(authority, home_id, "wall", origin + Vector2i(3, 0))
	var completed_window := _designate_target(authority, home_id, "window", {"cell": origin + Vector2i(3, 0), "orientation_axis": "axis_y"})
	for site_id: String in [completed_floor, completed_door, completed_window]: _expect_ok(authority.request_debug_complete_construction(home_id, site_id), "complete structural site")
	_check(not completed_wall.is_empty() and not door_wall.is_empty() and not window_wall.is_empty(), "completed wall identifiers created")

	var incomplete_ids: Array[String] = []
	incomplete_ids.append(_partial(authority, home_id, "floor", origin + Vector2i(0, 2), "floor_worker", 0.5))
	incomplete_ids.append(_partial(authority, home_id, "wall", origin + Vector2i(1, 2), "wall_worker", 1.0))
	_complete(authority, home_id, "wall", origin + Vector2i(2, 2))
	incomplete_ids.append(_partial_target(authority, home_id, "door", {"cell": origin + Vector2i(2, 2), "orientation_axis": "axis_y"}, "door_worker", 1.25))
	_complete(authority, home_id, "wall", origin + Vector2i(3, 2))
	incomplete_ids.append(_partial_target(authority, home_id, "window", {"cell": origin + Vector2i(3, 2), "orientation_axis": "axis_x"}, "window_worker", 0.75))
	var designated := _designate(authority, home_id, "floor", origin + Vector2i(4, 2)); incomplete_ids.append(designated)
	var remote_floor_cell := _first_walkable(remote); var remote_floor := _complete(authority, remote_id, "floor", remote_floor_cell)
	_check(not remote_floor.is_empty(), "second location structural record created")

	var saved := authority.export_state(); var restored_registry := Registry.new(); _expect_ok(restored_registry.import_state(registry.export_state()), "registry clone imports")
	var restored := Authority.new(); restored.configure(restored_registry); _expect_ok(restored.import_state(saved), "structural section imports")
	_check(restored.export_state() == saved, "normalized structural authority round trips exactly")
	var service := SaveService.new(); var encoded: Variant = service.call("_encode_vectors", {"structural_construction": saved}); var parsed: Variant = JSON.parse_string(JSON.stringify(encoded)); var decoded: Variant = service.call("_decode_vectors", parsed)
	var json_restored := Authority.new(); json_restored.configure(restored_registry); _expect_ok(json_restored.import_state(decoded.structural_construction), "JSON structural section imports")
	_check(json_restored.export_state() == saved, "JSON round trip preserves normalized structural authority")
	var completed := restored.get_location_completed_structures(home_id)
	_check(completed.floor_cells.has(origin) and completed.structure_cells.has(origin + Vector2i.RIGHT), "completed floors and walls restore")
	_check(String(completed.structure_cells[origin + Vector2i(2, 0)].fixture_kind) == "door" and String(completed.structure_cells[origin + Vector2i(3, 0)].fixture_kind) == "window", "completed door and window restore")
	_check(restored.get_location_completed_structures(remote_id).floor_cells.has(remote_floor_cell), "mixed structural state restores across locations")
	for site_id: String in incomplete_ids:
		var before := authority.get_construction_site(home_id, site_id); var after := restored.get_construction_site(home_id, site_id)
		_check(not after.is_empty() and is_equal_approx(float(after.build_progress), float(before.build_progress)) and bool(after.resources_consumed) == bool(before.resources_consumed), "incomplete progress/material state restores for %s" % site_id)
		_check(String(after.reserved_by_colonist_id).is_empty(), "worker assignment excluded for %s" % site_id)
	var available := restored.get_available_construction_site(home_id, "rediscovery_worker", origin)
	_check(bool(available.ok), "unfinished construction is rediscoverable")

	var empty := Authority.new(); empty.configure(restored_registry); var empty_data := empty.export_state(); var empty_restored := Authority.new(); empty_restored.configure(restored_registry)
	_expect_ok(empty_restored.import_state(empty_data), "empty structural state round trips")
	_check(empty_restored.export_state() == empty_data, "empty state remains empty")

	_test_invalid(restored, saved, func(data: Dictionary) -> void: _construction_location(data).construction_sites[0].erase("site_id"), "missing identifier")
	_test_invalid(restored, saved, func(data: Dictionary) -> void: _construction_location(data).construction_sites[0].cell = "bad", "invalid cell")
	_test_invalid(restored, saved, func(data: Dictionary) -> void: _construction_location(data).construction_sites[0].piece_kind = "unknown", "unknown type")
	_test_invalid(restored, saved, func(data: Dictionary) -> void: _construction_location(data).construction_sites[1].site_id = _construction_location(data).construction_sites[0].site_id, "duplicate identifier")
	_test_invalid(restored, saved, func(data: Dictionary) -> void: _construction_location(data).construction_sites[0].build_progress = -1.0, "invalid progress")
	_test_invalid(restored, saved, func(data: Dictionary) -> void: _construction_location(data).location_id = "missing", "missing location")
	_finish()

func _test_invalid(authority: RefCounted, saved: Dictionary, mutate: Callable, label: String) -> void:
	var invalid: Dictionary = saved.duplicate(true); mutate.call(invalid); var before: Dictionary = authority.export_state(); var result: Dictionary = authority.import_state(invalid)
	_check(not bool(result.ok) and authority.export_state() == before, "%s rejects without partial replacement" % label)

func _construction_location(data: Dictionary) -> Dictionary:
	for location: Dictionary in data.locations:
		if (location.construction_sites as Array).size() >= 2: return location
	return {}

func _partial(authority: RefCounted, location_id: String, kind: String, cell: Vector2i, worker: String, progress: float) -> String:
	return _partial_id(authority, location_id, _designate(authority, location_id, kind, cell), worker, progress)
func _partial_target(authority: RefCounted, location_id: String, kind: String, target: Dictionary, worker: String, progress: float) -> String:
	return _partial_id(authority, location_id, _designate_target(authority, location_id, kind, target), worker, progress)
func _partial_id(authority: RefCounted, location_id: String, site_id: String, worker: String, progress: float) -> String:
	_expect_ok(authority.reserve_construction_site(location_id, site_id, worker, Vector2i(authority.get_construction_site(location_id, site_id).cell)), "reserve incomplete %s" % site_id)
	_expect_ok(authority.request_progress_construction(location_id, site_id, worker, progress), "progress incomplete %s" % site_id)
	return site_id
func _complete(authority: RefCounted, location_id: String, kind: String, cell: Vector2i) -> String:
	var site_id: String = _designate(authority, location_id, kind, cell); _expect_ok(authority.request_debug_complete_construction(location_id, site_id), "complete %s" % site_id); return site_id
func _designate(authority: RefCounted, location_id: String, kind: String, cell: Vector2i) -> String:
	return _designate_target(authority, location_id, kind, cell)
func _designate_target(authority: RefCounted, location_id: String, kind: String, target: Variant) -> String:
	var result: Dictionary = authority.request_designate_construction(location_id, kind, [target]); _expect_ok(result, "designate %s" % kind); return String(result.get("site_ids", [""])[0])

func _find_walkable_region(location: Dictionary, size: Vector2i) -> Vector2i:
	var walkable: Dictionary = {}; for terrain: Dictionary in location.terrain: if bool(terrain.get("walkable", false)): walkable[Vector2i(terrain.cell)] = true
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
	for terrain: Dictionary in location.terrain:
		if bool(terrain.get("walkable", false)): return Vector2i(terrain.cell)
	return Vector2i(-1, -1)

func _expect_ok(result: Dictionary, label: String) -> void: _check(bool(result.get("ok", false)), "%s: %s" % [label, result.get("reason", "missing result")])
func _check(condition: bool, label: String) -> void: _checks += 1; if not condition: _failures.append(label)
func _finish() -> void:
	if _failures.is_empty(): print("STRUCTURAL_CONSTRUCTION_PERSISTENCE_VALIDATION: PASS (%d checks)" % _checks); quit(0)
	else:
		for failure: String in _failures: push_error(failure)
		quit(1)
