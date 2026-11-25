shader_type spatial;
render_mode specular_disabled;

// Timber, painted brickwork, shuttered concrete, oxidized sheet and painted trim.
uniform int finish;
uniform vec4 tone : source_color = vec4(1.0);
uniform sampler2D patina : repeat_enable, filter_linear_mipmap;
uniform vec4 bare_wood : source_color = vec4(.61, .56, .47, 1.0);
uniform vec4 clay : source_color = vec4(.54, .32, .23, 1.0);
uniform vec4 oxide : source_color = vec4(.49, .28, .16, 1.0);
uniform vec4 mortar : source_color = vec4(.56, .52, .45, 1.0);
uniform float ground_y;
uniform bool detached = false;
uniform mat4 rest_frame = mat4(1.0);
varying vec3 metres;
varying vec3 face;
varying vec3 surface_color;

void vertex() {
	mat4 frame = detached ? rest_frame : MODEL_MATRIX;
	metres = (frame * vec4(VERTEX, 1.0)).xyz;
	metres.y -= ground_y;
	face = normalize(mat3(frame) * NORMAL);
	vec3 v = COLOR.rgb;
	if (!OUTPUT_IS_SRGB) {
		v = mix(pow((v + .055) / 1.055, vec3(2.4)), v / 12.92, lessThan(v, vec3(.04045)));
	}
	surface_color = v * tone.rgb;
}

void fragment() {
	vec3 n = abs(face);
	bool horizontal = n.y > max(n.x, n.z);
	vec2 p = horizontal ? metres.xz : vec2(n.z >= n.x ? metres.x : metres.z, metres.y);
	float broad = texture(patina, p * vec2(.105, .12)).r;
	float runs = texture(patina, p * vec2(.82, .16) + vec2(.31, .15)).r;
	float flake = texture(patina, p * .94 + vec2(.16, .73)).r;
	float weather = .66 * broad + .24 * runs + .10 * flake;
	float dry = smoothstep(.35, .68, broad);
	float damp = horizontal ? 0.0 : 1.0 - smoothstep(.20, .68, metres.y + (broad - .50) * .64);
	float drip = smoothstep(.49, .79, runs) * (1.0 - .70 * dry);
	vec3 col = surface_color;
	if (finish == 0) {
		// Long grey fibres among strips of surviving varnish.
		float grain = texture(patina, p * vec2(.17, 2.71)).r;
		float silver = smoothstep(.34, .72, broad * .68 + grain * .32);
		col = mix(col, bare_wood.rgb, silver * .75);
		col *= .83 + .26 * grain - .19 * drip;
	} else if (finish == 1) {
		// At the ragged edge of the render a staggered bond and its chalky joints appear.
		float reveal = smoothstep(.56, .62, weather + .11 * damp);
		vec2 cell = p / vec2(.41, .155);
		cell.x += mod(floor(cell.y), 2.0) * .5;
		vec2 inside = min(fract(cell), 1.0 - fract(cell)) * vec2(.41, .155);
		float joint = min(inside.x, inside.y);
		float aa = clamp(max(fwidth(p.x), fwidth(p.y)), .001, .027);
		float brick = smoothstep(.005 - aa, .008 + aa, joint + (flake - .5) * .013);
		vec3 backing = mix(mortar.rgb * .82, clay.rgb * (.74 + .47 * flake), brick);
		col = mix(col, backing, reveal);
		col *= 1.02 - .29 * drip;
	} else if (finish == 2) {
		// Chalky bloom spreads over the damp wall; vertical runoff darkens the concrete.
		float lime = smoothstep(.34, .65, weather + .13 * damp);
		col = mix(col, mortar.rgb * 1.12, lime * .55);
		float form_joint = abs(fract(p.y / .76 + .5) - .5);
		col *= .97 - .32 * drip - .11 * (1.0 - smoothstep(.004, .023 + fwidth(p.y), form_joint));
	} else if (finish == 3) {
		// Orange runs extend beyond the dark centre of the oxidized patches.
		float rust = smoothstep(.51, .61, weather + drip * .22);
		float pit = smoothstep(.58, .68, weather);
		col = mix(col, oxide.rgb * (.91 + .27 * flake), .86 * rust);
		col *= 1.04 - .30 * pit - .13 * drip;
	} else {
		float rub = smoothstep(.55, .67, weather);
		col = mix(col, mortar.rgb, rub * .55);
		col *= 1.0 - .26 * drip;
	}
	col *= (.91 + .13 * flake) * (1.0 - damp * .26);
	ALBEDO = col;
	ROUGHNESS = .97;
}
