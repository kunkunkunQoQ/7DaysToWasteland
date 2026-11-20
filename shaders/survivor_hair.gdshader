shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// U travels across a lock; V follows its sweep from the part towards the tips.
uniform float strand_count : hint_range(2.0,160.0,1.0) = 9.0;

float strand(float phase) {
	float band = 1.0 - smoothstep(0.10,0.50,fwidth(phase));
	return sin(phase*TAU)*band;
}

void fragment() {
	vec3 dye = COLOR.rgb;
	#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	dye = mix(dye/12.92,pow((dye+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),dye));
	#endif
	float u = UV.x*strand_count;
	float v = UV.y;
	float drift = 0.12*sin(v*6.4+u*0.35) + 0.075*sin(11.1*v-u*0.84);
	float ribbon = strand(u*0.28+drift*0.32);
	float fibers = strand(u+drift)*0.13+strand(u*2.17-drift)*0.052;
	float root_light = mix(0.83,1.04,smoothstep(0.0,0.56,v));
	ALBEDO = dye*root_light*(1.0+0.16*ribbon+fibers);
	ROUGHNESS = clamp(0.70+0.055*ribbon+0.04*(1.0-v),0.57,0.86);
	SPECULAR = 0.23;
}
