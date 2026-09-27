extends SceneTree
## The Modern car on its own in a plain showroom, from the study's camera angles
## (front three-quarter, driver side, rear three-quarter, top, low front).
##   OUT=/tmp/shots xvfb-run ... godot --rendering-driver opengl3 --resolution 1280x720 -s tests/shots_showroom.gd

var out := OS.get_environment("OUT")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.3, 0.31, 0.33)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.77, 0.8)
	e.ambient_light_energy = 0.6
	e.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-58), deg_to_rad(35), 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.33, 0.35)
	fm.roughness = 0.35
	floor.material_override = fm
	world.add_child(floor)
	var car := Node3D.new()
	world.add_child(car)
	var team := {"c1": Color(0.07, 0.07, 0.08), "c2": Color(0.07, 0.07, 0.08), "cn": Color(0.07, 0.07, 0.08), "num": "", "sponsor": "", "make": int(OS.get_environment("MAKE")) if OS.get_environment("MAKE") != "" else 0}
	var CB = load("res://scripts/car_body.gd")
	var info = CB.build(car, team, car)
	if OS.get_environment("DENT") == "1":
		CB.dent(info, {"front": 0.6, "rear": 0.0, "left": 0.0, "right": 0.5}, 1)
	var cam := Camera3D.new()
	cam.fov = 30.0
	world.add_child(cam)
	cam.current = true
	var views := {"front": Vector3(4.6, 1.6, -5.2), "side": Vector3(-7.6, 1.1, -0.2), "rear": Vector3(3.0, 1.8, 6.2),
		"top": Vector3(0.8, 9.0, -0.6), "low": Vector3(2.6, 0.35, -5.4)}
	for k in views:
		cam.global_transform = Transform3D(Basis(), views[k]).looking_at(Vector3(0, 0.5, 0), Vector3.UP)
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("show%s_%s.png" % [OS.get_environment("MAKE"), k]))
		print("saved ", k)
	quit(0)
