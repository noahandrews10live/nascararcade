// Exhaust heat shimmer: a camera-facing card that bends the image behind it.
// Strength is set per car (instance uniform) from throttle and speed.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
instance uniform float strength = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	// Billboard around the card's own centre.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	// Soft oval falloff, strongest near the exhaust (bottom of the card).
	vec2 c = UV * 2.0 - 1.0;
	float fall = clamp(1.0 - dot(c * vec2(1.0, 0.8), c * vec2(1.0, 0.8)), 0.0, 1.0) * smoothstep(-1.0, 0.2, c.y);
	vec2 flow = vec2(noise(UV * vec2(9.0, 5.0) + vec2(0.0, TIME * 4.0)), noise(UV * vec2(7.0, 6.0) - vec2(TIME * 3.0, 0.0))) - 0.5;
	vec2 offs = flow * 0.012 * strength * fall;
	ALBEDO = textureLod(screen_tex, SCREEN_UV + offs, 0.0).rgb;
	ALPHA = step(0.001, strength * fall);
}
