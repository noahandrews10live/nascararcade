extends Node
## In-race goals: a few things to go for in every race besides the result, each
## worth XP the moment it's done, on a ticker under the flag banner.
##   - stage gains: three spots in the stage (from where you start it), or win
##     it if you start it near the front. A new one each stage;
##   - lead a lap: be in front at the line once;
##   - beat a rival: a car that starts just ahead of you. If someone wrecks
##     you, they become the rival.
## The XP is added to the race's award (Game.award_race's extra).

signal done(goal: Dictionary)

var race: Node3D
var goals: Array = [] # {id, text, xp, state: 0 open / 1 done / -1 missed}
var earned := 0
var rival: Node3D = null
var flash := "" # the last goal done, shown in gold for a few seconds
var flash_t := 0.0
var _cycle_t := 0.0
var _cycle := 0
var _laps_led0 := 0

const XP_STAGE := 50
const XP_STAGE_WIN := 80
const XP_LEAD := 75
const XP_RIVAL := 60
const STAGE_GAIN := 3


func begin(r: Node3D) -> void:
	race = r
	var p: Node3D = race.player
	goals.clear()
	earned = 0
	_laps_led0 = p.laps_led
	if race.control and race.control.enabled and race.control.stage_ends.size() > 0:
		race.control.stage_done.connect(_on_stage_done)
		_stage_goal(1, _pos(p))
	goals.append({"id": "lead", "text": "LEAD A LAP", "xp": XP_LEAD, "state": 0})
	# The rival: the best driver starting a few places ahead.
	var grid: int = int(p.get_meta("grid", 0))
	var best_skill := -1.0
	for c in race.cars:
		var g: int = int(c.get_meta("grid", 0))
		if c != p and not c.is_player and g < grid and g >= grid - 4 and c.ai_skill > best_skill:
			best_skill = c.ai_skill
			rival = c
	if rival == null:
		for c in race.cars:
			if c != p and int(c.get_meta("grid", 0)) == grid + 1:
				rival = c
	if rival:
		goals.append({"id": "rival", "text": _rival_text(), "xp": XP_RIVAL, "state": 0})
	race.car_finished.connect(_on_finished)


func _rival_text() -> String:
	var d: String = String(rival.team.driver)
	return "BEAT THE #%s (%s)" % [rival.team.num, d.get_slice(" ", d.get_slice_count(" ") - 1)]


func _pos(c: Node3D) -> int:
	return race.order.find(c) + 1


func _goal(id: String) -> Dictionary:
	for g in goals:
		if g.id == id:
			return g
	return {}


func _stage_goal(n: int, from: int) -> void:
	var target: int = max(1, from - STAGE_GAIN)
	var g := {"id": "stage%d" % n, "stage": n, "target": target, "state": 0}
	if target == 1:
		g.text = "WIN STAGE %d" % n
		g.xp = XP_STAGE_WIN
	else:
		g.text = "STAGE %d: GAIN %d SPOTS (P%d OR BETTER)" % [n, from - target, target]
		g.xp = XP_STAGE
	goals.append(g)


func _complete(g: Dictionary) -> void:
	if g.is_empty() or int(g.state) != 0:
		return
	g.state = 1
	earned += int(g.xp)
	flash = "GOAL: %s  +%d XP" % [g.text, int(g.xp)]
	flash_t = 4.0
	done.emit(g)


func _on_stage_done(n: int, order: Array) -> void:
	var p: Node3D = race.player
	var g: Dictionary = _goal("stage%d" % n)
	var at: int = order.find(p) + 1
	if not g.is_empty() and int(g.state) == 0:
		if at > 0 and at <= int(g.target):
			_complete(g)
		else:
			g.state = -1
	if n < race.control.stage_ends.size() and at > 0:
		_stage_goal(n + 1, at)


func _on_finished(c: Node3D, _place: int) -> void:
	if c != race.player:
		return
	var g: Dictionary = _goal("rival")
	if not g.is_empty() and int(g.state) == 0:
		# You took the flag first, or they're out / still running behind you.
		if not rival.finished or rival.finish_order > c.finish_order:
			_complete(g)
		else:
			g.state = -1
	for o in goals:
		if int(o.state) == 0:
			o.state = -1


func _process(delta: float) -> void:
	if race and is_instance_valid(race) and race.running:
		tick(delta)


func tick(delta: float) -> void:
	if race == null or race.player == null:
		return
	var p: Node3D = race.player
	flash_t = max(flash_t - delta, 0.0)
	_cycle_t += delta
	if p.laps_led > _laps_led0:
		_complete(_goal("lead"))
	# Wrecked by someone: they're the rival now (while that goal is open).
	var g: Dictionary = _goal("rival")
	if not g.is_empty() and int(g.state) == 0:
		for o in p.rivals:
			if float(p.rivals[o]) > 0.5 and o != rival and is_instance_valid(o) and not o.out and not o.is_player:
				rival = o
				g.text = _rival_text()
				flash = "NEW RIVAL: THE #%s WRECKED YOU - BEAT THEM" % rival.team.num
				flash_t = 4.0
				break


## The ticker's line: the goal just done (gold), else the open goals in turn.
func ticker() -> Dictionary:
	if flash_t > 0.0:
		return {"text": flash, "gold": true}
	var open: Array = goals.filter(func(g): return int(g.state) == 0)
	if open.is_empty():
		return {"text": "", "gold": false}
	if _cycle_t > 4.0:
		_cycle_t = 0.0
		_cycle += 1
	var g: Dictionary = open[_cycle % open.size()]
	var extra := ""
	if g.id == "rival" and rival:
		var gap: int = _pos(race.player) - _pos(rival)
		extra = "  (AHEAD)" if gap < 0 else "  (%d SPOT%s BEHIND)" % [gap, "" if gap == 1 else "S"]
	elif String(g.id).begins_with("stage"):
		extra = "  (NOW P%d)" % _pos(race.player)
	var n_done: int = goals.filter(func(x): return int(x.state) == 1).size()
	return {"text": "GOAL: %s%s  +%d XP   [%d/%d DONE]" % [g.text, extra, int(g.xp), n_done, goals.size()], "gold": false}
