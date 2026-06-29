extends Node
class_name TimeState

signal time_changed(day: int, hour: int, minute: int)
signal day_started(day: int)
signal night_started(day: int)
signal day_phase_changed(is_daytime: bool)

const MINUTES_PER_DAY := 1440.0
const DAY_START_HOUR := 6
const NIGHT_START_HOUR := 18

@export_range(1.0, 240.0, 1.0) var day_length_minutes: float = 12.0
@export_range(0.0, 32.0, 0.1) var time_scale: float = 1.0
@export var paused: bool = false

var current_day: int = 1
var current_minutes: float = float(DAY_START_HOUR * 60)
var _last_emitted_day: int = current_day
var _last_emitted_minute: int = -1
var _last_is_day: bool = true

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
	paused = value

func set_time_scale(value: float) -> void:
	time_scale = maxf(value, 0.0)

func get_day() -> int:
	return current_day

func get_hour() -> int:
	return int(floor(current_minutes / 60.0)) % 24

func get_minute() -> int:
	return int(floor(current_minutes)) % 60

func get_time_label() -> String:
	return "Day %d %02d:%02d" % [get_day(), get_hour(), get_minute()]

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
	}

func import_state(state: Dictionary) -> Dictionary:
	current_day = maxi(1, int(state.get("current_day", current_day)))
	current_minutes = clampf(float(state.get("current_minutes", current_minutes)), 0.0, MINUTES_PER_DAY - 0.001)
	day_length_minutes = maxf(1.0, float(state.get("day_length_minutes", day_length_minutes)))
	time_scale = maxf(0.0, float(state.get("time_scale", time_scale)))
	paused = bool(state.get("paused", paused))
	_last_emitted_day = -1
	_last_emitted_minute = -1
	_last_is_day = not is_day()
	_emit_time_if_changed(true)
	return {
		"ok": true,
		"reason": "imported",
	}

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
