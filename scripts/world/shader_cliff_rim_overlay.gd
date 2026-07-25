extends Node2D
class_name ShaderCliffRimOverlay

## Purpose: Render presentation-only cliff rims from a bounded elevation texture.
## Responsibility: Own the transient R8 texture, chunk texel ownership, and shader-covered polygon.
## Assumption: Loaded cells plus the one-cell neighbour halo span fewer cells than texture_size on each axis, avoiding ring-slot collisions.

const RimShader = preload("res://scripts/world/shader_cliff_rim_overlay.gdshader")

var _texture_size: int = 256
var _image: Image
var _texture: ImageTexture
var _loaded_image: Image
var _loaded_texture: ImageTexture
var _polygon: Polygon2D
var _material: ShaderMaterial
var _cells_by_chunk: Dictionary = {}
var _slot_owner: Dictionary = {}
var _slot_cell: Dictionary = {}
var _loaded_cells_by_chunk: Dictionary = {}
var _map_origin: Vector2
var _map_step_x: Vector2
var _map_step_y: Vector2
var _vertical_offset: float
var _rim_width: float
var _rim_softness: float
var _direction_mask: Vector4 = Vector4.ONE


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
	_map_origin = map_origin
	_map_step_x = map_step_x
	_map_step_y = map_step_y
	_vertical_offset = vertical_offset
	_rim_width = maxf(width, 0.1)
	_rim_softness = maxf(softness, 0.0)
	_image = Image.create(_texture_size, _texture_size, false, Image.FORMAT_R8)
	_image.fill(Color.BLACK)
	_texture = ImageTexture.create_from_image(_image)
	_loaded_image = Image.create(_texture_size, _texture_size, false, Image.FORMAT_R8)
	_loaded_image.fill(Color.BLACK)
	_loaded_texture = ImageTexture.create_from_image(_loaded_image)
	_material = ShaderMaterial.new()
	_material.shader = RimShader
	_material.set_shader_parameter("elevation_texture", _texture)
	_material.set_shader_parameter("loaded_cell_texture", _loaded_texture)
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
	_direction_mask = direction_mask
	_material.set_shader_parameter("direction_mask", direction_mask)


func set_debug_elevation(enabled: bool) -> void:
	## Debug visualization is transient shader state and is never serialized.
	if _material != null:
		_material.set_shader_parameter("debug_elevation", enabled)


func update_chunk(chunk_coord: Vector2i, elevations_by_cell: Dictionary, loaded_cells: Array = []) -> void:
	remove_chunk(chunk_coord, false)
	var owned_cells: Dictionary = {}
	for cell_value: Variant in elevations_by_cell:
		var cell: Vector2i = cell_value
		var slot := _cell_to_slot(cell)
		var existing_owner: Variant = _slot_owner.get(slot)
		if existing_owner != null and existing_owner != chunk_coord and _slot_cell.get(slot) != cell:
			push_warning("Shader cliff-rim elevation texture slot collision at %s." % slot)
		_slot_owner[slot] = chunk_coord
		_slot_cell[slot] = cell
		owned_cells[cell] = true
		_write_elevation(slot, int(elevations_by_cell[cell]))
	_cells_by_chunk[chunk_coord] = owned_cells
	var loaded_lookup: Dictionary = {}
	for cell_value: Variant in loaded_cells:
		var cell: Vector2i = cell_value
		loaded_lookup[cell] = true
		_loaded_image.set_pixelv(_cell_to_slot(cell), Color.WHITE)
	_loaded_cells_by_chunk[chunk_coord] = loaded_lookup
	_texture.update(_image)
	_loaded_texture.update(_loaded_image)


func update_cell(chunk_coord: Vector2i, cell: Vector2i, elevation: int) -> void:
	if not _cells_by_chunk.has(chunk_coord):
		_cells_by_chunk[chunk_coord] = {}
	var slot := _cell_to_slot(cell)
	_slot_owner[slot] = chunk_coord
	_slot_cell[slot] = cell
	(_cells_by_chunk[chunk_coord] as Dictionary)[cell] = true
	_write_elevation(slot, elevation)
	_texture.update(_image)


func remove_chunk(chunk_coord: Vector2i, upload: bool = true) -> void:
	if not _cells_by_chunk.has(chunk_coord) and not _loaded_cells_by_chunk.has(chunk_coord):
		return
	for cell_value: Variant in (_cells_by_chunk.get(chunk_coord, {}) as Dictionary):
		var cell: Vector2i = cell_value
		var slot := _cell_to_slot(cell)
		if _slot_owner.get(slot) != chunk_coord:
			continue
		_slot_owner.erase(slot)
		_slot_cell.erase(slot)
		_write_elevation(slot, 0)
	_cells_by_chunk.erase(chunk_coord)
	for cell_value: Variant in (_loaded_cells_by_chunk.get(chunk_coord, {}) as Dictionary):
		_loaded_image.set_pixelv(_cell_to_slot(cell_value as Vector2i), Color.BLACK)
	_loaded_cells_by_chunk.erase(chunk_coord)
	if upload:
		_texture.update(_image)
		_loaded_texture.update(_loaded_image)


func clear() -> void:
	_cells_by_chunk.clear()
	_slot_owner.clear()
	_slot_cell.clear()
	_loaded_cells_by_chunk.clear()
	_image.fill(Color.BLACK)
	_loaded_image.fill(Color.BLACK)
	_texture.update(_image)
	_loaded_texture.update(_loaded_image)


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


func get_debug_elevation_at_cell(cell: Vector2i) -> int:
	## Focused validation seam: decode the exact R8 texel sampled by the shader.
	if _image == null:
		return 0
	var red: float = _image.get_pixelv(_cell_to_slot(cell)).r
	return clampi(roundi(red * 2.0), 0, 2)


func get_debug_loaded_at_cell(cell: Vector2i) -> bool:
	## Decode the exact nearest-filtered R8 loaded-mask texel sampled by the shader.
	if _loaded_image == null:
		return false
	return _loaded_image.get_pixelv(_cell_to_slot(cell)).r > 0.5


func get_debug_exposed_directions(cell: Vector2i) -> Array[String]:
	var directions: Array[String] = []
	var current_elevation: int = get_debug_elevation_at_cell(cell)
	for entry: Dictionary in [
		{"name": "north", "offset": Vector2i.UP},
		{"name": "east", "offset": Vector2i.RIGHT},
		{"name": "south", "offset": Vector2i.DOWN},
		{"name": "west", "offset": Vector2i.LEFT},
	]:
		if current_elevation > get_debug_elevation_at_cell(cell + (entry["offset"] as Vector2i)):
			directions.append(String(entry["name"]))
	return directions


func get_debug_fragment_analysis(local_world_position: Vector2) -> Dictionary:
	## GDScript replica of the shader's pixel-to-cell conversion and edge coverage.
	var candidates: Array[Dictionary] = []
	var rim_strength: float = 0.0
	var rim_edge_selected: bool = false
	var visible_surface_selected: bool = false
	var valid_surface_count: int = 0
	var visible_owner: Dictionary = {}
	var determinant: float = _map_step_x.x * _map_step_y.y - _map_step_y.x * _map_step_x.y
	for elevation_level in range(0, 3):
		var top_offset := Vector2(0.0, -16.0 * elevation_level - 8.0 + _vertical_offset)
		var relative: Vector2 = local_world_position - _map_origin - top_offset
		var continuous_cell := Vector2(
			(relative.x * _map_step_y.y - relative.y * _map_step_y.x) / determinant,
			(_map_step_x.x * relative.y - _map_step_x.y * relative.x) / determinant
		)
		# Match TileMapLayer.local_to_map() on exact isometric diamond edges.
		var derived_cell_vector := Vector2(
			ceilf(continuous_cell.x - 0.5),
			floorf(continuous_cell.y + 0.5)
		)
		var derived_cell := Vector2i(int(derived_cell_vector.x), int(derived_cell_vector.y))
		var local_basis: Vector2 = continuous_cell - derived_cell_vector
		var loaded: bool = get_debug_loaded_at_cell(derived_cell)
		var sampled_elevation: int = get_debug_elevation_at_cell(derived_cell)
		var candidate := {
			"elevation_level": elevation_level,
			"continuous_cell": continuous_cell,
			"derived_cell": derived_cell,
			"local_basis": local_basis,
			"loaded": loaded,
			"sampled_elevation": sampled_elevation,
			"neighbour_elevations": {},
			"edge_exists": {},
			"edge_bands": {},
			"edge_coverages": {},
			"coverage": 0.0,
			"rim_strength": 0.0,
			"output_reason": "not_visible_owner",
		}
		if not loaded or sampled_elevation != elevation_level or absf(local_basis.x) > 0.5 or absf(local_basis.y) > 0.5:
			candidates.append(candidate)
			continue
		if visible_surface_selected:
			candidate["occluded_by_lower_surface"] = true
			candidates.append(candidate)
			valid_surface_count += 1
			continue
		visible_surface_selected = true
		valid_surface_count += 1
		visible_owner = candidate
		if elevation_level == 0:
			candidate["output_reason"] = "visible_owner_e0"
			candidates.append(candidate)
			continue
		var distances := {
			"north": absf(local_basis.y + 0.5) * 14.310835,
			"east": absf(local_basis.x - 0.5) * 14.310835,
			"south": absf(local_basis.y - 0.5) * 14.310835,
			"west": absf(local_basis.x + 0.5) * 14.310835,
		}
		var neighbour_offsets := {
			"north": Vector2i.UP,
			"east": Vector2i.RIGHT,
			"south": Vector2i.DOWN,
			"west": Vector2i.LEFT,
		}
		var mask_lookup := {
			"north": _direction_mask.x,
			"east": _direction_mask.y,
			"south": _direction_mask.z,
			"west": _direction_mask.w,
		}
		var candidate_coverage: float = 0.0
		var edge_exists: Dictionary = {}
		var edge_bands: Dictionary = {}
		var edge_coverages: Dictionary = {}
		for direction: String in distances:
			var neighbour_elevation: int = get_debug_elevation_at_cell(derived_cell + (neighbour_offsets[direction] as Vector2i))
			var has_downward_edge: bool = float(mask_lookup[direction]) > 0.0 and sampled_elevation > neighbour_elevation
			var edge_band: float = _edge_coverage(float(distances[direction]))
			var coverage: float = edge_band if has_downward_edge and edge_band > 0.0 else 0.0
			(candidate["neighbour_elevations"] as Dictionary)[direction] = neighbour_elevation
			edge_exists[direction] = has_downward_edge
			edge_bands[direction] = edge_band
			edge_coverages[direction] = coverage
			candidate_coverage = maxf(candidate_coverage, coverage)
			if coverage > 0.0:
				rim_edge_selected = true
		candidate["edge_coverages"] = edge_coverages
		candidate["edge_exists"] = edge_exists
		candidate["edge_bands"] = edge_bands
		candidate["coverage"] = candidate_coverage
		candidate["rim_strength"] = candidate_coverage
		candidate["output_reason"] = "rim_edge_band" if candidate_coverage > 0.0 else "no_downward_edge_in_band"
		rim_strength = candidate_coverage
		candidates.append(candidate)
	var output_reason := "no_visible_owner"
	if visible_surface_selected:
		if int(visible_owner.get("elevation_level", 0)) == 0:
			output_reason = "visible_owner_e0"
		elif not rim_edge_selected:
			output_reason = "no_downward_edge_in_band"
		elif rim_strength <= 0.0:
			output_reason = "zero_rim_strength"
		else:
			output_reason = "rim_edge_band"
	return {
		"world_position": local_world_position,
		"coverage": rim_strength,
		"rim_strength": rim_strength,
		"rim_edge_selected": rim_edge_selected,
		"output_reason": output_reason,
		"valid_surface_count": valid_surface_count,
		"visible_owner": visible_owner,
		"candidates": candidates,
	}


func _edge_coverage(distance: float) -> float:
	if _rim_softness <= 0.0:
		return 1.0 if distance <= _rim_width else 0.0
	var amount: float = clampf((distance - _rim_width) / _rim_softness, 0.0, 1.0)
	var smooth_amount: float = amount * amount * (3.0 - 2.0 * amount)
	return 1.0 - smooth_amount


func _cell_to_slot(cell: Vector2i) -> Vector2i:
	return Vector2i(posmod(cell.x, _texture_size), posmod(cell.y, _texture_size))


func _write_elevation(slot: Vector2i, elevation: int) -> void:
	_image.set_pixelv(slot, Color(float(clampi(elevation, 0, 2)) * 0.5, 0.0, 0.0, 1.0))
