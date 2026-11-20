shader_type spatial;
render_mode specular_disabled;
varying vec3 local_point;
uniform vec4 coat_dye : source_color = vec4(0.286,0.435,0.396,1.0);
uniform vec4 trouser_dye : source_color = vec4(0.22,0.27,0.29,1.0);
uniform vec4 scarf_dye : source_color = vec4(0.76,0.46,0.28,1.0);

void vertex() {
	local_point = VERTEX;
}

void fragment() {
	vec2 grain = vec2(local_point.x + local_point.z * 0.82, local_point.y) * 440.0;
	float resolved = 1.0 - smoothstep(0.32, 1.45, max(fwidth(grain.x), fwidth(grain.y)));
	float thread = sin(grain.x * 3.14) * cos(grain.y * 3.14);
	float folds = sin(local_point.y * 67.0 + 4.7 * sin(local_point.x * 11.0 + local_point.z * 14.0));
	float wear = smoothstep(0.52, 1.0, folds);
	vec3 dye = COLOR.rgb;
	#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	dye = pow(dye, vec3(2.2));
	#endif
	vec3 pigment = COLOR.rgb;
	float canvas = 1.0 - smoothstep(0.035,0.105,distance(pigment,vec3(0.286,0.435,0.396)));
	float trousers = 1.0 - smoothstep(0.022,0.084,distance(pigment,vec3(0.22,0.27,0.29)));
	float scarf = 1.0 - smoothstep(0.034,0.095,distance(pigment,vec3(0.756,0.463,0.278)));
	dye = mix(dye,coat_dye.rgb * clamp(pigment.g/0.435,0.68,1.24),canvas);
	dye = mix(dye,trouser_dye.rgb * clamp(pigment.g/0.27,0.70,1.18),trousers);
	dye = mix(dye,scarf_dye.rgb,scarf);
	ALBEDO = dye * (0.90 + wear * 0.16 + thread * 0.065 * resolved);
	ROUGHNESS = 0.94;
}
