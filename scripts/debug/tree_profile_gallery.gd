extends Node2D

## Purpose: Render and validate the supported visual-only tree presentation profiles.
## Responsibility: Exercise deterministic profile generation, archetype identity,
## terrain palettes, and the fruit overlay without configuring runtime resources.
## Assumption: This scene is a developer gallery and is never part of normal world generation.

const ProcSpriteCache = preload("res://scripts/procgen/proc_sprite_cache.gd")
const ProcTrees = preload("res://scripts/procgen/proc_trees.gd")
const PropPrewarmConfig = preload("res://scripts/world/props/prop_prewarm_config.gd")
const ResourceVariantOverlayScript = preload("res://scripts/entities/resource_variant_overlay.gd")
const ResourceVisualDefinitionRef = preload("res://scripts/world/props/resource_visual_definition.gd")
const TreeProfiles = preload("res://scripts/procgen/tree_profiles.gd")

const BASE_TREE_SIZE := 30
const PROFILE_COLUMNS := ["sapling", "juvenile", "mature"]
const ARCHETYPE_ROWS := ["deciduous", "conifer", "dead"]
const TERRAIN_BY_ARCHETYPE := {
	"deciduous": "GRASS",
	"conifer": "DARK_DIRT",
	"dead": "MUD",
}
const SEED_BY_ARCHETYPE := {
	"deciduous": 1103,
	"conifer": 2207,
	"dead": 3313,
}
const GALLERY_OUTPUT_PATH := "res://.codex_tmp/tree_profile_gallery.png"

var _validation_failures: Array[String] = []


func _ready() -> void:
	_build_gallery()
	_validate_determinism()
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if "--validate-tree-gallery" in user_args or "--capture-tree-gallery" in user_args:
		var capture_gallery: bool = "--capture-tree-gallery" in user_args
		await get_tree().process_frame
		if capture_gallery:
			await RenderingServer.frame_post_draw
		else:
			await get_tree().process_frame
		_finish_validation(capture_gallery)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1152.0, 648.0)), Color("18202a"))
	draw_rect(Rect2(Vector2(22.0, 62.0), Vector2(1108.0, 548.0)), Color("242f3d"), true)


func _build_gallery() -> void:
	_add_label("Procedural Tree Presentation Profiles", Vector2(24.0, 14.0), 26)
	_add_label("Visual-only debug gallery — runtime-generated trees remain mature", Vector2(25.0, 43.0), 14, Color("aebdca"))
	for column_index in PROFILE_COLUMNS.size():
		_add_label(PROFILE_COLUMNS[column_index].capitalize(), Vector2(205.0 + column_index * 245.0, 76.0), 18)
	_add_label("Fruiting Mature", Vector2(918.0, 76.0), 18)
	for row_index in ARCHETYPE_ROWS.size():
		var archetype: String = ARCHETYPE_ROWS[row_index]
		var baseline_y: float = 215.0 + row_index * 155.0
		_add_label(archetype.capitalize(), Vector2(42.0, baseline_y - 62.0), 18)
		_add_label(String(TERRAIN_BY_ARCHETYPE[archetype]), Vector2(42.0, baseline_y - 38.0), 12, Color("8293a3"))
		for column_index in PROFILE_COLUMNS.size():
			_add_tree(
				Vector2(245.0 + column_index * 245.0, baseline_y),
				int(SEED_BY_ARCHETYPE[archetype]),
				archetype,
				String(TERRAIN_BY_ARCHETYPE[archetype]),
				PROFILE_COLUMNS[column_index],
				false
			)
		if archetype == "deciduous":
			_add_tree(Vector2(990.0, baseline_y), 4409, archetype, "GRASS", "mature", true)


func _add_tree(position_value: Vector2, seed: int, archetype: String, terrain_tag: String, profile: String, force_fruit: bool) -> void:
	var holder := Node2D.new()
	holder.position = position_value
	holder.scale = Vector2(2.4, 2.4)
	add_child(holder)
	var texture: Texture2D = ProcSpriteCache.get_texture("tree", seed, BASE_TREE_SIZE, 0, archetype, terrain_tag, "large", profile)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = true
	sprite.offset = Vector2(0.0, -float(texture.get_height()) * 0.5)
	holder.add_child(sprite)
	if force_fruit:
		var overlay: Node2D = ResourceVariantOverlayScript.new()
		holder.add_child(overlay)
		var config: Dictionary = ResourceVisualDefinitionRef.get_definition("tree").get("visual_variant", {}).duplicate(true)
		config["chance_percent"] = 100
		overlay.call("configure", config, seed, archetype, texture)


func _add_label(text_value: String, position_value: Vector2, font_size: int, color: Color = Color.WHITE) -> void:
	var label := Label.new()
	label.text = text_value
	label.position = position_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)


func _validate_determinism() -> void:
	if ProcTrees.get_supported_presentation_profiles() != PackedStringArray(PROFILE_COLUMNS):
		_validation_failures.append("supported_profile_list_mismatch")
	if TreeProfiles.get_active_runtime_size_tier() != "large":
		_validation_failures.append("runtime_tree_tier_changed")
	for archetype: String in ARCHETYPE_ROWS:
		for profile: String in PROFILE_COLUMNS:
			var seed: int = int(SEED_BY_ARCHETYPE[archetype])
			var terrain_tag: String = String(TERRAIN_BY_ARCHETYPE[archetype])
			var first: Dictionary = ProcTrees.generate_tree(seed, BASE_TREE_SIZE, archetype, terrain_tag, "large", profile)
			var second: Dictionary = ProcTrees.generate_tree(seed, BASE_TREE_SIZE, archetype, terrain_tag, "large", profile)
			if first["canvas"].data != second["canvas"].data:
				_validation_failures.append("nondeterministic_%s_%s" % [archetype, profile])
			if String(first.get("archetype", "")) != archetype:
				_validation_failures.append("archetype_changed_%s_%s" % [archetype, profile])
			var expected_tier: String = "small" if profile == "sapling" else ("medium" if profile == "juvenile" else "large")
			if String(first.get("size_tier", "")) != expected_tier:
				_validation_failures.append("tier_mismatch_%s_%s" % [archetype, profile])
	var default_result: Dictionary = ProcTrees.generate_tree(5501, BASE_TREE_SIZE, "deciduous", "GRASS", "large")
	if String(default_result.get("presentation_profile", "")) != "mature" or String(default_result.get("size_tier", "")) != "large":
		_validation_failures.append("default_runtime_profile_changed")
	_validate_fruit_determinism()
	_validate_prewarm_scope()


func _validate_fruit_determinism() -> void:
	var config: Dictionary = ResourceVisualDefinitionRef.get_definition("tree").get("visual_variant", {}).duplicate(true)
	config["chance_percent"] = 100
	var first: Node2D = ResourceVariantOverlayScript.new()
	var second: Node2D = ResourceVariantOverlayScript.new()
	add_child(first)
	add_child(second)
	var texture: Texture2D = ProcSpriteCache.get_texture("tree", 4409, BASE_TREE_SIZE, 0, "deciduous", "GRASS", "large", "mature")
	first.call("configure", config, 4409, "deciduous", texture)
	second.call("configure", config, 4409, "deciduous", texture)
	if first.get("_fruit_points") != second.get("_fruit_points") or first.get("_fruit_colors") != second.get("_fruit_colors"):
		_validation_failures.append("nondeterministic_fruit_overlay")
	var fruit_count: int = (first.get("_fruit_points") as Array).size()
	if fruit_count < int(config.get("min_count", 0)) or fruit_count > int(config.get("max_count", fruit_count)):
		_validation_failures.append("fruit_count_out_of_range_%d" % fruit_count)
	first.queue_free()
	second.queue_free()


func _validate_prewarm_scope() -> void:
	const VARIANT_CAP := 18
	var request: Dictionary = PropPrewarmConfig.get_tree_request(VARIANT_CAP, BASE_TREE_SIZE)
	var size_tiers: PackedStringArray = request.get("size_tiers", PackedStringArray())
	if size_tiers != PackedStringArray(["large"]):
		_validation_failures.append("tree_prewarm_profiles_expanded")
		return
	ProcSpriteCache.clear()
	ProcSpriteCache.prewarm(String(request["kind"]), int(request["variant_cap"]), request["archetypes"], request["terrain_tags"], size_tiers, request["size_map"])
	var expected_count: int = VARIANT_CAP * (request["archetypes"] as PackedStringArray).size() * (request["terrain_tags"] as PackedStringArray).size()
	if ProcSpriteCache.get_cache_size() != expected_count:
		_validation_failures.append("tree_prewarm_cache_count_%d" % ProcSpriteCache.get_cache_size())


func _finish_validation(capture_gallery: bool) -> void:
	if capture_gallery:
		var viewport_texture: ViewportTexture = get_viewport().get_texture()
		var image: Image = viewport_texture.get_image() if viewport_texture != null else null
		if image == null:
			_validation_failures.append("gallery_capture_unavailable")
		else:
			var save_error: Error = image.save_png(ProjectSettings.globalize_path(GALLERY_OUTPUT_PATH))
			if save_error != OK:
				_validation_failures.append("gallery_save_failed_%d" % save_error)
	if _validation_failures.is_empty():
		var output_label: String = GALLERY_OUTPUT_PATH if capture_gallery else "not_requested"
		print("TREE_PROFILE_GALLERY_VALID profiles=sapling,juvenile,mature fruit=deterministic output=", output_label)
		get_tree().quit(0)
		return
	for failure: String in _validation_failures:
		push_error("Tree profile gallery validation failed: %s" % failure)
	get_tree().quit(1)
