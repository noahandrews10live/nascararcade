shader_type spatial;
// Standing water on the racing surface (scripts/rain_fx.gd): a thin glossy film
// that follows the weather's wet bands across the track (the cars dry a line),
// puddles where water collects (more toward the low side of the banking), rings
// from the raindrops while it's raining, and, on ULTRA, a real mirror image of the
// world in it (a second camera below the track, see rain_fx.gd).
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

uniform sampler2D bands : filter_linear, repeat_disable; // alpha: wetness per band
uniform float band_count = 8.0;
uniform float rain = 0.0; // falling now, 0..1
uniform float track_width = 16.0;
uniform float seed = 0.0;
uniform sampler2D reflection : filter_linear, repeat_disable, hint_default_black;
uniform float planar = 0.0; // 0: off (the probes and sky reflect), 1: mirror image

varying vec2 m; // metres (across from the inside edge, along)

void vertex() {
	m = UV2;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise2(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float w = texture(bands, vec2(UV.x / band_count, 0.5)).a;
	float d = m.x;
	float s = m.y;
	// Puddles: patches metres long in the low spots; banking drains water to the
	// inside, so they gather there first.
	float pn = vnoise2(vec2(s / 9.0, d / 3.0) + seed) * 0.7 + vnoise2(vec2(s / 2.5, d / 1.2) + seed * 1.7) * 0.3;
	float low_side = 1.0 - smoothstep(0.0, track_width * 0.4, d);
	float puddle = smoothstep(0.66 - 0.2 * low_side - 0.15 * w, 0.76 - 0.2 * low_side - 0.15 * w, pn) * smoothstep(0.3, 0.75, w);
	float a = max(clamp(w * 1.1, 0.0, 0.85), puddle * 0.95);
	if (a < 0.01) discard;
	// Raindrop rings: one drop per 40 cm cell at a time, each ring spreading and
	// fading; tilts the water's normal (only while it's raining, mostly in puddles).
	vec3 n = NORMAL;
	if (rain > 0.02) {
		vec2 p = vec2(d, s) * 2.5;
		vec2 cell = floor(p);
		vec2 f = fract(p);
		float ph = hash2(cell + seed);
		float t = fract(TIME * (0.8 + 0.4 * ph) + ph);
		vec2 c = vec2(hash2(cell + 3.1), hash2(cell + 7.7)) * 0.6 + 0.2;
		vec2 dv = f - c;
		float r = length(dv);
		float ring = sin((r - t * 0.45) * 55.0) * exp(-abs(r - t * 0.45) * 28.0) * (1.0 - t);
		vec2 tilt = dv / max(r, 1e-3) * ring * 0.35 * rain * (0.4 + 0.6 * puddle);
		n = normalize(n + (VIEW_MATRIX * vec4(tilt.x, 0.0, tilt.y, 0.0)).xyz);
	}
	NORMAL = n;
	ALBEDO = vec3(0.03, 0.035, 0.04);
	ROUGHNESS = mix(0.05, 0.02, puddle);
	SPECULAR = 1.0;
	if (planar > 0.0) {
		// The mirror camera's picture, upside down, wobbled by the water.
		vec2 uv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y) + n.xz * 0.03;
		float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 5.0);
		EMISSION = texture(reflection, uv).rgb * fres * planar * (0.5 + 0.5 * puddle);
	}
	ALPHA = a;
}
