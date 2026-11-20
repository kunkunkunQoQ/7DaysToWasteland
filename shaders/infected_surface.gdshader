shader_type spatial;

// Vertex alpha stores the surface finish. Fabric is matte; membranes,
// polished crystal and enamel catch progressively narrower highlights.
uniform float hurt = 0.0;
uniform float signal_glow = 0.0;
varying float finish;

void vertex() {
	finish = COLOR.a;
}

void fragment() {
	vec3 pigment = COLOR.rgb;
	#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
		pigment = pow(pigment, vec3(2.2));
	#endif
	ALBEDO = mix(mix(pigment, vec3(0.59, 0.22, 0.22), hurt * 0.38), vec3(1.0, 0.97, 0.91), smoothstep(0.54, 0.80, hurt));
	EMISSION = ALBEDO * signal_glow * smoothstep(0.18, 0.85, max(pigment.r, max(pigment.b, pigment.g)));
	ROUGHNESS = mix(0.98, 0.28, finish);
}

void light() {
	float incidence = max(dot(NORMAL, LIGHT), 0.0);
	float diffuse = 0.12 + smoothstep(0.05, 0.42, incidence) * 0.33
		+ smoothstep(0.40, 0.87, incidence) * 0.55;
	DIFFUSE_LIGHT += LIGHT_COLOR * diffuse * ATTENUATION / PI;
	float highlight = pow(max(dot(NORMAL, normalize(VIEW + LIGHT)), 0.0), mix(9.0, 52.0, finish));
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * highlight * finish * incidence * 0.48;
}
