class_name ExperimentalBuildingTopologyResolver
extends RefCounted

## Purpose: Resolve authored prototype cells into normalized semantic building topology.
## Ownership: Owns no authored or gameplay state; returned records are disposable results.
## Responsibility: Derive exterior edges/corners and validate explicit interior walls/openings.
## Integration: Used only by the isolated procedural building experiment.

const SIDES := {
	&"north": {"neighbor": Vector2i(0, -1), "start": Vector2i(0, 0), "end": Vector2i(1, 0)},
	&"east": {"neighbor": Vector2i(1, 0), "start": Vector2i(1, 0), "end": Vector2i(1, 1)},
	&"south": {"neighbor": Vector2i(0, 1), "start": Vector2i(0, 1), "end": Vector2i(1, 1)},
	&"west": {"neighbor": Vector2i(-1, 0), "start": Vector2i(0, 0), "end": Vector2i(0, 1)},
}


func resolve(layout: ExperimentalBuildingLayout) -> Dictionary:
	assert(layout.validate(), "Cannot resolve invalid authored layout: %s" % layout.layout_id)
	var exterior_by_key: Dictionary = {}
	for cell: Vector2i in layout.occupied_cells:
		for side: StringName in SIDES:
			var side_data: Dictionary = SIDES[side]
			if layout.occupied_cells.has(cell + side_data.neighbor):
				continue
			var start: Vector2i = cell + side_data.start
			var end: Vector2i = cell + side_data.end
			var normalized := layout.normalize_edge(start, end)
			var key := layout.edge_key(normalized[0], normalized[1])
			exterior_by_key[key] = {"start": normalized[0], "end": normalized[1], "key": key, "kind": &"exterior", "direction": side}
	var interior_by_key: Dictionary = {}
	for authored_edge: Dictionary in layout.interior_wall_edges:
		interior_by_key[authored_edge.key] = {"start": authored_edge.start, "end": authored_edge.end, "key": authored_edge.key, "kind": &"interior", "direction": _interior_direction(authored_edge)}
	var valid_openings: Dictionary = {}
	for opening: Dictionary in layout.openings:
		assert(exterior_by_key.has(opening.key) or interior_by_key.has(opening.key), "Opening does not reference a resolved wall: %s" % opening.key)
		valid_openings[opening.key] = opening
	return {
		"layout_id": layout.layout_id,
		"occupied_cells": layout.occupied_cells.duplicate(),
		"rooms": layout.rooms.duplicate(),
		"exterior_edges": exterior_by_key.values(),
		"interior_edges": interior_by_key.values(),
		"openings_by_edge": valid_openings,
		"corners": _derive_corners(layout),
		"roof_regions": _resolve_roof_regions(layout),
	}


func _derive_corners(layout: ExperimentalBuildingLayout) -> Array[Dictionary]:
	var vertices: Dictionary = {}
	for cell: Vector2i in layout.occupied_cells:
		for offset: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
			vertices[cell + offset] = true
	var corners: Array[Dictionary] = []
	for vertex: Vector2i in vertices:
		var quadrants := {
			&"north_west": layout.occupied_cells.has(vertex + Vector2i(-1, -1)),
			&"north_east": layout.occupied_cells.has(vertex + Vector2i(0, -1)),
			&"south_east": layout.occupied_cells.has(vertex),
			&"south_west": layout.occupied_cells.has(vertex + Vector2i(-1, 0)),
		}
		var occupied_count := 0
		for occupied: bool in quadrants.values():
			occupied_count += 1 if occupied else 0
		if occupied_count == 1:
			corners.append({"vertex": vertex, "kind": &"outer", "direction": _outer_direction(quadrants)})
		elif occupied_count == 3:
			corners.append({"vertex": vertex, "kind": &"inner", "direction": _missing_direction(quadrants)})
	return corners


func _outer_direction(quadrants: Dictionary) -> StringName:
	if quadrants.north_west: return &"south_east"
	if quadrants.north_east: return &"south_west"
	if quadrants.south_east: return &"north_west"
	return &"north_east"


func _missing_direction(quadrants: Dictionary) -> StringName:
	for direction: StringName in quadrants:
		if not quadrants[direction]:
			return direction
	return &""


func _interior_direction(edge: Dictionary) -> StringName:
	return &"east_west" if edge.start.y == edge.end.y else &"north_south"


func _resolve_roof_regions(layout: ExperimentalBuildingLayout) -> Array[Dictionary]:
	var resolved_regions: Array[Dictionary] = []
	for authored_region: Dictionary in layout.roof_regions:
		var region := authored_region.duplicate(true)
		region["supported"] = region.type == &"flat" or _is_rectangular_region(region.cells)
		if not region.supported:
			region["diagnostic"] = &"unsupported_non_rectangular_gable"
			push_warning("PROTOTYPE_UNSUPPORTED_ROOF %s: gabled regions must be rectangular" % layout.layout_id)
		resolved_regions.append(region)
	return resolved_regions


func _is_rectangular_region(cells: Array) -> bool:
	if cells.is_empty():
		return false
	var min_cell: Vector2i = cells[0]
	var max_cell: Vector2i = cells[0]
	for cell: Vector2i in cells:
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
	return cells.size() == (max_cell.x - min_cell.x + 1) * (max_cell.y - min_cell.y + 1)
