extends SceneTree
## Close-ups of the track surfaces (asphalt, apron, wall, infield grass) from a
## camera parked by the track in daylight, and a broadcast-height view.
##   OUT=/tmp/shots xvfb-run ... godot --rendering-driver opengl3 -s tests/shots_surface.gd

var main: Node
var out := OS.get_environment("OUT")


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)


func _run() -> void:
	var game: Node = root.get_node("Game")
	print("modern look: ", game.modern, "  photo asphalt: ", game._photo("asphalt"))
	await _frames(30)
	main.mode = "race"
	main.session = "practice"
	main._use_track(int(OS.get_environment("TRACK")) if OS.get_environment("TRACK") != "" else 0)
	main._enter_countdown()
	await _frames(90)
	main.hud.visible = false
	var tr = main.track
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.fov = 60.0
	var i := 40
	var hw: float = tr.width * 0.5
	var P := func(j: int, lat: float, up: float) -> Vector3:
		return tr.to_global(tr._pt(j % tr.n, lat) + Vector3.UP * up)
	var views := {
		"surface_low": [P.call(i, 2.0, 1.2), P.call(i + 12, -1.0, 0.0)],
		"surface_wall": [P.call(i, hw - 4.0, 1.5), P.call(i + 10, hw + 0.5, 0.6)],
		"surface_infield": [P.call(i, -hw + 1.0, 3.0), P.call(i + 10, -hw - 30.0, 0.0)],
		"surface_tv": [P.call(i, hw + 30.0, 35.0), P.call(i + 25, 0.0, 0.0)],
	}
	for k in views:
		cam.global_position = views[k][0]
		cam.look_at(views[k][1], Vector3.UP)
		await _frames(20)
		await _shot(k)
	quit(0)
