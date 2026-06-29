extends RefCounted
class_name ProcPrimitives

const ProcCanvas = preload("res://scripts/procgen/proc_canvas.gd")
const ProcRng = preload("res://scripts/procgen/proc_rng.gd")

static func clamp_int(value: int, minimum: int, maximum: int) -> int:
	return mini(maxi(value, minimum), maximum)

static func clamp_float(value: float, minimum: float, maximum: float) -> float:
	return minf(maxf(value, minimum), maximum)

static func clamp_channel(value: int) -> int:
	return clamp_int(value, 0, 255)

static func pick(rng: ProcRng, items: Array) -> Variant:
	return items[rng.next_int(0, items.size() - 1)]

static func as_rgba(color: Array, alpha: int) -> Array:
	return [color[0], color[1], color[2], alpha]

static func lighten_rgba(rgba: Array, amount: int) -> Array:
	return [clamp_channel(rgba[0] + amount), clamp_channel(rgba[1] + amount), clamp_channel(rgba[2] + amount), rgba[3]]

static func shift_color(base: Array, dr: int, dg: int, db: int) -> Array:
	return [clamp_channel(base[0] + dr), clamp_channel(base[1] + dg), clamp_channel(base[2] + db)]

static func jitter_color(rng: ProcRng, base: Array, delta: int, min_color: Array, max_color: Array) -> Array:
	return [
		clamp_int(base[0] + rng.next_int(-delta, delta), min_color[0], max_color[0]),
		clamp_int(base[1] + rng.next_int(-delta, delta), min_color[1], max_color[1]),
		clamp_int(base[2] + rng.next_int(-delta, delta), min_color[2], max_color[2]),
	]

static func sample_unique_indices(rng: ProcRng, length: int, count: int) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	if length <= 0 or count <= 0:
		return result
	var capped: int = mini(length, count)
	var indices: Array = []
	for i in range(length):
		indices.append(i)
	for i in range(capped):
		var j: int = rng.next_int(i, length - 1)
		var temp: Variant = indices[i]
		indices[i] = indices[j]
		indices[j] = temp
		result.append(indices[i])
	return result

static func distribute_lobes(rng: ProcRng, cx: float, cy: float, count: int, radius: float, dist_range: Vector2, angle_jitter: float = 0.75, vertical_bias: Vector2 = Vector2(0.9, 0.7)) -> Array:
	var angle_step: float = TAU / float(count)
	var angle_offset: float = rng.next_range(-PI, PI)
	var points: Array = []
	for i in range(count):
		var angle: float = angle_offset + angle_step * float(i) + rng.next_range(-angle_jitter, angle_jitter)
		var dist: float = radius * rng.next_range(dist_range.x, dist_range.y)
		var sin_angle: float = sin(angle)
		var v_scale: float = vertical_bias.x if sin_angle > 0.0 else vertical_bias.y
		points.append({"x": cx + cos(angle) * dist, "y": cy + sin_angle * dist * v_scale})
	return points

static func _composite_over(data: PackedByteArray, index: int, sr: int, sg: int, sb: int, sa: float) -> void:
	if data[index + 3] == 0:
		data[index] = clamp_channel(int(round(sr)))
		data[index + 1] = clamp_channel(int(round(sg)))
		data[index + 2] = clamp_channel(int(round(sb)))
		data[index + 3] = clamp_channel(int(round(sa * 255.0)))
		return
	var da: float = float(data[index + 3]) / 255.0
	var out_a: float = sa + da * (1.0 - sa)
	if out_a <= 0.0:
		return
	var inv_src: float = 1.0 - sa
	var inv_out: float = 1.0 / out_a
	data[index] = clamp_channel(int(round((float(sr) * sa + float(data[index]) * da * inv_src) * inv_out)))
	data[index + 1] = clamp_channel(int(round((float(sg) * sa + float(data[index + 1]) * da * inv_src) * inv_out)))
	data[index + 2] = clamp_channel(int(round((float(sb) * sa + float(data[index + 2]) * da * inv_src) * inv_out)))
	data[index + 3] = clamp_channel(int(round(out_a * 255.0)))

static func _ellipse_profile(alpha: int, falloff: float, hardness: float) -> Dictionary:
	var hc: float = clamp_float(hardness, 0.0, 1.0)
	var inner_fraction: float = 0.3 + 0.55 * hc
	return {
		"inner_fraction": inner_fraction,
		"outer_fraction": maxf(0.000001, 1.0 - inner_fraction),
		"effective_falloff": falloff + 2.5 * hc,
		"opacity": float(alpha) / 255.0,
	}

static func _ellipse_alpha(dist: float, inner_fraction: float, outer_fraction: float, effective_falloff: float, edge_limit: float, opacity: float) -> float:
	if dist <= inner_fraction:
		return opacity
	if dist > edge_limit:
		return 0.0
	var fraction: float = maxf((dist - inner_fraction) / outer_fraction, 0.0)
	var alpha: float = clamp_float(1.0 - pow(fraction, effective_falloff), 0.0, 1.0)
	return alpha * opacity

static func _ellipse_bounds(cx: float, cy: float, rx: float, ry: float, width: int, height: int) -> Rect2i:
	var rx_ceil: int = int(ceil(rx)) + 1
	var ry_ceil: int = int(ceil(ry)) + 1
	var x_min: int = clamp_int(int(floor(cx)) - rx_ceil, 0, width - 1)
	var x_max: int = clamp_int(int(floor(cx)) + rx_ceil, 0, width - 1)
	var y_min: int = clamp_int(int(floor(cy)) - ry_ceil, 0, height - 1)
	var y_max: int = clamp_int(int(floor(cy)) + ry_ceil, 0, height - 1)
	return Rect2i(x_min, y_min, x_max - x_min + 1, y_max - y_min + 1)

static func stamp_ellipse(canvas: ProcCanvas, cx: float, cy: float, rx: float, ry: float, r: int, g: int, b: int, alpha: int, falloff: float, hardness: float) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	var profile: Dictionary = _ellipse_profile(alpha, falloff, hardness)
	var edge_limit: float = 1.0 + 0.5 / maxf(rx, ry)
	var bounds: Rect2i = _ellipse_bounds(cx, cy, rx, ry, canvas.width, canvas.height)
	for row in range(bounds.position.y, bounds.position.y + bounds.size.y):
		for col in range(bounds.position.x, bounds.position.x + bounds.size.x):
			var ddx: float = (float(col) - cx) / rx
			var ddy: float = (float(row) - cy) / ry
			var dist: float = sqrt(ddx * ddx + ddy * ddy)
			var source_alpha: float = _ellipse_alpha(dist, profile.inner_fraction, profile.outer_fraction, profile.effective_falloff, edge_limit, profile.opacity)
			if source_alpha <= 0.0:
				continue
			_composite_over(canvas.data, canvas.get_index(col, row), r, g, b, source_alpha)

static func batch_stamp_ellipses(canvas: ProcCanvas, ellipses: Array, r: int, g: int, b: int, alpha: int, falloff: float, hardness: float) -> void:
	if ellipses.is_empty():
		return
	var profile: Dictionary = _ellipse_profile(alpha, falloff, hardness)
	var valid: Array = []
	var union_x0: int = canvas.width
	var union_y0: int = canvas.height
	var union_x1: int = -1
	var union_y1: int = -1
	for ellipse: Dictionary in ellipses:
		if ellipse.rx <= 0.0 or ellipse.ry <= 0.0:
			continue
		var bounds: Rect2i = _ellipse_bounds(ellipse.cx, ellipse.cy, ellipse.rx, ellipse.ry, canvas.width, canvas.height)
		valid.append({"ellipse": ellipse, "bounds": bounds, "edge_limit": 1.0 + 0.5 / maxf(ellipse.rx, ellipse.ry)})
		union_x0 = mini(union_x0, bounds.position.x)
		union_y0 = mini(union_y0, bounds.position.y)
		union_x1 = maxi(union_x1, bounds.position.x + bounds.size.x - 1)
		union_y1 = maxi(union_y1, bounds.position.y + bounds.size.y - 1)
	if valid.is_empty():
		return
	var cols: int = union_x1 - union_x0 + 1
	var rows: int = union_y1 - union_y0 + 1
	var remaining: PackedFloat32Array = PackedFloat32Array()
	remaining.resize(cols * rows)
	for i in range(remaining.size()):
		remaining[i] = 1.0
	for entry: Dictionary in valid:
		var ellipse: Dictionary = entry.ellipse
		var bounds: Rect2i = entry.bounds
		for row in range(bounds.position.y, bounds.position.y + bounds.size.y):
			for col in range(bounds.position.x, bounds.position.x + bounds.size.x):
				var ddx: float = (float(col) - ellipse.cx) / ellipse.rx
				var ddy: float = (float(row) - ellipse.cy) / ellipse.ry
				var dist: float = sqrt(ddx * ddx + ddy * ddy)
				var alpha_part: float = _ellipse_alpha(dist, profile.inner_fraction, profile.outer_fraction, profile.effective_falloff, entry.edge_limit, 1.0)
				if alpha_part <= 0.0:
					continue
				var idx: int = (row - union_y0) * cols + (col - union_x0)
				remaining[idx] *= 1.0 - alpha_part * profile.opacity
	for row in range(union_y0, union_y1 + 1):
		for col in range(union_x0, union_x1 + 1):
			var final_alpha: float = 1.0 - remaining[(row - union_y0) * cols + (col - union_x0)]
			if final_alpha <= 0.0:
				continue
			_composite_over(canvas.data, canvas.get_index(col, row), r, g, b, final_alpha)

static func stamp_three_tone(canvas: ProcCanvas, palette: Array, shadow_ellipses: Array, body_ellipses: Array, highlight_ellipses: Array, falloff: Array = [2.2, 2.0, 1.9], hardness: Array = [0.88, 0.86, 0.8], alpha: Array = [220, 250, 210]) -> void:
	var layers: Array = [shadow_ellipses, body_ellipses, highlight_ellipses]
	for i in range(3):
		var color: Array = palette[i]
		batch_stamp_ellipses(canvas, layers[i], color[0], color[1], color[2], alpha[i], falloff[i], hardness[i])

static func compute_rim_mask(canvas: ProcCanvas) -> PackedByteArray:
	var rim: PackedByteArray = PackedByteArray()
	rim.resize(canvas.width * canvas.height)
	for row in range(canvas.height):
		for col in range(canvas.width):
			var index: int = canvas.get_index(col, row)
			if canvas.data[index + 3] <= 128:
				continue
			var has_transparent: bool = row == 0 or canvas.get_alpha(col, row - 1) == 0 or row == canvas.height - 1 or canvas.get_alpha(col, row + 1) == 0 or col == 0 or canvas.get_alpha(col - 1, row) == 0 or col == canvas.width - 1 or canvas.get_alpha(col + 1, row) == 0
			if has_transparent:
				rim[row * canvas.width + col] = 1
	return rim

static func darken_rim(canvas: ProcCanvas, dr: int, dg: int, db: int) -> void:
	var rim: PackedByteArray = compute_rim_mask(canvas)
	for row in range(canvas.height):
		for col in range(canvas.width):
			if rim[row * canvas.width + col] == 0:
				continue
			var i: int = canvas.get_index(col, row)
			canvas.data[i] = clamp_channel(canvas.data[i] - dr)
			canvas.data[i + 1] = clamp_channel(canvas.data[i + 1] - dg)
			canvas.data[i + 2] = clamp_channel(canvas.data[i + 2] - db)

static func compute_span_widths(canvas: ProcCanvas, mask: PackedByteArray) -> PackedByteArray:
	var spans: PackedByteArray = PackedByteArray()
	spans.resize(canvas.width * canvas.height)
	for row in range(canvas.height):
		for col in range(canvas.width):
			if mask[row * canvas.width + col] == 0:
				continue
			var left: int = col
			while left > 0 and canvas.get_alpha(left - 1, row) > 128:
				left -= 1
			var right: int = col
			while right < canvas.width - 1 and canvas.get_alpha(right + 1, row) > 128:
				right += 1
			spans[row * canvas.width + col] = mini(255, right - left + 1)
	return spans

static func shift_to_bottom(canvas: ProcCanvas) -> void:
	var last_opaque_row: int = -1
	for row in range(canvas.height - 1, -1, -1):
		for col in range(canvas.width):
			if canvas.get_alpha(col, row) > 128:
				last_opaque_row = row
				break
		if last_opaque_row >= 0:
			break
	if last_opaque_row < 0:
		return
	var gap: int = canvas.height - 1 - last_opaque_row
	if gap <= 0:
		return
	var clone: PackedByteArray = canvas.data.duplicate()
	for row in range(canvas.height):
		for col in range(canvas.width):
			var dst_i: int = canvas.get_index(col, row)
			if row < gap:
				canvas.data[dst_i] = 0
				canvas.data[dst_i + 1] = 0
				canvas.data[dst_i + 2] = 0
				canvas.data[dst_i + 3] = 0
				continue
			var src_i: int = ((row - gap) * canvas.width + col) * 4
			canvas.data[dst_i] = clone[src_i]
			canvas.data[dst_i + 1] = clone[src_i + 1]
			canvas.data[dst_i + 2] = clone[src_i + 2]
			canvas.data[dst_i + 3] = clone[src_i + 3]

static func would_disconnect(canvas: ProcCanvas, row: int, col: int) -> bool:
	var opaque: Array = [
		row > 0 and canvas.get_alpha(col, row - 1) > 128,
		row > 0 and col < canvas.width - 1 and canvas.get_alpha(col + 1, row - 1) > 128,
		col < canvas.width - 1 and canvas.get_alpha(col + 1, row) > 128,
		row < canvas.height - 1 and col < canvas.width - 1 and canvas.get_alpha(col + 1, row + 1) > 128,
		row < canvas.height - 1 and canvas.get_alpha(col, row + 1) > 128,
		row < canvas.height - 1 and col > 0 and canvas.get_alpha(col - 1, row + 1) > 128,
		col > 0 and canvas.get_alpha(col - 1, row) > 128,
		row > 0 and col > 0 and canvas.get_alpha(col - 1, row - 1) > 128,
	]
	var components: int = 0
	for i in range(8):
		if opaque[i] and not opaque[(i + 7) % 8]:
			components += 1
			if components > 1:
				return true
	return false

static func nibble_rim(canvas: ProcCanvas, rng: ProcRng, nibble_prob: float, mask: PackedByteArray, guard: Callable = Callable(), on_erase: Callable = Callable()) -> void:
	var probability: float = clamp_float(nibble_prob, 0.0, 1.0)
	for row in range(canvas.height):
		for col in range(canvas.width):
			if mask[row * canvas.width + col] == 0:
				continue
			if rng.next_float() >= probability:
				continue
			if guard.is_valid() and not guard.call(row, col):
				continue
			canvas.data[canvas.get_index(col, row) + 3] = 0
			if on_erase.is_valid():
				on_erase.call(row, col)

static func draw_line(canvas: ProcCanvas, x0: int, y0: int, x1: int, y1: int, r: int, g: int, b: int, a: int, thickness: int) -> void:
	var half: int = int(floor(float(thickness) / 2.0))
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	var cx: int = x0
	var cy: int = y0
	while true:
		for py in range(maxi(0, cy - half), mini(canvas.height - 1, cy - half + thickness - 1) + 1):
			for px in range(maxi(0, cx - half), mini(canvas.width - 1, cx - half + thickness - 1) + 1):
				canvas.set_pixel(px, py, r, g, b, a)
		if cx == x1 and cy == y1:
			break
		var e2: int = err * 2
		if e2 >= dy:
			err += dy
			cx += sx
		if e2 <= dx:
			err += dx
			cy += sy

static func fill_triangle(canvas: ProcCanvas, x0: float, y0: float, x1: float, y1: float, x2: float, y2: float, r: int, g: int, b: int, a: int) -> void:
	var vertices: Array = [{"x": x0, "y": y0}, {"x": x1, "y": y1}, {"x": x2, "y": y2}]
	vertices.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return left.y < right.y)
	var v0: Dictionary = vertices[0]
	var v1: Dictionary = vertices[1]
	var v2: Dictionary = vertices[2]
	var scanline := func(y_start: int, y_end: int, xa: float, ya: float, xb: float, yb: float, xc: float, yc: float, xd: float, yd: float) -> void:
		for y in range(y_start, y_end + 1):
			if y < 0 or y >= canvas.height:
				continue
			var dy_ab: float = yb - ya
			var dy_cd: float = yd - yc
			var t_ab: float = 0.0 if is_zero_approx(dy_ab) else (float(y) - ya) / dy_ab
			var t_cd: float = 0.0 if is_zero_approx(dy_cd) else (float(y) - yc) / dy_cd
			var left_x: float = xa + t_ab * (xb - xa)
			var right_x: float = xc + t_cd * (xd - xc)
			if left_x > right_x:
				var temp: float = left_x
				left_x = right_x
				right_x = temp
			for x in range(maxi(0, int(ceil(left_x))), mini(canvas.width - 1, int(floor(right_x))) + 1):
				canvas.set_pixel(x, y, r, g, b, a)
	if v1.y > v0.y:
		scanline.call(int(ceil(v0.y)), int(floor(v1.y)), v0.x, v0.y, v1.x, v1.y, v0.x, v0.y, v2.x, v2.y)
	if v2.y > v1.y:
		scanline.call(int(ceil(v1.y)), int(floor(v2.y)), v1.x, v1.y, v2.x, v2.y, v0.x, v0.y, v2.x, v2.y)
