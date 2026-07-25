class_name CreatureDefinition
extends Resource

## Immutable authored constraints for one presentation-only quadruped body plan.

@export var definition_id: StringName = &"small_quadruped"
@export var body_length_range := Vector2i(20, 32)
@export var body_height_range := Vector2i(10, 17)
@export var head_size_range := Vector2i(7, 12)
@export var leg_length_range := Vector2i(8, 15)
@export var leg_thickness_range := Vector2i(2, 5)
@export var tail_length_range := Vector2i(8, 22)
@export_range(0.0, 1.0, 0.01) var tail_probability: float = 0.65
@export var body_colors: Array[Color] = []
@export var detail_colors: Array[Color] = []
@export var ear_profiles := PackedStringArray(["round", "pointed", "long"])
@export var body_profiles := PackedStringArray(["lean", "neutral", "stocky", "heavy_front", "heavy_rear"])
@export var posture_profiles := PackedStringArray(["neutral", "alert", "curious", "relaxed", "proud"])
@export var torso_taper_range := Vector2(-0.22, 0.22)
@export var chest_depth_range := Vector2(0.82, 1.25)
@export var hip_volume_range := Vector2(0.82, 1.24)
@export var stance_width_range := Vector2(0.9, 1.18)
@export var back_curve_range := Vector2(-0.12, 0.12)
@export var belly_curve_range := Vector2(-0.12, 0.16)
@export var shoulder_slope_range := Vector2(-0.1, 0.12)
@export var rump_slope_range := Vector2(-0.1, 0.12)
@export var neck_thickness_range := Vector2(0.65, 1.15)


func is_valid() -> bool:
	return not definition_id.is_empty() \
		and _valid_range(body_length_range) \
		and _valid_range(body_height_range) \
		and _valid_range(head_size_range) \
		and _valid_range(leg_length_range) \
		and _valid_range(leg_thickness_range) \
		and _valid_range(tail_length_range) \
		and not body_profiles.is_empty() \
		and not posture_profiles.is_empty() \
		and _valid_float_range(torso_taper_range) \
		and _valid_float_range(chest_depth_range) \
		and _valid_float_range(hip_volume_range) \
		and _valid_float_range(stance_width_range) \
		and _valid_float_range(back_curve_range) \
		and _valid_float_range(belly_curve_range) \
		and _valid_float_range(shoulder_slope_range) \
		and _valid_float_range(rump_slope_range) \
		and _valid_float_range(neck_thickness_range)


func _valid_range(value_range: Vector2i) -> bool:
	return value_range.x > 0 and value_range.y >= value_range.x


func _valid_float_range(value_range: Vector2) -> bool:
	return value_range.y >= value_range.x
