extends SceneTree
## How much damage things do: a car nosed into the wall at a few angles, and the
## damage a 25-car field carries after a couple of minutes of racing (short track
## and superspeedway pack). A car is out past 0.72 total damage.
##   godot --headless --fixed-fps 60 -s tests/damage_bench.gd

var Track: GDScript
var Race: GDScript
const DT := 1.0 / 60.0


func _initialize() -> void:
	_run.call_deferred()


func _wall(t: Node3D, yaw: float) -> Array:
	var race: Node3D = Race.new()
	root.add_child(race)
	race.setup(t, -1, 5, 1)
	race.grid_up(0.0, 40.0)
	race.go_green()
	var c: Node3D = race.cars[0]
	c.dist = t.length * 0.5
	c.v = 55.0
	c.d = t.outer_edge() - 4.0
	c.yaw = yaw
	var d0: float = c.d
	race.tick(DT)
	if c.d < d0:
		c.yaw = -yaw
	var hit := 0.0
	for i in 120:
		race.tick(DT)
		hit = max(hit, c.wall_hit)
	var out: Array = [hit, c.total_damage(), c.damage.front, c.damage.right]
	race.free()
	return out


func _field(t: Node3D, secs: float) -> String:
	var race: Node3D = Race.new()
	root.add_child(race)
	race.setup(t, -1, 50, 25)
	race.grid_up(0.0, 40.0)
	race.go_green()
	for i in int(secs * 60.0):
		race.tick(DT)
	var tot := 0.0
	var worst := 0.0
	var hurt := 0
	var out := 0
	for c in race.cars:
		var d: float = c.total_damage()
		tot += d
		worst = max(worst, d)
		if d > 0.1:
			hurt += 1
		if c.out:
			out += 1
	race.free()
	return "avg %.3f  worst %.2f  cars over 0.1: %d  out: %d" % [tot / 25.0, worst, hurt, out]


func _run() -> void:
	Track = load("res://scripts/track.gd")
	Race = load("res://scripts/race.gd")
	var game := root.get_node("Game")
	var t: Node3D = Track.new()
	root.add_child(t)
	t.setup(game.tracks[1])
	for y in [0.05, 0.1, 0.2, 0.35]:
		var r: Array = _wall(t, y)
		print("wall at %.0f deg: hit %.1f m/s  total %.3f  (front %.2f right %.2f)" % [rad_to_deg(y), r[0], r[1], r[2], r[3]])
	t.free()
	for idx in [2, 0]:
		t = Track.new()
		root.add_child(t)
		t.setup(game.tracks[idx])
		print("%s, 25 cars, 120 s: %s" % [game.tracks[idx].short, _field(t, 120.0)])
		t.free()
	quit()
