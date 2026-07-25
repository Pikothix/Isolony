class_name ExperimentalBuildingWallConnectionAdapter
extends RefCounted

## Purpose: Convert resolved experiment wall edges into visual-only junction masks.
## Ownership: Owns disposable connection-mask results; never modifies semantic topology.
## Integration: Used only by authored_test_style presentation.

const NORTH := 1
const EAST := 2
const SOUTH := 4
const WEST := 8

const MASK_NAMES := {
	NORTH: &"n",
	EAST: &"e",
	SOUTH: &"s",
	WEST: &"w",
	NORTH | SOUTH: &"ns",
	EAST | WEST: &"we",
	NORTH | WEST: &"nw",
	NORTH | EAST: &"ne",
	SOUTH | WEST: &"sw",
	SOUTH | EAST: &"se",
	NORTH | WEST | EAST: &"nwe",
	SOUTH | WEST | EAST: &"swe",
	NORTH | SOUTH | WEST: &"nsw",
	NORTH | SOUTH | EAST: &"sne",
	NORTH | SOUTH | EAST | WEST: &"nsew",
}


func resolve(topology: Dictionary) -> Array[Dictionary]:
	var masks_by_vertex: Dictionary = {}
	var contributions_by_vertex: Dictionary = {}
	var edges: Array = topology.exterior_edges + topology.interior_edges
	for edge: Dictionary in edges:
		# An opening owns this segment visually, so it must break the wall graph.
		if topology.openings_by_edge.has(edge.key):
			continue
		var direction_masks := masks_for_edge(edge)
		_add_edge_contribution(masks_by_vertex, contributions_by_vertex, edge.start, edge, direction_masks)
		_add_edge_contribution(masks_by_vertex, contributions_by_vertex, edge.end, edge, direction_masks)
	var requests: Array[Dictionary] = []
	for vertex: Vector2i in masks_by_vertex:
		var mask: int = masks_by_vertex[vertex]
		if not MASK_NAMES.has(mask):
			continue
		requests.append({
			"vertex": vertex,
			"connection_mask": mask,
			"semantic_id": StringName("wall_connection_%s" % MASK_NAMES[mask]),
			"contributions": contributions_by_vertex.get(vertex, []),
		})
	return requests


static func mask_for_delta(delta: Vector2i) -> int:
	match delta:
		Vector2i(0, -1): return NORTH
		Vector2i(1, 0): return EAST
		Vector2i(0, 1): return SOUTH
		Vector2i(-1, 0): return WEST
		_: return 0


static func direction_name_for_mask(mask: int) -> StringName:
	return MASK_NAMES.get(mask, &"invalid")


static func masks_for_edge(edge: Dictionary) -> Array[int]:
	match edge.direction:
		&"north": return [NORTH]
		&"east": return [EAST]
		&"south": return [SOUTH]
		&"west": return [WEST]
		# Interior axes have two visual faces and therefore contribute both normals.
		&"east_west": return [NORTH, SOUTH]
		&"north_south": return [EAST, WEST]
		_: return []


func _add_edge_contribution(masks_by_vertex: Dictionary, contributions_by_vertex: Dictionary, vertex: Vector2i, edge: Dictionary, direction_masks: Array[int]) -> void:
	assert(not direction_masks.is_empty(), "Wall edge must have a supported semantic direction")
	var combined_mask := 0
	var direction_names: Array[StringName] = []
	var cell_deltas: Array[Vector2i] = []
	for direction_mask: int in direction_masks:
		combined_mask |= direction_mask
		direction_names.append(direction_name_for_mask(direction_mask))
		cell_deltas.append(_cell_delta_for_mask(direction_mask))
	masks_by_vertex[vertex] = masks_by_vertex.get(vertex, 0) | combined_mask
	var contributions: Array = contributions_by_vertex.get(vertex, [])
	contributions.append({
		"edge_key": edge.key,
		"edge_kind": edge.kind,
		"edge_direction": edge.direction,
		"cell_deltas": cell_deltas,
		"directions": direction_names,
		"direction_mask": combined_mask,
	})
	contributions_by_vertex[vertex] = contributions


static func _cell_delta_for_mask(mask: int) -> Vector2i:
	match mask:
		NORTH: return Vector2i(0, -1)
		EAST: return Vector2i(1, 0)
		SOUTH: return Vector2i(0, 1)
		WEST: return Vector2i(-1, 0)
		_: return Vector2i.ZERO
