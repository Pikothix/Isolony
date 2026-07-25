extends SceneTree

const StateScript = preload("res://scripts/simulation/windowed_colony_state.gd")
var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var state := await _state()
	_check(state.get_game_phase() == StateScript.MAIN_MENU, "starts at main menu")
	var new_result: Dictionary = state.request_new_game(424242)
	_check(bool(new_result.ok), "fixed-seed new game succeeds")
	_check(state.get_simulation_clock() == {"day": 1, "hour": 0, "minute": 0}, "new game clock starts at Day 1 00:00")
	state.set("_simulation_time", 5.0); _check(state.get_simulation_clock() == {"day": 1, "hour": 0, "minute": 5}, "clock zero-pads minute-ready components")
	state.set("_simulation_time", 489.0); _check(state.get_simulation_clock() == {"day": 1, "hour": 8, "minute": 9}, "clock resolves hour and minute components")
	state.set("_simulation_time", 1439.0); _check(state.get_simulation_clock() == {"day": 1, "hour": 23, "minute": 59}, "clock resolves the end-of-day boundary")
	state.set("_simulation_time", 1440.0); _check(state.get_simulation_clock() == {"day": 2, "hour": 0, "minute": 0}, "clock increments day at 24 hours")
	state.set("_simulation_time", 0.0)
	_check(state.get_location_ids().size() == 1, "new game creates exactly one location")
	_check(state.get_colonist_ids().size() == 3, "new game creates exactly three colonists")
	var location := state.get_location_snapshot(StateScript.LOCATION_ID)
	_check((location.spawn_cells as Array).size() == 3 and (location.colonist_presence_ids as Array).size() == 3, "three colonists are present at starter site")
	var kinds: Dictionary = {}; var wood_potential := 0; var stone_potential := 0
	for resource: Dictionary in location.resources:
		kinds[String(resource.resource_kind)] = true
		if String(resource.resource_kind) in ["tree", "fruit_tree"]: wood_potential += int(resource.yield)
		if String(resource.resource_kind) == "rock": stone_potential += int(resource.yield)
	var balance := float(wood_potential) / float(wood_potential + stone_potential)
	_check(balance >= 0.4 and balance <= 0.6, "wood/stone harvest potential is balanced")
	_check(kinds.has("fruit_tree") and kinds.has("berry_bush") and kinds.has("fruit_bush"), "all forage resource kinds exist")
	for id: String in state.get_colonist_ids():
		var c := state.get_colonist_snapshot(id)
		_check(c.location_id == StateScript.LOCATION_ID and c.cell in location.spawn_cells, "colonist has valid starter spawn")
	_check(not bool(state.request_set_colonist_role(state.get_colonist_ids()[0], StateScript.ROLE_WOOD).ok), "role rejected before settlement")
	var settle := state.request_settle_starting_location(); var after_settle := state.get_location_snapshot(StateScript.LOCATION_ID)
	_check(bool(settle.ok) and bool(after_settle.claimed) and bool(after_settle.is_primary_settlement), "settling claims primary location")
	var settled_snapshot := state.export_save_data()
	_check(not bool(state.request_settle_starting_location().ok) and state.export_save_data() == settled_snapshot, "repeated settle is rejected without mutation")

	var ids := state.get_colonist_ids(); state.request_set_colonist_role(ids[0], StateScript.ROLE_WOOD); state.request_set_colonist_role(ids[1], StateScript.ROLE_MINING); state.request_set_colonist_role(ids[2], StateScript.ROLE_FORAGE)
	for _i in range(5000):
		state.advance_simulation(0.1)
		var totals: Dictionary = state.get_resource_summary().loose
		if int(totals.wood) > 0 and int(totals.stone) > 0 and int(totals.food) > 0: break
	var loose: Dictionary = state.get_resource_summary().loose
	_check(int(loose.wood) > 0 and int(loose.stone) > 0 and int(loose.food) > 0, "roles create physical wood, stone, and food piles")
	var before_total := _all_resources(state); state.request_set_colonist_role(ids[2], StateScript.ROLE_HAUL)
	for _i in range(3000):
		state.advance_simulation(0.1)
		if _stored_sum(state) > 0: break
	_check(_stored_sum(state) > 0, "hauling deposits into camp storage")
	_check(_all_resources(state) == before_total, "hauling conserves loose, carried, and stored resources")

	var hunger_before := float(state.get_colonist_snapshot(ids[0]).needs.hunger); state.advance_simulation(10.0)
	_check(float(state.get_colonist_snapshot(ids[0]).needs.hunger) < hunger_before, "hunger declines while settled")
	state.request_set_time_scale(0.0); var paused := state.get_colonist_snapshot(ids[0]); var paused_clock := state.get_simulation_clock(); state.advance_simulation(100.0)
	_check(state.get_colonist_snapshot(ids[0]) == paused, "pause prevents simulation and needs progression")
	_check(state.get_simulation_clock() == paused_clock, "pause stops authoritative clock progression")
	state.request_set_time_scale(1.0)

	var save_data := state.export_save_data(); var restored := await _state(); var restored_clock_signal: Dictionary = {}
	restored.simulation_time_changed.connect(func(day: int, hour: int, minute: int) -> void: restored_clock_signal["day"] = day; restored_clock_signal["hour"] = hour; restored_clock_signal["minute"] = minute)
	var loaded := restored.import_save_data(save_data)
	_check(bool(loaded.ok), "windowed colony save imports")
	_check(restored.get_simulation_clock() == state.get_simulation_clock() and restored_clock_signal == state.get_simulation_clock(), "load restores and immediately notifies the authoritative clock")
	_check(restored.get_game_seed() == state.get_game_seed() and _persistent_piles(restored) == _persistent_piles(state), "round trip preserves seed and persistent pile state")
	_check(restored.get_colonist_ids() == state.get_colonist_ids(), "round trip preserves colonist identities")
	var normalized_restored := restored.export_save_data(); _check(bool(restored.import_save_data(normalized_restored).ok) and restored.export_save_data() == normalized_restored, "repeated import does not duplicate or offset authoritative state")
	_check(bool(state.request_save_game().ok), "single-slot save writes windowed colony document")
	var file_restored := await _state(); var file_load: Dictionary = file_restored.request_load_game(); if not bool(file_load.ok): print("FILE_LOAD_FAILURE: ", file_load); _check(bool(file_load.ok) and file_restored.get_colonist_ids() == state.get_colonist_ids(), "single-slot file load restores colony once")
	for id: String in restored.get_colonist_ids(): _check(restored.get_colonist_snapshot(id).activity == "Idle" and restored.get_colonist_snapshot(id).role == state.get_colonist_snapshot(id).role, "load resets transient activity and preserves role")
	var invalid := save_data.duplicate(true); invalid.version = 99; var before_invalid := restored.export_save_data()
	_check(not bool(restored.import_save_data(invalid).ok) and restored.export_save_data() == before_invalid, "invalid version rejected before mutation")
	var legacy := save_data.duplicate(true); legacy.version = 3; legacy.erase("structural_construction"); var legacy_restored := await _state()
	_check(bool(legacy_restored.import_save_data(legacy).ok) and legacy_restored.get_location_construction_sites(StateScript.LOCATION_ID).is_empty(), "version 3 save without structural section loads compatible empty authored state")
	var deterministic := await _state(); deterministic.request_new_game(424242)
	_check(deterministic.get_location_snapshot(StateScript.LOCATION_ID).terrain == location.terrain and deterministic.get_location_snapshot(StateScript.LOCATION_ID).resources == location.resources, "fixed seed reproduces terrain and resources")

	if _failures.is_empty(): print("WINDOWED_COLONY_VALIDATION: PASS (%d checks)" % _checks); quit(0)
	else:
		for failure: String in _failures: push_error("WINDOWED_COLONY_VALIDATION: " + failure)
		quit(1)

func _state() -> WindowedColonyState:
	var state := StateScript.new(); root.add_child(state); await process_frame; state.set_process(false); return state
func location_after(state: WindowedColonyState) -> Dictionary: return state.get_location_snapshot(StateScript.LOCATION_ID)
func _persistent_piles(state: WindowedColonyState) -> Array:
	var piles: Array = state.export_save_data().location_registry.locations[0].piles
	return piles
func _stored_sum(state: WindowedColonyState) -> int: var t: Dictionary = state.get_resource_summary().stored; return int(t.wood) + int(t.stone) + int(t.food)
func _all_resources(state: WindowedColonyState) -> int:
	var s := state.get_resource_summary(); return int(s.stored.wood)+int(s.stored.stone)+int(s.stored.food)+int(s.loose.wood)+int(s.loose.stone)+int(s.loose.food)+int(s.carried.wood)+int(s.carried.stone)+int(s.carried.food)
func _check(condition: bool, description: String) -> void: _checks += 1; if not condition: _failures.append(description)
