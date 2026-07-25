extends RefCounted
class_name LocationConstructionCoordinator

const BuildingDefinition = preload("res://scripts/buildings/building_definition.gd")
const PLANNED := "PLANNED"
const UNDER_CONSTRUCTION := "UNDER_CONSTRUCTION"
const COMPLETED := "COMPLETED"
const VALID_STATES := [PLANNED, UNDER_CONSTRUCTION, COMPLETED]

var _registry: LocationRegistry
var _buildings: Dictionary = {}
var _next_sequence := 1
var _capacity_reservations: Dictionary = {}
var _derived_enclosures: Dictionary = {}
var _next_enclosure_sequence := 1

## Owns authoritative local building records, occupied cells, Supply Cache
## worker/material reservations, construction, and formal storage. Colonist
## tasks provide assignment validity context; movement and presentation remain
## outside this owner.
func configure(registry: LocationRegistry) -> void: _registry = registry

func validate_placement(location_id: String, building_id: String, origin: Vector2i) -> Dictionary:
	if _registry == null or not _registry.has(location_id): return _result(false, "unknown_location")
	var location := _registry.get_record(location_id)
	if not bool(location.get("claimed", false)): return _result(false, "location_not_claimed")
	if not BuildingDefinition.has_definition(building_id): return _result(false, "unknown_building")
	if (location.colonist_presence_ids as Array).is_empty(): return _result(false, "no_colonist_present")
	var cells := _footprint_cells(building_id, origin)
	for cell: Vector2i in cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= int(location.map_size.x) or cell.y >= int(location.map_size.y): return _result(false, "outside_bounds")
		var terrain := _terrain_at(location, cell)
		if terrain.is_empty() or String(terrain.get("terrain", "")) == "WATER": return _result(false, "terrain_blocked")
		for resource: Dictionary in location.resources:
			if Vector2i(resource.cell) == cell and not bool(resource.get("depleted", false)): return _result(false, "resource_blocked")
		for pile: Dictionary in location.piles:
			if bool(pile.enabled) and Vector2i(pile.cell) == cell: return _result(false, "pile_blocked")
		if _cell_occupied(location_id, cell): return _result(false, "building_overlap")
	return {"ok": true, "reason": "valid", "occupied_cells": cells}

func place(colonist_id: String, location_id: String, building_id: String, origin: Vector2i) -> Dictionary:
	var valid := validate_placement(location_id, building_id, origin)
	if not bool(valid.ok): return valid
	if colonist_id not in _registry.get_record(location_id).colonist_presence_ids: return _result(false, "colonist_not_present")
	var definition := BuildingDefinition.get_definition(building_id)
	var id := "location_building_%04d" % _next_sequence; _next_sequence += 1
	_buildings[id] = {"building_instance_id": id, "location_id": location_id, "building_id": building_id, "origin_cell": origin, "occupied_cells": valid.occupied_cells, "state": PLANNED, "build_progress": 0.0, "required_work": float(definition.build_time), "cost": definition.cost.duplicate(true), "resources_consumed": false, "assigned_worker_id": "", "material_reservation_id": "", "storage_contents": {"wood": 0, "stone": 0, "food": 0}, "storage_capacity": int(definition.get("storage_capacity", 0)), "enabled": false}
	return {"ok": true, "reason": "building_placed", "building_instance_id": id}

func assign_worker(colonist_id: String, location_id: String, building_instance_id: String) -> Dictionary:
	if colonist_id.is_empty() or not _registry.has(location_id) or colonist_id not in _registry.get_record(location_id).colonist_presence_ids: return _result(false, "invalid_worker")
	var building: Dictionary = _buildings.get(building_instance_id, {})
	if building.is_empty() or String(building.location_id) != location_id: return _result(false, "building_missing")
	if String(building.state) == COMPLETED: return _result(false, "building_completed")
	if not String(building.assigned_worker_id) in ["", colonist_id]: return _result(false, "building_reserved")
	for other: Dictionary in _buildings.values():
		if String(other.building_instance_id) != building_instance_id and String(other.assigned_worker_id) == colonist_id and String(other.state) != COMPLETED: return _result(false, "worker_already_assigned")
	if String(building.assigned_worker_id) == colonist_id: return {"ok": true, "reason": "already_assigned", "building_instance_id": building_instance_id}
	if not bool(building.resources_consumed):
		var reservation_id := "construction_%s" % building.building_instance_id
		var reserved := _registry.reserve_local_resources(location_id, building.cost, reservation_id)
		if not bool(reserved.ok): return reserved
		building.material_reservation_id = reservation_id
	building.assigned_worker_id = colonist_id
	return {"ok": true, "reason": "worker_assigned", "building_instance_id": building_instance_id}

func release_worker(building_instance_id: String, colonist_id: String, _reason := "") -> Dictionary:
	var building: Dictionary = _buildings.get(building_instance_id, {})
	if building.is_empty(): return _result(false, "building_missing")
	if String(building.assigned_worker_id) != colonist_id: return _result(false, "assignment_owner_mismatch")
	_release_assignment(building)
	return {"ok": true, "reason": "worker_released", "building_instance_id": building_instance_id}

func release_all_for_worker(colonist_id: String, reason := "") -> Array[String]:
	var released: Array[String] = []
	for building: Dictionary in _buildings.values():
		if String(building.assigned_worker_id) == colonist_id:
			_release_assignment(building); released.append(String(building.building_instance_id))
	released.sort()
	return released

func cleanup_stale_worker_assignments(is_valid_assignment: Callable) -> Array[String]:
	var released: Array[String] = []
	for building: Dictionary in _buildings.values():
		var worker_id := String(building.assigned_worker_id)
		if not worker_id.is_empty() and not bool(is_valid_assignment.call(String(building.building_instance_id), worker_id)):
			_release_assignment(building); released.append(String(building.building_instance_id))
	released.sort()
	return released

func cancel_building(building_instance_id: String) -> Dictionary:
	var building: Dictionary = _buildings.get(building_instance_id, {})
	if building.is_empty(): return _result(false, "building_missing")
	if String(building.state) == COMPLETED: return _result(false, "building_completed")
	_release_assignment(building)
	_buildings.erase(building_instance_id)
	return {"ok": true, "reason": "building_cancelled", "building_instance_id": building_instance_id, "location_id": String(building.location_id)}

func advance_worker(colonist_id: String, location_id: String, skill: float, delta: float, target_building_id := "") -> Dictionary:
	var building: Dictionary = _buildings.get(target_building_id, {})
	if building.is_empty() or String(building.location_id) != location_id or String(building.state) == COMPLETED: return _result(false, "no_construction_available")
	if String(building.assigned_worker_id) != colonist_id: return _result(false, "assignment_required")
	if not bool(building.resources_consumed):
		var consumed := _registry.consume_reserved_resources(location_id, String(building.material_reservation_id))
		if not bool(consumed.ok): return consumed
		building.resources_consumed = true; building.material_reservation_id = ""; building.state = UNDER_CONSTRUCTION
	var rate := lerpf(0.65, 1.5, clampf(skill, 0.0, 20.0) / 20.0)
	building.build_progress = minf(float(building.required_work), float(building.build_progress) + maxf(delta, 0.0) * rate)
	if float(building.build_progress) >= float(building.required_work):
		building.state = COMPLETED; building.enabled = true; _release_assignment(building)
		return {"ok": true, "reason": "building_completed", "building_instance_id": building.building_instance_id}
	return {"ok": true, "reason": "construction_progress", "building_instance_id": building.building_instance_id}

func reserve_storage(location_id: String, resource_type: String, amount: int, owner: String) -> Dictionary:
	if amount <= 0 or owner.is_empty() or _capacity_reservations.has(owner): return _result(false, "invalid_storage_reservation")
	for building: Dictionary in get_building_snapshots(location_id):
		if String(building.building_id) == "supply_cache" and String(building.state) == COMPLETED and bool(building.enabled) and get_available_capacity(String(building.building_instance_id)) >= amount:
			_capacity_reservations[owner] = {"building_instance_id": building.building_instance_id, "resource_type": resource_type, "amount": amount}
			return {"ok": true, "reason": "storage_reserved", "building_instance_id": building.building_instance_id, "cell": building.origin_cell}
	return _result(false, "no_formal_storage_capacity")

func store_reserved(owner: String) -> Dictionary:
	if not _capacity_reservations.has(owner): return _result(false, "storage_not_reserved")
	var reservation: Dictionary = _capacity_reservations[owner]; var building: Dictionary = _buildings.get(String(reservation.building_instance_id), {})
	var used := 0; if not building.is_empty(): for stored_amount: Variant in building.storage_contents.values(): used += int(stored_amount)
	if building.is_empty() or used + int(reservation.amount) > int(building.storage_capacity): return _result(false, "storage_capacity_changed")
	building.storage_contents[String(reservation.resource_type)] += int(reservation.amount); _capacity_reservations.erase(owner)
	return {"ok": true, "reason": "stored", "building_instance_id": building.building_instance_id}

func release_storage(owner: String) -> void: _capacity_reservations.erase(owner)
func get_available_capacity(id: String) -> int:
	var b: Dictionary = _buildings.get(id, {}); if b.is_empty() or String(b.state) != COMPLETED: return 0
	var used := 0; for amount: Variant in b.storage_contents.values(): used += int(amount)
	var reserved := 0; for r: Dictionary in _capacity_reservations.values(): if String(r.building_instance_id) == id: reserved += int(r.amount)
	return maxi(int(b.storage_capacity) - used - reserved, 0)
func remove_resource(id: String, type: String, amount: int) -> Dictionary:
	var b: Dictionary = _buildings.get(id, {}); if b.is_empty() or amount <= 0 or int(b.storage_contents.get(type, 0)) < amount: return _result(false, "insufficient_stored_resource")
	b.storage_contents[type] -= amount; return _result(true, "removed")
func synchronize_derived_enclosures(location_id: String, regions: Array) -> Dictionary:
	var existing: Array[Dictionary] = []
	for building: Dictionary in _derived_enclosures.values():
		if String(building.location_id) == location_id: existing.append(building)
	existing.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.building_instance_id) < String(b.building_instance_id))
	var retained_ids: Dictionary = {}
	var replacement: Dictionary = {}
	for raw_region: Variant in regions:
		var cells: Array = (raw_region as Array).duplicate()
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
		var candidates: Array[String] = []
		for old: Dictionary in existing:
			var old_id := String(old.building_instance_id)
			if not retained_ids.has(old_id) and _cells_overlap(cells, old.interior_cells): candidates.append(old_id)
		candidates.sort()
		var id: String
		if candidates.is_empty():
			id = "local_enclosure_%06d" % _next_enclosure_sequence
			_next_enclosure_sequence += 1
		else:
			id = candidates[0]
			for candidate_id: String in candidates: retained_ids[candidate_id] = true
		replacement[id] = _derived_enclosure_record(id, location_id, cells)
	for id: Variant in _derived_enclosures.keys():
		if String(_derived_enclosures[id].location_id) == location_id: _derived_enclosures.erase(id)
	for id: String in replacement: _derived_enclosures[id] = replacement[id]
	return {"ok": true, "reason": "derived_enclosures_synchronized", "building_ids": replacement.keys()}

func get_building_snapshot(id: String) -> Dictionary:
	if _buildings.has(id): return _buildings[id].duplicate(true)
	return _derived_enclosures.get(id, {}).duplicate(true)
func is_building_available_for_worker(id: String, colonist_id: String) -> bool:
	var building: Dictionary = _buildings.get(id, {})
	return not building.is_empty() and String(building.state) != COMPLETED and String(building.assigned_worker_id) in ["", colonist_id]
func get_building_snapshots(location_id := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []; for b: Dictionary in _buildings.values(): if location_id.is_empty() or String(b.location_id) == location_id: result.append(b.duplicate(true))
	for b: Dictionary in _derived_enclosures.values(): if location_id.is_empty() or String(b.location_id) == location_id: result.append(b.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.building_instance_id) < String(b.building_instance_id)); return result
func export_state() -> Dictionary:
	var placed: Array[Dictionary] = []
	for building: Dictionary in _buildings.values():
		var copy := building.duplicate(true)
		copy.assigned_worker_id = ""
		copy.material_reservation_id = ""
		placed.append(copy)
	placed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.building_instance_id) < String(b.building_instance_id))
	return {"buildings": placed, "next_sequence": _next_sequence}
func import_state(data: Dictionary) -> Dictionary:
	var staged: Dictionary = {}
	if not data.get("buildings", []) is Array: return _result(false, "invalid_buildings")
	for raw: Variant in data.get("buildings", []):
		if not raw is Dictionary: return _result(false, "invalid_building")
		var b: Dictionary = raw; var id := String(b.get("building_instance_id", "")); var location_id := String(b.get("location_id", "")); var building_id := String(b.get("building_id", ""))
		if id.is_empty() or staged.has(id) or not _registry.has(location_id) or not bool(_registry.get_record(location_id).get("claimed", false)) or not BuildingDefinition.has_definition(building_id) or String(b.get("state", "")) not in VALID_STATES: return _result(false, "invalid_building")
		for existing: Dictionary in staged.values(): for cell: Variant in b.get("occupied_cells", []): if cell in existing.get("occupied_cells", []): return _result(false, "overlapping_buildings")
		var copy := b.duplicate(true); copy.assigned_worker_id = ""; copy.material_reservation_id = ""; staged[id] = copy
	_buildings = staged; _next_sequence = maxi(int(data.get("next_sequence", 1)), 1); _capacity_reservations.clear(); _derived_enclosures.clear(); _next_enclosure_sequence = 1; return _result(true, "imported")
func _release_assignment(building: Dictionary) -> void:
	var reservation_id := String(building.material_reservation_id)
	if not reservation_id.is_empty(): _registry.release_resource_reservation(reservation_id)
	building.material_reservation_id = ""
	building.assigned_worker_id = ""
func _cell_occupied(location_id: String, cell: Vector2i) -> bool:
	for b: Dictionary in _buildings.values(): if String(b.location_id) == location_id and cell in b.occupied_cells: return true
	return false
func _footprint_cells(building_id: String, origin: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []; var size := Vector2i(BuildingDefinition.get_definition(building_id).footprint)
	for y in range(size.y): for x in range(size.x): result.append(origin + Vector2i(x, y))
	return result
func _terrain_at(location: Dictionary, cell: Vector2i) -> Dictionary:
	for terrain: Dictionary in location.terrain: if Vector2i(terrain.cell) == cell: return terrain
	return {}
func _cells_overlap(first: Array, second: Array) -> bool:
	var indexed: Dictionary = {}; for cell: Vector2i in first: indexed[cell] = true
	for cell: Vector2i in second:
		if indexed.has(cell): return true
	return false
func _derived_enclosure_record(id: String, location_id: String, cells: Array) -> Dictionary:
	var origin := Vector2i.ZERO
	if not cells.is_empty(): origin = Vector2i(cells[0])
	return {"building_instance_id": id, "location_id": location_id, "building_id": "enclosed_structure", "display_name": "Enclosed Building", "origin_cell": origin, "occupied_cells": cells.duplicate(), "state": COMPLETED, "build_progress": 0.0, "required_work": 0.0, "cost": {}, "resources_consumed": true, "assigned_worker_id": "", "material_reservation_id": "", "storage_contents": {}, "storage_capacity": 0, "enabled": true, "derived_enclosure": true, "enclosed": true, "interior_cells": cells.duplicate(), "interior_cell_count": cells.size(), "usable_area": cells.size(), "storage_capacity_basis": cells.size()}
func _result(ok: bool, reason: String) -> Dictionary: return {"ok": ok, "reason": reason}
