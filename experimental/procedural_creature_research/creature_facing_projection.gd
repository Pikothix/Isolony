class_name CreatureFacingProjection
extends RefCounted

## Pure presentation projection from direction-agnostic rig pose to four fixed isometric facings.

const NORTH_EAST := "NE"
const SOUTH_EAST := "SE"
const SOUTH_WEST := "SW"
const NORTH_WEST := "NW"
const FACINGS := [NORTH_EAST, SOUTH_EAST, SOUTH_WEST, NORTH_WEST]
const ROLES := ["near_front", "far_front", "near_rear", "far_rear"]


static func project(semantic_pose: Dictionary, facing: String) -> Dictionary:
	if semantic_pose.is_empty():
		return {}
	var resolved := facing if facing in FACINGS else NORTH_EAST
	var output := semantic_pose.duplicate(true)
	var forward := _forward_basis(resolved)
	var lateral := _lateral_basis(resolved)
	var source_map := _role_source_map(resolved)
	for key: String in ["body_anchor", "head_anchor", "front_hip", "rear_hip", "tail_root", "tail_mid", "tail_tip"]:
		if output.has(key):
			output[key] = _project_point(semantic_pose[key], 0.0, forward, lateral)
	for output_role: String in ROLES:
		var source_role: String = source_map[output_role]
		var lateral_sign: float = 1.0 if output_role.begins_with("near") else -1.0
		var hip_key := "%s_hip" % output_role
		var foot_key := "%s_foot" % output_role
		var source_hip_key := "%s_hip" % source_role
		var source_foot_key := "%s_foot" % source_role
		output[hip_key] = _project_point(semantic_pose[source_hip_key], lateral_sign * 2.2, forward, lateral)
		output[foot_key] = _project_point(semantic_pose[source_foot_key], lateral_sign * 2.8, forward, lateral)
		var source_solution: Dictionary = semantic_pose["%s_ik" % source_role]
		var projected_solution := source_solution.duplicate(true)
		projected_solution.root = output[hip_key]
		projected_solution.joint = _project_point(source_solution.joint, lateral_sign * 2.5, forward, lateral)
		projected_solution.target = output[foot_key]
		projected_solution.clamped_target = _project_point(source_solution.clamped_target, lateral_sign * 2.8, forward, lateral)
		output["%s_ik" % output_role] = projected_solution
		for suffix: String in ["state", "planted_world", "target_world", "preferred_local"]:
			var source_key := "%s_%s" % [source_role, suffix]
			if semantic_pose.has(source_key):
				output["%s_%s" % [output_role, suffix]] = semantic_pose[source_key]
		if semantic_pose.has("root_world_x") and semantic_pose.has("%s_target_world" % source_role):
			var target_world: Vector2 = semantic_pose["%s_target_world" % source_role]
			output["%s_projected_target_local" % output_role] = _project_point(Vector2(target_world.x - semantic_pose.root_world_x, target_world.y), lateral_sign * 2.8, forward, lateral)
		if semantic_pose.has("%s_preferred_local" % source_role):
			output["%s_projected_preferred_local" % output_role] = _project_point(semantic_pose["%s_preferred_local" % source_role], lateral_sign * 2.8, forward, lateral)
	output.facing = resolved
	output.forward_basis = forward
	output.lateral_basis = lateral
	output.role_source_map = source_map.duplicate(true)
	output.draw_order = ["far_rear", "far_front", "tail_back", "body", "near_rear", "near_front", "head", "attachments"]
	output.tail_behind_body = resolved in [SOUTH_EAST, SOUTH_WEST]
	output.show_far_eye = false
	output.near_ear_strength = 1.0
	output.far_ear_strength = 0.58
	output.torso_length_scale = 0.82
	output.apparent_width = 3.2
	output.travel_screen_direction = forward
	return output


static func display_name(facing: String) -> String:
	match facing:
		NORTH_EAST: return "North-East"
		SOUTH_EAST: return "South-East"
		SOUTH_WEST: return "South-West"
		NORTH_WEST: return "North-West"
		_: return "North-East"


static func _project_point(point: Vector2, lateral_offset: float, forward: Vector2, lateral: Vector2) -> Vector2:
	return Vector2(forward.x * point.x + lateral.x * lateral_offset, point.y + forward.y * point.x + lateral.y * lateral_offset)


static func _forward_basis(facing: String) -> Vector2:
	match facing:
		SOUTH_EAST: return Vector2(0.82, 0.32)
		SOUTH_WEST: return Vector2(-0.82, 0.32)
		NORTH_WEST: return Vector2(-0.82, -0.32)
		_: return Vector2(0.82, -0.32)


static func _lateral_basis(facing: String) -> Vector2:
	match facing:
		SOUTH_EAST, SOUTH_WEST: return Vector2(-0.48 if facing == SOUTH_EAST else 0.48, 0.24)
		_: return Vector2(0.48 if facing == NORTH_EAST else -0.48, 0.24)


static func _role_source_map(facing: String) -> Dictionary:
	if facing in [SOUTH_EAST, NORTH_WEST]:
		return {"near_front": "far_front", "far_front": "near_front", "near_rear": "far_rear", "far_rear": "near_rear"}
	return {"near_front": "near_front", "far_front": "far_front", "near_rear": "near_rear", "far_rear": "far_rear"}
