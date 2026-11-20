shader_type spatial;
render_mode specular_disabled;

uniform sampler2D face_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 face_rect = vec4(0.0,0.0,1.0,1.0);
uniform vec4 landmarks;
uniform float snout_length;
uniform vec3 portrait_marks;
uniform vec4 skin_tone : source_color;
uniform bool animal;
uniform bool feral_eyes;
uniform bool has_atlas;
uniform bool face_enabled = true;
uniform float hurt = 0.0;
varying vec3 skull;

void vertex() { skull = VERTEX; }

void fragment() {
	vec3 pigment = COLOR.rgb;
	float iris_glow = 0.0;
	#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
		pigment = pow(pigment, vec3(2.2));
	#endif
	if (has_atlas && face_enabled && UV2.x > 0.5) {
		float rear = (skull.z-landmarks.y)/snout_length;
		float height = (skull.y-landmarks.x)/landmarks.w;
		float width = skull.x/landmarks.z;
		// Eyes, cheek and projecting muzzle remain on their original surfaces.
		// Increasing the wrap behind the eyes carries the pigment around the temples.
		float lateral = abs(width)*(1.0+0.70*max(rear,0.0));
		float u_span = portrait_marks.x*min(lateral,1.0)
			+(0.47-portrait_marks.x)*(1.0-exp(-1.4*max(lateral-1.0,0.0)));
		float temple = smoothstep(0.82,1.14,abs(width))*smoothstep(-0.27,0.27,rear);
		float side_span = clamp(portrait_marks.x+0.22*rear+0.075*(abs(width)-1.0),0.16,0.49);
		u_span = mix(u_span,side_span,temple);
		float v = portrait_marks.y-(animal ? 0.45 : 0.73)*height-portrait_marks.z*rear;
		if (!animal && height>0.0) {
			v = portrait_marks.y-0.245*(1.0-exp(-3.1*height))-portrait_marks.z*rear;
		}
		vec2 uv = vec2(0.5-sign(width)*u_span,v);
		float coverage = (1.0-smoothstep(animal ? 0.25 : 0.50,animal ? 0.86 : 1.18,rear))
			*smoothstep(-0.02,0.085,v)*(1.0-smoothstep(0.89,1.045,v));
		vec4 portrait = texture(face_atlas,face_rect.xy+clamp(uv,vec2(0.023),vec2(0.977))*face_rect.zw);
		if (feral_eyes) {
			// UVs are local to a portrait tile, so both highlights stay on the face as it turns.
			vec2 eye = vec2((abs(uv.x-0.5)-0.25)/0.035,(uv.y-0.276)/0.024);
			iris_glow = (1.0-smoothstep(0.52,1.0,length(eye)))*coverage;
		}
		if (animal) {
			float eye_offset = abs(width)-1.0;
			float eye_distance = 12.0*eye_offset*eye_offset+25.0*height*height+12.0*rear*rear;
			float flank = smoothstep(0.62,1.15,abs(width))*smoothstep(-0.68,0.09,rear)*(1.0-exp(-eye_distance));
			vec3 coat = texture(face_atlas,face_rect.xy+vec2(0.12,0.54)*face_rect.zw).rgb;
			vec3 matched = clamp(pigment/max(coat,vec3(0.012)),vec3(0.55),vec3(3.4));
			portrait.rgb *= mix(vec3(1.0),matched,0.38*flank);
			coverage *= 1.0-0.76*flank;
		} else {
			// Bring the two exposed cheeks into the surrounding complexion. The
			// portrait keeps its shadows, wrinkles and distinct A/B pigmentation.
			vec3 cheek = texture(face_atlas,face_rect.xy+vec2(0.18,0.61)*face_rect.zw).rgb;
			cheek += texture(face_atlas,face_rect.xy+vec2(0.82,0.61)*face_rect.zw).rgb;
			vec3 match_skin = clamp(skin_tone.rgb/max(cheek*0.5,vec3(0.012)),vec3(0.55),vec3(3.3));
			portrait.rgb *= mix(vec3(1.0),match_skin,0.64);
		}
		pigment = mix(pigment,portrait.rgb,coverage*portrait.a);
	}
	pigment = mix(pigment,vec3(0.29,0.012,0.014),0.60*iris_glow);
	EMISSION = vec3(0.43,0.012,0.008)*iris_glow*(1.0-hurt);
	ALBEDO = mix(mix(pigment,vec3(0.59,0.22,0.22),hurt*0.38),vec3(1.0,0.97,0.91),smoothstep(0.54,0.80,hurt));
	ROUGHNESS = 1.0;
}

void light() {
	float incidence = max(dot(NORMAL,LIGHT),0.0);
	float diffuse = 0.12+smoothstep(0.05,0.42,incidence)*0.33+smoothstep(0.40,0.87,incidence)*0.55;
	DIFFUSE_LIGHT += LIGHT_COLOR*diffuse*ATTENUATION/PI;
}
