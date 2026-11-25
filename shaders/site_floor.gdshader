shader_type spatial;
render_mode specular_disabled;

uniform int finish;
uniform vec4 tone : source_color;
uniform vec4 accent : source_color;
uniform float weathering;
uniform sampler2D patina : repeat_enable, filter_linear_mipmap;
uniform vec4 exposed : source_color = vec4(.58,.53,.44,1.0);
varying float top;

float hash21(vec2 p) {
	vec3 v = fract(vec3(p.xyx)*vec3(.1031,.1030,.0973));
	v += dot(v,v.yzx+33.33);
	return fract((v.x+v.y)*v.z);
}

float joint(vec2 cell, vec2 half_width) {
	vec2 edge = abs(fract(cell+.5)-.5);
	vec2 aa = max(fwidth(cell)*.65, vec2(.001));
	vec2 interior = smoothstep(half_width-aa,half_width+aa,edge);
	return 1.0-min(interior.x,interior.y);
}

void vertex() {
	top = NORMAL.y;
}

void fragment() {
	vec2 p=UV2;
	vec3 col=tone.rgb;
	float grain=hash21(floor(p*18.0)+weathering);
	float detail=1.0-smoothstep(.025,.12,length(fwidth(p)));
	if (top>.96) {
		vec2 offset=weathering*vec2(.31,.69);
		float stain=texture(patina,p*.104+offset).r;
		float grit=texture(patina,p*.79-offset).r;
		if (finish==0) {
			float row=floor(p.y/.245);
			vec2 board=vec2(p.x/2.15+hash21(vec2(row,weathering)),p.y/.245);
			float shade=hash21(floor(board)+weathering);
			float streak=sin(p.y*145.0+2.8*sin(p.x*2.7+shade*19.0));
			col=mix(tone.rgb,accent.rgb,shade*.72)*(.96+.06*streak*detail);
			col*=1.0-.30*joint(board,vec2(.008,.032))*(.5+.5*detail);
			float grey=smoothstep(.42,.78,.72*stain+.28*grit);
			col=mix(col,exposed.rgb,grey*.46);
		} else if (finish==1) {
			vec2 tile=p/.55;
			vec2 cell=floor(tile);
			float border=step(2.0,abs(cell.x+.5))*step(abs(cell.x+.5),3.0);
			float checker=mod(cell.x+cell.y,2.0);
			col=mix(tone.rgb,accent.rgb,max(border*.86,checker*.24));
			col*=.92+.13*hash21(cell+weathering);
			col*=1.0-.26*joint(tile,vec2(.013))*(.55+.45*detail);
			// A few broken corners expose ochre bedding under the glazed tile.
			vec2 corner=fract(tile);
			if (hash21(cell+13.0)>.5) { corner.x=1.0-corner.x; }
			float loss=clamp((hash21(cell-weathering)*.72+stain*.28-.56)*1.9,0.0,.54);
			float bevel=corner.x*.88+corner.y+(grit-.5)*.35;
			col=mix(col,exposed.rgb*(.72+grit*.22),1.0-smoothstep(loss-.018,loss+.04,bevel));
		} else if (finish==2) {
			vec2 panels=p/vec2(2.4,2.0);
			col*=.9+.16*hash21(floor(panels)+weathering);
			col*=1.0-.24*joint(panels,vec2(.007));
			float dist_to_line=abs(abs(p.x)-1.22);
			float aa=max(fwidth(p.x),.001);
			float stripe=1.0-smoothstep(.048-aa,.048+aa,dist_to_line);
			float chips=hash21(floor(p*9.0)+weathering);
			col=mix(col,accent.rgb,stripe*(.44+.40*step(.31,chips))*smoothstep(.29,.62,stain+chips*.08));
			col*=1.0-.28*smoothstep(.56,.69,stain+(grit-.5)*.16);
		} else {
			float run=floor(p.y/.84);
			vec2 felt=vec2(p.x/3.85+fract(run*.39),p.y/.84);
			col=mix(tone.rgb,accent.rgb,.58*hash21(floor(felt)+weathering));
			col*=1.0-.27*joint(felt,vec2(.008,.028));
			// Dust collects at the rim of old rain pools in the roofing felt.
			float pond=stain+(grit-.5)*.14;
			float rim=1.0-smoothstep(.008,.033,abs(pond-.59));
			col=mix(col,exposed.rgb,rim*.28);
			col*=1.0-.20*smoothstep(.59,.65,pond);
		}
		col*=1.0+(.10*grain-.05)*detail;
	} else {
		col*=.79;
	}
	ALBEDO=col;
	ROUGHNESS=.96;
}
