extends RefCounted
class_name GenesisCommandParser

## Command registry for Genesis. It only resolves command text to explicit
## handlers; command effects remain owned by the Genesis controller.

var _handlers: Dictionary = {}
var _intent_aliases: Dictionary = {}
var _suggestion_aliases: Dictionary = {}


func register_command(command_name: String, handler: Callable) -> void:
	var normalized := command_name.strip_edges().to_lower()
	assert(not normalized.is_empty(), "Genesis commands require a name.")
	assert(handler.is_valid(), "Genesis commands require a valid handler.")
	_handlers[normalized] = handler


func clear_commands() -> void:
	_handlers.clear()


func register_suggestion_alias(alias: String, command_name: String) -> void:
	var normalized_alias := _normalize_phrase(alias)
	var normalized_command := _normalize_phrase(command_name)
	assert(not normalized_alias.is_empty(), "Genesis suggestion aliases require a source phrase.")
	assert(not normalized_command.is_empty(), "Genesis suggestion aliases require a target command.")
	_suggestion_aliases[normalized_alias] = normalized_command


func register_intent(intent_name: StringName, aliases: Array[String]) -> void:
	assert(not intent_name.is_empty(), "Genesis dialogue intents require a name.")
	for alias: String in aliases:
		var normalized := _normalize_phrase(alias)
		assert(not normalized.is_empty(), "Genesis dialogue aliases cannot be empty.")
		_intent_aliases[normalized] = intent_name


func resolve_intent(raw_input: String) -> StringName:
	return _intent_aliases.get(_normalize_phrase(raw_input), &"") as StringName


func get_command_names() -> Array[String]:
	var names: Array[String] = []
	for command_name: String in _handlers:
		names.append(command_name)
	names.sort()
	return names


func suggest_command(raw_input: String) -> String:
	var input_command := _get_command_token(raw_input)
	if input_command.is_empty():
		return ""
	var closest_command := ""
	var closest_distance := 2
	for command_name: String in _handlers:
		var distance := _edit_distance(input_command, command_name)
		if distance < closest_distance:
			closest_distance = distance
			closest_command = command_name
	for alias: String in _suggestion_aliases:
		var target := String(_suggestion_aliases[alias])
		if not _handlers.has(target):
			continue
		var distance := _edit_distance(input_command, alias)
		if distance < closest_distance:
			closest_distance = distance
			closest_command = target
	return closest_command if closest_distance <= 1 else ""


func execute(raw_input: String) -> bool:
	var normalized := raw_input.strip_edges()
	if normalized.is_empty():
		return true
	var separator_index := normalized.find(" ")
	var command_name := normalized.to_lower()
	var arguments := ""
	if separator_index >= 0:
		command_name = normalized.left(separator_index).to_lower()
		arguments = normalized.substr(separator_index + 1).strip_edges()
	if not _handlers.has(command_name):
		return false
	(_handlers[command_name] as Callable).call(arguments)
	return true


func _get_command_token(value: String) -> String:
	var normalized := _normalize_phrase(value)
	var separator_index := normalized.find(" ")
	return normalized if separator_index < 0 else normalized.left(separator_index)


func _edit_distance(left: String, right: String) -> int:
	var previous: Array[int] = []
	for column in range(right.length() + 1):
		previous.append(column)
	for left_index in range(left.length()):
		var current: Array[int] = [left_index + 1]
		for right_index in range(right.length()):
			var replacement_cost := 0 if left.unicode_at(left_index) == right.unicode_at(right_index) else 1
			current.append(mini(
				mini(current[right_index] + 1, previous[right_index + 1] + 1),
				previous[right_index] + replacement_cost
			))
		previous = current
	return previous.back()


func _normalize_phrase(value: String) -> String:
	var words := value.strip_edges().to_lower().split(" ", false)
	return " ".join(words)
