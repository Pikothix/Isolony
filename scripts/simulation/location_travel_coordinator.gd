extends RefCounted
class_name LocationTravelCoordinator

const SECONDS_PER_DISTANCE_UNIT := 10.0
const MIN_DURATION := 25.0
const MAX_DURATION := 90.0
var _records: Dictionary = {}

## Owns authoritative abstract travel records and progress. Presence mutation and
## deterministic entry placement are committed by WindowedColonyState.
func begin(colonist_id: String, origin_id: String, destination_id: String, origin: Vector2i, destination: Vector2i, departure_time: float) -> Dictionary:
	if _records.has(colonist_id): return _result(false, "already_travelling")
	var distance := Vector2(origin).distance_to(Vector2(destination))
	if distance <= 0.0: return _result(false, "invalid_route")
	var duration := clampf(distance * SECONDS_PER_DISTANCE_UNIT, MIN_DURATION, MAX_DURATION)
	_records[colonist_id] = {"colonist_id": colonist_id, "origin_location_id": origin_id, "destination_location_id": destination_id, "route_distance": distance, "travel_duration": duration, "travel_elapsed": 0.0, "departure_time": departure_time}
	return {"ok": true, "reason": "travel_started", "record": snapshot(colonist_id)}
func advance(delta: float) -> Array[Dictionary]:
	var completed: Array[Dictionary] = []
	for id: String in _records.keys():
		_records[id].travel_elapsed = minf(float(_records[id].travel_duration), float(_records[id].travel_elapsed) + delta)
		if float(_records[id].travel_elapsed) >= float(_records[id].travel_duration): completed.append(snapshot(id))
	return completed
func finish(colonist_id: String) -> void: _records.erase(colonist_id)
func has(colonist_id: String) -> bool: return _records.has(colonist_id)
func snapshot(colonist_id: String) -> Dictionary: return _records.get(colonist_id, {}).duplicate(true)
func snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _records.keys(): result.append(snapshot(id))
	result.sort_custom(func(a, b): return String(a.colonist_id) < String(b.colonist_id))
	return result
func import_records(records: Array) -> void:
	_records.clear()
	for raw: Dictionary in records: _records[String(raw.colonist_id)] = raw.duplicate(true)
func _result(ok: bool, reason: String) -> Dictionary: return {"ok": ok, "reason": reason}
