extends Node2D
class_name ColonistManager

signal population_replaced

const TraitRegistryRef = preload("res://scripts/entities/colonist_trait_registry.gd")

const FIRST_NAMES: Array[String] = [
	"Ada", "Bram", "Clara", "Dorian", "Elise", "Finn",
	"Greta", "Hugo", "Iris", "Jonas", "Mara", "Nolan",
]
const LAST_NAMES: Array[String] = [
	"Alder", "Bennett", "Cobb", "Dale", "Ellis", "Frost",
	"Gray", "Hart", "Ives", "Kern", "Lowe", "Marsh",
]

@export_range(1, 12, 1) var colonist_count: int = 3
@export var chunk_manager_path: NodePath = NodePath("../..")
@export var colonist_scene: PackedScene
@export var show_needs_labels_debug: bool = false

@onready var _chunk_manager: ChunkManager = get_node(chunk_manager_path) as ChunkManager
var _world_state: Node
var _cleanup_timer: float = 0.0
var _next_colonist_id: int = 1
var _initial_population_created: bool = false
var _applied_show_needs_labels_debug := false

@export_range(0.5, 10.0, 0.5) var reservation_cleanup_interval: float = 2.0
@export var simulation_profile_debug: bool = false
@export_range(0.5, 10.0, 0.5) var simulation_profile_summary_interval: float = 1.0
var _simulation_profile_elapsed := 0.0

## Purpose: Create, export, replace, and identify the authoritative colonist population.
## Responsibility: Own population lifecycle and reciprocal/name-resolved relationships; colonist nodes own individual records.
## Assumption: Import occurs after WorldState/ResourceStockpile clear transient work and capacity reservations.

func _ready() -> void:
	call_deferred("_spawn_initial_colonists")

func set_world_state(world_state: Node) -> void:
	_world_state = world_state


func set_needs_labels_debug_visible(enabled: bool) -> void:
	## Bulk presentation toggle. Individual colonists retain ownership of their label node.
	show_needs_labels_debug = enabled
	_sync_needs_label_debug_visibility()


func _sync_needs_label_debug_visibility() -> void:
	if _applied_show_needs_labels_debug == show_needs_labels_debug:
		return
	_applied_show_needs_labels_debug = show_needs_labels_debug
	for child: Node in get_children():
		if child is Colonist and not child.is_queued_for_deletion():
			(child as Colonist).set_needs_label_visible(show_needs_labels_debug)


func get_visible_needs_label_count() -> int:
	var count := 0
	for child: Node in get_children():
		if child is Colonist and child.visible and not child.is_queued_for_deletion() and (child as Colonist).is_needs_label_visible():
			count += 1
	return count


func _process(frame_delta: float) -> void:
	_sync_needs_label_debug_visibility()
	_update_simulation_profiling(frame_delta)
	if _world_state == null:
		return
	var delta: float = _world_state.get_simulation_delta(frame_delta)
	if delta <= 0.0:
		return
	_cleanup_timer -= delta
	if _cleanup_timer > 0.0:
		return
	_cleanup_timer = reservation_cleanup_interval
	var active_ids: Array[String] = get_active_colonist_ids()
	_world_state.cleanup_stale_construction_reservations(active_ids)
	_world_state.cleanup_stale_construction_material_deliveries(active_ids)
	_world_state.cleanup_stale_harvest_reservations(active_ids)
	_world_state.cleanup_stale_mining_reservations(active_ids)
	_world_state.cleanup_stale_haul_reservations(active_ids)


func _update_simulation_profiling(frame_delta: float) -> void:
	for child: Node in get_children():
		if child is Colonist and not child.is_queued_for_deletion():
			(child as Colonist).set_process_profiling_enabled(simulation_profile_debug)
	if not simulation_profile_debug:
		return
	_simulation_profile_elapsed += maxf(frame_delta, 0.0)
	if _simulation_profile_elapsed < simulation_profile_summary_interval:
		return
	var total_usec := 0
	var max_usec := 0
	var samples := 0
	var counters: Dictionary = {}
	for child: Node in get_children():
		if not child is Colonist or child.is_queued_for_deletion():
			continue
		var colonist := child as Colonist
		var profile: Dictionary = colonist.consume_process_profile()
		total_usec += int(profile.get("total_usec", 0))
		max_usec = maxi(max_usec, int(profile.get("max_usec", 0)))
		samples += int(profile.get("samples", 0))
		var colonist_counters: Dictionary = colonist.get_job_scheduling_debug_counters()
		for key: String in colonist_counters:
			counters[key] = int(counters.get(key, 0)) + int(colonist_counters.get(key, 0))
		colonist.reset_job_scheduling_debug_counters()
	print("SIMULATION_PROFILE seconds=%.2f colonist_process_ms=%.3f max_process_ms=%.3f samples=%d job_scans=%d path_queries=%d need_attempts=%d need_paths=%d" % [_simulation_profile_elapsed, float(total_usec) / 1000.0, float(max_usec) / 1000.0, samples, int(counters.get("job_evaluations_attempted", 0)), int(counters.get("path_queries_requested", 0)), int(counters.get("need_seeking_attempted", 0)), int(counters.get("need_path_queries", 0))])
	_simulation_profile_elapsed = 0.0

func get_active_colonist_ids() -> Array[String]:
	var active_ids: Array[String] = []
	for child: Node in get_children():
		if not child is Colonist or child.is_queued_for_deletion():
			continue
		var colonist: Colonist = child as Colonist
		if not colonist.colonist_id.is_empty():
			active_ids.append(colonist.colonist_id)
	return active_ids

func get_colonist_need_summaries() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for child: Node in get_children():
		if child is Colonist and not child.is_queued_for_deletion():
			var colonist: Colonist = child as Colonist
			var summary: Dictionary = colonist.get_needs_state()
			summary["colonist_id"] = colonist.colonist_id
			summaries.append(summary)
	return summaries

func get_colonist_at_world_position(world_position: Vector2, selection_radius: float = 16.0) -> Colonist:
	## Resolve presentation input against live colonists without moving selection state into this manager.
	var closest: Colonist
	var closest_distance_squared: float = selection_radius * selection_radius
	for child: Node in get_children():
		if not child is Colonist or child.is_queued_for_deletion():
			continue
		var colonist: Colonist = child as Colonist
		if colonist.current_world_space_id != _chunk_manager.get_active_world_space_id():
			continue
		var visual_center: Vector2 = colonist.global_position + Vector2(0, -8)
		var distance_squared: float = visual_center.distance_squared_to(world_position)
		if distance_squared <= closest_distance_squared:
			closest = colonist
			closest_distance_squared = distance_squared
	return closest

func get_first_colonist_in_world_space(world_space_id: String) -> Colonist:
	for child: Node in get_children():
		if child is Colonist and not child.is_queued_for_deletion():
			var colonist: Colonist = child as Colonist
			if colonist.current_world_space_id == world_space_id:
				return colonist
	return null

func refresh_active_world_space_visibility() -> void:
	for child: Node in get_children():
		if child is Colonist and not child.is_queued_for_deletion():
			(child as Colonist).sync_active_world_space_visibility()

func export_colonist_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for child: Node in get_children():
		if child is Colonist and not child.is_queued_for_deletion():
			records.append((child as Colonist).export_state())
	return records

func import_colonist_records(records: Array) -> Dictionary:
	## Validate stable ids before replacing the population, then resolve relationships after all nodes exist.
	if records.is_empty():
		return _build_import_result(false, "empty_colonist_records", 0, 0)
	var seen_ids: Dictionary = {}
	for entry: Variant in records:
		if not entry is Dictionary:
			return _build_import_result(false, "invalid_colonist_record", 0, 0)
		var record: Dictionary = entry
		var colonist_id: String = String(record.get("colonist_id", ""))
		if colonist_id.is_empty() or seen_ids.has(colonist_id):
			return _build_import_result(false, "invalid_or_duplicate_colonist_id", 0, 0)
		var world_space_id: String = String(record.get("world_space_id", ChunkManager.SURFACE_WORLD_SPACE_ID))
		if not _is_imported_world_space_supported(world_space_id):
			return _build_import_result(false, "unsupported_world_space_id", 0, 0)
		seen_ids[colonist_id] = true
	_clear_population()
	_initial_population_created = true
	_next_colonist_id = 1
	var restored_by_id: Dictionary = {}
	var unresolved_relationships: Dictionary = {}
	for entry: Variant in records:
		var record: Dictionary = entry
		var colonist: Colonist = colonist_scene.instantiate() as Colonist
		var colonist_id: String = String(record.get("colonist_id", ""))
		var cell: Vector2i = _cell_from_record(record)
		colonist.name = colonist_id
		add_child(colonist)
		colonist.initialize(
			_chunk_manager,
			cell,
			_world_state,
			colonist_id,
			String(record.get("first_name", "")),
			String(record.get("last_name", "")),
			{},
			[],
			String(record.get("world_space_id", ChunkManager.SURFACE_WORLD_SPACE_ID))
		)
		colonist.set_needs_label_visible(show_needs_labels_debug)
		var import_result: Dictionary = colonist.import_state(record)
		if not bool(import_result.get("ok", false)):
			_clear_population()
			return _build_import_result(false, String(import_result.get("reason", "colonist_import_failed")), 0, 0)
		restored_by_id[colonist_id] = colonist
		unresolved_relationships[colonist_id] = import_result.get("relationships", [])
		_update_next_colonist_id(colonist_id)
	colonist_count = restored_by_id.size()
	var skipped_relationships: int = _resolve_imported_relationships(restored_by_id, unresolved_relationships)
	_cleanup_timer = reservation_cleanup_interval
	population_replaced.emit()
	return _build_import_result(true, "imported", restored_by_id.size(), skipped_relationships)

func _is_imported_world_space_supported(world_space_id: String) -> bool:
	## WorldState imports interiors before this preflight, so every accepted identity already has an authority owner.
	if world_space_id == ChunkManager.SURFACE_WORLD_SPACE_ID:
		return true
	if _chunk_manager != null:
		return _chunk_manager.is_world_space_supported(world_space_id)
	return _world_state != null and _world_state.has_method("get_interior_for_world_space") and not _world_state.get_interior_for_world_space(world_space_id).is_empty()

func _spawn_initial_colonists() -> void:
	if colonist_scene == null or _initial_population_created:
		return
	_initial_population_created = true
	var spawned_colonists: Array[Colonist] = []
	for index in range(colonist_count):
		var spawn_origin: Vector2i = Vector2i(index * 2, index)
		# Initial placement is not a movement transition and runs before the first
		# streamed chunks are necessarily available.
		var spawn_cell: Vector2i = _chunk_manager.get_random_walkable_cell_near(spawn_origin, 8, 96, false)
		var colonist: Colonist = colonist_scene.instantiate() as Colonist
		var runtime_id := "colonist_%04d" % _next_colonist_id
		var generated_first_name: String = FIRST_NAMES[index % FIRST_NAMES.size()]
		var generated_last_name: String = LAST_NAMES[(index * 5 + 3) % LAST_NAMES.size()]
		var generated_skills: Dictionary = _generate_skills(index)
		var generated_trait_ids: Array[String] = _generate_trait_ids(index)
		_next_colonist_id += 1
		colonist.name = runtime_id
		add_child(colonist)
		colonist.initialize(_chunk_manager, spawn_cell, _world_state, runtime_id, generated_first_name, generated_last_name, generated_skills, generated_trait_ids)
		colonist.set_needs_label_visible(show_needs_labels_debug)
		spawned_colonists.append(colonist)
	_generate_initial_relationships(spawned_colonists)

func _generate_skills(spawn_index: int) -> Dictionary:
	## Deterministic spawn-order variation with one major and one distinct minor specialty.
	var generated: Dictionary = {}
	var skill_count: int = Colonist.SKILL_NAMES.size()
	var major_index: int = spawn_index % skill_count
	var minor_index: int = (major_index + 3 + (spawn_index % 4)) % skill_count
	for skill_index in range(skill_count):
		var level: int = (spawn_index * 7 + skill_index * 3 + (spawn_index + 1) * (skill_index + 2)) % 10
		var passion: String = Colonist.PASSION_NONE
		if skill_index == major_index:
			level = 9 + (spawn_index * 3) % 8
			passion = Colonist.PASSION_MAJOR
		elif skill_index == minor_index:
			level = 6 + (spawn_index * 5) % 7
			passion = Colonist.PASSION_MINOR
		generated[Colonist.SKILL_NAMES[skill_index]] = {
			"level": clampi(level, 0, 20),
			"xp": 0.0,
			"passion": passion,
		}
	return generated

func _generate_trait_ids(spawn_index: int) -> Array[String]:
	## Select 1-3 deterministic traits, skipping registry-defined conflicts and duplicates.
	var target_count: int = 1 + spawn_index % 3
	var trait_count: int = TraitRegistryRef.TRAIT_IDS.size()
	var step: int = spawn_index * 2 + 1
	var generated: Array[String] = []
	var attempt: int = 0
	while generated.size() < target_count and attempt < trait_count * 2:
		var candidate: String = TraitRegistryRef.TRAIT_IDS[(spawn_index + attempt * step) % trait_count]
		attempt += 1
		if candidate in generated:
			continue
		var conflicts: bool = false
		for existing_trait_id: String in generated:
			if TraitRegistryRef.are_conflicting(candidate, existing_trait_id):
				conflicts = true
				break
		if not conflicts:
			generated.append(candidate)
	return generated

func _generate_initial_relationships(colonists: Array[Colonist]) -> void:
	## Use fixed spawn-order pairs so every link is deterministic and reciprocal.
	if colonists.size() >= 2:
		_link_relationship(colonists[0], colonists[1], "partner", "partner")
	if colonists.size() >= 4:
		_link_relationship(colonists[2], colonists[3], "sibling", "sibling")

func _link_relationship(first: Colonist, second: Colonist, first_type: String, second_type: String) -> void:
	if first == null or second == null or first == second:
		return
	var first_added: bool = first.add_relationship(first_type, second.colonist_id, second.get_full_name())
	var second_added: bool = second.add_relationship(second_type, first.colonist_id, first.get_full_name())
	if first_added != second_added:
		push_error("Reciprocal relationship generation failed for '%s' and '%s'." % [first.colonist_id, second.colonist_id])

func _clear_population() -> void:
	for child: Node in get_children():
		if child is Colonist:
			remove_child(child)
			child.queue_free()

func _resolve_imported_relationships(restored_by_id: Dictionary, unresolved: Dictionary) -> int:
	var skipped: int = 0
	for source_id: Variant in unresolved.keys():
		var source: Colonist = restored_by_id.get(String(source_id)) as Colonist
		for entry: Variant in unresolved[source_id]:
			if not entry is Dictionary:
				skipped += 1
				continue
			var relationship: Dictionary = entry
			var relation_type: String = String(relationship.get("relation_type", ""))
			var target_id: String = String(relationship.get("target_colonist_id", ""))
			var target: Colonist = restored_by_id.get(target_id) as Colonist
			if source == null or target == null or not source.add_relationship(relation_type, target_id, target.get_full_name()):
				skipped += 1
	return skipped

func _cell_from_record(record: Dictionary) -> Vector2i:
	var values: Array = record.get("cell", [])
	if values.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(values[0]), int(values[1]))

func _update_next_colonist_id(colonist_id: String) -> void:
	if not colonist_id.begins_with("colonist_"):
		return
	var suffix: String = colonist_id.trim_prefix("colonist_")
	if suffix.is_valid_int():
		_next_colonist_id = maxi(_next_colonist_id, suffix.to_int() + 1)

func _build_import_result(ok: bool, reason: String, imported_count: int, skipped_relationships: int) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"imported_count": imported_count,
		"skipped_relationships": skipped_relationships,
	}
