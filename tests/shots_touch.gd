extends SceneTree
## Screenshots of a wide (phone-shaped) window with the touch controls showing:
## the title, track select, the race and the pause screen.
##   OUT=/tmp/shots xvfb-run ... godot --rendering-driver opengl3 --resolution 1600x720 -s tests/shots_touch.gd

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
	await _frames(60)
	main.touch.active = true
	main.touch.visible = true
	await _frames(10)
	await _shot("t1_title")
	main._enter_track_select()
	await _frames(20)
	await _shot("t2_track_select")
	main._use_track(1)
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true
	await _frames(400)
	main.autopilot = false
	main.race.player.ai = false
	await _frames(30)
	await _shot("t3_race")
	main.cam_mode = 3
	await _frames(30)
	await _shot("t4_cockpit")
	var e := InputEventAction.new()
	e.action = "pause"
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	e = InputEventAction.new()
	e.action = "pause"
	e.pressed = false
	Input.parse_input_event(e)
	await _frames(10)
	await _shot("t5_pause")
	quit(0)
