extends SceneTree
## Captures screenshots of each game state (needs a real renderer, e.g. xvfb-run):
##   OUT=/tmp/shots godot --fixed-fps 60 --path . -s tests/screenshots.gd

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
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("saved ", name)


func _run() -> void:
	var only := OS.get_environment("TRACK")
	await _frames(90)
	await _shot("01_title")
	main._enter_track_select()
	await _frames(20)
	await _shot("02_track_select")
	main._enter_car_select()
	await _frames(20)
	await _shot("03_car_select")
	if OS.get_environment("MODE") == "race":
		main.mode = "race"
		root.get_node("Game").tracks[int(only if only != "" else "1")].race_laps = 20
	for idx in root.get_node("Game").tracks.size():
		if only != "" and int(only) != idx:
			continue
		main._use_track(idx)
		main._enter_countdown()
		if main.mode == "race":
			main.autopilot = true
			await _frames(700)
			await _shot("r%d_a_green" % idx)
			main.race.control.throw_caution("DEBRIS (TEST)", null)
			await _frames(240)
			await _shot("r%d_b_caution" % idx)
			main.cam_mode = 1
			await _frames(1500)
			await _shot("r%d_c_caution_later" % idx)
			await _frames(1500)
			await _shot("r%d_d_later" % idx)
			quit(0)
			return
		main.autopilot = true
		await _frames(100)
		await _shot("t%d_a_countdown" % idx)
		await _frames(500)
		await _shot("t%d_b_race_chase" % idx)
		main.cam_mode = 1
		await _frames(300)
		await _shot("t%d_c_race_near" % idx)
		main.cam_mode = 2
		await _frames(200)
		await _shot("t%d_d_race_bumper" % idx)
		main.cam_mode = 0
		main.autopilot = false
		main._enter_title()
		await _frames(5)
	quit(0)
