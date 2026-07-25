extends PanelContainer
class_name DesktopWindow

signal focus_requested(window: Control)
signal minimise_requested(window: Control)
signal close_requested(window: Control)
signal maximise_requested(window: Control)

var window_title := "Window"
var allow_close := true
var allow_maximise := false
var _dragging := false
var _drag_offset := Vector2.ZERO
var _title_label: Label
var _title_bar: PanelContainer
var _content: MarginContainer
var _maximise_button: Button
var _maximised := false
var _normal_rect := Rect2()

## Reusable presentation-only desktop window. It owns drag/focus/minimise UI state and no gameplay data.
func _ready() -> void:
	custom_minimum_size = Vector2(260, 170)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_chrome()


func configure(title: String, close_enabled: bool = true, maximise_enabled: bool = false) -> void:
	window_title = title
	allow_close = close_enabled
	allow_maximise = maximise_enabled
	if is_node_ready():
		_title_label.text = title


func get_content_container() -> MarginContainer:
	return _content


func set_focused(focused: bool) -> void:
	if _title_bar != null:
		_title_bar.theme_type_variation = "ActiveTitleBar" if focused else "InactiveTitleBar"
	if _title_label != null:
		_title_label.add_theme_color_override("font_color", Color.WHITE if focused else Color("#202020"))


func is_maximised() -> bool:
	return _maximised


func set_maximised(maximised: bool, work_rect: Rect2) -> void:
	if maximised == _maximised: return
	if maximised:
		_normal_rect = Rect2(position, size)
		position = work_rect.position
		size = work_rect.size
	else:
		position = _normal_rect.position
		size = _normal_rect.size
	_maximised = maximised
	if _maximise_button != null:
		_maximise_button.text = "❐" if maximised else "□"


func _build_chrome() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	_title_bar = PanelContainer.new()
	_title_bar.theme_type_variation = "ActiveTitleBar"
	_title_bar.custom_minimum_size.y = 24
	_title_bar.gui_input.connect(_on_title_input)
	column.add_child(_title_bar)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 3)
	_title_bar.add_child(title_row)
	var icon := ColorRect.new()
	icon.color = Color("#4ab0a4")
	icon.custom_minimum_size = Vector2(14, 14)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(icon)
	_title_label = Label.new()
	_title_label.text = window_title
	_title_label.theme_type_variation = "WindowTitle"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(_title_label)
	var minimise := Button.new()
	minimise.text = "_"
	minimise.tooltip_text = "Minimise"
	minimise.custom_minimum_size = Vector2(23, 19)
	minimise.pressed.connect(func() -> void: minimise_requested.emit(self))
	title_row.add_child(minimise)
	if allow_maximise:
		_maximise_button = Button.new()
		_maximise_button.text = "□"
		_maximise_button.tooltip_text = "Maximise / Restore"
		_maximise_button.custom_minimum_size = Vector2(23, 19)
		_maximise_button.pressed.connect(func() -> void: maximise_requested.emit(self))
		title_row.add_child(_maximise_button)
	if allow_close:
		var close := Button.new()
		close.text = "X"
		close.tooltip_text = "Close presentation"
		close.custom_minimum_size = Vector2(23, 19)
		close.pressed.connect(func() -> void: close_requested.emit(self))
		title_row.add_child(close)
	_content = MarginContainer.new()
	_content.add_theme_constant_override("margin_left", 6)
	_content.add_theme_constant_override("margin_top", 5)
	_content.add_theme_constant_override("margin_right", 6)
	_content.add_theme_constant_override("margin_bottom", 6)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_content)
	gui_input.connect(_on_window_input)


func _on_window_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		focus_requested.emit(self)


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed and not _maximised
		if _dragging:
			_drag_offset = get_global_mouse_position() - global_position
			focus_requested.emit(self)
		elif event.pressed:
			focus_requested.emit(self)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var desktop_rect := get_parent_control().get_rect()
		var desired := get_global_mouse_position() - _drag_offset
		var title_visible_width := minf(size.x, 90.0)
		desired.x = clampf(desired.x, -size.x + title_visible_width, desktop_rect.size.x - title_visible_width)
		desired.y = clampf(desired.y, 0.0, maxf(0.0, desktop_rect.size.y - 28.0))
		position = desired
		accept_event()
