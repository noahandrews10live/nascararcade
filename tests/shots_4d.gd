extends SceneTree
## Screenshots of the in-race cameras (chase, bumper, cockpit) at speed, and a
## check that the camera feel leans the right way in a left turn.
##   OUT=/tmp/shots xvfb-run ... godot --rendering-driver vulkan -s tests/shots_4d.gd

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
	var tidx := int(OS.get_environment("TRACK")) if OS.get_environment("TRACK") != "" else 1
	await _frames(30)
	main._use_track(tidx)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true
	var rain := OS.get_environment("RAIN") == "1"
	await _frames(int(OS.get_environment("PREROLL")) if OS.get_environment("PREROLL") != "" else 600)
	var p = main.race.player
	# Sample the camera feel through a corner.
	var lat := 0.0
	var n := 0
	for i in 400:
		await process_frame
		if abs(p.v * p.r) > 8.0:
			lat += main.feel.off.x * sign(p.v * p.r)
			n += 1
	print("corner samples %d  head offset toward the outside %.3f m" % [n, lat / max(n, 1)])
	if out == "":
		quit(0)
		return
	if rain:
		var w = main.race.weather
		for i in w.wet.size():
			w.wet[i] = 0.9 if i != 3 and i != 4 else 0.35 # a drying line low down
		w.rain = 0.8
		w._rain_target = 0.8
		w.apply()
		await _frames(60)
	for m in [0, 1, 2, 3]:
		main.cam_mode = m
		await _frames(40)
		await _shot("%scam%d_%d" % ["rain_" if rain else "", m, tidx])
	quit(0)
