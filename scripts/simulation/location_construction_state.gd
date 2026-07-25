extends RefCounted
class_name LocationConstructionState

const PieceDefinitions = preload("res://scripts/simulation/construction_piece_definitions.gd")
const TerrainConfigRef = preload("res://scripts/world/terrain_config.gd")
const TraversalResolver = preload("res://scripts/simulation/location_traversal_resolver.gd")
const DESIGNATED := "designated"
const RESERVED := "reserved"
const UNDER_CONSTRUCTION := "under_construction"
const INVALID_DEPENDENCY := "invalid_dependency"
const WAITING_FOR_PREREQUISITE := "waiting_for_prerequisite"
const MISSING_RESOURCES := "missing_resources"
const UNREACHABLE := "unreachable"
const RESERVED_BY_OTHER := "reserved_by_other"
const AVAILABLE := "available"
const BASE_STRUCTURE_KINDS := ["wall"]
const FIXTURE_KINDS := ["door", "window"]
const STRUCTURE_WORK_OFFSETS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var _registry: RefCounted
var _existing_buildings: RefCounted
var _traversal: RefCounted
var _locations: Dictionary = {}
var _next_site_sequence := 1
var _enclosure_recompute_count := 0

## Owns authoritative per-location construction sites, full-cell wall records,
## optional wall fixtures, floor occupancy, and lifecycle/progress/reservations.
## Resource changes remain in LocationRegistry; presentation never owns state.
func configure(registry: RefCounted, existing_buildings: RefCounted = null, traversal: RefCounted = null) -> void:
	_registry = registry
	_existing_buildings = existing_buildings
	_traversal = traversal
	if _traversal == null:
		_traversal = TraversalResolver.new()
		_traversal.configure(_registry, self, _existing_buildings)

func validate_designation(location_id: String, piece_kind: String, cells: Array) -> Dictionary:
	return _stage_designation(location_id, piece_kind, cells)

func request_designate_construction(location_id: String, piece_kind: String, cells: Array) -> Dictionary:
	var staged := _stage_designation(location_id, piece_kind, cells)
	if not bool(staged.ok): return staged
	var state := _state_for(location_id)
	var site_ids: Array[String] = []
	for record: Dictionary in staged.records:
		var site_id := "construction_site_%06d" % _next_site_sequence
		_next_site_sequence += 1
		record.site_id = site_id
		record.resource_reservation_id = "location_construction_%s" % site_id
		state.construction_sites[site_id] = record
		if String(record.piece_kind) in BASE_STRUCTURE_KINDS: state.structure_site_cells[Vector2i(record.cell)] = site_id
		elif String(record.piece_kind) in FIXTURE_KINDS: state.fixture_site_cells[Vector2i(record.cell)] = site_id
		site_ids.append(site_id)
	return {"ok": true, "reason": "construction_designated", "site_ids": site_ids}

func request_cancel_construction(location_id: String, site_id: String) -> Dictionary:
	var state: Dictionary = _locations.get(location_id, {})
	if state.is_empty() or not state.construction_sites.has(site_id): return _result(false, "unknown_construction_site")
	var cancelled_site_ids: Array[String] = [site_id]
	for candidate: Dictionary in state.construction_sites.values():
		if site_id in candidate.get("prerequisite_site_ids", []): cancelled_site_ids.append(String(candidate.site_id))
	cancelled_site_ids.sort()
	for cancelled_id: String in cancelled_site_ids:
		var site: Dictionary = state.construction_sites.get(cancelled_id, {})
		if site.is_empty(): continue
		if not bool(site.resources_consumed): _registry.release_resource_reservation(String(site.resource_reservation_id))
		if String(site.piece_kind) in BASE_STRUCTURE_KINDS and String(state.structure_site_cells.get(Vector2i(site.cell), "")) == cancelled_id: state.structure_site_cells.erase(Vector2i(site.cell))
		elif String(site.piece_kind) in FIXTURE_KINDS and String(state.fixture_site_cells.get(Vector2i(site.cell), "")) == cancelled_id: state.fixture_site_cells.erase(Vector2i(site.cell))
		state.construction_sites.erase(cancelled_id)
	return {"ok": true, "reason": "construction_cancelled", "site_id": site_id, "cancelled_site_ids": cancelled_site_ids}

func request_debug_complete_construction(location_id: String, site_id: String) -> Dictionary:
	var state: Dictionary = _locations.get(location_id, {})
	if state.is_empty() or not state.construction_sites.has(site_id): return _result(false, "unknown_construction_site")
	var site: Dictionary = state.construction_sites[site_id]
	var dependency := _validate_completion(location_id, site)
	if not bool(dependency.ok): return dependency
	if not bool(site.resources_consumed): _registry.release_resource_reservation(String(site.resource_reservation_id))
	return _complete_site(state, site)

func get_available_construction_site(location_id: String, colonist_id: String, colonist_cell := Vector2i.ZERO) -> Dictionary:
	if colonist_id.is_empty(): return _result(false, "invalid_colonist")
	var candidates: Array[Dictionary] = []
	for site: Dictionary in get_location_construction_sites(location_id):
		var availability := _get_site_availability(location_id, site, colonist_id, colonist_cell)
		if String(availability.availability_reason) != AVAILABLE: continue
		site.work_cell = availability.work_cell
		site.work_path_cost = availability.path_cost
		candidates.append(site)
	if candidates.is_empty(): return _result(false, "no_construction_available")
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := float(a.work_path_cost)
		var db := float(b.work_path_cost)
		return da < db if da != db else String(a.site_id) < String(b.site_id))
	return {"ok": true, "reason": "construction_available", "site": candidates[0]}

func reserve_construction_site(location_id: String, site_id: String, colonist_id: String, colonist_cell := Vector2i.ZERO) -> Dictionary:
	var state: Dictionary = _locations.get(location_id, {})
	if state.is_empty() or not state.construction_sites.has(site_id): return _result(false, "unknown_construction_site")
	if colonist_id.is_empty(): return _result(false, "invalid_colonist")
	var site: Dictionary = state.construction_sites[site_id]
	if not String(site.reserved_by_colonist_id) in ["", colonist_id]: return _result(false, "construction_site_reserved")
	var availability := _get_site_availability(location_id, site, colonist_id, colonist_cell)
	if String(availability.availability_reason) != AVAILABLE:
		if String(availability.availability_reason) == MISSING_RESOURCES: return _result(false, "insufficient_local_resources")
		if String(availability.availability_reason) == UNREACHABLE: return _result(false, "no_reachable_work_cell")
		return _result(false, String(availability.availability_reason))
	if String(site.reserved_by_colonist_id).is_empty():
		if not bool(site.resources_consumed):
			var reserved: Dictionary = _registry.reserve_local_resources(location_id, site.required_resources, String(site.resource_reservation_id))
			if not bool(reserved.ok): return reserved
		site.reserved_by_colonist_id = colonist_id
		site.status = UNDER_CONSTRUCTION if bool(site.resources_consumed) else RESERVED
	return {"ok": true, "reason": "construction_site_reserved", "site_id": site_id, "work_cell": availability.work_cell}

func release_construction_site_reservation(location_id: String, site_id: String, colonist_id: String, _reason := "") -> Dictionary:
	var state: Dictionary = _locations.get(location_id, {})
	if state.is_empty() or not state.construction_sites.has(site_id): return _result(false, "unknown_construction_site")
	var site: Dictionary = state.construction_sites[site_id]
	if String(site.reserved_by_colonist_id) != colonist_id: return _result(false, "reservation_owner_mismatch")
	if not bool(site.resources_consumed): _registry.release_resource_reservation(String(site.resource_reservation_id))
	site.reserved_by_colonist_id = ""
	site.status = UNDER_CONSTRUCTION if bool(site.resources_consumed) else DESIGNATED
	return {"ok": true, "reason": "construction_reservation_released", "site_id": site_id}

func request_progress_construction(location_id: String, site_id: String, colonist_id: String, amount: float) -> Dictionary:
	var state: Dictionary = _locations.get(location_id, {})
	if state.is_empty() or not state.construction_sites.has(site_id): return _result(false, "unknown_construction_site")
	if amount <= 0.0: return _result(false, "invalid_work_amount")
	var site: Dictionary = state.construction_sites[site_id]
	if String(site.reserved_by_colonist_id) != colonist_id: return _result(false, "reservation_owner_mismatch")
	var valid := _validate_completion(location_id, site)
	if not bool(valid.ok): return valid
	if not bool(site.resources_consumed):
		var consumed: Dictionary = _registry.consume_reserved_resources(location_id, String(site.resource_reservation_id))
		if not bool(consumed.ok): return consumed
		site.resources_consumed = true
		site.status = UNDER_CONSTRUCTION
	site.build_progress = minf(float(site.build_required), float(site.build_progress) + amount)
	if float(site.build_progress) >= float(site.build_required): return _complete_site(state, site)
	return {"ok": true, "reason": "construction_progress", "site_id": site_id, "build_progress": site.build_progress, "build_required": site.build_required}

func cleanup_stale_construction_reservations(location_id: String, active_colonist_ids: Array[String]) -> Dictionary:
	var released: Array[String] = []
	for site: Dictionary in get_location_construction_sites(location_id):
		var owner := String(site.reserved_by_colonist_id)
		if not owner.is_empty() and owner not in active_colonist_ids:
			var result := release_construction_site_reservation(location_id, String(site.site_id), owner, "stale_colonist")
			if bool(result.ok): released.append(String(site.site_id))
	return {"ok": true, "reason": "stale_reservations_cleaned", "released_site_ids": released}

func resolve_construction_work_cell(location_id: String, site_id: String, colonist_cell := Vector2i.ZERO, colonist_id := "") -> Dictionary:
	var site := get_construction_site(location_id, site_id)
	if site.is_empty(): return _result(false, "unknown_construction_site")
	if _traversal == null: return _result(false, "traversal_unavailable")
	if String(site.piece_kind) == "floor":
		var floor_path: Dictionary = _traversal.find_path(location_id, colonist_cell, Vector2i(site.cell), colonist_id)
		if not bool(floor_path.ok): return _result(false, "no_reachable_work_cell")
		return {"ok": true, "reason": "work_cell_resolved", "work_cell": Vector2i(site.cell), "path_cost": float(floor_path.cost)}
	var candidates: Array[Dictionary] = []
	var order := 0
	for offset: Vector2i in STRUCTURE_WORK_OFFSETS:
		var cell := Vector2i(site.cell) + offset
		if _traversal.is_cell_traversable(location_id, cell, colonist_id):
			var path: Dictionary = _traversal.find_path(location_id, colonist_cell, cell, colonist_id)
			if bool(path.ok): candidates.append({"cell": cell, "cost": float(path.cost), "order": order})
		order += 1
	if candidates.is_empty(): return _result(false, "no_reachable_work_cell")
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.cost) < float(b.cost) if not is_equal_approx(float(a.cost), float(b.cost)) else int(a.order) < int(b.order))
	return {"ok": true, "reason": "work_cell_resolved", "work_cell": Vector2i(candidates[0].cell), "path_cost": float(candidates[0].cost)}

func get_location_construction_sites(location_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var state: Dictionary = _locations.get(location_id, {})
	for site: Dictionary in state.get("construction_sites", {}).values(): result.append(site.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.site_id) < String(b.site_id))
	return result

func get_location_completed_structures(location_id: String) -> Dictionary:
	var state: Dictionary = _locations.get(location_id, {})
	return state.get("completed_structures", _empty_completed()).duplicate(true)

## Persistence contract for authored cell construction. Derived cell indices and
## worker reservations are rebuilt instead of serialized.
func export_state() -> Dictionary:
	var locations: Array[Dictionary] = []
	var location_ids: Array[String] = []
	for location_id: String in _locations: location_ids.append(location_id)
	location_ids.sort()
	for location_id: String in location_ids:
		var state: Dictionary = _locations[location_id]
		var sites: Array[Dictionary] = []
		for site: Dictionary in state.construction_sites.values():
			var saved_site := site.duplicate(true)
			saved_site.reserved_by_colonist_id = ""
			saved_site.status = UNDER_CONSTRUCTION if bool(saved_site.resources_consumed) else DESIGNATED
			sites.append(saved_site)
		sites.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.site_id) < String(b.site_id))
		var completed_sites: Array[Dictionary] = []
		for completed_site: Dictionary in state.completed_sites.values(): completed_sites.append(completed_site.duplicate(true))
		completed_sites.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.site_id) < String(b.site_id))
		locations.append({
			"location_id": location_id,
			"construction_sites": sites,
			"completed_sites": completed_sites,
			"structure_cells": _records_from_cell_map(state.completed_structures.structure_cells),
			"floor_cells": _records_from_cell_map(state.completed_structures.floor_cells),
			"roof_cells": _records_from_cell_map(state.completed_structures.roof_cells),
		})
	return {"next_site_sequence": _next_site_sequence, "locations": locations}

## Validates and normalizes the complete section before replacing live state.
func import_state(data: Dictionary) -> Dictionary:
	var staged_result := _stage_import(data)
	if not bool(staged_result.ok): return staged_result
	_locations = staged_result.locations
	_next_site_sequence = int(staged_result.next_site_sequence)
	_enclosure_recompute_count += 1
	return _result(true, "imported")

func _stage_import(data: Dictionary) -> Dictionary:
	if not data.get("locations") is Array: return _result(false, "invalid_locations")
	if not data.has("next_site_sequence") or not _is_whole_number(data.next_site_sequence) or int(data.next_site_sequence) < 1: return _result(false, "invalid_next_site_sequence")
	var staged: Dictionary = {}
	var all_site_ids: Dictionary = {}
	var maximum_sequence := 0
	for raw_location: Variant in data.locations:
		if not raw_location is Dictionary: return _result(false, "invalid_location_construction_record")
		var location_id := String(raw_location.get("location_id", ""))
		if location_id.is_empty() or staged.has(location_id) or _registry == null or not _registry.has(location_id): return _result(false, "invalid_location_reference")
		if not raw_location.get("construction_sites") is Array or not raw_location.get("completed_sites") is Array: return _result(false, "invalid_location_construction_record")
		var structure_result := _stage_completed_cell_records(location_id, raw_location.get("structure_cells"), "wall", ["", "door", "window"])
		if not bool(structure_result.ok): return structure_result
		var floor_result := _stage_completed_cell_records(location_id, raw_location.get("floor_cells"), "floor", [""])
		if not bool(floor_result.ok): return floor_result
		var roof_result := _stage_completed_cell_records(location_id, raw_location.get("roof_cells"), "roof", [""])
		if not bool(roof_result.ok): return roof_result
		var state := {"construction_sites": {}, "structure_site_cells": {}, "fixture_site_cells": {}, "completed_sites": {}, "completed_structures": {"structure_cells": structure_result.records, "floor_cells": floor_result.records, "roof_cells": roof_result.records}}
		for raw_completed: Variant in raw_location.completed_sites:
			if not raw_completed is Dictionary or not raw_completed.get("cell") is Vector2i: return _result(false, "invalid_completed_site")
			var completed_id := String(raw_completed.get("site_id", "")); var completed_kind := String(raw_completed.get("piece_kind", ""))
			if completed_id.is_empty() or all_site_ids.has(completed_id) or not PieceDefinitions.has_definition(completed_kind) or String(raw_completed.get("location_id", "")) != location_id or not _cell_in_location(location_id, Vector2i(raw_completed.cell)): return _result(false, "invalid_completed_site")
			all_site_ids[completed_id] = true; maximum_sequence = maxi(maximum_sequence, _site_sequence(completed_id)); state.completed_sites[completed_id] = raw_completed.duplicate(true)
		for raw_site: Variant in raw_location.construction_sites:
			var site_result := _stage_site(location_id, raw_site, state, all_site_ids)
			if not bool(site_result.ok): return site_result
			var site: Dictionary = site_result.site; var site_id := String(site.site_id); all_site_ids[site_id] = true; maximum_sequence = maxi(maximum_sequence, _site_sequence(site_id)); state.construction_sites[site_id] = site
			if String(site.piece_kind) in BASE_STRUCTURE_KINDS: state.structure_site_cells[Vector2i(site.cell)] = site_id
			elif String(site.piece_kind) in FIXTURE_KINDS: state.fixture_site_cells[Vector2i(site.cell)] = site_id
		staged[location_id] = state
	for location_id: String in staged:
		for site: Dictionary in staged[location_id].construction_sites.values():
			for prerequisite_id: Variant in site.prerequisite_site_ids:
				if not all_site_ids.has(String(prerequisite_id)): return _result(false, "missing_prerequisite_site")
	return {"ok": true, "reason": "valid", "locations": staged, "next_site_sequence": maxi(int(data.next_site_sequence), maximum_sequence + 1)}

func _stage_site(location_id: String, raw_site: Variant, state: Dictionary, all_site_ids: Dictionary) -> Dictionary:
	if not raw_site is Dictionary: return _result(false, "invalid_construction_site")
	for field: String in ["site_id", "location_id", "cell", "piece_kind", "status", "required_resources", "resources_consumed", "build_progress", "build_required", "prerequisite_site_ids"]:
		if not raw_site.has(field): return _result(false, "missing_site_%s" % field)
	var site_id := String(raw_site.site_id); var piece_kind := String(raw_site.piece_kind)
	if site_id.is_empty() or all_site_ids.has(site_id) or String(raw_site.location_id) != location_id or not raw_site.cell is Vector2i or not _cell_in_location(location_id, Vector2i(raw_site.cell)): return _result(false, "invalid_construction_site")
	if not PieceDefinitions.has_definition(piece_kind) or bool(PieceDefinitions.get_definition(piece_kind).get("deferred", false)): return _result(false, "unknown_piece_kind")
	if typeof(raw_site.resources_consumed) != TYPE_BOOL or String(raw_site.status) not in [DESIGNATED, RESERVED, UNDER_CONSTRUCTION]: return _result(false, "invalid_site_status")
	if not raw_site.required_resources is Dictionary or not _valid_resource_cost(raw_site.required_resources) or not raw_site.prerequisite_site_ids is Array: return _result(false, "invalid_site_materials")
	if not _is_number(raw_site.build_progress) or not _is_number(raw_site.build_required): return _result(false, "invalid_site_progress")
	var progress := float(raw_site.build_progress); var required := float(raw_site.build_required)
	if not is_finite(progress) or not is_finite(required) or progress < 0.0 or required <= 0.0 or progress >= required: return _result(false, "invalid_site_progress")
	var cell := Vector2i(raw_site.cell); var orientation := String(raw_site.get("orientation_axis", "")); var definition := PieceDefinitions.get_definition(piece_kind)
	if orientation not in definition.get("allowed_orientations", []) and not (orientation.is_empty() and (definition.get("allowed_orientations", []) as Array).is_empty()): return _result(false, "invalid_site_orientation")
	if piece_kind in BASE_STRUCTURE_KINDS and (state.structure_site_cells.has(cell) or state.completed_structures.structure_cells.has(cell)): return _result(false, "duplicate_structure_cell")
	if piece_kind in FIXTURE_KINDS:
		var wall: Dictionary = state.completed_structures.structure_cells.get(cell, {})
		if state.fixture_site_cells.has(cell) or wall.is_empty() or not String(wall.get("fixture_kind", "")).is_empty(): return _result(false, "invalid_fixture_cell")
	if piece_kind == "floor" and (state.completed_structures.floor_cells.has(cell) or _site_cell_exists(state.construction_sites, piece_kind, cell)): return _result(false, "duplicate_floor_cell")
	var site: Dictionary = raw_site.duplicate(true); site.required_resources = _normalized_resource_cost(raw_site.required_resources); site.reserved_by_colonist_id = ""; site.resource_reservation_id = "location_construction_%s" % site_id; site.status = UNDER_CONSTRUCTION if bool(site.resources_consumed) else DESIGNATED
	return {"ok": true, "reason": "valid", "site": site}

func _stage_completed_cell_records(location_id: String, raw_records: Variant, expected_kind: String, allowed_fixtures: Array) -> Dictionary:
	if not raw_records is Array: return _result(false, "invalid_completed_structures")
	var records: Dictionary = {}
	for raw: Variant in raw_records:
		if not raw is Dictionary or not raw.get("cell") is Vector2i or String(raw.get("kind", "")) != expected_kind: return _result(false, "invalid_completed_structure")
		var cell := Vector2i(raw.cell); var fixture_kind := String(raw.get("fixture_kind", ""))
		if records.has(cell) or not _cell_in_location(location_id, cell) or fixture_kind not in allowed_fixtures: return _result(false, "invalid_completed_structure")
		if fixture_kind in FIXTURE_KINDS and String(raw.get("fixture_orientation", "")) not in PieceDefinitions.get_orientations(fixture_kind): return _result(false, "invalid_completed_structure")
		records[cell] = raw.duplicate(true)
	return {"ok": true, "reason": "valid", "records": records}

func _records_from_cell_map(records: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in records.values(): result.append(record.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: var ac := Vector2i(a.cell); var bc := Vector2i(b.cell); return ac.y < bc.y or (ac.y == bc.y and ac.x < bc.x))
	return result

func _cell_in_location(location_id: String, cell: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, Vector2i(_registry.get_record(location_id).map_size)).has_point(cell)

func _site_cell_exists(sites: Dictionary, piece_kind: String, cell: Vector2i) -> bool:
	for site: Dictionary in sites.values():
		if String(site.piece_kind) == piece_kind and Vector2i(site.cell) == cell: return true
	return false

func _valid_resource_cost(cost: Dictionary) -> bool:
	for resource_type: Variant in cost:
		if String(resource_type).is_empty() or not _is_whole_number(cost[resource_type]) or int(cost[resource_type]) < 0: return false
	return true

func _normalized_resource_cost(cost: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for resource_type: Variant in cost: normalized[String(resource_type)] = int(cost[resource_type])
	return normalized

func _is_number(value: Variant) -> bool: return typeof(value) in [TYPE_INT, TYPE_FLOAT]
func _is_whole_number(value: Variant) -> bool: return _is_number(value) and is_finite(float(value)) and is_equal_approx(float(value), float(int(value)))
func _site_sequence(site_id: String) -> int: return int(site_id.trim_prefix("construction_site_")) if site_id.begins_with("construction_site_") else 0

func get_construction_site(location_id: String, site_id: String) -> Dictionary:
	var state: Dictionary = _locations.get(location_id, {})
	return state.get("construction_sites", {}).get(site_id, {}).duplicate(true)

## Defensive presentation read. Availability precedence is dependency validity,
## prerequisite completion, resources, reachability, reservation, then available.
func get_construction_site_status(location_id: String, site_id: String, colonist_id := "", colonist_cell := Vector2i.ZERO) -> Dictionary:
	var site := get_construction_site(location_id, site_id)
	if site.is_empty(): return {}
	var availability := _get_site_availability(location_id, site, colonist_id, colonist_cell)
	return {
		"site_id": String(site.site_id),
		"piece_kind": String(site.piece_kind),
		"cell": Vector2i(site.cell),
		"orientation_axis": String(site.get("orientation_axis", "")),
		"status": String(site.status),
		"availability_reason": String(availability.availability_reason),
		"progress": float(site.build_progress),
		"build_required": float(site.build_required),
		"reserved_by_colonist_id": String(site.reserved_by_colonist_id),
		"prerequisite_site_ids": site.get("prerequisite_site_ids", []).duplicate(),
		"missing_resources": availability.get("missing_resources", {}).duplicate(true),
		"reachable": bool(availability.get("reachable", false)),
	}.duplicate(true)

func is_construction_cell_occupied(location_id: String, cell: Vector2i) -> bool:
	var state: Dictionary = _locations.get(location_id, {})
	if state.get("structure_site_cells", {}).has(cell) or state.get("fixture_site_cells", {}).has(cell): return true
	for site: Dictionary in state.get("construction_sites", {}).values():
		if Vector2i(site.cell) == cell: return true
	var completed: Dictionary = state.get("completed_structures", _empty_completed())
	return completed.structure_cells.has(cell) or completed.floor_cells.has(cell) or completed.roof_cells.has(cell)

func request_remove_completed_structure(location_id: String, cell: Vector2i) -> Dictionary:
	var location_check := _validate_location(location_id)
	if not bool(location_check.ok): return location_check
	var state := _state_for(location_id)
	if not state.completed_structures.structure_cells.has(cell): return _result(false, "unknown_structure_cell")
	if state.structure_site_cells.has(cell) or state.fixture_site_cells.has(cell): return _result(false, "fixture_installation_active")
	if not String(state.completed_structures.structure_cells[cell].get("fixture_kind", "")).is_empty(): return _result(false, "wall_fixture_present")
	state.completed_structures.structure_cells.erase(cell)
	for completed_site_id: Variant in state.completed_sites.keys():
		if Vector2i(state.completed_sites[completed_site_id].get("cell", Vector2i(-1, -1))) == cell: state.completed_sites.erase(completed_site_id)
	return {"ok": true, "reason": "structure_removed", "cell": cell}

## Explicit fixture removal preserves the authoritative wall record. Wall
## removal separately requires an empty fixture slot to prevent orphaned data.
func request_remove_wall_fixture(location_id: String, cell: Vector2i) -> Dictionary:
	var location_check := _validate_location(location_id)
	if not bool(location_check.ok): return location_check
	var state := _state_for(location_id)
	if state.fixture_site_cells.has(cell): return _result(false, "fixture_installation_active")
	var wall: Dictionary = state.completed_structures.structure_cells.get(cell, {})
	if wall.is_empty() or String(wall.get("kind", "")) != "wall": return _result(false, "compatible_wall_required")
	if String(wall.get("fixture_kind", "")).is_empty(): return _result(false, "wall_fixture_missing")
	wall.fixture_kind = ""
	wall.fixture_orientation = ""
	for completed_site_id: Variant in state.completed_sites.keys():
		var completed_site: Dictionary = state.completed_sites[completed_site_id]
		if Vector2i(completed_site.get("cell", Vector2i(-1, -1))) == cell and String(completed_site.get("piece_kind", "")) in FIXTURE_KINDS: state.completed_sites.erase(completed_site_id)
	return {"ok": true, "reason": "wall_fixture_removed", "cell": cell}

func get_structure_at_cell(location_id: String, cell: Vector2i) -> Dictionary:
	var state: Dictionary = _locations.get(location_id, {})
	return state.get("completed_structures", _empty_completed()).get("structure_cells", {}).get(cell, {}).duplicate(true)

func get_wall_fixture_at_cell(location_id: String, cell: Vector2i) -> Dictionary:
	var wall := get_structure_at_cell(location_id, cell)
	var fixture_kind := String(wall.get("fixture_kind", ""))
	if String(wall.get("kind", "")) != "wall" or fixture_kind.is_empty(): return {}
	return {"cell": cell, "kind": fixture_kind, "orientation": String(wall.get("fixture_orientation", ""))}

func get_enclosed_regions(location_id: String) -> Array[Array]:
	## Room/enclosure derivation depended on obsolete edge segments. Full-cell
	## structure placement deliberately defers replacement room semantics.
	return []

func get_enclosure_recompute_count() -> int: return _enclosure_recompute_count

func _stage_designation(location_id: String, piece_kind: String, requested_targets: Array) -> Dictionary:
	var location_check := _validate_location(location_id)
	if not bool(location_check.ok): return location_check
	if not PieceDefinitions.has_definition(piece_kind): return _result(false, "unknown_piece_kind")
	if bool(PieceDefinitions.get_definition(piece_kind).get("deferred", false)): return _result(false, "piece_deferred")
	if requested_targets.is_empty(): return _result(false, "empty_target_request")
	var normalized: Array = []
	var seen: Dictionary = {}
	for raw_target: Variant in requested_targets:
		if not raw_target is Vector2i and not raw_target is Dictionary: return _result(false, "invalid_cell")
		if raw_target is Dictionary and not raw_target.has("cell"): return _result(false, "invalid_cell")
		var cell := Vector2i(raw_target.cell) if raw_target is Dictionary else Vector2i(raw_target)
		if not seen.has(cell): seen[cell] = true; normalized.append(raw_target)
	normalized.sort_custom(func(a: Variant, b: Variant) -> bool:
		var a_cell := Vector2i(a.cell) if a is Dictionary else Vector2i(a)
		var b_cell := Vector2i(b.cell) if b is Dictionary else Vector2i(b)
		return a_cell.y < b_cell.y or (a_cell.y == b_cell.y and a_cell.x < b_cell.x))
	var records: Array[Dictionary] = []
	for target: Variant in normalized:
		var validation := _validate_target(location_id, piece_kind, target, "")
		if not bool(validation.ok): return validation
		var definition := PieceDefinitions.get_definition(piece_kind)
		var record := {"site_id": "", "location_id": location_id, "cell": Vector2i(validation.cell), "piece_kind": piece_kind, "status": DESIGNATED, "orientation_axis": String(validation.get("orientation_axis", "")), "expected_base_kind": String(validation.get("expected_base_kind", "")), "required_resources": definition.cost.duplicate(true), "resources_consumed": false, "resource_reservation_id": "", "build_progress": 0.0, "build_required": float(definition.work_required), "prerequisite_site_ids": [], "reserved_by_colonist_id": ""}
		records.append(record)
	return {"ok": true, "reason": "valid", "records": records}

func _validate_location(location_id: String) -> Dictionary:
	if _registry == null or not _registry.has(location_id): return _result(false, "unknown_location")
	if not bool(_registry.get_record(location_id).get("claimed", false)): return _result(false, "unclaimed_location")
	return _result(true, "valid")

func _validate_target(location_id: String, piece_kind: String, raw_target: Variant, ignored_site_id: String) -> Dictionary:
	if not raw_target is Vector2i and not raw_target is Dictionary: return _result(false, "invalid_cell")
	if raw_target is Dictionary and not raw_target.has("cell"): return _result(false, "invalid_cell")
	var floor_cell := Vector2i(raw_target.get("cell", Vector2i.ZERO)) if raw_target is Dictionary else Vector2i(raw_target)
	var orientation_axis := String(raw_target.get("orientation_axis", "")) if raw_target is Dictionary else ""
	if piece_kind in BASE_STRUCTURE_KINDS or piece_kind in FIXTURE_KINDS: return _validate_structure_target(location_id, piece_kind, floor_cell, orientation_axis, ignored_site_id)
	return _validate_floor_target(location_id, piece_kind, floor_cell, ignored_site_id)

func _validate_floor_target(location_id: String, piece_kind: String, cell: Vector2i, ignored_site_id: String) -> Dictionary:
	var location: Dictionary = _registry.get_record(location_id)
	var bounds := Rect2i(Vector2i.ZERO, Vector2i(location.map_size))
	if not bounds.has_point(cell): return _result(false, "cell_out_of_bounds")
	var terrain := _terrain_at(location, cell)
	if terrain.is_empty() or not bool(terrain.get("walkable", TerrainConfigRef.is_walkable(String(terrain.get("terrain", ""))))): return _result(false, "terrain_not_buildable")
	for resource: Dictionary in location.resources:
		if Vector2i(resource.cell) == cell and not bool(resource.get("depleted", false)): return _result(false, "resource_blocked")
	for pile: Dictionary in location.piles:
		if Vector2i(pile.cell) == cell and bool(pile.get("enabled", false)): return _result(false, "pile_blocked")
	if _existing_building_occupies(location_id, cell): return _result(false, "cell_occupied_by_building")
	var state := _state_for(location_id)
	var completed: Dictionary = state.completed_structures
	for site: Dictionary in state.construction_sites.values():
		if String(site.site_id) != ignored_site_id and String(site.piece_kind) == piece_kind and Vector2i(site.cell) == cell: return _result(false, "duplicate_construction_site")
	match piece_kind:
		"floor":
			if completed.floor_cells.has(cell): return _result(false, "floor_already_completed")
	return {"ok": true, "reason": "valid", "cell": cell, "orientation_axis": ""}

func _validate_structure_target(location_id: String, piece_kind: String, cell: Vector2i, orientation_axis: String, ignored_site_id: String) -> Dictionary:
	var location: Dictionary = _registry.get_record(location_id)
	var bounds := Rect2i(Vector2i.ZERO, Vector2i(location.map_size))
	if not bounds.has_point(cell): return _result(false, "cell_out_of_bounds")
	var terrain := _terrain_at(location, cell)
	if terrain.is_empty() or not bool(terrain.get("walkable", TerrainConfigRef.is_walkable(String(terrain.get("terrain", ""))))): return _result(false, "terrain_not_buildable")
	for resource: Dictionary in location.resources:
		if Vector2i(resource.cell) == cell and not bool(resource.get("depleted", false)): return _result(false, "resource_blocked")
	for pile: Dictionary in location.piles:
		if Vector2i(pile.cell) == cell and bool(pile.get("enabled", false)): return _result(false, "pile_blocked")
	if _existing_building_occupies(location_id, cell): return _result(false, "cell_occupied_by_building")
	var state := _state_for(location_id)
	var completed: Dictionary = state.completed_structures
	var definition := PieceDefinitions.get_definition(piece_kind)
	var orientations: Array = definition.get("allowed_orientations", [])
	if orientations.is_empty():
		if not orientation_axis.is_empty(): return _result(false, "unsupported_orientation")
	elif orientation_axis.is_empty() or orientation_axis not in orientations:
		return _result(false, "unsupported_orientation")
	if String(definition.get("placement_role", "")) == "wall_fixture":
		var fixture_site_id := String(state.fixture_site_cells.get(cell, ""))
		if not fixture_site_id.is_empty() and fixture_site_id != ignored_site_id: return _result(false, "fixture_cell_occupied")
		if not completed.structure_cells.has(cell): return _result(false, "compatible_wall_required")
		var source: Dictionary = completed.structure_cells[cell]
		var source_kind := String(source.get("kind", ""))
		if source_kind != String(definition.get("required_base_structure", "")): return _result(false, "compatible_wall_required")
		if not String(source.get("fixture_kind", "")).is_empty(): return _result(false, "fixture_cell_occupied")
		return {"ok": true, "reason": "valid", "cell": cell, "orientation_axis": orientation_axis, "expected_base_kind": source_kind}
	var occupying_site_id := String(state.structure_site_cells.get(cell, ""))
	if not occupying_site_id.is_empty() and occupying_site_id != ignored_site_id: return _result(false, "structure_cell_occupied")
	if completed.structure_cells.has(cell): return _result(false, "structure_cell_occupied")
	return {"ok": true, "reason": "valid", "cell": cell, "orientation_axis": "", "expected_base_kind": ""}

func _validate_completion(location_id: String, site: Dictionary) -> Dictionary:
	var location_check := _validate_location(location_id)
	if not bool(location_check.ok): return location_check
	return _validate_target(location_id, String(site.piece_kind), site, String(site.site_id))

func _validate_site_dependency(location_id: String, site: Dictionary) -> Dictionary:
	if String(site.location_id) != location_id: return _result(false, INVALID_DEPENDENCY)
	return _result(true, "valid")

func _get_site_availability(location_id: String, site: Dictionary, colonist_id: String, colonist_cell: Vector2i) -> Dictionary:
	var dependency := _validate_site_dependency(location_id, site)
	if not bool(dependency.ok) and String(dependency.reason) != WAITING_FOR_PREREQUISITE: return {"availability_reason": String(dependency.reason), "missing_resources": {}, "reachable": false}
	var placement := _validate_target(location_id, String(site.piece_kind), site, String(site.site_id))
	if not bool(placement.ok): return {"availability_reason": INVALID_DEPENDENCY, "missing_resources": {}, "reachable": false}
	if not bool(dependency.ok): return {"availability_reason": WAITING_FOR_PREREQUISITE, "missing_resources": {}, "reachable": false}
	var owner := String(site.reserved_by_colonist_id)
	var missing: Dictionary = {}
	if not bool(site.resources_consumed) and owner.is_empty(): missing = _registry.get_missing_local_resources(location_id, site.required_resources)
	if not missing.is_empty(): return {"availability_reason": MISSING_RESOURCES, "missing_resources": missing, "reachable": false}
	var work := resolve_construction_work_cell(location_id, String(site.site_id), colonist_cell, colonist_id)
	if not bool(work.ok): return {"availability_reason": UNREACHABLE, "missing_resources": {}, "reachable": false}
	if not owner.is_empty() and owner != colonist_id: return {"availability_reason": RESERVED_BY_OTHER, "missing_resources": {}, "reachable": true, "work_cell": work.work_cell, "path_cost": work.path_cost}
	return {"availability_reason": AVAILABLE, "missing_resources": {}, "reachable": true, "work_cell": work.work_cell, "path_cost": work.path_cost}

func _state_for(location_id: String) -> Dictionary:
	if not _locations.has(location_id):
		_locations[location_id] = {"construction_sites": {}, "structure_site_cells": {}, "fixture_site_cells": {}, "completed_sites": {}, "completed_structures": _empty_completed()}
	return _locations[location_id]

func _empty_completed() -> Dictionary:
	return {"structure_cells": {}, "floor_cells": {}, "roof_cells": {}}

func _terrain_at(location: Dictionary, cell: Vector2i) -> Dictionary:
	for terrain: Dictionary in location.terrain:
		if Vector2i(terrain.cell) == cell: return terrain
	return {}

func _existing_building_occupies(location_id: String, cell: Vector2i) -> bool:
	if _existing_buildings == null: return false
	for building: Dictionary in _existing_buildings.get_building_snapshots(location_id):
		if bool(building.get("derived_enclosure", false)): continue
		if cell in building.get("occupied_cells", []): return true
	return false

func _complete_site(state: Dictionary, site: Dictionary) -> Dictionary:
	var site_id := String(site.site_id)
	var cell := Vector2i(site.cell)
	match String(site.piece_kind):
		"wall": state.completed_structures.structure_cells[cell] = _structure_record(site)
		"door", "window":
			var wall: Dictionary = state.completed_structures.structure_cells[cell]
			wall.fixture_kind = String(site.piece_kind)
			wall.fixture_orientation = String(site.orientation_axis)
		"floor": state.completed_structures.floor_cells[cell] = {"cell": cell, "kind": "floor"}
	state.completed_sites[site_id] = {"site_id": site_id, "location_id": site.location_id, "cell": cell, "piece_kind": site.piece_kind}
	var unblocked_site_ids: Array[String] = []
	for candidate: Dictionary in state.construction_sites.values():
		if site_id in candidate.get("prerequisite_site_ids", []): unblocked_site_ids.append(String(candidate.site_id))
	unblocked_site_ids.sort()
	if String(site.piece_kind) in BASE_STRUCTURE_KINDS and String(state.structure_site_cells.get(cell, "")) == site_id: state.structure_site_cells.erase(cell)
	elif String(site.piece_kind) in FIXTURE_KINDS and String(state.fixture_site_cells.get(cell, "")) == site_id: state.fixture_site_cells.erase(cell)
	state.construction_sites.erase(site_id)
	return {"ok": true, "reason": "construction_completed", "site_id": site_id, "piece_kind": site.piece_kind, "cell": cell, "unblocked_site_ids": unblocked_site_ids}

func _structure_record(site: Dictionary) -> Dictionary:
	return {"world_space_id": String(site.location_id), "cell": Vector2i(site.cell), "kind": "wall", "fixture_kind": "", "fixture_orientation": ""}

func _result(ok: bool, reason: String) -> Dictionary:
	return {"ok": ok, "reason": reason}
