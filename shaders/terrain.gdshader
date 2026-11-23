shader_type spatial;
render_mode specular_disabled;

uniform float wind_time = 0.0;
uniform float rain = 0.0;
uniform float sunlight : hint_range(0.0, 1.0) = 1.0;
varying vec3 world_pos;
varying float sun_pattern;

float grain(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 grain_pos = world_pos.xz * 5.4;
	float mottled = grain(floor(grain_pos));
	float speckle = step(0.88, mottled) * 0.11 - step(mottled, 0.18) * 0.14 + 1.0;
	vec2 footprint = fwidth(grain_pos);
	float unresolved = smoothstep(0.45, 1.2, max(footprint.x, footprint.y));
	ALBEDO = COLOR.rgb * mix(speckle, 0.988, unresolved) * (1.0 - rain * 0.25);
	ROUGHNESS = 1.0;

	sun_pattern = 1.0;
	if (sunlight > 0.0) {
		float waves = sin(world_pos.x * 0.029 + wind_time * 0.027) * sin(world_pos.z * 0.048 - wind_time * 0.014);
		sun_pattern -= smoothstep(0.18, 0.64, waves) * 0.26 * sunlight;
		if (world_pos.y < -0.12) {
			float curl = sin(world_pos.x * 1.1 + wind_time * 0.53) + sin(world_pos.z * 1.3 - wind_time * 0.38);
			float caustic = 1.0 - smoothstep(0.04, 0.20, abs(curl + 0.3 * sin(world_pos.z * 2.7 + world_pos.x)));
			sun_pattern *= 1.0 + caustic * 0.42 * sunlight * exp(world_pos.y * 0.15) * (1.0 - unresolved);
		}
	}
}

void light() {
	float incidence = max(dot(NORMAL, LIGHT), 0.0);
	float pattern = LIGHT_IS_DIRECTIONAL ? sun_pattern : 1.0;
	DIFFUSE_LIGHT += LIGHT_COLOR * (incidence * pattern * ATTENUATION / PI);
}
