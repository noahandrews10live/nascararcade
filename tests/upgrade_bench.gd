extends SceneTree
## What career R&D is worth: one lap alone (the AI driving) in a rookie car
## (no upgrades), then with every upgrade maxed, at an intermediate, a short
## track and a road course. Prints lap time, top speed and the gain.
##   godot --headless --fixed-fps 60 -s tests/upgrade_bench.gd

var Track: GDScript
var Race: GDScript
const DT := 1.0 / 60.0
const MPH := 2.23694


func _initialize() -> void:
	_run.call_deferred()


func _lap(t: Node3D, lvl: int) -> Array:
	var game := root.get_node("Game")
	game.career = {"upgrades": {"engine": lvl, "aero": lvl, "chassis": lvl, "crew": lvl}}
	var race: Node3D = Race.new()
	root.add_child(race)
	race.setup(t, -1, 3, 1)
	race.grid_up(0.0, 40.0)
	var a: Node3D = race.cars[0]
	game.apply_career(a)
	a.dist = 0.0
	a.d = race.lanes[0]
	a.ai_lane = race.lanes[0]
	race.go_green()
	var sim := 0.0
	var t0 := -1.0
	var vmax := 0.0
	var lap_t := 0.0
	while sim < 400.0:
		race.tick(DT)
		sim += DT
		if a.lap() >= 1 and t0 < 0.0:
			t0 = sim
		if t0 > 0.0:
			vmax = max(vmax, a.v)
		if a.lap() >= 2:
			lap_t = sim - t0
			break
	race.free()
	return [lap_t, vmax * MPH]


func _run() -> void:
	Track = load("res://scripts/track.gd")
	Race = load("res://scripts/race.gd")
	var game := root.get_node("Game")
	for idx in [1, 2, 10, 0]:
		var t: Node3D = Track.new()
		root.add_child(t)
		t.setup(game.tracks[idx])
		var lo: Array = _lap(t, 0)
		var hi: Array = _lap(t, game.MAX_UPGRADE)
		print("%-28s rookie %.2fs %.1f mph | maxed %.2fs %.1f mph | %.1f%% faster, +%.1f mph" % [game.tracks[idx].name, lo[0], lo[1], hi[0], hi[1], (lo[0] / hi[0] - 1.0) * 100.0, hi[1] - lo[1]])
		t.free()
	game.career = {}
	quit()
