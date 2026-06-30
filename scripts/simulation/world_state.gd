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
const CONSTRUCTION_DELIVERY_RADIUS := 12

var _resource_stockpile
var _time_state
var _placement_query: Node
var _construction_sites: Dictionary = {}
var _occupied_construction_cells: Dictionary = {}
var _construction_reservations: Dictionary = {}
var _construction_material_reservations: Dictionary = {}
var _construction_delivery_reservations: Dictionary = {}
var _storage_components: Dictionary = {}
var _storage_component_reservations: Dictionary = {}
var _harvest_orders: Dictionary = {}
var _harvest_order_by_resource: Dictionary = {}
var _stockpile_zones: Dictionary = {}
var _stockpile_zone_by_cell: Dictionary = {}
var _next_stockpile_zone_id: int = 1
var _ground_items: Dictionary = {}
var _ground_item_ids_by_cell: Dictionary = {}
var _next_ground_item_id: int = 1
var _haul_reservations: Dictionary = {}

## Purpose: Minimal simulation-owned root for authoritative runtime state.
## Responsibility: Own resource/time/construction/storage-component/material-delivery/harvest-order/stockpile-zone/ground-item state and coordinate authoritative cross-owner mutations.
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
		"delivered_resources": {},
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
	_release_construction_materials(site_id)
	_release_construction_delivery_reservations_for_site(site_id, "construction_cancelled")
	_restore_delivered_construction_materials(site)
	var legacy_reservation_id: String = _build_construction_resource_reservation_id(site_id)
	if _resource_stockpile.has_resource_reservation(legacy_reservation_id):
		_resource_stockpile.release_resource_reservation(legacy_reservation_id)
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

func get_available_construction_material_deliveries(limit: int = DEFAULT_JOB_CANDIDATE_LIMIT) -> Array[Dictionary]:
	## Return bounded site-item pairs using the ground-item cell index; no world-wide item scan occurs.
	var deliveries: Array[Dictionary] = []
	var candidate_limit: int = clampi(limit, 0, MAX_JOB_CANDIDATE_LIMIT)
	if candidate_limit == 0 or _placement_query == null:
		return deliveries
	var site_ids: Array[String] = []
	for site_id_value: Variant in _construction_sites.keys():
		site_ids.append(String(site_id_value))
	site_ids.sort()
	for site_id: String in site_ids:
		var site: Dictionary = _construction_sites[site_id]
		if bool(site.get("completed", false)) or bool(site.get("resources_consumed", false)) or _construction_reservations.has(site_id):
			continue
		var origin: Vector2i = site.get("origin_cell", Vector2i.ZERO)
		if not _placement_query.is_cell_loaded(origin):
			continue
		var requirements: Dictionary = _get_ground_delivery_requirements(site)
		if requirements.is_empty():
			continue
		for item: Dictionary in _get_nearby_construction_ground_items(origin):
			var item_id: String = String(item.get("item_id", ""))
			var resource_type: String = String(item.get("resource_type", ""))
			var item_amount: int = int(item.get("amount", 0))
			var needed: int = int(requirements.get(resource_type, 0))
			if item_id.is_empty() or item_amount <= 0 or needed <= 0:
				continue
			if _haul_reservations.has(item_id) or _construction_delivery_reservations.has(item_id):
				continue
			var delivery_amount: int = mini(item_amount, needed)
			deliveries.append({
				"job_type": "deliver_construction_material",
				"site_id": site_id,
				"item_id": item_id,
				"resource_type": resource_type,
				"amount": delivery_amount,
				"item_cell": item.get("cell", Vector2i.ZERO),
				"site_cell": origin,
			})
			requirements[resource_type] = needed - delivery_amount
			if deliveries.size() >= candidate_limit:
				return deliveries
	return deliveries

func reserve_construction_material_delivery(site_id: String, item_id: String, colonist_id: String) -> Dictionary:
	if site_id.is_empty() or item_id.is_empty() or colonist_id.is_empty():
		return _build_construction_delivery_result(false, "invalid_reservation_request", site_id, item_id, colonist_id, {}, {})
	if not _construction_sites.has(site_id):
		return _build_construction_delivery_result(false, "unknown_site_id", site_id, item_id, colonist_id, {}, {})
	if not _ground_items.has(item_id):
		return _build_construction_delivery_result(false, "unknown_item_id", site_id, item_id, colonist_id, {}, {})
	if _haul_reservations.has(item_id) or _construction_delivery_reservations.has(item_id):
		return _build_construction_delivery_result(false, "item_reserved", site_id, item_id, colonist_id, _ground_items[item_id], {})
	var site: Dictionary = _construction_sites[site_id]
	if bool(site.get("completed", false)) or bool(site.get("resources_consumed", false)) or _construction_reservations.has(site_id):
		return _build_construction_delivery_result(false, "site_unavailable", site_id, item_id, colonist_id, _ground_items[item_id], {})
	var item: Dictionary = _ground_items[item_id]
	var origin: Vector2i = site.get("origin_cell", Vector2i.ZERO)
	var item_cell: Vector2i = item.get("cell", Vector2i.ZERO)
	if not bool(item.get("enabled", true)) or not _is_cell_within_construction_delivery_radius(origin, item_cell) or _placement_query == null or not _placement_query.is_cell_loaded(item_cell):
		return _build_construction_delivery_result(false, "item_unavailable", site_id, item_id, colonist_id, item, {})
	var resource_type: String = String(item.get("resource_type", ""))
	var amount: int = int(item.get("amount", 0))
	var requirements: Dictionary = _get_ground_delivery_requirements(site)
	var needed: int = int(requirements.get(resource_type, 0))
	if amount <= 0 or needed <= 0:
		return _build_construction_delivery_result(false, "item_not_required", site_id, item_id, colonist_id, item, {})
	var delivery_amount: int = mini(amount, needed)
	var reservation := {
		"site_id": site_id,
		"item_id": item_id,
		"reserved_by_colonist_id": colonist_id,
		"item": item.duplicate(true),
		"pickup_cell": item_cell,
		"destination_cell": origin,
		"delivery_amount": delivery_amount,
		"picked_up": false,
	}
	_construction_delivery_reservations[item_id] = reservation
	return _build_construction_delivery_result(true, "reserved", site_id, item_id, colonist_id, item, reservation)

func get_construction_material_delivery_reservation(item_id: String) -> Dictionary:
	return (_construction_delivery_reservations.get(item_id, {}) as Dictionary).duplicate(true)

func request_pickup_construction_material(item_id: String, colonist_id: String) -> Dictionary:
	if not _construction_delivery_reservations.has(item_id):
		return _build_construction_delivery_result(false, "not_reserved", "", item_id, colonist_id, {}, {})
	var reservation: Dictionary = _construction_delivery_reservations[item_id]
	var site_id: String = String(reservation.get("site_id", ""))
	if String(reservation.get("reserved_by_colonist_id", "")) != colonist_id or bool(reservation.get("picked_up", false)):
		return _build_construction_delivery_result(false, "pickup_not_authorized", site_id, item_id, colonist_id, reservation.get("item", {}), reservation)
	if not _ground_items.has(item_id) or not _haul_item_matches(_ground_items[item_id], reservation.get("item", {})):
		return _build_construction_delivery_result(false, "item_missing_or_changed", site_id, item_id, colonist_id, reservation.get("item", {}), reservation)
	var item: Dictionary = _ground_items[item_id]
	_unindex_ground_item(item)
	_ground_items.erase(item_id)
	ground_item_removed.emit(item_id)
	reservation["picked_up"] = true
	_construction_delivery_reservations[item_id] = reservation
	return _build_construction_delivery_result(true, "picked_up", site_id, item_id, colonist_id, item, reservation)

func request_deliver_construction_material(item_id: String, colonist_id: String, item_data: Dictionary, destination_cell: Vector2i) -> Dictionary:
	if not _construction_delivery_reservations.has(item_id):
		return _build_construction_delivery_result(false, "not_reserved", "", item_id, colonist_id, item_data, {})
	var reservation: Dictionary = _construction_delivery_reservations[item_id]
	var site_id: String = String(reservation.get("site_id", ""))
	if String(reservation.get("reserved_by_colonist_id", "")) != colonist_id or not bool(reservation.get("picked_up", false)) or not _haul_item_matches(item_data, reservation.get("item", {})) or destination_cell != reservation.get("destination_cell", Vector2i.ZERO):
		return _build_construction_delivery_result(false, "delivery_not_authorized", site_id, item_id, colonist_id, item_data, reservation)
	if not _construction_sites.has(site_id):
		return _build_construction_delivery_result(false, "site_missing", site_id, item_id, colonist_id, item_data, reservation)
	var site: Dictionary = _construction_sites[site_id]
	var resource_type: String = String(item_data.get("resource_type", ""))
	var item_amount: int = int(item_data.get("amount", 0))
	var delivery_amount: int = int(reservation.get("delivery_amount", item_amount))
	var outstanding: Dictionary = _get_undelivered_construction_cost(site)
	if bool(site.get("completed", false)) or bool(site.get("resources_consumed", false)) or delivery_amount <= 0 or delivery_amount > item_amount or delivery_amount > int(outstanding.get(resource_type, 0)):
		return _build_construction_delivery_result(false, "material_no_longer_required", site_id, item_id, colonist_id, item_data, reservation)
	var surplus_amount: int = item_amount - delivery_amount
	var prepared_surplus: Dictionary = {}
	var surplus_cell: Vector2i = destination_cell
	if surplus_amount > 0:
		surplus_cell = _find_construction_surplus_cell(site, reservation.get("pickup_cell", destination_cell))
		prepared_surplus = _prepare_ground_item(resource_type, surplus_amount, surplus_cell)
		if not bool(prepared_surplus.get("ok", false)):
			return _build_construction_delivery_result(false, "surplus_restore_failed", site_id, item_id, colonist_id, item_data, reservation)
	var delivered: Dictionary = site.get("delivered_resources", {}).duplicate(true)
	delivered[resource_type] = int(delivered.get(resource_type, 0)) + delivery_amount
	site["delivered_resources"] = delivered
	if _get_undelivered_construction_cost(site).is_empty():
		## Final delivery is the single authority transition from staged materials to a funded site.
		site["resources_consumed"] = true
		site["consumed_resources"] = site.get("required_resources", {}).duplicate(true)
	_construction_sites[site_id] = site
	_construction_delivery_reservations.erase(item_id)
	if surplus_amount > 0:
		_commit_ground_item(prepared_surplus.get("item", {}), int(prepared_surplus.get("next_id", _next_ground_item_id + 1)))
	construction_site_changed.emit(site.duplicate(true))
	var result: Dictionary = _build_construction_delivery_result(true, "delivered", site_id, item_id, colonist_id, item_data, reservation)
	result["surplus_amount"] = surplus_amount
	result["surplus_cell"] = surplus_cell
	return result

func release_construction_material_delivery(item_id: String, colonist_id: String = "", reason: String = "released", drop_cell: Variant = null) -> Dictionary:
	if not _construction_delivery_reservations.has(item_id):
		return _build_construction_delivery_result(false, "not_reserved", "", item_id, colonist_id, {}, {})
	var reservation: Dictionary = _construction_delivery_reservations[item_id]
	var reserved_by: String = String(reservation.get("reserved_by_colonist_id", ""))
	var site_id: String = String(reservation.get("site_id", ""))
	if not colonist_id.is_empty() and reserved_by != colonist_id:
		return _build_construction_delivery_result(false, "reserved_by_other_colonist", site_id, item_id, reserved_by, reservation.get("item", {}), reservation)
	if bool(reservation.get("picked_up", false)):
		var restore_cell: Vector2i = reservation.get("pickup_cell", Vector2i.ZERO)
		if drop_cell is Vector2i:
			restore_cell = drop_cell
		_restore_reserved_ground_item(reservation, restore_cell, "construction material")
	_construction_delivery_reservations.erase(item_id)
	var result: Dictionary = _build_construction_delivery_result(true, "released", site_id, item_id, reserved_by, reservation.get("item", {}), reservation)
	result["release_reason"] = reason
	return result

func release_all_construction_material_deliveries_for_colonist(colonist_id: String, reason: String = "colonist_cleanup") -> void:
	if colonist_id.is_empty():
		return
	for item_id_value: Variant in _construction_delivery_reservations.keys():
		var item_id: String = String(item_id_value)
		if String((_construction_delivery_reservations[item_id] as Dictionary).get("reserved_by_colonist_id", "")) == colonist_id:
			release_construction_material_delivery(item_id, colonist_id, reason)

func cleanup_stale_construction_material_deliveries(active_colonist_ids: Array) -> void:
	var active: Dictionary = {}
	for colonist_id_value: Variant in active_colonist_ids:
		active[String(colonist_id_value)] = true
	for item_id_value: Variant in _construction_delivery_reservations.keys():
		var item_id: String = String(item_id_value)
		if not active.has(String((_construction_delivery_reservations[item_id] as Dictionary).get("reserved_by_colonist_id", ""))):
			release_construction_material_delivery(item_id, "", "stale_owner_cleanup")

func _get_undelivered_construction_cost(site: Dictionary) -> Dictionary:
	var remaining: Dictionary = {}
	var delivered: Dictionary = site.get("delivered_resources", {})
	for resource_type_value: Variant in site.get("required_resources", {}).keys():
		var resource_type: String = String(resource_type_value)
		var amount: int = maxi(int(site.get("required_resources", {}).get(resource_type_value, 0)) - int(delivered.get(resource_type, 0)), 0)
		if amount > 0:
			remaining[resource_type] = amount
	return remaining

func _get_ground_delivery_requirements(site: Dictionary) -> Dictionary:
	var requirements: Dictionary = _get_undelivered_construction_cost(site)
	if not _storage_components.is_empty():
		for resource_type_value: Variant in requirements.keys():
			var resource_type: String = String(resource_type_value)
			requirements[resource_type] = maxi(int(requirements[resource_type]) - get_available_storage_resource_total(resource_type), 0)
	for reservation_value: Variant in _construction_delivery_reservations.values():
		var reservation: Dictionary = reservation_value
		if String(reservation.get("site_id", "")) != String(site.get("site_id", "")):
			continue
		var item: Dictionary = reservation.get("item", {})
		var resource_type: String = String(item.get("resource_type", ""))
		var delivery_amount: int = int(reservation.get("delivery_amount", item.get("amount", 0)))
		requirements[resource_type] = maxi(int(requirements.get(resource_type, 0)) - delivery_amount, 0)
	var empty_keys: Array[String] = []
	for resource_type_value: Variant in requirements.keys():
		if int(requirements[resource_type_value]) <= 0:
			empty_keys.append(String(resource_type_value))
	for resource_type: String in empty_keys:
		requirements.erase(resource_type)
	return requirements

func _get_nearby_construction_ground_items(origin: Vector2i) -> Array[Dictionary]:
	var radius := CONSTRUCTION_DELIVERY_RADIUS
	var items: Array[Dictionary] = get_ground_items_in_cell_rect(Rect2i(origin - Vector2i(radius, radius), Vector2i(radius * 2 + 1, radius * 2 + 1)))
	items.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_cell: Vector2i = first.get("cell", Vector2i.ZERO)
		var second_cell: Vector2i = second.get("cell", Vector2i.ZERO)
		var first_distance: int = (first_cell - origin).length_squared()
		var second_distance: int = (second_cell - origin).length_squared()
		return first_distance < second_distance if first_distance != second_distance else String(first.get("item_id", "")) < String(second.get("item_id", ""))
	)
	return items

func _is_cell_within_construction_delivery_radius(origin: Vector2i, cell: Vector2i) -> bool:
	var offset: Vector2i = cell - origin
	return absi(offset.x) <= CONSTRUCTION_DELIVERY_RADIUS and absi(offset.y) <= CONSTRUCTION_DELIVERY_RADIUS

func _find_construction_surplus_cell(site: Dictionary, fallback_cell: Vector2i) -> Vector2i:
	## Keep loose surplus outside every occupied construction footprint while remaining near the delivery site.
	var origin: Vector2i = site.get("origin_cell", Vector2i.ZERO)
	for radius in range(1, CONSTRUCTION_DELIVERY_RADIUS + 1):
		for y in range(origin.y - radius, origin.y + radius + 1):
			for x in range(origin.x - radius, origin.x + radius + 1):
				if x != origin.x - radius and x != origin.x + radius and y != origin.y - radius and y != origin.y + radius:
					continue
				var candidate := Vector2i(x, y)
				if _is_valid_construction_surplus_cell(candidate):
					return candidate
	if _is_valid_construction_surplus_cell(fallback_cell):
		return fallback_cell
	return origin

func _is_valid_construction_surplus_cell(cell: Vector2i) -> bool:
	if _placement_query == null or not _placement_query.is_cell_loaded(cell) or _occupied_construction_cells.has(cell):
		return false
	var tile_info: Dictionary = _placement_query.get_effective_tile_info(cell)
	var terrain_name: String = String(tile_info.get("terrain", ""))
	return bool(tile_info.get("walkable", false)) and terrain_name != "WATER" and terrain_name != "ROCK_WALL" and not bool(tile_info.get("mineable", false)) and not _placement_query.is_cell_blocked_by_resource(cell)

func _has_construction_delivery_reservations_for_site(site_id: String) -> bool:
	for reservation_value: Variant in _construction_delivery_reservations.values():
		if String((reservation_value as Dictionary).get("site_id", "")) == site_id:
			return true
	return false

func _release_construction_delivery_reservations_for_site(site_id: String, reason: String) -> void:
	for item_id_value: Variant in _construction_delivery_reservations.keys():
		var item_id: String = String(item_id_value)
		if String((_construction_delivery_reservations[item_id] as Dictionary).get("site_id", "")) == site_id:
			release_construction_material_delivery(item_id, "", reason)

func _restore_delivered_construction_materials(site: Dictionary) -> void:
	if bool(site.get("resources_consumed", false)):
		return
	var origin: Vector2i = site.get("origin_cell", Vector2i.ZERO)
	for resource_type_value: Variant in site.get("delivered_resources", {}).keys():
		var resource_type: String = String(resource_type_value)
		var amount: int = int(site.get("delivered_resources", {}).get(resource_type_value, 0))
		if amount <= 0:
			continue
		var restore_result: Dictionary = create_ground_item(resource_type, amount, origin)
		if not bool(restore_result.get("ok", false)):
			push_error("Failed to restore cancelled construction material: %s" % String(restore_result.get("reason", "unknown")))

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
		var remaining_cost: Dictionary = _get_undelivered_construction_cost(site)
		var resource_result: Dictionary
		if remaining_cost.is_empty():
			resource_result = _build_construction_material_result(true, "delivered", site_id, [])
		elif _storage_components.is_empty():
			## Bootstrap compatibility ends as soon as any completed storage component exists.
			resource_result = _resource_stockpile.reserve_resources(_build_construction_resource_reservation_id(site_id), remaining_cost)
		else:
			resource_result = _reserve_construction_materials(site_id, remaining_cost)
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
	_release_construction_materials(site_id)
	var legacy_reservation_id: String = _build_construction_resource_reservation_id(site_id)
	if _resource_stockpile.has_resource_reservation(legacy_reservation_id):
		var legacy_release: Dictionary = _resource_stockpile.release_resource_reservation(legacy_reservation_id)
		if not bool(legacy_release.get("ok", false)):
			return _build_reservation_result(false, String(legacy_release.get("reason", "resource_release_failed")), site_id, reserved_by, cleanup_reason)
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
			"resource_reserved": _construction_material_reservations.has(id_text) or _resource_stockpile.has_resource_reservation(_build_construction_resource_reservation_id(id_text)),
			"resources_consumed": bool(site.get("resources_consumed", false)),
			"completed": bool(site.get("completed", false)),
		})
	return {"count": entries.size(), "reservations": entries}

func get_construction_material_reservation_summary(site_id: String = "") -> Dictionary:
	var allocations: Array[Dictionary] = []
	var site_ids: Array[String] = []
	for reserved_site_id_value: Variant in _construction_material_reservations.keys():
		var reserved_site_id: String = String(reserved_site_id_value)
		if site_id.is_empty() or reserved_site_id == site_id:
			site_ids.append(reserved_site_id)
	site_ids.sort()
	for reserved_site_id: String in site_ids:
		for allocation_value: Variant in _construction_material_reservations[reserved_site_id]:
			allocations.append((allocation_value as Dictionary).duplicate(true))
	return {
		"site_id": site_id,
		"site_count": site_ids.size(),
		"count": allocations.size(),
		"allocations": allocations,
	}

func get_available_storage_resource_total(resource_type: String) -> int:
	var available: int = 0
	for storage_id_value: Variant in _storage_components.keys():
		available += _get_storage_component_available_resource_amount(String(storage_id_value), resource_type)
	return available

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
		if _has_construction_delivery_reservations_for_site(site_id):
			return _build_progress_result(false, "material_delivery_pending", site_id, amount, float(site.get("build_progress", 0.0)), false, false)
		var remaining_cost: Dictionary = _get_undelivered_construction_cost(site)
		var spend_result: Dictionary
		if remaining_cost.is_empty():
			spend_result = _build_construction_material_result(true, "delivered", site_id, [])
		elif _construction_material_reservations.has(site_id):
			spend_result = _consume_construction_materials(site_id)
		elif _resource_stockpile.has_resource_reservation(_build_construction_resource_reservation_id(site_id)):
			spend_result = _resource_stockpile.consume_reserved_resources(_build_construction_resource_reservation_id(site_id))
		elif not colonist_id.is_empty():
			return _build_progress_result(false, "missing_resource_reservation", site_id, amount, float(site.get("build_progress", 0.0)), false, false)
		else:
			## Unowned debug progress follows the same first-Storehouse bootstrap boundary as worker construction.
			if _storage_components.is_empty():
				spend_result = _resource_stockpile.request_spend_resources(remaining_cost)
			else:
				var direct_reservation: Dictionary = _reserve_construction_materials(site_id, remaining_cost)
				if bool(direct_reservation.get("ok", false)):
					spend_result = _consume_construction_materials(site_id)
					if not bool(spend_result.get("ok", false)):
						_release_construction_materials(site_id)
				else:
					spend_result = direct_reservation
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
	var site_id: String = String(site.get("site_id", ""))
	if _has_construction_delivery_reservations_for_site(site_id):
		return false
	var remaining_cost: Dictionary = _get_undelivered_construction_cost(site)
	if remaining_cost.is_empty():
		return true
	if _storage_components.is_empty():
		return _resource_stockpile.can_reserve_resources(remaining_cost)
	return _can_reserve_construction_materials(remaining_cost)

func get_construction_sites() -> Array[Dictionary]:
	var sites: Array[Dictionary] = []
	for site: Variant in _construction_sites.values():
		sites.append((site as Dictionary).duplicate(true))
	return sites

func get_storage_components() -> Array[Dictionary]:
	## Return defensive snapshots of building-owned storage contents and capacity state.
	var components: Array[Dictionary] = []
	var storage_ids: Array[String] = []
	for storage_id_value: Variant in _storage_components.keys():
		storage_ids.append(String(storage_id_value))
	storage_ids.sort()
	for storage_id: String in storage_ids:
		components.append(_copy_storage_component(_storage_components[storage_id]))
	return components

func get_storage_component(storage_id: String) -> Dictionary:
	if not _storage_components.has(storage_id):
		return {}
	return _copy_storage_component(_storage_components[storage_id])

func get_storage_components_for_building(building_id: String) -> Array[Dictionary]:
	var components: Array[Dictionary] = []
	for component: Dictionary in get_storage_components():
		if String(component.get("building_id", "")) == building_id:
			components.append(component)
	return components

func get_total_storage_component_capacity() -> int:
	var capacity: int = 0
	for component: Variant in _storage_components.values():
		capacity += int((component as Dictionary).get("capacity", 0))
	return capacity

func get_storage_component_reservation_summary(storage_id: String = "") -> Dictionary:
	var reservations: Dictionary = {}
	var reserved: int = 0
	for reservation_id_value: Variant in _storage_component_reservations.keys():
		var reservation_id: String = String(reservation_id_value)
		var reservation: Dictionary = _storage_component_reservations[reservation_id]
		if not storage_id.is_empty() and String(reservation.get("storage_id", "")) != storage_id:
			continue
		reservations[reservation_id] = reservation.duplicate(true)
		reserved += int(reservation.get("amount", 0))
	return {
		"storage_id": storage_id,
		"count": reservations.size(),
		"reserved": reserved,
		"reservations": reservations,
	}

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
	if _haul_reservations.has(item_id) or _construction_delivery_reservations.has(item_id):
		return _build_ground_item_result(false, "item_reserved", _ground_items[item_id])
	var item: Dictionary = _ground_items[item_id]
	_unindex_ground_item(item)
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
	for y in range(cell_rect.position.y, cell_rect.end.y):
		for x in range(cell_rect.position.x, cell_rect.end.x):
			var cell := Vector2i(x, y)
			for item_id_value: Variant in (_ground_item_ids_by_cell.get(cell, {}) as Dictionary).keys():
				var item_id: String = String(item_id_value)
				if not _ground_items.has(item_id):
					continue
				var item: Dictionary = _ground_items[item_id]
				if bool(item.get("enabled", true)):
					items.append(item.duplicate(true))
	items.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return String(first.get("item_id", "")) < String(second.get("item_id", ""))
	)
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
	for reservation_value: Variant in _construction_delivery_reservations.values():
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
	_rebuild_ground_item_cell_index()
	_next_ground_item_id = next_item_number
	_haul_reservations.clear()
	_construction_delivery_reservations.clear()
	_storage_component_reservations.clear()
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
	_index_ground_item(item)
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
		if not bool(item.get("enabled", true)) or _haul_reservations.has(item_id) or _construction_delivery_reservations.has(item_id):
			continue
		if not _placement_query.is_cell_loaded(item_cell) or _is_ground_item_already_stored(item_cell):
			continue
		if amount <= 0:
			continue
		var destination: Dictionary = _find_haul_destination(item_cell, amount)
		if not bool(destination.get("ok", false)):
			continue
		var candidate: Dictionary = item.duplicate(true)
		candidate["destination_cell"] = destination.get("cell", Vector2i.ZERO)
		candidate["destination_kind"] = String(destination.get("kind", ""))
		candidate["storage_id"] = String(destination.get("storage_id", ""))
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
	if _construction_delivery_reservations.has(item_id):
		return _build_haul_result(false, "item_reserved_for_construction", item_id, colonist_id, _ground_items[item_id] if _ground_items.has(item_id) else {}, {})
	var item: Dictionary = _ground_items[item_id]
	var item_cell: Vector2i = item.get("cell", Vector2i.ZERO)
	if not bool(item.get("enabled", true)) or _placement_query == null or not _placement_query.is_cell_loaded(item_cell):
		return _build_haul_result(false, "item_unavailable", item_id, colonist_id, item, {})
	if _is_ground_item_already_stored(item_cell):
		return _build_haul_result(false, "item_already_stockpiled", item_id, colonist_id, item, {})
	var destination: Dictionary = _find_haul_destination(item_cell, int(item.get("amount", 0)))
	if not bool(destination.get("ok", false)):
		return _build_haul_result(false, String(destination.get("reason", "no_destination")), item_id, colonist_id, item, {})
	var storage_reservation_id: String = _build_haul_storage_reservation_id(item_id)
	var destination_kind: String = String(destination.get("kind", ""))
	var storage_id: String = String(destination.get("storage_id", ""))
	var storage_result: Dictionary
	if destination_kind == "storage_component":
		storage_result = _reserve_storage_component_capacity(storage_reservation_id, storage_id, int(item.get("amount", 0)))
	else:
		storage_result = _resource_stockpile.reserve_storage(storage_reservation_id, int(item.get("amount", 0)))
	if not bool(storage_result.get("ok", false)):
		return _build_haul_result(false, String(storage_result.get("reason", "storage_reservation_failed")), item_id, colonist_id, item, {})
	var reservation := {
		"item_id": item_id,
		"reserved_by_colonist_id": colonist_id,
		"destination_cell": destination.get("cell", Vector2i.ZERO),
		"destination_kind": destination_kind,
		"storage_id": storage_id,
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
	_unindex_ground_item(item)
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
	if destination_cell != reservation.get("destination_cell", Vector2i.ZERO) or not _is_valid_reserved_haul_destination(reservation, destination_cell):
		return _build_haul_result(false, "destination_invalid", item_id, colonist_id, item_data, reservation)
	var amount: int = int(item_data.get("amount", 0))
	var storage_reservation_id: String = String(reservation.get("storage_reservation_id", ""))
	var destination_kind: String = String(reservation.get("destination_kind", ""))
	var capacity_result: Dictionary
	if destination_kind == "storage_component":
		capacity_result = _validate_storage_component_reservation(storage_reservation_id, String(reservation.get("storage_id", "")), amount)
	else:
		capacity_result = _resource_stockpile.validate_storage_reservation(storage_reservation_id, amount)
	if not bool(capacity_result.get("ok", false)):
		return _build_haul_result(false, String(capacity_result.get("reason", "storage_reservation_invalid")), item_id, colonist_id, item_data, reservation)
	var consume_result: Dictionary
	if destination_kind == "storage_component":
		consume_result = _consume_storage_component_reservation(storage_reservation_id, String(reservation.get("storage_id", "")), String(item_data.get("resource_type", "")), amount)
	else:
		consume_result = _resource_stockpile.consume_storage_reservation(storage_reservation_id, amount)
	if not bool(consume_result.get("ok", false)):
		return _build_haul_result(false, String(consume_result.get("reason", "storage_reservation_consume_failed")), item_id, colonist_id, item_data, reservation)
	if destination_kind != "storage_component":
		var addition_result: Dictionary = _resource_stockpile.request_add_resource(String(item_data.get("resource_type", "")), amount)
		if not bool(addition_result.get("ok", false)):
			push_error("Haul deposit invariant failed after consuming reserved capacity: %s" % String(addition_result.get("reason", "addition_failed")))
			return _build_haul_result(false, "stockpile_commit_invariant_failed", item_id, colonist_id, item_data, reservation)
	_haul_reservations.erase(item_id)
	var result: Dictionary = _build_haul_result(true, "deposited", item_id, colonist_id, item_data, reservation)
	result["resource_total"] = get_resource_total(String(item_data.get("resource_type", "")))
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

func _find_haul_destination(from_cell: Vector2i, amount: int = 0) -> Dictionary:
	var storage_destination: Dictionary = _find_storage_component_haul_destination(from_cell, amount)
	## Completed storage components end legacy-zone destination selection, even when full or temporarily unreachable.
	if not _storage_components.is_empty():
		return storage_destination
	return _find_legacy_stockpile_haul_destination(from_cell, amount)

func _find_storage_component_haul_destination(from_cell: Vector2i, amount: int) -> Dictionary:
	var found: bool = false
	var best_cell: Vector2i = Vector2i.ZERO
	var best_storage_id: String = ""
	var best_distance: int = 0
	var storage_ids: Array[String] = []

	for storage_id_value: Variant in _storage_components.keys():
		storage_ids.append(String(storage_id_value))
	storage_ids.sort()

	for storage_id: String in storage_ids:
		var component: Dictionary = _storage_components[storage_id]
		var open_capacity: int = _get_storage_component_available_capacity(storage_id)
		if open_capacity <= 0 or (amount > 0 and open_capacity < amount):
			continue

		for cell: Vector2i in _get_storage_component_destination_cells(component):
			if not _is_valid_storage_component_destination(cell):
				continue

			var distance: int = (cell - from_cell).length_squared()
			var is_better_tie: bool = (
				cell.y < best_cell.y
				or (
					cell.y == best_cell.y
					and (
						cell.x < best_cell.x
						or (
							cell.x == best_cell.x
							and storage_id < best_storage_id
						)
					)
				)
			)

			if not found or distance < best_distance or (distance == best_distance and is_better_tie):
				found = true
				best_cell = cell
				best_storage_id = storage_id
				best_distance = distance

	return {
		"ok": found,
		"reason": "found" if found else "no_valid_storehouse_destination",
		"kind": "storage_component",
		"cell": best_cell,
		"storage_id": best_storage_id,
	}
func _find_legacy_stockpile_haul_destination(from_cell: Vector2i, amount: int) -> Dictionary:
	var found: bool = false
	var best_cell: Vector2i = Vector2i.ZERO
	var best_distance: int = 0
	if _resource_stockpile == null:
		return {"ok": false, "reason": "stockpile_unavailable", "kind": "legacy_stockpile_zone", "cell": best_cell, "storage_id": ""}
	if amount > 0 and not _resource_stockpile.can_reserve_storage(amount):
		return {"ok": false, "reason": "insufficient_legacy_stockpile_capacity", "kind": "legacy_stockpile_zone", "cell": best_cell, "storage_id": ""}
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
	return {
		"ok": found,
		"reason": "found" if found else "no_valid_stockpile_destination",
		"kind": "legacy_stockpile_zone",
		"cell": best_cell,
		"storage_id": "",
	}

func _is_valid_reserved_haul_destination(reservation: Dictionary, cell: Vector2i) -> bool:
	if String(reservation.get("destination_kind", "")) == "storage_component":
		var storage_id: String = String(reservation.get("storage_id", ""))
		return _storage_components.has(storage_id) and _get_storage_component_destination_cells(_storage_components[storage_id]).has(cell) and _is_valid_storage_component_destination(cell)
	return _is_valid_haul_destination(cell)

func _is_valid_haul_destination(cell: Vector2i) -> bool:
	if _placement_query == null or not _placement_query.is_cell_loaded(cell) or not _is_cell_in_enabled_stockpile_zone(cell):
		return false
	var tile_info: Dictionary = _placement_query.get_effective_tile_info(cell)
	var terrain_name: String = String(tile_info.get("terrain", ""))
	return bool(tile_info.get("walkable", false)) and terrain_name != "WATER" and terrain_name != "ROCK_WALL" and not bool(tile_info.get("mineable", false)) and not _occupied_construction_cells.has(cell)

func _get_storage_component_destination_cells(component: Dictionary) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var seen: Dictionary = {}
	for occupied_cell: Vector2i in component.get("occupied_cells", []):
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var cell: Vector2i = occupied_cell + offset
			if seen.has(cell) or (component.get("occupied_cells", []) as Array).has(cell):
				continue
			seen[cell] = true
			candidates.append(cell)
	candidates.sort_custom(func(first: Vector2i, second: Vector2i) -> bool:
		return first.y < second.y if first.y != second.y else first.x < second.x
	)
	return candidates

func _is_valid_storage_component_destination(cell: Vector2i) -> bool:
	if _placement_query == null or not _placement_query.is_cell_loaded(cell):
		return false
	var tile_info: Dictionary = _placement_query.get_effective_tile_info(cell)
	var terrain_name: String = String(tile_info.get("terrain", ""))
	return bool(tile_info.get("walkable", false)) and terrain_name != "WATER" and terrain_name != "ROCK_WALL" and not bool(tile_info.get("mineable", false)) and not _occupied_construction_cells.has(cell)

func _is_cell_in_enabled_stockpile_zone(cell: Vector2i) -> bool:
	var zone_id: String = String(_stockpile_zone_by_cell.get(cell, ""))
	return not zone_id.is_empty() and bool((_stockpile_zones.get(zone_id, {}) as Dictionary).get("enabled", true))

func _is_ground_item_already_stored(cell: Vector2i) -> bool:
	## Legacy zones suppress hauling only until completed Storehouse storage becomes the active authority.
	return _storage_components.is_empty() and _is_cell_in_enabled_stockpile_zone(cell)

func _can_reserve_construction_materials(cost: Dictionary) -> bool:
	return bool(_plan_construction_material_allocations("", cost).get("ok", false))

func _reserve_construction_materials(site_id: String, cost: Dictionary) -> Dictionary:
	if site_id.is_empty():
		return _build_construction_material_result(false, "empty_site_id", site_id, [])
	if _construction_material_reservations.has(site_id):
		return _build_construction_material_result(false, "duplicate_reservation", site_id, _construction_material_reservations[site_id])
	var plan: Dictionary = _plan_construction_material_allocations(site_id, cost)
	if not bool(plan.get("ok", false)):
		return plan
	var allocations: Array = plan.get("allocations", [])
	_construction_material_reservations[site_id] = allocations.duplicate(true)
	return _build_construction_material_result(true, "reserved", site_id, allocations)

func _plan_construction_material_allocations(site_id: String, cost: Dictionary) -> Dictionary:
	var allocations: Array[Dictionary] = []
	var resource_types: Array[String] = []
	for resource_type_value: Variant in cost.keys():
		resource_types.append(String(resource_type_value))
	resource_types.sort()
	var storage_ids: Array[String] = []
	for storage_id_value: Variant in _storage_components.keys():
		storage_ids.append(String(storage_id_value))
	storage_ids.sort()
	for resource_type: String in resource_types:
		var required: int = int(cost.get(resource_type, 0))
		if resource_type.is_empty() or required < 0:
			return _build_construction_material_result(false, "invalid_cost", site_id, [])
		var remaining: int = required
		for storage_id: String in storage_ids:
			if remaining <= 0:
				break
			var available: int = _get_storage_component_available_resource_amount(storage_id, resource_type)
			var amount: int = mini(available, remaining)
			if amount <= 0:
				continue
			allocations.append({
				"construction_site_id": site_id,
				"storage_id": storage_id,
				"resource_type": resource_type,
				"amount": amount,
			})
			remaining -= amount
		if remaining > 0:
			return _build_construction_material_result(false, "insufficient_storage_resources", site_id, [])
	return _build_construction_material_result(true, "available", site_id, allocations)

func _consume_construction_materials(site_id: String) -> Dictionary:
	if not _construction_material_reservations.has(site_id):
		return _build_construction_material_result(false, "missing_reservation", site_id, [])
	var allocations: Array = _construction_material_reservations[site_id]
	var updated_contents: Dictionary = {}
	for allocation_value: Variant in allocations:
		var allocation: Dictionary = allocation_value
		var storage_id: String = String(allocation.get("storage_id", ""))
		var resource_type: String = String(allocation.get("resource_type", ""))
		var amount: int = int(allocation.get("amount", 0))
		if not _storage_components.has(storage_id) or resource_type.is_empty() or amount <= 0:
			return _build_construction_material_result(false, "invalid_reservation", site_id, allocations)
		var contents: Dictionary = updated_contents.get(storage_id, (_storage_components[storage_id] as Dictionary).get("contents", {}).duplicate(true))
		if int(contents.get(resource_type, 0)) < amount:
			return _build_construction_material_result(false, "reserved_material_unavailable", site_id, allocations)
		contents[resource_type] = int(contents.get(resource_type, 0)) - amount
		updated_contents[storage_id] = contents
	for storage_id_value: Variant in updated_contents.keys():
		var storage_id: String = String(storage_id_value)
		var component: Dictionary = _storage_components[storage_id]
		component["contents"] = (updated_contents[storage_id] as Dictionary).duplicate(true)
		_storage_components[storage_id] = component
	_construction_material_reservations.erase(site_id)
	var changed_resources: Dictionary = {}
	for allocation_value: Variant in allocations:
		changed_resources[String((allocation_value as Dictionary).get("resource_type", ""))] = true
	for resource_type_value: Variant in changed_resources.keys():
		var resource_type: String = String(resource_type_value)
		resource_total_changed.emit(resource_type, get_resource_total(resource_type))
	storage_capacity_changed.emit(get_storage_capacity(), get_stored_resource_total())
	return _build_construction_material_result(true, "consumed", site_id, allocations)

func _release_construction_materials(site_id: String) -> Dictionary:
	if not _construction_material_reservations.has(site_id):
		return _build_construction_material_result(false, "not_reserved", site_id, [])
	var allocations: Array = _construction_material_reservations[site_id]
	_construction_material_reservations.erase(site_id)
	return _build_construction_material_result(true, "released", site_id, allocations)

func _get_storage_component_available_resource_amount(storage_id: String, resource_type: String) -> int:
	if not _storage_components.has(storage_id) or resource_type.is_empty():
		return 0
	var available: int = int((_storage_components[storage_id] as Dictionary).get("contents", {}).get(resource_type, 0))
	for allocations_value: Variant in _construction_material_reservations.values():
		for allocation_value: Variant in allocations_value:
			var allocation: Dictionary = allocation_value
			if String(allocation.get("storage_id", "")) == storage_id and String(allocation.get("resource_type", "")) == resource_type:
				available -= int(allocation.get("amount", 0))
	return maxi(available, 0)

func _consume_storage_resource(resource_type: String, amount: int) -> Dictionary:
	if resource_type.is_empty() or amount <= 0:
		return {"ok": false, "reason": "invalid_resource_request", "resource_type": resource_type, "amount": amount}
	var storage_ids: Array[String] = []
	for storage_id_value: Variant in _storage_components.keys():
		storage_ids.append(String(storage_id_value))
	storage_ids.sort()
	var deductions: Array[Dictionary] = []
	var remaining: int = amount
	for storage_id: String in storage_ids:
		if remaining <= 0:
			break
		var available: int = _get_storage_component_available_resource_amount(storage_id, resource_type)
		var consumed: int = mini(available, remaining)
		if consumed <= 0:
			continue
		deductions.append({"storage_id": storage_id, "amount": consumed})
		remaining -= consumed
	if remaining > 0:
		return {"ok": false, "reason": "insufficient_storage_resources", "resource_type": resource_type, "amount": amount}
	for deduction: Dictionary in deductions:
		var storage_id: String = String(deduction.get("storage_id", ""))
		var component: Dictionary = _storage_components[storage_id]
		var contents: Dictionary = component.get("contents", {}).duplicate(true)
		contents[resource_type] = int(contents.get(resource_type, 0)) - int(deduction.get("amount", 0))
		component["contents"] = contents
		_storage_components[storage_id] = component
	resource_total_changed.emit(resource_type, get_resource_total(resource_type))
	storage_capacity_changed.emit(get_storage_capacity(), get_stored_resource_total())
	return {"ok": true, "reason": "consumed", "resource_type": resource_type, "amount": amount}

func _build_construction_material_result(ok: bool, reason: String, site_id: String, allocations: Array) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"construction_site_id": site_id,
		"allocations": allocations.duplicate(true),
	}

func _reserve_storage_component_capacity(reservation_id: String, storage_id: String, amount: int) -> Dictionary:
	if reservation_id.is_empty():
		return _build_storage_component_reservation_result(false, "empty_reservation_id", reservation_id, storage_id, amount)
	if not _storage_components.has(storage_id):
		return _build_storage_component_reservation_result(false, "unknown_storage_id", reservation_id, storage_id, amount)
	if amount <= 0:
		return _build_storage_component_reservation_result(false, "invalid_amount", reservation_id, storage_id, amount)
	if _storage_component_reservations.has(reservation_id):
		return _build_storage_component_reservation_result(false, "duplicate_reservation_id", reservation_id, storage_id, amount)
	if _get_storage_component_available_capacity(storage_id) < amount:
		return _build_storage_component_reservation_result(false, "insufficient_storage_capacity", reservation_id, storage_id, amount)
	_storage_component_reservations[reservation_id] = {
		"reservation_id": reservation_id,
		"storage_id": storage_id,
		"amount": amount,
	}
	return _build_storage_component_reservation_result(true, "reserved", reservation_id, storage_id, amount)

func _validate_storage_component_reservation(reservation_id: String, storage_id: String, amount: int) -> Dictionary:
	if not _storage_component_reservations.has(reservation_id):
		return _build_storage_component_reservation_result(false, "unknown_reservation_id", reservation_id, storage_id, amount)
	var reservation: Dictionary = _storage_component_reservations[reservation_id]
	if String(reservation.get("storage_id", "")) != storage_id:
		return _build_storage_component_reservation_result(false, "storage_id_mismatch", reservation_id, storage_id, amount)
	if int(reservation.get("amount", 0)) != amount or amount <= 0:
		return _build_storage_component_reservation_result(false, "reserved_amount_mismatch", reservation_id, storage_id, amount)
	if not _storage_components.has(storage_id):
		return _build_storage_component_reservation_result(false, "unknown_storage_id", reservation_id, storage_id, amount)
	return _build_storage_component_reservation_result(true, "valid", reservation_id, storage_id, amount)

func _consume_storage_component_reservation(reservation_id: String, storage_id: String, resource_type: String, amount: int) -> Dictionary:
	var validation: Dictionary = _validate_storage_component_reservation(reservation_id, storage_id, amount)
	if not bool(validation.get("ok", false)):
		return validation
	if resource_type.is_empty():
		return _build_storage_component_reservation_result(false, "empty_resource_type", reservation_id, storage_id, amount)
	var component: Dictionary = _storage_components[storage_id]
	var contents: Dictionary = component.get("contents", {}).duplicate(true)
	contents[resource_type] = int(contents.get(resource_type, 0)) + amount
	component["contents"] = contents
	_storage_components[storage_id] = component
	_storage_component_reservations.erase(reservation_id)
	resource_total_changed.emit(resource_type, get_resource_total(resource_type))
	storage_capacity_changed.emit(get_storage_capacity(), get_stored_resource_total())
	return _build_storage_component_reservation_result(true, "consumed", reservation_id, storage_id, amount)

func _release_storage_component_reservation(reservation_id: String) -> Dictionary:
	if not _storage_component_reservations.has(reservation_id):
		return _build_storage_component_reservation_result(false, "unknown_reservation_id", reservation_id, "", 0)
	var reservation: Dictionary = _storage_component_reservations[reservation_id]
	_storage_component_reservations.erase(reservation_id)
	return _build_storage_component_reservation_result(true, "released", reservation_id, String(reservation.get("storage_id", "")), int(reservation.get("amount", 0)))

func _get_storage_component_available_capacity(storage_id: String) -> int:
	if not _storage_components.has(storage_id):
		return 0
	var component: Dictionary = _storage_components[storage_id]
	return maxi(int(component.get("capacity", 0)) - _get_storage_component_stored_total(storage_id) - _get_storage_component_reserved_amount(storage_id), 0)

func _get_storage_component_stored_total(storage_id: String) -> int:
	if not _storage_components.has(storage_id):
		return 0
	var stored: int = 0
	for amount: Variant in (_storage_components[storage_id] as Dictionary).get("contents", {}).values():
		stored += int(amount)
	return stored

func _get_storage_component_reserved_amount(storage_id: String) -> int:
	var reserved: int = 0
	for reservation: Variant in _storage_component_reservations.values():
		var reservation_data: Dictionary = reservation
		if String(reservation_data.get("storage_id", "")) == storage_id:
			reserved += int(reservation_data.get("amount", 0))
	return reserved

func _get_storage_component_resource_total(resource_type: String) -> int:
	var total: int = 0
	for component: Variant in _storage_components.values():
		total += int((component as Dictionary).get("contents", {}).get(resource_type, 0))
	return total

func _get_all_storage_component_stored_total() -> int:
	var total: int = 0
	for storage_id_value: Variant in _storage_components.keys():
		total += _get_storage_component_stored_total(String(storage_id_value))
	return total

func _restore_reserved_haul_item(reservation: Dictionary, cell: Vector2i) -> void:
	_restore_reserved_ground_item(reservation, cell, "carried item")

func _restore_reserved_ground_item(reservation: Dictionary, cell: Vector2i, label: String) -> void:
	var item: Dictionary = reservation.get("item", {})
	var restore_result: Dictionary = create_ground_item(String(item.get("resource_type", "")), int(item.get("amount", 0)), cell)
	if not bool(restore_result.get("ok", false)):
		push_error("Failed to restore abandoned %s: %s" % [label, String(restore_result.get("reason", "unknown"))])

func _index_ground_item(item: Dictionary) -> void:
	var item_id: String = String(item.get("item_id", ""))
	if item_id.is_empty():
		return
	var cell: Vector2i = item.get("cell", Vector2i.ZERO)
	var cell_items: Dictionary = _ground_item_ids_by_cell.get(cell, {})
	cell_items[item_id] = true
	_ground_item_ids_by_cell[cell] = cell_items

func _unindex_ground_item(item: Dictionary) -> void:
	var item_id: String = String(item.get("item_id", ""))
	var cell: Vector2i = item.get("cell", Vector2i.ZERO)
	if not _ground_item_ids_by_cell.has(cell):
		return
	var cell_items: Dictionary = _ground_item_ids_by_cell[cell]
	cell_items.erase(item_id)
	if cell_items.is_empty():
		_ground_item_ids_by_cell.erase(cell)
	else:
		_ground_item_ids_by_cell[cell] = cell_items

func _rebuild_ground_item_cell_index() -> void:
	_ground_item_ids_by_cell.clear()
	for item_value: Variant in _ground_items.values():
		_index_ground_item(item_value as Dictionary)

func _release_haul_storage_reservation(reservation: Dictionary) -> void:
	var reservation_id: String = String(reservation.get("storage_reservation_id", ""))
	if reservation_id.is_empty():
		return
	if String(reservation.get("destination_kind", "")) == "storage_component":
		_release_storage_component_reservation(reservation_id)
	elif _resource_stockpile.has_storage_reservation(reservation_id):
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
		var entry := {
			"site_id": String(site.get("site_id", "")),
			"building_id": String(site.get("building_id", "")),
			"origin_cell": _serialize_cell(site.get("origin_cell", Vector2i.ZERO)),
			"occupied_cells": occupied_entries,
			"required_resources": site.get("required_resources", {}).duplicate(true),
			"consumed_resources": site.get("consumed_resources", {}).duplicate(true),
			"delivered_resources": site.get("delivered_resources", {}).duplicate(true),
			"resources_consumed": bool(site.get("resources_consumed", false)),
			"build_progress": float(site.get("build_progress", 0.0)),
			"build_time": float(site.get("build_time", 0.0)),
			"completed": bool(site.get("completed", false)),
		}
		var storage_id: String = _build_storage_component_id(String(site.get("site_id", "")))
		if _storage_components.has(storage_id):
			entry["storage_contents"] = (_storage_components[storage_id] as Dictionary).get("contents", {}).duplicate(true)
		entries.append(entry)
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
		var delivered_resources: Dictionary = entry_dict.get("delivered_resources", {}).duplicate(true)
		for resource_type_value: Variant in delivered_resources.keys():
			var resource_type: String = String(resource_type_value)
			var delivered_amount: int = int(delivered_resources[resource_type_value])
			if resource_type.is_empty() or not definition.get("cost", {}).has(resource_type) or delivered_amount < 0 or delivered_amount > int(definition.get("cost", {}).get(resource_type, 0)):
				return _build_import_result(false, "invalid_delivered_construction_resources")
		var site := {
			"site_id": site_id,
			"building_id": building_id,
			"origin_cell": origin_cell,
			"occupied_cells": footprint_cells,
			"required_resources": entry_dict.get("required_resources", definition.get("cost", {})).duplicate(true),
			"consumed_resources": entry_dict.get("consumed_resources", {}).duplicate(true),
			"delivered_resources": delivered_resources,
			"resources_consumed": bool(entry_dict.get("resources_consumed", false)),
			"build_progress": float(entry_dict.get("build_progress", 0.0)),
			"build_time": float(entry_dict.get("build_time", definition.get("build_time", 0.0))),
			"completed": bool(entry_dict.get("completed", false)),
			"storage_contents": entry_dict.get("storage_contents", {}).duplicate(true),
		}
		imported_sites[site_id] = site
		for cell: Vector2i in footprint_cells:
			imported_occupied_cells[cell] = site_id
	_construction_sites = imported_sites
	_occupied_construction_cells = imported_occupied_cells
	_construction_reservations.clear()
	_construction_material_reservations.clear()
	_construction_delivery_reservations.clear()
	_storage_components.clear()
	_storage_component_reservations.clear()
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
	var spend_result: Dictionary
	if _storage_components.is_empty():
		if _resource_stockpile == null:
			return _build_food_consumption_result(false, "stockpile_unavailable", colonist_id, amount, 0)
		spend_result = _resource_stockpile.request_spend_resources({"food": amount})
	else:
		spend_result = _consume_storage_resource("food", amount)
	if not bool(spend_result.get("ok", false)):
		return _build_food_consumption_result(false, String(spend_result.get("reason", "spend_failed")), colonist_id, amount, 0)
	return _build_food_consumption_result(true, "consumed", colonist_id, amount, amount)

func get_resource_total(resource_type: String) -> int:
	if _resource_stockpile == null:
		return _get_storage_component_resource_total(resource_type)
	return _resource_stockpile.get_total(resource_type) + _get_storage_component_resource_total(resource_type)

func get_resource_totals() -> Dictionary:
	var totals: Dictionary = _resource_stockpile.get_totals() if _resource_stockpile != null else {}
	for component: Variant in _storage_components.values():
		var contents: Dictionary = (component as Dictionary).get("contents", {})
		for resource_type: Variant in contents.keys():
			var key: String = String(resource_type)
			totals[key] = int(totals.get(key, 0)) + int(contents[resource_type])
	return totals

func get_storage_capacity() -> int:
	return _resource_stockpile.get_storage_capacity() if _resource_stockpile != null else 0

func get_stored_resource_total() -> int:
	return (_resource_stockpile.get_stored_total() if _resource_stockpile != null else 0) + _get_all_storage_component_stored_total()

func get_storage_state() -> Dictionary:
	var state: Dictionary = _resource_stockpile.get_storage_state() if _resource_stockpile != null else {"stored": 0, "capacity": 0, "reserved": 0, "available": 0, "over_capacity": false}
	state["stored"] = get_stored_resource_total()
	state["over_capacity"] = int(state.get("stored", 0)) > int(state.get("capacity", 0))
	return state

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
	_rebuild_storage_components()
	for site: Variant in _construction_sites.values():
		var site_data: Dictionary = site
		if not bool(site_data.get("completed", false)):
			continue
		var definition: Dictionary = BuildingDefinitionRef.get_definition(String(site_data.get("building_id", "")))
		capacity += maxi(int(definition.get("storage_capacity", 0)), 0)
	_resource_stockpile.set_storage_capacity(capacity)

func _rebuild_storage_components() -> void:
	var rebuilt: Dictionary = {}
	for site_value: Variant in _construction_sites.values():
		var site: Dictionary = site_value
		if not bool(site.get("completed", false)):
			continue
		var definition: Dictionary = BuildingDefinitionRef.get_definition(String(site.get("building_id", "")))
		var capacity: int = maxi(int(definition.get("storage_capacity", 0)), 0)
		if capacity <= 0:
			continue
		var storage_id: String = _build_storage_component_id(String(site.get("site_id", "")))
		var previous_contents: Dictionary = (_storage_components.get(storage_id, {}) as Dictionary).get("contents", site.get("storage_contents", {})).duplicate(true)
		rebuilt[storage_id] = {
			"storage_id": storage_id,
			"construction_site_id": String(site.get("site_id", "")),
			"building_id": String(site.get("building_id", "")),
			"origin_cell": site.get("origin_cell", Vector2i.ZERO),
			"occupied_cells": site.get("occupied_cells", []).duplicate(),
			"capacity": capacity,
			"contents": previous_contents,
		}
	_storage_components = rebuilt
	var stale_reservation_ids: Array[String] = []
	for reservation_id: Variant in _storage_component_reservations.keys():
		var reservation: Dictionary = _storage_component_reservations[reservation_id]
		if not _storage_components.has(String(reservation.get("storage_id", ""))):
			stale_reservation_ids.append(String(reservation_id))
	for reservation_id: String in stale_reservation_ids:
		_storage_component_reservations.erase(reservation_id)

func _copy_storage_component(component: Dictionary) -> Dictionary:
	return {
		"storage_id": String(component.get("storage_id", "")),
		"construction_site_id": String(component.get("construction_site_id", "")),
		"building_id": String(component.get("building_id", "")),
		"origin_cell": component.get("origin_cell", Vector2i.ZERO),
		"occupied_cells": component.get("occupied_cells", []).duplicate(),
		"capacity": int(component.get("capacity", 0)),
		"contents": component.get("contents", {}).duplicate(true),
		"reserved": _get_storage_component_reserved_amount(String(component.get("storage_id", ""))),
		"available": _get_storage_component_available_capacity(String(component.get("storage_id", ""))),
	}

func _build_storage_component_id(site_id: String) -> String:
	return "storage_%s" % site_id

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
		"destination_kind": String(reservation.get("destination_kind", "")),
		"storage_id": String(reservation.get("storage_id", "")),
		"storage_reservation_id": String(reservation.get("storage_reservation_id", "")),
		"reserved_by_colonist_id": String(reservation.get("reserved_by_colonist_id", "")),
		"picked_up": bool(reservation.get("picked_up", false)),
	}

func _build_construction_delivery_result(ok: bool, reason: String, site_id: String, item_id: String, colonist_id: String, item: Dictionary, reservation: Dictionary) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"site_id": site_id,
		"item_id": item_id,
		"colonist_id": colonist_id,
		"item": item.duplicate(true),
		"pickup_cell": reservation.get("pickup_cell", item.get("cell", Vector2i.ZERO)),
		"destination_cell": reservation.get("destination_cell", Vector2i.ZERO),
		"delivery_amount": int(reservation.get("delivery_amount", item.get("amount", 0))),
		"reserved_by_colonist_id": String(reservation.get("reserved_by_colonist_id", "")),
		"picked_up": bool(reservation.get("picked_up", false)),
	}

func _build_storage_component_reservation_result(ok: bool, reason: String, reservation_id: String, storage_id: String, amount: int) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"reservation_id": reservation_id,
		"storage_id": storage_id,
		"amount": amount,
		"reserved_storage": _get_storage_component_reserved_amount(storage_id),
		"available_storage": _get_storage_component_available_capacity(storage_id),
	}

func _build_import_result(ok: bool, reason: String) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
	}
