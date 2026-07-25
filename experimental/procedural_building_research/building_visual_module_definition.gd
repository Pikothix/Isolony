class_name ExperimentalBuildingVisualModuleDefinition
extends Resource

## Purpose: Stable experiment-local contract for one authored visual building module.
## Ownership: Owns visual metadata and asset references only; never topology or gameplay state.
## Integration: Resolved by ExperimentalBuildingVisualStyle and consumed by the prototype renderer.

const PLACEHOLDER := &"placeholder"
const TEXTURE := &"texture"
const ATLAS_REGION := &"atlas_region"
const PACKED_SCENE := &"packed_scene"
const TILE_SET := &"tile_set"

@export var semantic_id: StringName
@export var source_kind: StringName = PLACEHOLDER
@export var visual_kind: StringName
@export var texture: Texture2D
@export var atlas_region := Rect2i()
@export var packed_scene: PackedScene
@export var tile_set: TileSet
@export var tile_source_id := -1
@export var atlas_coordinates := Vector2i(-1, -1)
@export var alternative_tile_id := 0
@export var connection_mask := 0
@export var anchor := Vector2.ZERO
@export var pixel_anchor := Vector2.ZERO
@export var anchor_offset := Vector2.ZERO
@export var logical_span := Vector2i.ONE
@export var facing: StringName
@export var z_offset := 0
@export var compatibility_tags: Array[StringName] = []
@export var confidence: StringName = &"unrated"
@export_multiline var notes := ""


func is_valid() -> bool:
	if semantic_id.is_empty() or visual_kind.is_empty():
		return false
	if logical_span.x <= 0 or logical_span.y <= 0:
		return false
	match source_kind:
		PLACEHOLDER:
			return true
		TEXTURE:
			return texture != null
		ATLAS_REGION:
			return texture != null and atlas_region.size.x > 0 and atlas_region.size.y > 0
		PACKED_SCENE:
			return packed_scene != null
		TILE_SET:
			if tile_set == null or not tile_set.has_source(tile_source_id):
				return false
			var source := tile_set.get_source(tile_source_id) as TileSetAtlasSource
			return source != null and source.has_tile(atlas_coordinates) and source.has_alternative_tile(atlas_coordinates, alternative_tile_id)
		_:
			return false


func resolved_anchor() -> Vector2:
	# `anchor` remains a compatibility alias for early experiment definitions.
	return pixel_anchor + anchor_offset if pixel_anchor != Vector2.ZERO or anchor_offset != Vector2.ZERO else anchor
