extends Node3D
## Top level: owns the world, camera, UI and the arcade game flow
## (attract -> course select -> car select -> rolling start -> race -> results).

const Track := preload("res://scripts/track.gd")
const Race := preload("res://scripts/race.gd")
const Car := preload("res://scripts/car.gd")
const Weather := preload("res://scripts/weather.gd")
const TelemetryHud := preload("res://scripts/telemetry_hud.gd")
const TrackEditor := preload("res://scripts/track_editor.gd")
const Net := preload("res://scripts/net.gd")
const Wheel := preload("res://scripts/wheel.gd")
const Hud := preload("res://scripts/hud.gd")
const Synth := preload("res://scripts/audio.gd")
const Soundscape := preload("res://scripts/soundscape.gd")
const CamFeel := preload("res://scripts/cam_feel.gd")
const Cockpit := preload("res://scripts/cockpit.gd")
const CarBody := preload("res://scripts/car_body.gd")
const Showtime := preload("res://scripts/showtime.gd")
const Ghost := preload("res://scripts/ghost.gd")
const Atmosphere := preload("res://scripts/atmosphere.gd")
const RainFx := preload("res://scripts/rain_fx.gd")
const RaceDay := preload("res://scripts/race_day.gd")
const TouchControls := preload("res://scripts/touch_controls.gd")
const Tutorial := preload("res://scripts/tutorial.gd")
const Cloud := preload("res://scripts/cloud.gd")
const Menu := preload("res://scripts/menu.gd")

enum State { TITLE, MODE_SELECT, TRACK_SELECT, CAR_SELECT, MENU, COUNTDOWN, RACE, FINISHED, RESULTS, SESSION_RESULTS, STANDINGS, REPLAY }

const PACE_SPEED := 32.0
const SELECT_TIME := 20.0

var state := State.TITLE
var state_time := 0.0
var paused := false
var resume_t := 0.0 # > 0: counting 3-2-1 back into the race after a pause
var _bg_paused := false # paused because the app went to the background
var _resume_label: Label
const RESUME_PATH := "user://race_resume.cfg"
var _code_edit: LineEdit
var _account_note := ""
## A checkpoint being resumed (see _save_checkpoint), while the race is rebuilt.
var _resume := {}
var _ckpt_lap := -1
var _battery_t := 0.0 # seconds until the battery saver looks again
var battery_saver_on := false

var tracks := {}
var track: Node3D
var race: Node3D
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var synth: Node
var soundscape: Node3D
var hud: Control
var tutorial: Control # first race on a phone: short prompts
var cloud: Node # leaderboards, friends, events, progress online
var rival: Node3D # someone else's best lap to chase (a ghost)
var last_award := {} # the XP the last race earned
var _frame_ms: PackedFloat32Array = [] # this race's frame times (for the stats)
var frame_timer: Node # times our own work each frame (for AUTO field sizes)
var _script_ms := 0.0 # this race's script time, summed over _frame_ms's frames
var ui_layer: CanvasLayer
var ui_root: Control # the 640x480 menu frame, centred however wide the screen is
var screen: Control
var pause_layer: CanvasLayer
## The pause screen's keyboard keys (the touch controls show buttons instead).
var pause_keys: Label
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
var feel := CamFeel.new() # the camera feels the car's accelerations and the road
var cockpit: Node3D # the interior of the car you're riding in (cockpit view)
var atmosphere: Node # haze, sun shafts, lingering smoke, focus, glare
var rain_fx: Node3D # water film and dry line, spray, drops on the glass
var race_day: Node3D # pit crews, the flagman, the crowd, fireworks (a child of the race)
var touch: Control # on-screen controls for phones and tablets
var pit_menu: Control # the pit call screen under a quick caution (the race waits)
var _pit_info := {}
var _pit_board: Label
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
	["QUICK RACE", "STRAIGHT TO THE GRID: A SHORT RACE AT A RANDOM TRACK IN YOUR CAR.", "quick"],
	["ARCADE", "BEAT THE CLOCK. 16 CARS, SHORT RACES, NO CAUTIONS.", "arcade"],
	["SINGLE RACE", "A FULL RACE WEEKEND: PRACTICE, QUALIFYING, CAUTIONS, PITS, STAGES.", "race"],
	["SEASON", "RUN A CHAMPIONSHIP. POINTS, WINS AND STANDINGS ARE SAVED.", "season"],
	["CAREER", "ROOKIE TO CHAMPION: PRIZE MONEY, SPONSORS AND R&D UPGRADES.", "career"],
	["ONLINE", "RACE FRIENDS: HOST A ROOM AND SHARE THE CODE, OR JOIN ONE.", "online"],
	["LEADERBOARDS", "WORLD RECORDS, YOUR FRIENDS, AND THE DAILY AND WEEKLY EVENTS.", "boards"],
	["CHALLENGES", "RACE-DEFINING MOMENTS, AND A NEW ONE EVERY DAY.", "challenges"],
	["PAINT SHOP", "CREATE YOUR OWN CAR: NUMBER, DRIVER, SPONSOR, SCHEME AND COLORS.", "paint"],
	["OPTIONS", "CONTROLS, GRAPHICS, SOUND AND RECORDS.", "options"],
	["2 PLAYER", "SPLIT SCREEN. PLAYER 2: I J K L, U = PIT, OR A SECOND GAMEPAD.", "2p"],
	["TRACK EDITOR", "BUILD YOUR OWN TRACK, TEST-DRIVE IT AND SAVE IT AS A MOD.", "editor"],
]
## Modes that need a keyboard or two controllers aren't offered on a phone.
const DESK_MODES := ["2p", "editor"]


## The modes on offer on this device.
func _modes() -> Array:
	var list: Array = MODES
	if Game.touch_device() or Game.touch_active:
		list = MODES.filter(func(m): return not DESK_MODES.has(m[2]))
	var ck := resume_info()
	if not ck.is_empty():
		list = [["RESUME RACE", "LAP %d OF %d AT %s, RUNNING %s. CARRY ON WHERE YOU LEFT OFF." % [ck.lap, ck.laps, ck.track_name, Game.ordinal(ck.place)], "resume"]] + list
	return list


var mode_idx := 0
## Intro, showroom, TV package, replays, last-lap drama and victory lane.
var showtime: Node
## Your best lap at this track, driven by a see-through car.
var ghost: Node3D
var _quick_saved := {}

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
# split screen
var choosing_p2 := false
var team2 := 1
var split_layer: CanvasLayer
var split_cams: Array[Camera3D] = []
var split_huds: Array = []
var split_state := [{}, {}]
var replay_t := 0.0
var replay_rate := 1.0
var replay_focus := 0
var replay_cam := 0
var challenge := {}
var challenge_idx := -1
var challenge_result := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Never let a slow frame snowball into several catch-up physics ticks (input lag).
	Engine.max_physics_steps_per_frame = 2
	# GPU frame time feeds the AUTO quality setting.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
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
	_build_motion_blur()
	atmosphere = Atmosphere.new()
	add_child(atmosphere)
	atmosphere.setup(cam, env, sun)
	net = Net.new()
	net.name = "Net"
	add_child(net)
	wheel = Wheel.new()
	add_child(wheel)
	wheel.start_helper()
	net.lobby_changed.connect(func():
		if state == State.MENU and menu_kind == "lobby":
			if not net.connected and not net.hosting and net.room_code == "":
				_enter_online() # the room wasn't found, or the host left
			else:
				_enter_lobby())
	net.status.connect(func(t): _sub(t, 3.0))
	net.race_started.connect(_net_start_race)
	soundscape = Soundscape.new() # first: it sets up the "World" bus the synth uses
	add_child(soundscape)
	synth = Synth.new()
	add_child(synth)

	hud = Hud.new()
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 1
	add_child(hud_layer)
	hud_layer.add_child(hud)
	tutorial = Tutorial.new()
	tutorial.main = self
	hud_layer.add_child(tutorial)
	telemetry = TelemetryHud.new()
	telemetry.visible = false
	hud_layer.add_child(telemetry)
	hud.visible = false

	ui_layer = CanvasLayer.new()
	ui_layer.layer = 2
	add_child(ui_layer)
	ui_root = Game.center_frame(Control.new(), true)
	ui_layer.add_child(ui_root)

	pause_layer = CanvasLayer.new()
	pause_layer.layer = 5
	pause_layer.visible = false
	add_child(pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_layer.add_child(dim)
	var pause_frame := Game.center_frame(Control.new())
	pause_layer.add_child(pause_frame)
	var pl := Game.make_label("PAUSED", 56, Color(1, 0.9, 0.2), 8)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.size = Vector2(640, 60)
	pl.position = Vector2(0, 170)
	pause_frame.add_child(pl)
	_resume_label = Game.make_label("", 96, Color(1, 0.9, 0.2), 10)
	_resume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_resume_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_resume_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_resume_label.visible = false
	ui_layer.add_child(_resume_label)
	pause_keys = Game.make_label("ESC  RESUME        Q  QUIT / END SESSION", 18, Color.WHITE, 5)
	pause_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_keys.size = Vector2(640, 30)
	pause_keys.position = Vector2(0, 250)
	pause_frame.add_child(pause_keys)

	var touch_layer := CanvasLayer.new()
	touch_layer.layer = 6 # above the pause screen, so RESUME / QUIT can be tapped
	add_child(touch_layer)
	touch = TouchControls.new()
	touch.main = self
	touch_layer.add_child(touch)
	showtime = Showtime.new()
	showtime.name = "Showtime"
	add_child(showtime)
	showtime.setup(self)
	ghost = Ghost.new()
	ghost.name = "Ghost"
	add_child(ghost)
	rival = Ghost.new()
	rival.name = "Rival"
	add_child(rival)
	frame_timer = preload("res://scripts/frame_timer.gd").new()
	add_child(frame_timer)
	cloud = Cloud.new()
	cloud.name = "Cloud"
	add_child(cloud)
	Game.save_changed.connect(cloud.save_soon)
	cloud.restored.connect(func():
		_sub("YOUR SAVED GAME IS HERE", 2.5)
		if state == State.MODE_SELECT:
			_enter_mode_select())
	if cloud.enabled:
		cloud.register(func(ok: bool):
			if ok:
				cloud.sync(func(_ok: bool):
					cloud.push_profile())
				cloud.load_friends())

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
	# Modern fills any screen shape (the race view widens; menus stay centred in
	# a 640x480 frame); 1999 keeps its 4:3 picture.
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND if modern else Window.CONTENT_SCALE_ASPECT_KEEP
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_DISABLED
	if Game.forward_plus:
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 1.0
	if not OS.has_feature("web"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if Game.vsync else DisplayServer.VSYNC_DISABLED)
	scan_rect.visible = Game.scanlines and not modern
	if track == null:
		return
	var cfg: Dictionary = track.cfg
	var night: bool = cfg.get("night", false)
	sun.rotation = Vector3(-deg_to_rad(cfg.sun_elev), deg_to_rad(cfg.sun_az), 0)
	var sky := Sky.new()
	if modern:
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/sky.gdshader")
		sm.set_shader_parameter("zenith", cfg.sky_top)
		sm.set_shader_parameter("horizon", cfg.sky_horizon)
		sm.set_shader_parameter("ground", (cfg.grass as Color).darkened(0.45))
		sm.set_shader_parameter("sun_color", Color(1.0, 0.8, 0.6) if cfg.sun_elev < 20.0 else Color(1.0, 0.95, 0.86))
		sm.set_shader_parameter("night", night)
		sm.set_shader_parameter("energy", 1.0)
		sm.set_shader_parameter("cloud_cover", float(cfg.get("clouds", 0.42)))
		sm.set_shader_parameter("cloud_seed", float(hash(cfg.name) % 100))
		_set_sky_photo(sm, "night" if night else ("dusk" if float(cfg.sun_elev) < 16.0 else "day"))
		sky.sky_material = sm
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
		# AgX: a filmic curve, closer to how a camera sees a sunny track than ACES.
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
		env.tonemap_exposure = 1.12 if not night else 1.45
		env.tonemap_white = 6.0
		env.ssao_enabled = true
		env.ssao_radius = 1.2
		env.ssao_intensity = 1.8
		env.ssr_enabled = true
		env.ssr_max_steps = 48
		env.ssr_fade_in = 0.2
		env.ssr_fade_out = 2.0
		env.glow_enabled = true
		env.glow_intensity = 0.6 if not night else 0.95
		env.glow_bloom = 0.04 if not night else 0.08
		env.glow_hdr_threshold = 1.1 if not night else 0.85
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
		if not Game.forward_plus:
			# The browser renderer has no SSAO and lights in a flatter space, so the
			# sky fill washes everything out; pull it back.
			env.ambient_light_energy *= 0.5
			env.tonemap_exposure *= 0.85
			sun.light_energy *= 1.1
		_apply_quality(night)
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


## Real skies (CC0 Poly Haven HDRIs) for what the cars reflect and the ambient
## light: [file, where its sun is across the panorama, brightness to match ours].
const SKY_PHOTOS := {
	"day": ["res://assets/hdri/quarry_01.exr", 0.600, 1.66],
	"overcast": ["res://assets/hdri/blouberg_sunrise_2.exr", 0.055, 0.66],
	"dusk": ["res://assets/hdri/venice_sunset.exr", 0.600, 0.73],
	"night": ["res://assets/hdri/moonless_golf.exr", 0.321, 0.2],
}
var _sky_photo := ""
var _sky_tex := {}


func _set_sky_photo(sm: ShaderMaterial, kind: String) -> void:
	if kind == _sky_photo and sm.get_shader_parameter("env_mix") != null and float(sm.get_shader_parameter("env_mix")) > 0.0:
		return
	var info: Array = SKY_PHOTOS[kind]
	if not _sky_tex.has(kind):
		_sky_tex[kind] = load(info[0]) if ResourceLoader.exists(info[0]) else null
	var tex = _sky_tex[kind]
	if tex == null:
		sm.set_shader_parameter("env_mix", 0.0)
		return
	_sky_photo = kind
	sm.set_shader_parameter("env_map", tex)
	sm.set_shader_parameter("env_sun_u", info[1])
	sm.set_shader_parameter("env_scale", info[2])
	sm.set_shader_parameter("env_mix", 0.85)


## Sun, sky and light from the race clock, plus rain and a wet track (weather.gd).
var _rain_fx: Node3D
var _base_fog := 0.0


func apply_time_and_weather(w: Node) -> void:
	if track == null or env == null or env.sky == null:
		return
	var elev: float = w.sun_elevation()
	var az: float = w.sun_azimuth()
	var dark: bool = elev < 0.0
	var wet_avg: float = w.average_wet()
	# Below the horizon the moon lights the scene from high up instead.
	sun.rotation = Vector3(-deg_to_rad(clamp(elev, 8.0, 85.0) if not dark else 50.0), deg_to_rad(az), 0)
	var low: float = clamp(1.0 - elev / 20.0, 0.0, 1.0) # golden hour
	var sun_col := Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.62, 0.38), low)
	if dark:
		sun_col = Color(0.7, 0.78, 1.0)
	var energy: float = (0.15 if dark else lerp(1.4, 0.8, low)) * (1.0 - 0.45 * w.rain)
	sun.light_energy = energy
	sun.light_color = sun_col
	var sm = env.sky.sky_material
	if sm is ShaderMaterial and Game.modern:
		var cfg: Dictionary = track.cfg
		var night_sky: bool = elev < -3.0
		var dusk: float = clamp(1.0 - (elev + 3.0) / 12.0, 0.0, 1.0)
		sm.set_shader_parameter("night", night_sky)
		sm.set_shader_parameter("zenith", (cfg.sky_top as Color).lerp(Color(0.08, 0.1, 0.25), dusk * 0.8).lerp(Color(0.35, 0.37, 0.42), w.rain))
		sm.set_shader_parameter("horizon", (cfg.sky_horizon as Color).lerp(Color(1.0, 0.55, 0.35), low * (1.0 - w.rain)).lerp(Color(0.55, 0.57, 0.6), w.rain))
		sm.set_shader_parameter("sun_color", sun_col)
		sm.set_shader_parameter("cloud_cover", lerp(float(cfg.get("clouds", 0.42)), 0.97, w.rain))
		sm.set_shader_parameter("energy", lerp(1.0, 0.5, w.rain) * (1.0 if not dark else 0.8))
		_set_sky_photo(sm, "night" if night_sky else ("overcast" if w.rain > 0.35 else ("dusk" if elev < 16.0 else "day")))
	env.ambient_light_energy = (0.6 if dark else 1.0) * (1.0 - 0.3 * w.rain) * (0.5 if Game.modern and not Game.forward_plus else 1.0)
	if _base_fog == 0.0:
		_base_fog = env.fog_density
	env.fog_density = _base_fog * (1.0 + 3.0 * w.rain)
	if atmosphere and Game.modern:
		atmosphere.configure(true, Game.forward_plus, Game.quality_level(), dark, w.hour, max(w.rain, wet_avg * 0.5))
	# Light towers come on when it gets dark.
	for n in track.get_children():
		if n is SpotLight3D and Game.forward_plus:
			n.visible = Game.modern and (elev < 6.0)
	# A wet track: darker and glossy.
	var asphalt: Node = track.get_node_or_null("Surface_asphalt")
	if asphalt and asphalt.material_override:
		var m: StandardMaterial3D = asphalt.material_override
		if wet_avg > 0.01 or m.has_meta("wet_shown"):
			Game.style(m)
			m.roughness = lerp(m.roughness, 0.12, wet_avg)
			m.albedo_color = m.albedo_color.darkened(0.35 * wet_avg)
			m.set_meta("wet_shown", wet_avg > 0.01)
	_update_rain_fx(w.rain)


func _update_rain_fx(amount: float) -> void:
	if amount <= 0.02 and _rain_fx == null:
		return
	if _rain_fx == null:
		var qm := QuadMesh.new()
		qm.size = Vector2(0.015, 0.7)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.8, 0.85, 0.9, 0.35)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		qm.material = m
		var p := CPUParticles3D.new()
		p.amount = 1600 if Game.forward_plus else 500
		p.lifetime = 0.9
		p.local_coords = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(22, 1, 22)
		p.direction = Vector3(0.05, -1, 0)
		p.spread = 3.0
		p.initial_velocity_min = 24.0
		p.initial_velocity_max = 30.0
		p.gravity = Vector3.ZERO
		p.mesh = qm
		p.position = Vector3(0, 14, -8)
		cam.add_child(p)
		_rain_fx = p
	var rp := _rain_fx as CPUParticles3D
	rp.emitting = amount > 0.02
	# Heavier rain reads as denser, brighter streaks.
	var qm: QuadMesh = rp.mesh
	(qm.material as StandardMaterial3D).albedo_color.a = 0.12 + 0.35 * clamp(amount, 0.0, 1.0)


## Modern-mode quality preset: what each level turns on, cheapest first.
##   LOW     FSR 2 at 67%, 2 shadow splits (2K), no SSAO / SSR / volumetrics
##   MEDIUM  FSR 2 at 77%, 2 splits (4K), half-res SSAO
##   HIGH    FSR 2 at 87%, 4 splits (4K), SSAO, volumetric fog at night
##   ULTRA   native res + FSR 2 anti-aliasing, 4 splits (8K), SSAO, SSR
## FSR 2 includes temporal anti-aliasing, so MSAA stays off.
func _apply_quality(night: bool) -> void:
	var q := Game.quality_level()
	var vp := get_viewport()
	var fp := Game.forward_plus
	if fp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		vp.scaling_3d_scale = [0.67, 0.67, 0.77, 0.87, 1.0][q]
		vp.fsr_sharpness = 0.35
	else:
		# Compatibility renderer (browser): plain upscaling and FXAA.
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		_web_scale = [0.7, 0.7, 0.85, 1.0, 1.0][q]
		_fit_web_resolution(true)
		# (Godot 4.7's Compatibility renderer has no FXAA; MSAA smooths the edges.)
		vp.msaa_3d = Viewport.MSAA_2X if q >= 3 else Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size([2048, 2048, 4096, 4096, 8192][q], true)
	sun.shadow_enabled = fp or q >= 2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q >= 3 and fp else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = [150.0, 150.0, 200.0, 320.0, 420.0][q] if fp else [0.0, 0.0, 120.0, 180.0, 240.0][q]
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][q])
	env.ssao_enabled = fp and q >= 2
	if fp:
		RenderingServer.environment_set_ssao_quality(
			RenderingServer.ENV_SSAO_QUALITY_LOW if q <= 2 else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, q <= 2, 0.5, 2, 50.0, 300.0)
	env.ssr_enabled = fp and q >= 4
	env.volumetric_fog_enabled = fp and night and q >= 3
	env.glow_enabled = fp or q >= 3
	get_tree().call_group("probe", "set_visible", fp and q >= 3)
	get_tree().call_group("haze", "set_visible", fp and q >= 3)


## Browsers (phones above all): the canvas is the screen's full native size (on an
## iPhone 16 Pro Max in landscape, 2868 x 1320) and frames come as fast as the
## display refreshes (up to 120 Hz). The UI is always drawn at native resolution;
## the 3D picture starts native too, and in AUTO the resolution scale steps down
## when frames can't keep up with the refresh rate and climbs back when they can.
## RESOLUTION option: AUTO / NATIVE (always full) / BALANCED (75%) / PERFORMANCE (50%).
const RES_MODES := ["AUTO", "NATIVE", "BALANCED", "PERFORMANCE"]
var _web_scale := 1.0 # from the quality preset (desktop browsers)
var _web_px := Vector2i.ZERO
var _dyn_scale := 1.0 # AUTO's current 3D resolution scale
var _dyn_time := 0.0
var _dyn_frames := 0
var _dyn_cool := 0.0
var _js_win = null


## The display's refresh rate in Hz, as the page measured it (the browser draws a
## frame per refresh); the engine's own figure elsewhere.
func display_hz() -> float:
	if OS.has_feature("web"):
		if _js_win == null:
			_js_win = JavaScriptBridge.get_interface("window")
		var hz = _js_win.stHz if _js_win else null
		if hz != null and float(hz) > 20.0:
			return float(hz)
	var r: float = DisplayServer.screen_get_refresh_rate()
	return r if r > 20.0 else 60.0


func _fit_web_resolution(force := false) -> void:
	if Game.forward_plus:
		return
	var px: Vector2i = get_window().size
	if px != _web_px or force:
		_web_px = px
	var mode: int = int(Game.settings.get("res_mode", 0))
	var scale := 1.0
	match mode:
		0:
			scale = _dyn_scale
		1:
			scale = 1.0
		2:
			scale = 0.75
		3:
			scale = 0.5
	var mobile: bool = Game.touch_device()
	if not mobile and mode == 0:
		scale = min(scale, _web_scale) # desktop browsers follow the quality preset
	get_viewport().scaling_3d_scale = clamp(scale, 0.35, 1.0)


## AUTO resolution: hold the display's refresh rate. Measured over a second at a
## time; drops 3D resolution by 10% when frames run long, adds 5% back when there's
## plenty of room (never above native).
func _dynamic_resolution(delta: float) -> void:
	if not OS.has_feature("web") or Game.forward_plus or int(Game.settings.get("res_mode", 0)) != 0:
		return
	if paused or state != State.RACE:
		_dyn_time = 0.0
		_dyn_frames = 0
		return
	_dyn_cool = max(_dyn_cool - delta, 0.0)
	_dyn_time += delta
	_dyn_frames += 1
	if _dyn_time < 1.0:
		return
	var avg: float = _dyn_time / max(_dyn_frames, 1)
	_dyn_time = 0.0
	_dyn_frames = 0
	if _dyn_cool > 0.0:
		return
	var budget: float = 1.0 / display_hz()
	var before := _dyn_scale
	if avg > budget * 1.12:
		_dyn_scale = max(_dyn_scale - 0.1, 0.5)
	elif avg < budget * 1.03:
		_dyn_scale = min(_dyn_scale + 0.05, 1.0)
	if not is_equal_approx(before, _dyn_scale):
		_dyn_cool = 2.0
		_fit_web_resolution(true)


## Camera motion blur (desktop Modern): a full-screen card on the camera, see
## shaders/motion_blur.gdshader. Off in menus, split screen and the 1999 look.
var _blur: MeshInstance3D
var _blur_mat: ShaderMaterial
var _prev_view := Projection()
var _prev_cam := Transform3D()


func _build_motion_blur() -> void:
	if not Game.forward_plus:
		return
	_blur = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	_blur.mesh = qm
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = load("res://shaders/motion_blur.gdshader")
	# First in the transparent pass: it blurs the opaque scene, then smoke, spray,
	# skid marks, glass and text draw over it (the screen copy it reads is taken
	# before any of them, so drawing it later would paint over them all).
	_blur_mat.render_priority = -128
	_blur.material_override = _blur_mat
	_blur.extra_cull_margin = 16384.0
	_blur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blur.position = Vector3(0, 0, -1)
	_blur.visible = false
	cam.add_child(_blur)


func _update_motion_blur() -> void:
	if _blur == null:
		return
	var on: bool = Game.modern and Game.motion_blur > 0 and split_cams.is_empty() and not paused \
		and state in [State.COUNTDOWN, State.RACE, State.FINISHED, State.REPLAY]
	var xf := cam.global_transform
	var view := Projection(xf.affine_inverse())
	# A camera cut would smear the whole frame: start fresh instead.
	var cut: bool = xf.origin.distance_to(_prev_cam.origin) > 25.0 or xf.basis.z.dot(_prev_cam.basis.z) < 0.9
	_blur.visible = on and not cut
	if on:
		_blur_mat.set_shader_parameter("prev_view", _prev_view)
		_blur_mat.set_shader_parameter("amount", 0.35 if Game.motion_blur == 1 else 0.7)
		_blur_mat.set_shader_parameter("samples", 6 if Game.quality_level() <= 2 else 10)
		var riding: bool = state != State.REPLAY
		_blur_mat.set_shader_parameter("near_sharp", [10.0, 7.0, 1.0, 1.5][cam_mode] if riding else 0.0)
	_prev_view = view
	_prev_cam = xf


## AUTO quality: watch frame times while racing and step the preset down when
## frames are late, or back up (to HIGH at most) when there's plenty of headroom.
var _aq_time := 0.0
var _aq_frames := 0
var _aq_late := 0
var _aq_cool := 0.0
var _aq_good := 0.0


func _auto_quality(delta: float) -> void:
	if not Game.modern or Game.quality != 0 or state != State.RACE or paused:
		_aq_time = 0.0
		_aq_frames = 0
		_aq_late = 0
		return
	_aq_cool = max(_aq_cool - delta, 0.0)
	var hz: float = max(display_hz(), 30.0)
	if battery_saver_on:
		hz = 30.0 # capped on purpose: judge against 30 fps
	var budget: float = 1.0 / min(hz, 144.0)
	_aq_time += delta
	_aq_frames += 1
	if delta > budget * 1.5:
		_aq_late += 1
	if _aq_time < 3.0:
		return
	var late_frac: float = float(_aq_late) / maxi(_aq_frames, 1)
	var avg: float = _aq_time / maxi(_aq_frames, 1)
	_aq_time = 0.0
	_aq_frames = 0
	_aq_late = 0
	if _aq_cool > 0.0:
		return
	if (late_frac > 0.1 or avg > budget * 1.2) and Game.auto_quality > 1:
		Game.auto_quality -= 1
		_aq_good = 0.0
		_aq_cool = 6.0
		_apply_graphics()
		Game.save_settings()
	elif late_frac < 0.01 and avg < budget * 1.05:
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		if gpu_ms > 0.0 and gpu_ms < budget * 1000.0 * 0.45:
			_aq_good += 3.0
			if _aq_good >= 15.0 and Game.auto_quality < 3:
				Game.auto_quality += 1
				_aq_good = 0.0
				_aq_cool = 6.0
				_apply_graphics()
				Game.save_settings()
		else:
			_aq_good = 0.0


## Spins and wrecks: smoke hangs in the air, the crowd gets on its feet.
func _on_race_incident(c: Node3D, kind: String) -> void:
	if kind != "spin" and kind != "out":
		return
	atmosphere.puff(c.global_position, 1.4 if kind == "out" else 1.0)
	soundscape.cheer(1.0 if kind == "out" else 0.6)


func _new_race(player_team: int) -> void:
	if race:
		race.queue_free()
		race = null
	race = Race.new()
	race.name = "Race"
	add_child(race)
	race.incident.connect(_on_race_incident)
	atmosphere.clear_smoke()
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
	elif mode == "online":
		var roster: Array = net_config.roster
		race.setup(track, player_team, int(net_config.laps), roster.size(), roster)
		# The full rules: the host's race control runs them for everyone.
		race.enable_rules()
		race.control.message.connect(_on_control_message)
		race.control.flag_changed.connect(_on_flag)
	elif mode == "2p":
		var size2: int = Game.field_size()
		race.setup(track, player_team, Game.race_laps(Game.selected_track), size2, [], team2)
		race.enable_rules()
		race.control.message.connect(_on_control_message)
		race.control.flag_changed.connect(_on_flag)
	elif sim and session == "race" and not _resume.is_empty():
		var roster: Array = _resume.cars.map(func(c): return int(c.team))
		race.setup(track, player_team, int(_resume.laps), roster.size(), roster)
		race.enable_rules()
		race.control.message.connect(_on_control_message)
		race.control.flag_changed.connect(_on_flag)
	elif sim and session == "race":
		var size: int = Game.field_size()
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
	if race.control:
		race.control.pit_call.connect(_on_pit_call)
		race.control.pit_report.connect(_on_pit_report)
	race.car_finished.connect(_on_finished)
	if mode == "online":
		net.attach(race)
	# Time of day for every race; weather for the full-rules races.
	# (Not online: every screen's rain would fall differently.)
	var weather_mode: int = int(Game.settings.get("weather", 0)) if (race.control and mode != "challenge" and mode != "online") else 0
	var w: Node = Weather.new()
	race.add_child(w)
	w.start(track, race, self, weather_mode)
	race.weather = w
	# The world around the race: crowd voices, crews and flagman, rain effects.
	soundscape.build_crowd(track)
	race_day = RaceDay.new()
	race.add_child(race_day)
	race_day.setup(race, soundscape, atmosphere)
	if rain_fx:
		rain_fx.clear()
	if race.weather and Game.modern:
		if rain_fx == null:
			rain_fx = RainFx.new()
			add_child(rain_fx)
		rain_fx.setup(track, race.weather, cam)


func _clear_screen() -> void:
	if screen:
		screen.queue_free()
	screen = Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(screen)
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
	showtime.reset()
	ghost.end()
	rival.end()
	if not _quick_saved.is_empty():
		for k in _quick_saved:
			Game.settings[k] = _quick_saved[k]
		_quick_saved.clear()
	_teardown_split()
	choosing_p2 = false
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
	_label("start", _press("START"), 30, Color.WHITE, Vector2(0, 300), HORIZONTAL_ALIGNMENT_CENTER, 7)
	_label("", "TILT OR DRAG TO STEER    GREEN GAS    RED BRAKE" if _touchy() else "ARROWS / WASD  STEER + GAS + BRAKE     C  CAMERA     ESC  PAUSE", 11, Color(0.85, 0.85, 0.85), Vector2(0, 420), HORIZONTAL_ALIGNMENT_CENTER, 3)
	_label("", "FREE PLAY", 16, Color(0.3, 1.0, 0.4), Vector2(0, 446), HORIZONTAL_ALIGNMENT_CENTER, 4)
	_label("gfx", _graphics_text(), 12, Color(0.5, 0.9, 1.0), Vector2(0, 400), HORIZONTAL_ALIGNMENT_CENTER, 3)
	_label("", "(C)1999  THUNDER ARCADE WORKS", 11, Color(0.8, 0.8, 0.8), Vector2(0, 462 - (6 if int(Game.settings.get("big_text", 0)) == 1 else 0)), HORIZONTAL_ALIGNMENT_CENTER, 3)
	showtime.start_intro()
	if not showtime.intro_active:
		showtime.music.play("menu")


## Quick Race: a short race at a random track, straight to the grid.
func _quick_race() -> void:
	mode = "race"
	session = "race"
	_quick_saved = {"length": Game.settings.length, "weekend": Game.settings.weekend}
	Game.settings.length = 1
	Game.settings.weekend = 0
	_use_track(randi() % Game.tracks.size())
	_enter_countdown()


func _start_mode(id: String) -> void:
	match id:
		"resume":
			resume_race()
		"quick":
			_quick_race()
		"arcade", "race":
			mode = id
			_enter_track_select()
		"season":
			mode = "season"
			if Game.season.is_empty():
				_enter_car_select()
			else:
				_enter_season_hub()
		"career":
			mode = "career"
			if Game.career.is_empty():
				_enter_car_select()
			else:
				_enter_career_hub()
		"2p":
			mode = "2p"
			choosing_p2 = false
			_enter_track_select()
		"challenges":
			_enter_challenges()
		"paint":
			_enter_paint_shop()
		"online":
			_enter_online()
		"editor":
			_enter_track_editor()
		"options":
			_enter_options()
		"boards":
			_enter_boards()


## The garage: your car in the showroom on the left, the modes as big tiles on
## the right (Quick Race across the top). Tap a tile, or move with the arrows.
var _tiles: Array = [] # [Rect2 in frame units, index]


func _enter_mode_select() -> void:
	_set_state(State.MODE_SELECT)
	synth.beep(1320.0, 0.08)
	_clear_screen()
	var modes: Array = _modes()
	mode_idx = clamp(mode_idx, 0, modes.size() - 1)
	# Your car on the turntable.
	if preview_car == null or not is_instance_valid(preview_car):
		preview_car = Car.new()
		add_child(preview_car)
		preview_car.setup(Game.teams[Game.selected_team] if Game.selected_team < Game.teams.size() else Game.teams[0], null)
		preview_car.position = showtime.showroom_spot()
		showtime.present_car(preview_car)
	var t: Dictionary = Game.teams[clamp(Game.selected_team, 0, Game.teams.size() - 1)]
	_label("", "SPEEDWAY THUNDER", 26, Color(1.0, 0.85, 0.1), Vector2(18, 14), HORIZONTAL_ALIGNMENT_LEFT, 7)
	_label("", "#%s  %s" % [t.num, t.driver], 16, Color.WHITE, Vector2(18, 348), HORIZONTAL_ALIGNMENT_LEFT, 5)
	_label("", "%s  -  %s" % [t.sponsor, CarBody.MAKES[CarBody.make_of(t)].name], 12, Color(1.0, 0.85, 0.3), Vector2(18, 370), HORIZONTAL_ALIGNMENT_LEFT, 4)
	# Your level and how far into it you are.
	var lp: Array = Game.level_progress(int(Game.progress.xp))
	_label("", "LEVEL %d" % Game.level(), 16, Color(0.5, 0.9, 1.0), Vector2(18, 392), HORIZONTAL_ALIGNMENT_LEFT, 5)
	_panel(Rect2(104, 398, 180, 10), Color(0, 0, 0, 0.6))
	_panel(Rect2(104, 398, 180.0 * float(lp[0]) / max(float(lp[1]), 1.0), 10), Color(0.3, 0.8, 1.0))
	_label("", "%d / %d XP" % [int(lp[0]), int(lp[1])], 10, Color(0.8, 0.85, 0.9), Vector2(104, 410), HORIZONTAL_ALIGNMENT_LEFT, 3)
	var streak := Game.streak_now()
	if streak > 0:
		_label("", "DAILY STREAK %d%s" % [streak, "  (DONE TODAY)" if Game.progress.get("streak_day", "") == Game.daily_key() else "  - KEEP IT GOING TODAY"], 10, Color(1.0, 0.7, 0.2), Vector2(18, 426), HORIZONTAL_ALIGNMENT_LEFT, 3)
	_tiles.clear()
	var x0 := 322.0
	var y := 18.0
	var w := 300.0
	for i in modes.size():
		var r: Rect2
		if i == 0:
			r = Rect2(x0, y, w, 62)
			y += 70.0
		else:
			var col := (i - 1) % 2
			r = Rect2(x0 + col * (w * 0.5 + 3.0), y, w * 0.5 - 3.0, 50)
			if col == 1 or i == modes.size() - 1:
				y += 56.0
		_tiles.append([r, i])
		var bg := Panel.new()
		bg.position = r.position
		bg.size = r.size
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.add_child(bg)
		menu_labels["tile%d" % i] = bg
		var l := Game.make_label(modes[i][0], 20 if i == 0 else 14, Color.WHITE, 5)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.position = r.position
		l.size = r.size
		screen.add_child(l)
		menu_labels["mode%d" % i] = l
	_label("mdesc", "", 12, Color(0.75, 0.88, 1.0), Vector2(0, 446), HORIZONTAL_ALIGNMENT_CENTER, 3)
	_refresh_mode_select()


func _refresh_mode_select() -> void:
	var modes: Array = _modes()
	for i in modes.size():
		var sel := i == mode_idx
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.85, 0.12, 0.1, 0.92) if i == 0 else Color(0.05, 0.07, 0.12, 0.82)
		if sel:
			sb.bg_color = sb.bg_color.lightened(0.15)
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(3 if sel else 1)
		sb.border_color = Color(1.0, 0.85, 0.1) if sel else Color(1, 1, 1, 0.18)
		(menu_labels["tile%d" % i] as Panel).add_theme_stylebox_override("panel", sb)
		(menu_labels["mode%d" % i] as Label).label_settings.font_color = Color(1.0, 0.9, 0.3) if sel else Color.WHITE
	menu_labels.mdesc.text = modes[mode_idx][1]


## A tap on the garage screen (frame units): pick that tile and go.
func _mode_tap(p: Vector2) -> bool:
	for t in _tiles:
		if (t[0] as Rect2).grow(3.0).has_point(p):
			mode_idx = t[1]
			_refresh_mode_select()
			synth.beep(1320.0, 0.06)
			_start_mode(String(_modes()[mode_idx][2]))
			return true
	return false


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
	_label("", "SWIPE OR TAP < >  TO BROWSE        GO  TO SELECT" if _touchy() else "<   LEFT / RIGHT   >        START  SELECT", 14, Color(0.85, 0.85, 0.85), Vector2(0, 414))
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
	_label("title", "SELECT CAR", 34, Color(1.0, 0.85, 0.1), Vector2(0, 14), HORIZONTAL_ALIGNMENT_CENTER, 8)
	_label("timer", "20", 30, Color(1, 0.3, 0.2), Vector2(560, 14), HORIZONTAL_ALIGNMENT_LEFT, 7)
	_panel(Rect2(40, 300, 560, 150), Color(0, 0, 0, 0.6))
	_label("num", "", 40, Color.WHITE, Vector2(60, 306), HORIZONTAL_ALIGNMENT_LEFT, 8)
	_label("driver", "", 22, Color.WHITE, Vector2(150, 308), HORIZONTAL_ALIGNMENT_LEFT, 6)
	_label("sponsor", "", 16, Color(1, 0.85, 0.3), Vector2(150, 336), HORIZONTAL_ALIGNMENT_LEFT, 5)
	_label("stats", "", 14, Color(0.5, 0.9, 1.0), Vector2(60, 364), HORIZONTAL_ALIGNMENT_LEFT, 4)
	_label("", "SWIPE OR TAP < >  FOR ANOTHER CAR        GO  TO RACE" if _touchy() else "<   LEFT / RIGHT   >        START  RACE!", 14, Color(0.85, 0.85, 0.85), Vector2(0, 430))
	_refresh_car_select()


func _refresh_car_select() -> void:
	var t: Dictionary = Game.teams[team2 if choosing_p2 else Game.selected_team]
	if menu_labels.has("title"):
		menu_labels.title.text = "PLAYER 2: SELECT CAR" if choosing_p2 else ("PLAYER 1: SELECT CAR" if mode == "2p" else "SELECT CAR")
	menu_labels.num.text = "#" + t.num
	menu_labels.num.label_settings.font_color = t.c1.lightened(0.2)
	menu_labels.driver.text = t.driver
	menu_labels.sponsor.text = "%s  -  %s" % [t.sponsor, CarBody.MAKES[CarBody.make_of(t)].name]
	var bar := func(v: float) -> String:
		var n := int(round(clamp((v - 0.94) / 0.12, 0.0, 1.0) * 10.0))
		return "|".repeat(n + 4) + ".".repeat(10 - n)
	menu_labels.stats.text = "TOP SPEED  %s\nACCEL      %s\nHANDLING   %s" % [bar.call(t.speed), bar.call(t.accel), bar.call(t.handling)]
	if preview_car:
		preview_car.queue_free()
	preview_car = Car.new()
	add_child(preview_car)
	preview_car.setup(t, null)
	preview_car.position = showtime.showroom_spot()
	showtime.present_car(preview_car)


func _enter_countdown() -> void:
	showtime.reset()
	showtime.music.stop()
	_set_state(State.COUNTDOWN)
	if tutorial and Tutorial.wanted(mode):
		tutorial.begin()
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
	_ckpt_lap = -1
	if not _resume.is_empty():
		_apply_resume()
		return
	var chase_self: bool = session in ["practice", "qualify"] or (mode == "challenge" and String(challenge.get("goal", "")) == "time")
	if race.player:
		ghost.begin(Game.selected_track, chase_self and split_cams.is_empty(), race.player.team)
	# Online: chase your fastest friend's best lap here (or the world record's).
	rival.end()
	_frame_ms = PackedFloat32Array()
	_script_ms = 0.0
	last_award = {}
	if chase_self and split_cams.is_empty() and cloud.enabled and race.player:
		var tidx: int = Game.selected_track
		var rteam: Dictionary = race.player.team
		cloud.rival_ghost(tidx, func(r: Dictionary):
			if r.has("samples") and Game.selected_track == tidx and state in [State.COUNTDOWN, State.RACE] and race and race.player:
				var t2: Dictionary = rteam.duplicate()
				t2["make"] = int(r.get("make", 0))
				rival.begin_samples(r.samples, t2, Color(1.0, 0.55, 0.1), "%s  %s" % [String(r.name), Game.format_time(float(r.lap_ms) / 1000.0)])
				_sub("CHASING %s's BEST LAP" % String(r.name), 3.0))
	# Arcade clock: generous first lap, then an extension each lap.
	var ref := 0.0
	var seg: float = track.length / track.n
	for i in track.n:
		ref += seg / min(track.speed_profile[i], 80.0)
	# (Real laps run ~25% over the ideal profile: traffic, tyre warm-up, bumps.)
	# Road courses run further over it (braking zones, traffic in the hairpins).
	var slack: float = 1.2 if track.cfg.get("road", false) else 1.0
	time_left = round(ref * 1.8 * slack + 25.0)
	lap_bonus = round(ref * 1.35 * slack)
	hud.race = race
	telemetry.car = race.player
	hud.track = track
	hud.time_left = time_left
	hud.show_timer = mode == "arcade"
	hud.control = race.control
	hud.visible = true
	_teardown_split()
	if mode == "2p":
		_build_split()
	hud.clear_messages()
	var intro: String = {"practice": "PRACTICE", "qualify": "QUALIFYING"}.get(session, "GET READY!") if mode != "arcade" else "GET READY!"
	if mode == "challenge":
		intro = challenge.name
		hud.show_timer = false
	_msg(intro, 2.0, Color(1, 0.9, 0.2))
	_sub((track.cfg.name if session != "practice" else ("PAUSE THEN QUIT TO END PRACTICE" if _touchy() else "ESC THEN Q TO END PRACTICE")) if mode != "challenge" else challenge.desc, 3.0)
	countdown_step = 0
	new_records.clear()
	game_over_reason = ""
	cam_pos = race.player.global_position + Vector3(0, 30, 0)


func _enter_results() -> void:
	_set_state(State.RESULTS)
	hud.visible = false
	_teardown_split()
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
	if not last_award.is_empty():
		var lp: Array = Game.level_progress(int(last_award.total))
		var txt := "+%d XP     LEVEL %d  (%d / %d)" % [int(last_award.xp), int(last_award.level), int(lp[0]), int(lp[1])]
		if last_award.levelled_up:
			txt = "LEVEL UP!  LEVEL %d     +%d XP" % [int(last_award.level), int(last_award.xp)]
		_label("", txt, 16, Color(1.0, 0.85, 0.2), Vector2(0, min(y2, 412)), HORIZONTAL_ALIGNMENT_CENTER, 5)
	_label("start", _press("CONTINUE"), 20, Color.WHITE, Vector2(0, 440), HORIZONTAL_ALIGNMENT_CENTER, 5)
	if race.rec_times.size() > 20:
		_label("", "R  REPLAY   H  HIGHLIGHTS", 12, Color(0.6, 0.9, 1.0), Vector2(420, 446), HORIZONTAL_ALIGNMENT_LEFT, 3)


# --- race events --------------------------------------------------------------

func _on_lap(car: Node3D, laps_done: int, lap_time: float) -> void:
	if car != race.player or state != State.RACE:
		return
	if Game.submit_record(Game.selected_track, "lap", lap_time):
		ghost.save_best()
		# Your best lap here, and its ghost, to the leaderboards.
		cloud.submit_lap(Game.selected_track, lap_time, CarBody.make_of(race.player.team), ghost._best)
		if not new_records.has("NEW LAP RECORD!"):
			new_records.append("NEW LAP RECORD!")
	if mode != "arcade" and session == "race" and race.control and laps_done % 5 == 0 and laps_done < race.laps:
		# Crew chief's report every five laps.
		var pos: int = race.position_of(car)
		var lead: Node3D = race.order[0]
		var gap: float = (lead.dist - car.dist) / max(car.v, 20.0)
		var fuel_laps: int = int(car.fuel / max(track.length / 1000.0 * 0.62 * car.burn_scale, 0.001))
		var tyre: String = "tires are good" if car.tyre_grip() > 0.95 else ("tires are going away" if car.tyre_grip() > 0.88 else "tires are gone")
		var where: String = "you're the leader" if pos == 1 else "P%d, %.1f back of the leader" % [pos, gap]
		_radio("%s. %s, fuel for %d laps." % [where, tyre, fuel_laps])
	if mode != "arcade":
		if session == "practice":
			_msg(Game.format_time(lap_time), 2.0, Color.WHITE)
			_sub("BEST " + Game.format_time(car.best_lap), 2.0)
		elif session == "qualify" and laps_done == 0:
			_msg("TIMED LAP", 1.5, Color(0.3, 1.0, 0.4))
		return
	if laps_done < race.laps:
		time_left += lap_bonus
		synth.beep(1568.0, 0.1)
		synth.beep(2093.0, 0.2)
		if laps_done == race.laps - 1:
			_msg("FINAL LAP!", 2.0, Color(1, 1, 1))
		else:
			_msg("EXTENDED TIME!", 2.0, Color(0.3, 1.0, 0.4))
		_sub("LAP %s    +%d SEC" % [Game.format_time(lap_time), int(lap_bonus)], 2.5)


func _on_finished(car: Node3D, place: int) -> void:
	if (car != race.player and car != race.player2) or state != State.RACE:
		return
	if tutorial:
		tutorial.finish()
	if session == "qualify":
		_finish_qualifying(car.best_lap)
		return
	if mode == "2p" and not (race.player.finished and race.player2.finished):
		car.ai = true # cool-down lap while the other player finishes
		_msg("%s FINISHES %s" % ["PLAYER 1" if car == race.player else "PLAYER 2", Game.ordinal(place)], 3.0)
		return
	if mode == "challenge":
		var ok := false
		match String(challenge.goal):
			"win": ok = place == 1
			"top3": ok = place <= 3
			"top5": ok = place <= 5
			"top10": ok = place <= 10
			"time": ok = car.best_lap > 0.0 and car.best_lap <= float(challenge.time)
		if challenge_idx < 0:
			cloud.submit_daily(place, race.time) # today's board, done or not
		if ok:
			var first := Game.complete_daily() if challenge_idx < 0 else Game.complete_challenge(challenge_idx)
			challenge_result = "CHALLENGE COMPLETE!" + ("   LEGEND UNLOCKED: #00 THUNDERBOLT" if first and Game.challenges_done.size() == 5 else "")
			if challenge_idx < 0:
				# The daily: keep the streak going.
				var st: Dictionary = Game.add_streak_day()
				if int(st.xp) > 0:
					challenge_result += "   %d-DAY STREAK! +%d XP" % [int(st.streak), int(st.xp)]
				if st.unlocked_scheme:
					challenge_result += "   CHECKERED SCHEME UNLOCKED"
				cloud.push_profile()
		else:
			challenge_result = "CHALLENGE FAILED"
		if challenge.goal == "time":
			challenge_result += "   LAP %s" % Game.format_time(car.best_lap)
	# XP for the race (not practice or qualifying), and how the game ran.
	if car == race.player:
		clear_checkpoint()
	if session == "race" and car == race.player and mode != "2p":
		last_award = Game.award_race(place, race.cars.size(), race.laps, car.total_damage() < 0.08)
		cloud.push_profile()
		_send_stats()
	_set_state(State.FINISHED)
	showtime.on_finished(car, place)
	if place == 1 and mode != "2p" and mode != "online" and game_over_reason == "":
		showtime.start_victory(car)
	hud.show_timer = false
	var col := Color(1, 0.9, 0.2) if place == 1 else Color.WHITE
	_msg("WINNER!" if place == 1 else "FINISH!", 4.0, col)
	_sub("YOU FINISHED %s" % Game.ordinal(place), 5.0)
	for i in 3:
		synth.beep(1046.0 + i * 262.0, 0.12)
	if Game.submit_record(Game.selected_track, "race", car.finish_time):
		new_records.append("NEW RACE RECORD!  %s" % Game.format_time(car.finish_time))


# --- main loop ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if editor and is_instance_valid(editor) and editor.visible and state == State.MENU:
		editor.handle(event)
		return
	if photo_mode and state != State.REPLAY:
		_photo_input(event)
		return
	if event.is_action_pressed("clip") and state == State.RACE and split_cams.is_empty():
		showtime.request_clip() # the last 15 seconds, as a video
		return
	if event.is_action_pressed("photo") and state in [State.RACE, State.FINISHED] and split_cams.is_empty():
		# Freeze the race and line up a shot.
		paused = true
		pause_layer.visible = false
		_photo_orbit = Vector3(0.6, 0.25, 9.0)
		_enter_photo()
		return
	if event.is_action_pressed("telemetry") and state in [State.RACE, State.COUNTDOWN, State.FINISHED]:
		telemetry.visible = not telemetry.visible
		telemetry.car = race.player
	if event.is_action_pressed("toggle_scanlines"):
		Game.scanlines = not Game.scanlines
		scan_rect.visible = Game.scanlines and not Game.modern
	if pit_menu and is_instance_valid(pit_menu):
		pit_menu.handle(event)
		return
	if state in [State.COUNTDOWN, State.RACE, State.FINISHED]:
		if event.is_action_pressed("pause"):
			if resume_t > 0.0:
				_cancel_resume() # paused again during the count
			elif paused and state == State.RACE and _count_back():
				_start_resume()
			else:
				paused = not paused
				pause_layer.visible = paused
				_bg_paused = false
		elif paused and event.is_action_pressed("quit_race"):
			clear_checkpoint() # quitting on purpose: nothing to come back to
			resume_t = 0.0
			_resume_label.visible = false
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
			cam_mode = (cam_mode + 1) % 4
	if paused:
		return
	match state:
		State.TITLE:
			if showtime.intro_active:
				if event.is_pressed():
					showtime.skip_intro()
				return
			if event.is_action_pressed("start"):
				_enter_mode_select()
		State.MODE_SELECT:
			var n_modes: int = _modes().size()
			if event.is_action_pressed("menu_up") or event.is_action_pressed("menu_down") or event.is_action_pressed("steer_left") or event.is_action_pressed("steer_right"):
				var step := 1 if (event.is_action_pressed("menu_down") or event.is_action_pressed("steer_right")) else -1
				mode_idx = posmod(mode_idx + step, n_modes)
				synth.beep(880.0, 0.05)
				_refresh_mode_select()
			elif event.is_action_pressed("start"):
				_start_mode(String(_modes()[mode_idx][2]))
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
				if choosing_p2:
					team2 = pick[posmod(max(pick.find(team2), 0) + dir, pick.size())]
					if team2 == Game.selected_team:
						team2 = pick[posmod(pick.find(team2) + dir, pick.size())]
				else:
					var cur: int = max(pick.find(Game.selected_team), 0)
					Game.selected_team = pick[posmod(cur + dir, pick.size())]
				synth.beep(880.0, 0.05)
				_refresh_car_select()
			elif event.is_action_pressed("start") and mode == "2p" and not choosing_p2:
				choosing_p2 = true
				var pick: Array = Game.selectable_teams()
				team2 = pick[(max(pick.find(Game.selected_team), 0) + 1) % pick.size()]
				_refresh_car_select()
			elif event.is_action_pressed("start"):
				match mode:
					"2p":
						Game.settings.weekend = 0
						_enter_race_setup()
					"arcade":
						_enter_countdown()
					"race":
						_enter_race_setup()
					"season":
						_enter_season_setup()
					"career":
						Game.new_career(Game.selected_team)
						_enter_career_hub()
			elif event.is_action_pressed("back") and choosing_p2:
				choosing_p2 = false
				_refresh_car_select()
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
			if photo_mode:
				_photo_input(event)
				return
			if event.is_action_pressed("photo"):
				_enter_photo()
				return
			if event.is_action_pressed("start") or event.is_action_pressed("back") or event.is_action_pressed("replay"):
				_hl_clips.clear()
				_hl_label = ""
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
				replay_cam = (replay_cam + 1) % 7
		State.RESULTS:
			if event.is_action_pressed("replay") and race.rec_times.size() > 20:
				_enter_replay()
			elif event.is_action_pressed("highlights") and race.rec_times.size() > 20:
				_enter_highlights()
			elif event.is_action_pressed("start") and state_time > 1.0:
				if (mode == "season" or mode == "career") and not Game.season.is_empty():
					_after_season_race()
				elif mode == "challenge":
					_enter_challenges()
				elif mode == "online" and net.connected:
					net.in_race = false
					_enter_lobby()
				else:
					_enter_title()


func _physics_process(delta: float) -> void:
	if paused:
		synth.engine_on = false
		synth.squeal = 0.0
		synth.pass_volume = 0.0
		return
	state_time += delta
	if net and net.in_race:
		net.tick(delta)
	if showtime.physics(delta):
		return # a replay holds the race
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
			if race.player:
				ghost.record(race.player, race.time, delta)
			if mode != "arcade":
				_check_player_out(delta)
				return
			time_left -= delta
			hud.time_left = time_left
			if time_left <= 0.0:
				time_left = 0.0
				game_over_reason = "TIME UP"
				_msg("TIME UP", 4.0, Color(1, 0.25, 0.2))
				_sub("GAME OVER", 4.0)
				synth.beep(220.0, 0.6, 0.4)
				race.player.ai = false
				_set_state(State.FINISHED)
		State.FINISHED:
			if showtime.victory_physics(delta):
				return
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
			if photo_mode:
				pass
			elif not _hl_clips.is_empty():
				_highlight_tick(delta)
			else:
				replay_t = clamp(replay_t + delta * replay_rate, race.rec_times[0], race.rec_times[race.rec_times.size() - 1])
			race.replay_apply(replay_t)
			_replay_overlay()


var _out_timer := 0.0


## Wrecked out or stopped with an empty tank: the player's race is over.
func _check_player_out(delta: float) -> void:
	var p: Node3D = race.player
	# Stranded on track or on the way to pit road (pit road itself is automatic).
	var dry: bool = p.fuel <= 0.0 and p.speed() < 1.0 and p.pit_state <= 1
	if p.out or dry:
		_out_timer += delta
		if _out_timer > 3.0:
			_out_timer = 0.0
			p.out = true
			game_over_reason = "OUT OF FUEL" if dry else "WRECKED  -  OUT OF THE RACE"
			if mode == "challenge":
				challenge_result = "CHALLENGE FAILED"
			_msg("OUT OF FUEL" if dry else "OUT OF THE RACE", 3.0, Color(1, 0.3, 0.2))
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
				_msg("3", 1.0, Color(1, 0.3, 0.2))
				synth.beep(660.0, 0.25)
			2:
				_msg("2", 1.0, Color(1, 0.8, 0.2))
				synth.beep(660.0, 0.25)
			3:
				_msg("1", 1.0, Color(1, 1, 0.3))
				synth.beep(660.0, 0.25)
			4:
				_msg("GREEN FLAG!", 1.6, Color(0.3, 1.0, 0.3))
				_sub("GO! GO! GO!", 1.6)
				synth.beep(1320.0, 0.6)
				race.go_green()
				_set_state(State.RACE)


func _player2_input() -> void:
	var p: Node3D = race.player2
	if p == null or p.finished:
		return
	var ctl: Node = race.control
	if Input.is_action_just_pressed("p2_pit"):
		p.want_pit = not p.want_pit
	var auto: bool = ctl.flag == ctl.Flag.YELLOW or p.pit_state != 0 or (p.want_pit and _near_pit_entry(p))
	p.ai = auto or autopilot
	if p.ai:
		return
	p.throttle = Input.get_action_strength("p2_accelerate")
	p.brake = Input.get_action_strength("p2_brake")
	_rumble(p, 1)
	p.steer_in = Input.get_action_strength("p2_right") - Input.get_action_strength("p2_left")


## Gamepad rumble: the front tyres scrubbing (light motor), bumps, locked brakes,
## wall hits and contact (heavy motor).
var _rumble_t := [0.0, 0.0]


var _buzz_cool := 0.0
var _buzz_gear := 0
var _buzz_hit := 0.0


## The phone buzzes: a pulse that scales with each hit (contact, walls, big
## bumps) and light ticks while a wheel is locked. Short and only on events,
## not a constant rumble, so it's felt without draining the battery.
func _phone_haptics(p: Node3D) -> void:
	if not Game.touch_active or int(Game.settings.get("haptics", 1)) == 0:
		return
	var dt := get_physics_process_delta_time()
	_buzz_cool -= dt
	var h := haptics(p, Time.get_ticks_msec() / 1000.0)
	var hit: float = h.hit
	if hit > 0.22 and hit > _buzz_hit + 0.15 and _buzz_cool <= 0.0:
		Input.vibrate_handheld(int(30 + 90 * hit), clamp(0.35 + hit * 0.65, 0.0, 1.0))
		_buzz_cool = 0.12
	elif p.locked_wheels != 0 and _buzz_cool <= 0.0 and p.speed() > 8.0:
		Input.vibrate_handheld(12, 0.3)
		_buzz_cool = 0.14
	elif p.gear != _buzz_gear and _buzz_gear > 0 and _buzz_cool <= 0.0:
		Input.vibrate_handheld(10, 0.45) # a click through the shifter
		_buzz_cool = 0.08
	elif p.on_grass and p.speed() > 12.0 and _buzz_cool <= 0.0:
		# Off the edge: a quick rhythm, faster with speed, like running over the
		# rumble strip and onto the grass.
		Input.vibrate_handheld(8, 0.35)
		_buzz_cool = clamp(3.0 / p.speed(), 0.05, 0.16)
	_buzz_gear = p.gear
	_buzz_hit = move_toward(_buzz_hit, hit, dt * 3.0) if hit < _buzz_hit else hit


func _rumble(p: Node3D, device: int) -> void:
	if device == 0:
		_phone_haptics(p)
	if Input.get_connected_joypads().find(device) < 0:
		return
	_rumble_t[device] -= get_physics_process_delta_time()
	if _rumble_t[device] > 0.0:
		return
	_rumble_t[device] = 1.0 / 30.0
	var h := haptics(p, Time.get_ticks_msec() / 1000.0)
	if h.weak > 0.02 or h.strong > 0.02:
		Input.start_joy_vibration(device, h.weak, h.strong, 0.06)


## What the car is doing, as feel: layers for the two rumble motors (the light,
## fast "weak" one and the heavy "strong" one), shared with the wheel's force
## feedback.
##   engine    a hum that rises with revs and buzzes on the limiter
##   grip      pulses that quicken as the tyres reach the limit and beyond
##   road      texture, seams and kerbs from the suspension
##   hits      thumps from contact and walls; a stutter from locked wheels
func haptics(p: Node3D, t: float) -> Dictionary:
	var rpm_f: float = clamp((p.rpm() - 2800.0) / (p.REDLINE - 2800.0), 0.0, 1.0)
	var engine: float = 0.05 + 0.1 * rpm_f + (0.25 if p.rpm() > p.REDLINE - 150.0 else 0.0)
	var limit: float = clamp(max(p.scrub, p.slide), 0.0, 1.5)
	var grip := 0.0
	if limit > 0.25:
		var hz: float = 6.0 + limit * 14.0
		grip = (0.35 + 0.4 * clamp(limit - 0.25, 0.0, 1.0)) * (1.0 if fmod(t * hz, 1.0) < 0.5 else 0.2)
	var rough := 0.0
	for i in 4:
		rough += abs(p._road_rate[i])
	var road: float = clamp(rough * 0.3, 0.0, 0.6)
	var lock: float = (0.45 if fmod(t * 18.0, 1.0) < 0.5 else 0.0) if p.locked_wheels != 0 else 0.0
	var hit: float = clamp(p.bump / 12.0 + p.wall_hit / 10.0 + (0.7 if p.tumbling else 0.0), 0.0, 1.0)
	return {
		"weak": clamp(engine + grip + road * 0.4, 0.0, 1.0),
		"strong": clamp(road + lock + hit, 0.0, 1.0),
		"hit": hit,
	}


func _player_input() -> void:
	if race.player2:
		_player2_input()
	var p: Node3D = race.player
	if autopilot:
		p.ai = true
		p.autopilot_forced = true
		return
	var ctl: Node = race.control
	if ctl:
		if Input.is_action_just_pressed("pit"):
			p.want_pit = not p.want_pit
			_sub("PIT THIS LAP: %s" % _plan_name(p.pit_plan) if p.want_pit else "PIT CANCELLED", 2.0)
		if Input.is_action_just_pressed("pit_option"):
			var cycle := {"4": "2", "2": "F", "F": "4"}
			if track.cfg.get("road", false) and race.weather and race.weather.mode > 0:
				cycle = {"4": "2", "2": "F", "F": "W", "W": "4"}
			p.pit_plan = cycle.get(p.pit_plan, "4")
			_sub("PIT PLAN: %s" % _plan_name(p.pit_plan), 2.0)
		if ctl.choosing and Input.is_action_just_pressed("steer_left"):
			ctl.player_lane_choice = 0
			_sub("RESTART: INSIDE LANE", 2.0)
		elif ctl.choosing and Input.is_action_just_pressed("steer_right"):
			ctl.player_lane_choice = 1
			_sub("RESTART: OUTSIDE LANE", 2.0)
		# The car drives itself under caution and on pit road (auto pit / auto caution).
		var auto: bool = ctl.flag == ctl.Flag.YELLOW or p.pit_state != 0 or (p.want_pit and _near_pit_entry(p))
		p.ai = auto
		if auto:
			return
	p.throttle = Input.get_action_strength("accelerate")
	p.brake = Input.get_action_strength("brake")
	_rumble(p, 0)
	p.steer_in = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	# A steering wheel (when set up) takes over steering and pedals.
	var wr: Dictionary = wheel.read()
	if not wr.is_empty():
		p.throttle = max(p.throttle, wr.throttle)
		p.brake = max(p.brake, wr.brake)
		p.steer_in = wr.steer
		wheel.update(p, get_physics_process_delta_time())
	# AUTO GAS: the car holds the speed it can take through the corner ahead (the
	# way the AI does, with a little margin); you steer. The brake pedal still
	# brakes, and the gas pedal can push harder.
	if int(Game.settings.get("auto_gas", 0)) == 1 and race and race.track:
		var look: float = max(p.v, 0.0) * 0.8 + 10.0
		var target: float = race.track.profile_at(p.s() + look) * 0.94 * sqrt(max(p.tyre_grip(), 0.3))
		target = min(target, race.track.profile_at(p.s()) * 0.96 * sqrt(max(p.tyre_grip(), 0.3)))
		var auto_thr: float = clamp((target - p.v) * 0.6 + 0.4, 0.0, 1.0)
		var auto_brk: float = clamp((p.v - target) * 0.25, 0.0, 1.0)
		if p.brake < 0.05:
			p.throttle = max(p.throttle, auto_thr)
			p.brake = auto_brk
		else:
			p.throttle = 0.0
	if Input.is_action_just_pressed("shift_up"):
		p.shift_request = 1
	elif Input.is_action_just_pressed("shift_down"):
		p.shift_request = -1


func _note_perf() -> void:
	var total := 0.0
	for f in _frame_ms:
		total += f
	# With the battery saver's 30 fps cap the frame time says nothing about
	# headroom; the script time still does.
	var frame: float = 16.7 if battery_saver_on else total / _frame_ms.size()
	Game.note_race_perf(race.cars.size(), _script_ms / _frame_ms.size(), frame)


## How the game ran this race (frame rate on this device), anonymously.
func _send_stats() -> void:
	if _frame_ms.size() < 60:
		return
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var total := 0.0
	for f in _frame_ms:
		total += f
	var avg_ms: float = total / _frame_ms.size()
	var p95: float = sorted[int(sorted.size() * 0.95)]
	var device := OS.get_name()
	if OS.has_feature("web"):
		device = "web-" + ("tablet" if Game.touch_device() and not OS.has_feature("web_android") and not OS.has_feature("web_ios") else ("android" if OS.has_feature("web_android") else ("ios" if OS.has_feature("web_ios") else "desktop")))
	var sz := get_window().size
	cloud.submit_session({"device": "%s %dx%d" % [device, sz.x, sz.y], "touch": Game.touch_active, "fps_avg": snappedf(1000.0 / max(avg_ms, 0.1), 0.1),
		"fps_p5": snappedf(1000.0 / max(p95, 0.1), 0.1), "cars": race.cars.size(), "quality": Game.quality_level(), "secs": int(total / 1000.0), "mode": mode})


# --- touch: menus are touched directly --------------------------------------

func _touchy() -> bool:
	return Game.touch_active or Game.touch_device()


## "PRESS START" with keys and pads, "TAP TO START" / "TAP TO CONTINUE" on a phone.
func _press(what: String) -> String:
	if _touchy():
		return "TAP TO " + what
	return "PRESS START"

var _drag_acc := 0.0


## A tap at `pos` (screen) on a menu screen. Returns true if something took it.
func ui_tap(pos: Vector2) -> bool:
	var p: Vector2 = ui_root.get_global_transform_with_canvas().affine_inverse() * pos
	if pit_menu and is_instance_valid(pit_menu):
		return pit_menu.tap(p)
	match state:
		State.TITLE:
			if showtime.intro_active:
				showtime.skip_intro()
			else:
				_enter_mode_select()
			return true
		State.MODE_SELECT:
			return _mode_tap(p)
		State.MENU:
			return menu != null and menu.tap(p)
	return false


## A tap that hit nothing: on screens that are waiting for you to carry on
## (results, standings, replays), that's "continue".
func ui_continue() -> void:
	if state in [State.RESULTS, State.SESSION_RESULTS, State.STANDINGS, State.REPLAY]:
		var ev := InputEventAction.new()
		ev.action = "start"
		ev.pressed = true
		Input.parse_input_event(ev)
		var up := InputEventAction.new()
		up.action = "start"
		up.pressed = false
		Input.parse_input_event.call_deferred(up)


## A finger dragging up or down by `dy` screen pixels: scrolls a long list.
func ui_drag(dy: float, _pos: Vector2) -> void:
	var m: Control = pit_menu if pit_menu and is_instance_valid(pit_menu) else (menu if state == State.MENU else null)
	if m == null:
		return
	var sc: float = ui_root.get_global_transform_with_canvas().get_scale().y
	_drag_acc += dy / max(sc, 0.01)
	if abs(_drag_acc) >= 54.0:
		m.drag(_drag_acc)
		_drag_acc = 0.0


## Quick caution: the race waits while the player makes the pit call.
func _on_pit_call(info: Dictionary) -> void:
	_pit_info = info
	if pit_menu and is_instance_valid(pit_menu):
		pit_menu.queue_free()
	# Online the race can't stop for one player: the car circulates on its own
	# under caution while you choose.
	paused = mode != "online"
	pause_layer.visible = false
	hud.visible = false # the pit call screen has the running order and laps to go
	synth.beep(660.0, 0.2)
	var options: Array = info.options
	var names: Array = []
	for i in options.size():
		names.append(String(info.names[i]) + ("  *" if options[i] == info.advice else ""))
	pit_menu = Menu.new()
	pit_menu.top = 250
	pit_menu.width = 540
	ui_root.add_child(pit_menu)
	pit_menu.build("CAUTION - %s" % String(info.reason), [
		{"id": "plan", "label": "PIT CALL", "values": names, "index": max(options.find(info.advice), 0)},
		{"id": "chassis", "label": "CHASSIS", "values": ["NO CHANGE", "TIGHTEN (ROUND OF WEDGE IN)", "LOOSEN (ROUND OF WEDGE OUT)"], "index": 0,
			"hint": "TIGHT: THE FRONT PUSHES UP THE TRACK.  LOOSE: THE REAR WANTS TO COME AROUND"},
		{"id": "go", "label": "CONFIRM", "hint": "START TO SEND IT"},
	])
	var lines := [
		"RUNNING %s OF %d  -  %d LAPS TO GO" % [Game.ordinal(int(info.position)), int(info.field), int(info.laps_left)],
		"TIRES %d%% WORN (GRIP %d%%)   FUEL %d LAPS   DAMAGE %s" % [int(round(float(info.wear) * 100.0)), int(round(float(info.grip) * 100.0)), int(info.fuel_laps), "NONE" if float(info.damage) < 0.02 else ("LIGHT" if float(info.damage) < 0.1 else "HEAVY")],
		"CREW CHIEF: %s" % String(info.names[max(options.find(info.advice), 0)]),
	]
	for i in lines.size():
		var l := Game.make_label(lines[i], 18 if i < 2 else 16, Color.WHITE if i < 2 else Color(1.0, 0.85, 0.2), 5)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(640, 24)
		l.position = Vector2(0, 90 + i * 30)
		pit_menu.add_child(l)
	_pit_hint()
	pit_menu.changed.connect(func(_id, _i): _pit_hint())
	pit_menu.activated.connect(func(_id): _close_pit_menu())


## The pit call row's hint: where that choice would put you for the restart.
func _pit_hint() -> void:
	var options: Array = _pit_info.options
	var o: String = options[pit_menu.value("plan")]
	var est: int = int(_pit_info.estimate.get(o, 0))
	var now: int = int(_pit_info.position)
	var diff := now - est
	pit_menu.rows[0].hint = "RESTART ABOUT %s %s    * = CREW CHIEF'S CALL" % [Game.ordinal(est), ("(+%d)" % diff) if diff > 0 else (("(%d)" % diff) if diff < 0 else "(SAME)")]
	pit_menu._refresh()


func _close_pit_menu() -> void:
	if pit_menu == null or not is_instance_valid(pit_menu):
		return
	var call: String = _pit_info.options[pit_menu.value("plan")]
	var wedge: float = [0.0, 120.0, -120.0][pit_menu.value("chassis")]
	pit_menu.queue_free()
	pit_menu = null
	paused = false
	hud.visible = true
	synth.beep(1320.0, 0.08)
	if race and race.control:
		race.control.resolve_player(call, wedge)


## After the stops: who pitted and where you'll restart, for a few seconds.
func _on_pit_report(lines: Array) -> void:
	if _pit_board and is_instance_valid(_pit_board):
		_pit_board.queue_free()
	_pit_board = Game.make_label("\n".join(lines), 16, Color.WHITE, 5)
	_pit_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pit_board.size = Vector2(640, 90)
	_pit_board.position = Vector2(0, 76) # under the flag banner, clear of the messages below
	ui_root.add_child(_pit_board)
	var t := get_tree().create_timer(5.0)
	var board := _pit_board
	t.timeout.connect(func():
		if is_instance_valid(board):
			board.queue_free())


func _plan_name(plan: String) -> String:
	return {"4": "4 TIRES + FUEL", "2": "2 TIRES + FUEL", "F": "FUEL ONLY", "W": "WET TIRES + FUEL"}.get(plan, plan)


func _near_pit_entry(p: Node3D) -> bool:
	var to_entry: float = fposmod(track.pit_in_s() - p.s(), track.length)
	return to_entry < 500.0


## Radio: the crew chief speaks his calls (the OS / browser voice). The spotter
## and the TV booth are on screen only.
var telemetry: Control
var _voices: PackedStringArray = []


func _radio(text: String) -> void:
	if not Game.radio_voice or state == State.REPLAY:
		return
	if _voices.is_empty():
		_voices = DisplayServer.tts_get_voices_for_language("en")
		if _voices.is_empty():
			return
	DisplayServer.tts_speak(text.to_lower(), _voices[min(1, _voices.size() - 1)], 70, 0.9, 1.1, 0, false)


func _on_control_message(text: String, kind: String) -> void:
	match kind:
		"pit", "flag", "stage":
			_radio(text)
	match kind:
		"flag":
			_msg(text, 2.5, Color(1, 0.9, 0.2) if text.begins_with("CAUTION") or text == "ONE TO GO" else (Color(0.3, 1.0, 0.3) if text.begins_with("GREEN") else Color.WHITE))
			if text == "ONE TO GO":
				_sub("CHOOSE YOUR LANE:  LEFT = INSIDE   RIGHT = OUTSIDE", 6.0)
		"stage":
			_msg(text, 3.0, Color(0.4, 0.9, 1.0))
		"pit":
			_sub(text, 3.0)
		"spotter":
			hud.spotter(text)
		_:
			_sub(text, 3.0)


func _on_flag(flag: String) -> void:
	showtime.on_flag(flag)
	match flag:
		"YELLOW":
			synth.beep(440.0, 0.4)
		"GREEN":
			synth.beep(1320.0, 0.5)
		"WHITE":
			synth.beep(990.0, 0.3)


## Phones: the race stops when the app goes to the background (a call, a
## notification, another app) and the sound goes quiet; coming back shows the
## pause screen, and RESUME counts 3-2-1 back in.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			AudioServer.set_bus_mute(0, true)
			auto_pause()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			AudioServer.set_bus_mute(0, false)


## Pauses a race in progress (not online: the others race on), e.g. when the
## app is backgrounded. Returns whether it paused.
func auto_pause() -> bool:
	if race == null or state not in [State.COUNTDOWN, State.RACE] or paused or mode == "online" \
			or photo_mode or (pit_menu and is_instance_valid(pit_menu)):
		return false
	if resume_t > 0.0:
		_cancel_resume()
		return true
	paused = true
	pause_layer.visible = true
	_bg_paused = true
	return true


## After a pause mid-race, a count back in, so you're not thrown straight into
## a corner: always after the app was away, and on touch screens.
func _count_back() -> bool:
	return _bg_paused or _touchy()


func _start_resume() -> void:
	resume_t = 3.0
	pause_layer.visible = false
	_bg_paused = false


func _cancel_resume() -> void:
	resume_t = 0.0
	_resume_label.visible = false
	pause_layer.visible = true


func _update_resume(delta: float) -> void:
	if resume_t <= 0.0:
		return
	if not paused or state != State.RACE:
		resume_t = 0.0
		_resume_label.visible = false
		return
	var before := ceili(resume_t)
	resume_t -= delta
	if resume_t <= 0.0:
		resume_t = 0.0
		_resume_label.visible = false
		paused = false
		synth.beep(1320.0, 0.15)
		return
	_resume_label.visible = true
	_resume_label.text = str(ceili(resume_t))
	_resume_label.scale = Vector2.ONE
	if ceili(resume_t) != before:
		synth.beep(880.0, 0.08)


func _update_battery(delta: float) -> void:
	_battery_t -= delta
	if _battery_t > 0.0:
		return
	_battery_t = 10.0
	var on := Game.battery_saving()
	if on != battery_saver_on:
		battery_saver_on = on
		Engine.max_fps = 30 if on else 0


# --- your account: the saved game online, and moving to a new phone ----------

func _enter_account() -> void:
	var cl: bool = cloud.enabled
	var code_line: String = "FRIEND CODE  " + (cloud.friend_code if cloud.registered() else "(NOT ONLINE YET)")
	var sync_line: String = "SAVED ONLINE  " + (cloud.last_sync.substr(0, 16).replace("T", " ") if cloud.last_sync != "" else "NOT YET")
	var rows := [
		{"id": "info", "label": code_line, "hint": "FRIENDS ADD YOU WITH THIS CODE"},
		{"id": "save_now", "label": sync_line, "hint": "TAP TO SAVE NOW (IT ALSO SAVES BY ITSELF AFTER EACH RACE)"},
		{"id": "give_code", "label": "MOVE TO A NEW PHONE", "hint": "GET A CODE HERE, THEN TYPE IT ON THE NEW PHONE (IT WORKS FOR 24 HOURS)"},
		{"id": "take_code", "label": "I HAVE A CODE FROM MY OLD PHONE", "hint": "BRINGS YOUR ACCOUNT AND SAVED GAME TO THIS PHONE"},
		{"id": "back", "label": "DONE"},
	]
	if not cl:
		rows[1].hint = "OFFLINE: CLOUD SAVE NEEDS AN INTERNET CONNECTION"
	_open_menu("account", "ACCOUNT", rows, rows.size() - 1)
	if _account_note != "":
		_sub(_account_note, 4.0)
		_account_note = ""


func _account_action(id: String) -> void:
	match id:
		"save_now":
			_sub("SAVING...", 1.5)
			cloud.push_save(func(ok: bool):
				_sub("SAVED ONLINE" if ok else "COULDN'T REACH THE SERVER", 2.5)
				if menu_kind == "account":
					_enter_account())
		"give_code":
			_sub("GETTING A CODE...", 2.0)
			cloud.transfer_code(func(ok: bool, text: String):
				if ok:
					_account_note = "YOUR CODE: %s   TYPE IT ON THE NEW PHONE WITHIN 24 HOURS" % text
					transfer_code_shown = text
				else:
					_account_note = text
				if menu_kind == "account":
					_enter_account())
		"take_code":
			_ask_code()
		"back":
			if _code_edit:
				_code_edit.visible = false
			_enter_options()


var transfer_code_shown := ""


func _ask_code() -> void:
	if _code_edit == null:
		_code_edit = LineEdit.new()
		_code_edit.position = Vector2(170, 380)
		_code_edit.size = Vector2(300, 44)
		_code_edit.add_theme_font_size_override("font_size", 24)
		_code_edit.max_length = 8
		_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_code_edit.placeholder_text = "8-LETTER CODE"
		_code_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
		_code_edit.text_submitted.connect(_claim_code)
		_code_edit.text_changed.connect(func(t: String):
			var up := t.to_upper()
			if up != t:
				_code_edit.text = up
				_code_edit.caret_column = up.length()
			if up.length() == 8:
				_claim_code(up))
		ui_root.add_child(_code_edit)
	_code_edit.text = ""
	_code_edit.visible = true
	_code_edit.grab_focus()


func _claim_code(code: String) -> void:
	if _code_edit:
		_code_edit.visible = false
	_sub("CHECKING THE CODE...", 2.0)
	cloud.claim(code, func(ok: bool, text: String):
		_account_note = text if ok else text
		if ok:
			synth.beep(1760.0, 0.2)
		if menu_kind == "account":
			_enter_account())


# --- carrying on an interrupted race ----------------------------------------
# Every lap you complete under green in a full race (Single Race, Season,
# Career) is saved: where every car is on the track, its speed, fuel, tyres,
# damage and laps, and the race's time, cautions and stage. If the app is
# closed or killed, the garage offers RESUME RACE, which rebuilds the race and
# puts everyone back, then counts 3-2-1.

func _checkpoint_ok() -> bool:
	return race != null and race.control != null and race.player != null and session == "race" \
		and mode in ["race", "season", "career"] and split_cams.is_empty() and not race.arcade


func _maybe_checkpoint() -> void:
	if state != State.RACE or paused or not _checkpoint_ok():
		return
	var p: Node3D = race.player
	if p.lap_idx == _ckpt_lap or p.finished or p.out or p.pit_state != 0 or race.control.flag != race.control.Flag.GREEN:
		return
	_ckpt_lap = p.lap_idx
	if p.lap_idx >= 1:
		save_checkpoint()


func save_checkpoint() -> void:
	var cars: Array = []
	for c in race.cars:
		cars.append({"team": int(c.get_meta("team_idx", -1)), "dist": c.dist, "d": c.d, "v": c.v, "fuel": c.fuel,
			"wear": c.tyre_wear, "damage": c.damage.duplicate(), "out": c.out, "why": c.out_reason,
			"best": c.best_lap, "last": c.last_lap, "lap_start": c.lap_start_time, "led": c.laps_led,
			"stage_pts": c.stage_points, "player": c == race.player})
	var ctl: Node = race.control
	var data := {"mode": mode, "track": Game.selected_track, "team": Game.selected_team, "laps": race.laps,
		"lap": mini(race.player.lap() + 1, race.laps), "place": race.order.find(race.player) + 1,
		"time": race.time, "cautions": ctl.caution_count, "stage": ctl.stage, "stage_results": ctl.stage_results,
		"cars": cars, "saved": Time.get_unix_time_from_system()}
	if race.weather:
		data.weather = {"hour": race.weather.hour, "rain": race.weather.rain, "target": race.weather._rain_target, "wet": race.weather.wet}
	var cf := ConfigFile.new()
	cf.set_value("race", "data", data)
	cf.save(RESUME_PATH)


func clear_checkpoint() -> void:
	if FileAccess.file_exists(RESUME_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RESUME_PATH))


## The saved race, if there is one: {lap, laps, track_name, place, data}.
func resume_info() -> Dictionary:
	if not FileAccess.file_exists(RESUME_PATH):
		return {}
	var cf := ConfigFile.new()
	if cf.load(RESUME_PATH) != OK:
		return {}
	var d = cf.get_value("race", "data", {})
	if not (d is Dictionary) or not d.has("cars") or int(d.get("track", -1)) < 0 or int(d.track) >= Game.tracks.size():
		return {}
	return {"lap": int(d.get("lap", 1)), "laps": int(d.laps), "track_name": String(Game.tracks[int(d.track)].get("name", "")), "place": int(d.get("place", 1)), "data": d}


func resume_race() -> void:
	var info := resume_info()
	if info.is_empty():
		_enter_mode_select()
		return
	var d: Dictionary = info.data
	mode = String(d.mode)
	session = "race"
	Game.selected_team = int(d.team)
	_use_track(int(d.track))
	_resume = d
	_enter_countdown()


## After the race is rebuilt from a checkpoint: everyone back where they were,
## then 3-2-1 and go.
func _apply_resume() -> void:
	var d: Dictionary = _resume
	_resume = {}
	race.time = float(d.time)
	for i in min(race.cars.size(), d.cars.size()):
		var c: Node3D = race.cars[i]
		var s: Dictionary = d.cars[i]
		c.pace_mode = false
		c.dist = float(s.dist)
		c.d = float(s.d)
		c.ai_lane = c.d
		c.v = float(s.v)
		c.yaw = 0.0
		c.fuel = float(s.fuel)
		c.tyre_wear = float(s.wear)
		for k in s.damage:
			c.damage[k] = float(s.damage[k])
		c._update_damage_visual()
		c.out = bool(s.out)
		c.out_reason = String(s.why)
		c.best_lap = float(s.best)
		c.last_lap = float(s.last)
		c.lap_start_time = float(s.lap_start)
		c.laps_led = int(s.led)
		c.stage_points = int(s.stage_pts)
		c.lap_idx = c.lap()
		c.sync_visual()
	var ctl: Node = race.control
	ctl.caution_count = int(d.cautions)
	ctl.stage = int(d.stage)
	ctl.stage_results = d.stage_results
	if race.weather and d.has("weather"):
		race.weather.hour = float(d.weather.hour)
		race.weather.rain = float(d.weather.rain)
		race.weather._rain_target = float(d.weather.target)
		race.weather.wet = d.weather.wet
		race.weather.apply()
	race._update_order()
	race.go_green()
	_ckpt_lap = race.player.lap_idx if race.player else -1
	_set_state(State.RACE)
	paused = true
	_start_resume()


func _process(delta: float) -> void:
	_update_resume(delta)
	_maybe_checkpoint()
	_update_battery(delta)
	if wheel and wheel.poll_detect() and state == State.MENU and menu_kind == "wheel":
		_enter_wheel_setup()
	if showtime:
		showtime.process(delta)
		if tutorial and tutorial.active:
			if state in [State.COUNTDOWN, State.RACE]:
				tutorial.update(delta)
			elif state in [State.TITLE, State.MODE_SELECT, State.MENU]:
				tutorial.visible = false
				tutorial.active = false
	if ghost and ghost.active and race and race.player and state in [State.COUNTDOWN, State.RACE]:
		ghost.update(track, race.player, race.time)
	if rival and rival.active and race and race.player and state in [State.COUNTDOWN, State.RACE]:
		rival.update(track, race.player, race.time)
	if state == State.RACE and not paused:
		_frame_ms.append(delta * 1000.0)
		_script_ms += frame_timer.busy_ms
		if _frame_ms.size() == 1200 and race: # 20 s of racing: enough to size AUTO fields
			_note_perf()
	if race == null:
		return
	race.interpolate(Engine.get_physics_interpolation_fraction() if Game.smoothing else 1.0)
	_update_camera(delta)
	_fit_camera_aspect()
	_update_motion_blur()
	if race_day and is_instance_valid(race_day):
		race_day.update(delta)
	if rain_fx and race.weather:
		var view := ""
		if state in [State.COUNTDOWN, State.RACE, State.FINISHED] and not photo_mode and split_cams.is_empty():
			view = "cockpit" if cam_mode == 3 else ("bumper" if cam_mode == 2 else "chase")
		var rf: Node3D = race.player if state != State.REPLAY else tv_target
		rain_fx.update(delta, race, cam, view, rf if rf and is_instance_valid(rf) else null)
	if atmosphere:
		var racing: bool = state in [State.COUNTDOWN, State.RACE, State.FINISHED, State.REPLAY] and not photo_mode and split_cams.is_empty()
		var fc: Node3D = race.player if race and state != State.REPLAY else tv_target
		atmosphere.update(delta, fc.speed() if fc and is_instance_valid(fc) else 0.0, cockpit != null and is_instance_valid(cockpit) and cockpit.visible, racing)
	_auto_quality(delta)
	if OS.has_feature("web") and Game.modern:
		_dynamic_resolution(delta)
		if get_window().size != _web_px:
			_fit_web_resolution(true)
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
	if showtime.engine_blip():
		return # the showroom car revving
	var focus: Node3D = null
	if state in [State.COUNTDOWN, State.RACE, State.FINISHED] and race.player:
		focus = race.player
		synth.master = 0.8
		soundscape.level_db = 0.0
	else:
		focus = tv_target
		synth.master = 0.35
		soundscape.level_db = -9.0
	if focus == null or not is_instance_valid(focus):
		synth.engine_on = false
		synth.wind = 0.0
		soundscape.update(null, cam, null, false, get_process_delta_time())
		return
	var inside: bool = cockpit != null and is_instance_valid(cockpit) and cockpit.visible
	soundscape.update(race, cam, focus, inside, get_process_delta_time())
	var spd_f: float = clamp(focus.speed() / 95.0, 0.0, 1.2)
	synth.wind = spd_f * spd_f * (0.35 if inside else 0.8)
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
	synth.pass_volume = 0.0 # other cars are placed in 3D by the soundscape


## A screen taller than it is wide (a tablet held upright): the camera keeps its
## width of view instead of its height, so the road isn't seen through a slot.
func _fit_camera_aspect() -> void:
	var c := get_viewport().get_camera_3d()
	if c == null:
		return
	var vs := get_viewport().get_visible_rect().size
	c.keep_aspect = Camera3D.KEEP_WIDTH if vs.y > vs.x else Camera3D.KEEP_HEIGHT


func _update_camera(delta: float) -> void:
	if not (state in [State.COUNTDOWN, State.RACE, State.FINISHED] and cam_mode == 3 and not photo_mode):
		_hide_cockpit()
	if showtime.camera(delta):
		return
	shake = max(shake - delta * 2.5, 0.0)
	var sh := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), 0) * shake * 0.25
	match state:
		State.COUNTDOWN, State.RACE, State.FINISHED:
			if photo_mode:
				_photo_camera(delta)
				return
			_chase_camera(race.player, delta, cam_mode)
			cam.fov += showtime.fov_offset
			sh = Vector3.ZERO # the chase and in-car cameras shake through the camera feel
			if split_cams.size() == 2:
				_split_camera(split_cams[0], split_state[0], race.player, delta)
				_split_camera(split_cams[1], split_state[1], race.player2, delta)
		State.REPLAY:
			if photo_mode:
				_photo_camera(delta)
				return
			if replay_cam == 0:
				_director(delta)
			var focus: Node3D = race.cars[replay_focus]
			var shot: int = _dir_shot if replay_cam == 0 else replay_cam
			match shot:
				1:
					_chase_camera(focus, delta, 0)
				2:
					_chase_camera(focus, delta, 2)
				3:
					tv_target = focus
					tv_mode = 3
					_tv_camera(delta, true)
				4:
					_roof_camera(focus)
				5:
					_blimp_camera(focus, delta)
				_:
					tv_target = focus
					tv_mode = 2
					_tv_camera(delta, true)
		State.CAR_SELECT, State.MENU, State.MODE_SELECT:
			if preview_car and (state == State.CAR_SELECT or state == State.MODE_SELECT or menu_kind == "paint"):
				# The turntable slows as the car comes round to a front three-quarter
				# view (its best side), and speeds up through the rest.
				var best := 0.6 + PI - 0.55
				var off := wrapf(orbit - best, -PI, PI)
				orbit += delta * (0.12 + 0.55 * (1.0 - cos(off)) * 0.5)
				preview_car.rotation.y = orbit
				var p := preview_car.global_position
				cam.fov = 42.0
				var eye := p + Vector3(sin(0.6) * 9.0, 1.35, cos(0.6) * 9.0)
				cam.global_position = eye
				var side := (p - eye).cross(Vector3.UP).normalized()
				# In the paint shop, frame the car on the right, clear of the menu.
				# In the garage, on the left, clear of the tiles.
				var shift := -side * 1.9 if state == State.MENU else (side * 3.4 if state == State.MODE_SELECT else Vector3.ZERO)
				cam.look_at(p + Vector3(0, -0.9, 0) + shift, Vector3.UP)
			else:
				_tv_camera(delta)
		_:
			_tv_camera(delta)
	cam.global_position += cam.global_transform.basis * sh


## Cockpit view: the camera is the driver's head, inside the car's sprung body,
## pushed around by the g-forces and looking a little into the corner.
func _cockpit_camera(car: Node3D, delta: float, spd: float) -> void:
	if cockpit == null or not is_instance_valid(cockpit) or cockpit.car != car:
		if cockpit and is_instance_valid(cockpit):
			cockpit.queue_free()
		cockpit = Cockpit.new()
		car.model.add_child(cockpit)
		cockpit.build(car, Game.modern and Game.quality_level() >= 1)
	cockpit.show_inside(true)
	cockpit.update(delta)
	var look := Basis(Vector3.UP, -car.steer * 0.35)
	cam.global_transform = cockpit.eye_transform() * Transform3D(look, Vector3.ZERO) * feel.update(car, delta, 0.35, 1.8)
	cam.fov = 66.0 + spd * 6.0
	cam.near = 0.03
	cam_pos = cam.global_position


func _hide_cockpit() -> void:
	if cockpit and is_instance_valid(cockpit) and cockpit.visible:
		cockpit.show_inside(false)
		cam.near = 0.3


func _chase_camera(car: Node3D, delta: float, mode: int) -> void:
	var tr: Transform3D = car.global_transform
	var back := tr.basis.z
	var up := tr.basis.y
	var spd: float = clamp(abs(car.v) / 85.0, 0.0, 1.2)
	if mode == 2:
		cam.global_transform = tr * Transform3D(Basis(), Vector3(0, 1.05, -2.3)) * feel.update(car, delta, 0.6)
		cam.fov = 70.0 + spd * 10.0
		cam_pos = cam.global_position
		return
	if mode == 3:
		_cockpit_camera(car, delta, spd)
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
	# The chase camera is on a long arm: it feels the car, but softly.
	cam.global_transform = cam.global_transform * feel.update(car, delta, 0.45, 0.35)


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
		{"id": "field", "label": "FIELD SIZE", "values": ["AUTO  %d CARS" % Game.field_size() if int(Game.settings.field) < 0 else "AUTO"] + Game.FIELDS.map(func(f): return "%d CARS" % f), "index": int(Game.settings.field) + 1, "hint": "AUTO: AS MANY AS THIS DEVICE RUNS SMOOTHLY"},
		{"id": "weekend", "label": "WEEKEND", "values": Game.WEEKENDS, "index": Game.settings.weekend, "hint": "QUALIFY TO SET YOUR STARTING SPOT"},
		{"id": "catchup", "label": "CATCH-UP", "values": ["OFF", "ON"], "index": int(Game.settings.get("catchup", 0)), "hint": "ON: THE FIELD STAYS CLOSE TO YOU, AHEAD OR BEHIND"},
		{"id": "cautions", "label": "CAUTIONS", "values": ["OFF", "QUICK", "FULL"], "index": Game.settings.cautions, "hint": "QUICK: ABOUT 15 S FROM YELLOW TO GREEN. FULL: REAL CAUTION LAPS BEHIND THE PACE CAR"},
		{"id": "weather", "label": "WEATHER", "values": ["CLEAR", "CHANGEABLE", "RAIN"], "index": int(Game.settings.get("weather", 0)), "hint": "RAIN HOLDS OVALS UNDER CAUTION.  ROAD COURSES RACE ON WET TIRES"},
		{"id": "damage", "label": "DAMAGE", "values": ["OFF", "ON"], "index": Game.settings.damage, "hint": "DAMAGE HURTS SPEED, HANDLING AND CAN END YOUR RACE"},
		{"id": "wear", "label": "FUEL + TIRE WEAR", "values": ["OFF", "ON"], "index": Game.settings.wear, "hint": "SCALED TO RACE LENGTH SO PIT STRATEGY MATTERS"},
		{"id": "assists", "label": "DRIVING ASSISTS", "values": ["OFF", "MILD", "FULL"], "index": Game.settings.assists, "hint": "MILD: STEERING HELP ONLY, LOOSER TRACTION AND ABS.  OFF: ALL YOU"},
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
	var st: Dictionary = Game.setup
	var bal := ["TIGHT 3", "TIGHT 2", "TIGHT 1", "NEUTRAL", "LOOSE 1", "LOOSE 2", "LOOSE 3"]
	var three := ["SOFT", "STANDARD", "STIFF"]
	var psi := ["LOW", "STANDARD", "HIGH"]
	var rows := [
		{"id": "balance", "label": "WEDGE", "values": bal, "index": int(st.balance) + 3, "hint": "CROSS WEIGHT: TIGHT PUSHES UP THE TRACK, LOOSE TURNS BUT CAN SPIN"},
		{"id": "springs_f", "label": "FRONT SPRINGS", "values": three, "index": int(st.springs_f), "hint": "SOFT: MORE GRIP OVER BUMPS.  STIFF: STEADIER, SITS HIGHER"},
		{"id": "springs_r", "label": "REAR SPRINGS", "values": three, "index": int(st.springs_r), "hint": "STIFFER REAR = LOOSER"},
		{"id": "bar_f", "label": "FRONT SWAY BAR", "values": three, "index": int(st.bar_f), "hint": "STIFFER BAR = LESS ROLL, TIGHTER IN THE MIDDLE OF THE CORNER"},
		{"id": "bump", "label": "BUMP STOPS", "values": ["LOW", "STANDARD", "HIGH"], "index": int(st.bump), "hint": "WHEN THE CAR LANDS ON ITS STOPS IN THE BANKING"},
		{"id": "stagger", "label": "STAGGER", "values": ["LESS", "STANDARD", "MORE"], "index": int(st.stagger), "hint": "MORE STAGGER HELPS IT TURN LEFT (LOOSER ON EXIT)"},
		{"id": "psi_l", "label": "LEFT PRESSURES", "values": psi, "index": int(st.psi_l), "hint": "LOW: MORE GRIP, FASTER WEAR.  HIGH: LESS GRIP, LASTS"},
		{"id": "psi_r", "label": "RIGHT PRESSURES", "values": psi, "index": int(st.psi_r), "hint": "THE RIGHT SIDES DO THE WORK ON AN OVAL"},
		{"id": "bias", "label": "BRAKE BIAS", "values": ["54% F", "56% F", "58% F", "60% F", "62% F"], "index": int(st.bias), "hint": "MORE FRONT: STABLE UNDER BRAKES, CAN LOCK THE FRONTS"},
		{"id": "gearing", "label": "GEARING", "values": ["SHORT", "STANDARD", "LONG"], "index": int(st.gearing), "hint": "SHORT: QUICKER OFF THE CORNERS.  LONG: MORE TOP SPEED"},
		{"id": "sheets", "label": "SETUP SHEETS", "hint": "SAVE, LOAD OR SHARE SETUPS"},
		{"id": "back", "label": "DONE"},
	]
	_open_menu("garage", "GARAGE", rows, rows.size() - 1)
	menu.row_h = 25
	menu.top = 78
	menu.build("GARAGE", rows, rows.size() - 1)


func _enter_setup_sheets() -> void:
	var sheets: Dictionary = Game.setup_sheets(Game.selected_track)
	var rows := [{"id": "sheet_save", "label": "SAVE CURRENT SETUP", "hint": "SAVED FOR %s" % Game.tracks[Game.selected_track].short}]
	for name in sheets:
		rows.append({"id": "sheet:" + String(name), "label": "LOAD  " + String(name)})
	rows.append({"id": "sheet_copy", "label": "COPY SHARE CODE", "hint": "PUTS A CODE FOR THIS SETUP ON THE CLIPBOARD"})
	rows.append({"id": "sheet_paste", "label": "PASTE SHARE CODE", "hint": "LOADS A SETUP CODE FROM THE CLIPBOARD"})
	rows.append({"id": "sheet_back", "label": "BACK"})
	_open_menu("sheets", "SETUP SHEETS", rows, 0)


func _on_sheet(id: String) -> void:
	match id:
		"sheets":
			_enter_setup_sheets()
		"sheet_save":
			var n := Game.setup_sheets(Game.selected_track).size() + 1
			Game.save_setup_sheet(Game.selected_track, "SETUP %d" % n)
			_enter_setup_sheets()
			_sub("SAVED AS SETUP %d" % n, 2.0)
		"sheet_copy":
			DisplayServer.clipboard_set(Game.setup_code())
			_sub("SETUP CODE COPIED", 2.0)
		"sheet_paste":
			_sub("SETUP LOADED" if Game.setup_from_code(DisplayServer.clipboard_get()) else "NO SETUP CODE ON THE CLIPBOARD", 2.0)
		"sheet_back":
			_enter_garage(menu_return)
		_:
			var sheets: Dictionary = Game.setup_sheets(Game.selected_track)
			var key := id.substr(6)
			if sheets.has(key):
				Game.load_setup(sheets[key])
				_sub("LOADED " + key, 2.0)
				_enter_garage(menu_return)


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


## "2868 X 1320 @ 120 HZ - 3D AT 100%": what the screen is and what's drawn.
func _display_hint() -> String:
	var px: Vector2i = get_window().size
	return "SCREEN %d X %d @ %d HZ  -  3D AT %d%%.  AUTO: NATIVE, LOWERED ONLY TO HOLD THE REFRESH RATE" % [px.x, px.y, int(round(display_hz())), int(round(get_viewport().scaling_3d_scale * 100.0))]


func _enter_options() -> void:
	var rows := [
		{"id": "gfx", "label": "GRAPHICS", "values": ["1999", "MODERN"] if Game.modern_supported else ["1999"], "index": 1 if Game.modern else 0, "hint": "MODERN: REALISTIC LIGHTING AND DETAIL.  1999: THE ORIGINAL ARCADE LOOK"},
		{"id": "quality", "label": "QUALITY (MODERN)", "values": Game.QUALITY_NAMES, "index": Game.quality, "hint": "AUTO LOWERS DETAIL WHEN FRAMES RUN LATE"},
		{"id": "res_mode", "label": "RESOLUTION", "values": RES_MODES, "index": int(Game.settings.get("res_mode", 0)), "hint": _display_hint()},
		{"id": "smooth", "label": "MOTION SMOOTHING", "values": ["OFF", "ON"], "index": 1 if Game.smoothing else 0, "hint": "SMOOTH MOTION ON 120/144 HZ SCREENS (ADDS UNDER 1 FRAME OF DELAY)"},
		{"id": "blur", "label": "MOTION BLUR", "values": ["OFF", "LOW", "HIGH"], "index": Game.motion_blur, "hint": "DESKTOP MODERN LOOK ONLY"},
		{"id": "wheel_setup", "label": "WHEEL SETUP", "hint": "STEERING WHEEL, PEDALS AND FORCE FEEDBACK"},
		{"id": "big_text", "label": "LARGE TEXT", "values": ["OFF", "ON"], "index": int(Game.settings.get("big_text", 0)), "hint": "BIGGER SMALL PRINT IN MENUS AND THE RACE SCREEN"},
		{"id": "map_contrast", "label": "MAP DOTS", "values": ["TEAM COLOURS", "HIGH CONTRAST"], "index": int(Game.settings.get("map_contrast", 0)), "hint": "HIGH CONTRAST: WHITE DOTS, THE LEADER RINGED, YOU A BLINKING SQUARE"},
		{"id": "hand", "label": "CONTROLS", "values": ["RIGHT-HANDED", "LEFT-HANDED"], "index": int(Game.settings.get("hand", 0)), "hint": "LEFT-HANDED: PEDALS ON THE LEFT, STEER ON THE RIGHT"},
		{"id": "battery", "label": "BATTERY SAVER", "values": ["OFF", "AUTO", "ON"], "index": int(Game.settings.get("battery", 1)), "hint": "30 FPS TO SAVE BATTERY AND HEAT.  AUTO: ON BATTERY AT 20% OR LESS"},
		{"id": "haptics", "label": "VIBRATION", "values": ["OFF", "ON"], "index": int(Game.settings.get("haptics", 1)), "hint": "PHONES: A BUZZ ON HITS AND LOCKED WHEELS"},
		{"id": "share_stats", "label": "SHARE STATS", "values": ["OFF", "ON"], "index": int(Game.settings.get("share_stats", 1)), "hint": "SENDS YOUR FRAME RATE AND DEVICE TYPE AFTER A RACE (NOTHING PERSONAL) TO HELP TUNE THE GAME"},
		{"id": "auto_gas", "label": "GAS", "values": ["YOU", "AUTO"], "index": int(Game.settings.get("auto_gas", 0)), "hint": "AUTO: THE CAR TAKES EACH CORNER AT A SAFE SPEED, YOU STEER (ONE THUMB). BRAKE STILL WORKS"},
		{"id": "tilt_sens", "label": "TILT STEERING", "values": ["GENTLE", "NORMAL", "QUICK", "VERY QUICK"], "index": int(Game.settings.get("tilt_sens", 1)), "hint": "PHONES: HOW FAR YOU TILT FOR FULL LOCK (18 / 12 / 9 / 6 DEGREES)"},
		{"id": "radio", "label": "CREW CHIEF VOICE", "values": ["OFF", "ON"], "index": 1 if Game.radio_voice else 0, "hint": "THE CREW CHIEF'S CALLS, SPOKEN"},
		{"id": "commentary", "label": "COMMENTARY", "values": ["OFF", "ON"], "index": int(Game.settings.get("commentary", 1)), "hint": "THE TV BOOTH'S PLAY-BY-PLAY AND ANALYST LINES, ON SCREEN"},
		{"id": "vsync", "label": "VSYNC", "values": ["OFF", "ON"], "index": 1 if Game.vsync else 0, "hint": "OFF: LOWEST INPUT DELAY, MAY TEAR"},
		{"id": "scan", "label": "SCANLINES (1999)", "values": ["OFF", "ON"], "index": 1 if Game.scanlines else 0},
		{"id": "account", "label": "ACCOUNT + NEW PHONE", "hint": "YOUR SAVED GAME ONLINE, AND MOVING IT TO A NEW PHONE"},
		{"id": "reset", "label": "RESET LAP RECORDS"},
		{"id": "back", "label": "DONE"},
	]
	_open_menu("options", "OPTIONS", rows, rows.size() - 1)


func _on_menu_changed(id: String, idx: int) -> void:
	synth.beep(880.0, 0.04)
	match menu_kind:
		"race_setup":
			if id == "field":
				Game.settings.field = idx - 1
				Game.save_settings()
			elif Game.settings.has(id):
				Game.settings[id] = idx
				Game.save_settings()
		"wheel":
			match id:
				"wh_enabled":
					Game.wheel.enabled = idx == 1
					Game.save_settings()
					if Game.wheel.enabled:
						wheel.start_helper()
					_enter_wheel_setup()
				"invert":
					Game.wheel.invert = idx == 1
					Game.save_settings()
				"rotation", "ffb":
					Game.wheel[id] = idx
					Game.save_settings()
		"lobby":
			match id:
				"lobby_track":
					_lobby_track = idx
				"lobby_laps":
					_lobby_laps = idx
				"lobby_ai":
					_lobby_ai = idx
		"garage":
			if id == "balance":
				Game.setup.balance = idx - 3
			elif Game.setup.has(id):
				Game.setup[id] = idx
			Game.save_settings()
		"paint":
			if id == "scheme" and not Game.scheme_unlocked(idx):
				# Locked: show what it looks like, but it isn't yours yet.
				_sub("%s UNLOCKS WITH %s" % [CarBody.SCHEMES[idx], Game.scheme_needs(idx).replace("LV ", "LEVEL ")], 2.5)
				var keep: int = Game.custom.scheme
				Game.custom.scheme = idx
				_paint_preview()
				Game.custom.scheme = keep
			else:
				Game.custom[id] = idx + 1 if id == "num" else idx
				_paint_preview()
		"boards":
			_on_boards_changed(id, idx)
		"options":
			if id == "gfx" and Game.modern_supported and (idx == 1) != Game.modern:
				Game.toggle_graphics()
				Game.save_settings()
			elif id == "quality":
				Game.quality = idx
				if idx != 0:
					Game.auto_quality = min(idx, 3)
				_apply_graphics()
				Game.save_settings()
			elif id == "smooth":
				Game.smoothing = idx == 1
				Game.save_settings()
			elif id == "blur":
				Game.motion_blur = idx
				Game.save_settings()
			elif id == "radio":
				Game.radio_voice = idx == 1
				Game.save_settings()
			elif id == "res_mode":
				Game.settings["res_mode"] = idx
				_fit_web_resolution(true)
				Game.save_settings()
				menu.rows[menu.cursor].hint = _display_hint()
				menu._refresh()
			elif id == "commentary":
				Game.settings["commentary"] = idx
				Game.save_settings()
			elif id == "tilt_sens":
				Game.settings["tilt_sens"] = idx
				Game.save_settings()
			elif id == "battery":
				Game.settings["battery"] = idx
				Game.save_settings()
				_battery_t = 0.0
			elif id == "big_text":
				Game.settings["big_text"] = idx
				Game.save_settings()
				_enter_options() # rebuild the screen in the new size
				for i in menu.rows.size():
					if String(menu.rows[i].get("id", "")) == "big_text":
						menu.cursor = i
				menu._keep_cursor_visible()
				menu._refresh()
			elif id == "map_contrast" or id == "hand":
				Game.settings[id] = idx
				Game.save_settings()
			elif id == "auto_gas" or id == "share_stats" or id == "haptics":
				Game.settings[id] = idx
				Game.save_settings()
			elif id == "vsync":
				Game.vsync = idx == 1
				_apply_graphics()
				Game.save_settings()
			elif id == "scan":
				Game.scanlines = idx == 1
				scan_rect.visible = Game.scanlines and not Game.modern
				Game.save_settings()


func _on_menu_activated(id: String) -> void:
	synth.beep(1320.0, 0.06)
	if menu_kind == "account":
		_account_action(id)
		return
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
	if id == "daily":
		_start_challenge(-1)
		return
	if id.begins_with("sheet"):
		_on_sheet(id)
		return
	if id.begins_with("net_"):
		_on_online_menu(id)
		return
	if id == "b_add":
		_add_friend()
		return
	if id == "b_back":
		_enter_mode_select()
		return
	if id == "wheel_setup":
		_enter_wheel_setup()
		return
	if id.begins_with("wh_"):
		match id:
			"wh_steer", "wh_throttle", "wh_brake":
				wheel.begin_detect({"wh_steer": "steer_axis", "wh_throttle": "throttle_axis", "wh_brake": "brake_axis"}[id])
				_enter_wheel_setup()
			"wh_back":
				_enter_options()
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
		"restart":
			_enter_career_confirm("restart")
		"retire":
			_enter_career_confirm("retire")
		"cr_same":
			_restart_career(true)
		"cr_new":
			_restart_career(false)
		"cr_retire":
			_drop_career_checkpoint()
			Game.clear_career()
			Game.clear_season()
			_enter_title()
		"cr_cancel":
			_enter_career_hub()
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
		"account":
			_enter_account()
		"reset":
			Game.records = ConfigFile.new()
			Game.records.save(Game.RECORDS_PATH)
			Game.save_changed.emit()
			_sub("RECORDS CLEARED", 2.0)
		"back":
			_on_menu_cancelled()


func _on_menu_cancelled() -> void:
	match menu_kind:
		"career_confirm":
			_enter_career_hub()
		"boards":
			if _friend_edit:
				_friend_edit.visible = false
			_enter_mode_select()
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
		"sheets":
			_enter_garage(menu_return)
		"online":
			_enter_mode_select()
		"wheel":
			_enter_options()
		"lobby":
			net.leave()
			_enter_online()
		"rnd", "sponsors":
			_enter_career_hub()
		"hub", "options":
			_enter_mode_select()
		"account":
			if _code_edit:
				_code_edit.visible = false
			_enter_options()
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
		if editor and is_instance_valid(editor) and Game.track().name == "EDITOR TEST":
			_enter_track_editor() # back to the editor after a test drive
			return
		_enter_title()
		return
	session = sessions[session_idx]
	_enter_countdown()


## Starting order for the race: qualifying order if we have one (the player keeps
## their spot even in a smaller field), otherwise random with the player mid-pack.
func _grid_for(size: int, player_team: int) -> Array:
	if qual_grid.is_empty():
		# No qualifying: start in the middle of the pack, not at the back of it.
		if Game.teams.size() < size:
			Game._fill_teams()
		var others: Array = range(Game.teams.size()).filter(func(i): return i != player_team)
		others.shuffle()
		var slot: int = (size - 1) / 2
		var out: Array = []
		for i in size:
			out.append(player_team if i == slot else others.pop_back())
		return out
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
	_label("start", _press("CONTINUE") + " TO THE RACE", 18, Color.WHITE, Vector2(0, 440), HORIZONTAL_ALIGNMENT_CENTER, 5)


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
	_label("start", _press("CONTINUE"), 16, Color.WHITE, Vector2(0, 446), HORIZONTAL_ALIGNMENT_CENTER, 4)


# --- paint shop ---------------------------------------------------------------------

func _enter_paint_shop() -> void:
	var cols: Array = Game.PALETTE.map(func(p): return p[0])
	var nums: Array = range(1, 100).map(func(n): return str(n))
	var rows := [
		{"id": "num", "label": "CAR NUMBER", "values": nums, "index": int(Game.custom.num) - 1},
		{"id": "first", "label": "FIRST NAME", "values": Game.FIRST_NAMES, "index": Game.custom.first},
		{"id": "last", "label": "LAST NAME", "values": Game.LAST_NAMES, "index": Game.custom.last},
		{"id": "sponsor", "label": "SPONSOR", "values": Game.SPONSORS, "index": Game.custom.sponsor},
		{"id": "make", "label": "BODY", "values": CarBody.MAKES.map(func(m): return m.name), "index": Game.custom.make, "hint": "FOUR BODIES ON ONE CHASSIS: SAME SPEED, DIFFERENT LOOKS"},
		{"id": "scheme", "label": "SCHEME", "values": range(CarBody.SCHEMES.size()).map(func(i): return CarBody.SCHEMES[i] if Game.scheme_unlocked(i) else "%s (%s)" % [CarBody.SCHEMES[i], Game.scheme_needs(i)]), "index": Game.custom.scheme, "hint": "HOW YOUR COLORS GO ON. RACE TO LEVEL UP AND UNLOCK MORE"},
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
	preview_car.position = showtime.showroom_spot()
	showtime.present_car(preview_car)


# --- Lightning Challenges ---------------------------------------------------------

func _enter_challenges() -> void:
	mode = "challenge"
	var daily: Dictionary = Game.daily_challenge()
	var rows: Array = [{"id": "daily", "label": ("[X] " if Game.daily_done() else "[ ] ") + "TODAY: " + String(daily.name), "hint": daily.desc}]
	for i in Game.CHALLENGES.size():
		var ch: Dictionary = Game.CHALLENGES[i]
		var done: bool = Game.challenges_done.has(str(i))
		rows.append({"id": "ch_%d" % i, "label": ("[X] " if done else "[ ] ") + ch.name, "hint": ch.desc})
	var title := "LIGHTNING CHALLENGES  %d/%d" % [Game.challenges_done.size(), Game.CHALLENGES.size()]
	_open_menu("challenges", title, rows, challenge_idx + 1)
	menu.row_h = 28
	menu.build(title, rows, challenge_idx + 1)


func _start_challenge(idx: int) -> void:
	challenge_idx = idx
	challenge = Game.daily_challenge() if idx < 0 else Game.CHALLENGES[idx]
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
		{"id": "restart", "label": "RESTART CAREER", "hint": "START AGAIN FROM YEAR 1 WITH $%s" % Game.money_text(Game.CAREER_START_MONEY)},
		{"id": "retire", "label": "RETIRE", "hint": "ENDS AND DELETES THIS CAREER"},
	]
	_open_menu("hub", "YEAR %d  -  $%s  -  REP %d" % [cr.year, Game.money_text(cr.money), cr.rep], rows, 0)
	menu.row_h = 28
	menu.build(menu.title, rows, 0)


## Restarting or retiring throws away everything this career has done, so ask
## first (the safe choice is the one the cursor starts on).
func _enter_career_confirm(kind: String) -> void:
	var cr: Dictionary = Game.career
	var t: Dictionary = Game.teams[int(cr.team)]
	var lost := "YEAR %d, $%s, %d WINS" % [int(cr.year), Game.money_text(cr.money), int(cr.stats.wins)]
	var rows: Array
	var title: String
	if kind == "restart":
		title = "RESTART CAREER?"
		rows = [
			{"id": "cr_cancel", "label": "KEEP MY CAREER", "hint": lost},
			{"id": "cr_same", "label": "START OVER IN THE #%s" % t.num, "hint": "YEAR 1, $%s IN THE BANK, NO UPGRADES. THIS CAREER IS DELETED" % Game.money_text(Game.CAREER_START_MONEY)},
			{"id": "cr_new", "label": "START OVER IN A NEW CAR", "hint": "PICK ANY CAR, THEN YEAR 1 WITH $%s. THIS CAREER IS DELETED" % Game.money_text(Game.CAREER_START_MONEY)},
		]
	else:
		title = "RETIRE?"
		rows = [
			{"id": "cr_cancel", "label": "KEEP RACING", "hint": lost},
			{"id": "cr_retire", "label": "RETIRE AND DELETE THIS CAREER", "hint": "THIS CAN'T BE UNDONE"},
		]
	_open_menu("career_confirm", title, rows, 0)


## A race checkpoint from the old career would put you back in it.
func _drop_career_checkpoint() -> void:
	if String(resume_info().get("data", {}).get("mode", "")) == "career":
		clear_checkpoint()


func _restart_career(same_car: bool) -> void:
	var team: int = int(Game.career.team)
	_drop_career_checkpoint()
	Game.clear_career()
	Game.clear_season()
	mode = "career"
	if same_car:
		Game.selected_team = team
		Game.new_career(team)
		_enter_career_hub()
		_sub("NEW CAREER: YEAR 1, $%s IN THE BANK" % Game.money_text(Game.CAREER_START_MONEY), 3.0)
	else:
		_enter_car_select()


func _enter_rnd(cursor := 0) -> void:
	var rows: Array = []
	for u in Game.UPGRADES:
		var lvl: int = Game.career.upgrades[u[0]]
		var bar := "|".repeat(lvl) + ".".repeat(Game.MAX_UPGRADE - lvl)
		var now := "NOW " + Game.upgrade_effect_text(u[0], lvl)
		var nxt := "MAXED" if lvl >= Game.MAX_UPGRADE else "NEXT: %s FOR $%s" % [Game.upgrade_effect_text(u[0], lvl + 1), Game.money_text(Game.upgrade_cost(u[0]))]
		rows.append({"id": "up_" + u[0], "label": "%s  %s" % [u[1], bar], "hint": "%s  -  %s" % [now, nxt]})
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
	_label("start", _press("CONTINUE"), 16, Color.WHITE, Vector2(0, 432), HORIZONTAL_ALIGNMENT_CENTER, 4)


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
	ui_root.add_child(ov)


func _replay_overlay() -> void:
	var ov: Label = ui_root.get_node_or_null("ReplayOverlay")
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
	ov.text = "%s  %s / %s  %s   #%s %s   [%s]\nLEFT/RIGHT CAR   UP/DOWN SPEED   C CAMERA   F PHOTO   START EXIT" % [blink, Game.format_time(at), Game.format_time(span), rate, c.team.num, c.team.driver, (["DIRECTOR", "CHASE", "BUMPER", "HELICOPTER", "ROOF", "BLIMP", "TRACKSIDE"][replay_cam] + ("  " + _hl_label if _hl_label != "" else ""))]
	synth.engine_on = true
	synth.engine_rpm = 3000.0 + abs(c.v) * 70.0
	synth.engine_load = 0.8


# --- leaderboards --------------------------------------------------------------

const BOARDS := ["TRACK RECORDS", "FRIENDS", "DAILY CHALLENGE", "WEEKLY TIME TRIAL"]
var _board := 0
var _board_track := 0
var _board_rows: Array = []
var _board_state := "" # "", "loading", "offline"
var _friend_edit: LineEdit


func _enter_boards(refetch := true) -> void:
	var names: Array = Game.tracks.slice(0, Cloud.RANKED_TRACKS).map(func(t): return t.short)
	_board_track = clamp(_board_track, 0, names.size() - 1)
	var wk: Dictionary = Game.weekly_event()
	var rows: Array = [
		{"id": "board", "label": "BOARD", "values": BOARDS, "index": _board},
	]
	if _board <= 1:
		rows.append({"id": "b_track", "label": "TRACK", "values": names, "index": _board_track})
	var sub := ""
	match _board:
		2: sub = "TODAY: " + String(Game.daily_challenge().name)
		3: sub = "THIS WEEK: " + String(wk.name)
	if sub != "":
		rows.append({"id": "b_sub", "label": sub, "disabled": true})
	if _board_state == "loading":
		rows.append({"id": "b_wait", "label": "LOADING...", "disabled": true})
	elif _board_state == "offline" or not cloud.enabled:
		rows.append({"id": "b_wait", "label": "OFFLINE - CAN'T REACH THE LEADERBOARDS", "disabled": true})
	elif _board_rows.is_empty():
		rows.append({"id": "b_wait", "label": "NO TIMES YET - SET ONE!", "disabled": true})
	for i in _board_rows.size():
		var r: Dictionary = _board_rows[i]
		var me: bool = String(r.get("player_id", "")) == cloud.id
		var val := ""
		if _board == 2:
			var det: Dictionary = r.get("detail", {}) if r.get("detail", {}) is Dictionary else {}
			val = "%s  %s" % [Game.ordinal(int(det.get("place", 0))), Game.format_time(float(det.get("time", 0.0)))]
		else:
			val = Game.format_time(float(r.get("lap_ms", r.get("score", 0))) / 1000.0)
		rows.append({"id": "b_row", "label": "%d  %s  #%s%s" % [i + 1, String(r.name), String(r.num), "  (YOU)" if me else ""], "values": [val], "index": 0, "disabled": true})
	rows.append({"id": "b_code", "label": "YOUR FRIEND CODE", "values": [cloud.friend_code if cloud.friend_code != "" else "-"], "index": 0, "disabled": true,
		"hint": "SEND IT TO FRIENDS: THEY ADD YOU, AND YOU RACE EACH OTHER'S GHOSTS"})
	rows.append({"id": "b_add", "label": "ADD A FRIEND", "hint": "TYPE THEIR 6-CHARACTER FRIEND CODE (%d FRIENDS)" % cloud.friends.size()})
	rows.append({"id": "b_back", "label": "BACK"})
	var cur := 0
	if menu and menu_kind == "boards":
		cur = min(menu.cursor, rows.size() - 1)
	_open_menu("boards", "LEADERBOARDS", rows, cur)
	if refetch:
		_fetch_board()


func _fetch_board() -> void:
	if not cloud.enabled:
		return
	_board_state = "loading"
	var want := [_board, _board_track]
	var got := func(rows: Array):
		if [_board, _board_track] != want:
			return # moved on
		_board_rows = rows
		_board_state = "" if cloud.online else "offline"
		if state == State.MENU and menu_kind == "boards":
			_enter_boards(false)
	match _board:
		0:
			cloud.top_laps(_board_track, got)
		1:
			cloud.load_friends(func(_ok): cloud.friend_laps(_board_track, got))
		2:
			cloud.event_board(Game.daily_event_key(), got)
		3:
			cloud.event_board(String(Game.weekly_event().key), got)


func _on_boards_changed(id: String, idx: int) -> void:
	if id == "board":
		_board = idx
	elif id == "b_track":
		_board_track = idx
	_board_rows = []
	_enter_boards()


func _add_friend() -> void:
	if _friend_edit == null:
		_friend_edit = LineEdit.new()
		_friend_edit.position = Vector2(170, 360)
		_friend_edit.size = Vector2(300, 40)
		_friend_edit.max_length = 6
		_friend_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_friend_edit.placeholder_text = "FRIEND CODE"
		_friend_edit.add_theme_font_size_override("font_size", 22)
		_friend_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
		var go := func(t: String):
			_friend_edit.visible = false
			cloud.add_friend(t, func(ok: bool, msg: String):
				_sub(msg, 3.0)
				if ok and state == State.MENU and menu_kind == "boards":
					_enter_boards())
		_friend_edit.text_submitted.connect(go)
		_friend_edit.text_changed.connect(func(t: String):
			if t.length() == 6:
				go.call(t))
		ui_root.add_child(_friend_edit)
	_friend_edit.text = ""
	_friend_edit.visible = true
	_friend_edit.grab_focus()


# --- online ---------------------------------------------------------------------

var net: Node
var net_config := {}
var net_address := "ws://127.0.0.1:24565"
var _lobby_track := 0
var _lobby_laps := 1
var _lobby_ai := 1
var _addr_edit: LineEdit


func _enter_online() -> void:
	var rows := [
		{"id": "net_room_host", "label": "HOST A RACE", "hint": "YOU GET A ROOM CODE TO SEND YOUR FRIENDS"},
		{"id": "net_room_join", "label": "JOIN WITH A CODE", "hint": "TYPE THE 4-DIGIT CODE FROM THE HOST"},
		{"id": "net_host", "label": "HOST ON THIS COMPUTER", "hint": "DESKTOP: OPENS PORT %d ON YOUR NETWORK" % Net.PORT},
		{"id": "net_addr", "label": "ADDRESS", "values": [net_address], "index": 0, "hint": "START TO TYPE AN ADDRESS (BROWSERS NEED A WSS:// HOST)"},
		{"id": "net_join", "label": "JOIN BY ADDRESS", "hint": "CONNECTS TO THE ADDRESS ABOVE"},
		{"id": "net_back", "label": "BACK"},
	]
	_open_menu("online", "ONLINE", rows, 0)


func _enter_lobby() -> void:
	var rows: Array = []
	for id in net.players:
		var pl: Dictionary = net.players[id]
		var team: Dictionary = Game.teams[clamp(int(pl.team), 0, Game.teams.size() - 1)]
		rows.append({"id": "net_player", "label": "%s  #%s" % [pl.name, team.num], "disabled": true, "hint": "HOST" if int(id) == 1 else "READY"})
	if net.hosting:
		var names: Array = Game.tracks.map(func(t): return t.short)
		rows.append({"id": "lobby_track", "label": "TRACK", "values": names, "index": _lobby_track})
		rows.append({"id": "lobby_laps", "label": "LAPS", "values": ["3", "5", "10", "20"], "index": _lobby_laps})
		rows.append({"id": "lobby_ai", "label": "AI CARS", "values": ["0", "8", "16", "24"], "index": _lobby_ai})
		rows.append({"id": "net_start", "label": "START RACE"})
	else:
		rows.append({"id": "net_wait", "label": "WAITING FOR THE HOST", "disabled": true})
	rows.append({"id": "net_leave", "label": "LEAVE"})
	var title := "LOBBY  (%d DRIVERS)" % net.players.size()
	if net.room_code != "":
		title = "ROOM %s  -  %d DRIVER%s" % [net.room_code, net.players.size(), "" if net.players.size() == 1 else "S"]
		if not net.connected:
			rows = [{"id": "net_wait", "label": "FINDING ROOM %s..." % net.room_code, "disabled": true}, {"id": "net_leave", "label": "CANCEL"}]
	_open_menu("lobby", title, rows, rows.size() - (2 if net.hosting else 1))


func _on_online_menu(id: String) -> void:
	match id:
		"net_host":
			var err: String = net.host()
			if err != "":
				_sub(err, 3.0)
			else:
				_enter_lobby()
		"net_join":
			var err2: String = net.join(net_address)
			if err2 != "":
				_sub(err2, 3.0)
			else:
				_enter_lobby()
		"net_room_host":
			var err3: String = net.host_room()
			if err3 != "":
				_sub(err3, 3.0)
			else:
				_enter_lobby()
				_sub("ROOM CODE %s - SEND IT TO YOUR FRIENDS" % net.room_code, 6.0)
		"net_room_join":
			_edit_address(true)
		"net_addr":
			_edit_address()
		"net_back":
			_enter_mode_select()
		"net_leave":
			net.leave()
			_enter_online()
		"net_start":
			var laps: int = [3, 5, 10, 20][_lobby_laps]
			var ai: int = [0, 8, 16, 24][_lobby_ai]
			net.start_race(_lobby_track, laps, ai + net.players.size())


var _editing_code := false


## Typing an address, or (`code`) a room code: a number pad on a phone.
func _edit_address(code := false) -> void:
	_editing_code = code
	if _addr_edit == null:
		_addr_edit = LineEdit.new()
		_addr_edit.position = Vector2(120, 360)
		_addr_edit.size = Vector2(400, 40)
		_addr_edit.add_theme_font_size_override("font_size", 22)
		_addr_edit.text_submitted.connect(func(t: String):
			_addr_edit.visible = false
			if _editing_code:
				var err: String = net.join_room(t)
				if err != "":
					_sub(err, 3.0)
					_enter_online()
				else:
					_enter_lobby()
			else:
				net_address = t.strip_edges()
				_enter_online())
		# Four digits is the whole code: go as soon as they're typed.
		_addr_edit.text_changed.connect(func(t: String):
			if _editing_code and t.length() == 4 and t.is_valid_int():
				_addr_edit.text_submitted.emit(t))
		ui_root.add_child(_addr_edit)
	_addr_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER if code else LineEdit.KEYBOARD_TYPE_URL
	_addr_edit.max_length = 4 if code else 0
	_addr_edit.placeholder_text = "ROOM CODE" if code else ""
	_addr_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER if code else HORIZONTAL_ALIGNMENT_LEFT
	_addr_edit.text = "" if code else net_address
	_addr_edit.visible = true
	_addr_edit.grab_focus()


func _net_start_race(config: Dictionary) -> void:
	net_config = config
	mode = "online"
	session = "race"
	var slot: int = net.my_slot(config)
	Game.selected_team = int(config.roster[slot]) if slot >= 0 else Game.selected_team
	_use_track(int(config.track))
	seed(int(config.seed))
	_enter_countdown()


# --- wheel setup -----------------------------------------------------------------

var wheel: Node


func _enter_wheel_setup() -> void:
	var w: Dictionary = Game.wheel
	var st: String = wheel.status if wheel.status != "" else ("HELPER NOT RUNNING" if w.enabled else "")
	var axis_txt := func(key: String) -> String:
		return ("MOVE IT NOW..." if wheel.detecting == key else "PAD %d AXIS %d" % [int(w.device), int(w[key])])
	var rows := [
		{"id": "wh_enabled", "label": "USE A WHEEL", "values": ["OFF", "ON"], "index": 1 if w.enabled else 0, "hint": st},
		{"id": "wh_steer", "label": "STEERING", "values": [axis_txt.call("steer_axis")], "index": 0, "hint": "START, THEN TURN THE WHEEL"},
		{"id": "wh_throttle", "label": "THROTTLE", "values": [axis_txt.call("throttle_axis")], "index": 0, "hint": "START, THEN PRESS THE THROTTLE"},
		{"id": "wh_brake", "label": "BRAKE", "values": [axis_txt.call("brake_axis")], "index": 0, "hint": "START, THEN PRESS THE BRAKE"},
		{"id": "invert", "label": "PEDALS", "values": ["NORMAL", "INVERTED"], "index": 1 if w.invert else 0, "hint": "IF THE CAR ACCELERATES WITH YOUR FOOT OFF, INVERT"},
		{"id": "rotation", "label": "WHEEL ROTATION", "values": Wheel.ROTATIONS.map(func(x): return "%d DEG" % x), "index": int(w.rotation), "hint": "SET THE SAME IN YOUR WHEEL'S OWN SOFTWARE"},
		{"id": "ffb", "label": "FORCE FEEDBACK", "values": ["OFF", "LIGHT", "MEDIUM", "STRONG", "MAX"], "index": int(w.ffb), "hint": "WINDOWS: NEEDS FFB_HELPER.EXE NEXT TO THE GAME"},
		{"id": "wh_back", "label": "DONE"},
	]
	_open_menu("wheel", "WHEEL SETUP", rows, 0)


# --- track editor ---------------------------------------------------------------------

var editor: Control


func _enter_track_editor() -> void:
	_set_state(State.MENU)
	_clear_screen()
	menu_kind = "editor"
	if editor == null or not is_instance_valid(editor):
		editor = TrackEditor.new()
		editor.test_drive.connect(_editor_test_drive)
		editor.closed.connect(func():
			editor.visible = false
			_enter_mode_select())
		ui_root.add_child(editor)
	editor.visible = true


## Practice on the layout being edited (it's added as a track for the session).
func _editor_test_drive(cfg: Dictionary) -> void:
	editor.visible = false
	var d: Dictionary = cfg.duplicate(true)
	d.name = "EDITOR TEST"
	var idx: int = Game.add_track(d)
	if tracks.has(idx):
		tracks[idx].queue_free()
		tracks.erase(idx)
	mode = "race"
	_use_track(idx)
	sessions = ["practice"]
	session_idx = 0
	session = "practice"
	_enter_countdown()


# --- broadcast director, highlights, photo mode -------------------------------------

## Director: cuts between the action like a TV truck. Incidents first, then the
## closest battle in the top positions, then the leader, with a mix of shots.
var _dir_timer := 0.0
var _dir_shot := 6
var _hl_clips: Array = []
var _hl_index := 0
var _hl_label := ""
var photo_mode := false
var _photo_orbit := Vector3(0.6, 0.25, 9.0) # yaw, pitch, distance
var _photo_prev_rate := 1.0


func _replay_order() -> Array:
	var o: Array = race.cars.filter(func(c): return c.visible)
	o.sort_custom(func(a, b): return a.dist > b.dist)
	return o


func _director(delta: float) -> void:
	_dir_timer -= delta * max(abs(replay_rate), 0.5)
	# An incident on screen right now takes priority.
	for h in race.highlights:
		if abs(float(h.t) - replay_t) < 1.0 and int(h.car) != replay_focus and int(h.car) >= 0 and _dir_timer < 3.0:
			replay_focus = int(h.car)
			_dir_shot = [6, 5, 3][rng.randi() % 3]
			_dir_timer = 5.0
			tv_anchor = Vector3.ZERO
			return
	if _dir_timer > 0.0:
		return
	_dir_timer = rng.randf_range(4.0, 8.0)
	var o := _replay_order()
	var pick: Node3D = o[0] if not o.is_empty() else race.cars[0]
	# The closest fight in the top ten.
	var best := 1e9
	for i in range(0, min(10, o.size() - 1)):
		var gap: float = o[i].dist - o[i + 1].dist
		if gap < best and gap < 12.0:
			best = gap
			pick = o[i + 1]
	if rng.randf() < 0.2 and race.player:
		pick = race.player
	replay_focus = max(race.cars.find(pick), 0)
	_dir_shot = [6, 6, 1, 3, 4, 5, 2][rng.randi() % 7]
	tv_anchor = Vector3.ZERO


func _roof_camera(car: Node3D) -> void:
	var tr: Transform3D = car.global_transform
	cam.global_transform = tr * Transform3D(Basis().rotated(Vector3.RIGHT, -0.12), Vector3(0, 1.75, 0.9))
	cam.fov = 72.0


func _blimp_camera(car: Node3D, delta: float) -> void:
	var tr: Transform3D = car.global_transform
	var target := tr.origin + Vector3(0, 140, 0) + tr.basis.z * 120.0
	cam_pos = cam_pos.lerp(target, 1.0 - exp(-1.5 * delta))
	cam.global_position = cam_pos
	cam.look_at(tr.origin, Vector3.UP)
	cam.fov = 38.0


## Highlights: every incident, big hit and lead change, three seconds either side,
## the moment itself in slow motion.
func _enter_highlights() -> void:
	_enter_replay()
	_hl_clips.clear()
	var last_t := -100.0
	for h in race.highlights:
		if float(h.t) - last_t < 4.0:
			continue
		last_t = float(h.t)
		_hl_clips.append(h)
	if _hl_clips.is_empty():
		_hl_label = "NO HIGHLIGHTS - FULL REPLAY"
		return
	_hl_index = 0
	_start_clip()


func _start_clip() -> void:
	var h: Dictionary = _hl_clips[_hl_index]
	replay_t = max(float(h.t) - 3.0, race.rec_times[0])
	replay_focus = max(int(h.car), 0)
	replay_cam = 0
	_dir_timer = 6.0
	_dir_shot = [6, 5, 3][_hl_index % 3]
	tv_anchor = Vector3.ZERO
	var car_name: String = race.cars[replay_focus].team.num
	_hl_label = "HIGHLIGHT %d/%d: %s #%s" % [_hl_index + 1, _hl_clips.size(), h.kind, car_name]


func _highlight_tick(delta: float) -> void:
	var h: Dictionary = _hl_clips[_hl_index]
	var t0: float = float(h.t)
	var rate := 0.35 if abs(replay_t - t0) < 1.2 else 1.0
	replay_t += delta * rate
	if replay_t > t0 + 3.5 or replay_t >= race.rec_times[race.rec_times.size() - 1]:
		_hl_index += 1
		if _hl_index >= _hl_clips.size():
			_hl_clips.clear()
			_hl_label = ""
			screen.visible = true
			_set_state(State.RESULTS)
			hud.visible = false
			return
		_start_clip()


## Photo mode: freeze the moment, fly the camera round the car, take the shot.
func _enter_photo() -> void:
	photo_mode = true
	_photo_prev_rate = replay_rate
	replay_rate = 0.0
	hud.visible = false
	telemetry.visible = false
	var ov: Node = ui_root.get_node_or_null("ReplayOverlay")
	if ov:
		ov.visible = false
	_sub("PHOTO MODE: ARROWS ORBIT  W/S ZOOM  E/Q HEIGHT  ENTER SNAP  BACKSPACE EXIT", 4.0)
	if Game.forward_plus:
		var ca := CameraAttributesPractical.new()
		ca.dof_blur_far_enabled = true
		ca.dof_blur_amount = 0.08
		cam.attributes = ca


func _exit_photo() -> void:
	photo_mode = false
	replay_rate = _photo_prev_rate
	cam.attributes = null
	if state != State.REPLAY:
		hud.visible = true
		paused = false
	var ov: Node = ui_root.get_node_or_null("ReplayOverlay")
	if ov:
		ov.visible = true


func _photo_focus() -> Node3D:
	return race.cars[replay_focus] if state == State.REPLAY else race.player


func _photo_camera(delta: float) -> void:
	var car := _photo_focus()
	if car == null:
		return
	if Input.is_action_pressed("steer_left"):
		_photo_orbit.x -= delta * 1.2
	if Input.is_action_pressed("steer_right"):
		_photo_orbit.x += delta * 1.2
	if Input.is_action_pressed("accelerate"):
		_photo_orbit.z = max(_photo_orbit.z - delta * 6.0, 3.0)
	if Input.is_action_pressed("brake"):
		_photo_orbit.z = min(_photo_orbit.z + delta * 6.0, 40.0)
	if Input.is_action_pressed("shift_up"):
		_photo_orbit.y = min(_photo_orbit.y + delta * 0.6, 1.4)
	if Input.is_action_pressed("shift_down"):
		_photo_orbit.y = max(_photo_orbit.y - delta * 0.6, -0.05)
	var p: Vector3 = car.global_position + Vector3(0, 0.8, 0)
	var dir := Vector3(sin(_photo_orbit.x) * cos(_photo_orbit.y), sin(_photo_orbit.y), cos(_photo_orbit.x) * cos(_photo_orbit.y))
	cam.global_position = p + dir * _photo_orbit.z
	cam.look_at(p, Vector3.UP)
	cam.fov = 45.0
	if cam.attributes is CameraAttributesPractical:
		(cam.attributes as CameraAttributesPractical).dof_blur_far_distance = _photo_orbit.z * 1.6
		(cam.attributes as CameraAttributesPractical).dof_blur_far_transition = _photo_orbit.z * 2.0


func _photo_input(event: InputEvent) -> void:
	if event.is_action_pressed("back") or event.is_action_pressed("photo"):
		_exit_photo()
	elif event.is_action_pressed("start"):
		_take_photo()


func _take_photo() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		return
	var fname := "speedway_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(img.save_png_to_buffer(), fname, "image/png")
		_sub("PHOTO SAVED TO YOUR DOWNLOADS", 2.0)
	else:
		DirAccess.make_dir_recursive_absolute("user://photos")
		img.save_png("user://photos/" + fname)
		_sub("PHOTO SAVED: " + ProjectSettings.globalize_path("user://photos/" + fname), 3.0)
	synth.beep(1500.0, 0.05)


# --- split screen -------------------------------------------------------------------

func _msg(text: String, seconds := 2.0, color := Color(1, 0.9, 0.2)) -> void:
	hud.message(text, seconds, color)
	for h in split_huds:
		h.message(text, seconds, color)


func _sub(text: String, seconds := 2.0) -> void:
	hud.sub_message(text, seconds)
	for h in split_huds:
		h.sub_message(text, seconds)


func _build_split() -> void:
	Game.set_two_player_input(true)
	split_layer = CanvasLayer.new()
	split_layer.layer = 0
	add_child(split_layer)
	var split_frame := Game.center_frame(Control.new())
	split_layer.add_child(split_frame)
	for i in 2:
		# Each half: its own viewport, shown as a picture (no SubViewportContainer,
		# which the trimmed web engine leaves out).
		var vp := SubViewport.new()
		vp.size = Vector2i(640, 239)
		vp.audio_listener_enable_3d = false
		split_frame.add_child(vp)
		var cont := TextureRect.new()
		cont.position = Vector2(0, i * 241)
		cont.size = Vector2(640, 239)
		cont.stretch_mode = TextureRect.STRETCH_SCALE
		cont.texture = vp.get_texture()
		split_frame.add_child(cont)
		var c := Camera3D.new()
		c.far = 3000.0
		c.near = 0.3
		vp.add_child(c)
		c.current = true
		var hl := CanvasLayer.new()
		vp.add_child(hl)
		var h: Control = Hud.new()
		var sc := 0.6
		h.auto_size = false
		h.W = 640.0 / sc
		h.H = 239.0 / sc
		h.player_idx = i + 1
		h.show_timer = false
		h.race = race
		h.track = track
		h.control = race.control
		hl.add_child(h)
		h.scale = Vector2(sc, sc)
		split_cams.append(c)
		split_huds.append(h)
		split_state[i] = {}
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0)
	bar.position = Vector2(0, 239)
	bar.size = Vector2(640, 2)
	split_frame.add_child(bar)
	hud.visible = false


func _teardown_split() -> void:
	if split_layer:
		split_layer.queue_free()
		split_layer = null
		Game.set_two_player_input(false)
	split_cams.clear()
	split_huds.clear()


func _split_camera(c: Camera3D, st: Dictionary, car: Node3D, delta: float) -> void:
	if car == null:
		return
	var tr: Transform3D = car.global_transform
	var back := tr.basis.z
	var up := tr.basis.y
	var cb: Vector3 = st.get("back", back)
	if cb.dot(back) < 0.3:
		cb = back
	cb = cb.lerp(back, 1.0 - exp(-7.0 * delta)).normalized()
	st["back"] = cb
	c.global_position = tr.origin + cb * 7.0 + up * 2.4
	c.look_at(tr.origin + up * 1.0 - cb * 8.0, up.lerp(Vector3.UP, 0.4).normalized())
	c.fov = 62.0 + clamp(abs(car.v) / 85.0, 0.0, 1.2) * 12.0
