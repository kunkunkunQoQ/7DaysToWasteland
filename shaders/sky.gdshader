shader_type sky;

uniform vec3 sun_dir = vec3(-0.35, 0.14, -0.926);
uniform float daylight = 0.62;
uniform float twilight = 0.92;
uniform float blood = 0.0;
uniform float wet = 0.0;
uniform float clock_seconds = 0.0;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 f = fract(p);
	vec2 i = floor(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), u.x), mix(h(i + vec2(0, 1)), h(i + vec2(1)), u.x), u.y);
}

float cloud(vec2 p) {
	return 0.60 * noise2(p) + 0.26 * noise2(p * 2.11 + 7.0) + 0.14 * noise2(p * 4.31 - 5.0);
}

void sky() {
	vec3 ray = EYEDIR;
	float elevation = max(ray.y, 0.0);
	float toward = pow(max(dot(normalize(vec3(ray.x, 0.0, ray.z) + vec3(0.0001, 0.0, 0.0)),
		normalize(vec3(sun_dir.x, 0.0, sun_dir.z))), 0.0), 3.5);
	vec3 top = mix(vec3(0.037, 0.029, 0.088), vec3(0.31, 0.48, 0.69), daylight);
	top = mix(top, vec3(0.10, 0.21, 0.27), twilight * 0.88);
	vec3 low = mix(vec3(0.11, 0.081, 0.18), vec3(0.79, 0.67, 0.62), daylight);
	low = mix(low, mix(vec3(0.36, 0.49, 0.51), vec3(0.93, 0.49, 0.27), toward), twilight);
	top = mix(top, vec3(0.078, 0.032, 0.12), blood);
	low = mix(low, mix(vec3(0.27, 0.105, 0.25), vec3(0.65, 0.12, 0.20), toward), blood);
	float height_band = floor(pow(elevation / 0.64, 0.52) * 23.0) / 23.0;
	vec3 col = mix(low, top, clamp(height_band, 0.0, 1.0));
	col = mix(col, vec3(dot(col, vec3(0.3, 0.5, 0.2))) * vec3(0.72, 0.79, 1.08), wet * 0.64);
	float sun_dot = dot(ray, sun_dir);
	float disk = smoothstep(mix(0.9965, 0.9953, blood), mix(0.99685, 0.9957, blood), sun_dot);
	vec3 sun_col = mix(vec3(1.0, 0.89, 0.64), vec3(0.99, 0.14, 0.20), blood);
	float glow = pow(max(sun_dot, 0.0), 23.0);
	col += sun_col * glow * mix(0.16, 0.35, twilight) * (1.0 - wet * 0.8);
	float band = floor(ray.y * 112.0) / 112.0;
	sun_col *= 0.9 + 0.1 * sin(band * 49.0);
	col = mix(col, sun_col, disk * (1.0 - wet * 0.82));

	if (ray.y > 0.015) {
		vec2 layer = ray.xz / (0.37 + ray.y) * vec2(2.38, 4.15) + vec2(4.5, 3.1) + vec2(clock_seconds * 0.004, 0);
		float wisp = smoothstep(0.65, 0.84, noise2(layer * vec2(0.84, 3.4) + 17.2)) * 0.31;
		col = mix(col, low * 1.1, wisp * smoothstep(0.05, 0.27, ray.y));
		float cumulus = cloud(layer);
		float cover = step(0.60 - wet * 0.15, cumulus) * smoothstep(0.032, 0.14, ray.y);
		float lit = floor(smoothstep(0.55, 0.82, cumulus + 0.05 * toward) * 8.0) / 8.0;
		vec3 shade = mix(vec3(0.10, 0.08, 0.20), vec3(0.38, 0.38, 0.44), max(daylight, twilight));
		vec3 rim = mix(vec3(0.23, 0.21, 0.39), vec3(0.97, 0.61, 0.43), max(daylight, twilight));
		shade = mix(shade, vec3(0.22, 0.061, 0.17), blood);
		rim = mix(rim, vec3(0.68, 0.16, 0.23), blood);
		vec3 cloud_col = mix(shade, rim, lit);
		col = mix(col, mix(cloud_col, shade * 0.63, wet * 0.8), cover * (0.95 - disk * 0.62));
		vec2 grid = floor(ray.xz / (ray.y + 0.7) * 460.0);
		float star = step(0.997, h(grid)) * (1.0 - cover) * smoothstep(0.12, 0.35, ray.y);
		col += vec3(0.70, 0.67, 0.79) * star * (1.0 - max(daylight, twilight)) * (1.0 - wet);
	}
	COLOR = max(col, vec3(0.0));
}
