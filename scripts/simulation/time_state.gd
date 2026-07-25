extends Node
class_name TimeState

signal time_changed(day: int, hour: int, minute: int)
signal day_started(day: int)
signal night_started(day: int)
signal day_phase_changed(is_daytime: bool)
signal speed_mode_changed(mode: String, time_scale: float)

const MINUTES_PER_DAY := 1440.0
const DAY_START_HOUR := 6
const NIGHT_START_HOUR := 18
const SPEED_MODE_PAUSE := "pause"
const SPEED_MODE_NORMAL := "normal"
const SPEED_MODE_FAST := "fast"
const SPEED_MODE_FASTER := "faster"
const SPEED_SCALES := {
	SPEED_MODE_PAUSE: 0.0,
	SPEED_MODE_NORMAL: 1.0,
	SPEED_MODE_FAST: 3.0,
	SPEED_MODE_FASTER: 6.0,
}

@export_range(1.0, 240.0, 1.0) var day_length_minutes: float = 12.0
@export_range(0.0, 32.0, 0.1) var time_scale: float = 1.0
@export var paused: bool = false

var current_day: int = 1
var current_minutes: float = float(DAY_START_HOUR * 60)
var _last_emitted_day: int = current_day
var _last_emitted_minute: int = -1
var _last_is_day: bool = true
var _speed_mode: String = SPEED_MODE_NORMAL
var _previous_non_paused_speed_mode: String = SPEED_MODE_NORMAL

## Purpose: Owns simulation time and day/night phase.
## Responsibility: Advance time, expose read APIs, and notify presentation listeners about clock/phase changes.
## Assumption: Seasons, schedules, weather, and lighting authority are out of scope for this milestone.
func _ready() -> void:
	_last_is_day = is_day()
	_emit_time_if_changed(true)

func advance(delta: float) -> void:
	if paused or delta <= 0.0 or time_scale <= 0.0:
		return
	var minutes_per_second: float = MINUTES_PER_DAY / maxf(day_length_minutes * 60.0, 0.001)
	current_minutes += delta * minutes_per_second * time_scale
	while current_minutes >= MINUTES_PER_DAY:
		current_minutes -= MINUTES_PER_DAY
		current_day += 1
		day_started.emit(current_day)
	_emit_time_if_changed(false)

func set_paused(value: bool) -> void:
	if value:
		set_speed_mode(SPEED_MODE_PAUSE)
	else:
		set_speed_mode(_previous_non_paused_speed_mode)

func set_time_scale(value: float) -> void:
	set_speed_mode(_get_mode_for_scale(value))

func set_speed_mode(mode: String) -> Dictionary:
	var normalized_mode := mode.strip_edges().to_lower()
	if not SPEED_SCALES.has(normalized_mode):
		return {"ok": false, "reason": "unknown_speed_mode", "mode": normalized_mode, "time_scale": get_time_scale()}
	if normalized_mode == SPEED_MODE_PAUSE:
		if _speed_mode != SPEED_MODE_PAUSE:
			_previous_non_paused_speed_mode = _speed_mode
		_speed_mode = SPEED_MODE_PAUSE
		paused = true
		time_scale = 0.0
	else:
		_speed_mode = normalized_mode
		_previous_non_paused_speed_mode = normalized_mode
		paused = false
		time_scale = float(SPEED_SCALES[normalized_mode])
	speed_mode_changed.emit(_speed_mode, time_scale)
	return {"ok": true, "reason": "set", "mode": _speed_mode, "time_scale": time_scale}

func toggle_pause() -> Dictionary:
	return set_speed_mode(_previous_non_paused_speed_mode if is_paused() else SPEED_MODE_PAUSE)

func get_speed_mode() -> String:
	return _speed_mode

func get_time_scale() -> float:
	return time_scale

func is_paused() -> bool:
	return paused

func get_day() -> int:
	return current_day

func get_hour() -> int:
	return int(floor(current_minutes / 60.0)) % 24

func get_minute() -> int:
	return int(floor(current_minutes)) % 60

func get_time_label() -> String:
	return "Day %d %02d:%02d" % [get_day(), get_hour(), get_minute()]


func debug_set_time_of_day(hour: int, minute: int = 0) -> Dictionary:
	## Debug clock teleport only: this does not simulate elapsed time or advance colonist work, needs, or jobs.
	if hour < 0 or hour >= 24:
		return {"ok": false, "reason": "invalid_hour", "hour": hour, "minute": minute}
	if minute < 0 or minute >= 60:
		return {"ok": false, "reason": "invalid_minute", "hour": hour, "minute": minute}
	current_minutes = float(hour * 60 + minute)
	_emit_time_if_changed(true)
	return {"ok": true, "reason": "debug_time_set", "day": current_day, "hour": hour, "minute": minute}

func is_day() -> bool:
	var hour: int = get_hour()
	return hour >= DAY_START_HOUR and hour < NIGHT_START_HOUR

func is_night() -> bool:
	return not is_day()

func export_state() -> Dictionary:
	return {
		"current_day": current_day,
		"current_minutes": current_minutes,
		"day_length_minutes": day_length_minutes,
		"time_scale": time_scale,
		"paused": paused,
		"speed_mode": _speed_mode,
		"previous_non_paused_speed_mode": _previous_non_paused_speed_mode,
	}

func import_state(state: Dictionary) -> Dictionary:
	current_day = maxi(1, int(state.get("current_day", current_day)))
	current_minutes = clampf(float(state.get("current_minutes", current_minutes)), 0.0, MINUTES_PER_DAY - 0.001)
	day_length_minutes = maxf(1.0, float(state.get("day_length_minutes", day_length_minutes)))
	var imported_mode := String(state.get("speed_mode", ""))
	if SPEED_SCALES.has(imported_mode):
		_previous_non_paused_speed_mode = String(state.get("previous_non_paused_speed_mode", SPEED_MODE_NORMAL))
		if not SPEED_SCALES.has(_previous_non_paused_speed_mode) or _previous_non_paused_speed_mode == SPEED_MODE_PAUSE:
			_previous_non_paused_speed_mode = SPEED_MODE_NORMAL
		set_speed_mode(imported_mode)
	else:
		var imported_scale := maxf(0.0, float(state.get("time_scale", time_scale)))
		_previous_non_paused_speed_mode = _get_mode_for_scale(imported_scale)
		set_speed_mode(SPEED_MODE_PAUSE if bool(state.get("paused", paused)) else _previous_non_paused_speed_mode)
	_last_emitted_day = -1
	_last_emitted_minute = -1
	_last_is_day = not is_day()
	_emit_time_if_changed(true)
	return {
		"ok": true,
		"reason": "imported",
	}

func _get_mode_for_scale(scale: float) -> String:
	var non_negative_scale := maxf(scale, 0.0)
	if non_negative_scale <= 0.0:
		return SPEED_MODE_PAUSE
	var closest_mode := SPEED_MODE_NORMAL
	var closest_distance := INF
	for mode_value: Variant in [SPEED_MODE_NORMAL, SPEED_MODE_FAST, SPEED_MODE_FASTER]:
		var candidate_mode: String = mode_value
		var distance := absf(non_negative_scale - float(SPEED_SCALES[candidate_mode]))
		if distance < closest_distance:
			closest_distance = distance
			closest_mode = candidate_mode
	return closest_mode

func _emit_time_if_changed(force: bool) -> void:
	var current_total_minute: int = int(floor(current_minutes))
	if force or current_day != _last_emitted_day or current_total_minute != _last_emitted_minute:
		_last_emitted_day = current_day
		_last_emitted_minute = current_total_minute
		time_changed.emit(current_day, get_hour(), get_minute())
	var currently_day: bool = is_day()
	if force or currently_day != _last_is_day:
		_last_is_day = currently_day
		day_phase_changed.emit(currently_day)
		if currently_day:
			day_started.emit(current_day)
		else:
			night_started.emit(current_day)
