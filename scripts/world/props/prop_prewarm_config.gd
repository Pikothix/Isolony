extends RefCounted
class_name PropPrewarmConfig

const RockProfiles = preload("res://scripts/procgen/rock_profiles.gd")
const TreeProfiles = preload("res://scripts/procgen/tree_profiles.gd")

static func get_rock_size_map(rock_small_size: int, rock_medium_size: int, rock_large_size: int) -> Dictionary:
	return RockProfiles.get_size_map(rock_small_size, rock_medium_size, rock_large_size)

static func get_tree_prewarm_archetypes() -> PackedStringArray:
	return TreeProfiles.get_active_prewarm_archetypes()

static func get_tree_prewarm_terrain_tags() -> PackedStringArray:
	return TreeProfiles.get_active_prewarm_terrain_tags()

static func get_tree_active_size_tiers() -> PackedStringArray:
	return TreeProfiles.get_active_runtime_size_tiers()

static func get_rock_prewarm_archetypes() -> PackedStringArray:
	return RockProfiles.get_active_prewarm_archetypes()

static func get_rock_prewarm_terrain_tags() -> PackedStringArray:
	return RockProfiles.get_active_prewarm_terrain_tags()

static func get_rock_active_size_tiers() -> PackedStringArray:
	return RockProfiles.get_active_runtime_size_tiers()

static func get_tree_request(variant_cap: int, tree_large_size: int) -> Dictionary:
	# Tree prewarm intentionally mirrors the live runtime baseline to keep startup cost bounded.
	return {
		"kind": "tree",
		"variant_cap": variant_cap,
		"archetypes": get_tree_prewarm_archetypes(),
		"terrain_tags": get_tree_prewarm_terrain_tags(),
		"size_tiers": get_tree_active_size_tiers(),
		"size_map": TreeProfiles.get_active_runtime_size_map(tree_large_size),
	}

static func get_rock_request(variant_cap: int, rock_small_size: int, rock_medium_size: int, rock_large_size: int) -> Dictionary:
	# Rock prewarm intentionally mirrors the live runtime baseline to keep startup cost bounded.
	return {
		"kind": "rock",
		"variant_cap": variant_cap,
		"archetypes": get_rock_prewarm_archetypes(),
		"terrain_tags": get_rock_prewarm_terrain_tags(),
		"size_tiers": get_rock_active_size_tiers(),
		"size_map": get_rock_size_map(rock_small_size, rock_medium_size, rock_large_size),
	}
