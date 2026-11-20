shader_type canvas_item;
render_mode unshaded;

uniform sampler2D lookup : filter_nearest, repeat_disable;
uniform sampler2D hands_layer : filter_nearest, repeat_disable;
uniform bool hands_visible = false;
uniform bool underwater = false;
uniform int backdrop = 0;
uniform vec4 impact_color : source_color = vec4(0.94, 0.36, 0.47, 1.0);
uniform vec2 impact_level = vec2(0.0);

void fragment() {
	vec2 sample_uv = UV;
	if (underwater) {
		sample_uv += TEXTURE_PIXEL_SIZE * vec2(sin(UV.y * 21.0 + TIME * 1.5), cos(UV.x * 17.0 + TIME)) * 0.52;
	}
	vec3 source = clamp(texture(TEXTURE, clamp(sample_uv, vec2(0.0), vec2(1.0))).rgb, 0.0, 1.0);
	if (hands_visible) {
		vec4 held = texture(hands_layer,UV);
		source = mix(source,held.rgb,held.a);
	}
	vec3 cell = clamp(floor(source * 16.0), 0.0, 15.0);
	ivec2 point = ivec2(floor(UV / TEXTURE_PIXEL_SIZE)) % 4;
	float matrix[16] = {0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0};
	float threshold = (matrix[point.y * 4 + point.x] + 0.5) / 16.0;
	float row = (cell.y + cell.z * 16.0 + 0.5) / 256.0;
	vec4 a = texture(lookup, vec2((cell.x + 0.5) / 32.0, row));
	vec3 b = texture(lookup, vec2((cell.x + 16.5) / 32.0, row)).rgb;
	vec3 wash = mix(a.rgb, b, a.a);
	vec3 pixel = mix(source, wash, 0.23);
	pixel += (mix(a.rgb, b, step(threshold, a.a)) - wash) * 0.075;
	if (backdrop != 0) {
		float glass = backdrop == 1 ? (1.0 - smoothstep(0.17,0.64,UV.x))*0.72 : 0.94;
		if (glass > 0.0) {
			vec2 px = TEXTURE_PIXEL_SIZE * (backdrop == 1 ? 2.3 : 4.0);
			vec3 diffused = source * 0.24;
			diffused += (texture(TEXTURE, UV+vec2(px.x,0)).rgb+texture(TEXTURE, UV-vec2(px.x,0)).rgb
				+texture(TEXTURE, UV+vec2(0,px.y)).rgb+texture(TEXTURE, UV-vec2(0,px.y)).rgb)*0.115;
			diffused += (texture(TEXTURE, UV+px).rgb+texture(TEXTURE, UV-px).rgb
				+texture(TEXTURE, UV+px*vec2(-1,1)).rgb+texture(TEXTURE, UV+px*vec2(1,-1)).rgb)*0.075;
			pixel = mix(pixel,diffused,glass);
		}
	}
	if (underwater) {
		float surface_light = 1.0 - smoothstep(0.0, 0.76, UV.y);
		vec3 submerged_light = pixel * vec3(0.73, 0.95, 0.94) + vec3(0.008, 0.024, 0.026) * surface_light;
		pixel = mix(pixel, submerged_light, 0.66);
	}
	if (impact_level.x + impact_level.y > 0.001) {
		vec2 edges = abs((floor(UV / TEXTURE_PIXEL_SIZE) + 0.5) * TEXTURE_PIXEL_SIZE * 2.0 - 1.0);
		float distance_to_center = length(edges * vec2(0.82, 0.92));
		float edge = smoothstep(0.57, 1.18, distance_to_center + (threshold - 0.5) * 0.044);
		float low = edge * impact_level.y;
		pixel = mix(pixel, pixel * vec3(0.66, 0.32, 0.40) + vec3(0.22, 0.025, 0.062), low);
		pixel = mix(pixel, impact_color.rgb * 0.76 + pixel * 0.24, edge * impact_level.x * 0.68);
	}
	COLOR = vec4(pixel, 1.0);
}
