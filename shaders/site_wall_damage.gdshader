shader_type spatial;
render_mode specular_disabled, depth_draw_never;

uniform bool severe = false;
uniform bool timber = false;
uniform vec3 impact;
varying vec3 offset;
varying vec3 facing;

float grit(vec2 p) {
	vec3 n=fract(vec3(p.xyx)*vec3(.103,.097,.101));
	n+=dot(n,n.yzx+33.3);
	return fract((n.x+n.y)*n.z);
}

// A continuous, tapered fracture between two points on the surface, in metres.
float fracture(vec2 p, vec2 a, vec2 b, float width, float salt) {
	vec2 v=b-a;
	float t=dot(p-a,v)/dot(v,v);
	vec2 across=normalize(vec2(-v.y,v.x));
	float step_pos=clamp(t,0.0,1.0)*7.0;
	float kink=mix(grit(vec2(floor(step_pos),salt)),grit(vec2(floor(step_pos)+1.0,salt)),fract(step_pos))-.5;
	float dist=abs(dot(p-a,across)-kink*.077*sin(clamp(t,0.0,1.0)*3.14159));
	float taper=width*mix(1.25,.18,clamp(t,0.0,1.0));
	float aa=clamp(length(fwidth(p))*.55,.0015,.016);
	return (1.0-smoothstep(taper-aa,taper+aa,dist))*smoothstep(-.02,.02,t)*(1.0-smoothstep(.95,1.0,t));
}

void vertex() {
	offset=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz-impact;
	facing=MODEL_NORMAL_MATRIX*NORMAL;
}

void fragment() {
	vec3 n=abs(normalize(facing));
	if (n.y>.70) { discard; }
	vec2 p=vec2(n.x>n.z ? offset.z : offset.x,offset.y);
	if (timber) { p=vec2(p.y*2.45,p.x*.80); }
	if (dot(p,p)>2.5) { discard; }
	float seed=grit(floor(impact.xz*7.0));
	p.x*=seed>.5 ? 1.0 : -1.0;
	float reach=severe ? 1.0 : .64;
	vec2 q=p/reach;
	float w=severe ? .015 : .011;
	vec2 upper=vec2(timber?.033:.19,.46);
	vec2 lower=vec2(timber?-.027:-.24,-.38);
	float line=max(fracture(q,vec2(0.0),upper,w,seed),fracture(q,vec2(0.0),lower,w,seed+3.0));
	line=max(line,fracture(q,upper,upper+vec2(timber?-.05:-.12,.48),w*.75,seed+1.0));
	line=max(line,fracture(q,lower,lower+vec2(timber?.05:.13,-.48),w*.72,seed+2.0));
	if (severe) {
		line=max(line,fracture(q,upper*.60,vec2(timber?-.15:-.38,.57),w*.70,seed+7.0));
		line=max(line,fracture(q,lower*.51,vec2(timber?.16:.47,-.43),w*.67,seed+6.0));
	}
	vec2 chip_pos=q*vec2(timber?1.28:1.07,timber?.82:1.20);
	float fleck=grit(floor(chip_pos*35.0)+seed);
	float irregular=fleck*.035+.020*sin(chip_pos.x*47.0+chip_pos.y*18.0);
	float chip_radius=(severe?.17:.099)+irregular;
	float chip=1.0-smoothstep(chip_radius-.013,chip_radius,length(chip_pos));
	float alpha=max(line*.85,chip);
	if (alpha<.08) { discard; }
	vec3 exposed=timber ? vec3(.47,.32,.19) : vec3(.44,.39,.32);
	ALBEDO=mix(exposed*(.78+.32*fleck),vec3(.15,.12,.10),line*.78);
	ROUGHNESS=1.0;
	ALPHA=alpha;
}
