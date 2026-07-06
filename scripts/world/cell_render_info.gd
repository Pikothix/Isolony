extends RefCounted
class_name CellRenderInfo

## Purpose: Define the single world-space presentation model for elevated terrain blocks.
## Responsibility: Resolve cliff atlas roles and every block anchor without owning terrain or simulation state.
## Assumption: Terrain uses a 32x16 isometric grid and each elevation level is one 16-pixel block step.

const TILE_GRID_SIZE := Vector2i(32, 16)
const BLOCK_LAYER_OFFSET := Vector2(0.0, -16.0)
const TOP_DIAMOND_OFFSET := Vector2(0.0, -8.0)
const TOP_DIAMOND_HALF_SIZE := Vector2(16.0, 8.0)


static func build(tile_info: Dictionary, base_position: Vector2) -> Dictionary:
	var elevation: int = clampi(int(tile_info.get("elevation", 0)), 0, 2)
	var atlas_pair: Dictionary = _get_atlas_pair(tile_info)
	var stack_layers: Array[Dictionary] = []
	for level in range(1, elevation + 1):
		var is_top: bool = level == elevation
		stack_layers.append({
			"level": level,
			"role": "top" if is_top else "support",
			"layer_offset": BLOCK_LAYER_OFFSET * level,
			"world_position": base_position + BLOCK_LAYER_OFFSET * level,
			"atlas_coords": atlas_pair.get("top" if is_top else "support", Vector2i(-1, -1)),
		})
	return {
		"cell": tile_info.get("cell", Vector2i.ZERO),
		"elevation": elevation,
		"terrain_name": String(tile_info.get("terrain", "")),
		"source_id": int(tile_info.get("source_id", -1)),
		"top_tile_atlas_coords": atlas_pair.get("top", tile_info.get("atlas_coords", Vector2i(-1, -1))),
		"support_tile_atlas_coords": atlas_pair.get("support", tile_info.get("atlas_coords", Vector2i(-1, -1))),
		"base_position": base_position,
		"top_position": base_position + BLOCK_LAYER_OFFSET * elevation,
		"stack_layers": stack_layers,
	}


static func get_visible_top_center(cell_map_position: Vector2, elevation: int) -> Vector2:
	return cell_map_position + BLOCK_LAYER_OFFSET * clampi(elevation, 0, 2) + TOP_DIAMOND_OFFSET


static func contains_visible_top(world_local_position: Vector2, top_center: Vector2) -> bool:
	var offset: Vector2 = world_local_position - top_center
	return absf(offset.x) / TOP_DIAMOND_HALF_SIZE.x + absf(offset.y) / TOP_DIAMOND_HALF_SIZE.y <= 1.0


static func _get_atlas_pair(tile_info: Dictionary) -> Dictionary:
	var visual_column: int = -1
	match String(tile_info.get("terrain", "")):
		"DIRT", "DARK_DIRT", "TILLED_DIRT_DRY":
			visual_column = 0
		"GRASS", "MUD":
			visual_column = 1
		"SAND", "RED_SAND":
			visual_column = 2
		"STONE", "GRAVEL", "ROCK_WALL":
			visual_column = 3
	var original_atlas: Vector2i = tile_info.get("atlas_coords", Vector2i(-1, -1))
	if visual_column < 0:
		return {"top": original_atlas, "support": original_atlas}
	return {"top": Vector2i(visual_column, 0), "support": Vector2i(visual_column, 1)}
