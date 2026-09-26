extends SceneTree
## Screenshots of a quick caution: the pit call screen and the line-up after it.
##   OUT=/tmp/shots xvfb-run ... godot --rendering-driver opengl3 --resolution 1600x720 -s tests/shots_caution.gd

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
	var game := root.get_node("Game")
	await _frames(30)
	game.settings.length = 1
	game.settings.field = 0
	game.settings.weekend = 0
	main.mode = "race"
	main.session = "race"
	main._use_track(1)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true
	await _frames(900)
	main.touch.active = true
	main.touch.visible = true
	main.race.player.tyre_wear = 0.35
	main.race.control.throw_caution("DEBRIS", null)
	main.autopilot = false
	main.race.player.autopilot_forced = false
	var w := 0
	while main.pit_menu == null and w < 600:
		await process_frame
		w += 1
	await _frames(10)
	await _shot("c1_pit_call")
	main._close_pit_menu()
	await _frames(60)
	await _shot("c2_lined_up")
	quit(0)
