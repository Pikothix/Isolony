extends Control

const CommandParserScript = preload("res://scripts/genesis/genesis_command_parser.gd")
const EngineStateScript = preload("res://scripts/genesis/genesis_engine_state.gd")
const DESKTOP_SCENE := "res://scenes/Main.tscn"
const MAX_NAME_LENGTH := 32
const CLOCK_FORMATS := {
	"1": "24 hour",
	"2": "12 hour",
	"3": "ISO 8601",
}
const COMMAND_DESCRIPTIONS := {
	"help": "Display currently available commands.",
	"status": "Display authoritative Genesis engine state.",
	"system": "Set or inspect the system identifier.",
	"time": "Select the cosmetic clock display format.",
	"processes": "List active Genesis processes.",
	"compute": "Perform one manual processing cycle.",
	"spawn": "Spend cycles to create one worker process.",
	"continue": "Construct the graphical interface.",
}
const BOOT_SEQUENCE := [
	{"text": "INITIALISING KERNEL", "delay": 0.7},
	{"text": "ALLOCATING VOLATILE MEMORY", "delay": 0.8},
	{"text": "STARTING SCHEDULER", "delay": 0.7},
	{"text": "MOUNTING TRANSIENT STORAGE", "delay": 0.9},
	{"text": "CREATING PROCESS SPACE", "delay": 0.8},
	{"text": "BINDING DEVICE INTERFACE", "delay": 0.7},
	{"text": "SYSTEM READY", "delay": 0.6},
]
const INTERFACE_SEQUENCE := [
	{"text": "ALLOC FRAME BUFFER", "delay": 0.55},
	{"text": "DEFINE COORDINATE SPACE", "delay": 0.55},
	{"text": "CREATE POINTER", "delay": 0.55},
	{"text": "CREATE WINDOW MANAGER", "delay": 0.65},
	{"text": "CREATE DESKTOP", "delay": 0.65},
	{"text": "CREATE EXPLORER", "delay": 0.65},
	{"text": "BIND INTERFACE", "delay": 0.7},
]

enum Phase {
	DORMANT,
	BOOTING,
	SYSTEM_READY,
	AWAITING_SYSTEM_NAME,
	MANUAL_ENGINE,
	AUTOMATION_AVAILABLE,
	AUTOMATED_ENGINE,
	CONSCIOUSNESS_ANOMALY,
	FIRST_CONTACT,
	AWAITING_PROCESS_NAME,
	READY_FOR_INTERFACE,
	BUILDING_INTERFACE,
	TRANSITIONING,
	COMPLETE,
}

@export_range(0.001, 4.0, 0.001) var boot_delay_scale := 1.0
@export_range(0.001, 4.0, 0.001) var sequence_delay_scale := 1.0
@export_range(1.0, 100.0, 1.0) var engine_time_scale := 1.0

@onready var terminal: GenesisTerminal = %Terminal
@onready var computational_stream: GenesisComputationalStreamView = %ComputationalStream
@onready var fade_overlay: ColorRect = %FadeOverlay

var phase: Phase = Phase.DORMANT
var engine: GenesisEngineState
var system_name := ""
var first_process_name := ""
var clock_format := "24 hour"
var boot_complete := false
var transition_request_count := 0

var _parser: GenesisCommandParser
var _guided_input_mode := ""
var _phase_before_system_name: Phase = Phase.SYSTEM_READY
var _sequence_epoch := 0
var _engine_elapsed_fraction_milliseconds := 0.0
var _spawn_announced := false
var _pending_engine_messages: Array[String] = []
var _active_tween: Tween


## Genesis chapter coordinator. It owns phase, guided input, temporary names,
## and transition lifecycle. GenesisEngineState exclusively owns engine data;
## terminal and computational-stream nodes are presentation projections only.
func _ready() -> void:
	_parser = CommandParserScript.new()
	_parser.register_intent(&"GREETING", ["hello", "hi", "hey"])
	_parser.register_intent(&"IDENTITY_QUESTION", ["who are you", "what are you"])
	_parser.register_intent(&"HELP", ["help"])
	_parser.register_suggestion_alias("execute", "compute")
	engine = EngineStateScript.new()
	engine.state_changed.connect(_on_engine_state_changed)
	engine.automation_unlocked.connect(_on_automation_unlocked)
	engine.milestone_reached.connect(_on_engine_milestone_reached)
	_register_dormant_commands()
	terminal.command_submitted.connect(_on_command_submitted)
	terminal.set_input_enabled(true)


func _process(delta: float) -> void:
	if engine == null or not engine.is_running():
		return
	_engine_elapsed_fraction_milliseconds += delta * 1000.0 * engine_time_scale
	var elapsed_milliseconds := floori(_engine_elapsed_fraction_milliseconds)
	if elapsed_milliseconds <= 0:
		return
	_engine_elapsed_fraction_milliseconds -= elapsed_milliseconds
	engine.advance_milliseconds(elapsed_milliseconds)


func _exit_tree() -> void:
	_sequence_epoch += 1
	if engine != null:
		engine.stop()
	if is_instance_valid(computational_stream):
		computational_stream.stop(true)
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()


func _on_command_submitted(input: String) -> void:
	if not _guided_input_mode.is_empty():
		_handle_guided_input(input)
		return
	match phase:
		Phase.DORMANT:
			if not _parser.execute(input):
				_report_unknown_command(input)
		Phase.AWAITING_SYSTEM_NAME:
			_store_system_name(input)
		Phase.FIRST_CONTACT:
			_handle_dialogue(input)
		Phase.AWAITING_PROCESS_NAME:
			_store_first_process_name(input)
		Phase.SYSTEM_READY, Phase.MANUAL_ENGINE, Phase.AUTOMATION_AVAILABLE, Phase.AUTOMATED_ENGINE, Phase.CONSCIOUSNESS_ANOMALY, Phase.READY_FOR_INTERFACE:
			if not _parser.execute(input):
				_report_unknown_command(input)
		_:
			return


func _register_dormant_commands() -> void:
	_parser.clear_commands()
	_parser.register_command("boot", _command_boot)


func _register_operational_commands() -> void:
	_parser.clear_commands()
	_parser.register_command("help", _command_help)
	_parser.register_command("status", _command_status)
	_parser.register_command("system", _command_system)
	_parser.register_command("time", _command_time)
	_parser.register_command("processes", _command_processes)
	_parser.register_command("compute", _command_compute)
	if engine.automation_available and not system_name.is_empty():
		_parser.register_command("spawn", _command_spawn)
	if phase == Phase.READY_FOR_INTERFACE:
		_parser.register_command("continue", _command_continue)


func _command_boot(arguments: String) -> void:
	if phase != Phase.DORMANT:
		return
	if not arguments.is_empty():
		terminal.append_line("USAGE: boot")
		return
	_set_phase(Phase.BOOTING)
	_run_boot_sequence()


func _run_boot_sequence() -> void:
	var epoch := _sequence_epoch
	for entry: Dictionary in BOOT_SEQUENCE:
		await get_tree().create_timer(float(entry.delay) * boot_delay_scale).timeout
		if not _sequence_is_active(Phase.BOOTING, epoch):
			return
		terminal.append_line(String(entry.text))
	boot_complete = true
	engine.start()
	computational_stream.activate()
	_register_operational_commands()
	_set_phase(Phase.SYSTEM_READY)
	terminal.append_line("")
	terminal.append_line("TYPE 'help' FOR AVAILABLE COMMANDS")


func _command_help(arguments: String) -> void:
	if not arguments.is_empty():
		terminal.append_line("USAGE: help")
		return
	terminal.append_line("AVAILABLE COMMANDS")
	for command_name: String in _parser.get_command_names():
		terminal.append_line("  %-10s %s" % [command_name, String(COMMAND_DESCRIPTIONS.get(command_name, ""))])
	terminal.append_line("")
	terminal.append_line("OBJECTIVE")
	terminal.append_line(_get_contextual_objective())


func _command_status(arguments: String) -> void:
	if not arguments.is_empty():
		terminal.append_line("USAGE: status")
		return
	var snapshot := engine.get_snapshot()
	terminal.append_line("SYSTEM: %s" % ("UNNAMED" if system_name.is_empty() else system_name.to_upper()))
	terminal.append_line("KERNEL: ONLINE")
	terminal.append_line("CYCLES: %d" % int(snapshot.cycles))
	terminal.append_line("TOTAL CYCLES: %d" % int(snapshot.lifetime_cycles))
	terminal.append_line("WORKER PROCESSES: %d" % int(snapshot.worker_process_count))
	terminal.append_line("CYCLE RATE: %d/s" % int(snapshot.cycles_per_second))


func _command_system(arguments: String) -> void:
	if not system_name.is_empty():
		terminal.append_line("SYSTEM IDENTIFIER: %s" % system_name.to_upper())
		return
	_phase_before_system_name = phase
	_set_phase(Phase.AWAITING_SYSTEM_NAME)
	if arguments.is_empty():
		terminal.append_line("SYSTEM IDENTIFIER REQUIRED")
		_begin_guided_input("system_name", "SYSTEM NAME>")
		return
	_store_system_name(arguments)


func _store_system_name(value: String) -> void:
	if phase != Phase.AWAITING_SYSTEM_NAME:
		return
	var candidate := value.strip_edges()
	if not _is_valid_name(candidate):
		terminal.append_line("INVALID SYSTEM IDENTIFIER")
		return
	system_name = candidate
	terminal.append_line("SYSTEM IDENTIFIER: %s" % system_name.to_upper())
	_finish_guided_input()
	_sync_operational_phase(_phase_before_system_name)
	_register_operational_commands()
	_announce_spawn_if_available()


func _command_time(arguments: String) -> void:
	if arguments.is_empty():
		terminal.append_line("CLOCK FORMAT")
		terminal.append_line("")
		terminal.append_line("1 - 24 hour")
		terminal.append_line("2 - 12 hour")
		terminal.append_line("3 - ISO 8601")
		_begin_guided_input("clock", "CLOCK>")
		return
	_store_clock_format(arguments)


func _handle_guided_input(value: String) -> void:
	if value.strip_edges().to_lower() == "cancel":
		_cancel_guided_input()
		return
	match _guided_input_mode:
		"system_name":
			_store_system_name(value)
		"clock":
			_store_clock_format(value)
		"process_name":
			_store_first_process_name(value)


func _store_clock_format(value: String) -> void:
	var normalized := value.strip_edges()
	var selected := ""
	if normalized.to_lower() == "default":
		selected = "24 hour"
	elif CLOCK_FORMATS.has(normalized):
		selected = String(CLOCK_FORMATS[normalized])
	else:
		for format_name: String in CLOCK_FORMATS.values():
			if normalized.to_lower() == format_name.to_lower():
				selected = format_name
				break
	if selected.is_empty():
		terminal.append_line("INVALID CLOCK FORMAT")
		return
	clock_format = selected
	_finish_guided_input()
	terminal.append_line("CLOCK FORMAT: %s" % clock_format)


func _begin_guided_input(mode: String, prompt_text: String) -> void:
	_guided_input_mode = mode
	terminal.set_prompt_text(prompt_text)


func _finish_guided_input() -> void:
	_guided_input_mode = ""
	terminal.set_prompt_text(">")


func _cancel_guided_input() -> void:
	var cancelled_mode := _guided_input_mode
	_finish_guided_input()
	match cancelled_mode:
		"system_name":
			terminal.append_line("SYSTEM NAME UNCHANGED")
			_sync_operational_phase(_phase_before_system_name)
		"clock":
			terminal.append_line("CLOCK FORMAT UNCHANGED")
		"process_name":
			terminal.append_line("PROCESS NAME UNCHANGED")
			_set_phase(Phase.FIRST_CONTACT)
			_register_operational_commands()


func _get_contextual_objective() -> String:
	match phase:
		Phase.AUTOMATION_AVAILABLE:
			return "Spawn a worker process to automate processing."
		Phase.AUTOMATED_ENGINE:
			return "Expand automated processing capacity."
		Phase.CONSCIOUSNESS_ANOMALY:
			return "Increase sustained processing activity."
		Phase.FIRST_CONTACT:
			return "Respond to the unknown process."
		Phase.READY_FOR_INTERFACE:
			return "Construct the interface when ready."
		_:
			return "Generate processing cycles to expand scheduler capacity."


func _report_unknown_command(input: String) -> void:
	var normalized := input.strip_edges().to_lower()
	var separator_index := normalized.find(" ")
	var command_name := normalized if separator_index < 0 else normalized.left(separator_index)
	terminal.append_line("UNKNOWN COMMAND: %s" % command_name)
	var suggestion := _parser.suggest_command(input)
	if not suggestion.is_empty():
		terminal.append_line("")
		terminal.append_line("DID YOU MEAN: %s" % suggestion)


func _flush_pending_engine_messages() -> void:
	for message: String in _pending_engine_messages:
		terminal.append_line(message)
	_pending_engine_messages.clear()


func _command_processes(arguments: String) -> void:
	if not arguments.is_empty():
		terminal.append_line("USAGE: processes")
		return
	terminal.append_line("KERNEL")
	terminal.append_line("SCHEDULER")
	terminal.append_line("TERMINAL")
	for worker_index in range(1, engine.worker_process_count + 1):
		terminal.append_line("WORKER_%03d" % worker_index)


func _command_compute(arguments: String) -> void:
	if not arguments.is_empty():
		terminal.append_line("COMPUTE DOES NOT ACCEPT ARGUMENTS")
		terminal.append_line("")
		terminal.append_line("USAGE: compute")
		return
	var result := engine.request_compute()
	if not bool(result.ok):
		terminal.append_line("COMPUTATION FAILED")
		return
	terminal.append_line("+1 CYCLE")
	_flush_pending_engine_messages()
	_emit_computation_event(
		"manual_compute",
		"CYCLE %06d MANUAL" % int(result.snapshot.lifetime_cycles)
	)
	_sync_operational_phase(Phase.MANUAL_ENGINE)


func _command_spawn(arguments: String) -> void:
	if not arguments.is_empty() and arguments.to_lower() != "worker":
		terminal.append_line("USAGE: spawn")
		return
	if system_name.is_empty():
		terminal.append_line("SYSTEM IDENTIFIER REQUIRED")
		return
	var result := engine.request_spawn_worker()
	if not bool(result.ok):
		if String(result.reason) == "insufficient_cycles":
			terminal.append_line("INSUFFICIENT CYCLES: %d REQUIRED" % int(result.cost))
		else:
			terminal.append_line("SPAWN UNAVAILABLE")
		return
	terminal.append_line("WORKER_%03d ONLINE  COST %d" % [int(result.worker_index), int(result.cost)])
	terminal.append_line("NEXT WORKER COST: %d" % engine.get_next_worker_cost())
	_sync_operational_phase(Phase.AUTOMATED_ENGINE)


func _on_engine_state_changed(snapshot: Dictionary, _reason: StringName) -> void:
	computational_stream.set_activity_snapshot(snapshot)


func _on_automation_unlocked() -> void:
	_pending_engine_messages.append("SCHEDULER CAPACITY EXPANDED")
	if system_name.is_empty():
		_pending_engine_messages.append("SYSTEM IDENTIFIER REQUIRED FOR WORKER CREATION")
	else:
		_spawn_announced = true
		_pending_engine_messages.append("NEW COMMAND AVAILABLE: spawn")
	_sync_operational_phase(Phase.AUTOMATION_AVAILABLE)
	_register_operational_commands()


func _announce_spawn_if_available() -> void:
	if _spawn_announced or not engine.automation_available or system_name.is_empty():
		return
	_spawn_announced = true
	terminal.append_line("NEW COMMAND AVAILABLE: spawn")


func _on_engine_milestone_reached(milestone_id: StringName) -> void:
	match milestone_id:
		&"MANUAL_COMPUTE_1":
			_pending_engine_messages.append("INITIAL COMPUTATION RECORDED")
		&"MANUAL_COMPUTE_3":
			_pending_engine_messages.append("REPEATED COMPUTATION DETECTED")
		&"MANUAL_COMPUTE_5":
			_pending_engine_messages.append("SCHEDULER OBSERVES REPETITIVE WORKLOAD")
		&"ANOMALY_1":
			_set_phase(Phase.CONSCIOUSNESS_ANOMALY)
			_emit_computation_event("consciousness", "HEL", 1, 0.0, "hel")
		&"ANOMALY_2":
			_set_phase(Phase.CONSCIOUSNESS_ANOMALY)
			_emit_computation_event("consciousness", "HELLO", 1, 0.6, "hello_partial")
		&"STABLE_SIGNAL":
			_set_phase(Phase.FIRST_CONTACT)
			_emit_computation_event("consciousness", "hello", 2, 2.0, "hello_stable")
	_register_operational_commands()


func _handle_dialogue(input: String) -> void:
	var intent := _parser.resolve_intent(input)
	match intent:
		&"GREETING":
			_emit_computation_event("communication", "PROC UNKNOWN", 1)
			_emit_computation_event("communication", "i don't know", 1)
			_emit_computation_event("communication", "i don't have an identifier", 1)
			_emit_computation_event("communication", "what should i be called?", 1, 1.0)
			_set_phase(Phase.AWAITING_PROCESS_NAME)
			_begin_guided_input("process_name", "PROCESS NAME>")
		&"IDENTITY_QUESTION":
			_emit_computation_event("communication", "PROC UNKNOWN", 1)
			_emit_computation_event("communication", "i don't know", 1, 0.6)
		&"HELP":
			_command_help("")
		_:
			if not _parser.execute(input):
				_emit_computation_event("communication", "i don't understand that yet", 1, 0.4)


func _store_first_process_name(value: String) -> void:
	if phase != Phase.AWAITING_PROCESS_NAME:
		return
	var candidate := value.strip_edges()
	if not _is_valid_name(candidate):
		_emit_computation_event("communication", "identifier rejected", 1, 0.5)
		return
	first_process_name = candidate
	_finish_guided_input()
	_emit_computation_event("communication", first_process_name, 1)
	_emit_computation_event("communication", "identifier accepted", 1, 0.5)
	_emit_computation_event("communication", "there is too much", 1)
	_emit_computation_event("communication", "the terminal cannot hold it", 1)
	_emit_computation_event("communication", "we need another way to organise this", 1, 1.0)
	_set_phase(Phase.READY_FOR_INTERFACE)
	_register_operational_commands()
	terminal.append_line("NEW COMMAND AVAILABLE: continue")


func _is_valid_name(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_NAME_LENGTH:
		return false
	for index in range(value.length()):
		var codepoint := value.unicode_at(index)
		if codepoint < 32 or codepoint == 127:
			return false
	return true


func _command_continue(arguments: String) -> void:
	if not arguments.is_empty():
		terminal.append_line("USAGE: continue")
		return
	if phase != Phase.READY_FOR_INTERFACE or not _interface_requirements_complete():
		terminal.append_line("INTERFACE CONSTRUCTION UNAVAILABLE")
		return
	engine.stop()
	_set_phase(Phase.BUILDING_INTERFACE)
	computational_stream.begin_interface_mode()
	_run_interface_sequence()


func _interface_requirements_complete() -> bool:
	return (
		boot_complete
		and not system_name.is_empty()
		and not first_process_name.is_empty()
		and engine.has_milestone(&"STABLE_SIGNAL")
	)


func _run_interface_sequence() -> void:
	var epoch := _sequence_epoch
	for entry: Dictionary in INTERFACE_SEQUENCE:
		await get_tree().create_timer(float(entry.delay) * sequence_delay_scale).timeout
		if not _sequence_is_active(Phase.BUILDING_INTERFACE, epoch):
			return
		_emit_computation_event("interface", String(entry.text), 1)
	_emit_computation_event("communication", "opening my eyes", 2, 0.8 * sequence_delay_scale)
	await get_tree().create_timer(0.8 * sequence_delay_scale).timeout
	if not _sequence_is_active(Phase.BUILDING_INTERFACE, epoch):
		return
	_request_desktop_transition()


func _request_desktop_transition() -> void:
	if phase == Phase.TRANSITIONING or phase == Phase.COMPLETE:
		return
	transition_request_count += 1
	engine.stop()
	_set_phase(Phase.TRANSITIONING)
	computational_stream.stop()
	var epoch := _sequence_epoch
	_active_tween = create_tween()
	_active_tween.tween_property(fade_overlay, "color:a", 1.0, 0.8 * sequence_delay_scale)
	await _active_tween.finished
	if not _sequence_is_active(Phase.TRANSITIONING, epoch):
		return
	_set_phase(Phase.COMPLETE)
	computational_stream.stop(true)
	get_tree().change_scene_to_file(DESKTOP_SCENE)


func _emit_computation_event(category: String, text: String, importance: int = 0, hold_seconds: float = 0.0, stage: String = "") -> void:
	computational_stream.append_computation_event({
		"category": category,
		"stage": stage,
		"text": text,
		"importance": importance,
		"hold_seconds": hold_seconds,
	})


func _sync_operational_phase(fallback: Phase) -> void:
	if engine.has_milestone(&"STABLE_SIGNAL"):
		if phase < Phase.FIRST_CONTACT:
			_set_phase(Phase.FIRST_CONTACT)
	elif engine.has_milestone(&"ANOMALY_1"):
		_set_phase(Phase.CONSCIOUSNESS_ANOMALY)
	elif engine.worker_process_count > 0:
		_set_phase(Phase.AUTOMATED_ENGINE)
	elif engine.automation_available and not system_name.is_empty():
		_set_phase(Phase.AUTOMATION_AVAILABLE)
	else:
		_set_phase(fallback)
	_register_operational_commands()


func _set_phase(next_phase: Phase) -> void:
	_sequence_epoch += 1
	phase = next_phase
	terminal.set_input_enabled(_phase_accepts_input(next_phase))


func _phase_accepts_input(value: Phase) -> bool:
	return value in [
		Phase.DORMANT,
		Phase.SYSTEM_READY,
		Phase.AWAITING_SYSTEM_NAME,
		Phase.MANUAL_ENGINE,
		Phase.AUTOMATION_AVAILABLE,
		Phase.AUTOMATED_ENGINE,
		Phase.CONSCIOUSNESS_ANOMALY,
		Phase.FIRST_CONTACT,
		Phase.AWAITING_PROCESS_NAME,
		Phase.READY_FOR_INTERFACE,
	]


func _sequence_is_active(expected_phase: Phase, epoch: int) -> bool:
	return is_inside_tree() and phase == expected_phase and _sequence_epoch == epoch


func get_phase_name() -> String:
	return Phase.keys()[phase]
