extends RefCounted
class_name ScoutingCoordinator

const VALID_SEARCH_TYPES := ["woodland", "rocky", "forage_rich", "general"]
var _records: Dictionary = {}

## Owns authoritative scouting records and progress. Location generation remains
## owned by LocationRegistry and colonist presence changes are requested by state.
func begin(colonist: Dictionary, origin_id: String, search_type: String, sequence: int, game_seed: int) -> Dictionary:
	var id := String(colonist.get("colonist_id", ""))
	if id.is_empty() or _records.has(id): return _result(false, "scout_unavailable")
	if search_type not in VALID_SEARCH_TYPES: return _result(false, "invalid_search_type")
	var skill_name := "Mining" if search_type == "rocky" else "Plants"
	var skill := clampf(float(colonist.get("skills", {}).get(skill_name, 0)), 0.0, 20.0)
	var ranges := {"general": Vector2(60, 22), "woodland": Vector2(55, 20), "rocky": Vector2(55, 20), "forage_rich": Vector2(50, 18)}
	var duration := lerpf(ranges[search_type].x, ranges[search_type].y, skill / 20.0)
	var seed: int = absi(hash("%d:scout:%d:%s:%s" % [game_seed, sequence, origin_id, search_type]))
	_records[id] = {"colonist_id": id, "origin_location_id": origin_id, "search_type": search_type, "sequence": sequence, "discovery_seed": seed, "duration": duration, "elapsed": 0.0}
	return {"ok": true, "reason": "scouting_started", "record": _records[id].duplicate(true)}

func advance(delta: float) -> Array[Dictionary]:
	var completed: Array[Dictionary] = []
	for id: String in _records.keys():
		_records[id].elapsed = minf(float(_records[id].duration), float(_records[id].elapsed) + delta)
		if float(_records[id].elapsed) >= float(_records[id].duration): completed.append(_records[id].duplicate(true))
	return completed
func finish(colonist_id: String) -> void: _records.erase(colonist_id)
func cancel(colonist_id: String) -> Dictionary:
	if not _records.has(colonist_id): return _result(false, "not_scouting")
	var record: Dictionary = _records[colonist_id]; _records.erase(colonist_id); return {"ok": true, "reason": "scouting_cancelled", "record": record}
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
