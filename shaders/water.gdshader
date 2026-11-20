shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D screen_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 sun_dir = vec3(-0.35, 0.14, -0.926);
uniform float daylight = 0.62;
uniform float twilight = 0.92;
uniform float blood = 0.0;
uniform float rain = 0.0;
uniform float seconds = 0.0;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float depth = textureLod(screen_depth, SCREEN_UV, 0.0).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0);
	#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	#endif
	vec4 scene_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float thickness = max(0.0, -scene_pos.z / scene_pos.w + VERTEX.z);
	vec3 ray = normalize(CAMERA_POSITION_WORLD - world_pos);
	float water_depth = thickness * abs(ray.y) / max(abs(VIEW.z), 0.12);
	vec2 p = world_pos.xz;
	float broad = sin(dot(p, vec2(0.20, 0.36)) - seconds * 0.55);
	float drift = sin(dot(p, vec2(-0.27, 0.17)) + seconds * 0.34);
	float crest_phase = dot(p, vec2(0.62, 2.4)) + broad * 1.8 + drift - seconds * 1.26;
	float fine_fade = 1.0 - smoothstep(0.22, 1.4, fwidth(crest_phase));
	float ripple = sin(crest_phase) * fine_fade;
	float sunlit = max(daylight, twilight * 0.89);
	vec3 sand = vec3(0.49, 0.63, 0.42);
	vec3 shoal = vec3(0.13, 0.54, 0.47);
	vec3 basin = vec3(0.038, 0.25, 0.28);
	vec3 col = mix(sand, shoal, smoothstep(0.0, 0.78, water_depth));
	col = mix(col, basin, smoothstep(0.54, 4.8, water_depth));
	col *= (1.0 + broad * drift * 0.10) * mix(0.32, 0.99, sunlit);
	vec3 normal = normalize(vec3(0.043 * broad + 0.023 * ripple, 1.0, 0.046 * drift + 0.052 * ripple));
	vec3 reflected = reflect(-ray, normal);
	float fresnel = pow(1.0 - clamp(abs(ray.y), 0.0, 1.0), 3.3);
	float glancing = clamp(dot(reflected, sun_dir), 0.0, 1.0);
	vec3 haze = mix(vec3(0.24, 0.45, 0.49), vec3(0.80, 0.52, 0.32), pow(glancing, 7.0) * twilight);
	col = mix(col, haze * mix(0.35, 0.97, sunlit), fresnel * 0.56);
	float horizon_sun = max(0.0, dot(normalize(-ray.xz + vec2(0.0001)), normalize(sun_dir.xz + vec2(0.0001))));
	float trail = pow(horizon_sun, 30.0) * pow(glancing, 13.0);
	float wave_patch = sin(dot(p, vec2(0.41, -0.22)) + drift * 2.0 + seconds * 0.17);
	float streak = smoothstep(0.49, 0.92, ripple + broad * 0.16) * smoothstep(-0.70, 0.52, wave_patch);
	col += vec3(0.036, 0.078, 0.061) * streak * (0.4 + 0.6 * fresnel) * sunlit;
	float sky_wave = sin(dot(p, vec2(0.12, 0.56)) + drift * 2.0 - seconds * 0.36);
	float sky_band = smoothstep(0.53, 0.94, sky_wave) * smoothstep(-0.3, 0.8, broad);
	col += vec3(0.035, 0.045, 0.039) * sky_band * sunlit;
	vec3 amber = mix(vec3(0.92, 0.64, 0.37), vec3(1.0, 0.82, 0.53), streak);
	col = mix(col, amber, trail * (0.13 + 0.55 * streak) * sunlit * (1.0 - rain * 0.72));
	float lap = 1.0 - smoothstep(0.025, 0.13, abs(water_depth - 0.14 - broad * 0.07));
	col = mix(col, vec3(0.63, 0.76, 0.61) * mix(0.37, 1.0, sunlit), lap * (0.16 + 0.22 * max(0.0, drift)));
	float shelf = smoothstep(0.05, 0.48, water_depth) * (1.0 - smoothstep(0.85, 2.0, water_depth));
	float light_net = 1.0 - smoothstep(0.02, 0.20, abs(sin(p.x * 1.8 + ripple) + sin(p.y * 2.1 + broad)));
	col += vec3(0.095, 0.092, 0.055) * light_net * shelf * sunlit * fine_fade;
	col = mix(col, vec3(0.15, 0.23, 0.30), rain * 0.36);
	col = mix(col, col * vec3(0.61, 0.31, 0.61) + vec3(0.047, 0.005, 0.027), blood);
	ALBEDO = col;
	ALPHA = mix(0.57, 1.0, smoothstep(0.0, 1.55, water_depth));
	if (CAMERA_POSITION_WORLD.y < -0.035) {
		float through = smoothstep(0.35, 0.90, -ray.y);
		vec3 surface = mix(vec3(0.045,0.24,0.25),vec3(0.39,0.68,0.57),through);
		surface += vec3(0.08,0.13,0.09) * (sky_band*0.55 + streak*0.45) * sunlit;
		ALBEDO = surface * mix(0.30,1.0,sunlit);
		ALPHA = mix(1.0,0.87,through);
	}
}
