extends SceneTree
## Replays after a race: the director cuts between cars and shots, highlights
## play clip by clip and return to the results, photo mode freezes and resumes.
##   godot --headless --fixed-fps 60 -s tests/director_test.gd

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


func _run() -> void:
	for i in 20:
		await physics_frame
	var game := root.get_node("Game")
	game.tracks[2].full_laps = 40
	game.settings.length = 1
	game.settings.field = 0
	game.settings.weather = 0
	game.settings.weekend = 0
	main.mode = "race"
	main.session = "race"
	main._use_track(2)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true
	var sim := 0.0
	while main.state != main.State.RESULTS and sim < 900.0:
		await physics_frame
		sim += 1.0 / 60.0
	_check(main.state == main.State.RESULTS, "race reaches results")
	# Make sure there's something to highlight.
	var race: Node3D = main.race
	race.highlights.append({"t": race.rec_times[race.rec_times.size() / 2], "car": 3, "kind": "SPIN"})
	main._enter_replay()
	var focuses := {}
	var shots := {}
	for i in 60 * 40:
		await physics_frame
		focuses[main.replay_focus] = true
		shots[main._dir_shot] = true
	print("   director used %d cars and %d kinds of shot in 40 s" % [focuses.size(), shots.size()])
	_check(focuses.size() >= 3, "the director cuts between cars")
	_check(shots.size() >= 3, "the director mixes camera shots")
	# Photo mode freezes the replay and gives it back.
	var t0: float = main.replay_t
	main._enter_photo()
	for i in 30:
		await physics_frame
	_check(main.photo_mode and abs(main.replay_t - t0) < 0.01, "photo mode freezes the moment")
	main._exit_photo()
	for i in 30:
		await physics_frame
	_check(not main.photo_mode and main.replay_t > t0, "leaving photo mode resumes the replay")
	# Highlights: back to the results at the end of the reel.
	main._set_state(main.State.RESULTS)
	main._enter_highlights()
	var clips: int = main._hl_clips.size()
	sim = 0.0
	while main.state == main.State.REPLAY and sim < 300.0:
		await physics_frame
		sim += 1.0 / 60.0
	print("   %d highlight clips played in %.0f s" % [clips, sim])
	_check(clips >= 1, "the race produced highlights")
	_check(main.state == main.State.RESULTS, "the highlight reel ends back on the results")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
