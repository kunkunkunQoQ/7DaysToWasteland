shader_type canvas_item;
render_mode unshaded;

uniform sampler2D ink_layer : hint_screen_texture, filter_nearest, repeat_disable;
uniform float strength : hint_range(0.0,0.8) = 0.44;

void fragment() {
	vec2 xy = SCREEN_UV;
	vec2 sx = vec2(SCREEN_PIXEL_SIZE.x,0.0);
	vec2 sy = vec2(0.0,SCREEN_PIXEL_SIZE.y);
	vec4 center = textureLod(ink_layer,xy,0.0);
	vec4 frosted = center;
	if (strength > 0.001) {
		vec4 haze = center * 0.35;
		haze += (textureLod(ink_layer,xy-sx,0.0)+textureLod(ink_layer,xy+sx,0.0)
			+textureLod(ink_layer,xy-sy,0.0)+textureLod(ink_layer,xy+sy,0.0))*0.125;
		haze += (textureLod(ink_layer,xy-sx-sy,0.0)+textureLod(ink_layer,xy+sx-sy,0.0)
			+textureLod(ink_layer,xy-sx+sy,0.0)+textureLod(ink_layer,xy+sx+sy,0.0))*0.0375;
		frosted = mix(center,haze,strength);
	}
	if (frosted.a > 0.0001) {
		frosted.rgb /= frosted.a;
	}
	COLOR *= frosted;
}
