extends Control
class_name HaulConnectionOverlay

var colony_state: Node
var location_windows: Dictionary
var expedition_window: Control

## Presentation-only route projection. Endpoints come from window geometry while
## source, destination, phase, resource, and amount come from authoritative haul records.
func configure(state: Node, open_windows: Dictionary, expedition: Control) -> void:
	colony_state = state
	location_windows = open_windows
	expedition_window = expedition
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void: queue_redraw()


func _draw() -> void:
	if colony_state == null or expedition_window == null or not expedition_window.visible: return
	for haul: Dictionary in colony_state.get_haul_snapshots():
		var source_id := String(haul.source_location_id)
		if not location_windows.has(source_id): continue
		var source: Control = location_windows[source_id].window
		if not is_instance_valid(source) or not source.visible: continue
		var start := source.position + source.size * 0.5
		var finish := expedition_window.position + expedition_window.size * 0.5
		draw_line(start, finish, Color("#f4d35e"), 3.0)
		var progress := float(haul.phase_progress)
		var marker := start.lerp(finish, progress if String(haul.phase) == "TRAVELLING_TO_DESTINATION" else 1.0 - progress)
		draw_circle(marker, 6.0, Color("#8b5a2b"))
		draw_string(ThemeDB.fallback_font, marker + Vector2(9, -5), "%d %s" % [maxi(int(haul.reserved_amount), int(haul.carried_amount)), String(haul.resource_type).capitalize()], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
