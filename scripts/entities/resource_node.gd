extends Area2D
class_name ResourceNode

## Purpose: Present one generated resource and forward click intent for harvest designation.
## Responsibility: Own resource presentation metadata only; simulation authority remains in WorldState/ChunkManager.
## Assumption: The designation marker is reconstructible UI state and never authorizes harvest completion.

signal harvest_requested(resource_id: String)
signal inspection_requested(inspection_data: Dictionary)

const ProcSpriteCache = preload("res://scripts/procgen/proc_sprite_cache.gd")

@export var resource_id: String = ""
@export var cell: Vector2i = Vector2i.ZERO
var elevation: int = 0
@export var resource_type: String = "wood"
@export var yield_amount: int = 5
@export var visual_definition_id: String = ""
@export var placeholder_visual_id: String = ""
@export var use_procedural_sprite: bool = false
@export_enum("none", "tree", "rock", "bush") var procedural_sprite_kind: String = "none"
@export var procedural_seed: int = 0
@export_range(0, 256, 1) var procedural_variant_cap: int = 0
@export_range(8, 64, 1) var procedural_sprite_size: int = 20
@export var procedural_archetype: String = ""
@export var procedural_terrain_tag: String = ""
@export var procedural_size_tier: String = "medium"

## Presentation-only metadata derived from ResourceVisualDefinition. This is
## intentionally excluded from resource identity, yield, and persistence.
var visual_variant_config: Dictionary = {}

@onready var _procedural_sprite: Sprite2D = get_node_or_null("ProceduralSprite") as Sprite2D
@onready var _variant_overlay: Node2D = get_node_or_null("VariantOverlay") as Node2D
var _harvest_designated: bool = false
# Populated only when ChunkManager's opt-in spawn profiler is active. These
# values let it separate _ready visual work from scene-tree/collision entry.
var profile_ready_timing: bool = false
var profile_ready_total_usec: int = 0
var profile_visual_refresh_usec: int = 0

func _ready() -> void:
	var profile_start_usec: int = Time.get_ticks_usec() if profile_ready_timing else 0
	input_pickable = true
	var visual_start_usec: int = Time.get_ticks_usec() if profile_ready_timing else 0
	_refresh_visual()
	if profile_ready_timing:
		var profile_end_usec := Time.get_ticks_usec()
		profile_visual_refresh_usec = profile_end_usec - visual_start_usec
		profile_ready_total_usec = profile_end_usec - profile_start_usec

func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	## Main consumes releases that complete area drags; an unconsumed release remains an exact single-resource click.
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		inspection_requested.emit(get_inspection_data())
		harvest_requested.emit(resource_id)
		get_viewport().set_input_as_handled()


func get_inspection_data() -> Dictionary:
	## Return a fresh presentation snapshot. Callers cannot mutate resource state,
	## procedural cache metadata, or the configured visual-variant dictionary.
	var resource_kind: String = visual_definition_id if not visual_definition_id.is_empty() else procedural_sprite_kind
	var variant: Dictionary = {
		"archetype": procedural_archetype,
		"terrain_palette": procedural_terrain_tag,
		"size_tier": procedural_size_tier,
		"sprite_size": procedural_sprite_size,
	}
	if resource_kind == "tree":
		var fruit_count: int = 0
		if _variant_overlay != null and _variant_overlay.has_method("get_fruit_count"):
			fruit_count = int(_variant_overlay.call("get_fruit_count"))
		variant["fruiting"] = fruit_count > 0
		variant["fruit_count"] = fruit_count
	elif resource_kind == "berry_bush":
		var metadata: Dictionary = ProcSpriteCache.get_metadata(
			"bush",
			procedural_seed,
			procedural_sprite_size,
			procedural_variant_cap,
			procedural_archetype,
			procedural_terrain_tag,
			procedural_size_tier
		)
		variant["archetype"] = String(metadata.get("archetype", procedural_archetype))
		variant["berry_count"] = int(metadata.get("berry_count", 0))
		variant["berry_color"] = String(metadata.get("berry_color_name", ""))
	return {
		"resource_id": resource_id,
		"display_name": _get_inspection_display_name(resource_kind),
		"resource_kind": resource_kind,
		"resource_type": resource_type,
		"yield_amount": yield_amount,
		"cell": cell,
		"elevation": elevation,
		"visual_variant": variant.duplicate(true),
	}


func _get_inspection_display_name(resource_kind: String) -> String:
	match resource_kind:
		"tree":
			match procedural_archetype:
				"conifer":
					return "Conifer Tree"
				"dead":
					return "Dead Tree"
				_:
					return "Deciduous Tree"
		"berry_bush":
			return "Berry Bush"
		"rock":
			return "Stone Boulder"
		_:
			return resource_kind.replace("_", " ").capitalize() if not resource_kind.is_empty() else "Resource"

func set_harvest_designated(designated: bool) -> void:
	## Presentation only: WorldState owns whether a designation exists.
	if _harvest_designated == designated:
		return
	_harvest_designated = designated
	queue_redraw()

func is_harvest_designated() -> bool:
	return _harvest_designated

func _draw() -> void:
	if not _harvest_designated:
		return
	var marker_color := Color(1.0, 0.82, 0.18, 0.95)
	draw_arc(Vector2(0, 3), 9.0, 0.0, TAU, 24, marker_color, 1.5)
	draw_line(Vector2(-4, 3), Vector2(4, 3), marker_color, 1.5)

func _refresh_visual() -> void:
	if not is_node_ready():
		return
	var procedural_enabled: bool = use_procedural_sprite and procedural_sprite_kind != "none" and _procedural_sprite != null
	if procedural_enabled:
		var texture: Texture2D = ProcSpriteCache.get_texture(procedural_sprite_kind, procedural_seed, procedural_sprite_size, procedural_variant_cap, procedural_archetype, procedural_terrain_tag, procedural_size_tier)
		if texture != null:
			_procedural_sprite.texture = texture
			_procedural_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_procedural_sprite.centered = true
			_procedural_sprite.offset = Vector2(0, -float(texture.get_height()) * 0.5)
			_procedural_sprite.visible = true
		else:
			procedural_enabled = false
	if _procedural_sprite != null and not procedural_enabled:
		_procedural_sprite.texture = null
		_procedural_sprite.visible = false
	for child: Node in get_children():
		if child == _procedural_sprite:
			continue
		if child is Polygon2D:
			child.visible = not procedural_enabled
	_apply_visual_variant(procedural_enabled)

func _apply_visual_variant(procedural_enabled: bool) -> void:
	## Variant selection affects scene children only and never mutates gameplay fields.
	var variant_kind: String = String(visual_variant_config.get("kind", ""))
	if variant_kind == "berry_cluster":
		_apply_berry_cluster_variant()
	if _variant_overlay == null:
		return
	if variant_kind != "tree_fruit_overlay":
		_variant_overlay.call("configure", {}, procedural_seed, procedural_archetype, Vector2.ZERO)
		return
	var fallback_size: Vector2 = visual_variant_config.get("fallback_visual_size", Vector2(36.0, 38.0))
	var visual_source: Variant = fallback_size
	if procedural_enabled and _procedural_sprite != null and _procedural_sprite.texture != null:
		visual_source = _procedural_sprite.texture
	_variant_overlay.call("configure", visual_variant_config, procedural_seed, procedural_archetype, visual_source)

func _apply_berry_cluster_variant() -> void:
	var berry_left := get_node_or_null("BerryLeft") as Polygon2D
	var berry_center := get_node_or_null("BerryCenter") as Polygon2D
	var berry_right := get_node_or_null("BerryRight") as Polygon2D
	if berry_left == null or berry_center == null or berry_right == null:
		push_warning("Berry cluster variant requires BerryLeft, BerryCenter, and BerryRight polygon children.")
		return
	var palettes: Array = visual_variant_config.get("palettes", [])
	if palettes.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = procedural_seed + 104729
	var minimum_count: int = clampi(int(visual_variant_config.get("min_count", 1)), 1, 3)
	var maximum_count: int = clampi(int(visual_variant_config.get("max_count", 3)), minimum_count, 3)
	var visible_count: int = rng.randi_range(minimum_count, maximum_count)
	var palette: Array = palettes[rng.randi_range(0, palettes.size() - 1)]
	if palette.is_empty():
		return
	var berry_nodes: Array[Polygon2D] = [berry_left, berry_center, berry_right]
	var visible_indices: Dictionary = {1: [1], 2: [0, 2], 3: [0, 1, 2]}
	for index in berry_nodes.size():
		var berry: Polygon2D = berry_nodes[index]
		berry.visible = index in visible_indices[visible_count]
		berry.color = palette[index % palette.size()]
