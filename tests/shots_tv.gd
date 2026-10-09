extends SceneTree
## Frames from the TV cameras (replay director, trackside, blimp...) during a
## race, to check nothing blocks the view: TRACK=n, CAMS="0,6" (replay cams).
##   OUT=/tmp/shots TRACK=2 xvfb-run ... godot --rendering-driver opengl3 -s tests/shots_tv.gd

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
	var cams: Array = Array(OS.get_environment("CAMS").split(",")) if OS.get_environment("CAMS") != "" else ["0", "6"]
	game.settings.weather = 0
	game.settings.weekend = 0
	game.settings.field = 0
	main.mode = "race"
	main.session = "race"
	main._use_track(tidx)
	main._enter_countdown()
	main.autopilot = true
	await _frames(60 * 40)
	main._enter_replay()
	for cs in cams:
		main.replay_cam = int(cs)
		main.replay_t = main.race.rec_times[0] + 2.0
		main.replay_rate = 1.0
		for k in 8:
			await _frames(150)
			await RenderingServer.frame_post_draw
			var name := "tv_t%d_c%s_%02d" % [tidx, cs, k]
			root.get_node("Game").screen_image(root).save_png(out.path_join(name + ".png"))
			print("saved ", name)
	quit(0)
