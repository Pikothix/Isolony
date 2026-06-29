extends RefCounted
class_name TreeProfiles

const ProcPrimitives = preload("res://scripts/procgen/proc_primitives.gd")

# Active baseline: runtime trees currently use only the large tier, and prewarm mirrors that scope.
const ACTIVE_RUNTIME_SIZE_TIER: String = "large"
const ACTIVE_RUNTIME_SIZE_TIERS: Array[String] = ["large"]
const ACTIVE_PREWARM_ARCHETYPES: Array[String] = ["deciduous", "conifer", "dead"]
const ACTIVE_PREWARM_BIOME_TAGS: Array[String] = ["GRASS", "DARK_DIRT", "MUD"]

# Publicly supported tree controls.
const SUPPORTED_ARCHETYPES: Array[String] = ["deciduous", "conifer", "dead"]
const SUPPORTED_BIOME_TAGS: Array[String] = ["default", "GRASS", "DARK_DIRT", "MUD"]

# Available internally, but not part of the active runtime baseline.
const AVAILABLE_SIZE_TIERS: Array[String] = ["small", "medium", "large"]
const INTERNAL_ARCHETYPE_SAPLING: String = "sapling"

const TRUNK_PALETTES: Array = [[90, 58, 32], [100, 50, 25], [85, 70, 55], [60, 40, 20]]
const MEADOW_CANOPY_BASES: Array = [[65, 145, 50], [55, 135, 45], [75, 150, 40], [50, 140, 55]]
const DECIDUOUS_CANOPY_BASES: Array = [[65, 145, 50], [55, 135, 45], [75, 150, 40], [50, 140, 55], [80, 150, 30], [90, 145, 25], [35, 130, 60], [40, 135, 55], [55, 120, 35], [110, 130, 35], [95, 140, 30]]
const SWAMP_CANOPY_BASES: Array = [[40, 92, 44], [58, 94, 51], [68, 101, 50], [72, 92, 42]]
const HIGHLAND_CANOPY_BASES: Array = [[54, 122, 54], [66, 128, 58], [74, 134, 62], [82, 138, 68]]
const CONIFER_BASES: Array = [[30, 90, 30], [25, 85, 35], [35, 95, 25], [20, 82, 40], [40, 98, 22]]
const DEAD_BASES: Array = [[80, 70, 55], [75, 65, 50], [90, 80, 65], [72, 62, 48]]
const MOSS_RGBA: Array = [50, 70, 40, 180]

static func get_active_runtime_size_tier() -> String:
	return ACTIVE_RUNTIME_SIZE_TIER

static func get_active_runtime_size_tiers() -> PackedStringArray:
	return PackedStringArray(ACTIVE_RUNTIME_SIZE_TIERS)

static func get_active_prewarm_archetypes() -> PackedStringArray:
	return PackedStringArray(ACTIVE_PREWARM_ARCHETYPES)

static func get_active_prewarm_terrain_tags() -> PackedStringArray:
	return PackedStringArray(ACTIVE_PREWARM_BIOME_TAGS)

static func get_supported_archetypes() -> PackedStringArray:
	return PackedStringArray(SUPPORTED_ARCHETYPES)

static func get_supported_terrain_tags() -> PackedStringArray:
	return PackedStringArray(SUPPORTED_BIOME_TAGS)

static func get_active_runtime_size_map(tree_large_size: int) -> Dictionary:
	return {ACTIVE_RUNTIME_SIZE_TIER: tree_large_size}

static func get_size_scale_for_tier(size_tier: String) -> float:
	match size_tier:
		"small":
			return 0.82
		"large":
			return 1.28
		_:
			return 1.0

static func pick_canopy_base(rng, terrain_tag: String, archetype: String) -> Array:
	if archetype == "conifer":
		return ProcPrimitives.pick(rng, CONIFER_BASES)
	if archetype == "dead":
		return ProcPrimitives.pick(rng, DEAD_BASES)
	match terrain_tag:
		"GRASS":
			return ProcPrimitives.pick(rng, MEADOW_CANOPY_BASES)
		"MUD":
			return ProcPrimitives.pick(rng, SWAMP_CANOPY_BASES)
		"DARK_DIRT":
			return ProcPrimitives.pick(rng, HIGHLAND_CANOPY_BASES)
		_:
			return ProcPrimitives.pick(rng, DECIDUOUS_CANOPY_BASES)

static func resolve_archetype(seed: int, requested: String, terrain_tag: String) -> String:
	if requested != "":
		return requested
	var bucket: int = seed % 20
	match terrain_tag:
		"GRASS", "default":
			if bucket < 19:
				return "deciduous"
			return "conifer"
		"DARK_DIRT":
			if bucket < 19:
				return "conifer"
			return "dead"
		"MUD":
			if bucket < 18:
				return "deciduous"
			return "dead"
		_:
			if bucket < 15:
				return "deciduous"
			if bucket < 19:
				return "conifer"
			return "dead"
