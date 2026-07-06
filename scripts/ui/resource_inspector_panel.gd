extends PanelContainer
class_name ResourceInspectorPanel

## Purpose: Display a transient, read-only snapshot of a clicked generated resource.
## Responsibility: Format inspection data supplied by Main without querying or mutating simulation state.
## Assumption: Selection is reconstructible UI state and is intentionally excluded from saves.

@onready var _name_label: Label = $MarginContainer/VBoxContainer/NameLabel
@onready var _kind_label: Label = $MarginContainer/VBoxContainer/KindLabel
@onready var _yield_label: Label = $MarginContainer/VBoxContainer/YieldLabel
@onready var _location_label: Label = $MarginContainer/VBoxContainer/LocationLabel
@onready var _variant_label: Label = $MarginContainer/VBoxContainer/VariantLabel

var _display_snapshot: Dictionary = {}


func _ready() -> void:
	clear_selection()


func display_resource(inspection_data: Dictionary) -> void:
	if inspection_data.is_empty():
		clear_selection()
		return
	_display_snapshot = inspection_data.duplicate(true)
	_name_label.text = String(inspection_data.get("display_name", "Resource"))
	_kind_label.text = "Kind: %s" % String(inspection_data.get("resource_kind", "unknown")).replace("_", " ").capitalize()
	_yield_label.text = "%s x%d" % [String(inspection_data.get("resource_type", "resource")).capitalize(), int(inspection_data.get("yield_amount", 0))]
	var cell: Vector2i = inspection_data.get("cell", Vector2i.ZERO)
	_location_label.text = "Cell: (%d, %d)  |  Elevation: %d" % [cell.x, cell.y, int(inspection_data.get("elevation", 0))]
	_variant_label.text = _format_variant(String(inspection_data.get("resource_kind", "")), inspection_data.get("visual_variant", {}))
	visible = true


func clear_selection() -> void:
	_display_snapshot.clear()
	visible = false
	if _name_label == null:
		return
	_name_label.text = ""
	_kind_label.text = ""
	_yield_label.text = ""
	_location_label.text = ""
	_variant_label.text = ""


func get_display_snapshot() -> Dictionary:
	## Focused validation hook; callers receive no reference to panel-owned state.
	return _display_snapshot.duplicate(true)


func _format_variant(resource_kind: String, variant: Dictionary) -> String:
	var archetype: String = String(variant.get("archetype", "")).capitalize()
	match resource_kind:
		"tree":
			if bool(variant.get("fruiting", false)):
				return "Variant: %s | Fruiting (%d)" % [archetype, int(variant.get("fruit_count", 0))]
			return "Variant: %s | No fruit" % archetype
		"berry_bush":
			return "Variant: %s | %s berries (%d)" % [archetype, String(variant.get("berry_color", "Unknown")), int(variant.get("berry_count", 0))]
		"rock":
			return "Variant: %s | %s | %d px" % [archetype, String(variant.get("size_tier", "medium")).capitalize(), int(variant.get("sprite_size", 0))]
		_:
			return "Variant: %s" % (archetype if not archetype.is_empty() else "Default")
