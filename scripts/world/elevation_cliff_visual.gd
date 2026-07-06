extends Node2D
class_name ElevationStackVisual

## Purpose: Project elevated terrain as stacked isometric tiles in one world-space visual.
## Responsibility: Cache rendered cells by chunk without calculating coordinates or owning terrain state.
## Assumption: CellRenderInfo is the sole source of atlas roles and layer positions; this node owns no gameplay state.

const STANDALONE_CHUNK_KEY := Vector2i(2147483647, 2147483647)

var _layers_by_offset: Dictionary = {}
var _cells_by_chunk: Dictionary = {}


func configure(tile_set: TileSet, render_infos: Array[Dictionary]) -> void:
	_clear_layers()
	_cells_by_chunk.clear()
	_write_chunk(tile_set, STANDALONE_CHUNK_KEY, render_infos)


func configure_chunks(tile_set: TileSet, render_infos_by_chunk: Dictionary) -> void:
	## Explicit global rebuild path for imports, restores, and debug refreshes.
	_clear_layers()
	_cells_by_chunk.clear()
	for chunk_coord_value: Variant in render_infos_by_chunk:
		var chunk_coord: Vector2i = chunk_coord_value
		var render_infos: Array[Dictionary] = []
		render_infos.assign(render_infos_by_chunk[chunk_coord])
		_write_chunk(tile_set, chunk_coord, render_infos)


func configure_chunk(tile_set: TileSet, chunk_coord: Vector2i, render_infos: Array[Dictionary]) -> void:
	_remove_chunk_cells(chunk_coord)
	_write_chunk(tile_set, chunk_coord, render_infos)


func remove_chunk(chunk_coord: Vector2i) -> void:
	_remove_chunk_cells(chunk_coord)


func _write_chunk(tile_set: TileSet, chunk_coord: Vector2i, render_infos: Array[Dictionary]) -> void:
	var cells_by_offset: Dictionary = {}
	for render_info: Dictionary in render_infos:
		for stack_layer_value: Variant in render_info.get("stack_layers", []):
			var stack_layer: Dictionary = stack_layer_value as Dictionary
			var layer_offset: Vector2 = stack_layer.get("layer_offset", Vector2.ZERO)
			var layer_key: int = roundi(layer_offset.y)
			var layer: TileMapLayer = _get_or_create_layer(tile_set, layer_offset)
			var cell: Vector2i = render_info.get("cell", Vector2i.ZERO)
			layer.set_cell(
				cell,
				int(render_info.get("source_id", -1)),
				stack_layer.get("atlas_coords", Vector2i(-1, -1))
			)
			if not cells_by_offset.has(layer_key):
				cells_by_offset[layer_key] = {}
			(cells_by_offset[layer_key] as Dictionary)[cell] = true
	_cells_by_chunk[chunk_coord] = cells_by_offset


func _remove_chunk_cells(chunk_coord: Vector2i) -> void:
	if not _cells_by_chunk.has(chunk_coord):
		return
	var cells_by_offset: Dictionary = _cells_by_chunk[chunk_coord]
	for layer_key_value: Variant in cells_by_offset:
		var layer_key: int = int(layer_key_value)
		if not _layers_by_offset.has(layer_key):
			continue
		var layer: TileMapLayer = _layers_by_offset[layer_key] as TileMapLayer
		for cell_value: Variant in (cells_by_offset[layer_key] as Dictionary).keys():
			layer.erase_cell(cell_value as Vector2i)
	_cells_by_chunk.erase(chunk_coord)


func _clear_layers() -> void:
	for layer_value: Variant in _layers_by_offset.values():
		(layer_value as TileMapLayer).clear()


func _get_or_create_layer(tile_set: TileSet, layer_position: Vector2) -> TileMapLayer:
	var key: int = roundi(layer_position.y)
	if _layers_by_offset.has(key):
		return _layers_by_offset[key] as TileMapLayer
	var layer := TileMapLayer.new()
	layer.name = "Elevation_%d" % abs(key)
	layer.tile_set = tile_set
	layer.position = layer_position
	_layers_by_offset[key] = layer
	add_child(layer)
	return layer
