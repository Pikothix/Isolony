extends PanelContainer
class_name WorkPriorityTable

## Purpose: Present a live colonist-by-work-type priority matrix above the bottom toolbar.
## Responsibility: Read live Colonist priority APIs, emit edits through set_work_priority(), and rebuild presentation rows.
## Assumption: Button labels and live-node references are transient; this panel owns no work policy or save data.

const PRIORITY_DISABLED_TEXT := "-"

@onready var _table_grid: GridContainer = $MarginContainer/VBoxContainer/TableScroll/TableGrid

var _colonist_manager: ColonistManager
var _priority_cells: Array[Dictionary] = []
var _buttons_by_cell: Dictionary = {}
var _displayed_colonist_ids: Array[String] = []


func _ready() -> void:
	_table_grid.columns = Colonist.WORK_TYPES.size() + 1


func _process(_delta: float) -> void:
	if visible:
		refresh_priority_labels()


func setup(colonist_manager: ColonistManager) -> void:
	if _colonist_manager != null and is_instance_valid(_colonist_manager) and _colonist_manager.population_replaced.is_connected(_on_population_replaced):
		_colonist_manager.population_replaced.disconnect(_on_population_replaced)
	_colonist_manager = colonist_manager
	if _colonist_manager != null and not _colonist_manager.population_replaced.is_connected(_on_population_replaced):
		_colonist_manager.population_replaced.connect(_on_population_replaced)
	call_deferred("rebuild_table")


func rebuild_table() -> void:
	for child: Node in _table_grid.get_children():
		child.queue_free()
	_priority_cells.clear()
	_buttons_by_cell.clear()
	_displayed_colonist_ids.clear()
	_add_header("Colonist", 160.0)
	for work_type: String in Colonist.WORK_TYPES:
		_add_header(work_type, 78.0)
	if _colonist_manager == null or not is_instance_valid(_colonist_manager):
		return
	var colonists: Array[Colonist] = _get_live_colonists()
	for colonist: Colonist in colonists:
		_displayed_colonist_ids.append(colonist.colonist_id)
		var name_label := Label.new()
		name_label.custom_minimum_size = Vector2(160, 34)
		name_label.text = colonist.get_full_name()
		name_label.tooltip_text = colonist.colonist_id
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_table_grid.add_child(name_label)
		for work_type: String in Colonist.WORK_TYPES:
			var button := Button.new()
			button.custom_minimum_size = Vector2(78, 34)
			button.tooltip_text = "%s — %s" % [colonist.get_full_name(), work_type]
			button.pressed.connect(_on_priority_pressed.bind(colonist, work_type, button))
			_table_grid.add_child(button)
			_priority_cells.append({"colonist": colonist, "work_type": work_type, "button": button})
			_buttons_by_cell[_cell_key(colonist.colonist_id, work_type)] = button
			_refresh_priority_button(colonist, work_type, button)


func refresh_priority_labels() -> void:
	for cell: Dictionary in _priority_cells:
		var colonist: Colonist = cell.get("colonist") as Colonist
		var button: Button = cell.get("button") as Button
		if colonist == null or button == null or not is_instance_valid(colonist) or not is_instance_valid(button):
			continue
		_refresh_priority_button(colonist, String(cell.get("work_type", "")), button)


func get_work_types() -> Array[String]:
	return Colonist.WORK_TYPES.duplicate()


func get_row_count() -> int:
	return _displayed_colonist_ids.size()


func get_displayed_colonist_ids() -> Array[String]:
	return _displayed_colonist_ids.duplicate()


func get_priority_button(colonist_id: String, work_type: String) -> Button:
	return _buttons_by_cell.get(_cell_key(colonist_id, work_type)) as Button


func _on_population_replaced() -> void:
	call_deferred("rebuild_table")


func _on_priority_pressed(colonist: Colonist, work_type: String, button: Button) -> void:
	if colonist == null or not is_instance_valid(colonist):
		return
	var current: int = colonist.get_work_priority(work_type)
	var next_priority: int = (current + 1) % (Colonist.WORK_PRIORITY_MAX + 1)
	if not colonist.set_work_priority(work_type, next_priority):
		push_warning("Work table rejected priority edit for %s/%s." % [colonist.colonist_id, work_type])
		return
	_refresh_priority_button(colonist, work_type, button)


func _refresh_priority_button(colonist: Colonist, work_type: String, button: Button) -> void:
	var priority: int = colonist.get_work_priority(work_type)
	button.text = PRIORITY_DISABLED_TEXT if priority == Colonist.WORK_DISABLED else str(priority)
	button.modulate = Color(0.72, 0.72, 0.72) if priority == Colonist.WORK_DISABLED else Color.WHITE


func _get_live_colonists() -> Array[Colonist]:
	var colonists: Array[Colonist] = []
	for child: Node in _colonist_manager.get_children():
		if child is Colonist and not child.is_queued_for_deletion():
			colonists.append(child as Colonist)
	colonists.sort_custom(func(first: Colonist, second: Colonist) -> bool:
		return first.colonist_id < second.colonist_id
	)
	return colonists


func _add_header(text: String, minimum_width: float) -> void:
	var label := Label.new()
	label.custom_minimum_size = Vector2(minimum_width, 32)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_table_grid.add_child(label)


func _cell_key(colonist_id: String, work_type: String) -> String:
	return "%s|%s" % [colonist_id, work_type]
