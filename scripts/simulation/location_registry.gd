extends RefCounted
class_name LocationRegistry

const Generator = preload("res://scripts/simulation/bounded_location_generator.gd")
const STARTING_LOCATION_ID := "starting_location"
const HOME := "HOME"
const DISCOVERED := "DISCOVERED"
const RETAINED := "RETAINED"
const DEPLETED := "DEPLETED"
const DISCARDED := "DISCARDED"
var _locations: Dictionary = {}
var _next_pile_sequence := 1
var _resource_reservations: Dictionary = {}

## Owns persistent bounded locations: identity, generation base, runtime resource
## deltas, lifecycle, world position, local piles, and presence membership.
func create_starting_location(game_seed: int) -> Dictionary:
	var generated := Generator.new().generate(game_seed, "general")
	if generated.is_empty(): return {}
	var record := _record_from_generated(STARTING_LOCATION_ID, "Home Settlement", "general", generated, Vector2i.ZERO, HOME)
	record.claimed = true; record.claimed_at_simulation_time = 0.0; record.claimed_by_colony_id = "player_colony"; record.primary_settlement = true; record.is_primary_settlement = true; record.settled = false
	_locations = {STARTING_LOCATION_ID: record}; _next_pile_sequence = 1
	return record

func create_discovered_location(origin_id: String, search_type: String, sequence: int, seed_value: int, world_position: Vector2i) -> Dictionary:
	if not has(origin_id): return {}
	var id := "location_%04d" % sequence
	if has(id): return {}
	var generated := Generator.new().generate(seed_value, search_type)
	if generated.is_empty(): return {}
	var name := "%s Site %d" % [search_type.replace("_", " ").capitalize(), sequence]
	var record := _record_from_generated(id, name, search_type, generated, world_position, DISCOVERED)
	_locations[id] = record
	return record

func _record_from_generated(id: String, name: String, type: String, generated: Dictionary, position: Vector2i, lifecycle: String) -> Dictionary:
	return {"location_id": id, "display_name": name, "location_type": type, "seed": int(generated.generation_seed), "world_position": position, "distance_metadata": {}, "lifecycle_state": lifecycle, "discovery_state": lifecycle, "claimed": false, "claimed_at_simulation_time": -1.0, "claimed_by_colony_id": "", "primary_settlement": false, "is_primary_settlement": false, "generated_base": {"generation_config": generated.generation_config}, "runtime_deltas": {}, "generation_config": generated.generation_config, "map_size": generated.map_size, "terrain": generated.terrain, "resources": generated.resources, "spawn_cells": generated.spawn_cells, "entry_cell": generated.spawn_cells[0], "exit_cell": generated.spawn_cells[0], "camp_storage_cell": generated.camp_storage_cell, "temporary_remote_storage": false, "colonist_presence_ids": [], "piles": [], "settled": false}

func has(id: String) -> bool: return _locations.has(id) and String(_locations[id].lifecycle_state) != DISCARDED
func get_record(id: String) -> Dictionary: return _locations.get(id, {})
func ids() -> Array[String]:
	var result: Array[String] = []; for key: Variant in _locations: if has(String(key)): result.append(String(key))
	result.sort_custom(func(a: String, b: String) -> bool:
		var order := {HOME: 0, RETAINED: 1, DISCOVERED: 2, DEPLETED: 3}; var ar: Dictionary = _locations[a]; var br: Dictionary = _locations[b]
		var ao := int(order.get(String(ar.lifecycle_state), 9)); var bo := int(order.get(String(br.lifecycle_state), 9)); return ao < bo if ao != bo else a < b)
	return result
func snapshot(id: String) -> Dictionary:
	var result := get_record(id).duplicate(true); if not result.is_empty(): result.resource_totals = resource_totals(id); result.potentials = potential_summary(id)
	return result
func snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in ids(): result.append(snapshot(id))
	return result
func settle(id: String) -> Dictionary:
	if id != STARTING_LOCATION_ID or not has(id): return _result(false, "invalid_home")
	var location := get_record(id); if bool(location.settled): return _result(false, "already_settled")
	location.settled = true; return _result(true, "settled")
func retain(id: String) -> Dictionary:
	if not has(id): return _result(false, "unknown_location")
	if String(get_record(id).lifecycle_state) != DISCOVERED: return _result(false, "not_discovered")
	get_record(id).lifecycle_state = RETAINED; get_record(id).discovery_state = RETAINED; return _result(true, "retained")
func claim(id: String, colonist_id: String, simulation_time: float) -> Dictionary:
	if id == STARTING_LOCATION_ID: return _result(false, "home_location")
	if not has(id): return _result(false, "unknown_location")
	var record := get_record(id)
	if String(record.lifecycle_state) != RETAINED: return _result(false, "location_not_retained")
	if bool(record.claimed): return _result(false, "already_claimed")
	if colonist_id not in record.colonist_presence_ids: return _result(false, "no_colonist_present")
	record.claimed = true; record.claimed_at_simulation_time = simulation_time; record.claimed_by_colony_id = "player_colony"
	return _result(true, "claimed")
func discard(id: String) -> Dictionary:
	if id == STARTING_LOCATION_ID: return _result(false, "home_cannot_be_discarded")
	if not has(id): return _result(false, "unknown_location")
	var record := get_record(id)
	if bool(record.get("claimed", false)): return _result(false, "claimed_location")
	if not (record.colonist_presence_ids as Array).is_empty() or not (record.piles as Array).is_empty(): return _result(false, "location_in_use")
	_locations.erase(id); return _result(true, "discarded")
func rename(id: String, value: String) -> Dictionary:
	var cleaned := value.strip_edges(); if not has(id) or cleaned.is_empty(): return _result(false, "invalid_name")
	get_record(id).display_name = cleaned.left(48); return _result(true, "renamed")
func add_presence(id: String, colonist_id: String) -> Dictionary:
	if not has(id): return _result(false, "unknown_location")
	var presence: Array = get_record(id).colonist_presence_ids; if colonist_id in presence: return _result(false, "already_present")
	presence.append(colonist_id); presence.sort(); return _result(true, "presence_added")
func remove_presence(id: String, colonist_id: String) -> Dictionary:
	if not has(id): return _result(false, "unknown_location")
	var presence: Array = get_record(id).colonist_presence_ids; if colonist_id not in presence: return _result(false, "not_present")
	presence.erase(colonist_id); return _result(true, "presence_removed")
func find_resource(id: String, resource_id: String) -> Dictionary:
	if has(id): for resource: Dictionary in get_record(id).resources: if String(resource.resource_id) == resource_id: return resource
	return {}
func create_or_merge_pile(id: String, type: String, amount: int, cell: Vector2i, stored := false) -> Dictionary:
	if not has(id) or type not in ["wood", "stone", "food"] or amount <= 0: return _result(false, "invalid_pile_request")
	for pile: Dictionary in get_record(id).piles:
		if bool(pile.enabled) and String(pile.resource_type) == type and Vector2i(pile.cell) == cell and bool(pile.stored) == stored: pile.amount += amount; return {"ok": true, "reason": "pile_merged", "pile_id": pile.pile_id}
	var pile_id := "pile_%04d" % _next_pile_sequence; _next_pile_sequence += 1
	get_record(id).piles.append({"pile_id": pile_id, "location_id": id, "resource_type": type, "amount": amount, "cell": cell, "stored": stored, "reserved_amount": 0, "reservation_owner_id": "", "enabled": true}); return {"ok": true, "reason": "pile_created", "pile_id": pile_id}
func get_pile_snapshot(id: String, pile_id: String) -> Dictionary: return _find_pile(id, pile_id).duplicate(true)
func get_pile_snapshots(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if has(id):
		for pile: Dictionary in get_record(id).piles: result.append(pile.duplicate(true))
	return result
func reserve_pile(id: String, pile_id: String, owner: String, amount: int) -> Dictionary:
	var pile := _find_pile(id, pile_id); if pile.is_empty() or not bool(pile.enabled): return _result(false, "pile_unavailable")
	if owner.is_empty() or amount <= 0 or not String(pile.reservation_owner_id).is_empty() or amount > int(pile.amount): return _result(false, "invalid_reservation")
	pile.reserved_amount = amount; pile.reservation_owner_id = owner; return _result(true, "reserved")
func release_pile_reservation(id: String, pile_id: String, owner: String) -> Dictionary:
	var pile := _find_pile(id, pile_id); if pile.is_empty() or String(pile.reservation_owner_id) != owner: return _result(false, "reservation_owner_mismatch")
	pile.reserved_amount = 0; pile.reservation_owner_id = ""; return _result(true, "released")
func pickup_reserved_pile(id: String, pile_id: String, owner: String, amount: int) -> Dictionary:
	var pile := _find_pile(id, pile_id); if pile.is_empty() or String(pile.reservation_owner_id) != owner or int(pile.reserved_amount) != amount or int(pile.amount) < amount: return _result(false, "invalid_pickup")
	pile.amount -= amount; pile.reserved_amount = 0; pile.reservation_owner_id = ""; pile.enabled = int(pile.amount) > 0; return {"ok": true, "reason": "picked_up", "amount": amount, "resource_type": pile.resource_type, "cell": pile.cell}
func get_consumable_stored_amount(id: String, type: String) -> int:
	if not has(id): return 0
	var available := 0
	for pile: Dictionary in get_record(id).piles:
		if _is_pile_consumable(id, pile, type): available += int(pile.amount)
	return available
func consume_stored(id: String, type: String, amount: int) -> Dictionary:
	if amount <= 0 or not has(id): return _result(false, "invalid_amount")
	var candidates: Array = get_record(id).piles.duplicate(); candidates.sort_custom(func(a, b): return String(a.pile_id) < String(b.pile_id))
	var valid: Array = []; for p: Dictionary in candidates: if _is_pile_consumable(id, p, type): valid.append(p)
	var available := 0; for p: Dictionary in valid: available += int(p.amount)
	if available < amount: return _result(false, "insufficient_stored_resource")
	var remaining := amount; for p: Dictionary in valid: var take := mini(remaining, int(p.amount)); p.amount -= take; remaining -= take; p.enabled = int(p.amount) > 0; if remaining <= 0: break
	return _result(true, "consumed")
func reserve_local_resources(id: String, cost: Dictionary, owner: String) -> Dictionary:
	if owner.is_empty() or _resource_reservations.has(owner) or not has(id): return _result(false, "invalid_resource_reservation")
	var selections: Array[Dictionary] = []
	for type: Variant in cost:
		var needed := int(cost[type]); var candidates: Array = get_record(id).piles.duplicate(); candidates.sort_custom(func(a, b): return String(a.pile_id) < String(b.pile_id))
		for pile: Dictionary in candidates:
			if needed <= 0: break
			if bool(pile.enabled) and String(pile.resource_type) == String(type) and String(pile.reservation_owner_id).is_empty():
				var take := mini(needed, int(pile.amount)); selections.append({"pile_id": pile.pile_id, "amount": take}); needed -= take
		if needed > 0: return _result(false, "insufficient_local_resources")
	for selection: Dictionary in selections:
		var pile := _find_pile(id, String(selection.pile_id)); pile.reservation_owner_id = owner; pile.reserved_amount = int(selection.amount)
	_resource_reservations[owner] = {"location_id": id, "selections": selections}
	return _result(true, "resources_reserved")
func can_reserve_local_resources(id: String, cost: Dictionary) -> bool:
	if not has(id): return false
	for type: Variant in cost:
		var available := 0
		for pile: Dictionary in get_record(id).piles:
			if bool(pile.enabled) and String(pile.resource_type) == String(type) and String(pile.reservation_owner_id).is_empty(): available += int(pile.amount)
		if available < int(cost[type]): return false
	return true
func get_missing_local_resources(id: String, cost: Dictionary) -> Dictionary:
	var missing: Dictionary = {}
	if not has(id): return cost.duplicate(true)
	for type: Variant in cost:
		var available := 0
		for pile: Dictionary in get_record(id).piles:
			if bool(pile.enabled) and String(pile.resource_type) == String(type) and String(pile.reservation_owner_id).is_empty(): available += int(pile.amount)
		var amount := int(cost[type]) - available
		if amount > 0: missing[String(type)] = amount
	return missing
func consume_reserved_resources(id: String, owner: String) -> Dictionary:
	var reservation: Dictionary = _resource_reservations.get(owner, {})
	if reservation.is_empty() or String(reservation.location_id) != id: return _result(false, "resource_reservation_missing")
	for selection: Dictionary in reservation.selections:
		var pile := _find_pile(id, String(selection.pile_id)); var amount := int(selection.amount)
		if pile.is_empty() or String(pile.reservation_owner_id) != owner or int(pile.amount) < amount: return _result(false, "resource_reservation_invalid")
	for selection: Dictionary in reservation.selections:
		var pile := _find_pile(id, String(selection.pile_id)); pile.amount -= int(selection.amount); pile.reserved_amount = 0; pile.reservation_owner_id = ""; pile.enabled = int(pile.amount) > 0
	_resource_reservations.erase(owner); return _result(true, "resources_consumed")
func release_resource_reservation(owner: String) -> void:
	var reservation: Dictionary = _resource_reservations.get(owner, {})
	for selection: Dictionary in reservation.get("selections", []):
		var pile := _find_pile(String(reservation.get("location_id", "")), String(selection.pile_id)); if not pile.is_empty() and String(pile.reservation_owner_id) == owner: pile.reserved_amount = 0; pile.reservation_owner_id = ""
	_resource_reservations.erase(owner)
func resource_totals(id: String) -> Dictionary:
	var totals := {"stored": {"wood": 0, "stone": 0, "food": 0}, "loose": {"wood": 0, "stone": 0, "food": 0}}
	if has(id): for pile: Dictionary in get_record(id).piles: if bool(pile.enabled): totals["stored" if bool(pile.stored) else "loose"][String(pile.resource_type)] += int(pile.amount)
	return totals
func potential_summary(id: String) -> Dictionary:
	var result := {"wood": 0, "stone": 0, "food": 0}; if has(id): for r: Dictionary in get_record(id).resources: if not bool(r.depleted) and not (String(r.resource_type) == "food" and bool(r.fruit_harvested)): result[String(r.resource_type)] += int(r.yield)
	return result
func export_state() -> Dictionary:
	var locations := snapshots()
	# Pile claims back worker/material transactions and are deliberately transient.
	for location: Dictionary in locations:
		for pile: Dictionary in location.piles:
			pile.reserved_amount = 0
			pile.reservation_owner_id = ""
	return {"locations": locations, "next_pile_sequence": _next_pile_sequence}
func import_state(data: Dictionary) -> Dictionary:
	if not data.get("locations") is Array or (data.locations as Array).is_empty(): return _result(false, "invalid_locations")
	var staged: Dictionary = {}
	for raw: Variant in data.locations:
		if not raw is Dictionary: return _result(false, "invalid_location")
		var id := String(raw.get("location_id", "")); if id.is_empty() or staged.has(id) or not raw.get("world_position") is Vector2i or not raw.get("resources") is Array or not raw.get("piles") is Array or not raw.get("colonist_presence_ids") is Array: return _result(false, "invalid_location")
		staged[id] = raw.duplicate(true)
	if not staged.has(STARTING_LOCATION_ID) or Vector2i(staged[STARTING_LOCATION_ID].world_position) != Vector2i.ZERO: return _result(false, "invalid_home")
	_locations = staged; _next_pile_sequence = maxi(int(data.get("next_pile_sequence", 1)), 1); _resource_reservations.clear(); return _result(true, "imported")
func _find_pile(id: String, pile_id: String) -> Dictionary:
	if has(id): for pile: Dictionary in get_record(id).piles: if String(pile.pile_id) == pile_id: return pile
	return {}
func _is_pile_consumable(id: String, pile: Dictionary, type: String) -> bool:
	return bool(pile.enabled) and String(pile.resource_type) == type and (bool(pile.stored) or (id != STARTING_LOCATION_ID and Vector2i(pile.cell) == Vector2i(get_record(id).entry_cell)))
func _result(ok: bool, reason: String) -> Dictionary: return {"ok": ok, "reason": reason}
