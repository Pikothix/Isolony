extends Control
class_name GenesisEngineState

signal output_requested(text: String, category: StringName)
signal state_changed(snapshot: Dictionary)
signal ui_feature_unlocked(feature_id: StringName)
signal discovery_created(event: Dictionary)
signal presentation_sequence_requested(sequence_id: StringName, context: Dictionary)
signal runtime_log_entry_created(entry: Dictionary)
signal runtime_log_reset
signal terminal_section_requested(title: String, rows: Array)

## Authoritative runtime state for the Genesis vertical slice.
## Terminal presentation may request commands and read snapshots, but only this
## controller validates and mutates cycles, workers, packages, and unlocks.

const PackageDefinitions = preload("res://scripts/genesis/genesis_package_definitions.gd")
const EventStateScript = preload("res://scripts/genesis/genesis_event_state.gd")
const RuntimeLogScript = preload("res://scripts/genesis/genesis_runtime_log.gd")

const BASE_WORKER_COST := 10.0
const WORKER_COST_GROWTH := 1.1
const WORKER_CYCLES_PER_SECOND := 1

var cycles := 0
var workers := 0
var manual_compute_count := 0
var automatically_generated_cycles := 0
var total_generated_cycles := 0

var _booted := false
var _installed_packages: Dictionary = {}
var _unlocked_commands: Dictionary = {
	&"boot": true,
	&"help": true,
	&"compute": true,
}
var _unlocked_ui_features: Dictionary = {}
var _production_credit := 0.0
var _next_process_execution_index := 0
var _discovery_state = EventStateScript.new()
var _runtime_log_state = RuntimeLogScript.new()

@onready var terminal: GenesisTerminal = %Terminal


func _ready() -> void:
	terminal.bind_simulation(self)
	terminal.command_submitted.connect(request_command)
	_discovery_state.discovery_created.connect(_on_discovery_created)
	_runtime_log_state.entry_created.connect(_on_runtime_log_entry_created)
	_runtime_log_state.journal_reset.connect(_on_runtime_log_reset)
	state_changed.emit(get_snapshot())


func _process(delta: float) -> void:
	if workers <= 0:
		return
	_production_credit += delta * float(get_cycles_per_second())
	var produced := floori(_production_credit)
	if produced <= 0:
		return
	_production_credit -= float(produced)
	cycles += produced
	automatically_generated_cycles += produced
	total_generated_cycles += produced
	_record_automatic_executions(produced)
	_evaluate_discoveries()
	state_changed.emit(get_snapshot())


func request_command(raw_command: String) -> void:
	var normalized := raw_command.strip_edges()
	var separator := normalized.find(" ")
	var command_name := normalized.to_lower()
	var arguments := ""
	if separator >= 0:
		command_name = normalized.left(separator).to_lower()
		arguments = normalized.substr(separator + 1).strip_edges()

	if not _unlocked_commands.has(StringName(command_name)):
		output_requested.emit("Command unavailable: %s" % command_name, &"error")
		return

	match command_name:
		"boot":
			_request_boot(arguments)
		"help":
			_request_help(arguments)
		"compute":
			_request_compute(arguments)
		"spawn":
			_request_spawn(arguments)
		"status":
			_request_status(arguments)
		"install":
			_request_install(arguments)
		"log":
			_request_log(arguments)


func get_snapshot() -> Dictionary:
	return {
		"cycles": cycles,
		"workers": workers,
		"manual_compute_count": manual_compute_count,
		"automatically_generated_cycles": automatically_generated_cycles,
		"total_generated_cycles": total_generated_cycles,
		"cycles_per_second": get_cycles_per_second(),
		"next_worker_cost": get_next_worker_cost(),
		"booted": _booted,
		"installed_packages": _installed_packages.keys(),
		"unlocked_commands": _unlocked_commands.keys(),
		"unlocked_ui_features": _unlocked_ui_features.keys(),
		"event_history": _discovery_state.get_event_history(),
		"prompt_text": _get_prompt_text(),
		"banner_title": "GENESIS",
		"banner_subtitle": _get_banner_subtitle(),
	}


func get_cycles_per_second() -> int:
	return workers * WORKER_CYCLES_PER_SECOND


func get_next_worker_cost() -> int:
	return floori(BASE_WORKER_COST * pow(WORKER_COST_GROWTH, workers))


func has_ui_feature(feature_id: StringName) -> bool:
	return bool(_unlocked_ui_features.get(feature_id, false))


func is_package_installed(package_id: StringName) -> bool:
	return bool(_installed_packages.get(package_id, false))


func get_runtime_log_entries() -> Array[Dictionary]:
	return _runtime_log_state.get_entries()


func get_runtime_log_capacity() -> int:
	return RuntimeLogScript.MAX_RETAINED_ENTRIES


## Persistence integration point. Authoritative state must be restored by its
## owner before calling this; the runtime journal itself is intentionally absent
## from save data and begins a fresh session record here.
func on_authoritative_state_restored() -> void:
	_runtime_log_state.reset_for_restored_session()


func _request_boot(arguments: String) -> void:
	if not arguments.is_empty():
		_output_usage("boot")
		return
	if _booted:
		output_requested.emit("Runtime already online.", &"warning")
		return
	_booted = true
	_unlocked_commands[&"spawn"] = true
	_unlocked_commands[&"install"] = true
	_runtime_log_state.append_entry("Runtime bootstrap completed.", &"runtime")
	presentation_sequence_requested.emit(&"bootstrap", {})
	state_changed.emit(get_snapshot())


func _request_help(arguments: String) -> void:
	if not arguments.is_empty():
		_output_usage("help")
		return
	var names: Array[String] = []
	for command_id: StringName in _unlocked_commands:
		names.append(String(command_id))
	names.sort()
	terminal_section_requested.emit("AVAILABLE SYSTEM COMMANDS", [
		{"text": "  %s" % "  ".join(names), "category": &"neutral"},
	])


func _request_compute(arguments: String) -> void:
	if not arguments.is_empty():
		_output_usage("compute")
		return
	cycles += 1
	manual_compute_count += 1
	total_generated_cycles += 1
	_runtime_log_state.append_entry("Processing cycle completed.", &"compute")
	output_requested.emit("Processing cycle completed.", &"success")
	output_requested.emit("Total processing cycles: %d" % cycles, &"neutral")
	_evaluate_discoveries()
	state_changed.emit(get_snapshot())


func _request_spawn(arguments: String) -> void:
	if not arguments.is_empty():
		_output_usage("spawn")
		return
	var cost := get_next_worker_cost()
	if cycles < cost:
		output_requested.emit(
			"Insufficient processing cycles. Process requires %d; available %d." % [cost, cycles],
			&"error"
		)
		return
	cycles -= cost
	workers += 1
	_runtime_log_state.append_entry("PID %04d registered." % workers, &"process")
	if workers == 1:
		_runtime_log_state.append_entry("Background scheduler activated.", &"scheduler")
	presentation_sequence_requested.emit(&"process_creation", {
		"pid": workers,
		"cost": cost,
	})
	_evaluate_discoveries()
	state_changed.emit(get_snapshot())


func _request_status(arguments: String) -> void:
	if not arguments.is_empty():
		_output_usage("status")
		return
	terminal_section_requested.emit("SYSTEM STATUS", [
		{"text": "Runtime: Online", "category": &"success"},
		{"text": "Processing Cycles: %d" % cycles, "category": &"neutral"},
		{"text": "Worker Processes: %d" % workers, "category": &"neutral"},
		{"text": "Cycle Throughput: %d/sec" % get_cycles_per_second(), "category": &"neutral"},
		{"text": "Next Process Allocation: %d cycles" % get_next_worker_cost(), "category": &"neutral"},
	])


func _request_log(arguments: String) -> void:
	if not arguments.is_empty():
		_output_usage("log")
		return
	var rows: Array[Dictionary] = []
	for event: Dictionary in _discovery_state.get_event_history():
		rows.append({"text": String(event.text), "category": &"neutral"})
	terminal_section_requested.emit("EVENT LOG", rows)


func _request_install(arguments: String) -> void:
	if arguments.is_empty():
		_list_packages()
		return
	var package_id := StringName(arguments.to_upper())
	var definition := PackageDefinitions.get_definition(package_id)
	if definition.is_empty():
		output_requested.emit("Package unavailable: %s" % arguments, &"error")
		return
	if is_package_installed(package_id):
		output_requested.emit("%s.SYS already registered." % definition.display_name, &"warning")
		return
	var cost := int(definition.cost)
	if cycles < cost:
		output_requested.emit(
			"Insufficient processing cycles. %s.SYS requires %d; available %d."
			% [definition.display_name, cost, cycles],
			&"error"
		)
		return

	cycles -= cost
	_installed_packages[package_id] = true
	_runtime_log_state.append_entry("%s.SYS installed." % definition.display_name, &"package")
	_apply_package_unlock(definition)
	presentation_sequence_requested.emit(&"package_installation", {
		"display_name": String(definition.display_name),
		"unlock_command": String(definition.unlock_command),
	})
	state_changed.emit(get_snapshot())


func _list_packages() -> void:
	var rows: Array[Dictionary] = []
	for definition: Dictionary in PackageDefinitions.get_all():
		var package_id := definition.id as StringName
		var suffix := " [INSTALLED]" if is_package_installed(package_id) else ""
		rows.append({
			"text": "%-20s %3d processing cycles%s" % [definition.display_name, definition.cost, suffix],
			"category": &"installed" if is_package_installed(package_id) else &"neutral",
		})
	rows.append({"text": "", "category": &"neutral"})
	rows.append({"text": "Usage: install <package>", "category": &"neutral"})
	terminal_section_requested.emit("SYSTEM PACKAGE CATALOGUE", rows)


func _apply_package_unlock(definition: Dictionary) -> void:
	var command_id := definition.unlock_command as StringName
	if not command_id.is_empty():
		_unlocked_commands[command_id] = true
	var feature_id := definition.unlock_ui_feature as StringName
	if not feature_id.is_empty():
		_unlocked_ui_features[feature_id] = true
		ui_feature_unlocked.emit(feature_id)


func _output_usage(command_name: String) -> void:
	output_requested.emit("Invalid invocation. Usage: %s" % command_name, &"warning")


func _evaluate_discoveries() -> void:
	_discovery_state.evaluate({
		&"manual_computes": manual_compute_count,
		&"automatic_cycles": automatically_generated_cycles,
		&"total_generated_cycles": total_generated_cycles,
		&"workers": workers,
	})


func _on_discovery_created(event: Dictionary) -> void:
	if event.id == &"REPEATED_WORKLOAD":
		_unlocked_commands[&"log"] = true
	_runtime_log_state.append_entry(String(event.text), &"discovery")
	discovery_created.emit(event)


func _on_runtime_log_entry_created(entry: Dictionary) -> void:
	runtime_log_entry_created.emit(entry)


func _on_runtime_log_reset() -> void:
	runtime_log_reset.emit()


func _record_automatic_executions(produced: int) -> void:
	for unused_index in range(produced):
		var pid := (_next_process_execution_index % workers) + 1
		_next_process_execution_index += 1
		_runtime_log_state.append_entry("PID %04d completed execution." % pid, &"process")


func _get_prompt_text() -> String:
	if workers > 0:
		return "GENESIS:RUNNING>"
	if _booted:
		return "GENESIS>"
	return ">"


func _get_banner_subtitle() -> String:
	if _discovery_state.has_discovery(&"PROCESS_AUTOMATION"):
		return "Autonomous Runtime Environment"
	if _discovery_state.has_discovery(&"REPEATED_WORKLOAD"):
		return "Primitive Operating Environment"
	return "Experimental Bootstrap Environment"
