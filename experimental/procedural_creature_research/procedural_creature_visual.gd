class_name ProceduralCreatureVisual
extends Node2D

## Renders reconstructible geometry from deterministic CreatureRig pose samples.

const CreatureRigScript := preload("res://experimental/procedural_creature_research/creature_rig.gd")
const FacingProjection := preload("res://experimental/procedural_creature_research/creature_facing_projection.gd")

const MODE_NORMAL := "Normal"
const MODE_SILHOUETTE := "Silhouette"
const MODE_DEPTH_LAYERS := "Depth Layers"
const MODE_ANCHORS := "Anchors"
const MODE_NEUTRAL := "Neutral Palette"
const SUPPORTED_MODES := [MODE_NORMAL, MODE_SILHOUETTE, MODE_DEPTH_LAYERS, MODE_ANCHORS, MODE_NEUTRAL]

const SILHOUETTE_COLOR := Color("17191d")
const NEUTRAL_BODY := Color("899097")
const NEUTRAL_DETAIL := Color("42484e")
const DEPTH_FAR := Color("5579b8")
const DEPTH_BODY := Color("9b9fa5")
const DEPTH_NEAR := Color("e0a44c")
const DEPTH_HEAD := Color("73b781")
const DEPTH_ATTACHMENT := Color("b36bad")

var _genome: Resource
var _diagnostic_mode: String = MODE_NORMAL
var _rig: RefCounted
var _elapsed_time: float = 0.0
var _gait: String = CreatureRigScript.GAIT_IDLE
var _animation_speed: float = 1.0
var _paused: bool = false
var _facing: String = FacingProjection.NORTH_EAST


func configure(genome: Resource, diagnostic_mode: String = MODE_NORMAL) -> void:
	_genome = genome
	_rig = CreatureRigScript.new(genome)
	_elapsed_time = 0.0
	set_diagnostic_mode(diagnostic_mode)
	set_process(true)


func set_animation(gait: String, speed: float, paused: bool) -> void:
	var resolved_gait: String = gait if gait in [CreatureRigScript.GAIT_IDLE, CreatureRigScript.GAIT_WALKING, CreatureRigScript.GAIT_PLANTED] else CreatureRigScript.GAIT_IDLE
	var resolved_speed := clampf(speed, 0.1, 2.5)
	if resolved_gait != _gait or (resolved_gait == CreatureRigScript.GAIT_PLANTED and not is_equal_approx(resolved_speed, _animation_speed)):
		_rig.reset_locomotion(resolved_speed)
		_elapsed_time = 0.0
	_gait = resolved_gait
	_animation_speed = resolved_speed
	_paused = paused
	queue_redraw()


func reset_locomotion() -> void:
	_elapsed_time = 0.0
	if _rig != null:
		_rig.reset_locomotion(_animation_speed)
	queue_redraw()


func set_facing(facing: String) -> void:
	_facing = facing if facing in FacingProjection.FACINGS else FacingProjection.NORTH_EAST
	queue_redraw()


func sample_pose(elapsed_time: float, gait: String, speed: float) -> Dictionary:
	return {} if _rig == null else FacingProjection.project(_rig.sample(elapsed_time, gait, speed), _facing)


func get_genome_summary() -> String:
	return "" if _genome == null else _genome.debug_summary()


func get_projected_pose() -> Dictionary:
	return _pose().duplicate(true) if _rig != null else {}


func get_body_outline_points() -> PackedVector2Array:
	return PackedVector2Array() if _rig == null else _derive_body_outline(_pose())


func _process(delta: float) -> void:
	if not _paused:
		if _gait == CreatureRigScript.GAIT_PLANTED:
			_rig.advance_locomotion(delta, _animation_speed)
		else:
			_elapsed_time += delta
	queue_redraw()


func set_diagnostic_mode(mode: String) -> void:
	_diagnostic_mode = mode if mode in SUPPORTED_MODES else MODE_NORMAL
	queue_redraw()


func get_semantic_points() -> Dictionary:
	return {} if _rig == null else _pose().duplicate(true)


func _draw() -> void:
	if _genome == null:
		return
	var anchors := _pose()
	var body_center: Vector2 = anchors.body_anchor
	var silhouette := _diagnostic_mode == MODE_SILHOUETTE
	var body_color := _body_color()
	var detail_color := _detail_color()
	if _gait == CreatureRigScript.GAIT_PLANTED:
		_draw_travel_lane(anchors.root_world_x, anchors.travel_screen_direction)
	_draw_ellipse_polygon(Vector2(body_center.x, anchors.ground_y + 2.0), Vector2(_genome.body_length * 0.58, 3.0), Color(0.02, 0.03, 0.04, 0.3), 12)

	# Intentional static depth order: far legs, rear attachment, body, near legs, head/details.
	_draw_leg("far_rear", anchors.far_rear_ik, anchors.far_rear_foot, SILHOUETTE_COLOR if silhouette else (DEPTH_FAR if _diagnostic_mode == MODE_DEPTH_LAYERS else body_color.darkened(0.24)), detail_color)
	_draw_leg("far_front", anchors.far_front_ik, anchors.far_front_foot, SILHOUETTE_COLOR if silhouette else (DEPTH_FAR if _diagnostic_mode == MODE_DEPTH_LAYERS else body_color.darkened(0.24)), detail_color)
	if _genome.has_tail and anchors.tail_behind_body:
		_draw_tail(anchors, SILHOUETTE_COLOR if silhouette else (DEPTH_ATTACHMENT if _diagnostic_mode == MODE_DEPTH_LAYERS else detail_color))
	_draw_body_outline(anchors, SILHOUETTE_COLOR if silhouette else (DEPTH_BODY if _diagnostic_mode == MODE_DEPTH_LAYERS else body_color))
	if _genome.has_tail and not anchors.tail_behind_body:
		_draw_tail(anchors, SILHOUETTE_COLOR if silhouette else (DEPTH_ATTACHMENT if _diagnostic_mode == MODE_DEPTH_LAYERS else detail_color))
	_draw_leg("near_rear", anchors.near_rear_ik, anchors.near_rear_foot, SILHOUETTE_COLOR if silhouette else (DEPTH_NEAR if _diagnostic_mode == MODE_DEPTH_LAYERS else body_color.darkened(0.06)), detail_color)
	_draw_leg("near_front", anchors.near_front_ik, anchors.near_front_foot, SILHOUETTE_COLOR if silhouette else (DEPTH_NEAR if _diagnostic_mode == MODE_DEPTH_LAYERS else body_color.darkened(0.06)), detail_color)
	_draw_head(anchors, silhouette, body_color, detail_color)
	if _diagnostic_mode == MODE_ANCHORS:
		_draw_anchor_overlay(anchors)


func _pose() -> Dictionary:
	var semantic_pose: Dictionary
	if _gait == CreatureRigScript.GAIT_PLANTED:
		semantic_pose = _rig.get_current_planted_pose()
	else:
		var sample_time: float = 0.0 if _diagnostic_mode == MODE_ANCHORS else _elapsed_time
		semantic_pose = _rig.sample(sample_time, _gait, _animation_speed)
	return FacingProjection.project(semantic_pose, _facing)


func _draw_body_outline(anchors: Dictionary, color: Color) -> void:
	draw_colored_polygon(_derive_body_outline(anchors), color)


func _derive_body_outline(anchors: Dictionary) -> PackedVector2Array:
	var center: Vector2 = anchors.body_anchor
	var half_length: float = _genome.body_length * 0.5
	var half_height: float = _genome.body_height * 0.5 * anchors.torso_height_scale
	var forward: Vector2 = Vector2(anchors.forward_basis).normalized()
	half_length *= anchors.torso_length_scale
	var front_height: float = half_height * (1.0 + _genome.torso_taper) * _genome.chest_depth * anchors.chest_depth_scale
	var rear_height: float = half_height * (1.0 - _genome.torso_taper) * _genome.hip_volume
	var back_curve: float = _genome.back_curve
	var belly_curve: float = _genome.belly_curve
	var shoulder_slope: float = _genome.shoulder_slope
	var rump_slope: float = _genome.rump_slope
	match String(_genome.body_profile):
		"lean": belly_curve -= 0.08
		"stocky": belly_curve += 0.1
		"heavy_front": shoulder_slope -= 0.06
		"heavy_rear": rump_slope -= 0.06
	match String(_genome.posture):
		"alert": back_curve *= 0.45; shoulder_slope -= 0.03
		"curious": shoulder_slope -= 0.025
		"relaxed": back_curve += 0.04; belly_curve += 0.04
		"proud": shoulder_slope -= 0.06
	var neck_half: float = maxf(2.2, half_height * 0.42 * _genome.neck_thickness)
	var neck_center: Vector2 = center.lerp(anchors.head_anchor, 0.58)
	var torso := PackedVector2Array([
		_body_point(center, forward, -half_length * 0.7, -rear_height * (0.66 - rump_slope)),
		_body_point(center, forward, -half_length * 0.15, -half_height * (0.82 + back_curve)),
		_body_point(center, forward, half_length * 0.5, -front_height * (0.72 - shoulder_slope)),
		neck_center + Vector2(0, -neck_half),
		center.lerp(anchors.head_anchor, 0.7),
		neck_center + Vector2(0, neck_half),
		neck_center + forward * (half_length * 0.18) + Vector2(0, neck_half * 0.9),
		_body_point(center, forward, half_length * 0.58, front_height * 0.72),
		_body_point(center, forward, half_length * 0.26, half_height * (0.62 + belly_curve * 0.7)),
		_body_point(center, forward, -half_length * 0.12, half_height * (0.68 + belly_curve)),
		_body_point(center, forward, -half_length * 0.45, rear_height * (0.58 + belly_curve * 0.35)),
		_body_point(center, forward, -half_length * 0.7, rear_height * 0.62),
		_body_point(center, forward, -half_length * 0.84, rear_height * 0.12),
		_body_point(center, forward, -half_length * 0.76, -rear_height * (0.5 - rump_slope)),
	])
	return _ensure_clockwise(torso)


func _draw_leg(role: String, solution: Dictionary, actual_foot: Vector2, color: Color, foot_color: Color) -> void:
	var hip: Vector2 = solution.root
	var knee: Vector2 = solution.joint
	var solved_foot: Vector2 = solution.clamped_target
	var base_width: float = maxf(1.5, float(_genome.leg_thickness))
	var is_front: bool = role.ends_with("front")
	var upper_hip_width: float = base_width * (1.18 if is_front else 1.28)
	var upper_knee_width: float = maxf(1.25, base_width * (0.68 if is_front else 0.82))
	var lower_foot_width: float = maxf(1.25, base_width * (0.58 if is_front else 0.76))
	_draw_tapered_segment(hip, knee, upper_hip_width, upper_knee_width, 0.0, 0.7, color)
	_draw_tapered_segment(knee, solved_foot, upper_knee_width, lower_foot_width, 0.7, 0.35, color)
	# This bridge sits under both overlapping polygons, avoiding a detached-cap silhouette.
	draw_circle(knee.round(), maxf(0.75, upper_knee_width * 0.45), color)
	if solution.clamped:
		draw_line(solved_foot.round(), actual_foot.round(), Color(0.9, 0.3, 0.24, 0.75), 1.0, false)
	_draw_foot_pad(role, actual_foot, color if _diagnostic_mode in [MODE_SILHOUETTE, MODE_DEPTH_LAYERS] else foot_color)


func _draw_tapered_segment(start: Vector2, end: Vector2, start_width: float, end_width: float, overlap_start: float, overlap_end: float, color: Color) -> void:
	var delta := end - start
	if delta.length_squared() < 0.0001:
		draw_circle(start.round(), maxf(start_width, end_width) * 0.5, color)
		return
	var direction := delta.normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	var extended_start := start - direction * overlap_start
	var extended_end := end + direction * overlap_end
	var polygon := PackedVector2Array([
		extended_start + perpendicular * start_width * 0.5,
		extended_end + perpendicular * end_width * 0.5,
		extended_end - perpendicular * end_width * 0.5,
		extended_start - perpendicular * start_width * 0.5,
	])
	draw_colored_polygon(_snapped_points(polygon), color)


func _draw_foot_pad(role: String, foot: Vector2, color: Color) -> void:
	var pad_length: float = 3.4 if role.ends_with("front") else 4.0
	var pad_height: float = maxf(1.5, float(_genome.leg_thickness) * 0.42)
	var heel := foot + Vector2(-0.75, -pad_height * 0.45)
	var toe := foot + Vector2(pad_length, -pad_height * 0.2)
	var polygon := PackedVector2Array([
		heel,
		toe,
		toe + Vector2(0, pad_height),
		heel + Vector2(0, pad_height),
	])
	draw_colored_polygon(_snapped_points(polygon), color)


func _draw_head(anchors: Dictionary, silhouette: bool, body_color: Color, detail_color: Color) -> void:
	var center: Vector2 = anchors.head_anchor
	var ear_offset: float = anchors.ear_offset
	var forward: Vector2 = Vector2(anchors.forward_basis).normalized()
	var lateral: Vector2 = Vector2(anchors.lateral_basis).normalized()
	var radius := Vector2(_genome.head_size * 0.52, _genome.head_size * 0.47)
	var head_color := SILHOUETTE_COLOR if silhouette else (DEPTH_HEAD if _diagnostic_mode == MODE_DEPTH_LAYERS else body_color.lightened(0.04))
	_draw_ellipse_polygon(center, radius, head_color, 12)
	var attachment_color := SILHOUETTE_COLOR if silhouette else (DEPTH_ATTACHMENT if _diagnostic_mode == MODE_DEPTH_LAYERS else detail_color)
	_draw_ear(center - lateral * radius.x * 0.28 + Vector2(0, -radius.y * 0.62 + ear_offset), Color(attachment_color, anchors.far_ear_strength))
	_draw_ear(center + lateral * radius.x * 0.3 + Vector2(0, -radius.y * 0.62 - ear_offset * 0.7), attachment_color)
	if silhouette:
		return
	var near_eye := center + forward * radius.x * 0.3 + lateral * radius.x * 0.22 + Vector2(0, -1)
	draw_circle(near_eye.round(), 1.2, Color("17151a"))
	if anchors.show_far_eye:
		draw_circle((center + forward * radius.x * 0.3 - lateral * radius.x * 0.18 + Vector2(0, -1)).round(), 0.8, Color("17151a"))
	var muzzle := center + forward * radius.x * 0.72 + Vector2(0, radius.y * 0.18 + _genome.muzzle_offset)
	_draw_ellipse_polygon(muzzle.round(), Vector2(maxf(2.0, radius.x * 0.38 * _genome.muzzle_length), maxf(1.5, radius.y * 0.28)), attachment_color, 8)


func _draw_ear(root: Vector2, color: Color) -> void:
	var ear_length: float = 5.0 if _genome.head_size <= 8 else 7.0
	match String(_genome.ear_profile):
		"pointed":
			draw_colored_polygon(PackedVector2Array([root + Vector2(-2, 1), root + Vector2(0, -ear_length), root + Vector2(3, 1)]), color)
		"long":
			draw_colored_polygon(PackedVector2Array([root + Vector2(-2, 0), root + Vector2(-1, -ear_length), root + Vector2(2, -ear_length - 1), root + Vector2(3, 1)]), color)
		_:
			draw_circle(root.round(), 3.0, color)


func _draw_tail(anchors: Dictionary, color: Color) -> void:
	draw_polyline(PackedVector2Array([anchors.tail_root, Vector2(anchors.tail_mid).round(), Vector2(anchors.tail_tip).round()]), color, maxf(2.0, _genome.leg_thickness - 1.0), false)


func _draw_anchor_overlay(anchors: Dictionary) -> void:
	var font := ThemeDB.fallback_font
	draw_line(Vector2(-38, anchors.ground_y), Vector2(38, anchors.ground_y), Color("55dbe0"), 1.0)
	var facing_tip: Vector2 = Vector2(anchors.body_anchor) + Vector2(anchors.forward_basis).normalized() * 12.0
	draw_line(anchors.body_anchor, facing_tip, Color("ffdf75"), 1.2)
	draw_string(font, facing_tip + Vector2(2, -2), anchors.facing, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color("ffdf75"))
	var entries := {
		"body_anchor": "body", "head_anchor": "head", "front_hip": "F hip", "rear_hip": "R hip",
		"near_front_foot": "NF", "near_rear_foot": "NR", "far_front_foot": "FF", "far_rear_foot": "FR", "tail_root": "tail",
	}
	for key: String in entries:
		var point: Vector2 = anchors[key]
		draw_circle(point, 1.8, Color("55dbe0"))
		draw_string(font, point + Vector2(2, -2), entries[key], HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("d5ffff"))
	for leg_role: String in ["near_front", "far_front", "near_rear", "far_rear"]:
		var solution: Dictionary = anchors["%s_ik" % leg_role]
		var knee: Vector2 = solution.joint
		var diagnostic_color := Color("ff5e57") if solution.clamped else Color("8dff9b")
		draw_circle(knee, 1.8, diagnostic_color)
		draw_line(solution.root, knee, Color(diagnostic_color, 0.55), 0.7)
		draw_line(knee, solution.clamped_target, Color(diagnostic_color, 0.55), 0.7)
		draw_string(font, knee + Vector2(2, -2), "%.2f%s" % [solution.extension_ratio, " !" if solution.clamped else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 5, diagnostic_color)
	var outline: PackedVector2Array = _derive_body_outline(anchors)
	for index in range(0, outline.size(), 2):
		draw_circle(outline[index], 1.2, Color("ff9fcf"))
		draw_string(font, outline[index] + Vector2(1, -1), "b%d" % index, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Color("ffd2e7"))
	if _gait == CreatureRigScript.GAIT_PLANTED:
		draw_string(font, Vector2(-38, -38), "root %.1f" % anchors.root_world_x, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color("ffdf75"))
		for foot_key: String in ["near_front", "far_front", "near_rear", "far_rear"]:
			var actual: Vector2 = anchors["%s_foot" % foot_key]
			var preferred: Vector2 = anchors["%s_projected_preferred_local" % foot_key]
			var target_local: Vector2 = anchors["%s_projected_target_local" % foot_key]
			draw_circle(preferred, 1.5, Color("80a7ff"))
			draw_circle(target_local, 1.5, Color("ff8f72"))
			draw_line(actual, target_local, Color(1.0, 0.56, 0.45, 0.55), 0.7)
			draw_string(font, actual + Vector2(2, 5), String(anchors["%s_state" % foot_key]), HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Color("fff0c2"))


func _draw_travel_lane(root_world_x: float, travel_direction: Vector2) -> void:
	var direction := travel_direction.normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	draw_line(-direction * 52.0 + Vector2(0, 1), direction * 52.0 + Vector2(0, 1), Color(0.38, 0.44, 0.48, 0.75), 1.0)
	var scroll: float = fposmod(root_world_x, 8.0)
	for index in range(-7, 8):
		var along: float = float(index * 8) - scroll
		var point := direction * along + Vector2(0, 1)
		draw_line(point - perpendicular * 2.0, point + perpendicular * 2.0, Color(0.5, 0.57, 0.61, 0.7), 1.0)


func _body_color() -> Color:
	return NEUTRAL_BODY if _diagnostic_mode == MODE_NEUTRAL else _genome.body_color


func _detail_color() -> Color:
	return NEUTRAL_DETAIL if _diagnostic_mode == MODE_NEUTRAL else _genome.detail_color


func _draw_ellipse_polygon(center: Vector2, radii: Vector2, color: Color, point_count: int) -> void:
	var points := PackedVector2Array()
	for index in range(point_count):
		var angle := TAU * float(index) / float(point_count)
		points.append((center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y)).round())
	draw_colored_polygon(points, color)


func _draw_oriented_ellipse(center: Vector2, radii: Vector2, forward: Vector2, color: Color, point_count: int) -> void:
	var points := PackedVector2Array()
	for index in range(point_count):
		var angle := TAU * float(index) / float(point_count)
		points.append((_body_point(center, forward, cos(angle) * radii.x, sin(angle) * radii.y)).round())
	draw_colored_polygon(points, color)


func _body_point(center: Vector2, forward: Vector2, along: float, vertical: float) -> Vector2:
	return center + forward * along + Vector2(0, vertical)


func _snapped_points(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		result.append(point.round())
	return result


func _ensure_clockwise(points: PackedVector2Array) -> PackedVector2Array:
	var twice_area: float = 0.0
	for index in range(points.size()):
		var current: Vector2 = points[index]
		var following: Vector2 = points[(index + 1) % points.size()]
		twice_area += current.x * following.y - following.x * current.y
	if twice_area < 0.0:
		var reversed := PackedVector2Array()
		for index in range(points.size() - 1, -1, -1):
			reversed.append(points[index])
		return reversed
	return points
