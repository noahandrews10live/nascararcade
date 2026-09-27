extends SceneTree
## Screenshots of the showtime moments: the intro (three beats), the showroom,
## a race with the TV package, a wreck replay and victory lane; plus checks that
## each one starts and hands back cleanly.
##   OUT=/tmp/shots xvfb-run ... godot --rendering-driver opengl3 --resolution 1280x720 -s tests/shots_wow.gd

var main: Node
var out := OS.get_environment("OUT")
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Wait until `cond` holds (at most `limit` frames).
func _until(cond: Callable, limit := 3000) -> void:
	var n := 0
	while not cond.call() and n < limit:
		await process_frame
		n += 1


func _race_secs(s: float) -> void:
	var t0: float = main.race.time
	await _until(func(): return main.race.time - t0 >= s, 20000)


func _shot(name: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)


func _run() -> void:
	var st = main.showtime
	await _frames(5)
	_check(st.intro_active, "the intro plays when the game starts")
	await _until(func(): return st.intro_t > 2.0)
	await _shot("w1_intro_heli")
	await _until(func(): return st.intro_t > 6.0)
	await _shot("w2_intro_trackside")
	await _until(func(): return st.intro_t > 10.3)
	await _shot("w3_intro_logo")
	await _until(func(): return not st.intro_active)
	await _frames(3)
	_check(not st.intro_active and main.ui_root.modulate.a > 0.99, "the intro hands over to the title")
	main.mode = "race"
	main._enter_track_select()
	main._enter_car_select()
	await _frames(40)
	_check(st.showroom != null and st.showroom.visible, "car select is in the showroom")
	await _shot("w4_showroom")
	# A race.
	var game := root.get_node("Game")
	game.settings.weekend = 0
	game.settings.field = 0
	main.session = "race"
	main._use_track(1)
	main._enter_countdown()
	main.autopilot = true
	await _until(func(): return main.state == main.State.RACE, 20000)
	await _race_secs(25.0)
	await _shot("w5_race_tv")
	_check(st._ticker.visible and st._ticker.text.length() > 10, "the running-order ticker is on screen")
	# A wreck replay.
	var victim: Node3D = main.race.order[3]
	st._on_incident(victim, "out")
	await _until(func(): return st.replay_active, 400)
	await _frames(30)
	_check(st.replay_active, "a big wreck is replayed")
	await _shot("w6_replay")
	var hold: float = main.race.time
	await _frames(20)
	_check(is_equal_approx(main.race.time, hold), "the race holds during the replay")
	var guard := 0
	while st.replay_active and guard < 60 * 30:
		await process_frame
		guard += 1
	_check(not st.replay_active, "the replay hands back to the live race")
	await _frames(20)
	_check(main.race.time > hold, "the race runs again after the replay")
	# Victory lane.
	main._set_state(main.State.FINISHED)
	st.start_victory(main.race.player)
	await _until(func(): return st._v_t > st.VIC_LANE + 2.0, 6000)
	_check(st.victory_active and st._v_stage != null, "victory lane is built for a win")
	await _shot("w7_victory")
	await _until(func(): return not st.victory_active, 6000)
	await _frames(3)
	_check(not st.victory_active and main.state == main.State.RESULTS, "victory lane hands over to the results")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
