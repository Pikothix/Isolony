extends RefCounted
class_name TerrainConfig

const TILE_SOURCE_ID := 2
const INVALID_ATLAS_COORDS := Vector2i(-1, -1)

const TERRAIN_DEFS := {
	"DIRT": {"tiles": [Vector2i(0, 0), Vector2i(0, 1)], "walkable": true},
	"DARK_DIRT": {"tiles": [Vector2i(0, 7)], "walkable": true},
	"TILLED_DIRT_DRY": {"tiles": [Vector2i(0, 4)], "walkable": true},
	"WATER": {"tiles": [Vector2i(0, 13), Vector2i(0, 14), Vector2i(0, 15)], "walkable": false},
	"GRASS": {"tiles": [Vector2i(1, 0), Vector2i(1, 1)], "walkable": true},
	"SAND": {"tiles": [Vector2i(2, 0), Vector2i(2, 1)], "walkable": true},
	"RED_SAND": {"tiles": [Vector2i(2, 2), Vector2i(2, 3)], "walkable": true},
	"STONE": {"tiles": [Vector2i(3, 0), Vector2i(3, 1)], "walkable": true},
	"GRAVEL": {"tiles": [Vector2i(3, 3)], "walkable": true},
	"ROCK_WALL": {"tiles": [Vector2i(3, 0), Vector2i(3, 1)], "walkable": false, "mineable": true},
	"MUD": {"tiles": [Vector2i(4, 1)], "walkable": true},
}

const TREE_TERRAINS := {
	"GRASS": true,
	"DARK_DIRT": true,
	"MUD": true,
}

const ROCK_TERRAINS := {
	"STONE": true,
	"GRAVEL": true,
}

const BERRY_BUSH_TERRAINS := {
	"GRASS": true,
	"DARK_DIRT": true,
	"MUD": true,
}

const DISPLAY_NAMES := {
	"DIRT": "Dirt",
	"DARK_DIRT": "Dark Dirt",
	"TILLED_DIRT_DRY": "Tilled Dirt",
	"WATER": "Water",
	"GRASS": "Grass",
	"SAND": "Sand",
	"RED_SAND": "Red Sand",
	"STONE": "Stone",
	"GRAVEL": "Gravel",
	"ROCK_WALL": "Rock Wall",
	"MUD": "Mud",
}

const SELECTABLE_TERRAINS := [
	"GRASS",
	"DIRT",
	"SAND",
	"STONE",
	"GRAVEL",
	"TILLED_DIRT_DRY",
]

## Purpose: Authoritative metadata access for terrain definitions used by world, placement, and UI code.
## Responsibility: Keep terrain atlas, display, walkability, and prop-support queries in one place.
## Assumption: Terrain classification still lives in WorldGenerator for this milestone.
static func has_terrain(terrain_name: String) -> bool:
	return TERRAIN_DEFS.has(terrain_name)

static func get_terrain_def(terrain_name: String) -> Dictionary:
	if not has_terrain(terrain_name):
		push_warning("TerrainConfig has no terrain named '%s'." % terrain_name)
		return {}
	return TERRAIN_DEFS[terrain_name].duplicate()

static func get_tiles(terrain_name: String) -> Array[Vector2i]:
	var terrain_def: Dictionary = get_terrain_def(terrain_name)
	if terrain_def.is_empty():
		return []
	var typed_tiles: Array[Vector2i] = []
	for tile: Variant in terrain_def.get("tiles", []):
		typed_tiles.append(tile as Vector2i)
	return typed_tiles

static func get_atlas_coords(terrain_name: String) -> Vector2i:
	var tiles: Array[Vector2i] = get_tiles(terrain_name)
	if tiles.is_empty():
		return INVALID_ATLAS_COORDS
	return tiles[0]

static func is_walkable(terrain_name: String) -> bool:
	var terrain_def: Dictionary = get_terrain_def(terrain_name)
	if terrain_def.is_empty():
		return false
	return bool(terrain_def.get("walkable", false))

static func is_mineable(terrain_name: String) -> bool:
	var terrain_def: Dictionary = get_terrain_def(terrain_name)
	if terrain_def.is_empty():
		return false
	return bool(terrain_def.get("mineable", false))

static func supports_trees(terrain_name: String) -> bool:
	return TREE_TERRAINS.has(terrain_name)

static func supports_rocks(terrain_name: String) -> bool:
	return ROCK_TERRAINS.has(terrain_name)

static func supports_berry_bushes(terrain_name: String) -> bool:
	return BERRY_BUSH_TERRAINS.has(terrain_name)

static func get_display_name(terrain_name: String) -> String:
	if terrain_name.is_empty():
		return "BLANK"
	if not has_terrain(terrain_name):
		push_warning("TerrainConfig has no display name for unknown terrain '%s'." % terrain_name)
		return ""
	return String(DISPLAY_NAMES.get(terrain_name, terrain_name.capitalize()))

static func get_selectable_terrains(include_blank: bool = true) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if include_blank:
		entries.append({"id": "", "label": "BLANK"})
	for terrain_name: String in SELECTABLE_TERRAINS:
		entries.append({"id": terrain_name, "label": get_display_name(terrain_name)})
	return entries
