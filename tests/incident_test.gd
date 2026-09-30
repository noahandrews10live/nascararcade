extends SceneTree
## Race control spots incidents and throws the yellow when it should, in a real
## 25-car race with the rules on:
##   ovals: a car turned around, a hard hit on the wall, a car stopped on the
##   apron, a car crawling round after a spin, a pile of debris;
##   road courses: a car stuck in the grass (but not straight away);
##   and a clean race doesn't throw phantom cautions for incidents.
##   godot --headless --fixed-fps 60 -s tests/incident_test.gd

var Track: GDScript
var Race: GDScript
const DT := 1.0 / 60.0
var failures := 0
var game: Node


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _track(idx: int) -> Node3D:
	var t: Node3D = Track.new()
	root.add_child(t)
	t.setup(game.tracks[idx])
	return t


## A race under way: green for a while, the field strung out.
func _race(t: Node3D) -> Node3D:
	var race: Node3D = Race.new()
	root.add_child(race)
	race.setup(t, -1, 30, 25)
	race.enable_rules()
	race.control.debris_rate = 0.0
	race.grid_up(0.0, 40.0)
	race.go_green()
	for i in 60 * 12:
		race.tick(DT)
	return race


## Runs until the yellow or `secs`; returns [reason, seconds] ("" if none).
func _until_yellow(race: Node3D, secs: float, each := Callable()) -> Array:
	var ctl: Node = race.control
	var got := [""]
	var cb := func(text: String, kind: String):
		if kind == "flag" and text.begins_with("CAUTION") and got[0] == "":
			got[0] = text.trim_prefix("CAUTION  -  ")
	ctl.message.connect(cb)
	var t := 0.0
	while t < secs and ctl.flag != ctl.Flag.YELLOW:
		if each.is_valid():
			each.call()
		race.tick(DT)
		t += DT
	ctl.message.disconnect(cb)
	return [got[0], t]


## A mid-pack car to have the incident (not alongside pit road, where a stopped
## car is just a car in the pits).
func _victim(race: Node3D) -> Node3D:
	for i in range(10, race.order.size()):
		var c: Node3D = race.order[i]
		if not race.track.in_pit_roadway(c.s()) and not race.track.in_pit_roadway(c.s() + 60.0):
			return c
	# Everyone's still near the line: put one on the far side of the track.
	var v: Node3D = race.order[12]
	var L: float = race.track.length
	v.dist = floor(v.dist / L) * L + L * 0.5
	return v


## Stops a car for good where it is (no fuel, no speed).
func _stall(c: Node3D) -> void:
	c.fuel = 0.0
	c.v = 0.0
	c.vy = 0.0
	c.r = 0.0


func _run() -> void:
	Track = load("res://scripts/track.gd")
	Race = load("res://scripts/race.gd")
	game = root.get_node("Game")
	game.settings.cautions = 1
	game.settings.weather = 0
	var oval := _track(1)

	# A clean race first: no yellow for nothing.
	var race := _race(oval)
	var res := _until_yellow(race, 60.0)
	print("   60 s of green racing: caution=%s" % (res[0] if res[0] != "" else "none"))
	_check(res[0] == "" or res[0] in ["ACCIDENT", "SPIN", "CAR IN THE WALL"], "no caution without an incident")
	race.free()

	# Turned around: even if it drives off, that's a yellow on an oval.
	race = _race(oval)
	var c := _victim(race)
	c.yaw = 2.2
	res = _until_yellow(race, 6.0)
	print("   turned around at %.0f mph: %s after %.1f s" % [c.v * 2.237, res[0], res[1]])
	_check(res[0] != "" and res[1] < 4.0, "a car turned around brings out the caution")
	race.free()

	# A hard hit on the wall.
	race = _race(oval)
	c = _victim(race)
	var hit := [0.0]
	# Nose the car toward the outside wall at racing speed (which way that is
	# in yaw: try one, and turn the other way if it's heading down the track).
	c.d = oval.outer_edge() - 3.0
	c.yaw = 0.3
	var d0: float = c.d
	race.tick(DT)
	if c.d < d0:
		c.yaw = -0.3
	res = _until_yellow(race, 4.0, func(): hit[0] = max(hit[0], c.wall_hit))
	print("   into the wall at %.1f m/s: %s after %.1f s" % [hit[0], res[0], res[1]])
	_check(res[0] != "", "a hard hit on the wall brings out the caution")
	race.free()

	# Stopped on the apron (off the racing surface).
	race = _race(oval)
	c = _victim(race)
	c.d = oval.inner_edge() - 3.0
	_stall(c)
	res = _until_yellow(race, 10.0, func(): c.fuel = 0.0)
	print("   stopped on the apron: %s after %.1f s" % [res[0], res[1]])
	_check(res[0] != "" and res[1] < 6.0, "a car stopped on the apron brings out the caution")
	race.free()

	# Spun and crawling round far off the pace.
	race = _race(oval)
	c = _victim(race)
	c.yaw = 0.9
	res = _until_yellow(race, 12.0, func():
		c.v = min(c.v, 22.0)) # limping
	print("   spun, then limping at 50 mph: %s after %.1f s" % [res[0], res[1]])
	_check(res[0] != "" and res[1] < 10.0, "a car limping round after a spin brings out the caution")
	race.free()

	# Debris: a few pieces left lying on the racing surface.
	race = _race(oval)
	var far: float = race.order[0].dist + oval.length * 0.5
	race.spawn_debris(far, 0.0, 3)
	res = _until_yellow(race, 10.0)
	print("   debris on the track: %s after %.1f s" % [res[0], res[1]])
	_check(res[0] == "DEBRIS", "debris on the racing surface brings out the caution")
	race.free()
	oval.free()

	# Road course: stuck in the grass. Not straight away (they can get going), but
	# not left there either.
	var road := _track(10)
	race = _race(road)
	c = _victim(race)
	c.d = road.apron_edge() - 6.0
	_stall(c)
	res = _until_yellow(race, 20.0, func(): c.fuel = 0.0)
	print("   road course, stuck in the grass: %s after %.1f s" % [res[0], res[1]])
	_check(res[0] != "" and res[1] > 6.0 and res[1] < 16.0, "a car stuck in the grass brings out the caution (after a while)")
	race.free()
	road.free()

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
