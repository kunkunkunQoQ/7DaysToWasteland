shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform float brightness = 1.0;
uniform bool vertex_paint = false;
uniform bool skin_shading = false;
uniform bool work_gloves = false;
uniform bool paw_gloves = false;
varying vec3 model_point;
varying vec3 hand_position;


void vertex() {
	model_point = abs(VERTEX);
	hand_position = VERTEX;

}

void fragment() {
	float bands = 0.64 + step(0.15, NORMAL.y + NORMAL.x * 0.37) * 0.17
		+ step(0.44, NORMAL.y + NORMAL.x * 0.37) * 0.19;
	float edge = max(min(model_point.x, model_point.y), max(min(model_point.x, model_point.z), min(model_point.y, model_point.z)));
	float ink = 1.0 - step(0.465, edge) * 0.38;
	vec3 pigment = tint.rgb;
	if (vertex_paint) {
		pigment = COLOR.rgb;
		#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
		pigment = pow(pigment,vec3(2.2));
		#endif
		ink = 1.0;
	}
	if (skin_shading) {
		float sky = smoothstep(-0.68,0.92,dot(normalize(NORMAL),normalize(vec3(-0.38,0.78,0.49))));
		bands = 0.68 + 0.36 * sky;
		if (!work_gloves && !paw_gloves) {
			float palm = smoothstep(0.139,0.185,-hand_position.z);
			float crease = abs(hand_position.z + 0.145 + (hand_position.x-0.13)*0.15);
			float wrinkle = (1.0-smoothstep(0.001,0.004,crease))*smoothstep(0.04,0.082,-hand_position.y);
			pigment *= mix(vec3(1.04,0.975,0.95),vec3(1.0),sky);
			pigment *= 1.0 + palm*0.05 - wrinkle*0.13;
		}
		if (paw_gloves && hand_position.z < -0.105) {
			vec2 uv=hand_position.xz;
			float pad=length((uv-vec2(0.124,-0.215))/vec2(0.036,0.027));
			for(int i=0;i<4;i++) {
				vec2 toe=vec2(0.081+float(i)*0.028,-0.255);
				pad=min(pad,length((uv-toe)/vec2(0.010,0.014)));
			}
			vec3 fur=mix(vec3(0.91,0.62,0.67),vec3(0.96,0.85,0.70),smoothstep(0.88,1.03,pad));
			#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
			fur=pow(fur,vec3(2.2));
			#endif
			pigment=fur;
		}
		if (work_gloves && hand_position.z < -0.091) {
			float cuff = 1.0 - smoothstep(0.012,0.021,abs(hand_position.z + 0.108));
			float knuckle = smoothstep(-0.015,0.025,hand_position.y) * smoothstep(0.16,0.22,-hand_position.z);
			vec3 leather = mix(vec3(0.43,0.26,0.13),vec3(0.24,0.17,0.11),knuckle);
			leather = mix(leather,vec3(0.23,0.22,0.17),cuff);
			#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
			leather = pow(leather,vec3(2.2));
			#endif
			pigment = leather;
		}
	}
	ALBEDO = pigment * bands * ink * (0.56 + 0.48 * brightness);
}
