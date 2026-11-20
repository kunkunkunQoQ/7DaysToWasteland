shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
uniform sampler2D scene_normal : hint_normal_roughness_texture, filter_nearest, repeat_disable;
#endif
uniform vec3 ink : source_color = vec3(0.08, 0.050, 0.11);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float depth_at(vec2 uv, mat4 inverse_projection) {
	float d = textureLod(scene_depth, uv, 0.0).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	d = d * 2.0 - 1.0;
	#endif
	vec4 view = inverse_projection * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -view.z / view.w;
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	float d = depth_at(uv, INV_PROJECTION_MATRIX);
	vec2 taps[4] = { vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0) };
	float edge = 0.0;
	#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
	vec3 base = textureLod(scene_normal, uv, 0.0).xyz * 2.0 - 1.0;
	#endif
	for (int i = 0; i < 4; i++) {
		vec2 near_uv = uv + taps[i] * px;
		float other = depth_at(near_uv, INV_PROJECTION_MATRIX);
		float relative = (other - d) / (d + 0.08);
		edge = max(edge, smoothstep(0.043, 0.081, relative) * 0.75);
		#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
		vec3 normal_other = textureLod(scene_normal, near_uv, 0.0).xyz * 2.0 - 1.0;
		float ridge = smoothstep(0.49, 0.83, 1.0 - dot(base, normal_other));
		if (relative >= -0.0007 && abs(relative) < 0.026 && d < 65.0) {
			edge = max(edge, ridge * 0.31);
		}
		#endif
	}
	ALBEDO = ink;
	ALPHA = edge * 0.61 * (1.0 - smoothstep(54.0, 123.0, d));
}
