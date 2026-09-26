shader_type spatial;
// A flag rippling as it's waved: travelling waves along the cloth, stronger at
// the free end. col_a/col_b with checks = 1 make the chequered flag.
render_mode cull_disabled;

uniform vec4 col_a : source_color = vec4(0.1, 0.75, 0.2, 1.0);
uniform vec4 col_b : source_color = vec4(0.1, 0.75, 0.2, 1.0);
uniform float checks = 0.0;

void vertex() {
	float free_end = UV.x;
	VERTEX.z += sin(UV.x * 9.0 - TIME * 14.0) * 0.07 * free_end + sin(UV.y * 5.0 + TIME * 9.0) * 0.03 * free_end;
}

void fragment() {
	vec2 g = floor(UV * vec2(6.0, 4.0));
	float c = mod(g.x + g.y, 2.0) * checks;
	ALBEDO = mix(col_a.rgb, col_b.rgb, c);
	ROUGHNESS = 0.9;
}
