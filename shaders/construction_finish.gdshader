shader_type spatial;

uniform vec4 tint : source_color = vec4(0.63, 0.46, 0.3, 1.0);
uniform int tier = 0;
uniform int cracks = 0;
varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

float noise_cell(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void fragment() {
	vec3 n = abs(local_normal);
	vec2 uv = (n.y > n.x && n.y >= n.z ? local_pos.xz : (n.z >= n.x ? local_pos.xy : local_pos.zy)) + 0.5;
	float pixel = max(max(fwidth(uv.x), fwidth(uv.y)), 0.001);
	float detail = 1.0 - smoothstep(0.006, 0.035, pixel);
	float fleck = (noise_cell(floor(uv * 64.0)) - 0.5) * detail;
	float shade = 1.0;
	float metal = 0.0;
	bool hardware = COLOR.r < 0.45;
	if (tier == 5) {
		shade = 1.0 + fleck * 0.12;
	} else if (hardware || tier == 4) {
		vec2 panel = fract(uv * vec2(2.0, 1.0) + vec2(0.25, 0.0));
		vec2 edge = min(panel, 1.0 - panel) / vec2(2.0, 1.0);
		float joint = min(edge.x, edge.y);
		shade = 0.65 + 0.35 * smoothstep(0.002, 0.010 + pixel, joint);
		shade += 0.14 * (1.0 - smoothstep(0.0, 0.009 + pixel, abs(joint - 0.017)));
		float rivet = distance(edge, vec2(0.038, 0.047));
		shade += (1.0 - smoothstep(0.009, 0.016 + pixel, rivet)) * 0.32 * detail;
		shade += fleck * 0.09;
		metal = 0.42;
	} else if (tier <= 1) {
		float row = floor(uv.y * 5.0);
		float plank = fract(uv.y * 5.0);
		float cut = min(plank, 1.0 - plank) * 0.2;
		float grain = sin(plank * 27.0 + sin(uv.x * 7.0 + row) * 1.4);
		shade = 0.72 + 0.26 * smoothstep(0.0, 0.008 + pixel, cut);
		shade += (noise_cell(vec2(row, 1.0)) - 0.5) * 0.22 + grain * 0.043 * detail + fleck * 0.12;
	} else if (tier == 2) {
		float row = floor(uv.y * 4.0);
		vec2 course = vec2(uv.x * 2.5 + mod(row, 2.0) * 0.5, uv.y * 4.0);
		course.x += 0.065 * sin(uv.y * 27.0 + row);
		vec2 stone = fract(course);
		vec2 rim = min(stone, 1.0 - stone);
		float face = min(rim.x, rim.y) + 0.018 * fleck;
		shade = 0.57 + 0.45 * smoothstep(0.019, 0.09 + pixel, face);
		shade += (noise_cell(floor(course)) - 0.5) * 0.30 + fleck * 0.17;
	} else {
		vec2 form = abs(fract(uv * vec2(1.0, 2.0)) - 0.5);
		float line = 1.0 - smoothstep(0.002, 0.012 + pixel, 0.5 - form.y);
		vec2 tie = fract(uv * 2.0) - 0.5;
		float hole = 1.0 - smoothstep(0.023, 0.047 + pixel, length(tie));
		shade = 1.0 - line * 0.13 - hole * 0.37 * detail + fleck * 0.14;
	}
	if (cracks > 0) {
		float kink = floor(sin(uv.y * 16.0) * 2.0) * 0.014;
		float seam = abs(uv.x - (0.30 + uv.y * 0.45 + kink));
		float damage = (1.0 - smoothstep(0.007, 0.016 + pixel * 0.35, seam)) * smoothstep(0.18, 0.28, uv.y);
		if (cracks == 2) {
			float branch = abs(uv.x - (0.78 - uv.y * 0.46 - kink));
			damage = max(damage, (1.0 - smoothstep(0.01, 0.022 + pixel * 0.35, branch)) * (1.0 - smoothstep(0.53, 0.62, uv.y)));
			shade *= 0.92;
		}
		shade *= 1.0 - damage * 0.68;
	}
	vec3 base = hardware ? vec3(0.15, 0.145, 0.13) : tint.rgb;
	if (tier == 5) {
		base = OUTPUT_IS_SRGB ? COLOR.rgb : mix(pow((COLOR.rgb + 0.055) / 1.055, vec3(2.4)), COLOR.rgb / 12.92, lessThanEqual(COLOR.rgb, vec3(0.04045)));
	}
	ALBEDO = base * shade;
	METALLIC = metal;
	ROUGHNESS = mix(0.93, 0.65, metal * 2.0);
}
