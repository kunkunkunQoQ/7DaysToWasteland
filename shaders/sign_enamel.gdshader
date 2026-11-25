shader_type spatial;
render_mode specular_disabled;

uniform vec4 enamel : source_color;
uniform vec4 primer : source_color = vec4(.55,.48,.36,1.);
uniform vec4 rust : source_color = vec4(.49,.29,.18,1.);
uniform vec4 rule : source_color = vec4(.77,.69,.51,1.);
uniform float wear;
uniform float variation;
varying vec2 point;
varying vec2 half_size;
varying float face;

float hash_cell(vec2 cell) {
	vec3 h = fract(cell.xyx * vec3(.1031,.1030,.0973));
	h += dot(h,h.yzx + 33.33);
	return fract((h.x + h.y) * h.z);
}

float mottling(vec2 p) {
	vec2 cell = floor(p);
	vec2 t = smoothstep(vec2(0.),vec2(1.),fract(p));
	return mix(mix(hash_cell(cell),hash_cell(cell+vec2(1.,0.)),t.x),
		mix(hash_cell(cell+vec2(0.,1.)),hash_cell(cell+1.),t.x),t.y);
}

void vertex() {
	vec2 size = vec2(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz));
	point = VERTEX.xy * size;
	half_size = size * .5;
	face = NORMAL.z;
}

void fragment() {
	vec3 paint = enamel.rgb;
	if (face > .9) {
		vec2 p = point + vec2(11.7,9.3)*variation;
		vec2 margin = half_size - abs(point);
		float edge = min(margin.x,margin.y);
		float aa = max(.002,length(fwidth(point))*.5);
		float detail = 1.-smoothstep(.012,.075,aa);
		float broad = mottling(p * vec2(2.,3.));
		float grain = mix(.5,mottling(p*vec2(28.,39.)),detail);
		paint = mix(paint,primer.rgb,.08 + .21*wear*broad);
		// A surviving coach line breaks where the former coat shows at the edge.
		float line = 1.-smoothstep(.005,.005+aa,abs(edge-.027));
		paint = mix(paint,rule.rgb,line*(.43+.27*broad));
		float chip = (.014 + .18*pow(broad,3.) + .047*(grain-.5))*wear;
		float loss = 1.-smoothstep(chip-aa,chip+aa,edge);
		paint = mix(paint,mix(primer.rgb,rust.rgb,smoothstep(.25,.78,grain)),loss);
		// Rain carries iron oxide downward from the original four fasteners.
		vec2 bolt = abs(point)-(half_size-vec2(.061,.071));
		float run = (half_size.y-.071)*sign(point.y)-point.y;
		float stripe = 1.-smoothstep(.004,.014+aa,abs(bolt.x+.003*sin(run*33.)));
		float trail = stripe*step(0.,run)*(1.-smoothstep(.02,.07+.14*wear,run));
		paint = mix(paint,rust.rgb,trail*(.42+.25*grain));
		float ring = 1.-smoothstep(.011,.017+aa,length(bolt));
		float head = 1.-smoothstep(.006,.010+aa,length(bolt));
		paint = mix(mix(paint,rust.rgb,ring),primer.rgb*.58,head);
	}
	ALBEDO = paint;
	ROUGHNESS = .94;
}
