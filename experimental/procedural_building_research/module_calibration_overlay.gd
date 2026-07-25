extends Node2D

## Purpose: Optional visual diagnostics for one authored atlas module instance.
## Ownership: Displays disposable calibration metadata; never changes module placement.
## Integration: Created only by the experiment renderer when calibration debug is enabled.

var semantic_id: StringName
var topology_anchor := Vector2.ZERO
var sprite_origin := Vector2.ZERO
var source_size := Vector2.ZERO
var pixel_anchor := Vector2.ZERO
var display_scale := 1.0


func configure(id: StringName, topology_point: Vector2, final_sprite_origin: Vector2, region_size: Vector2, module_pixel_anchor: Vector2, scale_factor: float) -> void:
	semantic_id = id
	topology_anchor = topology_point
	sprite_origin = final_sprite_origin
	source_size = region_size
	pixel_anchor = module_pixel_anchor
	display_scale = scale_factor
	z_index = 100
	queue_redraw()


func _draw() -> void:
	var bounds := Rect2(sprite_origin, source_size * display_scale)
	draw_rect(bounds, Color("42d9ff"), false, 1.0)
	draw_circle(topology_anchor, 2.5, Color("52ff78"))
	draw_circle(sprite_origin, 2.0, Color("ffe052"))
	draw_line(sprite_origin, topology_anchor, Color("ff9e42"), 1.0)
	var label := "%s  pixel_anchor=%s  world=%s" % [semantic_id, pixel_anchor, sprite_origin]
	draw_string(ThemeDB.fallback_font, sprite_origin + Vector2(2.0, -3.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, Color.WHITE)
