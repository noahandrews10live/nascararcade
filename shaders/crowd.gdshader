shader_type spatial;
// The grandstand crowd (MultiMeshes, one per section of the stands, near and far
// versions of the fan). Fans shuffle while seated, stand, raise their arms and
// jump when something happens (excitement), and run a Mexican wave round the
// stands under caution.
// The mesh's vertex alpha says which part of the fan a vertex is: 1 shirt (the
// instance colour), 0.75 arm (shirt sleeve), 0.5 skin, 0 hair or cap. Skin, hair
// and caps are picked per fan from its instance id.
render_mode cull_back;

uniform float excitement : hint_range(0.0, 1.0) = 0.0;
uniform float wave : hint_range(0.0, 1.0) = 0.0;
uniform float modern = 1.0;

varying float part;
varying vec3 shirt;
varying flat float fan;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	// Each fan's own dice, from where they sit (the instance ids restart in
	// every section of the stands).
	vec3 inst = MODEL_MATRIX[3].xyz;
	float id = floor(fract(dot(inst, vec3(0.1731, 0.0517, 0.1913))) * 9973.0);
	fan = id;
	part = COLOR.a;
	shirt = COLOR.rgb;
	float ph = hash(id) * 6.2831;
	float lift = 0.0;
	// A little life all the time.
	lift += 0.02 * sin(TIME * (1.0 + hash(id + 3.0)) + ph);
	// On their feet, bouncing, when the race gives them something.
	float up = smoothstep(0.1, 0.5, excitement * (0.6 + 0.4 * hash(id + 7.0)));
	lift += up * (0.25 + 0.3 * max(0.0, sin(TIME * (7.0 + 3.0 * hash(id + 1.0)) + ph)));
	// The wave: a band of standing fans running along the stand.
	float along = inst.x * 0.7 + inst.z * 0.7;
	float band = smoothstep(0.85, 1.0, sin(along * 0.05 - TIME * 2.2));
	float waving = wave * band;
	lift += waving * 0.5;
	// Arms go up with them: swing each arm about its shoulder.
	float arms = max(up * step(0.5, hash(id + 5.0)), waving);
	if (abs(part - 0.75) < 0.1) {
		VERTEX.y = mix(VERTEX.y, 1.36 - VERTEX.y, arms);
		VERTEX.x *= 1.0 + arms * 0.25;
	}
	VERTEX.y += lift;
}

void fragment() {
	float id = fan;
	vec3 c = shirt;
	if (part < 0.25) {
		// Hair (black, brown, blond, grey) or a cap in a team's colour.
		float h = hash(id + 11.0);
		if (hash(id + 13.0) < 0.4) {
			c = vec3(hash(id + 17.0), hash(id + 19.0), hash(id + 23.0));
			c = mix(vec3(0.15), c, 0.85);
		} else {
			c = h < 0.45 ? vec3(0.06, 0.05, 0.045) : (h < 0.75 ? vec3(0.28, 0.18, 0.1) : (h < 0.9 ? vec3(0.75, 0.62, 0.38) : vec3(0.6, 0.6, 0.58)));
		}
	} else if (part < 0.6) {
		float t = hash(id + 29.0);
		c = t < 0.45 ? vec3(0.94, 0.78, 0.66) : (t < 0.7 ? vec3(0.8, 0.6, 0.46) : (t < 0.87 ? vec3(0.62, 0.43, 0.3) : vec3(0.38, 0.25, 0.18)));
	}
	ALBEDO = modern > 0.5 ? c * c : c; // the colours are sRGB in the Modern look
	ROUGHNESS = 0.85;
}
