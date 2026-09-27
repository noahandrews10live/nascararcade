extends Node
## Showtime: the presentation around the racing.
##   - the intro: a helicopter sweep of the track, the field thundering by a
##     trackside camera, a jet flyover and the anthem, before the logo;
##   - a studio showroom for car select and the paint shop: the car on a lit
##     turntable, revving when you pick it, its paint going on over grey primer;
##   - the TV package: a running-order ticker, NEW LEADER and FASTEST LAP bugs,
##     BATTLE FOR POSITION call-outs and a two-voice commentary booth;
##   - wreck replays: a big crash is shown again in slow motion from three angles
##     while the race holds, then "back to live";
##   - last-lap drama: the music builds, the crowd rises, the camera tightens,
##     and a close finish goes to slow motion on a finish-line camera;
##   - victory: your burnout (you drive it), then victory lane with the car,
##     the driver up top with the trophy, confetti and fireworks.

const Music := preload("res://scripts/music.gd")
const Car := preload("res://scripts/car.gd")

var main: Node
var music: Node
var layer: CanvasLayer
var ui: Control

# TV package
var _ticker: Label
var _ticker_t := 0.0
var _bug: Label # NEW LEADER / FASTEST LAP / PHOTO FINISH
var _bug_t := 0.0
var _battle: Label
var _battle_t := 0.0
var _battle_cool := 0.0
var _battle_pair := ""
var _battle_since := 0.0
var _replay_bug: Label
var _booth: Label
var _booth_t := 0.0
var _leader: Node3D
var _fastest := 0.0
var _race_ref: Node3D

# Commentary
var _say_cool := 0.0
var _pending: Array = [] # [delay, who, text]

# Intro
var intro_active := false
var intro_t := 0.0
const INTRO_LEN := 11.0
var _jets: Array = []
var _intro_done_once := false

# Showroom
var showroom: Node3D
var _paint_t := 1.0
var _rev_t := 9.0

# Wreck replay
var replay_active := false
var _rp_t := 0.0
var _rp_start := 0.0
var _rp_end := 0.0
var _rp_car: Node3D
var _rp_snapshot: Array = []
var _rp_pending := -1.0 # seconds until the replay starts
var _rp_center := 0.0
var _rp_cool := 0.0
var _rp_hud := true
var _rp_real := 0.0
var clip_mode := false # replaying the last 15 s for a video clip

# Last lap / photo finish
var fov_offset := 0.0
var _last_lap := false
var photo_finish := false
var _pf_t := 0.0

# Victory
var victory_active := false
var _v_t := 0.0
var _v_car: Node3D
var _v_stage: Node3D
var _v_clone: Node3D


func setup(m: Node) -> void:
	main = m
	music = Music.new()
	add_child(music)
	layer = CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	_ticker = _mk_label(12, Color(1, 1, 1))
	_bug = _mk_label(22, Color(1, 0.85, 0.15))
	_bug.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_battle = _mk_label(15, Color(1, 1, 1))
	_battle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_replay_bug = _mk_label(20, Color(1, 0.25, 0.2))
	_booth = _mk_label(13, Color(0.85, 0.95, 1.0))
	_booth.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for l in [_ticker, _bug, _battle, _replay_bug, _booth]:
		l.visible = false


func _mk_label(size: int, col: Color) -> Label:
	var l: Label = Game.make_label("", size, col, 5)
	ui.add_child(l)
	return l


func _panel_style(l: Label, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	l.add_theme_stylebox_override("normal", sb)


# --- per frame ------------------------------------------------------------------

func process(delta: float) -> void:
	var sr: Rect2 = Game.safe_rect(get_viewport())
	var racing: bool = main.state in [main.State.COUNTDOWN, main.State.RACE, main.State.FINISHED] and main.race != null and main.split_cams.is_empty()
	_layout(sr)
	if main.race != _race_ref:
		_race_ref = main.race
		_leader = null
		_fastest = 0.0
		_last_lap = false
		_welcomed = false
		_to_go_said.clear()
		_player_best = 99
		_player_mark = 99
		_player_mark_t = 0.0
		_story_t = 0.0
		_gap_t = 0.0
		_last_pit_leader = null
		if main.race and main.race.control and not main.race.control.message.is_connected(_on_control_message):
			main.race.control.message.connect(_on_control_message)
		if main.race and main.race.has_signal("lap_completed") and not main.race.lap_completed.is_connected(_on_lap):
			main.race.lap_completed.connect(_on_lap)
			main.race.incident.connect(_on_incident)
	_update_intro(delta)
	_update_showroom(delta)
	# TV package: only while racing, not in the cockpit-only arcade feel of the 1999 look.
	var tv: bool = racing and main.hud.visible and not replay_active
	_ticker.visible = tv and main.state != main.State.COUNTDOWN
	if _ticker.visible:
		_ticker_t -= delta
		if _ticker_t <= 0.0:
			_ticker_t = 1.0
			_ticker.text = _ticker_text()
	_bug_t -= delta
	_bug.visible = _bug_t > 0.0 and (tv or replay_active or victory_active)
	_battle_t -= delta
	_battle_cool -= delta
	_battle.visible = tv and _battle_t > 0.0
	if tv and main.state == main.State.RACE:
		_watch_leader()
		_watch_battles(delta)
		_watch_story(delta)
	if racing and main.state == main.State.COUNTDOWN and not _welcomed and not intro_active:
		_welcomed = true
		say("pbp", _line("welcome") % _track_name().capitalize())
		say("color", _line("welcome_color"), 1.0)
	_booth_t -= delta
	_booth.visible = _booth_t > 0.0
	_update_commentary(delta)
	_update_last_lap(delta, racing)
	_update_music(racing)
	if _rp_pending >= 0.0 and not replay_active:
		_rp_pending -= delta
		if _rp_pending < 0.0:
			_start_replay(_rp_car, _rp_center, false)
	_rp_cool -= delta


func _layout(sr: Rect2) -> void:
	_ticker.position = Vector2(sr.position.x, sr.end.y - 24)
	_ticker.size = Vector2(sr.size.x, 20)
	_ticker.clip_text = true
	# Captions stay in the middle, clear of the course map and the buttons
	# beside it (top right), wrapping onto two lines on a narrow screen.
	var inset := 0.0
	if main.hud and sr.size.y < sr.size.x:
		inset = max(0.0, sr.size.x - main.hud.map_rect().position.x + 70.0)
	for l: Label in [_bug, _battle]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bug.position = Vector2(sr.position.x + inset, sr.position.y + sr.size.y * 0.2)
	_bug.size = Vector2(sr.size.x - inset * 2.0, 30)
	_battle.position = Vector2(sr.position.x + inset, sr.position.y + sr.size.y * 0.27)
	_battle.size = Vector2(sr.size.x - inset * 2.0, 24)
	_replay_bug.position = sr.position + Vector2(14, 12)
	_booth.position = Vector2(sr.position.x + sr.size.x * 0.2, sr.end.y - 70)
	_booth.size = Vector2(sr.size.x * 0.6, 40)
	_booth.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _name(c: Node3D) -> String:
	var d: String = String(c.team.driver)
	return "#%s %s" % [c.team.num, d.get_slice(" ", d.get_slice_count(" ") - 1)]


func _ticker_text() -> String:
	var race: Node3D = main.race
	if race.order.is_empty():
		return ""
	var lead: Node3D = race.order[0]
	var parts := []
	for i in min(race.order.size(), 12):
		var c: Node3D = race.order[i]
		var gap := ""
		if i > 0:
			var dd: float = lead.dist - c.dist
			var laps := int(dd / race.track.length)
			gap = ("  -%d L" % laps) if laps >= 1 else ("  +%.2f" % (dd / max(lead.speed(), 20.0)))
		var me := " <" if c == race.player else ""
		parts.append("%d %s%s%s" % [i + 1, _name(c), gap, me])
	return "  |  ".join(parts)


func show_bug(text: String, seconds := 3.0, col := Color(1, 0.85, 0.15)) -> void:
	_bug.text = text
	_bug.label_settings.font_color = col
	_bug_t = seconds


func _watch_leader() -> void:
	var race: Node3D = main.race
	if race.order.is_empty():
		return
	var l: Node3D = race.order[0]
	if _leader == null:
		_leader = l
		return
	if l != _leader and race.time > 20.0:
		_leader = l
		show_bug("NEW LEADER  %s" % _name(l), 3.0)
		say("pbp", _line("lead") % _spoken(l))
		if randf() < 0.6:
			say("color", _line("lead_color"), 2.8)


func _watch_battles(delta: float) -> void:
	var race: Node3D = main.race
	var best := ""
	var best_pair: Array = []
	for i in range(0, min(race.order.size() - 1, 10)):
		var a: Node3D = race.order[i]
		var b: Node3D = race.order[i + 1]
		if a.pit_state != 0 or b.pit_state != 0:
			continue
		var gap: float = (a.dist - b.dist) / max(a.speed(), 20.0)
		if gap < 0.25:
			best = "%d" % (i + 1)
			best_pair = [a, b]
			break
	if best == "" or best != _battle_pair:
		_battle_pair = best
		_battle_since = 0.0
		return
	_battle_since += delta
	if _battle_since > 3.0 and _battle_cool <= 0.0:
		_battle_cool = 25.0
		_battle_t = 5.0
		_battle.text = "BATTLE FOR %s:  %s  vs  %s" % ["THE LEAD" if best == "1" else Game.ordinal(int(best)), _name(best_pair[0]), _name(best_pair[1])]
		main.soundscape.cheer(0.55)
		var spot: String = "the lead" if best == "1" else Game.ordinal(int(best)).to_lower()
		var bl := _line("battle")
		if bl.begins_with("What"):
			say("pbp", bl % [spot, _spoken(best_pair[0]), _spoken(best_pair[1])])
		else:
			say("pbp", bl % [_spoken(best_pair[0]), _spoken(best_pair[1]), spot])


func _on_lap(car: Node3D, _laps_done: int, lap_time: float) -> void:
	if lap_time <= 0.0 or main.race == null or car.get_meta("lap_void", false):
		return
	if _fastest == 0.0 or lap_time < _fastest - 0.001:
		var first := _fastest == 0.0
		_fastest = lap_time
		if not first and main.state == main.State.RACE:
			show_bug("FASTEST LAP  %s  %s" % [_name(car), Game.format_time(lap_time)], 3.0, Color(0.75, 0.45, 1.0))
			if randf() < 0.4:
				say("color", _line("fastest") % _spoken(car))


func _spoken(c: Node3D) -> String:
	var d: String = String(c.team.driver)
	return "the number %s of %s" % [c.team.num, d.get_slice(" ", d.get_slice_count(" ") - 1).capitalize()] if randf() < 0.4 else d.get_slice(" ", d.get_slice_count(" ") - 1).capitalize()


# --- commentary -----------------------------------------------------------------

## What the booth says, a handful of ways each so it doesn't repeat itself.
## %s is filled in by the caller.
const LINES := {
	"welcome": ["Welcome to %s! Forty of the best are strapped in and ready.", "Good afternoon from %s, and what a day for a race!", "We're live at %s. Engines are warm, the crowd is loud."],
	"welcome_color": ["Track position is going to be everything today.", "Keep an eye on tire wear. This place chews them up.", "It's all about the restarts at a place like this.", "Nobody wins it on the first lap, but plenty lose it there."],
	"green": ["And we're green! Here they come!", "Green flag! The field roars into turn one!", "They're off, and it's three wide already!", "Green, green, green! Let's go racing!"],
	"restart": ["Back to green, and they're racing again!", "The restart is clean, and they're off!", "Green flag on the restart, and here comes the push!"],
	"caution": ["Caution's out!", "Yellow flag, the field slows down.", "And there's the caution."],
	"caution_color": ["Crew chiefs are doing the math on pit strategy right now.", "That bunches them back up. Anybody can win this.", "Fresh tires or track position? That's the big call."],
	"lead": ["%s takes the lead!", "And %s powers to the front!", "New leader: %s!", "%s gets by for the lead!", "There goes %s, into the lead!"],
	"lead_color": ["That was a great run off the corner.", "That pass has been coming for a few laps.", "Look at the momentum carried through there.", "Perfect use of the draft to make that happen.", "A textbook move for the lead."],
	"battle": ["What a battle for %s! %s and %s, side by side!", "%s and %s are going at it for %s!"],
	"fastest": ["%s just set the fastest lap of the race.", "That's the quickest lap of the day for %s.", "%s is flying. Fastest lap so far."],
	"incident": ["Trouble! %s is around!", "Oh no, %s gets loose!", "Big moment for %s!", "%s is in trouble!", "Smoke! %s is spinning!"],
	"incident_color": ["That's going to hurt the points.", "Took away the air off the nose, and around it went.", "Nowhere to go there.", "They got into the marbles and that was it."],
	"white": ["White flag! One lap to go!", "There's the white flag! One more time around!"],
	"white_color": ["This is where it's won or lost.", "Everybody's going for it now.", "Hold on to your seats, folks."],
	"to_go_10": ["Ten laps to go, and %s still leads.", "Ten to go! %s out front."],
	"to_go_5": ["Five laps to go! %s leads by %s.", "Five to go, %s with a gap of %s."],
	"gap": ["%s leads by %s over %s.", "Out front it's %s, %s clear of %s.", "%s with a %s cushion over %s."],
	"up": ["%s is on the move, up to %s!", "Look at %s charging through the field, now %s!", "%s picks off another one, running %s now."],
	"top10": ["%s has cracked the top ten!", "%s is now inside the top ten."],
	"top5": ["%s is into the top five!", "Here comes %s, into the top five!"],
	"pit_lead": ["The leader %s heads down pit road.", "%s brings it in from the lead."],
	"stage": ["%s wins stage %s!", "Stage %s goes to %s!"],
	"win": ["%s wins it!", "And %s takes the checkered flag!", "%s is your winner!", "Checkered flag! %s wins at %s!"],
	"win_color": ["What a drive. The class of the field today.", "Nobody had anything for them today.", "They made every right move when it mattered.", "That's a win they'll remember for a long time."],
	"filler": ["You can see the cars moving around looking for grip.", "The track's taking rubber now; the groove is widening.", "Fuel mileage could come into play here.", "These guys are running inches apart at speed.", "The crews are watching the tire temps closely.", "Listen to those engines. Nine thousand rpm."],
	"filler_draft": ["The draft is everything here. Nobody can get away alone.", "Watch for the big run from the back of this pack.", "You need friends at a place like this."],
	"victory_lane": ["And here comes the winner into victory lane!", "Victory lane, and the celebration is on!"],
}

var _recent_lines: Array = []
var _story_t := 0.0 # seconds since the booth last had something to say
var _gap_t := 0.0
var _welcomed := false
var _to_go_said := {}
var _player_best := 99
var _player_mark := 99
var _player_mark_t := 0.0
var _last_pit_leader: Node3D
var _voice_pbp := ""
var _voice_color := ""


## A line from the bank, not one said in the last few calls.
func _line(key: String) -> String:
	var opts: Array = LINES[key]
	var fresh: Array = opts.filter(func(o): return not _recent_lines.has(o))
	var pick: String = (fresh if not fresh.is_empty() else opts).pick_random()
	_recent_lines.append(pick)
	if _recent_lines.size() > 14:
		_recent_lines.pop_front()
	return pick


## Queue a line for the booth: "pbp" (play-by-play) or "color" (the analyst).
func say(who: String, text: String, delay := 0.0) -> void:
	if int(Game.settings.get("commentary", 1)) == 0:
		return
	if _pending.size() > 2:
		return
	_pending.append([delay, who, text])


func _update_commentary(delta: float) -> void:
	_say_cool -= delta
	if _pending.is_empty():
		return
	_pending[0][0] -= delta
	if _pending[0][0] > 0.0 or _say_cool > 0.0:
		return
	var p: Array = _pending.pop_front()
	var who: String = p[1]
	var text: String = p[2]
	_booth.text = ("BOOTH:  " if who == "pbp" else "ANALYST:  ") + text.to_upper()
	_booth_t = 4.0
	_say_cool = 3.0
	_story_t = 0.0
	if Game.radio_voice and main.state != main.State.REPLAY:
		if _voice_pbp == "":
			_pick_voices()
		if _voice_pbp != "":
			var v: String = _voice_pbp if who == "pbp" else _voice_color
			DisplayServer.tts_speak(text.to_lower(), v, 65, 1.0 if who == "pbp" else 0.9, 1.12 if who == "pbp" else 1.02, 0, false)


## The two booth voices: the most natural-sounding English voices the device
## has (the "natural", "neural", "enhanced" and premium ones first), and two
## different ones if there are two.
func _pick_voices() -> void:
	var all: Array = DisplayServer.tts_get_voices()
	var scored: Array = []
	for v in all:
		var lang: String = String(v.get("language", ""))
		if not lang.begins_with("en"):
			continue
		var nm: String = String(v.get("name", "")).to_lower()
		var sc := 0
		for good in ["natural", "neural", "online", "enhanced", "premium", "google us english", "google uk english"]:
			if nm.contains(good):
				sc += 10
		for named in ["samantha", "alex", "daniel", "aaron", "evan", "nathan", "guy", "davis", "tony", "jenny", "aria", "christopher", "eric"]:
			if nm.contains(named):
				sc += 4
		if lang.begins_with("en-US") or lang.begins_with("en_US"):
			sc += 2
		if nm.contains("compact") or nm.contains("espeak"):
			sc -= 5
		scored.append([sc, String(v.get("id", ""))])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	if scored.is_empty():
		var ids := DisplayServer.tts_get_voices_for_language("en")
		if ids.is_empty():
			return
		_voice_pbp = ids[0]
		_voice_color = ids[min(1, ids.size() - 1)]
		return
	_voice_pbp = scored[0][1]
	_voice_color = scored[min(1, scored.size() - 1)][1]


func _track_name() -> String:
	if main.race and main.race.track and main.race.track.cfg.has("name"):
		return String(main.race.track.cfg.name)
	return "the speedway"


## Stage wins and such from race control.
func _on_control_message(text: String, kind: String) -> void:
	if kind == "stage" and text.contains("#"):
		var who := text.get_slice("  ", 1).strip_edges() # "#7 BUCK RYDER"
		var stage := text.get_slice(" ", 1)
		var nm := who.get_slice(" ", who.get_slice_count(" ") - 1).capitalize()
		var l := _line("stage")
		say("pbp", l % [nm, stage] if l.begins_with("%s") else l % [stage, nm])


## The story of the race between the big moments: laps to go, the gap at the
## front, your charge through the field, the leader pitting, and the analyst
## filling a quiet moment.
func _watch_story(delta: float) -> void:
	var race: Node3D = main.race
	if race.order.size() < 2:
		return
	_story_t += delta
	_gap_t += delta
	var lead: Node3D = race.order[0]
	var second: Node3D = race.order[1]
	var gap: float = (lead.dist - second.dist) / max(lead.speed(), 20.0)
	var gap_s := "%.1f seconds" % gap if gap >= 1.0 else "half a second" if gap >= 0.4 else "a whisker"
	var to_go: int = race.laps - lead.lap() - 1
	if race.laps >= 12 and to_go == 10 and not _to_go_said.has(10):
		_to_go_said[10] = true
		say("pbp", _line("to_go_10") % _spoken(lead))
	elif race.laps >= 8 and to_go == 5 and not _to_go_said.has(5):
		_to_go_said[5] = true
		say("pbp", _line("to_go_5") % [_spoken(lead), gap_s])
	# The leader stops.
	if lead.pit_state != 0 and _last_pit_leader != lead:
		_last_pit_leader = lead
		say("pbp", _line("pit_lead") % _spoken(lead))
	# You, working through the field.
	var me: Node3D = race.player
	if me and not me.finished:
		var pos: int = race.position_of(me)
		_player_mark_t += delta
		if _player_mark == 99 or _player_mark_t > 40.0:
			_player_mark = pos
			_player_mark_t = 0.0
		if race.time > 20.0:
			if pos <= 5 and _player_best > 5:
				say("pbp", _line("top5") % _spoken(me))
				_player_mark = pos
			elif pos <= 10 and _player_best > 10 and race.cars.size() > 14:
				say("pbp", _line("top10") % _spoken(me))
				_player_mark = pos
			elif _player_mark - pos >= 3:
				say("pbp", _line("up") % [_spoken(me), Game.ordinal(pos).to_lower()])
				_player_mark = pos
				_player_mark_t = 0.0
		_player_best = min(_player_best, pos) if race.time > 20.0 else pos
	# Quiet for a while: the gap at the front, or the analyst.
	if _story_t > 22.0 and _gap_t > 45.0 and race.time > 40.0:
		_gap_t = 0.0
		say("pbp", _line("gap") % [_spoken(lead), gap_s, _spoken(second)])
	elif _story_t > 34.0:
		var ss: bool = race.track and int(race.track.cfg.get("hp", 0)) == 510
		say("color", _line("filler_draft" if ss and randf() < 0.6 else "filler"))


## Race events from main (flags, finishes).
func on_flag(flag: String) -> void:
	match flag:
		"GREEN":
			if main.race and main.race.time < 30.0:
				say("pbp", _line("green"))
			else:
				say("pbp", _line("restart"))
		"YELLOW":
			say("pbp", _line("caution"))
			if randf() < 0.5:
				say("color", _line("caution_color"), 3.0)
		"WHITE":
			say("pbp", _line("white"))
			say("color", _line("white_color"), 2.5)


func _on_incident(car: Node3D, kind: String) -> void:
	if main.state != main.State.RACE or main.race == null:
		return
	var big: bool = kind == "out" or car.tumbling or car.total_damage() > 0.25
	say("pbp", _line("incident") % _spoken(car))
	if big and randf() < 0.5:
		say("color", _line("incident_color"), 3.0)
	if big and _rp_cool <= 0.0 and _rp_pending < 0.0 and main.race.rec_times.size() > 40 and not main.paused and main.mode != "2p":
		_rp_car = car
		_rp_center = main.race.rec_clock
		_rp_pending = 2.5
		main.soundscape.cheer(0.9)


# --- wreck replay (and video clips) ---------------------------------------------

## Holds the race and shows `car` around rec-time `center` in slow motion from
## three angles. With `clip`, replays the last 15 seconds at full speed instead.
func _start_replay(car: Node3D, center: float, clip: bool) -> void:
	var race: Node3D = main.race
	if race == null or race.rec_times.size() < 20 or not is_instance_valid(car):
		return
	if main.state != main.State.RACE or main.paused:
		return
	replay_active = true
	clip_mode = clip
	_rp_car = car
	_rp_cool = 45.0
	var t_end: float = race.rec_times[race.rec_times.size() - 1]
	if clip:
		_rp_start = max(race.rec_times[0], t_end - 15.0)
		_rp_end = t_end
	else:
		_rp_start = max(race.rec_times[0], center - 3.0)
		_rp_end = min(t_end, center + 3.5)
	_rp_t = _rp_start
	_rp_real = 0.0
	_rp_snapshot.clear()
	for c in race.rec_cars:
		_rp_snapshot.append([c, c.tumbling, c.dist, c.d, c.yaw, c.v, c.visible, c.chassis_roll, c.chassis_pitch, c.chassis_z, c.spinning, c.r, c.slide, c.scrub, c.scraping])
	_rp_hud = main.hud.visible
	main.hud.visible = false
	main.touch.visible = false
	_replay_bug.text = "REPLAY" if not clip else "CLIP  -  RECORDING"
	_replay_bug.visible = true
	show_bug(_name(car) if not clip else "", 2.0, Color.WHITE)


func request_clip() -> void:
	if replay_active or main.race == null:
		return
	var focus: Node3D = main.race.player if main.race.player else main.race.order[0]
	_start_replay(focus, 0.0, true)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.stClipStart && window.stClipStart()")


## Runs instead of the race while a replay is on. Returns true when it did.
func physics(delta: float) -> bool:
	if not replay_active:
		return false
	var rate := 1.0 if clip_mode else 0.4
	_rp_real += delta
	_rp_t += delta * rate
	main.race.replay_apply(min(_rp_t, _rp_end))
	var skip: bool = Input.is_action_just_pressed("start") or Input.is_action_just_pressed("back")
	if _rp_t >= _rp_end or (skip and _rp_real > 0.5):
		_end_replay()
	return true


func _end_replay() -> void:
	replay_active = false
	for s in _rp_snapshot:
		var c: Node3D = s[0]
		if not is_instance_valid(c):
			continue
		c.tumbling = s[1]
		c.dist = s[2]
		c.d = s[3]
		c.yaw = s[4]
		c.v = s[5]
		c.visible = s[6]
		c.chassis_roll = s[7]
		c.chassis_pitch = s[8]
		c.chassis_z = s[9]
		c.spinning = s[10]
		c.r = s[11]
		c.slide = s[12]
		c.scrub = s[13]
		c.scraping = s[14]
		c.sync_visual(false)
		c._tr_prev = c._tr_cur
	_rp_snapshot.clear()
	main.hud.visible = _rp_hud
	main.touch.visible = main.touch.active
	_replay_bug.visible = false
	if clip_mode and OS.has_feature("web"):
		JavaScriptBridge.eval("window.stClipStop && window.stClipStop()")
		show_bug("CLIP SAVED", 2.0, Color(0.4, 1.0, 0.5))
	elif clip_mode:
		main._take_photo()
		show_bug("PHOTO SAVED (VIDEO CLIPS: BROWSER / PHONE VERSION)", 2.5, Color(0.4, 1.0, 0.5))
	else:
		show_bug("BACK TO LIVE", 1.5, Color(1, 1, 1))
	clip_mode = false


# --- cameras ----------------------------------------------------------------------

## Takes over the camera for the intro, replays, the photo finish and victory
## lane. Returns true when it did.
func camera(delta: float) -> bool:
	var cam: Camera3D = main.cam
	if intro_active:
		_intro_camera(delta)
		return true
	if replay_active and is_instance_valid(_rp_car):
		var third := (_rp_end - _rp_start) / 3.0
		var shot := 0 if clip_mode else clampi(int((_rp_t - _rp_start) / max(third, 0.1)), 0, 2)
		match shot:
			0:
				if clip_mode:
					main._chase_camera(_rp_car, delta, 0)
				else:
					main.tv_target = _rp_car
					main.tv_mode = 3
					main._tv_camera(delta, true)
			1:
				main._chase_camera(_rp_car, delta, 0)
			_:
				main._blimp_camera(_rp_car, delta)
		return true
	if photo_finish:
		var tr: Node3D = main.track
		var i := 0
		var p: Vector3 = tr.pos[i] + tr.right[i] * (tr.outer_edge() + 6.0) + Vector3.UP * 1.6
		cam.global_position = p
		cam.fov = 38.0
		cam.look_at(tr.pos[i] + tr.right[i] * (tr.width * -0.1) + Vector3.UP * 0.8, Vector3.UP)
		return true
	if victory_active and _v_t > VIC_LANE and is_instance_valid(_v_clone):
		# From the infield side, looking out at the grandstands, swinging slowly.
		var tr: Node3D = main.track
		var c: Vector3 = _v_clone.global_position
		var a: float = sin((_v_t - VIC_LANE) * 0.3) * 0.7
		var back: Vector3 = (-tr.right[0]).rotated(Vector3.UP, a)
		cam.fov = 48.0
		cam.global_position = c + back * 8.0 + Vector3.UP * (1.8 + 0.4 * sin(_v_t * 0.5))
		cam.look_at(c + Vector3.UP * 1.5, Vector3.UP)
		return true
	return false


# --- intro ----------------------------------------------------------------------

## The first time the title comes up: a cinematic lap of the track before the logo.
func start_intro() -> void:
	if _intro_done_once or OS.get_environment("ST_NO_INTRO") == "1" or DisplayServer.get_name() == "headless":
		return
	_intro_done_once = true
	intro_active = true
	intro_t = 0.0
	music.play("anthem")
	main.ui_root.modulate.a = 0.0
	main.hud.visible = false


func skip_intro() -> void:
	if intro_active:
		intro_t = INTRO_LEN


func _update_intro(delta: float) -> void:
	if not intro_active:
		return
	intro_t += delta
	# The logo fades in over the last two seconds.
	main.ui_root.modulate.a = clamp((intro_t - (INTRO_LEN - 2.0)) / 2.0, 0.0, 1.0)
	if intro_t > 5.2 and _jets.is_empty():
		_launch_jets()
	for j in _jets:
		j.position += j.get_meta("vel") * delta
	if intro_t >= INTRO_LEN:
		intro_active = false
		main.ui_root.modulate.a = 1.0
		for j in _jets:
			j.queue_free()
		_jets.clear()
		music.play("menu")


func _intro_camera(_delta: float) -> void:
	var cam: Camera3D = main.cam
	var tr: Node3D = main.track
	var race: Node3D = main.race
	var t := intro_t
	var mid := Vector3.ZERO
	for i in range(0, tr.n, max(1, tr.n / 16)):
		mid += tr.pos[i]
	mid /= float(ceil(tr.n / float(max(1, tr.n / 16))))
	if t < 4.5:
		# Helicopter: a high, slow orbit that descends toward the start line.
		var a := t * 0.22 + 0.4
		var r: float = tr.length / TAU * 1.25
		cam.fov = 55.0
		cam.global_position = mid + Vector3(sin(a) * r, lerp(220.0, 90.0, t / 4.5), cos(a) * r)
		cam.look_at(mid.lerp(tr.pos[0], t / 4.5), Vector3.UP)
	elif t < 8.0 and race and not race.order.is_empty():
		# Trackside, low on the wall: the field thunders past.
		var lead: Node3D = race.order[0]
		var s: float = fposmod(lead.s() + 120.0, tr.length)
		var i: int = int(s / tr.length * tr.n) % tr.n
		cam.fov = 42.0
		cam.global_position = tr.surface_point(float(i) / tr.n * tr.length, tr.inner_edge() - 2.0) + Vector3.UP * 1.3
		cam.look_at(lead.global_position + Vector3.UP * 0.8, Vector3.UP)
	else:
		# Up over the grandstand as the jets clear and the logo comes in.
		var i := 0
		var k: float = clamp((t - 8.0) / 3.0, 0.0, 1.0)
		cam.fov = 60.0
		cam.global_position = tr.pos[i] + tr.right[i] * (tr.outer_edge() + 25.0 - 10.0 * k) + Vector3.UP * lerp(12.0, 45.0, k)
		cam.look_at(tr.pos[i] + tr.fwd[i] * 60.0 + Vector3.UP * lerp(8.0, 40.0, k), Vector3.UP)


func _launch_jets() -> void:
	var tr: Node3D = main.track
	var i := 0
	var dir: Vector3 = -tr.fwd[i]
	var start: Vector3 = tr.pos[i] + tr.fwd[i] * 700.0 + Vector3.UP * 140.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.45, 0.5)
	mat.metallic = 0.6
	mat.roughness = 0.35
	for k in 4:
		var jet := Node3D.new()
		var off: Vector3 = Vector3(0, -k * 3.0, 0) + tr.right[i] * (float(k) - 1.5) * 16.0 + dir * -abs(float(k) - 1.5) * 14.0
		jet.position = start + off
		jet.set_meta("vel", dir * 190.0)
		main.add_child(jet)
		jet.look_at_from_position(jet.position, jet.position + dir, Vector3.UP)
		for part in [[Vector3(1.2, 1.1, 14.0), Vector3.ZERO], [Vector3(10.0, 0.25, 3.5), Vector3(0, 0, 1.0)], [Vector3(4.0, 0.2, 1.8), Vector3(0, 0.3, 6.0)], [Vector3(0.2, 2.2, 2.0), Vector3(0, 1.3, 6.0)]]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = part[0]
			mi.mesh = bm
			mi.material_override = mat
			mi.position = part[1]
			jet.add_child(mi)
		var trail := CPUParticles3D.new()
		trail.amount = 60
		trail.lifetime = 2.5
		trail.position = Vector3(0, 0, 7.5)
		trail.direction = Vector3(0, 0, 1)
		trail.spread = 4.0
		trail.initial_velocity_min = 2.0
		trail.initial_velocity_max = 4.0
		trail.gravity = Vector3.ZERO
		trail.scale_amount_min = 1.5
		trail.scale_amount_max = 3.0
		trail.color = Color(1, 1, 1, 0.5)
		var qm := QuadMesh.new()
		qm.size = Vector2(1.5, 1.5)
		var pm := StandardMaterial3D.new()
		pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.vertex_color_use_as_albedo = true
		qm.material = pm
		trail.mesh = qm
		trail.local_coords = false
		jet.add_child(trail)
		_jets.append(jet)
	main.soundscape.cheer(1.0)
	main.synth.crash(0.35) # the roar arriving


# --- showroom -------------------------------------------------------------------

## A studio for car select and the paint shop: dark room, glossy floor, a lit
## turntable. Returns where the car sits.
func showroom_spot() -> Vector3:
	if showroom == null or not is_instance_valid(showroom):
		_build_showroom()
	return showroom.global_position + Vector3(0, 0.12, 0)


func _build_showroom() -> void:
	showroom = Node3D.new()
	showroom.name = "Showroom"
	main.add_child(showroom)
	showroom.global_position = Vector3(0, -600.0, 0)
	var room := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 16.0
	cyl.bottom_radius = 16.0
	cyl.height = 12.0
	cyl.flip_faces = true
	room.mesh = cyl
	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.13, 0.14, 0.17)
	wall.roughness = 0.9
	room.material_override = wall
	room.position = Vector3(0, 5.9, 0)
	showroom.add_child(room)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(32, 32)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.03, 0.03, 0.035)
	fm.metallic = 0.3
	fm.roughness = 0.12
	floor.material_override = fm
	showroom.add_child(floor)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 4.2
	dm.bottom_radius = 4.3
	dm.height = 0.12
	dm.radial_segments = 64
	disc.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.12, 0.12, 0.14)
	dmat.metallic = 0.7
	dmat.roughness = 0.25
	disc.material_override = dmat
	disc.position = Vector3(0, 0.06, 0)
	showroom.add_child(disc)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 4.25
	tm.outer_radius = 4.35
	tm.rings = 64
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.emission_enabled = true
	rmat.emission = Color(0.4, 0.75, 1.0)
	rmat.emission_energy_multiplier = 3.0
	rmat.albedo_color = Color(0.4, 0.75, 1.0)
	ring.material_override = rmat
	ring.position = Vector3(0, 0.12, 0)
	showroom.add_child(ring)
	# Light panels overhead, and light strips round the walls: a studio, not
	# a void.
	var panel_m := StandardMaterial3D.new()
	panel_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel_m.albedo_color = Color(1.0, 0.98, 0.94)
	var pq := BoxMesh.new()
	pq.size = Vector3(1.2, 0.05, 7.0)
	for k in 5:
		var pn := MeshInstance3D.new()
		pn.mesh = pq
		pn.material_override = panel_m
		pn.position = Vector3(-4.8 + k * 2.4, 10.5, 0)
		showroom.add_child(pn)
	var strip_m := StandardMaterial3D.new()
	strip_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strip_m.albedo_color = Color(0.35, 0.7, 1.0)
	var sq := BoxMesh.new()
	sq.size = Vector3(0.08, 9.0, 0.08)
	for k in 16:
		var a := TAU * k / 16.0
		var st := MeshInstance3D.new()
		st.mesh = sq
		st.material_override = strip_m
		st.position = Vector3(sin(a) * 15.8, 4.6, cos(a) * 15.8)
		showroom.add_child(st)
	var band := MeshInstance3D.new()
	var bt := TorusMesh.new()
	bt.inner_radius = 15.7
	bt.outer_radius = 15.85
	bt.rings = 96
	band.mesh = bt
	band.material_override = strip_m
	band.position = Vector3(0, 0.3, 0)
	showroom.add_child(band)
	# Key, fill and two rim lights.
	for L in [[Vector3(5, 7, 5), Color(1.0, 0.96, 0.9), 5.0], [Vector3(-6, 5, 3), Color(0.8, 0.88, 1.0), 2.2], [Vector3(-3, 4, -7), Color(0.6, 0.8, 1.0), 4.0], [Vector3(5, 3, -6), Color(1.0, 0.7, 0.5), 3.0]]:
		var sl := SpotLight3D.new()
		sl.light_color = L[1]
		sl.light_energy = L[2]
		sl.spot_range = 22.0
		sl.spot_angle = 38.0
		sl.shadow_enabled = L[2] > 4.5
		showroom.add_child(sl)
		sl.look_at_from_position(showroom.global_position + L[0], showroom.global_position + Vector3(0, 0.6, 0), Vector3.UP)


## The car on show changed: rev it and paint it.
func present_car(car: Node3D) -> void:
	_paint_t = 0.0
	_rev_t = 0.0
	main.orbit = 0.6 + PI - 1.3 # turns into its best angle as the paint goes on
	if car and car._body.has("paint"):
		(car._body.paint as StandardMaterial3D).albedo_color = Color(0.3, 0.31, 0.33)


func _update_showroom(delta: float) -> void:
	var car: Node3D = main.preview_car
	_paint_t += delta
	_rev_t += delta
	if car and is_instance_valid(car) and car._body.has("paint"):
		var k: float = clamp((_paint_t - 0.15) / 0.7, 0.0, 1.0)
		(car._body.paint as StandardMaterial3D).albedo_color = Color(0.3, 0.31, 0.33).lerp(Color.WHITE, k * k * (3.0 - 2.0 * k))
	if showroom and is_instance_valid(showroom):
		showroom.visible = main.state in [main.State.CAR_SELECT, main.State.MENU, main.State.MODE_SELECT] and car != null and is_instance_valid(car)


## A blip of the throttle on the car in the showroom. Returns true while it plays.
func engine_blip() -> bool:
	if _rev_t > 1.6 or not main.state in [main.State.CAR_SELECT, main.State.MENU, main.State.MODE_SELECT]:
		return false
	var synth = main.synth
	synth.engine_on = true
	synth.master = 0.8
	var t := _rev_t
	synth.engine_rpm = 1800.0 + 7200.0 * (sin(clamp(t / 0.55, 0.0, 1.0) * PI * 0.5) if t < 0.55 else clamp(1.0 - (t - 0.55) / 0.9, 0.0, 1.0))
	synth.engine_load = 1.0 if t < 0.55 else 0.0
	synth.wind = 0.0
	synth.squeal = 0.0
	return true


## Music outside the big moments: a tense pulse under caution, a groove for
## qualifying runs, and the wind-down behind the results.
func _update_music(racing: bool) -> void:
	if intro_active or victory_active or _last_lap or music.cue == "anthem":
		return
	var st: int = main.state
	if st == main.State.RESULTS:
		if music.cue != "victory":
			music.play("results")
		return
	if not racing or main.race == null:
		if music.cue in ["caution", "qualify", "results"]:
			music.stop()
		return
	var ctl: Node = main.race.control
	var yellow: bool = ctl != null and ctl.flag == ctl.Flag.YELLOW
	if yellow and st == main.State.RACE:
		music.play("caution")
	elif main.session == "qualify" and st == main.State.RACE:
		music.play("qualify")
	elif music.cue in ["caution", "qualify", "results"]:
		music.stop()


# --- last lap and photo finish ------------------------------------------------------

func _update_last_lap(delta: float, racing: bool) -> void:
	var race: Node3D = main.race
	fov_offset = move_toward(fov_offset, 0.0, delta * 2.0)
	if not racing or race == null or race.order.is_empty() or intro_active:
		if music.cue == "lastlap" and not victory_active:
			music.stop()
		_last_lap = false
		return
	var lead: Node3D = race.order[0]
	var last: bool = main.state == main.State.RACE and lead.lap() == race.laps - 1 and not lead.finished
	if last and not _last_lap:
		_last_lap = true
		music.play("lastlap")
		if main.mode == "arcade":
			say("pbp", "Final lap!")
	if _last_lap and main.state == main.State.RACE:
		var frac: float = fposmod(lead.dist, race.track.length) / race.track.length
		music.intensity = frac
		main.soundscape.cheer(0.5 + 0.5 * frac)
		if race.player and not race.player.finished:
			fov_offset = -6.0 * frac # the camera tightens on you
		# Photo finish: the first two nose to nose near the line.
		if race.order.size() > 1 and not photo_finish:
			var second: Node3D = race.order[1]
			var to_line: float = race.track.length - fposmod(lead.dist, race.track.length)
			if to_line < 60.0 and lead.dist - second.dist < 6.0:
				photo_finish = true
				_pf_t = 0.0
				Engine.time_scale = 0.25
	if photo_finish:
		_pf_t += delta / max(Engine.time_scale, 0.01)
		if race.finish_count >= 2 or _pf_t > 3.0 or main.state != main.State.RACE and main.state != main.State.FINISHED:
			photo_finish = false
			Engine.time_scale = 1.0
			var fin: Array = race.cars.filter(func(x): return x.finished).duplicate()
			fin.sort_custom(func(x, y): return x.finish_order < y.finish_order)
			if fin.size() >= 2:
				var a: Node3D = fin[0]
				var b: Node3D = fin[1]
				var margin: float = abs(b.finish_time - a.finish_time)
				show_bug("PHOTO FINISH!  %s BY %.3fs" % [_name(a), margin], 4.0)
				say("pbp", "Photo finish! %s wins it by %.3f of a second!" % [_spoken(a), margin])


func on_finished(car: Node3D, place: int) -> void:
	if place == 1:
		music.play("victory")
		if not photo_finish:
			var wl := _line("win")
			say("pbp", wl % [_spoken(car), _track_name()] if wl.count("%s") == 2 else wl % _spoken(car))
			if randf() < 0.7:
				say("color", _line("win_color"), 3.0)


# --- victory ------------------------------------------------------------------------

const VIC_BURNOUT := 3.0
const VIC_LANE := 11.0
const VIC_END := 21.0


func start_victory(car: Node3D) -> void:
	victory_active = true
	_v_t = 0.0
	_v_car = car
	music.play("victory")


## Runs in the FINISHED state for a win. Returns true while the celebration owns it.
func victory_physics(delta: float) -> bool:
	if not victory_active:
		return false
	var race: Node3D = main.race
	_v_t += delta
	var c := _v_car
	if not is_instance_valid(c):
		_end_victory()
		return false
	if _v_t < VIC_LANE:
		if _v_t > VIC_BURNOUT:
			# Your burnout: you drive it.
			if _v_t - delta <= VIC_BURNOUT:
				main._sub("BURNOUT!  HOLD THE GAS, STEER HARD", 4.0)
			c.ai = false
			c.throttle = Input.get_action_strength("accelerate")
			c.brake = Input.get_action_strength("brake") * 0.4
			c.steer_in = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
			if main.autopilot or OS.get_environment("ST_AUTO_BURNOUT") == "1":
				c.throttle = 1.0
				c.steer_in = -1.0
			if c.throttle > 0.5 and c.speed() < 30.0 and randf() < delta * 8.0:
				main.atmosphere.puff(c.global_position - c.global_transform.basis.z * -2.0, 1.2)
		race.tick(delta)
		if Input.is_action_just_pressed("start") and _v_t > VIC_BURNOUT + 1.0:
			_v_t = VIC_LANE
		return true
	if not is_instance_valid(_v_stage):
		_build_victory_lane()
	race.tick(delta)
	if _v_t > VIC_END or (Input.is_action_just_pressed("start") and _v_t > VIC_LANE + 1.0):
		_end_victory()
		main._enter_results()
	return true


func _build_victory_lane() -> void:
	var tr: Node3D = main.track
	var c := _v_car
	c.ai = true
	main.hud.visible = false
	_v_stage = Node3D.new()
	_v_stage.name = "VictoryLane"
	main.add_child(_v_stage)
	var i := 0
	var at: Vector3 = tr.pos[i] + tr.right[i] * (tr.inner_wall() - 9.0)
	_v_stage.global_position = at
	# The winning car, parked on a stage.
	_v_clone = Car.new()
	_v_stage.add_child(_v_clone)
	_v_clone.setup(c.team, null)
	_v_clone.global_position = at + Vector3(0, 0.3, 0)
	_v_clone.look_at_from_position(_v_clone.global_position, _v_clone.global_position + tr.fwd[i], Vector3.UP)
	var stage := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 5.5
	sm.bottom_radius = 5.8
	sm.height = 0.3
	stage.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.1, 0.1, 0.12)
	smat.metallic = 0.5
	smat.roughness = 0.3
	stage.material_override = smat
	stage.position = Vector3(0, 0.15, 0)
	_v_stage.add_child(stage)
	# The driver up on the roof with the trophy.
	var driver: Node3D = main.race_day._person(c.team.c1, c.team.c2) if main.race_day else Node3D.new()
	_v_clone.model.add_child(driver)
	driver.position = Vector3(0, 1.3, 0.3)
	if main.race_day:
		driver.pose = "arms_up"
	var cup := _trophy()
	_v_clone.model.add_child(cup)
	cup.position = Vector3(0.25, 3.05, 0.3)
	# Crew around the car.
	if main.race_day:
		for k in 6:
			var p = main.race_day._person(c.team.c1, c.team.c2, "cap")
			_v_stage.add_child(p)
			var a := TAU * k / 6.0
			p.position = Vector3(sin(a) * 4.2, 0.3, cos(a) * 4.2)
			p.rotation.y = a # facing the car
			p.pose = "cheer" if k % 2 == 0 else "wave"
	# Confetti.
	var conf := CPUParticles3D.new()
	conf.amount = 400
	conf.lifetime = 5.0
	conf.position = Vector3(0, 14, 0)
	conf.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	conf.emission_box_extents = Vector3(8, 1, 8)
	conf.direction = Vector3(0, -1, 0)
	conf.spread = 30.0
	conf.initial_velocity_min = 0.5
	conf.initial_velocity_max = 2.0
	conf.gravity = Vector3(0, -1.6, 0)
	conf.angular_velocity_min = -360.0
	conf.angular_velocity_max = 360.0
	conf.scale_amount_min = 0.6
	conf.scale_amount_max = 1.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.85, 0.1))
	grad.set_color(1, Color(0.95, 0.2, 0.25))
	grad.add_point(0.33, Color(0.2, 0.6, 1.0))
	grad.add_point(0.66, Color(1, 1, 1))
	conf.color_initial_ramp = grad
	var qm := QuadMesh.new()
	qm.size = Vector2(0.08, 0.12)
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.metallic = 0.6
	cm.roughness = 0.3
	qm.material = cm
	conf.mesh = qm
	_v_stage.add_child(conf)
	main.soundscape.cheer(1.0)
	show_bug("VICTORY LANE", 3.0)
	say("pbp", _line("victory_lane"))


func _trophy() -> Node3D:
	var n := Node3D.new()
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.78, 0.3)
	gold.metallic = 1.0
	gold.roughness = 0.18
	for part in [[0.16, 0.2, 0.08, 0.0], [0.03, 0.04, 0.35, 0.2], [0.2, 0.08, 0.3, 0.52], [0.24, 0.2, 0.06, 0.7]]:
		var mi := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = part[0]
		cy.bottom_radius = part[1]
		cy.height = part[2]
		cy.radial_segments = 24
		mi.mesh = cy
		mi.material_override = gold
		mi.position = Vector3(0, part[3], 0)
		n.add_child(mi)
	return n


func _end_victory() -> void:
	victory_active = false
	if is_instance_valid(_v_stage):
		_v_stage.queue_free()
	_v_stage = null
	_v_clone = null


## Whatever happens, leave the engine at normal speed when the race goes away.
func reset() -> void:
	Engine.time_scale = 1.0
	photo_finish = false
	if replay_active:
		_end_replay()
	_end_victory()
	_pending.clear()
	_rp_pending = -1.0
	_last_lap = false
	if music.cue in ["lastlap", "victory"]:
		music.play("menu")
