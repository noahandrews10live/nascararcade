extends SceneTree
## Plays a Single Race (full rules) through the real game flow with the player on
## autopilot, forces a caution, and checks it reaches the results screen.
##   godot --headless --fixed-fps 60 --path . -s tests/race_mode_test.gd

var main: Node
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	print("  ok   " if cond else "  FAIL ", msg)
	if not cond:
		failures += 1


func _run() -> void:
	for i in 20:
		await physics_frame
	var game := root.get_node("Game")
	var tidx := int(OS.get_environment("TRACK")) if OS.get_environment("TRACK") != "" else 2
	var force_at := float(OS.get_environment("FORCE")) if OS.get_environment("FORCE") != "" else 25.0
	game.tracks[tidx].full_laps = 140 # 14 laps at the default SHORT length
	game.settings.length = 1
	main.mode = "race"
	main._use_track(tidx)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true
	_check(main.race.control != null, "race control is on")
	_check(main.race.cars.size() == 40, "40-car field")
	var forced := false
	var saw_pit := false
	var saw_yellow := false
	var sim := 0.0
	while main.state != main.State.RESULTS and sim < 900.0:
		await physics_frame
		sim += 1.0 / 60.0
		var ctl = main.race.control
		if OS.get_environment("JAM") != "" and int(sim * 60) % 120 == 0 and main.race.time > force_at:
			var slow := []
			for c in main.race.cars:
				if c.v < 4.0 and not c.towed and c.pit_state != 3:
					slow.append("#%s v=%.1f d=%.1f s=%.0f pit=%d lane=%.1f yaw=%.2f rev=%.1f want=%s" % [c.team.num, c.v, c.d, c.s(), c.pit_state, c.ai_lane, c.yaw, c.ai_reverse, c.want_pit])
			print("t=%.0f flag=%d cl=%d pace s=%.0f v=%.0f slow=%d %s" % [main.race.time, ctl.flag, ctl.caution_laps, ctl.pace_car.s(), ctl.pace_car.v, slow.size(), str(slow.slice(0, 4))])
			if main.race.time > force_at + 60:
				quit()
				return
		if not forced and main.race.time > force_at:
			forced = true
			ctl.throw_caution("DEBRIS (TEST)", null)
		if ctl.flag == ctl.Flag.YELLOW:
			saw_yellow = true
		for c in main.race.cars:
			if c.pit_state == 3:
				saw_pit = true
	_check(saw_yellow, "a caution came out")
	_check(saw_pit, "cars made pit stops")
	_check(main.state == main.State.RESULTS, "reached results (%.0fs sim)" % sim)
	print("  player finished %s, cautions %d" % [game.ordinal(main.race.position_of(main.race.player)), main.race.control.caution_count])
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
