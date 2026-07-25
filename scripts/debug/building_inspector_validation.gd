extends SceneTree

const State = preload("res://scripts/simulation/windowed_colony_state.gd")

var _failures: Array[String] = []

func _init() -> void:
	var state := State.new()
	_expect_ok(state.request_new_game(7132026), "new game")
	_expect_ok(state.request_settle_starting_location(), "settle starting location")
	var location := state.get_location_snapshot(State.LOCATION_ID)
	var origin := _find_valid_origin(state, location)
	_expect(origin != Vector2i(-1, -1), "valid Supply Cache origin found")
	if origin != Vector2i(-1, -1): _run_snapshot_checks(state, origin)
	if _failures.is_empty(): print("BUILDING_INSPECTOR_VALIDATION PASS"); quit(0)
	else:
		for failure: String in _failures: push_error(failure)
		print("BUILDING_INSPECTOR_VALIDATION FAIL count=", _failures.size()); quit(1)

func _run_snapshot_checks(state: Node, origin: Vector2i) -> void:
	var colonist_id: String = state.get_colonist_ids()[0]
	var placed: Dictionary = state.request_place_building(colonist_id, State.LOCATION_ID, "supply_cache", origin)
	_expect_ok(placed, "Supply Cache placement")
	var building_id := String(placed.get("building_instance_id", ""))
	var save_before_read: Dictionary = state.export_save_data()
	var planned: Dictionary = state.get_building_inspector_snapshot(building_id)
	_expect(String(planned.building_id) == building_id and String(planned.display_name) == "Supply Cache", "snapshot exposes stable identity and definition name")
	_expect(String(planned.building_type) == "supply_cache" and not bool(planned.completed) and String(planned.completion_state) == "PLANNED", "snapshot exposes type and completion")
	_expect(String(planned.world_space_id) == State.LOCATION_ID and planned.occupied_cells == [origin], "snapshot exposes location and footprint")
	_expect(not bool(planned.tracking.occupants_supported) and planned.occupants.is_empty(), "occupants are explicitly unsupported")
	_expect(bool(planned.tracking.stored_items_supported) and planned.stored_items.is_empty(), "authoritative storage support reports empty contents")
	_expect(not bool(planned.tracking.furniture_supported) and planned.furniture.is_empty(), "furniture is explicitly unsupported")
	_expect(not bool(planned.enclosed) and int(planned.interior_cell_count) == 0, "placed building reports no derived enclosure")
	planned.occupied_cells.clear(); planned.tracking.stored_items_supported = false
	var reread: Dictionary = state.get_building_inspector_snapshot(building_id)
	_expect(reread.occupied_cells == [origin] and bool(reread.tracking.stored_items_supported), "inspector snapshot is defensive")
	_expect(state.export_save_data() == save_before_read, "inspector reads and caller mutation do not change save authority")
	var construction: RefCounted = state.get("_construction")
	var registry: RefCounted = state.get("_registry")
	var home: Dictionary = registry.get_record(State.LOCATION_ID)
	_expect_ok(registry.create_or_merge_pile(State.LOCATION_ID, "wood", 30, Vector2i(home.camp_storage_cell), true), "provide construction material through registry")
	_expect_ok(construction.assign_worker(colonist_id, State.LOCATION_ID, building_id), "assign Supply Cache worker through owner")
	var completion: Dictionary = construction.advance_worker(colonist_id, State.LOCATION_ID, 20.0, 100.0, building_id)
	_expect_ok(completion, "complete Supply Cache through owner")
	if not bool(completion.ok): return
	_expect_ok(construction.reserve_storage(State.LOCATION_ID, "wood", 7, "inspector_validation"), "reserve authoritative storage")
	_expect_ok(construction.store_reserved("inspector_validation"), "store authoritative contents")
	var completed: Dictionary = state.get_building_inspector_snapshot(building_id)
	_expect(bool(completed.completed) and String(completed.completion_state) == "COMPLETED", "completed state projects")
	_expect(completed.stored_items == [{"resource_type": "wood", "amount": 7}], "stored items come from authoritative storage contents")
	completed.stored_items[0].amount = 999
	_expect(int(state.get_building_inspector_snapshot(building_id).stored_items[0].amount) == 7, "stored item entries are defensive")
	var wall_cell := _find_valid_wall_cell(state, home, origin)
	_expect(wall_cell != Vector2i(-1, -1), "structure inspector wall cell found")
	if wall_cell != Vector2i(-1, -1):
		var wall: Dictionary = state.request_designate_construction(State.LOCATION_ID, "wall", [wall_cell]); _expect_ok(wall, "structure inspector wall designated")
		_expect_ok(state.request_debug_complete_construction(State.LOCATION_ID, String(wall.site_ids[0])), "structure inspector wall completed")
		var door: Dictionary = state.request_designate_construction(State.LOCATION_ID, "door", [{"cell": wall_cell, "orientation_axis": "axis_y"}]); _expect_ok(door, "structure inspector door fixture designated")
		_expect_ok(state.request_debug_complete_construction(State.LOCATION_ID, String(door.site_ids[0])), "structure inspector door fixture completed")
		var structure_inspector: Dictionary = state.get_structure_inspector_snapshot(State.LOCATION_ID, wall_cell)
		_expect(String(structure_inspector.structure_kind) == "wall" and String(structure_inspector.fixture_kind) == "door" and String(structure_inspector.fixture_orientation) == "axis_y", "structure inspector reports wall and fixture separately")
		structure_inspector.fixture_kind = "window"
		_expect(String(state.get_structure_inspector_snapshot(State.LOCATION_ID, wall_cell).fixture_kind) == "door", "structure inspector snapshot is defensive")

func _find_valid_origin(state: Node, location: Dictionary) -> Vector2i:
	for terrain: Dictionary in location.terrain:
		var cell := Vector2i(terrain.cell)
		if bool(state.validate_building_placement(State.LOCATION_ID, "supply_cache", cell).ok): return cell
	return Vector2i(-1, -1)

func _find_valid_wall_cell(state: Node, location: Dictionary, excluded: Vector2i) -> Vector2i:
	for terrain: Dictionary in location.terrain:
		var cell := Vector2i(terrain.cell)
		if cell != excluded and bool(state.validate_construction_designation(State.LOCATION_ID, "wall", [cell]).ok): return cell
	return Vector2i(-1, -1)

func _expect_ok(result: Dictionary, label: String) -> void:
	_expect(bool(result.get("ok", false)), "%s: %s" % [label, result.get("reason", "missing result")])

func _expect(condition: bool, label: String) -> void:
	if not condition: _failures.append(label)
