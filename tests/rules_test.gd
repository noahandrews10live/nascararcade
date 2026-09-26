extends SceneTree
## Full race with the NASCAR rules on: cautions, pit stops, stages, restarts, points.
##   godot --headless --path . -s tests/rules_test.gd   (TRACK=n LAPS=n FORCE=secs)

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node("Game")
	game.debug_seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 3
	var idx := int(OS.get_environment("TRACK")) if OS.get_environment("TRACK") != "" else 1
	var t: Node3D = load("res://scripts/track.gd").new()
	root.add_child(t)
	t.setup(game.tracks[idx])
	var laps := int(OS.get_environment("LAPS")) if OS.get_environment("LAPS") != "" else int(game.tracks[idx].race_laps)
	var race: Node3D = load("res://scripts/race.gd").new()
	root.add_child(race)
	race.setup(t, -1, laps, 40)
	race.enable_rules()
	var ctl: Node = race.control
	var log := []
	ctl.message.connect(func(text, kind):
		if kind != "spotter":
			var lead = ctl.leader()
			print("  [%6.1fs lap %2d] %s" % [race.time, lead.lap() + 1, text]))
	race.incident.connect(func(c, kind):
		if kind == "out" and OS.get_environment("OUTS") != "":
			print("  OUT t=%.1f #%s flag=%d pit=%d v=%.1f d=%.1f s=%.0f dmg=%s bump=%.1f wall=%.1f yaw=%.2f" % [race.time, c.team.num, ctl.flag, c.pit_state, c.v, c.d, c.s(), str(c.damage), c.bump, c.wall_hit, c.yaw]))
	race.grid_up(-150.0, 30.0)
	for i in 180:
		race.tick(1.0 / 60.0)
	race.go_green()
	var force := float(OS.get_environment("FORCE")) if OS.get_environment("FORCE") != "" else 0.0
	var forced := false
	var sim := 0.0
	var pit_stops := 0
	var prev_state := {}
	var max_sim := float(OS.get_environment("MAXSIM")) if OS.get_environment("MAXSIM") != "" else 3000.0
	while sim < max_sim:
		race.tick(1.0 / 60.0)
		sim += 1.0 / 60.0
		for c in race.cars:
			if c.pit_state == 3 and prev_state.get(c, 0) != 3:
				pit_stops += 1
			prev_state[c] = c.pit_state
		if OS.get_environment("DBG51") != "" and int(sim * 60) % 120 == 0 and race.time > 140 and race.time < 330:
			var lead = ctl.leader()
			var c51 = null
			for c in race.cars:
				if c.team.num == "51": c51 = c
			print("t=%.0f armed=%s cl=%d lead#%s s=%.0f v=%.0f pit=%d | pace s=%.0f v=%.0f vis=%s | #51 s=%.0f d=%.1f v=%.1f lane=%.1f yaw=%.2f dmg=%.2f rev=%.1f stuck=%.1f" % [race.time, ctl.restart_armed, ctl.caution_laps, lead.team.num, lead.s(), lead.v, lead.pit_state, ctl.pace_car.s(), ctl.pace_car.v, ctl.pace_car.visible, c51.s(), c51.d, c51.v, c51.ai_lane, c51.yaw, c51.total_damage(), c51.ai_reverse, c51.ai_stuck])
		if force > 0.0 and not forced and race.time > force:
			forced = true
			ctl.throw_caution("DEBRIS (TEST)", null)
		if race.finish_count >= race.cars.size() - 1 or (race.finish_count > 0 and race.time - race.order[0].finish_time > 60.0):
			break
	print("Finished in %.0fs sim, %d cautions, %d pit stops, %d laps" % [sim, ctl.caution_count, pit_stops, race.laps])
	for i in min(12, race.order.size()):
		var c: Node3D = race.order[i]
		print("  %2d #%-3s %-18s laps=%d led=%d stage=%d pts=%d dmg=%.2f %s" % [i + 1, c.team.num, c.team.driver, c.lap(), c.laps_led, c.stage_points, ctl.finishing_points(i + 1, c), c.total_damage(), "OUT" if c.out else ""])
	quit()
