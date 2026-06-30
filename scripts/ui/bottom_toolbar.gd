extends PanelContainer
class_name BottomToolbar

## Purpose: Present the bottom control toolbar plus mutually exclusive Architect and Work panels.
## Responsibility: Emit player intent and project Main-owned control mode; never mutate simulation state.
## Assumption: Architect/Work visibility, selected tab, and generated buttons are transient and unsaved.

const BuildingDefinitionRef = preload("res://scripts/buildings/building_definition.gd")

signal building_requested(building_id: String)
signal harvest_mode_requested
signal cancel_mode_requested

@onready var _architect_button: Button = $MarginContainer/VBoxContainer/ToolbarButtons/ArchitectButton
@onready var _work_button: Button = $MarginContainer/VBoxContainer/ToolbarButtons/WorkButton
@onready var _harvest_button: Button = $MarginContainer/VBoxContainer/ToolbarButtons/HarvestButton
@onready var _cancel_button: Button = $MarginContainer/VBoxContainer/ToolbarButtons/CancelButton
@onready var _mode_label: Label = $MarginContainer/VBoxContainer/ModeLabel
@onready var _architect_menu: PanelContainer = $"../ArchitectMenu"
@onready var _work_panel: PanelContainer = $"../WorkPriorityPanel"
@onready var _building_buttons: HBoxContainer = $"../ArchitectMenu/MarginContainer/VBoxContainer/BuildingButtons"

var _buttons_by_building_id: Dictionary = {}


func _ready() -> void:
	_rebuild_building_buttons()
	_architect_button.pressed.connect(_on_architect_pressed)
	_work_button.pressed.connect(_on_work_pressed)
	_harvest_button.pressed.connect(_on_harvest_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	set_architect_menu_open(false)
	set_work_panel_open(false)


func set_mode(mode_text: String, can_cancel: bool) -> void:
	_mode_label.text = "Mode: %s" % mode_text
	_cancel_button.disabled = not can_cancel
	if not can_cancel and mode_text == "Normal Selection":
		close_submenus()


func set_architect_menu_open(open: bool) -> void:
	_set_architect_menu_visible(open)
	if open:
		_set_work_panel_visible(false)


func is_architect_menu_open() -> bool:
	return _architect_menu.visible


func set_work_panel_open(open: bool) -> void:
	_set_work_panel_visible(open)
	if open:
		_set_architect_menu_visible(false)


func is_work_panel_open() -> bool:
	return _work_panel.visible


func close_submenus() -> void:
	_set_architect_menu_visible(false)
	_set_work_panel_visible(false)


func get_building_button_ids() -> Array[String]:
	var ids: Array[String] = []
	for building_id: String in BuildingDefinitionRef.get_building_ids():
		if _buttons_by_building_id.has(building_id):
			ids.append(building_id)
	return ids


func get_building_button(building_id: String) -> Button:
	return _buttons_by_building_id.get(building_id) as Button


func _on_architect_pressed() -> void:
	set_architect_menu_open(_architect_button.button_pressed)


func _on_work_pressed() -> void:
	set_work_panel_open(_work_button.button_pressed)


func _on_harvest_pressed() -> void:
	close_submenus()
	harvest_mode_requested.emit()


func _on_cancel_pressed() -> void:
	close_submenus()
	cancel_mode_requested.emit()


func _on_building_pressed(building_id: String) -> void:
	if not BuildingDefinitionRef.has_definition(building_id):
		push_warning("Architect menu ignored unknown building '%s'." % building_id)
		return
	close_submenus()
	building_requested.emit(building_id)


func _set_architect_menu_visible(visible: bool) -> void:
	_architect_menu.visible = visible
	_architect_button.button_pressed = visible


func _set_work_panel_visible(visible: bool) -> void:
	_work_panel.visible = visible
	_work_button.button_pressed = visible


func _rebuild_building_buttons() -> void:
	## Generated controls are projections of BuildingDefinition and carry no construction authority.
	for child: Node in _building_buttons.get_children():
		child.queue_free()
	_buttons_by_building_id.clear()
	var building_ids: Array[String] = BuildingDefinitionRef.get_building_ids()
	for index in range(building_ids.size()):
		var building_id: String = building_ids[index]
		var definition: Dictionary = BuildingDefinitionRef.get_definition(building_id)
		var button := Button.new()
		button.name = "%sButton" % building_id.to_pascal_case()
		button.custom_minimum_size = Vector2(150, 48)
		button.text = "%s  [%d]" % [String(definition.get("display_name", building_id.capitalize())), index + 1]
		button.tooltip_text = _build_tooltip(definition)
		var icon_path: String = String(definition.get("icon_path", ""))
		if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
			var icon_resource: Resource = load(icon_path)
			if icon_resource is Texture2D:
				button.icon = icon_resource as Texture2D
		button.pressed.connect(_on_building_pressed.bind(building_id))
		_building_buttons.add_child(button)
		_buttons_by_building_id[building_id] = button


func _build_tooltip(definition: Dictionary) -> String:
	var cost_parts: Array[String] = []
	var cost: Dictionary = definition.get("cost", {})
	var resource_types: Array[String] = []
	for resource_type_value: Variant in cost.keys():
		resource_types.append(String(resource_type_value))
	resource_types.sort()
	for resource_type: String in resource_types:
		cost_parts.append("%d %s" % [int(cost.get(resource_type, 0)), resource_type.capitalize()])
	var footprint: Vector2i = definition.get("footprint", Vector2i.ONE)
	return "%s\nCost: %s\nFootprint: %dx%d" % [
		String(definition.get("display_name", "Building")),
		", ".join(cost_parts) if not cost_parts.is_empty() else "None",
		footprint.x,
		footprint.y,
	]
