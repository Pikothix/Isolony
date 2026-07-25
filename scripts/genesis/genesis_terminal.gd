extends VBoxContainer
class_name GenesisTerminal

signal command_submitted(command: String)

## Presentation-only terminal. It owns input, scrolling, formatting, command
## history navigation, and the optional resource monitor. It never mutates
## authoritative Genesis state.

const ANSI_COLORS := {
	&"success": Color("79d279"),
	&"warning": Color("e0c46c"),
	&"error": Color("e07171"),
	&"discovery": Color("69c9d0"),
	&"heading": Color("69c9d0"),
	&"installed": Color("79d279"),
	&"separator": Color("66827a"),
}
const KERNEL_LOG_COLORS := {
	&"compute": Color("aeb8b2"),
	&"runtime": Color("8fb8a0"),
	&"process": Color("9aaebc"),
	&"package": Color("b5a77d"),
	&"discovery": Color("69c9d0"),
	&"scheduler": Color("959ca8"),
}

var _simulation: GenesisEngineState
var _submitted_commands: Array[String] = []
var _history_index := 0
var _history_draft := ""
var _ansi_enabled := false
var _history_enabled := false
var _resource_monitor: Label
var _presentation_queue: Array[Dictionary] = []
var _presentation_queue_active := false
var _kernel_log_panel: VBoxContainer
var _kernel_log_output: RichTextLabel
var _kernel_log_header: Label
var _rendered_runtime_entries: Array[Dictionary] = []
var _kernel_log_following := true
var _kernel_log_internal_scroll := false
var _rebuilding_kernel_log := false

@onready var output: RichTextLabel = %Output
@onready var command_input: LineEdit = %CommandInput
@onready var prompt: Label = %Prompt
@onready var banner_title: Label = %BannerTitle
@onready var banner_subtitle: Label = %BannerSubtitle
@onready var banner_hint: Label = %BannerHint
@onready var _workspace: HBoxContainer = get_parent() as HBoxContainer


func _ready() -> void:
	command_input.keep_editing_on_text_submit = true
	command_input.text_submitted.connect(_on_text_submitted)
	command_input.gui_input.connect(_on_command_input_gui_input)
	call_deferred("_focus_input")


func bind_simulation(simulation: GenesisEngineState) -> void:
	_simulation = simulation
	simulation.output_requested.connect(_on_output_requested)
	simulation.state_changed.connect(_on_state_changed)
	simulation.ui_feature_unlocked.connect(_on_ui_feature_unlocked)
	simulation.discovery_created.connect(_on_discovery_created)
	simulation.presentation_sequence_requested.connect(_on_presentation_sequence_requested)
	simulation.runtime_log_entry_created.connect(_on_runtime_log_entry_created)
	simulation.runtime_log_reset.connect(_on_runtime_log_reset)
	simulation.terminal_section_requested.connect(_on_terminal_section_requested)


func append_output(text: String, category: StringName = &"neutral") -> void:
	_enqueue_presentation({
		"type": &"line",
		"text": text,
		"category": category,
	})


func _render_line(text: String, category: StringName = &"neutral") -> void:
	if _ansi_enabled and ANSI_COLORS.has(category):
		output.push_color(ANSI_COLORS[category])
		output.append_text(text)
		output.pop()
		output.newline()
	else:
		output.append_text(text + "\n")
	call_deferred("_scroll_to_latest")
	call_deferred("_ensure_input_focus")


func _on_text_submitted(text: String) -> void:
	var command := text.strip_edges()
	command_input.clear()
	if command.is_empty():
		_focus_input()
		return
	_submitted_commands.append(command)
	_history_index = _submitted_commands.size()
	_history_draft = ""
	_render_line(prompt.text + " " + command)
	command_submitted.emit(command)
	_focus_input()


func _on_command_input_gui_input(event: InputEvent) -> void:
	if not _history_enabled or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_UP:
		_navigate_history(-1)
		command_input.accept_event()
	elif key_event.keycode == KEY_DOWN:
		_navigate_history(1)
		command_input.accept_event()


func _navigate_history(direction: int) -> void:
	if _submitted_commands.is_empty():
		return
	if _history_index == _submitted_commands.size() and direction < 0:
		_history_draft = command_input.text
	_history_index = clampi(_history_index + direction, 0, _submitted_commands.size())
	if _history_index == _submitted_commands.size():
		command_input.text = _history_draft
	else:
		command_input.text = _submitted_commands[_history_index]
	command_input.caret_column = command_input.text.length()


func _on_ui_feature_unlocked(feature_id: StringName) -> void:
	match feature_id:
		&"resource_monitor":
			_create_resource_monitor()
			_update_resource_monitor(_simulation.get_snapshot())
		&"kernel_log":
			_create_kernel_log()
		&"command_history":
			_history_enabled = true
		&"ansi":
			_ansi_enabled = true
			_apply_ansi_theme()
			_render_runtime_log_history()


func _on_state_changed(snapshot: Dictionary) -> void:
	prompt.text = String(snapshot.prompt_text)
	banner_title.text = String(snapshot.banner_title)
	banner_subtitle.text = String(snapshot.banner_subtitle)
	banner_hint.visible = not bool(snapshot.booted)
	if _resource_monitor != null:
		_update_resource_monitor(snapshot)


func _on_discovery_created(event: Dictionary) -> void:
	_enqueue_presentation({
		"type": &"discovery",
		"event": event,
	})


func _on_output_requested(text: String, category: StringName) -> void:
	append_output(text, category)


func _on_presentation_sequence_requested(sequence_id: StringName, context: Dictionary) -> void:
	_enqueue_presentation({
		"type": &"sequence",
		"sequence_id": sequence_id,
		"context": context,
	})


func _on_terminal_section_requested(title: String, rows: Array) -> void:
	_enqueue_presentation({
		"type": &"section",
		"title": title,
		"rows": rows,
	})


func _on_runtime_log_entry_created(entry: Dictionary) -> void:
	if _kernel_log_output == null:
		return
	_rendered_runtime_entries.append(entry)
	var capacity := _simulation.get_runtime_log_capacity()
	if _rendered_runtime_entries.size() > capacity:
		_rendered_runtime_entries.pop_front()
		_render_runtime_log_history()
	else:
		_render_runtime_log_entry(entry)


func _on_runtime_log_reset() -> void:
	_rendered_runtime_entries.clear()
	if _kernel_log_output != null:
		_kernel_log_output.clear()
		_kernel_log_following = true


func _enqueue_presentation(item: Dictionary) -> void:
	_presentation_queue.append(item)
	if not _presentation_queue_active:
		_process_presentation_queue()


func _process_presentation_queue() -> void:
	_presentation_queue_active = true
	while not _presentation_queue.is_empty():
		var item: Dictionary = _presentation_queue.pop_front()
		match item.type:
			&"line":
				_render_line(String(item.text), item.category as StringName)
			&"discovery":
				_render_discovery(item.event)
			&"section":
				_render_section(String(item.title), item.rows)
			&"sequence":
				await _render_sequence(item.sequence_id, item.context)
	_presentation_queue_active = false
	_ensure_input_focus()


func _render_sequence(sequence_id: StringName, context: Dictionary) -> void:
	match sequence_id:
		&"bootstrap":
			await _render_timed_lines([
				{"text": "Beginning bootstrap...", "category": &"neutral", "delay": 0.0},
				{"text": "[ OK ] Processor initialised", "category": &"success", "delay": 0.28},
				{"text": "[ OK ] Runtime allocated", "category": &"success", "delay": 0.28},
				{"text": "[ OK ] Scheduler online", "category": &"success", "delay": 0.28},
				{"text": "[ OK ] Terminal attached", "category": &"success", "delay": 0.28},
				{"text": "[ OK ] Bootstrap complete", "category": &"success", "delay": 0.28},
				{"text": "GENESIS online.", "category": &"success", "delay": 0.2},
			])
		&"process_creation":
			await _render_timed_lines([
				{"text": "Creating background process...", "category": &"neutral", "delay": 0.0},
				{"text": "PID %04d registered." % int(context.pid), "category": &"success", "delay": 0.16},
				{"text": "Background execution active.", "category": &"success", "delay": 0.16},
			])
		&"package_installation":
			var command_name := String(context.unlock_command)
			var registration_text := (
				"Registering command..."
				if not command_name.is_empty()
				else "Registering system component..."
			)
			await _render_timed_lines([
				{"text": "Installing %s.SYS..." % context.display_name, "category": &"neutral", "delay": 0.0},
				{"text": "Copying package...", "category": &"neutral", "delay": 0.18},
				{"text": registration_text, "category": &"neutral", "delay": 0.18},
				{"text": "Installation complete.", "category": &"success", "delay": 0.18},
			])


func _render_timed_lines(lines: Array) -> void:
	for line: Dictionary in lines:
		var delay := float(line.delay)
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
		_render_line(String(line.text), line.category as StringName)


func _render_discovery(event: Dictionary) -> void:
	_render_section("DISCOVERY", [
		{"text": String(event.text), "category": &"discovery"},
	])


func _render_section(title: String, rows: Array) -> void:
	var separator_category := &"separator" if _ansi_enabled else &"neutral"
	var heading_category := &"heading" if _ansi_enabled else &"neutral"
	_render_line("================================", separator_category)
	_render_line(title, heading_category)
	_render_line("================================", separator_category)
	for row: Dictionary in rows:
		_render_line(String(row.text), row.category as StringName)


func _create_kernel_log() -> void:
	if _kernel_log_panel != null:
		return
	_kernel_log_panel = VBoxContainer.new()
	_kernel_log_panel.name = "KernelLogPane"
	_kernel_log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kernel_log_panel.size_flags_stretch_ratio = 0.35
	_kernel_log_panel.add_theme_constant_override("separation", 6)

	_kernel_log_header = Label.new()
	_kernel_log_header.name = "KernelLogHeader"
	_kernel_log_header.text = "KERNEL LOG"
	_kernel_log_header.add_theme_font_override("font", command_input.get_theme_font("font"))
	_kernel_log_header.add_theme_font_size_override("font_size", 16)
	_kernel_log_header.add_theme_color_override(
		"font_color",
		Color("69c9d0") if _ansi_enabled else Color("8f9a94")
	)

	var separator := HSeparator.new()
	separator.name = "KernelLogSeparator"

	_kernel_log_output = RichTextLabel.new()
	_kernel_log_output.name = "KernelLogOutput"
	_kernel_log_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_kernel_log_output.bbcode_enabled = false
	_kernel_log_output.scroll_active = true
	_kernel_log_output.scroll_following = false
	_kernel_log_output.selection_enabled = true
	_kernel_log_output.add_theme_font_override("normal_font", command_input.get_theme_font("font"))
	_kernel_log_output.add_theme_font_size_override("normal_font_size", 13)
	_kernel_log_output.add_theme_color_override("default_color", Color("a3aaa6"))

	_workspace.add_child(_kernel_log_panel)
	_kernel_log_panel.add_child(_kernel_log_header)
	_kernel_log_panel.add_child(separator)
	_kernel_log_panel.add_child(_kernel_log_output)
	_kernel_log_output.get_v_scroll_bar().value_changed.connect(_on_kernel_log_scroll_changed)
	if _resource_monitor != null:
		_resource_monitor.reparent(_kernel_log_panel)
		_kernel_log_panel.move_child(_resource_monitor, 0)

	_rendered_runtime_entries = _simulation.get_runtime_log_entries()
	_render_runtime_log_history()


func _render_runtime_log_history() -> void:
	if _kernel_log_output == null:
		return
	var should_follow := _kernel_log_following
	var previous_scroll := _kernel_log_output.get_v_scroll_bar().value
	_rebuilding_kernel_log = true
	_kernel_log_internal_scroll = true
	_kernel_log_output.clear()
	for entry: Dictionary in _rendered_runtime_entries:
		_render_runtime_log_entry(entry)
	_kernel_log_internal_scroll = false
	_rebuilding_kernel_log = false
	if should_follow:
		call_deferred("_scroll_kernel_log_to_latest")
	else:
		call_deferred("_restore_kernel_log_scroll", previous_scroll)


func _render_runtime_log_entry(entry: Dictionary) -> void:
	var should_follow := _kernel_log_following
	var line := "[%06d] %s" % [entry.sequence, entry.message]
	var category := entry.category as StringName
	if _ansi_enabled and KERNEL_LOG_COLORS.has(category):
		_kernel_log_output.push_color(KERNEL_LOG_COLORS[category])
		_kernel_log_output.append_text(line)
		_kernel_log_output.pop()
		_kernel_log_output.newline()
	else:
		_kernel_log_output.append_text(line + "\n")
	if should_follow and not _rebuilding_kernel_log:
		call_deferred("_scroll_kernel_log_to_latest")


func _on_kernel_log_scroll_changed(_value: float) -> void:
	if _kernel_log_internal_scroll or _kernel_log_output == null:
		return
	_kernel_log_following = _is_kernel_log_at_bottom()


func _is_kernel_log_at_bottom() -> bool:
	var scrollbar := _kernel_log_output.get_v_scroll_bar()
	return scrollbar.value >= scrollbar.max_value - scrollbar.page - 1.0


func _apply_ansi_theme() -> void:
	prompt.add_theme_color_override("font_color", Color("79d279"))
	command_input.add_theme_color_override("font_color", Color("d9f2df"))
	command_input.add_theme_color_override("caret_color", Color("79d279"))
	banner_title.add_theme_color_override("font_color", Color("69c9d0"))
	banner_subtitle.add_theme_color_override("font_color", Color("79d279"))
	if _resource_monitor != null:
		_resource_monitor.add_theme_color_override("font_color", Color("79d279"))
	if _kernel_log_header != null:
		_kernel_log_header.add_theme_color_override("font_color", Color("69c9d0"))


func _create_resource_monitor() -> void:
	if _resource_monitor != null:
		return
	_resource_monitor = Label.new()
	_resource_monitor.name = "ResourceMonitor"
	_resource_monitor.add_theme_color_override(
		"font_color",
		Color("79d279") if _ansi_enabled else Color("d7d7d7")
	)
	_resource_monitor.add_theme_font_override("font", command_input.get_theme_font("font"))
	var monitor_parent: Container = _kernel_log_panel if _kernel_log_panel != null else self
	monitor_parent.add_child(_resource_monitor)
	monitor_parent.move_child(_resource_monitor, 0)


func _update_resource_monitor(snapshot: Dictionary) -> void:
	_resource_monitor.text = "Processing Cycles: %d    Processes: %d    Throughput: %d/sec" % [
		snapshot.cycles,
		snapshot.workers,
		snapshot.cycles_per_second,
	]


func _focus_input() -> void:
	if not is_inside_tree():
		return
	command_input.grab_focus()
	command_input.edit()
	command_input.caret_column = command_input.text.length()


func _ensure_input_focus() -> void:
	if not is_inside_tree() or not command_input.is_visible_in_tree():
		return
	if command_input.has_focus() and command_input.is_editing():
		return
	var caret_position := command_input.caret_column
	command_input.grab_focus()
	command_input.edit()
	command_input.caret_column = clampi(caret_position, 0, command_input.text.length())


func _scroll_to_latest() -> void:
	output.scroll_to_line(maxi(0, output.get_line_count() - 1))


func _scroll_kernel_log_to_latest() -> void:
	if _kernel_log_output == null or not _kernel_log_following:
		return
	_kernel_log_internal_scroll = true
	_kernel_log_output.scroll_to_line(maxi(0, _kernel_log_output.get_line_count() - 1))
	_kernel_log_internal_scroll = false
	_kernel_log_following = true


func _restore_kernel_log_scroll(value: float) -> void:
	if _kernel_log_output == null:
		return
	_kernel_log_internal_scroll = true
	_kernel_log_output.get_v_scroll_bar().value = value
	_kernel_log_internal_scroll = false
	_kernel_log_following = false
