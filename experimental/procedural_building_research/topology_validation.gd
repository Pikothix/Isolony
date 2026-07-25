extends SceneTree

## Purpose: Focused automated validation for isolated building topology research.
## Ownership: Creates and discards only experiment-local layouts and scene instances.
## Integration: Run explicitly with Godot --script; it has no production dependencies.

const Layouts := preload("res://experimental/procedural_building_research/prototype_layouts.gd")
const Resolver := preload("res://experimental/procedural_building_research/building_topology_resolver.gd")
const PrototypeScene := preload("res://experimental/procedural_building_research/ProceduralBuildingPrototype.tscn")
const VisualStyles := preload("res://experimental/procedural_building_research/prototype_visual_styles.gd")
const VisualStyle := preload("res://experimental/procedural_building_research/building_visual_style.gd")
const VisualModule := preload("res://experimental/procedural_building_research/building_visual_module_definition.gd")
const WallConnectionAdapter := preload("res://experimental/procedural_building_research/building_wall_connection_adapter.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var rectangle := Resolver.new().resolve(Layouts.create(0))
	_expect(rectangle.exterior_edges.size() == 18, "5x4 rectangle has 18 derived perimeter edges")
	_expect(_unique_edge_count(rectangle.exterior_edges) == 18, "rectangle perimeter contains no duplicates")
	_expect(_corner_count(rectangle.corners, &"outer") == 4, "rectangle has four outer corners")
	_expect(_corner_count(rectangle.corners, &"inner") == 0, "rectangle has no concave corners")
	var rectangle_masks := _connection_masks_by_vertex(rectangle)
	_expect(rectangle_masks.get(Vector2i(0, 0)) == 9, "rectangle northwest vertex resolves NW")
	_expect(rectangle_masks.get(Vector2i(5, 0)) == 3, "rectangle northeast vertex resolves NE")
	_expect(rectangle_masks.get(Vector2i(0, 4)) == 12, "rectangle southwest vertex resolves SW")
	_expect(rectangle_masks.get(Vector2i(5, 4)) == 6, "rectangle southeast vertex resolves SE")
	_expect(rectangle_masks.get(Vector2i(1, 0)) == 1, "rectangle north run resolves N")
	_expect(rectangle_masks.get(Vector2i(5, 3)) == 2, "rectangle east run resolves E")
	_expect(rectangle_masks.get(Vector2i(4, 4)) == 4, "rectangle south run resolves S")
	_expect(rectangle_masks.get(Vector2i(0, 2)) == 8, "rectangle west run resolves W")

	var l_shape := Resolver.new().resolve(Layouts.create(1))
	_expect(l_shape.exterior_edges.size() == 18, "L shape has 18 derived perimeter edges")
	_expect(_unique_edge_count(l_shape.exterior_edges) == 18, "L-shape perimeter contains no duplicates")
	_expect(_corner_count(l_shape.corners, &"inner") == 1, "L shape identifies one concave corner")
	_expect(_has_corner(l_shape.corners, &"inner", &"north_east"), "L-shape concave corner orientation is north-east")
	_expect(_connection_masks_by_vertex(l_shape).get(Vector2i(3, 2)) == 3, "L-shape concave junction resolves NE")

	var two_room := Resolver.new().resolve(Layouts.create(2))
	_expect(two_room.exterior_edges.size() == 20, "6x4 two-room rectangle has 20 perimeter edges")
	_expect(two_room.interior_edges.size() == 4, "two-room divider has four shared edges rendered once")
	var interior_door_count := 0
	for edge: Dictionary in two_room.interior_edges:
		var opening: Dictionary = two_room.openings_by_edge.get(edge.key, {})
		if not opening.is_empty() and opening.kind == ExperimentalBuildingLayout.DOOR:
			interior_door_count += 1
	_expect(interior_door_count == 1, "two-room divider contains one doorway replacement")
	var two_room_masks := _connection_masks_by_vertex(two_room)
	_expect(two_room_masks.get(Vector2i(3, 0)) == 11, "two-room north divider junction resolves NWE")
	_expect(two_room_masks.get(Vector2i(3, 4)) == 14, "two-room south divider junction resolves SWE")
	_expect(two_room_masks.get(Vector2i(3, 2)) == 10 and two_room_masks.get(Vector2i(3, 3)) == 10, "interior doorway breaks the divider into WE terminals")

	var east_calibration := Resolver.new().resolve(Layouts.create(3))
	_expect(east_calibration.layout_id == &"east_door_calibration" and east_calibration.occupied_cells.size() == 16, "east-door calibration is an isolated 4x4 authored box")
	var east_opening_edge := _opening_edge(east_calibration)
	_expect(east_opening_edge.start == Vector2i(4, 1) and east_opening_edge.end == Vector2i(4, 2), "east-door calibration opening uses the authored east edge")
	_expect(east_opening_edge.direction == &"east", "east-door calibration resolves the confirmed east compass direction")

	var prototype := PrototypeScene.instantiate()
	root.add_child(prototype)
	await process_frame
	var generated_visuals: Node = prototype.get_node("GeneratedVisuals")
	prototype.set_style_by_index(0)
	generated_visuals.add_child(Node2D.new())
	prototype.set_layout(2)
	_expect(generated_visuals.get_child_count() == 0, "layout switching clears generated visual nodes immediately")
	await process_frame
	var diagnostics: Dictionary = prototype.get_diagnostic_summary()
	_expect(not diagnostics.missing_fallback_modules.is_empty(), "missing semantic modules use diagnosed fallbacks")
	var placeholder_style: Resource = VisualStyles.create_placeholder_style()
	_expect(placeholder_style.validate(), "authored placeholder visual style validates")
	_expect(placeholder_style.render_roofs and not placeholder_style.compact_missing_geometry, "placeholder style preserves full roof and fallback presentation")
	_expect(not placeholder_style.resolve(&"floor").used_fallback, "mapped semantic ID resolves through the visual style")
	_expect(placeholder_style.resolve(&"inner_corner_north_east").used_fallback, "unmapped semantic ID resolves to style fallback")
	var atlas_contract := VisualModule.new()
	atlas_contract.semantic_id = &"test_atlas"
	atlas_contract.visual_kind = &"floor"
	atlas_contract.source_kind = VisualModule.ATLAS_REGION
	atlas_contract.atlas_region = Rect2i(0, 0, 16, 16)
	_expect(not atlas_contract.is_valid(), "atlas contract rejects a missing texture reference")
	var authored_style: Resource = VisualStyles.create_authored_test_style()
	_expect(authored_style.validate(), "authored test visual style validates")
	_expect(not authored_style.render_roofs and authored_style.compact_missing_geometry, "authored style suppresses unsupported roofs and uses compact diagnostics")
	_expect(authored_style.cell_half == Vector2(16, 8) and authored_style.display_scale == 1.0, "authored style uses the TileSet native 32x16 projection")
	_expect(authored_style.use_wall_connection_masks, "authored style enables the presentation-only wall connection adapter")
	_expect(WallConnectionAdapter.mask_for_delta(Vector2i(0, -1)) == WallConnectionAdapter.NORTH, "delta (0,-1) contributes North only")
	_expect(WallConnectionAdapter.mask_for_delta(Vector2i(1, 0)) == WallConnectionAdapter.EAST, "delta (1,0) contributes East only")
	_expect(WallConnectionAdapter.mask_for_delta(Vector2i(0, 1)) == WallConnectionAdapter.SOUTH, "delta (0,1) contributes South only")
	_expect(WallConnectionAdapter.mask_for_delta(Vector2i(-1, 0)) == WallConnectionAdapter.WEST, "delta (-1,0) contributes West only")
	for semantic_id: StringName in [&"floor", &"floor_cool", &"door_north", &"door_east", &"door_south", &"door_west", &"window_north", &"window_east", &"window_south", &"window_west", &"roof_fill"]:
		_expect(not authored_style.resolve(semantic_id).used_fallback, "authored style maps %s" % semantic_id)
	_expect(authored_style.floor_module_for_room(&"main") == &"floor" and authored_style.floor_module_for_room(&"store") == &"floor_cool", "authored style selects floor semantics from room data with a default")
	_expect(authored_style.floor_module_for_room(&"unmapped_room") == &"floor", "unmapped room IDs use the default floor semantic")
	var invalid_floor_style: Resource = VisualStyles.create_authored_test_style()
	invalid_floor_style.floor_modules_by_room[&"invalid_room"] = &"missing_floor"
	_expect(not invalid_floor_style.validate(), "invalid explicit floor mappings fail style validation instead of silently omitting tiles")
	var expected_wall_atlas := {
		1: Vector2i(1, 0), 2: Vector2i(2, 1), 4: Vector2i(1, 2), 8: Vector2i(0, 1),
		3: Vector2i(2, 0), 5: Vector2i(1, 3), 9: Vector2i(0, 0), 6: Vector2i(2, 2),
		10: Vector2i(3, 1), 12: Vector2i(0, 2), 11: Vector2i(3, 0), 14: Vector2i(3, 2),
		13: Vector2i(0, 3), 7: Vector2i(2, 3), 15: Vector2i(3, 3),
	}
	for mask: int in expected_wall_atlas:
		var semantic_id := StringName("wall_connection_%s" % WallConnectionAdapter.MASK_NAMES[mask])
		var definition: Resource = authored_style.resolve(semantic_id).definition
		_expect(definition.source_kind == VisualModule.TILE_SET and definition.tile_source_id == 0 and definition.connection_mask == mask, "wall mask %s resolves through TileSet source 0" % mask)
		_expect(definition.atlas_coordinates == expected_wall_atlas[mask], "wall mask %s selects atlas %s" % [mask, expected_wall_atlas[mask]])
		_expect(_resolved_mask_at_origin(mask) == mask, "focused wall graph derives mask %s at its origin vertex" % mask)
	for semantic_id: StringName in [&"outer_corner_north_east", &"interior_wall_north_south", &"door_interior_north"]:
		_expect(authored_style.resolve(semantic_id).used_fallback, "authored style keeps uncertain %s on fallback" % semantic_id)
	var floor_definition: Resource = authored_style.resolve(&"floor").definition
	var cool_floor_definition: Resource = authored_style.resolve(&"floor_cool").definition
	_expect(floor_definition.source_kind == VisualModule.TILE_SET and floor_definition.tile_source_id == 0 and floor_definition.atlas_coordinates == Vector2i(4, 3), "floor uses prototype_test TileSet source 0 atlas (4,3)")
	_expect(_texture_origin(floor_definition) == Vector2i(0, 8) and _tile_region_size(floor_definition) == Vector2i(32, 32), "default floor trusts the authored 32x32 TileSet tile origin")
	_expect(cool_floor_definition.tile_source_id == 0 and cool_floor_definition.atlas_coordinates == Vector2i(4, 3) and _texture_origin(cool_floor_definition) == Vector2i(0, 8), "room-selected floor semantics share the supplied prototype floor module")
	_expect(_texture_origin(authored_style.resolve(&"wall_connection_n").definition) == Vector2i(0, 8), "wall modules preserve the saved TileSet texture origin")
	_expect(authored_style.resolve(&"wall_connection_we").definition.atlas_coordinates == Vector2i(3, 1), "WE wall uses atlas (3,1)")
	_expect(authored_style.resolve(&"wall_connection_swe").definition.atlas_coordinates == Vector2i(3, 2), "SWE wall uses distinct atlas (3,2)")
	var south_door: Resource = authored_style.resolve(&"door_south").definition
	var east_door: Resource = authored_style.resolve(&"door_east").definition
	_expect(south_door.source_kind == VisualModule.TILE_SET and south_door.tile_source_id == 0 and south_door.atlas_coordinates == Vector2i(5, 1), "south door uses prototype_test atlas (5,1)")
	_expect(east_door.source_kind == VisualModule.TILE_SET and east_door.tile_source_id == 0 and east_door.atlas_coordinates == Vector2i(4, 1), "east door uses prototype_test atlas (4,1)")
	for semantic_id: StringName in [&"floor", &"roof_fill", &"door_north", &"door_east", &"door_south", &"door_west", &"window_north", &"window_east", &"window_south", &"window_west"]:
		_expect(_texture_origin(authored_style.resolve(semantic_id).definition) == Vector2i(0, 8), "%s uses its authored TileSet origin" % semantic_id)
	_expect(authored_style.resolve(&"window_west").definition.atlas_coordinates == Vector2i(6, 0), "west window resolves the supplied duplicate label to atlas (6,0)")
	_expect(authored_style.resolve(&"window_east").definition.atlas_coordinates == Vector2i(6, 1), "east window resolves the supplied duplicate label to atlas (6,1)")
	_expect(floor_definition.z_offset == authored_style.resolve(&"wall_connection_n").definition.z_offset, "floors share the lower-wall z plane and rely on deterministic floor-first layer order")
	_expect(authored_style.resolve(&"wall_connection_n").definition.z_offset < authored_style.resolve(&"door_south").definition.z_offset, "doors have explicit z order above wall junctions")
	for layout_index in range(4):
		prototype.set_visual_style(placeholder_style)
		prototype.set_layout(layout_index)
		_expect(generated_visuals.get_child_count() == 0, "placeholder layout %d has no stale authored instances" % layout_index)
		prototype.set_visual_style(authored_style)
		_expect(_tile_layer_count(generated_visuals) == 3, "authored layout %d creates one floor, one wall, and one opening TileMapLayer" % layout_index)
		var resolved_layout: Dictionary = Resolver.new().resolve(Layouts.create(layout_index))
		var floor_layer := _floor_tile_layer(generated_visuals)
		_expect(floor_layer != null and _same_cells(floor_layer.get_used_cells(), resolved_layout.occupied_cells), "authored layout %d places exactly one floor tile on every occupied coordinate and nowhere else" % layout_index)
		if layout_index == 0:
			var wall_layer := _wall_tile_layer(generated_visuals)
			var door_layer := _tile_layer_by_z(generated_visuals, 1)
			_expect(floor_layer.position + floor_layer.map_to_local(Vector2i.ZERO) == Vector2.ZERO, "floor TileMap cell zero shares the calibration scene's map-lattice origin")
			_expect(floor_layer.z_index == 0 and not floor_layer.y_sort_enabled and floor_layer.z_as_relative, "floor layer uses the visible base canvas plane without y-sort")
			_expect(floor_layer.get_index() < wall_layer.get_index(), "floor layer is deterministically created before the same-plane wall layer")
			_expect(wall_layer.position + wall_layer.map_to_local(Vector2i.ZERO) == Vector2.ZERO, "wall TileMap cell zero aligns to the topology vertex")
			_expect(floor_layer.position == wall_layer.position, "floor and wall layers use the calibration scene's shared TileMap transform")
			_expect(door_layer.position == wall_layer.position and door_layer.scale == wall_layer.scale, "opening and wall layers share the same transform")
			_expect(Vector2i(2, 4) in door_layer.get_used_cells() and door_layer.get_cell_source_id(Vector2i(2, 4)) == 0 and door_layer.get_cell_atlas_coords(Vector2i(2, 4)) == Vector2i(5, 1), "rectangle south door uses its opening start vertex and supplied atlas tile")
			var opening_anchor := door_layer.position + door_layer.map_to_local(Vector2i(2, 4)) * door_layer.scale
			_expect(opening_anchor == Vector2(-32, 48), "rectangle south door resolves to the authoritative wall-edge anchor")
			_expect(opening_anchor - Vector2(_texture_origin(south_door)) - Vector2(16, 16) == Vector2(-48, 24), "south door TileSet region trusts the authored full-module origin")
			_expect(wall_layer.get_used_cells().size() == WallConnectionAdapter.new().resolve(resolved_layout).size(), "one resolved wall vertex produces exactly one wall cell write")
		var layout_diagnostics: Dictionary = prototype.get_diagnostic_summary()
		_expect(_floor_request_count(layout_diagnostics.resolved_instance_counts) == [20, 16, 24, 16][layout_index], "authored layout %d has one data-selected floor request per occupied cell" % layout_index)
		_expect(layout_diagnostics.floor_projection.size() == resolved_layout.occupied_cells.size(), "authored layout %d diagnostics report every floor placement without duplicates" % layout_index)
		for coordinate: Vector2i in resolved_layout.occupied_cells:
			var floor_record: Dictionary = layout_diagnostics.floor_projection.get(coordinate, {})
			var expected_semantic: StringName = authored_style.floor_module_for_room(resolved_layout.rooms[coordinate])
			_expect(floor_record.get("semantic_id", &"") == expected_semantic and floor_record.get("source_id", -1) == 0 and floor_record.get("atlas_coordinates", Vector2i(-1, -1)) == Vector2i(4, 3), "floor at %s preserves room selection and uses the supplied floor tile" % coordinate)
		_expect(_wall_request_count(layout_diagnostics.resolved_instance_counts) == WallConnectionAdapter.new().resolve(Resolver.new().resolve(Layouts.create(layout_index))).size(), "authored layout %d emits one module per wall-graph vertex" % layout_index)
		var expected_door := &"door_east" if layout_index == 3 else &"door_south"
		_expect(layout_diagnostics.resolved_instance_counts.get(expected_door, 0) == 1, "authored layout %d replaces one wall with %s" % [layout_index, expected_door])
		_expect(&"roof_fill" in layout_diagnostics.suppressed_visual_modules and &"roof_edge" in layout_diagnostics.suppressed_visual_modules, "authored layout %d reports roof semantics without rendering them" % layout_index)
		if layout_index < 3:
			_expect(layout_diagnostics.resolved_instance_counts.get(&"window_east", 0) == 1 and not layout_diagnostics.fallback_presentations.has(&"window_east"), "authored layout %d maps its east window as a wall replacement" % layout_index)
		else:
			var east_door_layer := _tile_layer_by_z(generated_visuals, 1)
			var east_wall_layer := _wall_tile_layer(generated_visuals)
			_expect(east_door_layer.get_used_cells() == [Vector2i(4, 1)] and east_door_layer.get_cell_source_id(Vector2i(4, 1)) == 0 and east_door_layer.get_cell_atlas_coords(Vector2i(4, 1)) == Vector2i(4, 1), "east calibration places the supplied east door at the opening start vertex")
			_expect(east_door_layer.position == east_wall_layer.position and east_door_layer.scale == east_wall_layer.scale, "east calibration door shares the wall-layer transform")
			var east_anchor := east_door_layer.position + east_door_layer.map_to_local(Vector2i(4, 1)) * east_door_layer.scale
			_expect(east_anchor == Vector2(48, 40), "east calibration door resolves to the authoritative wall-edge anchor")
		_expect(not layout_diagnostics.tile_set_modules.is_empty(), "authored layout %d reports TileSet source diagnostics" % layout_index)
	var topology_before_style_switch: Dictionary = prototype.get_generation_summary().duplicate()
	prototype.set_visual_style(authored_style)
	var topology_after_style_switch: Dictionary = prototype.get_generation_summary()
	_expect(topology_before_style_switch.layout == topology_after_style_switch.layout and topology_before_style_switch.occupied_cells == topology_after_style_switch.occupied_cells and topology_before_style_switch.exterior_edges == topology_after_style_switch.exterior_edges and topology_before_style_switch.interior_edges == topology_after_style_switch.interior_edges, "style switching does not change resolved topology")
	_expect(generated_visuals.get_child_count() > 0, "authored TileSet mappings create disposable visual layers")
	prototype.set_visual_style(placeholder_style)
	_expect(generated_visuals.get_child_count() == 0, "switching back to placeholder style clears authored instances")
	prototype.tile_module_debug = true
	prototype.set_layout(0)
	prototype.set_visual_style(authored_style)
	_expect(_tile_layer_count(generated_visuals) == 3, "optional TileSet debug mode does not alter generated visuals")
	prototype.tile_module_debug = false
	prototype.set_visual_style(placeholder_style)
	prototype.set_layout(2)
	var instance_style := VisualStyle.new()
	instance_style.style_id = &"validation_scene_instance"
	instance_style.fallback_module = _placeholder_definition(&"validation_fallback", &"fallback")
	var scene_definition := VisualModule.new()
	scene_definition.semantic_id = &"floor"
	scene_definition.visual_kind = &"floor"
	scene_definition.source_kind = VisualModule.PACKED_SCENE
	scene_definition.packed_scene = PackedScene.new()
	var packed_root := Node2D.new()
	_expect(scene_definition.packed_scene.pack(packed_root) == OK, "PackedScene visual module test fixture packs")
	packed_root.free()
	instance_style.add_module(scene_definition)
	prototype.set_visual_style(instance_style)
	_expect(generated_visuals.get_child_count() == 24, "PackedScene floor definitions create one visual module instance per occupied cell")
	prototype.queue_free()

	if _failures == 0:
		print("PROTOTYPE_TOPOLOGY_VALIDATION PASS")
		quit(0)
	else:
		push_error("PROTOTYPE_TOPOLOGY_VALIDATION FAILURES=%d" % _failures)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)


func _unique_edge_count(edges: Array) -> int:
	var keys: Dictionary = {}
	for edge: Dictionary in edges:
		keys[edge.key] = true
	return keys.size()


func _connection_masks_by_vertex(topology: Dictionary) -> Dictionary:
	var masks: Dictionary = {}
	for request: Dictionary in WallConnectionAdapter.new().resolve(topology):
		masks[request.vertex] = request.connection_mask
	return masks


func _corner_count(corners: Array, kind: StringName) -> int:
	var count := 0
	for corner: Dictionary in corners:
		count += 1 if corner.kind == kind else 0
	return count


func _has_corner(corners: Array, kind: StringName, direction: StringName) -> bool:
	for corner: Dictionary in corners:
		if corner.kind == kind and corner.direction == direction:
			return true
	return false


func _texture_origin(definition: Resource) -> Vector2i:
	var source := definition.tile_set.get_source(definition.tile_source_id) as TileSetAtlasSource
	return source.get_tile_data(definition.atlas_coordinates, definition.alternative_tile_id).texture_origin


func _tile_region_size(definition: Resource) -> Vector2i:
	var source := definition.tile_set.get_source(definition.tile_source_id) as TileSetAtlasSource
	return source.get_tile_texture_region(definition.atlas_coordinates).size


func _tile_layer_count(parent: Node) -> int:
	var count := 0
	for child: Node in parent.get_children():
		count += 1 if child is TileMapLayer else 0
	return count


func _tile_layer_by_z(parent: Node, z_index: int) -> TileMapLayer:
	for child: Node in parent.get_children():
		if child is TileMapLayer and child.z_index == z_index:
			return child
	return null


func _floor_tile_layer(parent: Node) -> TileMapLayer:
	for child: Node in parent.get_children():
		if child is TileMapLayer and child.name.begins_with("TileModules_cell"):
			return child
	return null


func _wall_tile_layer(parent: Node) -> TileMapLayer:
	var prefix := "TileModules_vertex_"
	for child: Node in parent.get_children():
		if child is TileMapLayer and child.name.begins_with(prefix):
			return child
	return null


func _wall_request_count(counts: Dictionary) -> int:
	var count := 0
	for semantic_id: Variant in counts:
		if String(semantic_id).begins_with("wall_connection_"):
			count += counts[semantic_id]
	return count


func _floor_request_count(counts: Dictionary) -> int:
	return counts.get(&"floor", 0) + counts.get(&"floor_cool", 0)


func _same_cells(actual: Array[Vector2i], expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	var actual_set: Dictionary = {}
	for cell: Vector2i in actual:
		actual_set[cell] = true
	if actual_set.size() != actual.size():
		return false
	for cell: Vector2i in expected:
		if not actual_set.has(cell):
			return false
	return true


func _resolved_mask_at_origin(expected_mask: int) -> int:
	var edges: Array[Dictionary] = []
	var deltas := {
		WallConnectionAdapter.NORTH: Vector2i(0, -1),
		WallConnectionAdapter.EAST: Vector2i(1, 0),
		WallConnectionAdapter.SOUTH: Vector2i(0, 1),
		WallConnectionAdapter.WEST: Vector2i(-1, 0),
	}
	var directions := {
		WallConnectionAdapter.NORTH: &"north",
		WallConnectionAdapter.EAST: &"east",
		WallConnectionAdapter.SOUTH: &"south",
		WallConnectionAdapter.WEST: &"west",
	}
	for direction_mask: int in deltas:
		if expected_mask & direction_mask:
			var endpoint: Vector2i = deltas[direction_mask]
			edges.append({"start": Vector2i.ZERO, "end": endpoint, "key": "0,0:%s,%s" % [endpoint.x, endpoint.y], "kind": &"exterior", "direction": directions[direction_mask]})
	var topology := {"exterior_edges": edges, "interior_edges": [], "openings_by_edge": {}}
	for request: Dictionary in WallConnectionAdapter.new().resolve(topology):
		if request.vertex == Vector2i.ZERO:
			return request.connection_mask
	return 0


func _opening_edge(topology: Dictionary) -> Dictionary:
	for edge: Dictionary in topology.exterior_edges:
		if topology.openings_by_edge.has(edge.key):
			return edge
	return {}


func _placeholder_definition(semantic_id: StringName, visual_kind: StringName) -> Resource:
	var definition := VisualModule.new()
	definition.semantic_id = semantic_id
	definition.visual_kind = visual_kind
	definition.compatibility_tags = [&"validation"]
	return definition
