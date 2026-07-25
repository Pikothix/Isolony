extends Node2D
class_name LocationColonistVisual

const COLONIST_TEXTURE = preload("res://assets/COLONIST.png")

var _sprite: Sprite2D
var _carry: Label

## Presentation-only colonist projection. It owns no simulation process, jobs,
## needs, position, or carried payload; configure_from_snapshot replaces visuals.
func _ready() -> void:
	_ensure_visual_nodes()


func _ensure_visual_nodes() -> void:
	if _sprite != null and _carry != null:
		return
	var shadow := Polygon2D.new()
	shadow.color = Color(0, 0, 0, 0.22)
	shadow.polygon = PackedVector2Array([Vector2(-7, 0), Vector2(0, 4), Vector2(7, 0), Vector2(0, -4)])
	add_child(shadow)
	_sprite = Sprite2D.new()
	_sprite.texture = COLONIST_TEXTURE
	_sprite.position = Vector2(0, -10)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_carry = Label.new()
	_carry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_carry.position = Vector2(8, -28)
	_carry.add_theme_color_override("font_color", Color("#fff2a8"))
	_carry.add_theme_color_override("font_outline_color", Color.BLACK)
	_carry.add_theme_constant_override("outline_size", 2)
	_carry.add_theme_font_size_override("font_size", 9)
	add_child(_carry)


func configure_from_snapshot(colonist: Dictionary) -> void:
	_ensure_visual_nodes()
	var carried: Dictionary = colonist.get("carried", {})
	var amount := int(carried.get("amount", 0))
	_carry.text = "▣ %d" % amount if amount > 0 else ""
