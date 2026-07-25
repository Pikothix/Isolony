extends SceneTree

const StateScript = preload("res://scripts/simulation/windowed_colony_state.gd")
var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await _stored_food_available()
	await _no_food_anywhere()
	await _gatherable_food_recovery()
	await _loose_food_haul_recovery()
	await _unrelated_work_restricted()
	await _rest_recovery()
	await _save_load_round_trip()
	if _failures.is_empty():
		print("NEED_LOOP_SAFETY_VALIDATION: PASS (%d checks)" % _checks)
		quit(0)
	else:
		for failure: String in _failures:
			push_error("NEED_LOOP_SAFETY_VALIDATION: " + failure)
		quit(1)

func _stored_food_available() -> void:
	var state := await _settled_state(10101)
	var id := state.get_colonist_ids()[0]
	var colonist: Dictionary = (state.get("_colonists") as Dictionary)[id]
	colonist.needs.hunger = 25.0
	var registry: RefCounted = state.get("_registry")
	var camp := Vector2i(state.get_location_snapshot(StateScript.LOCATION_ID).camp_storage_cell)
	registry.call("create_or_merge_pile", StateScript.LOCATION_ID, "food", 2, camp, true)
	state.advance_simulation(0.1)
	_check(String(state.get_colonist_snapshot(id).activity) == "Eating", "stored Food starts eating")
	_check(int(state.get_resource_summary().stored.food) == 1, "stored Food decreases exactly once when eating starts")
	state.advance_simulation(1.0)
	var after := state.get_colonist_snapshot(id)
	_check(is_equal_approx(float(after.needs.hunger), 54.901), "eating restores the expected Hunger amount")
	_check(int(state.get_resource_summary().stored.food) == 1, "eating progress does not consume Food again")
	_check(String(after.target_id).is_empty() and int(after.carried.amount) == 0, "eating does not mutate unrelated work state")

func _no_food_anywhere() -> void:
	var state := await _settled_state(20202)
	var id := state.get_colonist_ids()[0]
	var colonist: Dictionary = (state.get("_colonists") as Dictionary)[id]
	colonist.needs.hunger = 25.0
	state.advance_simulation(0.1)
	var first := state.get_colonist_snapshot(id)
	for _step in range(20):
		state.advance_simulation(0.1)
	var after := state.get_colonist_snapshot(id)
	_check(bool(first.hunger_recovery) and bool(after.hunger_recovery), "failed eating enters stable transient recovery")
	_check(String(after.activity) == "Hungry - no stored food", "no-Food recovery remains decision-capable without ordinary work")
	_check(_physical_food(state) == 0, "no-Food recovery creates or mutates no Food")
	var registry: RefCounted = state.get("_registry")
	var camp := Vector2i(state.get_location_snapshot(StateScript.LOCATION_ID).camp_storage_cell)
	registry.call("create_or_merge_pile", StateScript.LOCATION_ID, "food", 1, camp, true)
	state.advance_simulation(0.1)
	_check(String(state.get_colonist_snapshot(id).activity) == "Eating", "recovery notices newly consumable Food on a later decision")

func _gatherable_food_recovery() -> void:
	var state := await _settled_state(30303)
	var id := state.get_colonist_ids()[0]
	state.request_set_colonist_role(id, StateScript.ROLE_FORAGE)
	var colonist: Dictionary = (state.get("_colonists") as Dictionary)[id]
	colonist.needs.hunger = 25.0
	var produced := false
	for _step in range(6000):
		state.advance_simulation(0.1)
		if int(state.get_resource_summary().loose.food) > 0:
			produced = true
			break
	_check(produced, "hungry Foraging selects and completes Food recovery work")
	_check(int(state.get_resource_summary().stored.food) == 0, "Foraging creates loose Food without bypassing logistics")
	var harvested := false
	for resource: Dictionary in state.get_location_snapshot(StateScript.LOCATION_ID).resources:
		if String(resource.resource_kind) in ["berry_bush", "fruit_bush", "fruit_tree"] and bool(resource.fruit_harvested):
			harvested = true
			break
	_check(harvested, "Food recovery uses normal authoritative resource harvest completion")

func _loose_food_haul_recovery() -> void:
	var state := await _settled_state(40404)
	var id := state.get_colonist_ids()[0]
	state.request_set_colonist_role(id, StateScript.ROLE_HAUL)
	var colonist: Dictionary = (state.get("_colonists") as Dictionary)[id]
	colonist.needs.hunger = 25.0
	var registry: RefCounted = state.get("_registry")
	var location := state.get_location_snapshot(StateScript.LOCATION_ID)
	var spawn_cells: Array = location.spawn_cells
	var loose_cell := Vector2i(spawn_cells[0])
	colonist.cell = Vector2i(spawn_cells[0])
	colonist.visual_cell = Vector2(colonist.cell)
	registry.call("create_or_merge_pile", StateScript.LOCATION_ID, "wood", 4, Vector2i(spawn_cells[1]), false)
	registry.call("create_or_merge_pile", StateScript.LOCATION_ID, "food", 3, loose_cell, false)
	var recovered := false
	for _step in range(6000):
		state.advance_simulation(0.1)
		var snapshot := state.get_colonist_snapshot(id)
		if float(snapshot.needs.hunger) > 25.0:
			recovered = true
			break
	_check(recovered, "hungry Hauling deposits Food and later eats it normally")
	_check(int(state.get_resource_summary().stored.food) == 2 and int(state.get_resource_summary().loose.food) == 0, "Food uses normal deposit then one-unit consumption")
	_check(int(state.get_resource_summary().loose.wood) == 4, "Hunger recovery does not haul unrelated loose resources")

func _unrelated_work_restricted() -> void:
	var state := await _settled_state(50505)
	var id := state.get_colonist_ids()[0]
	state.request_set_colonist_role(id, StateScript.ROLE_WOOD)
	state.advance_simulation(0.1)
	var colonist: Dictionary = (state.get("_colonists") as Dictionary)[id]
	var target_id := String(colonist.target_id)
	_check(not target_id.is_empty(), "ordinary Woodcutting target exists before Hunger interruption")
	colonist.needs.hunger = 25.0
	state.advance_simulation(0.1)
	var interrupted := state.get_colonist_snapshot(id)
	for _step in range(100):
		state.advance_simulation(0.1)
	var resource: Dictionary = (state.get("_registry") as RefCounted).call("find_resource", StateScript.LOCATION_ID, target_id)
	_check(String(interrupted.target_id).is_empty() and String(interrupted.activity) == "Hungry - no stored food", "low Hunger cancels and blocks unrelated role work")
	_check(not bool(resource.depleted), "blocked unrelated work does not complete while hungry")

func _rest_recovery() -> void:
	var state := await _settled_state(60606)
	var id := state.get_colonist_ids()[0]
	var colonist: Dictionary = (state.get("_colonists") as Dictionary)[id]
	colonist.needs.hunger = 100.0
	colonist.needs.rest = 20.0
	state.advance_simulation(0.1)
	_check(String(state.get_colonist_snapshot(id).activity) == "Sleeping on ground", "low Rest enters ground sleep")
	for _step in range(1000):
		state.advance_simulation(0.1)
		if float(state.get_colonist_snapshot(id).needs.rest) >= 80.0:
			break
	var after := state.get_colonist_snapshot(id)
	_check(float(after.needs.rest) >= 80.0 and String(after.activity) == "Idle", "ground sleep restores Rest and returns to ordinary decisions")

func _save_load_round_trip() -> void:
	var state := await _settled_state(70707)
	var id := state.get_colonist_ids()[0]
	var colonist: Dictionary = (state.get("_colonists") as Dictionary)[id]
	colonist.needs.hunger = 25.0
	colonist.needs.rest = 47.0
	state.advance_simulation(0.1)
	var saved := state.export_save_data()
	_check(not (saved.colonists[0] as Dictionary).has("hunger_recovery"), "transient Hunger recovery is excluded from save data")
	var restored := await _state()
	var loaded: Dictionary = restored.import_save_data(saved)
	var restored_colonist := restored.get_colonist_snapshot(id)
	_check(bool(loaded.ok) and is_equal_approx(float(restored_colonist.needs.hunger), float(saved.colonists[0].needs.hunger)) and is_equal_approx(float(restored_colonist.needs.rest), 47.0 - 0.0055), "Hunger and Rest round-trip through the existing schema")
	_check(not bool(restored_colonist.hunger_recovery) and String(restored_colonist.activity) == "Idle", "load reconstructs transient recovery and activity")

func _settled_state(seed_value: int) -> WindowedColonyState:
	var state := await _state()
	state.request_new_game(seed_value)
	state.request_settle_starting_location()
	return state

func _state() -> WindowedColonyState:
	var state := StateScript.new()
	root.add_child(state)
	await process_frame
	state.set_process(false)
	return state

func _physical_food(state: WindowedColonyState) -> int:
	var summary := state.get_resource_summary()
	return int(summary.stored.food) + int(summary.loose.food) + int(summary.carried.food)

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
