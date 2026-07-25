extends Node
class_name LightingState

## Purpose: Derive authoritative gameplay light from simulation-owned time, WorldSpace identity, and completed building effects.
## Responsibility: Provide deterministic, reconstructible cell light queries. It stores no light field and has no rendering responsibilities.
## Assumption: This first slice has no occlusion. Future propagation must preserve this query contract while adding terrain and building blockers.

const MAX_LIGHT_LEVEL := 15
const SURFACE_NIGHT_AMBIENT_LEVEL := 4
const INTERIOR_AMBIENT_LEVEL := 0

var _world_state: Node


func configure(world_state: Node) -> void:
	_world_state = world_state


func get_cell_light(cell: Vector2i, world_space_id: String) -> Dictionary:
	var normalized_world_space_id := world_space_id.strip_edges()
	if _world_state == null or not _world_state.is_world_space_supported(normalized_world_space_id):
		return _build_light_result(cell, normalized_world_space_id, 0, 0, [])
	var ambient_level := _get_ambient_level(normalized_world_space_id)
	var emitted_level := 0
	var source_ids: Array[String] = []
	for effect: Dictionary in _world_state.get_completed_building_effects(normalized_world_space_id):
		var radius := maxf(float(effect.get("light_radius", 0.0)), 0.0)
		if radius <= 0.0:
			continue
		var origin_cell: Vector2i = effect.get("origin_cell", Vector2i.ZERO)
		var distance := absi(cell.x - origin_cell.x) + absi(cell.y - origin_cell.y)
		if float(distance) > radius:
			continue
		var source_level := _get_source_light_level(radius, distance)
		if source_level > emitted_level:
			emitted_level = source_level
			source_ids.clear()
			source_ids.append(String(effect.get("site_id", "")))
		elif source_level == emitted_level and source_level > 0:
			source_ids.append(String(effect.get("site_id", "")))
	source_ids.sort()
	return _build_light_result(cell, normalized_world_space_id, ambient_level, emitted_level, source_ids)


func get_light_level(cell: Vector2i, world_space_id: String) -> int:
	return int(get_cell_light(cell, world_space_id).get("total_level", 0))


func get_ambient_light_level(world_space_id: String) -> int:
	## Exposes the authoritative phase/WorldSpace baseline without projecting any source lighting.
	return _get_ambient_level(world_space_id.strip_edges())


func is_cell_lit(cell: Vector2i, world_space_id: String) -> bool:
	return get_light_level(cell, world_space_id) > 0


func is_cell_dark(cell: Vector2i, world_space_id: String) -> bool:
	return bool(get_cell_light(cell, world_space_id).get("is_dark", true))


func _get_ambient_level(world_space_id: String) -> int:
	if world_space_id != _world_state.SURFACE_WORLD_SPACE_ID:
		return INTERIOR_AMBIENT_LEVEL
	return MAX_LIGHT_LEVEL if _world_state.is_day() else SURFACE_NIGHT_AMBIENT_LEVEL


func _get_source_light_level(radius: float, distance: int) -> int:
	## Manhattan distance is deterministic and matches later cardinal propagation without diagonal special cases.
	var attenuation_per_cell := maxi(1, floori(12.0 / maxf(radius, 1.0)))
	return clampi(MAX_LIGHT_LEVEL - distance * attenuation_per_cell, 1, MAX_LIGHT_LEVEL)


func _build_light_result(cell: Vector2i, world_space_id: String, ambient_level: int, emitted_level: int, source_ids: Array[String]) -> Dictionary:
	var clamped_ambient := clampi(ambient_level, 0, MAX_LIGHT_LEVEL)
	var clamped_emitted := clampi(emitted_level, 0, MAX_LIGHT_LEVEL)
	var total_level := maxi(clamped_ambient, clamped_emitted)
	return {
		"world_space_id": world_space_id,
		"cell": cell,
		"ambient_level": clamped_ambient,
		"emitted_level": clamped_emitted,
		"total_level": total_level,
		"is_dark": total_level <= 0,
		"source_ids": source_ids.duplicate(),
	}
