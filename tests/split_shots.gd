extends SceneTree
## Two-player split screen: both cars on autopilot, screenshot + reaches results.
var main: Node
var out := OS.get_environment("OUT")


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node("Game")
	for i in 30:
		await process_frame
	var saved: Dictionary = game.settings.duplicate()
	game.settings.length = 0
	game.settings.field = 0
	main.mode = "2p"
	main.team2 = 1
	main._use_track(2)
	main._enter_countdown()
	main.autopilot = true
	print("split views: ", main.split_cams.size(), " player2: ", main.race.player2 != null)
	if out != "":
		for i in 900:
			await physics_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("split.png"))
		print("saved split")
		game.settings = saved
		quit()
		return
	var t := 0.0
	while main.state != main.State.RESULTS and t < 1500.0:
		await physics_frame
		t += 1.0 / 60.0
	print("results: ", main.state == main.State.RESULTS, "  P1 ", game.ordinal(main.race.position_of(main.race.player)), "  P2 ", game.ordinal(main.race.position_of(main.race.player2)))
	game.settings = saved
	game.save_settings()
	quit()
