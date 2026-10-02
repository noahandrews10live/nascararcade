extends Control
## Your pit stop, the way TV shows it:
##   - on pit road, a speed panel: the limit and five lights (green under it,
##     red over);
##   - in the box, the pit-stop camera from the wall, and a panel with the stop
##     clock, each tyre as it comes off and goes on (right side first), the fuel
##     going in and any adjustment;
##   - the jack drops: GO! Hit the gas and your reaction is part of the stop; jump
##     it before the jack's down and it costs you (holding the gas through it is a
##     slow getaway);
##   - off pit road: the stop, your getaway and the places it won or lost.
## Under a QUICK caution the stops are made at once, so yours is shown as a short
## replay at your box before the restart (tap to skip).
## Lives in the HUD (its coordinates).

const SHOW_SPEED := 1.6 # the replay of a quick-caution stop runs this much faster
const JUMP_WINDOW := 1.2 # pressing the gas this close to GO is jumping the jack
const JUMP_PENALTY := 1.5

var main: Node
var hud: Control
# The stop on screen.
var car: Node3D
var showing := false # a quick-caution stop being replayed
var stop := {} # race_control's record of the stop
var clock := 0.0 # seconds into the stop
var _total := 0.0
var _go_t := -1.0 # time since GO (the replay) or -1
var _jumped := false
var _reaction := -1.0
var _was_state := 0
var _entry_pos := 0
var _summary := ""
var _summary_t := 0.0
var _show_saved := {}
var _cam_pos := Vector3.ZERO
var _cam_init := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func active() -> bool:
	return showing or (car != null and is_instance_valid(car) and car.pit_state == 3)


## Every frame (main's _process).
func update(delta: float) -> void:
	size = Vector2(hud.W, hud.H)
	_summary_t = max(_summary_t - delta, 0.0)
	var p: Node3D = main.race.player if main.race else null
	if showing:
		_update_show(delta)
	elif p and is_instance_valid(p) and main.state == main.State.RACE:
		_update_live(p, delta)
	visible = hud.visible or showing
	queue_redraw()


func _update_live(p: Node3D, delta: float) -> void:
	var st: int = p.pit_state
	if st != _was_state:
		if _was_state == 0 and st != 0:
			_entry_pos = main.race.position_of(p)
			_jumped = false
			_reaction = -1.0
		if st == 3:
			car = p
			stop = p.get_meta("stop", {})
			_total = max(p.pit_timer, 0.1)
			clock = 0.0
			_cam_init = false
		if _was_state == 3 and st != 3:
			_reaction = float(p.get_meta("reaction", -1.0))
		if st == 0 and _was_state != 0:
			_finish_summary(p, main.race.position_of(p))
			car = null
		_was_state = st
	if st != 3 or main.paused:
		return
	clock += delta
	# The jack drop: the player's GO.
	var gas_press: bool = Input.is_action_just_pressed("accelerate")
	var gas_held: bool = Input.get_action_strength("accelerate") > 0.5
	if p.pit_timer > 0.0:
		if gas_press and p.pit_timer < JUMP_WINDOW and not _jumped:
			_jumped = true
			p.pit_timer += JUMP_PENALTY
			_total += JUMP_PENALTY
			main._sub("YOU JUMPED THE JACK!  +%.1f s" % JUMP_PENALTY, 2.0)
			main.synth.beep(220.0, 0.25, 0.4)
	elif not p.get_meta("released", false):
		var go_t: float = float(p.get_meta("go_t", 0.0))
		if gas_press or (Game.touch_active and int(Game.settings.get("auto_gas", 0)) == 1 and go_t > 0.35):
			p.set_meta("released", true)
		elif gas_held and go_t > 0.45:
			p.set_meta("released", true) # held it through: a slow getaway


func _finish_summary(p: Node3D, pos_now: int) -> void:
	if stop.is_empty():
		return
	var diff: int = _entry_pos - pos_now
	var places := "SAME PLACE" if diff == 0 else ("+%d" % diff if diff > 0 else "%d" % diff)
	var react := ""
	if _reaction >= 0.0:
		react = "  -  GETAWAY %.2f s %s" % [_reaction, "GREAT!" if _reaction < 0.3 else ("GOOD" if _reaction < 0.6 else "SLOW")]
	if _jumped:
		react += "  -  JUMPED THE JACK"
	_summary = "STOP %.1f s%s  -  OFF PIT ROAD %s (%s)" % [_total, react, Game.ordinal(pos_now), places]
	_summary_t = 6.0
	hud.crew_call(_summary)


## A quick caution's stop for the player, replayed at the box (the race waits).
func start_show(p: Node3D) -> void:
	var ctl: Node = main.race.control
	if ctl == null or not p.has_meta("stop"):
		return
	car = p
	stop = p.get_meta("stop")
	_total = max(float(stop.total), 0.1)
	clock = 0.0
	_go_t = -1.0
	showing = true
	_cam_init = false
	# Put the car in its box for the replay (where it really is goes back after).
	_show_saved = {"dist": p.dist, "d": p.d, "v": p.v, "pit": p.pit_state, "timer": p.pit_timer}
	var s: float = ctl.box_s(p)
	var L: float = main.track.length
	p.dist = p.dist - fposmod(p.dist, L) + s
	p.d = main.track.pit_lane_d() - 1.6
	p.v = 0.0
	p.pit_state = 3
	p.pit_timer = _total
	p.sync_visual()
	main.paused = true


func _update_show(delta: float) -> void:
	var p: Node3D = car
	if p == null or not is_instance_valid(p):
		_end_show()
		return
	var skip: bool = Input.is_action_just_pressed("start") or Input.is_action_just_pressed("accelerate")
	if _go_t < 0.0:
		clock += delta * SHOW_SPEED
		p.pit_timer = max(_total - clock, 0.0)
		if clock >= _total:
			_go_t = 0.0
			main.synth.beep(1320.0, 0.15)
	else:
		_go_t += delta
		# Away it goes.
		p.dist += delta * min(_go_t * 9.0, 14.0)
		p.pit_state = 4
		p.sync_visual()
		if _go_t > 1.3:
			_end_show()
			return
	if skip and clock > 0.5:
		_end_show()


func skip() -> void:
	if showing and clock > 0.3:
		_end_show()


func _end_show() -> void:
	showing = false
	var p: Node3D = car
	car = null
	if p and is_instance_valid(p) and not _show_saved.is_empty():
		p.dist = float(_show_saved.dist)
		p.d = float(_show_saved.d)
		p.v = float(_show_saved.v)
		p.pit_state = int(_show_saved.pit)
		p.pit_timer = float(_show_saved.timer)
		p.sync_visual()
	_show_saved = {}
	main.paused = false


## The pit-stop camera: on the pit wall, ahead of the car, looking back at it
## and the crew. Returns true while it has the shot.
func camera(cam: Camera3D, delta: float) -> bool:
	if not active() or car == null or not is_instance_valid(car):
		return false
	var t: Node3D = main.track
	var s: float = car.s()
	var fwd: Vector3 = t.fwd_at(s)
	var right: Vector3 = t.right_at(s)
	var cp: Vector3 = car.global_position
	# (Just over the pit wall, ahead of the war wagon, so nothing's in the way.)
	var want: Vector3 = cp - right * 3.2 + fwd * 7.5 + Vector3.UP * 2.5
	if not _cam_init:
		_cam_pos = want
		_cam_init = true
	_cam_pos = _cam_pos.lerp(want, clamp(delta * 3.0, 0.0, 1.0))
	cam.global_position = _cam_pos
	cam.fov = 50.0
	cam.look_at(cp + Vector3.UP * 0.6 - fwd * 0.6, Vector3.UP)
	return true


# --- drawing ------------------------------------------------------------------------

func _draw() -> void:
	var f: Font = Game.arcade_font
	var p: Node3D = main.race.player if main.race else null
	if p == null or not is_instance_valid(p):
		return
	# Pit road speed: the limit and five lights.
	if not showing and (p.pit_state == 2 or p.pit_state == 4) and main.track.in_pit_zone(p.s()):
		var lim: float = main.race.control.pit_speed * 2.237 if main.race.control else 45.0
		var mph: float = p.speed() * 2.237
		var x := 18.0
		var y: float = hud.H * 0.42
		draw_rect(Rect2(x, y, 170, 46), Color(0.04, 0.05, 0.09, 0.85))
		draw_string(f, Vector2(x + 8, y + 15), "PIT ROAD  %d MPH" % int(round(lim)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.85, 0.2))
		for k in 5:
			# Four greens up to the limit (all four lit: right on it), red over it.
			var thr: float = lim * (0.85 + k * 0.05) - 0.5 if k < 4 else lim + 1.0
			var on: bool = mph >= thr
			var col := Color(0.2, 0.9, 0.3) if k < 4 else Color(1.0, 0.2, 0.15)
			if mph > lim + 1.0:
				col = Color(1.0, 0.2, 0.15)
			draw_rect(Rect2(x + 8 + k * 30, y + 24, 24, 14), col if on else Color(0.15, 0.15, 0.2))
	if active() and car == p:
		_draw_stop(f)
	if _summary_t > 0.0 and not active():
		pass # the summary goes up as a crew chief's call


func _draw_stop(f: Font) -> void:
	var x := 18.0
	var y: float = hud.H * 0.38
	var w := 210.0
	var h := 150.0
	draw_rect(Rect2(x, y, w, h), Color(0.04, 0.05, 0.09, 0.88))
	draw_rect(Rect2(x, y, w, 20), Color(0.85, 0.65, 0.05))
	draw_string(f, Vector2(x + 8, y + 15), "PIT STOP" + ("  (REPLAY)" if showing else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.05, 0.05, 0.05))
	var t_now: float = min(clock, _total)
	draw_string(f, Vector2(x + w - 60, y + 15), "%.1f" % t_now, HORIZONTAL_ALIGNMENT_RIGHT, 52, 13, Color(0.05, 0.05, 0.05))
	# The tyres: right side first, then the left (as the crew does them).
	var corners: Array = stop.get("corners", [])
	var tyre_t: float = float(stop.get("tyre_t", 0.0))
	var prog: float = clamp(t_now / max(tyre_t, 0.1), 0.0, 1.0)
	var names := ["LF", "RF", "LR", "RR"]
	var pos := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]
	var right_only: bool = not (corners.has(0) or corners.has(2))
	for i in 4:
		var bx: float = x + 12 + pos[i].x * 52
		var by: float = y + 30 + pos[i].y * 38
		var col := Color(0.25, 0.27, 0.32)
		var label := "-"
		if corners.has(i):
			# Right side tyres (1, 3) in the first half, left (0, 2) in the second.
			var a: float = 0.0 if (i == 1 or i == 3 or right_only) else 0.48
			var b: float = 0.45 if (i == 1 or i == 3) and not right_only else 1.0
			var q: float = clamp((prog - a) / max(b - a, 0.01), 0.0, 1.0)
			col = Color(0.85, 0.65, 0.1).lerp(Color(0.25, 0.85, 0.35), q) if q > 0.0 else Color(0.4, 0.4, 0.45)
			label = "NEW" if q >= 1.0 else ("%d%%" % int(q * 100.0) if q > 0.0 else "")
		draw_rect(Rect2(bx, by, 44, 30), col)
		draw_string(f, Vector2(bx, by + 12), names[i], HORIZONTAL_ALIGNMENT_CENTER, 44, 10, Color.WHITE)
		draw_string(f, Vector2(bx, by + 25), label, HORIZONTAL_ALIGNMENT_CENTER, 44, 9, Color.WHITE)
	# Fuel.
	var fuel_t: float = float(stop.get("fuel_t", 0.0))
	var fq: float = clamp(t_now / max(fuel_t, 0.1), 0.0, 1.0) if fuel_t > 0.05 else 1.0
	draw_string(f, Vector2(x + 122, y + 40), "FUEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.85, 0.95))
	draw_rect(Rect2(x + 122, y + 46, 76, 10), Color(0.15, 0.15, 0.2))
	draw_rect(Rect2(x + 122, y + 46, 76 * fq, 10), Color(1.0, 0.75, 0.15))
	var notes := []
	if float(stop.get("wedge", 0.0)) > 0.0:
		notes.append("WEDGE IN")
	elif float(stop.get("wedge", 0.0)) < 0.0:
		notes.append("WEDGE OUT")
	if float(stop.get("repair", 0.0)) > 0.0:
		notes.append("REPAIRS")
	for k in notes.size():
		draw_string(f, Vector2(x + 122, y + 76 + k * 13), notes[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.75, 0.85, 1.0))
	# GO.
	var go: bool = (showing and _go_t >= 0.0) or (not showing and car.pit_timer <= 0.0)
	if go:
		var blink: bool = int(Time.get_ticks_msec() / 150) % 2 == 0
		draw_rect(Rect2(x, y + h - 40, w, 40), Color(0.1, 0.65, 0.2) if blink else Color(0.05, 0.4, 0.12))
		draw_string(f, Vector2(x, y + h - 14), "GO! GO! GO!", HORIZONTAL_ALIGNMENT_CENTER, w, 20, Color.WHITE)
	elif not showing:
		var hint := "HIT THE GAS ON GO" if not Game.touch_active or int(Game.settings.get("auto_gas", 0)) == 0 else "THE CREW SENDS YOU"
		draw_string(f, Vector2(x, y + h - 14), hint, HORIZONTAL_ALIGNMENT_CENTER, w, 11, Color(1.0, 0.85, 0.3))
	else:
		draw_string(f, Vector2(x, y + h - 14), "TAP TO SKIP", HORIZONTAL_ALIGNMENT_CENTER, w, 10, Color(0.7, 0.75, 0.85))
