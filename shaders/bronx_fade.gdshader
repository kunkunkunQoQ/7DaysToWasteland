shader_type spatial;
render_mode cull_disabled, diffuse_burley;
float hash(vec2 p) {
	p=fract(p*vec2(0.3181,0.3679));
	p+=dot(p,p+19.371);
	return fract(p.x*p.y);
}
void fragment() {
	vec3 dye=COLOR.rgb;
	#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	dye=mix(dye/12.92,pow((dye+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),dye));
	#endif
	vec2 cells=UV*vec2(650.0,95.0);
	float dots=hash(floor(cells));
	float aa=1.0-smoothstep(0.35,1.5,max(fwidth(cells).x,fwidth(cells).y));
	ALBEDO=dye*(1.0+aa*(dots-0.5)*0.38);
	ROUGHNESS=0.94;
	SPECULAR=0.09;
}
