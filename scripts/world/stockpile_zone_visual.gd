extends Node2D
class_name StockpileZoneVisual

## Purpose: Draw one reconstructible stockpile-zone cell marker.
## Responsibility: Present zone membership only; WorldState remains authoritative.
## Assumption: ChunkManager supplies the current isometric cell basis and recreates this node after streaming/load.

const FILL_COLOR := Color(0.18, 0.62, 1.0, 0.24)
const OUTLINE_COLOR := Color(0.28, 0.76, 1.0, 0.88)

var _corners: PackedVector2Array = PackedVector2Array()

func configure(x_step: Vector2, y_step: Vector2) -> void:
	var first: Vector2 = -x_step * 0.5 - y_step * 0.5
	var second: Vector2 = first + x_step
	var fourth: Vector2 = first + y_step
	var third: Vector2 = second + y_step
	_corners = PackedVector2Array([first, second, third, fourth])
	queue_redraw()

func _draw() -> void:
	if _corners.size() != 4:
		return
	draw_colored_polygon(_corners, FILL_COLOR)
	draw_polyline(PackedVector2Array([_corners[0], _corners[1], _corners[2], _corners[3], _corners[0]]), OUTLINE_COLOR, 1.25, true)
