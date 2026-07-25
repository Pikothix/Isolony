class_name CreatureRig
extends RefCounted

## Owns deterministic semantic pose generation and transient planted-foot presentation state.
## Root travel and foot world positions are diagnostic presentation data, never gameplay position.

const GAIT_IDLE := "Idle"
const GAIT_WALKING := "Treadmill Walk"
const GAIT_PLANTED := "Planted Walk"
const FIXED_TIMESTEP := 1.0 / 60.0
const ROOT_SPEED := 12.0
const MAX_STEPS_PER_ADVANCE := 240
const TwoBoneIKScript := preload("res://experimental/procedural_creature_research/two_bone_ik.gd")

const STATE_STANCE := "STANCE"
const STATE_LIFT := "LIFT"
const STATE_SWING := "SWING"
const STATE_PLANT := "PLANT"
const FOOT_KEYS := ["near_front", "far_front", "near_rear", "far_rear"]

var _genome: Resource
var _root_x: float = 0.0
var _sim_time: float = 0.0
var _accumulator: float = 0.0
var _active_speed: float = 1.0
var _feet: Dictionary = {}
var _visited_states: Dictionary = {}
var _last_pose: Dictionary = {}


func _init(genome: Resource) -> void:
	_genome = genome
	reset_locomotion()


func reset_locomotion(speed: float = 1.0) -> void:
	_root_x = 0.0
	_sim_time = 0.0
	_accumulator = 0.0
	_active_speed = clampf(speed, 0.1, 2.5)
	_feet.clear()
	_visited_states.clear()
	var base := _base_pose()
	for key: String in FOOT_KEYS:
		var local_key := "%s_foot" % key
		var world_position: Vector2 = base[local_key]
		_feet[key] = {
			"state": STATE_STANCE,
			"world": world_position,
			"planted_world": world_position,
			"step_start_world": world_position,
			"target_world": world_position,
			"plant_start_world": world_position,
			"height": 0.0,
		}
		_visited_states[key] = {STATE_STANCE: true}
	_last_pose = _compose_planted_pose()


func advance_locomotion(delta: float, speed: float) -> Dictionary:
	var resolved_speed := clampf(speed, 0.1, 2.5)
	if not is_equal_approx(resolved_speed, _active_speed):
		reset_locomotion(resolved_speed)
	_accumulator += maxf(delta, 0.0)
	var steps := 0
	while _accumulator + 0.0000001 >= FIXED_TIMESTEP and steps < MAX_STEPS_PER_ADVANCE:
		_fixed_step()
		_accumulator -= FIXED_TIMESTEP
		steps += 1
	if steps == MAX_STEPS_PER_ADVANCE:
		_accumulator = minf(_accumulator, FIXED_TIMESTEP)
	_last_pose = _compose_planted_pose()
	return _last_pose.duplicate(true)


func get_current_planted_pose() -> Dictionary:
	return _last_pose.duplicate(true)


func get_locomotion_snapshot() -> Dictionary:
	var foot_snapshot := {}
	for key: String in FOOT_KEYS:
		var foot: Dictionary = _feet[key]
		foot_snapshot[key] = {
			"state": foot.state,
			"world": Vector2(foot.world),
			"planted_world": Vector2(foot.planted_world),
			"target_world": Vector2(foot.target_world),
			"height": snappedf(foot.height, 0.000001),
		}
	return {
		"root_x": snappedf(_root_x, 0.000001),
		"sim_time": snappedf(_sim_time, 0.000001),
		"accumulator": snappedf(_accumulator, 0.000001),
		"feet": foot_snapshot,
		"pose": _last_pose.duplicate(true),
	}


func get_visited_states() -> Dictionary:
	return _visited_states.duplicate(true)


func sample(elapsed_time: float, gait: String, speed: float) -> Dictionary:
	if gait == GAIT_PLANTED:
		var replay := CreatureRig.new(_genome)
		replay.reset_locomotion(speed)
		var aligned_steps: int = maxi(0, int(floor(elapsed_time / FIXED_TIMESTEP + 0.000001)))
		for _step in range(aligned_steps):
			replay._fixed_step()
		replay._last_pose = replay._compose_planted_pose()
		return replay._last_pose.duplicate(true)
	return _sample_stateless(elapsed_time, gait, speed)


func sample_planted_snapshot(elapsed_time: float, speed: float) -> Dictionary:
	var replay := CreatureRig.new(_genome)
	replay.reset_locomotion(speed)
	var aligned_steps: int = maxi(0, int(floor(elapsed_time / FIXED_TIMESTEP + 0.000001)))
	for _step in range(aligned_steps):
		replay._fixed_step()
	replay._last_pose = replay._compose_planted_pose()
	return replay.get_locomotion_snapshot()


func _fixed_step() -> void:
	_sim_time += FIXED_TIMESTEP
	_root_x += ROOT_SPEED * _active_speed * FIXED_TIMESTEP
	for key: String in FOOT_KEYS:
		_update_foot(key)


func _update_foot(key: String) -> void:
	var foot: Dictionary = _feet[key]
	var phase: float = fposmod(_sim_time * _active_speed + _phase_offset(key), 1.0)
	var desired := _state_for_phase(phase)
	if desired != foot.state:
		_enter_state(key, foot, desired)
	var progress := _state_progress(phase, desired)
	match desired:
		STATE_STANCE:
			foot.world = foot.planted_world
			foot.height = 0.0
		STATE_LIFT:
			var eased := _smoothstep(progress)
			foot.world = Vector2(foot.step_start_world).lerp(foot.target_world, eased * 0.08)
			foot.height = sin(progress * PI * 0.5) * 2.0
		STATE_SWING:
			var eased := _smoothstep(progress)
			foot.world = Vector2(foot.step_start_world).lerp(foot.target_world, lerpf(0.08, 0.88, eased))
			foot.height = 2.0 + sin(progress * PI) * 1.4
		STATE_PLANT:
			var eased := _smoothstep(progress)
			foot.world = Vector2(foot.plant_start_world).lerp(foot.target_world, eased)
			# Smooth height as well as horizontal travel so contact decelerates without popping.
			foot.height = lerpf(2.0, 0.0, eased)
	_feet[key] = foot


func _enter_state(key: String, foot: Dictionary, state: String) -> void:
	foot.state = state
	_visited_states[key][state] = true
	match state:
		STATE_LIFT:
			foot.step_start_world = foot.planted_world
			# Select once: predicted root at plant completion plus preferred local placement.
			var remaining: float = 0.52 / _active_speed
			var preferred: Vector2 = _preferred_local_foot(key)
			var stride_lead: float = clampf(ROOT_SPEED * _active_speed * 0.18, 1.8, 4.8)
			foot.target_world = Vector2(_root_x + ROOT_SPEED * _active_speed * remaining + preferred.x + stride_lead, preferred.y)
		STATE_PLANT:
			foot.plant_start_world = foot.world
		STATE_STANCE:
			foot.world = foot.target_world
			foot.planted_world = foot.target_world
			foot.height = 0.0
	_feet[key] = foot


func _compose_planted_pose() -> Dictionary:
	var pose := _base_pose()
	var gait_phase: float = _sim_time * _active_speed * TAU
	var body_delta := Vector2(sin(gait_phase * 0.5) * 0.25, -abs(sin(gait_phase)) * 0.9)
	_apply_body_motion(pose, body_delta)
	pose.head_anchor.y -= body_delta.y * 0.7
	pose.root_world_x = _root_x
	pose.ear_offset = sin(gait_phase - 0.7) * 0.5
	for key: String in FOOT_KEYS:
		var foot: Dictionary = _feet[key]
		pose["%s_foot" % key] = Vector2(foot.world.x - _root_x, foot.world.y - foot.height)
		pose["%s_state" % key] = foot.state
		pose["%s_planted_world" % key] = foot.planted_world
		pose["%s_target_world" % key] = foot.target_world
		pose["%s_preferred_local" % key] = _preferred_local_foot(key)
	_apply_tail_follow(pose, gait_phase, body_delta, GAIT_PLANTED)
	_solve_leg_ik(pose)
	return pose


func _sample_stateless(elapsed_time: float, gait: String, speed: float) -> Dictionary:
	var seed_phase: float = float(posmod(_genome.seed, 997)) / 997.0 * TAU
	var gait_phase: float = elapsed_time * maxf(speed, 0.0) * TAU + seed_phase
	var breath_phase: float = elapsed_time * 1.35 + seed_phase
	var pose := _base_pose()
	var body_delta := Vector2.ZERO
	var breath: float = sin(breath_phase)
	pose.torso_height_scale = 1.0 + breath * 0.018
	pose.chest_depth_scale = 1.0 + breath * 0.025
	pose.ear_offset = sin(breath_phase - 0.45) * 0.45
	if gait == GAIT_WALKING:
		body_delta.y = -abs(sin(gait_phase)) * 1.2
		body_delta.x = sin(gait_phase * 0.5) * 0.35
		pose.ear_offset += sin(gait_phase - 0.7) * 0.55
		_apply_treadmill_feet(pose, gait_phase)
	else:
		body_delta.x = sin(elapsed_time * 0.42 + seed_phase) * 0.45
		var weight: float = sin(elapsed_time * 0.55 + seed_phase) * 0.45
		for key: String in ["front_hip", "far_front_hip", "near_front_hip"]: pose[key].y += weight
		for key: String in ["rear_hip", "far_rear_hip", "near_rear_hip"]: pose[key].y -= weight
	_apply_body_motion(pose, body_delta)
	pose.head_anchor.y -= body_delta.y * 0.68
	pose.head_anchor.y += sin((gait_phase if gait == GAIT_WALKING else breath_phase) - 0.3) * 0.35
	_apply_tail_follow(pose, gait_phase if gait == GAIT_WALKING else breath_phase, body_delta, gait)
	_solve_leg_ik(pose)
	return pose


func _solve_leg_ik(pose: Dictionary) -> void:
	var total_length: float = _genome.leg_length + _genome.body_height * 0.3 + 3.0
	var upper_ratio: float = 0.5
	match String(_genome.body_profile):
		"lean": upper_ratio = 0.47
		"stocky": upper_ratio = 0.53
	var upper_length: float = total_length * upper_ratio
	var lower_length: float = total_length - upper_length
	for role: String in FOOT_KEYS:
		var family: String = "front" if role.ends_with("front") else "rear"
		var hip_key := "%s_%s_hip" % ["near" if role.begins_with("near") else "far", family]
		var foot_key := "%s_foot" % role
		var bend_direction: float = 1.0 if family == "front" else -1.0
		var solution: Dictionary = TwoBoneIKScript.solve(pose[hip_key], pose[foot_key], upper_length, lower_length, bend_direction)
		solution["distance"] = Vector2(pose[hip_key]).distance_to(pose[foot_key])
		solution["bend_direction"] = bend_direction
		pose["%s_ik" % role] = solution


func _base_pose() -> Dictionary:
	var body_center := Vector2(0.0, round(-_genome.leg_length - _genome.body_height * 0.38 + _genome.back_slope))
	var hip_spread: float = round(_genome.body_length * 0.32)
	var hip_y: float = round(body_center.y + _genome.body_height * 0.18)
	var foot_spread: float = round(_genome.body_length * 0.4 * _genome.stance_width)
	var head_offset := Vector2.ZERO
	var tail_lift: float = 0.0
	match String(_genome.posture):
		"alert": head_offset = Vector2(0, -2); tail_lift = 0.38
		"curious": head_offset = Vector2(3, 1); tail_lift = 0.05
		"relaxed": head_offset = Vector2(-1, 2); tail_lift = -0.25
		"proud": head_offset = Vector2(1, -2); tail_lift = 0.5
	var tail_root := Vector2(round(-_genome.body_length * 0.45), round(body_center.y - _genome.body_height * 0.02))
	return {
		"body_anchor": body_center, "head_anchor": Vector2(round(hip_spread + _genome.head_size * 0.35), round(body_center.y - _genome.body_height * 0.08)) + head_offset,
		"front_hip": Vector2(hip_spread, hip_y), "rear_hip": Vector2(-hip_spread, hip_y),
		"far_front_hip": Vector2(hip_spread - 2, hip_y - 1), "far_rear_hip": Vector2(-hip_spread + 2, hip_y - 1),
		"near_front_hip": Vector2(hip_spread + 2, hip_y + 1), "near_rear_hip": Vector2(-hip_spread - 2, hip_y + 1),
		"near_front_foot": Vector2(foot_spread + 3, 0), "near_rear_foot": Vector2(-foot_spread - 3, 0),
		"far_front_foot": Vector2(foot_spread - 3, -1), "far_rear_foot": Vector2(-foot_spread + 3, -1),
		"tail_root": tail_root, "tail_lift": tail_lift, "ground_y": 0.0, "root_world_x": 0.0,
		"torso_height_scale": 1.0, "chest_depth_scale": 1.0, "ear_offset": 0.0,
	}


func _preferred_local_foot(key: String) -> Vector2:
	return _base_pose()["%s_foot" % key]


func _phase_offset(key: String) -> float:
	return 0.0 if key in ["near_front", "far_rear"] else 0.5


func _state_for_phase(phase: float) -> String:
	if phase < 0.12: return STATE_LIFT
	if phase < 0.40: return STATE_SWING
	if phase < 0.52: return STATE_PLANT
	return STATE_STANCE


func _state_progress(phase: float, state: String) -> float:
	match state:
		STATE_LIFT: return phase / 0.12
		STATE_SWING: return (phase - 0.12) / 0.28
		STATE_PLANT: return (phase - 0.40) / 0.12
		_: return (phase - 0.52) / 0.48


func _smoothstep(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _apply_treadmill_feet(pose: Dictionary, phase: float) -> void:
	_apply_treadmill_foot(pose, "near_front_foot", phase)
	_apply_treadmill_foot(pose, "far_rear_foot", phase)
	_apply_treadmill_foot(pose, "far_front_foot", phase + PI)
	_apply_treadmill_foot(pose, "near_rear_foot", phase + PI)


func _apply_treadmill_foot(pose: Dictionary, key: String, phase: float) -> void:
	var swing: float = sin(phase)
	if swing > 0.0:
		pose[key].y -= swing * 3.2
		pose[key].x += -cos(phase) * 2.4


func _apply_body_motion(pose: Dictionary, delta: Vector2) -> void:
	for key: String in ["body_anchor", "front_hip", "rear_hip", "far_front_hip", "far_rear_hip", "near_front_hip", "near_rear_hip", "tail_root"]:
		pose[key] = Vector2(pose[key]) + delta
	pose.head_anchor = Vector2(pose.head_anchor) + delta


func _apply_tail_follow(pose: Dictionary, phase: float, body_delta: Vector2, gait: String) -> void:
	var root: Vector2 = pose.tail_root
	var lagged_phase: float = phase - (0.85 if gait in [GAIT_WALKING, GAIT_PLANTED] else 0.55)
	var follow: float = sin(lagged_phase) * (1.7 if gait in [GAIT_WALKING, GAIT_PLANTED] else 0.55) - body_delta.y * 0.35
	var tip := root + Vector2(-_genome.tail_length, -_genome.tail_length * float(pose.tail_lift) + follow)
	pose.tail_mid = root.lerp(tip, 0.52) + Vector2(0, follow * 0.35)
	pose.tail_tip = tip
