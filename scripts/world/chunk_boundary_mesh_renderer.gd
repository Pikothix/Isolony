extends Node2D
class_name ChunkBoundaryMeshRenderer

## Purpose: Render one loaded chunk's precomputed cliff faces as a 2D mesh.
## Responsibility: Convert already-detected elevation drops into presentation-only polygons.
## Assumption: ChunkManager owns effective elevation reads, chunk dirtiness, and streaming lifecycle.

var chunk_coord: Vector2i = Vector2i.ZERO
var _faces_by_cell: Dictionary = {}
var _mesh_instance: MeshInstance2D
var _rim_color: Color = Color.WHITE
var _vertical_offset: float = 0.0
var _vertex_count: int = 0
var _face_count: int = 0


func configure(
		p_chunk_coord: Vector2i,
		faces_by_cell: Dictionary,
		color: Color,
		alpha: float,
		_width: float,
		vertical_offset: float
) -> void:
	chunk_coord = p_chunk_coord
	name = "ChunkBoundaryMesh_%d_%d" % [chunk_coord.x, chunk_coord.y]
	_faces_by_cell = faces_by_cell.duplicate(true)
	_apply_style(color, alpha, _width, vertical_offset)
	_rebuild_mesh()


func configure_cells(
		faces_by_cell: Dictionary,
		color: Color,
		alpha: float,
		_width: float,
		vertical_offset: float
) -> void:
	for cell_value: Variant in faces_by_cell:
		_faces_by_cell[cell_value] = faces_by_cell[cell_value]
	_apply_style(color, alpha, _width, vertical_offset)
	_rebuild_mesh()


func get_segment_count() -> int:
	return _face_count


func get_vertex_count() -> int:
	return _vertex_count


func get_draw_call_count() -> int:
	return 1 if _face_count > 0 else 0


func get_segments_by_cell() -> Dictionary:
	return _faces_by_cell


func _apply_style(color: Color, alpha: float, _width: float, vertical_offset: float) -> void:
	_rim_color = Color(color, clampf(alpha, 0.0, 1.0))
	_vertical_offset = vertical_offset


func _rebuild_mesh() -> void:
	_ensure_mesh_instance()
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	_face_count = 0
	var offset := Vector2(0.0, _vertical_offset)
	for cell_faces_value: Variant in _faces_by_cell.values():
		for face_value: Variant in (cell_faces_value as Dictionary).values():
			var face_polygon: PackedVector2Array = face_value as PackedVector2Array
			if face_polygon.size() < 3:
				continue
			var offset_face := PackedVector2Array()
			for point: Vector2 in face_polygon:
				offset_face.append(point + offset)
			_append_face_polygon(vertices, indices, offset_face)
			_face_count += 1
	_vertex_count = vertices.size()
	if vertices.is_empty():
		_mesh_instance.mesh = null
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_instance.mesh = mesh
	_mesh_instance.modulate = _rim_color


func _append_face_polygon(vertices: PackedVector3Array, indices: PackedInt32Array, face_polygon: PackedVector2Array) -> void:
	if face_polygon.size() < 3:
		return
	var base_index: int = vertices.size()
	for point: Vector2 in face_polygon:
		vertices.append(Vector3(point.x, point.y, 0.0))
	for index in range(1, face_polygon.size() - 1):
		indices.append(base_index)
		indices.append(base_index + index)
		indices.append(base_index + index + 1)


func _ensure_mesh_instance() -> void:
	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		return
	_mesh_instance = MeshInstance2D.new()
	_mesh_instance.name = "MeshInstance2D"
	add_child(_mesh_instance)
