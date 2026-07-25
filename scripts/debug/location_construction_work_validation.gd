extends SceneTree

const State = preload("res://scripts/simulation/windowed_colony_state.gd")

var _failures: Array[String] = []

func _init() -> void:
	var state := State.new(); root.add_child(state)
	_expect_ok(state.request_new_game(86420), "new game starts")
	_expect_ok(state.request_settle_starting_location(), "home settles")
	var registry: RefCounted = state.get("_registry")
	var home_id := State.LOCATION_ID
	var home: Dictionary = registry.get_record(home_id)
	for resource: Dictionary in home.resources: resource.depleted = true
	var build_cell := _first_free_walkable(home, [Vector2i(home.camp_storage_cell)])
	_expect(build_cell != Vector2i(-1, -1), "free construction cell found")
	_expect_ok(registry.create_or_merge_pile(home_id, "wood", 2, Vector2i(home.camp_storage_cell), true), "construction wood created")
	var designation := state.request_designate_construction(home_id, "wall", [build_cell])
	_expect_ok(designation, "wall designated")
	var site_id := String(designation.get("site_ids", [""])[0])
	var colonist_id := state.get_colonist_ids()[0]
	_expect_reason(state.get_available_construction_site("another_location", colonist_id), "colonist_not_present", "colonist cannot inspect another location")
	_expect_ok(state.request_set_colonist_role(colonist_id, State.ROLE_CONSTRUCTION), "colonist assigned construction")
	for _step in range(180):
		state.advance_simulation(0.25)
		if state.get_construction_site(home_id, site_id).is_empty(): break
	_expect(state.get_construction_site(home_id, site_id).is_empty(), "colonist completes reserved site")
	_expect(state.get_location_completed_structures(home_id).structure_cells.has(build_cell), "colonist completion mutates authoritative structure-cell state")
	_expect(int(registry.get_pile_snapshots(home_id)[0].amount) == 0, "colonist work consumes exact wall cost")

	_expect_ok(registry.create_or_merge_pile(home_id, "wood", 2, Vector2i(home.camp_storage_cell), true), "cancellation wood created")
	var second_cell := _first_free_walkable(home, [Vector2i(home.camp_storage_cell), build_cell])
	var second := state.request_designate_construction(home_id, "wall", [second_cell]); _expect_ok(second, "second wall designated")
	var second_id := String(second.get("site_ids", [""])[0])
	state.advance_simulation(0.01)
	_expect(String(state.get_construction_site(home_id, second_id).reserved_by_colonist_id) == colonist_id, "idle construction colonist reserves candidate")
	_expect_ok(state.request_set_colonist_role(colonist_id, State.ROLE_NONE), "role change cancels execution")
	_expect(String(state.get_construction_site(home_id, second_id).reserved_by_colonist_id).is_empty(), "role change releases site reservation")
	_expect(String(registry.get_pile_snapshots(home_id)[0].reservation_owner_id).is_empty(), "role change releases resource reservation")

	if _failures.is_empty(): print("LOCATION_CONSTRUCTION_WORK_VALIDATION PASS"); quit(0)
	else:
		for failure: String in _failures: push_error(failure)
		print("LOCATION_CONSTRUCTION_WORK_VALIDATION FAIL count=", _failures.size()); quit(1)

func _first_free_walkable(location: Dictionary, excluded: Array[Vector2i]) -> Vector2i:
	var walkable: Dictionary = {}
	for terrain: Dictionary in location.terrain:
		if bool(terrain.get("walkable", false)): walkable[Vector2i(terrain.cell)] = true
	for terrain: Dictionary in location.terrain:
		var cell := Vector2i(terrain.cell)
		if not bool(terrain.get("walkable", false)) or cell in excluded: continue
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if walkable.has(cell + offset): return cell
	return Vector2i(-1, -1)

func _expect_ok(result: Dictionary, label: String) -> void: _expect(bool(result.get("ok", false)), "%s: %s" % [label, result.get("reason", "missing result")])
func _expect_reason(result: Dictionary, reason: String, label: String) -> void: _expect(not bool(result.get("ok", false)) and String(result.get("reason", "")) == reason, "%s: expected %s, got %s" % [label, reason, result])
func _expect(condition: bool, label: String) -> void:
	if not condition: _failures.append(label)
