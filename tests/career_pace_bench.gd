extends SceneTree
## Can a new career car keep up? A full-field race with your car (the AI
## driving it) starting mid-pack: where it runs after laps 1 and 3 as a
## brand-new career car (no R&D) and with everything maxed, against the same
## car outside career mode.
##   godot --headless --fixed-fps 60 -s tests/career_pace_bench.gd

var Track: GDScript
var Race: GDScript
const DT := 1.0 / 60.0


func _initialize() -> void:
	_run.call_deferred()


func _race(t: Node3D, lvl: int, ai_control := false) -> String:
	var game := root.get_node("Game")
	var race: Node3D = Race.new()
	root.add_child(race)
	if lvl >= 0:
		game.career = {"upgrades": {"engine": lvl, "aero": lvl, "chassis": lvl, "crew": lvl}}
		race.career = true
	race.setup(t, -1 if ai_control else 0, 5, 25)
	race.grid_up(0.0, 40.0)
	var me: Node3D = race.player
	if ai_control:
		for c in race.cars:
			if int(c.get_meta("grid")) == 24:
				me = c
	me.ai = true
	race.go_green()
	var out := ""
	var sim := 0.0
	var marks := [1, 3]
	while sim < 600.0 and not marks.is_empty():
		race.tick(DT)
		sim += DT
		var leader: Node3D = race.order[0]
		if leader.lap() >= marks[0] + 1:
			var p: int = race.position_of(me)
			var ahead: float = race.order[p - 2].dist - me.dist if p > 1 else 0.0
			out += "L%d P%-2d %4.0fm back (%3.0fm to the car ahead)  " % [marks[0], p, leader.dist - me.dist, ahead]
			marks.pop_front()
	race.free()
	game.career = {}
	return out


func _run() -> void:
	Track = load("res://scripts/track.gd")
	Race = load("res://scripts/race.gd")
	var game := root.get_node("Game")
	for idx in [1, 0, 2]:
		var t: Node3D = Track.new()
		root.add_child(t)
		t.setup(game.tracks[idx])
		print(game.tracks[idx].name)
		print("   AI car      ", _race(t, -1, true))
		print("   not career  ", _race(t, -1))
		print("   new career  ", _race(t, 0))
		print("   maxed       ", _race(t, game.MAX_UPGRADE))
		t.free()
	quit()
