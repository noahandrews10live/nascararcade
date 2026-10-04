extends SceneTree
## The tire report and the advanced garage:
##   - camber shows in the tread temperatures: MORE runs the inside hot (and
##     the report says take some out), LESS runs it cooler across;
##   - pressures show in the middle against the edges: HIGH right pressures
##     crown the right sides (too much air), LOW heats the edges (too little);
##   - in practice the report comes up every few laps by itself, and on demand;
##   - the advanced page (shocks, camber, track bar) sets the car;
##   - under caution the pit call can move the track bar.
##   godot --headless --fixed-fps 60 -s tests/tyre_report_test.gd

var main: Node
var game: Node
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _laps(p: Node3D, n: int) -> void:
	var l0: int = p.lap()
	while p.lap() < l0 + n:
		await physics_frame


## A setup on the car (as the garage leaves it), reset tyres, a few laps, the read.
func _run_with(p: Node3D, changes: Dictionary) -> Dictionary:
	for k in changes:
		game.setup[k] = changes[k]
	game.apply_setup(p)
	for i in 4:
		p.tread_io[i] = 0.0
		p.tread_crown[i] = 0.0
	await _laps(p, 3)
	var r: Dictionary = main.TyreReport.read(p)
	for k in changes:
		game.setup[k] = 1
	return r


func _run() -> void:
	game = root.get_node("Game")
	for i in 20:
		await physics_frame
	main.clear_checkpoint()
	game.settings.weather = 0
	game.settings.weekend = 0
	main.mode = "race"
	main.session = "practice"
	main._use_track(1)
	main._enter_countdown()
	main.autopilot = true
	while main.state != main.State.RACE:
		await physics_frame
	var p: Node3D = main.race.player
	await _laps(p, 1)

	# 1. Practice: the report every few laps by itself.
	var seen := false
	var l0: int = p.lap()
	while p.lap() < l0 + main.PRACTICE_REPORT_EVERY + 1:
		await physics_frame
		seen = seen or main.tyre_panel.visible
	_check(seen, "in practice the tire report comes up by itself every %d laps" % main.PRACTICE_REPORT_EVERY)

	# 2. Camber.
	var std: Dictionary = await _run_with(p, {})
	var more: Dictionary = await _run_with(p, {"camber": 2})
	var less: Dictionary = await _run_with(p, {"camber": 0})
	print("   RF inside-outside: less %.1f, standard %.1f, more %.1f C" % [less.io[1], std.io[1], more.io[1]])
	print("   standard: %s (fronts-rears %.1f C)" % [str(std.advice), std.balance])
	print("   more camber: %s" % str(more.advice))
	_check(more.io[1] > std.io[1] + 3.0 and std.io[1] > less.io[1] + 1.5, "camber shows across the tread: more camber, hotter inside")
	_check(abs(std.io[1]) < main.TyreReport.IO_HOT, "the standard setup reads about even across the RF")
	_check(str(more.advice).contains("INSIDE HOT") and str(more.advice).contains("TOO MUCH CAMBER"), "MORE camber: the report says take some out")

	# 3. Pressures.
	var hi: Dictionary = await _run_with(p, {"psi_r": 2})
	var lo: Dictionary = await _run_with(p, {"psi_r": 0})
	print("   right-side crown: low %.1f, standard %.1f, high %.1f C" % [(lo.crown[1] + lo.crown[3]) * 0.5, (std.crown[1] + std.crown[3]) * 0.5, (hi.crown[1] + hi.crown[3]) * 0.5])
	print("   high right air: %s" % str(hi.advice))
	_check(str(hi.advice).contains("TOO MUCH AIR - LOWER THE RIGHT"), "HIGH right pressures: hot in the middle, too much air")
	_check(str(lo.advice).contains("TOO LITTLE AIR - RAISE THE RIGHT"), "LOW right pressures: hot on the edges, too little air")
	_check(not str(std.advice).contains("AIR"), "standard pressures: no pressure call")

	# 4. On demand.
	main.tyre_panel.visible = false
	main.show_tyre_report()
	await process_frame
	_check(main.tyre_panel.visible and not main.tyre_panel.report.is_empty(), "the report on demand (Y / TIRE REPORT)")

	# 5. The advanced page sets the car.
	game.setup.camber = 2
	game.setup.shocks = 0
	game.setup.track_bar = 2
	game.apply_setup(p)
	_check(p.camber_scale > 1.2 and p.damp_scale < 0.9 and p.track_bar == 1.0, "the advanced page: camber, shocks and track bar on the car")
	main._enter_garage_advanced()
	var ids: Array = main.menu.rows.map(func(r): return r.get("id", ""))
	_check(ids.has("shocks") and ids.has("camber") and ids.has("track_bar"), "the advanced garage page has shocks, camber and the track bar")
	game.setup.camber = 1
	game.setup.shocks = 1
	game.setup.track_bar = 1
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
