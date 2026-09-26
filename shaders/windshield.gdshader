shader_type spatial;
// Rain on the glass: beads that refract the view, running back and up the
// screen with speed, cleared by a wiper sweep. Drawn on a card in front of the
// camera (cockpit and bumper views; a few drops on the lens for chase cams).
render_mode unshaded, depth_test_disabled, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.0;   // 0 dry .. 1 pouring
uniform float speed = 0.0;    // 0 .. 1.2 (car speed / 90 m/s)
uniform float wipe = -1.0;    // wiper angle 0..1 while sweeping, <0 parked
uniform float time_s = 0.0;
uniform float density = 1.0;  // fewer drops on a camera lens
uniform float refill = 1.0;   // after a wipe the glass fills up again

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// One layer of drops on a grid; returns the refraction offset and a mask.
vec3 drops(vec2 uv, float scale, float t, float streak) {
	vec2 g = uv * scale;
	g.y += t * streak; // wind carries them up the glass at speed
	vec2 cell = floor(g);
	vec2 f = fract(g) - 0.5;
	vec2 h = hash2(cell);
	if (h.x > amount * density * 0.9) return vec3(0.0);
	vec2 c = (h - 0.5) * 0.6;
	vec2 d = f - c;
	d.y /= 1.0 + streak * 0.6; // stretched into streaks
	float r = 0.08 + 0.1 * h.y;
	float m = smoothstep(r, r * 0.6, length(d));
	// Each drop lives a while, then a new one lands.
	float life = fract(t * 0.3 + h.x * 7.0);
	m *= smoothstep(0.0, 0.1, life) * smoothstep(1.0, 0.7, life);
	return vec3(d * m * 0.5, m);
}

void fragment() {
	if (amount <= 0.01) discard;
	vec2 uv = SCREEN_UV;
	vec2 asp = vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
	vec3 a = drops(uv * asp, 18.0, time_s, 1.0 + speed * 6.0);
	vec3 b = drops(uv * asp + 3.1, 34.0, time_s * 1.3, 1.0 + speed * 9.0);
	vec2 off = a.xy + b.xy * 0.6;
	float m = max(a.z, b.z) * refill;
	off *= refill;
	// The wiper blade pivots at the bottom centre and clears what it passes.
	if (wipe >= 0.0) {
		vec2 p = (uv - vec2(0.5, 1.05)) * asp;
		float ang = atan(p.x, -p.y); // -1.2 .. 1.2 across the glass
		float blade = mix(-1.3, 1.3, wipe);
		float cleared = smoothstep(0.0, 0.25, (blade - ang));
		m *= 1.0 - cleared * 0.95;
		off *= 1.0 - cleared * 0.95;
	}
	if (m < 0.01) discard;
	vec3 col = texture(screen_tex, uv + off * 0.06).rgb;
	col = mix(col, col * 1.15 + 0.03, m * 0.5); // beads catch a little light
	ALBEDO = col;
	ALPHA = clamp(m * 1.2, 0.0, 1.0);
}
