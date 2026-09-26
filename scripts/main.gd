extends Node3D
## Top level: owns the world, camera, UI and the arcade game flow
## (attract -> course select -> car select -> rolling start -> race -> results).

const Track := preload("res://scripts/track.gd")
const Race := preload("res://scripts/race.gd")
const Car := preload("res://scripts/car.gd")
const Hud := preload("res://scripts/hud.gd")
const Synth := preload("res://scripts/audio.gd")
const Menu := preload("res://scripts/menu.gd")

enum State { TITLE, MODE_SELECT, TRACK_SELECT, CAR_SELECT, MENU, COUNTDOWN, RACE, FINISHED, RESULTS, SESSION_RESULTS, STANDINGS, REPLAY }

const PACE_SPEED := 32.0
const SELECT_TIME := 20.0

var state := State.TITLE
var state_time := 0.0
var paused := false

var tracks := {}
var track: Node3D
var race: Node3D
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var synth: Node
var hud: Control
var ui_layer: CanvasLayer
var screen: Control
var pause_layer: CanvasLayer
var scan_rect: ColorRect
var preview_car: Node3D

# race flow
var countdown_step := 0
var time_left := 0.0
var lap_bonus := 0.0
var game_over_reason := ""
var new_records: PackedStringArray = []
var results_snapshot: Array = []

# camera
var cam_mode := 0
var cam_pos := Vector3.ZERO
var cam_back := Vector3.BACK
var cam_car: Node3D = null
var shake := 0.0
var tv_mode := 0
var tv_target: Node3D
var tv_timer := 0.0
var tv_anchor := Vector3.ZERO
var orbit := 0.0

# menu
var sel_timer := 0.0
var menu_labels := {}
var rng := RandomNumberGenerator.new()

## Set by automated tests: drive the player car with the AI.
var autopilot := false

## "arcade" = the 1999 cabinet game (clock, 16 cars). "race" = full NASCAR rules.
var mode := "arcade"
const MODES := [
	["ARCADE", "BEAT THE CLOCK. 16 CARS, SHORT RACES, NO CAUTIONS."],
	["SINGLE RACE", "A FULL RACE WEEKEND: PRACTICE, QUALIFYING, CAUTIONS, PITS, STAGES."],
	["SEASON", "RUN A CHAMPIONSHIP. POINTS, WINS AND STANDINGS ARE SAVED."],
	["CAREER", "ROOKIE TO CHAMPION: PRIZE MONEY, SPONSORS AND R&D UPGRADES."],
	["LIGHTNING CHALLENGES", "RACE-DEFINING MOMENTS. BEAT FIVE TO UNLOCK A LEGEND."],
	["PAINT SHOP", "CREATE YOUR OWN CAR: NUMBER, DRIVER, SPONSOR AND COLORS."],
	["OPTIONS", "GRAPHICS AND RECORDS."],
]
var mode_idx := 0

# menus and race weekends
var menu: Control
var menu_kind := ""
var menu_return := ""
var sessions: Array = ["race"]
var session_idx := 0
var session := "race" # practice / qualify / race
var qual_grid: Array = [] # team indices, fastest first
var qual_rows: Array = [] # [team idx, time]
var _qual_base := {}
var replay_t := 0.0
var replay_rate := 1.0
var replay_focus := 0
var replay_cam := 0
var challenge := {}
var challenge_idx := -1
var challenge_result := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	env = Environment.new()
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
	sun.shadow_enabled = false
	add_child(sun)
	cam = Camera3D.new()
	cam.far = 3000.0
	cam.near = 0.3
	add_child(cam)
	cam.current = true
	synth = Synth.new()
	add_child(synth)

	hud = Hud.new()
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 1
	add_child(hud_layer)
	hud_layer.add_child(hud)
	hud.visible = false

	ui_layer = CanvasLayer.new()
	ui_layer.layer = 2
	add_child(ui_layer)

	pause_layer = CanvasLayer.new()
	pause_layer.layer = 5
	pause_layer.visible = false
	add_child(pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_layer.add_child(dim)
	var pl := Game.make_label("PAUSED", 56, Color(1, 0.9, 0.2), 8)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.size = Vector2(640, 60)
	pl.position = Vector2(0, 170)
	pause_layer.add_child(pl)
	var pl2 := Game.make_label("ESC  RESUME        Q  QUIT / END SESSION", 18, Color.WHITE, 5)
	pl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl2.size = Vector2(640, 30)
	pl2.position = Vector2(0, 250)
	pause_layer.add_child(pl2)

	var scan_layer := CanvasLayer.new()
	scan_layer.layer = 10
	add_child(scan_layer)
	scan_rect = ColorRect.new()
	scan_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	scan_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	float line = mod(floor(FRAGCOORD.y), 2.0);
	vec2 uv = SCREEN_UV - 0.5;
	float vig = smoothstep(0.35, 0.75, length(uv * vec2(1.0, 0.9)));
	COLOR = vec4(0.0, 0.0, 0.0, line * 0.13 + vig * 0.45);
}
"""
	var smat := ShaderMaterial.new()
	smat.shader = sh
	scan_rect.material = smat
	scan_layer.add_child(scan_rect)
	scan_rect.visible = Game.scanlines

	Game.graphics_changed.connect(func():
		_apply_graphics()
		_refresh_graphics_label())
	_enter_title()


func _refresh_graphics_label() -> void:
	if menu_labels.has("gfx"):
		menu_labels.gfx.text = _graphics_text()


func _graphics_text() -> String:
	if not Game.modern_supported:
		return "GRAPHICS: 1999"
	return "F3  GRAPHICS: %s" % ("MODERN" if Game.modern else "1999")


# --- world ---------------------------------------------------------------------

func _use_track(idx: int) -> void:
	Game.selected_track = idx
	if not tracks.has(idx):
		var t: Node3D = Track.new()
		t.name = "Track%d" % idx
		add_child(t)
		t.setup(Game.tracks[idx])
		tracks[idx] = t
	for k in tracks:
		tracks[k].visible = k == idx
	track = tracks[idx]
	_apply_graphics()


## Applies the 1999 or modern look to the renderer, environment and window.
func _apply_graphics() -> void:
	var modern := Game.modern
	var win := get_window()
	# 1999: render everything at 640x480 and upscale. Modern: native resolution 3D,
	# with the 640x480 UI scaled up smoothly.
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS if modern else Window.CONTENT_SCALE_MODE_VIEWPORT
	get_viewport().msaa_3d = Viewport.MSAA_4X if modern else Viewport.MSAA_DISABLED
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	scan_rect.visible = Game.scanlines and not modern
	if track == null:
		return
	var cfg: Dictionary = track.cfg
	var night: bool = cfg.get("night", false)
	sun.rotation = Vector3(-deg_to_rad(cfg.sun_elev), deg_to_rad(cfg.sun_az), 0)
	var sky := Sky.new()
	if modern and not night:
		var ps := PhysicalSkyMaterial.new()
		ps.rayleigh_coefficient = 2.2
		ps.mie_coefficient = 0.004
		ps.turbidity = 8.0
		ps.sun_disk_scale = 1.5
		ps.ground_color = (cfg.grass as Color).darkened(0.3)
		ps.energy_multiplier = 1.0
		sky.sky_material = ps
	else:
		var psm := ProceduralSkyMaterial.new()
		psm.sky_top_color = cfg.sky_top
		psm.sky_horizon_color = cfg.sky_horizon
		psm.ground_horizon_color = cfg.sky_horizon
		psm.ground_bottom_color = (cfg.grass as Color).darkened(0.5)
		psm.sun_angle_max = 20.0
		sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.fog_enabled = true
	env.fog_light_color = cfg.fog
	env.fog_sky_affect = 0.3
	if modern:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 1.0 if not night else 0.6
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.0 if not night else 1.3
		env.tonemap_white = 6.0
		env.ssao_enabled = true
		env.ssao_radius = 1.2
		env.ssao_intensity = 1.8
		env.ssr_enabled = true
		env.ssr_max_steps = 48
		env.ssr_fade_in = 0.2
		env.ssr_fade_out = 2.0
		env.glow_enabled = true
		env.glow_intensity = 0.6
		env.glow_bloom = 0.04
		env.glow_hdr_threshold = 1.1
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		env.fog_density = 0.00035 if not night else 0.0012
		env.fog_sun_scatter = 0.35
		env.fog_aerial_perspective = 0.6
		env.fog_sky_affect = 0.0 if not night else 0.3
		env.volumetric_fog_enabled = night
		env.volumetric_fog_density = 0.012
		env.volumetric_fog_albedo = Color(0.8, 0.8, 0.85)
		env.volumetric_fog_length = 220.0
		env.adjustment_enabled = true
		env.adjustment_saturation = 1.08
		env.adjustment_contrast = 1.04
		sun.light_energy = 0.15 if night else (1.4 if cfg.sun_elev > 20.0 else 1.1)
		sun.light_color = Color(0.7, 0.78, 1.0) if night else Color(1.0, 0.97, 0.92)
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 320.0
		sun.shadow_blur = 1.2
		sun.light_angular_distance = 0.6
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.55, 0.55, 0.7) if night else (cfg.sky_horizon as Color)
		env.ambient_light_energy = 0.9 if night else 0.55
		env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.tonemap_exposure = 1.0
		env.ssao_enabled = false
		env.ssr_enabled = false
		env.glow_enabled = false
		env.volumetric_fog_enabled = false
		env.adjustment_enabled = false
		env.fog_density = 0.0016 if night else 0.0009
		env.fog_sun_scatter = 0.0
		env.fog_aerial_perspective = 0.0
		sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
		sun.light_energy = 0.55 if night else 1.1
		sun.light_color = Color(0.8, 0.85, 1.0) if night else Color(1.0, 0.97, 0.9)
		sun.shadow_enabled = false


func _new_race(player_team: int) -> void:
	if race:
		race.queue_free()
		race = null
	race = Race.new()
	race.name = "Race"
	add_child(race)
	var sim := mode != "arcade" and player_team >= 0
	race.career = mode == "career" and not Game.career.is_empty()
	if mode == "challenge":
		var ch: Dictionary = challenge
		var size: int = ch.field
		var grid: Array = []
		if size > 1:
			var others: Array = range(Game.teams.size()).filter(func(i): return i != player_team and not Game.teams[i].get("legend", false))
			others.shuffle()
			for i in size:
				grid.append(player_team if i == int(ch.grid) - 1 else others.pop_back())
		race.setup(track, player_team, int(ch.laps), size, grid)
		if ch.get("wear", false) or ch.has("fuel"):
			race.enable_rules()
			race.control.cautions_enabled = false
			race.control.stage_ends.clear()
			for c in race.cars:
				c.burn_scale = 1.0 # real fuel mileage in challenges
			race.control.message.connect(_on_control_message)
			race.control.flag_changed.connect(_on_flag)
		var p: Node3D = race.player
		p.fuel = Car.FUEL_CAPACITY * float(ch.get("fuel", 1.0))
		p.tyre_wear = float(ch.get("tyres", 0.0))
		if ch.has("damage"):
			for k in p.damage:
				p.damage[k] = float(ch.damage)
			p._update_damage_visual()
	elif sim and session == "race":
		var size: int = Game.FIELDS[Game.settings.field]
		race.setup(track, player_team, Game.race_laps(Game.selected_track), size, _grid_for(size, player_team))
		race.enable_rules()
		race.control.message.connect(_on_control_message)
		race.control.flag_changed.connect(_on_flag)
	elif sim:
		# Practice / qualifying: the player alone on track.
		race.setup(track, player_team, 999 if session == "practice" else 1, 1)
	else:
		race.arcade_setup = true
		race.setup(track, player_team, int(track.cfg.laps), 16 if player_team >= 0 else 24)
		race.arcade = true
	race.lap_completed.connect(_on_lap)
	race.car_finished.connect(_on_finished)


func _clear_screen() -> void:
	if screen:
		screen.queue_free()
	screen = Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(screen)
	menu_labels.clear()


func _label(key: String, text: String, size: int, color: Color, pos: Vector2, align := HORIZONTAL_ALIGNMENT_CENTER, outline := 6) -> Label:
	var l := Game.make_label(text, size, color, outline)
	l.horizontal_alignment = align
	l.position = pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		l.size = Vector2(640, 0)
		l.position.x = 0
	screen.add_child(l)
	if key != "":
		menu_labels[key] = l
	return l


func _panel(rect: Rect2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = rect.position
	r.size = rect.size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(r)
	return r


# --- states ----------------------------------------------------------------------

func _set_state(s: State) -> void:
	state = s
	state_time = 0.0


func _start_attract() -> void:
	_new_race(-1)
	race.grid_up(-40.0, PACE_SPEED)
	race.go_green()
	# Let the field spread out a little so the demo looks like a race in progress.
	for i in 240:
		race.tick(1.0 / 30.0)
	tv_timer = 0.0
	tv_target = race.order[0]
	hud.visible = false
	hud.race = null


func _enter_title() -> void:
	_set_state(State.TITLE)
	get_tree().paused = false
	pause_layer.visible = false
	if preview_car:
		preview_car.queue_free()
		preview_car = null
	_use_track(Game.selected_track)
	_start_attract()
	_clear_screen()
	_panel(Rect2(0, 40, 640, 150), Color(0, 0, 0, 0.45))
	_label("logo1", "SPEEDWAY", 64, Color(0.95, 0.15, 0.1), Vector2(0, 44), HORIZONTAL_ALIGNMENT_CENTER, 10)
	_label("logo2", "THUNDER", 72, Color(1.0, 0.85, 0.1), Vector2(0, 100), HORIZONTAL_ALIGNMENT_CENTER, 12)
	_label("", Game.SUBTITLE, 18, Color(0.5, 0.9, 1.0), Vector2(0, 176), HORIZONTAL_ALIGNMENT_CENTER, 5)
	_label("start", "PRESS START", 30, Color.WHITE, Vector2(0, 300), HORIZONTAL_ALIGNMENT_CENTER, 7)
	_label("", "ARROWS / WASD  STEER + GAS + BRAKE     C  CAMERA     ESC  PAUSE", 11, Color(0.85, 0.85, 0.85), Vector2(0, 420), HORIZONTAL_ALIGNMENT_CENTER, 3)
	_label("", "FREE PLAY", 16, Color(0.3, 1.0, 0.4), Vector2(0, 446), HORIZONTAL_ALIGNMENT_CENTER, 4)
	_label("gfx", _graphics_text(), 12, Color(0.5, 0.9, 1.0), Vector2(0, 400), HORIZONTAL_ALIGNMENT_CENTER, 3)
	_label("", "(C)1999  THUNDER ARCADE WORKS", 11, Color(0.8, 0.8, 0.8), Vector2(0, 462), HORIZONTAL_ALIGNMENT_CENTER, 3)


func _enter_mode_select() -> void:
	_set_state(State.MODE_SELECT)
	synth.beep(1320.0, 0.08)
	_clear_screen()
	_label("", "SELECT MODE", 34, Color(1.0, 0.85, 0.1), Vector2(0, 30), HORIZONTAL_ALIGNMENT_CENTER, 8)
	var step: int = int(300.0 / MODES.size())
	_panel(Rect2(60, 96, 520, MODES.size() * step + 20), Color(0, 0, 0, 0.6))
	for i in MODES.size():
		_label("mode%d" % i, MODES[i][0], 26, Color.WHITE, Vector2(0, 104 + i * step), HORIZONTAL_ALIGNMENT_CENTER, 7)
		_label("mdesc%d" % i, MODES[i][1], 11, Color(0.7, 0.8, 0.9), Vector2(0, 136 + i * step), HORIZONTAL_ALIGNMENT_CENTER, 3)
	_label("", "UP / DOWN   CHOOSE        START  SELECT", 14, Color(0.85, 0.85, 0.85), Vector2(0, 420))
	_refresh_mode_select()


func _refresh_mode_select() -> void:
	for i in MODES.size():
		var l: Label = menu_labels["mode%d" % i]
		l.label_settings.font_color = Color(1.0, 0.85, 0.1) if i == mode_idx else Color(0.6, 0.6, 0.65)
		l.text = ("> %s <" % MODES[i][0]) if i == mode_idx else MODES[i][0]


func _enter_track_select() -> void:
	_set_state(State.TRACK_SELECT)
	sel_timer = SELECT_TIME
	synth.beep(1320.0, 0.08)
	_clear_screen()
	_label("", "SELECT COURSE", 34, Color(1.0, 0.85, 0.1), Vector2(0, 14), HORIZONTAL_ALIGNMENT_CENTER, 8)
	_label("timer", "20", 30, Color(1, 0.3, 0.2), Vector2(560, 14), HORIZONTAL_ALIGNMENT_LEFT, 7)
	_panel(Rect2(40, 250, 560, 190), Color(0, 0, 0, 0.6))
	_label("level", "", 26, Color(0.3, 1.0, 0.4), Vector2(0, 258))
	_label("name", "", 22, Color.WHITE, Vector2(0, 292))
	_label("kind", "", 16, Color(0.5, 0.9, 1.0), Vector2(0, 322))
	_label("info", "", 16, Color.WHITE, Vector2(0, 350))
	_label("rec", "", 14, Color(1, 0.85, 0.3), Vector2(0, 380))
	_label("", "<   LEFT / RIGHT   >        START  SELECT", 14, Color(0.85, 0.85, 0.85), Vector2(0, 414))
	_refresh_track_select()


func _refresh_track_select() -> void:
	var cfg: Dictionary = Game.track()
	menu_labels.level.text = "<  %s  >" % cfg.level
	menu_labels.name.text = cfg.name
	menu_labels.kind.text = cfg.kind
	var miles: float = track.length / 1609.34
	var lap_count: int = cfg.race_laps if mode == "race" else cfg.laps
	menu_labels.info.text = "%.2f MILES     %d LAPS     BANKING %d DEG" % [miles, lap_count, cfg.bank_turn]
	menu_labels.rec.text = "BEST LAP %s      BEST RACE %s" % [Game.format_time(Game.get_record(Game.selected_track, "lap")), Game.format_time(Game.get_record(Game.selected_track, "race"))]


func _enter_car_select() -> void:
	_set_state(State.CAR_SELECT)
	sel_timer = SELECT_TIME
	synth.beep(1320.0, 0.08)
	_clear_screen()
	_label("", "SELECT CAR", 34, Color(1.0, 0.85, 0.1), Vector2(0, 14), HORIZONTAL_ALIGNMENT_CENTER, 8)
	_label("timer", "20", 30, Color(1, 0.3, 0.2), Vector2(560, 14), HORIZONTAL_ALIGNMENT_LEFT, 7)
	_panel(Rect2(40, 300, 560, 150), Color(0, 0, 0, 0.6))
	_label("num", "", 40, Color.WHITE, Vector2(60, 306), HORIZONTAL_ALIGNMENT_LEFT, 8)
	_label("driver", "", 22, Color.WHITE, Vector2(150, 308), HORIZONTAL_ALIGNMENT_LEFT, 6)
	_label("sponsor", "", 16, Color(1, 0.85, 0.3), Vector2(150, 336), HORIZONTAL_ALIGNMENT_LEFT, 5)
	_label("stats", "", 14, Color(0.5, 0.9, 1.0), Vector2(60, 364), HORIZONTAL_ALIGNMENT_LEFT, 4)
	_label("", "<   LEFT / RIGHT   >        START  RACE!", 14, Color(0.85, 0.85, 0.85), Vector2(0, 430))
	_refresh_car_select()


func _refresh_car_select() -> void:
	var t: Dictionary = Game.teams[Game.selected_team]
	menu_labels.num.text = "#" + t.num
	menu_labels.num.label_settings.font_color = t.c1.lightened(0.2)
	menu_labels.driver.text = t.driver
	menu_labels.sponsor.text = t.sponsor
	var bar := func(v: float) -> String:
		var n := int(round(clamp((v - 0.94) / 0.12, 0.0, 1.0) * 10.0))
		return "|".repeat(n + 4) + ".".repeat(10 - n)
	menu_labels.stats.text = "TOP SPEED  %s\nACCEL      %s\nHANDLING   %s" % [bar.call(t.speed), bar.call(t.accel), bar.call(t.handling)]
	if preview_car:
		preview_car.queue_free()
	preview_car = Car.new()
	add_child(preview_car)
	preview_car.setup(t, null)
	var base: Vector3 = track.pos[0] + track.right[0] * (track.inner_wall() - 14.0)
	preview_car.position = base + Vector3.UP * 0.02


func _enter_countdown() -> void:
	_set_state(State.COUNTDOWN)
	synth.beep(1760.0, 0.12)
	if preview_car:
		preview_car.queue_free()
		preview_car = null
	_clear_screen()
	_new_race(Game.selected_team)
	var lead := -(PACE_SPEED * 5.2 + 15.0)
	if mode == "challenge" and challenge.has("start"):
		lead = float(challenge.start)
	elif mode == "challenge" and int(challenge.laps) <= 3:
		lead = -120.0
	if session == "qualify":
		lead = -track.length * 0.7 # a warm-up lap, then the timed lap
	elif session == "practice":
		lead = -60.0
	race.grid_up(lead, PACE_SPEED)
	# Arcade clock: generous first lap, then an extension each lap.
	var ref := 0.0
	var seg: float = track.length / track.n
	for i in track.n:
		ref += seg / min(track.speed_profile[i], 80.0)
	time_left = round(ref * 1.6 + 12.0)
	lap_bonus = round(ref * 1.2)
	hud.race = race
	hud.track = track
	hud.time_left = time_left
	hud.show_timer = mode == "arcade"
	hud.control = race.control
	hud.visible = true
	hud.clear_messages()
	var intro: String = {"practice": "PRACTICE", "qualify": "QUALIFYING"}.get(session, "GET READY!") if mode != "arcade" else "GET READY!"
	if mode == "challenge":
		intro = challenge.name
		hud.show_timer = false
	hud.message(intro, 2.0, Color(1, 0.9, 0.2))
	hud.sub_message((track.cfg.name if session != "practice" else "ESC THEN Q TO END PRACTICE") if mode != "challenge" else challenge.desc, 3.0)
	countdown_step = 0
	new_records.clear()
	game_over_reason = ""
	cam_pos = race.player.global_position + Vector3(0, 30, 0)


func _enter_results() -> void:
	_set_state(State.RESULTS)
	hud.visible = false
	_clear_screen()
	_panel(Rect2(30, 10, 580, 460), Color(0, 0, 0, 0.7))
	var head := "GAME OVER" if game_over_reason != "" else "RACE RESULTS"
	_label("", head, 34, Color(1.0, 0.85, 0.1) if game_over_reason == "" else Color(1, 0.3, 0.2), Vector2(0, 16), HORIZONTAL_ALIGNMENT_CENTER, 8)
	_label("", track.cfg.name, 14, Color(0.5, 0.9, 1.0), Vector2(0, 58), HORIZONTAL_ALIGNMENT_CENTER, 4)
	var y := 84
	var leader_time := 0.0
	var sim := race.control != null
	var rows: Array[int] = []
	for i in race.order.size():
		if rows.size() < 13 or race.order[i].is_player:
			rows.append(i)
	rows = rows.slice(0, 14)
	var row_h := 24
	if sim:
		for h in [["POS", 60], ["CAR", 100], ["DRIVER", 160], ["LED", 376], ["STG", 416], ["PTS", 460]]:
			_label("", h[0], 11, Color(0.6, 0.7, 0.8), Vector2(h[1], 72), HORIZONTAL_ALIGNMENT_LEFT, 3)
		y = 86
	for i in race.order.size():
		if i not in rows:
			continue
		var c: Node3D = race.order[i]
		var col := Color(1, 0.9, 0.2) if c.is_player else Color.WHITE
		var gap := ""
		if c.finished:
			if i == 0:
				leader_time = c.finish_time
				gap = Game.format_time(c.finish_time)
			else:
				gap = "+%.2f" % (c.finish_time - leader_time)
		else:
			gap = "RUNNING"
		_label("", "%2d" % (i + 1), 16, col, Vector2(60, y), HORIZONTAL_ALIGNMENT_LEFT, 4)
		_label("", "#" + c.team.num, 16, c.team.c1.lightened(0.3), Vector2(100, y), HORIZONTAL_ALIGNMENT_LEFT, 4)
		_label("", ("%s  (YOU)" % c.team.driver) if c.is_player else c.team.driver, 16, col, Vector2(160, y), HORIZONTAL_ALIGNMENT_LEFT, 4)
		if sim:
			if c.out:
				gap = "OUT"
			elif c.finished and i > 0 and c.lap() < race.order[0].lap():
				gap = "-%d LAP" % (race.order[0].lap() - c.lap())
			_label("", "%d" % c.laps_led, 14, col, Vector2(380, y + 2), HORIZONTAL_ALIGNMENT_LEFT, 3)
			_label("", "%d" % c.stage_points, 14, col, Vector2(420, y + 2), HORIZONTAL_ALIGNMENT_LEFT, 3)
			_label("", "%d" % race.control.finishing_points(i + 1, c), 16, Color(1, 0.85, 0.3), Vector2(460, y), HORIZONTAL_ALIGNMENT_LEFT, 4)
			_label("", gap if gap == "OUT" or gap.ends_with("LAP") else "", 12, col, Vector2(510, y + 3), HORIZONTAL_ALIGNMENT_LEFT, 3)
		else:
			_label("", gap, 16, col, Vector2(430, y), HORIZONTAL_ALIGNMENT_LEFT, 4)
		y += row_h
	var y2 := y + 4
	if game_over_reason != "":
		_label("", game_over_reason, 18, Color(1, 0.3, 0.2), Vector2(0, y2), HORIZONTAL_ALIGNMENT_CENTER, 5)
		y2 += 24
	if mode == "challenge" and challenge_result != "":
		_label("", challenge_result, 18, Color(0.3, 1.0, 0.4) if challenge_result.begins_with("CHALLENGE COMPLETE") else Color(1, 0.3, 0.2), Vector2(0, min(y2, 410)), HORIZONTAL_ALIGNMENT_CENTER, 5)
	for r in new_records:
		_label("", r, 18, Color(0.3, 1.0, 0.4), Vector2(0, y2), HORIZONTAL_ALIGNMENT_CENTER, 5)
		y2 += 22
	_label("start", "PRESS START", 20, Color.WHITE, Vector2(0, 440), HORIZONTAL_ALIGNMENT_CENTER, 5)
	if race.rec_times.size() > 20:
		_label("", "R  WATCH REPLAY", 12, Color(0.6, 0.9, 1.0), Vector2(470, 446), HORIZONTAL_ALIGNMENT_LEFT, 3)


# --- race events --------------------------------------------------------------

func _on_lap(car: Node3D, laps_done: int, lap_time: float) -> void:
	if car != race.player or state != State.RACE:
		return
	if Game.submit_record(Game.selected_track, "lap", lap_time):
		if not new_records.has("NEW LAP RECORD!"):
			new_records.append("NEW LAP RECORD!")
	if mode != "arcade":
		if session == "practice":
			hud.message(Game.format_time(lap_time), 2.0, Color.WHITE)
			hud.sub_message("BEST " + Game.format_time(car.best_lap), 2.0)
		elif session == "qualify" and laps_done == 0:
			hud.message("TIMED LAP", 1.5, Color(0.3, 1.0, 0.4))
		return
	if laps_done < race.laps:
		time_left += lap_bonus
		synth.beep(1568.0, 0.1)
		synth.beep(2093.0, 0.2)
		if laps_done == race.laps - 1:
			hud.message("FINAL LAP!", 2.0, Color(1, 1, 1))
		else:
			hud.message("EXTENDED TIME!", 2.0, Color(0.3, 1.0, 0.4))
		hud.sub_message("LAP %s    +%d SEC" % [Game.format_time(lap_time), int(lap_bonus)], 2.5)


func _on_finished(car: Node3D, place: int) -> void:
	if car != race.player or state != State.RACE:
		return
	if session == "qualify":
		_finish_qualifying(car.best_lap)
		return
	if mode == "challenge":
		var ok := false
		match String(challenge.goal):
			"win": ok = place == 1
			"top3": ok = place <= 3
			"top5": ok = place <= 5
			"top10": ok = place <= 10
			"time": ok = car.best_lap > 0.0 and car.best_lap <= float(challenge.time)
		if ok:
			var first := Game.complete_challenge(challenge_idx)
			challenge_result = "CHALLENGE COMPLETE!" + ("   LEGEND UNLOCKED: #00 THUNDERBOLT" if first and Game.challenges_done.size() == 5 else "")
		else:
			challenge_result = "CHALLENGE FAILED"
		if challenge.goal == "time":
			challenge_result += "   LAP %s" % Game.format_time(car.best_lap)
	_set_state(State.FINISHED)
	hud.show_timer = false
	var col := Color(1, 0.9, 0.2) if place == 1 else Color.WHITE
	hud.message("WINNER!" if place == 1 else "FINISH!", 4.0, col)
	hud.sub_message("YOU FINISHED %s" % Game.ordinal(place), 5.0)
	for i in 3:
		synth.beep(1046.0 + i * 262.0, 0.12)
	if Game.submit_record(Game.selected_track, "race", car.finish_time):
		new_records.append("NEW RACE RECORD!  %s" % Game.format_time(car.finish_time))


# --- main loop ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_scanlines"):
		Game.scanlines = not Game.scanlines
		scan_rect.visible = Game.scanlines and not Game.modern
	if state in [State.COUNTDOWN, State.RACE, State.FINISHED]:
		if event.is_action_pressed("pause"):
			paused = not paused
			pause_layer.visible = paused
		elif paused and event.is_action_pressed("quit_race"):
			paused = false
			pause_layer.visible = false
			if session == "practice":
				session_idx += 1
				_start_session()
			elif (mode == "season" or mode == "career") and not Game.season.is_empty():
				_return_hub()
			else:
				_enter_title()
			return
		elif event.is_action_pressed("camera"):
			cam_mode = (cam_mode + 1) % 3
	if paused:
		return
	match state:
		State.TITLE:
			if event.is_action_pressed("start"):
				_enter_mode_select()
		State.MODE_SELECT:
			if event.is_action_pressed("menu_up") or event.is_action_pressed("menu_down"):
				mode_idx = posmod(mode_idx + (1 if event.is_action_pressed("menu_down") else -1), MODES.size())
				synth.beep(880.0, 0.05)
				_refresh_mode_select()
			elif event.is_action_pressed("start"):
				match mode_idx:
					0, 1:
						mode = ["arcade", "race"][mode_idx]
						_enter_track_select()
					2:
						mode = "season"
						if Game.season.is_empty():
							_enter_car_select()
						else:
							_enter_season_hub()
					3:
						mode = "career"
						if Game.career.is_empty():
							_enter_car_select()
						else:
							_enter_career_hub()
					4:
						_enter_challenges()
					5:
						_enter_paint_shop()
					6:
						_enter_options()
			elif event.is_action_pressed("back"):
				_enter_title()
		State.TRACK_SELECT:
			if event.is_action_pressed("steer_left") or event.is_action_pressed("steer_right"):
				var dir := -1 if event.is_action_pressed("steer_left") else 1
				var idx := posmod(Game.selected_track + dir, Game.tracks.size())
				synth.beep(880.0, 0.05)
				_use_track(idx)
				_start_attract()
				_refresh_track_select()
			elif event.is_action_pressed("start"):
				_enter_car_select()
			elif event.is_action_pressed("back"):
				_enter_title()
		State.CAR_SELECT:
			if event.is_action_pressed("steer_left") or event.is_action_pressed("steer_right"):
				var dir := -1 if event.is_action_pressed("steer_left") else 1
				var pick: Array = Game.selectable_teams()
				var cur: int = max(pick.find(Game.selected_team), 0)
				Game.selected_team = pick[posmod(cur + dir, pick.size())]
				synth.beep(880.0, 0.05)
				_refresh_car_select()
			elif event.is_action_pressed("start"):
				match mode:
					"arcade":
						_enter_countdown()
					"race":
						_enter_race_setup()
					"season":
						_enter_season_setup()
					"career":
						Game.new_career(Game.selected_team)
						_enter_career_hub()
			elif event.is_action_pressed("back"):
				if mode == "season" or mode == "career":
					_enter_mode_select()
				else:
					_enter_track_select()
		State.MENU:
			if menu:
				menu.handle(event)
		State.SESSION_RESULTS:
			if event.is_action_pressed("start") and state_time > 0.8:
				session_idx += 1
				_start_session()
		State.STANDINGS:
			if (event.is_action_pressed("start") or event.is_action_pressed("back")) and state_time > 0.5:
				if Game.season.is_empty():
					_enter_title()
				else:
					_return_hub()
		State.REPLAY:
			if event.is_action_pressed("start") or event.is_action_pressed("back") or event.is_action_pressed("replay"):
				screen.visible = true
				_set_state(State.RESULTS)
				hud.visible = false
			elif event.is_action_pressed("steer_left") or event.is_action_pressed("steer_right"):
				var dir := -1 if event.is_action_pressed("steer_left") else 1
				replay_focus = posmod(replay_focus + dir, race.cars.size())
			elif event.is_action_pressed("menu_up") or event.is_action_pressed("menu_down"):
				var rates := [-4.0, -1.0, 0.0, 0.5, 1.0, 2.0, 4.0]
				var i := rates.find(replay_rate)
				i = clamp(i + (1 if event.is_action_pressed("menu_up") else -1), 0, rates.size() - 1)
				replay_rate = rates[i]
			elif event.is_action_pressed("camera"):
				replay_cam = (replay_cam + 1) % 4
		State.RESULTS:
			if event.is_action_pressed("replay") and race.rec_times.size() > 20:
				_enter_replay()
			elif event.is_action_pressed("start") and state_time > 1.0:
				if (mode == "season" or mode == "career") and not Game.season.is_empty():
					_after_season_race()
				elif mode == "challenge":
					_enter_challenges()
				else:
					_enter_title()


func _physics_process(delta: float) -> void:
	if paused:
		synth.engine_on = false
		synth.squeal = 0.0
		synth.pass_volume = 0.0
		return
	state_time += delta
	match state:
		State.TITLE, State.MODE_SELECT, State.TRACK_SELECT, State.CAR_SELECT, State.MENU, State.SESSION_RESULTS, State.STANDINGS:
			_loop_attract()
			race.tick(delta)
		State.COUNTDOWN:
			race.tick(delta)
			_countdown_logic()
		State.RACE:
			_player_input()
			race.tick(delta)
			if mode != "arcade":
				_check_player_out(delta)
				return
			time_left -= delta
			hud.time_left = time_left
			if time_left <= 0.0:
				time_left = 0.0
				game_over_reason = "TIME UP"
				hud.message("TIME UP", 4.0, Color(1, 0.25, 0.2))
				hud.sub_message("GAME OVER", 4.0)
				synth.beep(220.0, 0.6, 0.4)
				race.player.ai = false
				_set_state(State.FINISHED)
		State.FINISHED:
			if game_over_reason != "":
				race.player.throttle = 0.0
				race.player.brake = 0.3
				race.player.steer_in = 0.0
			race.tick(delta)
			if state_time > 5.0:
				_enter_results()
		State.RESULTS:
			race.tick(delta)
		State.REPLAY:
			replay_t = clamp(replay_t + delta * replay_rate, race.rec_times[0], race.rec_times[race.rec_times.size() - 1])
			race.replay_apply(replay_t)
			_replay_overlay()


var _out_timer := 0.0


## Wrecked out or stopped with an empty tank: the player's race is over.
func _check_player_out(delta: float) -> void:
	var p: Node3D = race.player
	var dry: bool = p.fuel <= 0.0 and p.speed() < 1.0 and p.pit_state == 0
	if p.out or dry:
		_out_timer += delta
		if _out_timer > 3.0:
			_out_timer = 0.0
			p.out = true
			game_over_reason = "OUT OF FUEL" if dry else "WRECKED  -  OUT OF THE RACE"
			if mode == "challenge":
				challenge_result = "CHALLENGE FAILED"
			hud.message("OUT OF FUEL" if dry else "OUT OF THE RACE", 3.0, Color(1, 0.3, 0.2))
			_set_state(State.FINISHED)
	else:
		_out_timer = 0.0


func _loop_attract() -> void:
	# Keep the attract race looping forever.
	if race.finish_count > 0 and state_time > 1.0:
		var leader: Node3D = race.order[0]
		if leader.finished and race.time - leader.finish_time > 20.0:
			_start_attract()


func _countdown_logic() -> void:
	var t := state_time
	var steps := [2.0, 3.0, 4.0, 5.0]
	if countdown_step < steps.size() and t >= steps[countdown_step]:
		countdown_step += 1
		match countdown_step:
			1:
				hud.message("3", 1.0, Color(1, 0.3, 0.2))
				synth.beep(660.0, 0.25)
			2:
				hud.message("2", 1.0, Color(1, 0.8, 0.2))
				synth.beep(660.0, 0.25)
			3:
				hud.message("1", 1.0, Color(1, 1, 0.3))
				synth.beep(660.0, 0.25)
			4:
				hud.message("GREEN FLAG!", 1.6, Color(0.3, 1.0, 0.3))
				hud.sub_message("GO! GO! GO!", 1.6)
				synth.beep(1320.0, 0.6)
				race.go_green()
				_set_state(State.RACE)


func _player_input() -> void:
	var p: Node3D = race.player
	if autopilot:
		p.ai = true
		p.autopilot_forced = true
		return
	var ctl: Node = race.control
	if ctl:
		if Input.is_action_just_pressed("pit"):
			p.want_pit = not p.want_pit
			hud.sub_message("PIT THIS LAP: %s" % _plan_name(p.pit_plan) if p.want_pit else "PIT CANCELLED", 2.0)
		if Input.is_action_just_pressed("pit_option"):
			p.pit_plan = {"4": "2", "2": "F", "F": "4"}[p.pit_plan]
			hud.sub_message("PIT PLAN: %s" % _plan_name(p.pit_plan), 2.0)
		if ctl.choosing and Input.is_action_just_pressed("steer_left"):
			ctl.player_lane_choice = 0
			hud.sub_message("RESTART: INSIDE LANE", 2.0)
		elif ctl.choosing and Input.is_action_just_pressed("steer_right"):
			ctl.player_lane_choice = 1
			hud.sub_message("RESTART: OUTSIDE LANE", 2.0)
		# The car drives itself under caution and on pit road (auto pit / auto caution).
		var auto: bool = ctl.flag == ctl.Flag.YELLOW or p.pit_state != 0 or (p.want_pit and _near_pit_entry(p))
		p.ai = auto
		if auto:
			return
	p.throttle = Input.get_action_strength("accelerate")
	p.brake = Input.get_action_strength("brake")
	p.steer_in = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	if Input.is_action_just_pressed("shift_up"):
		p.shift_request = 1
	elif Input.is_action_just_pressed("shift_down"):
		p.shift_request = -1


func _plan_name(plan: String) -> String:
	return {"4": "4 TIRES + FUEL", "2": "2 TIRES + FUEL", "F": "FUEL ONLY"}[plan]


func _near_pit_entry(p: Node3D) -> bool:
	var to_entry: float = fposmod(track.pit_in_s() - p.s(), track.length)
	return to_entry < 500.0


func _on_control_message(text: String, kind: String) -> void:
	match kind:
		"flag":
			hud.message(text, 2.5, Color(1, 0.9, 0.2) if text.begins_with("CAUTION") or text == "ONE TO GO" else (Color(0.3, 1.0, 0.3) if text.begins_with("GREEN") else Color.WHITE))
			if text == "ONE TO GO":
				hud.sub_message("CHOOSE YOUR LANE:  LEFT = INSIDE   RIGHT = OUTSIDE", 6.0)
		"stage":
			hud.message(text, 3.0, Color(0.4, 0.9, 1.0))
		"pit":
			hud.sub_message(text, 3.0)
		"spotter":
			hud.spotter(text)
		_:
			hud.sub_message(text, 3.0)


func _on_flag(flag: String) -> void:
	match flag:
		"YELLOW":
			synth.beep(440.0, 0.4)
		"GREEN":
			synth.beep(1320.0, 0.5)
		"WHITE":
			synth.beep(990.0, 0.3)


func _process(delta: float) -> void:
	if race == null:
		return
	_update_camera(delta)
	_update_audio()
	if screen:
		var blink := int(state_time * 3.0) % 2 == 0
		match state:
			State.TITLE:
				menu_labels.start.visible = blink
				var sc := 1.0 + sin(state_time * 3.0) * 0.03
				menu_labels.logo2.pivot_offset = Vector2(320, 36)
				menu_labels.logo2.scale = Vector2(sc, sc)
			State.TRACK_SELECT, State.CAR_SELECT:
				if mode != "arcade":
					menu_labels.timer.text = ""
					return
				if not paused:
					sel_timer -= delta
				menu_labels.timer.text = "%d" % max(ceil(sel_timer), 0)
				if sel_timer <= 0.0:
					if state == State.TRACK_SELECT:
						_enter_car_select()
					else:
						_enter_countdown()
			State.RESULTS:
				menu_labels.start.visible = blink and state_time > 1.0


func _update_audio() -> void:
	var focus: Node3D = null
	if state in [State.COUNTDOWN, State.RACE, State.FINISHED] and race.player:
		focus = race.player
		synth.master = 0.8
	else:
		focus = tv_target
		synth.master = 0.35
	if focus == null or not is_instance_valid(focus):
		synth.engine_on = false
		return
	synth.engine_on = true
	synth.engine_rpm = focus.rpm()
	synth.engine_load = focus.throttle
	synth.squeal = clamp(focus.scrub * 1.5, 0.0, 1.0)
	if focus.wall_hit > 2.0:
		synth.crash(focus.wall_hit / 25.0)
		if focus == race.player:
			shake = max(shake, clamp(focus.wall_hit / 20.0, 0.2, 1.0))
	if focus.bump > 3.0:
		synth.crash(focus.bump / 40.0)
		if focus == race.player:
			shake = max(shake, clamp(focus.bump / 30.0, 0.1, 0.6))
	# Nearest other car for the pass-by whoosh.
	var best := 1e9
	var best_car: Node3D = null
	for c in race.cars:
		if c == focus:
			continue
		var dist: float = c.global_position.distance_to(cam.global_position)
		if dist < best:
			best = dist
			best_car = c
	if best_car:
		synth.pass_volume = clamp(1.0 - best / 45.0, 0.0, 1.0) * 0.8
		var to_cam: Vector3 = (cam.global_position - best_car.global_position).normalized()
		var vel: Vector3 = -best_car.global_transform.basis.z * best_car.v
		var cam_vel: Vector3 = -focus.global_transform.basis.z * focus.v
		var closing := (vel - cam_vel).dot(to_cam)
		synth.pass_pitch = clamp((0.6 + best_car.v / 90.0) * (1.0 + closing / 120.0), 0.3, 2.5)


func _update_camera(delta: float) -> void:
	shake = max(shake - delta * 2.5, 0.0)
	var sh := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), 0) * shake * 0.25
	match state:
		State.COUNTDOWN, State.RACE, State.FINISHED:
			_chase_camera(race.player, delta, cam_mode)
		State.REPLAY:
			var focus: Node3D = race.cars[replay_focus]
			match replay_cam:
				0:
					tv_target = focus
					_tv_camera(delta, true)
				1:
					_chase_camera(focus, delta, 0)
				2:
					_chase_camera(focus, delta, 2)
				3:
					tv_target = focus
					tv_mode = 3
					_tv_camera(delta, true)
		State.CAR_SELECT, State.MENU:
			if preview_car and (state == State.CAR_SELECT or menu_kind == "paint"):
				orbit += delta * 0.5
				preview_car.rotation.y = orbit
				var p := preview_car.global_position
				cam.fov = 45.0
				var eye := p + Vector3(sin(0.6) * 9.0, 2.3, cos(0.6) * 9.0)
				cam.global_position = eye
				var side := (p - eye).cross(Vector3.UP).normalized()
				# In the paint shop, frame the car on the right, clear of the menu.
				var shift := -side * 1.9 if state == State.MENU else Vector3.ZERO
				cam.look_at(p + Vector3(0, -0.9, 0) + shift, Vector3.UP)
			else:
				_tv_camera(delta)
		_:
			_tv_camera(delta)
	cam.global_position += cam.global_transform.basis * sh


func _chase_camera(car: Node3D, delta: float, mode: int) -> void:
	var tr: Transform3D = car.global_transform
	var back := tr.basis.z
	var up := tr.basis.y
	var spd: float = clamp(abs(car.v) / 85.0, 0.0, 1.2)
	if mode == 2:
		cam.global_transform = tr * Transform3D(Basis(), Vector3(0, 1.05, -2.3))
		cam.fov = 70.0 + spd * 10.0
		cam_pos = cam.global_position
		return
	var dist := 7.0 if mode == 0 else 4.8
	var height := 2.5 if mode == 0 else 1.8
	# Only the heading is smoothed so the car stays put on screen at any speed.
	if car != cam_car or cam_back.dot(back) < 0.3:
		cam_back = back
		cam_car = car
	cam_back = cam_back.lerp(back, 1.0 - exp(-7.0 * delta)).normalized()
	cam_pos = tr.origin + cam_back * dist + up * height
	cam.global_position = cam_pos
	var look := tr.origin + up * 1.0 - cam_back * 8.0
	cam.look_at(look, up.lerp(Vector3.UP, 0.4).normalized())
	cam.fov = 64.0 + spd * 14.0


func _tv_camera(delta: float, fixed := false) -> void:
	tv_timer -= delta
	if tv_target == null or not is_instance_valid(tv_target) or tv_timer <= 0.0:
		tv_timer = rng.randf_range(5.0, 8.0)
		if not fixed:
			var pick: int = rng.randi() % min(6, race.order.size())
			tv_target = race.order[pick]
		if not (fixed and replay_cam == 3):
			tv_mode = [0, 2, 2, 3][rng.randi() % 4] if fixed else rng.randi() % 4
		tv_anchor = Vector3.ZERO
		cam_pos = tv_target.global_position + Vector3(0, 40, 0)
	var t := tv_target
	match tv_mode:
		0, 1:
			_chase_camera(t, delta, 0)
		2:
			# Trackside camera on the outside wall, leapfrogging ahead of the car.
			var ahead: float = fposmod(tv_anchor.x - t.s() + track.length * 0.5, track.length) - track.length * 0.5
			if tv_anchor == Vector3.ZERO or ahead < -60.0 or ahead > 260.0:
				tv_anchor.x = t.s() + 180.0
			cam.global_position = track.surface_point(tv_anchor.x, track.outer_edge()) + Vector3.UP * 7.0
			cam.look_at(t.global_position + Vector3.UP, Vector3.UP)
			cam.fov = 55.0
		3:
			# Helicopter shot.
			var tr: Transform3D = t.global_transform
			var target := tr.origin + tr.basis.z * 45.0 + Vector3.UP * 30.0 + tr.basis.x * 20.0
			cam_pos = cam_pos.lerp(target, 1.0 - exp(-3.0 * delta))
			cam.global_position = cam_pos
			cam.look_at(tr.origin - tr.basis.z * 10.0, Vector3.UP)
			cam.fov = 60.0


# --- menus: race setup, garage, season, options -----------------------------------

func _open_menu(kind: String, title: String, rows: Array, cursor := 0) -> void:
	_set_state(State.MENU)
	_clear_screen()
	menu_kind = kind
	menu = Menu.new()
	screen.add_child(menu)
	menu.build(title, rows, cursor)
	menu.activated.connect(_on_menu_activated)
	menu.changed.connect(_on_menu_changed)
	menu.cancelled.connect(_on_menu_cancelled)


func _enter_race_setup(return_to := "") -> void:
	if return_to != "":
		menu_return = return_to
	elif mode != "season" and mode != "career":
		menu_return = "car"
	var lengths: Array = []
	for i in Game.LENGTHS.size():
		var full: int = Game.tracks[Game.selected_track].get("full_laps", 200)
		lengths.append("%s  %d LAPS" % [Game.LENGTHS[i][0], max(5, int(round(full * float(Game.LENGTHS[i][1]))))])
	var diffs: Array = Game.DIFFICULTIES.map(func(d): return d[0])
	var rows := [
		{"id": "length", "label": "RACE LENGTH", "values": lengths, "index": Game.settings.length, "hint": "PERCENT OF A REAL CUP RACE DISTANCE"},
		{"id": "difficulty", "label": "DIFFICULTY", "values": diffs, "index": Game.settings.difficulty, "hint": "HOW FAST AND SHARP THE OTHER DRIVERS ARE"},
		{"id": "field", "label": "FIELD SIZE", "values": Game.FIELDS.map(func(f): return "%d CARS" % f), "index": Game.settings.field},
		{"id": "weekend", "label": "WEEKEND", "values": Game.WEEKENDS, "index": Game.settings.weekend, "hint": "QUALIFY TO SET YOUR STARTING SPOT"},
		{"id": "cautions", "label": "CAUTIONS", "values": ["OFF", "ON"], "index": Game.settings.cautions},
		{"id": "damage", "label": "DAMAGE", "values": ["OFF", "ON"], "index": Game.settings.damage, "hint": "DAMAGE HURTS SPEED, HANDLING AND CAN END YOUR RACE"},
		{"id": "wear", "label": "FUEL + TIRE WEAR", "values": ["OFF", "ON"], "index": Game.settings.wear, "hint": "SCALED TO RACE LENGTH SO PIT STRATEGY MATTERS"},
		{"id": "assists", "label": "DRIVING ASSISTS", "values": ["OFF", "ON"], "index": Game.settings.assists, "hint": "STEERING, TRACTION AND STABILITY HELP"},
		{"id": "manual", "label": "TRANSMISSION", "values": ["AUTOMATIC", "MANUAL"], "index": Game.settings.manual, "hint": "MANUAL: E = UP, Q = DOWN (RB / LB)"},
		{"id": "garage", "label": "GARAGE SETUP", "hint": "BALANCE, TIRE PRESSURE AND GEARING"},
	]
	if mode == "season" or mode == "career":
		rows.append({"id": "back", "label": "DONE"})
	else:
		rows.append({"id": "go", "label": "START RACE WEEKEND"})
	_open_menu("race_setup", "RACE SETTINGS", rows, rows.size() - 1)


func _enter_garage(return_to: String) -> void:
	menu_return = return_to
	var bal := ["TIGHT 3", "TIGHT 2", "TIGHT 1", "NEUTRAL", "LOOSE 1", "LOOSE 2", "LOOSE 3"]
	var rows := [
		{"id": "balance", "label": "HANDLING BALANCE", "values": bal, "index": int(Game.setup.balance) + 3, "hint": "WEDGE / TRACK BAR: TIGHT PUSHES UP THE TRACK, LOOSE TURNS BUT CAN SPIN"},
		{"id": "pressure", "label": "TIRE PRESSURE", "values": ["LOW", "STANDARD", "HIGH"], "index": Game.setup.pressure, "hint": "LOW: MORE GRIP, FASTER WEAR.  HIGH: LESS GRIP, LASTS LONGER"},
		{"id": "gearing", "label": "GEARING", "values": ["SHORT", "STANDARD", "LONG"], "index": Game.setup.gearing, "hint": "SHORT: QUICKER OFF THE CORNERS.  LONG: MORE TOP SPEED"},
		{"id": "back", "label": "DONE"},
	]
	_open_menu("garage", "GARAGE", rows, 3)


func _enter_season_setup() -> void:
	var rows := [
		{"id": "slen", "label": "SEASON LENGTH", "values": Game.SEASON_LENGTHS.map(func(x): return "%s  %d RACES" % [x[0], x[1]]), "index": 0},
		{"id": "start_season", "label": "START SEASON"},
	]
	_open_menu("season_setup", "NEW SEASON", rows, 1)


func _enter_season_hub() -> void:
	mode = "season"
	var sn: Dictionary = Game.season
	Game.selected_team = int(sn.team)
	var n: int = sn.schedule.size()
	var rnd: int = sn.round
	var next_track: int = sn.schedule[min(rnd, n - 1)]
	_use_track(next_track)
	_start_attract()
	var me: String = Game.teams[int(sn.team)].num
	var pos := 0
	var pts := 0
	var table := Game.standings()
	for i in table.size():
		if table[i][0] == me:
			pos = i + 1
			pts = table[i][1]
	var rows := [
		{"id": "weekend", "label": "RACE %d/%d:  %s" % [rnd + 1, n, Game.tracks[next_track].short], "hint": "%s  -  %d LAPS" % [Game.tracks[next_track].name, Game.race_laps(next_track)]},
		{"id": "settings", "label": "RACE SETTINGS"},
		{"id": "garage", "label": "GARAGE SETUP"},
		{"id": "standings", "label": "STANDINGS", "hint": ("YOU ARE %s WITH %d POINTS" % [Game.ordinal(pos), pts]) if pos > 0 else "NO RACES RUN YET"},
		{"id": "abandon", "label": "ABANDON SEASON", "hint": "DELETES THE SAVED SEASON"},
		{"id": "main", "label": "MAIN MENU", "hint": "YOUR SEASON IS SAVED"},
	]
	_open_menu("hub", "SEASON  -  #%s %s" % [me, Game.teams[int(sn.team)].driver], rows, 0)


func _enter_options() -> void:
	var rows := [
		{"id": "gfx", "label": "GRAPHICS", "values": ["1999", "MODERN"] if Game.modern_supported else ["1999"], "index": 1 if Game.modern else 0, "hint": "MODERN NEEDS A VULKAN GPU (NOT AVAILABLE IN THE BROWSER)"},
		{"id": "scan", "label": "SCANLINES (1999)", "values": ["OFF", "ON"], "index": 1 if Game.scanlines else 0},
		{"id": "reset", "label": "RESET LAP RECORDS"},
		{"id": "back", "label": "DONE"},
	]
	_open_menu("options", "OPTIONS", rows, 3)


func _on_menu_changed(id: String, idx: int) -> void:
	synth.beep(880.0, 0.04)
	match menu_kind:
		"race_setup":
			if Game.settings.has(id):
				Game.settings[id] = idx
				Game.save_settings()
		"garage":
			if id == "balance":
				Game.setup.balance = idx - 3
			elif Game.setup.has(id):
				Game.setup[id] = idx
			Game.save_settings()
		"paint":
			Game.custom[id] = idx + 1 if id == "num" else idx
			_paint_preview()
		"options":
			if id == "gfx" and Game.modern_supported and (idx == 1) != Game.modern:
				Game.toggle_graphics()
				Game.save_settings()
			elif id == "scan":
				Game.scanlines = idx == 1
				scan_rect.visible = Game.scanlines and not Game.modern
				Game.save_settings()


func _on_menu_activated(id: String) -> void:
	synth.beep(1320.0, 0.06)
	if id.begins_with("up_"):
		var key := id.substr(3)
		if Game.buy_upgrade(key):
			synth.beep(1760.0, 0.15)
		else:
			synth.beep(220.0, 0.2)
		_enter_rnd(menu.cursor)
		return
	if id.begins_with("offer_"):
		Game.career.sponsor = Game.career.offers[int(id.substr(6))]
		Game.save_career()
		_enter_career_hub()
		return
	if id.begins_with("ch_"):
		_start_challenge(int(id.substr(3)))
		return
	match id:
		"go", "weekend":
			_start_weekend()
		"garage":
			_enter_garage("race_setup" if menu_kind == "race_setup" else "hub")
		"rnd":
			_enter_rnd()
		"sponsors":
			_enter_sponsors()
		"stats":
			_enter_career_stats()
		"retire":
			Game.clear_career()
			Game.clear_season()
			_enter_title()
		"settings":
			_enter_race_setup("hub")
		"standings":
			_enter_standings()
		"abandon":
			Game.clear_season()
			_enter_title()
		"main":
			_enter_title()
		"start_season":
			Game.new_season(Game.selected_team, menu.value("slen"))
			_enter_season_hub()
		"save":
			Game.save_custom()
			Game.selected_team = Game.custom_team_idx
			if preview_car:
				preview_car.queue_free()
				preview_car = null
			_enter_mode_select()
		"reset":
			Game.records = ConfigFile.new()
			Game.records.save(Game.RECORDS_PATH)
			hud.sub_message("RECORDS CLEARED", 2.0)
		"back":
			_on_menu_cancelled()


func _on_menu_cancelled() -> void:
	match menu_kind:
		"race_setup":
			if menu_return == "hub" or mode == "season" or mode == "career":
				_return_hub()
			else:
				_enter_car_select()
		"garage":
			if menu_return == "hub":
				_return_hub()
			else:
				_enter_race_setup()
		"rnd", "sponsors":
			_enter_career_hub()
		"hub", "options":
			_enter_title()
		"challenges":
			_enter_mode_select()
		"paint":
			if preview_car:
				preview_car.queue_free()
				preview_car = null
			Game.load_custom()
			_enter_mode_select()
		"season_setup":
			_enter_car_select()


# --- race weekends ------------------------------------------------------------------

func _start_weekend() -> void:
	sessions = [["race"], ["qualify", "race"], ["practice", "qualify", "race"]][Game.settings.weekend]
	session_idx = 0
	qual_grid = []
	qual_rows = []
	_start_session()


func _start_session() -> void:
	if session_idx >= sessions.size():
		_enter_title()
		return
	session = sessions[session_idx]
	_enter_countdown()


## Starting order for the race: qualifying order if we have one (the player keeps
## their spot even in a smaller field), otherwise random with the player mid-pack.
func _grid_for(size: int, player_team: int) -> Array:
	if qual_grid.is_empty():
		return []
	var grid: Array = []
	for t in qual_grid:
		var room: int = size - (0 if grid.has(player_team) or t == player_team else 1)
		if grid.size() < room or t == player_team:
			grid.append(t)
	return grid.slice(0, size)


## A realistic pole-speed lap for this track: one AI car, alone, simulated offscreen.
func _qual_base_time() -> float:
	var key: int = Game.selected_track
	if _qual_base.has(key):
		return _qual_base[key]
	var r: Node3D = Race.new()
	add_child(r)
	r.arcade_setup = true
	r.setup(track, -1, 2, 1)
	r.visible = false
	r.cars[0].ai_skill = 1.0
	r.grid_up(-track.length * 0.7, PACE_SPEED)
	r.go_green()
	var t := 0.0
	while t < 300.0 and r.cars[0].lap() < 1:
		r.tick(1.0 / 60.0)
		t += 1.0 / 60.0
	var best: float = r.cars[0].best_lap if r.cars[0].best_lap > 0.0 else track.length / 70.0
	r.queue_free()
	_qual_base[key] = best
	return best


func _finish_qualifying(player_time: float) -> void:
	var base := _qual_base_time()
	var rng2 := RandomNumberGenerator.new()
	rng2.randomize()
	qual_rows = []
	for i in Game.teams.size():
		if i == Game.selected_team:
			qual_rows.append([i, player_time])
			continue
		var skill: float = float(Game.teams[i].get("skill", 0.97)) * Game.ai_skill_scale() / 0.985
		var t: float = base * (0.994 + (0.99 - skill) * 0.9) + rng2.randf_range(0.0, base * 0.006)
		qual_rows.append([i, t])
	qual_rows.sort_custom(func(a, b): return a[1] < b[1])
	qual_grid = qual_rows.map(func(r): return r[0])
	_enter_session_results()


func _enter_session_results() -> void:
	_set_state(State.SESSION_RESULTS)
	hud.visible = false
	_clear_screen()
	_panel(Rect2(30, 10, 580, 460), Color(0, 0, 0, 0.72))
	_label("", "QUALIFYING", 34, Color(1.0, 0.85, 0.1), Vector2(0, 16), HORIZONTAL_ALIGNMENT_CENTER, 8)
	_label("", track.cfg.name, 14, Color(0.5, 0.9, 1.0), Vector2(0, 58), HORIZONTAL_ALIGNMENT_CENTER, 4)
	var y := 86
	var pole: float = qual_rows[0][1]
	var shown := 0
	for i in qual_rows.size():
		var ti: int = qual_rows[i][0]
		var me := ti == Game.selected_team
		if shown >= 13 and not me:
			continue
		if shown >= 14:
			break
		var t: Dictionary = Game.teams[ti]
		var col := Color(1, 0.9, 0.2) if me else Color.WHITE
		var mph: float = track.length / qual_rows[i][1] * Game.MPS_TO_MPH
		_label("", "%2d" % (i + 1), 16, col, Vector2(60, y), HORIZONTAL_ALIGNMENT_LEFT, 4)
		_label("", "#" + t.num, 16, t.c1.lightened(0.3), Vector2(100, y), HORIZONTAL_ALIGNMENT_LEFT, 4)
		_label("", ("%s  (YOU)" % t.driver) if me else t.driver, 16, col, Vector2(160, y), HORIZONTAL_ALIGNMENT_LEFT, 4)
		_label("", "%s  %.3f MPH" % [Game.format_time(qual_rows[i][1]), mph] if i == 0 else "+%.3f" % (qual_rows[i][1] - pole), 14, col, Vector2(410, y + 2), HORIZONTAL_ALIGNMENT_LEFT, 3)
		y += 24
		shown += 1
	_label("start", "PRESS START FOR THE RACE", 18, Color.WHITE, Vector2(0, 440), HORIZONTAL_ALIGNMENT_CENTER, 5)


# --- season -------------------------------------------------------------------------

func _after_season_race() -> void:
	var finish: Array = []
	for i in race.order.size():
		var c: Node3D = race.order[i]
		var pts: int = race.control.finishing_points(i + 1, c) if race.control else 0
		finish.append({"num": c.team.num, "pos": i + 1, "points": pts})
	if mode == "career":
		var p: Node3D = race.player
		var pole: bool = not qual_grid.is_empty() and qual_grid[0] == Game.selected_team
		Game.career_race(race.position_of(p), race.cars.size(), p.laps_led, pole)
	Game.record_season_race(Game.selected_track, finish)
	if int(Game.season.round) >= Game.season.schedule.size():
		_enter_standings(true)
	else:
		_return_hub()


func _return_hub() -> void:
	if mode == "career" or Game.season.get("career", false):
		_enter_career_hub()
	else:
		_enter_season_hub()


func _enter_standings(final := false) -> void:
	_set_state(State.STANDINGS)
	_clear_screen()
	_panel(Rect2(30, 10, 580, 460), Color(0, 0, 0, 0.72))
	var table := Game.standings()
	var me: String = Game.teams[int(Game.season.team)].num
	var head := "FINAL STANDINGS" if final else "STANDINGS"
	_label("", head, 34, Color(1.0, 0.85, 0.1), Vector2(0, 16), HORIZONTAL_ALIGNMENT_CENTER, 8)
	_label("", "AFTER %d OF %d RACES" % [int(Game.season.round), Game.season.schedule.size()], 14, Color(0.5, 0.9, 1.0), Vector2(0, 58), HORIZONTAL_ALIGNMENT_CENTER, 4)
	for h in [["POS", 60], ["CAR", 100], ["DRIVER", 160], ["PTS", 420], ["WINS", 470], ["TOP 5", 522]]:
		_label("", h[0], 11, Color(0.6, 0.7, 0.8), Vector2(h[1], 76), HORIZONTAL_ALIGNMENT_LEFT, 3)
	var y := 92
	var shown := 0
	for i in table.size():
		var row: Array = table[i]
		var is_me: bool = row[0] == me
		if shown >= 13 and not is_me:
			continue
		if shown >= 14:
			break
		var t := Game.team_by_num(row[0])
		var col := Color(1, 0.9, 0.2) if is_me else Color.WHITE
		_label("", "%2d" % (i + 1), 16, col, Vector2(60, y), HORIZONTAL_ALIGNMENT_LEFT, 4)
		_label("", "#" + row[0], 16, (t.c1 as Color).lightened(0.3) if t else Color.WHITE, Vector2(100, y), HORIZONTAL_ALIGNMENT_LEFT, 4)
		_label("", t.driver if t else "?", 16, col, Vector2(160, y), HORIZONTAL_ALIGNMENT_LEFT, 4)
		_label("", "%d" % row[1], 16, Color(1, 0.85, 0.3), Vector2(420, y), HORIZONTAL_ALIGNMENT_LEFT, 4)
		_label("", "%d" % row[2], 14, col, Vector2(478, y + 2), HORIZONTAL_ALIGNMENT_LEFT, 3)
		_label("", "%d" % row[3], 14, col, Vector2(530, y + 2), HORIZONTAL_ALIGNMENT_LEFT, 3)
		y += 24
		shown += 1
	if final and table.size() > 0:
		var champ := Game.team_by_num(table[0][0])
		_label("", "CHAMPION:  #%s %s" % [table[0][0], champ.driver], 20, Color(0.3, 1.0, 0.4), Vector2(0, 420), HORIZONTAL_ALIGNMENT_CENTER, 5)
		if Game.season.get("career", false) and not Game.career.is_empty():
			var my_pos := 0
			var my_row: Array = []
			for i in table.size():
				if table[i][0] == me:
					my_pos = i + 1
					my_row = table[i]
			Game.career_season_end(my_pos, my_row[1] if my_row.size() else 0, my_row[2] if my_row.size() else 0)
		else:
			Game.clear_season()
	_label("start", "PRESS START", 16, Color.WHITE, Vector2(0, 446), HORIZONTAL_ALIGNMENT_CENTER, 4)


# --- paint shop ---------------------------------------------------------------------

func _enter_paint_shop() -> void:
	var cols: Array = Game.PALETTE.map(func(p): return p[0])
	var nums: Array = range(1, 100).map(func(n): return str(n))
	var rows := [
		{"id": "num", "label": "CAR NUMBER", "values": nums, "index": int(Game.custom.num) - 1},
		{"id": "first", "label": "FIRST NAME", "values": Game.FIRST_NAMES, "index": Game.custom.first},
		{"id": "last", "label": "LAST NAME", "values": Game.LAST_NAMES, "index": Game.custom.last},
		{"id": "sponsor", "label": "SPONSOR", "values": Game.SPONSORS, "index": Game.custom.sponsor},
		{"id": "c1", "label": "BODY COLOR", "values": cols, "index": Game.custom.c1},
		{"id": "c2", "label": "TRIM COLOR", "values": cols, "index": Game.custom.c2},
		{"id": "cn", "label": "NUMBER COLOR", "values": cols, "index": Game.custom.cn},
		{"id": "save", "label": "SAVE CAR", "hint": "YOUR CAR APPEARS IN CAR SELECT FOR EVERY MODE"},
	]
	_open_menu("paint", "PAINT SHOP", rows, 0)
	menu.top = 90
	menu.row_h = 30
	menu.width = 330
	menu.left_override = 30
	menu.build("PAINT SHOP", rows, 0)
	_paint_preview()


func _paint_preview() -> void:
	if preview_car:
		preview_car.queue_free()
	preview_car = Car.new()
	add_child(preview_car)
	preview_car.setup(Game.custom_team(), null)
	var base: Vector3 = track.pos[0] + track.right[0] * (track.inner_wall() - 14.0)
	preview_car.position = base + Vector3.UP * 0.02


# --- Lightning Challenges ---------------------------------------------------------

func _enter_challenges() -> void:
	mode = "challenge"
	var rows: Array = []
	for i in Game.CHALLENGES.size():
		var ch: Dictionary = Game.CHALLENGES[i]
		var done: bool = Game.challenges_done.has(str(i))
		rows.append({"id": "ch_%d" % i, "label": ("[X] " if done else "[ ] ") + ch.name, "hint": ch.desc})
	var title := "LIGHTNING CHALLENGES  %d/%d" % [Game.challenges_done.size(), Game.CHALLENGES.size()]
	_open_menu("challenges", title, rows, max(challenge_idx, 0))
	menu.row_h = 28
	menu.build(title, rows, max(challenge_idx, 0))


func _start_challenge(idx: int) -> void:
	challenge_idx = idx
	challenge = Game.CHALLENGES[idx]
	challenge_result = ""
	session = "race"
	_use_track(int(challenge.track))
	_enter_countdown()


# --- career -------------------------------------------------------------------------

func _enter_career_hub() -> void:
	mode = "career"
	var cr: Dictionary = Game.career
	if Game.season.is_empty():
		Game.new_season(int(cr.team), 1)
		Game.season.career = true
		Game.save_season()
	var sn: Dictionary = Game.season
	Game.selected_team = int(cr.team)
	var n: int = sn.schedule.size()
	var rnd: int = min(int(sn.round), n - 1)
	var next_track: int = sn.schedule[rnd]
	_use_track(next_track)
	_start_attract()
	var me: String = Game.teams[int(cr.team)].num
	var pos := 0
	var pts := 0
	var table := Game.standings()
	for i in table.size():
		if table[i][0] == me:
			pos = i + 1
			pts = table[i][1]
	var sp: Dictionary = cr.sponsor
	var rows := [
		{"id": "weekend", "label": "RACE %d/%d:  %s" % [rnd + 1, n, Game.tracks[next_track].short], "hint": "%s  -  %d LAPS" % [Game.tracks[next_track].name, Game.race_laps(next_track)]},
		{"id": "rnd", "label": "R&D SHOP", "hint": "BANK: $%s" % Game.money_text(cr.money)},
		{"id": "sponsors", "label": "SPONSOR: %s" % sp.name, "hint": "$%s PER RACE, $%s FOR A WIN" % [Game.money_text(sp.per_race), Game.money_text(sp.bonus_win)]},
		{"id": "garage", "label": "GARAGE SETUP"},
		{"id": "settings", "label": "RACE SETTINGS"},
		{"id": "standings", "label": "STANDINGS", "hint": ("SEASON %d: %s WITH %d POINTS" % [cr.year, Game.ordinal(pos), pts]) if pos > 0 else "SEASON %d: NO RACES RUN YET" % cr.year},
		{"id": "stats", "label": "CAREER RECORD", "hint": cr.get("last", "")},
		{"id": "main", "label": "SAVE + MAIN MENU"},
		{"id": "retire", "label": "RETIRE", "hint": "ENDS AND DELETES THIS CAREER"},
	]
	_open_menu("hub", "YEAR %d  -  $%s  -  REP %d" % [cr.year, Game.money_text(cr.money), cr.rep], rows, 0)
	menu.row_h = 28
	menu.build(menu.title, rows, 0)


func _enter_rnd(cursor := 0) -> void:
	var rows: Array = []
	for u in Game.UPGRADES:
		var lvl: int = Game.career.upgrades[u[0]]
		var bar := "|".repeat(lvl) + ".".repeat(Game.MAX_UPGRADE - lvl)
		var cost := "MAXED" if lvl >= Game.MAX_UPGRADE else "$" + Game.money_text(Game.upgrade_cost(u[0]))
		rows.append({"id": "up_" + u[0], "label": "%s  %s" % [u[1], bar], "hint": "%s  -  NEXT LEVEL %s" % [u[2], cost]})
	rows.append({"id": "back", "label": "DONE"})
	_open_menu("rnd", "R&D  -  BANK $%s" % Game.money_text(Game.career.money), rows, cursor)


func _enter_sponsors() -> void:
	var rows: Array = []
	var i := 0
	for o in Game.career.offers:
		rows.append({"id": "offer_%d" % i, "label": o.name, "hint": "$%s PER RACE  +  $%s PER WIN" % [Game.money_text(o.per_race), Game.money_text(o.bonus_win)]})
		i += 1
	rows.append({"id": "back", "label": "KEEP %s" % Game.career.sponsor.name})
	_open_menu("sponsors", "SPONSOR OFFERS  (REP %d)" % Game.career.rep, rows, rows.size() - 1)


func _enter_career_stats() -> void:
	_set_state(State.STANDINGS)
	_clear_screen()
	_panel(Rect2(60, 20, 520, 440), Color(0, 0, 0, 0.72))
	var cr: Dictionary = Game.career
	var t: Dictionary = Game.teams[int(cr.team)]
	_label("", "CAREER RECORD", 32, Color(1.0, 0.85, 0.1), Vector2(0, 28), HORIZONTAL_ALIGNMENT_CENTER, 8)
	_label("", "#%s %s  -  %s" % [t.num, t.driver, cr.sponsor.name], 16, Color(0.5, 0.9, 1.0), Vector2(0, 70), HORIZONTAL_ALIGNMENT_CENTER, 4)
	var st: Dictionary = cr.stats
	var lines := [
		["SEASONS", str(int(cr.year))], ["STARTS", str(st.starts)], ["WINS", str(st.wins)], ["TOP 5", str(st.top5)],
		["TOP 10", str(st.top10)], ["POLES", str(st.poles)], ["LAPS LED", str(st.laps_led)],
		["CHAMPIONSHIPS", str(st.titles)], ["CAREER EARNINGS", "$" + Game.money_text(st.earnings)], ["REPUTATION", "%d / 100" % cr.rep],
	]
	var y := 104
	for ln in lines:
		_label("", ln[0], 18, Color.WHITE, Vector2(110, y), HORIZONTAL_ALIGNMENT_LEFT, 4)
		_label("", ln[1], 18, Color(1, 0.85, 0.3), Vector2(380, y), HORIZONTAL_ALIGNMENT_LEFT, 4)
		y += 28
	var hist := ""
	for h in cr.history:
		hist += "Y%d: %s  " % [h.year, Game.ordinal(h.pos)]
	if hist != "":
		_label("", hist, 12, Color(0.8, 0.85, 0.9), Vector2(0, 400), HORIZONTAL_ALIGNMENT_CENTER, 3)
	_label("start", "PRESS START", 16, Color.WHITE, Vector2(0, 432), HORIZONTAL_ALIGNMENT_CENTER, 4)


# --- replays ------------------------------------------------------------------------

func _enter_replay() -> void:
	_set_state(State.REPLAY)
	screen.visible = false
	replay_t = race.rec_times[0]
	replay_rate = 1.0
	replay_cam = 0
	replay_focus = max(race.cars.find(race.player), 0)
	tv_timer = 0.0
	hud.visible = false
	var ov := Game.make_label("", 14, Color(1, 0.9, 0.2), 4)
	ov.name = "ReplayOverlay"
	ov.position = Vector2(16, 12)
	ui_layer.add_child(ov)


func _replay_overlay() -> void:
	var ov: Label = ui_layer.get_node_or_null("ReplayOverlay")
	if ov == null:
		return
	if state != State.REPLAY:
		ov.queue_free()
		return
	var c: Node3D = race.cars[replay_focus]
	var span: float = race.rec_times[race.rec_times.size() - 1] - race.rec_times[0]
	var at: float = replay_t - race.rec_times[0]
	var rate := "PAUSED" if replay_rate == 0.0 else ("x%s" % str(replay_rate))
	var blink := "REPLAY" if int(Time.get_ticks_msec() / 500) % 2 == 0 else "      "
	ov.text = "%s  %s / %s  %s   #%s %s   [%s]\nLEFT/RIGHT CAR   UP/DOWN SPEED   C CAMERA   START EXIT" % [blink, Game.format_time(at), Game.format_time(span), rate, c.team.num, c.team.driver, ["TV", "CHASE", "BUMPER", "HELICOPTER"][replay_cam]]
	synth.engine_on = true
	synth.engine_rpm = 3000.0 + abs(c.v) * 70.0
	synth.engine_load = 0.8
