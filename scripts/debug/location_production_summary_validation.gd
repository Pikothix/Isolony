extends SceneTree

const StateScript = preload("res://scripts/simulation/windowed_colony_state.gd")
const MainScene = preload("res://scenes/Main.tscn")

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _authoritative_accounting()
	await _presentation_independence()
	if _failures.is_empty():
		print("LOCATION_PRODUCTION_SUMMARY_VALIDATION: PASS (%d checks)" % _checks)
		quit(0)
	else:
		for failure: String in _failures:
			push_error("LOCATION_PRODUCTION_SUMMARY_VALIDATION: " + failure)
		quit(1)


func _authoritative_accounting() -> void:
	var state := await _settled_state(81001)
	var ids := state.get_colonist_ids()
	var wood_yield := _complete_targeted_gather(state, ids[0], StateScript.LOCATION_ID, StateScript.ROLE_WOOD, ["tree", "fruit_tree"])
	var after_wood := state.get_location_production_summary(StateScript.LOCATION_ID)
	_check(wood_yield > 0, "controlled authoritative Wood gathering completes")
	_check(int(after_wood.production.wood.recent_amount) == wood_yield and int(after_wood.production.stone.recent_amount) == 0, "gathering records its exact output once")
	_check(float(after_wood.production.wood.per_minute) == float(wood_yield), "60-second rate projects recent authoritative amount per minute")
	_check(int(after_wood.production.wood.loose) == wood_yield, "gathered output exists as one physical loose pile")
	_check(String(after_wood.status) == "producing", "recent completed production yields Producing status")

	state.request_set_colonist_role(ids[0], StateScript.ROLE_NONE)
	state.request_set_colonist_role(ids[1], StateScript.ROLE_HAUL)
	var gross_before_haul := int(after_wood.production.wood.recent_amount)
	for _step in range(6000):
		state.advance_simulation(0.1)
		var summary := state.get_location_production_summary(StateScript.LOCATION_ID)
		if int(summary.production.wood.stored) > 0:
			break
	var after_haul := state.get_location_production_summary(StateScript.LOCATION_ID)
	_check(int(after_haul.production.wood.recent_amount) == gross_before_haul, "hauling and deposit do not double-count production")
	_check(int(after_haul.production.wood.stored) > 0 and int(after_haul.production.wood.loose) < wood_yield, "loose and stored projections follow authoritative movement")

	state.request_set_colonist_role(ids[1], StateScript.ROLE_NONE)
	var second_wood_yield := _complete_targeted_gather(state, ids[0], StateScript.LOCATION_ID, StateScript.ROLE_WOOD, ["tree", "fruit_tree"])
	var food_yield := _complete_targeted_gather(state, ids[2], StateScript.LOCATION_ID, StateScript.ROLE_FORAGE, ["berry_bush", "fruit_bush", "fruit_tree"])
	var multiple := state.get_location_production_summary(StateScript.LOCATION_ID)
	_check(int(multiple.production.wood.recent_amount) == wood_yield + second_wood_yield, "multiple same-resource events sum")
	_check(int(multiple.production.food.recent_amount) == food_yield and int(multiple.production.stone.recent_amount) == 0, "resource categories remain independent")

	var physical_before_expiry := _physical_total(state, StateScript.LOCATION_ID)
	state.set("_simulation_time", state.get_simulation_time() + 60.1)
	var expired := state.get_location_production_summary(StateScript.LOCATION_ID)
	_check(int(expired.production.wood.recent_amount) == 0 and int(expired.production.food.recent_amount) == 0, "events expire beyond the rolling window")
	_check(_physical_total(state, StateScript.LOCATION_ID) == physical_before_expiry, "history expiry does not mutate physical resources")
	_check(String(expired.status) == "idle", "present workers without recent production yield Idle status")

	var registry: RefCounted = state.get("_registry")
	var remote: Dictionary = registry.call("create_discovered_location", StateScript.LOCATION_ID, "rocky", 1, 81002, Vector2i(4, 3))
	var remote_id := String(remote.location_id)
	registry.call("retain", remote_id)
	_check(String(state.get_location_production_summary(remote_id).status) == "no_workers", "empty location yields No workers status")
	var remote_worker_id := ids[0]
	registry.call("remove_presence", StateScript.LOCATION_ID, remote_worker_id)
	registry.call("add_presence", remote_id, remote_worker_id)
	var remote_worker: Dictionary = (state.get("_colonists") as Dictionary)[remote_worker_id]
	remote_worker.location_id = remote_id
	remote_worker.cell = Vector2i(remote.spawn_cells[0])
	remote_worker.visual_cell = Vector2(remote_worker.cell)
	var tracker: RefCounted = state.get("_production_tracker")
	tracker.call("record_production", remote_id, "stone", 7, state.get_simulation_time())
	registry.call("create_or_merge_pile", remote_id, "stone", 7, Vector2i(remote.entry_cell), false)
	var home_summary := state.get_location_production_summary(StateScript.LOCATION_ID)
	var remote_summary := state.get_location_production_summary(remote_id)
	_check(int(remote_summary.production.stone.recent_amount) == 7, "remote production event records against its own location")
	_check(int(home_summary.production.stone.recent_amount) == 0, "location summaries do not share production events")

	state.request_set_colonist_role(remote_worker_id, StateScript.ROLE_WOOD)
	remote_summary = state.get_location_production_summary(remote_id)
	_check(int(remote_summary.roles[StateScript.ROLE_WOOD]) == 1, "role counts use authoritative presence and colonist records")
	var travel := state.request_send_colonist_to_location(remote_worker_id, StateScript.LOCATION_ID)
	_check(bool(travel.ok) and int(state.get_location_production_summary(remote_id).roles.get(StateScript.ROLE_WOOD, 0)) == 0, "departure immediately removes the traveller from origin role counts")
	var travel_record := state.get_travel_snapshot(remote_worker_id)
	state.advance_simulation(float(travel_record.travel_duration) + 0.1)
	_check(int(state.get_location_production_summary(StateScript.LOCATION_ID).roles.get(StateScript.ROLE_WOOD, 0)) == 1, "arrival adds the traveller to destination role counts")

	tracker.call("record_production", remote_id, "food", 3, state.get_simulation_time())
	var saved := state.export_save_data()
	_check(not saved.has("production_history") and not saved.has("production_analytics"), "recent analytics are absent from save data")
	var restored := await _state()
	_check(bool(restored.import_save_data(saved).ok), "save imports with unchanged schema")
	var restored_remote := restored.get_location_production_summary(remote_id)
	_check(int(restored_remote.production.food.recent_amount) == 0, "load starts with empty recent history")
	_check(int(restored_remote.production.stone.loose) == int(state.get_location_production_summary(remote_id).production.stone.loose), "load reconstructs current resource totals")
	_check(restored_remote.roles == state.get_location_production_summary(remote_id).roles, "load reconstructs current role counts")

	tracker.call("record_production", StateScript.LOCATION_ID, "wood", 9, state.get_simulation_time())
	state.request_new_game(81003)
	_check(int(state.get_location_production_summary(StateScript.LOCATION_ID).production.wood.recent_amount) == 0, "new game clears old analytics")

	var defensive := restored.get_location_production_summary(remote_id)
	defensive.production.stone.recent_amount = 999
	defensive.roles["forged"] = 99
	var reread := restored.get_location_production_summary(remote_id)
	_check(int(reread.production.stone.recent_amount) != 999 and not reread.roles.has("forged"), "summary reads are defensive")


func _presentation_independence() -> void:
	root.size = Vector2i(1280, 720)
	var main: Control = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main.call("_new_game")
	await process_frame
	var state: WindowedColonyState = main.get("colony_state")
	state.set_process(false)
	state.request_settle_starting_location()
	var widget: Dictionary = (main.get("_location_widgets") as Dictionary)[StateScript.LOCATION_ID]
	var label: Label = (main.get("_production_summary_labels") as Dictionary)[StateScript.LOCATION_ID]
	var before_text := label.text
	main.call("_minimise_window", widget.window)
	var produced := _complete_targeted_gather(state, state.get_colonist_ids()[0], StateScript.LOCATION_ID, StateScript.ROLE_WOOD, ["tree", "fruit_tree"])
	_check(produced > 0 and int(state.get_location_production_summary(StateScript.LOCATION_ID).production.wood.recent_amount) == produced, "production collection continues while presentation is suspended")
	_check(label.text == before_text, "suspended production presentation stops updating")
	main.call("_focus_window", widget.window)
	_check(label.text != before_text and label.text.contains("Wood") and label.text.contains("%.1f/min" % float(produced)), "restore immediately refreshes the production projection")
	var authority_before_close := state.get_location_production_summary(StateScript.LOCATION_ID)
	main.call("_close_window", widget.window)
	await process_frame
	main.call("_open_location", StateScript.LOCATION_ID)
	await process_frame
	var reopened_label: Label = (main.get("_production_summary_labels") as Dictionary)[StateScript.LOCATION_ID]
	_check(reopened_label.text.contains("%.1f/min" % float(produced)) and state.get_location_production_summary(StateScript.LOCATION_ID) == authority_before_close, "reopen reconstructs the same in-memory analytics without owning them")
	main.queue_free()
	await process_frame


func _complete_targeted_gather(state: WindowedColonyState, colonist_id: String, location_id: String, role: String, resource_kinds: Array[String]) -> int:
	var target: Dictionary = {}
	for resource: Dictionary in state.get_location_snapshot(location_id).resources:
		if String(resource.resource_kind) in resource_kinds and not bool(resource.depleted) and not (role == StateScript.ROLE_FORAGE and bool(resource.fruit_harvested)):
			target = resource
			break
	if target.is_empty(): return 0
	var colonist: Dictionary = (state.get("_colonists") as Dictionary)[colonist_id]
	state.request_set_colonist_role(colonist_id, role)
	var interaction_cell := Vector2i(-1, -1)
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var candidate := Vector2i(target.cell) + offset
		if state.is_cell_traversable(location_id, candidate, colonist_id):
			interaction_cell = candidate
			break
	if interaction_cell == Vector2i(-1, -1): return 0
	colonist.needs.hunger = 100.0
	colonist.needs.rest = 100.0
	colonist.location_id = location_id
	colonist.cell = interaction_cell
	colonist.visual_cell = Vector2(colonist.cell)
	colonist.target_id = String(target.resource_id)
	colonist.activity_work_cell = interaction_cell
	colonist.work_progress = 0.0
	var before := int(state.get_location_production_summary(location_id).production[String("food" if role == StateScript.ROLE_FORAGE else target.resource_type)].recent_amount)
	for _step in range(3000):
		state.advance_simulation(0.1)
		var output_type := "food" if role == StateScript.ROLE_FORAGE else String(target.resource_type)
		var after := int(state.get_location_production_summary(location_id).production[output_type].recent_amount)
		if after > before:
			return after - before
	return 0


func _physical_total(state: WindowedColonyState, location_id: String) -> int:
	var summary := state.get_location_production_summary(location_id)
	var total := 0
	for resource_type: String in ["wood", "stone", "food"]:
		total += int(summary.production[resource_type].stored) + int(summary.production[resource_type].loose) + int(summary.production[resource_type].carried)
	return total


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


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
