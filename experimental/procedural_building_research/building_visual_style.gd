class_name ExperimentalBuildingVisualStyle
extends Resource

## Purpose: Map semantic topology requests to authored visual module definitions.
## Ownership: Owns the visual catalogue and fallback definition, not layout or topology.
## Responsibility: Validate stable IDs and resolve every request deterministically.
## Integration: Used only by the isolated prototype renderer.

@export var style_id: StringName
@export var cell_half := Vector2(32.0, 16.0)
@export_range(1.0, 8.0, 1.0) var display_scale := 1.0
@export var render_roofs := true
@export var compact_missing_geometry := false
@export var use_wall_connection_masks := false
@export var default_floor_module: StringName = &"floor"
@export var floor_modules_by_room: Dictionary = {}
@export var modules: Array[Resource] = []
@export var fallback_module: Resource

var _modules_by_id: Dictionary = {}


func add_module(definition: Resource) -> void:
	assert(definition != null and definition.is_valid(), "Invalid visual module definition")
	assert(not _modules_by_id.has(definition.semantic_id), "Duplicate semantic module ID: %s" % definition.semantic_id)
	modules.append(definition)
	_modules_by_id[definition.semantic_id] = definition


func resolve(semantic_id: StringName) -> Dictionary:
	_ensure_index()
	var definition: Resource = _modules_by_id.get(semantic_id)
	if definition != null:
		return {"requested_id": semantic_id, "resolved_id": definition.semantic_id, "definition": definition, "used_fallback": false}
	assert(fallback_module != null and fallback_module.is_valid(), "Visual style requires a valid fallback module")
	return {"requested_id": semantic_id, "resolved_id": fallback_module.semantic_id, "definition": fallback_module, "used_fallback": true}


func floor_module_for_room(room_id: StringName) -> StringName:
	return floor_modules_by_room.get(room_id, default_floor_module)


func validate() -> bool:
	if style_id.is_empty() or cell_half.x <= 0.0 or cell_half.y <= 0.0 or display_scale <= 0.0 or fallback_module == null or not fallback_module.is_valid():
		return false
	var seen: Dictionary = {}
	for definition: Resource in modules:
		if definition == null or not definition.is_valid() or seen.has(definition.semantic_id):
			return false
		seen[definition.semantic_id] = true
	if not seen.has(default_floor_module):
		return false
	for semantic_id: StringName in floor_modules_by_room.values():
		if not seen.has(semantic_id):
			return false
	return true


func mapped_semantic_ids() -> Array:
	_ensure_index()
	return _modules_by_id.keys()


func _ensure_index() -> void:
	if _modules_by_id.size() == modules.size():
		return
	_modules_by_id.clear()
	for definition: Resource in modules:
		if definition != null:
			_modules_by_id[definition.semantic_id] = definition
