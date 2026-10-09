extends SceneTree
## The realism pass (what each renderer draws is in tests/shots_look.gd):
##   - car paint: the body's own shader (specular anti-aliasing, race wear), wear
##     building up as the car drives;
##   - reflection probes box-projected;
##   - the crowd in sections, near and far versions of each;
##   - the asphalt's own history in the wear overlay; worn painted lines;
##   - heat on Android: resolution steps down, comes back when cool;
##   - MetalFX only on iOS;
##   - the wet film: puddles and the mirror image (ULTRA, native only), the mirror
##     camera reflected in the surface;
##   - the browser renderer keeps its highlights (no colour-adjustment pass).
##   godot --headless --fixed-fps 60 -s tests/gfx_realism_test.gd


var main: Node
var game: Node
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _run() -> void:
	game = root.get_node("Game")
	var CarBody: Script = load("res://scripts/car_body.gd")
	var RainFx: Script = load("res://scripts/rain_fx.gd")
	for i in 20:
		await physics_frame
	main.clear_checkpoint()
	game.modern = true
	game.settings.length = 1
	game.settings.field = 0
	game.settings.weather = 0
	game.settings.weekend = 0
	game.settings.cautions = 0
	main.mode = "race"
	main.session = "race"
	main._use_track(1)
	main._enter_countdown()
	main.autopilot = true
	var race = main.race
	var p: Node3D = race.player
	while not race.running:
		await physics_frame

	# Paint.
	var body: Dictionary = p._body
	var fx = body.get("paint_fx")
	_check(fx is ShaderMaterial and fx.shader.resource_path.ends_with("car_paint.gdshader"), "the body's paint is its own shader")
	var on_both := true
	for l in body.lods:
		on_both = on_both and (l.mi as MeshInstance3D).get_surface_override_material(0) == fx
	_check(on_both, "on both the near and far body")
	var code: String = fx.shader.code
	_check(code.contains("CLEARCOAT_ROUGHNESS = spec_aa(") and code.contains("ROUGHNESS = spec_aa("), "the clear coat and the paint both get specular anti-aliasing")
	var other: Node3D = race.cars[1] if race.cars[0] == p else race.cars[0]
	_check(other._body.paint_fx != fx, "every car its own paint (its own wear)")
	for i in 60 * 20:
		await physics_frame
	print("   after 20 s: grime %.3f  rubber %.3f  bugs %.3f" % [p.paint_grime, p.paint_rubber, p.paint_bugs])
	_check(p.paint_grime > 0.0 and p.paint_rubber > 0.0 and p.paint_bugs > 0.0, "driving dirties the paint")
	_check(float(fx.get_shader_parameter("rubber")) > 0.0, "and the shader shows it")
	CarBody.set_wear(body, 0.5, 0.25, 0.1)
	_check(is_equal_approx(float(fx.get_shader_parameter("grime")), 0.5) and is_equal_approx(float(fx.get_shader_parameter("bugs")), 0.1), "set_wear sets the paint's wear")

	# Probes.
	var t: Node3D = main.track
	var probes := t.get_children().filter(func(n): return n is ReflectionProbe)
	_check(probes.size() >= 2 and probes.all(func(pr): return pr.box_projection), "reflection probes, box-projected (%d)" % probes.size())

	# Crowd.
	var near := 0
	var far := 0
	var near_fans := 0
	var far_fans := 0
	var ranges_ok := true
	for n in t.get_children():
		if n is MultiMeshInstance3D and String(n.name).begins_with("Crowd"):
			if String(n.name).ends_with("Far"):
				far += 1
				far_fans += n.multimesh.instance_count
				ranges_ok = ranges_ok and n.visibility_range_begin > 0.0
			else:
				near += 1
				near_fans += n.multimesh.instance_count
				ranges_ok = ranges_ok and n.visibility_range_end > 0.0
	print("   crowd: %d sections, %d fans" % [near, near_fans])
	_check(near >= 3 and near == far, "the crowd in sections, each near and far")
	_check(near_fans == far_fans and near_fans > 0, "the same fans in both")
	_check(ranges_ok, "near up close, far beyond")
	var crowd := t.get_children().filter(func(n): return n is MultiMeshInstance3D and String(n.name).begins_with("Crowd"))
	var tri := {}
	for n in crowd:
		tri["far" if String(n.name).ends_with("Far") else "near"] = n.multimesh.mesh.get_faces().size() / 3
	print("   a fan: %d triangles near, %d far" % [tri.get("near", 0), tri.get("far", 0)])
	_check(tri.get("far", 99) <= 10, "far fans are flat cut-outs")

	# The asphalt's history.
	var wmat: ShaderMaterial = t.wear._mat
	_check(is_equal_approx(float(wmat.get_shader_parameter("track_len")), float(t.length)), "the wear overlay knows the track's length (patches, seams in metres)")
	var line: Node = t.get_node_or_null("Surface_line")
	_check(line and line.material_override.albedo_texture != null, "painted lines worn")

	# Heat (Android).
	main.thermal_cap = 1.0
	main.apply_thermal(0.9, 0)
	main.apply_thermal(0.9, 0)
	_check(is_equal_approx(main.thermal_cap, 0.8), "hot: the resolution steps down")
	for i in 5:
		main.apply_thermal(0.99, 3)
	_check(is_equal_approx(main.thermal_cap, 0.6), "never below 60%")
	for i in 6:
		main.apply_thermal(0.5, 0)
	_check(is_equal_approx(main.thermal_cap, 0.7), "cool for 30 s: a step back up")
	main.thermal_cap = 1.0
	_check(not main.metalfx_active(), "MetalFX only on iOS")

	# Rain.
	var w = race.weather
	w.rain = 1.0
	for b in w.wet.size():
		w.wet[b] = 0.8
	for i in 90:
		await physics_frame
	var rf = main.rain_fx
	_check(rf != null and rf.film != null and rf.film.material_override.shader.resource_path.ends_with("wet_film.gdshader"), "the wet film: puddles and rain rings")
	var q_before: int = game.quality
	game.quality = 4
	_check(RainFx.mirror_allowed() == (game.forward_plus or game.mobile_renderer), "the mirror image on ULTRA, native renderers only")
	if rf:
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.global_transform = Transform3D(Basis.from_euler(Vector3(-0.3, 0.4, 0)), Vector3(3, 10, 2))
		rf._set_mirror(true, cam)
		rf._update_mirror(cam, null)
		var mc: Camera3D = rf.mirror_cam
		var ok: bool = mc.global_position.distance_to(Vector3(3, -10, 2)) < 1e-3 and mc.global_transform.basis.determinant() > 0.0
		# A point on the surface is seen the same place by both, upside down.
		var q := Vector3(4, 0, -12)
		var a: Vector2 = cam.unproject_position(q) / root.get_visible_rect().size
		var b: Vector2 = mc.unproject_position(q) / Vector2(rf.mirror_vp.size)
		print("   surface point on screen: main %s, mirror %s (flipped)" % [str(a), str(Vector2(b.x, 1.0 - b.y))])
		ok = ok and abs(a.x - b.x) < 0.01 and abs(a.y - (1.0 - b.y)) < 0.01
		_check(ok, "the mirror camera: reflected below the surface, picture upside down")
		rf._set_mirror(false, null)
		cam.queue_free()
	game.quality = q_before
	w.rain = 0.0

	# The browser renderer: no colour-adjustment pass (it renders into an 8-bit
	# buffer first, which clipped every highlight at 1.0: whites came out grey).
	var fp: bool = game.forward_plus
	var mob: bool = game.mobile_renderer
	game.forward_plus = false
	game.mobile_renderer = false
	main._apply_graphics()
	_check(not main.env.adjustment_enabled, "browser: highlights kept (no adjustment pass)")
	game.forward_plus = fp
	game.mobile_renderer = mob
	main._apply_graphics()
	_check(main.env.adjustment_enabled == (fp or mob), "desktop and phone apps keep their grade")
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)
