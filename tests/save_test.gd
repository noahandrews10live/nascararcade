extends SceneTree
## SAVE mode (running lean, lift and coast), measured: your car alone on track, laps with it
## off and then on. Saving must burn clearly less fuel and wear the tyres less,
## for a real but modest cost in lap time; the crew chief's numbers come from
## what the car actually burned.
##   godot --headless --fixed-fps 60 -s tests/save_test.gd   (TRACK=n)

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


## Laps with `saving` as given: fuel and rear-tyre wear per lap, the average lap.
func _laps(p: Node3D, saving: bool, laps: int) -> Dictionary:
	p.saving = saving
	var start_lap: int = p.lap()
	while p.lap() == start_lap:
		await physics_frame
	var f0: float = p.fuel
	var w0: float = p.tyre_wear4[2] + p.tyre_wear4[3]
	var t0: float = main.race.time
	var l0: int = p.lap()
	while p.lap() < l0 + laps:
		await physics_frame
	return {"fuel": (f0 - p.fuel) / laps, "wear": (p.tyre_wear4[2] + p.tyre_wear4[3] - w0) / laps, "lap": (main.race.time - t0) / laps}


func _run() -> void:
	game = root.get_node("Game")
	for i in 20:
		await physics_frame
	main.clear_checkpoint()
	game.settings.weather = 0
	game.settings.weekend = 0
	main.mode = "race"
	main.session = "practice"
	main._use_track(int(OS.get_environment("TRACK")) if OS.get_environment("TRACK") != "" else 1)
	main._enter_countdown()
	main.autopilot = true
	while main.state != main.State.RACE:
		await physics_frame
	var p: Node3D = main.race.player
	if main.crew_watch == null:
		# (practice has no crew chief of its own: the test brings one to measure)
		main.crew_watch = load("res://scripts/crew_watch.gd").new()
		main.add_child(main.crew_watch)
		main.crew_watch.begin(main.race)
	await _laps(p, false, 1) # (a flying lap first)
	var off: Dictionary = await _laps(p, false, 3)
	var on: Dictionary = await _laps(p, true, 3)
	print("   off: %.3f L/lap, rear wear %.5f/lap, %.2f s/lap" % [off.fuel, off.wear, off.lap])
	print("   on:  %.3f L/lap, rear wear %.5f/lap, %.2f s/lap" % [on.fuel, on.wear, on.lap])
	print("   per km: %.3f L/km (lap length %.0f m)" % [off.fuel / (main.race.track.length / 1000.0), main.race.track.length])
	_check(abs(p.fuel_lap - off.fuel) / off.fuel < 0.15, "the car measures its own fuel per lap (%.3f L)" % p.fuel_lap)
	var fuel_cut: float = 1.0 - on.fuel / off.fuel
	var wear_cut: float = 1.0 - on.wear / max(off.wear, 1e-9)
	var cost: float = on.lap - off.lap
	print("   saving: %.0f%% less fuel, %.0f%% less rear wear, %.2f s a lap slower" % [fuel_cut * 100.0, wear_cut * 100.0, cost])
	_check(fuel_cut > 0.1, "SAVE burns clearly less fuel (%.0f%%)" % (fuel_cut * 100.0))
	_check(wear_cut > 0.0, "and wears the rears less (%.0f%%)" % (wear_cut * 100.0))
	_check(cost > 0.05 and cost < off.lap * 0.05, "for a real but modest cost (%.2f s a lap, %.1f%%)" % [cost, cost / off.lap * 100.0])
	# The crew chief's numbers: fuel per lap as measured.
	var cw: Node = main.crew_watch
	if cw and cw.has_method("fuel_per_lap"):
		var fpl: float = cw.fuel_per_lap(p, false)
		var fps: float = cw.fuel_per_lap(p, true)
		print("   crew chief: %.3f L/lap normal, %.3f saving" % [fpl, fps])
		_check(abs(fpl - off.fuel) / off.fuel < 0.15 and abs(fps - on.fuel) / on.fuel < 0.15, "the crew chief's fuel numbers are what the car burned")
	else:
		_check(false, "crew chief has fuel_per_lap")
	# The call: a run a lap short at normal pace, but saving makes it.
	if cw:
		var race = main.race
		p.saving = false
		var per: float = cw.fuel_per_lap(p, false)
		var to_go := 12
		race.laps = p.lap() + to_go
		p.fuel = per * (to_go - 1.0)
		cw.log.clear()
		cw._level.clear()
		for i in 120:
			await physics_frame
		var said := ""
		for e in cw.log:
			said += String(e.text) + " | "
		print("   crew chief: %s" % said)
		_check(said.contains("SAVE AND WE MAKE IT"), "a lap short: the crew chief says saving makes it")
		p.saving = true
		p.fuel = per * (to_go + 3.0)
		cw._level.clear()
		for i in 120:
			await physics_frame
		said = ""
		for e in cw.log:
			said += String(e.text) + " | "
		_check(said.contains("RACE IT"), "and once there's enough, to race it")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
