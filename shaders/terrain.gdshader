shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform float wind_time = 0.0;
uniform float rain = 0.0;
varying vec3 world_pos;

float grain(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float mottled = grain(floor(world_pos.xz * 5.4));
	float speckle = step(0.88, mottled) * 0.11 - step(mottled, 0.18) * 0.14 + 1.0;
	float waves = sin(world_pos.x * 0.029 + wind_time * 0.027) * sin(world_pos.z * 0.048 - wind_time * 0.014);
	float cloud_shadow = 1.0 - step(0.37, waves) * 0.18;
	ALBEDO = COLOR.rgb * speckle * cloud_shadow * (1.0 - rain * 0.25);
	if (world_pos.y < -0.12) {
		float curl = sin(world_pos.x * 1.1 + wind_time * 0.53) + sin(world_pos.z * 1.3 - wind_time * 0.38);
		float caustic = 1.0 - smoothstep(0.04,0.20,abs(curl + 0.3*sin(world_pos.z*2.7 + world_pos.x)));
		ALBEDO *= 1.0 + caustic * 0.38 * exp(world_pos.y * 0.15);
	}
	ROUGHNESS = 1.0;
}
