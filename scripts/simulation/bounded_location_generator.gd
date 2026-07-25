extends RefCounted
class_name BoundedLocationGenerator

const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const HashHelpers = preload("res://scripts/world/props/prop_spawn_helpers.gd")
const MAP_SIZE := Vector2i(32, 32)
const MAX_ATTEMPTS := 12

## Produces a deterministic, validated starter map. Mutable depletion is excluded.
func generate(game_seed: int, location_type := "general") -> Dictionary:
	for attempt in range(MAX_ATTEMPTS):
		var generated := _generate_attempt(game_seed + attempt * 104729, attempt, location_type)
		if bool(generated.get("valid", false)):
			generated["generation_config"]["attempt"] = attempt
			return generated
	return {}

func _generate_attempt(seed_value: int, attempt: int, location_type: String) -> Dictionary:
	var generator: Node = WorldGeneratorScript.new()
	generator.seed = seed_value; generator.terrain_scale = 0.55; generator.landmass_scale = 0.75; generator.call("_rebuild_noise")
	var terrain: Array[Dictionary] = []; var walkable: Array[Vector2i] = []
	for y in range(MAP_SIZE.y):
		for x in range(MAP_SIZE.x):
			var tile: Dictionary = generator.get_tile_info(Vector2i(x, y))
			terrain.append(tile)
			if bool(tile.get("walkable", false)): walkable.append(Vector2i(tile.cell))
	generator.free()
	walkable.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ah := HashHelpers.normalized_hash(a.x, a.y, seed_value, 911)
		var bh := HashHelpers.normalized_hash(b.x, b.y, seed_value, 911)
		return ah < bh if not is_equal_approx(ah, bh) else (a.y < b.y or (a.y == b.y and a.x < b.x)))
	if walkable.size() < 160: return {"valid": false}
	var spawn_cells := _select_spawn_cluster(walkable)
	if spawn_cells.size() != 3: return {"valid": false}
	var excluded: Dictionary = {}; for cell: Vector2i in spawn_cells: excluded[cell] = true
	var storage_cell := _nearest_free_walkable(walkable, spawn_cells[0], excluded); excluded[storage_cell] = true
	var candidates: Array[Vector2i] = []
	for cell: Vector2i in walkable:
		if not excluded.has(cell): candidates.append(cell)
	var resources: Array[Dictionary] = []
	var counts := _resource_counts(location_type)
	var cursor := 0
	for kind: String in counts:
		for _i in range(int(counts[kind])):
			if cursor >= candidates.size(): break
			resources.append(_resource_record(kind, candidates[cursor], seed_value)); cursor += 1
	resources.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.resource_id) < String(b.resource_id))
	return {"valid": resources.size() == 93, "map_size": MAP_SIZE, "terrain": terrain, "resources": resources, "spawn_cells": spawn_cells, "camp_storage_cell": storage_cell, "generation_seed": seed_value, "generation_config": {"bounds": Rect2i(Vector2i.ZERO, MAP_SIZE), "terrain_scale": 0.55, "landmass_scale": 0.75, "attempt": attempt}}

func _resource_counts(location_type: String) -> Dictionary:
	match location_type:
		"woodland": return {"tree": 48, "rock": 15, "fruit_tree": 12, "berry_bush": 10, "fruit_bush": 8}
		"rocky": return {"tree": 18, "rock": 52, "fruit_tree": 5, "berry_bush": 10, "fruit_bush": 8}
		"forage_rich": return {"tree": 25, "rock": 18, "fruit_tree": 14, "berry_bush": 20, "fruit_bush": 16}
		_: return {"tree": 34, "rock": 34, "fruit_tree": 7, "berry_bush": 10, "fruit_bush": 8}

func _select_spawn_cluster(walkable: Array[Vector2i]) -> Array[Vector2i]:
	var available: Dictionary = {}; for cell: Vector2i in walkable: available[cell] = true
	for centre: Vector2i in walkable:
		var result: Array[Vector2i] = [centre]
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i(1, 1)]:
			if available.has(centre + offset): result.append(centre + offset)
			if result.size() == 3: return result
	return []

func _nearest_free_walkable(cells: Array[Vector2i], origin: Vector2i, excluded: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1); var distance := 1 << 30
	for cell: Vector2i in cells:
		if excluded.has(cell): continue
		var candidate := absi(cell.x - origin.x) + absi(cell.y - origin.y)
		if candidate < distance or (candidate == distance and str(cell) < str(best)): best = cell; distance = candidate
	return best

func _resource_record(kind: String, cell: Vector2i, seed_value: int) -> Dictionary:
	var output := "wood" if kind in ["tree", "fruit_tree"] else ("stone" if kind == "rock" else "food")
	var ranges := {"tree": Vector2i(18, 30), "rock": Vector2i(14, 24), "berry_bush": Vector2i(5, 10), "fruit_bush": Vector2i(7, 12), "fruit_tree": Vector2i(10, 18)}
	var limits: Vector2i = ranges[kind]
	var deterministic := int(floor(HashHelpers.normalized_hash(cell.x, cell.y, seed_value, 1301) * float(limits.y - limits.x + 1))) + limits.x
	return {"resource_id": "%s:%d:%d" % [kind, cell.x, cell.y], "resource_kind": kind, "resource_type": output, "scene": "rock" if kind == "rock" else ("berry_bush" if kind in ["berry_bush", "fruit_bush"] else "tree"), "cell": cell, "yield": deterministic, "depleted": false, "fruit_harvested": false}
