extends RefCounted
class_name PropVisualConfig

const ProcRng = preload("res://scripts/procgen/proc_rng.gd")
const RockProfiles = preload("res://scripts/procgen/rock_profiles.gd")
const TreeProfiles = preload("res://scripts/procgen/tree_profiles.gd")
const ResourceVisualDefinitionRef = preload("res://scripts/world/props/resource_visual_definition.gd")

static func resolve_rock_sprite_size(size_tier: String, small_size: int, medium_size: int, large_size: int) -> int:
	return RockProfiles.resolve_sprite_size(size_tier, small_size, medium_size, large_size)

static func build_resource_visual_config(spawn_data: Dictionary, chunk_coord: Vector2i, chunk_size: int, world_seed: int, use_procedural_tree_sprites: bool, use_procedural_rock_sprites: bool, tree_variant_cap: int, rock_variant_cap: int, tree_large_size: int, rock_small_size: int, rock_medium_size: int, rock_large_size: int) -> Dictionary:
	var scene_key: String = String(spawn_data["scene"])
	var visual_definition: Dictionary = ResourceVisualDefinitionRef.get_definition(scene_key)
	var procedural_profile_id: String = String(visual_definition.get("procedural_profile_id", "none"))
	var terrain_tag: String = String(spawn_data.get("terrain", ""))
	var use_procedural: bool = (procedural_profile_id == "tree" and use_procedural_tree_sprites) or (procedural_profile_id == "rock" and use_procedural_rock_sprites)
	var local_cell: Vector2i = spawn_data["cell"] - chunk_coord * chunk_size
	var full_seed: int = ProcRng.derive_resource_seed(chunk_coord, local_cell, world_seed, scene_key)
	var visual_config: Dictionary = {
		"use_procedural_sprite": use_procedural,
		"visual_definition_id": scene_key,
		"placeholder_visual_id": String(visual_definition.get("placeholder_visual_id", "")),
		"icon_path": String(visual_definition.get("icon_path", "")),
		"procedural_profile_id": procedural_profile_id,
		"procedural_sprite_kind": procedural_profile_id if use_procedural else "none",
		"procedural_seed": full_seed,
		"procedural_variant_cap": 0,
		"procedural_terrain_tag": "",
		"procedural_size_tier": "medium",
		"procedural_sprite_size": 20,
		"procedural_archetype": "",
	}
	if procedural_profile_id == "tree":
		visual_config["procedural_variant_cap"] = tree_variant_cap
		visual_config["procedural_terrain_tag"] = terrain_tag
		# Keep the active tree baseline explicit: runtime trees stay on the large tier only.
		visual_config["procedural_size_tier"] = TreeProfiles.get_active_runtime_size_tier()
		visual_config["procedural_sprite_size"] = tree_large_size
		visual_config["procedural_archetype"] = TreeProfiles.resolve_archetype(full_seed, "", String(visual_config["procedural_terrain_tag"]))
	elif procedural_profile_id == "rock":
		visual_config["procedural_variant_cap"] = rock_variant_cap
		visual_config["procedural_terrain_tag"] = terrain_tag
		# Keep the active rock baseline explicit: runtime rocks stay on medium/large tiers only.
		visual_config["procedural_size_tier"] = RockProfiles.get_runtime_size_tier(full_seed, String(visual_config["procedural_terrain_tag"]))
		visual_config["procedural_sprite_size"] = resolve_rock_sprite_size(String(visual_config["procedural_size_tier"]), rock_small_size, rock_medium_size, rock_large_size)
		visual_config["procedural_archetype"] = RockProfiles.resolve_archetype(full_seed, "", String(visual_config["procedural_terrain_tag"]))
	return visual_config
