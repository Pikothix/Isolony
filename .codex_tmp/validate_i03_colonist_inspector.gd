extends SceneTree

## Purpose: Validate I03 structured colonist inspection, selection lifetime, read-only refresh, and I02 compatibility.
## Responsibility: Exercise the real Main selection flow, ColonistInfoPanel projection, and WorkPriorityTable editor.
## Assumption: The inspector owns no authoritative state and therefore export records remain identical across refresh.

const MainScene = preload("res://scenes/Main.tscn")

var _failed := false
var _main: Node
var _manager: ColonistManager
var _panel: PanelContainer
var _work_table: PanelContainer
var _toolbar: PanelContainer


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("I03 colonist inspector validation failed: %s" % message)
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
	_manager = _main.get_node("ChunkManager/GameplayYSort/ColonistManager") as ColonistManager
	_panel = _main.get_node_or_null("CanvasLayer/ColonistInfoPanel") as PanelContainer
	_work_table = _main.get_node_or_null("CanvasLayer/WorkPriorityPanel") as PanelContainer
	_toolbar = _main.get_node_or_null("CanvasLayer/BottomToolbar") as PanelContainer
	_freeze_runtime()

	if not _test_initially_clear():
		return
	if not _test_structured_selected_projection():
		return
	if not _test_work_table_compatibility():
		return
	if not _test_deselection():
		return

	print("I03 COLONIST INSPECTOR VALIDATION PASSED: clear state, structured identity/activity/needs/traits/relationships/skills/work projection, read-only refresh, Work-tab editing, and deselection")
	quit(0)


func _freeze_runtime() -> void:
	_main.set_process(false)
	_manager.set_process(false)
	for colonist: Colonist in _get_colonists():
		colonist.set_process(false)


func _test_initially_clear() -> bool:
	if not _require(_panel != null, "ColonistInfoPanel is missing"):
		return false
	var snapshot: Dictionary = _panel.get_display_snapshot()
	return _require(not bool(snapshot.get("visible", true)) and String(snapshot.get("name", "")).is_empty(), "inspector was not hidden and clear without selection")


func _test_structured_selected_projection() -> bool:
	var colonists: Array[Colonist] = _get_colonists()
	if not _require(not colonists.is_empty(), "no colonist available"):
		return false
	var colonist: Colonist = colonists[0]
	var before: Dictionary = colonist.export_state()
	_main._set_selected_colonist(colonist)
	_panel._process(0.0)
	var snapshot: Dictionary = _panel.get_display_snapshot()
	if not _require(bool(snapshot.get("visible", false)), "selecting a colonist did not show inspector"):
		return false
	if not _require(String(snapshot.get("name", "")) == colonist.get_full_name(), "identity name is incorrect"):
		return false
	if not _require(String(snapshot.get("identity_meta", "")).contains(colonist.colonist_id), "identity metadata does not include colonist id"):
		return false
	if not _require(String(snapshot.get("activity", "")).contains("Activity:"), "activity section is missing"):
		return false
	var needs_text: String = String(snapshot.get("needs", ""))
	for need_name: String in ["Rest", "Warmth", "Shelter", "Hunger"]:
		if not _require(needs_text.contains(need_name), "Needs section is missing %s" % need_name):
			return false
	var trait_names: Array[String] = colonist.get_trait_display_names()
	var traits_text: String = String(snapshot.get("traits", ""))
	if trait_names.is_empty():
		if not _require(traits_text == "None", "empty Traits section does not display None"):
			return false
	else:
		for trait_name: String in trait_names:
			if not _require(traits_text.contains(trait_name), "Traits section is missing %s" % trait_name):
				return false
	var relationships: Array[Dictionary] = colonist.get_relationships()
	var relationships_text: String = String(snapshot.get("relationships", ""))
	if relationships.is_empty():
		if not _require(relationships_text == "None", "empty Relationships section does not display None"):
			return false
	else:
		for relationship: Dictionary in relationships:
			if not _require(relationships_text.contains(String(relationship.get("target_display_name", ""))), "Relationships section is missing target"):
				return false
	var skills_text: String = String(snapshot.get("skills", ""))
	for skill_name: String in Colonist.SKILL_NAMES:
		if not _require(skills_text.contains(skill_name), "Skills section is missing %s" % skill_name):
			return false
	var work_text: String = String(snapshot.get("work_priorities", ""))
	for work_type: String in Colonist.WORK_TYPES:
		if not _require(work_text.contains(work_type), "read-only Work section is missing %s" % work_type):
			return false
	var inspector_buttons: Array[Node] = _panel.find_children("*", "Button", true, false)
	if not _require(inspector_buttons.is_empty(), "inspector still contains redundant priority editors"):
		return false
	_panel._process(0.0)
	var after: Dictionary = colonist.export_state()
	return _require(before == after, "inspector refresh mutated authoritative colonist state")


func _test_work_table_compatibility() -> bool:
	var colonist: Colonist = _get_colonists()[0]
	_toolbar.set_work_panel_open(true)
	var button: Button = _work_table.get_priority_button(colonist.colonist_id, "Construct")
	if not _require(button != null, "I02 Work table lost selected colonist priority cell"):
		return false
	var original: int = colonist.get_work_priority("Construct")
	button.pressed.emit()
	if not _require(colonist.get_work_priority("Construct") == (original + 1) % (Colonist.WORK_PRIORITY_MAX + 1), "I02 Work table no longer edits authoritative priority"):
		return false
	for _press in range(4):
		button.pressed.emit()
	_toolbar.set_work_panel_open(false)
	return _require(colonist.get_work_priority("Construct") == original, "Work-table compatibility cycle did not restore priority")


func _test_deselection() -> bool:
	_main._set_selected_colonist(null)
	var snapshot: Dictionary = _panel.get_display_snapshot()
	return _require(not bool(snapshot.get("visible", true)) and String(snapshot.get("name", "")).is_empty(), "deselecting did not hide and clear inspector")


func _get_colonists() -> Array[Colonist]:
	var colonists: Array[Colonist] = []
	for child: Node in _manager.get_children():
		if child is Colonist and not child.is_queued_for_deletion():
			colonists.append(child as Colonist)
	colonists.sort_custom(func(first: Colonist, second: Colonist) -> bool:
		return first.colonist_id < second.colonist_id
	)
	return colonists
