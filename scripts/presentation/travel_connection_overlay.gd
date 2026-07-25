extends Control
class_name TravelConnectionOverlay

var colony_state: Node
var location_windows: Dictionary

## Presentation-only projection. Authoritative progress comes from travel records;
## window geometry is used only to draw currently visible endpoints.
func configure(state: Node, open_windows: Dictionary) -> void:
	colony_state = state; location_windows = open_windows; mouse_filter = Control.MOUSE_FILTER_IGNORE; set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func _process(_delta: float) -> void: queue_redraw()
func _draw() -> void:
	if colony_state == null: return
	for travel: Dictionary in colony_state.get_travel_snapshots():
		var origin_id := String(travel.origin_location_id); var destination_id := String(travel.destination_location_id)
		if not location_windows.has(origin_id) or not location_windows.has(destination_id): continue
		var origin: Control = location_windows[origin_id].window; var destination: Control = location_windows[destination_id].window
		if not is_instance_valid(origin) or not is_instance_valid(destination) or not origin.visible or not destination.visible: continue
		var start := origin.position + origin.size * 0.5; var finish := destination.position + destination.size * 0.5
		draw_line(start, finish, Color("#f4d35e"), 3.0)
		var progress := clampf(float(travel.travel_elapsed) / maxf(float(travel.travel_duration), 0.001), 0.0, 1.0); var marker := start.lerp(finish, progress)
		draw_circle(marker, 6.0, Color("#4ab0a4")); draw_string(ThemeDB.fallback_font, marker + Vector2(9, -5), String(travel.colonist_id), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
