extends PanelContainer
class_name BottomToolbar

## Purpose: Present bottom actions and route Architect/Work drawer requests.
## Responsibility: Emit player intent and reflect BottomUiController state; never mutate simulation state.
## Assumption: Toolbar controls and drawer selection are transient and unsaved.

const BuildingDefinitionRef = preload("res://scripts/buildings/building_definition.gd")

signal building_requested(building_id: String)
signal harvest_mode_requested
signal cancel_mode_requested
signal time_speed_requested(mode: String)

@onready var _architect_button: Button = $MarginContainer/VBoxContainer/ToolbarButtons/ArchitectButton
@onready var _work_button: Button = $MarginContainer/VBoxContainer/ToolbarButtons/WorkButton
@onready var _harvest_button: Button = $MarginContainer/VBoxContainer/ToolbarButtons/HarvestButton
@onready var _cancel_button: Button = $MarginContainer/VBoxContainer/ToolbarButtons/CancelButton
@onready var _pause_speed_button: Button = $MarginContainer/VBoxContainer/SpeedButtons/PauseButton
@onready var _normal_speed_button: Button = $MarginContainer/VBoxContainer/SpeedButtons/NormalButton
@onready var _fast_speed_button: Button = $MarginContainer/VBoxContainer/SpeedButtons/FastButton
@onready var _faster_speed_button: Button = $MarginContainer/VBoxContainer/SpeedButtons/FasterButton
@onready var _mode_label: Label = $MarginContainer/VBoxContainer/ModeLabel
@onready var _drawer_controller: BottomUiController = $"../BottomUiController"
@onready var _building_buttons: HBoxContainer = $"../ArchitectMenu/MarginContainer/VBoxContainer/BuildingButtons"

var _buttons_by_building_id: Dictionary = {}


func _ready() -> void:
	_rebuild_building_buttons()
	_architect_button.pressed.connect(_on_architect_pressed)
	_work_button.pressed.connect(_on_work_pressed)
	_harvest_button.pressed.connect(_on_harvest_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_pause_speed_button.pressed.connect(_on_time_speed_pressed.bind("pause"))
	_normal_speed_button.pressed.connect(_on_time_speed_pressed.bind("normal"))
	_fast_speed_button.pressed.connect(_on_time_speed_pressed.bind("fast"))
	_faster_speed_button.pressed.connect(_on_time_speed_pressed.bind("faster"))
	_drawer_controller.active_drawer_changed.connect(_on_active_drawer_changed)
	set_architect_menu_open(false)
	set_time_speed_mode("normal")


func set_mode(mode_text: String, can_cancel: bool) -> void:
	_mode_label.text = "Mode: %s" % mode_text
	_cancel_button.disabled = not can_cancel
	if not can_cancel and mode_text == "Normal Selection":
		close_submenus()

func set_time_speed_mode(mode: String) -> void:
	## Presentation-only selection state. TimeState remains authoritative for the actual simulation speed.
	var buttons := {
		"pause": _pause_speed_button,
		"normal": _normal_speed_button,
		"fast": _fast_speed_button,
		"faster": _faster_speed_button,
	}
	for button_mode_value: Variant in buttons.keys():
		var button: Button = buttons[button_mode_value]
		button.button_pressed = String(button_mode_value) == mode


func set_architect_menu_open(open: bool) -> void:
	_drawer_controller.open_drawer(BottomUiController.DRAWER_ARCHITECT) if open else _drawer_controller.close_drawer_if_active(BottomUiController.DRAWER_ARCHITECT)


func is_architect_menu_open() -> bool:
	return _drawer_controller.get_active_drawer() == BottomUiController.DRAWER_ARCHITECT


func set_work_panel_open(open: bool) -> void:
	_drawer_controller.open_drawer(BottomUiController.DRAWER_WORK) if open else _drawer_controller.close_drawer_if_active(BottomUiController.DRAWER_WORK)


func is_work_panel_open() -> bool:
	return _drawer_controller.get_active_drawer() == BottomUiController.DRAWER_WORK


func close_submenus() -> void:
	_drawer_controller.close_current_drawer()


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
	_drawer_controller.close_current_drawer()
	harvest_mode_requested.emit()


func _on_cancel_pressed() -> void:
	_drawer_controller.close_current_drawer()
	cancel_mode_requested.emit()

func _on_time_speed_pressed(mode: String) -> void:
	time_speed_requested.emit(mode)


func _on_building_pressed(building_id: String) -> void:
	if not BuildingDefinitionRef.has_definition(building_id):
		push_warning("Architect menu ignored unknown building '%s'." % building_id)
		return
	close_submenus()
	building_requested.emit(building_id)


func _on_active_drawer_changed(drawer_id: String) -> void:
	_architect_button.button_pressed = drawer_id == BottomUiController.DRAWER_ARCHITECT
	_work_button.button_pressed = drawer_id == BottomUiController.DRAWER_WORK


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
