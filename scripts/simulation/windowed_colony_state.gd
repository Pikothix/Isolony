extends Node
class_name WindowedColonyState

signal state_changed
signal game_replaced
signal location_created(location_id: String)
signal location_changed(location_id: String, change_type: String, subject_id: String)
signal colonist_motion_changed(colonist_id: String, location_id: String)
signal haul_state_changed(colonist_id: String)
signal scouting_changed(colonist_id: String)
signal travel_changed(colonist_id: String)
signal discovery_completed(location_id: String)
signal building_changed(location_id: String, building_instance_id: String)
signal location_construction_changed(location_id: String, change_type: String, site_id: String)
signal time_scale_changed(scale: float)
signal simulation_time_changed(day: int, hour: int, minute: int)

const Registry = preload("res://scripts/simulation/location_registry.gd")
const SaveService = preload("res://scripts/simulation/save_game_service.gd")
const Scouting = preload("res://scripts/simulation/scouting_coordinator.gd")
const Travel = preload("res://scripts/simulation/location_travel_coordinator.gd")
const Construction = preload("res://scripts/simulation/location_construction_coordinator.gd")
const LocationConstruction = preload("res://scripts/simulation/location_construction_state.gd")
const Traversal = preload("res://scripts/simulation/location_traversal_resolver.gd")
const ProductionTracker = preload("res://scripts/simulation/location_production_tracker.gd")
const BuildingDefinition = preload("res://scripts/buildings/building_definition.gd")
const MAIN_MENU := "MAIN_MENU"
const LOCATION_EVALUATION := "LOCATION_EVALUATION"
const SETTLED := "SETTLED"
const ROLE_NONE := "unassigned"
const ROLE_WOOD := "woodcutting"
const ROLE_MINING := "mining"
const ROLE_FORAGE := "foraging"
const ROLE_HAUL := "hauling"
const ROLE_SCOUT := "scout"
const ROLE_CONSTRUCTION := "construction"
const VALID_ROLES := [ROLE_NONE, ROLE_WOOD, ROLE_MINING, ROLE_FORAGE, ROLE_HAUL, ROLE_SCOUT, ROLE_CONSTRUCTION]
const VALID_TIME_SCALES := [0.0, 1.0, 2.0, 4.0]
const DISPLAY_MINUTES_PER_SIMULATION_SECOND := 1.0
const DISPLAY_MINUTES_PER_DAY := 24 * 60
const LOCATION_ID := Registry.STARTING_LOCATION_ID
const SAVE_PATH := "user://windowed_colony_v3.json"
const MOVE_SECONDS_PER_CELL := 0.7
const HAUL_CAPACITY := 8
const CONSTRUCTION_TRAVEL_TIMEOUT := 60.0
const REPATH_COOLDOWN := 0.25

var _registry := Registry.new()
var _colonists: Dictionary = {}
var _game_phase := MAIN_MENU
var _game_seed := 0
var _simulation_time := 0.0
var _time_scale := 1.0
var _last_emitted_display_minute := -1
var _next_reservation := 1
var _scouting := Scouting.new()
var _travel := Travel.new()
var _construction := Construction.new()
var _location_construction := LocationConstruction.new()
var _traversal := Traversal.new()
var _scouting_sequence := 0
var _production_tracker := ProductionTracker.new()

## Top-level authority for phase, seed, time, roster, validated requests and save coordination.
func _process(frame_delta: float) -> void: advance_simulation(frame_delta)

func request_new_game(optional_seed := 0) -> Dictionary:
	var seed_value := int(optional_seed)
	if seed_value == 0: seed_value = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())
	var generated := _registry.create_starting_location(seed_value)
	if generated.is_empty(): return _result(false, "location_generation_failed")
	_construction = Construction.new(); _construction.configure(_registry); _location_construction = LocationConstruction.new(); _traversal = Traversal.new(); _traversal.configure(_registry, _location_construction, _construction); _location_construction.configure(_registry, _construction, _traversal)
	_game_seed = seed_value; _simulation_time = 0.0; _time_scale = 1.0; _game_phase = LOCATION_EVALUATION; _next_reservation = 1; _scouting_sequence = 0; _scouting = Scouting.new(); _travel = Travel.new(); _production_tracker = ProductionTracker.new(); _colonists.clear()
	var names := ["Ada Alder", "Bram Bennett", "Clara Cobb"]
	for i in range(3):
		var id := "colonist_%08x_%d" % [abs(seed_value) & 0xffffffff, i + 1]
		var plants := 3 + _seed_value(seed_value, i, 17) % 8; var mining := 3 + _seed_value(seed_value, i, 29) % 8
		_colonists[id] = {"colonist_id": id, "display_name": names[_seed_value(seed_value, i, 41) % names.size()], "skills": {"Plants": plants, "Mining": mining, "Construction": 3 + _seed_value(seed_value, i, 37) % 8}, "traits": [["Hard Worker"], ["Night Owl"], ["Kind"]][_seed_value(seed_value, i, 53) % 3], "needs": {"hunger": 100.0, "rest": 100.0}, "location_id": LOCATION_ID, "role": ROLE_NONE, "activity": "Inspecting location", "cell": Vector2i(generated.spawn_cells[i]), "visual_cell": Vector2(generated.spawn_cells[i]), "target_id": "", "work_progress": 0.0, "move_progress": 0.0, "movement_path": [], "movement_path_index": 0, "movement_target": Vector2i.ZERO, "repath_timer": 0.0, "movement_failure_reason": "", "activity_work_cell": Vector2i(-1, -1), "construction_work_cell": Vector2i.ZERO, "construction_travel_elapsed": 0.0, "carried": {"type": "", "amount": 0, "origin_pile_id": "", "origin_cell": Vector2i.ZERO, "destination_building_id": ""}, "reservation_id": "", "hunger_recovery": false}
		generated.colonist_presence_ids.append(id)
	_emit_simulation_time_changed(true); game_replaced.emit(); location_created.emit(LOCATION_ID); state_changed.emit()
	return {"ok": true, "reason": "new_game", "location_id": LOCATION_ID, "seed": seed_value}

func request_settle_starting_location() -> Dictionary:
	if _game_phase != LOCATION_EVALUATION: return _result(false, "invalid_game_phase")
	var result := _registry.settle(LOCATION_ID)
	if not bool(result.ok): return result
	_game_phase = SETTLED
	for colonist: Dictionary in _colonists.values(): colonist.activity = "Idle"
	location_changed.emit(LOCATION_ID, "settled", ""); state_changed.emit(); return _result(true, "settled")

func request_set_colonist_role(colonist_id: String, role: String) -> Dictionary:
	if _game_phase != SETTLED: return _result(false, "not_settled")
	if not _colonists.has(colonist_id): return _result(false, "unknown_colonist")
	if role not in VALID_ROLES: return _result(false, "unsupported_role")
	if role == ROLE_SCOUT: return _result(false, "choose_scout_search_type")
	if _scouting.has(colonist_id) or _travel.has(colonist_id): return _result(false, "colonist_away")
	var colonist: Dictionary = _colonists[colonist_id]
	if String(colonist.role) == role: return _result(false, "already_assigned")
	_cancel_activity(colonist); colonist.role = role; colonist.activity = "Idle" if role == ROLE_NONE else "Selecting local work"
	state_changed.emit(); return _result(true, "role_set")

func request_start_scouting(colonist_id: String, search_type: String) -> Dictionary:
	if _game_phase != SETTLED: return _result(false, "not_settled")
	if not _colonists.has(colonist_id): return _result(false, "unknown_colonist")
	if _travel.has(colonist_id) or _scouting.has(colonist_id): return _result(false, "colonist_away")
	var colonist: Dictionary = _colonists[colonist_id]
	var origin := String(colonist.location_id)
	if not _registry.has(origin) or colonist_id not in _registry.get_record(origin).colonist_presence_ids: return _result(false, "invalid_origin")
	if int(colonist.carried.amount) > 0: return _result(false, "unresolved_carried_payload")
	var result := _scouting.begin(colonist, origin, search_type, _scouting_sequence + 1, _game_seed)
	if not bool(result.ok): return result
	_cancel_activity(colonist); _scouting_sequence += 1; _registry.remove_presence(origin, colonist_id); colonist.location_id = ""; colonist.role = ROLE_SCOUT; colonist.activity = "Scouting"
	location_changed.emit(origin, "assignment", colonist_id); scouting_changed.emit(colonist_id); state_changed.emit(); return result

func request_cancel_scouting(colonist_id: String) -> Dictionary:
	var result := _scouting.cancel(colonist_id)
	if not bool(result.ok): return result
	_restore_scout_to_origin(_colonists[colonist_id], result.record); return result

func request_retain_location(location_id: String) -> Dictionary:
	var result := _registry.retain(location_id); if bool(result.ok): location_changed.emit(location_id, "lifecycle", ""); state_changed.emit()
	return result
func request_claim_location(colonist_id: String, location_id: String) -> Dictionary:
	if _scouting.has(colonist_id): return _result(false, "colonist_scouting")
	if _travel.has(colonist_id): return _result(false, "colonist_travelling")
	var result := _registry.claim(location_id, colonist_id, _simulation_time)
	if bool(result.ok): location_changed.emit(location_id, "claim", ""); state_changed.emit()
	return result
func validate_building_placement(location_id: String, building_id: String, origin_cell: Vector2i) -> Dictionary:
	var result := _construction.validate_placement(location_id, building_id, origin_cell)
	if not bool(result.ok): return result
	for cell: Vector2i in result.occupied_cells:
		if _location_construction.is_construction_cell_occupied(location_id, cell): return _result(false, "construction_cell_occupied")
	return result
func request_place_building(colonist_id: String, location_id: String, building_id: String, origin_cell: Vector2i) -> Dictionary:
	if _scouting.has(colonist_id) or _travel.has(colonist_id): return _result(false, "colonist_away")
	var valid := validate_building_placement(location_id, building_id, origin_cell)
	if not bool(valid.ok): return valid
	var result := _construction.place(colonist_id, location_id, building_id, origin_cell)
	if bool(result.ok): building_changed.emit(location_id, String(result.building_instance_id)); state_changed.emit()
	return result
func validate_construction_designation(location_id: String, piece_kind: String, cells: Array) -> Dictionary:
	return _location_construction.validate_designation(location_id, piece_kind, cells)
func request_designate_construction(location_id: String, piece_kind: String, cells: Array) -> Dictionary:
	var result := _location_construction.request_designate_construction(location_id, piece_kind, cells)
	if bool(result.ok):
		for site_id: String in result.site_ids: location_construction_changed.emit(location_id, "site_added", site_id)
		state_changed.emit()
	return result
func request_cancel_construction(location_id: String, site_id: String) -> Dictionary:
	var result := _location_construction.request_cancel_construction(location_id, site_id)
	if bool(result.ok):
		var cancelled_site_ids: Array = result.get("cancelled_site_ids", [site_id])
		for colonist: Dictionary in _colonists.values():
			if String(colonist.target_id) in cancelled_site_ids: _clear_location_construction_job(colonist, false, "site_cancelled")
		for cancelled_site_id: String in cancelled_site_ids: location_construction_changed.emit(location_id, "site_cancelled", cancelled_site_id)
		state_changed.emit()
	return result
func get_available_construction_site(location_id: String, colonist_id: String) -> Dictionary:
	if not _colonists.has(colonist_id) or String(_colonists[colonist_id].location_id) != location_id: return _result(false, "colonist_not_present")
	return _location_construction.get_available_construction_site(location_id, colonist_id, Vector2i(_colonists[colonist_id].cell))
func reserve_construction_site(location_id: String, site_id: String, colonist_id: String) -> Dictionary:
	if not _colonists.has(colonist_id) or String(_colonists[colonist_id].location_id) != location_id: return _result(false, "colonist_not_present")
	var result := _location_construction.reserve_construction_site(location_id, site_id, colonist_id, Vector2i(_colonists[colonist_id].cell))
	if bool(result.ok): location_construction_changed.emit(location_id, "site_reserved", site_id); state_changed.emit()
	return result
func release_construction_site_reservation(location_id: String, site_id: String, colonist_id: String, reason := "") -> Dictionary:
	var result := _location_construction.release_construction_site_reservation(location_id, site_id, colonist_id, reason)
	if bool(result.ok): location_construction_changed.emit(location_id, "site_updated", site_id); state_changed.emit()
	return result
func request_progress_construction(location_id: String, site_id: String, colonist_id: String, amount: float) -> Dictionary:
	if not _colonists.has(colonist_id) or String(_colonists[colonist_id].location_id) != location_id: return _result(false, "colonist_not_present")
	var result := _location_construction.request_progress_construction(location_id, site_id, colonist_id, amount)
	if bool(result.ok):
		location_construction_changed.emit(location_id, "site_completed" if String(result.reason) == "construction_completed" else "site_updated", site_id)
		for unblocked_site_id: String in result.get("unblocked_site_ids", []): location_construction_changed.emit(location_id, "dependent_unblocked", unblocked_site_id)
		state_changed.emit()
	return result
func request_debug_complete_construction(location_id: String, site_id: String) -> Dictionary:
	var result := _location_construction.request_debug_complete_construction(location_id, site_id)
	if bool(result.ok):
		location_construction_changed.emit(location_id, "site_completed", site_id)
		for unblocked_site_id: String in result.get("unblocked_site_ids", []): location_construction_changed.emit(location_id, "dependent_unblocked", unblocked_site_id)
		state_changed.emit()
	return result
func request_remove_completed_structure(location_id: String, cell: Vector2i) -> Dictionary:
	var result := _location_construction.request_remove_completed_structure(location_id, cell)
	if bool(result.ok): location_construction_changed.emit(location_id, "structure_removed", "%d:%d" % [cell.x, cell.y]); state_changed.emit()
	return result
func request_remove_wall_fixture(location_id: String, cell: Vector2i) -> Dictionary:
	var result := _location_construction.request_remove_wall_fixture(location_id, cell)
	if bool(result.ok): location_construction_changed.emit(location_id, "fixture_removed", "%d:%d" % [cell.x, cell.y]); state_changed.emit()
	return result
func request_cancel_building(building_instance_id: String) -> Dictionary:
	var building := _construction.get_building_snapshot(building_instance_id)
	if building.is_empty(): return _result(false, "building_missing")
	var assigned_worker_id := String(building.assigned_worker_id)
	var result := _construction.cancel_building(building_instance_id)
	if bool(result.ok):
		if _colonists.has(assigned_worker_id) and String(_colonists[assigned_worker_id].target_id) == building_instance_id:
			_clear_supply_cache_job(_colonists[assigned_worker_id], false, "site_cancelled")
		building_changed.emit(String(result.location_id), building_instance_id); state_changed.emit()
	return result
func is_cell_traversable(location_id: String, cell: Vector2i, actor_id := "") -> bool:
	return _valid_traversal_actor(location_id, actor_id) and _traversal.is_cell_traversable(location_id, cell, actor_id)
func get_traversal_cost(location_id: String, cell: Vector2i, actor_id := "") -> float:
	return _traversal.get_traversal_cost(location_id, cell, actor_id) if _valid_traversal_actor(location_id, actor_id) else INF
func find_path(location_id: String, start: Vector2i, goal: Vector2i, actor_id := "") -> Dictionary:
	if not _valid_traversal_actor(location_id, actor_id): return {"ok": false, "reason": "invalid_actor_context", "path": [], "cost": 0.0}
	var result: Dictionary = _traversal.find_path(location_id, start, goal, actor_id)
	result.path = result.get("path", []).duplicate()
	return result
func request_discard_location(location_id: String) -> Dictionary:
	for record: Dictionary in _travel.snapshots(): if String(record.origin_location_id) == location_id or String(record.destination_location_id) == location_id: return _result(false, "location_in_use")
	for record: Dictionary in _scouting.snapshots(): if String(record.origin_location_id) == location_id: return _result(false, "location_in_use")
	var result := _registry.discard(location_id); if bool(result.ok): state_changed.emit()
	return result
func request_rename_location(location_id: String, value: String) -> Dictionary:
	var result := _registry.rename(location_id, value); if bool(result.ok): state_changed.emit()
	return result

func request_send_colonist_to_location(colonist_id: String, destination_location_id: String) -> Dictionary:
	if not _colonists.has(colonist_id): return _result(false, "unknown_colonist")
	if not _registry.has(destination_location_id): return _result(false, "unknown_destination")
	var destination := _registry.get_record(destination_location_id)
	if String(destination.lifecycle_state) not in [Registry.HOME, Registry.RETAINED]: return _result(false, "destination_not_retained")
	if _scouting.has(colonist_id): return _result(false, "colonist_scouting")
	if _travel.has(colonist_id): return _result(false, "colonist_travelling")
	var colonist: Dictionary = _colonists[colonist_id]; var origin_id := String(colonist.location_id)
	if origin_id == destination_location_id: return _result(false, "already_there")
	if not _registry.has(origin_id) or colonist_id not in _registry.get_record(origin_id).colonist_presence_ids: return _result(false, "invalid_origin")
	if int(colonist.carried.amount) > 0: return _result(false, "unresolved_carried_payload")
	var result := _travel.begin(colonist_id, origin_id, destination_location_id, Vector2i(_registry.get_record(origin_id).world_position), Vector2i(destination.world_position), _simulation_time)
	if not bool(result.ok): return result
	_cancel_activity(colonist); _registry.remove_presence(origin_id, colonist_id); colonist.location_id = ""; colonist.activity = "Travelling"
	location_changed.emit(origin_id, "assignment", colonist_id); travel_changed.emit(colonist_id); state_changed.emit(); return result
func request_return_colonist_home(colonist_id: String) -> Dictionary: return request_send_colonist_to_location(colonist_id, LOCATION_ID)

func request_set_time_scale(scale: float) -> Dictionary:
	if scale not in VALID_TIME_SCALES: return _result(false, "invalid_time_scale")
	_time_scale = scale; time_scale_changed.emit(scale); state_changed.emit(); return _result(true, "time_scale_set")
func request_save_game() -> Dictionary:
	if _game_phase != SETTLED: return _result(false, "not_settled")
	return SaveService.new().save_windowed_colony(SAVE_PATH, export_save_data())
func request_load_game() -> Dictionary:
	var loaded := SaveService.new().load_windowed_colony(SAVE_PATH)
	if not bool(loaded.ok): return loaded
	return import_save_data(loaded.data)
func has_valid_save() -> bool: return bool(SaveService.new().inspect_windowed_colony_save(SAVE_PATH).ok)

func advance_simulation(frame_delta: float) -> void:
	var delta := maxf(frame_delta, 0.0) * _time_scale
	if delta <= 0.0 or _game_phase != SETTLED: return
	_simulation_time += delta
	_emit_simulation_time_changed()
	for record: Dictionary in _scouting.advance(delta): _complete_scouting(record)
	for record: Dictionary in _travel.advance(delta): _complete_travel(record)
	audit_supply_cache_assignments()
	for id: String in get_colonist_ids():
		var colonist: Dictionary = _colonists[id]
		colonist.needs.hunger = maxf(float(colonist.needs.hunger) - 0.09 * delta, 0.0)
		colonist.needs.rest = maxf(float(colonist.needs.rest) - 0.055 * delta, 0.0)
		if _scouting.has(id) or _travel.has(id): continue
		if String(colonist.activity) == "Eating": _advance_eating(colonist, delta)
		elif String(colonist.activity) == "Sleeping on ground": _advance_sleep(colonist, delta)
		elif float(colonist.needs.hunger) <= 25.0: _advance_hunger_recovery(colonist, delta)
		else:
			colonist.hunger_recovery = false
			if float(colonist.needs.rest) <= 20.0: _start_sleep(colonist)
			elif String(colonist.role) == ROLE_HAUL: _advance_haul(colonist, delta)
			elif String(colonist.role) == ROLE_CONSTRUCTION: _advance_construction(colonist, delta)
			elif String(colonist.role) in [ROLE_WOOD, ROLE_MINING, ROLE_FORAGE]: _advance_gather(colonist, delta)

func _advance_construction(colonist: Dictionary, delta: float) -> void:
	var location_id := String(colonist.location_id)
	var colonist_id := String(colonist.colonist_id)
	var active_site_id := String(colonist.target_id)
	var active_building := _construction.get_building_snapshot(active_site_id)
	if not active_building.is_empty():
		if String(active_building.state) == Construction.COMPLETED or String(active_building.assigned_worker_id) != colonist_id or String(active_building.location_id) != location_id:
			_clear_supply_cache_job(colonist, true, "site_unavailable")
			return
		if _move_toward(colonist, Vector2i(active_building.origin_cell), delta):
			colonist.construction_travel_elapsed += delta; colonist.activity = "Walking to Supply Cache construction"
			if float(colonist.construction_travel_elapsed) >= CONSTRUCTION_TRAVEL_TIMEOUT: _clear_supply_cache_job(colonist, true, "travel_timeout")
			return
		colonist.construction_travel_elapsed = 0.0
		var supply_result := _construction.advance_worker(colonist_id, location_id, float(colonist.skills.get("Construction", 10)), delta, active_site_id)
		if not bool(supply_result.ok):
			_clear_supply_cache_job(colonist, true, String(supply_result.reason))
			return
		var updated := _construction.get_building_snapshot(active_site_id)
		if String(supply_result.reason) == "building_completed":
			colonist.target_id = ""; colonist.activity = "Built Supply Cache"
		else: colonist.activity = "Constructing %d%%" % int(100.0 * float(updated.build_progress) / float(updated.required_work))
		building_changed.emit(location_id, active_site_id); state_changed.emit()
		return
	if active_site_id.begins_with("construction_site_"):
		var site := _location_construction.get_construction_site(location_id, active_site_id)
		if site.is_empty() or String(site.reserved_by_colonist_id) != colonist_id:
			_clear_location_construction_job(colonist, false, "site_unavailable")
			return
		var work_cell := Vector2i(colonist.construction_work_cell)
		if not _traversal.is_cell_traversable(location_id, work_cell, colonist_id):
			var work_check := _location_construction.resolve_construction_work_cell(location_id, active_site_id, Vector2i(colonist.cell), colonist_id)
			if not bool(work_check.ok):
				_clear_location_construction_job(colonist, true, String(work_check.reason))
				return
			colonist.construction_work_cell = Vector2i(work_check.work_cell); work_cell = Vector2i(work_check.work_cell)
		if _move_toward(colonist, work_cell, delta):
			colonist.construction_travel_elapsed += delta
			colonist.activity = "Walking to construction"
			if float(colonist.construction_travel_elapsed) >= CONSTRUCTION_TRAVEL_TIMEOUT: _clear_location_construction_job(colonist, true, "travel_timeout")
			return
		colonist.construction_travel_elapsed = 0.0
		var skill := clampf(float(colonist.skills.get("Construction", 10)), 0.0, 20.0)
		var rate := lerpf(0.65, 1.5, skill / 20.0)
		if "Hard Worker" in colonist.traits: rate *= 1.25
		var result := request_progress_construction(location_id, active_site_id, colonist_id, rate * delta)
		if not bool(result.ok):
			_clear_location_construction_job(colonist, true, String(result.reason))
			return
		if String(result.reason) == "construction_completed":
			colonist.target_id = ""; colonist.construction_work_cell = Vector2i.ZERO; colonist.activity = "Built %s" % String(result.piece_kind).capitalize()
		else: colonist.activity = "Constructing %d%%" % int(100.0 * float(result.build_progress) / float(result.build_required))
		return
	var available := _location_construction.get_available_construction_site(location_id, colonist_id, Vector2i(colonist.cell))
	if bool(available.ok):
		var candidate: Dictionary = available.site
		var reservation := reserve_construction_site(location_id, String(candidate.site_id), colonist_id)
		if bool(reservation.ok):
			colonist.target_id = String(candidate.site_id); colonist.construction_work_cell = Vector2i(reservation.work_cell); colonist.construction_travel_elapsed = 0.0; colonist.activity = "Reserved construction"
			return
	var candidates: Array[Dictionary] = []
	for building: Dictionary in _construction.get_building_snapshots(location_id): if String(building.state) != Construction.COMPLETED and String(building.assigned_worker_id) in ["", String(colonist.colonist_id)]: candidates.append(building)
	if candidates.is_empty(): colonist.activity = "No construction available"; return
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): var da := Vector2i(a.origin_cell).distance_squared_to(Vector2i(colonist.cell)); var db := Vector2i(b.origin_cell).distance_squared_to(Vector2i(colonist.cell)); return da < db if da != db else String(a.building_instance_id) < String(b.building_instance_id))
	var target: Dictionary = candidates[0]
	var assignment := _construction.assign_worker(colonist_id, location_id, String(target.building_instance_id))
	if not bool(assignment.ok): colonist.activity = "Construction: %s" % String(assignment.reason).replace("_", " "); return
	colonist.target_id = String(target.building_instance_id); colonist.construction_travel_elapsed = 0.0; colonist.activity = "Reserved Supply Cache construction"
	building_changed.emit(location_id, String(target.building_instance_id)); state_changed.emit()

func _advance_gather(colonist: Dictionary, delta: float) -> void:
	var location_id := String(colonist.location_id)
	var target := _registry.find_resource(location_id, String(colonist.target_id))
	if target.is_empty() or not _resource_matches_role(target, String(colonist.role)):
		target = _nearest_resource(colonist)
		if target.is_empty(): colonist.activity = "No role work available"; colonist.target_id = ""; return
		colonist.target_id = target.resource_id; colonist.activity_work_cell = Vector2i(target.work_cell); colonist.work_progress = 0.0
	if _move_toward(colonist, Vector2i(colonist.activity_work_cell), delta): colonist.activity = "Walking to %s" % _resource_label(target); return
	var duration := _work_duration(colonist, target); colonist.work_progress += delta; colonist.activity = "%s %d%%" % [_work_label(target, String(colonist.role)), mini(99, int(100.0 * float(colonist.work_progress) / duration))]
	if float(colonist.work_progress) < duration: return
	var output := "food" if String(colonist.role) == ROLE_FORAGE else String(target.resource_type)
	if output == "food": target.fruit_harvested = true
	else: target.depleted = true
	var pile := _registry.create_or_merge_pile(location_id, output, int(target.yield), Vector2i(target.cell), false)
	if bool(pile.ok):
		_production_tracker.record_production(location_id, output, int(target.yield), _simulation_time)
	colonist.target_id = ""; colonist.activity_work_cell = Vector2i(-1, -1); colonist.work_progress = 0.0; colonist.activity = "Produced %d %s" % [int(target.yield), output.capitalize()]
	location_changed.emit(location_id, "resource_depleted" if bool(target.depleted) else "resource_harvested", String(target.resource_id)); location_changed.emit(location_id, "pile", String(pile.pile_id)); state_changed.emit()

func _advance_haul(colonist: Dictionary, delta: float, required_resource_type := "") -> void:
	var location_id := String(colonist.location_id)
	var destination_building_id := String(colonist.carried.get("destination_building_id", ""))
	var destination_cell := Vector2i(_registry.get_record(location_id).camp_storage_cell if location_id == LOCATION_ID else _registry.get_record(location_id).entry_cell)
	if not destination_building_id.is_empty():
		var building_cell := Vector2i(_construction.get_building_snapshot(destination_building_id).origin_cell)
		if Vector2i(colonist.activity_work_cell) == Vector2i(-1, -1):
			var interaction := _resolve_interaction_cell(colonist, building_cell)
			if not bool(interaction.ok): colonist.activity = "Storage unreachable"; return
			colonist.activity_work_cell = Vector2i(interaction.cell)
		destination_cell = Vector2i(colonist.activity_work_cell)
	if int(colonist.carried.amount) > 0:
		if _move_toward(colonist, destination_cell, delta): colonist.activity = "Carrying locally"; return
		if not destination_building_id.is_empty():
			var stored := _construction.store_reserved(String(colonist.reservation_id))
			if not bool(stored.ok): _registry.create_or_merge_pile(location_id, String(colonist.carried.type), int(colonist.carried.amount), Vector2i(colonist.carried.origin_cell), false)
			else: building_changed.emit(location_id, destination_building_id)
		else:
			var deposited := _registry.create_or_merge_pile(location_id, String(colonist.carried.type), int(colonist.carried.amount), destination_cell, location_id == LOCATION_ID); location_changed.emit(location_id, "pile", String(deposited.pile_id))
		colonist.carried = {"type": "", "amount": 0, "origin_pile_id": "", "origin_cell": Vector2i.ZERO, "destination_building_id": ""}; colonist.activity_work_cell = Vector2i(-1, -1); colonist.reservation_id = ""; colonist.activity = "Deposited locally"; haul_state_changed.emit(String(colonist.colonist_id)); state_changed.emit(); return
	var pile := _registry.get_pile_snapshot(location_id, String(colonist.target_id))
	if pile.is_empty() or bool(pile.stored) or not bool(pile.enabled) or (not required_resource_type.is_empty() and String(pile.resource_type) != required_resource_type) or not String(pile.reservation_owner_id) in ["", String(colonist.reservation_id)]:
		_cancel_activity(colonist); pile = _nearest_loose_pile(colonist, required_resource_type)
		if pile.is_empty(): colonist.activity = "No hauling available"; return
		var reservation := "local_haul_%d" % _next_reservation; _next_reservation += 1
		var amount := mini(HAUL_CAPACITY, int(pile.amount)); var storage_reservation := _construction.reserve_storage(location_id, String(pile.resource_type), amount, reservation)
		var reserved := _registry.reserve_pile(location_id, String(pile.pile_id), reservation, amount)
		if not bool(reserved.ok): _construction.release_storage(reservation); return
		colonist.carried.destination_building_id = String(storage_reservation.get("building_instance_id", ""))
		colonist.target_id = pile.pile_id; colonist.reservation_id = reservation; location_changed.emit(location_id, "pile", String(pile.pile_id))
		pile = _registry.get_pile_snapshot(location_id, String(pile.pile_id))
	if _move_toward(colonist, Vector2i(pile.cell), delta): colonist.activity = "Walking to loose pile"; return
	var amount := mini(HAUL_CAPACITY, int(pile.reserved_amount)); var pickup := _registry.pickup_reserved_pile(location_id, String(pile.pile_id), String(colonist.reservation_id), amount)
	if not bool(pickup.ok): _cancel_activity(colonist); return
	var destination_id := String(colonist.carried.get("destination_building_id", "")); colonist.carried = {"type": pile.resource_type, "amount": amount, "origin_pile_id": pile.pile_id, "origin_cell": pile.cell, "destination_building_id": destination_id}; colonist.activity_work_cell = Vector2i(-1, -1); colonist.target_id = ""; haul_state_changed.emit(String(colonist.colonist_id)); location_changed.emit(location_id, "pile", String(pile.pile_id))

func _advance_hunger_recovery(colonist: Dictionary, delta: float) -> void:
	var location_id := String(colonist.location_id)
	if not bool(colonist.get("hunger_recovery", false)) or _registry.get_consumable_stored_amount(location_id, "food") > 0:
		if _try_eat(colonist): return
	colonist.hunger_recovery = true
	if String(colonist.role) == ROLE_FORAGE:
		_advance_gather(colonist, delta)
	elif String(colonist.role) == ROLE_HAUL:
		_advance_haul(colonist, delta, "food")
	else:
		colonist.activity = "Hungry - no stored food"

func _try_eat(colonist: Dictionary) -> bool:
	_cancel_activity(colonist)
	var result := _registry.consume_stored(String(colonist.location_id), "food", 1)
	if not bool(result.ok):
		colonist.activity = "Hungry - no stored food"
		return false
	colonist.activity = "Eating"; colonist.work_progress = 0.0; state_changed.emit()
	return true
func _advance_eating(colonist: Dictionary, delta: float) -> void:
	colonist.work_progress += delta
	if float(colonist.work_progress) >= 1.0: colonist.needs.hunger = minf(100.0, float(colonist.needs.hunger) + 30.0); colonist.work_progress = 0.0; colonist.activity = "Idle"; state_changed.emit()
func _start_sleep(colonist: Dictionary) -> void: _cancel_activity(colonist); colonist.activity = "Sleeping on ground"; colonist.work_progress = 0.0
func _advance_sleep(colonist: Dictionary, delta: float) -> void:
	colonist.needs.rest = minf(100.0, float(colonist.needs.rest) + 1.6 * delta)
	if float(colonist.needs.rest) >= 80.0: colonist.activity = "Idle"; state_changed.emit()

func _move_toward(colonist: Dictionary, target: Vector2i, delta: float) -> bool:
	var current := Vector2i(colonist.cell)
	if current == target:
		colonist.visual_cell = Vector2(target); _clear_movement_path(colonist); return false
	colonist.repath_timer = maxf(float(colonist.get("repath_timer", 0.0)) - delta, 0.0)
	if Vector2i(colonist.get("movement_target", Vector2i.ZERO)) != target:
		_clear_movement_path(colonist); colonist.movement_target = target; colonist.repath_timer = 0.0
	var path: Array = colonist.get("movement_path", [])
	var path_index := int(colonist.get("movement_path_index", 0))
	if path.is_empty() or path_index >= path.size():
		if float(colonist.repath_timer) > 0.0: return true
		var path_result := find_path(String(colonist.location_id), current, target, String(colonist.colonist_id))
		if not bool(path_result.ok):
			colonist.movement_failure_reason = String(path_result.reason); colonist.repath_timer = REPATH_COOLDOWN; colonist.move_progress = 0.0
			return true
		colonist.movement_path = path_result.path.duplicate(); colonist.movement_path_index = 1; colonist.movement_failure_reason = ""
		path = colonist.movement_path; path_index = 1
	if path_index >= path.size():
		_clear_movement_path(colonist); colonist.movement_failure_reason = "path_exhausted"; return true
	var next_cell := Vector2i(path[path_index])
	if not _traversal.is_cell_traversable(String(colonist.location_id), next_cell, String(colonist.colonist_id)) or not _traversal.can_traverse_edge(String(colonist.location_id), current, next_cell):
		_clear_movement_path(colonist); colonist.movement_failure_reason = "next_cell_blocked"; colonist.repath_timer = 0.0
		return true
	colonist.move_progress += delta / MOVE_SECONDS_PER_CELL
	if float(colonist.move_progress) >= 1.0:
		colonist.move_progress -= 1.0; colonist.cell = next_cell; colonist.visual_cell = Vector2(next_cell); colonist.movement_path_index = path_index + 1; colonist_motion_changed.emit(String(colonist.colonist_id), String(colonist.location_id))
	return Vector2i(colonist.cell) != target

func _clear_movement_path(colonist: Dictionary) -> void:
	colonist.movement_path = []
	colonist.movement_path_index = 0
	colonist.movement_target = Vector2i.ZERO
	colonist.move_progress = 0.0

func _valid_traversal_actor(location_id: String, actor_id: String) -> bool:
	return actor_id.is_empty() or (_colonists.has(actor_id) and String(_colonists[actor_id].location_id) == location_id)

func _nearest_resource(colonist: Dictionary) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for resource: Dictionary in _registry.get_record(String(colonist.location_id)).resources:
		if _resource_matches_role(resource, String(colonist.role)): candidates.append(resource)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _target_less(a, b, Vector2i(colonist.cell)))
	# Gathering does not reserve globally optimal work. Check deterministic nearby
	# candidates until one has a reachable interaction cell, avoiding a full path
	# query for every resource in the location.
	for resource: Dictionary in candidates:
		var work := _resolve_interaction_cell(colonist, Vector2i(resource.cell))
		if bool(work.ok): var candidate := resource.duplicate(true); candidate.work_cell = work.cell; return candidate
	return {}

func _resolve_interaction_cell(colonist: Dictionary, target_cell: Vector2i) -> Dictionary:
	var location_id := String(colonist.location_id); var actor_id := String(colonist.colonist_id); var origin := Vector2i(colonist.cell)
	var candidates: Array[Dictionary] = []
	if _traversal.is_cell_traversable(location_id, target_cell, actor_id): candidates.append({"cell": target_cell, "order": 0})
	var order := 1
	for offset: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var cell := target_cell + offset
		if _traversal.is_cell_traversable(location_id, cell, actor_id): candidates.append({"cell": cell, "order": order})
		order += 1
	var reachable: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		var path := find_path(location_id, origin, Vector2i(candidate.cell), actor_id)
		if bool(path.ok): candidate.cost = float(path.cost); reachable.append(candidate)
	if reachable.is_empty(): return _result(false, "no_reachable_interaction_cell")
	reachable.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.cost) < float(b.cost) if not is_equal_approx(float(a.cost), float(b.cost)) else int(a.order) < int(b.order))
	return {"ok": true, "reason": "interaction_cell_resolved", "cell": Vector2i(reachable[0].cell), "cost": float(reachable[0].cost)}
func _resource_matches_role(resource: Dictionary, role: String) -> bool:
	if bool(resource.depleted): return false
	if role == ROLE_WOOD: return String(resource.resource_kind) in ["tree", "fruit_tree"]
	if role == ROLE_MINING: return String(resource.resource_kind) == "rock"
	return role == ROLE_FORAGE and String(resource.resource_kind) in ["berry_bush", "fruit_bush", "fruit_tree"] and not bool(resource.fruit_harvested)
func _nearest_loose_pile(colonist: Dictionary, required_resource_type := "") -> Dictionary:
	var piles: Array[Dictionary] = []
	for pile: Dictionary in _registry.get_pile_snapshots(String(colonist.location_id)):
		if bool(pile.enabled) and not bool(pile.stored) and String(pile.reservation_owner_id).is_empty() and (required_resource_type.is_empty() or String(pile.resource_type) == required_resource_type): piles.append(pile)
	piles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _target_less(a, b, Vector2i(colonist.cell)))
	return {} if piles.is_empty() else piles[0]
func _target_less(a: Dictionary, b: Dictionary, origin: Vector2i) -> bool:
	var da := absi(Vector2i(a.cell).x-origin.x)+absi(Vector2i(a.cell).y-origin.y); var db := absi(Vector2i(b.cell).x-origin.x)+absi(Vector2i(b.cell).y-origin.y)
	return da < db if da != db else String(a.get("resource_id", a.get("pile_id", ""))) < String(b.get("resource_id", b.get("pile_id", "")))
func _work_duration(colonist: Dictionary, target: Dictionary) -> float:
	var base := 15.0 if String(target.resource_kind) in ["tree", "fruit_tree"] else (18.0 if String(target.resource_kind) == "rock" else 6.0)
	var skill_name := "Mining" if String(target.resource_kind) == "rock" else "Plants"; var skill := clampf(float(colonist.skills[skill_name]), 0.0, 20.0)
	var multiplier := lerpf(0.65, 1.5, skill / 20.0); var trait_rate := 1.25 if "Hard Worker" in colonist.traits else 1.0
	return base / (multiplier * trait_rate)
func debug_work_duration(colonist_id: String, resource_id: String) -> float: return _work_duration(_colonists.get(colonist_id, {}), _registry.find_resource(LOCATION_ID, resource_id))

func _clear_location_construction_job(colonist: Dictionary, release_reservation: bool, reason: String) -> void:
	var site_id := String(colonist.target_id)
	if release_reservation and site_id.begins_with("construction_site_"):
		release_construction_site_reservation(String(colonist.location_id), site_id, String(colonist.colonist_id), reason)
	colonist.target_id = ""
	colonist.construction_work_cell = Vector2i.ZERO
	colonist.construction_travel_elapsed = 0.0
	_clear_movement_path(colonist)
	colonist.repath_timer = 0.0
	colonist.movement_failure_reason = reason
	colonist.activity = "Construction: %s" % reason.replace("_", " ")

func _clear_supply_cache_job(colonist: Dictionary, release_assignment: bool, reason: String) -> void:
	var building_id := String(colonist.target_id)
	if release_assignment and not building_id.is_empty(): _construction.release_worker(building_id, String(colonist.colonist_id), reason)
	colonist.target_id = ""
	colonist.construction_travel_elapsed = 0.0
	_clear_movement_path(colonist)
	colonist.repath_timer = 0.0
	colonist.movement_failure_reason = reason
	colonist.activity = "Construction: %s" % reason.replace("_", " ")

func _cancel_activity(colonist: Dictionary) -> void:
	if String(colonist.target_id).begins_with("construction_site_"):
		release_construction_site_reservation(String(colonist.location_id), String(colonist.target_id), String(colonist.colonist_id), "activity_cancelled")
	elif not _construction.get_building_snapshot(String(colonist.target_id)).is_empty():
		_construction.release_worker(String(colonist.target_id), String(colonist.colonist_id), "activity_cancelled")
	if not String(colonist.reservation_id).is_empty(): _construction.release_storage(String(colonist.reservation_id))
	if not String(colonist.reservation_id).is_empty() and not String(colonist.target_id).is_empty(): _registry.release_pile_reservation(String(colonist.location_id), String(colonist.target_id), String(colonist.reservation_id))
	if int(colonist.carried.amount) > 0:
		_registry.create_or_merge_pile(String(colonist.location_id), String(colonist.carried.type), int(colonist.carried.amount), Vector2i(colonist.carried.origin_cell), false)
		colonist.carried = {"type": "", "amount": 0, "origin_pile_id": "", "origin_cell": Vector2i.ZERO, "destination_building_id": ""}
	colonist.target_id = ""; colonist.reservation_id = ""; colonist.work_progress = 0.0; _clear_movement_path(colonist); colonist.repath_timer = 0.0; colonist.movement_failure_reason = ""; colonist.activity_work_cell = Vector2i(-1, -1); colonist.construction_work_cell = Vector2i.ZERO; colonist.construction_travel_elapsed = 0.0
func get_game_phase() -> String: return _game_phase
func get_game_seed() -> int: return _game_seed
func get_simulation_time() -> float: return _simulation_time
func get_simulation_clock() -> Dictionary:
	var total_minutes := maxi(0, int(floor(_simulation_time * DISPLAY_MINUTES_PER_SIMULATION_SECOND)))
	return {"day": int(total_minutes / DISPLAY_MINUTES_PER_DAY) + 1, "hour": int(total_minutes % DISPLAY_MINUTES_PER_DAY / 60), "minute": total_minutes % 60}
func get_time_scale() -> float: return _time_scale
func get_colonist_snapshot(id: String) -> Dictionary: return _colonists.get(id, {}).duplicate(true)
func get_colonist_ids() -> Array[String]:
	var result: Array[String] = []
	for id: Variant in _colonists: result.append(String(id))
	result.sort()
	return result
func get_location_snapshot(id: String) -> Dictionary:
	var result := _registry.snapshot(id); if result.is_empty(): return result
	result.building_records = _construction.get_building_snapshots(id); result.formal_storage = {"wood": 0, "stone": 0, "food": 0}
	for b: Dictionary in result.building_records: for type: Variant in b.storage_contents: result.formal_storage[String(type)] += int(b.storage_contents[type])
	return result
func get_location_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _registry.ids(): result.append(get_location_snapshot(id))
	return result
func get_location_ids() -> Array[String]: return _registry.ids()
func get_pile_snapshot(id: String, pile_id: String) -> Dictionary: return _registry.get_pile_snapshot(id, pile_id)
func get_pile_snapshots(id: String) -> Array[Dictionary]: return _registry.get_pile_snapshots(id)
func get_building_snapshot(id: String) -> Dictionary: return _construction.get_building_snapshot(id)
func get_building_snapshots(location_id: String) -> Array[Dictionary]: return _construction.get_building_snapshots(location_id)
func is_supply_cache_available_for_worker(building_instance_id: String, colonist_id: String) -> bool: return _construction.is_building_available_for_worker(building_instance_id, colonist_id)
func release_supply_cache_assignments_for_colonist(colonist_id: String, reason := "colonist_removed") -> Array[String]:
	var released := _construction.release_all_for_worker(colonist_id, reason)
	if _colonists.has(colonist_id) and String(_colonists[colonist_id].target_id) in released:
		_clear_supply_cache_job(_colonists[colonist_id], false, reason)
	for building_id: String in released:
		var building := _construction.get_building_snapshot(building_id)
		building_changed.emit(String(building.location_id), building_id)
	if not released.is_empty(): state_changed.emit()
	return released
func audit_supply_cache_assignments() -> Array[String]:
	var released := _construction.cleanup_stale_worker_assignments(_is_valid_supply_cache_assignment)
	for building_id: String in released:
		var building := _construction.get_building_snapshot(building_id)
		building_changed.emit(String(building.location_id), building_id)
	if not released.is_empty(): state_changed.emit()
	return released
func _is_valid_supply_cache_assignment(building_instance_id: String, colonist_id: String) -> bool:
	var building := _construction.get_building_snapshot(building_instance_id)
	if building.is_empty() or String(building.state) == Construction.COMPLETED or String(building.building_id) != "supply_cache": return false
	if not _colonists.has(colonist_id) or _scouting.has(colonist_id) or _travel.has(colonist_id): return false
	var colonist: Dictionary = _colonists[colonist_id]
	return String(colonist.role) == ROLE_CONSTRUCTION and String(colonist.location_id) == String(building.location_id) and String(colonist.target_id) == building_instance_id and colonist_id in _registry.get_record(String(building.location_id)).colonist_presence_ids
## Read-only composition boundary for building UI. Building/storage fields come
## from their simulation owner; occupants and furniture remain explicitly
## unsupported until an authoritative interior system exists.
func get_building_inspector_snapshot(id: String) -> Dictionary:
	var building := _construction.get_building_snapshot(id)
	if building.is_empty(): return {}
	var definition := BuildingDefinition.get_definition(String(building.building_id))
	var stored_items: Array[Dictionary] = []
	for resource_type: Variant in building.get("storage_contents", {}):
		var amount := int(building.storage_contents[resource_type])
		if amount > 0: stored_items.append({"resource_type": String(resource_type), "amount": amount})
	stored_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.resource_type) < String(b.resource_type))
	return {
		"building_id": String(building.building_instance_id),
		"display_name": String(building.get("display_name", definition.get("display_name", building.building_id))),
		"building_type": String(building.building_id),
		"completion_state": String(building.state),
		"completed": String(building.state) == Construction.COMPLETED,
		"world_space_id": String(building.location_id),
		"occupied_cells": building.get("occupied_cells", []).duplicate(true),
		"enclosed": bool(building.get("enclosed", false)),
		"interior_cells": building.get("interior_cells", []).duplicate(true),
		"interior_cell_count": int(building.get("interior_cell_count", 0)),
		"usable_area": int(building.get("usable_area", 0)),
		"storage_capacity_basis": int(building.get("storage_capacity_basis", 0)),
		"occupants": [],
		"stored_items": stored_items,
		"furniture": [],
		"tracking": {"occupants_supported": false, "stored_items_supported": int(building.get("storage_capacity", 0)) > 0, "furniture_supported": false},
	}.duplicate(true)
func get_location_construction_sites(location_id: String) -> Array[Dictionary]: return _location_construction.get_location_construction_sites(location_id)
func get_location_completed_structures(location_id: String) -> Dictionary: return _location_construction.get_location_completed_structures(location_id)
func get_structure_at_cell(location_id: String, cell: Vector2i) -> Dictionary: return _location_construction.get_structure_at_cell(location_id, cell)
func get_wall_fixture_at_cell(location_id: String, cell: Vector2i) -> Dictionary: return _location_construction.get_wall_fixture_at_cell(location_id, cell)
## Defensive structure-cell inspector projection. Building inspection remains a
## separate query because buildings and wall fixtures have different owners.
func get_structure_inspector_snapshot(location_id: String, cell: Vector2i) -> Dictionary:
	var structure := get_structure_at_cell(location_id, cell)
	if structure.is_empty(): return {}
	var fixture := get_wall_fixture_at_cell(location_id, cell)
	return {"cell": cell, "structure_kind": String(structure.get("kind", "")), "fixture_kind": String(fixture.get("kind", "")), "fixture_orientation": String(fixture.get("orientation", ""))}
func get_enclosed_regions(location_id: String) -> Array[Array]: return _location_construction.get_enclosed_regions(location_id)
func get_construction_site(location_id: String, site_id: String) -> Dictionary: return _location_construction.get_construction_site(location_id, site_id)
func get_construction_site_status(location_id: String, site_id: String) -> Dictionary:
	var site := _location_construction.get_construction_site(location_id, site_id)
	if site.is_empty(): return {}
	var context_id := String(site.reserved_by_colonist_id)
	if context_id.is_empty() or not _colonists.has(context_id) or String(_colonists[context_id].location_id) != location_id:
		context_id = ""
		var candidates: Array[String] = []
		for colonist_id: String in _colonists:
			if String(_colonists[colonist_id].location_id) == location_id and String(_colonists[colonist_id].role) == ROLE_CONSTRUCTION: candidates.append(colonist_id)
		candidates.sort()
		if not candidates.is_empty(): context_id = candidates[0]
	var context_cell := Vector2i(_registry.get_record(location_id).get("entry_cell", Vector2i.ZERO))
	if not context_id.is_empty(): context_cell = Vector2i(_colonists[context_id].cell)
	return _location_construction.get_construction_site_status(location_id, site_id, context_id, context_cell)
func get_available_capacity(building_instance_id: String) -> int: return _construction.get_available_capacity(building_instance_id)
func request_remove_stored_resource(building_instance_id: String, resource_type: String, amount: int) -> Dictionary:
	var result := _construction.remove_resource(building_instance_id, resource_type, amount)
	if bool(result.ok): var building := _construction.get_building_snapshot(building_instance_id); building_changed.emit(String(building.location_id), building_instance_id); state_changed.emit()
	return result
func get_scouting_snapshot(id: String) -> Dictionary: return _scouting.snapshot(id)
func get_scouting_snapshots() -> Array[Dictionary]: return _scouting.snapshots()
func get_travel_snapshot(id: String) -> Dictionary: return _travel.snapshot(id)
func get_travel_snapshots() -> Array[Dictionary]: return _travel.snapshots()
func get_resource_summary() -> Dictionary:
	var totals := _registry.resource_totals(LOCATION_ID); totals["carried"] = {"wood": 0, "stone": 0, "food": 0}
	for colonist: Dictionary in _colonists.values(): if int(colonist.carried.amount) > 0: totals.carried[String(colonist.carried.type)] += int(colonist.carried.amount)
	return totals

func get_location_production_summary(location_id: String) -> Dictionary:
	if not _registry.has(location_id): return {}
	var recent: Dictionary = _production_tracker.get_recent_amounts(location_id, _simulation_time)
	var location_totals: Dictionary = _registry.resource_totals(location_id)
	var formal_storage := {"wood": 0, "stone": 0, "food": 0}
	for building: Dictionary in _construction.get_building_snapshots(location_id):
		for resource_type: Variant in building.get("storage_contents", {}):
			formal_storage[String(resource_type)] += int(building.storage_contents[resource_type])
	var carried := {"wood": 0, "stone": 0, "food": 0}
	var roles: Dictionary = {}
	for colonist_id: String in _registry.get_record(location_id).colonist_presence_ids:
		if not _colonists.has(colonist_id): continue
		var colonist: Dictionary = _colonists[colonist_id]
		var role := String(colonist.role)
		roles[role] = int(roles.get(role, 0)) + 1
		if int(colonist.carried.amount) > 0:
			carried[String(colonist.carried.type)] += int(colonist.carried.amount)
	var production: Dictionary = {}
	var recent_total := 0
	for resource_type: String in ProductionTracker.RESOURCE_TYPES:
		var recent_amount := int(recent[resource_type])
		recent_total += recent_amount
		production[resource_type] = {
			"recent_amount": recent_amount,
			"per_minute": float(recent_amount) * 60.0 / ProductionTracker.WINDOW_SECONDS,
			"stored": int(location_totals.stored[resource_type]) + int(formal_storage[resource_type]),
			"loose": int(location_totals.loose[resource_type]),
			"carried": int(carried[resource_type]),
		}
	var presence_count := (_registry.get_record(location_id).colonist_presence_ids as Array).size()
	var status := "no_workers" if presence_count == 0 else ("producing" if recent_total > 0 else "idle")
	return {
		"location_id": location_id,
		"window_seconds": ProductionTracker.WINDOW_SECONDS,
		"production": production,
		"roles": roles.duplicate(true),
		"status": status,
	}.duplicate(true)

func export_save_data() -> Dictionary:
	var colonists: Array[Dictionary] = []
	for id: String in get_colonist_ids():
		var c: Dictionary = _colonists[id]; colonists.append({"colonist_id": c.colonist_id, "display_name": c.display_name, "skills": c.skills.duplicate(true), "traits": c.traits.duplicate(), "needs": c.needs.duplicate(true), "location_id": c.location_id, "role": c.role, "cell": c.cell, "visual_cell": c.visual_cell, "carried": c.carried.duplicate(true)})
	return {"schema": "windowed_colony", "version": SaveService.WINDOWED_COLONY_SAVE_VERSION, "game_phase": _game_phase, "game_seed": _game_seed, "simulation_time": _simulation_time, "time_scale": _time_scale, "primary_settlement_id": LOCATION_ID, "scouting_sequence": _scouting_sequence, "location_registry": _registry.export_state(), "location_construction": _construction.export_state(), "structural_construction": _location_construction.export_state(), "colonists": colonists, "active_scouting": _scouting.snapshots(), "active_travel": _travel.snapshots()}
func import_save_data(data: Dictionary) -> Dictionary:
	var validation := SaveService.new().validate_windowed_colony_data(data)
	if not bool(validation.ok): return validation
	var staged_registry := Registry.new(); var registry_result := staged_registry.import_state(data.location_registry)
	if not bool(registry_result.ok): return _result(false, "registry_%s" % registry_result.reason)
	var staged_construction := Construction.new(); staged_construction.configure(staged_registry); var construction_result := staged_construction.import_state(data.location_construction)
	if not bool(construction_result.ok): return _result(false, "construction_%s" % construction_result.reason)
	var staged_location_construction := LocationConstruction.new(); var staged_traversal := Traversal.new(); staged_traversal.configure(staged_registry, staged_location_construction, staged_construction); staged_location_construction.configure(staged_registry, staged_construction, staged_traversal)
	var structural_data: Dictionary = data.get("structural_construction", {"next_site_sequence": 1, "locations": []})
	var structural_result := staged_location_construction.import_state(structural_data)
	if not bool(structural_result.ok): return _result(false, "structural_construction_%s" % structural_result.reason)
	var staged_colonists: Dictionary = {}
	for raw: Dictionary in data.colonists:
		var id := String(raw.colonist_id); var c := raw.duplicate(true); c.activity = "Idle"; c.target_id = ""; c.work_progress = 0.0; c.move_progress = 0.0; c.movement_path = []; c.movement_path_index = 0; c.movement_target = Vector2i.ZERO; c.repath_timer = 0.0; c.movement_failure_reason = ""; c.activity_work_cell = Vector2i(-1, -1); c.reservation_id = ""; c.visual_cell = Vector2(c.cell); c.construction_work_cell = Vector2i.ZERO; c.construction_travel_elapsed = 0.0; c.hunger_recovery = false; staged_colonists[id] = c
	_registry = staged_registry; _construction = staged_construction; _location_construction = staged_location_construction; _traversal = staged_traversal; _colonists = staged_colonists; _scouting = Scouting.new(); _scouting.import_records(data.active_scouting); _travel = Travel.new(); _travel.import_records(data.active_travel); _production_tracker = ProductionTracker.new(); _game_phase = String(data.game_phase); _game_seed = int(data.game_seed); _simulation_time = float(data.simulation_time); _time_scale = float(data.time_scale); _scouting_sequence = int(data.scouting_sequence); _next_reservation = 1
	_emit_simulation_time_changed(true); game_replaced.emit()
	for location_id: String in _registry.ids(): location_created.emit(location_id)
	state_changed.emit()
	return _result(true, "loaded")

## Notifies presentation with components derived from authoritative elapsed time.
## The signal carries no independently advancing clock state.
func _emit_simulation_time_changed(force := false) -> void:
	var display_minute := maxi(0, int(floor(_simulation_time * DISPLAY_MINUTES_PER_SIMULATION_SECOND)))
	if not force and display_minute == _last_emitted_display_minute: return
	_last_emitted_display_minute = display_minute
	var clock := get_simulation_clock()
	simulation_time_changed.emit(int(clock.day), int(clock.hour), int(clock.minute))

func _complete_scouting(record: Dictionary) -> void:
	var origin := _registry.get_record(String(record.origin_location_id)); var seed_value := int(record.discovery_seed)
	var offset := Vector2i(2 + seed_value % 4, 2 + int(seed_value / 7.0) % 4)
	if seed_value % 2 == 0: offset.x *= -1
	if seed_value % 3 == 0: offset.y *= -1
	var location := _registry.create_discovered_location(String(record.origin_location_id), String(record.search_type), int(record.sequence), seed_value, Vector2i(origin.world_position) + offset)
	var colonist: Dictionary = _colonists[String(record.colonist_id)]; _scouting.finish(String(record.colonist_id)); _restore_scout_to_origin(colonist, record)
	if not location.is_empty(): location_created.emit(String(location.location_id)); discovery_completed.emit(String(location.location_id))
func _restore_scout_to_origin(colonist: Dictionary, record: Dictionary) -> void:
	var origin_id := String(record.origin_location_id); _registry.add_presence(origin_id, String(colonist.colonist_id)); colonist.location_id = origin_id; colonist.cell = _registry.get_record(origin_id).entry_cell; colonist.visual_cell = Vector2(colonist.cell); colonist.role = ROLE_NONE; colonist.activity = "Idle"; location_changed.emit(origin_id, "assignment", String(colonist.colonist_id)); scouting_changed.emit(String(colonist.colonist_id)); state_changed.emit()
func _complete_travel(record: Dictionary) -> void:
	var id := String(record.colonist_id); var destination_id := String(record.destination_location_id)
	if not _registry.has(destination_id): destination_id = String(record.origin_location_id)
	var colonist: Dictionary = _colonists[id]; _travel.finish(id); _registry.add_presence(destination_id, id); colonist.location_id = destination_id; colonist.cell = _registry.get_record(destination_id).entry_cell; colonist.visual_cell = Vector2(colonist.cell); colonist.activity = "Idle"; location_changed.emit(destination_id, "assignment", id); travel_changed.emit(id); state_changed.emit()
func _resource_label(target: Dictionary) -> String: return String(target.resource_kind).replace("_", " ")
func _work_label(target: Dictionary, role: String) -> String: return "Foraging" if role == ROLE_FORAGE else ("Mining" if role == ROLE_MINING else "Cutting")
func _seed_value(seed_value: int, index: int, salt: int) -> int: return abs(hash("%d:%d:%d" % [seed_value, index, salt]))
func _result(ok: bool, reason: String) -> Dictionary: return {"ok": ok, "reason": reason}
