extends SceneTree
## The physics governor (race.gd's sim_level), level by level, in a 25-car race:
##   - each level costs less than the one before (the game's own time per frame);
##   - the racing doesn't change: the field's best laps within 1% of level 0, no
##     more spins or wrecks, nothing thrown off the world;
##   - a car stepped every other tick is drawn just as smoothly (it moves the same
##     distance every frame, not double on one frame and nothing on the next);
##   - the race starts at the level remembered from the last race;
##   - up to 8 catch-up physics ticks a frame (tests/realtime_check.gd measures
##     the race clock against the wall clock with a renderer).
##   godot --headless --fixed-fps 60 -s tests/sim_level_test.gd   (TRACK=n)

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


func _race(level: int, secs: float) -> Dictionary:
	game.sim_level = level
	game.settings.weekend = 0
	game.settings.weather = 0
	game.settings.cautions = 0
	game.settings.field = 1
	seed(1234)
	main.mode = "race"
	main.session = "race"
	main._use_track(int(OS.get_environment("TRACK")) if OS.get_environment("TRACK") != "" else 1)
	main._enter_countdown()
	main.autopilot = true
	while main.state != main.State.RACE:
		await process_frame
	var race = main.race
	var busy := 0.0
	var n := 0
	var spins := 0
	var outs := 0
	var bad := false
	var was_spin := {}
	# Smoothness: a car out in the field, its drawn position frame to frame.
	var jumps := []
	var watch: Node3D = null
	var last_pos := Vector3.ZERO
	while race.time < secs:
		await process_frame
		busy += main.frame_timer.busy_ms
		n += 1
		for c in race.cars:
			if is_nan(c.dist) or is_nan(c.v) or abs(c.global_position.y) > 400.0:
				bad = true
			if c.spinning and not was_spin.get(c, false):
				spins += 1
			was_spin[c] = c.spinning
		if race.time < 8.0:
			continue
		# Where each car is drawn this frame: between its physics states, as the
		# renderer sees it (main interpolates after this point in the frame).
		race.interpolate(0.5)
		if watch == null or watch.tick_span != 2:
			watch = null
			for c in race.cars:
				if not c.is_player and c.tick_span == 2:
					watch = c
					last_pos = c.global_position
					break
			continue
		var step: float = watch.global_position.distance_to(last_pos)
		var expect: float = watch.speed() / 60.0
		if expect > 0.5:
			jumps.append(step / expect)
			if abs(step / expect - 1.0) > 0.35 and OS.get_environment("DEBUG_JUMP") != "":
				print("   jump %.2f m (expect %.2f) span %d since %d t %.2f s %.1f" % [step, expect, watch.tick_span, Engine.get_physics_frames() - watch._tr_frame, race.time, watch.s()])
		last_pos = watch.global_position
	for c in race.cars:
		if c.out:
			outs += 1
	var bests := []
	for c in race.cars:
		if c.best_lap > 0.0 and not c.is_player:
			bests.append(c.best_lap)
	bests.sort()
	var med: float = bests[bests.size() / 2] if bests.size() > 0 else 0.0
	var worst_jump := 0.0
	for j in jumps:
		worst_jump = max(worst_jump, abs(j - 1.0))
	var res := {"busy": busy / max(n, 1), "spins": spins, "outs": outs, "bad": bad, "best": med, "jump": worst_jump, "level": race.sim_level, "watched": jumps.size()}
	main._enter_title()
	for i in 5:
		await process_frame
	return res


func _run() -> void:
	game = root.get_node("Game")
	for i in 20:
		await process_frame
	main.clear_checkpoint()
	var secs: float = float(OS.get_environment("SECONDS")) if OS.get_environment("SECONDS") != "" else 100.0
	var r := {}
	for level in [0, 1, 2]:
		r[level] = await _race(level, secs)
		print("   level %d: %.2f ms/frame, median best lap %.3f s, %d spins, %d out, worst frame-step error %.0f%% (%d frames watched)" % [
			level, r[level].busy, r[level].best, r[level].spins, r[level].outs, r[level].jump * 100.0, r[level].watched])
	for level in [0, 1, 2]:
		_check(r[level].level == level, "level %d: the race starts at the remembered level" % level)
		_check(not r[level].bad, "level %d: no NaNs, nothing thrown off the world" % level)
	for level in [1, 2]:
		_check(r[level].busy < r[level - 1].busy * 0.97, "level %d costs less than level %d (%.2f vs %.2f ms)" % [level, level - 1, r[level].busy, r[level - 1].busy])
		_check(r[0].best > 0.0 and abs(r[level].best - r[0].best) / r[0].best < 0.01, "level %d: the field's pace is the same (best lap %.3f vs %.3f s)" % [level, r[level].best, r[0].best])
		_check(r[level].spins <= r[0].spins + 2 and r[level].outs <= r[0].outs + 1, "level %d: no extra spins or wrecks (%d/%d vs %d/%d)" % [level, r[level].spins, r[level].outs, r[0].spins, r[0].outs])
		_check(r[level].watched > 100 and r[level].jump < 0.35, "level %d: a car stepped every other tick moves smoothly (worst %.0f%% off)" % [level, r[level].jump * 100.0])
	_check(r[2].busy < r[0].busy * 0.75, "the top level saves at least 25%% (%.2f -> %.2f ms)" % [r[0].busy, r[2].busy])
	_check(Engine.max_physics_steps_per_frame >= 8, "up to 8 catch-up physics ticks a frame: real time down to 7.5 fps")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
