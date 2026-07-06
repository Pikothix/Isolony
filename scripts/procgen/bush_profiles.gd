extends RefCounted
class_name BushProfiles

## Purpose: Define presentation-only berry-bush silhouettes and palettes.
## Responsibility: Centralize deterministic bush visual choices for ProcBushes.
## Assumption: Profiles never represent resource state, yield, or depletion.

const SUPPORTED_ARCHETYPES: Array[String] = ["rounded", "wide", "upright"]
const FOLIAGE_BY_TERRAIN := {
	"GRASS": [[38, 112, 48], [45, 126, 52], [56, 134, 48]],
	"DARK_DIRT": [[48, 105, 42], [62, 116, 48], [72, 124, 52]],
	"MUD": [[38, 91, 48], [47, 102, 55], [57, 108, 52]],
	"default": [[40, 112, 46], [52, 126, 50], [62, 132, 48]],
}
const BERRY_PALETTES: Array = [
	[[164, 20, 58], [220, 44, 78]],
	[[76, 31, 158], [132, 63, 210]],
	[[28, 76, 166], [52, 126, 224]],
	[[178, 58, 24], [236, 104, 36]],
]
const BERRY_COLOR_NAMES: Array[String] = ["Red", "Purple", "Blue", "Orange"]


static func resolve_archetype(seed: int, requested: String) -> String:
	if requested in SUPPORTED_ARCHETYPES:
		return requested
	return SUPPORTED_ARCHETYPES[abs(seed) % SUPPORTED_ARCHETYPES.size()]


static func get_foliage_bases(terrain_tag: String) -> Array:
	return FOLIAGE_BY_TERRAIN.get(terrain_tag, FOLIAGE_BY_TERRAIN["default"])
