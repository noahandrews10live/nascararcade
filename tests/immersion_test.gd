extends SceneTree
## The "being there" systems in a real race:
##   - nearby cars get 3D engine voices; the echo rises by the grandstand;
##   - the camera head leans to the outside in the turns;
##   - the cockpit view puts the camera inside the car, with the interior shown;
##   - the line the field drives rubbers in (and grips more); marbles collect off it;
##   - the flagman shows yellow under caution; a crew works on a car in its box;
##   - rain lays a water film and spray behind cars at speed;
##   - rumble layers respond to the limit and to hits.
##   godot --headless --fixed-fps 60 -s tests/immersion_test.gd

var main: Node
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
		await physics_frame


func _run() -> void:
	var game := root.get_node("Game")
	await _frames(20)
	game.tracks[1].full_laps = 60
	game.settings.length = 1
	game.settings.field = 0
	game.settings.weather = 0
	game.settings.weekend = 0
	main.mode = "race"
	main.session = "race"
	main._use_track(1)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true
	var race = main.race
	var p = race.player
	await _frames(900)
	# --- sound
	var voices := 0
	for c in main.soundscape.assigned:
		if c != null:
			voices += 1
	print("   engine voices in use: %d  (state %s, playing %d)" % [voices, main.state, main.soundscape.players.filter(func(x): return x.playing).size()])
	_check(voices >= 3, "the cars around you have 3D engine voices")
	_check(main.soundscape.crowd.size() > 0, "the crowd is placed in the grandstand")
	# --- camera lean
	main.cam_mode = 0
	var lean := 0.0
	var n := 0
	for i in 600:
		await process_frame
		if abs(p.v * p.r) > 8.0:
			lean += main.feel.off.x * sign(p.v * p.r)
			n += 1
	print("   head offset to the outside of the turns: %.3f m (%d samples)" % [lean / max(n, 1), n])
	_check(n > 20 and lean / n > 0.01, "the camera leans to the outside in the turns")
	# --- cockpit
	main.cam_mode = 3
	await _frames(10)
	await process_frame
	main._update_camera(1.0 / 60.0) # measure right after the camera update
	var local_eye: Vector3 = main.cockpit.global_transform.affine_inverse() * main.cam.global_position
	var inside_dist: float = local_eye.distance_to(main.cockpit.EYE)
	_check(main.cockpit != null and main.cockpit.visible, "the cockpit interior is shown in the cockpit view")
	_check(inside_dist < 0.3, "the cockpit camera sits in the driver's seat (%.2f m from the eye point)" % inside_dist)
	main.cam_mode = 0
	await _frames(5)
	await process_frame
	_check(not main.cockpit.visible, "the interior is hidden again outside the cockpit view")
	# --- the rubber line
	await _frames(60 * 150)
	var wear = race.wear
	var best_band := 0
	var best := -1.0
	var row_s: float = race.track.length * 0.25 # into turn 1-2
	var hw: float = race.track.width * 0.5
	for b in wear.BANDS:
		var d: float = -hw + (b + 0.5) / wear.BANDS * race.track.width
		var r: float = wear.rubber_at(row_s, d)
		if r > best:
			best = r
			best_band = b
	var d_line: float = -hw + (best_band + 0.5) / wear.BANDS * race.track.width
	var d_off: float = hw - 0.5 if d_line < 0.0 else -hw + 0.5
	var g_line: float = race.track.grip_at(row_s, d_line)
	var g_off: float = race.track.grip_at(row_s, d_off)
	var marb := 0.0
	for r in wear.rows:
		for b in wear.BANDS:
			marb = max(marb, wear.marbles[r * wear.BANDS + b])
	print("   rubber on the line %.2f at d=%.1f  grip on line %.3f vs off line %.3f  most marbles %.2f" % [best, d_line, g_line, g_off, marb])
	_check(best > 0.2, "the line the cars drive is rubbering in")
	_check(g_line > g_off, "the rubbered line grips more than the rest")
	_check(marb > 0.02, "marbles collect off the line")
	# --- the flagman and the crews
	race.control.throw_caution("DEBRIS (TEST)", null)
	await _frames(30)
	await process_frame
	var fc: Array = main.race_day._flag_colours()
	_check((fc[0] as Color).is_equal_approx(Color(1.0, 0.85, 0.05)), "the flagman shows the yellow under caution")
	var saw_crew := false
	for i in 60 * 120:
		await physics_frame
		for cr in main.race_day.crews:
			if cr[0].visible:
				saw_crew = true
		if saw_crew:
			break
	_check(saw_crew, "a pit crew goes over the wall for a stop")
	# --- rain
	var w = race.weather
	for i in w.wet.size():
		w.wet[i] = 0.9
	w.rain = 0.8
	w._rain_target = 0.8
	await _frames(180)
	if main.rain_fx == null:
		print("   (the 1999 look has no rain effects; skipped)")
	var spraying := 0
	if main.rain_fx:
		var emitters: Array = main.rain_fx.spray if not main.rain_fx.spray.is_empty() else main.rain_fx.spray_cpu
		for e in emitters:
			if e.emitting:
				spraying += 1
		_check(main.rain_fx.film != null and main.rain_fx.film.visible, "rain lays a film of water on the track")
		print("   cars throwing spray: %d" % spraying)
		_check(spraying > 0, "cars at speed throw up spray")
	# --- rumble layers
	var calm: Dictionary = main.haptics(p, 0.1)
	p.scrub = 1.0
	p.wall_hit = 12.0
	var busy: Dictionary = main.haptics(p, 0.1)
	_check(busy.weak > calm.weak and busy.strong > calm.strong, "rumble rises at the grip limit and on hits")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
