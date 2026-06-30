extends SceneTree

## Purpose: Validate that Storehouses own active storage gameplay while legacy stockpile compatibility remains loadable.
## Responsibility: Exercise bootstrap, Storehouse hauling/construction/eating, legacy-zone persistence, and aggregate reads.
## Assumption: Direct stockpile-zone creation is retained only as a validator/save-compatibility fixture.

const MainScene = preload("res://scenes/Main.tscn")
const SaveGameServiceRef = preload("res://scripts/simulation/save_game_service.gd")
const INVALID_CELL := Vector2i(2147483647, 2147483647)

var _failed: bool = false
var _main: Node
var _world_state: Node
var _chunk_manager: ChunkManager
var _colonist_manager: ColonistManager


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("R02G legacy stockpile cleanup validation failed: %s" % message)
	quit(1)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _run() -> void:
	_main = MainScene.instantiate()
	root.add_child(_main)
	for _frame in range(160):
		await process_frame
	_world_state = _main.get("_world_state")
	_chunk_manager = _main.get_node("ChunkManager") as ChunkManager
	_colonist_manager = _main.get_node("ChunkManager/GameplayYSort/ColonistManager") as ColonistManager
	_freeze_scene()
	if not _validate_stockpile_creation_is_not_player_facing():
		return

	for fixture: Dictionary in [
		{"resource_type": "wood", "amount": 40},
		{"resource_type": "stone", "amount": 10},
		{"resource_type": "food", "amount": 2},
	]:
		if not _require(bool(_world_state.add_resource(String(fixture["resource_type"]), int(fixture["amount"])).get("ok", false)), "could not seed legacy bootstrap resources"):
			return
	var legacy_stockpile: Node = _world_state.get_resource_stockpile()
	var storehouse_origin: Vector2i = _complete_first_storehouse(Vector2i.ZERO)
	if not _require(storehouse_origin != INVALID_CELL, "first Storehouse did not bootstrap from legacy stockpile"):
		return
	if not _require(legacy_stockpile.get_total("wood") == 10 and legacy_stockpile.get_total("stone") == 0 and legacy_stockpile.get_total("food") == 2, "bootstrap consumed incorrect legacy totals"):
		return

	var component: Dictionary = _world_state.get_storage_components()[0]
	var storage_id: String = String(component.get("storage_id", ""))
	for fixture: Dictionary in [
		{"resource_type": "wood", "amount": 8},
		{"resource_type": "stone", "amount": 3},
		{"resource_type": "food", "amount": 3},
	]:
		if not _deposit_to_storage(storage_id, String(fixture["resource_type"]), int(fixture["amount"]), "r02g_seed_%s" % fixture["resource_type"]):
			return
	if not _require(_aggregate_totals_match_sources(storage_id), "aggregate totals duplicated legacy or Storehouse contents after hauling"):
		return

	var zone_cell: Vector2i = _find_clean_cell(storehouse_origin + Vector2i(10, 8))
	if not _require(zone_cell != INVALID_CELL, "could not find legacy stockpile-zone fixture cell"):
		return
	var zone_result: Dictionary = _world_state.request_create_stockpile_zone([zone_cell])
	if not _require(bool(zone_result.get("ok", false)), "could not create legacy zone compatibility fixture"):
		return
	var zone_item: Dictionary = _world_state.create_ground_item("wood", 1, zone_cell)
	if not _require(bool(zone_item.get("ok", false)), "could not create item on imported-zone fixture"):
		return
	var zone_item_id: String = String(zone_item.get("item_id", ""))
	var zone_reservation: Dictionary = _world_state.reserve_haul_item(zone_item_id, "r02g_zone_item")
	if not _require(bool(zone_reservation.get("ok", false)) and String(zone_reservation.get("destination_kind", "")) == "storage_component" and String(zone_reservation.get("storage_id", "")) == storage_id, "legacy zone prevented Storehouse hauling after storage became active"):
		return
	if not _complete_reserved_haul(zone_item_id, "r02g_zone_item", zone_reservation):
		return
	if not _require(legacy_stockpile.get_total("wood") == 10 and int((_world_state.get_storage_component(storage_id).get("contents", {}) as Dictionary).get("wood", 0)) == 9, "Storehouse haul duplicated into legacy totals"):
		return

	var campfire_origin: Vector2i = _find_valid_building_origin("campfire", storehouse_origin + Vector2i(8, 0))
	if not _require(campfire_origin != INVALID_CELL, "could not find Storehouse-funded construction cell"):
		return
	var campfire_placement: Dictionary = _world_state.request_place_construction("campfire", campfire_origin)
	var campfire_id := "campfire:%d:%d" % [campfire_origin.x, campfire_origin.y]
	var construction_reservation: Dictionary = _world_state.reserve_construction_site("r02g_builder", campfire_id)
	if not _require(bool(campfire_placement.get("ok", false)) and bool(construction_reservation.get("ok", false)), "Storehouse-funded construction could not reserve"):
		return
	if not _require(_world_state.get_construction_material_reservation_summary(campfire_id).get("count", 0) > 0 and not legacy_stockpile.has_resource_reservation("construction:%s" % campfire_id), "construction reserved legacy totals after Storehouse activation"):
		return
	var construction_progress: Dictionary = _world_state.request_progress_construction(campfire_id, 10.0, "r02g_builder")
	if not _require(bool(construction_progress.get("completed", false)) and legacy_stockpile.get_total("wood") == 10 and int((_world_state.get_storage_component(storage_id).get("contents", {}) as Dictionary).get("wood", 0)) == 4, "construction did not consume Storehouse Wood exclusively"):
		return
	if not _deposit_to_storage(storage_id, "wood", 5, "r02g_direct_seed"):
		return
	var direct_origin: Vector2i = _find_valid_building_origin("campfire", campfire_origin + Vector2i(4, 0))
	var direct_placement: Dictionary = _world_state.request_place_construction("campfire", direct_origin)
	var direct_id := "campfire:%d:%d" % [direct_origin.x, direct_origin.y]
	var direct_progress: Dictionary = _world_state.request_progress_construction(direct_id, 10.0)
	if not _require(bool(direct_placement.get("ok", false)) and bool(direct_progress.get("completed", false)) and legacy_stockpile.get_total("wood") == 10 and int((_world_state.get_storage_component(storage_id).get("contents", {}) as Dictionary).get("wood", 0)) == 4, "unowned construction progress used legacy Wood after Storehouse activation"):
		return

	var food_before: int = int((_world_state.get_storage_component(storage_id).get("contents", {}) as Dictionary).get("food", 0))
	var eat_result: Dictionary = _world_state.request_consume_food("r02g_eater", 1)
	if not _require(bool(eat_result.get("ok", false)) and legacy_stockpile.get_total("food") == 2 and int((_world_state.get_storage_component(storage_id).get("contents", {}) as Dictionary).get("food", 0)) == food_before - 1, "eating did not consume Storehouse Food exclusively"):
		return

	component = _world_state.get_storage_component(storage_id)
	var oversized_amount: int = int(component.get("available", 0)) + 1
	var oversized_cell: Vector2i = _find_clean_cell(zone_cell + Vector2i(4, 0))
	var oversized_item: Dictionary = _world_state.create_ground_item("stone", oversized_amount, oversized_cell)
	if not _require(oversized_cell != INVALID_CELL and bool(oversized_item.get("ok", false)), "could not create Storehouse-capacity fixture"):
		return
	var oversized_reservation: Dictionary = _world_state.reserve_haul_item(String(oversized_item.get("item_id", "")), "r02g_no_zone_fallback")
	if not _require(not bool(oversized_reservation.get("ok", false)) and String(oversized_reservation.get("reason", "")) == "no_valid_storehouse_destination", "full Storehouse selection fell back to a legacy stockpile zone"):
		return
	if not _require(legacy_stockpile.get_storage_reservation_summary().get("count", -1) == 0, "failed Storehouse haul reserved legacy capacity"):
		return
	if not _require(_aggregate_totals_match_sources(storage_id), "aggregate totals duplicated resources after construction or eating"):
		return

	var exported_zones: Array[Dictionary] = _world_state.export_stockpile_zones()
	if not _require(bool(_world_state.import_stockpile_zones([]).get("ok", false)) and bool(_world_state.import_stockpile_zones(exported_zones).get("ok", false)), "legacy zone import compatibility failed"):
		return
	var save_service := SaveGameServiceRef.new()
	var save_data: Dictionary = save_service.build_save_data(_main.get_node("WorldGenerator"), _world_state, _chunk_manager, _colonist_manager)
	var saved_legacy_totals: Dictionary = save_data.get("stockpile", {}).duplicate(true)
	if not _require(int(save_data.get("version", -1)) == 2 and (save_data.get("deltas", {}) as Dictionary).get("stockpile_zones", []).size() == 1, "version-2 save omitted legacy stockpile or zone compatibility"):
		return
	var load_result: Dictionary = save_service.apply_save_data(save_data, _main.get_node("WorldGenerator"), _world_state, _chunk_manager, _colonist_manager)
	if not _require(bool(load_result.get("ok", false)) and _world_state.get_stockpile_zones().size() == 1 and legacy_stockpile.get_totals() == saved_legacy_totals, "version-2 save/load did not preserve legacy stockpile compatibility"):
		return
	component = _world_state.get_storage_components()[0]
	storage_id = String(component.get("storage_id", ""))
	if not _require(_aggregate_totals_match_sources(storage_id), "save/load duplicated resources between legacy totals and Storehouse contents"):
		return

	var older_v2_save: Dictionary = save_data.duplicate(true)
	(older_v2_save.get("deltas", {}) as Dictionary).erase("stockpile_zones")
	var older_load_result: Dictionary = save_service.apply_save_data(older_v2_save, _main.get_node("WorldGenerator"), _world_state, _chunk_manager, _colonist_manager)
	if not _require(bool(older_load_result.get("ok", false)) and _world_state.get_stockpile_zones().is_empty(), "older version-2 save without stockpile zones no longer loads"):
		return

	print("R02G validation passed: legacy bootstrap/save compatibility, Storehouse-only hauling/worker/direct construction/eating, zone fallback cleanup, aggregate totals, and no duplication")
	quit(0)


func _validate_stockpile_creation_is_not_player_facing() -> bool:
	var toolbar: Node = _main.get_node("CanvasLayer/BottomToolbar")
	if not _require(toolbar.get_node_or_null("MarginContainer/VBoxContainer/ToolbarButtons/StockpileButton") == null and not toolbar.has_signal("stockpile_mode_requested"), "stockpile-zone creation remains player-facing"):
		return false
	_main.call("_cancel_control_mode")
	var shortcut := InputEventKey.new()
	shortcut.keycode = KEY_Z
	shortcut.pressed = true
	_main.call("_unhandled_input", shortcut)
	return _require(String(_main.call("get_control_mode_name")) == "normal", "Z shortcut still enters stockpile creation mode")


func _complete_first_storehouse(origin_hint: Vector2i) -> Vector2i:
	if not _world_state.get_storage_components().is_empty():
		return INVALID_CELL
	var origin: Vector2i = _find_valid_building_origin("storehouse", origin_hint)
	if origin == INVALID_CELL:
		return INVALID_CELL
	var placement: Dictionary = _world_state.request_place_construction("storehouse", origin)
	var site_id := "storehouse:%d:%d" % [origin.x, origin.y]
	var reservation: Dictionary = _world_state.reserve_construction_site("r02g_bootstrap_builder", site_id)
	if not bool(placement.get("ok", false)) or not bool(reservation.get("ok", false)):
		return INVALID_CELL
	if not _world_state.get_resource_stockpile().has_resource_reservation("construction:%s" % site_id):
		return INVALID_CELL
	var progress: Dictionary = _world_state.request_progress_construction(site_id, 50.0, "r02g_bootstrap_builder")
	return origin if bool(progress.get("completed", false)) and _world_state.get_storage_components().size() == 1 else INVALID_CELL


func _deposit_to_storage(storage_id: String, resource_type: String, amount: int, colonist_id: String) -> bool:
	var component: Dictionary = _world_state.get_storage_component(storage_id)
	var item_cell: Vector2i = _find_storage_access_cell(component)
	if not _require(item_cell != INVALID_CELL, "could not find Storehouse access cell"):
		return false
	var item_result: Dictionary = _world_state.create_ground_item(resource_type, amount, item_cell)
	if not _require(bool(item_result.get("ok", false)), "could not create %s Storehouse fixture" % resource_type):
		return false
	var item_id: String = String(item_result.get("item_id", ""))
	var reservation: Dictionary = _world_state.reserve_haul_item(item_id, colonist_id)
	if not _require(bool(reservation.get("ok", false)) and String(reservation.get("destination_kind", "")) == "storage_component" and String(reservation.get("storage_id", "")) == storage_id, "hauling did not choose Storehouse for %s" % resource_type):
		return false
	return _complete_reserved_haul(item_id, colonist_id, reservation)


func _complete_reserved_haul(item_id: String, colonist_id: String, reservation: Dictionary) -> bool:
	var pickup: Dictionary = _world_state.request_pickup_ground_item(item_id, colonist_id)
	var deposit: Dictionary = _world_state.request_deposit_carried_item(colonist_id, pickup.get("item", {}), reservation.get("destination_cell", Vector2i.ZERO))
	return _require(bool(pickup.get("ok", false)) and bool(deposit.get("ok", false)), "could not complete reserved Storehouse haul")


func _aggregate_totals_match_sources(storage_id: String) -> bool:
	var component_contents: Dictionary = _world_state.get_storage_component(storage_id).get("contents", {})
	var legacy_stockpile: Node = _world_state.get_resource_stockpile()
	for resource_type: String in ["wood", "stone", "food"]:
		var expected: int = legacy_stockpile.get_total(resource_type) + int(component_contents.get(resource_type, 0))
		if _world_state.get_resource_total(resource_type) != expected or int(_world_state.get_resource_totals().get(resource_type, 0)) != expected:
			return false
	return true


func _find_storage_access_cell(component: Dictionary) -> Vector2i:
	var occupied: Array = component.get("occupied_cells", [])
	for occupied_cell: Vector2i in occupied:
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var cell: Vector2i = occupied_cell + offset
			if not occupied.has(cell) and _is_clean_cell(cell):
				return cell
	return INVALID_CELL


func _find_valid_building_origin(building_id: String, hint: Vector2i) -> Vector2i:
	for radius in range(64):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := hint + Vector2i(x, y)
				if bool(_world_state.validate_construction_placement(building_id, candidate).get("ok", false)):
					return candidate
	return INVALID_CELL


func _find_clean_cell(hint: Vector2i) -> Vector2i:
	for radius in range(64):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var cell := hint + Vector2i(x, y)
				if _is_clean_cell(cell):
					return cell
	return INVALID_CELL


func _is_clean_cell(cell: Vector2i) -> bool:
	if not _chunk_manager.is_cell_loaded(cell):
		return false
	var tile: Dictionary = _chunk_manager.get_effective_tile_info(cell)
	var terrain: String = String(tile.get("terrain", ""))
	return bool(tile.get("walkable", false)) and terrain != "WATER" and terrain != "ROCK_WALL" and not bool(tile.get("mineable", false)) and not _chunk_manager.is_cell_blocked_by_resource(cell) and _world_state.get_construction_site_at_cell(cell).is_empty() and not _world_state.is_cell_in_stockpile_zone(cell)


func _freeze_scene() -> void:
	_main.set_process(false)
	_chunk_manager.set_process(false)
	_colonist_manager.set_process(false)
	for child: Node in _colonist_manager.get_children():
		if child is Colonist:
			child.set_process(false)
