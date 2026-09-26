extends SceneTree
## Full-field AI race with incident logging (TRACK=n SECS=s [EVERY=frames] [TRACE=car#] [NOLANE=1]).
func _initialize():
	var t = load("res://scripts/track.gd").new()
	root.add_child(t)
	t.setup(root.get_node("Game").tracks[int(OS.get_environment("TRACK"))])
	root.get_node("Game").debug_seed = 7
	var race = load("res://scripts/race.gd").new()
	root.add_child(race)
	race.setup(t, -1, 5, 40)
	race.debug_no_lane_changes = OS.get_environment("NOLANE") == "1"
	race.grid_up(-150.0, 30.0)
	for i in 180:
		race.tick(1.0/60.0)
	race.go_green()
	var hits := {}
	var logged := [0]
	race.incident.connect(func(c, kind):
		if logged[0] < 6:
			logged[0] += 1
			print("INCIDENT t=%.1f #%s %s v=%.0f d=%.1f lane=%.1f yaw=%.2f r=%.2f vy=%.1f slide=%.2f scrub=%.2f bump=%.1f wall=%.1f k=%.4f thr=%.1f brk=%.1f dmg=%.2f dfm=%.2f" % [race.time, c.team.num, kind, c.v*2.237, c.d, c.ai_lane, c.yaw, c.r, c.vy, c.slide, c.scrub, c.bump, c.wall_hit, t.curvature_at(c.s()), c.throttle, c.brake, c.total_damage(), c.df_front_mult]))
	var trace_num := OS.get_environment("TRACE")
	for i in int(OS.get_environment("SECS")) * 60:
		race.tick(1.0/60.0)
		if trace_num != "" and i % 10 == 0:
			for c in race.cars:
				if c.team.num == trace_num:
					var near := ""
					for o in race.cars:
						var g = race._gap(c, o)
						if o != c and abs(g) < 12 and abs(o.d - c.d) < 4:
							near += " [#%s g=%.1f dd=%.1f]" % [o.team.num, g, o.d - c.d]
					print("TR t=%.2f v=%.0f d=%.2f lane=%.1f yaw=%.3f vy=%.2f r=%.3f rdes=%.3f scrub=%.2f slide=%.2f dfm=%.2f thr=%.2f brk=%.2f k=%.4f%s" % [race.time, c.v*2.237, c.d, c.ai_lane, c.yaw, c.vy, c.r, c.ai_r_des, c.scrub, c.slide, c.df_front_mult, c.throttle, c.brake, t.curvature_at(c.s()), near + " | " + ", ".join(c.dbg.map(func(x): return "%.2f" % x)) + " g=%d" % c.gear])
		for c in race.cars:
			if c.wall_hit > 3.0:
				hits[c] = hits.get(c, 0) + 1
		if i % int(OS.get_environment("EVERY") if OS.get_environment("EVERY") != "" else "600") == 0:
			var slow := 0
			var dm := 0.0
			for c in race.cars:
				if c.v < 25: slow += 1
				dm += c.total_damage()
			var bumps := 0
			var spins := 0
			for c in race.cars:
				if c.bump > 2.0: bumps += 1
				if c.spinning: spins += 1
			print("t=%.1f slow=%d avgdmg=%.2f bumps=%d spins=%d" % [i/60.0, slow, dm/40, bumps, spins])
	for c in race.order:
		print("%2d #%-3s lap=%d v=%.0f d=%.1f lane=%.1f yaw=%.2f dmg=%.2f hits=%d thr=%.1f brk=%.1f" % [race.position_of(c), c.team.num, c.lap(), c.v*2.237, c.d, c.ai_lane, c.yaw, c.total_damage(), hits.get(c,0), c.throttle, c.brake])
	quit()
