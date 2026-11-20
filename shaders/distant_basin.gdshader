shader_type spatial;
render_mode depth_draw_always, cull_disabled, specular_disabled;

uniform sampler2D terrain_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform bool regional_color = false;
varying vec3 basin_point;

void vertex() {
	basin_point = VERTEX;
}

void fragment() {
	// Only fill gaps behind streamed geometry. The near terrain owns every visible surface.
	if (textureLod(terrain_depth, SCREEN_UV, 0.0).r > 0.000001) {
		discard;
	}
	float rock = smoothstep(0.2, 0.84, UV.y);
	vec3 slope = mix(vec3(0.19, 0.31, 0.28), vec3(0.37, 0.43, 0.40), rock);
	if (regional_color) { slope = COLOR.rgb; }
	float gullies = sin(basin_point.x * 0.29 + basin_point.z * 0.19 + 1.9 * sin(basin_point.z * 0.09));
	float strata = smoothstep(0.1, 0.75, sin(basin_point.y * 0.96 + gullies));
	slope *= 0.85 + 0.13 * smoothstep(-0.40, 0.65, gullies) + 0.10 * rock * strata;
	ALBEDO = mix(slope, vec3(0.13, 0.35, 0.35), smoothstep(0.28, 0.89, UV.x));
	ROUGHNESS = 1.0;
	ALPHA = 1.0;
}
