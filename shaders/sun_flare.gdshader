shader_type spatial;
// Sun glare: a soft bloom round the sun, a horizontal streak and a few ghosts
// reflected through the centre of the lens. Drawn on a card in front of the
// camera; hidden when anything (a grandstand, a car, the cockpit roof) covers
// the sun, found by sampling the depth buffer at the sun's position.
render_mode unshaded, blend_add, depth_test_disabled, cull_disabled, skip_vertex_transform, fog_disabled;

uniform vec2 sun_uv = vec2(0.5);
uniform float strength = 0.0;
uniform vec3 tint = vec3(1.0, 0.92, 0.8);
uniform float aspect = 1.333;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

float sky_at(vec2 uv) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0.0;
	float d = texture(depth_tex, uv).r;
	// Reversed-Z on Forward+ (far = 0); the Compatibility renderer uses far = 1.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return d > 0.9999 ? 1.0 : 0.0;
#else
	return d < 0.0001 ? 1.0 : 0.0;
#endif
}

void fragment() {
	if (strength <= 0.0) discard;
	// How much of the sun disc is uncovered (five taps).
	float o = 0.006;
	float vis = (sky_at(sun_uv) + sky_at(sun_uv + vec2(o, 0.0)) + sky_at(sun_uv - vec2(o, 0.0))
		+ sky_at(sun_uv + vec2(0.0, o)) + sky_at(sun_uv - vec2(0.0, o))) / 5.0;
	vis *= strength;
	if (vis <= 0.001) discard;
	vec2 uv = SCREEN_UV;
	vec2 d = (uv - sun_uv) * vec2(aspect, 1.0);
	float r = length(d);
	vec3 c = tint * (0.12 * exp(-r * 12.0) + 0.8 * exp(-r * 45.0));
	// Anamorphic streak.
	c += tint * 0.12 * exp(-abs(d.y) * 180.0) * exp(-abs(d.x) * 2.5);
	// Ghosts along the line through the centre.
	vec2 axis = vec2(0.5) - sun_uv;
	for (int i = 1; i <= 4; i++) {
		float k = float(i) * 0.55;
		vec2 g = (uv - (sun_uv + axis * k)) * vec2(aspect, 1.0);
		float size = 0.03 + 0.02 * float(i % 3);
		float ring = smoothstep(size, size * 0.7, length(g));
		vec3 gc = mix(vec3(0.5, 0.8, 1.0), vec3(1.0, 0.6, 0.3), fract(k));
		c += gc * ring * 0.05;
	}
	ALBEDO = c * vis;
}
