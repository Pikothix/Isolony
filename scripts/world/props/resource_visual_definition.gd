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
		"visual_variant": {
			"kind": "tree_fruit_overlay",
			"chance_percent": 28,
			"min_count": 3,
			"max_count": 7,
			"allowed_archetypes": ["deciduous"],
			"fallback_visual_size": Vector2(36.0, 38.0),
			"palettes": [
				[Color(0.82, 0.16, 0.12), Color(1.0, 0.38, 0.18)],
				[Color(0.92, 0.55, 0.08), Color(1.0, 0.78, 0.2)],
			],
		},
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
		"procedural_profile_id": "bush",
		"placeholder_visual_id": "berry_bush_polygon",
	},
}


static func has_definition(resource_kind: String) -> bool:
	return DEFINITIONS.has(resource_kind)


static func get_definition(resource_kind: String) -> Dictionary:
	if not has_definition(resource_kind):
		return {}
	return DEFINITIONS[resource_kind].duplicate(true)
