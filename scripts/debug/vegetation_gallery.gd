extends Node2D

## Purpose: Present representative procedural vegetation and rock variants for review.
## Responsibility: Build and validate a development-only comparison gallery.
## Assumption: This scene is launched directly and is never integrated into gameplay.

const ProcBushes = preload("res://scripts/procgen/proc_bushes.gd")
const ProcSpriteCache = preload("res://scripts/procgen/proc_sprite_cache.gd")
const ProcTrees = preload("res://scripts/procgen/proc_trees.gd")
const ResourceVariantOverlayScript = preload("res://scripts/entities/resource_variant_overlay.gd")
const ResourceVisualDefinitionRef = preload("res://scripts/world/props/resource_visual_definition.gd")

const OUTPUT_PATH := "res://.codex_tmp/vegetation_gallery.png"
const TREE_SIZE := 38
const BUSH_SIZE := 28
const ROCK_SIZE := 24

var _validation_failures: Array[String] = []


func _ready() -> void:
	_build_gallery()
	_validate_determinism()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--validate-vegetation-gallery" in args or "--capture-vegetation-gallery" in args:
		await get_tree().process_frame
		var capture: bool = "--capture-vegetation-gallery" in args
		if capture:
			# Capture requires a rendered frame; validation remains compatible with
			# headless/dummy rendering by using the non-capture argument.
			await RenderingServer.frame_post_draw
		_finish(capture)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280.0, 720.0)), Color("17202a"))
	draw_rect(Rect2(24.0, 58.0, 1232.0, 200.0), Color("232f3b"))
	draw_rect(Rect2(24.0, 276.0, 1232.0, 196.0), Color("232f3b"))
	draw_rect(Rect2(24.0, 490.0, 1232.0, 190.0), Color("232f3b"))


func _build_gallery() -> void:
	_add_label("Procedural Vegetation Gallery", Vector2(24.0, 12.0), 26)
	_add_label("Development-only · deterministic presentation variants", Vector2(420.0, 20.0), 14, Color("aebdca"))
	_add_label("Trees", Vector2(42.0, 68.0), 20)
	var tree_specs: Array = [
		["Sapling", 1103, "deciduous", "GRASS", "sapling", false],
		["Juvenile", 1103, "deciduous", "GRASS", "juvenile", false],
		["Mature deciduous", 1207, "deciduous", "GRASS", "mature", false],
		["Mature conifer", 2207, "conifer", "DARK_DIRT", "mature", false],
		["Dead tree", 3313, "dead", "MUD", "mature", false],
		["Fruiting deciduous", 4409, "deciduous", "GRASS", "mature", true],
	]
	for index in tree_specs.size():
		var spec: Array = tree_specs[index]
		var x: float = 155.0 + float(index) * 198.0
		_add_tree(Vector2(x, 222.0), int(spec[1]), String(spec[2]), String(spec[3]), String(spec[4]), bool(spec[5]))
		_add_centered_label(String(spec[0]), Vector2(x, 92.0), 156.0)

	_add_label("Berry bushes", Vector2(42.0, 286.0), 20)
	for index in 7:
		var seed: int = 6101 + index * 127
		var x: float = 176.0 + float(index) * 160.0
		var terrain: String = ["GRASS", "DARK_DIRT", "MUD"][index % 3]
		_add_sprite(Vector2(x, 430.0), ProcSpriteCache.get_texture("bush", seed, BUSH_SIZE, 0, "", terrain, "small"), 3.0)
		var result: Dictionary = ProcBushes.generate_bush(seed, BUSH_SIZE, "", terrain)
		_add_centered_label("%s · %d berries" % [String(result["archetype"]).capitalize(), int(result["berry_count"])], Vector2(x, 320.0), 142.0, 13)

	_add_label("Rocks", Vector2(42.0, 500.0), 20)
	var rock_archetypes := ["rounded", "tall", "flat", "blocky"]
	for index in rock_archetypes.size():
		var x: float = 270.0 + float(index) * 250.0
		var terrain: String = ["GRASS", "DARK_DIRT", "MUD", "STONE"][index]
		_add_sprite(Vector2(x, 646.0), ProcSpriteCache.get_texture("rock", 8003 + index * 211, ROCK_SIZE, 0, rock_archetypes[index], terrain, "medium"), 3.0)
		_add_centered_label("%s · %s" % [String(rock_archetypes[index]).capitalize(), terrain], Vector2(x, 536.0), 180.0)


func _add_tree(position_value: Vector2, seed: int, archetype: String, terrain: String, profile: String, fruiting: bool) -> void:
	var holder := Node2D.new()
	holder.position = position_value
	holder.scale = Vector2(2.55, 2.55)
	add_child(holder)
	var texture: Texture2D = ProcSpriteCache.get_texture("tree", seed, TREE_SIZE, 0, archetype, terrain, "large", profile)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.offset = Vector2(0.0, -float(texture.get_height()) * 0.5)
	holder.add_child(sprite)
	if fruiting:
		var overlay: Node2D = ResourceVariantOverlayScript.new()
		holder.add_child(overlay)
		var config: Dictionary = ResourceVisualDefinitionRef.get_definition("tree").get("visual_variant", {}).duplicate(true)
		config["chance_percent"] = 100
		overlay.call("configure", config, seed, archetype, texture)


func _add_sprite(position_value: Vector2, texture: Texture2D, scale_value: float) -> void:
	var sprite := Sprite2D.new()
	sprite.position = position_value
	sprite.scale = Vector2(scale_value, scale_value)
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.offset = Vector2(0.0, -float(texture.get_height()) * 0.5)
	add_child(sprite)


func _add_label(text_value: String, position_value: Vector2, font_size: int, color: Color = Color.WHITE) -> void:
	var label := Label.new()
	label.text = text_value
	label.position = position_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)


func _add_centered_label(text_value: String, center: Vector2, width: float, font_size: int = 14) -> void:
	var label := Label.new()
	label.text = text_value
	label.position = Vector2(center.x - width * 0.5, center.y)
	label.size = Vector2(width, 24.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("d6e0e8"))
	add_child(label)


func _validate_determinism() -> void:
	for seed in [6101, 6228, 6355, 6482]:
		var first: Dictionary = ProcBushes.generate_bush(seed, BUSH_SIZE, "", "GRASS")
		var second: Dictionary = ProcBushes.generate_bush(seed, BUSH_SIZE, "", "GRASS")
		if first["canvas"].data != second["canvas"].data:
			_validation_failures.append("nondeterministic_bush_%d" % seed)
		if int(first["berry_count"]) < 3 or int(first["berry_count"]) > 9:
			_validation_failures.append("berry_count_out_of_range_%d" % seed)
	var tree_texture: Texture2D = ProcSpriteCache.get_texture("tree", 4409, TREE_SIZE, 0, "deciduous", "GRASS", "large", "mature")
	var config: Dictionary = ResourceVisualDefinitionRef.get_definition("tree").get("visual_variant", {}).duplicate(true)
	config["chance_percent"] = 100
	var first_overlay: Node2D = ResourceVariantOverlayScript.new()
	var second_overlay: Node2D = ResourceVariantOverlayScript.new()
	add_child(first_overlay)
	add_child(second_overlay)
	first_overlay.call("configure", config, 4409, "deciduous", tree_texture)
	second_overlay.call("configure", config, 4409, "deciduous", tree_texture)
	if first_overlay.get("_fruit_points") != second_overlay.get("_fruit_points"):
		_validation_failures.append("nondeterministic_fruit")
	var image: Image = tree_texture.get_image()
	for point: Vector2 in first_overlay.get("_fruit_points"):
		var pixel := Vector2i(int(round(point.x + float(image.get_width()) * 0.5)), int(round(point.y + float(image.get_height()))))
		if image.get_pixelv(pixel).a <= 0.65:
			_validation_failures.append("detached_fruit_%s" % pixel)
	first_overlay.queue_free()
	second_overlay.queue_free()
	_validate_fruit_anchor_matrix(config)
	_validate_resource_boundaries()
	_validate_bush_cache_cap()


func _validate_fruit_anchor_matrix(config: Dictionary) -> void:
	var terrains := ["GRASS", "DARK_DIRT", "MUD"]
	var profiles := ["sapling", "juvenile", "mature"]
	for terrain: String in terrains:
		for profile: String in profiles:
			for seed in [1207, 4409, 7717]:
				var texture: Texture2D = ProcSpriteCache.get_texture("tree", seed, TREE_SIZE, 0, "deciduous", terrain, "large", profile)
				var overlay: Node2D = ResourceVariantOverlayScript.new()
				add_child(overlay)
				overlay.call("configure", config, seed, "deciduous", texture)
				var image: Image = texture.get_image()
				var points: Array = overlay.get("_fruit_points")
				if points.size() < int(config.get("min_count", 0)):
					_validation_failures.append("insufficient_fruit_%s_%s_%d" % [terrain, profile, seed])
				for point: Vector2 in points:
					var pixel := Vector2i(int(round(point.x + float(image.get_width()) * 0.5)), int(round(point.y + float(image.get_height()))))
					if image.get_pixelv(pixel).a <= 0.65:
						_validation_failures.append("detached_fruit_%s_%s_%d" % [terrain, profile, seed])
				overlay.queue_free()


func _validate_resource_boundaries() -> void:
	var bush_scene: PackedScene = load("res://scenes/entities/BerryBush.tscn") as PackedScene
	var bush: Node = bush_scene.instantiate()
	if bush.get("resource_type") != "food" or int(bush.get("yield_amount")) != 6:
		_validation_failures.append("berry_gameplay_fields_changed")
	if bush.get_node_or_null("CollisionShape2D") == null or not bush.has_method("set_harvest_designated"):
		_validation_failures.append("berry_interaction_boundary_changed")
	bush.call("set_harvest_designated", true)
	if not bool(bush.call("is_harvest_designated")):
		_validation_failures.append("harvest_designation_failed")
	bush.free()


func _validate_bush_cache_cap() -> void:
	ProcSpriteCache.clear()
	for seed in range(24):
		ProcSpriteCache.get_texture("bush", seed, 26, 8, "", "GRASS", "small")
	if ProcSpriteCache.get_cache_size() != 8:
		_validation_failures.append("bush_cache_cap_%d" % ProcSpriteCache.get_cache_size())


func _finish(capture: bool) -> void:
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.codex_tmp"))
		var error: Error = get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
		if error != OK:
			_validation_failures.append("capture_failed_%d" % error)
	if _validation_failures.is_empty():
		print("VEGETATION_GALLERY_VALID output=", OUTPUT_PATH if capture else "not_requested")
		get_tree().quit(0)
		return
	for failure: String in _validation_failures:
		push_error("Vegetation gallery validation failed: %s" % failure)
	get_tree().quit(1)
