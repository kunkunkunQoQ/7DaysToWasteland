shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_disabled;

varying vec3 scene_point;

float grain(vec3 p) {
	p = fract(p * vec3(0.1031,0.1030,0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x+p.y)*p.z);
}

void vertex() {
	scene_point = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
}

void fragment() {
	vec3 pixel = floor(scene_point * 8.0);
	float speck = grain(pixel);
	float blocks = grain(floor(scene_point * 2.2));
	float detail = 0.88 + step(0.32, speck)*0.074 + step(0.76,speck)*0.12;
	float flakes = step(0.71, blocks)*step(0.83,speck);
	vec3 pigment = COLOR.rgb;
	#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	pigment = pow(pigment,vec3(2.05));
	#endif
	ALBEDO = pigment * detail * 1.07 + vec3(0.023,0.014,0.006) * flakes;
	ROUGHNESS = 1.0;
}
