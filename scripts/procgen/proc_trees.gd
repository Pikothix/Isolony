extends RefCounted
class_name ProcTrees

const ProcCanvas = preload("res://scripts/procgen/proc_canvas.gd")
const ProcPrimitives = preload("res://scripts/procgen/proc_primitives.gd")
const ProcRng = preload("res://scripts/procgen/proc_rng.gd")
const TreeProfiles = preload("res://scripts/procgen/tree_profiles.gd")

static func get_supported_archetypes() -> PackedStringArray:
	return TreeProfiles.get_supported_archetypes()

static func get_supported_terrain_tags() -> PackedStringArray:
	return TreeProfiles.get_supported_terrain_tags()

static func _size_scale_for_tier(size_tier: String) -> float:
	return TreeProfiles.get_size_scale_for_tier(size_tier)

static func _resolve_canvas_size(rng: ProcRng, archetype: String, base_size: int, size_tier: String) -> int:
	var size: int = int(round(float(base_size + rng.next_int(-3, 3)) * _size_scale_for_tier(size_tier)))
	if archetype == "conifer":
		size += 1
	elif archetype == TreeProfiles.INTERNAL_ARCHETYPE_SAPLING:
		size -= 2
	return ProcPrimitives.clamp_int(size, 14, 42)

static func _pick_canopy_base(rng: ProcRng, terrain_tag: String, archetype: String) -> Array:
	return TreeProfiles.pick_canopy_base(rng, terrain_tag, archetype)

static func _resolve_archetype(seed: int, requested: String, terrain_tag: String) -> String:
	return TreeProfiles.resolve_archetype(seed, requested, terrain_tag)

static func _draw_segment(canvas: ProcCanvas, from_x: float, from_y: float, to_x: float, to_y: float, rgba: Array, thickness: int = 1) -> void:
	ProcPrimitives.draw_line(canvas, int(round(from_x)), int(round(from_y)), int(round(to_x)), int(round(to_y)), rgba[0], rgba[1], rgba[2], rgba[3], maxi(1, thickness))

static func _fill_horizontal(canvas: ProcCanvas, y: int, left: int, right: int, rgba: Array) -> void:
	if y < 0 or y >= canvas.height:
		return
	var clamped_left: int = ProcPrimitives.clamp_int(mini(left, right), 0, canvas.width - 1)
	var clamped_right: int = ProcPrimitives.clamp_int(maxi(left, right), 0, canvas.width - 1)
	for x in range(clamped_left, clamped_right + 1):
		canvas.set_pixel(x, y, rgba[0], rgba[1], rgba[2], rgba[3])

static func _draw_tapered_trunk(canvas: ProcCanvas, cx: float, bottom_y: int, top_y: int, width_bottom: float, width_top: float, rgba: Array, root_flare: int) -> void:
	var y0: int = maxi(0, mini(top_y, bottom_y))
	var y1: int = mini(canvas.height - 1, maxi(top_y, bottom_y))
	var span: int = maxi(1, y1 - y0)
	for y in range(y0, y1 + 1):
		var t: float = float(y - y0) / float(span)
		var width: float = width_top + (width_bottom - width_top) * t
		var half: float = maxf(0.5, width * 0.5)
		_fill_horizontal(canvas, y, int(round(cx - half)), int(round(cx + half)), rgba)
	for i in range(maxi(1, root_flare)):
		var flare_width: float = width_bottom + float(root_flare - i)
		var half_flare: float = flare_width * 0.5
		_fill_horizontal(canvas, mini(canvas.height - 1, y1 - i), int(round(cx - half_flare)), int(round(cx + half_flare)), rgba)

static func _nibble_canopy(canvas: ProcCanvas, rng: ProcRng, cx: float, cy: float, radius: float, nibble_prob: float, interior_prob: float) -> void:
	var rim: PackedByteArray = ProcPrimitives.compute_rim_mask(canvas)
	var safe_radius: float = maxf(radius, 0.000001)
	var has_rim: bool = false
	for row in range(canvas.height):
		for col in range(canvas.width):
			if rim[row * canvas.width + col] == 0:
				continue
			var dx: float = (float(col) - cx) / safe_radius
			var dy: float = (float(row) - cy) / (safe_radius * 0.9)
			if dx * dx + dy * dy > 1.6:
				rim[row * canvas.width + col] = 0
			else:
				has_rim = true
	if not has_rim:
		return
	var span_at_rim: PackedByteArray = ProcPrimitives.compute_span_widths(canvas, rim)
	var any_nibbled: bool = false
	for row in range(canvas.height):
		for col in range(canvas.width):
			if rim[row * canvas.width + col] == 0:
				continue
			if rng.next_float() >= nibble_prob:
				continue
			if span_at_rim[row * canvas.width + col] <= 3:
				continue
			if ProcPrimitives.would_disconnect(canvas, row, col):
				continue
			canvas.data[canvas.get_index(col, row) + 3] = 0
			rim[row * canvas.width + col] = 2
			any_nibbled = true
	if not any_nibbled or interior_prob <= 0.0:
		return
	for row in range(canvas.height):
		for col in range(canvas.width):
			if rim[row * canvas.width + col] != 2:
				continue
			if rng.next_float() >= interior_prob:
				continue
			var step_x: int = 0
			var step_y: int = 0
			if cx > float(col):
				step_x = 1
			elif cx < float(col):
				step_x = -1
			if cy > float(row):
				step_y = 1
			elif cy < float(row):
				step_y = -1
			var inner_x: int = ProcPrimitives.clamp_int(col + step_x, 0, canvas.width - 1)
			var inner_y: int = ProcPrimitives.clamp_int(row + step_y, 0, canvas.height - 1)
			if canvas.get_alpha(inner_x, inner_y) <= 128:
				continue
			var left: int = inner_x
			while left > 0 and canvas.get_alpha(left - 1, inner_y) > 128:
				left -= 1
			var right: int = inner_x
			while right < canvas.width - 1 and canvas.get_alpha(right + 1, inner_y) > 128:
				right += 1
			if right - left + 1 > 3 and not ProcPrimitives.would_disconnect(canvas, inner_y, inner_x):
				canvas.data[canvas.get_index(inner_x, inner_y) + 3] = 0

static func _finish_tree(canvas: ProcCanvas, rng: ProcRng, center_x: float, center_y: float, radius: float) -> void:
	_nibble_canopy(canvas, rng, center_x, center_y, radius, 0.25, 0.1)
	ProcPrimitives.darken_rim(canvas, 30, 30, 20)

static func _branch(canvas: ProcCanvas, tips: Array, rng: ProcRng, x: float, y: float, angle: float, length: float, thickness: int, depth: int, rgba: Array, spread_base: float, shrink: float, asymmetry: float) -> void:
	if depth <= 0 or length < 1.5:
		tips.append({"x": x, "y": y})
		return
	var x2: float = x + length * sin(angle)
	var y2: float = y - length * cos(angle)
	_draw_segment(canvas, x, y, x2, y2, rgba, thickness)
	var spread: float = spread_base + rng.next_range(-0.15, 0.15)
	var left_spread: float = spread + asymmetry * rng.next_range(-0.2, 0.2)
	var right_spread: float = spread + asymmetry * rng.next_range(-0.2, 0.2)
	var child_length: float = length * (shrink + rng.next_range(-0.1, 0.1))
	var lighter: Array = ProcPrimitives.lighten_rgba(rgba, 8)
	_branch(canvas, tips, rng, x2, y2, angle - left_spread, child_length, maxi(1, thickness - 1), depth - 1, lighter, spread_base, shrink, asymmetry)
	_branch(canvas, tips, rng, x2, y2, angle + right_spread, child_length, maxi(1, thickness - 1), depth - 1, lighter, spread_base, shrink, asymmetry)

static func _build_canopy_ellipses(rng: ProcRng, lobes: Array, base_radius: float, size: int, crown_rx_scale: float, crown_ry_scale: float) -> Dictionary:
	var shadows: Array = []
	var mids: Array = []
	var highlights: Array = []
	for lobe: Dictionary in lobes:
		for _i in range(rng.next_int(1, 3)):
			var radius_shadow: float = base_radius * rng.next_range(0.62, 0.76)
			shadows.append({"cx": lobe.x + rng.next_range(-size * 0.05, size * 0.05), "cy": lobe.y + rng.next_range(-size * 0.07, size * 0.04), "rx": radius_shadow * crown_rx_scale, "ry": radius_shadow * crown_ry_scale})
		for _i in range(rng.next_int(1, 3)):
			var radius_mid: float = base_radius * rng.next_range(0.56, 0.72)
			mids.append({"cx": lobe.x + rng.next_range(-size * 0.04, size * 0.04), "cy": lobe.y + rng.next_range(-size * 0.05, size * 0.03), "rx": radius_mid * crown_rx_scale, "ry": radius_mid * crown_ry_scale})
		for _i in range(rng.next_int(1, 2)):
			var radius_high: float = base_radius * rng.next_range(0.42, 0.56)
			highlights.append({"cx": lobe.x + rng.next_range(-size * 0.03, size * 0.03), "cy": lobe.y + rng.next_range(-size * 0.08, -size * 0.02), "rx": radius_high * crown_rx_scale, "ry": radius_high * crown_ry_scale})
	return {"shadows": shadows, "mids": mids, "highlights": highlights}

static func _generate_deciduous(canvas: ProcCanvas, size: int, rng: ProcRng, terrain_tag: String) -> void:
	var trunk_base: Array = ProcPrimitives.jitter_color(rng, ProcPrimitives.pick(rng, TreeProfiles.TRUNK_PALETTES), 10, [40, 25, 10], [120, 95, 75])
	var canopy_base: Array = ProcPrimitives.jitter_color(rng, _pick_canopy_base(rng, terrain_tag, "deciduous"), 20, [15, 70, 10], [170, 195, 95])
	var shadow: Array = ProcPrimitives.as_rgba(ProcPrimitives.shift_color(canopy_base, -55, -50, -30), 230)
	var mid: Array = ProcPrimitives.as_rgba(canopy_base, 220)
	var highlight: Array = ProcPrimitives.as_rgba(ProcPrimitives.shift_color(canopy_base, 55, 45, 20), 200)
	var trunk: Array = ProcPrimitives.as_rgba(trunk_base, 255)
	var crown_rx_scale: float = 1.0
	var crown_ry_scale: float = 1.0
	var canopy_center_x_offset: float = 0.0
	var crown_roll: int = rng.next_int(0, 99)
	if crown_roll >= 35 and crown_roll <= 54:
		crown_rx_scale = 0.75
		crown_ry_scale = 1.25
	elif crown_roll >= 55 and crown_roll <= 84:
		crown_rx_scale = 1.3
		crown_ry_scale = 0.8
	elif crown_roll >= 85:
		canopy_center_x_offset = rng.next_range(-size * 0.18, size * 0.18)
	var lean: float = rng.next_range(-1.5, 1.5)
	var cx: float = float(size) * 0.5 + lean * 0.3
	var trunk_bottom: int = size - 1
	var trunk_height: int = int(round(float(size) * rng.next_range(0.35, 0.45)))
	var trunk_top: int = trunk_bottom - trunk_height
	var trunk_width_bottom: float = maxf(2.0, float(size) * 0.15 + rng.next_range(-0.3, 0.3))
	var trunk_width_top: float = maxf(1.0, trunk_width_bottom * 0.5)
	_draw_tapered_trunk(canvas, cx, trunk_bottom, trunk_top, trunk_width_bottom, trunk_width_top, trunk, rng.next_int(1, 2))
	var tips: Array = []
	var branch_x: float = cx + lean * 0.5
	var branch_y: float = float(trunk_top)
	_branch(canvas, tips, rng, branch_x, branch_y, lean * 0.08, float(size) * 0.15, 1, 2, trunk, 0.6, 0.65, 0.0)
	var canopy_cx: float = branch_x + canopy_center_x_offset
	var canopy_cy: float = branch_y - float(size) * 0.1
	if not tips.is_empty():
		var sum_y: float = 0.0
		for tip: Dictionary in tips:
			sum_y += tip.y
		canopy_cy = sum_y / float(tips.size())
	var base_radius: float = float(size) * rng.next_range(0.2, 0.28)
	canopy_cy = maxf(canopy_cy, float(trunk_top) - base_radius * 0.55)
	var lobe_centers: Array = ProcPrimitives.distribute_lobes(rng, canopy_cx, canopy_cy, rng.next_int(3, 6), base_radius, Vector2(0.45, 0.65))
	var central_fills: Array = []
	for _i in range(rng.next_int(1, 3)):
		var radius: float = base_radius * rng.next_range(0.55, 0.7)
		central_fills.append({"cx": canopy_cx + rng.next_range(-0.5, 0.5), "cy": canopy_cy + rng.next_range(-0.5, 0.3), "rx": radius * crown_rx_scale, "ry": radius * crown_ry_scale})
	var layers: Dictionary = _build_canopy_ellipses(rng, lobe_centers, base_radius, size, crown_rx_scale, crown_ry_scale)
	for tip_index: int in ProcPrimitives.sample_unique_indices(rng, tips.size(), rng.next_int(1, 3)):
		var tip: Dictionary = tips[tip_index]
		var radius_shadow: float = base_radius * rng.next_range(0.5, 0.68)
		layers["shadows"].append({"cx": tip.x + canopy_center_x_offset + rng.next_range(-0.5, 0.5), "cy": tip.y - 1.0 + rng.next_range(-0.5, 0.3), "rx": radius_shadow * crown_rx_scale, "ry": radius_shadow * crown_ry_scale})
	ProcPrimitives.batch_stamp_ellipses(canvas, central_fills, shadow[0], shadow[1], shadow[2], shadow[3], 1.4, 0.5)
	ProcPrimitives.batch_stamp_ellipses(canvas, layers["shadows"], shadow[0], shadow[1], shadow[2], shadow[3], 1.8, 0.8)
	ProcPrimitives.batch_stamp_ellipses(canvas, layers["mids"], mid[0], mid[1], mid[2], mid[3], 1.5, 0.7)
	ProcPrimitives.batch_stamp_ellipses(canvas, layers["highlights"], highlight[0], highlight[1], highlight[2], highlight[3], 1.3, 0.6)
	_finish_tree(canvas, rng, canopy_cx, canopy_cy, base_radius * 2.0)

static func _generate_conifer(canvas: ProcCanvas, size: int, rng: ProcRng, terrain_tag: String) -> void:
	var trunk_base: Array = ProcPrimitives.jitter_color(rng, ProcPrimitives.pick(rng, TreeProfiles.TRUNK_PALETTES), 10, [40, 25, 10], [120, 95, 75])
	var canopy_base: Array = ProcPrimitives.jitter_color(rng, _pick_canopy_base(rng, terrain_tag, "conifer"), 15, [10, 55, 10], [100, 150, 110])
	var trunk: Array = ProcPrimitives.as_rgba(trunk_base, 255)
	var lean: float = rng.next_range(-1.5, 1.5)
	var cx: float = float(size) * 0.5 + lean * 0.3
	var trunk_bottom: int = size - 1
	var tier_count: int = rng.next_int(3, 6)
	var max_width: float = float(size) * rng.next_range(0.35, 0.55)
	var tier_height_base: float = float(size) * 0.35
	var canopy_base_y: int = trunk_bottom - int(round(float(size) * 0.2))
	var current_bottom: int = canopy_base_y
	var top_most: int = current_bottom
	var tiers: Array = []
	for i in range(tier_count):
		var t: float = 0.0 if tier_count == 1 else float(i) / float(tier_count - 1)
		var tier_width: float = max_width * (1.0 - t * 0.65) * rng.next_range(0.9, 1.1)
		var tier_height: int = maxi(3, int(round(tier_height_base * (1.0 - t * 0.2))))
		var tier_cx: float = cx + rng.next_range(-0.7, 0.7) + lean * t * 0.4
		var shade: int = int(round(t * 35.0))
		var tier_color: Array = ProcPrimitives.as_rgba(ProcPrimitives.shift_color(canopy_base, shade, shade, shade), 240)
		var tier_top: int = current_bottom - tier_height
		tiers.append({"cx": tier_cx, "top": tier_top, "bottom": current_bottom, "half_width": tier_width * 0.5, "color": tier_color})
		top_most = mini(top_most, tier_top)
		current_bottom = tier_top + maxi(1, int(round(float(tier_height) * 0.35)))
	_draw_tapered_trunk(canvas, cx, trunk_bottom, canopy_base_y, maxf(1.5, float(size) * 0.1), 1.0, trunk, rng.next_int(1, 2))
	for tier: Dictionary in tiers:
		ProcPrimitives.fill_triangle(canvas, tier.cx, float(tier.top), tier.cx - tier.half_width, float(tier.bottom), tier.cx + tier.half_width, float(tier.bottom), tier.color[0], tier.color[1], tier.color[2], tier.color[3])
	_finish_tree(canvas, rng, cx, float(top_most + canopy_base_y) * 0.5, maxf(max_width * 0.9, float(trunk_bottom - top_most) * 0.75))

static func _generate_dead(canvas: ProcCanvas, size: int, rng: ProcRng) -> void:
	var dead_base: Array = ProcPrimitives.jitter_color(rng, ProcPrimitives.pick(rng, TreeProfiles.DEAD_BASES), 8, [55, 45, 35], [105, 95, 80])
	var trunk: Array = ProcPrimitives.as_rgba(dead_base, 255)
	var lean: float = rng.next_range(-1.5, 1.5)
	var cx: float = float(size) * 0.5 + lean * 0.3
	var trunk_bottom: int = size - 1
	var trunk_height: int = int(round(float(size) * rng.next_range(0.45, 0.55)))
	var trunk_top: int = trunk_bottom - trunk_height
	_draw_tapered_trunk(canvas, cx, trunk_bottom, trunk_top, maxf(3.0, float(size) * 0.18), maxf(1.5, float(size) * 0.08), trunk, rng.next_int(1, 2))
	var tips: Array = []
	_branch(canvas, tips, rng, cx + lean * 0.5, float(trunk_top), lean * 0.06, float(size) * 0.28, 3, 4, trunk, 0.7, 0.65, 0.4)
	for index: int in ProcPrimitives.sample_unique_indices(rng, tips.size(), rng.next_int(0, 3)):
		var point: Dictionary = tips[index]
		var radius: float = rng.next_range(0.8, 1.4)
		ProcPrimitives.stamp_ellipse(canvas, point.x, point.y, radius, radius, TreeProfiles.MOSS_RGBA[0], TreeProfiles.MOSS_RGBA[1], TreeProfiles.MOSS_RGBA[2], TreeProfiles.MOSS_RGBA[3], 1.4, 0.5)
	_finish_tree(canvas, rng, cx, float(trunk_top) + float(size) * 0.18, float(size) * 0.55)

static func _generate_sapling(canvas: ProcCanvas, size: int, rng: ProcRng, terrain_tag: String) -> void:
	var trunk_base: Array = ProcPrimitives.jitter_color(rng, ProcPrimitives.pick(rng, TreeProfiles.TRUNK_PALETTES), 8, [45, 30, 15], [115, 90, 70])
	var canopy_base: Array = ProcPrimitives.jitter_color(rng, _pick_canopy_base(rng, terrain_tag, "deciduous"), 12, [35, 90, 20], [150, 180, 90])
	var shadow: Array = ProcPrimitives.as_rgba(ProcPrimitives.shift_color(canopy_base, -40, -35, -20), 210)
	var mid: Array = ProcPrimitives.as_rgba(canopy_base, 200)
	var highlight: Array = ProcPrimitives.as_rgba(ProcPrimitives.shift_color(canopy_base, 40, 30, 15), 190)
	var trunk: Array = ProcPrimitives.as_rgba(trunk_base, 255)
	var lean: float = rng.next_range(-1.5, 1.5)
	var cx: float = float(size) * 0.5 + lean * 0.3
	var trunk_bottom: int = size - 1
	var trunk_top: int = int(round(float(size) * 0.42))
	_draw_tapered_trunk(canvas, cx, trunk_bottom, trunk_top, 1.5, 1.0, trunk, rng.next_int(1, 2))
	var canopy_cx: float = cx + lean * 0.3
	var canopy_cy: float = float(trunk_top) - float(size) * 0.08
	var base_radius: float = float(size) * rng.next_range(0.16, 0.22)
	var lobe_centers: Array = ProcPrimitives.distribute_lobes(rng, canopy_cx, canopy_cy, rng.next_int(2, 4), base_radius, Vector2(0.4, 0.6))
	var central_fills: Array = [{"cx": canopy_cx, "cy": canopy_cy, "rx": base_radius * rng.next_range(0.45, 0.55), "ry": base_radius * rng.next_range(0.45, 0.55)}]
	var layers: Dictionary = _build_canopy_ellipses(rng, lobe_centers, base_radius, size, 1.0, 1.0)
	ProcPrimitives.batch_stamp_ellipses(canvas, central_fills, shadow[0], shadow[1], shadow[2], shadow[3], 1.4, 0.5)
	ProcPrimitives.batch_stamp_ellipses(canvas, layers["shadows"], shadow[0], shadow[1], shadow[2], shadow[3], 1.5, 0.5)
	ProcPrimitives.batch_stamp_ellipses(canvas, layers["mids"], mid[0], mid[1], mid[2], mid[3], 1.3, 0.5)
	ProcPrimitives.batch_stamp_ellipses(canvas, layers["highlights"], highlight[0], highlight[1], highlight[2], highlight[3], 1.2, 0.4)
	_finish_tree(canvas, rng, canopy_cx, canopy_cy, base_radius * 1.9)

static func generate_tree(seed: int, size: int = 20, archetype: String = "", terrain_tag: String = "default", size_tier: String = "medium") -> Dictionary:
	var resolved_archetype: String = _resolve_archetype(seed, archetype, terrain_tag)
	var rng := ProcRng.new(seed)
	var canvas_size: int = _resolve_canvas_size(rng, resolved_archetype, size, size_tier)
	var canvas := ProcCanvas.new(canvas_size, canvas_size)
	match resolved_archetype:
		"conifer":
			_generate_conifer(canvas, canvas_size, rng, terrain_tag)
		"dead":
			_generate_dead(canvas, canvas_size, rng)
		"sapling":
			_generate_sapling(canvas, canvas_size, rng, terrain_tag)
		_:
			_generate_deciduous(canvas, canvas_size, rng, terrain_tag)
	return {"canvas": canvas, "archetype": resolved_archetype}
