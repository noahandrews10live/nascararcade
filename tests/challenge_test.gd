extends SceneTree
## Runs every Lightning Challenge with the player on autopilot; each must reach the
## results screen with a verdict.  CH=n runs just one.
var main: Node
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node("Game")
	for i in 10:
		await physics_frame
	var saved: Dictionary = game.challenges_done.duplicate()
	main.autopilot = true
	for idx in game.CHALLENGES.size():
		if OS.get_environment("CH") != "" and int(OS.get_environment("CH")) != idx:
			continue
		main._enter_challenges()
		main._start_challenge(idx)
		var t := 0.0
		while main.state != main.State.RESULTS and t < 600.0:
			await physics_frame
			t += 1.0 / 60.0
		var ok: bool = main.state == main.State.RESULTS and main.challenge_result != ""
		print("  %s %-22s %s  (%s, %.0fs)" % ["ok  " if ok else "FAIL", game.CHALLENGES[idx].name, main.challenge_result, game.ordinal(main.race.position_of(main.race.player)), t])
		if not ok:
			failures += 1
	game.challenges_done = saved
	var cf := ConfigFile.new()
	cf.set_value("done", "list", saved)
	cf.save(game.CHALLENGES_PATH)
	print("FAILURES: ", failures)
	quit(1 if failures else 0)
