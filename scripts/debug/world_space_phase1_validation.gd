extends SceneTree

## Purpose: Focused headless validation for the retained streamed-world WorldSpace identity seam.
## Responsibility: Verify colonist import policy and WorldSpace-aware local path contracts.
## Assumption: Surface always exists; other ids require a WorldState-owned interior.

const ChunkManagerScript = preload("res://scripts/world/chunk_manager.gd")
const ColonistScript = preload("res://scripts/entities/colonist.gd")
const ColonistManagerScript = preload("res://scripts/entities/colonist_manager.gd")
const ReachabilityQueryRef = preload("res://scripts/world/reachability_query.gd")
const SaveGameServiceScript = preload("res://scripts/simulation/save_game_service.gd")

var _failures: Array[String] = []


class WorldStateStub extends Node:
	func get_construction_site_at_cell(_cell: Vector2i, _world_space_id: String = ChunkManager.SURFACE_WORLD_SPACE_ID) -> Dictionary:
		return {}

	func get_interior_for_world_space(world_space_id: String) -> Dictionary:
		return {"interior_id": "cave_0001", "world_space_id": world_space_id} if world_space_id == "cave_0001" else {}


func _init() -> void:
	_run()


func _run() -> void:
	_validate_colonist_persistence()
	_validate_manager_import_preflight()
	_validate_save_service_preflight()
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
	unsupported_record["world_space_id"] = "missing_world_space"
	var unsupported_colonist: Colonist = ColonistScript.new() as Colonist
	unsupported_colonist.colonist_id = "validation_colonist"
	unsupported_colonist.current_cell = Vector2i(9, 9)
	var unsupported_result: Dictionary = unsupported_colonist.import_state(unsupported_record)
	_check(
		not bool(unsupported_result.get("ok", false)) and String(unsupported_result.get("reason", "")) == "unsupported_world_space_id",
		"unsupported colonist WorldSpace did not reject safely"
	)
	_check(unsupported_colonist.current_cell == Vector2i(9, 9), "rejected colonist import mutated live state")
	var empty_identity_record: Dictionary = exported.duplicate(true)
	empty_identity_record["world_space_id"] = ""
	var empty_identity_result: Dictionary = unsupported_colonist.import_state(empty_identity_record)
	_check(not bool(empty_identity_result.get("ok", false)) and String(empty_identity_result.get("reason", "")) == "unsupported_world_space_id", "explicit empty WorldSpace did not reject")

	var supported_record: Dictionary = exported.duplicate(true)
	supported_record["world_space_id"] = "cave_0001"
	var supported_colonist: Colonist = ColonistScript.new() as Colonist
	supported_colonist.colonist_id = "validation_colonist"
	supported_colonist.world_state = WorldStateStub.new()
	var supported_result: Dictionary = supported_colonist.import_state(supported_record)
	_check(bool(supported_result.get("ok", false)), "WorldState-backed interior colonist failed to import")
	_check(supported_colonist.current_world_space_id == "cave_0001", "supported interior identity was not preserved")
	var round_trip: Dictionary = supported_colonist.export_state()
	_check(String(round_trip.get("world_space_id", "")) == "cave_0001", "colonist WorldSpace identity drifted on round trip")
	_check(round_trip.get("cell", []) == supported_record.get("cell", []), "colonist local cell drifted on round trip")
	_check(round_trip.get("world_position", []) == supported_record.get("world_position", []), "colonist exact movement position drifted on round trip")
	var repeated_result: Dictionary = supported_colonist.import_state(round_trip)
	_check(bool(repeated_result.get("ok", false)) and supported_colonist.export_state() == round_trip, "repeated colonist import drifted authoritative state")
	colonist.free()
	legacy_colonist.free()
	unsupported_colonist.free()
	supported_colonist.world_state.free()
	supported_colonist.free()


func _validate_manager_import_preflight() -> void:
	var chunk_manager: ChunkManager = ChunkManagerScript.new() as ChunkManager
	var manager: ColonistManager = ColonistManagerScript.new() as ColonistManager
	manager.set("_chunk_manager", chunk_manager)
	var live_colonist: Colonist = ColonistScript.new() as Colonist
	live_colonist.colonist_id = "live_colonist"
	manager.add_child(live_colonist)
	var invalid_record: Dictionary = live_colonist.export_state()
	invalid_record["world_space_id"] = "missing_world_space"
	var result: Dictionary = manager.import_colonist_records([invalid_record])
	_check(not bool(result.get("ok", false)) and String(result.get("reason", "")) == "unsupported_world_space_id", "manager accepted an unsupported colonist WorldSpace")
	_check(live_colonist.get_parent() == manager, "manager replaced live population before WorldSpace validation")
	manager.free()
	chunk_manager.free()


func _validate_save_service_preflight() -> void:
	var service: SaveGameService = SaveGameServiceScript.new() as SaveGameService
	var unsupported_result: Dictionary = service.call("_validate_colonist_world_spaces", [{"world_space_id": "missing_world_space"}], {"interiors": []})
	_check(not bool(unsupported_result.get("ok", false)) and String(unsupported_result.get("reason", "")) == "unsupported_colonist_world_space_id", "save service did not preflight unsupported colonist WorldSpace")
	var supported_result: Dictionary = service.call("_validate_colonist_world_spaces", [{"world_space_id": "cave_0001"}], {"interiors": [{"world_space_id": "cave_0001"}]})
	_check(bool(supported_result.get("ok", false)), "save service rejected a colonist backed by an imported interior")


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
