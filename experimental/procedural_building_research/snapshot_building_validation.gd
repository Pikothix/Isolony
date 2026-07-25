extends SceneTree

## Purpose: Focused automated validation for the interactive full-cell snapshot building slice.
## Ownership: Owns test fixtures only; never participates in runtime presentation.

const LocationState := preload("res://experimental/procedural_building_research/prototype_location_state.gd")
const BuildingPlan := preload("res://experimental/procedural_building_research/prototype_building_plan.gd")
const BuildingService := preload("res://experimental/procedural_building_research/prototype_building_service.gd")
const VisualStyles := preload("res://experimental/procedural_building_research/prototype_visual_styles.gd")
const SnapshotScene := preload("res://experimental/procedural_building_research/PrototypeSnapshotBuildingScene.tscn")

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var location := LocationState.new(Rect2i(0, 0, 12, 10))
	_validate_wall_state(location)
	_validate_floor_fill(location)
	_validate_openings(location)
	_validate_atlas_mapping()
	await _validate_overlay_write_counts()
	await _validate_scene_and_rendering()
	if _failures == 0:
		print("PROTOTYPE_SNAPSHOT_BUILDING_VALIDATION PASS")
		quit(0)
	else:
		push_error("PROTOTYPE_SNAPSHOT_BUILDING_VALIDATION FAILURES=%d" % _failures)
		quit(1)


func _validate_wall_state(location: RefCounted) -> void:
	var plan := BuildingPlan.new()
	var service := BuildingService.new()
	_expect(service.request_add_wall_cells(plan, [Vector2i(2, 2)], location).valid and plan.wall_cells == [Vector2i(2, 2)], "one wall cell can be added")
	_expect(service.request_add_wall_cells(plan, [Vector2i(2, 2), Vector2i(2, 2)], location).valid and plan.wall_cells.size() == 1, "duplicate wall cells normalize")
	var before: Dictionary = plan.snapshot()
	_expect(not service.request_add_wall_cells(plan, [Vector2i(12, 2)], location).valid and plan.snapshot() == before, "out-of-bounds wall request is rejected atomically")
	var run := [Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4)] as Array[Vector2i]
	service.request_set_wall_cells(plan, run, location)
	service.request_set_opening(plan, Vector2i(4, 4), &"door")
	service.request_remove_wall_cells(plan, [Vector2i(4, 4)], location)
	_expect(not plan.openings.has(Vector2i(4, 4)), "removing a wall also removes its opening")


func _validate_floor_fill(location: RefCounted) -> void:
	var service := BuildingService.new()
	var plan := BuildingPlan.new()
	service.request_set_wall_cells(plan, _perimeter(Vector2i(2, 2), Vector2i(4, 4)), location)
	var four: Dictionary = service.request_fill_interior_floors(plan, Vector2i(3, 3), location)
	_expect(four.valid and four.cell_count == 4 and plan.floor_cells.size() == 4, "closed 4x4 perimeter produces a 2x2 floor region")
	_expect(_no_overlap(plan.wall_cells, plan.floor_cells), "accepted floors never overlap walls")
	service.request_set_wall_cells(plan, _perimeter(Vector2i(1, 2), Vector2i(5, 4)), location)
	plan.floor_cells.clear()
	var five: Dictionary = service.request_fill_interior_floors(plan, Vector2i(2, 3), location)
	_expect(five.valid and five.cell_count == 6, "closed 5x4 perimeter produces a 3x2 floor region")
	var open_walls := _perimeter(Vector2i(2, 2), Vector2i(4, 4))
	open_walls.erase(Vector2i(3, 2))
	service.request_set_wall_cells(plan, open_walls, location)
	var accepted_before: Array[Vector2i] = plan.floor_cells.duplicate()
	var open_result: Dictionary = service.request_fill_interior_floors(plan, Vector2i(3, 3), location)
	_expect(not open_result.valid and plan.floor_cells == accepted_before, "open perimeter is rejected without floor mutation")
	var wall_seed: Dictionary = service.request_fill_interior_floors(plan, Vector2i(2, 2), location)
	_expect(not wall_seed.valid, "floor seed on a wall is rejected")
	plan = BuildingPlan.new()
	var two_rooms := _perimeter(Vector2i(1, 1), Vector2i(4, 4))
	two_rooms.append_array(_perimeter(Vector2i(6, 1), Vector2i(4, 4)))
	service.request_set_wall_cells(plan, two_rooms, location)
	var room_a: Dictionary = service.request_fill_interior_floors(plan, Vector2i(2, 2), location)
	var room_b: Dictionary = service.request_fill_interior_floors(plan, Vector2i(7, 2), location)
	_expect(room_a.valid and room_b.valid and plan.floor_cells.size() == 8, "multiple enclosed rooms fill independently")


func _validate_openings(location: RefCounted) -> void:
	var service := BuildingService.new()
	var plan := BuildingPlan.new()
	var rectangle := _perimeter(Vector2i(2, 2), Vector2i(5, 4))
	service.request_set_wall_cells(plan, rectangle, location)
	var ew_cell := Vector2i(4, 2)
	var ns_cell := Vector2i(2, 4)
	var door: Dictionary = service.request_set_opening(plan, ew_cell, &"door")
	_expect(door.valid and door.opening.orientation_group == "east_west", "grid left/right wall connectivity accepts an east/west door")
	var window: Dictionary = service.request_set_opening(plan, ns_cell, &"window")
	_expect(window.valid and window.opening.orientation_group == "north_south", "grid up/down wall connectivity accepts a north/south window")
	_expect(plan.wall_cells.size() == rectangle.size(), "adding openings does not change authoritative wall-cell count")
	var corner := Vector2i(2, 2)
	_expect(not service.request_set_opening(plan, corner, &"door").valid, "corner wall cell rejects an opening")
	_expect(not service.request_set_opening(plan, Vector2i(4, 3), &"door").valid, "non-wall cell rejects an opening")
	var isolated_plan := BuildingPlan.new()
	service.request_set_wall_cells(isolated_plan, [Vector2i(8, 8)], location)
	_expect(not service.request_set_opening(isolated_plan, Vector2i(8, 8), &"door").valid, "isolated wall cell rejects an opening")
	var junction_plan := BuildingPlan.new()
	service.request_set_wall_cells(junction_plan, [Vector2i(7, 6), Vector2i(8, 6), Vector2i(9, 6), Vector2i(8, 5)], location)
	_expect(not service.request_set_opening(junction_plan, Vector2i(8, 6), &"window").valid, "wall junction rejects an opening")
	var replace: Dictionary = service.request_set_opening(plan, ew_cell, &"window")
	_expect(replace.valid and plan.openings.size() == 2 and plan.openings[ew_cell].kind == "window" and plan.wall_cells.size() == rectangle.size(), "door-to-window replacement changes only the opening record")
	_expect(service.request_remove_opening(plan, ew_cell).valid and not plan.openings.has(ew_cell) and plan.wall_cells.has(ew_cell), "removing an opening retains its base wall cell")


func _validate_atlas_mapping() -> void:
	var style: Resource = VisualStyles.create_snapshot_cell_style()
	var expected := {
		&"wall": Vector2i(0, 0),
		&"door_east_west": Vector2i(1, 2),
		&"door_north_south": Vector2i(0, 2),
		&"window_east_west": Vector2i(3, 2),
		&"window_north_south": Vector2i(2, 2),
		&"floor": Vector2i(4, 1),
		&"roof_fill": Vector2i(4, 0),
	}
	for semantic: StringName in expected:
		_expect(style.resolve(semantic).definition.atlas_coordinates == expected[semantic], "%s uses atlas %s" % [semantic, expected[semantic]])
	_expect(not style.render_roofs, "snapshot roof mapping remains suppressed")


func _validate_overlay_write_counts() -> void:
	var scene := SnapshotScene.instantiate()
	root.add_child(scene)
	await process_frame
	var renderer: Node2D = scene.get_node("SnapshotPanel/PrototypeRenderer")
	var wall_run: Array[Vector2i] = []
	for x in range(1, 11):
		wall_run.append(Vector2i(x, 1))
	scene.begin_wall_mode()
	scene.set_pending_walls_for_validation(wall_run)
	_expect(scene.confirm_pending_walls().valid, "ten-cell overlay fixture accepts its authoritative wall run")
	scene._set_tool(&"door", "")
	_expect(scene.apply_tool_at(Vector2i(2, 1)).valid and scene.apply_tool_at(Vector2i(3, 1)).valid, "overlay fixture places two doors")
	scene._set_tool(&"window", "")
	_expect(scene.apply_tool_at(Vector2i(5, 1)).valid and scene.apply_tool_at(Vector2i(6, 1)).valid and scene.apply_tool_at(Vector2i(8, 1)).valid, "overlay fixture places three windows")
	_expect(scene.accepted_plan.wall_cells.size() == 10 and scene.accepted_plan.openings.size() == 5, "five openings retain all ten authoritative wall cells")
	_expect(renderer.rendered_wall_count() == 10 and renderer.rendered_opening_count() == 5, "ten wall cells render ten bases plus five overlays")
	_expect(renderer.rendered_atlas(&"wall", Vector2i(2, 1)) == Vector2i(0, 0) and renderer.rendered_atlas(&"opening", Vector2i(2, 1)) == Vector2i(1, 2), "one logical opening cell contains both its wall base and door overlay")
	var walls_before: Array[Vector2i] = scene.accepted_plan.wall_cells.duplicate()
	scene._set_tool(&"window", "")
	_expect(scene.apply_tool_at(Vector2i(2, 1)).valid and scene.accepted_plan.wall_cells == walls_before and scene.accepted_plan.openings.size() == 5 and scene.accepted_plan.openings[Vector2i(2, 1)].kind == "window", "door replacement changes only its opening record")
	scene._set_tool(&"remove", "")
	_expect(scene.apply_tool_at(Vector2i(2, 1)).valid and scene.accepted_plan.wall_cells == walls_before and renderer.rendered_wall_count() == 10 and renderer.rendered_opening_count() == 4, "opening removal deletes only its overlay and leaves every base wall")
	scene.queue_free()
	await process_frame


func _validate_scene_and_rendering() -> void:
	var scene := SnapshotScene.instantiate()
	root.add_child(scene)
	await process_frame
	var renderer: Node2D = scene.get_node("SnapshotPanel/PrototypeRenderer")
	var rectangle := _perimeter(Vector2i(2, 2), Vector2i(5, 4))
	scene.begin_wall_mode()
	scene.set_pending_walls_for_validation(rectangle)
	_expect(scene.confirm_pending_walls().valid, "snapshot wall confirmation creates authoritative wall cells")
	_expect(renderer.rendered_wall_count() == rectangle.size() and renderer.rendered_floor_count() == 0, "renderer writes one base wall tile per wall and no implicit floors")
	scene._set_tool(&"fill_floor", "")
	_expect(scene.apply_tool_at(Vector2i(3, 3)).valid and renderer.rendered_floor_count() == 6, "explicit fill writes one floor tile per enclosed cell")
	scene._set_tool(&"door", "")
	_expect(scene.apply_tool_at(Vector2i(4, 2)).valid, "scene places an east/west door")
	_expect(scene.apply_tool_at(Vector2i(6, 3)).valid, "scene places a north/south door")
	scene._set_tool(&"window", "")
	_expect(scene.apply_tool_at(Vector2i(2, 4)).valid, "scene places a north/south window")
	_expect(scene.apply_tool_at(Vector2i(4, 5)).valid, "scene places an east/west window")
	_expect(renderer.rendered_wall_count() == rectangle.size() and renderer.rendered_opening_count() == 4, "openings overlay without reducing base wall writes")
	_expect(renderer.rendered_atlas(&"opening", Vector2i(4, 2)) == Vector2i(1, 2) and renderer.rendered_atlas(&"opening", Vector2i(6, 3)) == Vector2i(0, 2), "both calibrated door art planes render at their cells")
	_expect(renderer.rendered_atlas(&"opening", Vector2i(4, 5)) == Vector2i(3, 2) and renderer.rendered_atlas(&"opening", Vector2i(2, 4)) == Vector2i(2, 2), "both calibrated window art planes render at their cells")
	_expect(renderer.rendered_atlas(&"wall", Vector2i(4, 2)) == Vector2i(0, 0) and renderer.rendered_atlas(&"wall", Vector2i(2, 4)) == Vector2i(0, 0), "opening cells retain their base wall writes")
	_expect(renderer.rendered_layer_position(&"wall") == renderer.rendered_layer_position(&"opening") and renderer.rendered_layer_position(&"wall") - renderer.rendered_layer_position(&"floor") == Vector2(0, 8), "wall and opening layers share the eight-pixel presentation offset")
	scene._set_tool(&"remove", "")
	_expect(scene.apply_tool_at(Vector2i(4, 2)).valid and renderer.rendered_wall_count() == rectangle.size() and renderer.rendered_opening_count() == 3, "removing an opening leaves base wall rendering unchanged")
	_expect(renderer.rendered_roof_count() == 0, "roof layer remains empty and suppressed")
	_expect(not _script_mentions_legacy_snapshot_path(), "interactive snapshot controller and renderer do not use legacy span or corner packing")
	scene.queue_free()
	await process_frame


func _script_mentions_legacy_snapshot_path() -> bool:
	for path: String in [
		"res://experimental/procedural_building_research/prototype_snapshot_controller.gd",
		"res://experimental/procedural_building_research/prototype_snapshot_renderer.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		if "building_wall_span_resolver" in source or "building_visual_wall_tiler" in source:
			return true
	return false


func _perimeter(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(origin.x, origin.x + size.x):
		cells.append(Vector2i(x, origin.y))
		cells.append(Vector2i(x, origin.y + size.y - 1))
	for y in range(origin.y + 1, origin.y + size.y - 1):
		cells.append(Vector2i(origin.x, y))
		cells.append(Vector2i(origin.x + size.x - 1, y))
	return cells


func _no_overlap(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	for cell: Vector2i in a:
		if b.has(cell):
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)
