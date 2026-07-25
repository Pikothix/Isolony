shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform sampler2D elevation_texture : filter_nearest, repeat_disable;
uniform sampler2D loaded_cell_texture : filter_nearest, repeat_disable;
uniform vec2 elevation_texture_size = vec2(256.0);
uniform vec2 loaded_cell_min;
uniform vec2 loaded_cell_max;
uniform vec2 map_origin;
uniform vec2 map_step_x = vec2(16.0, 8.0);
uniform vec2 map_step_y = vec2(-16.0, 8.0);
uniform vec4 rim_color : source_color = vec4(0.12, 0.09, 0.05, 0.65);
uniform float rim_width : hint_range(0.1, 4.0) = 1.0;
uniform float vertical_offset : hint_range(-4.0, 4.0) = -0.5;
uniform float rim_softness : hint_range(0.0, 3.0) = 0.75;
uniform vec4 direction_mask = vec4(1.0);
uniform bool debug_elevation = false;

varying vec2 local_world_position;

void vertex() {
	local_world_position = VERTEX;
}

float elevation_at(vec2 cell) {
	vec2 slot = mod(mod(cell, elevation_texture_size) + elevation_texture_size, elevation_texture_size);
	return floor(texture(elevation_texture, (slot + vec2(0.5)) / elevation_texture_size).r * 2.0 + 0.5);
}

bool cell_is_loaded(vec2 cell) {
	if (!all(greaterThanEqual(cell, loaded_cell_min)) || !all(lessThanEqual(cell, loaded_cell_max))) {
		return false;
	}
	vec2 slot = mod(mod(cell, elevation_texture_size) + elevation_texture_size, elevation_texture_size);
	return texture(loaded_cell_texture, (slot + vec2(0.5)) / elevation_texture_size).r > 0.5;
}

void fragment() {
	vec2 world_position = local_world_position;
	float determinant = map_step_x.x * map_step_y.y - map_step_y.x * map_step_x.y;
	float rim_strength = 0.0;
	float visible_elevation = 0.0;
	bool visible_surface_selected = false;
	bool rim_edge_selected = false;

	for (int elevation_level = 0; elevation_level <= 2; elevation_level++) {
		float elevation = float(elevation_level);
		vec2 top_offset = vec2(0.0, -16.0 * elevation - 8.0 + vertical_offset);
		vec2 relative = world_position - map_origin - top_offset;
		vec2 continuous_cell = vec2(
			(relative.x * map_step_y.y - relative.y * map_step_y.x) / determinant,
			(map_step_x.x * relative.y - map_step_x.y * relative.x) / determinant
		);
		// Match TileMapLayer.local_to_map() on an exact isometric diamond edge:
		// X ties select the lower coordinate while Y ties select the higher one.
		vec2 cell = vec2(
			ceil(continuous_cell.x - 0.5),
			floor(continuous_cell.y + 0.5)
		);
		vec2 local_basis = continuous_cell - cell;
		if (!cell_is_loaded(cell) || any(greaterThan(abs(local_basis), vec2(0.5)))) {
			continue;
		}
		float current_elevation = elevation_at(cell);
		if (abs(current_elevation - elevation) > 0.1) {
			continue;
		}
		// Projected top diamonds from different elevations can overlap. The
		// first matching surface is the visible one; rear elevated rims must
		// not bleed through a foreground terrain top that owns the same pixel.
		if (visible_surface_selected) {
			continue;
		}
		visible_surface_selected = true;
		visible_elevation = current_elevation;
		if (elevation_level == 0) {
			continue;
		}
		float edge_scale = 14.310835;
		float north_distance = abs(local_basis.y + 0.5) * edge_scale;
		float east_distance = abs(local_basis.x - 0.5) * edge_scale;
		float south_distance = abs(local_basis.y - 0.5) * edge_scale;
		float west_distance = abs(local_basis.x + 0.5) * edge_scale;
		float north_elevation = elevation_at(cell + vec2(0.0, -1.0));
		float east_elevation = elevation_at(cell + vec2(1.0, 0.0));
		float south_elevation = elevation_at(cell + vec2(0.0, 1.0));
		float west_elevation = elevation_at(cell + vec2(-1.0, 0.0));
		float north_band = 1.0 - smoothstep(rim_width, rim_width + rim_softness, north_distance);
		float east_band = 1.0 - smoothstep(rim_width, rim_width + rim_softness, east_distance);
		float south_band = 1.0 - smoothstep(rim_width, rim_width + rim_softness, south_distance);
		float west_band = 1.0 - smoothstep(rim_width, rim_width + rim_softness, west_distance);
		bool north_edge = direction_mask.x > 0.0 && current_elevation > north_elevation + 0.1;
		bool east_edge = direction_mask.y > 0.0 && current_elevation > east_elevation + 0.1;
		bool south_edge = direction_mask.z > 0.0 && current_elevation > south_elevation + 0.1;
		bool west_edge = direction_mask.w > 0.0 && current_elevation > west_elevation + 0.1;
		float edge_coverage = 0.0;
		if (north_edge && north_band > 0.0) {
			edge_coverage = max(edge_coverage, north_band);
			rim_edge_selected = true;
		}
		if (east_edge && east_band > 0.0) {
			edge_coverage = max(edge_coverage, east_band);
			rim_edge_selected = true;
		}
		if (south_edge && south_band > 0.0) {
			edge_coverage = max(edge_coverage, south_band);
			rim_edge_selected = true;
		}
		if (west_edge && west_band > 0.0) {
			edge_coverage = max(edge_coverage, west_band);
			rim_edge_selected = true;
		}
		rim_strength = edge_coverage;
	}

	if (debug_elevation) {
		if (!visible_surface_selected) {
			discard;
		}
		float debug_alpha = 0.75;
		vec3 debug_color = vec3(0.0, 0.0, 0.0);
		if (visible_elevation < 0.5) {
			debug_color = vec3(0.0, 1.0, 0.0);
		} else if (visible_elevation < 1.5) {
			debug_color = vec3(0.0, 0.25, 1.0);
		} else {
			debug_color = vec3(1.0, 0.0, 0.0);
		}
		COLOR = vec4(debug_color * debug_alpha, debug_alpha);
	} else {
		if (!visible_surface_selected || visible_elevation < 0.5 || !rim_edge_selected || rim_strength <= 0.0) {
			discard;
		}
		float rim_alpha = rim_color.a * rim_strength;
		COLOR = vec4(rim_color.rgb * rim_alpha, rim_alpha);
	}
}
