shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform bool timber = false;
uniform bool submerged = false;
varying vec3 local_point;

float grain(vec3 p) {
	p = fract(p * vec3(.1031,.1030,.0973));
	p += dot(p,p.yxz+33.33);
	return fract((p.x+p.y)*p.z);
}

void vertex() {
	local_point = VERTEX;
}

void fragment() {
	vec3 dye = COLOR.rgb;
	#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	dye = pow(dye,vec3(2.2));
	#endif
	float detail = 1.0 - smoothstep(.004,.035,length(fwidth(local_point)));
	float grit = grain(floor(local_point*74.0));
	float streak = sin(local_point.y*126.0 + 3.4*sin(local_point.x*7.0+local_point.z*9.0));
	float wear = timber ? (.06*streak+.055*grit) : (.025*grit+.12*step(.985,grit));
	float oxide = grain(floor(vec3(local_point.x*16.0,local_point.y*6.0,local_point.z*16.0)));
	float patina = submerged ? (1.0-smoothstep(-.40,.20,local_point.y))*smoothstep(.32,.84,oxide)*.33 : 0.0;
	ALBEDO = mix(dye*(1.0+wear*detail),dye*vec3(.60,.91,.70),patina);
	ROUGHNESS = timber ? .93 : mix(.60,.83,oxide);
}
