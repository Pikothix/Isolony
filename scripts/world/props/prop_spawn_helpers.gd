extends RefCounted
class_name PropSpawnHelpers

const TerrainConfigRef = preload("res://scripts/world/terrain_config.gd")

# Terrain-specific density modifiers stay here so prop spawn tuning has one entry point.
static func tree_density_for_terrain(terrain: String, tree_density: float) -> float:
	match terrain:
		"GRASS":
			return tree_density * 0.95
		"MUD":
			return tree_density * 0.72
		"DARK_DIRT":
			return tree_density * 0.82
		"GRAVEL", "STONE":
			return 0.0
		_:
			return tree_density

static func rock_density_for_terrain(terrain: String, rock_density: float) -> float:
	match terrain:
		"GRAVEL":
			return rock_density * 1.1
		"STONE":
			return rock_density * 0.95
		_:
			return rock_density

static func berry_bush_density_for_terrain(terrain: String, berry_bush_density: float) -> float:
	match terrain:
		"GRASS":
			return berry_bush_density
		"DARK_DIRT":
			return berry_bush_density * 0.9
		"MUD":
			return berry_bush_density * 1.15
		_:
			return 0.0

static func build_resource_spawn(cell: Vector2i, tile_info: Dictionary, seed: int, tree_density: float, rock_density: float, berry_bush_density: float) -> Dictionary:
	if not tile_info.walkable:
		return {}
	var terrain: String = String(tile_info.terrain)
	# Trees and rocks intentionally share the same deterministic roll to preserve current exclusivity/order.
	var roll: float = normalized_hash(cell.x, cell.y, seed, 97)
	if TerrainConfigRef.supports_trees(terrain) and roll < tree_density_for_terrain(terrain, tree_density):
		return {"cell": cell, "scene": "tree", "resource_type": "wood", "amount": 8, "terrain": terrain}
	if TerrainConfigRef.supports_rocks(terrain) and roll < rock_density_for_terrain(terrain, rock_density):
		return {"cell": cell, "scene": "rock", "resource_type": "stone", "amount": 10, "terrain": terrain}
	# Bushes use a separate deterministic roll but remain exclusive with an already-selected tree/rock.
	var berry_roll: float = normalized_hash(cell.x, cell.y, seed, 211)
	if TerrainConfigRef.supports_berry_bushes(terrain) and berry_roll < berry_bush_density_for_terrain(terrain, berry_bush_density):
		return {"cell": cell, "scene": "berry_bush", "resource_type": "food", "amount": 6, "terrain": terrain}
	return {}

static func normalized_hash(x: int, y: int, seed: int, salt: int) -> float:
	return float(hash_coords(x, y, seed, salt) % 10000) / 10000.0

static func hash_coords(x: int, y: int, seed: int, salt: int) -> int:
	var value: int = seed
	value ^= x * 374761393
	value ^= y * 668265263
	value ^= salt * 2147489
	value = int(value ^ (value >> 13))
	value *= 1274126177
	value = int(value ^ (value >> 16))
	return abs(value)
