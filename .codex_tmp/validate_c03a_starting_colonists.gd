extends SceneTree

## Purpose: Validate the reduced three-colonist new-game population.
## Responsibility: Exercise Main startup and verify distinct, valid initial Colonist records and cells.
## Assumption: Save imports remain count-driven by saved records rather than the new-game scene default.

const MainScene = preload("res://scenes/Main.tscn")

var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("C03A starting colonists validation failed: %s" % message)
	quit(1)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _run() -> void:
	var main: Node = MainScene.instantiate()
	root.add_child(main)
	var manager: ColonistManager = main.get_node("ChunkManager/GameplayYSort/ColonistManager") as ColonistManager
	var chunk_manager: ChunkManager = main.get_node("ChunkManager") as ChunkManager
	for _frame in range(160):
		await process_frame
		var spawning_colonists: Array[Colonist] = _get_colonists(manager)
		if spawning_colonists.size() == 3 and _all_cells_loaded(chunk_manager, spawning_colonists):
			break
	main.set_process(false)
	chunk_manager.set_process(false)
	manager.set_process(false)
	var colonists: Array[Colonist] = _get_colonists(manager)
	for colonist: Colonist in colonists:
		colonist.set_process(false)

	if not _require(main.get("_world_state") != null and manager != null and chunk_manager != null, "Main startup did not initialize required authorities"):
		return
	if not _require(manager.colonist_count == 3 and colonists.size() == 3, "new game did not create exactly three colonists"):
		return

	var seen_ids: Dictionary = {}
	var seen_cells: Dictionary = {}
	for colonist: Colonist in colonists:
		if not _require(is_instance_valid(colonist) and not colonist.colonist_id.is_empty(), "colonist did not spawn with a valid identity"):
			return
		if not _require(not seen_ids.has(colonist.colonist_id), "starting colonists have duplicate ids"):
			return
		seen_ids[colonist.colonist_id] = true
		if not _require(not seen_cells.has(colonist.current_cell), "starting colonists occupy overlapping cells"):
			return
		seen_cells[colonist.current_cell] = true
		if not _require(_is_valid_spawn_cell(chunk_manager, colonist.current_cell), "colonist spawned on an invalid cell: %s (%s)" % [colonist.current_cell, chunk_manager.get_effective_tile_info(colonist.current_cell)]):
			return

	var exported_records: Array[Dictionary] = manager.export_colonist_records()
	var import_result: Dictionary = manager.import_colonist_records(exported_records)
	if not _require(bool(import_result.get("ok", false)) and int(import_result.get("imported_count", 0)) == 3 and _get_colonists(manager).size() == 3, "existing population save records did not reload successfully"):
		return

	print("C03A validation passed: Main startup creates three uniquely identified colonists on distinct valid cells, and population records reload")
	quit(0)


func _get_colonists(manager: ColonistManager) -> Array[Colonist]:
	var colonists: Array[Colonist] = []
	if manager == null:
		return colonists
	for child: Node in manager.get_children():
		if child is Colonist and not child.is_queued_for_deletion():
			colonists.append(child as Colonist)
	colonists.sort_custom(func(first: Colonist, second: Colonist) -> bool:
		return first.colonist_id < second.colonist_id
	)
	return colonists


func _is_valid_spawn_cell(chunk_manager: ChunkManager, cell: Vector2i) -> bool:
	if not chunk_manager.is_cell_loaded(cell):
		return false
	var tile: Dictionary = chunk_manager.get_effective_tile_info(cell)
	var terrain: String = String(tile.get("terrain", ""))
	return bool(tile.get("walkable", false)) and terrain != "WATER" and terrain != "ROCK_WALL" and not bool(tile.get("mineable", false))


func _all_cells_loaded(chunk_manager: ChunkManager, colonists: Array[Colonist]) -> bool:
	for colonist: Colonist in colonists:
		if not chunk_manager.is_cell_loaded(colonist.current_cell):
			return false
	return true
