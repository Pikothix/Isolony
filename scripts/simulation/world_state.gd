extends Node
class_name WorldState

signal resource_total_changed(resource_type: String, total: int)
signal storage_capacity_changed(capacity: int, stored: int)
signal time_changed(day: int, hour: int, minute: int)
signal day_started(day: int)
signal night_started(day: int)
signal day_phase_changed(is_daytime: bool)
signal construction_site_added(site: Dictionary)
signal construction_site_changed(site: Dictionary)
signal construction_site_cancelled(site_id: String, site: Dictionary)
signal construction_sites_replaced()
signal harvest_order_added(order: Dictionary)
signal harvest_order_changed(order: Dictionary)
signal harvest_order_removed(order_id: String, resource_id: String)
signal harvest_orders_replaced()
signal stockpile_zone_added(zone: Dictionary)
signal stockpile_zone_removed(zone_id: String)
signal stockpile_zones_replaced()
signal ground_item_added(item: Dictionary)
signal ground_item_removed(item_id: String)
signal ground_items_replaced()

const ResourceStockpileScript = preload("res://scripts/simulation/resource_stockpile.gd")
const TimeStateScript = preload("res://scripts/simulation/time_state.gd")
const BuildingDefinitionRef = preload("res://scripts/buildings/building_definition.gd")
const DEFAULT_JOB_CANDIDATE_LIMIT := 16
const MAX_JOB_CANDIDATE_LIMIT := 64

var _resource_stockpile
var _time_state
var _placement_query: Node
var _construction_sites: Dictionary = {}
var _occupied_construction_cells: Dictionary = {}
var _construction_reservations: Dictionary = {}
var _harvest_orders: Dictionary = {}
var _harvest_order_by_resource: Dictionary = {}
var _stockpile_zones: Dictionary = {}
var _stockpile_zone_by_cell: Dictionary = {}
var _next_stockpile_zone_id: int = 1
var _ground_items: Dictionary = {}
var _next_ground_item_id: int = 1
var _haul_reservations: Dictionary = {}

## Purpose: Minimal simulation-owned root for authoritative runtime state.
## Responsibility: Own resource/time/construction/harvest-order/stockpile-zone/ground-item state and coordinate authoritative cross-owner mutations.
## Assumption: ChunkManager supplies read-only loaded terrain/resource queries and renders reconstructible projections.
func _ready() -> void:
	_resource_stockpile = ResourceStockpileScript.new()
	_resource_stockpile.name = "ResourceStockpile"
	add_child(_resource_stockpile)
	_resource_stockpile.resource_total_changed.connect(_on_resource_total_changed)
	_resource_stockpile.storage_capacity_changed.connect(_on_storage_capacity_changed)
	_time_state = TimeStateScript.new()
	_time_state.name = "TimeState"
	add_child(_time_state)
	_time_state.time_changed.connect(_on_time_changed)
	_time_state.day_started.connect(_on_day_started)
	_time_state.night_started.connect(_on_night_started)
	_time_state.day_phase_changed.connect(_on_day_phase_changed)
	_refresh_storage_capacity()

func get_resource_stockpile() -> Node:
	return _resource_stockpile

func get_time_state() -> Node:
	return _time_state

func set_placement_query(placement_query: Node) -> void:
	_placement_query = placement_query

func validate_construction_placement(building_id: String, origin_cell: Vector2i) -> Dictionary:
	var definition: Dictionary = BuildingDefinitionRef.get_definition(building_id)
	if definition.is_empty():
		return _build_placement_result(false, "unknown_building_id", building_id, origin_cell, [])
	var footprint: Vector2i = definition.get("footprint", Vector2i.ZERO)
	if footprint.x <= 0 or footprint.y <= 0:
		return _build_placement_result(false, "invalid_footprint", building_id, origin_cell, [])
	var occupied_cells: Array[Vector2i] = []
	for y in range(footprint.y):
		for x in range(footprint.x):
			occupied_cells.append(origin_cell + Vector2i(x, y))
	if _placement_query == null:
		return _build_placement_result(false, "placement_query_unavailable", building_id, origin_cell, occupied_cells)
	for cell: Vector2i in occupied_cells:
		if not _placement_query.is_cell_loaded(cell):
			return _build_placement_result(false, "cell_not_loaded", building_id, origin_cell, occupied_cells)
		var tile_info: Dictionary = _placement_query.get_effective_tile_info(cell)
		var terrain_name: String = String(tile_info.get("terrain", ""))
		if not bool(tile_info.get("walkable", false)):
			return _build_placement_result(false, "cell_not_walkable", building_id, origin_cell, occupied_cells)
		if terrain_name == "WATER" or terrain_name == "ROCK_WALL" or bool(tile_info.get("mineable", false)):
			return _build_placement_result(false, "blocked_terrain", building_id, origin_cell, occupied_cells)
		if _placement_query.is_cell_blocked_by_resource(cell):
			return _build_placement_result(false, "cell_occupied", building_id, origin_cell, occupied_cells)
		if _occupied_construction_cells.has(cell):
			return _build_placement_result(false, "cell_occupied", building_id, origin_cell, occupied_cells)
		if _stockpile_zone_by_cell.has(cell):
			return _build_placement_result(false, "cell_in_stockpile_zone", building_id, origin_cell, occupied_cells)
	return _build_placement_result(true, "valid", building_id, origin_cell, occupied_cells)

func request_place_construction(building_id: String, origin_cell: Vector2i) -> Dictionary:
	var result: Dictionary = validate_construction_placement(building_id, origin_cell)
	if not bool(result.get("ok", false)):
		return result
	var definition: Dictionary = BuildingDefinitionRef.get_definition(building_id)
	var site_id := "%s:%d:%d" % [building_id, origin_cell.x, origin_cell.y]
	var consumed_resources: Dictionary = {}
	for resource_type: Variant in definition.get("cost", {}).keys():
		consumed_resources[String(resource_type)] = 0
	var site := {
		"site_id": site_id,
		"building_id": building_id,
		"origin_cell": origin_cell,
		"occupied_cells": result.get("occupied_cells", []).duplicate(),
		"required_resources": definition.get("cost", {}).duplicate(true),
		"consumed_resources": consumed_resources,
		"resources_consumed": false,
		"build_progress": 0.0,
		"build_time": float(definition.get("build_time", 0.0)),
		"completed": false,
	}
	_construction_sites[site_id] = site
	for cell: Vector2i in site["occupied_cells"]:
		_occupied_construction_cells[cell] = site_id
	construction_site_added.emit(site.duplicate(true))
	return _build_placement_result(true, "placed", building_id, origin_cell, site["occupied_cells"])

func request_cancel_construction(site_id: String) -> Dictionary:
	if site_id.is_empty():
		return _build_cancellation_result(false, "empty_site_id", site_id, "", Vector2i.ZERO, false)
	if not _construction_sites.has(site_id):
		return _build_cancellation_result(false, "unknown_site_id", site_id, "", Vector2i.ZERO, false)
	var site: Dictionary = _construction_sites[site_id]
	var building_id: String = String(site.get("building_id", ""))
	var origin_cell: Vector2i = site.get("origin_cell", Vector2i.ZERO)
	var resources_consumed: bool = bool(site.get("resources_consumed", false))
	if bool(site.get("completed", false)):
		return _build_cancellation_result(false, "already_completed", site_id, building_id, origin_cell, resources_consumed)
	if _construction_reservations.has(site_id):
		var worker_release: Dictionary = release_construction_reservation(site_id, "", "construction_cancelled")
		if not bool(worker_release.get("ok", false)):
			return _build_cancellation_result(false, "worker_%s" % String(worker_release.get("reason", "release_failed")), site_id, building_id, origin_cell, resources_consumed)
	var resource_reservation_id: String = _build_construction_resource_reservation_id(site_id)
	if _resource_stockpile.has_resource_reservation(resource_reservation_id):
		var resource_release: Dictionary = _resource_stockpile.release_resource_reservation(resource_reservation_id)
		if not bool(resource_release.get("ok", false)):
			return _build_cancellation_result(false, "resource_%s" % String(resource_release.get("reason", "release_failed")), site_id, building_id, origin_cell, resources_consumed)
	for cell: Vector2i in site.get("occupied_cells", []):
		if String(_occupied_construction_cells.get(cell, "")) == site_id:
			_occupied_construction_cells.erase(cell)
	_construction_sites.erase(site_id)
	construction_site_cancelled.emit(site_id, site.duplicate(true))
	return _build_cancellation_result(true, "cancelled", site_id, building_id, origin_cell, resources_consumed)

func get_available_construction_site() -> Dictionary:
	var sites: Array[Dictionary] = get_available_construction_sites(1)
	return sites[0] if not sites.is_empty() else {}

func get_available_construction_sites(limit: int = DEFAULT_JOB_CANDIDATE_LIMIT) -> Array[Dictionary]:
	## Return a bounded stable-id-ordered snapshot without creating worker or resource reservations.
	var sites: Array[Dictionary] = []
	var candidate_limit: int = clampi(limit, 0, MAX_JOB_CANDIDATE_LIMIT)
	if candidate_limit == 0:
		return sites
	var site_ids: Array[String] = []
	for site_id_value: Variant in _construction_sites.keys():
		site_ids.append(String(site_id_value))
	site_ids.sort()
	for site_id: String in site_ids:
		var site: Dictionary = _construction_sites[site_id]
		if bool(site.get("completed", false)) or _construction_reservations.has(site_id):
			continue
		if _placement_query != null and not _placement_query.is_cell_loaded(site.get("origin_cell", Vector2i.ZERO)):
			continue
		if not _can_fund_construction_site(site):
			continue
		sites.append(site.duplicate(true))
		if sites.size() >= candidate_limit:
			break
	return sites

func reserve_construction_site(colonist_id: String, site_id: String) -> Dictionary:
	if colonist_id.is_empty():
		return _build_reservation_result(false, "empty_colonist_id", site_id, colonist_id)
	if not _construction_sites.has(site_id):
		return _build_reservation_result(false, "unknown_site_id", site_id, colonist_id)
	var site: Dictionary = _construction_sites[site_id]
	if bool(site.get("completed", false)):
		return _build_reservation_result(false, "already_completed", site_id, colonist_id)
	if _construction_reservations.has(site_id):
		var existing_colonist: String = String(_construction_reservations[site_id])
		if existing_colonist == colonist_id:
			return _build_reservation_result(true, "already_reserved", site_id, colonist_id)
		return _build_reservation_result(false, "already_reserved", site_id, existing_colonist)
	if not _can_fund_construction_site(site):
		return _build_reservation_result(false, "insufficient_resources", site_id, colonist_id)
	if not bool(site.get("resources_consumed", false)):
		var resource_result: Dictionary = _resource_stockpile.reserve_resources(_build_construction_resource_reservation_id(site_id), site.get("required_resources", {}))
		if not bool(resource_result.get("ok", false)):
			return _build_reservation_result(false, String(resource_result.get("reason", "resource_reservation_failed")), site_id, colonist_id)
	_construction_reservations[site_id] = colonist_id
	return _build_reservation_result(true, "reserved", site_id, colonist_id)

func release_construction_reservation(site_id: String, colonist_id: String = "", cleanup_reason: String = "released") -> Dictionary:
	if not _construction_reservations.has(site_id):
		return _build_reservation_result(false, "not_reserved", site_id, colonist_id, cleanup_reason)
	var reserved_by: String = String(_construction_reservations[site_id])
	if not colonist_id.is_empty() and reserved_by != colonist_id:
		return _build_reservation_result(false, "reserved_by_other_colonist", site_id, reserved_by, cleanup_reason)
	var resource_reservation_id: String = _build_construction_resource_reservation_id(site_id)
	if _resource_stockpile.has_resource_reservation(resource_reservation_id):
		var resource_result: Dictionary = _resource_stockpile.release_resource_reservation(resource_reservation_id)
		if not bool(resource_result.get("ok", false)):
			return _build_reservation_result(false, String(resource_result.get("reason", "resource_release_failed")), site_id, reserved_by, cleanup_reason)
	_construction_reservations.erase(site_id)
	return _build_reservation_result(true, "released", site_id, reserved_by, cleanup_reason)

func release_construction_site(site_id: String, colonist_id: String = "") -> Dictionary:
	## Backward-compatible entry point retained for the Milestone 15 colonist flow.
	return release_construction_reservation(site_id, colonist_id, "release_requested")

func release_all_reservations_for_colonist(colonist_id: String, cleanup_reason: String = "colonist_cleanup") -> Dictionary:
	if colonist_id.is_empty():
		return _build_cleanup_result(false, "empty_colonist_id", colonist_id, [], [])
	var site_ids: Array[String] = []
	for site_id: Variant in _construction_reservations.keys():
		if String(_construction_reservations[site_id]) == colonist_id:
			site_ids.append(String(site_id))
	var released_site_ids: Array[String] = []
	var failed_site_ids: Array[String] = []
	for site_id: String in site_ids:
		var result: Dictionary = release_construction_reservation(site_id, colonist_id, cleanup_reason)
		if bool(result.get("ok", false)):
			released_site_ids.append(site_id)
		else:
			failed_site_ids.append(site_id)
	var result_reason := "cleanup_failed" if not failed_site_ids.is_empty() else ("released" if not released_site_ids.is_empty() else "no_reservations")
	return _build_cleanup_result(failed_site_ids.is_empty(), result_reason, colonist_id, released_site_ids, failed_site_ids)

func cleanup_stale_construction_reservations(active_colonist_ids: Array) -> Dictionary:
	var active_ids: Dictionary = {}
	for colonist_id: Variant in active_colonist_ids:
		var id_text: String = String(colonist_id)
		if not id_text.is_empty():
			active_ids[id_text] = true
	var stale_site_ids: Array[String] = []
	for site_id: Variant in _construction_reservations.keys():
		var id_text: String = String(site_id)
		var owner_id: String = String(_construction_reservations[site_id])
		var site: Dictionary = _construction_sites.get(id_text, {})
		if not active_ids.has(owner_id) or site.is_empty() or bool(site.get("completed", false)):
			stale_site_ids.append(id_text)
	var released_site_ids: Array[String] = []
	var failed_site_ids: Array[String] = []
	for site_id: String in stale_site_ids:
		var result: Dictionary = release_construction_reservation(site_id, "", "stale_owner_cleanup")
		if bool(result.get("ok", false)):
			released_site_ids.append(site_id)
		else:
			failed_site_ids.append(site_id)
	var result_reason := "cleanup_failed" if not failed_site_ids.is_empty() else ("cleaned" if not released_site_ids.is_empty() else "nothing_stale")
	return _build_cleanup_result(failed_site_ids.is_empty(), result_reason, "", released_site_ids, failed_site_ids)

func get_construction_reservation_summary() -> Dictionary:
	var entries: Array[Dictionary] = []
	for site_id: Variant in _construction_reservations.keys():
		var id_text: String = String(site_id)
		var site: Dictionary = _construction_sites.get(id_text, {})
		entries.append({
			"site_id": id_text,
			"colonist_id": String(_construction_reservations[site_id]),
			"resource_reserved": _resource_stockpile.has_resource_reservation(_build_construction_resource_reservation_id(id_text)),
			"resources_consumed": bool(site.get("resources_consumed", false)),
			"completed": bool(site.get("completed", false)),
		})
	return {"count": entries.size(), "reservations": entries}

func get_construction_reservation(site_id: String) -> String:
	return String(_construction_reservations.get(site_id, ""))

func get_construction_site(site_id: String) -> Dictionary:
	if not _construction_sites.has(site_id):
		return {}
	return (_construction_sites[site_id] as Dictionary).duplicate(true)

func get_completed_building_effects() -> Array[Dictionary]:
	var effects: Array[Dictionary] = []
	for site: Variant in _construction_sites.values():
		var site_data: Dictionary = site
		if not bool(site_data.get("completed", false)):
			continue
		var building_id: String = String(site_data.get("building_id", ""))
		var definition: Dictionary = BuildingDefinitionRef.get_definition(building_id)
		if definition.is_empty():
			continue
		var light_radius: float = maxf(float(definition.get("light_radius", 0.0)), 0.0)
		var warmth_radius: float = maxf(float(definition.get("warmth_radius", 0.0)), 0.0)
		var shelter_radius: float = maxf(float(definition.get("shelter_radius", 0.0)), 0.0)
		var shelter_capacity: int = maxi(int(definition.get("shelter_capacity", 0)), 0)
		if light_radius <= 0.0 and warmth_radius <= 0.0 and shelter_radius <= 0.0:
			continue
		effects.append({
			"site_id": String(site_data.get("site_id", "")),
			"building_id": building_id,
			"origin_cell": site_data.get("origin_cell", Vector2i.ZERO),
			"light_radius": light_radius,
			"warmth_radius": warmth_radius,
			"shelter_radius": shelter_radius,
			"shelter_capacity": shelter_capacity,
			"effect_tags": definition.get("effect_tags", []).duplicate(),
		})
	return effects

func get_effects_at_cell(cell: Vector2i) -> Dictionary:
	var light_sources: Array[String] = []
	var warmth_sources: Array[String] = []
	var shelter_sources: Array[String] = []
	var shelter_capacity: int = 0
	for effect: Dictionary in get_completed_building_effects():
		var origin_cell: Vector2i = effect.get("origin_cell", Vector2i.ZERO)
		var distance: float = Vector2(cell - origin_cell).length()
		var site_id: String = String(effect.get("site_id", ""))
		if float(effect.get("light_radius", 0.0)) > 0.0 and distance <= float(effect.get("light_radius", 0.0)):
			light_sources.append(site_id)
		if float(effect.get("warmth_radius", 0.0)) > 0.0 and distance <= float(effect.get("warmth_radius", 0.0)):
			warmth_sources.append(site_id)
		if float(effect.get("shelter_radius", 0.0)) > 0.0 and distance <= float(effect.get("shelter_radius", 0.0)):
			shelter_sources.append(site_id)
			shelter_capacity += int(effect.get("shelter_capacity", 0))
	return {
		"cell": cell,
		"is_lit": not light_sources.is_empty(),
		"is_warmed": not warmth_sources.is_empty(),
		"is_sheltered": not shelter_sources.is_empty(),
		"light_sources": light_sources,
		"warmth_sources": warmth_sources,
		"shelter_sources": shelter_sources,
		"shelter_capacity": shelter_capacity,
	}

func is_cell_lit(cell: Vector2i) -> bool:
	return bool(get_effects_at_cell(cell).get("is_lit", false))

func is_cell_warmed(cell: Vector2i) -> bool:
	return bool(get_effects_at_cell(cell).get("is_warmed", false))

func get_nearest_warmed_cell(from_cell: Vector2i) -> Dictionary:
	## Return the nearest currently loaded, walkable cell covered by completed-building warmth.
	return _get_nearest_effect_cell(from_cell, "warmth_radius")

func get_shelter_sources() -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	for effect: Dictionary in get_completed_building_effects():
		if float(effect.get("shelter_radius", 0.0)) > 0.0:
			sources.append(effect.duplicate(true))
	return sources

func get_shelter_at_cell(cell: Vector2i) -> Dictionary:
	var effects: Dictionary = get_effects_at_cell(cell)
	return {
		"cell": cell,
		"is_sheltered": bool(effects.get("is_sheltered", false)),
		"shelter_sources": effects.get("shelter_sources", []).duplicate(),
		"shelter_capacity": int(effects.get("shelter_capacity", 0)),
	}

func is_cell_sheltered(cell: Vector2i) -> bool:
	return bool(get_shelter_at_cell(cell).get("is_sheltered", false))

func get_nearest_sheltered_cell(from_cell: Vector2i) -> Dictionary:
	## Return the nearest currently loaded, walkable cell covered by completed-building shelter.
	return _get_nearest_effect_cell(from_cell, "shelter_radius")

func _get_nearest_effect_cell(from_cell: Vector2i, radius_key: String) -> Dictionary:
	if _placement_query == null:
		return {"ok": false, "reason": "placement_query_unavailable", "cell": from_cell, "site_id": ""}
	var found: bool = false
	var nearest_cell: Vector2i = from_cell
	var nearest_site_id: String = ""
	var nearest_distance_squared: int = 0
	for effect: Dictionary in get_completed_building_effects():
		var radius: float = float(effect.get(radius_key, 0.0))
		if radius <= 0.0:
			continue
		var origin_cell: Vector2i = effect.get("origin_cell", Vector2i.ZERO)
		var cell_radius: int = ceili(radius)
		for y in range(-cell_radius, cell_radius + 1):
			for x in range(-cell_radius, cell_radius + 1):
				var offset := Vector2i(x, y)
				if Vector2(offset).length() > radius:
					continue
				var candidate: Vector2i = origin_cell + offset
				if not _is_valid_effect_target_cell(candidate):
					continue
				var distance_squared: int = (candidate - from_cell).length_squared()
				if not found or distance_squared < nearest_distance_squared:
					found = true
					nearest_cell = candidate
					nearest_site_id = String(effect.get("site_id", ""))
					nearest_distance_squared = distance_squared
	if not found:
		return {"ok": false, "reason": "no_valid_effect_cell", "cell": from_cell, "site_id": ""}
	return {
		"ok": true,
		"reason": "found",
		"cell": nearest_cell,
		"site_id": nearest_site_id,
	}

func _is_valid_effect_target_cell(cell: Vector2i) -> bool:
	if not _placement_query.is_cell_loaded(cell):
		return false
	var tile_info: Dictionary = _placement_query.get_effective_tile_info(cell)
	if not bool(tile_info.get("walkable", false)):
		return false
	var terrain_name: String = String(tile_info.get("terrain", ""))
	if terrain_name == "WATER" or terrain_name == "ROCK_WALL" or bool(tile_info.get("mineable", false)):
		return false
	if _placement_query.is_cell_blocked_by_resource(cell):
		return false
	return not _occupied_construction_cells.has(cell)

func request_progress_construction(site_id: String, amount: float = 1.0, colonist_id: String = "") -> Dictionary:
	## Consume the site's earmark on first work (or spend unreserved stock for debug use), then apply progress.
	if not _construction_sites.has(site_id):
		return _build_progress_result(false, "unknown_site_id", site_id, amount, 0.0, false, false)
	var site: Dictionary = _construction_sites[site_id]
	if bool(site.get("completed", false)):
		return _build_progress_result(false, "already_completed", site_id, amount, float(site.get("build_progress", 0.0)), true, bool(site.get("resources_consumed", false)))
	var building_id: String = String(site.get("building_id", ""))
	var definition: Dictionary = BuildingDefinitionRef.get_definition(building_id)
	if definition.is_empty():
		return _build_progress_result(false, "missing_building_definition", site_id, amount, float(site.get("build_progress", 0.0)), false, bool(site.get("resources_consumed", false)))
	if not is_finite(amount) or amount <= 0.0:
		return _build_progress_result(false, "invalid_progress_amount", site_id, amount, float(site.get("build_progress", 0.0)), false, bool(site.get("resources_consumed", false)))
	if not colonist_id.is_empty() and String(_construction_reservations.get(site_id, "")) != colonist_id:
		return _build_progress_result(false, "site_not_reserved_by_colonist", site_id, amount, float(site.get("build_progress", 0.0)), false, bool(site.get("resources_consumed", false)))
	var required_build_amount: float = float(definition.get("build_time", 0.0))
	if not is_finite(required_build_amount) or required_build_amount <= 0.0:
		return _build_progress_result(false, "invalid_build_amount", site_id, amount, float(site.get("build_progress", 0.0)), false, bool(site.get("resources_consumed", false)))
	var resources_consumed: bool = bool(site.get("resources_consumed", false))
	if not resources_consumed:
		var resource_reservation_id: String = _build_construction_resource_reservation_id(site_id)
		var spend_result: Dictionary
		if _resource_stockpile.has_resource_reservation(resource_reservation_id):
			spend_result = _resource_stockpile.consume_reserved_resources(resource_reservation_id)
		elif not colonist_id.is_empty():
			return _build_progress_result(false, "missing_resource_reservation", site_id, amount, float(site.get("build_progress", 0.0)), false, false)
		else:
			spend_result = _resource_stockpile.request_spend_resources(site.get("required_resources", {}))
		if not bool(spend_result.get("ok", false)):
			return _build_progress_result(false, String(spend_result.get("reason", "resource_spend_failed")), site_id, amount, float(site.get("build_progress", 0.0)), false, false)
		site["resources_consumed"] = true
		site["consumed_resources"] = site.get("required_resources", {}).duplicate(true)
		resources_consumed = true
	var next_progress: float = minf(float(site.get("build_progress", 0.0)) + amount, required_build_amount)
	site["build_progress"] = next_progress
	site["build_time"] = required_build_amount
	if next_progress >= required_build_amount:
		site["completed"] = true
		if _construction_reservations.has(site_id):
			release_construction_reservation(site_id, colonist_id, "construction_completed")
	_construction_sites[site_id] = site
	if bool(site["completed"]):
		_refresh_storage_capacity()
	construction_site_changed.emit(site.duplicate(true))
	return _build_progress_result(true, "completed" if bool(site["completed"]) else "progressed", site_id, amount, next_progress, bool(site["completed"]), resources_consumed)

func get_construction_site_at_cell(cell: Vector2i) -> Dictionary:
	if not _occupied_construction_cells.has(cell):
		return {}
	var site_id: String = String(_occupied_construction_cells[cell])
	if not _construction_sites.has(site_id):
		return {}
	return (_construction_sites[site_id] as Dictionary).duplicate(true)

func _can_fund_construction_site(site: Dictionary) -> bool:
	if bool(site.get("resources_consumed", false)):
		return true
	return _resource_stockpile.can_reserve_resources(site.get("required_resources", {}))

func get_construction_sites() -> Array[Dictionary]:
	var sites: Array[Dictionary] = []
	for site: Variant in _construction_sites.values():
		sites.append((site as Dictionary).duplicate(true))
	return sites

func request_create_stockpile_zone(cells: Array) -> Dictionary:
	## Validate the complete request before assigning an id or mutating authoritative zone state.
	var validation: Dictionary = _validate_stockpile_zone_cells(cells, true, _stockpile_zone_by_cell)
	if not bool(validation.get("ok", false)):
		return _build_stockpile_zone_result(false, String(validation.get("reason", "invalid_cells")), {}, validation.get("invalid_cell", Vector2i.ZERO))
	var normalized_cells: Array[Vector2i] = validation.get("cells", [])
	var zone_number: int = _next_stockpile_zone_id
	var zone_id := "stockpile_%04d" % zone_number
	while _stockpile_zones.has(zone_id):
		zone_number += 1
		zone_id = "stockpile_%04d" % zone_number
	_next_stockpile_zone_id = zone_number + 1
	var zone := {
		"zone_id": zone_id,
		"cells": normalized_cells,
		"enabled": true,
		"label": "Stockpile %d" % zone_number,
	}
	_stockpile_zones[zone_id] = zone
	for cell: Vector2i in normalized_cells:
		_stockpile_zone_by_cell[cell] = zone_id
	stockpile_zone_added.emit(zone.duplicate(true))
	return _build_stockpile_zone_result(true, "created", zone, Vector2i.ZERO)

func request_remove_stockpile_zone(zone_id: String) -> Dictionary:
	if zone_id.is_empty():
		return _build_stockpile_zone_result(false, "empty_zone_id", {}, Vector2i.ZERO)
	if not _stockpile_zones.has(zone_id):
		return _build_stockpile_zone_result(false, "unknown_zone_id", {}, Vector2i.ZERO)
	var zone: Dictionary = _stockpile_zones[zone_id]
	for cell: Vector2i in zone.get("cells", []):
		if String(_stockpile_zone_by_cell.get(cell, "")) == zone_id:
			_stockpile_zone_by_cell.erase(cell)
	_stockpile_zones.erase(zone_id)
	stockpile_zone_removed.emit(zone_id)
	return _build_stockpile_zone_result(true, "removed", zone, Vector2i.ZERO)

func get_stockpile_zones() -> Array[Dictionary]:
	var zones: Array[Dictionary] = []
	for zone_value: Variant in _stockpile_zones.values():
		zones.append((zone_value as Dictionary).duplicate(true))
	zones.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return String(first.get("zone_id", "")) < String(second.get("zone_id", ""))
	)
	return zones

func is_cell_in_stockpile_zone(cell: Vector2i) -> bool:
	return _stockpile_zone_by_cell.has(cell)

func export_stockpile_zones() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for zone: Dictionary in get_stockpile_zones():
		var serialized_cells: Array[Dictionary] = []
		for cell: Vector2i in zone.get("cells", []):
			serialized_cells.append(_serialize_cell(cell))
		entries.append({
			"zone_id": String(zone.get("zone_id", "")),
			"cells": serialized_cells,
			"enabled": bool(zone.get("enabled", true)),
			"label": String(zone.get("label", "")),
		})
	return entries

func import_stockpile_zones(entries: Array) -> Dictionary:
	## Import validates schema, duplicate cells, construction conflicts, and cross-zone overlap without requiring chunks to be loaded.
	var imported_zones: Dictionary = {}
	var imported_by_cell: Dictionary = {}
	var next_zone_number: int = 1
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			return _build_import_result(false, "invalid_stockpile_zone_entry")
		var entry: Dictionary = entry_value
		var zone_id: String = String(entry.get("zone_id", ""))
		if zone_id.is_empty() or imported_zones.has(zone_id):
			return _build_import_result(false, "invalid_or_duplicate_stockpile_zone_id")
		var cells: Array[Vector2i] = []
		for cell_value: Variant in entry.get("cells", []):
			if not cell_value is Dictionary:
				return _build_import_result(false, "invalid_stockpile_zone_cell")
			cells.append(_deserialize_cell(cell_value))
		var validation: Dictionary = _validate_stockpile_zone_cells(cells, false, imported_by_cell)
		if not bool(validation.get("ok", false)):
			return _build_import_result(false, "stockpile_zone_%s" % String(validation.get("reason", "invalid")))
		var normalized_cells: Array[Vector2i] = validation.get("cells", [])
		var zone := {
			"zone_id": zone_id,
			"cells": normalized_cells,
			"enabled": bool(entry.get("enabled", true)),
			"label": String(entry.get("label", zone_id)),
		}
		imported_zones[zone_id] = zone
		for cell: Vector2i in normalized_cells:
			imported_by_cell[cell] = zone_id
		if zone_id.begins_with("stockpile_") and zone_id.trim_prefix("stockpile_").is_valid_int():
			next_zone_number = maxi(next_zone_number, int(zone_id.trim_prefix("stockpile_")) + 1)
	_stockpile_zones = imported_zones
	_stockpile_zone_by_cell = imported_by_cell
	_next_stockpile_zone_id = next_zone_number
	stockpile_zones_replaced.emit()
	return _build_import_result(true, "imported")

func _validate_stockpile_zone_cells(cells: Array, require_loaded: bool, occupied_zone_cells: Dictionary) -> Dictionary:
	if cells.is_empty():
		return {"ok": false, "reason": "empty_cells", "cells": [], "invalid_cell": Vector2i.ZERO}
	if _placement_query == null:
		return {"ok": false, "reason": "placement_query_unavailable", "cells": [], "invalid_cell": Vector2i.ZERO}
	var normalized: Array[Vector2i] = []
	var seen: Dictionary = {}
	for cell_value: Variant in cells:
		if typeof(cell_value) != TYPE_VECTOR2I:
			return {"ok": false, "reason": "invalid_cell", "cells": [], "invalid_cell": Vector2i.ZERO}
		var cell: Vector2i = cell_value
		if seen.has(cell):
			continue
		seen[cell] = true
		if require_loaded and not _placement_query.is_cell_loaded(cell):
			return {"ok": false, "reason": "cell_not_loaded", "cells": [], "invalid_cell": cell}
		if require_loaded:
			var tile_info: Dictionary = _placement_query.get_effective_tile_info(cell)
			var terrain_name: String = String(tile_info.get("terrain", ""))
			if not bool(tile_info.get("walkable", false)):
				return {"ok": false, "reason": "cell_not_walkable", "cells": [], "invalid_cell": cell}
			if terrain_name == "WATER" or terrain_name == "ROCK_WALL" or bool(tile_info.get("mineable", false)):
				return {"ok": false, "reason": "blocked_terrain", "cells": [], "invalid_cell": cell}
		if _occupied_construction_cells.has(cell):
			return {"ok": false, "reason": "cell_occupied_by_construction", "cells": [], "invalid_cell": cell}
		if occupied_zone_cells.has(cell):
			return {"ok": false, "reason": "zone_overlap", "cells": [], "invalid_cell": cell}
		normalized.append(cell)
	return {"ok": true, "reason": "valid", "cells": normalized, "invalid_cell": Vector2i.ZERO}

func create_ground_item(resource_type: String, amount: int, cell: Vector2i) -> Dictionary:
	## Public creation path for future simulation systems; visuals and UI must never call this as authority.
	var prepared: Dictionary = _prepare_ground_item(resource_type, amount, cell)
	if not bool(prepared.get("ok", false)):
		return _build_ground_item_result(false, String(prepared.get("reason", "invalid_item")), {})
	var item: Dictionary = prepared.get("item", {})
	_commit_ground_item(item, int(prepared.get("next_id", _next_ground_item_id + 1)))
	return _build_ground_item_result(true, "created", item)

func remove_ground_item(item_id: String) -> Dictionary:
	if item_id.is_empty():
		return _build_ground_item_result(false, "empty_item_id", {})
	if not _ground_items.has(item_id):
		return _build_ground_item_result(false, "unknown_item_id", {})
	if _haul_reservations.has(item_id):
		return _build_ground_item_result(false, "item_reserved", _ground_items[item_id])
	var item: Dictionary = _ground_items[item_id]
	_ground_items.erase(item_id)
	ground_item_removed.emit(item_id)
	return _build_ground_item_result(true, "removed", item)

func get_ground_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for item_value: Variant in _ground_items.values():
		items.append((item_value as Dictionary).duplicate(true))
	items.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return String(first.get("item_id", "")) < String(second.get("item_id", ""))
	)
	return items

func get_ground_items_in_cell_rect(cell_rect: Rect2i) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	if cell_rect.size.x <= 0 or cell_rect.size.y <= 0:
		return items
	for item: Dictionary in get_ground_items():
		if bool(item.get("enabled", true)) and cell_rect.has_point(item.get("cell", Vector2i.ZERO)):
			items.append(item)
	return items

func export_ground_items() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for item: Dictionary in get_ground_items():
		entries.append({
			"item_id": String(item.get("item_id", "")),
			"resource_type": String(item.get("resource_type", "")),
			"amount": int(item.get("amount", 0)),
			"cell": _serialize_cell(item.get("cell", Vector2i.ZERO)),
			"enabled": bool(item.get("enabled", true)),
		})
	# Carrying is transient. Save its payload as a ground item at the pickup cell so load cannot lose resources.
	for reservation_value: Variant in _haul_reservations.values():
		var reservation: Dictionary = reservation_value
		if not bool(reservation.get("picked_up", false)):
			continue
		var item: Dictionary = reservation.get("item", {})
		entries.append({
			"item_id": String(item.get("item_id", "")),
			"resource_type": String(item.get("resource_type", "")),
			"amount": int(item.get("amount", 0)),
			"cell": _serialize_cell(reservation.get("pickup_cell", item.get("cell", Vector2i.ZERO))),
			"enabled": true,
		})
	entries.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return String(first.get("item_id", "")) < String(second.get("item_id", ""))
	)
	return entries

func import_ground_items(entries: Array) -> Dictionary:
	var imported_items: Dictionary = {}
	var next_item_number: int = 1
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			return _build_import_result(false, "invalid_ground_item_entry")
		var entry: Dictionary = entry_value
		var item_id: String = String(entry.get("item_id", ""))
		var resource_type: String = String(entry.get("resource_type", ""))
		var amount: int = int(entry.get("amount", 0))
		if item_id.is_empty() or imported_items.has(item_id):
			return _build_import_result(false, "invalid_or_duplicate_ground_item_id")
		if resource_type.is_empty() or amount <= 0:
			return _build_import_result(false, "invalid_ground_item_fields")
		var item := {
			"item_id": item_id,
			"resource_type": resource_type,
			"amount": amount,
			"cell": _deserialize_cell(entry.get("cell", {})),
			"enabled": bool(entry.get("enabled", true)),
		}
		imported_items[item_id] = item
		if item_id.begins_with("ground_item_") and item_id.trim_prefix("ground_item_").is_valid_int():
			next_item_number = maxi(next_item_number, int(item_id.trim_prefix("ground_item_")) + 1)
	_ground_items = imported_items
	_next_ground_item_id = next_item_number
	_haul_reservations.clear()
	ground_items_replaced.emit()
	return _build_import_result(true, "imported")

func _prepare_ground_item(resource_type: String, amount: int, cell: Vector2i) -> Dictionary:
	if resource_type.is_empty():
		return {"ok": false, "reason": "empty_resource_type", "item": {}}
	if amount <= 0:
		return {"ok": false, "reason": "invalid_amount", "item": {}}
	var item_number: int = _next_ground_item_id
	var item_id := "ground_item_%06d" % item_number
	while _ground_items.has(item_id):
		item_number += 1
		item_id = "ground_item_%06d" % item_number
	return {
		"ok": true,
		"reason": "valid",
		"next_id": item_number + 1,
		"item": {
			"item_id": item_id,
			"resource_type": resource_type,
			"amount": amount,
			"cell": cell,
			"enabled": true,
		},
	}

func _commit_ground_item(item: Dictionary, next_id: int) -> void:
	var item_id: String = String(item.get("item_id", ""))
	_ground_items[item_id] = item
	_next_ground_item_id = maxi(next_id, _next_ground_item_id)
	ground_item_added.emit(item.duplicate(true))

func get_available_haul_item(_colonist_id: String = "") -> Dictionary:
	var items: Array[Dictionary] = get_available_haul_items(_colonist_id, 1)
	return items[0] if not items.is_empty() else {}

func get_available_haul_items(_colonist_id: String = "", limit: int = DEFAULT_JOB_CANDIDATE_LIMIT) -> Array[Dictionary]:
	## Destination selection is read-only here; reserve_haul_item() recomputes it and reserves capacity atomically.
	var candidates: Array[Dictionary] = []
	var candidate_limit: int = clampi(limit, 0, MAX_JOB_CANDIDATE_LIMIT)
	if candidate_limit == 0 or _placement_query == null:
		return candidates
	for item: Dictionary in get_ground_items():
		var item_id: String = String(item.get("item_id", ""))
		var item_cell: Vector2i = item.get("cell", Vector2i.ZERO)
		var amount: int = int(item.get("amount", 0))
		if not bool(item.get("enabled", true)) or _haul_reservations.has(item_id):
			continue
		if not _placement_query.is_cell_loaded(item_cell) or _is_cell_in_enabled_stockpile_zone(item_cell):
			continue
		if amount <= 0 or not _resource_stockpile.can_reserve_storage(amount):
			continue
		var destination: Dictionary = _find_haul_destination(item_cell)
		if not bool(destination.get("ok", false)):
			continue
		var candidate: Dictionary = item.duplicate(true)
		candidate["destination_cell"] = destination.get("cell", Vector2i.ZERO)
		candidates.append(candidate)
		if candidates.size() >= candidate_limit:
			break
	return candidates

func reserve_haul_item(item_id: String, colonist_id: String) -> Dictionary:
	if item_id.is_empty():
		return _build_haul_result(false, "empty_item_id", item_id, colonist_id, {}, {})
	if colonist_id.is_empty():
		return _build_haul_result(false, "empty_colonist_id", item_id, colonist_id, {}, {})
	if not _ground_items.has(item_id):
		return _build_haul_result(false, "unknown_item_id", item_id, colonist_id, {}, {})
	if _haul_reservations.has(item_id):
		var existing: Dictionary = _haul_reservations[item_id]
		var same_owner: bool = String(existing.get("reserved_by_colonist_id", "")) == colonist_id
		return _build_haul_result(same_owner, "already_reserved", item_id, colonist_id, existing.get("item", {}), existing)
	var item: Dictionary = _ground_items[item_id]
	var item_cell: Vector2i = item.get("cell", Vector2i.ZERO)
	if not bool(item.get("enabled", true)) or _placement_query == null or not _placement_query.is_cell_loaded(item_cell):
		return _build_haul_result(false, "item_unavailable", item_id, colonist_id, item, {})
	if _is_cell_in_enabled_stockpile_zone(item_cell):
		return _build_haul_result(false, "item_already_stockpiled", item_id, colonist_id, item, {})
	var destination: Dictionary = _find_haul_destination(item_cell)
	if not bool(destination.get("ok", false)):
		return _build_haul_result(false, String(destination.get("reason", "no_destination")), item_id, colonist_id, item, {})
	var storage_reservation_id: String = _build_haul_storage_reservation_id(item_id)
	var storage_result: Dictionary = _resource_stockpile.reserve_storage(storage_reservation_id, int(item.get("amount", 0)))
	if not bool(storage_result.get("ok", false)):
		return _build_haul_result(false, String(storage_result.get("reason", "storage_reservation_failed")), item_id, colonist_id, item, {})
	var reservation := {
		"item_id": item_id,
		"reserved_by_colonist_id": colonist_id,
		"destination_cell": destination.get("cell", Vector2i.ZERO),
		"storage_reservation_id": storage_reservation_id,
		"item": item.duplicate(true),
		"pickup_cell": item_cell,
		"picked_up": false,
	}
	_haul_reservations[item_id] = reservation
	return _build_haul_result(true, "reserved", item_id, colonist_id, item, reservation)

func get_haul_item_reservation(item_id: String) -> Dictionary:
	return (_haul_reservations.get(item_id, {}) as Dictionary).duplicate(true)

func release_haul_item(item_id: String, colonist_id: String = "", reason: String = "released") -> Dictionary:
	if not _haul_reservations.has(item_id):
		return _build_haul_result(false, "not_reserved", item_id, colonist_id, {}, {})
	var reservation: Dictionary = _haul_reservations[item_id]
	var reserved_by: String = String(reservation.get("reserved_by_colonist_id", ""))
	if not colonist_id.is_empty() and reserved_by != colonist_id:
		return _build_haul_result(false, "reserved_by_other_colonist", item_id, reserved_by, reservation.get("item", {}), reservation)
	if bool(reservation.get("picked_up", false)):
		_restore_reserved_haul_item(reservation, reservation.get("pickup_cell", Vector2i.ZERO))
	_release_haul_storage_reservation(reservation)
	_haul_reservations.erase(item_id)
	var result: Dictionary = _build_haul_result(true, "released", item_id, reserved_by, reservation.get("item", {}), reservation)
	result["release_reason"] = reason
	return result

func request_pickup_ground_item(item_id: String, colonist_id: String) -> Dictionary:
	if not _haul_reservations.has(item_id):
		return _build_haul_result(false, "not_reserved", item_id, colonist_id, {}, {})
	var reservation: Dictionary = _haul_reservations[item_id]
	if String(reservation.get("reserved_by_colonist_id", "")) != colonist_id:
		return _build_haul_result(false, "reservation_owner_mismatch", item_id, colonist_id, reservation.get("item", {}), reservation)
	if bool(reservation.get("picked_up", false)):
		return _build_haul_result(false, "already_picked_up", item_id, colonist_id, reservation.get("item", {}), reservation)
	if not _ground_items.has(item_id):
		return _build_haul_result(false, "item_missing", item_id, colonist_id, reservation.get("item", {}), reservation)
	var item: Dictionary = _ground_items[item_id]
	if not _haul_item_matches(item, reservation.get("item", {})):
		return _build_haul_result(false, "item_mismatch", item_id, colonist_id, item, reservation)
	_ground_items.erase(item_id)
	ground_item_removed.emit(item_id)
	reservation["picked_up"] = true
	reservation["item"] = item.duplicate(true)
	_haul_reservations[item_id] = reservation
	return _build_haul_result(true, "picked_up", item_id, colonist_id, item, reservation)

func request_deposit_carried_item(colonist_id: String, item_data: Dictionary, destination_cell: Vector2i) -> Dictionary:
	var item_id: String = String(item_data.get("item_id", ""))
	if not _haul_reservations.has(item_id):
		return _build_haul_result(false, "not_reserved", item_id, colonist_id, item_data, {})
	var reservation: Dictionary = _haul_reservations[item_id]
	if String(reservation.get("reserved_by_colonist_id", "")) != colonist_id:
		return _build_haul_result(false, "reservation_owner_mismatch", item_id, colonist_id, item_data, reservation)
	if not bool(reservation.get("picked_up", false)):
		return _build_haul_result(false, "item_not_picked_up", item_id, colonist_id, item_data, reservation)
	if not _haul_item_matches(item_data, reservation.get("item", {})):
		return _build_haul_result(false, "item_mismatch", item_id, colonist_id, item_data, reservation)
	if destination_cell != reservation.get("destination_cell", Vector2i.ZERO) or not _is_valid_haul_destination(destination_cell):
		return _build_haul_result(false, "destination_invalid", item_id, colonist_id, item_data, reservation)
	var amount: int = int(item_data.get("amount", 0))
	var storage_reservation_id: String = String(reservation.get("storage_reservation_id", ""))
	var capacity_result: Dictionary = _resource_stockpile.validate_storage_reservation(storage_reservation_id, amount)
	if not bool(capacity_result.get("ok", false)):
		return _build_haul_result(false, String(capacity_result.get("reason", "storage_reservation_invalid")), item_id, colonist_id, item_data, reservation)
	var consume_result: Dictionary = _resource_stockpile.consume_storage_reservation(storage_reservation_id, amount)
	if not bool(consume_result.get("ok", false)):
		return _build_haul_result(false, String(consume_result.get("reason", "storage_reservation_consume_failed")), item_id, colonist_id, item_data, reservation)
	var addition_result: Dictionary = _resource_stockpile.request_add_resource(String(item_data.get("resource_type", "")), amount)
	if not bool(addition_result.get("ok", false)):
		push_error("Haul deposit invariant failed after consuming reserved capacity: %s" % String(addition_result.get("reason", "addition_failed")))
		return _build_haul_result(false, "stockpile_commit_invariant_failed", item_id, colonist_id, item_data, reservation)
	_haul_reservations.erase(item_id)
	var result: Dictionary = _build_haul_result(true, "deposited", item_id, colonist_id, item_data, reservation)
	result["resource_total"] = _resource_stockpile.get_total(String(item_data.get("resource_type", "")))
	return result

func request_drop_carried_item(item_id: String, colonist_id: String, cell: Vector2i, reason: String = "haul_dropped") -> Dictionary:
	if not _haul_reservations.has(item_id):
		return _build_haul_result(false, "not_reserved", item_id, colonist_id, {}, {})
	var reservation: Dictionary = _haul_reservations[item_id]
	if String(reservation.get("reserved_by_colonist_id", "")) != colonist_id or not bool(reservation.get("picked_up", false)):
		return _build_haul_result(false, "drop_not_authorized", item_id, colonist_id, reservation.get("item", {}), reservation)
	var drop_result: Dictionary = create_ground_item(String(reservation.get("item", {}).get("resource_type", "")), int(reservation.get("item", {}).get("amount", 0)), cell)
	if not bool(drop_result.get("ok", false)):
		return _build_haul_result(false, "drop_%s" % String(drop_result.get("reason", "failed")), item_id, colonist_id, reservation.get("item", {}), reservation)
	_release_haul_storage_reservation(reservation)
	_haul_reservations.erase(item_id)
	var result: Dictionary = _build_haul_result(true, "dropped", item_id, colonist_id, drop_result.get("item", {}), reservation)
	result["release_reason"] = reason
	return result

func release_all_haul_reservations_for_colonist(colonist_id: String, reason: String = "colonist_cleanup") -> void:
	if colonist_id.is_empty():
		return
	for item_id_value: Variant in _haul_reservations.keys():
		var item_id: String = String(item_id_value)
		var reservation: Dictionary = _haul_reservations[item_id]
		if String(reservation.get("reserved_by_colonist_id", "")) == colonist_id:
			release_haul_item(item_id, colonist_id, reason)

func cleanup_stale_haul_reservations(active_colonist_ids: Array) -> void:
	var active: Dictionary = {}
	for colonist_id_value: Variant in active_colonist_ids:
		active[String(colonist_id_value)] = true
	for item_id_value: Variant in _haul_reservations.keys():
		var item_id: String = String(item_id_value)
		var reservation: Dictionary = _haul_reservations[item_id]
		if not active.has(String(reservation.get("reserved_by_colonist_id", ""))):
			release_haul_item(item_id, "", "stale_owner_cleanup")

func _find_haul_destination(from_cell: Vector2i) -> Dictionary:
	var found: bool = false
	var best_cell: Vector2i = Vector2i.ZERO
	var best_distance: int = 0
	for zone_value: Variant in _stockpile_zones.values():
		var zone: Dictionary = zone_value
		if not bool(zone.get("enabled", true)):
			continue
		for cell: Vector2i in zone.get("cells", []):
			if not _is_valid_haul_destination(cell):
				continue
			var distance: int = (cell - from_cell).length_squared()
			if not found or distance < best_distance or (distance == best_distance and (cell.y < best_cell.y or (cell.y == best_cell.y and cell.x < best_cell.x))):
				found = true
				best_cell = cell
				best_distance = distance
	return {"ok": found, "reason": "found" if found else "no_valid_stockpile_destination", "cell": best_cell}

func _is_valid_haul_destination(cell: Vector2i) -> bool:
	if _placement_query == null or not _placement_query.is_cell_loaded(cell) or not _is_cell_in_enabled_stockpile_zone(cell):
		return false
	var tile_info: Dictionary = _placement_query.get_effective_tile_info(cell)
	var terrain_name: String = String(tile_info.get("terrain", ""))
	return bool(tile_info.get("walkable", false)) and terrain_name != "WATER" and terrain_name != "ROCK_WALL" and not bool(tile_info.get("mineable", false)) and not _occupied_construction_cells.has(cell)

func _is_cell_in_enabled_stockpile_zone(cell: Vector2i) -> bool:
	var zone_id: String = String(_stockpile_zone_by_cell.get(cell, ""))
	return not zone_id.is_empty() and bool((_stockpile_zones.get(zone_id, {}) as Dictionary).get("enabled", true))

func _restore_reserved_haul_item(reservation: Dictionary, cell: Vector2i) -> void:
	var item: Dictionary = reservation.get("item", {})
	var restore_result: Dictionary = create_ground_item(String(item.get("resource_type", "")), int(item.get("amount", 0)), cell)
	if not bool(restore_result.get("ok", false)):
		push_error("Failed to restore abandoned carried item: %s" % String(restore_result.get("reason", "unknown")))

func _release_haul_storage_reservation(reservation: Dictionary) -> void:
	var reservation_id: String = String(reservation.get("storage_reservation_id", ""))
	if not reservation_id.is_empty() and _resource_stockpile.has_storage_reservation(reservation_id):
		_resource_stockpile.release_storage_reservation(reservation_id)

func _haul_item_matches(first: Dictionary, second: Dictionary) -> bool:
	return String(first.get("item_id", "")) == String(second.get("item_id", "")) and String(first.get("resource_type", "")) == String(second.get("resource_type", "")) and int(first.get("amount", 0)) == int(second.get("amount", 0))

func _build_haul_storage_reservation_id(item_id: String) -> String:
	return "haul_capacity:%s" % item_id

func export_construction_sites() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for site: Dictionary in get_construction_sites():
		var occupied_entries: Array[Dictionary] = []
		for cell: Vector2i in site.get("occupied_cells", []):
			occupied_entries.append(_serialize_cell(cell))
		entries.append({
			"site_id": String(site.get("site_id", "")),
			"building_id": String(site.get("building_id", "")),
			"origin_cell": _serialize_cell(site.get("origin_cell", Vector2i.ZERO)),
			"occupied_cells": occupied_entries,
			"required_resources": site.get("required_resources", {}).duplicate(true),
			"consumed_resources": site.get("consumed_resources", {}).duplicate(true),
			"resources_consumed": bool(site.get("resources_consumed", false)),
			"build_progress": float(site.get("build_progress", 0.0)),
			"build_time": float(site.get("build_time", 0.0)),
			"completed": bool(site.get("completed", false)),
		})
	return entries

func import_construction_sites(entries: Array) -> Dictionary:
	var imported_sites: Dictionary = {}
	var imported_occupied_cells: Dictionary = {}
	for entry: Variant in entries:
		if not entry is Dictionary:
			return _build_import_result(false, "invalid_construction_site_entry")
		var entry_dict: Dictionary = entry
		var building_id: String = String(entry_dict.get("building_id", ""))
		var definition: Dictionary = BuildingDefinitionRef.get_definition(building_id)
		if definition.is_empty():
			return _build_import_result(false, "unknown_construction_building")
		var origin_cell: Vector2i = _deserialize_cell(entry_dict.get("origin_cell", {}))
		var footprint_cells: Array[Vector2i] = []
		var saved_cells: Array = entry_dict.get("occupied_cells", entry_dict.get("footprint_cells", []))
		for cell_entry: Variant in saved_cells:
			if not cell_entry is Dictionary:
				return _build_import_result(false, "invalid_construction_footprint")
			footprint_cells.append(_deserialize_cell(cell_entry))
		var expected_footprint: Vector2i = definition.get("footprint", Vector2i.ZERO)
		if footprint_cells.size() != expected_footprint.x * expected_footprint.y or footprint_cells.is_empty():
			return _build_import_result(false, "invalid_construction_footprint")
		var expected_cells: Array[Vector2i] = []
		for y in range(expected_footprint.y):
			for x in range(expected_footprint.x):
				expected_cells.append(origin_cell + Vector2i(x, y))
		var site_cells: Dictionary = {}
		for cell: Vector2i in footprint_cells:
			if not expected_cells.has(cell) or site_cells.has(cell):
				return _build_import_result(false, "invalid_construction_footprint")
			site_cells[cell] = true
			if imported_occupied_cells.has(cell):
				return _build_import_result(false, "overlapping_construction_sites")
		var site_id: String = String(entry_dict.get("site_id", "%s:%d:%d" % [building_id, origin_cell.x, origin_cell.y]))
		if site_id.is_empty() or imported_sites.has(site_id):
			return _build_import_result(false, "invalid_construction_site_id")
		var site := {
			"site_id": site_id,
			"building_id": building_id,
			"origin_cell": origin_cell,
			"occupied_cells": footprint_cells,
			"required_resources": entry_dict.get("required_resources", definition.get("cost", {})).duplicate(true),
			"consumed_resources": entry_dict.get("consumed_resources", entry_dict.get("delivered_resources", {})).duplicate(true),
			"resources_consumed": bool(entry_dict.get("resources_consumed", false)),
			"build_progress": float(entry_dict.get("build_progress", 0.0)),
			"build_time": float(entry_dict.get("build_time", definition.get("build_time", 0.0))),
			"completed": bool(entry_dict.get("completed", false)),
		}
		imported_sites[site_id] = site
		for cell: Vector2i in footprint_cells:
			imported_occupied_cells[cell] = site_id
	_construction_sites = imported_sites
	_occupied_construction_cells = imported_occupied_cells
	_construction_reservations.clear()
	_resource_stockpile.clear_resource_reservations()
	_refresh_storage_capacity()
	construction_sites_replaced.emit()
	return _build_import_result(true, "imported")

func request_designate_harvest(resource_id: String) -> Dictionary:
	## Convert presentation input into simulation-owned intent without harvesting the resource.
	if resource_id.is_empty():
		return _build_harvest_order_result(false, "empty_resource_id", {})
	if _harvest_order_by_resource.has(resource_id):
		return _build_harvest_order_result(false, "already_designated", get_harvest_order(String(_harvest_order_by_resource[resource_id])))
	if _placement_query == null or not _placement_query.has_method("get_harvest_resource_snapshot"):
		return _build_harvest_order_result(false, "resource_query_unavailable", {})
	var snapshot: Dictionary = _placement_query.get_harvest_resource_snapshot(resource_id)
	if not bool(snapshot.get("ok", false)):
		return _build_harvest_order_result(false, String(snapshot.get("reason", "resource_invalid")), {})
	var order_id := "harvest:%s" % resource_id
	var order := {
		"order_id": order_id,
		"resource_id": resource_id,
		"resource_type": String(snapshot.get("resource_type", "")),
		"yield_amount": int(snapshot.get("yield_amount", 0)),
		"cell": snapshot.get("cell", Vector2i.ZERO),
		"reserved_by_colonist_id": "",
		"completed": false,
		"cancelled": false,
	}
	_harvest_orders[order_id] = order
	_harvest_order_by_resource[resource_id] = order_id
	harvest_order_added.emit(order.duplicate(true))
	return _build_harvest_order_result(true, "designated", order)

func request_cancel_harvest_order(order_id: String) -> Dictionary:
	if not _harvest_orders.has(order_id):
		return _build_harvest_order_result(false, "unknown_order_id", {})
	var order: Dictionary = _harvest_orders[order_id]
	order["cancelled"] = true
	_remove_harvest_order(order_id, order)
	return _build_harvest_order_result(true, "cancelled", order)

func get_harvest_order(order_id: String) -> Dictionary:
	if not _harvest_orders.has(order_id):
		return {}
	return (_harvest_orders[order_id] as Dictionary).duplicate(true)

func get_harvest_orders() -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	for order: Variant in _harvest_orders.values():
		orders.append((order as Dictionary).duplicate(true))
	return orders

func has_harvest_order_for_resource(resource_id: String) -> bool:
	return _harvest_order_by_resource.has(resource_id)

func get_available_harvest_order() -> Dictionary:
	var orders: Array[Dictionary] = get_available_harvest_orders(1)
	return orders[0] if not orders.is_empty() else {}

func get_available_harvest_orders(limit: int = DEFAULT_JOB_CANDIDATE_LIMIT) -> Array[Dictionary]:
	## Return valid live-resource-backed intent in deterministic order without reserving an order.
	var orders: Array[Dictionary] = []
	var candidate_limit: int = clampi(limit, 0, MAX_JOB_CANDIDATE_LIMIT)
	if candidate_limit == 0 or _placement_query == null:
		return orders
	var order_ids: Array[String] = []
	for order_id_value: Variant in _harvest_orders.keys():
		order_ids.append(String(order_id_value))
	order_ids.sort()
	for order_id: String in order_ids:
		var order: Dictionary = _harvest_orders[order_id]
		if not String(order.get("reserved_by_colonist_id", "")).is_empty():
			continue
		var snapshot: Dictionary = _placement_query.get_harvest_resource_snapshot(String(order.get("resource_id", "")))
		if not _harvest_snapshot_matches_order(snapshot, order):
			continue
		orders.append(order.duplicate(true))
		if orders.size() >= candidate_limit:
			break
	return orders

func reserve_harvest_order(order_id: String, colonist_id: String) -> Dictionary:
	if colonist_id.is_empty():
		return _build_harvest_order_result(false, "empty_colonist_id", {})
	if not _harvest_orders.has(order_id):
		return _build_harvest_order_result(false, "unknown_order_id", {})
	var order: Dictionary = _harvest_orders[order_id]
	var reserved_by: String = String(order.get("reserved_by_colonist_id", ""))
	if not reserved_by.is_empty():
		return _build_harvest_order_result(reserved_by == colonist_id, "already_reserved", order)
	var snapshot: Dictionary = _placement_query.get_harvest_resource_snapshot(String(order.get("resource_id", ""))) if _placement_query != null else {}
	if not _harvest_snapshot_matches_order(snapshot, order):
		return _build_harvest_order_result(false, String(snapshot.get("reason", "resource_invalid")), order)
	order["reserved_by_colonist_id"] = colonist_id
	_harvest_orders[order_id] = order
	harvest_order_changed.emit(order.duplicate(true))
	return _build_harvest_order_result(true, "reserved", order)

func release_harvest_order(order_id: String, colonist_id: String = "", reason: String = "released") -> Dictionary:
	if not _harvest_orders.has(order_id):
		return _build_harvest_order_result(false, "unknown_order_id", {})
	var order: Dictionary = _harvest_orders[order_id]
	var reserved_by: String = String(order.get("reserved_by_colonist_id", ""))
	if reserved_by.is_empty():
		return _build_harvest_order_result(false, "not_reserved", order)
	if not colonist_id.is_empty() and colonist_id != reserved_by:
		return _build_harvest_order_result(false, "reserved_by_other_colonist", order)
	order["reserved_by_colonist_id"] = ""
	order["release_reason"] = reason
	_harvest_orders[order_id] = order
	harvest_order_changed.emit(order.duplicate(true))
	return _build_harvest_order_result(true, "released", order)

func get_harvest_order_reservation(order_id: String) -> String:
	var order: Dictionary = _harvest_orders.get(order_id, {})
	return String(order.get("reserved_by_colonist_id", ""))

func release_all_harvest_orders_for_colonist(colonist_id: String, reason: String = "colonist_cleanup") -> void:
	if colonist_id.is_empty():
		return
	for order_id: Variant in _harvest_orders.keys():
		var order: Dictionary = _harvest_orders[order_id]
		if String(order.get("reserved_by_colonist_id", "")) == colonist_id:
			release_harvest_order(String(order_id), colonist_id, reason)

func cleanup_stale_harvest_reservations(active_colonist_ids: Array) -> void:
	var active_ids: Dictionary = {}
	for colonist_id: Variant in active_colonist_ids:
		active_ids[String(colonist_id)] = true
	for order_id: Variant in _harvest_orders.keys():
		var order: Dictionary = _harvest_orders[order_id]
		var reserved_by: String = String(order.get("reserved_by_colonist_id", ""))
		if not reserved_by.is_empty() and not active_ids.has(reserved_by):
			release_harvest_order(String(order_id), "", "stale_owner_cleanup")

func request_complete_harvest_order(order_id: String, colonist_id: String) -> Dictionary:
	## Preflight the complete item record before depletion; after commit, item publication cannot fail validation.
	if not _harvest_orders.has(order_id):
		return _build_harvest_order_result(false, "unknown_order_id", {})
	if colonist_id.is_empty():
		return _build_harvest_order_result(false, "empty_colonist_id", get_harvest_order(order_id))
	var order: Dictionary = _harvest_orders[order_id]
	if String(order.get("reserved_by_colonist_id", "")) != colonist_id:
		return _build_harvest_order_result(false, "reservation_owner_mismatch", order)
	if _placement_query == null or not _placement_query.has_method("commit_harvest_resource"):
		return _build_harvest_order_result(false, "resource_authority_unavailable", order)
	var snapshot: Dictionary = _placement_query.get_harvest_resource_snapshot(String(order.get("resource_id", "")))
	if not _harvest_snapshot_matches_order(snapshot, order):
		return _build_harvest_order_result(false, String(snapshot.get("reason", "resource_mismatch")), order)
	var resource_type: String = String(order.get("resource_type", ""))
	var yield_amount: int = int(order.get("yield_amount", 0))
	var item_cell: Vector2i = order.get("cell", Vector2i.ZERO)
	var prepared_item: Dictionary = _prepare_ground_item(resource_type, yield_amount, item_cell)
	if not bool(prepared_item.get("ok", false)):
		return _build_harvest_order_result(false, "ground_item_%s" % String(prepared_item.get("reason", "invalid")), order)
	var depletion_result: Dictionary = _placement_query.commit_harvest_resource(String(order.get("resource_id", "")))
	if not bool(depletion_result.get("ok", false)):
		return _build_harvest_order_result(false, String(depletion_result.get("reason", "depletion_failed")), order)
	var item: Dictionary = prepared_item.get("item", {})
	_commit_ground_item(item, int(prepared_item.get("next_id", _next_ground_item_id + 1)))
	order["completed"] = true
	_remove_harvest_order(order_id, order)
	var result: Dictionary = _build_harvest_order_result(true, "completed", order)
	result["item"] = item.duplicate(true)
	result["item_id"] = String(item.get("item_id", ""))
	result["amount_dropped"] = yield_amount
	return result

func export_harvest_orders() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for order: Dictionary in get_harvest_orders():
		entries.append({
			"order_id": String(order.get("order_id", "")),
			"resource_id": String(order.get("resource_id", "")),
			"resource_type": String(order.get("resource_type", "")),
			"yield_amount": int(order.get("yield_amount", 0)),
			"cell": _serialize_cell(order.get("cell", Vector2i.ZERO)),
		})
	return entries

func import_harvest_orders(entries: Array) -> Dictionary:
	var imported_orders: Dictionary = {}
	var imported_by_resource: Dictionary = {}
	for entry: Variant in entries:
		if not entry is Dictionary:
			return _build_import_result(false, "invalid_harvest_order_entry")
		var data: Dictionary = entry
		var resource_id: String = String(data.get("resource_id", ""))
		var order_id: String = String(data.get("order_id", "harvest:%s" % resource_id))
		var resource_type: String = String(data.get("resource_type", ""))
		var yield_amount: int = int(data.get("yield_amount", 0))
		if resource_id.is_empty() or order_id.is_empty() or resource_type.is_empty() or yield_amount <= 0:
			return _build_import_result(false, "invalid_harvest_order_fields")
		if imported_orders.has(order_id) or imported_by_resource.has(resource_id):
			return _build_import_result(false, "duplicate_harvest_order")
		var order := {
			"order_id": order_id,
			"resource_id": resource_id,
			"resource_type": resource_type,
			"yield_amount": yield_amount,
			"cell": _deserialize_cell(data.get("cell", {})),
			"reserved_by_colonist_id": "",
			"completed": false,
			"cancelled": false,
		}
		imported_orders[order_id] = order
		imported_by_resource[resource_id] = order_id
	_harvest_orders = imported_orders
	_harvest_order_by_resource = imported_by_resource
	_resource_stockpile.clear_storage_reservations()
	harvest_orders_replaced.emit()
	return _build_import_result(true, "imported")

func discard_depleted_harvest_orders() -> int:
	## Called after ChunkManager imports depletion ids so stale saved intent cannot survive.
	if _placement_query == null:
		return 0
	var discarded: int = 0
	for order_id: Variant in _harvest_orders.keys():
		var order: Dictionary = _harvest_orders[order_id]
		if _placement_query.is_resource_depleted(String(order.get("resource_id", ""))):
			_remove_harvest_order(String(order_id), order)
			discarded += 1
	return discarded

func _harvest_snapshot_matches_order(snapshot: Dictionary, order: Dictionary) -> bool:
	return (
		bool(snapshot.get("ok", false))
		and String(snapshot.get("resource_id", "")) == String(order.get("resource_id", ""))
		and String(snapshot.get("resource_type", "")) == String(order.get("resource_type", ""))
		and int(snapshot.get("yield_amount", 0)) == int(order.get("yield_amount", 0))
		and snapshot.get("cell", Vector2i.ZERO) == order.get("cell", Vector2i.ZERO)
	)

func _remove_harvest_order(order_id: String, order: Dictionary) -> void:
	var resource_id: String = String(order.get("resource_id", ""))
	_harvest_orders.erase(order_id)
	_harvest_order_by_resource.erase(resource_id)
	harvest_order_removed.emit(order_id, resource_id)

func advance_time(delta: float) -> void:
	if _time_state == null:
		return
	_time_state.advance(delta)

func get_time_label() -> String:
	if _time_state == null:
		return ""
	return _time_state.get_time_label()

func is_day() -> bool:
	return _time_state != null and _time_state.is_day()

func is_night() -> bool:
	return _time_state != null and _time_state.is_night()

func add_resource(resource_type: String, amount: int) -> Dictionary:
	if _resource_stockpile == null:
		return _build_resource_result(false, "stockpile_unavailable", resource_type, amount, 0)
	return _resource_stockpile.request_add_resource(resource_type, amount)

func validate_resource_addition(resource_type: String, amount: int) -> Dictionary:
	if _resource_stockpile == null:
		return _build_resource_result(false, "stockpile_unavailable", resource_type, amount, 0)
	return _resource_stockpile.validate_resource_addition(resource_type, amount)

func request_consume_food(colonist_id: String, amount: int = 1) -> Dictionary:
	## Atomically spend abstract stored Food; physical ground Food is deliberately not eligible.
	if colonist_id.is_empty():
		return _build_food_consumption_result(false, "empty_colonist_id", colonist_id, amount, 0)
	if amount <= 0:
		return _build_food_consumption_result(false, "invalid_amount", colonist_id, amount, 0)
	if _resource_stockpile == null:
		return _build_food_consumption_result(false, "stockpile_unavailable", colonist_id, amount, 0)
	var spend_result: Dictionary = _resource_stockpile.request_spend_resources({"food": amount})
	if not bool(spend_result.get("ok", false)):
		return _build_food_consumption_result(false, String(spend_result.get("reason", "spend_failed")), colonist_id, amount, 0)
	return _build_food_consumption_result(true, "consumed", colonist_id, amount, amount)

func get_resource_total(resource_type: String) -> int:
	if _resource_stockpile == null:
		return 0
	return _resource_stockpile.get_total(resource_type)

func get_resource_totals() -> Dictionary:
	if _resource_stockpile == null:
		return {}
	return _resource_stockpile.get_totals()

func get_storage_capacity() -> int:
	return _resource_stockpile.get_storage_capacity() if _resource_stockpile != null else 0

func get_stored_resource_total() -> int:
	return _resource_stockpile.get_stored_total() if _resource_stockpile != null else 0

func get_storage_state() -> Dictionary:
	return _resource_stockpile.get_storage_state() if _resource_stockpile != null else {"stored": 0, "capacity": 0, "reserved": 0, "available": 0, "over_capacity": false}

func export_state() -> Dictionary:
	return {
		"time": _time_state.export_state() if _time_state != null else {},
		"stockpile": _resource_stockpile.export_state() if _resource_stockpile != null else {},
		"construction_sites": export_construction_sites(),
		"harvest_orders": export_harvest_orders(),
		"stockpile_zones": export_stockpile_zones(),
		"ground_items": export_ground_items(),
	}

func import_state(state: Dictionary) -> Dictionary:
	if _time_state != null:
		var time_result: Dictionary = _time_state.import_state(state.get("time", {}))
		if not bool(time_result.get("ok", false)):
			return _build_import_result(false, "time_%s" % String(time_result.get("reason", "failed")))
	if _resource_stockpile != null:
		var stockpile_result: Dictionary = _resource_stockpile.import_state(state.get("stockpile", {}))
		if not bool(stockpile_result.get("ok", false)):
			return _build_import_result(false, "stockpile_%s" % String(stockpile_result.get("reason", "failed")))
	var construction_result: Dictionary = import_construction_sites(state.get("construction_sites", []))
	if not bool(construction_result.get("ok", false)):
		return construction_result
	var harvest_result: Dictionary = import_harvest_orders(state.get("harvest_orders", []))
	if not bool(harvest_result.get("ok", false)):
		return harvest_result
	var stockpile_result: Dictionary = import_stockpile_zones(state.get("stockpile_zones", []))
	if not bool(stockpile_result.get("ok", false)):
		return stockpile_result
	var ground_item_result: Dictionary = import_ground_items(state.get("ground_items", []))
	if not bool(ground_item_result.get("ok", false)):
		return ground_item_result
	return _build_import_result(true, "imported")

func _build_placement_result(ok: bool, reason: String, building_id: String, origin_cell: Vector2i, occupied_cells: Array) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"building_id": building_id,
		"origin_cell": origin_cell,
		"occupied_cells": occupied_cells.duplicate(),
	}

func _build_progress_result(ok: bool, reason: String, site_id: String, amount: float, build_progress: float, completed: bool, resources_consumed: bool) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"site_id": site_id,
		"amount": amount,
		"build_progress": build_progress,
		"completed": completed,
		"resources_consumed": resources_consumed,
	}

func _build_cancellation_result(ok: bool, reason: String, site_id: String, building_id: String, origin_cell: Vector2i, resources_consumed: bool) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"site_id": site_id,
		"building_id": building_id,
		"origin_cell": origin_cell,
		"resources_consumed": resources_consumed,
		"refunded_resources": {},
	}

func _build_reservation_result(ok: bool, reason: String, site_id: String, colonist_id: String, cleanup_reason: String = "") -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"site_id": site_id,
		"colonist_id": colonist_id,
		"cleanup_reason": cleanup_reason,
	}

func _build_cleanup_result(ok: bool, reason: String, colonist_id: String, released_site_ids: Array[String], failed_site_ids: Array[String]) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"colonist_id": colonist_id,
		"released_site_ids": released_site_ids.duplicate(),
		"failed_site_ids": failed_site_ids.duplicate(),
		"released_count": released_site_ids.size(),
	}

func _build_construction_resource_reservation_id(site_id: String) -> String:
	return "construction:%s" % site_id

func _serialize_cell(cell: Vector2i) -> Dictionary:
	return {"x": cell.x, "y": cell.y}

func _deserialize_cell(cell_data: Dictionary) -> Vector2i:
	return Vector2i(int(cell_data.get("x", 0)), int(cell_data.get("y", 0)))

func _on_resource_total_changed(resource_type: String, total: int) -> void:
	resource_total_changed.emit(resource_type, total)

func _on_storage_capacity_changed(capacity: int, stored: int) -> void:
	storage_capacity_changed.emit(capacity, stored)

func _refresh_storage_capacity() -> void:
	if _resource_stockpile == null:
		return
	var capacity: int = ResourceStockpileScript.BASE_STORAGE_CAPACITY
	for site: Variant in _construction_sites.values():
		var site_data: Dictionary = site
		if not bool(site_data.get("completed", false)):
			continue
		var definition: Dictionary = BuildingDefinitionRef.get_definition(String(site_data.get("building_id", "")))
		capacity += maxi(int(definition.get("storage_capacity", 0)), 0)
	_resource_stockpile.set_storage_capacity(capacity)

func _on_time_changed(day: int, hour: int, minute: int) -> void:
	time_changed.emit(day, hour, minute)

func _on_day_started(day: int) -> void:
	day_started.emit(day)

func _on_night_started(day: int) -> void:
	night_started.emit(day)

func _on_day_phase_changed(is_daytime: bool) -> void:
	day_phase_changed.emit(is_daytime)

func _build_resource_result(ok: bool, reason: String, resource_type: String, amount: int, total: int) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"resource_type": resource_type,
		"amount": amount,
		"total": total,
	}

func _build_food_consumption_result(ok: bool, reason: String, colonist_id: String, amount_requested: int, amount_consumed: int) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"colonist_id": colonist_id,
		"amount_requested": amount_requested,
		"amount_consumed": amount_consumed,
		"food_remaining": get_resource_total("food"),
	}

func _build_harvest_order_result(ok: bool, reason: String, order: Dictionary) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"order": order.duplicate(true),
		"order_id": String(order.get("order_id", "")),
		"resource_id": String(order.get("resource_id", "")),
	}

func _build_stockpile_zone_result(ok: bool, reason: String, zone: Dictionary, invalid_cell: Vector2i) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"zone": zone.duplicate(true),
		"zone_id": String(zone.get("zone_id", "")),
		"cell_count": (zone.get("cells", []) as Array).size(),
		"invalid_cell": invalid_cell,
	}

func _build_ground_item_result(ok: bool, reason: String, item: Dictionary) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"item": item.duplicate(true),
		"item_id": String(item.get("item_id", "")),
		"resource_type": String(item.get("resource_type", "")),
		"amount": int(item.get("amount", 0)),
		"cell": item.get("cell", Vector2i.ZERO),
	}

func _build_haul_result(ok: bool, reason: String, item_id: String, colonist_id: String, item: Dictionary, reservation: Dictionary) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"item_id": item_id,
		"colonist_id": colonist_id,
		"item": item.duplicate(true),
		"destination_cell": reservation.get("destination_cell", Vector2i.ZERO),
		"reserved_by_colonist_id": String(reservation.get("reserved_by_colonist_id", "")),
		"picked_up": bool(reservation.get("picked_up", false)),
	}

func _build_import_result(ok: bool, reason: String) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
	}
