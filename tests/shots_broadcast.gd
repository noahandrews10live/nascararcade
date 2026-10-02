extends SceneTree
## Screenshots of the TV broadcast HUD in a race (OUT=dir, TRACK=n; needs a
## renderer, e.g. xvfb-run ... --rendering-driver opengl3).

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
	await _frames(20)
	var game := root.get_node("Game")
	game.settings.weather = 0
	game.settings.weekend = 0
	game.settings.field = 0
	game.settings.cautions = 1
	game.settings.tv_graphics = 1
	main.mode = "race"
	main.session = "race"
	main._use_track(int(OS.get_environment("TRACK")) if OS.get_environment("TRACK") != "" else 11)
	main._enter_countdown()
	main.autopilot = true
	while main.state != main.State.RACE:
		await process_frame
	for k in 3:
		await _frames(90)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("broadcast_%d.png" % k))
		print("saved ", k)
	main.race.control._end_stage()
	await _frames(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("broadcast_stage.png"))
	quit()
