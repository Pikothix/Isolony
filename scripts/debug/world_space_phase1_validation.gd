extends SceneTree

## Purpose: Focused headless validation for the surface-only WorldSpace identity seam.
## Responsibility: Verify colonist persistence defaults and WorldSpace-aware local path contracts.
## Assumption: Phase 1 supports only ChunkManager.SURFACE_WORLD_SPACE_ID.

const ChunkManagerScript = preload("res://scripts/world/chunk_manager.gd")
const ColonistScript = preload("res://scripts/entities/colonist.gd")
const ReachabilityQueryRef = preload("res://scripts/world/reachability_query.gd")

var _failures: Array[String] = []


class WorldStateStub extends Node:
	func get_construction_site_at_cell(_cell: Vector2i) -> Dictionary:
		return {}


func _init() -> void:
	_run()


func _run() -> void:
	_validate_colonist_persistence()
	_validate_world_space_path_contract()
	if _failures.is_empty():
		print("WORLD_SPACE_PHASE1_VALIDATION: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error("WORLD_SPACE_PHASE1_VALIDATION: %s" % failure)
	quit(1)


func _validate_colonist_persistence() -> void:
	var colonist: Colonist = ColonistScript.new() as Colonist
	colonist.colonist_id = "validation_colonist"
	_check(
		colonist.current_world_space_id == ChunkManager.SURFACE_WORLD_SPACE_ID,
		"new colonist did not default to surface"
	)
	var exported: Dictionary = colonist.export_state()
	_check(
		String(exported.get("world_space_id", "")) == ChunkManager.SURFACE_WORLD_SPACE_ID,
		"colonist export omitted the surface world_space_id"
	)

	var legacy_record: Dictionary = exported.duplicate(true)
	legacy_record.erase("world_space_id")
	var legacy_colonist: Colonist = ColonistScript.new() as Colonist
	legacy_colonist.colonist_id = "validation_colonist"
	var legacy_result: Dictionary = legacy_colonist.import_state(legacy_record)
	_check(bool(legacy_result.get("ok", false)), "legacy colonist record failed to import")
	_check(
		legacy_colonist.current_world_space_id == ChunkManager.SURFACE_WORLD_SPACE_ID,
		"legacy colonist record did not normalize to surface"
	)

	var unsupported_record: Dictionary = exported.duplicate(true)
	unsupported_record["world_space_id"] = "cave"
	var unsupported_colonist: Colonist = ColonistScript.new() as Colonist
	unsupported_colonist.colonist_id = "validation_colonist"
	var unsupported_result: Dictionary = unsupported_colonist.import_state(unsupported_record)
	_check(
		not bool(unsupported_result.get("ok", false)) and String(unsupported_result.get("reason", "")) == "unsupported_world_space_id",
		"unsupported colonist WorldSpace did not reject safely"
	)
	colonist.free()
	legacy_colonist.free()
	unsupported_colonist.free()


func _validate_world_space_path_contract() -> void:
	var chunk_manager: ChunkManager = ChunkManagerScript.new() as ChunkManager
	var world_state := WorldStateStub.new()
	var start_cell := Vector2i.ZERO
	var target_cell := Vector2i.RIGHT
	var tile_lookup := {
		start_cell: _build_walkable_tile(start_cell),
		target_cell: _build_walkable_tile(target_cell),
	}
	chunk_manager.set("_loaded_chunks", {
		Vector2i.ZERO: {
			"tile_lookup": tile_lookup,
			"resource_spawns": [],
		}
	})

	_check(
		chunk_manager.get_active_world_space_id() == ChunkManager.SURFACE_WORLD_SPACE_ID,
		"ChunkManager active WorldSpace seam was not fixed to surface"
	)
	var unsupported: Dictionary = ReachabilityQueryRef.find_path(
		chunk_manager,
		world_state,
		"cave",
		start_cell,
		target_cell
	)
	_check(
		not bool(unsupported.get("reachable", false)) and String(unsupported.get("reason", "")) == "unsupported_world_space_id",
		"unsupported path WorldSpace did not reject safely"
	)
	_check(String(unsupported.get("world_space_id", "")) == "cave", "rejected path result lost its WorldSpace identity")

	var surface: Dictionary = ReachabilityQueryRef.find_path(
		chunk_manager,
		world_state,
		ChunkManager.SURFACE_WORLD_SPACE_ID,
		start_cell,
		target_cell
	)
	_check(bool(surface.get("reachable", false)), "same-surface path was not reachable")
	_check(String(surface.get("world_space_id", "")) == ChunkManager.SURFACE_WORLD_SPACE_ID, "surface path result lost its WorldSpace identity")
	_check((surface.get("path", []) as Array) == [target_cell], "surface path contained unexpected cells")

	var colonist: Colonist = ColonistScript.new() as Colonist
	colonist.chunk_manager = chunk_manager
	colonist.world_state = world_state
	colonist.current_world_space_id = ChunkManager.SURFACE_WORLD_SPACE_ID
	colonist.current_cell = start_cell
	colonist.target_cell = target_cell
	var mismatched_path: Array[Vector2i] = [target_cell]
	colonist.set("_current_path", mismatched_path)
	colonist.set("_current_path_world_space_id", "cave")
	colonist.set("_path_index", 0)
	colonist.call("_move_towards_target", 0.1)
	_check(not colonist.has_active_path(), "live movement retained a path from another WorldSpace")
	_check(colonist.current_cell == start_cell, "live movement advanced along a path from another WorldSpace")
	colonist.free()
	chunk_manager.free()
	world_state.free()


func _build_walkable_tile(cell: Vector2i) -> Dictionary:
	return {
		"cell": cell,
		"terrain": "GRASS",
		"walkable": true,
		"mineable": false,
		"elevation": 0,
	}


func _check(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
