extends SceneTree

## Purpose: Validate I02 Work-tab composition, live priority editing, population refresh, and save exclusion.
## Responsibility: Exercise the real Main scene, BottomToolbar, WorkPriorityTable, Colonist APIs, and current save boundary.
## Assumption: Programmatic button presses represent UI intent and no gameplay job is required for priority editing.

const MainScene = preload("res://scenes/Main.tscn")
const SaveGameServiceRef = preload("res://scripts/simulation/save_game_service.gd")

var _failed := false
var _main: Node
var _world_state: Node
var _chunk_manager: ChunkManager
var _manager: ColonistManager
var _toolbar: PanelContainer
var _work_table: PanelContainer


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("I02 work priority table validation failed: %s" % message)
	quit(1)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _run() -> void:
	_main = MainScene.instantiate()
	root.add_child(_main)
	for _frame in range(180):
		await process_frame
	_world_state = _main.get("_world_state")
	_chunk_manager = _main.get_node("ChunkManager") as ChunkManager
	_manager = _main.get_node("ChunkManager/GameplayYSort/ColonistManager") as ColonistManager
	_toolbar = _main.get_node_or_null("CanvasLayer/BottomToolbar") as PanelContainer
	_work_table = _main.get_node_or_null("CanvasLayer/WorkPriorityPanel") as PanelContainer
	_freeze_runtime()

	if not _test_tabs_and_visibility():
		return
	if not _test_table_shape():
		return
	if not _test_priority_edit_and_wrap():
		return
	if not await _test_population_replacement_refresh():
		return
	if not _test_save_exclusion():
		return

	print("I02 WORK PRIORITY TABLE VALIDATION PASSED: tabs, exclusive panels, rows/columns, authoritative priority cycling, population replacement, and save exclusion")
	quit(0)


func _freeze_runtime() -> void:
	_main.set_process(false)
	_chunk_manager.set_process(false)
	_manager.set_process(false)
	for colonist: Colonist in _get_colonists():
		colonist.set_process(false)
	_world_state.get_time_state().import_state({"current_day": 1, "current_minutes": 600.0, "paused": true})


func _test_tabs_and_visibility() -> bool:
	if not _require(_toolbar != null and _work_table != null, "toolbar or WorkPriorityPanel is missing"):
		return false
	var buttons: Node = _main.get_node("CanvasLayer/BottomToolbar/MarginContainer/VBoxContainer/ToolbarButtons")
	var architect_button: Button = buttons.get_node_or_null("ArchitectButton") as Button
	var work_button: Button = buttons.get_node_or_null("WorkButton") as Button
	if not _require(architect_button != null and work_button != null, "Architect or Work tab is missing"):
		return false
	if not _require(not _toolbar.is_architect_menu_open() and not _toolbar.is_work_panel_open(), "toolbar panels should start closed"):
		return false
	work_button.button_pressed = true
	work_button.pressed.emit()
	if not _require(_toolbar.is_work_panel_open() and _work_table.visible and not _toolbar.is_architect_menu_open(), "Work tab did not exclusively open work table"):
		return false
	architect_button.button_pressed = true
	architect_button.pressed.emit()
	if not _require(_toolbar.is_architect_menu_open() and not _toolbar.is_work_panel_open(), "Architect tab did not hide work table"):
		return false
	work_button.button_pressed = true
	work_button.pressed.emit()
	return _require(_toolbar.is_work_panel_open() and not _toolbar.is_architect_menu_open(), "Work tab did not hide Architect menu")


func _test_table_shape() -> bool:
	var expected_types: Array[String] = ["Construct", "Harvest", "Haul", "Mine", "Farm", "Cook", "Craft", "Doctor", "Research", "Guard"]
	if not _require(_work_table.get_work_types() == expected_types, "work columns do not match Colonist.WORK_TYPES"):
		return false
	var colonists: Array[Colonist] = _get_colonists()
	if not _require(_work_table.get_row_count() == colonists.size(), "work table row count does not match live population"):
		return false
	var expected_ids: Array[String] = []
	for colonist: Colonist in colonists:
		expected_ids.append(colonist.colonist_id)
	if not _require(_work_table.get_displayed_colonist_ids() == expected_ids, "work rows are not stable-id ordered"):
		return false
	for colonist: Colonist in colonists:
		for work_type: String in expected_types:
			if not _require(_work_table.get_priority_button(colonist.colonist_id, work_type) != null, "missing %s/%s priority cell" % [colonist.colonist_id, work_type]):
				return false
	return true


func _test_priority_edit_and_wrap() -> bool:
	var colonists: Array[Colonist] = _get_colonists()
	if not _require(not colonists.is_empty(), "no colonist available for priority editing"):
		return false
	var colonist: Colonist = colonists[0]
	var work_type := "Construct"
	var button: Button = _work_table.get_priority_button(colonist.colonist_id, work_type)
	var original: int = colonist.get_work_priority(work_type)
	button.pressed.emit()
	var expected_next: int = (original + 1) % (Colonist.WORK_PRIORITY_MAX + 1)
	if not _require(colonist.get_work_priority(work_type) == expected_next, "priority cell did not mutate authoritative Colonist value"):
		return false
	_work_table.refresh_priority_labels()
	var expected_text := "-" if expected_next == Colonist.WORK_DISABLED else str(expected_next)
	if not _require(button.text == expected_text, "priority button label did not refresh from Colonist"):
		return false
	for _press in range(4):
		button.pressed.emit()
	if not _require(colonist.get_work_priority(work_type) == original, "five priority presses did not wrap to original value"):
		return false
	_work_table.refresh_priority_labels()
	var original_text := "-" if original == Colonist.WORK_DISABLED else str(original)
	return _require(button.text == original_text, "wrapped priority label is incorrect")


func _test_population_replacement_refresh() -> bool:
	var records: Array[Dictionary] = _manager.export_colonist_records()
	var expected_count: int = records.size()
	var import_result: Dictionary = _manager.import_colonist_records(records)
	if not _require(bool(import_result.get("ok", false)), "population replacement failed"):
		return false
	for _frame in range(3):
		await process_frame
	var colonists: Array[Colonist] = _get_colonists()
	if not _require(_work_table.get_row_count() == expected_count and colonists.size() == expected_count, "work table did not rebuild after population replacement"):
		return false
	for colonist: Colonist in colonists:
		if not _require(_work_table.get_priority_button(colonist.colonist_id, "Construct") != null, "replacement row is missing for %s" % colonist.colonist_id):
			return false
	return true


func _test_save_exclusion() -> bool:
	var save_service := SaveGameServiceRef.new()
	_toolbar.set_work_panel_open(false)
	var closed_data: Dictionary = save_service.build_save_data(_main.get_node("WorldGenerator"), _world_state, _chunk_manager, _manager)
	_toolbar.set_work_panel_open(true)
	var open_data: Dictionary = save_service.build_save_data(_main.get_node("WorldGenerator"), _world_state, _chunk_manager, _manager)
	if not _require(closed_data == open_data, "Work tab visibility changed save data"):
		return false
	for forbidden_key: String in ["work_panel", "work_table", "selected_tab", "priority_button"]:
		if not _require(not _contains_key_recursive(open_data, forbidden_key), "save contains transient UI key %s" % forbidden_key):
			return false
	_toolbar.set_work_panel_open(false)
	return true


func _get_colonists() -> Array[Colonist]:
	var colonists: Array[Colonist] = []
	for child: Node in _manager.get_children():
		if child is Colonist and not child.is_queued_for_deletion():
			colonists.append(child as Colonist)
	colonists.sort_custom(func(first: Colonist, second: Colonist) -> bool:
		return first.colonist_id < second.colonist_id
	)
	return colonists


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
