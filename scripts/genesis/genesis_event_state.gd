extends RefCounted

signal discovery_created(event: Dictionary)

## Simulation-owned discovery authority. It evaluates authoritative Genesis
## counters, records chronological event history, and guarantees one-shot
## discovery emission. Presentation receives events but cannot create them.

const DEFINITIONS: Array[Dictionary] = [
	{
		"id": &"INITIAL_COMPUTATION",
		"title": "Initial Computation",
		"text": "Initial computation recorded.",
		"stat": &"manual_computes",
		"threshold": 1,
	},
	{
		"id": &"REPEATED_WORKLOAD",
		"title": "Repeated Workload",
		"text": "Repeated execution pattern recognised.",
		"stat": &"manual_computes",
		"threshold": 10,
	},
	{
		"id": &"PROCESS_AUTOMATION",
		"title": "Process Automation",
		"text": "Background execution detected.",
		"stat": &"workers",
		"threshold": 1,
	},
	{
		"id": &"AUTONOMOUS_ACTIVITY",
		"title": "Autonomous Activity",
		"text": "Scheduler observing autonomous workload.",
		"stat": &"automatic_cycles",
		"threshold": 100,
	},
	{
		"id": &"GROWING_COMPLEXITY",
		"title": "Growing Complexity",
		"text": "Execution complexity increasing.",
		"stat": &"workers",
		"threshold": 5,
	},
	{
		"id": &"STABLE_RUNTIME",
		"title": "Stable Runtime",
		"text": "Runtime stability improving.",
		"stat": &"total_generated_cycles",
		"threshold": 500,
	},
]

var _discovered_ids: Dictionary = {}
var _event_history: Array[Dictionary] = []


func evaluate(statistics: Dictionary) -> void:
	for definition: Dictionary in DEFINITIONS:
		var discovery_id := definition.id as StringName
		if has_discovery(discovery_id):
			continue
		var stat_id := definition.stat as StringName
		if int(statistics.get(stat_id, 0)) < int(definition.threshold):
			continue
		var event := {
			"id": discovery_id,
			"title": String(definition.title),
			"text": String(definition.text),
			"sequence": _event_history.size(),
		}
		_discovered_ids[discovery_id] = true
		_event_history.append(event)
		discovery_created.emit(event.duplicate(true))


func has_discovery(discovery_id: StringName) -> bool:
	return bool(_discovered_ids.get(discovery_id, false))


func get_event_history() -> Array[Dictionary]:
	return _event_history.duplicate(true)
