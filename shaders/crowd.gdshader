shader_type spatial;
// The grandstand crowd (one MultiMesh). Fans shuffle while seated, stand and
// jump when something happens (excitement), and run a Mexican wave round the
// stands under caution.
render_mode cull_back;

uniform float excitement : hint_range(0.0, 1.0) = 0.0;
uniform float wave : hint_range(0.0, 1.0) = 0.0;
uniform float modern = 1.0;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	float id = float(INSTANCE_ID);
	float ph = hash(id) * 6.2831;
	vec3 inst = MODEL_MATRIX[3].xyz;
	float lift = 0.0;
	// A little life all the time.
	lift += 0.02 * sin(TIME * (1.0 + hash(id + 3.0)) + ph);
	// On their feet, bouncing, when the race gives them something.
	float up = smoothstep(0.1, 0.5, excitement * (0.6 + 0.4 * hash(id + 7.0)));
	lift += up * (0.25 + 0.3 * max(0.0, sin(TIME * (7.0 + 3.0 * hash(id + 1.0)) + ph)));
	// The wave: a band of standing fans running along the stand.
	float along = inst.x * 0.7 + inst.z * 0.7;
	float band = smoothstep(0.85, 1.0, sin(along * 0.05 - TIME * 2.2));
	lift += wave * band * 0.5;
	// Arms up with the lift: stretch the top of the body.
	VERTEX.y += lift * (0.6 + 0.4 * step(0.7, VERTEX.y));
}

void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = modern > 0.5 ? c * c : c; // vertex colours are sRGB in the Modern look
	ROUGHNESS = 0.85;
}
