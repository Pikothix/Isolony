extends Control

const DesktopWindowScript = preload("res://scripts/desktop/desktop_window.gd")
const LocationViewScript = preload("res://scripts/presentation/job_location_view.gd")
const StateScript = preload("res://scripts/simulation/windowed_colony_state.gd")
const TravelOverlayScript = preload("res://scripts/presentation/travel_connection_overlay.gd")
const COLONIST_TEXTURE = preload("res://assets/COLONIST.png")

@onready var colony_state: WindowedColonyState = $WindowedColonyState
@onready var desktop: Control = $Desktop
@onready var window_layer: Control = $Desktop/WindowLayer
@onready var desktop_shell: DesktopShell = $Desktop/DesktopShell
var _menu: Control
var _windows: Array[Control] = []
var _colonist_widgets: Dictionary = {}
var _location_widget: Dictionary = {}
var _location_widgets: Dictionary = {}
var _locations_list: VBoxContainer
var _selected_colonist_id := ""
var _feedback: Label
var _active_construction_tool := ""
var _construction_tool_buttons: Dictionary = {}
var _construction_feedback_labels: Dictionary = {}
var _building_inspector_widgets: Dictionary = {}
var _production_summary_labels: Dictionary = {}

## Presentation coordinator only: builds windows and submits validated requests.
func _ready() -> void:
	desktop_shell.save_game_requested.connect(_save_game)
	desktop_shell.load_game_requested.connect(_load_game)
	desktop_shell.new_game_requested.connect(_new_game)
	desktop_shell.exit_requested.connect(_request_exit)
	desktop_shell.window_focus_requested.connect(_focus_window)
	desktop_shell.window_minimise_requested.connect(_minimise_window)
	colony_state.simulation_time_changed.connect(_on_simulation_time_changed)
	desktop_shell.set_load_available(colony_state.has_valid_save())
	_build_time_controls(); _refresh_simulation_clock(); colony_state.game_replaced.connect(_rebuild_gameplay); colony_state.state_changed.connect(_refresh); colony_state.discovery_completed.connect(_show_discovery_result); _show_main_menu()

func _show_main_menu() -> void:
	desktop.visible = false
	if _menu != null: _menu.queue_free()
	_menu = CenterContainer.new(); _menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(_menu)
	var panel := PanelContainer.new(); panel.custom_minimum_size = Vector2(360, 250); _menu.add_child(panel)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 10); panel.add_child(box)
	var title := Label.new(); title.text = "ISO COLONY"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size", 28); box.add_child(title)
	for entry: Array in [["New Game", _new_game], ["Load Game", _load_game], ["Quit", _request_exit]]:
		var button := Button.new(); button.text = entry[0]; button.custom_minimum_size.y = 42; button.pressed.connect(entry[1]); box.add_child(button)
		if entry[0] == "Load Game": button.disabled = not colony_state.has_valid_save()
	_feedback = Label.new(); _feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(_feedback)

func _new_game() -> void:
	var result := colony_state.request_new_game()
	if not bool(result.ok) and is_instance_valid(_feedback): _feedback.text = "New Game failed: " + String(result.reason)
func _load_game() -> void:
	var result := colony_state.request_load_game()
	if not bool(result.ok) and is_instance_valid(_feedback): _feedback.text = "Load failed: " + String(result.reason).replace("_", " ")

func _save_game() -> void:
	var result := colony_state.request_save_game()
	if bool(result.ok): desktop_shell.set_load_available(true)

func _request_exit() -> void:
	get_tree().quit()

func _rebuild_gameplay() -> void:
	if _menu != null: _menu.queue_free(); _menu = null
	desktop.visible = true
	desktop_shell.close_start_menu(); desktop_shell.clear_windows()
	for window: Control in _windows: if is_instance_valid(window): window.queue_free()
	_windows.clear(); _colonist_widgets.clear(); _location_widget.clear(); _location_widgets.clear(); _building_inspector_widgets.clear(); _construction_tool_buttons.clear(); _construction_feedback_labels.clear(); _production_summary_labels.clear(); _active_construction_tool = ""
	desktop_shell.set_load_available(colony_state.has_valid_save())
	var ids := colony_state.get_colonist_ids()
	for i in ids.size(): _build_colonist_window(ids[i], Vector2(20 + i * 285, 20))
	_open_location(StateScript.LOCATION_ID); _build_locations_window(); var overlay := TravelOverlayScript.new(); overlay.configure(colony_state, _location_widgets); window_layer.add_child(overlay); window_layer.move_child(overlay, 0); _refresh()

func _build_time_controls() -> void:
	var time_buttons := desktop_shell.get_time_button_container()
	var label := Label.new(); label.text = "Time:"; time_buttons.add_child(label)
	for entry: Array in [["Pause", 0.0], ["1x", 1.0], ["2x", 2.0], ["4x", 4.0]]:
		var button := Button.new(); button.text = entry[0]; button.pressed.connect(func() -> void: desktop_shell.close_start_menu(); colony_state.request_set_time_scale(float(entry[1]))); time_buttons.add_child(button)

func _on_simulation_time_changed(day: int, hour: int, minute: int) -> void:
	desktop_shell.set_simulation_clock(day, hour, minute)
	for location_id: String in _location_widgets:
		_refresh_location_production(location_id)

func _refresh_simulation_clock() -> void:
	var clock := colony_state.get_simulation_clock()
	_on_simulation_time_changed(int(clock.day), int(clock.hour), int(clock.minute))

func _build_colonist_window(id: String, position_value: Vector2) -> void:
	var c := colony_state.get_colonist_snapshot(id); var window := _create_window(String(c.display_name), position_value, Vector2(270, 390), false)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 5); window.get_content_container().add_child(box)
	var portrait := TextureRect.new(); portrait.texture = COLONIST_TEXTURE; portrait.custom_minimum_size = Vector2(64, 64); portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; box.add_child(portrait)
	var facts := Label.new(); facts.text = "Plants %d   Mining %d   Construction %d\nTraits: %s" % [c.skills.Plants, c.skills.Mining, c.skills.get("Construction", 0), ", ".join(c.traits)]; facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(facts)
	var status := Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; status.custom_minimum_size.y = 95; box.add_child(status)
	var roles := GridContainer.new(); roles.columns = 2; box.add_child(roles)
	for entry: Array in [["Woodcutting", StateScript.ROLE_WOOD], ["Mining", StateScript.ROLE_MINING], ["Foraging", StateScript.ROLE_FORAGE], ["Hauling", StateScript.ROLE_HAUL], ["Construction", StateScript.ROLE_CONSTRUCTION], ["Unassigned", StateScript.ROLE_NONE]]:
		var button := Button.new(); button.text = entry[0]; button.pressed.connect(func() -> void: colony_state.request_set_colonist_role(id, String(entry[1]))); roles.add_child(button)
	var scout := MenuButton.new(); scout.text = "Scout"
	for entry: Array in [["Woodland", "woodland"], ["Rocky Area", "rocky"], ["Forage-Rich", "forage_rich"], ["General Area", "general"]]:
		scout.get_popup().add_item(entry[0]); scout.get_popup().set_item_metadata(scout.get_popup().item_count - 1, entry[1])
	scout.get_popup().id_pressed.connect(func(index: int) -> void: colony_state.request_start_scouting(id, String(scout.get_popup().get_item_metadata(index))))
	roles.add_child(scout)
	var go_to := Button.new(); go_to.text = "Go To..."; go_to.pressed.connect(func() -> void: _selected_colonist_id = id; _refresh()); roles.add_child(go_to)
	var home := Button.new(); home.text = "Return Home"; home.pressed.connect(func() -> void: colony_state.request_return_colonist_home(id)); roles.add_child(home)
	_colonist_widgets[id] = {"status": status, "roles": roles}

func _open_location(location_id: String) -> void:
	if _location_widgets.has(location_id): _focus_window(_location_widgets[location_id].window); return
	var location := colony_state.get_location_snapshot(location_id); if location.is_empty(): return
	var window := _create_window(String(location.display_name), Vector2(300 + _location_widgets.size() * 35, 360 + _location_widgets.size() * 25), Vector2(700, 520), location_id != StateScript.LOCATION_ID)
	var box := VBoxContainer.new(); window.get_content_container().add_child(box)
	var heading := Label.new(); heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(heading)
	var settle := Button.new(); settle.text = "Settle Here"; settle.visible = location_id == StateScript.LOCATION_ID; settle.pressed.connect(func() -> void: colony_state.request_settle_starting_location()); box.add_child(settle)
	var view: Control
	var claim := Button.new(); claim.text = "Claim Location"; claim.pressed.connect(func() -> void: var l := colony_state.get_location_snapshot(location_id); if not l.colonist_presence_ids.is_empty(): colony_state.request_claim_location(String(l.colonist_presence_ids[0]), location_id)); box.add_child(claim)
	var build := Button.new(); build.text = "Build Supply Cache"; build.pressed.connect(func() -> void: _set_active_construction_tool(""); view.begin_supply_cache_placement()); box.add_child(build)
	var workspace := HBoxContainer.new(); workspace.add_theme_constant_override("separation", 6); workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL; box.add_child(workspace)
	var navigation := _build_location_navigation(location_id); workspace.add_child(navigation)
	var inset := PanelContainer.new(); inset.theme_type_variation = "InsetPanel"; inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL; inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(inset)
	view = LocationViewScript.new(); view.configure(colony_state, location_id, Callable(self, "get_active_construction_tool")); view.size_flags_horizontal = Control.SIZE_EXPAND_FILL; view.size_flags_vertical = Control.SIZE_EXPAND_FILL; view.construction_feedback.connect(_on_construction_feedback.bind(location_id)); view.building_inspection_requested.connect(_open_building_inspector); inset.add_child(view)
	_location_widgets[location_id] = {"heading": heading, "settle": settle, "claim": claim, "build": build, "view": view, "window": window, "navigation": navigation, "expanded_section": "", "section_buttons": navigation.get_meta("section_buttons"), "section_contents": navigation.get_meta("section_contents")}; if location_id == StateScript.LOCATION_ID: _location_widget = _location_widgets[location_id]
	window.focus_requested.connect(func(_w: Control) -> void: if not _selected_colonist_id.is_empty(): colony_state.request_send_colonist_to_location(_selected_colonist_id, location_id); _selected_colonist_id = "")
	_refresh()

func _build_locations_window() -> void:
	var window := _create_window("Known Locations", Vector2(880, 20), Vector2(500, 520), false); var scroll := ScrollContainer.new(); window.get_content_container().add_child(scroll); _locations_list = VBoxContainer.new(); _locations_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(_locations_list)

## Builds presentation-owned accordion navigation for one location window.
## Section state is local to the window; tool actions keep using the existing
## authoritative state and location-view request paths.
func _build_location_navigation(location_id: String) -> VBoxContainer:
	var navigation := VBoxContainer.new(); navigation.name = "LocationNavigation"; navigation.custom_minimum_size.x = 180; navigation.add_theme_constant_override("separation", 2)
	var section_buttons: Dictionary = {}
	var section_contents: Dictionary = {}
	for section_name: String in ["Production", "Construction", "Buildings", "Colonists", "Storage"]:
		var section_key := section_name.to_lower()
		var section_button := Button.new(); section_button.name = "%sSectionButton" % section_name; section_button.text = "\u25b6 %s" % section_name; section_button.alignment = HORIZONTAL_ALIGNMENT_LEFT; section_button.pressed.connect(_set_location_section.bind(location_id, section_key)); navigation.add_child(section_button); section_buttons[section_key] = section_button
		var margin := MarginContainer.new(); margin.name = "%sSectionContent" % section_name; margin.add_theme_constant_override("margin_left", 12); margin.visible = false; navigation.add_child(margin); section_contents[section_key] = margin
		if section_key == "production": margin.add_child(_build_production_section(location_id))
		elif section_key == "construction": margin.add_child(_build_construction_section(location_id))
		else:
			var placeholder := Label.new(); placeholder.text = "%s tools are not available yet." % section_name; placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; margin.add_child(placeholder)
	navigation.set_meta("section_buttons", section_buttons); navigation.set_meta("section_contents", section_contents)
	return navigation

func _build_production_section(location_id: String) -> Label:
	var label := Label.new()
	label.name = "ProductionSummary"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 160
	_production_summary_labels[location_id] = label
	return label

func _refresh_location_production(location_id: String) -> void:
	if not _production_summary_labels.has(location_id) or not _location_widgets.has(location_id): return
	var widget: Dictionary = _location_widgets[location_id]
	if widget.view.is_rendering_suspended(): return
	var summary := colony_state.get_location_production_summary(location_id)
	if summary.is_empty(): return
	var lines: Array[String] = ["Last %ds — %s" % [int(summary.window_seconds), String(summary.status).replace("_", " ").capitalize()]]
	for resource_type: String in ["wood", "stone", "food"]:
		var resource: Dictionary = summary.production[resource_type]
		lines.append("%s %.1f/min  S:%d L:%d C:%d" % [resource_type.capitalize(), float(resource.per_minute), int(resource.stored), int(resource.loose), int(resource.carried)])
	var role_parts: Array[String] = []
	for role: String in [StateScript.ROLE_WOOD, StateScript.ROLE_MINING, StateScript.ROLE_FORAGE, StateScript.ROLE_HAUL, StateScript.ROLE_CONSTRUCTION, StateScript.ROLE_NONE]:
		var count := int(summary.roles.get(role, 0))
		if count > 0: role_parts.append("%s %d" % [role.capitalize(), count])
	lines.append("Workers: %s" % ("None" if role_parts.is_empty() else " · ".join(role_parts)))
	(_production_summary_labels[location_id] as Label).text = "\n".join(lines)

func _build_construction_section(location_id: String) -> VBoxContainer:
	var box := VBoxContainer.new(); box.name = "ConstructionTools"; box.add_theme_constant_override("separation", 4)
	var tool_buttons: Dictionary = {}
	for entry: Array in [["Wall", "wall"], ["Floor", "floor"], ["Door", "door"], ["Window", "window"]]:
		var piece_kind := String(entry[1]); var button := Button.new(); button.name = "%sToolButton" % String(entry[0]); button.text = entry[0]; button.toggle_mode = true; button.pressed.connect(_set_active_construction_tool.bind(piece_kind)); box.add_child(button); tool_buttons[piece_kind] = button
	var roof := Button.new(); roof.name = "RoofToolButton"; roof.text = "Roof (Deferred)"; roof.disabled = true; roof.tooltip_text = "Roof construction is deferred"; box.add_child(roof)
	var cancel := Button.new(); cancel.name = "CancelToolButton"; cancel.text = "Cancel Tool"; cancel.pressed.connect(_set_active_construction_tool.bind("")); box.add_child(cancel)
	var feedback := Label.new(); feedback.name = "ConstructionFeedback"; feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(feedback)
	_construction_tool_buttons[location_id] = tool_buttons; _construction_feedback_labels[location_id] = feedback; _refresh_construction_tool_ui()
	return box

func _set_location_section(location_id: String, section_key: String) -> void:
	if not _location_widgets.has(location_id): return
	var widget: Dictionary = _location_widgets[location_id]
	var expanded := "" if String(widget.expanded_section) == section_key else section_key
	widget.expanded_section = expanded
	for key: String in widget.section_buttons:
		(widget.section_buttons[key] as Button).text = "%s %s" % ["\u25bc" if key == expanded else "\u25b6", key.capitalize()]
		(widget.section_contents[key] as Control).visible = key == expanded

func get_active_construction_tool() -> String:
	return _active_construction_tool

func _set_active_construction_tool(piece_kind: String) -> void:
	_active_construction_tool = piece_kind
	for widget: Dictionary in _location_widgets.values(): widget.view.cancel_construction_interaction()
	_refresh_construction_tool_ui()

func _refresh_construction_tool_ui() -> void:
	for tool_buttons: Dictionary in _construction_tool_buttons.values():
		for piece_kind: String in tool_buttons: (tool_buttons[piece_kind] as Button).button_pressed = piece_kind == _active_construction_tool

func _on_construction_feedback(message: String, location_id: String) -> void:
	if _construction_feedback_labels.has(location_id): (_construction_feedback_labels[location_id] as Label).text = message.capitalize()

func _open_building_inspector(building_id: String) -> void:
	if _building_inspector_widgets.has(building_id):
		var existing: Control = _building_inspector_widgets[building_id].window
		_focus_window(existing); return
	var snapshot := colony_state.get_building_inspector_snapshot(building_id)
	if snapshot.is_empty(): return
	var window := _create_window(String(snapshot.display_name), Vector2(520, 180), Vector2(360, 360), true)
	var label := Label.new(); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.selectable = true
	window.get_content_container().add_child(label)
	_building_inspector_widgets[building_id] = {"window": window, "label": label}
	_refresh_building_inspector(building_id)

func _refresh_building_inspector(building_id: String) -> void:
	if not _building_inspector_widgets.has(building_id): return
	var snapshot := colony_state.get_building_inspector_snapshot(building_id)
	if snapshot.is_empty(): return
	var stored_lines: Array[String] = []
	if bool(snapshot.tracking.stored_items_supported):
		for item: Dictionary in snapshot.stored_items: stored_lines.append("%s: %d" % [String(item.resource_type).capitalize(), int(item.amount)])
	var lines: Array[String] = [
		"Type: %s" % String(snapshot.building_type).capitalize(),
		"State: %s" % String(snapshot.completion_state).capitalize(),
		"Footprint: %d cell(s)" % snapshot.occupied_cells.size(),
		"Enclosed: %s" % ("Yes" if bool(snapshot.enclosed) else "No"),
		"Interior area: %d cell(s)" % int(snapshot.interior_cell_count),
		"Location: %s" % String(snapshot.world_space_id),
		"",
		"Occupants inside: Not tracked",
		"Stored items: %s" % ("Not tracked" if not bool(snapshot.tracking.stored_items_supported) else ("None" if stored_lines.is_empty() else "\n  " + "\n  ".join(stored_lines))),
		"Furniture inside: Not tracked",
		"",
		"Details",
		"Building ID: %s" % String(snapshot.building_id),
	]
	(_building_inspector_widgets[building_id].label as Label).text = "\n".join(lines)

func _rebuild_locations_list() -> void:
	if _locations_list == null: return
	for child: Node in _locations_list.get_children(): child.queue_free()
	for location: Dictionary in colony_state.get_location_snapshots():
		var row := VBoxContainer.new(); var p: Dictionary = location.potentials; var home := colony_state.get_location_snapshot(StateScript.LOCATION_ID); var distance := Vector2(location.world_position).distance_to(Vector2(home.world_position)); var label := Label.new(); label.text = "%s | %s | %.1f from Home | Colonists %d | Buildings %d\nLoose W:%d S:%d F:%d | Stored W:%d S:%d F:%d" % [location.display_name, "Claimed Outpost" if bool(location.claimed) and not bool(location.primary_settlement) else location.lifecycle_state, distance, location.colonist_presence_ids.size(), location.building_records.size(), location.resource_totals.loose.wood, location.resource_totals.loose.stone, location.resource_totals.loose.food, location.formal_storage.wood, location.formal_storage.stone, location.formal_storage.food]; row.add_child(label)
		var actions := HBoxContainer.new(); row.add_child(actions); var open := Button.new(); open.text = "Open / Focus"; open.pressed.connect(func() -> void: _open_location(String(location.location_id))); actions.add_child(open)
		var rename := LineEdit.new(); rename.placeholder_text = "Rename"; rename.custom_minimum_size.x = 90; rename.text_submitted.connect(func(value: String) -> void: colony_state.request_rename_location(String(location.location_id), value)); actions.add_child(rename)
		if String(location.lifecycle_state) == "DISCOVERED": var retain := Button.new(); retain.text = "Retain"; retain.pressed.connect(func() -> void: colony_state.request_retain_location(String(location.location_id))); actions.add_child(retain); var discard := Button.new(); discard.text = "Discard"; discard.pressed.connect(func() -> void: colony_state.request_discard_location(String(location.location_id))); actions.add_child(discard)
		if String(location.lifecycle_state) == "RETAINED" and not bool(location.claimed): var claim := Button.new(); claim.text = "Claim"; claim.disabled = location.colonist_presence_ids.is_empty(); claim.pressed.connect(func() -> void: if not location.colonist_presence_ids.is_empty(): colony_state.request_claim_location(String(location.colonist_presence_ids[0]), String(location.location_id))); actions.add_child(claim)
		var send := Button.new(); send.text = "Send Selected"; send.disabled = _selected_colonist_id.is_empty(); send.pressed.connect(func() -> void: colony_state.request_send_colonist_to_location(_selected_colonist_id, String(location.location_id))); actions.add_child(send); _locations_list.add_child(row); _locations_list.add_child(HSeparator.new())

func _show_discovery_result(location_id: String) -> void:
	var location := colony_state.get_location_snapshot(location_id); var window := _create_window("Location Discovered", Vector2(430, 180), Vector2(390, 300), true); var box := VBoxContainer.new(); window.get_content_container().add_child(box); var p: Dictionary = location.potentials; var label := Label.new(); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.text = "%s\nType: %s\nWorld position: %s\nPotential — Wood %d, Stone %d, Food %d" % [location.display_name, location.location_type, location.world_position, p.wood, p.stone, p.food]; box.add_child(label); var inspect := Button.new(); inspect.text = "Inspect"; inspect.pressed.connect(func() -> void: _open_location(location_id)); box.add_child(inspect); var retain := Button.new(); retain.text = "Retain"; retain.pressed.connect(func() -> void: colony_state.request_retain_location(location_id)); box.add_child(retain); var discard := Button.new(); discard.text = "Discard"; discard.pressed.connect(func() -> void: colony_state.request_discard_location(location_id)); box.add_child(discard)

func _create_window(title: String, position_value: Vector2, size_value: Vector2, close_enabled: bool) -> Control:
	var window: Control = DesktopWindowScript.new(); window.configure(title, close_enabled, true); window.position = _clamp_window_spawn(position_value, size_value); window.size = size_value; window_layer.add_child(window); _windows.append(window)
	desktop_shell.register_window(window, title)
	window.minimise_requested.connect(_minimise_window); window.maximise_requested.connect(_maximise_window); window.close_requested.connect(_close_window); window.focus_requested.connect(_focus_window)
	_focus_window(window)
	return window

func _focus_window(window: Control) -> void:
	if not is_instance_valid(window): return
	desktop_shell.close_start_menu(); window.visible = true; _set_window_content_suspended(window, false); window.move_to_front()
	for candidate: Control in _windows:
		if is_instance_valid(candidate): candidate.set_focused(candidate == window)
	desktop_shell.set_window_minimized(window, false)

func _minimise_window(window: Control) -> void:
	if not is_instance_valid(window): return
	desktop_shell.close_start_menu(); _set_window_content_suspended(window, true); window.visible = false; window.set_focused(false); desktop_shell.set_window_minimized(window, true)

func _maximise_window(window: Control) -> void:
	if not is_instance_valid(window): return
	_focus_window(window)
	window.set_maximised(not window.is_maximised(), Rect2(Vector2.ZERO, window_layer.size))

func _close_window(window: Control) -> void:
	if not is_instance_valid(window): return
	desktop_shell.close_start_menu()
	_set_window_content_suspended(window, true)
	_cleanup_window_lookups(window)
	_windows.erase(window)
	desktop_shell.unregister_window(window)
	window.queue_free()
	_focus_top_visible_window()

func _set_window_content_suspended(window: Control, suspended: bool) -> void:
	for widget: Dictionary in _location_widgets.values():
		if widget.window == window:
			widget.view.set_rendering_suspended(suspended)
			if not suspended: _refresh_location_production(String(widget.view.location_id))
			return

func _cleanup_window_lookups(window: Control) -> void:
	for location_id: String in _location_widgets.keys():
		if _location_widgets[location_id].window == window:
			if _location_widget == _location_widgets[location_id]: _location_widget = {}
			_location_widgets.erase(location_id)
			_construction_tool_buttons.erase(location_id)
			_construction_feedback_labels.erase(location_id)
			_production_summary_labels.erase(location_id)
	for building_id: String in _building_inspector_widgets.keys():
		if _building_inspector_widgets[building_id].window == window: _building_inspector_widgets.erase(building_id)

func _focus_top_visible_window() -> void:
	for index in range(window_layer.get_child_count() - 1, -1, -1):
		var candidate := window_layer.get_child(index)
		if candidate in _windows and is_instance_valid(candidate) and candidate.visible:
			_focus_window(candidate)
			return
	desktop_shell.set_active_window(null)

func _clamp_window_spawn(requested_position: Vector2, window_size: Vector2) -> Vector2:
	var working_size := window_layer.size
	return Vector2(clampf(requested_position.x, 0.0, maxf(0.0, working_size.x - window_size.x)), clampf(requested_position.y, 0.0, maxf(0.0, working_size.y - window_size.y)))

func _refresh() -> void:
	if _location_widget.is_empty(): return
	_rebuild_locations_list()
	var settled := colony_state.get_game_phase() == StateScript.SETTLED; _location_widget.settle.visible = not settled
	for location_id: String in _location_widgets:
		var widget: Dictionary = _location_widgets[location_id]; var l := colony_state.get_location_snapshot(location_id); var claimed := bool(l.get("claimed", false)); widget.claim.visible = location_id != StateScript.LOCATION_ID and not claimed; widget.claim.disabled = String(l.lifecycle_state) != "RETAINED" or l.colonist_presence_ids.is_empty(); widget.build.visible = location_id != StateScript.LOCATION_ID and claimed
		if location_id != StateScript.LOCATION_ID: widget.heading.text = "%s | Status: %s\nLoose W:%d S:%d F:%d | Formal W:%d S:%d F:%d | Buildings %d" % [l.display_name, "Claimed Outpost" if claimed else String(l.lifecycle_state).capitalize(), l.resource_totals.loose.wood, l.resource_totals.loose.stone, l.resource_totals.loose.food, l.formal_storage.wood, l.formal_storage.stone, l.formal_storage.food, l.building_records.size()]
		_refresh_location_production(location_id)
	var summary := colony_state.get_resource_summary(); var location := colony_state.get_location_snapshot(StateScript.LOCATION_ID)
	_location_widget.heading.text = "%s | %s | Seed %d\nStored W:%d S:%d F:%d   Loose W:%d S:%d F:%d   Carried W:%d S:%d F:%d" % [location.display_name, "Settled" if settled else "Evaluating", colony_state.get_game_seed(), summary.stored.wood, summary.stored.stone, summary.stored.food, summary.loose.wood, summary.loose.stone, summary.loose.food, summary.carried.wood, summary.carried.stone, summary.carried.food]
	for id: String in colony_state.get_colonist_ids():
		var c := colony_state.get_colonist_snapshot(id); var widget: Dictionary = _colonist_widgets[id]; var mobility := ""
		var travel := colony_state.get_travel_snapshot(id); var scouting := colony_state.get_scouting_snapshot(id)
		if not travel.is_empty(): mobility = "\n%s → %s  %d%%" % [travel.origin_location_id, travel.destination_location_id, int(100.0 * float(travel.travel_elapsed) / float(travel.travel_duration))]
		elif not scouting.is_empty(): mobility = "\nScouting %s  %d%%" % [scouting.search_type, int(100.0 * float(scouting.elapsed) / float(scouting.duration))]
		var current_name := "Away" if String(c.location_id).is_empty() else String(colony_state.get_location_snapshot(String(c.location_id)).display_name)
		widget.status.text = "Location: %s\nRole: %s\nActivity: %s%s\nHunger: %d   Rest: %d%s" % [current_name, String(c.role).capitalize(), c.activity, mobility, int(c.needs.hunger), int(c.needs.rest), "\nWarning: low needs" if float(c.needs.hunger) < 30.0 or float(c.needs.rest) < 30.0 else ""]
		for child: Control in widget.roles.get_children(): child.disabled = not settled
	for building_id: String in _building_inspector_widgets: _refresh_building_inspector(building_id)
