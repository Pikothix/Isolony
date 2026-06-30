extends SceneTree

## Purpose: Validate removal of stockpile-zone creation from the active player workflow.
## Responsibility: Exercise toolbar/shortcut deprecation while preserving legacy zone import, projection, save, and hauling compatibility.
## Assumption: Direct WorldState zone creation remains available only as a legacy fixture/API compatibility path.

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
	push_error("R02F stockpile-zone deprecation validation failed: %s" % message)
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

	var toolbar: Node = _main.get_node("CanvasLayer/BottomToolbar")
	if not _require(toolbar.get_node_or_null("MarginContainer/VBoxContainer/ToolbarButtons/StockpileButton") == null, "bottom toolbar still exposes Stockpile Zone creation"):
		return
	if not _require(not toolbar.has_signal("stockpile_mode_requested"), "bottom toolbar still exposes stockpile creation intent"):
		return
	_main.call("_cancel_control_mode")
	var shortcut := InputEventKey.new()
	shortcut.keycode = KEY_Z
	shortcut.pressed = true
	_main.call("_unhandled_input", shortcut)
	if not _require(String(_main.call("get_control_mode_name")) == "normal", "Z shortcut still enters stockpile placement mode"):
		return

	var storehouse_origin: Vector2i = _complete_storehouse(Vector2i.ZERO)
	if not _require(storehouse_origin != INVALID_CELL, "could not complete Storehouse fixture"):
		return
	var component: Dictionary = _world_state.get_storage_components()[0]
	var storage_id: String = String(component.get("storage_id", ""))
	var item_cell: Vector2i = _find_storage_access_cell(component)
	var item_result: Dictionary = _world_state.create_ground_item("wood", 4, item_cell)
	if not _require(item_cell != INVALID_CELL and bool(item_result.get("ok", false)), "could not create Storehouse haul fixture"):
		return
	var item_id: String = String(item_result.get("item_id", ""))
	var reservation: Dictionary = _world_state.reserve_haul_item(item_id, "r02f_worker")
	var pickup: Dictionary = _world_state.request_pickup_ground_item(item_id, "r02f_worker")
	var deposit: Dictionary = _world_state.request_deposit_carried_item("r02f_worker", pickup.get("item", {}), reservation.get("destination_cell", Vector2i.ZERO))
	if not _require(bool(reservation.get("ok", false)) and String(reservation.get("destination_kind", "")) == "storage_component" and String(reservation.get("storage_id", "")) == storage_id and bool(pickup.get("ok", false)) and bool(deposit.get("ok", false)), "Storehouse hauling no longer works"):
		return
	if not _require(int((_world_state.get_storage_component(storage_id).get("contents", {}) as Dictionary).get("wood", 0)) == 4, "Storehouse haul did not update component contents"):
		return

	var zone_cell: Vector2i = _find_clean_cell(storehouse_origin + Vector2i(10, 8))
	if not _require(zone_cell != INVALID_CELL, "could not find legacy zone cell"):
		return
	var zone_result: Dictionary = _world_state.request_create_stockpile_zone([zone_cell])
	if not _require(bool(zone_result.get("ok", false)), "legacy zone fixture creation failed"):
		return
	var exported_zones: Array[Dictionary] = _world_state.export_stockpile_zones()
	if not _require(exported_zones.size() == 1, "legacy zone export failed"):
		return
	if not _require(bool(_world_state.import_stockpile_zones([]).get("ok", false)) and _world_state.get_stockpile_zones().is_empty(), "legacy zone clear import failed"):
		return
	if not _require(bool(_world_state.import_stockpile_zones(exported_zones).get("ok", false)) and _world_state.get_stockpile_zones().size() == 1, "legacy zone re-import failed"):
		return
	await process_frame
	var visual_root: Node = _chunk_manager.get_node("GameplayYSort/StockpileZoneRoot")
	if not _require(visual_root.get_child_count() > 0, "imported legacy zone did not project a visual"):
		return
	for child: Node in visual_root.get_children():
		child.queue_free()
	await process_frame
	if not _require(_world_state.get_stockpile_zones().size() == 1 and _world_state.is_cell_in_stockpile_zone(zone_cell), "removing a legacy zone visual changed authoritative data"):
		return

	var save_service := SaveGameServiceRef.new()
	var save_data: Dictionary = save_service.build_save_data(_main.get_node("WorldGenerator"), _world_state, _chunk_manager, _colonist_manager)
	var saved_zones: Array = (save_data.get("deltas", {}) as Dictionary).get("stockpile_zones", [])
	if not _require(saved_zones.size() == 1 and String((saved_zones[0] as Dictionary).get("zone_id", "")) == String(zone_result.get("zone_id", "")), "save export did not preserve the imported legacy zone"):
		return

	print("R02F validation passed: toolbar/shortcut deprecation, Storehouse hauling, legacy zone import/projection authority, and save export")
	quit(0)


func _complete_storehouse(origin_hint: Vector2i) -> Vector2i:
	var origin: Vector2i = _find_valid_building_origin("storehouse", origin_hint)
	if origin == INVALID_CELL:
		return INVALID_CELL
	if not bool(_world_state.add_resource("wood", 30).get("ok", false)) or not bool(_world_state.add_resource("stone", 10).get("ok", false)):
		return INVALID_CELL
	var placement: Dictionary = _world_state.request_place_construction("storehouse", origin)
	var site_id := "storehouse:%d:%d" % [origin.x, origin.y]
	var progress: Dictionary = _world_state.request_progress_construction(site_id, 50.0)
	return origin if bool(placement.get("ok", false)) and bool(progress.get("completed", false)) else INVALID_CELL


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
