extends RefCounted
class_name ResourceVisualDefinition

## Purpose: Central visual metadata for generated resource kinds.
## Responsibility: Map stable resource-kind ids to replaceable scene/icon paths and procedural profiles.
## Assumption: Yield, depletion, cell identity, and stockpile type remain outside this presentation registry.

const DEFINITIONS := {
	"tree": {
		"id": "tree",
		"scene_path": "res://scenes/entities/Tree.tscn",
		"icon_path": "",
		"procedural_profile_id": "tree",
		"placeholder_visual_id": "tree_polygon",
	},
	"rock": {
		"id": "rock",
		"scene_path": "res://scenes/entities/Rock.tscn",
		"icon_path": "",
		"procedural_profile_id": "rock",
		"placeholder_visual_id": "rock_polygon",
	},
	"berry_bush": {
		"id": "berry_bush",
		"scene_path": "res://scenes/entities/BerryBush.tscn",
		"icon_path": "",
		"procedural_profile_id": "none",
		"placeholder_visual_id": "berry_bush_polygon",
	},
}


static func has_definition(resource_kind: String) -> bool:
	return DEFINITIONS.has(resource_kind)


static func get_definition(resource_kind: String) -> Dictionary:
	if not has_definition(resource_kind):
		return {}
	return DEFINITIONS[resource_kind].duplicate(true)
