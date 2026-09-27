extends SceneTree
## A lineup of the track people in each pose (screenshot with OUT=dir and a renderer).

const Person := preload("res://scripts/person.gd")
var out := OS.get_environment("OUT")


func _initialize() -> void:
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.6, 0.8)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment.ambient_light_energy = 0.6
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	sun.shadow_enabled = true
	w.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	w.add_child(ground)
	var poses := ["stand", "walk", "work", "wave", "cheer", "arms_up"]
	var cols := [Color(0.8, 0.1, 0.1), Color(0.1, 0.3, 0.8), Color(0.95, 0.75, 0.1), Color(0.1, 0.6, 0.2), Color(0.9, 0.9, 0.9), Color(0.2, 0.2, 0.2)]
	for i in poses.size():
		var p := Person.new()
		w.add_child(p)
		p.setup(cols[i], Color(1, 1, 1) if i != 4 else Color(0.1, 0.1, 0.6), "cap" if i % 2 else "helmet", i)
		p.pose = poses[i]
		p.position = Vector3(-3.75 + i * 1.5, 0, 0)
		p.rotation.y = 0.5 if i != 2 else -1.2
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.6, 5.2), Vector3(0, 0.9, 0))
	cam.fov = 60
	_run.call_deferred()


func _run() -> void:
	for i in 20:
		await process_frame
	if out != "":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("people.png"))
		print("saved people")
	quit(0)
