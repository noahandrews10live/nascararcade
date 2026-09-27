extends SceneTree
## The four bodies are split evenly across every field (the player's own pick
## counts toward its make).
##   godot --headless -s tests/makes_test.gd

var failures := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var Track = load("res://scripts/track.gd")
	var Race = load("res://scripts/race.gd")
	var game := root.get_node("Game")
	var t: Node3D = Track.new()
	root.add_child(t)
	t.setup(game.tracks[1])
	for size in [16, 20, 30, 40]:
		for player in [-1, 0]:
			var race: Node3D = Race.new()
			root.add_child(race)
			race.setup(t, player, 3, size)
			var counts := [0, 0, 0, 0]
			for c in race.cars:
				counts[c._body.make] += 1
			var spread: int = counts.max() - counts.min()
			print("   %d cars%s: %s" % [size, " with the player" if player >= 0 else "", str(counts)])
			_check(spread <= 1, "%d cars%s: the four bodies split evenly" % [size, " with the player" if player >= 0 else ""])
			race.free()
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
