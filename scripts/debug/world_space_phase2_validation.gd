extends SceneTree

## Purpose: Focused headless validation for surface-scoped WorldState records.
## Responsibility: Verify additive save compatibility, scoped indexes, and unchanged surface gameplay flows.
## Assumption: Phase 2 supports only WorldState.SURFACE_WORLD_SPACE_ID.

const WorldStateScript = preload("res://scripts/simulation/world_state.gd")

const SURFACE := "surface"
const HARVEST_RESOURCE_ID := "tree:5:5"
const HARVEST_CELL := Vector2i(5, 5)

var _failures: Array[String] = []


class PlacementQueryStub extends Node:
	var resource_depleted: bool = false

	func is_cell_loaded(_cell: Vector2i, world_space_id: String = "surface") -> bool:
		return world_space_id == "surface"

	func get_effective_tile_info(cell: Vector2i, world_space_id: String = "surface") -> Dictionary:
		if world_space_id != "surface":
			return {}
		return {
			"cell": cell,
			"terrain": "GRASS",
			"walkable": true,
			"mineable": false,
			"elevation": 0,
		}

	func is_cell_blocked_by_resource(_cell: Vector2i, world_space_id: String = "surface") -> bool:
		return world_space_id != "surface"

	func get_harvest_resource_snapshot(resource_id: String) -> Dictionary:
		if resource_id != HARVEST_RESOURCE_ID or resource_depleted:
			return {"ok": false, "reason": "resource_depleted" if resource_depleted else "unknown_resource"}
		return {
			"ok": true,
			"reason": "valid",
			"resource_id": HARVEST_RESOURCE_ID,
			"resource_type": "wood",
			"yield_amount": 8,
			"cell": HARVEST_CELL,
		}

	func commit_harvest_resource(resource_id: String) -> Dictionary:
		var snapshot: Dictionary = get_harvest_resource_snapshot(resource_id)
		if not bool(snapshot.get("ok", false)):
			return snapshot
		resource_depleted = true
		return snapshot

	func is_resource_depleted(resource_id: String) -> bool:
		return resource_id == HARVEST_RESOURCE_ID and resource_depleted


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_import_export_compatibility()
	await _validate_surface_gameplay_flows()
	if _failures.is_empty():
		print("WORLD_SPACE_PHASE2_VALIDATION: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error("WORLD_SPACE_PHASE2_VALIDATION: %s" % failure)
	quit(1)


func _validate_import_export_compatibility() -> void:
	var context: Dictionary = await _create_world_state()
	var world_state: WorldState = context["world_state"]
	var legacy_site := {
		"site_id": "campfire:0:0",
		"building_id": "campfire",
		"origin_cell": {"x": 0, "y": 0},
		"occupied_cells": [{"x": 0, "y": 0}],
		"required_resources": {"wood": 5},
		"consumed_resources": {"wood": 0},
		"delivered_resources": {},
		"resources_consumed": false,
		"build_progress": 0.0,
		"build_time": 10.0,
		"completed": false,
	}
	_check_ok(world_state.import_construction_sites([legacy_site]), "legacy construction import")
	_check(String(world_state.get_construction_site("campfire:0:0").get("world_space_id", "")) == SURFACE, "legacy construction did not default to surface")
	_check(String(world_state.export_construction_sites()[0].get("world_space_id", "")) == SURFACE, "construction export omitted world_space_id")

	var legacy_order := {
		"order_id": "harvest:%s" % HARVEST_RESOURCE_ID,
		"resource_id": HARVEST_RESOURCE_ID,
		"resource_type": "wood",
		"yield_amount": 8,
		"cell": {"x": HARVEST_CELL.x, "y": HARVEST_CELL.y},
	}
	_check_ok(world_state.import_harvest_orders([legacy_order]), "legacy harvest-order import")
	_check(String(world_state.get_harvest_order(String(legacy_order["order_id"])).get("world_space_id", "")) == SURFACE, "legacy harvest order did not default to surface")
	_check(String(world_state.export_harvest_orders()[0].get("world_space_id", "")) == SURFACE, "harvest export omitted world_space_id")

	var legacy_zone := {
		"zone_id": "stockpile_0001",
		"cells": [{"x": 10, "y": 10}],
		"enabled": true,
		"label": "Legacy Stockpile",
	}
	_check_ok(world_state.import_stockpile_zones([legacy_zone]), "legacy stockpile-zone import")
	_check(String(world_state.get_stockpile_zones()[0].get("world_space_id", "")) == SURFACE, "legacy stockpile zone did not default to surface")
	_check(String(world_state.export_stockpile_zones()[0].get("world_space_id", "")) == SURFACE, "stockpile export omitted world_space_id")

	var legacy_item := {
		"item_id": "ground_item_000001",
		"resource_type": "wood",
		"amount": 3,
		"cell": {"x": 4, "y": 4},
		"enabled": true,
	}
	_check_ok(world_state.import_ground_items([legacy_item]), "legacy ground-item import")
	_check(String(world_state.get_ground_items()[0].get("world_space_id", "")) == SURFACE, "legacy ground item did not default to surface")
	_check(String(world_state.export_ground_items()[0].get("world_space_id", "")) == SURFACE, "ground-item export omitted world_space_id")

	for test_case: Dictionary in [
		{"label": "construction", "entry": legacy_site, "method": "import_construction_sites"},
		{"label": "harvest order", "entry": legacy_order, "method": "import_harvest_orders"},
		{"label": "stockpile zone", "entry": legacy_zone, "method": "import_stockpile_zones"},
		{"label": "ground item", "entry": legacy_item, "method": "import_ground_items"},
	]:
		var unsupported: Dictionary = (test_case["entry"] as Dictionary).duplicate(true)
		unsupported["world_space_id"] = "cave"
		var result: Dictionary = world_state.call(StringName(test_case["method"]), [unsupported])
		_check(not bool(result.get("ok", false)), "unsupported %s WorldSpace did not reject" % String(test_case["label"]))

	var unsupported_state := {
		"construction_sites": [],
		"harvest_orders": [],
		"stockpile_zones": [],
		"ground_items": [legacy_item.merged({"world_space_id": "cave"}, true)],
	}
	var state_result: Dictionary = world_state.import_state(unsupported_state)
	_check(not bool(state_result.get("ok", false)), "combined state import accepted an unsupported WorldSpace")
	_cleanup_context(context)


func _validate_surface_gameplay_flows() -> void:
	var context: Dictionary = await _create_world_state()
	var world_state: WorldState = context["world_state"]

	_check_ok(world_state.add_resource("wood", 5), "construction resource setup")
	var placement: Dictionary = world_state.request_place_construction("campfire", Vector2i.ZERO, SURFACE)
	_check_ok(placement, "surface construction placement")
	var site: Dictionary = world_state.get_construction_site_at_cell(Vector2i.ZERO, SURFACE)
	_check(String(site.get("world_space_id", "")) == SURFACE, "placed construction site was not surface-scoped")
	_check(world_state.get_construction_site_at_cell(Vector2i.ZERO, "cave").is_empty(), "unsupported construction query leaked a surface site")
	_check_ok(world_state.request_progress_construction(String(site.get("site_id", "")), 10.0), "surface construction completion")
	_check(world_state.is_cell_warmed(Vector2i.ZERO, SURFACE), "completed Campfire did not provide surface warmth")
	_check(not world_state.is_cell_warmed(Vector2i.ZERO, "cave"), "surface building effect leaked into an unsupported WorldSpace")

	var designation: Dictionary = world_state.request_designate_harvest(HARVEST_RESOURCE_ID, SURFACE)
	_check_ok(designation, "surface harvest designation")
	var order_id: String = String(designation.get("order_id", ""))
	_check_ok(world_state.reserve_harvest_order(order_id, "colonist_validation"), "surface harvest reservation")
	var completion: Dictionary = world_state.request_complete_harvest_order(order_id, "colonist_validation")
	_check_ok(completion, "surface harvest completion")
	var harvested_item: Dictionary = completion.get("item", {})
	_check(String(harvested_item.get("world_space_id", "")) == SURFACE, "harvest completion created an unscoped ground item")

	var zone_result: Dictionary = world_state.request_create_stockpile_zone([Vector2i(10, 10)], SURFACE)
	_check_ok(zone_result, "surface stockpile-zone creation")
	_check(world_state.is_cell_in_stockpile_zone(Vector2i(10, 10), SURFACE), "surface stockpile index lookup failed")
	_check(not world_state.is_cell_in_stockpile_zone(Vector2i(10, 10), "cave"), "surface stockpile index leaked across WorldSpaces")

	var item_id: String = String(harvested_item.get("item_id", ""))
	var haul_reservation: Dictionary = world_state.reserve_haul_item(item_id, "colonist_validation", SURFACE)
	_check_ok(haul_reservation, "surface haul reservation")
	_check(String(haul_reservation.get("world_space_id", "")) == SURFACE, "haul reservation omitted world_space_id")
	var pickup: Dictionary = world_state.request_pickup_ground_item(item_id, "colonist_validation")
	_check_ok(pickup, "surface ground-item pickup")
	var destination_cell: Vector2i = haul_reservation.get("destination_cell", Vector2i.ZERO)
	_check_ok(world_state.request_deposit_carried_item("colonist_validation", pickup.get("item", {}), destination_cell, SURFACE), "surface haul deposit")
	_cleanup_context(context)


func _create_world_state() -> Dictionary:
	var placement_query := PlacementQueryStub.new()
	root.add_child(placement_query)
	var world_state: WorldState = WorldStateScript.new() as WorldState
	root.add_child(world_state)
	await process_frame
	world_state.set_placement_query(placement_query)
	return {"world_state": world_state, "placement_query": placement_query}


func _cleanup_context(context: Dictionary) -> void:
	var world_state: Node = context.get("world_state") as Node
	var placement_query: Node = context.get("placement_query") as Node
	if world_state != null:
		world_state.free()
	if placement_query != null:
		placement_query.free()


func _check_ok(result: Dictionary, label: String) -> void:
	_check(bool(result.get("ok", false)), "%s failed: %s" % [label, String(result.get("reason", "unknown"))])


func _check(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
