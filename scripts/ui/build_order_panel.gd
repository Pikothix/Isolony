extends PanelContainer
class_name BuildOrderPanel

## Purpose: Discoverable request-only controls for build, harvest, and stockpile-zone designation.
## Responsibility: Emit player intent and display the current Main-owned control mode.
## Assumption: This panel owns no construction, harvest-order, or simulation state.

const BuildingDefinitionRef = preload("res://scripts/buildings/building_definition.gd")

signal building_requested(building_id: String)
signal harvest_mode_requested
signal stockpile_mode_requested
signal cancel_mode_requested

@onready var _mode_label: Label = $MarginContainer/VBoxContainer/ModeLabel
@onready var _cancel_button: Button = $MarginContainer/VBoxContainer/CancelButton


func _ready() -> void:
	_configure_building_button($MarginContainer/VBoxContainer/CampfireButton, "campfire", "1")
	_configure_building_button($MarginContainer/VBoxContainer/CabinButton, "cabin", "2")
	_configure_building_button($MarginContainer/VBoxContainer/StorehouseButton, "storehouse", "3")
	$MarginContainer/VBoxContainer/HarvestButton.pressed.connect(harvest_mode_requested.emit)
	$MarginContainer/VBoxContainer/StockpileButton.pressed.connect(stockpile_mode_requested.emit)
	_cancel_button.pressed.connect(cancel_mode_requested.emit)


func set_mode(mode_text: String, can_cancel: bool) -> void:
	_mode_label.text = "Mode: %s" % mode_text
	_cancel_button.disabled = not can_cancel


func _on_building_pressed(building_id: String) -> void:
	building_requested.emit(building_id)


func _configure_building_button(button: Button, building_id: String, shortcut: String) -> void:
	var definition: Dictionary = BuildingDefinitionRef.get_definition(building_id)
	button.text = "%s  [%s]" % [String(definition.get("display_name", building_id.capitalize())), shortcut]
	var icon_path: String = String(definition.get("icon_path", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var icon_resource: Resource = load(icon_path)
		if icon_resource is Texture2D:
			button.icon = icon_resource as Texture2D
	button.pressed.connect(_on_building_pressed.bind(building_id))
