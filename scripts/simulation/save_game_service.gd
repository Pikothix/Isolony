extends RefCounted
class_name SaveGameService

const SAVE_VERSION := 2

## Purpose: Small, non-autoload persistence service for current world and colonist authority.
## Responsibility: Validate top-level save structure, serialize/deserialize versioned dictionaries, and coordinate state-owner import order, including harvest intent, zones, and ground items.
## Assumption: Menus, slots, full scene reload, migration, and future systems remain outside this milestone.
func build_save_data(world_generator: Node, world_state: Node, chunk_manager: Node, colonist_manager: Node) -> Dictionary:
	var world_state_data: Dictionary = world_state.export_state()
	var deltas: Dictionary = chunk_manager.export_world_deltas()
	deltas["construction_sites"] = world_state_data.get("construction_sites", [])
	deltas["harvest_orders"] = world_state_data.get("harvest_orders", [])
	deltas["stockpile_zones"] = world_state_data.get("stockpile_zones", [])
	deltas["ground_items"] = world_state_data.get("ground_items", [])
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
		"stockpile_zones": deltas.get("stockpile_zones", []),
		"ground_items": deltas.get("ground_items", []),
	})
	if not bool(world_state_result.get("ok", false)):
		return _build_result(false, "world_state_%s" % String(world_state_result.get("reason", "failed")), save_data)
	var delta_result: Dictionary = chunk_manager.import_world_deltas(deltas)
	if not bool(delta_result.get("ok", false)):
		return _build_result(false, "deltas_%s" % String(delta_result.get("reason", "failed")), save_data)
	world_state.discard_depleted_harvest_orders()
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
