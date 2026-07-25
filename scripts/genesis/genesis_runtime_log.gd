extends RefCounted

signal entry_created(entry: Dictionary)
signal journal_reset

## Authoritative bounded journal of Genesis runtime activity. The simulation is
## the only writer; presentation receives immutable entry copies for rendering.

const MAX_RETAINED_ENTRIES := 200

var _entries: Array[Dictionary] = []
var _next_sequence := 1


func append_entry(message: String, category: StringName = &"runtime") -> void:
	assert(not message.is_empty(), "Kernel Log entries require a semantic message.")
	var entry := {
		"sequence": _next_sequence,
		"message": message,
		"category": category,
	}
	_next_sequence += 1
	_entries.append(entry)
	if _entries.size() > MAX_RETAINED_ENTRIES:
		_entries.pop_front()
	entry_created.emit(entry.duplicate(true))


func get_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


func reset_for_restored_session() -> void:
	_entries.clear()
	_next_sequence = 1
	journal_reset.emit()
	append_entry("Session restored.", &"runtime")
	append_entry("Runtime resumed.", &"runtime")
