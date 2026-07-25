class_name ExperimentalBuildingVisualWallTiler
extends RefCounted

## Purpose: Pack semantic boundary spans and vertices into hybrid corner/straight wall tiles.
## Ownership: Owns disposable ordered runs and visual tile requests only.
## Integration: Consumes semantic spans/topology; atlas mapping remains in BuildingVisualStyle.

const ConnectionAdapter := preload("res://experimental/procedural_building_research/building_wall_connection_adapter.gd")
const DIRECTION_ORDER := {&"north": 0, &"east": 1, &"south": 2, &"west": 3}
const STRAIGHT_MASKS := {
	&"north": ConnectionAdapter.NORTH,
	&"east": ConnectionAdapter.EAST,
	&"south": ConnectionAdapter.SOUTH,
	&"west": ConnectionAdapter.WEST,
}


func resolve(spans: Array[Dictionary], topology: Dictionary) -> Dictionary:
	var ordered_spans := spans.duplicate(true)
	ordered_spans.sort_custom(_span_less)
	var runs := _build_runs(ordered_spans)
	for run: Dictionary in runs:
		if run.length < 2:
			return {
				"supported": false,
				"reason": "The current wall atlas cannot pack a boundary run of length 1 without overlapping endpoint corners.",
				"unsupported_run": run,
				"runs": runs,
				"visual_requests": [],
			}
	var spans_by_vertex := _spans_by_vertex(ordered_spans)
	var corners: Array = topology.get("corners", []).duplicate(true)
	corners.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _vertex_less(a.vertex, b.vertex))
	var requests: Array[Dictionary] = []
	for corner: Dictionary in corners:
		var incident: Array = spans_by_vertex.get(corner.vertex, [])
		if incident.size() != 2:
			return {
				"supported": false,
				"reason": "Boundary vertex %s has %d incident exterior spans; only two-span corners are supported." % [corner.vertex, incident.size()],
				"unsupported_vertex": corner.vertex,
				"runs": runs,
				"visual_requests": [],
			}
		var source_keys: Array[StringName] = []
		for span: Dictionary in incident:
			source_keys.append(span.span_key)
		source_keys.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		requests.append({
			"request_key": StringName("corner:%d,%d" % [corner.vertex.x, corner.vertex.y]),
			"tile_cell": corner.vertex,
			"visual_semantic": _corner_semantic(corner.direction),
			"source_kind": &"corner",
			"source_span_keys": source_keys,
			"source_vertex": corner.vertex,
			"corner_kind": corner.kind,
			"corner_direction": corner.direction,
		})
	for run: Dictionary in runs:
		var run_spans: Array = run.ordered_spans
		for index in range(1, run_spans.size() - 1):
			var span: Dictionary = run_spans[index]
			requests.append({
				"request_key": StringName("straight:%s" % span.span_key),
				"tile_cell": span.start_vertex,
				"visual_semantic": _straight_semantic(span.direction),
				"source_kind": &"straight",
				"source_span_keys": [span.span_key] as Array[StringName],
				"source_vertex": span.start_vertex,
			})
	requests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.request_key) < String(b.request_key))
	var request_keys: Dictionary = {}
	var tile_cells: Dictionary = {}
	for request: Dictionary in requests:
		if request_keys.has(request.request_key):
			return {"supported": false, "reason": "Duplicate visual request key: %s" % request.request_key, "runs": runs, "visual_requests": []}
		if tile_cells.has(request.tile_cell):
			return {"supported": false, "reason": "Overlapping visual wall requests at %s" % request.tile_cell, "runs": runs, "visual_requests": []}
		request_keys[request.request_key] = true
		tile_cells[request.tile_cell] = true
	return {"supported": true, "reason": "Visual wall tiling resolved.", "runs": runs, "visual_requests": requests}


func _build_runs(spans: Array[Dictionary]) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	var current: Array[Dictionary] = []
	for span: Dictionary in spans:
		if current.is_empty() or (current[-1].direction == span.direction and current[-1].end_vertex == span.start_vertex):
			current.append(span)
		else:
			runs.append(_make_run(current))
			current = [span]
	if not current.is_empty():
		runs.append(_make_run(current))
	return runs


func _make_run(spans: Array[Dictionary]) -> Dictionary:
	return {
		"direction": spans[0].direction,
		"ordered_spans": spans.duplicate(true),
		"start_vertex": spans[0].start_vertex,
		"end_vertex": spans[-1].end_vertex,
		"length": spans.size(),
	}


func _spans_by_vertex(spans: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for span: Dictionary in spans:
		for vertex: Vector2i in [span.start_vertex, span.end_vertex]:
			var incident: Array = result.get(vertex, [])
			incident.append(span)
			result[vertex] = incident
	return result


func _span_less(a: Dictionary, b: Dictionary) -> bool:
	var direction_compare: int = int(DIRECTION_ORDER[a.direction]) - int(DIRECTION_ORDER[b.direction])
	if direction_compare != 0:
		return direction_compare < 0
	if a.direction in [&"north", &"south"]:
		if a.start_vertex.y != b.start_vertex.y:
			return a.start_vertex.y < b.start_vertex.y
		if a.start_vertex.x != b.start_vertex.x:
			return a.start_vertex.x < b.start_vertex.x
	else:
		if a.start_vertex.x != b.start_vertex.x:
			return a.start_vertex.x < b.start_vertex.x
		if a.start_vertex.y != b.start_vertex.y:
			return a.start_vertex.y < b.start_vertex.y
	return String(a.span_key) < String(b.span_key)


func _vertex_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


func _straight_semantic(direction: StringName) -> StringName:
	var mask: int = STRAIGHT_MASKS[direction]
	return StringName("wall_connection_%s" % ConnectionAdapter.direction_name_for_mask(mask))


func _corner_semantic(direction: StringName) -> StringName:
	var mask := 0
	match direction:
		&"north_west": mask = ConnectionAdapter.NORTH | ConnectionAdapter.WEST
		&"north_east": mask = ConnectionAdapter.NORTH | ConnectionAdapter.EAST
		&"south_west": mask = ConnectionAdapter.SOUTH | ConnectionAdapter.WEST
		&"south_east": mask = ConnectionAdapter.SOUTH | ConnectionAdapter.EAST
	assert(mask != 0, "Unsupported topology corner direction: %s" % direction)
	return StringName("wall_connection_%s" % ConnectionAdapter.direction_name_for_mask(mask))
