extends RefCounted
class_name ProcBoulders

const ProcCanvas = preload("res://scripts/procgen/proc_canvas.gd")
const ProcPrimitives = preload("res://scripts/procgen/proc_primitives.gd")
const ProcRng = preload("res://scripts/procgen/proc_rng.gd")
const RockProfiles = preload("res://scripts/procgen/rock_profiles.gd")

static func get_supported_archetypes() -> PackedStringArray:
	return RockProfiles.get_supported_archetypes()

static func get_supported_terrain_tags() -> PackedStringArray:
	return RockProfiles.get_supported_terrain_tags()

static func _size_scale_for_tier(size_tier: String) -> float:
	return RockProfiles.get_size_scale_for_tier(size_tier)

static func _archetype_from_seed(seed: int, requested: String, terrain_tag: String) -> String:
	return RockProfiles.resolve_archetype(seed, requested, terrain_tag)

static func _pick_stone_colors(rng: ProcRng, terrain_tag: String) -> Array:
	return RockProfiles.pick_stone_colors(rng, terrain_tag)

static func _add_surface_detail(canvas: ProcCanvas, rng: ProcRng, cx: float, cy: float, base_rx: float, base_ry: float, shadow_rgb: Array) -> void:
	if rng.next_float() <= 0.6:
		var crack_color: Array = ProcPrimitives.shift_color(shadow_rgb, -20, -20, -18)
		for _i in range(rng.next_int(1, 3)):
			var angle: float = rng.next_range(-PI, PI * 0.3)
			var start_r: float = rng.next_range(0.55, 0.85)
			var sx: float = cx + cos(angle) * base_rx * start_r
			var sy: float = cy + sin(angle) * base_ry * start_r
			var crack_angle: float = angle + PI + rng.next_range(-0.6, 0.6)
			var crack_len: float = rng.next_range(1.5, 3.5)
			ProcPrimitives.draw_line(canvas, int(round(sx)), int(round(sy)), int(round(sx + cos(crack_angle) * crack_len)), int(round(sy + sin(crack_angle) * crack_len)), crack_color[0], crack_color[1], crack_color[2], 190, 1)
	if rng.next_float() <= 0.5:
		for _i in range(rng.next_int(2, 4)):
			var spot_angle: float = rng.next_range(-PI * 0.8, PI * 0.4)
			var spot_dist: float = rng.next_range(0.25, 0.7)
			var mx: float = cx + cos(spot_angle) * base_rx * spot_dist
			var my: float = cy + sin(spot_angle) * base_ry * spot_dist
			var spot_radius: float = rng.next_range(0.7, 1.5)
			var lichen: Array = ProcPrimitives.pick(rng, RockProfiles.get_lichen_palette())
			ProcPrimitives.stamp_ellipse(canvas, mx, my, spot_radius, spot_radius, lichen[0], lichen[1], lichen[2], lichen[3], 1.4, 0.15)

static func _nibble_boulder(canvas: ProcCanvas, rng: ProcRng, nibble_prob: float) -> void:
	var rim: PackedByteArray = ProcPrimitives.compute_rim_mask(canvas)
	var first_opaque_row: int = canvas.height
	var last_opaque_row: int = -1
	for row in range(canvas.height):
		for col in range(canvas.width):
			if canvas.get_alpha(col, row) <= 0:
				continue
			first_opaque_row = mini(first_opaque_row, row)
			last_opaque_row = maxi(last_opaque_row, row)
	if first_opaque_row > last_opaque_row:
		return
	var midpoint: int = int((first_opaque_row + last_opaque_row) / 2)
	for row in range(midpoint, canvas.height):
		for col in range(canvas.width):
			rim[row * canvas.width + col] = 0
	ProcPrimitives.nibble_rim(canvas, rng, nibble_prob, rim)

static func _derive_lobe_layers(cx: float, cy: float, ox: float, oy: float, rx: float, ry: float, size: int) -> Dictionary:
	return {"body": {"cx": cx + ox, "cy": cy + oy, "rx": rx, "ry": ry}, "shadow": {"cx": cx + ox * 0.75, "cy": cy + oy * 0.675 + float(size) * 0.028, "rx": rx * 1.06, "ry": ry * 1.08}, "highlight": {"cx": cx + ox * 0.36 - float(size) * 0.028, "cy": cy + oy * 0.29 - float(size) * 0.065, "rx": rx * 0.32, "ry": ry * 0.21}}

static func _finish_boulder(canvas: ProcCanvas, rng: ProcRng, palette: Array, cx: float, cy: float, base_rx: float, base_ry: float, shadow_ellipses: Array, body_ellipses: Array, highlight_ellipses: Array, nibble_prob: float, falloff: Array = [2.2, 2.0, 1.9], hardness: Array = [0.88, 0.86, 0.8]) -> void:
	ProcPrimitives.stamp_three_tone(canvas, palette, shadow_ellipses, body_ellipses, highlight_ellipses, falloff, hardness)
	_add_surface_detail(canvas, rng, cx, cy, base_rx, base_ry, palette[0])
	_nibble_boulder(canvas, rng, nibble_prob)
	ProcPrimitives.darken_rim(canvas, 18, 18, 15)

static func _generate_rounded(canvas: ProcCanvas, size: int, rng: ProcRng, terrain_tag: String) -> void:
	var palette: Array = _pick_stone_colors(rng, terrain_tag)
	var cx: float = float(size) * 0.5 + rng.next_range(-0.3, 0.3)
	var cy: float = float(size) * 0.72 + rng.next_range(-0.08, 0.14)
	var base_rx: float = float(size) * rng.next_range(0.28, 0.34)
	var base_ry: float = float(size) * rng.next_range(0.20, 0.26)
	var body_ellipses: Array = [{"cx": cx, "cy": cy, "rx": base_rx, "ry": base_ry}, {"cx": cx + rng.next_range(-0.5, 0.5), "cy": cy - float(size) * 0.08, "rx": base_rx * 0.72, "ry": base_ry * 0.56}]
	var shadow_ellipses: Array = [{"cx": cx, "cy": cy + float(size) * 0.04, "rx": base_rx * 1.06, "ry": base_ry * 1.1}]
	var highlight_ellipses: Array = [{"cx": cx - float(size) * 0.05, "cy": cy - float(size) * 0.1, "rx": base_rx * 0.52, "ry": base_ry * 0.24}]
	for i in range(rng.next_int(2, 3)):
		var angle: float = rng.next_range(0.0, PI) + float(i) * PI + rng.next_range(-0.45, 0.45)
		var ox: float = cos(angle) * base_rx * rng.next_range(0.2, 0.42)
		var oy: float = maxf(0.0, sin(angle) * base_ry * rng.next_range(0.1, 0.3))
		var lobe: Dictionary = _derive_lobe_layers(cx, cy, ox, oy, base_rx * rng.next_range(0.7, 1.0), base_ry * rng.next_range(0.48, 0.68), size)
		body_ellipses.append(lobe["body"])
		shadow_ellipses.append(lobe["shadow"])
		highlight_ellipses.append(lobe["highlight"])
	_finish_boulder(canvas, rng, palette, cx, cy, base_rx, base_ry, shadow_ellipses, body_ellipses, highlight_ellipses, 0.1)

static func _generate_tall(canvas: ProcCanvas, size: int, rng: ProcRng, terrain_tag: String) -> void:
	var palette: Array = _pick_stone_colors(rng, terrain_tag)
	var cx: float = float(size) * 0.5 + rng.next_range(-0.3, 0.3)
	var cy: float = float(size) * 0.70 + rng.next_range(-0.06, 0.10)
	var base_rx: float = float(size) * rng.next_range(0.22, 0.28)
	var base_ry: float = float(size) * rng.next_range(0.26, 0.34)
	var body_ellipses: Array = [{"cx": cx, "cy": cy + float(size) * 0.08, "rx": base_rx * 1.30, "ry": base_ry * 0.58}, {"cx": cx, "cy": cy, "rx": base_rx, "ry": base_ry}, {"cx": cx + rng.next_range(-0.5, 0.5), "cy": cy - float(size) * 0.12, "rx": base_rx * 0.65, "ry": base_ry * 0.48}]
	var shadow_ellipses: Array = [{"cx": cx, "cy": cy + float(size) * 0.09, "rx": base_rx * 1.36, "ry": base_ry * 0.65}]
	var highlight_ellipses: Array = [{"cx": cx - float(size) * 0.04, "cy": cy - float(size) * 0.14, "rx": base_rx * 0.56, "ry": base_ry * 0.22}]
	for _i in range(rng.next_int(1, 2)):
		var angle: float = rng.next_range(0.0, PI) + rng.next_range(-0.4, 0.4)
		var ox: float = cos(angle) * base_rx * rng.next_range(0.28, 0.52)
		var oy: float = maxf(0.0, sin(angle) * base_ry * rng.next_range(0.10, 0.26))
		var lobe: Dictionary = _derive_lobe_layers(cx, cy, ox, oy, base_rx * rng.next_range(0.62, 0.90), base_ry * rng.next_range(0.42, 0.62), size)
		body_ellipses.append(lobe["body"])
		shadow_ellipses.append(lobe["shadow"])
		highlight_ellipses.append(lobe["highlight"])
	_finish_boulder(canvas, rng, palette, cx, cy, base_rx, base_ry, shadow_ellipses, body_ellipses, highlight_ellipses, 0.10)

static func _generate_flat(canvas: ProcCanvas, size: int, rng: ProcRng, terrain_tag: String) -> void:
	var palette: Array = _pick_stone_colors(rng, terrain_tag)
	var cx: float = float(size) * 0.5 + rng.next_range(-0.4, 0.4)
	var cy: float = float(size) * 0.78 + rng.next_range(-0.06, 0.08)
	var base_rx: float = float(size) * rng.next_range(0.36, 0.44)
	var base_ry: float = float(size) * rng.next_range(0.13, 0.18)
	var body_ellipses: Array = [{"cx": cx, "cy": cy, "rx": base_rx, "ry": base_ry}, {"cx": cx + rng.next_range(-0.5, 0.5), "cy": cy - float(size) * 0.04, "rx": base_rx * 0.80, "ry": base_ry * 0.55}]
	var shadow_ellipses: Array = [{"cx": cx, "cy": cy + float(size) * 0.03, "rx": base_rx * 1.06, "ry": base_ry * 1.14}]
	var highlight_ellipses: Array = [{"cx": cx - float(size) * 0.04, "cy": cy - float(size) * 0.05, "rx": base_rx * 0.58, "ry": base_ry * 0.28}]
	for _i in range(rng.next_int(1, 2)):
		var angle: float = (0.0 if rng.next_int(0, 1) == 0 else PI) + rng.next_range(-0.35, 0.35)
		var ox: float = cos(angle) * base_rx * rng.next_range(0.18, 0.38)
		var oy: float = maxf(0.0, sin(angle) * base_ry * rng.next_range(0.08, 0.22))
		var lobe: Dictionary = _derive_lobe_layers(cx, cy, ox, oy, base_rx * rng.next_range(0.65, 0.92), base_ry * rng.next_range(0.44, 0.64), size)
		body_ellipses.append(lobe["body"])
		shadow_ellipses.append(lobe["shadow"])
		highlight_ellipses.append(lobe["highlight"])
	_finish_boulder(canvas, rng, palette, cx, cy, base_rx, base_ry, shadow_ellipses, body_ellipses, highlight_ellipses, 0.08)

static func _generate_blocky(canvas: ProcCanvas, size: int, rng: ProcRng, terrain_tag: String) -> void:
	var palette: Array = _pick_stone_colors(rng, terrain_tag)
	var cx: float = float(size) * 0.5 + rng.next_range(-0.6, 0.6)
	var cy: float = float(size) * 0.72 + rng.next_range(-0.08, 0.12)
	var base_rx: float = float(size) * rng.next_range(0.26, 0.32)
	var base_ry: float = float(size) * rng.next_range(0.22, 0.28)
	var body_ellipses: Array = [{"cx": cx, "cy": cy, "rx": base_rx, "ry": base_ry}, {"cx": cx - float(size) * 0.03, "cy": cy - float(size) * 0.07, "rx": base_rx * 0.74, "ry": base_ry * 0.62}]
	var shadow_ellipses: Array = [{"cx": cx, "cy": cy + float(size) * 0.04, "rx": base_rx * 1.1, "ry": base_ry * 1.1}]
	var highlight_ellipses: Array = [{"cx": cx - float(size) * 0.06, "cy": cy - float(size) * 0.1, "rx": base_rx * 0.44, "ry": base_ry * 0.22}]
	var cluster_angle: float = rng.next_range(0.0, TAU)
	for _i in range(rng.next_int(2, 3)):
		var angle: float = cluster_angle + rng.next_range(-1.05, 1.05)
		var ox: float = cos(angle) * base_rx * rng.next_range(0.26, 0.5)
		var oy: float = maxf(0.0, sin(angle) * base_ry * rng.next_range(0.16, 0.38))
		var lobe: Dictionary = _derive_lobe_layers(cx, cy, ox, oy, base_rx * rng.next_range(0.68, 1.02), base_ry * rng.next_range(0.48, 0.7), size)
		body_ellipses.append(lobe["body"])
		shadow_ellipses.append(lobe["shadow"])
		highlight_ellipses.append(lobe["highlight"])
	_finish_boulder(canvas, rng, palette, cx, cy, base_rx, base_ry, shadow_ellipses, body_ellipses, highlight_ellipses, 0.14, [2.4, 2.2, 2.0], [0.92, 0.9, 0.84])

static func generate_boulder(seed: int, size: int = 16, archetype: String = "", terrain_tag: String = "default", size_tier: String = "medium") -> Dictionary:
	var resolved_archetype: String = _archetype_from_seed(seed, archetype, terrain_tag)
	var rng := ProcRng.new(seed)
	var actual_size: int = ProcPrimitives.clamp_int(int(round(float(size + rng.next_int(-2, 2)) * _size_scale_for_tier(size_tier))), 12, 28)
	var canvas := ProcCanvas.new(actual_size, actual_size)
	match resolved_archetype:
		"tall":
			_generate_tall(canvas, actual_size, rng, terrain_tag)
		"flat":
			_generate_flat(canvas, actual_size, rng, terrain_tag)
		"blocky":
			_generate_blocky(canvas, actual_size, rng, terrain_tag)
		_:
			_generate_rounded(canvas, actual_size, rng, terrain_tag)
	ProcPrimitives.shift_to_bottom(canvas)
	return {"canvas": canvas, "archetype": resolved_archetype}
