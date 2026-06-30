extends SceneTree

## Purpose: Validate transient player-issued colonist Move commands.
## Responsibility: Exercise Main right-click translation, Colonist command replacement/movement/cleanup, and save exclusion.
## Assumption: Manual Move uses only currently loaded orthogonal ReachabilityQuery paths.

const MainScene = preload("res://scenes/Main.tscn")
const ReachabilityQueryRef = preload("res://scripts/world/reachability_query.gd")
const SaveGameServiceRef = preload("res://scripts/simulation/save_game_service.gd")
const INVALID_CELL := Vector2i(2147483647, 2147483647)

var _failed: bool = false
var _main: Node
var _world_state: Node
var _chunk_manager: ChunkManager
var _manager: ColonistManager
var _worker: Colonist


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("C03B manual move validation failed: %s" % message)
	quit(1)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _run() -> void:
	_main = MainScene.instantiate()
	root.add_child(_main)
	for _frame in range(160):
		await process_frame
	_world_state = _main.get("_world_state")
	_chunk_manager = _main.get_node("ChunkManager") as ChunkManager
	_manager = _main.get_node("ChunkManager/GameplayYSort/ColonistManager") as ColonistManager
	var colonists: Array[Colonist] = _get_colonists()
	if not _require(_world_state != null and colonists.size() >= 2, "Main scene did not initialize two selectable colonists"):
		return
	_worker = colonists[0]
	_freeze_scene(colonists)
	_prepare_worker(_worker)

	var first_target: Vector2i = _find_reachable_target(_worker.current_cell + Vector2i(7, 0), [], 3)
	if not _require(first_target != INVALID_CELL, "could not find first manual destination"):
		return
	_main.call("_set_selected_colonist", _worker)
	_issue_right_click(first_target)
	if not _require(_worker.has_active_player_command() and _worker.get_player_command_name() == "move" and _worker.get_manual_move_destination() == first_target and _worker.has_active_path(), "Main right-click did not issue a Move command"):
		return

	var exported_while_moving: Dictionary = _worker.export_state()
	var save_service := SaveGameServiceRef.new()
	var save_data: Dictionary = save_service.build_save_data(_main.get_node("WorldGenerator"), _world_state, _chunk_manager, _manager)
	for forbidden_key: String in ["player_command", "manual_destination", "manual_path"]:
		if not _require(not _contains_key_recursive(exported_while_moving, forbidden_key) and not _contains_key_recursive(save_data, forbidden_key), "save/export persisted transient %s" % forbidden_key):
			return

	_main.call("_set_selected_colonist", null)
	if not _require(_worker.has_active_player_command() and _worker.get_manual_move_destination() == first_target, "deselecting cancelled manual movement"):
		return
	_main.call("_set_selected_colonist", colonists[1])
	if not _require(_worker.has_active_player_command() and _worker.get_manual_move_destination() == first_target, "selecting another colonist changed existing movement"):
		return

	_main.call("_set_selected_colonist", _worker)
	var second_target: Vector2i = _find_reachable_target(_worker.current_cell + Vector2i(-7, 5), [first_target], 3)
	if not _require(second_target != INVALID_CELL, "could not find replacement manual destination"):
		return
	var previous_path: Array[Vector2i] = _worker.get_current_path()
	_issue_right_click(second_target)
	if not _require(_worker.has_active_player_command() and _worker.get_manual_move_destination() == second_target and _worker.target_cell == second_target and _worker.get_current_path() != previous_path, "second Move command did not replace the first"):
		return

	var state_before_invalid := {
		"activity": _worker.get_activity_name(),
		"destination": _worker.get_manual_move_destination(),
		"path": _worker.get_current_path(),
	}
	var invalid_result: Dictionary = _main.call("_request_selected_colonist_move", _world_to_screen(Vector2(10000000.0, 10000000.0)))
	if not _require(not bool(invalid_result.get("ok", false)) and _worker.get_activity_name() == state_before_invalid["activity"] and _worker.get_manual_move_destination() == state_before_invalid["destination"] and _worker.get_current_path() == state_before_invalid["path"], "invalid destination changed the active command"):
		return

	var blocked_target: Vector2i = _find_reachable_target(_worker.current_cell + Vector2i(8, -5), [first_target, second_target], 3)
	if not _require(blocked_target != INVALID_CELL, "could not find path invalidation destination"):
		return
	var blocked_command: Dictionary = _worker.request_manual_move(blocked_target)
	var blocked_path: Array[Vector2i] = _worker.get_current_path()
	if not _require(bool(blocked_command.get("ok", false)) and not blocked_path.is_empty(), "could not start path invalidation fixture"):
		return
	var blocking_cell: Vector2i = blocked_path[0]
	var blocking_placement: Dictionary = _world_state.request_place_construction("campfire", blocking_cell)
	if not _require(bool(blocking_placement.get("ok", false)), "could not block the active manual path"):
		return
	_worker._process(0.02)
	if not _require(not _worker.has_active_player_command() and _worker.get_activity_name() == "idle" and not _worker.has_active_path(), "path invalidation did not clear Move and resume AI"):
		return
	var blocking_site: Dictionary = _world_state.get_construction_site_at_cell(blocking_cell)
	_world_state.request_cancel_construction(String(blocking_site.get("site_id", "")))

	var arrival_target: Vector2i = _find_reachable_target(_worker.current_cell + Vector2i(6, 6), [first_target, second_target, blocking_cell], 3)
	if not _require(arrival_target != INVALID_CELL and bool(_worker.request_manual_move(arrival_target).get("ok", false)), "could not start arrival fixture"):
		return
	for _step in range(1200):
		_worker._process(0.02)
		if not _worker.has_active_player_command():
			break
	if not _require(_worker.current_cell == arrival_target and not _worker.has_active_player_command() and _worker.get_activity_name() == "idle" and not _worker.has_active_path(), "arrival did not clear Move and return to idle AI"):
		return
	_worker._process(0.02)
	if not _require(_worker.get_activity_name() != "moving_to_player_command" and not _worker.has_active_player_command(), "automatic AI did not resume after arrival"):
		return

	print("C03B validation passed: Main right-click, replacement, selection independence, invalid rejection, path invalidation, arrival, AI resume, and save exclusion")
	quit(0)


func _issue_right_click(cell: Vector2i) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.position = _world_to_screen(_chunk_manager.get_cell_world_position(cell))
	_main.call("_unhandled_input", event)


func _world_to_screen(world_position: Vector2) -> Vector2:
	return _main.get_canvas_transform() * world_position


func _find_reachable_target(hint: Vector2i, excluded: Array[Vector2i], minimum_steps: int) -> Vector2i:
	for radius in range(64):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := hint + Vector2i(x, y)
				if candidate in excluded:
					continue
				var path_result: Dictionary = ReachabilityQueryRef.find_path(_chunk_manager, _world_state, _worker.current_cell, candidate)
				if bool(path_result.get("reachable", false)) and (path_result.get("path", []) as Array).size() >= minimum_steps:
					return candidate
	return INVALID_CELL


func _prepare_worker(worker: Colonist) -> void:
	worker.move_speed = 1000.0
	worker.rest = 100.0
	worker.warmth = 100.0
	worker.shelter = 100.0
	worker.hunger = 100.0
	for work_type: String in Colonist.WORK_TYPES:
		worker.set_work_priority(work_type, 0)
	worker._enter_idle()
	worker.set("_pause_timer", 0.0)
	_world_state.get_time_state().import_state({"current_day": 1, "current_minutes": 600.0, "paused": true})


func _get_colonists() -> Array[Colonist]:
	var colonists: Array[Colonist] = []
	if _manager == null:
		return colonists
	for child: Node in _manager.get_children():
		if child is Colonist and not child.is_queued_for_deletion():
			colonists.append(child as Colonist)
	colonists.sort_custom(func(first: Colonist, second: Colonist) -> bool:
		return first.colonist_id < second.colonist_id
	)
	return colonists


func _freeze_scene(colonists: Array[Colonist]) -> void:
	_main.set_process(false)
	_chunk_manager.set_process(false)
	_manager.set_process(false)
	for colonist: Colonist in colonists:
		colonist.set_process(false)


func _contains_key_recursive(value: Variant, target_key: String) -> bool:
	if value is Dictionary:
		for key: Variant in (value as Dictionary).keys():
			if String(key) == target_key or _contains_key_recursive((value as Dictionary)[key], target_key):
				return true
	elif value is Array:
		for entry: Variant in value:
			if _contains_key_recursive(entry, target_key):
				return true
	return false
