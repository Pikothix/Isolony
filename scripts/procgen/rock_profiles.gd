extends RefCounted
class_name RockProfiles

const ProcPrimitives = preload("res://scripts/procgen/proc_primitives.gd")

# Active baseline: runtime rocks currently use only medium/large tiers, and prewarm mirrors that scope.
const ACTIVE_PREWARM_ARCHETYPES: Array[String] = ["rounded", "flat", "blocky", "tall"]
const ACTIVE_PREWARM_BIOME_TAGS: Array[String] = ["STONE", "GRAVEL"]
const ACTIVE_RUNTIME_SIZE_TIERS: Array[String] = ["medium", "large"]

# Publicly supported rock controls.
const SUPPORTED_ARCHETYPES: Array[String] = ["rounded", "tall", "flat", "blocky"]
const SUPPORTED_BIOME_TAGS: Array[String] = ["default", "STONE", "GRAVEL"]

# Available internally, but not part of the current active runtime baseline.
const AVAILABLE_SIZE_TIERS: Array[String] = ["small", "medium", "large"]
const FUTURE_SURFACE_CLUE_NOTE: String = "Small rocks remain an inactive future-facing option for possible surface-clue/pebble usage."

const BOULDER_BASE_PALETTES: Array = [[152, 132, 112], [140, 120, 100], [130, 114, 94], [120, 128, 140], [110, 120, 134], [128, 130, 138], [136, 137, 141], [124, 126, 130], [114, 116, 120], [108, 114, 104], [122, 116, 108]]
const STONE_PALETTES: Array = [[118, 122, 130], [126, 128, 134], [110, 118, 126], [132, 134, 138]]
const GRAVEL_PALETTES: Array = [[146, 140, 132], [136, 132, 126], [122, 118, 114], [116, 124, 130]]
const LICHEN_PALETTE: Array = [[55, 72, 42, 140], [62, 78, 48, 130], [48, 65, 38, 120], [70, 80, 50, 110]]

static func get_active_prewarm_archetypes() -> PackedStringArray:
	return PackedStringArray(ACTIVE_PREWARM_ARCHETYPES)

static func get_active_prewarm_terrain_tags() -> PackedStringArray:
	return PackedStringArray(ACTIVE_PREWARM_BIOME_TAGS)

static func get_active_runtime_size_tiers() -> PackedStringArray:
	return PackedStringArray(ACTIVE_RUNTIME_SIZE_TIERS)

static func get_supported_archetypes() -> PackedStringArray:
	return PackedStringArray(SUPPORTED_ARCHETYPES)

static func get_supported_terrain_tags() -> PackedStringArray:
	return PackedStringArray(SUPPORTED_BIOME_TAGS)

static func get_lichen_palette() -> Array:
	return LICHEN_PALETTE

static func get_size_scale_for_tier(size_tier: String) -> float:
	match size_tier:
		"small":
			return 0.88
		"large":
			return 1.22
		_:
			return 1.0

static func get_runtime_size_tier(seed: int, terrain_tag: String) -> String:
	var roll: int = seed % 100
	if terrain_tag == "STONE" and roll < 18:
		return "large"
	return "medium"

static func get_size_map(rock_small_size: int, rock_medium_size: int, rock_large_size: int) -> Dictionary:
	return {"small": rock_small_size, "medium": rock_medium_size, "large": rock_large_size}

static func resolve_sprite_size(size_tier: String, small_size: int, medium_size: int, large_size: int) -> int:
	match size_tier:
		"small":
			return small_size
		"large":
			return large_size
		_:
			return medium_size

static func resolve_archetype(seed: int, requested: String, terrain_tag: String) -> String:
	if requested != "":
		return requested
	var roll: int = seed % 20
	if terrain_tag == "GRAVEL":
		if roll < 10:
			return "flat"
		if roll < 17:
			return "rounded"
		return "blocky"
	if terrain_tag == "STONE":
		if roll < 9:
			return "rounded"
		if roll < 15:
			return "blocky"
		if roll < 18:
			return "tall"
		return "flat"
	if roll < 7:
		return "rounded"
	if roll < 11:
		return "tall"
	if roll < 16:
		return "flat"
	return "blocky"

static func pick_palette_source(terrain_tag: String) -> Array:
	if terrain_tag == "GRAVEL":
		return GRAVEL_PALETTES
	if terrain_tag == "STONE":
		return STONE_PALETTES
	return BOULDER_BASE_PALETTES

static func pick_stone_colors(rng, terrain_tag: String) -> Array:
	var palette_source: Array = pick_palette_source(terrain_tag)
	var base: Array = ProcPrimitives.pick(rng, palette_source)
	var brightness_offset: int = rng.next_int(-18, 18)
	var temp_offset: int = rng.next_int(-8, 8)
	var min_channel: int = 70
	var max_channel: int = 190
	var body: Array = [
		ProcPrimitives.clamp_int(base[0] + brightness_offset - temp_offset, min_channel, max_channel),
		ProcPrimitives.clamp_int(base[1] + brightness_offset, min_channel, max_channel),
		ProcPrimitives.clamp_int(base[2] + brightness_offset + temp_offset, min_channel, max_channel + 10),
	]
	return [ProcPrimitives.shift_color(body, -36, -36, -34), body, ProcPrimitives.shift_color(body, 36, 36, 38)]
