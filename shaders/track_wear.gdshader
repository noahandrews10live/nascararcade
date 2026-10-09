shader_type spatial;
// A thin film over the racing surface, drawn in one pass:
//  - What the race does to it: rubber laid down by the field (R) and marbles
//    thrown off it (G), per cell of the track (see scripts/track_wear.gd).
//  - What years of racing did to it before today: sun-faded and fresher stretches,
//    tar-sealed paving joints and cracks, patched sections, dust and grit along the
//    edges where nobody drives. Fixed per track (seed), placed in metres along and
//    across the surface; seamless at the start/finish line.
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform sampler2D wear : filter_linear, repeat_disable;
uniform float track_len = 1000.0; // metres along (UV.y 0..1)
uniform float track_width = 16.0; // metres across (UV.x 0..1)
uniform float seed = 0.0;
uniform float age = 1.0; // 0: freshly repaved, 1: an old surface

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Noise over (along, across) in metres that wraps around the lap: "along" runs
// round a circle, so there's no seam at the line. `scale` is metres per cell.
float lap_noise(float v, float d, vec2 scale) {
	float r = track_len / (6.2831853 * scale.x);
	float a = v * 6.2831853;
	return vnoise(vec3(cos(a) * r, sin(a) * r, d / scale.y) + seed);
}

// A thin line (half-width w metres) at distance x, faded out where it's thinner
// than a pixel instead of shimmering.
float thin_line(float x, float w) {
	float fw = max(fwidth(x), 1e-4);
	return (1.0 - smoothstep(w - fw, w + fw, x)) * clamp(w * 2.0 / fw, 0.0, 1.0);
}

void over(inout vec4 film, inout float rough, vec3 col, float a, float r) {
	float na = film.a + (1.0 - film.a) * a;
	if (na > 1e-4) {
		film.rgb = mix(film.rgb, col, a / na);
		rough = mix(rough, r, a / na);
	}
	film.a = na;
}

void fragment() {
	float d = UV.x * track_width; // metres from the inside edge
	float s = UV.y * track_len; // metres along
	vec4 film = vec4(0.0);
	float rough = 0.82;
	// Faded (oxidised, grey) and fresher (dark) stretches, metres to tens of metres.
	float mac = lap_noise(UV.y, d, vec2(26.0, 9.0)) * 0.65 + lap_noise(UV.y, d, vec2(7.0, 3.0)) * 0.35;
	over(film, rough, vec3(0.30, 0.30, 0.29), smoothstep(0.55, 0.9, mac) * 0.22 * age, 0.9);
	over(film, rough, vec3(0.035, 0.035, 0.04), smoothstep(0.45, 0.12, mac) * 0.2 * age, 0.72);
	// Patches: every 70 m or so, a rectangle of newer asphalt with a sealed edge.
	float cell = floor(s / 70.0);
	float hp = hash(vec2(cell, seed));
	if (hp < 0.4 * age) {
		float ps = cell * 70.0 + 8.0 + hash(vec2(cell, seed + 1.0)) * 40.0;
		float pl = 4.0 + hash(vec2(cell, seed + 2.0)) * 9.0;
		float pw = 2.0 + hash(vec2(cell, seed + 3.0)) * 4.0;
		float pd = hash(vec2(cell, seed + 4.0)) * max(track_width - pw, 0.0);
		vec2 q = vec2(s - ps, d - pd);
		vec2 e = min(q, vec2(pl, pw) - q); // distance in from each edge
		float inside = step(0.0, min(e.x, e.y));
		over(film, rough, vec3(0.03, 0.03, 0.034), inside * 0.38, 0.7);
		over(film, rough, vec3(0.012, 0.012, 0.014), inside * thin_line(min(e.x, e.y), 0.05) * 0.75, 0.45);
	}
	// Paving joints run lengthways about a lane apart, sealed with tar in places.
	float wob = (vnoise(vec3(s * 0.08, d * 0.3, seed)) - 0.5) * 0.25;
	float lane = 3.7;
	float jd = abs(fract((d + wob) / lane + 0.5) - 0.5) * lane;
	float sealed = smoothstep(0.45, 0.65, lap_noise(UV.y, floor((d + wob) / lane + 0.5), vec2(40.0, 1.0)));
	float joint = thin_line(jd, 0.045) * sealed * age;
	// Cracks across the track, sealed: some 20 m cells have one, wandering and
	// stopping part way across.
	float cc = floor(s / 20.0);
	float crack = 0.0;
	if (hash(vec2(cc, seed + 7.0)) < 0.45 * age) {
		float cs = cc * 20.0 + 2.0 + hash(vec2(cc, seed + 8.0)) * 16.0;
		float cw = (vnoise(vec3(d * 0.6, cc, seed)) - 0.5) * 1.4;
		float span0 = hash(vec2(cc, seed + 9.0)) * track_width * 0.6;
		float span1 = span0 + track_width * (0.25 + 0.5 * hash(vec2(cc, seed + 10.0)));
		crack = thin_line(abs(s - cs - cw), 0.035) * step(span0, d) * step(d, span1);
	}
	over(film, rough, vec3(0.008, 0.008, 0.01), max(joint, crack) * 0.8, 0.4);
	// Dust and grit in the last metre or so at each edge, where no tyre cleans it.
	float edge = min(d, track_width - d);
	float dust = (1.0 - smoothstep(0.2, 1.4, edge + (vnoise(vec3(s * 0.4, d, seed)) - 0.5) * 0.8));
	over(film, rough, vec3(0.33, 0.31, 0.27), dust * 0.32, 0.95);

	// Today's race on top.
	vec2 w = texture(wear, UV).rg;
	// Marbles: loose specks, not a smooth stain.
	vec2 cellp = floor(UV2 * 14.0);
	float speck = step(0.55, hash(cellp)) * step(length(fract(UV2 * 14.0) - 0.5), 0.35);
	float rub = w.r * 0.42;
	float mar = w.g * speck * 0.9;
	over(film, rough, vec3(0.015, 0.015, 0.018), rub, 0.55); // the line polishes
	over(film, rough, vec3(0.05, 0.045, 0.04), mar, 0.95); // marbles are dull
	film.a = min(film.a, 0.9);
	if (film.a < 0.01) discard;
	ALBEDO = film.rgb;
	ROUGHNESS = rough;
	ALPHA = film.a;
}
