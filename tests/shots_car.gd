extends SceneTree
## Screenshots of the Modern car from the showroom's angles (front three-quarter,
## driver side, rear three-quarter, top, low front), plus the chase and cockpit
## views in a race.
##   OUT=/tmp/shots xvfb-run ... godot --rendering-driver opengl3 --resolution 1280x720 -s tests/shots_car.gd

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
	root.get_node("Game").screen_image(root).save_png(out.path_join(name + ".png"))
	print("saved ", name)


func _run() -> void:
	await _frames(30)
	main._use_track(1)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true
	await _frames(420)
	main.hud.visible = false
	main.cam_mode = 0
	await _frames(40)
	await _shot("car_chase")
	# Freeze the race and walk a camera round the player's car.
	main.race.process_mode = Node.PROCESS_MODE_DISABLED
	main.set_process(false)
	main.touch.visible = false
	var car: Node3D = main.race.player
	var cam: Camera3D = main.cam
	var fov := cam.fov
	cam.fov = 30.0
	var views := {"front": Vector3(4.6, 1.6, -5.2), "side": Vector3(-7.6, 1.1, -0.2), "rear": Vector3(3.0, 1.8, 6.2),
		"top": Vector3(0.8, 9.0, -0.6), "low": Vector3(2.6, 0.35, -5.4)}
	for k in views:
		var xf: Transform3D = car.model.global_transform
		var eye: Vector3 = xf * views[k]
		cam.global_transform = Transform3D(Basis(), eye).looking_at(xf * Vector3(0, 0.5, 0), xf.basis.y)
		await _frames(4)
		await _shot("car_" + k)
	cam.fov = fov
	main.race.process_mode = Node.PROCESS_MODE_INHERIT
	main.set_process(true)
	main.cam_mode = 3
	await _frames(40)
	await _shot("car_cockpit")
	quit(0)
