extends RefCounted
class_name InteriorTerrainSource

## Purpose: Convert simulation-owned interior instances into transient terrain chunk projections.
## Responsibility: Build cave-local tile info from immutable definitions without owning runtime state.
## Assumption: Interior terrain is read-only in this vertical slice; mined cell deltas need a future simulation owner.

const CaveDefinitionRef = preload("res://scripts/interiors/cave_definition.gd")
const TerrainConfigRef = preload("res://scripts/world/terrain_config.gd")

const FLOOR_TERRAIN := "STONE"
const WALL_TERRAIN := "ROCK_WALL"


static func generate_chunk(interior: Dictionary, chunk_coord: Vector2i, chunk_size: int) -> Dictionary:
	var tiles: Array[Dictionary] = []
	var tile_lookup: Dictionary = {}
	var walkable_cells: Array[Vector2i] = []
	var interior_type: String = String(interior.get("interior_type", ""))
	if interior_type.is_empty() or not bool(interior.get("enabled", false)) or not bool(interior.get("open", false)):
		return _build_chunk_result(chunk_coord, tiles, tile_lookup, walkable_cells)
	var chunk_rect := Rect2i(chunk_coord * chunk_size, Vector2i.ONE * chunk_size)
	for cell: Vector2i in CaveDefinitionRef.get_floor_cells(interior_type):
		if not chunk_rect.has_point(cell):
			continue
		var tile_info: Dictionary = _build_tile_info(cell, FLOOR_TERRAIN)
		tiles.append(tile_info)
		tile_lookup[cell] = tile_info
		walkable_cells.append(cell)
	for cell: Vector2i in CaveDefinitionRef.get_wall_cells(interior_type):
		if not chunk_rect.has_point(cell):
			continue
		var tile_info: Dictionary = _build_tile_info(cell, WALL_TERRAIN)
		tiles.append(tile_info)
		tile_lookup[cell] = tile_info
	return _build_chunk_result(chunk_coord, tiles, tile_lookup, walkable_cells)


static func get_tile_info(interior: Dictionary, cell: Vector2i) -> Dictionary:
	var interior_type: String = String(interior.get("interior_type", ""))
	if interior_type.is_empty() or not bool(interior.get("enabled", false)) or not bool(interior.get("open", false)):
		return {}
	if CaveDefinitionRef.is_floor_cell(interior_type, cell):
		return _build_tile_info(cell, FLOOR_TERRAIN)
	if CaveDefinitionRef.is_wall_cell(interior_type, cell):
		return _build_tile_info(cell, WALL_TERRAIN)
	return {}


static func get_wall_cells(interior: Dictionary) -> Array[Vector2i]:
	var interior_type: String = String(interior.get("interior_type", ""))
	if interior_type.is_empty() or not bool(interior.get("enabled", false)) or not bool(interior.get("open", false)):
		return []
	return CaveDefinitionRef.get_wall_cells(interior_type)


static func _build_chunk_result(chunk_coord: Vector2i, tiles: Array[Dictionary], tile_lookup: Dictionary, walkable_cells: Array[Vector2i]) -> Dictionary:
	return {
		"chunk_coord": chunk_coord,
		"tiles": tiles,
		"tile_lookup": tile_lookup,
		"walkable_cells": walkable_cells,
		"resources": [],
	}


static func _build_tile_info(cell: Vector2i, terrain_name: String) -> Dictionary:
	return {
		"cell": cell,
		"terrain": terrain_name,
		"atlas_coords": TerrainConfigRef.get_atlas_coords(terrain_name),
		"source_id": TerrainConfigRef.TILE_SOURCE_ID,
		"walkable": TerrainConfigRef.is_walkable(terrain_name),
		"mineable": false,
		"elevation": 0,
		"height": 0.0,
		"moisture": 0.0,
		"terrain_detail": 0.0,
	}
