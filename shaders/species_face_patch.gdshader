shader_type spatial;
render_mode depth_prepass_alpha, specular_disabled;

uniform sampler2D face_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 face_rect = vec4(0.0,0.0,1.0,1.0);
uniform bool has_atlas;
uniform bool face_enabled = true;

void fragment() {
	vec4 portrait = texture(face_atlas,face_rect.xy+clamp(UV,vec2(0.012),vec2(0.988))*face_rect.zw);
	float rim = 1.0-smoothstep(0.75,1.0,length((UV-vec2(0.5))/vec2(0.485)));
	ALBEDO = portrait.rgb;
	ALPHA = has_atlas && face_enabled ? portrait.a*rim : 0.0;
	ROUGHNESS = 0.91;
}
