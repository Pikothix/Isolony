class_name DiagnosticCreatureFactory
extends RefCounted

## Owns explicit bounded edge-case genomes for prototype diagnostics only.

const CreatureGenomeScript := preload("res://experimental/procedural_creature_research/creature_genome.gd")


static func create_specimens(definition: Resource) -> Array[Dictionary]:
	if definition == null or not definition.is_valid():
		return []
	var specs: Array[Dictionary] = [
		{"label": "short body / small head", "body_length": definition.body_length_range.x, "head_size": definition.head_size_range.x},
		{"label": "short body / large head", "body_length": definition.body_length_range.x, "head_size": definition.head_size_range.y},
		{"label": "long body / small head", "body_length": definition.body_length_range.y, "head_size": definition.head_size_range.x},
		{"label": "long body / largest head", "body_length": definition.body_length_range.y, "head_size": definition.head_size_range.y},
		{"label": "short / thin legs", "leg_length": definition.leg_length_range.x, "leg_thickness": definition.leg_thickness_range.x},
		{"label": "short / thick legs", "leg_length": definition.leg_length_range.x, "leg_thickness": definition.leg_thickness_range.y},
		{"label": "long / thin legs", "leg_length": definition.leg_length_range.y, "leg_thickness": definition.leg_thickness_range.x},
		{"label": "long / thick legs", "leg_length": definition.leg_length_range.y, "leg_thickness": definition.leg_thickness_range.y},
		{"label": "minimum tail", "has_tail": true, "tail_length": definition.tail_length_range.x},
		{"label": "maximum tail", "has_tail": true, "tail_length": definition.tail_length_range.y},
		{"label": "no tail", "has_tail": false, "tail_length": 0},
	]
	for ear_profile: String in definition.ear_profiles:
		specs.append({"label": "%s ears" % ear_profile, "ear_profile": StringName(ear_profile)})
	var result: Array[Dictionary] = []
	for index in range(specs.size()):
		result.append({"label": specs[index].label, "genome": _create_genome(definition, specs[index], index)})
	return result


static func is_within_bounds(genome: Resource, definition: Resource) -> bool:
	if genome == null or definition == null:
		return false
	return _in_range(genome.body_length, definition.body_length_range) \
		and _in_range(genome.body_height, definition.body_height_range) \
		and _in_range(genome.head_size, definition.head_size_range) \
		and _in_range(genome.leg_length, definition.leg_length_range) \
		and _in_range(genome.leg_thickness, definition.leg_thickness_range) \
		and (not genome.has_tail or _in_range(genome.tail_length, definition.tail_length_range)) \
		and (genome.has_tail or genome.tail_length == 0) \
		and String(genome.ear_profile) in definition.ear_profiles \
		and String(genome.body_profile) in definition.body_profiles \
		and String(genome.posture) in definition.posture_profiles \
		and _in_float_range(genome.torso_taper, definition.torso_taper_range) \
		and _in_float_range(genome.chest_depth, definition.chest_depth_range) \
		and _in_float_range(genome.hip_volume, definition.hip_volume_range) \
		and _in_float_range(genome.stance_width, definition.stance_width_range) \
		and _in_float_range(genome.back_curve, definition.back_curve_range) \
		and _in_float_range(genome.belly_curve, definition.belly_curve_range) \
		and _in_float_range(genome.shoulder_slope, definition.shoulder_slope_range) \
		and _in_float_range(genome.rump_slope, definition.rump_slope_range) \
		and _in_float_range(genome.neck_thickness, definition.neck_thickness_range)


static func _create_genome(definition: Resource, overrides: Dictionary, index: int) -> Resource:
	var genome := CreatureGenomeScript.new()
	genome.definition_id = definition.definition_id
	genome.seed = -1000 - index
	genome.body_length = overrides.get("body_length", _middle(definition.body_length_range))
	genome.body_height = overrides.get("body_height", _middle(definition.body_height_range))
	genome.head_size = overrides.get("head_size", _middle(definition.head_size_range))
	genome.leg_length = overrides.get("leg_length", _middle(definition.leg_length_range))
	genome.leg_thickness = overrides.get("leg_thickness", _middle(definition.leg_thickness_range))
	genome.body_profile = overrides.get("body_profile", StringName(definition.body_profiles[index % definition.body_profiles.size()]))
	genome.posture = overrides.get("posture", StringName(definition.posture_profiles[index % definition.posture_profiles.size()]))
	genome.torso_taper = overrides.get("torso_taper", 0.0)
	genome.chest_depth = overrides.get("chest_depth", 1.0)
	genome.hip_volume = overrides.get("hip_volume", 1.0)
	genome.stance_width = overrides.get("stance_width", 1.0)
	genome.muzzle_length = overrides.get("muzzle_length", 1.0)
	genome.back_curve = overrides.get("back_curve", 0.0)
	genome.belly_curve = overrides.get("belly_curve", 0.0)
	genome.shoulder_slope = overrides.get("shoulder_slope", 0.0)
	genome.rump_slope = overrides.get("rump_slope", 0.0)
	genome.neck_thickness = overrides.get("neck_thickness", 0.9)
	genome.has_tail = overrides.get("has_tail", true)
	genome.tail_length = overrides.get("tail_length", _middle(definition.tail_length_range)) if genome.has_tail else 0
	genome.ear_profile = overrides.get("ear_profile", StringName(definition.ear_profiles[index % definition.ear_profiles.size()] if not definition.ear_profiles.is_empty() else "round"))
	var palette_index: int = index % maxi(1, definition.body_colors.size())
	genome.body_color = definition.body_colors[palette_index] if not definition.body_colors.is_empty() else Color.WHITE
	genome.detail_color = definition.detail_colors[palette_index % definition.detail_colors.size()] if not definition.detail_colors.is_empty() else genome.body_color.darkened(0.45)
	return genome


static func _middle(value_range: Vector2i) -> int:
	return int(round((value_range.x + value_range.y) * 0.5))


static func _in_range(value: int, value_range: Vector2i) -> bool:
	return value >= value_range.x and value <= value_range.y


static func _in_float_range(value: float, value_range: Vector2) -> bool:
	return value >= value_range.x and value <= value_range.y
