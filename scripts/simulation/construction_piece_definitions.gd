extends RefCounted
class_name ConstructionPieceDefinitions

## Static production metadata for location construction pieces.
## Runtime sites and completed cells are owned by LocationConstructionState.
const DEFINITIONS := {
	"wall": {"stable_id": "wall", "display_name": "Wall", "placement_category": "structure", "placement_role": "base_structure", "required_base_structure": "", "allowed_orientations": [], "ghost_semantic": "wall", "completed_semantic": "wall", "cost": {"wood": 2}, "work_required": 4.0},
	"floor": {"stable_id": "floor", "display_name": "Floor", "placement_category": "floor", "required_base_kind": "", "ghost_semantic": "floor", "completed_semantic": "floor", "cost": {"wood": 1}, "work_required": 2.0},
	"door": {"stable_id": "door", "display_name": "Door", "placement_category": "structure", "placement_role": "wall_fixture", "required_base_structure": "wall", "allowed_orientations": ["axis_x", "axis_y"], "ghost_semantic": "door", "completed_semantic": "door", "cost": {"wood": 3}, "work_required": 5.0},
	"window": {"stable_id": "window", "display_name": "Window", "placement_category": "structure", "placement_role": "wall_fixture", "required_base_structure": "wall", "allowed_orientations": ["axis_x", "axis_y"], "ghost_semantic": "window", "completed_semantic": "window", "cost": {"wood": 2}, "work_required": 4.0},
	"roof": {"stable_id": "roof", "display_name": "Roof", "placement_category": "roof", "required_base_kind": "", "ghost_semantic": "roof", "completed_semantic": "roof", "deferred": true},
}

static func has_definition(piece_kind: String) -> bool:
	return DEFINITIONS.has(piece_kind)

static func get_definition(piece_kind: String) -> Dictionary:
	return DEFINITIONS.get(piece_kind, {}).duplicate(true)

static func get_definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for piece_kind: String in DEFINITIONS:
		result.append(get_definition(piece_kind))
	return result

static func get_orientations(piece_kind: String) -> Array:
	return get_definition(piece_kind).get("allowed_orientations", []).duplicate()

static func is_rotatable(piece_kind: String) -> bool:
	return get_orientations(piece_kind).size() > 1
