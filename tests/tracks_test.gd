extends SceneTree
## Builds every track and runs one AI car for a lap: length, turning, lap speed.
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node("Game")
	var Track: GDScript = load("res://scripts/track.gd")
	var Race: GDScript = load("res://scripts/race.gd")
	for idx in game.tracks.size():
		if OS.get_environment("TRACK") != "" and int(OS.get_environment("TRACK")) != idx:
			continue
		var t: Node3D = Track.new()
		root.add_child(t)
		t.setup(game.tracks[idx])
		var ksum := 0.0
		var right_turns := false
		for k in t.curv:
			ksum += k * (t.length / t.n)
			if k < -0.003:
				right_turns = true
		var r: Node3D = Race.new()
		root.add_child(r)
		r.arcade_setup = true
		r.setup(t, -1, 3, 1)
		r.cars[0].ai_skill = 1.0
		r.grid_up(-t.length * 0.5, 30.0)
		r.go_green()
		var sim := 0.0
		while sim < 400.0 and r.cars[0].lap() < 1:
			r.tick(1.0 / 60.0)
			sim += 1.0 / 60.0
		var c: Node3D = r.cars[0]
		print("%-30s %5.2f mi  turn %5.2f rad%s  lap %6.2fs  %5.1f mph  dmg %.2f spin %s" % [game.tracks[idx].name, t.length / 1609.34, ksum, "  (right turns)" if right_turns else "", c.best_lap, t.length / max(c.best_lap, 0.01) * 2.23694, c.total_damage(), c.spinning])
		r.free()
		t.free()
	quit()
