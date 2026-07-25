extends RefCounted
class_name LocationConstructionVisualConfig

## Production-only mapping from authoritative construction semantics to atlas art.
## The TileSet owns the 32x16 isometric calibration and common 8 px texture
## origins. Both floor and structure projections cancel that common origin so
## all construction categories meet the authoritative terrain-cell anchor.
const TILE_SOURCE_ID := 0
const WALL_VISUAL_OFFSET := Vector2(0, -8)
const FLOOR_LAYER_OFFSET := Vector2(0, -8)
const GHOST_ALPHA := 0.52
const GHOST_NEUTRAL := Color(1.0, 1.0, 1.0, GHOST_ALPHA)
const GHOST_PREREQUISITE := Color(0.62, 0.52, 1.0, 0.68)
const GHOST_MISSING_RESOURCES := Color(1.0, 0.58, 0.22, 0.68)
const GHOST_UNREACHABLE := Color(1.0, 0.28, 0.28, 0.7)
const GHOST_RESERVED := Color(1.0, 0.84, 0.28, 0.72)
const WALL := Vector2i(0, 0)
const FLOOR := Vector2i(4, 1)
const ROOF := Vector2i(4, 0)
const ATLAS := {
	"door": {"axis_x": Vector2i(1, 2), "axis_y": Vector2i(0, 2)},
	"window": {"axis_x": Vector2i(3, 2), "axis_y": Vector2i(2, 2)},
}

static func atlas_for(piece_kind: String, axis := "") -> Vector2i:
	match piece_kind:
		"wall": return WALL
		"floor": return FLOOR
		"roof": return ROOF
		"door", "window": return ATLAS[piece_kind].get(axis, Vector2i(-1, -1))
	return Vector2i(-1, -1)

## Resolves completed structure presentation without changing authoritative
## state. Current door/window atlas entries are fixture-face overlays, not
## complete full-cell wall bodies, so fixture cells use calibrated layering.
static func resolve_structure_visual(base_kind: String, fixture_kind := "", fixture_orientation := "") -> Dictionary:
	if base_kind != "wall": return {"mode": "unsupported", "parts": []}
	var base_part := {"kind": "wall", "axis": "", "tile": WALL}
	if fixture_kind.is_empty(): return {"mode": "base", "parts": [base_part]}
	var fixture_tile := atlas_for(fixture_kind, fixture_orientation)
	if fixture_tile == Vector2i(-1, -1): return {"mode": "unsupported", "parts": []}
	return {
		"mode": "layered",
		"base_tile": WALL,
		"fixture_tile": fixture_tile,
		"parts": [base_part, {"kind": fixture_kind, "axis": fixture_orientation, "tile": fixture_tile}],
	}

static func ghost_tint(status: String, availability_reason: String, progress: float, build_required: float) -> Color:
	if status == "under_construction":
		var ratio := clampf(progress / maxf(build_required, 0.001), 0.0, 1.0)
		return Color(1.0, 1.0, 1.0, lerpf(GHOST_ALPHA, 0.9, ratio))
	if status == "reserved" or availability_reason == "reserved_by_other": return GHOST_RESERVED
	match availability_reason:
		"waiting_for_prerequisite": return GHOST_PREREQUISITE
		"missing_resources": return GHOST_MISSING_RESOURCES
		"unreachable", "invalid_dependency": return GHOST_UNREACHABLE
	return GHOST_NEUTRAL
