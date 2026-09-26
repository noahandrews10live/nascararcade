// Camera motion blur. A full-screen card in front of the camera reconstructs each
// pixel's world position from depth, finds where it was on screen last frame
// (previous view-projection matrix, set from GDScript) and blurs along that path.
// Things moving with the camera (your car) stay sharp; the world streaks past.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform mat4 prev_view_proj;
uniform float amount = 0.5;
uniform int samples = 8;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view /= view.w;
	vec4 world = INV_VIEW_MATRIX * view;
	vec4 prev = prev_view_proj * world;
	prev.xyz /= prev.w;
	vec2 prev_uv = prev.xy * 0.5 + 0.5;
	vec2 vel = (SCREEN_UV - prev_uv) * amount;
	// Cap the streak so fast camera swings don't smear the whole screen.
	float len = length(vel);
	if (len > 0.04) {
		vel *= 0.04 / len;
	}
	vec3 col = vec3(0.0);
	for (int i = 0; i < samples; i++) {
		float t = float(i) / float(samples - 1) - 0.5;
		col += textureLod(screen_tex, SCREEN_UV - vel * t, 0.0).rgb;
	}
	ALBEDO = col / float(samples);
}
