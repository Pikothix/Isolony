extends SceneTree

const MainScene = preload("res://scenes/Main.tscn")
const State = preload("res://scripts/simulation/windowed_colony_state.gd")

var _failures: Array[String] = []
var _checks := 0
var _save_requests := 0
var _new_game_requests := 0

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main: Control = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main.call("_new_game")
	await process_frame
	var shell: DesktopShell = main.get("desktop_shell")
	var state: WindowedColonyState = main.get("colony_state")
	shell.save_game_requested.connect(func() -> void: _save_requests += 1)
	shell.new_game_requested.connect(func() -> void: _new_game_requests += 1)
	var start := shell.find_child("StartButton", true, false) as Button
	var menu := shell.find_child("StartMenu", true, false) as PanelContainer
	var dismiss := shell.find_child("StartMenuDismissLayer", true, false) as Button
	var save := shell.find_child("SaveGameButton", true, false) as Button
	var load := shell.find_child("LoadGameButton", true, false) as Button
	var new_game := shell.find_child("NewGameButton", true, false) as Button
	var settings := shell.find_child("SettingsButton", true, false) as Button
	var clock_panel := shell.find_child("SimulationClock", true, false) as PanelContainer
	var clock_label := shell.find_child("SimulationClockLabel", true, false) as Label
	_check(clock_panel != null and clock_label != null, "taskbar owns the simulation clock presentation")
	_check(clock_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE and clock_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "clock does not intercept desktop input")
	_check(clock_label.text == "Day 1  00:00", "clock initially projects authoritative simulation time")
	state.set("_simulation_time", 489.0); state.call("_emit_simulation_time_changed")
	_check(clock_label.text == "Day 1  08:09", "clock formats authoritative day and zero-padded 24-hour time")
	state.set("_simulation_time", 0.0); state.call("_emit_simulation_time_changed")

	start.button_pressed = true; start.pressed.emit()
	_check(menu.visible and start.button_pressed, "Start opens menu and appears pressed")
	start.button_pressed = false; start.pressed.emit()
	_check(not menu.visible and not start.button_pressed, "Start closes menu and releases pressed state")
	start.button_pressed = true; start.pressed.emit(); dismiss.pressed.emit()
	_check(not menu.visible, "outside click closes menu")
	start.button_pressed = true; start.pressed.emit()
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	shell.call("_unhandled_key_input", escape)
	_check(not menu.visible, "Escape closes menu")
	_check(menu.mouse_filter == Control.MOUSE_FILTER_STOP and dismiss.mouse_filter == Control.MOUSE_FILTER_STOP, "menu and dismissal layer consume clicks")
	_check(settings.disabled, "Settings remains a disabled placeholder")

	var before_menu := state.export_save_data()
	start.button_pressed = true; start.pressed.emit(); dismiss.pressed.emit()
	_check(state.export_save_data() == before_menu, "Start Menu state is excluded from simulation save data")
	_check(bool(state.request_settle_starting_location().ok), "validation colony settles")
	_check(bool(state.request_set_time_scale(0.0).ok), "validation simulation pauses")
	start.button_pressed = true; start.pressed.emit(); save.pressed.emit()
	_check(_save_requests == 1 and state.has_valid_save(), "Save command routes to the existing save request")
	_check(not load.disabled, "Load is enabled when the existing default-slot save is valid")
	var seed_before := state.get_game_seed()
	start.button_pressed = true; start.pressed.emit(); new_game.pressed.emit()
	await process_frame
	_check(_new_game_requests == 1 and state.get_game_seed() != seed_before, "New Game routes to the existing authoritative reset")

	var windows: Array = main.get("_windows")
	var window_buttons: HBoxContainer = shell.find_child("WindowButtons", true, false)
	_check(window_buttons.get_child_count() == windows.size(), "taskbar represents the Main window registry")
	var active_window: Control = shell.get("_active_window")
	var registered_buttons: Dictionary = shell.get("_window_buttons")
	_check(active_window != null and (registered_buttons[active_window] as Button).button_pressed, "active window button is highlighted")
	(registered_buttons[active_window] as Button).pressed.emit()
	_check(not active_window.visible, "active taskbar button minimizes its window")
	(registered_buttons[active_window] as Button).pressed.emit()
	_check(active_window.visible and shell.get("_active_window") == active_window, "taskbar button restores and focuses a minimized window")

	var location_widgets: Dictionary = main.get("_location_widgets")
	var location_widget: Dictionary = location_widgets.values()[0]
	var location_window: Control = location_widget.window
	var location_view: Control = location_widget.view
	if state.get_game_phase() != State.SETTLED: _check(bool(state.request_settle_starting_location().ok), "lifecycle validation colony settles")
	var lifecycle_save_before := state.export_save_data()
	var time_before_minimise := state.get_simulation_time()
	var snapshots_before_resume := int(location_view.get_full_snapshot_count())
	main.call("_minimise_window", location_window)
	_check(not location_window.visible and location_view.is_rendering_suspended(), "minimise hides the location window and suspends its projection")
	_check((shell.get("_window_buttons") as Dictionary).has(location_window), "minimise retains the location taskbar entry")
	state.advance_simulation(1.0)
	_check(state.get_simulation_time() > time_before_minimise and location_view.is_rendering_suspended(), "authoritative simulation advances while the location projection is suspended")
	_check(bool(state.request_set_time_scale(0.0).ok), "lifecycle validation pauses after explicit hidden-window advancement")
	main.call("_focus_window", location_window)
	_check(location_window.visible and not location_view.is_rendering_suspended(), "restore shows the location window and resumes its projection")
	_check(int(location_view.get_full_snapshot_count()) == snapshots_before_resume + 1, "restore refreshes the location projection from current authority")
	_check(shell.get("_active_window") == location_window, "restored location window becomes the active taskbar entry")

	var normal_rect := Rect2(location_window.position, location_window.size)
	var save_before_geometry := state.export_save_data()
	location_window.emit_signal("maximise_requested", location_window)
	_check(location_window.is_maximised() and location_window.position.is_equal_approx(Vector2.ZERO) and location_window.size.is_equal_approx(main.get("window_layer").size), "maximise fills the desktop work area without covering the taskbar")
	_check(String(location_window.get("_maximise_button").text) == "❐", "maximise updates the title-bar button to restore state")
	location_window.emit_signal("maximise_requested", location_window)
	_check(not location_window.is_maximised() and Rect2(location_window.position, location_window.size) == normal_rect, "restore from maximise returns the exact normal rectangle")
	main.call("_maximise_window", location_window); main.call("_maximise_window", location_window)
	_check(Rect2(location_window.position, location_window.size) == normal_rect, "repeated maximise and restore preserve the original normal rectangle")
	_check(state.export_save_data() == save_before_geometry, "focus and geometry lifecycle state are excluded from simulation save data")

	main.call("_minimise_window", location_window)
	main.call("_maximise_window", location_window)
	_check(location_window.visible and location_window.is_maximised() and not location_view.is_rendering_suspended(), "maximise after minimise restores, resumes, focuses, then maximises")
	main.call("_maximise_window", location_window)

	var generic_window: Control = main.call("_create_window", "Lifecycle Generic", Vector2(40, 40), Vector2(300, 220), true)
	main.call("_minimise_window", generic_window)
	_check(not generic_window.visible and not generic_window.has_method("set_rendering_suspended"), "generic windows minimise without requiring location-specific content")
	var generic_windows_before := (main.get("_windows") as Array).size()
	var generic_buttons_before := (shell.get("_window_buttons") as Dictionary).size()
	generic_window.emit_signal("close_requested", generic_window)
	await process_frame
	_check((main.get("_windows") as Array).size() == generic_windows_before - 1 and (shell.get("_window_buttons") as Dictionary).size() == generic_buttons_before - 1, "closing a minimized generic window removes live and taskbar references")

	main.call("_focus_window", (main.get("_windows") as Array)[0])
	main.call("_focus_window", location_window)
	_check(shell.get("_active_window") == location_window and main.get("window_layer").get_child(main.get("window_layer").get_child_count() - 1) == location_window, "focus synchronizes active taskbar state and front stacking")

	main.call("_maximise_window", location_window)
	var windows_before_close := (main.get("_windows") as Array).size()
	var buttons_before_close := (shell.get("_window_buttons") as Dictionary).size()
	var authority_before_close := state.export_save_data()
	location_window.emit_signal("close_requested", location_window)
	await process_frame
	_check((main.get("_windows") as Array).size() == windows_before_close - 1 and (shell.get("_window_buttons") as Dictionary).size() == buttons_before_close - 1, "closing a maximized location removes live and taskbar records")
	_check(not (main.get("_location_widgets") as Dictionary).has(State.LOCATION_ID), "closing a location removes its lookup entry")
	_check(not state.get_location_snapshot(State.LOCATION_ID).is_empty() and state.export_save_data() == authority_before_close, "closing a location leaves authoritative state unchanged")
	_check(shell.get("_active_window") == null or is_instance_valid(shell.get("_active_window")), "closing the active window leaves a valid fallback focus reference")
	main.call("_open_location", State.LOCATION_ID)
	await process_frame
	var reopened_widget: Dictionary = (main.get("_location_widgets") as Dictionary)[State.LOCATION_ID]
	_check(reopened_widget.window != location_window and (main.get("_windows") as Array).size() == windows_before_close, "reopening creates one fresh location window")
	_check((shell.get("_window_buttons") as Dictionary).size() == buttons_before_close and not reopened_widget.view.is_rendering_suspended(), "reopening creates one active taskbar entry and fresh projection")
	_check(state.export_save_data() == authority_before_close, "close and reopen remain excluded from simulation save data")
	_check(lifecycle_save_before.game_seed == state.export_save_data().game_seed, "desktop lifecycle never replaces authoritative game identity")

	location_widget = reopened_widget
	for section_key: String in ["construction", "buildings", "colonists", "storage"]:
		(location_widget.section_buttons[section_key] as Button).pressed.emit()
		_check(String(location_widget.expanded_section) == section_key, "%s location section expands" % section_key)
		for content_key: String in location_widget.section_contents:
			_check((location_widget.section_contents[content_key] as Control).visible == (content_key == section_key), "location accordion keeps one section open")
	(location_widget.section_buttons.construction as Button).pressed.emit()
	var tool_buttons: Dictionary = main.get("_construction_tool_buttons").values()[0]
	(tool_buttons.wall as Button).pressed.emit()
	start.button_pressed = true; start.pressed.emit(); dismiss.pressed.emit()
	_check(String(main.call("get_active_construction_tool")) == "wall", "desktop menu interaction does not change construction tool state")
	(location_widget.navigation.find_child("CancelToolButton", true, false) as Button).pressed.emit()
	_check(String(main.call("get_active_construction_tool")).is_empty(), "location construction Cancel Tool remains functional")
	var standalone_construction := false
	for window: Control in windows:
		if window.window_title == "Construction": standalone_construction = true
	_check(not standalone_construction, "standalone Construction window remains removed")
	var forbidden_location_control := false
	for node: Node in _descendants(location_widget.window):
		if node is Button and node.text in ["Save Game", "Main Menu / New Game"]: forbidden_location_control = true
	_check(not forbidden_location_control, "global commands remain absent from location windows")

	main.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition: _failures.append(description)


func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result


func _finish() -> void:
	if _failures.is_empty():
		print("DESKTOP_SHELL_VALIDATION: PASS (%d checks)" % _checks)
		quit(0)
	else:
		for failure: String in _failures: push_error("DESKTOP_SHELL_VALIDATION: " + failure)
		quit(1)
