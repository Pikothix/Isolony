extends Control
class_name DesktopShell

signal save_game_requested
signal load_game_requested
signal new_game_requested
signal exit_requested
signal window_focus_requested(window: Control)
signal window_minimise_requested(window: Control)

const TASKBAR_HEIGHT := 38.0
const START_MENU_WIDTH := 210.0
const START_MENU_HEIGHT := 218.0

var _dismiss_layer: Button
var _start_button: Button
var _start_menu: PanelContainer
var _load_button: Button
var _window_button_container: HBoxContainer
var _time_button_container: HBoxContainer
var _simulation_clock_label: Label
var _window_buttons: Dictionary = {}
var _active_window: Control

## Presentation-only desktop shell. It owns global menu visibility and taskbar
## button state, while Main routes commands and desktop-window operations.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_dismiss_layer()
	_build_start_menu()
	_build_taskbar()


func get_time_button_container() -> HBoxContainer:
	return _time_button_container


func set_simulation_clock(day: int, hour: int, minute: int) -> void:
	_simulation_clock_label.text = "Day %d  %02d:%02d" % [day, hour, minute]


func is_start_menu_open() -> bool:
	return _start_menu.visible


func set_load_available(available: bool) -> void:
	_load_button.disabled = not available


func close_start_menu() -> void:
	_set_start_menu_visible(false)


func register_window(window: Control, title: String) -> void:
	if _window_buttons.has(window):
		(_window_buttons[window] as Button).text = title
		return
	var button := Button.new()
	button.text = title
	button.toggle_mode = true
	button.custom_minimum_size.x = 120
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.tooltip_text = title
	button.pressed.connect(_on_window_button_pressed.bind(window))
	_window_button_container.add_child(button)
	_window_buttons[window] = button
	window.tree_exiting.connect(unregister_window.bind(window), CONNECT_ONE_SHOT)


func unregister_window(window: Control) -> void:
	if not _window_buttons.has(window): return
	var button: Button = _window_buttons[window]
	_window_buttons.erase(window)
	if is_instance_valid(button): button.queue_free()
	if _active_window == window: set_active_window(null)


func clear_windows() -> void:
	for button: Button in _window_buttons.values():
		if is_instance_valid(button): button.queue_free()
	_window_buttons.clear()
	_active_window = null


func set_active_window(window: Control) -> void:
	_active_window = window
	for registered_window: Control in _window_buttons:
		(_window_buttons[registered_window] as Button).button_pressed = registered_window == window


func set_window_minimized(window: Control, minimized: bool) -> void:
	if not _window_buttons.has(window): return
	if minimized and _active_window == window: set_active_window(null)
	elif not minimized: set_active_window(window)


func _build_dismiss_layer() -> void:
	_dismiss_layer = Button.new()
	_dismiss_layer.name = "StartMenuDismissLayer"
	_dismiss_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dismiss_layer.flat = true
	_dismiss_layer.focus_mode = Control.FOCUS_NONE
	_dismiss_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_dismiss_layer.visible = false
	_dismiss_layer.pressed.connect(close_start_menu)
	add_child(_dismiss_layer)


func _build_start_menu() -> void:
	_start_menu = PanelContainer.new()
	_start_menu.name = "StartMenu"
	_start_menu.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_start_menu.offset_left = 2
	_start_menu.offset_top = -TASKBAR_HEIGHT - START_MENU_HEIGHT
	_start_menu.offset_right = 2 + START_MENU_WIDTH
	_start_menu.offset_bottom = -TASKBAR_HEIGHT
	_start_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_start_menu.visible = false
	add_child(_start_menu)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	_start_menu.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)
	var header := PanelContainer.new()
	header.theme_type_variation = "ActiveTitleBar"
	column.add_child(header)
	var title := Label.new()
	title.text = "Iso Colony"
	title.theme_type_variation = "WindowTitle"
	title.add_theme_constant_override("outline_size", 0)
	header.add_child(title)
	column.add_child(HSeparator.new())
	_add_menu_button(column, "Save Game", func() -> void: _emit_command(save_game_requested))
	_load_button = _add_menu_button(column, "Load Game", func() -> void: _emit_command(load_game_requested))
	_add_menu_button(column, "New Game", func() -> void: _emit_command(new_game_requested))
	column.add_child(HSeparator.new())
	var settings := _add_menu_button(column, "Settings", Callable())
	settings.disabled = true
	column.add_child(HSeparator.new())
	_add_menu_button(column, "Exit", func() -> void: _emit_command(exit_requested))


func _build_taskbar() -> void:
	var taskbar := PanelContainer.new()
	taskbar.name = "Taskbar"
	taskbar.theme_type_variation = "Taskbar"
	taskbar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	taskbar.offset_top = -TASKBAR_HEIGHT
	taskbar.gui_input.connect(_on_taskbar_gui_input)
	add_child(taskbar)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 5)
	taskbar.add_child(bar)
	_start_button = Button.new()
	_start_button.name = "StartButton"
	_start_button.text = "Start"
	_start_button.toggle_mode = true
	_start_button.custom_minimum_size.x = 72
	_start_button.pressed.connect(func() -> void: _set_start_menu_visible(_start_button.button_pressed))
	bar.add_child(_start_button)
	_window_button_container = HBoxContainer.new()
	_window_button_container.name = "WindowButtons"
	_window_button_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_window_button_container.add_theme_constant_override("separation", 3)
	bar.add_child(_window_button_container)
	_time_button_container = HBoxContainer.new()
	_time_button_container.name = "TimeButtons"
	_time_button_container.add_theme_constant_override("separation", 3)
	bar.add_child(_time_button_container)
	var clock_panel := PanelContainer.new()
	clock_panel.name = "SimulationClock"
	clock_panel.theme_type_variation = "InsetPanel"
	clock_panel.custom_minimum_size.x = 96
	clock_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(clock_panel)
	_simulation_clock_label = Label.new()
	_simulation_clock_label.name = "SimulationClockLabel"
	_simulation_clock_label.text = "Day 1  00:00"
	_simulation_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_simulation_clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_simulation_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_panel.add_child(_simulation_clock_label)


func _add_menu_button(parent: VBoxContainer, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = text.replace(" ", "") + "Button"
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 28
	if action.is_valid(): button.pressed.connect(action)
	parent.add_child(button)
	return button


func _set_start_menu_visible(open: bool) -> void:
	_start_menu.visible = open
	_dismiss_layer.visible = open
	_start_button.button_pressed = open
	if open:
		_start_menu.move_to_front()
		_start_button.grab_focus()
	else:
		_start_button.release_focus()


func _emit_command(command: Signal) -> void:
	close_start_menu()
	command.emit()


func _on_window_button_pressed(window: Control) -> void:
	close_start_menu()
	if not is_instance_valid(window):
		unregister_window(window)
		return
	if window == _active_window and window.visible: window_minimise_requested.emit(window)
	else: window_focus_requested.emit(window)


func _on_taskbar_gui_input(event: InputEvent) -> void:
	if is_start_menu_open() and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		close_start_menu()


func _unhandled_key_input(event: InputEvent) -> void:
	if is_start_menu_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_start_menu()
		get_viewport().set_input_as_handled()
