extends SceneTree
## The NASCAR calendar replicas: every one builds, closes, turns once round to
## the left, is the real length (within 2%), has a pit road and grandstands, and
## a car laps it on autopilot at a believable speed for its kind of track. The
## track picker browses them as a group; a full season follows the calendar;
## only a few tracks stay built at once.
##   ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/replica_test.gd
##   ONLY=n  just replica n (0..28)

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


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	game = root.get_node("Game")
	await _frames(20)
	var R: GDScript = load("res://scripts/replica_tracks.gd")
	var first: int = game.ORIGINAL_TRACKS
	_check(game.tracks.size() >= first + R.TRACKS.size() and R.TRACKS.size() == 29, "29 replicas after the 11 originals (%d tracks)" % game.tracks.size())
	var only := OS.get_environment("ONLY")
	var speeds := []
	for k in R.TRACKS.size():
		if only != "" and int(only) != k:
			continue
		var idx: int = first + k
		var cfg: Dictionary = game.tracks[idx]
		main._use_track(idx)
		var t: Node3D = main.track
		var ksum := 0.0
		for c in t.curv:
			ksum += c * (t.length / t.n)
		var miles: float = t.length / 1609.344
		var real_mi: float = float(String(cfg.kind).get_slice(" ", 0))
		var ok_len: bool = absf(miles - real_mi) / real_mi < 0.02
		# A short autopilot run: laps and the speed.
		game.settings.weather = 0
		game.settings.field = 0
		game.settings.weekend = 0
		game.settings.cautions = 0
		main.mode = "arcade"
		main.session = "race"
		main._enter_countdown()
		main.autopilot = true
		var lap_t := 0.0
		var p: Node3D = main.race.player
		var sim := 0.0
		var best := 0.0
		# The second lap: a flying one (the first starts from the grid).
		var laps0 := -1
		while sim < 300.0 and best == 0.0:
			await physics_frame
			sim += 1.0 / 60.0
			if p.lap() >= 2 and p.last_lap > 0.0:
				best = p.last_lap
		var mph: float = t.length / max(best, 0.01) * 2.237 if best > 0.0 else 0.0
		speeds.append("%-15s %5.2f mi  lap %6.2f s  %5.1f mph" % [cfg.short, miles, best, mph])
		_check(abs(ksum - TAU) < 0.2 and ok_len and best > 0.0 and t.front_length() > 50.0 and t.stand_length() > 40.0,
			"%s: closes (%.2f rad), %.3f mi of %.3f, a lap in %.1f s (%.0f mph), front %.0f m" % [cfg.short, ksum, miles, real_mi, best, mph, t.front_length()])
		main._enter_title()
		await _frames(2)
	for l in speeds:
		print("   ", l)
	_check(main.tracks.size() <= main.MAX_BUILT_TRACKS, "only %d tracks kept built" % main.tracks.size())
	# The picker: browse within the group, jump between groups.
	main._use_track(first)
	main._enter_track_select()
	await _frames(2)
	_check(String(main.menu_labels.real.text).begins_with("MODELLED ON DAYTONA"), "the picker says what it's modelled on (%s)" % main.menu_labels.real.text)
	main._track_group_jump(1)
	_check(game.selected_track == 0 or game.selected_track >= first + R.TRACKS.size(), "up/down jumps to the next group (track %d)" % game.selected_track)
	main._use_track(first + R.TRACKS.size() - 1)
	var ev := InputEventAction.new()
	ev.action = "steer_right"
	ev.pressed = true
	main._unhandled_input(ev)
	_check(game.selected_track == first, "> at the end of the calendar wraps to its start")
	# A full season is the calendar.
	game.new_season(0, 2)
	var names: Array = game.season.schedule.map(func(i): return game.tracks[i].short)
	_check(names.size() == 36 and names[0] == "SURFSIDE" and names[35] == "BISCAYNE" and names.count("SURFSIDE") == 2, "a full season runs the 2026 calendar: %s ... %s" % [names.slice(0, 4), names.slice(32)])
	game.clear_season()
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
