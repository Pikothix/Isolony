class_name CreatureGenome
extends Resource

## Generated presentation parameters. Contains no simulation or pose state.

var definition_id: StringName = &""
var seed: int = 0
var body_length: int = 0
var body_height: int = 0
var head_size: int = 0
var leg_length: int = 0
var leg_thickness: int = 0
var body_color: Color = Color.WHITE
var detail_color: Color = Color.BLACK
var ear_profile: StringName = &"round"
var has_tail: bool = false
var tail_length: int = 0
var muzzle_offset: int = 0
var back_slope: int = 0
var body_profile: StringName = &"neutral"
var posture: StringName = &"neutral"
var torso_taper: float = 0.0
var chest_depth: float = 1.0
var hip_volume: float = 1.0
var stance_width: float = 1.0
var muzzle_length: float = 1.0
var back_curve: float = 0.0
var belly_curve: float = 0.0
var shoulder_slope: float = 0.0
var rump_slope: float = 0.0
var neck_thickness: float = 0.9


func to_dictionary() -> Dictionary:
	return {
		"definition_id": definition_id,
		"seed": seed,
		"body_length": body_length,
		"body_height": body_height,
		"head_size": head_size,
		"leg_length": leg_length,
		"leg_thickness": leg_thickness,
		"body_color": body_color,
		"detail_color": detail_color,
		"ear_profile": ear_profile,
		"has_tail": has_tail,
		"tail_length": tail_length,
		"muzzle_offset": muzzle_offset,
		"back_slope": back_slope,
		"body_profile": body_profile,
		"posture": posture,
		"torso_taper": snappedf(torso_taper, 0.001),
		"chest_depth": snappedf(chest_depth, 0.001),
		"hip_volume": snappedf(hip_volume, 0.001),
		"stance_width": snappedf(stance_width, 0.001),
		"muzzle_length": snappedf(muzzle_length, 0.001),
		"back_curve": snappedf(back_curve, 0.001),
		"belly_curve": snappedf(belly_curve, 0.001),
		"shoulder_slope": snappedf(shoulder_slope, 0.001),
		"rump_slope": snappedf(rump_slope, 0.001),
		"neck_thickness": snappedf(neck_thickness, 0.001),
	}.duplicate(true)


func debug_summary() -> String:
	return JSON.stringify(to_dictionary())
