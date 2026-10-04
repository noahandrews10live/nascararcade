extends SceneTree
## Race control's lines (your car, driven by you):
##   - the commitment line: below it at pit entry and staying out is a
##     pass-through;
##   - the yellow line at a superspeedway: pass a car below it and give the spot
##     back and that's that; keep it and it's a pass-through;
##   - pitting before pit road is open (a full caution): to the tail of the field
##     (and the quick caution's restart order puts a tail car last);
##   - and the rear-view mirror while racing (looks back; OFF puts it away).
##   godot --headless --fixed-fps 60 -s tests/penalties_test.gd

var main: Node
var game: Node
var failures := 0
var said: Array = []


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _heard(part: String) -> bool:
	return said.any(func(t): return String(t).contains(part))


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _race(track_idx: int) -> void:
	main.clear_checkpoint()
	game.settings.length = 1
	game.settings.field = 0
	game.settings.weather = 0
	game.settings.weekend = 0
	game.settings.cautions = 1
	game.tracks[track_idx].full_laps = 600
	main.mode = "race"
	main.session = "race"
	main._use_track(track_idx)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true
	main.race.control.debris_rate = 0.0
	main.race.control.cautions_enabled = false
	main.race.control.message.connect(func(t, _k): said.append(t))
	await _frames(60 * 20)


func _human(p: Node3D) -> void:
	main.autopilot = false
	p.autopilot_forced = false


func _robot() -> void:
	main.autopilot = true


func _run() -> void:
	game = root.get_node("Game")
	for i in 20:
		await physics_frame

	# 1. The commitment line.
	await _race(1)
	var race = main.race
	var ctl = race.control
	var p: Node3D = race.player
	var trk = race.track
	var cs: float = trk.pit_in_s() - trk.PIT_LANE_EXT + 10.0
	_human(p)
	said.clear()
	p.dist = floor(p.dist / trk.length) * trk.length + cs - 12.0 + trk.length
	p.v = 30.0
	p.yaw = 0.0
	for i in 60:
		p.d = trk.inner_edge() - 1.2 # (holding it down on the apron)
		await physics_frame
	print("   commitment: penalty '%s', d %.1f (line at %.1f)" % [p.penalty, p.d, trk.inner_edge()])
	_check(p.penalty == "PT" and _heard("COMMITMENT LINE"), "below the commitment line and staying out: a pass-through")
	p.penalty = ""
	p.want_pit = false
	_robot()
	await _frames(60 * 5)
	# ... but above it (on the track) is fine.
	_human(p)
	said.clear()
	p.dist = floor(p.dist / trk.length) * trk.length + cs - 25.0 + trk.length
	p.d = 0.0
	p.v = 30.0
	p.yaw = 0.0
	p.sync_visual()
	await _frames(90)
	_check(p.penalty == "" and not _heard("COMMITMENT"), "above it: nothing")
	_robot()

	# 2. Pitting before pit road is open (a full caution).
	ctl.quick = false
	ctl.cautions_enabled = true
	ctl.throw_caution("test", null)
	await _frames(5)
	said.clear()
	var pin: float = trk.pit_in_s()
	p.want_pit = true
	p.pit_state = ctl.Pit.APPROACH
	p.dist = floor(p.dist / trk.length) * trk.length + pin - 60.0 + trk.length
	p.d = trk.inner_edge() - 2.0
	p.sync_visual()
	var n := 0
	while p.pit_state == ctl.Pit.APPROACH and n < 120:
		await physics_frame
		n += 1
	print("   pit road closed: state %d, tail %s, pit_open %s" % [p.pit_state, p.get_meta("tail", false), ctl.pit_open])
	_check(not ctl.pit_open and p.get_meta("tail", false) and _heard("BEFORE PIT ROAD OPENED"), "pitting before pit road opens: to the tail")
	# The quick caution's order puts a tail car last.
	ctl._freeze = race.order.duplicate()
	ctl._calls.clear()
	var lead: Node3D = race.order[0]
	lead.set_meta("tail", true)
	var order: Array = ctl._compute_order()
	_check(order[-1] == lead or (order.find(lead) > order.size() - 4), "a tail penalty restarts at the back of the line")
	p.remove_meta("tail")
	ctl.quick = true

	# 3. The yellow line at a superspeedway.
	await _race(0)
	race = main.race
	ctl = race.control
	p = race.player
	trk = race.track
	var x: Node3D = null
	for c in race.order:
		if c != p and not c.out and c.pit_state == 0 and c.d > trk.inner_edge() + 5.0 and not trk.in_pit_zone(c.s() + 60.0) and not trk.in_pit_zone(c.s() - 40.0):
			x = c # (a car well up the track: room below it)
			break
	_human(p)
	said.clear()
	# The rule reads where the cars are: with the race held still, put your car
	# below the line and move it by, as race control sees it each tick.
	await physics_frame
	await physics_frame # (your hands on it: not driven for you)
	main.paused = true
	await physics_frame
	p.ai = false
	var x0: float = x.dist
	var t0: float = race.time
	ctl._below_ahead.clear()
	ctl._yl_owed = null
	var step := func(rel: float, low: bool, secs: float) -> void:
		p.dist = x0 + rel
		p.d = trk.inner_edge() - 1.4 if low else 0.0
		race.time += secs
		ctl._line_rules()
	for k in 10:
		step.call(-6.0 + k * 1.0, true, 0.1) # by it, below the line
	_check(_heard("BELOW THE YELLOW LINE - GIVE IT BACK"), "pass a car below the yellow line: give it back")
	step.call(-5.0, false, 0.5) # back behind it
	for k in 10:
		step.call(-5.0, false, 1.0)
	_check(p.penalty == "", "give it back: no penalty")
	# Again, and keep it.
	said.clear()
	for k in 10:
		step.call(-6.0 + k * 1.0, true, 0.1)
	for k in 10:
		step.call(12.0, false, 1.0)
	print("   kept it: penalty '%s'" % p.penalty)
	_check(p.penalty == "PT" and _heard("BELOW THE YELLOW LINE  -  PASS-THROUGH"), "keep it: a pass-through")
	p.penalty = ""
	p.want_pit = false
	race.time = t0 + 30.0
	p.dist = x0 - 30.0
	p.d = 0.0
	main.paused = false
	_robot()

	# (The rear-view mirror, while we're racing: on by default, room made for it.)
	await process_frame
	var m = main.mirror
	_check(m.frame_box.visible and main.hud.mirror_room > 0.0 and m.vp.world_3d == main.cam.get_world_3d(), "the rear-view mirror is up, looking at the same world")
	var back: Vector3 = -m.cam.global_transform.basis.z # (where it looks)
	var car_back: Vector3 = p.global_transform.basis.z
	_check(back.dot(car_back) > 0.9, "and it looks backward")
	_check(main.hud._banner_rect().position.y >= m.box().end.y, "the flag banner sits below it")
	game.settings.mirror = 0
	await process_frame
	await process_frame
	_check(not m.frame_box.visible and main.hud.mirror_room == 0.0, "MIRROR: OFF puts it away")
	game.settings.mirror = 1
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
