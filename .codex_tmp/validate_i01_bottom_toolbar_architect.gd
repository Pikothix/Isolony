extends SceneTree

## Purpose: Validate I01 bottom-toolbar composition, Architect requests, Main routing, and save exclusion.
## Responsibility: Exercise the real Main scene and generated BuildingDefinition-backed controls without altering production state.
## Assumption: Programmatic button presses represent UI intent; WorldState still validates every construction mutation.

const MainScene = preload("res://scenes/Main.tscn")
const BuildingDefinitionRef = preload("res://scripts/buildings/building_definition.gd")
const SaveGameServiceRef = preload("res://scripts/simulation/save_game_service.gd")

const INVALID_CELL := Vector2i(2147483647, 2147483647)

var _failed := false
var _main: Node
var _world_state: Node
var _chunk_manager: ChunkManager
var _manager: ColonistManager
var _toolbar: PanelContainer


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("I01 bottom toolbar validation failed: %s" % message)
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
	_toolbar = _main.get_node_or_null("CanvasLayer/BottomToolbar") as PanelContainer
	_freeze_runtime()

	if not _test_scene_structure_and_toggle():
		return
	if not _test_generated_building_requests():
		return
	if not _test_world_state_routing():
		return
	if not _test_compatibility_actions():
		return
	if not _test_save_exclusion():
		return

	print("I01 BOTTOM TOOLBAR VALIDATION PASSED: scene structure, Architect toggle, generated buildings, Main/WorldState routing, compatibility controls, cancel, and save exclusion")
	quit(0)


func _freeze_runtime() -> void:
	_main.set_process(false)
	_chunk_manager.set_process(false)
	_manager.set_process(false)
	for child: Node in _manager.get_children():
		if child is Colonist:
			child.set_process(false)
	_world_state.get_time_state().import_state({"current_day": 1, "current_minutes": 600.0, "paused": true})


func _test_scene_structure_and_toggle() -> bool:
	if not _require(_toolbar != null, "BottomToolbar is missing"):
		return false
	var architect_menu: Control = _main.get_node_or_null("CanvasLayer/ArchitectMenu") as Control
	var architect_button: Button = _main.get_node_or_null("CanvasLayer/BottomToolbar/MarginContainer/VBoxContainer/ToolbarButtons/ArchitectButton") as Button
	if not _require(architect_menu != null and architect_button != null, "Architect menu or button is missing"):
		return false
	if not _require(not _toolbar.is_architect_menu_open(), "Architect menu should start closed"):
		return false
	architect_button.button_pressed = true
	architect_button.pressed.emit()
	if not _require(_toolbar.is_architect_menu_open() and architect_menu.visible, "Architect button did not open submenu"):
		return false
	architect_button.button_pressed = false
	architect_button.pressed.emit()
	return _require(not _toolbar.is_architect_menu_open() and not architect_menu.visible, "Architect button did not close submenu")


func _test_generated_building_requests() -> bool:
	var expected_ids: Array[String] = BuildingDefinitionRef.get_building_ids()
	if not _require(expected_ids == ["campfire", "cabin", "storehouse"], "unexpected BuildingDefinition registry order"):
		return false
	if not _require(_toolbar.get_building_button_ids() == expected_ids, "Architect buttons do not match BuildingDefinition"):
		return false
	for building_id: String in expected_ids:
		var button: Button = _toolbar.get_building_button(building_id)
		if not _require(button != null and button.text.contains(String(BuildingDefinitionRef.get_definition(building_id).get("display_name", ""))), "missing generated button for %s" % building_id):
			return false
		_toolbar.set_architect_menu_open(true)
		button.pressed.emit()
		if not _require(_main.get_control_mode_name() == "build" and _main.get_selected_building_id() == building_id, "%s did not enter matching build mode" % building_id):
			return false
		if not _require(not _toolbar.is_architect_menu_open(), "%s selection did not close Architect menu" % building_id):
			return false
		_main._cancel_control_mode()
		if not _require(_main.get_control_mode_name() == "normal", "cancel did not leave %s placement mode" % building_id):
			return false
	return true


func _test_world_state_routing() -> bool:
	var campfire_button: Button = _toolbar.get_building_button("campfire")
	_toolbar.set_architect_menu_open(true)
	campfire_button.pressed.emit()
	var origin: Vector2i = _find_valid_building_origin("campfire")
	if not _require(origin != INVALID_CELL, "could not find valid Campfire origin"):
		return false
	var result: Dictionary = _main._request_place_selected_building_at_cell(origin)
	var site_id := "campfire:%d:%d" % [origin.x, origin.y]
	if not _require(bool(result.get("ok", false)) and not _world_state.get_construction_site(site_id).is_empty(), "Main placement request did not reach WorldState"):
		return false
	if not _require(bool(_world_state.request_cancel_construction(site_id).get("ok", false)), "could not clean up routed construction request"):
		return false
	_main._cancel_control_mode()
	return true


func _test_compatibility_actions() -> bool:
	var buttons: Node = _main.get_node("CanvasLayer/BottomToolbar/MarginContainer/VBoxContainer/ToolbarButtons")
	var harvest_button: Button = buttons.get_node("HarvestButton") as Button
	var stockpile_button: Button = buttons.get_node("StockpileButton") as Button
	var cancel_button: Button = buttons.get_node("CancelButton") as Button
	harvest_button.pressed.emit()
	if not _require(_main.get_control_mode_name() == "harvest", "Harvest toolbar request did not reach Main"):
		return false
	cancel_button.pressed.emit()
	if not _require(_main.get_control_mode_name() == "normal", "toolbar Cancel did not exit Harvest mode"):
		return false
	stockpile_button.pressed.emit()
	if not _require(_main.get_control_mode_name() == "stockpile", "Stockpile toolbar request did not reach Main"):
		return false
	cancel_button.pressed.emit()
	return _require(_main.get_control_mode_name() == "normal", "toolbar Cancel did not exit Stockpile mode")


func _test_save_exclusion() -> bool:
	var save_service := SaveGameServiceRef.new()
	_toolbar.set_architect_menu_open(false)
	var closed_data: Dictionary = save_service.build_save_data(_main.get_node("WorldGenerator"), _world_state, _chunk_manager, _manager)
	_toolbar.set_architect_menu_open(true)
	var open_data: Dictionary = save_service.build_save_data(_main.get_node("WorldGenerator"), _world_state, _chunk_manager, _manager)
	if not _require(closed_data == open_data, "toolbar visibility changed authoritative save data"):
		return false
	for forbidden_key: String in ["toolbar", "architect_menu", "selected_tab", "submenu"]:
		if not _require(not _contains_key_recursive(open_data, forbidden_key), "save contains transient UI key %s" % forbidden_key):
			return false
	_toolbar.set_architect_menu_open(false)
	return true


func _find_valid_building_origin(building_id: String) -> Vector2i:
	var center: Vector2i = _chunk_manager.world_to_cell(_main.get_viewport().get_camera_2d().get_screen_center_position())
	for radius in range(64):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := center + Vector2i(x, y)
				if bool(_world_state.validate_construction_placement(building_id, candidate).get("ok", false)):
					return candidate
	return INVALID_CELL


func _contains_key_recursive(value: Variant, target_key: String) -> bool:
	if value is Dictionary:
		for key: Variant in (value as Dictionary).keys():
			if String(key).to_lower().contains(target_key) or _contains_key_recursive((value as Dictionary)[key], target_key):
				return true
	elif value is Array:
		for entry: Variant in value:
			if _contains_key_recursive(entry, target_key):
				return true
	return false
