class_name ExperimentalBuildingWallSpanResolver
extends RefCounted

## Purpose: Convert semantic exterior boundary edges into one renderable span per interval.
## Ownership: Owns disposable span records and stable span-key derivation only.
## Integration: Consumes resolved topology; never reads or writes rendered cells.

const ConnectionAdapter := preload("res://experimental/procedural_building_research/building_wall_connection_adapter.gd")
const DIRECTION_MASKS := {
	&"north": ConnectionAdapter.NORTH,
	&"east": ConnectionAdapter.EAST,
	&"south": ConnectionAdapter.SOUTH,
	&"west": ConnectionAdapter.WEST,
}


func resolve(topology: Dictionary) -> Array[Dictionary]:
	var corners_by_vertex: Dictionary = {}
	for corner: Dictionary in topology.get("corners", []):
		corners_by_vertex[corner.vertex] = corner
	var spans: Array[Dictionary] = []
	var keys: Dictionary = {}
	for edge: Dictionary in topology.get("exterior_edges", []):
		var boundary_cell := _boundary_cell(edge)
		var span_key := StringName("%d,%d:%s" % [boundary_cell.x, boundary_cell.y, edge.direction])
		assert(not keys.has(span_key), "Duplicate wall span: %s" % span_key)
		keys[span_key] = true
		var classification := _classify(edge, corners_by_vertex)
		spans.append({
			"span_key": span_key,
			"boundary_cell": boundary_cell,
			"direction": edge.direction,
			"start_vertex": edge.start,
			"end_vertex": edge.end,
			"is_exterior": true,
			"visual_role": classification.visual_role,
			"semantic_id": classification.semantic_id,
			"source_edge_key": edge.key,
		})
	return spans


func _boundary_cell(edge: Dictionary) -> Vector2i:
	match edge.direction:
		&"north", &"west": return edge.start
		&"east": return edge.start + Vector2i.LEFT
		&"south": return edge.start + Vector2i.UP
		_: assert(false, "Unsupported exterior direction: %s" % edge.direction); return Vector2i.ZERO


func _classify(edge: Dictionary, corners_by_vertex: Dictionary) -> Dictionary:
	var corner: Dictionary = corners_by_vertex.get(edge.start, corners_by_vertex.get(edge.end, {}))
	var mask: int = DIRECTION_MASKS[edge.direction]
	var visual_role := StringName("straight_%s" % edge.direction)
	if not corner.is_empty():
		var corner_mask := _corner_mask(corner)
		mask |= corner_mask
		visual_role = StringName("%s_corner_%s" % ["outside" if corner.kind == &"outer" else "inside", corner.direction])
	return {
		"visual_role": visual_role,
		"semantic_id": StringName("wall_connection_%s" % ConnectionAdapter.direction_name_for_mask(mask)),
	}


func _corner_mask(corner: Dictionary) -> int:
	var direction: StringName = corner.direction
	# Both topology corner kinds name the unoccupied quadrant at the vertex.
	match direction:
		&"south_east": return ConnectionAdapter.SOUTH | ConnectionAdapter.EAST
		&"south_west": return ConnectionAdapter.SOUTH | ConnectionAdapter.WEST
		&"north_west": return ConnectionAdapter.NORTH | ConnectionAdapter.WEST
		&"north_east": return ConnectionAdapter.NORTH | ConnectionAdapter.EAST
	return 0
