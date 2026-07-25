extends Node2D
class_name ConnectionMarkerVisual

## Purpose: Present one active-WorldSpace endpoint of an authoritative Connection.
## Responsibility: Render the configured shared-TileSet endpoint asset and expose immutable hit-test metadata.
## Assumption: ChunkManager reconstructs this node; it owns no topology or interaction state.

const HIT_RADIUS := 24.0
const TILE_SOURCE_ID := 2
const SURFACE_HOLE_ATLAS_COORDS := Vector2i(5, 7)
const MINE_LADDER_ATLAS_COORDS := Vector2i(5, 8)
## Assign the four directional cave entrance textures at these paths when art is available.
const DIRECTIONAL_CAVE_OVERLAY_SPRITE_PATHS := {
	"north": "res://assets/sprites/cave_entrance_north.png",
	"east": "res://assets/sprites/cave_entrance_east.png",
	"south": "res://assets/sprites/cave_entrance_south.png",
	"west": "res://assets/sprites/cave_entrance_west.png",
}

var connection_id: String = ""
var world_space_id: String = ""
var cell: Vector2i = Vector2i.ZERO
var action_label: String = ""
var _is_cave_exit: bool = false
var _atlas_coords: Vector2i = SURFACE_HOLE_ATLAS_COORDS
var _tile_layer: TileMapLayer
var _hit_local_position: Vector2 = Vector2.ZERO
var _cave_entrance_facing := "south"
var _cave_overlay: Sprite2D


func configure(tile_set: TileSet, id: String, active_world_space_id: String, endpoint_cell: Vector2i, elevation: int, label: String, is_cave_exit: bool, cave_entrance_facing: String = "south") -> void:
	connection_id = id
	world_space_id = active_world_space_id
	cell = endpoint_cell
	action_label = label
	_is_cave_exit = is_cave_exit
	_cave_entrance_facing = cave_entrance_facing if DIRECTIONAL_CAVE_OVERLAY_SPRITE_PATHS.has(cave_entrance_facing) else "south"
	_atlas_coords = MINE_LADDER_ATLAS_COORDS if is_cave_exit else SURFACE_HOLE_ATLAS_COORDS
	if _tile_layer == null:
		_tile_layer = TileMapLayer.new()
		_tile_layer.name = "EndpointTile"
		add_child(_tile_layer)
	_tile_layer.tile_set = tile_set
	_tile_layer.set_cell(endpoint_cell, TILE_SOURCE_ID, _atlas_coords)
	position = CellRenderInfo.BLOCK_LAYER_OFFSET * clampi(elevation, 0, 2)
	_hit_local_position = _tile_layer.map_to_local(endpoint_cell) + CellRenderInfo.TOP_DIAMOND_OFFSET
	_configure_cave_entrance_overlay()
	z_index = 1
	queue_redraw()

func _configure_cave_entrance_overlay() -> void:
	if _is_cave_exit:
		return
	var sprite_path: String = DIRECTIONAL_CAVE_OVERLAY_SPRITE_PATHS[_cave_entrance_facing]
	if not ResourceLoader.exists(sprite_path):
		return
	if _cave_overlay == null:
		_cave_overlay = Sprite2D.new()
		_cave_overlay.name = "DirectionalCaveEntranceOverlay"
		add_child(_cave_overlay)
	_cave_overlay.texture = load(sprite_path) as Texture2D
	_cave_overlay.position = _hit_local_position
	_cave_overlay.z_index = 2

func _draw() -> void:
	## Fallback until the four assets listed above are supplied; never affects connection state.
	if _is_cave_exit or _cave_overlay != null:
		return
	var direction := _facing_vector(_cave_entrance_facing)
	var center := _hit_local_position
	draw_circle(center, 13.0, Color("27303a"))
	draw_arc(center, 13.0, 0.0, TAU, 16, Color("9aa4ad"), 2.0)
	draw_colored_polygon(PackedVector2Array([center + direction * 18.0, center + Vector2(-direction.y, direction.x) * 7.0, center + Vector2(direction.y, -direction.x) * 7.0]), Color("d1a85a"))

func _facing_vector(facing: String) -> Vector2:
	match facing:
		"north": return Vector2.UP
		"east": return Vector2.RIGHT
		"west": return Vector2.LEFT
		_: return Vector2.DOWN


func get_context_snapshot() -> Dictionary:
	return {
		"connection_id": connection_id,
		"world_space_id": world_space_id,
		"cell": cell,
		"action_label": action_label,
		"is_cave_exit": _is_cave_exit,
		"cave_entrance_facing": _cave_entrance_facing,
		"source_id": _tile_layer.get_cell_source_id(cell) if _tile_layer != null else -1,
		"atlas_coords": _tile_layer.get_cell_atlas_coords(cell) if _tile_layer != null else Vector2i(-1, -1),
	}


func contains_world_position(world_position: Vector2) -> bool:
	return get_visual_world_position().distance_squared_to(world_position) <= HIT_RADIUS * HIT_RADIUS


func get_visual_world_position() -> Vector2:
	return to_global(_hit_local_position)


func get_tile_anchor_world_position() -> Vector2:
	return _tile_layer.to_global(_tile_layer.map_to_local(cell)) if _tile_layer != null else global_position
