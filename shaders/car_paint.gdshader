shader_type spatial;
// The car body in the modern look: the livery (vertex colours) under a gloss
// clear coat, like StandardMaterial3D's "livery" set-up, plus two things a
// standard material can't do:
//  - Specular anti-aliasing. A 5 cm-wide car far down the straight turns a sharp
//    clear-coat highlight into a pixel that flickers on and off. Where the surface
//    curves faster than a pixel (the normal changes quickly across the screen) the
//    highlight is widened just enough to cover the pixel (Kaplanyan & Hoffman /
//    Tokuyoshi: roughness from the screen-space variance of the normal, capped).
//    The phone and desktop renderers' own roughness limiter only touches the base
//    roughness, not the clear coat, and the browser renderer has none.
//  - Race wear: dirt and brake dust low down, tyre rubber flicked onto the sides
//    behind the wheels, and a film of bugs on the nose, building up lap by lap.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float metallic = 0.15;
uniform float roughness = 0.28;
uniform float clearcoat = 1.0;
uniform float clearcoat_roughness = 0.05;
// Specular AA: how much the normal's screen-space change widens the highlight,
// and the most it may add (alpha^2 units, as in Godot's own limiter).
uniform float spec_aa_variance = 0.25;
uniform float spec_aa_limit = 0.18;
// Wear, 0..1 each (set from the race: laps run, contact, the pits wipe the nose).
uniform float grime = 0.0;
uniform float rubber = 0.0;
uniform float bugs = 0.0;
// The body's extent in its own space (nose at min z), for placing the wear.
uniform vec3 body_min = vec3(-1.0, 0.0, -2.6);
uniform vec3 body_max = vec3(1.0, 1.3, 2.6);
// Wheel centres along the body (front, rear), for the rubber behind each wheel.
uniform vec2 wheel_z = vec2(-1.43, 1.36);
uniform bool srgb_colors = true;
// Multiplies the livery (the showroom paints a grey car in).
uniform vec4 tint : source_color = vec4(1.0);

varying vec3 lp; // position on the body
varying vec3 ln; // normal on the body

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
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

vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

// Widens a perceptual roughness by the pixel's normal variance (capped).
float spec_aa(float r, vec3 n) {
	vec3 du = dFdx(n);
	vec3 dv = dFdy(n);
	float variance = spec_aa_variance * (dot(du, du) + dot(dv, dv));
	float kernel = min(2.0 * variance, spec_aa_limit);
	float a = r * r;
	return sqrt(sqrt(clamp(a * a + kernel, 0.0, 1.0)));
}

void fragment() {
	vec3 col = (srgb_colors ? to_linear(COLOR.rgb) : COLOR.rgb) * tint.rgb;
	float rough = roughness;
	float cc = clearcoat;
	float cc_rough = clearcoat_roughness;
	vec3 size = max(body_max - body_min, vec3(0.01));
	float h = (lp.y - body_min.y) / size.y; // 0 at the sill, 1 at the roof
	float fwd = (body_max.z - lp.z) / size.z; // 1 at the nose
	if (grime + rubber + bugs > 0.001) {
		float n1 = vnoise(lp * 7.0);
		float n2 = vnoise(lp * 23.0 + 11.0);
		// Road dirt and brake dust: thick along the sills, thinning up the doors,
		// streaked backwards by the air.
		float low = 1.0 - smoothstep(0.08, 0.5, h + (n1 - 0.5) * 0.25);
		float streak = vnoise(vec3(lp.x * 3.0, lp.y * 18.0, lp.z * 1.2));
		float dirt = grime * clamp(low * (0.55 + 0.6 * streak) + grime * 0.12 * n1, 0.0, 1.0);
		col = mix(col, vec3(0.16, 0.135, 0.11), dirt * 0.75);
		rough = mix(rough, 0.75, dirt);
		cc *= 1.0 - dirt * 0.85;
		// Rubber off the tyres: dark specks on the lower sides, densest behind
		// each wheel.
		float side = smoothstep(0.55, 0.85, abs(ln.x));
		float behind = max(1.0 - abs(lp.z - wheel_z.x - 0.55) * 2.2, 1.0 - abs(lp.z - wheel_z.y - 0.55) * 2.2);
		float speck = step(0.78 - 0.18 * rubber, n2) * step(h, 0.55);
		float rub = rubber * side * clamp(behind, 0.0, 1.0) * speck;
		col = mix(col, vec3(0.02, 0.02, 0.022), rub);
		rough = mix(rough, 0.9, rub);
		cc *= 1.0 - rub;
		// Bugs: a speckled film on the nose and the leading edges.
		float front = smoothstep(0.82, 0.98, fwd) * smoothstep(0.2, 0.7, -ln.z);
		float bug = bugs * front * step(0.62, n2) * (0.6 + 0.4 * n1);
		col = mix(col, vec3(0.22, 0.2, 0.12), bug * 0.8);
		cc_rough = mix(cc_rough, 0.5, bug);
	}
	ALBEDO = col;
	METALLIC = metallic;
	ROUGHNESS = spec_aa(rough, NORMAL);
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = spec_aa(cc_rough, NORMAL);
}
