class_name ModularCreatureSpriteSet
extends Resource

## Immutable authored texture references and attachment metadata for the modular renderer.

const REQUIRED_PARTS := [
	"body", "head", "front_upper_leg", "front_lower_leg", "rear_upper_leg", "rear_lower_leg",
	"foot", "ear_round", "ear_pointed", "ear_long", "tail_base", "tail_mid", "tail_tip", "shadow",
]

@export var set_id: StringName = &"small_quadruped_modular"
@export var north_oblique_parts: Dictionary = {}
@export var south_oblique_parts: Dictionary = {}
@export var part_pivots: Dictionary = {}
@export var default_part_scales: Dictionary = {}
@export var part_depth_biases: Dictionary = {}


func is_valid() -> bool:
	if set_id.is_empty():
		return false
	for part: String in REQUIRED_PARTS:
		if not north_oblique_parts.has(part) or north_oblique_parts[part] == null:
			return false
		if not south_oblique_parts.has(part) or south_oblique_parts[part] == null:
			return false
		if not part_pivots.has(part):
			return false
	return true


func get_parts_for_facing(facing: String) -> Dictionary:
	return (north_oblique_parts if facing in ["NE", "NW"] else south_oblique_parts).duplicate()


func should_mirror(facing: String) -> bool:
	return facing in ["SW", "NW"]


func get_pivot(part: String) -> Vector2:
	return part_pivots.get(part, Vector2.ZERO)
