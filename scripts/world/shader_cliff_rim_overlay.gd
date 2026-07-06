extends Node2D
class_name ShaderCliffRimOverlay

## Purpose: Render presentation-only cliff rims from a bounded elevation texture.
## Responsibility: Own the transient R8 texture, chunk texel ownership, and shader-covered polygon.
## Assumption: Loaded cells span fewer cells than texture_size on each axis, avoiding ring-slot collisions.

const RimShader = preload("res://scripts/world/shader_cliff_rim_overlay.gdshader")

var _texture_size: int = 256
var _image: Image
var _texture: ImageTexture
var _polygon: Polygon2D
var _material: ShaderMaterial
var _cells_by_chunk: Dictionary = {}
var _slot_owner: Dictionary = {}


func configure(
		texture_size: int,
		map_origin: Vector2,
		map_step_x: Vector2,
		map_step_y: Vector2,
		color: Color,
		alpha: float,
		width: float,
		vertical_offset: float,
		softness: float,
		direction_mode: int,
		debug_elevation: bool
) -> void:
	_texture_size = maxi(texture_size, 64)
	_image = Image.create(_texture_size, _texture_size, false, Image.FORMAT_R8)
	_image.fill(Color.BLACK)
	_texture = ImageTexture.create_from_image(_image)
	_material = ShaderMaterial.new()
	_material.shader = RimShader
	_material.set_shader_parameter("elevation_texture", _texture)
	_material.set_shader_parameter("elevation_texture_size", Vector2(_texture_size, _texture_size))
	_material.set_shader_parameter("map_origin", map_origin)
	_material.set_shader_parameter("map_step_x", map_step_x)
	_material.set_shader_parameter("map_step_y", map_step_y)
	_material.set_shader_parameter("rim_color", Color(color, clampf(alpha, 0.0, 1.0)))
	_material.set_shader_parameter("rim_width", maxf(width, 0.1))
	_material.set_shader_parameter("vertical_offset", vertical_offset)
	_material.set_shader_parameter("rim_softness", maxf(softness, 0.0))
	set_direction_mode(direction_mode)
	set_debug_elevation(debug_elevation)
	_polygon = Polygon2D.new()
	_polygon.name = "ShaderRimPolygon"
	_polygon.color = Color.WHITE
	_polygon.material = _material
	add_child(_polygon)


func set_direction_mode(direction_mode: int) -> void:
	## Uniform-only presentation update; elevation texture ownership is unchanged.
	if _material == null:
		return
	var direction_mask := Vector4.ONE
	match clampi(direction_mode, 0, 3):
		1:
			direction_mask = Vector4(1.0, 0.0, 0.0, 1.0)
		2:
			direction_mask = Vector4(0.0, 1.0, 1.0, 0.0)
		3:
			direction_mask = Vector4.ZERO
	_material.set_shader_parameter("direction_mask", direction_mask)


func set_debug_elevation(enabled: bool) -> void:
	## Debug visualization is transient shader state and is never serialized.
	if _material != null:
		_material.set_shader_parameter("debug_elevation", enabled)


func update_chunk(chunk_coord: Vector2i, elevations_by_cell: Dictionary) -> void:
	remove_chunk(chunk_coord, false)
	var owned_cells: Dictionary = {}
	for cell_value: Variant in elevations_by_cell:
		var cell: Vector2i = cell_value
		var slot := _cell_to_slot(cell)
		var existing_owner: Variant = _slot_owner.get(slot)
		if existing_owner != null and existing_owner != chunk_coord:
			push_warning("Shader cliff-rim elevation texture slot collision at %s." % slot)
		_slot_owner[slot] = chunk_coord
		owned_cells[cell] = true
		_write_elevation(slot, int(elevations_by_cell[cell]))
	_cells_by_chunk[chunk_coord] = owned_cells
	_texture.update(_image)


func update_cell(chunk_coord: Vector2i, cell: Vector2i, elevation: int) -> void:
	if not _cells_by_chunk.has(chunk_coord):
		_cells_by_chunk[chunk_coord] = {}
	var slot := _cell_to_slot(cell)
	_slot_owner[slot] = chunk_coord
	(_cells_by_chunk[chunk_coord] as Dictionary)[cell] = true
	_write_elevation(slot, elevation)
	_texture.update(_image)


func remove_chunk(chunk_coord: Vector2i, upload: bool = true) -> void:
	if not _cells_by_chunk.has(chunk_coord):
		return
	for cell_value: Variant in (_cells_by_chunk[chunk_coord] as Dictionary):
		var cell: Vector2i = cell_value
		var slot := _cell_to_slot(cell)
		if _slot_owner.get(slot) != chunk_coord:
			continue
		_slot_owner.erase(slot)
		_write_elevation(slot, 0)
	_cells_by_chunk.erase(chunk_coord)
	if upload:
		_texture.update(_image)


func clear() -> void:
	_cells_by_chunk.clear()
	_slot_owner.clear()
	_image.fill(Color.BLACK)
	_texture.update(_image)


func set_overlay_bounds(world_rect: Rect2, min_cell: Vector2i, max_cell: Vector2i) -> void:
	if _polygon == null:
		return
	_polygon.polygon = PackedVector2Array([
		world_rect.position,
		Vector2(world_rect.end.x, world_rect.position.y),
		world_rect.end,
		Vector2(world_rect.position.x, world_rect.end.y),
	])
	_polygon.uv = PackedVector2Array([
		Vector2.ZERO,
		Vector2.RIGHT,
		Vector2.ONE,
		Vector2.DOWN,
	])
	_material.set_shader_parameter("loaded_cell_min", Vector2(min_cell))
	_material.set_shader_parameter("loaded_cell_max", Vector2(max_cell))


func _cell_to_slot(cell: Vector2i) -> Vector2i:
	return Vector2i(posmod(cell.x, _texture_size), posmod(cell.y, _texture_size))


func _write_elevation(slot: Vector2i, elevation: int) -> void:
	_image.set_pixelv(slot, Color(float(clampi(elevation, 0, 2)) * 0.5, 0.0, 0.0, 1.0))
