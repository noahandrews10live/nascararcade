extends SceneTree
## Runs an arcade race on autopilot, opens the replay and screenshots it (needs a renderer).
var main: Node
var out := OS.get_environment("OUT")


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)


func _run() -> void:
	for i in 30:
		await process_frame
	main.mode = "arcade"
	main._use_track(7)
	main._enter_countdown()
	main.autopilot = true
	var t := 0.0
	while main.state != main.State.RESULTS and t < 400.0:
		await physics_frame
		t += 1.0 / 60.0
	print("results reached: ", main.state == main.State.RESULTS, " frames recorded: ", main.race.rec_times.size())
	await _shot("rp0_results")
	main._enter_replay()
	for i in 600:
		await physics_frame
	await _shot("rp1_tv")
	main.replay_cam = 1
	main.replay_rate = 2.0
	for i in 300:
		await physics_frame
	await _shot("rp2_chase")
	quit()
