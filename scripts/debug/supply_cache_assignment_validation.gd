extends SceneTree

const State = preload("res://scripts/simulation/windowed_colony_state.gd")
const COMPLETED := "COMPLETED"

var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	await _validate_normal_lifecycle()
	await _validate_explicit_release()
	await _validate_worker_removal_and_cleanup()
	await _validate_task_reset()
	await _validate_remote_travel_failure()
	await _validate_site_removal()
	await _validate_assignment_audit()
	await _validate_save_load()
	await _validate_population_replacement()
	if _failures.is_empty(): print("SUPPLY_CACHE_ASSIGNMENT_VALIDATION: PASS (%d checks)" % _checks); quit(0)
	else:
		for failure: String in _failures: push_error("SUPPLY_CACHE_ASSIGNMENT_VALIDATION: " + failure)
		quit(1)

func _validate_normal_lifecycle() -> void:
	var env := await _home_cache(71001)
	var state: WindowedColonyState = env.state; var owner: LocationConstructionCoordinator = state.get("_construction")
	var worker_id := String(env.worker_id); var competitor_id := String(env.competitor_id); var building_id := String(env.building_id)
	_expect_ok(state.request_set_colonist_role(worker_id, State.ROLE_CONSTRUCTION), "normal: construction role")
	state.advance_simulation(0.01)
	var assigned := state.get_building_snapshot(building_id)
	_expect(String(assigned.assigned_worker_id) == worker_id and String(state.get_colonist_snapshot(worker_id).target_id) == building_id, "normal: runtime assigns worker and exact task")
	_expect_reason(owner.assign_worker(competitor_id, State.LOCATION_ID, building_id), "building_reserved", "normal: competing worker rejected")
	_expect_reason(owner.assign_worker("missing_worker", State.LOCATION_ID, building_id), "invalid_worker", "normal: invalid worker rejected")
	_expect_ok(owner.advance_worker(worker_id, State.LOCATION_ID, 10.0, 1.0, building_id), "normal: construction progresses")
	var progressed := state.get_building_snapshot(building_id)
	_expect(float(progressed.build_progress) > 0.0 and bool(progressed.resources_consumed), "normal: progress consumes materials once")
	_expect_ok(owner.advance_worker(worker_id, State.LOCATION_ID, 20.0, 1000.0, building_id), "normal: construction completes")
	var completed := state.get_building_snapshot(building_id)
	_expect(String(completed.state) == COMPLETED and String(completed.assigned_worker_id).is_empty(), "normal: completion clears assignment")
	_expect_reason(owner.assign_worker(worker_id, State.LOCATION_ID, building_id), "building_completed", "normal: completed site rejects assignment")
	_expect_reason(owner.assign_worker(worker_id, State.LOCATION_ID, "missing_building"), "building_missing", "normal: missing site rejects assignment")

func _validate_explicit_release() -> void:
	var env := await _home_cache(71002)
	var state: WindowedColonyState = env.state; var owner: LocationConstructionCoordinator = state.get("_construction")
	var worker_id := String(env.worker_id); var building_id := String(env.building_id)
	_expect_ok(owner.assign_worker(worker_id, State.LOCATION_ID, building_id), "release: assignment")
	state.get("_colonists")[worker_id].target_id = building_id
	_expect_ok(owner.advance_worker(worker_id, State.LOCATION_ID, 10.0, 0.5, building_id), "release: consume and progress")
	var before := state.get_building_snapshot(building_id); var wood_before := _pile_total(state, State.LOCATION_ID, "wood")
	_expect_ok(owner.release_worker(building_id, worker_id, "validation_release"), "release: explicit release")
	var after := state.get_building_snapshot(building_id)
	_expect(String(after.assigned_worker_id).is_empty() and state.is_supply_cache_available_for_worker(building_id, worker_id), "release: site becomes available")
	_expect(is_equal_approx(float(after.build_progress), float(before.build_progress)) and bool(after.resources_consumed) == bool(before.resources_consumed), "release: progress and consumed state unchanged")
	_expect(_pile_total(state, State.LOCATION_ID, "wood") == wood_before, "release: consumed materials are not refunded")

func _validate_worker_removal_and_cleanup() -> void:
	var env := await _home_cache(71003)
	var state: WindowedColonyState = env.state; var owner: LocationConstructionCoordinator = state.get("_construction")
	var worker_id := String(env.worker_id); var competitor_id := String(env.competitor_id); var building_id := String(env.building_id)
	_expect_ok(owner.assign_worker(worker_id, State.LOCATION_ID, building_id), "removal: assignment")
	state.get("_colonists")[worker_id].target_id = building_id
	state.get("_registry").remove_presence(State.LOCATION_ID, worker_id); state.get("_colonists").erase(worker_id)
	var first := state.audit_supply_cache_assignments(); var second := state.audit_supply_cache_assignments()
	_expect(building_id in first and second.is_empty(), "removal: cleanup clears once and is idempotent")
	_expect_ok(owner.assign_worker(competitor_id, State.LOCATION_ID, building_id), "removal: another worker can claim")

func _validate_task_reset() -> void:
	var env := await _home_cache(71004)
	var state: WindowedColonyState = env.state; var worker_id := String(env.worker_id); var building_id := String(env.building_id)
	_expect_ok(state.request_set_colonist_role(worker_id, State.ROLE_CONSTRUCTION), "reset: construction role")
	state.advance_simulation(0.01)
	_expect(String(state.get_building_snapshot(building_id).assigned_worker_id) == worker_id, "reset: runtime assignment exists")
	_expect_ok(state.request_set_colonist_role(worker_id, State.ROLE_NONE), "reset: actual role reset")
	_expect(String(state.get_building_snapshot(building_id).assigned_worker_id).is_empty(), "reset: role reset releases immediately")
	_expect_ok(state.request_set_colonist_role(worker_id, State.ROLE_CONSTRUCTION), "reset: construction role restored")
	state.advance_simulation(0.01)
	_expect_ok(state.request_start_scouting(worker_id, "woodland"), "reset: scouting departure")
	_expect(String(state.get_building_snapshot(building_id).assigned_worker_id).is_empty(), "reset: scouting departure releases immediately")

func _validate_remote_travel_failure() -> void:
	var state := await _new_state(71005); var worker_id := state.get_colonist_ids()[0]
	_expect_ok(state.request_start_scouting(worker_id, "woodland"), "travel: scouting starts")
	var scout := state.get_scouting_snapshot(worker_id); state.advance_simulation(float(scout.duration) + 0.1)
	var remote_id := state.get_location_ids()[1]
	_expect_ok(state.request_retain_location(remote_id), "travel: remote retained")
	_expect_ok(state.request_send_colonist_to_location(worker_id, remote_id), "travel: worker sent remote")
	var travel := state.get_travel_snapshot(worker_id); state.advance_simulation(float(travel.travel_duration) + 0.1)
	_expect_ok(state.request_claim_location(worker_id, remote_id), "travel: remote claimed")
	var cell := _find_valid_cell(state, remote_id); _expect(cell != Vector2i(-1, -1), "travel: remote cache cell")
	var placed := state.request_place_building(worker_id, remote_id, "supply_cache", cell); _expect_ok(placed, "travel: remote cache placed")
	var building_id := String(placed.get("building_instance_id", ""))
	state.get("_registry").create_or_merge_pile(remote_id, "wood", 40, Vector2i(state.get_location_snapshot(remote_id).entry_cell), false)
	_expect_ok(state.request_set_colonist_role(worker_id, State.ROLE_CONSTRUCTION), "travel: remote construction role")
	state.advance_simulation(0.01)
	_expect(String(state.get_building_snapshot(building_id).assigned_worker_id) == worker_id, "travel: remote assignment exists")
	state.get("_colonists")[worker_id].construction_travel_elapsed = State.CONSTRUCTION_TRAVEL_TIMEOUT
	state.get("_colonists")[worker_id].cell = Vector2i(state.get_location_snapshot(remote_id).entry_cell)
	state.advance_simulation(0.01)
	_expect(String(state.get_building_snapshot(building_id).assigned_worker_id).is_empty(), "travel: failed or timed-out local travel releases remote cache")
	_expect(_pile_total(state, remote_id, "wood") == 40, "travel: unconsumed remote materials are neither lost nor duplicated")
	state.advance_simulation(0.01)
	_expect(String(state.get_building_snapshot(building_id).assigned_worker_id) == worker_id, "travel: remote cache can be reassigned after failure")
	_expect_ok(state.request_return_colonist_home(worker_id), "travel: location departure")
	_expect(String(state.get_building_snapshot(building_id).assigned_worker_id).is_empty(), "travel: location departure releases immediately")

func _validate_site_removal() -> void:
	var env := await _home_cache(71006)
	var state: WindowedColonyState = env.state; var owner: LocationConstructionCoordinator = state.get("_construction")
	var worker_id := String(env.worker_id); var building_id := String(env.building_id); var wood_before := _pile_total(state, State.LOCATION_ID, "wood")
	_expect_ok(owner.assign_worker(worker_id, State.LOCATION_ID, building_id), "site removal: assignment")
	state.get("_colonists")[worker_id].target_id = building_id
	_expect_ok(state.request_cancel_building(building_id), "site removal: supported cancellation")
	_expect(state.get_building_snapshot(building_id).is_empty() and String(state.get_colonist_snapshot(worker_id).target_id).is_empty(), "site removal: record and task cleared")
	_expect(_pile_total(state, State.LOCATION_ID, "wood") == wood_before, "site removal: unconsumed reservation released without resource mutation")

func _validate_assignment_audit() -> void:
	var env := await _home_cache(71007)
	var state: WindowedColonyState = env.state; var owner: LocationConstructionCoordinator = state.get("_construction")
	var worker_id := String(env.worker_id); var building_id := String(env.building_id)
	_expect_ok(state.request_set_colonist_role(worker_id, State.ROLE_CONSTRUCTION), "audit: construction role")
	_expect_ok(owner.assign_worker(worker_id, State.LOCATION_ID, building_id), "audit: assignment")
	state.get("_colonists")[worker_id].target_id = building_id
	_expect(state.audit_supply_cache_assignments().is_empty() and String(state.get_building_snapshot(building_id).assigned_worker_id) == worker_id, "audit: valid exact task protected")
	state.get("_colonists")[worker_id].target_id = "different_task"
	_expect(building_id in state.audit_supply_cache_assignments() and String(state.get_building_snapshot(building_id).assigned_worker_id).is_empty(), "audit: mismatched task cleared")

func _validate_save_load() -> void:
	var env := await _home_cache(71008)
	var state: WindowedColonyState = env.state; var owner: LocationConstructionCoordinator = state.get("_construction")
	var worker_id := String(env.worker_id); var building_id := String(env.building_id)
	_expect_ok(owner.assign_worker(worker_id, State.LOCATION_ID, building_id), "save: assignment")
	state.get("_colonists")[worker_id].target_id = building_id
	_expect_ok(owner.advance_worker(worker_id, State.LOCATION_ID, 10.0, 1.0, building_id), "save: progress")
	var before := state.get_building_snapshot(building_id); var wood_before := _pile_total(state, State.LOCATION_ID, "wood")
	var saved := state.export_save_data(); var exported: Dictionary = saved.location_construction.buildings[0]
	_expect(String(exported.assigned_worker_id).is_empty() and String(exported.material_reservation_id).is_empty(), "save: transient assignment excluded")
	var restored: WindowedColonyState = State.new(); root.add_child(restored); await process_frame; restored.set_process(false)
	_expect_ok(restored.import_save_data(saved), "save: load")
	var loaded := restored.get_building_snapshot(building_id)
	_expect(String(loaded.assigned_worker_id).is_empty() and is_equal_approx(float(loaded.build_progress), float(before.build_progress)) and bool(loaded.resources_consumed), "save: progress persists and assignment clears")
	_expect(_pile_total(restored, State.LOCATION_ID, "wood") == wood_before and restored.is_supply_cache_available_for_worker(building_id, worker_id), "save: materials conserved and site rediscoverable")

func _validate_population_replacement() -> void:
	var env := await _home_cache(71009)
	var state: WindowedColonyState = env.state; var owner: LocationConstructionCoordinator = state.get("_construction")
	var old_worker_id := String(env.worker_id); var building_id := String(env.building_id)
	_expect_ok(owner.assign_worker(old_worker_id, State.LOCATION_ID, building_id), "replacement: assignment")
	_expect_ok(state.request_new_game(71010), "replacement: new population")
	var stale_found := false
	for building: Dictionary in state.get_building_snapshots(State.LOCATION_ID): stale_found = stale_found or String(building.assigned_worker_id) == old_worker_id
	_expect(not stale_found, "replacement: old colonist id does not survive")

func _home_cache(seed_value: int) -> Dictionary:
	var state := await _new_state(seed_value); var ids := state.get_colonist_ids(); var cell := _find_valid_cell(state, State.LOCATION_ID)
	_expect(cell != Vector2i(-1, -1), "setup: valid cache cell")
	state.get("_registry").create_or_merge_pile(State.LOCATION_ID, "wood", 200, Vector2i(state.get_location_snapshot(State.LOCATION_ID).camp_storage_cell), true)
	var placed := state.request_place_building(ids[0], State.LOCATION_ID, "supply_cache", cell); _expect_ok(placed, "setup: cache placed")
	return {"state": state, "worker_id": ids[0], "competitor_id": ids[1], "building_id": String(placed.get("building_instance_id", ""))}

func _new_state(seed_value: int) -> WindowedColonyState:
	var state: WindowedColonyState = State.new(); root.add_child(state); await process_frame; state.set_process(false)
	_expect_ok(state.request_new_game(seed_value), "setup: new game")
	_expect_ok(state.request_settle_starting_location(), "setup: settle")
	return state

func _find_valid_cell(state: WindowedColonyState, location_id: String) -> Vector2i:
	for terrain: Dictionary in state.get_location_snapshot(location_id).terrain:
		var cell := Vector2i(terrain.cell)
		if bool(state.validate_building_placement(location_id, "supply_cache", cell).ok): return cell
	return Vector2i(-1, -1)

func _pile_total(state: WindowedColonyState, location_id: String, resource_type: String) -> int:
	var total := 0
	for pile: Dictionary in state.get_pile_snapshots(location_id):
		if bool(pile.enabled) and String(pile.resource_type) == resource_type: total += int(pile.amount)
	return total

func _expect_ok(result: Dictionary, label: String) -> void: _expect(bool(result.get("ok", false)), "%s: %s" % [label, result.get("reason", "missing result")])
func _expect_reason(result: Dictionary, reason: String, label: String) -> void: _expect(not bool(result.get("ok", false)) and String(result.get("reason", "")) == reason, "%s: expected %s, got %s" % [label, reason, result])
func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition: _failures.append(label)
