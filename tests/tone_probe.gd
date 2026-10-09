extends SceneTree
## Measures the picture's tone curve on the renderer it runs on: a row of patches
## of known brightness (emission 0.05 .. 16, unlit) through the game's own
## environment, read back as 0..255. Run once per renderer and compare:
##   xvfb-run -a godot --rendering-method mobile --resolution 1280x720 -s tests/tone_probe.gd
## (TONE_ENV=game uses main.gd's environment for a day track; HDR2D=1 turns on
## the viewport's HDR 2D first.) Prints one line: "tone <renderer> v0 v1 ...".

const LEVELS := [0.05, 0.1, 0.2, 0.35, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 16.0]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 20:
		await process_frame
	main._use_track(1)
	for i in 5:
		await process_frame
	if OS.get_environment("HDR2D") == "1":
		root.use_hdr_2d = true
	# Hide the world: only the patches, in front of the camera, on black.
	for c in main.get_children():
		if c is Node3D:
			c.visible = false
	var env: Environment = main.env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.fog_enabled = false
	env.glow_enabled = false
	env.ssao_enabled = false
	env.ssr_enabled = false
	env.volumetric_fog_enabled = false
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	main.sun.visible = false
	if OS.get_environment("GLOW") == "1":
		env.glow_enabled = true
	if OS.get_environment("NO_ADJ") == "1":
		env.adjustment_enabled = false
	var holder := Node3D.new()
	root.add_child(holder)
	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.current = true
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 16.0
	cam.position = Vector3(0, 0, 10)
	for k in LEVELS.size():
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.0, 1.0)
		q.mesh = qm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.BLACK
		m.metallic_specular = 0.0
		m.emission_enabled = true
		m.emission = Color.WHITE
		m.emission_energy_multiplier = LEVELS[k]
		q.material_override = m
		q.position = Vector3(-13.0 + k * 2.0, 0, 0)
		holder.add_child(q)
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_node("Game").screen_image(root)
	var vals := []
	var sz := img.get_size()
	for k in LEVELS.size():
		var world := Vector3(-13.0 + k * 2.0, 0, 0)
		var sp := cam.unproject_position(world)
		var px := Vector2i(int(sp.x * sz.x / root.get_visible_rect().size.x), int(sp.y * sz.y / root.get_visible_rect().size.y))
		var c := img.get_pixelv(px.clamp(Vector2i.ZERO, sz - Vector2i.ONE))
		vals.append(int(round(c.g * 255.0)))
	var game: Node = root.get_node("Game")
	var r := "forward_plus"
	if game.mobile_renderer:
		r = "mobile"
	elif not game.forward_plus:
		r = "compatibility"
	print("tone %s exp %.2f white %.1f hdr2d %s: %s" % [r, env.tonemap_exposure, env.tonemap_white, str(root.use_hdr_2d), " ".join(vals.map(func(x): return str(x)))])
	quit()
