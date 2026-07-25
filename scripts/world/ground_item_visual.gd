extends Node2D
class_name GroundItemVisual

## Purpose: Draw one reconstructible physical ground-item placeholder.
## Responsibility: Present resource type and amount only; WorldState owns the item record.
## Assumption: Hauling removes/recreates this projection through WorldState signals; visuals never authorize pickup or stacking.

var _resource_type: String = ""
var _amount: int = 0
var _label: Label
var _show_amount_label := false


func configure(resource_type: String, amount: int, show_amount_label: bool = false) -> void:
	_resource_type = resource_type
	_amount = amount
	_show_amount_label = show_amount_label
	_refresh_amount_label()
	queue_redraw()


func set_amount_label_visible(enabled: bool) -> void:
	if _show_amount_label == enabled:
		return
	_show_amount_label = enabled
	_refresh_amount_label()


func is_amount_label_visible() -> bool:
	return _label != null and _label.visible


func _refresh_amount_label() -> void:
	if not _show_amount_label:
		if _label != null:
			_label.visible = false
		return
	_ensure_label()
	_label.visible = true
	_label.text = "%s x%d" % [_get_display_name(), _amount]

func _ensure_label() -> void:
	if _label != null:
		return
	_label = Label.new()
	_label.position = Vector2(-28, 3)
	_label.size = Vector2(56, 16)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 9)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

func _draw() -> void:
	var color: Color = _get_resource_color()
	var points := PackedVector2Array([Vector2(0, -6), Vector2(9, 0), Vector2(0, 6), Vector2(-9, 0)])
	draw_colored_polygon(points, Color(color, 0.92))
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), color.lightened(0.22), 1.25, true)

func _get_resource_color() -> Color:
	match _resource_type:
		"wood":
			return Color(0.48, 0.27, 0.12)
		"stone":
			return Color(0.48, 0.53, 0.58)
		"food":
			return Color(0.72, 0.18, 0.28)
	return Color(0.55, 0.48, 0.72)

func _get_display_name() -> String:
	return "Berries" if _resource_type == "food" else _resource_type.capitalize()
