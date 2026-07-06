extends Node2D
class_name ResourceVariantOverlay

## Purpose: Render deterministic resource embellishments above base resource artwork.
## Responsibility: Own visual-only fruit placement and color; ResourceNode owns configuration.
## Assumption: Variant seeds and metadata are reconstructible and never enter simulation or saves.

var _fruit_points: Array[Vector2] = []
var _fruit_colors: Array[Color] = []
static var _canopy_candidate_cache: Dictionary = {}


func configure(config: Dictionary, visual_seed: int, archetype: String, visual_source: Variant) -> void:
	_fruit_points.clear()
	_fruit_colors.clear()
	visible = false
	if String(config.get("kind", "")) != "tree_fruit_overlay":
		queue_redraw()
		return
	var allowed_archetypes: Array = config.get("allowed_archetypes", [])
	if not allowed_archetypes.is_empty() and archetype not in allowed_archetypes:
		queue_redraw()
		return
	var palettes: Array = config.get("palettes", [])
	var visual_size := Vector2.ZERO
	var canopy_texture: Texture2D = null
	if visual_source is Texture2D:
		canopy_texture = visual_source as Texture2D
		visual_size = canopy_texture.get_size()
	elif visual_source is Vector2:
		visual_size = visual_source
	if palettes.is_empty() or visual_size.x <= 0.0 or visual_size.y <= 0.0:
		queue_redraw()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = visual_seed + 130363
	var chance_percent: int = clampi(int(config.get("chance_percent", 0)), 0, 100)
	if rng.randi_range(0, 99) >= chance_percent:
		queue_redraw()
		return
	var minimum_count: int = maxi(0, int(config.get("min_count", 0)))
	var maximum_count: int = maxi(minimum_count, int(config.get("max_count", minimum_count)))
	var fruit_count: int = rng.randi_range(minimum_count, maximum_count)
	var palette: Array = palettes[rng.randi_range(0, palettes.size() - 1)]
	if fruit_count <= 0 or palette.is_empty():
		queue_redraw()
		return
	var canopy_candidates := PackedVector2Array()
	if canopy_texture != null:
		canopy_candidates = _get_canopy_candidates(canopy_texture)
	_build_fruit_points(rng, fruit_count, visual_size, palette, canopy_candidates)
	visible = not _fruit_points.is_empty()
	queue_redraw()


func _get_canopy_candidates(texture: Texture2D) -> PackedVector2Array:
	## Cache a sparse set of pixels with opaque neighbours. Sampling the generated
	## texture makes attachment follow every canopy silhouette without retaining a
	## second full-size mask or changing simulation/resource data.
	var cache_key: int = texture.get_rid().get_id()
	if _canopy_candidate_cache.has(cache_key):
		return _canopy_candidate_cache[cache_key]
	var image: Image = texture.get_image()
	var candidates := PackedVector2Array()
	if image == null or image.is_empty():
		_canopy_candidate_cache[cache_key] = candidates
		return candidates
	var width: int = image.get_width()
	var height: int = image.get_height()
	var maximum_y: int = mini(height - 3, int(floor(float(height) * 0.72)))
	for y in range(2, maximum_y + 1, 2):
		for x in range(2, width - 2, 2):
			if image.get_pixel(x, y).a <= 0.65:
				continue
			if image.get_pixel(x - 2, y).a <= 0.65 or image.get_pixel(x + 2, y).a <= 0.65:
				continue
			if image.get_pixel(x, y - 2).a <= 0.65 or image.get_pixel(x, y + 2).a <= 0.65:
				continue
			# Sprite2D is centered and offset upward by half its height, so texture
			# pixel coordinates map to local space with the bottom at y = 0.
			candidates.append(Vector2(float(x) - float(width) * 0.5, float(y - height)))
	_canopy_candidate_cache[cache_key] = candidates
	return candidates


func _build_fruit_points(rng: RandomNumberGenerator, fruit_count: int, visual_size: Vector2, palette: Array, canopy_candidates: PackedVector2Array) -> void:
	if not canopy_candidates.is_empty():
		var available: PackedVector2Array = canopy_candidates.duplicate()
		while _fruit_points.size() < fruit_count and not available.is_empty():
			var candidate_index: int = rng.randi_range(0, available.size() - 1)
			var point: Vector2 = available[candidate_index]
			available.remove_at(candidate_index)
			var overlaps_existing := false
			for existing: Vector2 in _fruit_points:
				if existing.distance_squared_to(point) < 16.0:
					overlaps_existing = true
					break
			if overlaps_existing:
				continue
			_fruit_points.append(point)
			_fruit_colors.append(palette[rng.randi_range(0, palette.size() - 1)])
		return
	# Placeholder fallback: retain a conservative core anchor when no generated
	# texture is available. Runtime procedural trees use the sampled path above.
	var canopy_center := Vector2(0.0, -visual_size.y * 0.58)
	var canopy_radius := Vector2(visual_size.x * 0.2, visual_size.y * 0.18)
	var attempts: int = fruit_count * 12
	while _fruit_points.size() < fruit_count and attempts > 0:
		attempts -= 1
		var normalized := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		if normalized.length_squared() > 1.0:
			continue
		var point := Vector2(
			roundf(canopy_center.x + normalized.x * canopy_radius.x),
			roundf(canopy_center.y + normalized.y * canopy_radius.y)
		)
		var overlaps_existing := false
		for existing: Vector2 in _fruit_points:
			if existing.distance_squared_to(point) < 16.0:
				overlaps_existing = true
				break
		if overlaps_existing:
			continue
		_fruit_points.append(point)
		_fruit_colors.append(palette[rng.randi_range(0, palette.size() - 1)])


func _draw() -> void:
	for index in _fruit_points.size():
		var point: Vector2 = _fruit_points[index]
		var color: Color = _fruit_colors[index]
		draw_rect(Rect2(point - Vector2(1.0, 1.0), Vector2(3.0, 3.0)), color)
		draw_rect(Rect2(point - Vector2(1.0, 1.0), Vector2(1.0, 1.0)), color.lightened(0.35))


func get_fruit_count() -> int:
	## Read-only presentation hook used by resource inspection UI.
	return _fruit_points.size() if visible else 0
