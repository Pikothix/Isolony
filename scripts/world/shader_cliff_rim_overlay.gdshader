shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform sampler2D elevation_texture : filter_nearest, repeat_disable;
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
	return all(greaterThanEqual(cell, loaded_cell_min)) && all(lessThanEqual(cell, loaded_cell_max));
}

void fragment() {
	vec2 world_position = local_world_position;
	float determinant = map_step_x.x * map_step_y.y - map_step_y.x * map_step_x.y;
	float coverage = 0.0;
	float visible_elevation = 0.0;

	for (int elevation_level = 1; elevation_level <= 2; elevation_level++) {
		float elevation = float(elevation_level);
		vec2 top_offset = vec2(0.0, -16.0 * elevation - 8.0 + vertical_offset);
		vec2 relative = world_position - map_origin - top_offset;
		vec2 continuous_cell = vec2(
			(relative.x * map_step_y.y - relative.y * map_step_y.x) / determinant,
			(map_step_x.x * relative.y - map_step_x.y * relative.x) / determinant
		);
		vec2 cell = floor(continuous_cell + vec2(0.5));
		vec2 local_basis = continuous_cell - cell;
		if (!cell_is_loaded(cell) || any(greaterThan(abs(local_basis), vec2(0.5)))) {
			continue;
		}
		float current_elevation = elevation_at(cell);
		if (abs(current_elevation - elevation) > 0.1) {
			continue;
		}
		visible_elevation = max(visible_elevation, current_elevation);
		float edge_scale = 14.310835;
		float north_distance = abs(local_basis.y + 0.5) * edge_scale;
		float east_distance = abs(local_basis.x - 0.5) * edge_scale;
		float south_distance = abs(local_basis.y - 0.5) * edge_scale;
		float west_distance = abs(local_basis.x + 0.5) * edge_scale;
		float edge_coverage = 0.0;
		float north_exposed = step(elevation_at(cell + vec2(0.0, -1.0)) + 0.1, current_elevation);
		float east_exposed = step(elevation_at(cell + vec2(1.0, 0.0)) + 0.1, current_elevation);
		float south_exposed = step(elevation_at(cell + vec2(0.0, 1.0)) + 0.1, current_elevation);
		float west_exposed = step(elevation_at(cell + vec2(-1.0, 0.0)) + 0.1, current_elevation);
		edge_coverage = max(edge_coverage, direction_mask.x * north_exposed * (1.0 - smoothstep(rim_width, rim_width + rim_softness, north_distance)));
		edge_coverage = max(edge_coverage, direction_mask.y * east_exposed * (1.0 - smoothstep(rim_width, rim_width + rim_softness, east_distance)));
		edge_coverage = max(edge_coverage, direction_mask.z * south_exposed * (1.0 - smoothstep(rim_width, rim_width + rim_softness, south_distance)));
		edge_coverage = max(edge_coverage, direction_mask.w * west_exposed * (1.0 - smoothstep(rim_width, rim_width + rim_softness, west_distance)));
		coverage = max(coverage, edge_coverage);
	}

	if (debug_elevation) {
		if (visible_elevation <= 0.0) {
			discard;
		}
		float debug_alpha = 0.75;
		vec3 debug_color = vec3(visible_elevation * 0.5);
		COLOR = vec4(debug_color * debug_alpha, debug_alpha);
	} else {
		if (coverage <= 0.0) {
			discard;
		}
		float rim_alpha = rim_color.a * coverage;
		COLOR = vec4(rim_color.rgb * rim_alpha, rim_alpha);
	}
}
