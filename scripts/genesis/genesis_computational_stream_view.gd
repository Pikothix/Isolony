extends Control
class_name GenesisComputationalStreamView

## Bounded, non-interactive projection of Genesis computation. The controller
## supplies authorised semantic events; this view owns only flowing layout,
## transient anomaly anchoring, clipping, cadence, and visual emphasis.

const MAX_LINES := 36
const DEFAULT_SEED := 0x47454E45534953
const OPERATIONS: Array[String] = ["READ", "WRITE", "WAIT", "STACK", "SCHED"]
const ORDINARY_COLOR := Color(0.52, 0.58, 0.55, 0.78)
const IMPORTANT_COLOR := Color(0.82, 0.86, 0.83, 0.96)
const STABLE_COLOR := Color(0.95, 0.97, 0.95, 1.0)
const HEADER_HEIGHT := 28.0
const ANOMALY_BAND_HEIGHT := 46.0
const FLOW_LINE_HEIGHT := 22.0

enum Density {
	QUIET,
	ACTIVE,
	BUSY,
	SATURATED,
}

@onready var flowing_stream_layer: Control = %FlowingStreamLayer
@onready var flow_above: RichTextLabel = %FlowAbove
@onready var flow_below: RichTextLabel = %FlowBelow
@onready var anchored_anomaly_layer: Control = %AnchoredAnomalyLayer
@onready var anomaly_label: Label = %AnomalyLabel

var density: Density = Density.QUIET
var _events: Array[Dictionary] = []
var _anchored_anomaly: Dictionary = {}
var _pending_anomaly_sequence := -1
var _flow_entries_after_pending := 0
var _event_sequence := 0
var _rng := RandomNumberGenerator.new()
var _snapshot: Dictionary = {}
var _elapsed := 0.0
var _line_interval := 1.0
var _pause_remaining := 0.0
var _active := false
var _interface_mode := false
var _line_index := 0
var _anomaly_band_rect := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for flow_label: RichTextLabel in [flow_above, flow_below]:
		var scroll_bar := flow_label.get_v_scroll_bar()
		scroll_bar.modulate.a = 0.0
		scroll_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_layers()
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout_layers()


func _process(delta: float) -> void:
	if _pause_remaining > 0.0:
		_pause_remaining = maxf(0.0, _pause_remaining - delta)
		return
	_elapsed += delta
	var lines_this_frame := 0
	while _elapsed >= _line_interval and lines_this_frame < 4:
		_elapsed -= _line_interval
		_append_generated_event()
		lines_this_frame += 1


func activate(seed: int = DEFAULT_SEED) -> void:
	_rng.seed = seed
	_events.clear()
	_anchored_anomaly.clear()
	_pending_anomaly_sequence = -1
	_flow_entries_after_pending = 0
	_event_sequence = 0
	_snapshot = {}
	_elapsed = 0.0
	_pause_remaining = 0.0
	_line_index = 0
	_interface_mode = false
	_active = true
	visible = true
	anomaly_label.visible = false
	set_activity_snapshot({"worker_process_count": 0, "lifetime_cycles": 0, "cycles": 0})
	_layout_layers()


func stop(clear_buffer: bool = false) -> void:
	_active = false
	set_process(false)
	if clear_buffer:
		_events.clear()
		_anchored_anomaly.clear()
		_pending_anomaly_sequence = -1
		_flow_entries_after_pending = 0
	_layout_layers()


func is_running() -> bool:
	return _active and is_processing()


func set_activity_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	var workers := int(_snapshot.get("worker_process_count", 0))
	if workers <= 0:
		density = Density.QUIET
		_line_interval = 1.0
	elif workers <= 2:
		density = Density.ACTIVE
		_line_interval = 0.85 if workers == 1 else 0.55
	elif workers <= 4:
		density = Density.BUSY
		_line_interval = 0.25
	else:
		density = Density.SATURATED
		_line_interval = 0.08
	set_process(_active and (density != Density.QUIET or _interface_mode))


func append_computation_event(event: Dictionary) -> void:
	var text := String(event.get("text", ""))
	if text.is_empty():
		return
	_event_sequence += 1
	var normalized := {
		"category": String(event.get("category", "computation")),
		"stage": String(event.get("stage", "")),
		"text": text,
		"importance": clampi(int(event.get("importance", 0)), 0, 2),
		"sequence": _event_sequence,
	}
	if normalized.category == "consciousness":
		_append_consciousness_event(normalized)
	else:
		_events.append(normalized)
		if _pending_anomaly_sequence >= 0:
			_flow_entries_after_pending += 1
	var anchored_now := _maybe_anchor_pending_anomaly()
	anchored_now = _trim_flow_buffer() or anchored_now
	_pause_remaining = maxf(_pause_remaining, float(event.get("hold_seconds", 0.0)))
	if anchored_now:
		_layout_layers()
	else:
		_refresh_presentation()


func begin_interface_mode() -> void:
	_interface_mode = true
	density = Density.SATURATED
	_line_interval = 0.08
	set_process(_active)


func get_density_name() -> String:
	return Density.keys()[density]


func get_buffered_line_count() -> int:
	return _events.size()


func get_flowing_snapshot() -> Array[String]:
	var lines: Array[String] = []
	for event: Dictionary in _events:
		lines.append(String(event.text))
	return lines


func get_buffer_snapshot() -> Array[String]:
	var lines := get_flowing_snapshot()
	if not _anchored_anomaly.is_empty():
		lines.append(String(_anchored_anomaly.text))
	return lines


func get_event_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = _events.duplicate(true)
	if not _anchored_anomaly.is_empty():
		snapshot.append(_anchored_anomaly.duplicate(true))
	return snapshot


func is_consciousness_flowing() -> bool:
	return _pending_anomaly_sequence >= 0


func get_anchored_anomaly_text() -> String:
	return String(_anchored_anomaly.get("text", ""))


func get_anchored_anomaly_count() -> int:
	return 0 if _anchored_anomaly.is_empty() else 1


func get_anomaly_band_rect() -> Rect2:
	return _anomaly_band_rect


func get_flow_region_rects() -> Array[Rect2]:
	return [Rect2(flow_above.position, flow_above.size), Rect2(flow_below.position, flow_below.size)]


func generate_lines_for_validation(count: int) -> void:
	for unused_index in range(maxi(0, count)):
		_append_generated_event()


func advance_pending_anomaly_for_validation() -> void:
	while is_consciousness_flowing():
		_append_generated_event()


func _append_consciousness_event(event: Dictionary) -> void:
	if not _anchored_anomaly.is_empty():
		_anchored_anomaly = event
		return
	if _pending_anomaly_sequence >= 0:
		for index in range(_events.size()):
			if int(_events[index].sequence) == _pending_anomaly_sequence:
				_events[index] = event
				_pending_anomaly_sequence = int(event.sequence)
				return
	_events.append(event)
	_pending_anomaly_sequence = int(event.sequence)
	_flow_entries_after_pending = 0


func _maybe_anchor_pending_anomaly() -> bool:
	if _pending_anomaly_sequence < 0:
		return false
	var travel_distance := maxf(0.0, size.y - _anomaly_band_rect.end.y)
	var travel_steps := maxi(2, int(floor(travel_distance / FLOW_LINE_HEIGHT)))
	if _flow_entries_after_pending < travel_steps:
		return false
	for index in range(_events.size()):
		if int(_events[index].sequence) == _pending_anomaly_sequence:
			_anchored_anomaly = _events[index]
			_events.remove_at(index)
			break
	_pending_anomaly_sequence = -1
	_flow_entries_after_pending = 0
	return not _anchored_anomaly.is_empty()


func _trim_flow_buffer() -> bool:
	var anchored_removed_entry := false
	while _events.size() > MAX_LINES:
		var removed: Dictionary = _events.pop_front()
		if int(removed.sequence) == _pending_anomaly_sequence:
			_anchored_anomaly = removed
			_pending_anomaly_sequence = -1
			_flow_entries_after_pending = 0
			anchored_removed_entry = true
	return anchored_removed_entry


func _append_generated_event() -> void:
	_line_index += 1
	var lifetime := int(_snapshot.get("lifetime_cycles", 0))
	var workers := maxi(1, int(_snapshot.get("worker_process_count", 0)))
	var worker_index := ((_line_index - 1) % workers) + 1
	var operation: String = OPERATIONS[_rng.randi_range(0, OPERATIONS.size() - 1)]
	var text := ""
	match _line_index % 5:
		0:
			text = "CYCLE %06d" % (lifetime + _line_index)
		1:
			text = "PROC WORKER_%03d %s %02X" % [worker_index, operation, _rng.randi_range(0, 255)]
		2:
			text = "MEM %02X WRITE" % _rng.randi_range(0, 255)
		3:
			text = "SCHED QUEUE %02d" % worker_index
		_:
			text = "STACK %02X %02X" % [_rng.randi_range(0, 255), _rng.randi_range(0, 255)]
	append_computation_event({"category": "ambient", "text": text, "importance": 0})


func _layout_layers() -> void:
	var content_height := maxf(0.0, size.y - HEADER_HEIGHT)
	var center_y := HEADER_HEIGHT + content_height * 0.5
	var band_top := clampf(
		center_y - ANOMALY_BAND_HEIGHT * 0.5,
		HEADER_HEIGHT,
		maxf(HEADER_HEIGHT, size.y - ANOMALY_BAND_HEIGHT)
	)
	var band_bottom := minf(size.y, band_top + ANOMALY_BAND_HEIGHT)
	_anomaly_band_rect = Rect2(0.0, band_top, size.x, band_bottom - band_top)
	if _anchored_anomaly.is_empty():
		flow_above.position = Vector2(0.0, HEADER_HEIGHT)
		flow_above.size = Vector2(size.x, 0.0)
		flow_below.position = Vector2(0.0, HEADER_HEIGHT)
		flow_below.size = Vector2(size.x, content_height)
	else:
		flow_above.position = Vector2(0.0, HEADER_HEIGHT)
		flow_above.size = Vector2(size.x, maxf(0.0, band_top - HEADER_HEIGHT))
		flow_below.position = Vector2(0.0, band_bottom)
		flow_below.size = Vector2(size.x, maxf(0.0, size.y - band_bottom))
	anomaly_label.position = _anomaly_band_rect.position
	anomaly_label.size = _anomaly_band_rect.size
	if _maybe_anchor_pending_anomaly():
		_layout_layers()
		return
	_refresh_presentation()


func _refresh_presentation() -> void:
	if not is_instance_valid(flow_above):
		return
	var above_capacity := _flow_capacity(flow_above)
	var below_capacity := _flow_capacity(flow_below)
	var total_capacity := above_capacity + below_capacity
	var start_index := maxi(0, _events.size() - total_capacity)
	var visible_events: Array[Dictionary] = _events.slice(start_index)
	var below_start := maxi(0, visible_events.size() - below_capacity)
	var above_events: Array[Dictionary] = visible_events.slice(0, below_start)
	var below_events: Array[Dictionary] = visible_events.slice(below_start)
	_render_flow_region(flow_above, above_events, above_capacity)
	_render_flow_region(flow_below, below_events, below_capacity)
	anomaly_label.visible = not _anchored_anomaly.is_empty()
	if anomaly_label.visible:
		anomaly_label.text = String(_anchored_anomaly.text)
		anomaly_label.modulate = _color_for_importance(int(_anchored_anomaly.importance))
	else:
		anomaly_label.text = ""


func _render_flow_region(label: RichTextLabel, events: Array[Dictionary], capacity: int) -> void:
	label.clear()
	for unused_line in range(maxi(0, capacity - events.size())):
		label.newline()
	for event: Dictionary in events:
		label.push_color(_color_for_importance(int(event.importance)))
		label.add_text(String(event.text))
		label.pop()
		label.newline()
	call_deferred("_scroll_flow_to_latest", label)


func _scroll_flow_to_latest(label: RichTextLabel) -> void:
	if is_instance_valid(label):
		label.scroll_to_line(maxi(0, label.get_line_count() - 1))


func _flow_capacity(label: RichTextLabel) -> int:
	return maxi(1, int(floor(label.size.y / FLOW_LINE_HEIGHT)))


func _color_for_importance(importance: int) -> Color:
	if importance >= 2:
		return STABLE_COLOR
	if importance == 1:
		return IMPORTANT_COLOR
	return ORDINARY_COLOR
