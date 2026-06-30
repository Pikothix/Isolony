extends SceneTree

## Purpose: Validate the I05 completed-Storehouse read-only inspector flow.
## Responsibility: Exercise Main selection, capacity/content projection, empty state, and colonist-selection compatibility.
## Assumption: Storage fixtures are populated only through existing WorldState hauling APIs.

const MainScene = preload("res://scenes/Main.tscn")
const INVALID_CELL := Vector2i(2147483647, 2147483647)

var _failed: bool = false
var _main: Node
var _world_state: Node
var _chunk_manager: ChunkManager
var _colonist_manager: ColonistManager
var _panel: PanelContainer


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("I05 storage inspector validation failed: %s" % message)
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
	_panel = _main.get_node_or_null("CanvasLayer/StorageInspectorPanel") as PanelContainer
	_freeze_scene()
	if not _require(_world_state != null and _panel != null, "Main scene did not load the storage inspector"):
		return

	var origin: Vector2i = _complete_storehouse(Vector2i.ZERO)
	if not _require(origin != INVALID_CELL, "could not complete Storehouse fixture"):
		return
	if not _require(bool(_main.call("_select_storage_at_cell", origin)), "completed Storehouse could not be selected"):
		return
	var empty_snapshot: Dictionary = _panel.get_display_snapshot()
	if not _require(bool(empty_snapshot.get("visible", false)) and String(empty_snapshot.get("building_name", "")) == "Storehouse", "inspector did not display the selected building name"):
		return
	if not _require(String(empty_snapshot.get("capacity", "")) == "0 / 100", "inspector did not display empty used/capacity state"):
		return
	if not _require(String(empty_snapshot.get("contents", "")) == "Empty", "empty Storehouse did not display Empty"):
		return

	var component: Dictionary = _world_state.get_storage_components()[0]
	var storage_id: String = String(component.get("storage_id", ""))
	for fixture: Dictionary in [
		{"resource_type": "wood", "amount": 4},
		{"resource_type": "stone", "amount": 3},
		{"resource_type": "food", "amount": 2},
	]:
		if not _deposit_to_storage(storage_id, String(fixture["resource_type"]), int(fixture["amount"])):
			return
	await process_frame
	var populated_before: Dictionary = _world_state.get_storage_component(storage_id)
	_main.call("_refresh_selected_storage_inspector")
	var populated_snapshot: Dictionary = _panel.get_display_snapshot()
	var contents_text: String = String(populated_snapshot.get("contents", ""))
	if not _require(String(populated_snapshot.get("capacity", "")) == "9 / 100", "inspector capacity did not update from WorldState contents"):
		return
	for expected_line: String in ["Wood: 4", "Stone: 3", "Food: 2"]:
		if not _require(contents_text.contains(expected_line), "inspector omitted %s" % expected_line):
			return
	if not _require(_world_state.get_storage_component(storage_id) == populated_before, "inspector display mutated storage contents"):
		return

	var colonists: Array[Colonist] = _get_colonists()
	if not _require(not colonists.is_empty(), "Main scene did not spawn a colonist"):
		return
	_main.call("_set_selected_colonist", colonists[0])
	var colonist_panel: Node = _main.get_node("CanvasLayer/ColonistInfoPanel")
	if not _require(colonist_panel.visible and not _panel.visible and _main.get("_selected_colonist") == colonists[0], "colonist selection no longer replaces Storehouse selection"):
		return

	var terrain_cell: Vector2i = _find_clean_cell(origin + Vector2i(8, 8))
	if not _require(terrain_cell != INVALID_CELL, "could not find terrain selection fixture"):
		return
	_main.call("_set_selected_colonist", null)
	if not _require(not bool(_main.call("_select_storage_at_cell", terrain_cell)) and not _panel.visible and String(_main.get("_selected_storage_id")).is_empty(), "terrain selection did not clear Storehouse inspector"):
		return

	print("I05 validation passed: Main load, Storehouse selection, capacity, contents, Empty state, read-only projection, colonist compatibility, and terrain clear")
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


func _deposit_to_storage(storage_id: String, resource_type: String, amount: int) -> bool:
	var component: Dictionary = _world_state.get_storage_component(storage_id)
	var item_cell: Vector2i = _find_storage_access_cell(component)
	if not _require(item_cell != INVALID_CELL, "could not find Storehouse access cell"):
		return false
	var item_result: Dictionary = _world_state.create_ground_item(resource_type, amount, item_cell)
	if not _require(bool(item_result.get("ok", false)), "could not create %s fixture" % resource_type):
		return false
	var item_id: String = String(item_result.get("item_id", ""))
	var colonist_id := "i05_%s" % resource_type
	var reservation: Dictionary = _world_state.reserve_haul_item(item_id, colonist_id)
	var pickup: Dictionary = _world_state.request_pickup_ground_item(item_id, colonist_id)
	var deposit: Dictionary = _world_state.request_deposit_carried_item(colonist_id, pickup.get("item", {}), reservation.get("destination_cell", Vector2i.ZERO))
	return _require(bool(reservation.get("ok", false)) and String(reservation.get("storage_id", "")) == storage_id and bool(pickup.get("ok", false)) and bool(deposit.get("ok", false)), "could not deposit %s fixture" % resource_type)


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
	return bool(tile.get("walkable", false)) and terrain != "WATER" and terrain != "ROCK_WALL" and not bool(tile.get("mineable", false)) and not _chunk_manager.is_cell_blocked_by_resource(cell) and _world_state.get_construction_site_at_cell(cell).is_empty()


func _get_colonists() -> Array[Colonist]:
	var colonists: Array[Colonist] = []
	for child: Node in _colonist_manager.get_children():
		if child is Colonist and not child.is_queued_for_deletion():
			colonists.append(child as Colonist)
	return colonists


func _freeze_scene() -> void:
	_main.set_process(false)
	_chunk_manager.set_process(false)
	_colonist_manager.set_process(false)
	for child: Node in _colonist_manager.get_children():
		if child is Colonist:
			child.set_process(false)
