// Sky for the Modern look: gradient sky, sun disk and glow, and a layer of
// fair-weather cumulus. Static (no TIME) so the reflection cubemap is only
// rebuilt when the track changes. Works on Forward+ and Compatibility.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.16, 0.34, 0.72);
uniform vec3 horizon : source_color = vec3(0.70, 0.80, 0.92);
uniform vec3 ground : source_color = vec3(0.25, 0.27, 0.22);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float energy = 1.0;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_seed = 0.0;
uniform bool night = false;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		// Sky gradient: bright, hazy horizon to a deep zenith.
		float t = pow(1.0 - h, 3.0);
		col = mix(zenith, horizon, t);
	} else {
		col = mix(horizon * 0.8, ground, clamp(-h * 6.0, 0.0, 1.0));
	}
	vec3 sd = LIGHT0_DIRECTION;
	float mu = LIGHT0_ENABLED ? dot(d, sd) : 0.0;
	if (!night) {
		// Mie-ish glow around the sun, plus the disk itself.
		col += sun_color * (pow(max(mu, 0.0), 8.0) * 0.35 + pow(max(mu, 0.0), 200.0) * 1.2);
		if (!AT_CUBEMAP_PASS && mu > 0.99965) {
			col += sun_color * 40.0;
		}
	} else if (!AT_CUBEMAP_PASS && h > 0.0) {
		// Stars.
		vec2 sp = d.xz / (h + 0.3) * 260.0;
		float s = hash(floor(sp));
		col += vec3(step(0.9975, s) * 1.5 * smoothstep(0.0, 0.2, h));
	}
	if (h > 0.0 && cloud_cover > 0.0) {
		// Clouds on a flat layer: project the view ray onto it.
		vec2 uv = d.xz / (h + 0.06) * 1.4 + vec2(cloud_seed, cloud_seed * 0.7);
		float n = fbm(uv, AT_CUBEMAP_PASS ? 3 : 6);
		float c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.28, n);
		c *= smoothstep(0.0, 0.12, h); // fade into the haze at the horizon
		// Lit tops and grey bases, brighter toward the sun.
		float lit = fbm(uv + sd.xz * 0.12, AT_CUBEMAP_PASS ? 2 : 4);
		vec3 cloud = night ? vec3(0.02, 0.025, 0.04)
			: mix(vec3(0.55, 0.58, 0.64), vec3(1.05, 1.02, 0.98), clamp((n - lit) * 3.0 + 0.6, 0.0, 1.0));
		cloud += sun_color * pow(max(mu, 0.0), 6.0) * 0.4 * (night ? 0.0 : 1.0);
		col = mix(col, cloud, c * 0.92);
	}
	COLOR = col * energy;
}
