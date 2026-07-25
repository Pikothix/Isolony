class_name ModularCreatureSpriteRenderer
extends Node2D

## Draws authored modular sprites from an explicitly supplied projected-pose provider.
## It owns no rig, gait, foot state, genome generation, or simulation position.

const MODE_NORMAL := "Normal"
const MODE_DEPTH := "Depth Layers"
const MODE_ANCHORS := "Anchors"

var _genome: Resource
var _sprite_set: Resource
var _pose_source: Node
var _diagnostic_mode: String = MODE_NORMAL
var _parts: Dictionary = {}
var _pose: Dictionary = {}


func configure(genome: Resource, sprite_set: Resource, pose_source: Node, diagnostic_mode: String = MODE_NORMAL) -> void:
	_genome = genome
	_sprite_set = sprite_set
	_pose_source = pose_source
	_diagnostic_mode = diagnostic_mode if diagnostic_mode in [MODE_NORMAL, MODE_DEPTH, MODE_ANCHORS] else MODE_NORMAL
	_ensure_part_nodes()
	set_process(true)
	_update_parts()


func set_diagnostic_mode(mode: String) -> void:
	_diagnostic_mode = mode if mode in [MODE_NORMAL, MODE_DEPTH, MODE_ANCHORS] else MODE_NORMAL
	_update_parts()


func get_genome_summary() -> String:
	return "" if _genome == null else _genome.debug_summary()


func get_sprite_count() -> int:
	return _parts.size()


func get_transform_snapshot() -> Dictionary:
	var result := {}
	for key: String in _parts:
		var sprite: Sprite2D = _parts[key]
		result[key] = {"position": sprite.position, "rotation": sprite.rotation, "scale": sprite.scale, "z": sprite.z_index}
	return result


func get_texture_snapshot() -> Dictionary:
	var result := {}
	for key: String in _parts:
		var sprite: Sprite2D = _parts[key]
		result[key] = sprite.texture.resource_path if sprite.texture != null else ""
	return result


func refresh_from_pose() -> void:
	_update_parts()


func _process(_delta: float) -> void:
	_update_parts()


func _ensure_part_nodes() -> void:
	if not _parts.is_empty():
		return
	for key: String in [
		"shadow", "body", "head", "near_ear", "far_ear", "tail_base", "tail_mid", "tail_tip",
		"far_rear_upper", "far_rear_lower", "far_rear_foot", "far_front_upper", "far_front_lower", "far_front_foot",
		"near_rear_upper", "near_rear_lower", "near_rear_foot", "near_front_upper", "near_front_lower", "near_front_foot",
	]:
		var sprite := Sprite2D.new()
		sprite.name = key.to_pascal_case()
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		_parts[key] = sprite


func _update_parts() -> void:
	if _genome == null or _sprite_set == null or _pose_source == null or not _pose_source.has_method("get_projected_pose"):
		return
	_pose = _pose_source.get_projected_pose()
	if _pose.is_empty():
		return
	var textures: Dictionary = _sprite_set.get_parts_for_facing(_pose.facing)
	var mirror: bool = _sprite_set.should_mirror(_pose.facing)
	_configure_centered(_parts.shadow, textures.shadow, Vector2(_pose.body_anchor.x, _pose.ground_y + 2), Vector2(0.85, 0.65), Color(1, 1, 1, 0.5), -20, mirror)
	var body_scale := Vector2(clampf(float(_genome.body_length) / 28.0, 0.8, 1.25), clampf(float(_genome.body_height) / 14.0, 0.85, 1.2))
	_configure_centered(_parts.body, textures.body, _pose.body_anchor, body_scale, _body_modulate(), 0, mirror, Vector2(_pose.forward_basis).angle())
	var head_scale_value: float = clampf(float(_genome.head_size) / 10.0, 0.82, 1.18)
	_configure_centered(_parts.head, textures.head, _pose.head_anchor, Vector2.ONE * head_scale_value, _body_modulate(), 12, mirror, Vector2(_pose.forward_basis).angle())
	_configure_ears(textures, mirror)
	_configure_tail(textures, mirror)
	_configure_leg("far_rear", textures, -12)
	_configure_leg("far_front", textures, -11)
	_configure_leg("near_rear", textures, 8)
	_configure_leg("near_front", textures, 9)
	queue_redraw()


func _configure_leg(role: String, textures: Dictionary, depth: int) -> void:
	var family: String = "front" if role.ends_with("front") else "rear"
	var solution: Dictionary = _pose["%s_ik" % role]
	_configure_segment(_parts["%s_upper" % role], textures["%s_upper_leg" % family], solution.root, solution.joint, depth, _leg_modulate(role))
	_configure_segment(_parts["%s_lower" % role], textures["%s_lower_leg" % family], solution.joint, solution.clamped_target, depth + 1, _leg_modulate(role))
	var foot_scale := Vector2(clampf(float(_genome.leg_thickness) / 3.0, 0.72, 1.25), clampf(float(_genome.leg_thickness) / 3.0, 0.72, 1.15))
	_configure_centered(_parts["%s_foot" % role], textures.foot, _pose["%s_foot" % role], foot_scale, _detail_modulate(), depth + 2, _sprite_set.should_mirror(_pose.facing))


func _configure_segment(sprite: Sprite2D, texture: Texture2D, start: Vector2, end: Vector2, depth: int, color: Color) -> void:
	var delta := end - start
	sprite.texture = texture
	sprite.position = start
	sprite.centered = true
	sprite.offset = Vector2(0, texture.get_height() * 0.5)
	sprite.rotation = delta.angle() - PI * 0.5
	sprite.scale = Vector2(clampf(float(_genome.leg_thickness) / 3.0, 0.7, 1.25), maxf(0.05, delta.length() / float(texture.get_height())))
	sprite.modulate = color
	sprite.z_index = depth
	sprite.flip_h = false


func _configure_tail(textures: Dictionary, mirror: bool) -> void:
	_configure_tail_segment(_parts.tail_base, textures.tail_base, _pose.tail_root, _pose.tail_mid, -8 if _pose.tail_behind_body else 15, mirror)
	var tail_tip_start: Vector2 = Vector2(_pose.tail_mid).lerp(_pose.tail_tip, 0.55)
	_configure_tail_segment(_parts.tail_mid, textures.tail_mid, _pose.tail_mid, tail_tip_start, -7 if _pose.tail_behind_body else 16, mirror)
	_configure_tail_segment(_parts.tail_tip, textures.tail_tip, tail_tip_start, _pose.tail_tip, -6 if _pose.tail_behind_body else 17, mirror)


func _configure_tail_segment(sprite: Sprite2D, texture: Texture2D, start: Vector2, end: Vector2, depth: int, mirror: bool) -> void:
	var delta := end - start
	sprite.texture = texture
	sprite.position = start
	sprite.centered = true
	sprite.offset = Vector2(texture.get_width() * 0.5, 0)
	sprite.rotation = delta.angle()
	sprite.scale = Vector2(maxf(0.05, delta.length() / float(texture.get_width())), 0.9)
	sprite.modulate = _detail_modulate()
	sprite.z_index = depth
	sprite.flip_v = mirror


func _configure_ears(textures: Dictionary, mirror: bool) -> void:
	var ear_key := "ear_%s" % String(_genome.ear_profile)
	var lateral := Vector2(_pose.lateral_basis).normalized()
	var near_position: Vector2 = _pose.head_anchor + lateral * 3.0 + Vector2(0, -4)
	var far_position: Vector2 = _pose.head_anchor - lateral * 2.5 + Vector2(0, -4)
	_configure_centered(_parts.far_ear, textures[ear_key], far_position, Vector2.ONE * 0.85, Color(_detail_modulate(), _pose.far_ear_strength), 13, mirror)
	_configure_centered(_parts.near_ear, textures[ear_key], near_position, Vector2.ONE, _detail_modulate(), 14, mirror)


func _configure_centered(sprite: Sprite2D, texture: Texture2D, position_value: Vector2, scale_value: Vector2, color: Color, depth: int, mirror: bool, rotation_value: float = 0.0) -> void:
	sprite.texture = texture
	sprite.position = position_value
	sprite.centered = true
	sprite.offset = Vector2.ZERO
	sprite.scale = scale_value
	sprite.modulate = color
	sprite.z_index = depth
	sprite.flip_h = mirror
	sprite.rotation = rotation_value


func _body_modulate() -> Color:
	if _diagnostic_mode == MODE_DEPTH:
		return Color("9b9fa5")
	return _genome.body_color.lightened(0.18)


func _detail_modulate() -> Color:
	return Color("b36bad") if _diagnostic_mode == MODE_DEPTH else _genome.detail_color.lightened(0.28)


func _leg_modulate(role: String) -> Color:
	if _diagnostic_mode == MODE_DEPTH:
		return Color("e0a44c") if role.begins_with("near") else Color("5579b8")
	return _genome.body_color.lightened(0.05) if role.begins_with("near") else _genome.body_color.darkened(0.12)


func _draw() -> void:
	if _diagnostic_mode != MODE_ANCHORS or _pose.is_empty():
		return
	for role: String in ["near_front", "far_front", "near_rear", "far_rear"]:
		var solution: Dictionary = _pose["%s_ik" % role]
		draw_polyline(PackedVector2Array([solution.root, solution.joint, solution.clamped_target]), Color("65f4ff"), 0.8)
		draw_circle(solution.root, 1.5, Color("65f4ff"))
		draw_circle(solution.joint, 1.5, Color("ffcf66"))
		draw_circle(_pose["%s_foot" % role], 1.5, Color("ff7f72"))
	draw_circle(_pose.body_anchor, 1.8, Color("8dff9b"))
	draw_circle(_pose.head_anchor, 1.8, Color("8dff9b"))
