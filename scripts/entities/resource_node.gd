extends Area2D
class_name ResourceNode

## Purpose: Present one generated resource and forward click intent for harvest designation.
## Responsibility: Own resource presentation metadata only; simulation authority remains in WorldState/ChunkManager.
## Assumption: The designation marker is reconstructible UI state and never authorizes harvest completion.

signal harvest_requested(resource_id: String)

const ProcSpriteCache = preload("res://scripts/procgen/proc_sprite_cache.gd")

@export var resource_id: String = ""
@export var cell: Vector2i = Vector2i.ZERO
@export var resource_type: String = "wood"
@export var yield_amount: int = 5
@export var visual_definition_id: String = ""
@export var placeholder_visual_id: String = ""
@export var use_procedural_sprite: bool = false
@export_enum("none", "tree", "rock") var procedural_sprite_kind: String = "none"
@export var procedural_seed: int = 0
@export_range(0, 256, 1) var procedural_variant_cap: int = 0
@export_range(8, 64, 1) var procedural_sprite_size: int = 20
@export var procedural_archetype: String = ""
@export var procedural_terrain_tag: String = ""
@export var procedural_size_tier: String = "medium"

@onready var _procedural_sprite: Sprite2D = get_node_or_null("ProceduralSprite") as Sprite2D
var _harvest_designated: bool = false

func _ready() -> void:
	input_pickable = true
	_refresh_visual()

func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	## Main consumes releases that complete area drags; an unconsumed release remains an exact single-resource click.
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		harvest_requested.emit(resource_id)
		get_viewport().set_input_as_handled()

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
