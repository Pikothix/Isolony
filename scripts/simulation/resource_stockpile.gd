extends Node
class_name ResourceStockpile

signal resource_total_changed(resource_type: String, total: int)
signal storage_capacity_changed(capacity: int, stored: int)

const BASE_STORAGE_CAPACITY := 100

const STARTING_TOTALS := {
	"wood": 0,
	"stone": 0,
	"food": 0,
}

var _totals: Dictionary = STARTING_TOTALS.duplicate()
var _reservations: Dictionary = {}
var _storage_reservations: Dictionary = {}
var _storage_capacity: int = BASE_STORAGE_CAPACITY

## Purpose: Owns the colony's current resource totals for the simulation layer.
## Responsibility: Own abstract stored totals, transient resource earmarks/storage-capacity reservations, and atomic validated mutations.
## Assumption: Ground items live in WorldState and enter these totals only through validated hauling deposits.
func add_resource(resource_type: String, amount: int) -> int:
	## Backward-compatible total return; all additions still pass through capacity validation.
	var result: Dictionary = request_add_resource(resource_type, amount)
	return int(result.get("total", get_total(resource_type)))

func request_add_resource(resource_type: String, amount: int) -> Dictionary:
	var validation: Dictionary = validate_resource_addition(resource_type, amount)
	if not bool(validation.get("ok", false)):
		return validation
	var total: int = get_total(resource_type) + amount
	_totals[resource_type] = total
	resource_total_changed.emit(resource_type, total)
	return _build_add_result(true, "added", resource_type, amount, total)

func validate_resource_addition(resource_type: String, amount: int) -> Dictionary:
	if resource_type.is_empty():
		return _build_add_result(false, "empty_resource_type", resource_type, amount, 0)
	if amount <= 0:
		return _build_add_result(false, "invalid_amount", resource_type, amount, get_total(resource_type))
	if get_stored_total() + get_reserved_storage_amount() + amount > _storage_capacity:
		return _build_add_result(false, "storage_capacity_exceeded", resource_type, amount, get_total(resource_type))
	return _build_add_result(true, "valid", resource_type, amount, get_total(resource_type))

func set_storage_capacity(capacity: int) -> void:
	var next_capacity: int = maxi(capacity, 0)
	if next_capacity == _storage_capacity:
		return
	_storage_capacity = next_capacity
	storage_capacity_changed.emit(_storage_capacity, get_stored_total())

func get_storage_capacity() -> int:
	return _storage_capacity

func get_stored_total() -> int:
	var stored: int = 0
	for amount: Variant in _totals.values():
		stored += int(amount)
	return stored

func get_reserved_storage_amount() -> int:
	var reserved: int = 0
	for amount: Variant in _storage_reservations.values():
		reserved += int(amount)
	return reserved

func get_available_storage_capacity() -> int:
	return maxi(_storage_capacity - get_stored_total() - get_reserved_storage_amount(), 0)

func can_reserve_storage(amount: int) -> bool:
	return amount > 0 and amount <= get_available_storage_capacity()

func reserve_storage(reservation_id: String, amount: int) -> Dictionary:
	if reservation_id.is_empty():
		return _build_storage_reservation_result(false, "empty_reservation_id", reservation_id, amount)
	if amount <= 0:
		return _build_storage_reservation_result(false, "invalid_amount", reservation_id, amount)
	if _storage_reservations.has(reservation_id):
		return _build_storage_reservation_result(false, "duplicate_reservation_id", reservation_id, int(_storage_reservations[reservation_id]))
	if not can_reserve_storage(amount):
		return _build_storage_reservation_result(false, "insufficient_storage_capacity", reservation_id, amount)
	_storage_reservations[reservation_id] = amount
	return _build_storage_reservation_result(true, "reserved", reservation_id, amount)

func release_storage_reservation(reservation_id: String) -> Dictionary:
	if not _storage_reservations.has(reservation_id):
		return _build_storage_reservation_result(false, "unknown_reservation_id", reservation_id, 0)
	var amount: int = int(_storage_reservations[reservation_id])
	_storage_reservations.erase(reservation_id)
	return _build_storage_reservation_result(true, "released", reservation_id, amount)

func validate_storage_reservation(reservation_id: String, amount_added: int) -> Dictionary:
	if not _storage_reservations.has(reservation_id):
		return _build_storage_reservation_result(false, "unknown_reservation_id", reservation_id, amount_added)
	var reserved_amount: int = int(_storage_reservations[reservation_id])
	if amount_added <= 0 or amount_added != reserved_amount:
		return _build_storage_reservation_result(false, "reserved_amount_mismatch", reservation_id, reserved_amount)
	if get_stored_total() + get_reserved_storage_amount() > _storage_capacity:
		return _build_storage_reservation_result(false, "storage_capacity_exceeded", reservation_id, reserved_amount)
	return _build_storage_reservation_result(true, "valid", reservation_id, reserved_amount)

func consume_storage_reservation(reservation_id: String, amount_added: int) -> Dictionary:
	## Convert one complete future-yield earmark into immediately addable capacity.
	var validation: Dictionary = validate_storage_reservation(reservation_id, amount_added)
	if not bool(validation.get("ok", false)):
		return validation
	_storage_reservations.erase(reservation_id)
	return _build_storage_reservation_result(true, "consumed", reservation_id, amount_added)

func has_storage_reservation(reservation_id: String) -> bool:
	return _storage_reservations.has(reservation_id)

func get_storage_reservation_amount(reservation_id: String) -> int:
	return int(_storage_reservations.get(reservation_id, 0))

func get_storage_reservation_summary() -> Dictionary:
	return {
		"count": _storage_reservations.size(),
		"reserved": get_reserved_storage_amount(),
		"available": get_available_storage_capacity(),
		"reservations": _storage_reservations.duplicate(),
	}

func clear_storage_reservations() -> void:
	_storage_reservations.clear()

func get_storage_state() -> Dictionary:
	return {
		"stored": get_stored_total(),
		"capacity": _storage_capacity,
		"reserved": get_reserved_storage_amount(),
		"available": get_available_storage_capacity(),
		"over_capacity": get_stored_total() > _storage_capacity,
	}

func request_spend_resources(cost: Dictionary) -> Dictionary:
	## Ordinary spending may use only totals not already earmarked by reservations.
	var normalization: Dictionary = _normalize_cost(cost)
	if not bool(normalization.get("ok", false)):
		return _build_spend_result(false, String(normalization.get("reason", "invalid_cost")), {}, String(normalization.get("resource_type", "")), int(normalization.get("required", 0)), int(normalization.get("available", 0)))
	var normalized_cost: Dictionary = normalization["cost"]
	for resource_type: Variant in normalized_cost.keys():
		var key: String = String(resource_type)
		var required: int = int(normalized_cost[key])
		var available: int = get_available_total(key)
		if available < required:
			return _build_spend_result(false, "insufficient_resources", {}, key, required, available)
	for resource_type: Variant in normalized_cost.keys():
		var key: String = String(resource_type)
		var amount: int = int(normalized_cost[key])
		if amount == 0:
			continue
		_totals[key] = get_total(key) - amount
		resource_total_changed.emit(key, int(_totals[key]))
	return _build_spend_result(true, "spent", normalized_cost, "", 0, 0)

func get_available_total(resource_type: String) -> int:
	var reserved_total: int = 0
	for reservation: Variant in _reservations.values():
		reserved_total += int((reservation as Dictionary).get(resource_type, 0))
	return get_total(resource_type) - reserved_total

func can_reserve_resources(cost: Dictionary) -> bool:
	var normalization: Dictionary = _normalize_cost(cost)
	if not bool(normalization.get("ok", false)):
		return false
	var normalized_cost: Dictionary = normalization["cost"]
	for resource_type: Variant in normalized_cost.keys():
		var key: String = String(resource_type)
		if get_available_total(key) < int(normalized_cost[key]):
			return false
	return true

func reserve_resources(reservation_id: String, cost: Dictionary) -> Dictionary:
	if reservation_id.is_empty():
		return _build_reservation_result(false, "empty_reservation_id", reservation_id, {}, "", 0, 0)
	if _reservations.has(reservation_id):
		return _build_reservation_result(false, "duplicate_reservation_id", reservation_id, {}, "", 0, 0)
	var normalization: Dictionary = _normalize_cost(cost)
	if not bool(normalization.get("ok", false)):
		return _build_reservation_result(false, String(normalization.get("reason", "invalid_cost")), reservation_id, {}, String(normalization.get("resource_type", "")), int(normalization.get("required", 0)), int(normalization.get("available", 0)))
	var normalized_cost: Dictionary = normalization["cost"]
	for resource_type: Variant in normalized_cost.keys():
		var key: String = String(resource_type)
		var required: int = int(normalized_cost[key])
		var available: int = get_available_total(key)
		if available < required:
			return _build_reservation_result(false, "insufficient_available_resources", reservation_id, {}, key, required, available)
	_reservations[reservation_id] = normalized_cost.duplicate(true)
	return _build_reservation_result(true, "reserved", reservation_id, normalized_cost, "", 0, 0)

func release_resource_reservation(reservation_id: String) -> Dictionary:
	if not _reservations.has(reservation_id):
		return _build_reservation_result(false, "unknown_reservation_id", reservation_id, {}, "", 0, 0)
	var released: Dictionary = (_reservations[reservation_id] as Dictionary).duplicate(true)
	_reservations.erase(reservation_id)
	return _build_reservation_result(true, "released", reservation_id, released, "", 0, 0)

func consume_reserved_resources(reservation_id: String) -> Dictionary:
	if not _reservations.has(reservation_id):
		return _build_reservation_result(false, "unknown_reservation_id", reservation_id, {}, "", 0, 0)
	var reserved: Dictionary = _reservations[reservation_id]
	for resource_type: Variant in reserved.keys():
		var key: String = String(resource_type)
		var required: int = int(reserved[key])
		var total: int = get_total(key)
		if total < required:
			return _build_reservation_result(false, "reserved_total_unavailable", reservation_id, {}, key, required, total)
	for resource_type: Variant in reserved.keys():
		var key: String = String(resource_type)
		var amount: int = int(reserved[key])
		if amount == 0:
			continue
		_totals[key] = get_total(key) - amount
	_reservations.erase(reservation_id)
	for resource_type: Variant in reserved.keys():
		var key: String = String(resource_type)
		if int(reserved[key]) > 0:
			resource_total_changed.emit(key, get_total(key))
	return _build_reservation_result(true, "consumed", reservation_id, reserved, "", 0, 0)

func has_resource_reservation(reservation_id: String) -> bool:
	return _reservations.has(reservation_id)

func clear_resource_reservations() -> void:
	_reservations.clear()

func get_total(resource_type: String) -> int:
	return int(_totals.get(resource_type, 0))

func get_totals() -> Dictionary:
	return _totals.duplicate()

func export_state() -> Dictionary:
	return get_totals()

func import_state(state: Dictionary) -> Dictionary:
	var imported_totals: Dictionary = STARTING_TOTALS.duplicate()
	for resource_type: Variant in state.keys():
		var key: String = String(resource_type)
		var amount: int = int(state[resource_type])
		if key.is_empty():
			return _build_import_result(false, "empty_resource_type")
		if amount < 0:
			return _build_import_result(false, "negative_resource_total")
		imported_totals[key] = amount
	_totals = imported_totals
	_reservations.clear()
	_storage_reservations.clear()
	for resource_type: Variant in _totals.keys():
		resource_total_changed.emit(String(resource_type), int(_totals[resource_type]))
	storage_capacity_changed.emit(_storage_capacity, get_stored_total())
	return _build_import_result(true, "imported")

func _build_add_result(ok: bool, reason: String, resource_type: String, amount: int, total: int) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"resource_type": resource_type,
		"amount": amount,
		"total": total,
		"stored": get_stored_total(),
		"capacity": _storage_capacity,
		"reserved_capacity": get_reserved_storage_amount(),
		"available_capacity": get_available_storage_capacity(),
	}

func _build_storage_reservation_result(ok: bool, reason: String, reservation_id: String, amount: int) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"reservation_id": reservation_id,
		"amount": amount,
		"reserved_storage": get_reserved_storage_amount(),
		"available_storage": get_available_storage_capacity(),
	}

func _build_import_result(ok: bool, reason: String) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
	}

func _build_spend_result(ok: bool, reason: String, spent: Dictionary, resource_type: String, required: int, available: int) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"spent": spent.duplicate(true),
		"resource_type": resource_type,
		"required": required,
		"available": available,
		"totals": get_totals(),
	}

func _normalize_cost(cost: Dictionary) -> Dictionary:
	var normalized_cost: Dictionary = {}
	for resource_type: Variant in cost.keys():
		var key: String = String(resource_type)
		var amount: int = int(cost[resource_type])
		if key.is_empty():
			return {"ok": false, "reason": "empty_resource_type", "resource_type": key, "required": amount, "available": 0}
		if amount < 0:
			return {"ok": false, "reason": "invalid_cost_amount", "resource_type": key, "required": amount, "available": get_available_total(key)}
		normalized_cost[key] = amount
	return {"ok": true, "reason": "valid", "cost": normalized_cost}

func _build_reservation_result(ok: bool, reason: String, reservation_id: String, resources: Dictionary, resource_type: String, required: int, available: int) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"reservation_id": reservation_id,
		"resources": resources.duplicate(true),
		"resource_type": resource_type,
		"required": required,
		"available": available,
		"totals": get_totals(),
	}
