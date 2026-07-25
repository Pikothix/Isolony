extends SceneTree

const StateScript = preload("res://scripts/simulation/windowed_colony_state.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var state: WindowedColonyState = StateScript.new(); root.add_child(state); await process_frame; state.set_process(false)
	_check(bool(state.request_new_game(50505).ok), "new game")
	_check(bool(state.request_settle_starting_location().ok), "settle")
	var colonist_id := state.get_colonist_ids()[0]
	_check(not bool(state.request_claim_location(colonist_id, StateScript.LOCATION_ID).ok), "home claim rejected")
	_check(bool(state.request_start_scouting(colonist_id, "woodland").ok), "scout")
	var scout := state.get_scouting_snapshot(colonist_id); state.advance_simulation(float(scout.duration) + 0.1)
	var remote_id := state.get_location_ids()[1]
	_check(not bool(state.request_claim_location(colonist_id, remote_id).ok), "unretained claim rejected")
	_check(bool(state.request_retain_location(remote_id).ok), "retain")
	_check(not bool(state.request_claim_location(colonist_id, remote_id).ok), "absent claim rejected")
	_check(bool(state.request_send_colonist_to_location(colonist_id, remote_id).ok), "travel")
	var travel := state.get_travel_snapshot(colonist_id); state.advance_simulation(float(travel.travel_duration) + 0.1)
	_check(bool(state.request_claim_location(colonist_id, remote_id).ok), "claim")
	_check(not bool(state.request_discard_location(remote_id).ok), "claimed discard rejected")
	var cell := _find_valid_cell(state, remote_id)
	_check(cell != Vector2i(-1, -1), "valid placement cell")
	_check(bool(state.request_place_building(colonist_id, remote_id, "supply_cache", cell).ok), "place cache")
	_check(not bool(state.request_place_building(colonist_id, remote_id, "supply_cache", cell).ok), "overlap rejected")
	state._registry.create_or_merge_pile(remote_id, "wood", 20, Vector2i(state.get_location_snapshot(remote_id).entry_cell), false)
	_check(bool(state.request_set_colonist_role(colonist_id, StateScript.ROLE_CONSTRUCTION).ok), "construction role")
	for tick in range(160): state.advance_simulation(1.0)
	var building := state.get_building_snapshots(remote_id)[0]
	_check(String(building.state) == "COMPLETED" and bool(building.resources_consumed), "construction completes once")
	var reservation := state._construction.reserve_storage(remote_id, "stone", 8, "validation_haul")
	_check(bool(reservation.ok) and bool(state._construction.store_reserved("validation_haul").ok), "formal deposit")
	building = state.get_building_snapshot(String(building.building_instance_id)); _check(int(building.storage_contents.stone) == 8, "building owns contents")
	var saved := state.export_save_data(); _check(int(saved.version) == 4, "schema version 4")
	var restored: WindowedColonyState = StateScript.new(); root.add_child(restored); await process_frame; restored.set_process(false)
	_check(bool(restored.import_save_data(saved).ok), "round trip")
	var restored_location := restored.get_location_snapshot(remote_id); var restored_building: Dictionary = restored_location.building_records[0]
	_check(bool(restored_location.claimed) and String(restored_building.state) == "COMPLETED" and int(restored_building.storage_contents.stone) == 8, "claim building storage restored")
	var invalid := saved.duplicate(true); invalid.location_construction.buildings.append(invalid.location_construction.buildings[0].duplicate(true)); invalid.location_construction.buildings[1].building_instance_id = "duplicate_overlap"
	var before := restored.export_save_data(); _check(not bool(restored.import_save_data(invalid).ok) and restored.export_save_data() == before, "overlap rejected transactionally")
	if failures.is_empty(): print("P05_CLAIMING_BUILDING_VALIDATION: PASS (%d checks)" % checks); quit(0)
	else: for failure: String in failures: push_error(failure); quit(1)

func _find_valid_cell(state: WindowedColonyState, location_id: String) -> Vector2i:
	var location := state.get_location_snapshot(location_id)
	for terrain: Dictionary in location.terrain:
		var cell := Vector2i(terrain.cell)
		if bool(state.validate_building_placement(location_id, "supply_cache", cell).ok): return cell
	return Vector2i(-1, -1)
func _check(value: bool, label: String) -> void: checks += 1; if not value: failures.append(label)
