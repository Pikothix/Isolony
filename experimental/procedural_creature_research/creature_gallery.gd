extends Control

## Owns transient seed, gallery type, diagnostic mode, and scale-preview interaction.

const DEFINITION := preload("res://experimental/procedural_creature_research/definitions/small_quadruped.tres")
const GenomeGenerator := preload("res://experimental/procedural_creature_research/creature_genome_generator.gd")
const CreatureVisual := preload("res://experimental/procedural_creature_research/procedural_creature_visual.gd")
const DiagnosticFactory := preload("res://experimental/procedural_creature_research/diagnostic_creature_factory.gd")
const RigScript := preload("res://experimental/procedural_creature_research/creature_rig.gd")
const FacingProjection := preload("res://experimental/procedural_creature_research/creature_facing_projection.gd")
const ModularRenderer := preload("res://experimental/procedural_creature_research/modular_creature_sprite_renderer.gd")
const SPRITE_SET := preload("res://experimental/procedural_creature_research/definitions/small_quadruped_sprite_set.tres")
const VARIANT_COUNT := 12
const COLUMNS := 4

@onready var seed_input: SpinBox = %SeedInput
@onready var gallery: Node2D = %Gallery
@onready var summary_label: Label = %SummaryLabel
@onready var mode_selector: OptionButton = %ModeSelector
@onready var gallery_selector: OptionButton = %GallerySelector
@onready var game_scale_toggle: CheckButton = %GameScaleToggle
@onready var facing_selector: OptionButton = %FacingSelector
@onready var four_facing_toggle: CheckButton = %FourFacingToggle
@onready var renderer_selector: OptionButton = %RendererSelector

var _base_seed: int = 1000
var _gait: String = RigScript.GAIT_IDLE
var _paused: bool = false
var _animation_speed: float = 1.0


func _ready() -> void:
	for mode: String in CreatureVisual.SUPPORTED_MODES:
		mode_selector.add_item(mode)
	gallery_selector.add_item("Normal Seeds")
	gallery_selector.add_item("Extreme Specimens")
	for facing: String in FacingProjection.FACINGS:
		facing_selector.add_item(facing)
	renderer_selector.add_item("Procedural Polygons")
	renderer_selector.add_item("Modular Sprites")
	renderer_selector.add_item("Side-by-Side")
	%PreviousButton.pressed.connect(_change_seed.bind(-1))
	%NextButton.pressed.connect(_change_seed.bind(1))
	%RandomButton.pressed.connect(_randomize_seed)
	%RegenerateButton.pressed.connect(_regenerate_from_input)
	seed_input.value_changed.connect(_on_seed_value_changed)
	mode_selector.item_selected.connect(_on_diagnostic_changed)
	gallery_selector.item_selected.connect(_on_gallery_changed)
	game_scale_toggle.toggled.connect(_on_game_scale_toggled)
	facing_selector.item_selected.connect(_on_facing_changed)
	four_facing_toggle.toggled.connect(_on_four_facing_toggled)
	renderer_selector.item_selected.connect(_on_renderer_changed)
	%IdleButton.pressed.connect(_set_gait.bind(RigScript.GAIT_IDLE))
	%WalkingButton.pressed.connect(_set_gait.bind(RigScript.GAIT_WALKING))
	%PlantedButton.pressed.connect(_set_gait.bind(RigScript.GAIT_PLANTED))
	%ResetLocomotionButton.pressed.connect(_reset_locomotion)
	%PauseButton.toggled.connect(_set_paused)
	%SpeedSlider.value_changed.connect(_set_speed)
	seed_input.value = _base_seed
	_rebuild_gallery()


func _change_seed(delta: int) -> void:
	seed_input.value = int(seed_input.value) + delta


func _randomize_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	seed_input.value = rng.randi_range(0, 2_000_000_000)


func _regenerate_from_input() -> void:
	_base_seed = int(seed_input.value)
	_rebuild_gallery()


func _on_seed_value_changed(value: float) -> void:
	_base_seed = int(value)
	_rebuild_gallery()


func _on_diagnostic_changed(_index: int) -> void:
	_rebuild_gallery()


func _on_gallery_changed(_index: int) -> void:
	_rebuild_gallery()


func _on_game_scale_toggled(_enabled: bool) -> void:
	_rebuild_gallery()


func _on_facing_changed(_index: int) -> void:
	_rebuild_gallery()


func _on_four_facing_toggled(_enabled: bool) -> void:
	_rebuild_gallery()


func _on_renderer_changed(_index: int) -> void:
	_apply_renderer_visibility()


func _set_gait(gait: String) -> void:
	_gait = gait
	_update_animation_controls()


func _set_paused(paused: bool) -> void:
	_paused = paused
	_update_animation_controls()


func _set_speed(speed: float) -> void:
	_animation_speed = speed
	%SpeedValue.text = "%.2fx" % speed
	_update_animation_controls()


func _reset_locomotion() -> void:
	for cell in gallery.get_children():
		for child in cell.get_children():
			if child.has_method("reset_locomotion"):
				child.reset_locomotion()


func _update_animation_controls() -> void:
	for cell in gallery.get_children():
		for child in cell.get_children():
			if child.has_method("set_animation"):
				child.set_animation(_gait, _animation_speed, _paused)
	%MotionState.text = "%s%s" % [_gait, " (paused)" if _paused else ""]


func _rebuild_gallery() -> void:
	for child in gallery.get_children():
		child.queue_free()
	var specimens := _get_specimens()
	var display_entries: Array[Dictionary] = []
	if four_facing_toggle.button_pressed and not specimens.is_empty():
		for facing: String in FacingProjection.FACINGS:
			display_entries.append({"label": "%s • %s" % [specimens[0].label, facing], "genome": specimens[0].genome, "facing": facing})
	else:
		var selected_facing: String = facing_selector.get_item_text(facing_selector.selected)
		for specimen: Dictionary in specimens:
			var entry := specimen.duplicate(true)
			entry.facing = selected_facing
			display_entries.append(entry)
	var summaries: Array[String] = []
	var mode := mode_selector.get_item_text(mode_selector.selected)
	for index in range(display_entries.size()):
		var entry: Dictionary = display_entries[index]
		var genome: Resource = entry.genome
		var cell := Node2D.new()
		cell.set_meta("genome", genome)
		var columns: int = 2 if four_facing_toggle.button_pressed else COLUMNS
		var spacing := Vector2(430, 220) if four_facing_toggle.button_pressed else Vector2(245, 145)
		cell.position = Vector2(235 + (index % columns) * spacing.x, 270 + (index / columns) * spacing.y) if four_facing_toggle.button_pressed else Vector2(130 + (index % columns) * spacing.x, 225 + (index / columns) * spacing.y)
		gallery.add_child(cell)
		if game_scale_toggle.button_pressed:
			_add_isometric_reference(cell)
		var visual: Node2D = CreatureVisual.new()
		var renderer_mode: int = renderer_selector.selected
		var presentation_scale := Vector2.ONE if game_scale_toggle.button_pressed else Vector2(2.0, 2.0)
		visual.scale = presentation_scale
		visual.configure(genome, mode)
		visual.set_facing(entry.facing)
		visual.set_animation(_gait, _animation_speed, _paused)
		cell.add_child(visual)
		if renderer_mode in [1, 2]:
			var modular: Node2D = _create_modular_renderer(cell, visual, genome, mode)
			_apply_cell_renderer_visibility(visual, modular, renderer_mode)
		var label := Label.new()
		label.position = Vector2(-75, 22)
		label.text = entry.label
		label.add_theme_font_size_override("font_size", 12)
		cell.add_child(label)
		summaries.append(genome.debug_summary())
	var gallery_name := gallery_selector.get_item_text(gallery_selector.selected)
	var scale_name := "game scale on 32x16 cell" if game_scale_toggle.button_pressed else "2x inspection scale"
	var facing_name := "four-facing comparison" if four_facing_toggle.button_pressed else FacingProjection.display_name(facing_selector.get_item_text(facing_selector.selected))
	summary_label.text = "%d views • %s • %s • %s • %s • %s" % [display_entries.size(), gallery_name, facing_name, renderer_selector.get_item_text(renderer_selector.selected), mode, scale_name]
	print("CREATURE_GALLERY_SUMMARIES ", JSON.stringify(summaries))


func _apply_renderer_visibility() -> void:
	for cell in gallery.get_children():
		var polygon_visual: Node2D
		var modular_visual: Node2D
		for child in cell.get_children():
			if child.has_method("get_projected_pose"):
				polygon_visual = child
			elif child.has_method("get_sprite_count"):
				modular_visual = child
		if modular_visual == null and renderer_selector.selected in [1, 2] and polygon_visual != null:
			modular_visual = _create_modular_renderer(cell, polygon_visual, cell.get_meta("genome"), mode_selector.get_item_text(mode_selector.selected))
		if polygon_visual != null and modular_visual != null:
			_apply_cell_renderer_visibility(polygon_visual, modular_visual, renderer_selector.selected)
		elif polygon_visual != null:
			polygon_visual.visible = true
			polygon_visual.position = Vector2.ZERO


func _create_modular_renderer(cell: Node2D, polygon_visual: Node2D, genome: Resource, mode: String) -> Node2D:
	var modular: Node2D = ModularRenderer.new()
	modular.scale = polygon_visual.scale
	modular.configure(genome, SPRITE_SET, polygon_visual, mode)
	cell.add_child(modular)
	return modular


func _apply_cell_renderer_visibility(polygon_visual: Node2D, modular_visual: Node2D, renderer_mode: int) -> void:
	polygon_visual.visible = renderer_mode != 1
	modular_visual.visible = renderer_mode != 0
	polygon_visual.position = Vector2.ZERO
	modular_visual.position = Vector2.ZERO
	if renderer_mode == 2:
		var separation: float = 34.0 if game_scale_toggle.button_pressed else 42.0
		polygon_visual.position.x = -separation
		modular_visual.position.x = separation


func _get_specimens() -> Array[Dictionary]:
	if gallery_selector.selected == 1:
		return DiagnosticFactory.create_specimens(DEFINITION)
	var result: Array[Dictionary] = []
	for index in range(VARIANT_COUNT):
		var creature_seed := _base_seed + index
		var genome: Resource = GenomeGenerator.generate(DEFINITION, creature_seed)
		if genome != null:
			result.append({"label": "seed %d" % creature_seed, "genome": genome})
	return result


func _add_isometric_reference(parent: Node2D) -> void:
	var diamond := Polygon2D.new()
	diamond.polygon = PackedVector2Array([Vector2(0, -8), Vector2(16, 0), Vector2(0, 8), Vector2(-16, 0)])
	diamond.color = Color(0.24, 0.29, 0.32, 0.65)
	diamond.position = Vector2(0, 2)
	diamond.z_index = -2
	parent.add_child(diamond)
	var marker := Line2D.new()
	marker.points = PackedVector2Array([Vector2(-24, 0), Vector2(-24, -16)])
	marker.width = 1.0
	marker.default_color = Color(0.65, 0.72, 0.76, 0.8)
	marker.z_index = -1
	parent.add_child(marker)
