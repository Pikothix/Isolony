extends RefCounted
class_name BuildingDefinition

## Purpose: Data-driven registry for placeable building definitions.
## Responsibility: Supply immutable construction metadata to simulation and presentation code.
## Assumption: Definitions are code-backed until an external content format is explicitly needed.

const DEFINITIONS := {
	"campfire": {
		"id": "campfire",
		"display_name": "Campfire",
		"architect_order": 10,
		"footprint": Vector2i(1, 1),
		"cost": {"wood": 5},
		"build_time": 10.0,
		"construction_visual_id": "campfire_scaffold",
		"completed_visual_id": "campfire_placeholder",
		"construction_scene_path": "",
		"completed_scene_path": "",
		"icon_path": "",
		"placeholder_palette": {
			"foundation_fill": Color(0.45, 0.31, 0.16, 0.58),
			"foundation_line": Color(0.62, 0.45, 0.24, 0.85),
			"scaffold_dark": Color(0.24, 0.12, 0.05),
			"scaffold_light": Color(0.31, 0.16, 0.06),
			"stone": Color(0.38, 0.38, 0.40),
			"flame_outer": Color(1.0, 0.36, 0.06, 0.95),
			"flame_inner": Color(1.0, 0.82, 0.18, 0.98),
		},
		"light_radius": 4.0,
		"warmth_radius": 3.0,
		"effect_tags": ["light", "warmth"],
	},
	"cabin": {
		"id": "cabin",
		"display_name": "Cabin",
		"architect_order": 20,
		"footprint": Vector2i(2, 2),
		"cost": {"wood": 20},
		"build_time": 30.0,
		"construction_visual_id": "cabin_scaffold",
		"completed_visual_id": "cabin_placeholder",
		"construction_scene_path": "",
		"completed_scene_path": "",
		"icon_path": "",
		"placeholder_palette": {
			"foundation_fill": Color(0.28, 0.20, 0.12, 0.85),
			"foundation_line": Color(0.48, 0.34, 0.18, 0.90),
			"scaffold_dark": Color(0.30, 0.16, 0.06),
			"scaffold_light": Color(0.52, 0.31, 0.12),
			"body": Color(0.55, 0.32, 0.14),
			"roof": Color(0.27, 0.13, 0.08),
			"door": Color(0.20, 0.11, 0.05),
			"window": Color(0.55, 0.76, 0.86, 0.80),
		},
		"shelter_radius": 2.0,
		"shelter_capacity": 2,
		"effect_tags": ["shelter"],
	},
	"storehouse": {
		"id": "storehouse",
		"display_name": "Storehouse",
		"architect_order": 30,
		"footprint": Vector2i(3, 2),
		"cost": {"wood": 30, "stone": 10},
		"build_time": 50.0,
		"construction_visual_id": "storehouse_scaffold",
		"completed_visual_id": "storehouse_placeholder",
		"construction_scene_path": "",
		"completed_scene_path": "",
		"icon_path": "",
		"placeholder_palette": {
			"foundation_fill": Color(0.31, 0.23, 0.14, 0.86),
			"foundation_line": Color(0.54, 0.39, 0.20, 0.95),
			"scaffold_dark": Color(0.32, 0.18, 0.08),
			"scaffold_light": Color(0.58, 0.38, 0.16),
			"body": Color(0.49, 0.31, 0.14),
			"roof": Color(0.24, 0.13, 0.07),
			"door": Color(0.18, 0.10, 0.05),
			"crate": Color(0.62, 0.48, 0.25),
			"crate_line": Color(0.30, 0.19, 0.08),
		},
		"storage_capacity": 100,
		"effect_tags": ["storage"],
	},
}

static func has_definition(building_id: String) -> bool:
	return DEFINITIONS.has(building_id)

static func get_definition(building_id: String) -> Dictionary:
	if not has_definition(building_id):
		return {}
	return DEFINITIONS[building_id].duplicate(true)

static func get_building_ids() -> Array[String]:
	## Presentation-safe deterministic registry order; callers receive no mutable definition references.
	var building_ids: Array[String] = []
	for building_id_value: Variant in DEFINITIONS.keys():
		building_ids.append(String(building_id_value))
	building_ids.sort_custom(func(first: String, second: String) -> bool:
		var first_order: int = int(DEFINITIONS[first].get("architect_order", 0))
		var second_order: int = int(DEFINITIONS[second].get("architect_order", 0))
		return first_order < second_order if first_order != second_order else first < second
	)
	return building_ids

static func get_visual_metadata(building_id: String) -> Dictionary:
	var definition: Dictionary = get_definition(building_id)
	if definition.is_empty():
		return {}
	return {
		"construction_visual_id": String(definition.get("construction_visual_id", "generic_scaffold")),
		"completed_visual_id": String(definition.get("completed_visual_id", "generic_placeholder")),
		"construction_scene_path": String(definition.get("construction_scene_path", "")),
		"completed_scene_path": String(definition.get("completed_scene_path", "")),
		"icon_path": String(definition.get("icon_path", "")),
		"placeholder_palette": definition.get("placeholder_palette", {}).duplicate(true),
	}
