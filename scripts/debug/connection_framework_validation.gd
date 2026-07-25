extends SceneTree

## Purpose: Focused headless validation for authoritative WorldSpace connections.
## Responsibility: Verify connection lifecycle, validation, and additive save-version-2 compatibility.
## Assumption: The only supported WorldSpace in this milestone is "surface".

const WorldStateScript = preload("res://scripts/simulation/world_state.gd")
const SaveGameServiceScript = preload("res://scripts/simulation/save_game_service.gd")

const SURFACE := "surface"
const CONNECTION_ID := "test_connection"

var _failures: Array[String] = []


class SaveOwnerStub extends Node:
	func export_generation_state() -> Dictionary:
		return {
			"seed": 1,
			"generation_config": {
				"terrain_scale": 1.0,
				"landmass_scale": 1.0,
				"chunk_size": 16,
			},
		}

	func import_generation_state(_state: Dictionary) -> Dictionary:
		return {"ok": true, "reason": "imported"}

	func export_world_deltas() -> Dictionary:
		return {}

	func import_world_deltas(_deltas: Dictionary) -> Dictionary:
		return {"ok": true, "reason": "imported"}

	func export_colonist_records() -> Array:
		return []

	func import_colonist_records(_records: Array) -> Dictionary:
		return {"ok": true, "reason": "imported"}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_connection_lifecycle()
	await _validate_save_compatibility()
	if _failures.is_empty():
		print("CONNECTION_FRAMEWORK_VALIDATION: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error("CONNECTION_FRAMEWORK_VALIDATION: %s" % failure)
	quit(1)


func _validate_connection_lifecycle() -> void:
	var world_state: WorldState = await _create_world_state()
	var register_result: Dictionary = world_state.request_register_connection(
		CONNECTION_ID,
		"test_passage",
		SURFACE,
		Vector2i(2, 3),
		SURFACE,
		Vector2i(8, 9),
		true,
		true
	)
	_check_ok(register_result, "valid connection registration")
	_check(world_state.has_connection(CONNECTION_ID), "registered connection lookup failed")
	var connection: Dictionary = world_state.get_connection(CONNECTION_ID)
	_check(String(connection.get("connection_type", "")) == "test_passage", "connection type was not retained")
	_check(bool(connection.get("bidirectional", false)), "bidirectional flag was not retained")
	_check(connection.get("from_cell", Vector2i.ZERO) == Vector2i(2, 3), "from cell was not retained")
	_check(connection.get("to_cell", Vector2i.ZERO) == Vector2i(8, 9), "to cell was not retained")

	var duplicate_result: Dictionary = world_state.request_register_connection(
		CONNECTION_ID, "other", SURFACE, Vector2i(10, 10), SURFACE, Vector2i(11, 11), false, false
	)
	_check(not bool(duplicate_result.get("ok", true)), "duplicate connection id was accepted")
	_check(String(world_state.get_connection(CONNECTION_ID).get("connection_type", "")) == "test_passage", "duplicate registration replaced the original")

	var directed_result: Dictionary = world_state.request_register_connection(
		"directed_connection", "test_passage", SURFACE, Vector2i(4, 4), SURFACE, Vector2i(5, 5), false, true
	)
	_check_ok(directed_result, "directed connection registration")
	_check(not bool(world_state.get_connection("directed_connection").get("bidirectional", true)), "false bidirectional flag was not retained")
	_check(world_state.get_connections_for_world_space(SURFACE).size() == 2, "WorldSpace query did not return both endpoint matches")
	_check(world_state.get_connections_for_world_space("cave").is_empty(), "unsupported WorldSpace query returned records")

	var unsupported_result: Dictionary = world_state.request_register_connection(
		"invalid_connection", "test_passage", "cave", Vector2i.ZERO, SURFACE, Vector2i.ONE
	)
	_check(not bool(unsupported_result.get("ok", true)), "unsupported WorldSpace registration was accepted")
	_check(not world_state.has_connection("invalid_connection"), "invalid connection mutated storage")

	var exported: Array[Dictionary] = world_state.export_connections()
	var imported_world_state: WorldState = await _create_world_state()
	_check_ok(imported_world_state.import_connections(exported), "connection import")
	_check(imported_world_state.has_connection(CONNECTION_ID), "imported connection lookup failed")
	_check(bool(imported_world_state.get_connection(CONNECTION_ID).get("bidirectional", false)), "import lost bidirectional flag")

	var invalid_export: Array = exported.duplicate(true)
	invalid_export[0]["to_world_space_id"] = "cave"
	var invalid_import_result: Dictionary = imported_world_state.import_connections(invalid_export)
	_check(not bool(invalid_import_result.get("ok", true)), "unsupported WorldSpace import was accepted")
	_check(imported_world_state.has_connection(CONNECTION_ID), "rejected import replaced existing connections")

	_check_ok(world_state.request_remove_connection(CONNECTION_ID), "connection removal")
	_check(not world_state.has_connection(CONNECTION_ID), "removed connection remained in storage")
	world_state.queue_free()
	imported_world_state.queue_free()


func _validate_save_compatibility() -> void:
	var world_state: WorldState = await _create_world_state()
	_check_ok(world_state.request_register_connection(
		CONNECTION_ID, "test_passage", SURFACE, Vector2i(1, 1), SURFACE, Vector2i(2, 2)
	), "save fixture registration")
	var owner := SaveOwnerStub.new()
	root.add_child(owner)
	var save_service := SaveGameServiceScript.new()
	var save_data: Dictionary = save_service.build_save_data(owner, world_state, owner, owner)
	_check(int(save_data.get("version", -1)) == 2, "save version changed")
	var deltas: Dictionary = save_data.get("deltas", {})
	_check(deltas.get("connections", []).size() == 1, "save export omitted connections")

	var restored_world_state: WorldState = await _create_world_state()
	_check_ok(save_service.apply_save_data(save_data, owner, restored_world_state, owner, owner), "connection save load")
	_check(restored_world_state.has_connection(CONNECTION_ID), "save load did not restore connection")

	var legacy_save: Dictionary = save_data.duplicate(true)
	(legacy_save["deltas"] as Dictionary).erase("connections")
	_check_ok(save_service.apply_save_data(legacy_save, owner, restored_world_state, owner, owner), "version-2 save without connections")
	_check(restored_world_state.get_connections_for_world_space(SURFACE).is_empty(), "missing connection section did not default to empty")
	world_state.queue_free()
	restored_world_state.queue_free()
	owner.queue_free()


func _create_world_state() -> WorldState:
	var world_state := WorldStateScript.new()
	root.add_child(world_state)
	await process_frame
	return world_state


func _check_ok(result: Dictionary, context: String) -> void:
	_check(bool(result.get("ok", false)), "%s failed: %s" % [context, String(result.get("reason", "missing_reason"))])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
