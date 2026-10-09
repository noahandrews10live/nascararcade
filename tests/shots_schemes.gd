extends SceneTree
## Every paint scheme on a line of cars, three-quarter and side views
## (screenshots with OUT=dir and a renderer).

var Car: GDScript
var out := OS.get_environment("OUT")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var g: Node = root.get_node("Game")
	Car = load("res://scripts/car.gd")
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
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.3, 0.32)
	fl.material_override = fm
	w.add_child(fl)
	var n: int = 7
	for k in n:
		var t: Dictionary = g.teams[k].duplicate()
		t["scheme"] = k
		t["make"] = k % 4
		var c: Node3D = Car.new()
		w.add_child(c)
		c.setup(t, null)
		c.position = Vector3(-10.5 + k * 3.5, 0, 0)
		c.rotation.y = -0.5
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.fov = 50
	cam.look_at_from_position(Vector3(0, 5.5, 17), Vector3(0, 0.6, 0))
	for i in 15:
		await process_frame
	await _shot("schemes_all")
	# Close side views of three.
	for k in [2, 4, 5]:
		var x: float = -10.5 + k * 3.5
		cam.fov = 40
		cam.look_at_from_position(Vector3(x + 5.2, 1.4, -3.0), Vector3(x, 0.6, 0))
		for i in 4:
			await process_frame
		await _shot("scheme_%d" % k)
	quit(0)


func _shot(name: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	root.get_node("Game").screen_image(root).save_png(out.path_join(name + ".png"))
	print("saved ", name)
