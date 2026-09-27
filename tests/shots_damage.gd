extends SceneTree
## A wrecked car: dents, loose bodywork and tyre-rub smoke (screenshot with OUT=dir).

var out := OS.get_environment("OUT")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var g: Node = root.get_node("Game")
	var Car: GDScript = load("res://scripts/car.gd")
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.62, 0.78)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.77, 0.8)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	sun.shadow_enabled = true
	w.add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	fl.mesh = pm
	w.add_child(fl)
	var c: Node3D = Car.new()
	w.add_child(c)
	c.setup(g.teams[1], null)
	c.damage = {"front": 0.8, "rear": 0.7, "left": 0.2, "right": 0.75}
	c.v = 30.0
	c._update_damage_visual()
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.fov = 45
	for k in 2:
		cam.look_at_from_position(Vector3(4.8, 1.6, -4.2) if k == 0 else Vector3(-3.5, 1.7, 5.2), Vector3(0, 0.5, 0))
		for i in 40:
			c._update_fx(1.0 / 30.0)
			await process_frame
		if out != "":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("damage_%d.png" % k))
			print("saved damage_", k)
	quit(0)
