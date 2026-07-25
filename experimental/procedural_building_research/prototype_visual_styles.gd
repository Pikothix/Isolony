class_name ExperimentalBuildingPrototypeVisualStyles
extends RefCounted

## Purpose: Author the current experiment-local visual style catalogue.
## Ownership: Creates fresh style/definition Resources; references no production content.
## Integration: Replace placeholder entries here as verified building modules are authored.

const Style := preload("res://experimental/procedural_building_research/building_visual_style.gd")
const Module := preload("res://experimental/procedural_building_research/building_visual_module_definition.gd")
const ConnectionAdapter := preload("res://experimental/procedural_building_research/building_wall_connection_adapter.gd")
const PROTOTYPE_TILESET := preload("res://prototype_test.tres")


static func create_placeholder_style() -> Resource:
	var style := Style.new()
	style.style_id = &"research_placeholder"
	style.fallback_module = _placeholder(&"missing_module_fallback", &"fallback")
	_add(style, &"floor", &"floor")
	for direction: StringName in [&"north", &"east", &"south", &"west"]:
		_add(style, StringName("exterior_wall_%s" % direction), &"exterior_wall", direction)
		_add(style, StringName("door_%s" % direction), &"door", direction)
		_add(style, StringName("window_%s" % direction), &"window", direction)
		_add(style, StringName("outer_corner_%s" % _corner_direction(direction)), &"outer_corner", _corner_direction(direction))
	_add(style, &"interior_wall_north_south", &"interior_wall", &"north_south")
	_add(style, &"interior_wall_east_west", &"interior_wall", &"east_west")
	_add(style, &"roof_fill", &"roof_fill")
	_add(style, &"roof_ridge", &"roof_ridge")
	assert(style.validate(), "Authored placeholder visual style is invalid")
	return style


static func create_authored_test_style() -> Resource:
	var style := Style.new()
	style.style_id = &"authored_test_style"
	style.cell_half = Vector2(16.0, 8.0)
	style.display_scale = 1.0
	style.render_roofs = false
	style.compact_missing_geometry = true
	style.use_wall_connection_masks = true
	style.fallback_module = _placeholder(&"missing_module_fallback", &"fallback")
	_add_tileset(style, &"floor", &"floor", Vector2i(4, 3), 0, 0, [&"floor", &"warm"])
	_add_tileset(style, &"floor_cool", &"floor", Vector2i(4, 3), 0, 0, [&"floor", &"cool"])
	style.floor_modules_by_room = {
		&"store": &"floor_cool",
		&"east_room": &"floor_cool",
	}
	var wall_tiles := {
		ConnectionAdapter.NORTH: Vector2i(1, 0),
		ConnectionAdapter.EAST: Vector2i(2, 1),
		ConnectionAdapter.SOUTH: Vector2i(1, 2),
		ConnectionAdapter.WEST: Vector2i(0, 1),
		ConnectionAdapter.NORTH | ConnectionAdapter.SOUTH: Vector2i(1, 3),
		ConnectionAdapter.EAST | ConnectionAdapter.WEST: Vector2i(3, 1),
		ConnectionAdapter.NORTH | ConnectionAdapter.WEST: Vector2i(0, 0),
		ConnectionAdapter.NORTH | ConnectionAdapter.EAST: Vector2i(2, 0),
		ConnectionAdapter.SOUTH | ConnectionAdapter.WEST: Vector2i(0, 2),
		ConnectionAdapter.SOUTH | ConnectionAdapter.EAST: Vector2i(2, 2),
		ConnectionAdapter.NORTH | ConnectionAdapter.WEST | ConnectionAdapter.EAST: Vector2i(3, 0),
		ConnectionAdapter.SOUTH | ConnectionAdapter.WEST | ConnectionAdapter.EAST: Vector2i(3, 2),
		ConnectionAdapter.NORTH | ConnectionAdapter.SOUTH | ConnectionAdapter.WEST: Vector2i(0, 3),
		ConnectionAdapter.SOUTH | ConnectionAdapter.NORTH | ConnectionAdapter.EAST: Vector2i(2, 3),
		ConnectionAdapter.NORTH | ConnectionAdapter.SOUTH | ConnectionAdapter.EAST | ConnectionAdapter.WEST: Vector2i(3, 3),
	}
	for mask: int in wall_tiles:
		var mask_name: StringName = ConnectionAdapter.MASK_NAMES[mask]
		_add_tileset(style, StringName("wall_connection_%s" % mask_name), &"wall_connection", wall_tiles[mask], mask, 0, [&"wall_connection", mask_name])
	_add_tileset(style, &"door_west", &"door", Vector2i(4, 0), 0, 1, [&"door", &"west"])
	_add_tileset(style, &"door_north", &"door", Vector2i(5, 0), 0, 1, [&"door", &"north"])
	_add_tileset(style, &"door_east", &"door", Vector2i(4, 1), 0, 1, [&"door", &"east"])
	_add_tileset(style, &"door_south", &"door", Vector2i(5, 1), 0, 1, [&"door", &"south"])
	_add_tileset(style, &"window_west", &"window", Vector2i(6, 0), 0, 1, [&"window", &"west"])
	_add_tileset(style, &"window_north", &"window", Vector2i(7, 0), 0, 1, [&"window", &"north"])
	_add_tileset(style, &"window_east", &"window", Vector2i(6, 1), 0, 1, [&"window", &"east"])
	_add_tileset(style, &"window_south", &"window", Vector2i(7, 1), 0, 1, [&"window", &"south"])
	_add_tileset(style, &"roof_fill", &"roof_fill", Vector2i(4, 2), 0, 2, [&"roof"])
	assert(style.validate(), "Authored test visual style is invalid")
	return style


static func create_snapshot_cell_style() -> Resource:
	# This catalogue is deliberately separate from the legacy topology/connection-mask style.
	var style := Style.new()
	style.style_id = &"snapshot_full_cell_style"
	style.cell_half = Vector2(16.0, 8.0)
	style.display_scale = 1.0
	style.render_roofs = false
	style.fallback_module = _placeholder(&"missing_module_fallback", &"fallback")
	_add_tileset(style, &"wall", &"wall", Vector2i(0, 0), 0, 0, [&"full_cell"])
	# Semantic suffixes describe grid connectivity; the isometric art planes appear on the opposite named screen axis.
	_add_tileset(style, &"door_east_west", &"door", Vector2i(1, 2), 0, 1, [&"east_west"])
	_add_tileset(style, &"door_north_south", &"door", Vector2i(0, 2), 0, 1, [&"north_south"])
	_add_tileset(style, &"window_east_west", &"window", Vector2i(3, 2), 0, 1, [&"east_west"])
	_add_tileset(style, &"window_north_south", &"window", Vector2i(2, 2), 0, 1, [&"north_south"])
	_add_tileset(style, &"floor", &"floor", Vector2i(4, 1), 0, 0, [&"full_cell"])
	_add_tileset(style, &"roof_fill", &"roof_fill", Vector2i(4, 0), 0, 2, [&"roof", &"suppressed"])
	assert(style.validate(), "Snapshot full-cell visual style is invalid")
	return style


static func _add(style: Resource, semantic_id: StringName, visual_kind: StringName, facing: StringName = &"") -> void:
	style.add_module(_placeholder(semantic_id, visual_kind, facing))


static func _placeholder(semantic_id: StringName, visual_kind: StringName, facing: StringName = &"") -> Resource:
	var definition := Module.new()
	definition.semantic_id = semantic_id
	definition.visual_kind = visual_kind
	definition.facing = facing
	definition.compatibility_tags = [&"research_placeholder"]
	return definition


static func _add_tileset(style: Resource, semantic_id: StringName, visual_kind: StringName, coordinates: Vector2i, mask: int, z_offset: int, extra_tags: Array[StringName]) -> void:
	var definition := Module.new()
	definition.semantic_id = semantic_id
	definition.visual_kind = visual_kind
	definition.source_kind = Module.TILE_SET
	definition.tile_set = PROTOTYPE_TILESET
	definition.tile_source_id = 0
	definition.atlas_coordinates = coordinates
	definition.alternative_tile_id = 0
	definition.connection_mask = mask
	definition.z_offset = z_offset
	definition.compatibility_tags = [&"prototype_test_tileset", &"isometric_32x16", &"authored_test_style"]
	definition.compatibility_tags.append_array(extra_tags)
	definition.confidence = &"authoritative_tileset"
	definition.notes = "Calibration, atlas extent, and texture origin are owned by prototype_test.tres."
	style.add_module(definition)


static func _corner_direction(cardinal: StringName) -> StringName:
	match cardinal:
		&"north": return &"north_east"
		&"east": return &"south_east"
		&"south": return &"south_west"
		_: return &"north_west"
