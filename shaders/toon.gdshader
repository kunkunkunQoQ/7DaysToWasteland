shader_type spatial;
render_mode specular_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform float hurt = 0.0;

void fragment() {
	vec3 pigment = COLOR.rgb;
	#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
		pigment = pow(pigment, vec3(2.2));
	#endif
	ALBEDO = mix(mix(tint.rgb * pigment, vec3(0.59, 0.22, 0.22), hurt * 0.38), vec3(1.0, 0.97, 0.91), smoothstep(0.54, 0.80, hurt));
	ROUGHNESS = 1.0;
}

void light() {
	float coefficient = max(dot(NORMAL, LIGHT), 0.0);
	float step_light = 0.12 + smoothstep(0.05, 0.42, coefficient) * 0.33 + smoothstep(0.40, 0.87, coefficient) * 0.55;
	DIFFUSE_LIGHT += LIGHT_COLOR * step_light * ATTENUATION / 3.14159;
}
