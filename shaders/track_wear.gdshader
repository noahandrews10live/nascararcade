shader_type spatial;
// Rubber laid down by the field (R) and marbles thrown off it (G), per cell of
// the track (see scripts/track_wear.gd). Drawn as a thin film over the asphalt.
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform sampler2D wear : filter_linear, repeat_disable;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 w = texture(wear, UV).rg;
	// Marbles: loose specks, not a smooth stain.
	vec2 cellp = floor(UV2 * 14.0);
	float speck = step(0.55, hash(cellp)) * step(length(fract(UV2 * 14.0) - 0.5), 0.35);
	float rub = w.r * 0.42;
	float mar = w.g * speck * 0.9;
	float a = clamp(rub + mar, 0.0, 0.9);
	if (a < 0.01) discard;
	ALBEDO = mix(vec3(0.015, 0.015, 0.018), vec3(0.05, 0.045, 0.04), mar / max(a, 0.001));
	ROUGHNESS = mix(0.55, 0.95, mar / max(a, 0.001)); // the line polishes, marbles are dull
	ALPHA = a;
}
