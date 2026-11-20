shader_type spatial;

// Opaque vertex regions authored by the character mesh: trim .25, cotton .5,
// skin .75 and unmodified accessories 1. Coordinates follow each animated limb.
varying vec3 rest_point;

void vertex() {
	rest_point = VERTEX;
}

float filtered_wave(float cycles) {
	float visibility = 1.0 - smoothstep(0.16, 0.48, fwidth(cycles));
	return sin(TAU * cycles) * visibility;
}

void fragment() {
	vec3 pigment = COLOR.rgb;
	#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	pigment = mix(pigment / 12.92, pow((pigment + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), pigment));
	#endif
	float tag = COLOR.a;
	ROUGHNESS = 0.97;
	SPECULAR = 0.5;
	if (tag < 0.625) {
		float across = rest_point.x + rest_point.z * 0.71;
		float warp = filtered_wave(across * 214.0);
		float weft = filtered_wave(rest_point.y * 275.0);
		float folds = filtered_wave(rest_point.y * 9.0 + 0.26 * sin(across * 27.0));
		if (tag < 0.375) {
			float ribs = filtered_wave((across + rest_point.y * 0.34) * 150.0);
			pigment *= 1.0 + ribs * 0.081;
		} else {
			pigment *= 1.0 + 0.036 * warp + 0.022 * weft + 0.018 * folds;
		}
		ROUGHNESS = 0.93;
		SPECULAR = 0.24;
	} else if (tag < 0.875) {
		float warmth = 0.5 + 0.5 * sin(rest_point.y * 17.0 + rest_point.x * 8.0);
		pigment *= vec3(1.0 + 0.017 * warmth, 1.0, 1.0 - 0.013 * warmth);
		ROUGHNESS = 0.78;
		SPECULAR = 0.28;
	}
	ALBEDO = pigment;
}
