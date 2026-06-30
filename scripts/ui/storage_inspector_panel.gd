extends PanelContainer
class_name StorageInspectorPanel

## Purpose: Present the selected completed building's storage component.
## Responsibility: Format a defensive WorldState storage snapshot without owning or mutating storage state.
## Assumption: Main coordinates transient selection and supplies a current component snapshot after storage changes.

@onready var _building_name_label: Label = $MarginContainer/VBoxContainer/BuildingNameLabel
@onready var _capacity_value_label: Label = $MarginContainer/VBoxContainer/CapacityValueLabel
@onready var _contents_value_label: Label = $MarginContainer/VBoxContainer/ContentsValueLabel


func _ready() -> void:
	clear_selection()


func display_storage(building_name: String, component: Dictionary) -> void:
	if component.is_empty():
		clear_selection()
		return
	_building_name_label.text = building_name
	var contents: Dictionary = component.get("contents", {})
	var used_capacity: int = 0
	for amount: Variant in contents.values():
		used_capacity += maxi(int(amount), 0)
	_capacity_value_label.text = "%d / %d" % [used_capacity, maxi(int(component.get("capacity", 0)), 0)]
	_contents_value_label.text = _format_contents(contents)
	visible = true


func clear_selection() -> void:
	visible = false
	if _building_name_label == null:
		return
	_building_name_label.text = ""
	_capacity_value_label.text = ""
	_contents_value_label.text = ""


func get_display_snapshot() -> Dictionary:
	## Focused read-only validation hook for the current panel projection.
	return {
		"visible": visible,
		"building_name": _building_name_label.text if _building_name_label != null else "",
		"capacity": _capacity_value_label.text if _capacity_value_label != null else "",
		"contents": _contents_value_label.text if _contents_value_label != null else "",
	}


func _format_contents(contents: Dictionary) -> String:
	var resource_types: Array[String] = []
	for resource_type_value: Variant in contents.keys():
		var resource_type := String(resource_type_value)
		if int(contents.get(resource_type_value, 0)) > 0:
			resource_types.append(resource_type)
	resource_types.sort()
	if resource_types.is_empty():
		return "Empty"
	var lines: Array[String] = []
	for resource_type: String in resource_types:
		lines.append("%s: %d" % [resource_type.capitalize(), int(contents.get(resource_type, 0))])
	return "\n".join(lines)
