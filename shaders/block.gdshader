shader_type spatial;
render_mode specular_disabled;

uniform int cracks = 0;
uniform vec4 tint : source_color = vec4(0.6, 0.42, 0.24, 1.0);
uniform int tier = 0;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(131.5, 397.3))) * 23432.62);
}

void fragment() {
	vec2 tex = floor(UV * 32.0) / 32.0;
	float scratch = h(floor(tex * 28.0));
	float band = smoothstep(0.78, 0.94, sin(tex.y * (tier < 2 ? 59.0 : 31.0) + scratch * 0.9));
	float main_seam = abs(tex.y - (0.72 - tex.x * 0.61 + floor(sin(tex.x * 17.0) * 2.0) / 32.0));
	float crack = cracks > 0 ? step(main_seam, cracks == 2 ? 0.049 : 0.025) : 0.0;
	if (cracks == 2) {
		float branch = abs(tex.y - (tex.x * 0.79 + 0.11 + floor(sin(tex.x * 21.0)) / 32.0));
		crack = max(crack, step(branch, 0.031) * step(0.40, tex.x));
	}
	ALBEDO = tint.rgb * (0.86 + 0.24 * scratch - band * 0.11 - crack * 0.58);
	ROUGHNESS = 0.91;
}
