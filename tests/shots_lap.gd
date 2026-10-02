extends SceneTree
## Frames from the race camera around a lap (autopilot), to see what the player
## sees: TRACK=n picks the track, CAM=n the camera, EVERY seconds between shots.
##   OUT=/tmp/shots TRACK=2 xvfb-run ... godot --rendering-driver opengl3 -s tests/shots_lap.gd

var main: Node
var out := OS.get_environment("OUT")


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await _frames(30)
	var game := root.get_node("Game")
	var tidx := int(OS.get_environment("TRACK")) if OS.get_environment("TRACK") != "" else 2
	var every := float(OS.get_environment("EVERY")) if OS.get_environment("EVERY") != "" else 2.5
	var shots := int(OS.get_environment("SHOTS")) if OS.get_environment("SHOTS") != "" else 14
	game.settings.weather = 0
	main.mode = "race"
	main.session = OS.get_environment("SESSION") if OS.get_environment("SESSION") != "" else "practice"
	game.settings.weekend = 0
	game.settings.field = 0
	main._use_track(tidx)
	main._enter_countdown()
	main.autopilot = true
	await _frames(int(OS.get_environment("WAIT")) if OS.get_environment("WAIT") != "" else 240)
	if OS.get_environment("CAM") != "":
		main.cam_mode = int(OS.get_environment("CAM"))
	for k in shots:
		await _frames(int(every * 60.0))
		await RenderingServer.frame_post_draw
		var p: Node3D = main.race.player
		var name := "lap_t%d_%02d" % [tidx, k]
		root.get_texture().get_image().save_png(out.path_join(name + ".png"))
		print("saved %s  s=%.0f d=%.1f" % [name, p.s(), p.d])
	quit(0)
