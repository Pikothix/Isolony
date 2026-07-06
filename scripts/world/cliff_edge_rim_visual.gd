extends Node2D
class_name CliffEdgeRimVisual

## Purpose: Draw lightweight presentation-only rims for exposed elevated terrain edges.
## Responsibility: Cache and draw direction-grouped segments by loaded chunk and owning cell.
## Assumption: Segment coordinates are already projected into this node's local world space.

var _segments_by_chunk: Dictionary = {}
var _rim_color: Color = Color.WHITE
var _rim_width: float = 1.0
var _vertical_offset: float = 0.0


func configure(
		segments_by_chunk: Dictionary,
		color: Color,
		alpha: float,
		width: float,
		vertical_offset: float
) -> void:
	_segments_by_chunk = segments_by_chunk
	_apply_style(color, alpha, width, vertical_offset)
	queue_redraw()


func configure_chunk(
		chunk_coord: Vector2i,
		segments_by_cell: Dictionary,
		color: Color,
		alpha: float,
		width: float,
		vertical_offset: float
) -> void:
	_segments_by_chunk[chunk_coord] = segments_by_cell
	_apply_style(color, alpha, width, vertical_offset)
	queue_redraw()


func configure_cells(
		chunk_coord: Vector2i,
		segments_by_cell: Dictionary,
		color: Color,
		alpha: float,
		width: float,
		vertical_offset: float
) -> void:
	if not _segments_by_chunk.has(chunk_coord):
		_segments_by_chunk[chunk_coord] = {}
	var chunk_segments: Dictionary = _segments_by_chunk[chunk_coord]
	for cell_value: Variant in segments_by_cell:
		chunk_segments[cell_value] = segments_by_cell[cell_value]
	_segments_by_chunk[chunk_coord] = chunk_segments
	_apply_style(color, alpha, width, vertical_offset)
	queue_redraw()


func remove_chunk(chunk_coord: Vector2i) -> void:
	if not _segments_by_chunk.erase(chunk_coord):
		return
	queue_redraw()


func _apply_style(color: Color, alpha: float, width: float, vertical_offset: float) -> void:
	_rim_color = Color(color, clampf(alpha, 0.0, 1.0))
	_rim_width = maxf(width, 0.1)
	_vertical_offset = vertical_offset


func _draw() -> void:
	var offset := Vector2(0.0, _vertical_offset)
	for chunk_segments_value: Variant in _segments_by_chunk.values():
		for cell_segments_value: Variant in (chunk_segments_value as Dictionary).values():
			for segment_value: Variant in (cell_segments_value as Dictionary).values():
				var segment: PackedVector2Array = segment_value as PackedVector2Array
				if segment.size() != 2:
					continue
				draw_line(segment[0] + offset, segment[1] + offset, _rim_color, _rim_width, true)
