shader_type canvas_item;

uniform float strength = 1.0;
uniform bool landscape = false;

void fragment() {
	if (landscape) {
		float fade = 1.0 - smoothstep(0.16, 0.80, UV.x);
		float floor_fade = smoothstep(0.72, 1.0, UV.y);
		float alpha = (fade * 0.86 + floor_fade * 0.27) * strength;
		COLOR = vec4(0.058, 0.042, 0.081, clamp(alpha, 0.0, 0.94));
	} else {
		float edge = length((UV - 0.5) * vec2(1.28, 1.0));
		COLOR = vec4(0.042, 0.036, 0.073, strength * (0.69 + edge * 0.28));
	}
}
