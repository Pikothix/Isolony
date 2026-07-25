class_name CreatureGenomeGenerator
extends RefCounted

## Deterministically derives bounded presentation data from a definition and seed.

const CreatureGenomeScript := preload("res://experimental/procedural_creature_research/creature_genome.gd")


static func generate(definition: Resource, seed: int) -> Resource:
	if definition == null or not definition.is_valid():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var genome := CreatureGenomeScript.new()
	genome.definition_id = definition.definition_id
	genome.seed = seed

	# Controlled order: profile, proportions, shape, posture, head, legs, tail, palette, details.
	genome.body_profile = _pick_name(definition.body_profiles, rng, &"neutral")
	genome.body_length = rng.randi_range(definition.body_length_range.x, definition.body_length_range.y)
	genome.body_height = rng.randi_range(definition.body_height_range.x, definition.body_height_range.y)
	genome.torso_taper = rng.randf_range(definition.torso_taper_range.x, definition.torso_taper_range.y)
	genome.chest_depth = rng.randf_range(definition.chest_depth_range.x, definition.chest_depth_range.y)
	genome.hip_volume = rng.randf_range(definition.hip_volume_range.x, definition.hip_volume_range.y)
	genome.stance_width = rng.randf_range(definition.stance_width_range.x, definition.stance_width_range.y)
	_apply_profile_shape(genome, definition)
	genome.posture = _pick_name(definition.posture_profiles, rng, &"neutral")

	var body_length_ratio := inverse_lerp(float(definition.body_length_range.x), float(definition.body_length_range.y), float(genome.body_length))
	var head_max: int = definition.head_size_range.y - int(round(body_length_ratio * 2.0))
	if genome.body_profile == &"stocky":
		head_max = mini(head_max + 1, definition.head_size_range.y)
	head_max = maxi(head_max, definition.head_size_range.x)
	genome.head_size = rng.randi_range(definition.head_size_range.x, head_max)
	genome.muzzle_length = rng.randf_range(0.88, 1.14)
	genome.leg_length = rng.randi_range(definition.leg_length_range.x, definition.leg_length_range.y)
	var thickness_floor: int = definition.leg_thickness_range.x
	if genome.body_height >= definition.body_height_range.x + 4 or genome.body_profile in [&"stocky", &"heavy_front"]:
		thickness_floor = mini(thickness_floor + 1, definition.leg_thickness_range.y)
	genome.leg_thickness = rng.randi_range(thickness_floor, definition.leg_thickness_range.y)
	genome.has_tail = rng.randf() < definition.tail_probability
	var tail_max: int = maxi(definition.tail_length_range.x, mini(definition.tail_length_range.y, genome.body_length - 6))
	genome.tail_length = rng.randi_range(definition.tail_length_range.x, tail_max) if genome.has_tail else 0
	genome.ear_profile = _pick_name(definition.ear_profiles, rng, &"round")
	var palette_index := 0
	if not definition.body_colors.is_empty():
		palette_index = rng.randi_range(0, definition.body_colors.size() - 1)
		genome.body_color = definition.body_colors[palette_index]
	genome.detail_color = definition.detail_colors[palette_index % definition.detail_colors.size()] if not definition.detail_colors.is_empty() else genome.body_color.darkened(0.45)
	genome.muzzle_offset = rng.randi_range(-1, 1)
	genome.back_slope = rng.randi_range(-1, 1)
	# Cosmetic outline sampling is salted separately so primary generated traits remain stable.
	var outline_rng := RandomNumberGenerator.new()
	outline_rng.seed = seed ^ 0x5a17c9e3
	genome.back_curve = outline_rng.randf_range(definition.back_curve_range.x, definition.back_curve_range.y)
	genome.belly_curve = outline_rng.randf_range(definition.belly_curve_range.x, definition.belly_curve_range.y)
	genome.shoulder_slope = outline_rng.randf_range(definition.shoulder_slope_range.x, definition.shoulder_slope_range.y)
	genome.rump_slope = outline_rng.randf_range(definition.rump_slope_range.x, definition.rump_slope_range.y)
	genome.neck_thickness = outline_rng.randf_range(definition.neck_thickness_range.x, definition.neck_thickness_range.y)
	return genome


static func _apply_profile_shape(genome: Resource, definition: Resource) -> void:
	match String(genome.body_profile):
		"lean":
			genome.chest_depth *= 0.88
			genome.hip_volume *= 0.9
			genome.torso_taper = maxf(genome.torso_taper, 0.08)
		"stocky":
			genome.chest_depth *= 1.12
			genome.hip_volume *= 1.08
			genome.stance_width *= 1.08
		"heavy_front":
			genome.chest_depth *= 1.16
			genome.hip_volume *= 0.9
			genome.torso_taper = maxf(genome.torso_taper, 0.12)
		"heavy_rear":
			genome.chest_depth *= 0.9
			genome.hip_volume *= 1.16
			genome.torso_taper = minf(genome.torso_taper, -0.12)
	genome.torso_taper = clampf(genome.torso_taper, definition.torso_taper_range.x, definition.torso_taper_range.y)
	genome.chest_depth = clampf(genome.chest_depth, definition.chest_depth_range.x, definition.chest_depth_range.y)
	genome.hip_volume = clampf(genome.hip_volume, definition.hip_volume_range.x, definition.hip_volume_range.y)
	genome.stance_width = clampf(genome.stance_width, definition.stance_width_range.x, definition.stance_width_range.y)


static func _pick_name(options: PackedStringArray, rng: RandomNumberGenerator, fallback: StringName) -> StringName:
	if options.is_empty():
		return fallback
	return StringName(options[rng.randi_range(0, options.size() - 1)])
