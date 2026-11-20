shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;

uniform bool valid = true;
varying vec3 grid;

void vertex() {
	grid = VERTEX;
}

void fragment() {
	vec3 p = abs(fract((grid + vec3(0.5)) * 8.0 + vec3(0.5)) - vec3(0.5));
	float gridline = step(min(min(max(p.x, p.y), max(p.x, p.z)), max(p.y, p.z)), 0.15);
	ALBEDO = valid ? vec3(0.56,0.94,0.82) : vec3(0.93,0.36,0.37);
	ALPHA = 0.19 + gridline * 0.48;
}
