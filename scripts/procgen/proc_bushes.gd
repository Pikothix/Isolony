extends RefCounted
class_name ProcBushes

## Purpose: Generate deterministic berry-bush sprites through the shared canvas pipeline.
## Responsibility: Own bush silhouette, foliage density, palette, and cosmetic berries.
## Assumption: The supplied seed is presentation metadata and does not affect harvesting.

const BushProfiles = preload("res://scripts/procgen/bush_profiles.gd")
const ProcCanvas = preload("res://scripts/procgen/proc_canvas.gd")
const ProcPrimitives = preload("res://scripts/procgen/proc_primitives.gd")
const ProcRng = preload("res://scripts/procgen/proc_rng.gd")


static func generate_bush(seed: int, size: int = 26, archetype: String = "", terrain_tag: String = "default") -> Dictionary:
	var rng := ProcRng.new(seed)
	var resolved_archetype: String = BushProfiles.resolve_archetype(seed, archetype)
	var actual_size: int = ProcPrimitives.clamp_int(size + rng.next_int(-2, 2), 20, 32)
	var canvas := ProcCanvas.new(actual_size, actual_size)
	var foliage_base: Array = ProcPrimitives.jitter_color(rng, ProcPrimitives.pick(rng, BushProfiles.get_foliage_bases(terrain_tag)), 10, [24, 70, 28], [100, 155, 82])
	var shadow: Array = ProcPrimitives.shift_color(foliage_base, -34, -30, -22)
	var highlight: Array = ProcPrimitives.shift_color(foliage_base, 34, 38, 20)
	var center := Vector2(float(actual_size) * 0.5 + rng.next_range(-0.7, 0.7), float(actual_size) * 0.66)
	var silhouette_scale := Vector2.ONE
	match resolved_archetype:
		"wide":
			silhouette_scale = Vector2(1.22, 0.82)
		"upright":
			silhouette_scale = Vector2(0.82, 1.18)
	var base_radius: float = float(actual_size) * rng.next_range(0.17, 0.21)
	var lobe_count: int = rng.next_int(5, 9)
	var lobes: Array = ProcPrimitives.distribute_lobes(rng, center.x, center.y, lobe_count, base_radius * 1.35, Vector2(0.35, 0.82), 0.62, Vector2(1.0, 0.55))
	var shadows: Array = []
	var bodies: Array = []
	var highlights: Array = []
	for lobe: Dictionary in lobes:
		var radius: float = base_radius * rng.next_range(0.62, 0.92)
		var rx: float = radius * silhouette_scale.x * rng.next_range(0.88, 1.12)
		var ry: float = radius * silhouette_scale.y * rng.next_range(0.82, 1.14)
		shadows.append({"cx": lobe.x, "cy": lobe.y + 1.0, "rx": rx * 1.08, "ry": ry * 1.08})
		bodies.append({"cx": lobe.x, "cy": lobe.y, "rx": rx, "ry": ry})
		highlights.append({"cx": lobe.x - 0.7, "cy": lobe.y - 1.0, "rx": rx * 0.46, "ry": ry * 0.36})
	ProcPrimitives.batch_stamp_ellipses(canvas, shadows, shadow[0], shadow[1], shadow[2], 235, 1.8, 0.72)
	ProcPrimitives.batch_stamp_ellipses(canvas, bodies, foliage_base[0], foliage_base[1], foliage_base[2], 245, 1.5, 0.68)
	ProcPrimitives.batch_stamp_ellipses(canvas, highlights, highlight[0], highlight[1], highlight[2], 205, 1.35, 0.55)
	var berry_palette_index: int = rng.next_int(0, BushProfiles.BERRY_PALETTES.size() - 1)
	var berry_palette: Array = BushProfiles.BERRY_PALETTES[berry_palette_index]
	var berry_count: int = rng.next_int(3, 9)
	var berry_points: Array[Vector2] = []
	var attempts: int = berry_count * 14
	while berry_points.size() < berry_count and attempts > 0:
		attempts -= 1
		var point := Vector2(
			center.x + rng.next_range(-base_radius * 1.45, base_radius * 1.45) * silhouette_scale.x,
			center.y + rng.next_range(-base_radius * 1.1, base_radius * 0.65) * silhouette_scale.y
		)
		var px: int = int(round(point.x))
		var py: int = int(round(point.y))
		if canvas.get_alpha(px, py) < 150:
			continue
		var separated := true
		for existing: Vector2 in berry_points:
			if existing.distance_squared_to(point) < 7.0:
				separated = false
				break
		if not separated:
			continue
		berry_points.append(point)
		var berry_color: Array = berry_palette[rng.next_int(0, berry_palette.size() - 1)]
		var radius: float = rng.next_range(0.85, 1.25)
		ProcPrimitives.stamp_ellipse(canvas, point.x, point.y, radius, radius, berry_color[0], berry_color[1], berry_color[2], 255, 1.8, 0.7)
		canvas.set_pixel(px - 1, py - 1, mini(255, berry_color[0] + 55), mini(255, berry_color[1] + 55), mini(255, berry_color[2] + 55), 235)
	ProcPrimitives.darken_rim(canvas, 18, 20, 12)
	ProcPrimitives.shift_to_bottom(canvas)
	return {
		"canvas": canvas,
		"archetype": resolved_archetype,
		"berry_count": berry_points.size(),
		"berry_palette": berry_palette,
		"berry_color_name": BushProfiles.BERRY_COLOR_NAMES[berry_palette_index],
	}
