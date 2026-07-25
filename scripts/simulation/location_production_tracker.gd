extends RefCounted
class_name LocationProductionTracker

const WINDOW_SECONDS := 60.0
const MAX_EVENTS_PER_LOCATION := 256
const RESOURCE_TYPES := ["wood", "stone", "food"]

var _events_by_location: Dictionary = {}

## Owns bounded, transient observations of completed authoritative gathering.
## It never mutates resources and is deliberately excluded from persistence.
func record_production(location_id: String, resource_type: String, amount: int, simulation_time: float) -> Dictionary:
	if location_id.is_empty() or resource_type not in RESOURCE_TYPES or amount <= 0 or simulation_time < 0.0:
		return {"ok": false, "reason": "invalid_production_event"}
	_prune_location(location_id, simulation_time)
	if not _events_by_location.has(location_id):
		_events_by_location[location_id] = []
	var events: Array = _events_by_location[location_id]
	events.append({
		"location_id": location_id,
		"resource_type": resource_type,
		"amount": amount,
		"simulation_time": simulation_time,
	})
	while events.size() > MAX_EVENTS_PER_LOCATION:
		events.pop_front()
	return {"ok": true, "reason": "production_recorded"}


func get_recent_amounts(location_id: String, simulation_time: float) -> Dictionary:
	_prune_location(location_id, simulation_time)
	var amounts := {"wood": 0, "stone": 0, "food": 0}
	for event: Dictionary in _events_by_location.get(location_id, []):
		amounts[String(event.resource_type)] += int(event.amount)
	return amounts.duplicate(true)


func get_recent_events(location_id: String, simulation_time: float) -> Array[Dictionary]:
	_prune_location(location_id, simulation_time)
	var result: Array[Dictionary] = []
	for event: Dictionary in _events_by_location.get(location_id, []):
		result.append(event.duplicate(true))
	return result


func clear() -> void:
	_events_by_location.clear()


func _prune_location(location_id: String, simulation_time: float) -> void:
	if not _events_by_location.has(location_id):
		return
	var cutoff := simulation_time - WINDOW_SECONDS
	var retained: Array = []
	for event: Dictionary in _events_by_location[location_id]:
		if float(event.simulation_time) >= cutoff and float(event.simulation_time) <= simulation_time:
			retained.append(event)
	if retained.is_empty():
		_events_by_location.erase(location_id)
	else:
		_events_by_location[location_id] = retained
