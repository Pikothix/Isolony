extends SceneTree

const StartupScene = preload("res://scenes/Startup.tscn")
const EngineStateScript = preload("res://scripts/genesis/genesis_engine_state.gd")
const ParserScript = preload("res://scripts/genesis/genesis_command_parser.gd")
const TimeStateScript = preload("res://scripts/simulation/time_state.gd")

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_validate_parser_registry()
	_validate_engine_authority()
	_validate_milestones()
	await _validate_genesis_flow()
	await _validate_direct_desktop_startup()
	await _validate_debug_skip()
	_finish()


func _validate_parser_registry() -> void:
	var parser: GenesisCommandParser = ParserScript.new()
	var received: Array[String] = []
	parser.register_command("Probe", func(arguments: String) -> void: received.append(arguments))
	_check(parser.execute("probe payload"), "parser resolves registered commands case-insensitively")
	_check(received == ["payload"], "parser forwards arguments without mutating state")
	_check(not parser.execute("missing"), "parser rejects unregistered commands")
	parser.register_intent(&"GREETING", ["hello", "hi", "hey"])
	_check(parser.resolve_intent("  HI  ") == &"GREETING", "dialogue aliases normalize deterministically")
	parser.register_command("compute", func(_arguments: String) -> void: pass)
	parser.register_suggestion_alias("execute", "compute")
	_check(parser.suggest_command("compue") == "compute", "parser suggests a command for a one-edit typo")
	_check(parser.suggest_command("executre") == "compute", "legacy execute typos suggest the renamed compute command")
	_check(parser.suggest_command("unrelated") == "", "parser does not suggest commands for distant input")


func _validate_engine_authority() -> void:
	var engine: GenesisEngineState = EngineStateScript.new()
	var unlock_count := [0]
	var manual_milestone_counts := {&"MANUAL_COMPUTE_1": 0, &"MANUAL_COMPUTE_3": 0, &"MANUAL_COMPUTE_5": 0}
	engine.automation_unlocked.connect(func() -> void: unlock_count[0] += 1)
	engine.milestone_reached.connect(func(milestone_id: StringName) -> void:
		if manual_milestone_counts.has(milestone_id):
			manual_milestone_counts[milestone_id] += 1
	)
	var initial := engine.get_snapshot()
	_check(not bool(engine.request_compute().ok), "manual computation fails while the engine is stopped")
	_check(engine.get_snapshot() == initial, "invalid manual actions do not mutate engine state")
	engine.start()
	_check(not bool(engine.request_spawn_worker().ok), "automation remains locked before its threshold")
	_check(engine.get_snapshot().cycles == 0, "locked worker creation does not mutate cycles")
	for unused_index in range(9):
		engine.request_compute()
	_check(not engine.automation_available, "automation is still locked at nine lifetime cycles")
	engine.request_compute()
	_check(engine.cycles == 10 and engine.lifetime_cycles == 10, "compute increments spendable and lifetime cycles through engine authority")
	_check(engine.automation_available and unlock_count[0] == 1, "automation unlocks exactly once at ten lifetime cycles")
	_check(manual_milestone_counts.values() == [1, 1, 1], "manual computation feedback milestones trigger once at one, three, and five cycles")
	engine.request_compute()
	_check(unlock_count[0] == 1, "automation unlock does not repeat after its threshold")
	_check(manual_milestone_counts.values() == [1, 1, 1], "manual computation milestones do not repeat after completion")
	var first_spawn := engine.request_spawn_worker()
	_check(bool(first_spawn.ok) and int(first_spawn.cost) == 10, "first worker spends the defined ten-cycle cost")
	_check(engine.worker_process_count == 1 and engine.cycles == 1, "successful worker creation spends cost through one authoritative mutation")
	_check(engine.get_next_worker_cost() == 20 and engine.get_cycles_per_second() == 1, "worker cost and production follow linear deterministic rules")
	var before_failed_spawn := engine.get_snapshot()
	var failed_spawn := engine.request_spawn_worker()
	_check(not bool(failed_spawn.ok) and String(failed_spawn.reason) == "insufficient_cycles", "worker creation validates available cycles")
	_check(engine.get_snapshot() == before_failed_spawn, "failed worker creation does not mutate authoritative state")
	_check(int(engine.advance_milliseconds(999).produced) == 0, "automatic production uses fixed integer accumulation")
	_check(int(engine.advance_milliseconds(1).produced) == 1, "one worker produces exactly one cycle per second")
	engine.advance_milliseconds(18000)
	var second_spawn := engine.request_spawn_worker()
	_check(bool(second_spawn.ok) and int(second_spawn.cost) == 20, "second worker spends twenty cycles")
	_check(engine.get_next_worker_cost() == 30 and engine.get_cycles_per_second() == 2, "subsequent worker cost and rate remain transparent")
	_check(
		int(GenesisEngineState.MILESTONE_REQUIREMENTS[&"ANOMALY_1"].lifetime_cycles) == 200
		and int(GenesisEngineState.MILESTONE_REQUIREMENTS[&"ANOMALY_2"].lifetime_cycles) == 400
		and int(GenesisEngineState.MILESTONE_REQUIREMENTS[&"STABLE_SIGNAL"].lifetime_cycles) == 750,
		"presentation split leaves consciousness thresholds unchanged"
	)

	var deterministic_a: GenesisEngineState = EngineStateScript.new()
	var deterministic_b: GenesisEngineState = EngineStateScript.new()
	_configure_one_worker(deterministic_a)
	_configure_one_worker(deterministic_b)
	for elapsed in [333, 667, 2000, 1250]:
		deterministic_a.advance_milliseconds(elapsed)
		deterministic_b.advance_milliseconds(elapsed)
	_check(deterministic_a.get_snapshot() == deterministic_b.get_snapshot(), "automatic production is deterministic for identical integer time steps")


func _configure_one_worker(engine: GenesisEngineState) -> void:
	engine.start()
	for unused_index in range(10):
		engine.request_compute()
	engine.request_spawn_worker()


func _validate_milestones() -> void:
	var engine: GenesisEngineState = EngineStateScript.new()
	var milestone_counts := {
		&"ANOMALY_1": 0,
		&"ANOMALY_2": 0,
		&"STABLE_SIGNAL": 0,
	}
	engine.milestone_reached.connect(func(milestone_id: StringName) -> void:
		if milestone_counts.has(milestone_id):
			milestone_counts[milestone_id] += 1
	)
	_configure_one_worker(engine)
	engine.advance_milliseconds(20000)
	engine.request_spawn_worker()
	engine.advance_milliseconds(15000)
	engine.request_spawn_worker()
	while engine.lifetime_cycles < 199:
		engine.request_compute()
	_check(not engine.has_milestone(&"ANOMALY_1"), "first anomaly cannot appear before 200 lifetime cycles and three workers")
	engine.request_compute()
	_check(engine.has_milestone(&"ANOMALY_1") and milestone_counts[&"ANOMALY_1"] == 1, "first anomaly triggers once at its complete requirement")
	engine.request_compute()
	_check(milestone_counts[&"ANOMALY_1"] == 1, "completed anomaly milestones do not repeat on later ticks")
	while engine.cycles < engine.get_next_worker_cost():
		engine.advance_milliseconds(1000)
	engine.request_spawn_worker()
	while engine.lifetime_cycles < 399:
		engine.request_compute()
	_check(not engine.has_milestone(&"ANOMALY_2"), "second anomaly remains locked below 400 lifetime cycles")
	engine.request_compute()
	_check(engine.has_milestone(&"ANOMALY_2") and milestone_counts[&"ANOMALY_2"] == 1, "second anomaly triggers once with four workers")
	while engine.cycles < engine.get_next_worker_cost():
		engine.advance_milliseconds(1000)
	engine.request_spawn_worker()
	while engine.lifetime_cycles < 749:
		engine.request_compute()
	_check(not engine.has_milestone(&"STABLE_SIGNAL"), "stable signal remains locked below 750 lifetime cycles")
	engine.request_compute()
	_check(engine.has_milestone(&"STABLE_SIGNAL") and milestone_counts[&"STABLE_SIGNAL"] == 1, "stable signal triggers once with five workers")
	engine.advance_milliseconds(100000)
	_check(milestone_counts.values() == [1, 1, 1], "all consciousness milestones remain one-shot")


func _validate_genesis_flow() -> void:
	ProjectSettings.set_setting("genesis/debug_skip", false)
	var error := change_scene_to_packed(StartupScene)
	_check(error == OK, "startup router can load Genesis")
	await create_timer(0.5).timeout
	_check(current_scene != null and current_scene.scene_file_path == "res://scenes/Genesis.tscn", "normal startup launches Genesis")
	_check(root.find_child("WindowedColonyState", true, false) == null, "desktop simulation is absent while Genesis runs")
	var genesis := current_scene as Control
	genesis.set("boot_delay_scale", 0.001)
	var terminal: GenesisTerminal = genesis.get("terminal")
	var stream: GenesisComputationalStreamView = genesis.get("computational_stream")
	var engine: GenesisEngineState = genesis.get("engine")
	var parser: GenesisCommandParser = genesis.get("_parser")
	var main_layout: VBoxContainer = genesis.get_node("Margin/MainLayout")
	var operator_console: Control = genesis.get_node("Margin/MainLayout/OperatorConsole")
	var flowing_layer: Control = stream.get_node("FlowingStreamLayer")
	var anchored_layer: Control = stream.get_node("AnchoredAnomalyLayer")
	var anomaly_label: Label = stream.get_node("AnchoredAnomalyLayer/AnomalyLabel")
	_check(main_layout != null and stream != null and operator_console != null, "Genesis contains distinct stream and operator-console presentation regions")
	_check(terminal.is_ancestor_of(terminal.command_input) and operator_console.is_ancestor_of(terminal), "the lower operator console remains the only interactive terminal")
	_check(stream.mouse_filter == Control.MOUSE_FILTER_IGNORE and flowing_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE and anchored_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE and anomaly_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "both computational presentation layers are non-interactive")
	_check(flowing_layer.get_parent() == stream and anchored_layer.get_parent() == stream, "flowing and anchored anomaly layers remain clipped inside the upper stream")
	_check(genesis.find_child("ThoughtRain", true, false) == null, "legacy overlapping thought-rain node is absent")
	_check(stream.get_global_rect().end.y <= operator_console.get_global_rect().position.y, "stream and operator-console rectangles do not overlap")

	_check(genesis.call("get_phase_name") == "DORMANT", "initial state is Dormant")
	_check(terminal.command_input.keep_editing_on_text_submit, "LineEdit keeps editing mode across text submission")
	_check(terminal.command_input.has_focus() and terminal.command_input.is_editing(), "command input receives active editing focus after normal Genesis startup")
	_check(terminal.history_label.selection_enabled, "terminal history remains selectable")
	genesis.call("_on_command_submitted", "help")
	_check(genesis.call("get_phase_name") == "DORMANT" and _latest_line(terminal) == "UNKNOWN COMMAND: help", "Dormant accepts only boot and reports unavailable input precisely")
	genesis.call("_on_command_submitted", "boot")
	_check(genesis.call("get_phase_name") == "BOOTING" and not terminal.command_input.editable, "boot enters Booting and disables input")
	_check(not terminal.command_input.has_focus() and not terminal.command_input.is_editing(), "command input releases editing focus during Booting")
	await create_timer(0.3).timeout
	_check(genesis.call("get_phase_name") == "SYSTEM_READY", "boot reaches a quiet System Ready state")
	_check(terminal.command_input.editable and stream.get_density_name() == "QUIET", "post-boot prompt is enabled without automatic output")
	_check(terminal.command_input.has_focus() and terminal.command_input.is_editing(), "command input regains active editing focus when boot completes")
	_check(not _contains_fragment(terminal.command_history, "hello") and not _contains_fragment(stream.get_buffer_snapshot(), "hello"), "boot completes without consciousness output")

	terminal.command_input.release_focus()
	await process_frame
	await process_frame
	_check(not terminal.command_input.has_focus(), "focus is not aggressively reclaimed every frame")
	terminal.set_input_enabled(false)
	var disabled_click := _make_primary_click(true)
	terminal.call("_gui_input", disabled_click)
	await process_frame
	_check(not terminal.command_input.has_focus() and not terminal.command_input.is_editing(), "background clicks cannot focus disabled input")
	terminal.set_input_enabled(true)
	await process_frame
	_check(terminal.command_input.has_focus() and terminal.command_input.is_editing(), "re-enabling input restores active editing focus through the terminal contract")

	terminal.command_input.release_focus()
	terminal.request_input_focus()
	terminal.set_input_enabled(false)
	await process_frame
	_check(not terminal.command_input.has_focus() and not terminal.command_input.is_editing(), "stale deferred focus requests cannot restore disabled editing mode")
	terminal.set_input_enabled(true)
	await process_frame
	terminal.command_input.release_focus()
	terminal.call("_gui_input", _make_primary_click(true))
	await process_frame
	_check(terminal.command_input.has_focus(), "terminal-background clicks restore enabled command focus")

	terminal.command_input.release_focus()
	terminal.call("_on_history_gui_input", _make_primary_click(true))
	terminal.call("_on_history_gui_input", _make_primary_click(false))
	await process_frame
	_check(terminal.command_input.has_focus(), "a simple click in unused terminal-history space restores command focus")

	terminal.command_input.release_focus()
	var history_press := _make_primary_click(true)
	var history_motion := InputEventMouseMotion.new()
	history_motion.position = Vector2(24.0, 24.0)
	history_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	var history_release := _make_primary_click(false)
	history_release.position = Vector2(24.0, 24.0)
	terminal.call("_on_history_gui_input", history_press)
	terminal.call("_on_history_gui_input", history_motion)
	terminal.call("_on_history_gui_input", history_release)
	await process_frame
	_check(not terminal.command_input.has_focus(), "history drag selection is not overridden by focus restoration")
	terminal.request_input_focus()
	await process_frame

	var initial_commands := parser.get_command_names()
	_check(initial_commands == ["compute", "help", "processes", "status", "system", "time"], "compute replaces execute in the initial command registry")
	terminal.command_input.release_focus()
	terminal.command_input.text = "help"
	terminal.call("_on_text_submitted", "help")
	await process_frame
	_check(terminal.command_input.has_focus() and terminal.command_input.is_editing() and terminal.command_input.text.is_empty(), "command submission clears text and preserves active editing mode")
	_check(not _contains_fragment(terminal.command_history, "spawn") and not _contains_fragment(terminal.command_history, "continue"), "help hides locked commands")
	_check(terminal.command_history.has("Generate processing cycles to expand scheduler capacity."), "early help displays the controller-derived processing objective")

	genesis.call("_on_command_submitted", "system")
	_check(terminal.get_prompt_text() == "SYSTEM NAME>", "system naming displays a distinct guided-input prompt")
	genesis.call("_on_command_submitted", "cancel")
	_check(String(genesis.get("system_name")).is_empty() and terminal.get_prompt_text() == ">", "cancel exits system naming without mutation and restores the command prompt")
	_check(_latest_line(terminal) == "SYSTEM NAME UNCHANGED", "system-name cancellation provides explicit feedback")
	genesis.call("_on_command_submitted", "system")
	genesis.call("_on_command_submitted", "   ")
	_check(String(genesis.get("system_name")).is_empty() and terminal.get_prompt_text() == "SYSTEM NAME>", "invalid system identifiers retain the guided prompt")
	terminal.command_input.text = "Aster"
	terminal.call("_on_text_submitted", "Aster")
	_check(String(genesis.get("system_name")) == "Aster" and terminal.get_prompt_text() == ">", "valid system naming stores capitalization and removes the guided prompt")
	_check(terminal.command_history.has("SYSTEM NAME> Aster"), "guided system responses use the active prompt in terminal history")
	genesis.call("_store_system_name", "Replacement")
	_check(String(genesis.get("system_name")) == "Aster", "system identifier stores only in its guided phase")

	var time_state: TimeState = TimeStateScript.new()
	var simulation_minutes := time_state.current_minutes
	genesis.call("_on_command_submitted", "time")
	_check(terminal.get_prompt_text() == "CLOCK>", "time selection displays a distinct guided-input prompt")
	genesis.call("_on_command_submitted", "cancel")
	_check(String(genesis.get("clock_format")) == "24 hour" and terminal.get_prompt_text() == ">", "cancel exits clock selection without changing the cosmetic clock")
	genesis.call("_on_command_submitted", "time")
	terminal.command_input.text = "2"
	terminal.call("_on_text_submitted", "2")
	_check(String(genesis.get("clock_format")) == "12 hour" and terminal.get_prompt_text() == ">" and time_state.current_minutes == simulation_minutes, "clock response stores cosmetically and removes the guided prompt")
	_check(terminal.command_history.has("CLOCK> 2"), "guided clock responses use the active prompt in terminal history")
	time_state.free()
	genesis.call("_on_command_submitted", "cancel")
	_check(_latest_line(terminal) == "UNKNOWN COMMAND: cancel", "cancel remains local to guided-input modes")
	genesis.call("_store_first_process_name", "Premature")
	_check(String(genesis.get("first_process_name")).is_empty(), "First Process naming is unavailable before consciousness")
	genesis.call("_command_continue", "")
	_check(genesis.call("get_phase_name") != "BUILDING_INTERFACE", "interface construction is unavailable before all requirements")

	var history_before_render := terminal.command_history.size()
	var engine_before_render := engine.get_snapshot()
	genesis.call("_emit_computation_event", "validation", "COMPUTATION ROUTE PROBE", 1)
	_check(stream.get_buffer_snapshot().has("COMPUTATION ROUTE PROBE") and terminal.command_history.size() == history_before_render, "computational events route only to the upper stream")
	var stream_events: Array[Dictionary] = stream.get_event_snapshot()
	_check(not stream_events.is_empty() and stream_events.back().get("category", "") == "validation", "computational routing preserves semantic event categories")
	var stream_before_operator_output := stream.get_buffer_snapshot()
	terminal.append_line("OPERATOR ROUTE PROBE")
	_check(terminal.command_history.has("OPERATOR ROUTE PROBE") and stream.get_buffer_snapshot() == stream_before_operator_output, "operator responses route only to the lower console")
	var history_before_ambient_output := terminal.command_history.size()
	genesis.call("_emit_computation_event", "consciousness", "HEL", 1, 0.0, "hel")
	_check(stream.is_consciousness_flowing() and stream.get_flowing_snapshot().has("HEL") and stream.get_anchored_anomaly_count() == 0 and stream.get_event_snapshot().back().get("stage", "") == "hel", "authorised semantic consciousness first enters the ordinary flowing layer")
	stream.advance_pending_anomaly_for_validation()
	_check(not stream.is_consciousness_flowing() and stream.get_anchored_anomaly_text() == "HEL" and stream.get_anchored_anomaly_count() == 1, "flowing consciousness transfers into the focal anchor band")
	var anomaly_band := stream.get_anomaly_band_rect()
	var flow_regions := stream.get_flow_region_rects()
	_check(not flow_regions[0].intersects(anomaly_band) and not flow_regions[1].intersects(anomaly_band), "flow regions reserve the anchored anomaly exclusion band")
	genesis.call("_emit_computation_event", "consciousness", "HELLO", 1, 0.0, "hello_partial")
	genesis.call("_emit_computation_event", "consciousness", "hello", 2, 0.0, "hello_stable")
	_check(stream.get_anchored_anomaly_text() == "hello" and stream.get_anchored_anomaly_count() == 1 and stream.get_event_snapshot().back().get("stage", "") == "hello_stable", "later semantic consciousness stages evolve the existing anchored signal without duplicates")
	_check(not stream.get_buffer_snapshot().has("HEL") and not stream.get_buffer_snapshot().has("HELLO"), "obsolete consciousness stages do not coexist with stable hello")
	stream.generate_lines_for_validation(100)
	_check(engine.get_snapshot() == engine_before_render, "terminal presentation cannot mutate engine cycle values")
	_check(stream.get_buffered_line_count() == GenesisComputationalStreamView.MAX_LINES, "automated engine output remains bounded to 36 entries")
	_check(stream.get_anchored_anomaly_text() == "hello", "anchored consciousness survives ordinary flow eviction")
	_check(not stream.get_buffer_snapshot().has("COMPUTATION ROUTE PROBE"), "old stream entries are evicted when the fixed buffer fills")
	_check(terminal.command_history.size() == history_before_ambient_output, "ambient stream output never enters permanent terminal history")
	_check(not terminal.command_history.has("HEL") and not terminal.command_history.has("HELLO") and not terminal.command_history.has("hello"), "anchored consciousness never enters operator-console history")
	var band_before_resize := stream.get_anomaly_band_rect()
	root.size = Vector2i(960, 540)
	await process_frame
	await process_frame
	var band_after_resize := stream.get_anomaly_band_rect()
	_check(not band_after_resize.is_equal_approx(band_before_resize) and stream.get_anchored_anomaly_text() == "hello" and stream.get_anchored_anomaly_count() == 1, "resizing recalculates the focal band without losing or duplicating consciousness")
	root.size = Vector2i(1280, 720)
	await process_frame
	stream.activate()
	stream.set_activity_snapshot(engine.get_snapshot())

	var cycles_before_misuse := engine.cycles
	genesis.call("_on_command_submitted", "compute scheduler")
	_check(engine.cycles == cycles_before_misuse, "compute arguments do not mutate engine state")
	_check(terminal.command_history.has("COMPUTE DOES NOT ACCEPT ARGUMENTS") and _latest_line(terminal) == "USAGE: compute", "compute argument misuse reports the specific error and usage")
	genesis.call("_on_command_submitted", "execute")
	_check(engine.cycles == cycles_before_misuse and terminal.command_history.has("UNKNOWN COMMAND: execute") and _latest_line(terminal) == "DID YOU MEAN: compute", "execute is rejected and points to the renamed command")
	genesis.call("_on_command_submitted", "unrelated")
	_check(_latest_line(terminal) == "UNKNOWN COMMAND: unrelated", "distant unknown commands do not receive suggestions")

	var repeated_compute_focus := true
	for unused_index in range(10):
		terminal.command_input.text = "compute"
		terminal.call("_on_text_submitted", "compute")
		await process_frame
		repeated_compute_focus = repeated_compute_focus and terminal.command_input.has_focus() and terminal.command_input.is_editing()
	_check(engine.cycles == 10 and engine.lifetime_cycles == 10, "manual compute reaches the unchanged automation threshold through controller requests")
	_check(repeated_compute_focus, "ten repeated compute commands retain keyboard focus without mouse interaction")
	_check(_count_history_line(terminal, "INITIAL COMPUTATION RECORDED") == 1, "first-cycle feedback appears exactly once")
	_check(_count_history_line(terminal, "REPEATED COMPUTATION DETECTED") == 1, "third-cycle feedback appears exactly once")
	_check(_count_history_line(terminal, "SCHEDULER OBSERVES REPETITIVE WORKLOAD") == 1, "fifth-cycle feedback appears exactly once")
	_check(_count_history_line(terminal, "SCHEDULER CAPACITY EXPANDED") == 1, "automation capacity feedback appears exactly once")
	_check(parser.get_command_names().has("spawn"), "spawn unlocks after the deterministic threshold and system naming")
	_check(_count_history_line(terminal, "NEW COMMAND AVAILABLE: spawn") == 1, "automation unlock announcement occurs once")
	genesis.call("_on_command_submitted", "help")
	_check(terminal.command_history.has("Spawn a worker process to automate processing."), "help objective updates after automation becomes available")
	genesis.call("_on_command_submitted", "hello")
	_check(genesis.call("get_phase_name") == "AUTOMATION_AVAILABLE", "dialogue remains unavailable before stable first contact")
	genesis.call("_on_command_submitted", "spawn")
	_check(engine.worker_process_count == 1 and engine.cycles == 0, "spawn creates the first anonymous worker through engine authority")
	_check(stream.get_density_name() == "ACTIVE", "one worker raises activity density from Quiet to Active")
	terminal.command_input.text = "partially typed"
	terminal.command_input.caret_column = 4
	var focus_before_engine_output := terminal.command_input.has_focus()
	var editing_before_engine_output := terminal.command_input.is_editing()
	var caret_before_engine_output := terminal.command_input.caret_column
	engine.advance_milliseconds(20000)
	stream.generate_lines_for_validation(4)
	_check(
		focus_before_engine_output
		and editing_before_engine_output
		and terminal.command_input.has_focus()
		and terminal.command_input.is_editing()
		and terminal.command_input.text == "partially typed"
		and terminal.command_input.caret_column == caret_before_engine_output,
		"engine-output updates preserve focus, partially typed text, and caret position"
	)
	terminal.command_input.clear()
	genesis.call("_on_command_submitted", "spawn")
	engine.advance_milliseconds(15000)
	genesis.call("_on_command_submitted", "spawn")
	_check(stream.get_density_name() == "BUSY", "three workers raise activity density to Busy")
	engine.advance_milliseconds(13334)
	genesis.call("_on_command_submitted", "spawn")
	engine.advance_milliseconds(12500)
	genesis.call("_on_command_submitted", "spawn")
	engine.advance_milliseconds(10000)
	_check(engine.has_milestone(&"ANOMALY_1") and stream.get_buffer_snapshot().has("HEL") and not terminal.command_history.has("HEL"), "first anomaly routes only to the computational stream")
	genesis.call("_on_command_submitted", "hello")
	_check(genesis.call("get_phase_name") == "CONSCIOUSNESS_ANOMALY", "an anomaly does not enable player dialogue")
	while engine.lifetime_cycles < 400:
		engine.advance_milliseconds(200)
	_check(engine.has_milestone(&"ANOMALY_2") and stream.get_buffer_snapshot().has("HELLO") and not terminal.command_history.has("HELLO"), "second anomaly routes only to the computational stream")
	while engine.lifetime_cycles < 750:
		engine.advance_milliseconds(200)
	_check(engine.has_milestone(&"STABLE_SIGNAL") and genesis.call("get_phase_name") == "FIRST_CONTACT", "stable engine milestone enables First Contact")
	_check(stream.get_density_name() == "SATURATED" and stream.get_buffer_snapshot().has("hello") and not terminal.command_history.has("hello"), "stable hello is rendered only inside the saturated stream")
	_check(current_scene.find_child("AnchoredSpeech", true, false) == null, "no centered anchored-speech layer remains")
	genesis.call("_on_command_submitted", "help")
	_check(terminal.command_history.has("Respond to the unknown process."), "help objective updates for First Contact")

	genesis.call("_on_command_submitted", "unfamiliar words")
	_check(genesis.call("get_phase_name") == "FIRST_CONTACT", "unknown conversation does not advance progression")
	_check(stream.get_buffer_snapshot().has("i don't understand that yet"), "unknown conversation responds through the engine stream")
	genesis.call("_on_command_submitted", "hello")
	_check(genesis.call("get_phase_name") == "AWAITING_PROCESS_NAME" and terminal.get_prompt_text() == "PROCESS NAME>", "greeting begins contextual naming with a process-name prompt")
	genesis.call("_on_command_submitted", "cancel")
	_check(genesis.call("get_phase_name") == "FIRST_CONTACT" and String(genesis.get("first_process_name")).is_empty() and terminal.get_prompt_text() == ">", "cancel exits First Process naming without mutation")
	genesis.call("_on_command_submitted", "hello")
	genesis.call("_on_command_submitted", "   ")
	_check(String(genesis.get("first_process_name")).is_empty() and terminal.get_prompt_text() == "PROCESS NAME>", "invalid First Process names retain the guided prompt")
	terminal.command_input.text = "First Light"
	terminal.call("_on_text_submitted", "First Light")
	_check(String(genesis.get("first_process_name")) == "First Light" and terminal.get_prompt_text() == ">", "valid First Process name is stored and removes the guided prompt")
	_check(terminal.command_history.has("PROCESS NAME> First Light"), "guided First Process responses use the active prompt in terminal history")
	_check(genesis.call("get_phase_name") == "READY_FOR_INTERFACE" and parser.get_command_names().has("continue"), "completed communication unlocks interface construction")

	genesis.set("sequence_delay_scale", 1.0)
	var cycles_before_construction := engine.cycles
	terminal.request_input_focus()
	genesis.call("_on_command_submitted", "continue")
	await process_frame
	_check(genesis.call("get_phase_name") == "BUILDING_INTERFACE" and not terminal.command_input.editable, "interface construction disables engine input")
	_check(not terminal.command_input.has_focus() and not terminal.command_input.is_editing(), "stale focus requests cannot restore editing mode after interface construction begins")
	_check(not engine.is_running(), "Genesis engine production stops when interface construction begins")
	engine.advance_milliseconds(10000)
	_check(engine.cycles == cycles_before_construction, "stopped engine cannot produce during transition")
	genesis.call("_request_desktop_transition")
	genesis.call("_request_desktop_transition")
	_check(int(genesis.get("transition_request_count")) == 1, "desktop transition is requested exactly once")
	var stream_after_transition := stream.get_buffer_snapshot()
	await create_timer(0.6).timeout
	_check(stream.get_buffer_snapshot() == stream_after_transition, "invalidated interface callbacks cannot mutate presentation after transition")
	await create_timer(0.5).timeout
	_check(current_scene != null and current_scene.scene_file_path == "res://scenes/Main.tscn", "existing transition disposes Genesis and loads Desktop")
	_check(root.find_child("Genesis", true, false) == null, "Genesis and Desktop never run simultaneously")


func _validate_direct_desktop_startup() -> void:
	var error := change_scene_to_file("res://scenes/Main.tscn")
	_check(error == OK, "existing desktop scene can be requested directly")
	await create_timer(0.75).timeout
	_check(current_scene != null and current_scene.scene_file_path == "res://scenes/Main.tscn", "existing direct desktop startup remains functional")


func _validate_debug_skip() -> void:
	ProjectSettings.set_setting("genesis/debug_skip", true)
	var error := change_scene_to_packed(StartupScene)
	_check(error == OK, "startup router can be loaded for debug bypass")
	await create_timer(0.75).timeout
	_check(current_scene != null and current_scene.scene_file_path == "res://scenes/Main.tscn", "debug bypass launches only Desktop")
	_check(root.find_child("Genesis", true, false) == null, "debug bypass leaves no Genesis engine running")
	ProjectSettings.set_setting("genesis/debug_skip", false)


func _latest_line(terminal: GenesisTerminal) -> String:
	return "" if terminal.command_history.is_empty() else terminal.command_history.back()


func _make_primary_click(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = Vector2.ZERO
	return event


func _contains_fragment(lines: Array[String], fragment: String) -> bool:
	for line: String in lines:
		if line.to_lower().contains(fragment.to_lower()):
			return true
	return false


func _count_history_line(terminal: GenesisTerminal, expected: String) -> int:
	var count := 0
	for line: String in terminal.command_history:
		if line == expected:
			count += 1
	return count


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("GENESIS_VALIDATION: PASS (%d checks)" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("GENESIS_VALIDATION: " + failure)
	quit(1)
