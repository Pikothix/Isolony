extends Node2D
class_name Colonist

## Purpose: Persistent colonist records plus transient loaded-cell path movement, prioritized work, needs, and need-seeking behavior.
## Responsibility: Own authoritative identity, character data, needs, and work priorities while executing simulation-issued work orders over non-authoritative paths.
## Assumption: Import resumes from idle at the saved position; jobs, paths, carrying, reservations, movement targets, selection, and debug state are not saved.

const TraitRegistryRef = preload("res://scripts/entities/colonist_trait_registry.gd")
const ReachabilityQueryRef = preload("res://scripts/world/reachability_query.gd")

const SKILL_NAMES: Array[String] = [
	"Construction",
	"Mining",
	"Plants",
	"Cooking",
	"Crafting",
	"Animals",
	"Medicine",
	"Research",
	"Shooting",
	"Melee",
	"Social",
]
const PASSION_NONE := "none"
const PASSION_MINOR := "minor"
const PASSION_MAJOR := "major"
const VALID_PASSIONS: Array[String] = [PASSION_NONE, PASSION_MINOR, PASSION_MAJOR]
const RELATIONSHIP_TYPES: Array[String] = ["parent", "child", "sibling", "partner"]
const WORK_TYPES: Array[String] = [
	"Construct",
	"Harvest",
	"Haul",
	"Mine",
	"Farm",
	"Cook",
	"Craft",
	"Doctor",
	"Research",
	"Guard",
]
const WORK_DISABLED := 0
const WORK_PRIORITY_MIN := 1
const WORK_PRIORITY_MAX := 4
const JOB_TYPE_CONSTRUCT := "construct"
const JOB_TYPE_HARVEST := "harvest"
const JOB_TYPE_HAUL := "haul"
const JOB_CANDIDATE_LIMIT := 16
const JOB_EVALUATION_INTERVAL := 0.25
const JOB_EVALUATION_STAGGER_SLOTS := 8
const DEFAULT_WORK_PRIORITIES := {
	"Construct": 2,
	"Harvest": 2,
	"Haul": 0,
	"Mine": 0,
	"Farm": 0,
	"Cook": 0,
	"Craft": 0,
	"Doctor": 0,
	"Research": 0,
	"Guard": 0,
}

enum Activity {
	IDLE,
	WANDERING,
	MOVING_TO_CONSTRUCTION,
	CONSTRUCTING,
	SEEKING_WARMTH,
	SEEKING_SHELTER,
	EATING,
	MOVING_TO_HARVEST,
	HARVESTING,
	MOVING_TO_HAUL_ITEM,
	CARRYING_ITEM,
	MOVING_TO_STOCKPILE,
	DEPOSITING,
}

@export var move_speed: float = 42.0
@export_range(2, 12, 1) var wander_radius: int = 6
@export var pause_duration_min: float = 0.5
@export var pause_duration_max: float = 1.4
@export_range(0.1, 20.0, 0.1) var construction_work_rate: float = 2.0
@export_range(1.0, 120.0, 1.0) var construction_travel_timeout: float = 30.0
@export_range(0.1, 10.0, 0.1) var harvest_work_duration: float = 2.0
@export_range(1.0, 120.0, 1.0) var haul_travel_timeout: float = 30.0
@export_range(0.0, 2.0, 0.01) var night_rest_decay_rate: float = 0.12
@export_range(0.0, 2.0, 0.01) var day_rest_recovery_rate: float = 0.08
@export_range(0.0, 2.0, 0.01) var cold_decay_rate: float = 0.20
@export_range(0.0, 2.0, 0.01) var warmth_recovery_rate: float = 0.35
@export_range(0.0, 2.0, 0.01) var unsheltered_decay_rate: float = 0.15
@export_range(0.0, 2.0, 0.01) var shelter_recovery_rate: float = 0.25
@export_range(0.0, 2.0, 0.01) var hunger_decay_rate: float = 0.04
@export_range(0.0, 100.0, 1.0) var hunger_eat_threshold: float = 60.0
@export_range(0.0, 100.0, 1.0) var hunger_eating_target: float = 85.0
@export_range(1, 10, 1) var food_per_bite: int = 1
@export_range(1.0, 100.0, 1.0) var hunger_restored_per_food: float = 25.0
@export_range(0.1, 10.0, 0.1) var eating_duration: float = 0.75
@export_range(0.0, 100.0, 1.0) var warmth_seek_threshold: float = 60.0
@export_range(0.0, 100.0, 1.0) var shelter_seek_threshold: float = 60.0
@export_range(0.0, 100.0, 1.0) var need_seek_recovery_threshold: float = 80.0
@export var show_needs_debug: bool = true

var colonist_id: String = ""
var first_name: String = ""
var last_name: String = ""
var nickname: String = ""
var chunk_manager: ChunkManager
var world_state: Node
var current_cell: Vector2i = Vector2i.ZERO
var target_cell: Vector2i = Vector2i.ZERO
var rest: float = 100.0
var warmth: float = 100.0
var shelter: float = 100.0
var hunger: float = 100.0
var _skills: Dictionary = {}
var _traits: Array[Dictionary] = []
var _relationships: Array[Dictionary] = []
var _work_priorities: Dictionary = {}

var _activity: Activity = Activity.IDLE
var _construction_site_id: String = ""
var _construction_travel_elapsed: float = 0.0
var _eating_timer: float = 0.0
var _harvest_order_id: String = ""
var _harvest_travel_elapsed: float = 0.0
var _harvest_work_elapsed: float = 0.0
var _haul_item_id: String = ""
var _haul_destination_cell: Vector2i = Vector2i.ZERO
var _haul_travel_elapsed: float = 0.0
var _carried_item: Dictionary = {}
var _current_path: Array[Vector2i] = []
var _path_index: int = 0
var _target_position: Vector2 = Vector2.ZERO
var _pause_timer: float = 0.0
var _job_evaluation_cooldown_remaining: float = 0.0
var _job_scheduling_counters: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _is_environment_warm: bool = false
var _is_environment_sheltered: bool = false
var _last_needs_label_text: String = ""

@onready var _needs_label: Label = get_node_or_null("NeedsLabel") as Label
@onready var _selection_indicator: CanvasItem = get_node_or_null("SelectionIndicator") as CanvasItem

func _ready() -> void:
	_rng.randomize()

func _exit_tree() -> void:
	if world_state != null and is_instance_valid(world_state) and not colonist_id.is_empty():
		if not _haul_item_id.is_empty():
			_finish_haul_job("colonist_exit_tree")
		world_state.release_all_reservations_for_colonist(colonist_id, "colonist_exit_tree")
		world_state.release_all_harvest_orders_for_colonist(colonist_id, "colonist_exit_tree")
		world_state.release_all_haul_reservations_for_colonist(colonist_id, "colonist_exit_tree")

func initialize(
	manager: ChunkManager,
	spawn_cell: Vector2i,
	simulation_state: Node = null,
	assigned_id: String = "",
	assigned_first_name: String = "",
	assigned_last_name: String = "",
	initial_skills: Dictionary = {},
	initial_trait_ids: Array[String] = []
) -> void:
	chunk_manager = manager
	world_state = simulation_state
	colonist_id = assigned_id if not assigned_id.is_empty() else name
	first_name = assigned_first_name
	last_name = assigned_last_name
	_set_initial_skills(initial_skills)
	_set_initial_traits(initial_trait_ids)
	_set_initial_work_priorities({})
	current_cell = spawn_cell
	target_cell = spawn_cell
	global_position = chunk_manager.get_cell_world_position(spawn_cell) + Vector2(0, -6)
	_enter_idle()
	_set_initial_job_evaluation_stagger()
	reset_job_scheduling_debug_counters()
	_update_needs_label()

func _process(delta: float) -> void:
	if chunk_manager == null:
		return
	_update_needs(delta)
	match _activity:
		Activity.IDLE:
			_process_idle(delta)
		Activity.WANDERING, Activity.MOVING_TO_CONSTRUCTION, Activity.MOVING_TO_HARVEST, Activity.MOVING_TO_HAUL_ITEM, Activity.MOVING_TO_STOCKPILE:
			_move_towards_target(delta)
		Activity.CONSTRUCTING:
			_process_construction(delta)
		Activity.SEEKING_WARMTH, Activity.SEEKING_SHELTER:
			_process_need_seeking(delta)
		Activity.EATING:
			_process_eating(delta)
		Activity.HARVESTING:
			_process_harvesting(delta)
		Activity.CARRYING_ITEM, Activity.DEPOSITING:
			_process_hauling()

func get_activity_name() -> String:
	return Activity.keys()[_activity].to_lower()

func get_job_scheduling_debug_counters() -> Dictionary:
	## Expose transient scheduling cost without making diagnostics part of gameplay authority.
	var snapshot: Dictionary = _job_scheduling_counters.duplicate(true)
	snapshot["cooldown_remaining"] = _job_evaluation_cooldown_remaining
	snapshot["cooldown_interval"] = JOB_EVALUATION_INTERVAL
	return snapshot

func reset_job_scheduling_debug_counters() -> void:
	_job_scheduling_counters = {
		"job_evaluations_attempted": 0,
		"candidates_considered": 0,
		"path_queries_requested": 0,
		"path_queries_succeeded": 0,
		"path_queries_failed": 0,
		"reservations_attempted": 0,
		"reservations_succeeded": 0,
	}

func get_full_name() -> String:
	return (first_name + " " + last_name).strip_edges()

func set_nickname(value: String) -> void:
	## Nicknames are runtime identity state; presentation reads this value but never owns it.
	nickname = value.strip_edges()

func set_selected(is_selected: bool) -> void:
	if _selection_indicator != null:
		_selection_indicator.visible = is_selected

func get_skills() -> Dictionary:
	## Return a defensive copy so callers, especially UI, cannot mutate authoritative skill state.
	return _skills.duplicate(true)

func get_skill_level(skill_name: String) -> int:
	var skill: Dictionary = _skills.get(skill_name, {})
	return clampi(int(skill.get("level", 0)), 0, 20)

func get_skill_passion(skill_name: String) -> String:
	var skill: Dictionary = _skills.get(skill_name, {})
	var passion: String = String(skill.get("passion", PASSION_NONE))
	return passion if passion in VALID_PASSIONS else PASSION_NONE

func get_traits() -> Array[Dictionary]:
	## Return defensive records so presentation cannot mutate authoritative trait data.
	return _traits.duplicate(true)

func has_trait(trait_id: String) -> bool:
	for trait_data: Dictionary in _traits:
		if String(trait_data.get("id", "")) == trait_id:
			return true
	return false

func get_trait_display_names() -> Array[String]:
	var display_names: Array[String] = []
	for trait_data: Dictionary in _traits:
		display_names.append(String(trait_data.get("display_name", trait_data.get("id", "Unknown"))))
	return display_names

func get_relationships() -> Array[Dictionary]:
	## Return defensive records so UI cannot mutate authoritative relationship links.
	return _relationships.duplicate(true)

func add_relationship(relation_type: String, target_colonist_id: String, target_display_name: String) -> bool:
	## Relationship orchestration belongs to ColonistManager; this validates one owned directed link.
	if relation_type not in RELATIONSHIP_TYPES or target_colonist_id.is_empty() or target_display_name.strip_edges().is_empty():
		return false
	if target_colonist_id == colonist_id or has_relationship_with(target_colonist_id):
		return false
	_relationships.append({
		"relation_type": relation_type,
		"target_colonist_id": target_colonist_id,
		"target_display_name": target_display_name.strip_edges(),
	})
	return true

func has_relationship_with(target_colonist_id: String) -> bool:
	for relationship: Dictionary in _relationships:
		if String(relationship.get("target_colonist_id", "")) == target_colonist_id:
			return true
	return false

func get_work_priorities() -> Dictionary:
	## Return a defensive copy so presentation cannot mutate authoritative work policy.
	return _work_priorities.duplicate(true)

func get_work_priority(work_type: String) -> int:
	if work_type not in WORK_TYPES:
		return WORK_DISABLED
	return clampi(int(_work_priorities.get(work_type, WORK_DISABLED)), WORK_DISABLED, WORK_PRIORITY_MAX)

func set_work_priority(work_type: String, value: int) -> bool:
	## Reject unsupported work types and invalid values instead of silently changing player intent.
	if work_type not in WORK_TYPES or value < WORK_DISABLED or value > WORK_PRIORITY_MAX:
		return false
	_work_priorities[work_type] = value
	return true

func can_do_work(work_type: String) -> bool:
	return get_work_priority(work_type) >= WORK_PRIORITY_MIN

func get_effective_construction_work_rate() -> float:
	return maxf(construction_work_rate * _get_trait_modifier_product("construction_work_rate_multiplier"), 0.0)

func get_effective_night_rest_decay_rate() -> float:
	return maxf(night_rest_decay_rate * _get_trait_modifier_product("night_rest_decay_multiplier"), 0.0)

func get_construction_site_id() -> String:
	return _construction_site_id

func get_harvest_order_id() -> String:
	return _harvest_order_id

func get_haul_item_id() -> String:
	return _haul_item_id

func get_carried_item() -> Dictionary:
	return _carried_item.duplicate(true)

func get_current_path() -> Array[Vector2i]:
	## Validation/debug read only; path cells are transient and never exported.
	return _current_path.duplicate()

func has_active_path() -> bool:
	return _path_index < _current_path.size()

func get_needs_state() -> Dictionary:
	return {
		"rest": rest,
		"warmth": warmth,
		"shelter": shelter,
		"hunger": hunger,
		"is_night": world_state != null and world_state.is_night(),
		"is_warm": _is_environment_warm,
		"is_sheltered": _is_environment_sheltered,
		"cell": current_cell,
	}

func export_state() -> Dictionary:
	## Serialize authoritative colonist state only. Relationship names are re-resolved from stable ids on import.
	var trait_ids: Array[String] = []
	for trait_data: Dictionary in _traits:
		trait_ids.append(String(trait_data.get("id", "")))
	var relationship_records: Array[Dictionary] = []
	for relationship: Dictionary in _relationships:
		relationship_records.append({
			"relation_type": String(relationship.get("relation_type", "")),
			"target_colonist_id": String(relationship.get("target_colonist_id", "")),
		})
	return {
		"colonist_id": colonist_id,
		"first_name": first_name,
		"last_name": last_name,
		"nickname": nickname,
		"cell": [current_cell.x, current_cell.y],
		"world_position": [global_position.x, global_position.y],
		"needs": {
			"rest": rest,
			"warmth": warmth,
			"shelter": shelter,
			"hunger": hunger,
		},
		"skills": _skills.duplicate(true),
		"trait_ids": trait_ids,
		"relationships": relationship_records,
		"work_priorities": _work_priorities.duplicate(true),
	}

func import_state(data: Dictionary) -> Dictionary:
	## Restore one initialized colonist and return unresolved relationship ids for manager-level linking.
	var saved_id: String = String(data.get("colonist_id", ""))
	if saved_id.is_empty() or saved_id != colonist_id:
		return {"ok": false, "reason": "colonist_id_mismatch", "relationships": []}
	first_name = String(data.get("first_name", first_name)).strip_edges()
	last_name = String(data.get("last_name", last_name)).strip_edges()
	nickname = String(data.get("nickname", "")).strip_edges()
	_set_initial_skills(data.get("skills", {}))
	var imported_trait_ids: Array[String] = []
	for trait_id: Variant in data.get("trait_ids", []):
		imported_trait_ids.append(String(trait_id))
	_set_initial_traits(imported_trait_ids)
	_set_initial_work_priorities(data.get("work_priorities", {}))
	var needs: Dictionary = data.get("needs", {})
	rest = clampf(float(needs.get("rest", 100.0)), 0.0, 100.0)
	warmth = clampf(float(needs.get("warmth", 100.0)), 0.0, 100.0)
	shelter = clampf(float(needs.get("shelter", 100.0)), 0.0, 100.0)
	hunger = clampf(float(needs.get("hunger", 100.0)), 0.0, 100.0)
	var cell_values: Array = data.get("cell", [])
	if cell_values.size() >= 2:
		current_cell = Vector2i(int(cell_values[0]), int(cell_values[1]))
	var position_values: Array = data.get("world_position", [])
	if position_values.size() >= 2:
		global_position = Vector2(float(position_values[0]), float(position_values[1]))
	else:
		global_position = chunk_manager.get_cell_world_position(current_cell) + Vector2(0, -6)
	_relationships.clear()
	_reset_transient_state()
	_update_needs_label()
	var saved_relationships: Array = data.get("relationships", [])
	return {"ok": true, "reason": "imported", "relationships": saved_relationships.duplicate(true)}

func _set_initial_skills(initial_skills: Dictionary) -> void:
	## Normalize the manager-provided spawn data and guarantee the complete supported skill set.
	_skills.clear()
	for skill_name: String in SKILL_NAMES:
		var provided: Dictionary = initial_skills.get(skill_name, {})
		var passion: String = String(provided.get("passion", PASSION_NONE))
		if passion not in VALID_PASSIONS:
			passion = PASSION_NONE
		_skills[skill_name] = {
			"level": clampi(int(provided.get("level", 0)), 0, 20),
			"xp": maxf(float(provided.get("xp", 0.0)), 0.0),
			"passion": passion,
		}

func _set_initial_traits(initial_trait_ids: Array[String]) -> void:
	## Ignore invalid, duplicate, or conflicting manager input while preserving registry order.
	_traits.clear()
	for trait_id: String in initial_trait_ids:
		if not TraitRegistryRef.has_trait(trait_id) or has_trait(trait_id):
			continue
		var conflicts: bool = false
		for existing_trait: Dictionary in _traits:
			if TraitRegistryRef.are_conflicting(trait_id, String(existing_trait.get("id", ""))):
				conflicts = true
				break
		if not conflicts:
			_traits.append(TraitRegistryRef.get_trait(trait_id))

func _set_initial_work_priorities(initial_priorities: Dictionary) -> void:
	## Missing records use defaults, preserving compatibility with saves written before priorities existed.
	_work_priorities.clear()
	for work_type: String in WORK_TYPES:
		var default_value: int = int(DEFAULT_WORK_PRIORITIES.get(work_type, WORK_DISABLED))
		var value: int = int(initial_priorities.get(work_type, default_value))
		_work_priorities[work_type] = clampi(value, WORK_DISABLED, WORK_PRIORITY_MAX)

func _get_trait_modifier_product(modifier_name: String) -> float:
	var product: float = 1.0
	for trait_data: Dictionary in _traits:
		var modifiers: Dictionary = trait_data.get("modifiers", {})
		product *= maxf(float(modifiers.get(modifier_name, 1.0)), 0.0)
	return product

func _reset_transient_state() -> void:
	## Imported colonists deliberately forget jobs and paths so runtime authorities can assign fresh work.
	_construction_site_id = ""
	_construction_travel_elapsed = 0.0
	_eating_timer = 0.0
	_harvest_order_id = ""
	_harvest_travel_elapsed = 0.0
	_harvest_work_elapsed = 0.0
	_haul_item_id = ""
	_haul_destination_cell = Vector2i.ZERO
	_haul_travel_elapsed = 0.0
	_carried_item.clear()
	_clear_path()
	target_cell = current_cell
	_target_position = global_position
	set_selected(false)
	_enter_idle()
	_job_evaluation_cooldown_remaining = 0.0
	reset_job_scheduling_debug_counters()

func _update_needs(delta: float) -> void:
	if world_state == null or delta <= 0.0:
		return
	current_cell = chunk_manager.world_to_cell(global_position + Vector2(0, 6))
	var is_night: bool = world_state.is_night()
	_is_environment_warm = world_state.is_cell_warmed(current_cell)
	_is_environment_sheltered = world_state.is_cell_sheltered(current_cell)
	hunger -= hunger_decay_rate * delta
	if is_night:
		rest -= get_effective_night_rest_decay_rate() * delta
	else:
		rest += day_rest_recovery_rate * delta
	if _is_environment_warm:
		warmth += warmth_recovery_rate * delta
	elif is_night:
		warmth -= cold_decay_rate * delta
	else:
		warmth += day_rest_recovery_rate * delta
	if _is_environment_sheltered:
		shelter += shelter_recovery_rate * delta
	elif is_night:
		shelter -= unsheltered_decay_rate * delta
	else:
		shelter += day_rest_recovery_rate * delta
	rest = clampf(rest, 0.0, 100.0)
	warmth = clampf(warmth, 0.0, 100.0)
	shelter = clampf(shelter, 0.0, 100.0)
	hunger = clampf(hunger, 0.0, 100.0)
	_update_needs_label()

func _update_needs_label() -> void:
	if _needs_label == null:
		return
	_needs_label.visible = show_needs_debug
	if not show_needs_debug:
		return
	var next_text := "R%02d W%02d S%02d H%02d" % [roundi(rest), roundi(warmth), roundi(shelter), roundi(hunger)]
	if next_text == _last_needs_label_text:
		return
	_last_needs_label_text = next_text
	_needs_label.text = next_text
	var lowest_need: float = minf(rest, minf(warmth, minf(shelter, hunger)))
	_needs_label.modulate = Color(0.65, 1.0, 0.68) if lowest_need >= 65.0 else (Color(1.0, 0.86, 0.35) if lowest_need >= 35.0 else Color(1.0, 0.38, 0.32))

func _process_idle(delta: float) -> void:
	_job_evaluation_cooldown_remaining = maxf(_job_evaluation_cooldown_remaining - delta, 0.0)
	_pause_timer -= delta
	if _pause_timer > 0.0:
		return
	if _try_start_need_seeking():
		return
	if _try_start_eating():
		return
	if _job_evaluation_cooldown_remaining > 0.0:
		return
	_job_evaluation_cooldown_remaining = JOB_EVALUATION_INTERVAL
	if _try_start_prioritized_work():
		return
	_pick_new_wander_target()

func _try_start_prioritized_work() -> bool:
	_increment_job_scheduling_counter("job_evaluations_attempted")
	var job: Dictionary = choose_best_job(collect_available_jobs())
	return not job.is_empty() and start_job(job)

func collect_available_jobs() -> Array[Dictionary]:
	## Project reachable focused WorldState work sources into transient, non-authoritative candidates.
	## Source order is the stable tie-break: construction, then harvest, then haul.
	## One reachable candidate per work type is sufficient because reservation follows immediately on the main thread.
	var jobs: Array[Dictionary] = []
	if world_state == null or colonist_id.is_empty():
		return jobs
	if can_do_work("Construct"):
		for site: Dictionary in world_state.get_available_construction_sites(JOB_CANDIDATE_LIMIT):
			_increment_job_scheduling_counter("candidates_considered")
			var site_cell: Vector2i = site.get("origin_cell", current_cell)
			var site_path: Dictionary = _query_job_path(current_cell, site_cell, {"allow_target_construction": true})
			if not bool(site_path.get("reachable", false)):
				continue
			jobs.append({
				"job_type": JOB_TYPE_CONSTRUCT,
				"priority": get_work_priority("Construct"),
				"target_id": String(site.get("site_id", "")),
				"target_cell": site_cell,
				"reservation_result": {},
			})
			break
	if can_do_work("Harvest"):
		for order: Dictionary in world_state.get_available_harvest_orders(JOB_CANDIDATE_LIMIT):
			_increment_job_scheduling_counter("candidates_considered")
			var order_cell: Vector2i = order.get("cell", current_cell)
			var order_path: Dictionary = _query_job_path(current_cell, order_cell, {"allow_target_resource": true})
			if not bool(order_path.get("reachable", false)):
				continue
			jobs.append({
				"job_type": JOB_TYPE_HARVEST,
				"priority": get_work_priority("Harvest"),
				"target_id": String(order.get("order_id", "")),
				"target_cell": order_cell,
				"reservation_result": {},
			})
			break
	if can_do_work("Haul"):
		for item: Dictionary in world_state.get_available_haul_items(colonist_id, JOB_CANDIDATE_LIMIT):
			_increment_job_scheduling_counter("candidates_considered")
			var item_cell: Vector2i = item.get("cell", current_cell)
			var destination_cell: Vector2i = item.get("destination_cell", current_cell)
			var pickup_path: Dictionary = _query_job_path(current_cell, item_cell)
			if not bool(pickup_path.get("reachable", false)):
				continue
			var deposit_path: Dictionary = _query_job_path(item_cell, destination_cell)
			if not bool(deposit_path.get("reachable", false)):
				continue
			jobs.append({
				"job_type": JOB_TYPE_HAUL,
				"priority": get_work_priority("Haul"),
				"target_id": String(item.get("item_id", "")),
				"target_cell": item_cell,
				"destination_cell": destination_cell,
				"reservation_result": {},
			})
			break
	return jobs

func choose_best_job(candidates: Array[Dictionary]) -> Dictionary:
	## Reserve candidates in priority order. A candidate becomes selected only after WorldState accepts it.
	var remaining: Array[Dictionary] = candidates.duplicate(true)
	while not remaining.is_empty():
		var best_index: int = 0
		for index in range(1, remaining.size()):
			if int(remaining[index].get("priority", WORK_PRIORITY_MAX + 1)) < int(remaining[best_index].get("priority", WORK_PRIORITY_MAX + 1)):
				best_index = index
		var candidate: Dictionary = remaining.pop_at(best_index)
		var reservation: Dictionary = _reserve_job_candidate(candidate)
		if bool(reservation.get("ok", false)):
			candidate["reservation_result"] = reservation.duplicate(true)
			return candidate
	return {}

func start_job(job: Dictionary) -> bool:
	## Translate one reserved candidate into the existing transient activity state.
	## Any validation failure after reservation releases the authoritative reservation.
	var reservation: Dictionary = job.get("reservation_result", {})
	if not bool(reservation.get("ok", false)):
		return false
	var job_type: String = String(job.get("job_type", ""))
	var target_id: String = String(job.get("target_id", ""))
	if world_state == null or chunk_manager == null or colonist_id.is_empty() or target_id.is_empty():
		_release_job_candidate_reservation(job, "job_start_invalid_context")
		return false
	match job_type:
		JOB_TYPE_CONSTRUCT:
			if not can_do_work("Construct") or world_state.get_construction_reservation(target_id) != colonist_id:
				_release_job_candidate_reservation(job, "construction_start_validation_failed")
				return false
			var construction_target: Vector2i = job.get("target_cell", current_cell)
			var construction_path: Dictionary = _query_job_path(current_cell, construction_target, {"allow_target_construction": true})
			if not bool(construction_path.get("reachable", false)):
				_release_job_candidate_reservation(job, "construction_path_unreachable")
				return false
			_construction_site_id = target_id
			_construction_travel_elapsed = 0.0
			_apply_path(construction_path, construction_target)
			_activity = Activity.MOVING_TO_CONSTRUCTION
			return true
		JOB_TYPE_HARVEST:
			if not can_do_work("Harvest") or world_state.get_harvest_order_reservation(target_id) != colonist_id:
				_release_job_candidate_reservation(job, "harvest_start_validation_failed")
				return false
			var harvest_target: Vector2i = job.get("target_cell", current_cell)
			var harvest_path: Dictionary = _query_job_path(current_cell, harvest_target, {"allow_target_resource": true})
			if not bool(harvest_path.get("reachable", false)):
				_release_job_candidate_reservation(job, "harvest_path_unreachable")
				return false
			_harvest_order_id = target_id
			_harvest_travel_elapsed = 0.0
			_harvest_work_elapsed = 0.0
			_apply_path(harvest_path, harvest_target)
			_activity = Activity.MOVING_TO_HARVEST
			return true
		JOB_TYPE_HAUL:
			var haul_reservation: Dictionary = world_state.get_haul_item_reservation(target_id)
			if not can_do_work("Haul") or String(haul_reservation.get("reserved_by_colonist_id", "")) != colonist_id:
				_release_job_candidate_reservation(job, "haul_start_validation_failed")
				return false
			var haul_item: Dictionary = haul_reservation.get("item", {})
			var pickup_cell: Vector2i = haul_item.get("cell", job.get("target_cell", current_cell))
			var deposit_cell: Vector2i = haul_reservation.get("destination_cell", current_cell)
			var pickup_path: Dictionary = _query_job_path(current_cell, pickup_cell)
			var deposit_path: Dictionary = _query_job_path(pickup_cell, deposit_cell)
			if not bool(pickup_path.get("reachable", false)) or not bool(deposit_path.get("reachable", false)):
				_release_job_candidate_reservation(job, "haul_path_unreachable")
				return false
			_haul_item_id = target_id
			_haul_destination_cell = deposit_cell
			_haul_travel_elapsed = 0.0
			_carried_item.clear()
			_apply_path(pickup_path, pickup_cell)
			_activity = Activity.MOVING_TO_HAUL_ITEM
			return true
	_release_job_candidate_reservation(job, "unsupported_job_type")
	return false

func _reserve_job_candidate(candidate: Dictionary) -> Dictionary:
	if world_state == null or colonist_id.is_empty():
		return {"ok": false, "reason": "job_authority_unavailable"}
	var target_id: String = String(candidate.get("target_id", ""))
	var result: Dictionary = {"ok": false, "reason": "invalid_job_candidate"}
	match String(candidate.get("job_type", "")):
		JOB_TYPE_CONSTRUCT:
			if can_do_work("Construct") and not target_id.is_empty():
				_increment_job_scheduling_counter("reservations_attempted")
				result = world_state.reserve_construction_site(colonist_id, target_id)
		JOB_TYPE_HARVEST:
			if can_do_work("Harvest") and not target_id.is_empty():
				_increment_job_scheduling_counter("reservations_attempted")
				result = world_state.reserve_harvest_order(target_id, colonist_id)
		JOB_TYPE_HAUL:
			if can_do_work("Haul") and not target_id.is_empty():
				_increment_job_scheduling_counter("reservations_attempted")
				result = world_state.reserve_haul_item(target_id, colonist_id)
	if bool(result.get("ok", false)):
		_increment_job_scheduling_counter("reservations_succeeded")
	return result

func _release_job_candidate_reservation(job: Dictionary, reason: String) -> void:
	if world_state == null or colonist_id.is_empty():
		return
	var target_id: String = String(job.get("target_id", ""))
	if target_id.is_empty():
		return
	match String(job.get("job_type", "")):
		JOB_TYPE_CONSTRUCT:
			world_state.release_construction_reservation(target_id, colonist_id, reason)
		JOB_TYPE_HARVEST:
			world_state.release_harvest_order(target_id, colonist_id, reason)
		JOB_TYPE_HAUL:
			world_state.release_haul_item(target_id, colonist_id, reason)

func _query_path(cell: Vector2i, allow_target_construction: bool = false, allow_target_resource: bool = false) -> Dictionary:
	if chunk_manager == null or world_state == null:
		return {"ok": false, "reachable": false, "path": [], "reason": "query_context_unavailable"}
	return ReachabilityQueryRef.find_path(chunk_manager, world_state, current_cell, cell, {
		"allow_target_construction": allow_target_construction,
		"allow_target_resource": allow_target_resource,
	})

func _query_job_path(start_cell: Vector2i, destination_cell: Vector2i, options: Dictionary = {}) -> Dictionary:
	_increment_job_scheduling_counter("path_queries_requested")
	var result: Dictionary = ReachabilityQueryRef.find_path(chunk_manager, world_state, start_cell, destination_cell, options)
	_increment_job_scheduling_counter("path_queries_succeeded" if bool(result.get("reachable", false)) else "path_queries_failed")
	return result

func _increment_job_scheduling_counter(counter_name: String) -> void:
	_job_scheduling_counters[counter_name] = int(_job_scheduling_counters.get(counter_name, 0)) + 1

func _set_initial_job_evaluation_stagger() -> void:
	## Stable id hashing spreads initial work scans without introducing simulation randomness.
	var slot: int = 0
	for index in range(colonist_id.length()):
		slot = (slot * 31 + colonist_id.unicode_at(index)) % JOB_EVALUATION_STAGGER_SLOTS
	var offset: float = JOB_EVALUATION_INTERVAL * float(slot) / float(JOB_EVALUATION_STAGGER_SLOTS)
	_job_evaluation_cooldown_remaining = offset
	_pause_timer = offset

func _apply_path(path_result: Dictionary, final_cell: Vector2i) -> void:
	_current_path.clear()
	for cell_value: Variant in path_result.get("path", []):
		if typeof(cell_value) == TYPE_VECTOR2I:
			_current_path.append(cell_value)
	_path_index = 0
	target_cell = final_cell
	if has_active_path():
		_target_position = chunk_manager.get_cell_world_position(_current_path[_path_index]) + Vector2(0, -6)
	else:
		_target_position = global_position

func _clear_path() -> void:
	_current_path.clear()
	_path_index = 0

func _try_start_need_seeking() -> bool:
	if world_state == null or not world_state.is_night():
		return false
	var needs_warmth: bool = warmth < warmth_seek_threshold
	var needs_shelter: bool = shelter < shelter_seek_threshold
	if not needs_warmth and not needs_shelter:
		return false
	if needs_warmth and needs_shelter:
		if warmth <= shelter:
			return _try_seek_warmth() or _try_seek_shelter()
		return _try_seek_shelter() or _try_seek_warmth()
	if needs_warmth:
		return _try_seek_warmth()
	return _try_seek_shelter()

func _try_start_eating() -> bool:
	if world_state == null or colonist_id.is_empty() or hunger >= hunger_eat_threshold:
		return false
	if not _consume_food_bite():
		return false
	_activity = Activity.EATING
	_eating_timer = eating_duration
	return true

func _process_eating(delta: float) -> void:
	_eating_timer -= delta
	if _eating_timer > 0.0:
		return
	if hunger >= hunger_eating_target:
		_enter_idle()
		return
	if not _consume_food_bite():
		_enter_idle()
		return
	_eating_timer = eating_duration

func _consume_food_bite() -> bool:
	var result: Dictionary = world_state.request_consume_food(colonist_id, food_per_bite)
	if not bool(result.get("ok", false)):
		return false
	var amount_consumed: int = int(result.get("amount_consumed", 0))
	if amount_consumed <= 0:
		return false
	hunger = clampf(hunger + float(amount_consumed) * hunger_restored_per_food, 0.0, 100.0)
	_update_needs_label()
	return true

func _try_seek_warmth() -> bool:
	if world_state.is_cell_warmed(current_cell):
		_clear_path()
		target_cell = current_cell
		_target_position = global_position
		_activity = Activity.SEEKING_WARMTH
		return true
	var target: Dictionary = world_state.get_nearest_warmed_cell(current_cell)
	if not bool(target.get("ok", false)):
		return false
	return _set_need_seeking_target(Activity.SEEKING_WARMTH, target.get("cell", current_cell))

func _try_seek_shelter() -> bool:
	if world_state.is_cell_sheltered(current_cell):
		_clear_path()
		target_cell = current_cell
		_target_position = global_position
		_activity = Activity.SEEKING_SHELTER
		return true
	var target: Dictionary = world_state.get_nearest_sheltered_cell(current_cell)
	if not bool(target.get("ok", false)):
		return false
	return _set_need_seeking_target(Activity.SEEKING_SHELTER, target.get("cell", current_cell))

func _set_need_seeking_target(activity: Activity, cell: Vector2i) -> bool:
	var path_result: Dictionary = _query_path(cell)
	if not bool(path_result.get("reachable", false)):
		return false
	_apply_path(path_result, cell)
	_activity = activity
	return true

func _process_need_seeking(delta: float) -> void:
	if world_state == null or not world_state.is_night():
		_job_evaluation_cooldown_remaining = 0.0
		_enter_idle()
		return
	var seeking_warmth: bool = _activity == Activity.SEEKING_WARMTH
	var need_value: float = warmth if seeking_warmth else shelter
	var in_effect: bool = world_state.is_cell_warmed(current_cell) if seeking_warmth else world_state.is_cell_sheltered(current_cell)
	if in_effect:
		if need_value >= need_seek_recovery_threshold:
			_job_evaluation_cooldown_remaining = 0.0
			_enter_idle()
		return
	var target_still_valid: bool = world_state.is_cell_warmed(target_cell) if seeking_warmth else world_state.is_cell_sheltered(target_cell)
	if not target_still_valid:
		var retargeted: bool = _try_seek_warmth() if seeking_warmth else _try_seek_shelter()
		if not retargeted:
			_job_evaluation_cooldown_remaining = 0.0
			_enter_idle()
		return
	_move_towards_target(delta)

func _move_towards_target(delta: float) -> void:
	if _activity == Activity.MOVING_TO_CONSTRUCTION and world_state != null:
		_construction_travel_elapsed += delta
		if _construction_travel_elapsed >= construction_travel_timeout:
			_finish_construction_job("construction_travel_timeout")
			return
		if world_state.get_construction_reservation(_construction_site_id) != colonist_id:
			_finish_construction_job("reservation_lost")
			return
	elif _activity == Activity.MOVING_TO_HARVEST and world_state != null:
		_harvest_travel_elapsed += delta
		if _harvest_travel_elapsed >= construction_travel_timeout:
			_finish_harvest_job("harvest_travel_timeout")
			return
		if world_state.get_harvest_order_reservation(_harvest_order_id) != colonist_id:
			_finish_harvest_job("reservation_lost")
			return
	elif _activity == Activity.MOVING_TO_HAUL_ITEM or _activity == Activity.MOVING_TO_STOCKPILE:
		_haul_travel_elapsed += delta
		if world_state == null or _haul_travel_elapsed >= haul_travel_timeout:
			_finish_haul_job("haul_travel_timeout")
			return
		var haul_reservation: Dictionary = world_state.get_haul_item_reservation(_haul_item_id)
		if String(haul_reservation.get("reserved_by_colonist_id", "")) != colonist_id:
			_finish_haul_job("haul_reservation_lost")
			return
	if not has_active_path():
		_complete_path_arrival()
		return
	var next_cell: Vector2i = _current_path[_path_index]
	var options: Dictionary = _get_current_path_options()
	if not ReachabilityQueryRef.is_cell_traversable(chunk_manager, world_state, next_cell, current_cell, target_cell, options):
		_fail_current_movement("path_became_blocked")
		return
	_target_position = chunk_manager.get_cell_world_position(next_cell) + Vector2(0, -6)
	var offset: Vector2 = _target_position - global_position
	if offset.length() > move_speed * delta:
		global_position += offset.normalized() * move_speed * delta
		return
	global_position = _target_position
	current_cell = next_cell
	_path_index += 1
	if has_active_path():
		_target_position = chunk_manager.get_cell_world_position(_current_path[_path_index]) + Vector2(0, -6)
		return
	_complete_path_arrival()

func _get_current_path_options() -> Dictionary:
	return {
		"allow_target_construction": _activity == Activity.MOVING_TO_CONSTRUCTION,
		"allow_target_resource": _activity == Activity.MOVING_TO_HARVEST,
	}

func _fail_current_movement(reason: String) -> void:
	match _activity:
		Activity.MOVING_TO_CONSTRUCTION:
			_finish_construction_job(reason)
		Activity.MOVING_TO_HARVEST:
			_finish_harvest_job(reason)
		Activity.MOVING_TO_HAUL_ITEM, Activity.MOVING_TO_STOCKPILE:
			_finish_haul_job(reason)
		_:
			_enter_idle()

func _complete_path_arrival() -> void:
	_clear_path()
	current_cell = target_cell
	if _activity == Activity.MOVING_TO_CONSTRUCTION:
		var site: Dictionary = world_state.get_construction_site(_construction_site_id) if world_state != null else {}
		if site.is_empty() or bool(site.get("completed", false)):
			_finish_construction_job("site_invalid")
		else:
			_activity = Activity.CONSTRUCTING
	elif _activity == Activity.MOVING_TO_HARVEST:
		var order: Dictionary = world_state.get_harvest_order(_harvest_order_id) if world_state != null else {}
		if order.is_empty():
			_finish_harvest_job("order_invalid")
		else:
			_harvest_work_elapsed = 0.0
			_activity = Activity.HARVESTING
	elif _activity == Activity.MOVING_TO_HAUL_ITEM:
		var pickup: Dictionary = world_state.request_pickup_ground_item(_haul_item_id, colonist_id)
		if not bool(pickup.get("ok", false)):
			_finish_haul_job("pickup_%s" % String(pickup.get("reason", "failed")))
		else:
			_carried_item = pickup.get("item", {}).duplicate(true)
			_activity = Activity.CARRYING_ITEM
	elif _activity == Activity.MOVING_TO_STOCKPILE:
		_activity = Activity.DEPOSITING
	elif _activity == Activity.WANDERING:
		_enter_idle()

func _process_construction(delta: float) -> void:
	if world_state == null or _construction_site_id.is_empty():
		_finish_construction_job("missing_construction_context")
		return
	var site: Dictionary = world_state.get_construction_site(_construction_site_id)
	if site.is_empty() or bool(site.get("completed", false)):
		_finish_construction_job("site_invalid")
		return
	var result: Dictionary = world_state.request_progress_construction(_construction_site_id, get_effective_construction_work_rate() * delta, colonist_id)
	if not bool(result.get("ok", false)) or bool(result.get("completed", false)):
		_finish_construction_job("construction_completed" if bool(result.get("completed", false)) else "progress_%s" % String(result.get("reason", "failed")))

func _process_harvesting(delta: float) -> void:
	if world_state == null or _harvest_order_id.is_empty():
		_finish_harvest_job("missing_harvest_context")
		return
	if world_state.get_harvest_order_reservation(_harvest_order_id) != colonist_id:
		_finish_harvest_job("reservation_lost")
		return
	_harvest_work_elapsed += delta
	if _harvest_work_elapsed < harvest_work_duration:
		return
	var result: Dictionary = world_state.request_complete_harvest_order(_harvest_order_id, colonist_id)
	_finish_harvest_job("harvest_completed" if bool(result.get("ok", false)) else "harvest_%s" % String(result.get("reason", "failed")))

func _process_hauling() -> void:
	if world_state == null or _haul_item_id.is_empty():
		_finish_haul_job("missing_haul_context")
		return
	if _activity == Activity.CARRYING_ITEM:
		if _carried_item.is_empty():
			_finish_haul_job("missing_carried_item")
			return
		var deposit_path: Dictionary = _query_path(_haul_destination_cell)
		if not bool(deposit_path.get("reachable", false)):
			_finish_haul_job("stockpile_path_unreachable")
			return
		_apply_path(deposit_path, _haul_destination_cell)
		_haul_travel_elapsed = 0.0
		_activity = Activity.MOVING_TO_STOCKPILE
		return
	if _activity == Activity.DEPOSITING:
		var result: Dictionary = world_state.request_deposit_carried_item(colonist_id, _carried_item, _haul_destination_cell)
		_finish_haul_job("haul_deposited" if bool(result.get("ok", false)) else "deposit_%s" % String(result.get("reason", "failed")), bool(result.get("ok", false)))

func _pick_new_wander_target() -> void:
	for _attempt in range(12):
		var candidate: Vector2i = chunk_manager.get_random_walkable_cell_near(current_cell, wander_radius, 48)
		var path_result: Dictionary = _query_path(candidate)
		if not bool(path_result.get("reachable", false)):
			continue
		_apply_path(path_result, candidate)
		_activity = Activity.WANDERING
		return
	_enter_idle()

func _finish_construction_job(reason: String = "construction_abandoned") -> void:
	if world_state != null and not _construction_site_id.is_empty():
		world_state.release_construction_reservation(_construction_site_id, colonist_id, reason)
	_construction_site_id = ""
	_construction_travel_elapsed = 0.0
	_job_evaluation_cooldown_remaining = 0.0
	_enter_idle()

func _finish_harvest_job(reason: String = "harvest_abandoned") -> void:
	if world_state != null and not _harvest_order_id.is_empty():
		world_state.release_harvest_order(_harvest_order_id, colonist_id, reason)
	_harvest_order_id = ""
	_harvest_travel_elapsed = 0.0
	_harvest_work_elapsed = 0.0
	_job_evaluation_cooldown_remaining = 0.0
	_enter_idle()

func _finish_haul_job(reason: String = "haul_abandoned", deposited: bool = false) -> void:
	if world_state != null and not _haul_item_id.is_empty() and not deposited:
		if _carried_item.is_empty():
			world_state.release_haul_item(_haul_item_id, colonist_id, reason)
		else:
			var drop_result: Dictionary = world_state.request_drop_carried_item(_haul_item_id, colonist_id, current_cell, reason)
			if not bool(drop_result.get("ok", false)):
				world_state.release_haul_item(_haul_item_id, colonist_id, reason)
	_haul_item_id = ""
	_haul_destination_cell = Vector2i.ZERO
	_haul_travel_elapsed = 0.0
	_carried_item.clear()
	_job_evaluation_cooldown_remaining = 0.0
	_enter_idle()

func _enter_idle() -> void:
	_clear_path()
	target_cell = current_cell
	_target_position = global_position
	_activity = Activity.IDLE
	_pause_timer = _rng.randf_range(pause_duration_min, pause_duration_max)
