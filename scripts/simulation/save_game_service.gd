extends RefCounted
class_name SaveGameService

const SAVE_VERSION := 2
const WINDOWED_COLONY_SAVE_VERSION := 4

## Purpose: Small, non-autoload persistence service for current world and colonist authority.
## Responsibility: Validate top-level save structure, serialize/deserialize versioned dictionaries, and coordinate state-owner import order, including harvest intent, zones, ground items, interiors, and WorldSpace connections.
## Assumption: Menus, slots, full scene reload, migration, and future systems remain outside this milestone.
func build_save_data(world_generator: Node, world_state: Node, chunk_manager: Node, colonist_manager: Node) -> Dictionary:
	var world_state_data: Dictionary = world_state.export_state()
	var deltas: Dictionary = chunk_manager.export_world_deltas()
	deltas["construction_sites"] = world_state_data.get("construction_sites", [])
	deltas["harvest_orders"] = world_state_data.get("harvest_orders", [])
	deltas["mining_orders"] = world_state_data.get("mining_orders", [])
	deltas["mined_terrain_deltas"] = world_state_data.get("mined_terrain_deltas", [])
	deltas["stockpile_zones"] = world_state_data.get("stockpile_zones", [])
	deltas["ground_items"] = world_state_data.get("ground_items", [])
	deltas["interiors"] = world_state_data.get("interiors", [])
	deltas["connections"] = world_state_data.get("connections", [])
	return {
		"version": SAVE_VERSION,
		"world": world_generator.export_generation_state(),
		"time": world_state_data.get("time", {}),
		"stockpile": world_state_data.get("stockpile", {}),
		"deltas": deltas,
		"colonists": colonist_manager.export_colonist_records(),
	}

func save_to_file(path: String, world_generator: Node, world_state: Node, chunk_manager: Node, colonist_manager: Node) -> Dictionary:
	var save_data: Dictionary = build_save_data(world_generator, world_state, chunk_manager, colonist_manager)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _build_result(false, "open_write_failed", {})
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	return _build_result(true, "saved", save_data)

func load_from_file(path: String, world_generator: Node, world_state: Node, chunk_manager: Node, colonist_manager: Node) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _build_result(false, "file_missing", {})
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _build_result(false, "open_read_failed", {})
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return _build_result(false, "invalid_json", {})
	return apply_save_data(parsed, world_generator, world_state, chunk_manager, colonist_manager)

func apply_save_data(save_data: Dictionary, world_generator: Node, world_state: Node, chunk_manager: Node, colonist_manager: Node) -> Dictionary:
	if int(save_data.get("version", -1)) != SAVE_VERSION:
		return _build_result(false, "unsupported_version", save_data)
	var structure_result: Dictionary = _validate_save_structure(save_data)
	if not bool(structure_result.get("ok", false)):
		return _build_result(false, String(structure_result.get("reason", "invalid_structure")), save_data)
	var colonist_records: Variant = save_data.get("colonists", null)
	var world_result: Dictionary = world_generator.import_generation_state(save_data.get("world", {}))
	if not bool(world_result.get("ok", false)):
		return _build_result(false, "world_%s" % String(world_result.get("reason", "failed")), save_data)
	var deltas: Dictionary = save_data.get("deltas", {})
	var world_state_result: Dictionary = world_state.import_state({
		"time": save_data.get("time", {}),
		"stockpile": save_data.get("stockpile", {}),
		"construction_sites": deltas.get("construction_sites", []),
		"harvest_orders": deltas.get("harvest_orders", []),
		"mining_orders": deltas.get("mining_orders", []),
		"mined_terrain_deltas": deltas.get("mined_terrain_deltas", []),
		"stockpile_zones": deltas.get("stockpile_zones", []),
		"ground_items": deltas.get("ground_items", []),
		"interiors": deltas.get("interiors", []),
		"connections": deltas.get("connections", []),
	})
	if not bool(world_state_result.get("ok", false)):
		return _build_result(false, "world_state_%s" % String(world_state_result.get("reason", "failed")), save_data)
	var delta_result: Dictionary = chunk_manager.import_world_deltas(deltas)
	if not bool(delta_result.get("ok", false)):
		return _build_result(false, "deltas_%s" % String(delta_result.get("reason", "failed")), save_data)
	world_state.discard_depleted_harvest_orders()
	world_state.discard_stale_mining_orders()
	var colonist_result: Dictionary = colonist_manager.import_colonist_records(colonist_records)
	if not bool(colonist_result.get("ok", false)):
		return _build_result(false, "colonists_%s" % String(colonist_result.get("reason", "failed")), save_data)
	return _build_result(true, "loaded", save_data)

func _validate_save_structure(save_data: Dictionary) -> Dictionary:
	## Reject missing or mistyped owner sections before any owner mutates live state.
	for section_name: String in ["world", "time", "stockpile", "deltas"]:
		if not save_data.has(section_name):
			return _build_validation_result(false, "missing_%s" % section_name)
		if not save_data[section_name] is Dictionary:
			return _build_validation_result(false, "invalid_%s" % section_name)
	if not save_data.has("colonists"):
		return _build_validation_result(false, "missing_colonists")
	if not save_data["colonists"] is Array:
		return _build_validation_result(false, "invalid_colonists")
	var world_validation: Dictionary = _validate_world_generation_state(save_data["world"])
	if not bool(world_validation.get("ok", false)):
		return world_validation
	var colonist_world_space_validation: Dictionary = _validate_colonist_world_spaces(save_data["colonists"], save_data["deltas"])
	if not bool(colonist_world_space_validation.get("ok", false)):
		return colonist_world_space_validation
	return _build_validation_result(true, "valid")

func _validate_colonist_world_spaces(colonist_records: Array, deltas: Dictionary) -> Dictionary:
	## Preflight the exact cross-owner reference before any legacy load owner mutates live state.
	var interior_records: Variant = deltas.get("interiors", [])
	if not interior_records is Array:
		return _build_validation_result(false, "invalid_interiors")
	var supported_world_spaces: Dictionary = {"surface": true}
	for entry: Variant in interior_records:
		if not entry is Dictionary:
			return _build_validation_result(false, "invalid_interior_record")
		var world_space_id: String = String((entry as Dictionary).get("world_space_id", ""))
		if not world_space_id.is_empty():
			supported_world_spaces[world_space_id] = true
	for entry: Variant in colonist_records:
		if not entry is Dictionary:
			return _build_validation_result(false, "invalid_colonist_record")
		var world_space_id: String = String((entry as Dictionary).get("world_space_id", "surface"))
		if not supported_world_spaces.has(world_space_id):
			return _build_validation_result(false, "unsupported_colonist_world_space_id")
	return _build_validation_result(true, "valid")

func _validate_world_generation_state(world_data: Dictionary) -> Dictionary:
	if not world_data.has("seed") or not _is_numeric(world_data["seed"]) or not is_finite(float(world_data["seed"])):
		return _build_validation_result(false, "invalid_world_seed")
	if not world_data.has("generation_config") or not world_data["generation_config"] is Dictionary:
		return _build_validation_result(false, "invalid_world_generation_config")
	var config: Dictionary = world_data["generation_config"]
	for key: String in ["terrain_scale", "landmass_scale", "water_max", "coast_max", "stone_min", "dry_max", "wet_min", "saturated_min", "chunk_size"]:
		if config.has(key) and (not _is_numeric(config[key]) or not is_finite(float(config[key]))):
			return _build_validation_result(false, "invalid_world_generation_config")
	if float(config.get("terrain_scale", 1.0)) <= 0.0 or float(config.get("landmass_scale", 1.0)) <= 0.0:
		return _build_validation_result(false, "invalid_world_generation_config")
	if int(config.get("chunk_size", 1)) <= 0:
		return _build_validation_result(false, "invalid_world_generation_config")
	return _build_validation_result(true, "valid")

func _is_numeric(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

func _build_validation_result(ok: bool, reason: String) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
	}

func _build_result(ok: bool, reason: String, save_data: Dictionary) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"version": SAVE_VERSION,
		"data": save_data,
	}

## Separate persistence boundary for the windowed-colony prototype. Legacy version-2
## world saves are intentionally neither accepted nor migrated here.
func save_windowed_colony(path: String, save_data: Dictionary) -> Dictionary:
	var validation := validate_windowed_colony_data(save_data)
	if not bool(validation.ok): return validation
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return {"ok": false, "reason": "open_write_failed"}
	file.store_string(JSON.stringify(_encode_vectors(save_data), "\t")); file.close()
	return {"ok": true, "reason": "saved", "version": WINDOWED_COLONY_SAVE_VERSION}

func inspect_windowed_colony_save(path: String) -> Dictionary:
	var loaded := load_windowed_colony(path)
	return {"ok": bool(loaded.ok), "reason": String(loaded.reason)}

func load_windowed_colony(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok": false, "reason": "file_missing"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "reason": "open_read_failed"}
	var parsed: Variant = JSON.parse_string(file.get_as_text()); file.close()
	if not parsed is Dictionary: return {"ok": false, "reason": "invalid_json"}
	var decoded: Variant = _decode_vectors(parsed)
	if not decoded is Dictionary: return {"ok": false, "reason": "invalid_document"}
	var validation := validate_windowed_colony_data(decoded)
	if not bool(validation.ok): return validation
	return {"ok": true, "reason": "loaded", "version": WINDOWED_COLONY_SAVE_VERSION, "data": decoded}

func validate_windowed_colony_data(data: Dictionary) -> Dictionary:
	if String(data.get("schema", "")) != "windowed_colony": return {"ok": false, "reason": "unsupported_schema"}
	var version := int(data.get("version", -1))
	if version not in [3, WINDOWED_COLONY_SAVE_VERSION]: return {"ok": false, "reason": "unsupported_version"}
	if String(data.get("game_phase", "")) != "SETTLED": return {"ok": false, "reason": "invalid_game_phase"}
	if not data.get("location_registry") is Dictionary: return {"ok": false, "reason": "invalid_location_registry"}
	if not data.location_registry.get("locations") is Array or (data.location_registry.locations as Array).is_empty(): return {"ok": false, "reason": "invalid_locations"}
	if not data.get("colonists") is Array or (data.colonists as Array).size() != 3: return {"ok": false, "reason": "invalid_colonists"}
	if not data.get("active_scouting") is Array or not data.get("active_travel") is Array: return {"ok": false, "reason": "invalid_mobility_records"}
	if not data.get("location_construction") is Dictionary or not data.location_construction.get("buildings") is Array: return {"ok": false, "reason": "invalid_location_construction"}
	if version >= 4 and not data.get("structural_construction") is Dictionary: return {"ok": false, "reason": "invalid_structural_construction"}
	var locations: Dictionary = {}; var memberships: Dictionary = {}
	for raw_location: Variant in data.location_registry.locations:
		if not raw_location is Dictionary: return {"ok": false, "reason": "invalid_location"}
		var location_id := String(raw_location.get("location_id", ""))
		if location_id.is_empty() or locations.has(location_id) or not raw_location.get("world_position") is Vector2i or not raw_location.get("colonist_presence_ids") is Array: return {"ok": false, "reason": "invalid_location"}
		if bool(raw_location.get("claimed", false)) and (float(raw_location.get("claimed_at_simulation_time", -1.0)) < 0.0 or String(raw_location.get("claimed_by_colony_id", "")).is_empty()): return {"ok": false, "reason": "invalid_claim_metadata"}
		locations[location_id] = raw_location
		for member: Variant in raw_location.colonist_presence_ids:
			var member_id := String(member); if memberships.has(member_id): return {"ok": false, "reason": "duplicate_presence"}
			memberships[member_id] = location_id
	if not locations.has(String(data.get("primary_settlement_id", ""))) or Vector2i(locations[String(data.primary_settlement_id)].world_position) != Vector2i.ZERO: return {"ok": false, "reason": "invalid_primary_settlement"}
	var ids: Dictionary = {}
	for raw: Variant in data.colonists:
		if not raw is Dictionary: return {"ok": false, "reason": "invalid_colonist"}
		var id := String(raw.get("colonist_id", ""))
		if id.is_empty() or ids.has(id) or not raw.get("needs") is Dictionary or not raw.get("skills") is Dictionary or String(raw.get("role", "")) not in ["unassigned", "woodcutting", "mining", "foraging", "hauling", "scout", "construction"]: return {"ok": false, "reason": "invalid_colonist"}
		if int(raw.get("carried", {}).get("amount", 0)) > 0: return {"ok": false, "reason": "unresolved_carried_payload"}
		ids[id] = true
	var away: Dictionary = {}
	for scout: Variant in data.active_scouting:
		if not scout is Dictionary: return {"ok": false, "reason": "invalid_scouting_record"}
		var id := String(scout.get("colonist_id", "")); var origin := String(scout.get("origin_location_id", ""))
		if not ids.has(id) or away.has(id) or memberships.has(id) or not locations.has(origin) or float(scout.get("elapsed", -1)) < 0.0 or float(scout.get("elapsed", 0)) > float(scout.get("duration", -1)): return {"ok": false, "reason": "invalid_scouting_record"}
		away[id] = true
	for travel: Variant in data.active_travel:
		if not travel is Dictionary: return {"ok": false, "reason": "invalid_travel_record"}
		var id := String(travel.get("colonist_id", "")); var origin := String(travel.get("origin_location_id", "")); var destination := String(travel.get("destination_location_id", ""))
		if not ids.has(id) or away.has(id) or memberships.has(id) or not locations.has(origin) or not locations.has(destination) or float(travel.get("travel_elapsed", -1)) < 0.0 or float(travel.get("travel_elapsed", 0)) > float(travel.get("travel_duration", -1)): return {"ok": false, "reason": "invalid_travel_record"}
		away[id] = true
	for id: String in ids:
		if memberships.has(id) == away.has(id): return {"ok": false, "reason": "contradictory_colonist_presence"}
	return {"ok": true, "reason": "valid"}

func _encode_vectors(value: Variant) -> Variant:
	if value is Vector2i: return {"__type": "Vector2i", "x": value.x, "y": value.y}
	if value is Vector2: return {"__type": "Vector2", "x": value.x, "y": value.y}
	if value is Rect2i: return {"__type": "Rect2i", "x": value.position.x, "y": value.position.y, "w": value.size.x, "h": value.size.y}
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[key] = _encode_vectors(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(_encode_vectors(item))
		return result
	return value

func _decode_vectors(value: Variant) -> Variant:
	if value is Dictionary:
		var type_name := String(value.get("__type", ""))
		if type_name == "Vector2i": return Vector2i(int(value.x), int(value.y))
		if type_name == "Vector2": return Vector2(float(value.x), float(value.y))
		if type_name == "Rect2i": return Rect2i(int(value.x), int(value.y), int(value.w), int(value.h))
		var result: Dictionary = {}
		for key: Variant in value: result[key] = _decode_vectors(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(_decode_vectors(item))
		return result
	return value
