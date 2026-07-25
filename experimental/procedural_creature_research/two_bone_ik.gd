class_name TwoBoneIK
extends RefCounted

## Small pure two-segment solver for the flat-ground creature prototype.

const EPSILON := 0.0001


static func solve(root: Vector2, target: Vector2, upper_length: float, lower_length: float, bend_direction: float) -> Dictionary:
	var valid: bool = root.is_finite() and target.is_finite() and is_finite(upper_length) and is_finite(lower_length) and upper_length > EPSILON and lower_length > EPSILON
	if not valid:
		var safe_root := root if root.is_finite() else Vector2.ZERO
		var safe_target := target if target.is_finite() else safe_root + Vector2.DOWN * 2.0
		var fallback_direction := Vector2.DOWN
		var safe_upper := maxf(upper_length, 1.0) if is_finite(upper_length) else 1.0
		var safe_lower := maxf(lower_length, 1.0) if is_finite(lower_length) else 1.0
		var fallback_joint := safe_root + fallback_direction * safe_upper
		var fallback_target := fallback_joint + fallback_direction * safe_lower
		return _result(safe_root, fallback_joint, safe_target, fallback_target, false, false, 1.0, safe_upper, safe_lower)

	var delta := target - root
	var raw_distance := delta.length()
	var direction := delta / raw_distance if raw_distance > EPSILON else Vector2.DOWN
	var minimum_reach := absf(upper_length - lower_length)
	var maximum_reach := upper_length + lower_length
	var solve_min := maxf(minimum_reach + EPSILON, EPSILON)
	var solve_max := maxf(solve_min, maximum_reach - EPSILON)
	var clamped_distance := clampf(raw_distance, solve_min, solve_max)
	var clamped_target := root + direction * clamped_distance
	var along := (upper_length * upper_length - lower_length * lower_length + clamped_distance * clamped_distance) / (2.0 * clamped_distance)
	var height := sqrt(maxf(upper_length * upper_length - along * along, 0.0))
	var perpendicular := Vector2(-direction.y, direction.x)
	var bend_sign := 1.0 if bend_direction >= 0.0 else -1.0
	var joint := root + direction * along + perpendicular * height * bend_sign
	var reachable := raw_distance >= minimum_reach and raw_distance <= maximum_reach and raw_distance > EPSILON
	var extension_ratio := raw_distance / maximum_reach
	return _result(root, joint, target, clamped_target, reachable, true, extension_ratio, upper_length, lower_length)


static func _result(root: Vector2, joint: Vector2, target: Vector2, clamped_target: Vector2, reachable: bool, valid: bool, extension_ratio: float, upper_length: float, lower_length: float) -> Dictionary:
	return {
		"root": root,
		"joint": joint,
		"target": target,
		"clamped_target": clamped_target,
		"reachable": reachable,
		"clamped": not reachable,
		"valid": valid,
		"extension_ratio": extension_ratio,
		"upper_length": upper_length,
		"lower_length": lower_length,
		"minimum_reach": absf(upper_length - lower_length),
		"maximum_reach": upper_length + lower_length,
	}.duplicate(true)
