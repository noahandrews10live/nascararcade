extends SceneTree
## Screenshots of pit road and the player's stop (OUT=dir, TRACK=n; needs a
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


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("pit_%s.png" % name))
	print("saved ", name)


func _run() -> void:
	await _frames(20)
	var game := root.get_node("Game")
	game.settings.weather = 0
	game.settings.weekend = 0
	game.settings.field = 0
	game.settings.cautions = 1
	main.mode = "race"
	main.session = "race"
	main._use_track(int(OS.get_environment("TRACK")) if OS.get_environment("TRACK") != "" else 1)
	main._enter_countdown()
	main.autopilot = true
	while main.state != main.State.RACE:
		await process_frame
	var t: Node3D = main.track
	var ctl: Node = main.race.control
	# Overview of pit entry: barrier nose, attenuator, the lanes.
	var cam := Camera3D.new()
	root.add_child(cam)
	await _frames(30)
	for spot in [] if OS.get_environment("STOP_ONLY") != "" else [["entry", t.pit_in_s() - 110.0, 30.0, 14.0], ["road", t.pit_in_s() + 40.0, 18.0, 9.0], ["exit", t.pit_out_s() + 30.0, -35.0, 12.0]]:
		var s: float = fposmod(spot[1], t.length)
		var base: Vector3 = t.global_transform * t.surface_point(s, t.pit_lane_d() + 2.0)
		var fwd: Vector3 = t.fwd_at(s)
		var right: Vector3 = t.right_at(s)
		cam.global_position = base - fwd * float(spot[2]) - right * 10.0 + Vector3.UP * float(spot[3])
		cam.look_at(base + fwd * 25.0, Vector3.UP)
		cam.make_current()
		main.paused = true
		await _frames(4)
		await _shot(spot[0])
	cam.clear_current()
	main.paused = false
	# The player's stop.
	var p: Node3D = main.race.player
	p.want_pit = true
	p.pit_plan = "4"
	var took := {}
	var k := 0
	while k < 60 * 120:
		await process_frame
		k += 1
		if p.pit_state == 2 and t.in_pit_zone(p.s()) and not took.has("lane"):
			took["lane"] = true
			await _shot("lane")
		if p.pit_state == 3 and p.pit_timer < 6.0 and not took.has("stop"):
			took["stop"] = true
			await _shot("stop")
		if took.has("stop") and p.pit_state == 0:
			break
	await _frames(20)
	await _shot("summary")
	# A quick-caution replay.
	p.set_meta("stop", {"total": 11.0, "tyre_t": 9.0, "fuel_t": 7.0, "repair": 2.0, "corners": [0, 1, 2, 3], "fuel_add": 0.5, "wedge": 1})
	main.pit_show.start_show(p)
	await _frames(150)
	await _shot("replay")
	quit()
