extends SceneTree
## One car alone on each track (the AI driving at the limit): average, top and
## slowest-corner speeds against the real Gen 3 car at the track each one is
## modelled on (2024-26 qualifying speeds; 2026 engine packages).
##   godot --headless -s tests/lap_bench.gd        (TRACK=n for one track)

const DT := 1.0 / 60.0
const MPH := 2.23694
# Track index -> [real counterpart, its pole speed in mph]
const REAL := {
	0: ["Daytona", 181.0], 1: ["Texas", 185.0], 2: ["Bristol", 127.0], 3: ["Talladega", 181.0],
	4: ["Michigan", 186.0], 5: ["Kansas", 182.0], 6: ["Darlington", 168.0], 7: ["Martinsville", 97.0],
	8: ["Phoenix", 137.0], 9: ["Pocono", 171.0], 10: ["Watkins Glen / COTA", 110.0],
}
var Track
var Race


func _initialize() -> void:
	_run.call_deferred()


func _solo(t: Node3D) -> Dictionary:
	var race: Node3D = Race.new()
	root.add_child(race)
	race.setup(t, -1, 3, 1)
	race.grid_up(0.0, 40.0)
	var a: Node3D = race.cars[0]
	a.dist = 0.0
	a.d = race.lanes[0]
	a.ai_lane = race.lanes[0]
	a.ai_skill = 1.0 / 0.95 # a qualifying lap: right at the limit, no margin
	race.go_green()
	var vmax := 0.0
	var vmin := 999.0
	var lap_t := 0.0
	var t0 := -1.0
	var sim := 0.0
	while sim < 600.0:
		race.tick(DT)
		sim += DT
		if a.lap() >= 1 and t0 < 0.0:
			t0 = sim
		if t0 > 0.0:
			vmax = max(vmax, a.v)
			vmin = min(vmin, a.v)
		if a.lap() >= 2:
			lap_t = sim - t0
			break
	var res := {"lap": lap_t, "avg": t.length / max(lap_t, 0.01) * MPH, "top": vmax * MPH, "min": vmin * MPH, "spun": a.spinning}
	race.free()
	return res


func _run() -> void:
	Track = load("res://scripts/track.gd")
	Race = load("res://scripts/race.gd")
	var only := OS.get_environment("TRACK")
	var game := root.get_node("Game")
	var err := 0.0
	for idx in game.tracks.size():
		if only != "" and int(only) != idx:
			continue
		var t: Node3D = Track.new()
		root.add_child(t)
		t.setup(game.tracks[idx])
		var r := _solo(t)
		var pmin := 999.0
		var rmin := 1e9
		for i in t.speed_profile.size():
			pmin = min(pmin, t.speed_profile[i])
			if abs(t.curv[i]) > 1e-5:
				rmin = min(rmin, 1.0 / abs(t.curv[i]))
		print("   theory: slowest corner %.1f mph, tightest radius %.0f m" % [pmin * MPH, rmin])
		var real: Array = REAL.get(idx, ["?", 0.0])
		var dv: float = r.avg - float(real[1])
		err += dv * dv
		print("%-28s %4.2f mi %3d hp  lap %6.2fs  avg %5.1f  top %5.1f  min %5.1f  | %-12s %5.1f  (%+5.1f)%s" % [game.tracks[idx].short, t.length / 1609.34, int(game.tracks[idx].hp), r.lap, r.avg, r.top, r.min, real[0], real[1], dv, "  SPUN" if r.spun else ""])
		t.free()
	print("rms error %.1f mph" % sqrt(err / max(1, REAL.size() if only == "" else 1)))
	quit(0)
