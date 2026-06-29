extends Node
class_name WorldGenerator

const PropSpawnHelpers = preload("res://scripts/world/props/prop_spawn_helpers.gd")
const TerrainConfigRef = preload("res://scripts/world/terrain_config.gd")

const CHUNK_SIZE := 16
const HEIGHT_FREQUENCY := 0.015
const MOISTURE_FREQUENCY := 0.017
const TERRAIN_DETAIL_FREQUENCY := 0.03
const LANDMASS_FREQUENCY := 0.0032
const TREE_DENSITY := 0.12
const ROCK_DENSITY := 0.09
const BERRY_BUSH_DENSITY := 0.055

@export var seed: int = 184729
@export_range(0.1, 160.0, 0.1) var terrain_scale: float = 1.0
@export_range(0.1, 16.0, 0.1) var landmass_scale: float = 1.0
@export var water_max: float = 0.24
@export var coast_max: float = 0.34
@export var stone_min: float = 0.78
@export var dry_max: float = 0.25
@export var wet_min: float = 0.72
@export var saturated_min: float = 0.86

var _height_noise: FastNoiseLite
var _moisture_noise: FastNoiseLite
var _terrain_detail_noise: FastNoiseLite
var _landmass_noise: FastNoiseLite

func _ready() -> void:
	_rebuild_noise()

func _rebuild_noise() -> void:
	_height_noise = _build_noise(seed, _scaled_terrain_frequency(HEIGHT_FREQUENCY), FastNoiseLite.FRACTAL_FBM)
	_moisture_noise = _build_noise(seed + 7919, _scaled_terrain_frequency(MOISTURE_FREQUENCY), FastNoiseLite.FRACTAL_FBM)
	_terrain_detail_noise = _build_noise(seed + 15401, TERRAIN_DETAIL_FREQUENCY, FastNoiseLite.FRACTAL_FBM)
	_landmass_noise = _build_noise(seed + 23159, _scaled_landmass_frequency(LANDMASS_FREQUENCY), FastNoiseLite.FRACTAL_FBM)

func _scaled_terrain_frequency(base_frequency: float) -> float:
	return base_frequency / maxf(terrain_scale, 0.0001)

func _scaled_landmass_frequency(base_frequency: float) -> float:
	return base_frequency / maxf(landmass_scale, 0.0001)

func _build_noise(noise_seed: int, frequency: float, fractal_type: int) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = fractal_type
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	return noise

func sample_climate(cell: Vector2i) -> Dictionary:
	var x: float = float(cell.x)
	var y: float = float(cell.y)
	var base_height: float = remap(_height_noise.get_noise_2d(x, y), -1.0, 1.0, 0.0, 1.0)
	var base_moisture: float = remap(_moisture_noise.get_noise_2d(x, y), -1.0, 1.0, 0.0, 1.0)
	var terrain_detail: float = remap(_terrain_detail_noise.get_noise_2d(x, y), -1.0, 1.0, 0.0, 1.0)
	var landmass_bias: float = remap(_landmass_noise.get_noise_2d(x, y), -1.0, 1.0, -0.16, 0.16)
	var height: float = clamp(base_height + landmass_bias, 0.0, 1.0)
	height = lerpf(height, smoothstep(0.06, 0.94, height), 0.35)
	var coastal_humidity: float = 1.0 - clamp(abs(height - coast_max) / 0.18, 0.0, 1.0)
	var upland_dryness: float = clamp((height - 0.62) / 0.28, 0.0, 1.0)
	var moisture: float = clamp(
		base_moisture + coastal_humidity * 0.10 - upland_dryness * 0.12 + landmass_bias * 0.08,
		0.0,
		1.0
	)
	return {
		"height": height,
		"moisture": moisture,
		"terrain_detail": terrain_detail,
	}

func get_tile_info(cell: Vector2i) -> Dictionary:
	var climate: Dictionary = sample_climate(cell)
	var elevation: int = _classify_elevation(float(climate.height), float(climate.terrain_detail))
	var terrain_name: String = _classify_terrain(float(climate.height), float(climate.moisture), float(climate.terrain_detail), elevation)
	return build_tile_info_for_terrain(cell, terrain_name, climate)

func build_tile_info_for_terrain(cell: Vector2i, terrain_name: String, climate: Dictionary = {}) -> Dictionary:
	if not TerrainConfigRef.has_terrain(terrain_name):
		push_error("WorldGenerator cannot build tile info for unknown terrain '%s'." % terrain_name)
		return {}
	var resolved_climate: Dictionary = climate if not climate.is_empty() else sample_climate(cell)
	var elevation: int = _classify_elevation(float(resolved_climate.height), float(resolved_climate.terrain_detail))
	var atlas_coords: Vector2i = _pick_tile_variant(_get_tiles(terrain_name), cell, 13)
	return {
		"cell": cell,
		"terrain": terrain_name,
		"atlas_coords": atlas_coords,
		"source_id": TerrainConfigRef.TILE_SOURCE_ID,
		"walkable": _is_walkable(terrain_name) and elevation < 2,
		"mineable": _is_mineable(terrain_name),
		"elevation": elevation,
		"height": resolved_climate.height,
		"moisture": resolved_climate.moisture,
		"terrain_detail": resolved_climate.terrain_detail,
	}

func generate_chunk(chunk_coord: Vector2i) -> Dictionary:
	var origin: Vector2i = chunk_coord * CHUNK_SIZE
	var tiles: Array[Dictionary] = []
	var walkable_cells: Array[Vector2i] = []
	var resources: Array[Dictionary] = []
	for y in range(CHUNK_SIZE):
		for x in range(CHUNK_SIZE):
			var cell: Vector2i = origin + Vector2i(x, y)
			var tile_info: Dictionary = get_tile_info(cell)
			tiles.append(tile_info)
			if tile_info.walkable:
				walkable_cells.append(cell)
			var resource_spawn: Dictionary = PropSpawnHelpers.build_resource_spawn(cell, tile_info, seed, TREE_DENSITY, ROCK_DENSITY, BERRY_BUSH_DENSITY)
			if not resource_spawn.is_empty():
				resources.append(resource_spawn)
	return {"chunk_coord": chunk_coord, "tiles": tiles, "walkable_cells": walkable_cells, "resources": resources}

func export_generation_state() -> Dictionary:
	return {
		"seed": seed,
		"generation_config": {
			"terrain_scale": terrain_scale,
			"landmass_scale": landmass_scale,
			"water_max": water_max,
			"coast_max": coast_max,
			"stone_min": stone_min,
			"dry_max": dry_max,
			"wet_min": wet_min,
			"saturated_min": saturated_min,
			"chunk_size": CHUNK_SIZE,
		},
	}

func import_generation_state(state: Dictionary) -> Dictionary:
	seed = int(state.get("seed", seed))
	var config: Dictionary = state.get("generation_config", {})
	terrain_scale = float(config.get("terrain_scale", terrain_scale))
	landmass_scale = float(config.get("landmass_scale", landmass_scale))
	water_max = float(config.get("water_max", water_max))
	coast_max = float(config.get("coast_max", coast_max))
	stone_min = float(config.get("stone_min", stone_min))
	dry_max = float(config.get("dry_max", dry_max))
	wet_min = float(config.get("wet_min", wet_min))
	saturated_min = float(config.get("saturated_min", saturated_min))
	_rebuild_noise()
	return {
		"ok": true,
		"reason": "imported",
	}

func is_cell_walkable(cell: Vector2i) -> bool:
	return get_tile_info(cell).walkable

func get_cell_elevation(cell: Vector2i) -> int:
	return int(get_tile_info(cell).get("elevation", 0))

func is_cell_mineable(cell: Vector2i) -> bool:
	return bool(get_tile_info(cell).get("mineable", false))

func _classify_elevation(height: float, terrain_detail: float) -> int:
	if height < coast_max:
		return 0
	if height >= stone_min + 0.08 or (height >= stone_min and terrain_detail > 0.78):
		return 2
	if height >= stone_min - 0.12 or terrain_detail > 0.9:
		return 1
	return 0

func _classify_terrain(height: float, moisture: float, terrain_detail: float, elevation: int) -> String:
	if height < water_max:
		return "WATER"
	if elevation >= 2:
		return "ROCK_WALL"
	if height < coast_max:
		if height > coast_max - 0.025 and terrain_detail > 0.9:
			return "GRAVEL"
		return "SAND"
	if height >= stone_min:
		if moisture < dry_max * 0.8 and terrain_detail > 0.68:
			return "GRAVEL"
		return "STONE"
	if moisture <= dry_max:
		if height > coast_max + 0.04 and terrain_detail > 0.88:
			return "DIRT"
		return "RED_SAND"
	if moisture >= saturated_min:
		return "MUD"
	if moisture >= wet_min:
		if height < stone_min - 0.08 and terrain_detail > 0.82:
			return "MUD"
		return "DARK_DIRT"
	if terrain_detail > 0.94 and moisture < wet_min - 0.08:
		return "DIRT"
	return "GRASS"

func _get_tiles(terrain_name: String) -> Array[Vector2i]:
	return TerrainConfigRef.get_tiles(terrain_name)

func _is_walkable(terrain_name: String) -> bool:
	return TerrainConfigRef.is_walkable(terrain_name)

func _is_mineable(terrain_name: String) -> bool:
	return TerrainConfigRef.is_mineable(terrain_name)

func _pick_tile_variant(tiles: Array[Vector2i], cell: Vector2i, salt: int) -> Vector2i:
	if tiles.size() == 1:
		return tiles[0]
	var index: int = _hash_coords(cell.x, cell.y, salt) % tiles.size()
	return tiles[index]

func _hash_coords(x: int, y: int, salt: int) -> int:
	var value: int = seed
	value ^= x * 374761393
	value ^= y * 668265263
	value ^= salt * 2147489
	value = int(value ^ (value >> 13))
	value *= 1274126177
	value = int(value ^ (value >> 16))
	return abs(value)
