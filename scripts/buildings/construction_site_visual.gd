extends Node2D
class_name ConstructionSiteVisual

## Purpose: Lightweight placeholder drawing for construction sites and placement previews.
## Responsibility: Project authoritative cell state into a non-authoritative world-space visual.
## Assumption: Current building footprints use the existing 32x16 isometric cell proportions.

var _is_preview: bool = false
var _is_valid: bool = true
var _is_completed: bool = false
var _building_id: String = "campfire"
var _construction_visual_id: String = "campfire_scaffold"
var _completed_visual_id: String = "campfire_placeholder"
var _construction_scene_path: String = ""
var _completed_scene_path: String = ""
var _placeholder_palette: Dictionary = {}
var _external_visual: Node2D
var _external_visual_path: String = ""
var _footprint: Vector2i = Vector2i.ONE
var _light_radius: float = 0.0
var _warmth_radius: float = 0.0
var _shelter_radius: float = 0.0
var _shelter_capacity: int = 0
var _show_light_glow: bool = false

func configure_site(completed: bool = false, light_radius: float = 0.0, warmth_radius: float = 0.0, show_light_glow: bool = false) -> void:
	configure_building_site("campfire", completed, Vector2i.ONE, light_radius, warmth_radius, 0.0, 0, show_light_glow, "campfire_scaffold", "campfire_placeholder")

func configure_building_site(building_id: String, completed: bool, footprint: Vector2i, light_radius: float = 0.0, warmth_radius: float = 0.0, shelter_radius: float = 0.0, shelter_capacity: int = 0, show_light_glow: bool = false, construction_visual_id: String = "generic_scaffold", completed_visual_id: String = "generic_placeholder", construction_scene_path: String = "", completed_scene_path: String = "", placeholder_palette: Dictionary = {}) -> void:
	_is_preview = false
	_is_completed = completed
	_building_id = building_id
	_construction_visual_id = construction_visual_id
	_completed_visual_id = completed_visual_id
	_construction_scene_path = construction_scene_path
	_completed_scene_path = completed_scene_path
	_placeholder_palette = placeholder_palette.duplicate(true)
	_footprint = Vector2i(maxi(footprint.x, 1), maxi(footprint.y, 1))
	_light_radius = maxf(light_radius, 0.0) if completed else 0.0
	_warmth_radius = maxf(warmth_radius, 0.0) if completed else 0.0
	_shelter_radius = maxf(shelter_radius, 0.0) if completed else 0.0
	_shelter_capacity = maxi(shelter_capacity, 0) if completed else 0
	_show_light_glow = show_light_glow and completed and _light_radius > 0.0
	_sync_external_visual()
	queue_redraw()

func configure_preview(is_valid: bool, building_id: String = "campfire", footprint: Vector2i = Vector2i.ONE, construction_visual_id: String = "generic_scaffold", placeholder_palette: Dictionary = {}) -> void:
	_is_preview = true
	_is_valid = is_valid
	_building_id = building_id
	_construction_visual_id = construction_visual_id
	_placeholder_palette = placeholder_palette.duplicate(true)
	_footprint = Vector2i(maxi(footprint.x, 1), maxi(footprint.y, 1))
	_clear_external_visual()
	queue_redraw()

func get_effect_visual_state() -> Dictionary:
	return {
		"completed": _is_completed,
		"building_id": _building_id,
		"construction_visual_id": _construction_visual_id,
		"completed_visual_id": _completed_visual_id,
		"external_visual_path": _external_visual_path,
		"uses_external_visual": _external_visual != null and is_instance_valid(_external_visual),
		"footprint": _footprint,
		"light_radius": _light_radius,
		"warmth_radius": _warmth_radius,
		"shelter_radius": _shelter_radius,
		"shelter_capacity": _shelter_capacity,
		"light_glow_visible": _show_light_glow,
	}

func _draw() -> void:
	if _is_preview:
		var preview_color := Color(0.20, 0.95, 0.35, 0.42) if _is_valid else Color(0.95, 0.18, 0.18, 0.48)
		_draw_footprint(preview_color, preview_color.lightened(0.25), 2.0)
		return
	if _is_completed:
		if _show_light_glow:
			_draw_isometric_radius(_light_radius, Color(1.0, 0.72, 0.18, 0.10), Color(1.0, 0.72, 0.18, 0.34))
		if _warmth_radius > 0.0:
			_draw_isometric_radius(_warmth_radius, Color(1.0, 0.30, 0.08, 0.045), Color(1.0, 0.34, 0.10, 0.25))
		if _shelter_radius > 0.0:
			_draw_isometric_radius(_shelter_radius, Color(0.18, 0.58, 0.92, 0.04), Color(0.30, 0.70, 1.0, 0.28))
		if _external_visual != null and is_instance_valid(_external_visual):
			return
		if _completed_visual_id == "cabin_placeholder":
			_draw_completed_cabin()
		elif _completed_visual_id == "storehouse_placeholder":
			_draw_completed_storehouse()
		else:
			_draw_completed_campfire()
		return
	if _external_visual != null and is_instance_valid(_external_visual):
		return
	_draw_footprint(_palette_color("foundation_fill", Color(0.45, 0.31, 0.16, 0.58)), _palette_color("foundation_line", Color(0.62, 0.45, 0.24, 0.85)), 1.0)
	if _construction_visual_id == "cabin_scaffold":
		_draw_cabin_scaffold()
	elif _construction_visual_id == "storehouse_scaffold":
		_draw_storehouse_scaffold()
	else:
		draw_line(Vector2(-9, 2), Vector2(9, -4), _palette_color("scaffold_dark", Color(0.24, 0.12, 0.05)), 4.0)
		draw_line(Vector2(-9, -4), Vector2(9, 2), _palette_color("scaffold_light", Color(0.31, 0.16, 0.06)), 4.0)

func _draw_footprint(fill_color: Color, line_color: Color, line_width: float) -> void:
	for y in range(_footprint.y):
		for x in range(_footprint.x):
			var center := Vector2(float(x - y) * 16.0, float(x + y) * 8.0)
			var diamond := PackedVector2Array([center + Vector2(0, -8), center + Vector2(16, 0), center + Vector2(0, 8), center + Vector2(-16, 0)])
			draw_colored_polygon(diamond, fill_color)
			draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), line_color, line_width)

func _draw_completed_campfire() -> void:
	for stone_position: Vector2 in [Vector2(-8, 1), Vector2(-5, -4), Vector2(0, -6), Vector2(5, -4), Vector2(8, 1), Vector2(4, 5), Vector2(-4, 5)]:
		draw_circle(stone_position, 2.5, _palette_color("stone", Color(0.38, 0.38, 0.40)))
	draw_line(Vector2(-7, 2), Vector2(7, -3), _palette_color("scaffold_dark", Color(0.25, 0.12, 0.04)), 4.0)
	draw_line(Vector2(-7, -3), Vector2(7, 2), _palette_color("scaffold_light", Color(0.32, 0.16, 0.05)), 4.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-5, -3), Vector2(0, -15), Vector2(5, -3), Vector2(0, 2)]), _palette_color("flame_outer", Color(1.0, 0.36, 0.06, 0.95)))
	draw_colored_polygon(PackedVector2Array([Vector2(-2.5, -3), Vector2(0, -10), Vector2(2.5, -3), Vector2(0, 0)]), _palette_color("flame_inner", Color(1.0, 0.82, 0.18, 0.98)))

func _draw_cabin_scaffold() -> void:
	for post: Vector2 in [Vector2(-20, 10), Vector2(20, 10), Vector2(0, -8), Vector2(0, 28)]:
		draw_line(post, post + Vector2(0, -14), _palette_color("scaffold_dark", Color(0.30, 0.16, 0.06)), 3.0)
	draw_polyline(PackedVector2Array([Vector2(-20, 2), Vector2(0, -10), Vector2(20, 2)]), _palette_color("scaffold_light", Color(0.52, 0.31, 0.12)), 3.0)

func _draw_completed_cabin() -> void:
	_draw_footprint(_palette_color("foundation_fill", Color(0.28, 0.20, 0.12, 0.85)), _palette_color("foundation_line", Color(0.48, 0.34, 0.18, 0.9)), 1.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-20, 2), Vector2(0, -8), Vector2(20, 2), Vector2(20, 19), Vector2(0, 29), Vector2(-20, 19)]), _palette_color("body", Color(0.55, 0.32, 0.14)))
	draw_colored_polygon(PackedVector2Array([Vector2(-24, 2), Vector2(0, -18), Vector2(24, 2), Vector2(18, 8), Vector2(0, -8), Vector2(-18, 8)]), _palette_color("roof", Color(0.27, 0.13, 0.08)))
	draw_rect(Rect2(Vector2(-5, 9), Vector2(10, 18)), _palette_color("door", Color(0.20, 0.11, 0.05)))
	draw_rect(Rect2(Vector2(9, 8), Vector2(6, 7)), _palette_color("window", Color(0.55, 0.76, 0.86, 0.8)))

func _draw_storehouse_scaffold() -> void:
	for post: Vector2 in [Vector2(-28, 10), Vector2(0, -5), Vector2(28, 10), Vector2(0, 36)]:
		draw_line(post, post + Vector2(0, -12), _palette_color("scaffold_dark", Color(0.32, 0.18, 0.08)), 3.0)
	draw_polyline(PackedVector2Array([Vector2(-28, 2), Vector2(0, -12), Vector2(28, 2)]), _palette_color("scaffold_light", Color(0.58, 0.38, 0.16)), 3.0)

func _draw_completed_storehouse() -> void:
	_draw_footprint(_palette_color("foundation_fill", Color(0.31, 0.23, 0.14, 0.86)), _palette_color("foundation_line", Color(0.54, 0.39, 0.20, 0.95)), 1.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-30, 4), Vector2(0, -11), Vector2(30, 4), Vector2(30, 25), Vector2(0, 40), Vector2(-30, 25)]), _palette_color("body", Color(0.49, 0.31, 0.14)))
	draw_colored_polygon(PackedVector2Array([Vector2(-35, 3), Vector2(0, -21), Vector2(35, 3), Vector2(28, 10), Vector2(0, -9), Vector2(-28, 10)]), _palette_color("roof", Color(0.24, 0.13, 0.07)))
	draw_rect(Rect2(Vector2(-8, 13), Vector2(16, 25)), _palette_color("door", Color(0.18, 0.10, 0.05)))
	draw_rect(Rect2(Vector2(-25, 13), Vector2(9, 9)), _palette_color("crate", Color(0.62, 0.48, 0.25)))
	draw_line(Vector2(-25, 17), Vector2(-16, 17), _palette_color("crate_line", Color(0.30, 0.19, 0.08)), 1.5)

func _palette_color(key: String, fallback: Color) -> Color:
	var value: Variant = _placeholder_palette.get(key, fallback)
	return value if value is Color else fallback

func _sync_external_visual() -> void:
	var desired_path: String = _completed_scene_path if _is_completed else _construction_scene_path
	if desired_path == _external_visual_path and _external_visual != null and is_instance_valid(_external_visual):
		return
	_clear_external_visual()
	if desired_path.is_empty():
		return
	var resource: Resource = load(desired_path)
	if resource == null or not resource is PackedScene:
		push_warning("Building visual scene could not be loaded: %s" % desired_path)
		return
	var instance: Node = (resource as PackedScene).instantiate()
	if not instance is Node2D:
		push_warning("Building visual scene root must be Node2D: %s" % desired_path)
		instance.queue_free()
		return
	_external_visual = instance as Node2D
	_external_visual.name = "ExternalBuildingVisual"
	add_child(_external_visual)
	_external_visual_path = desired_path

func _clear_external_visual() -> void:
	if _external_visual != null and is_instance_valid(_external_visual):
		if _external_visual.get_parent() == self:
			remove_child(_external_visual)
		_external_visual.queue_free()
	_external_visual = null
	_external_visual_path = ""

func _draw_isometric_radius(radius: float, fill_color: Color, line_color: Color) -> void:
	var outline := PackedVector2Array([
		Vector2(0, -8.0 * radius),
		Vector2(16.0 * radius, 0),
		Vector2(0, 8.0 * radius),
		Vector2(-16.0 * radius, 0),
	])
	draw_colored_polygon(outline, fill_color)
	draw_polyline(PackedVector2Array([outline[0], outline[1], outline[2], outline[3], outline[0]]), line_color, 1.0)
