extends Node
## Global game data: tracks, teams, input bindings, records and the arcade font.

const TITLE := "SPEEDWAY THUNDER"
const SUBTITLE := "STOCK CAR ARCADE  '99"
const MPS_TO_MPH := 2.23694
const FIELD_SIZE := 12
const RECORDS_PATH := "user://records.cfg"

## Oval layout: two straights of `straight` metres joined by 180 degree turns of
## `radius`. `bump` pushes the frontstretch outward (tri-oval / quad-oval doglegs).
var tracks: Array[Dictionary] = [
	{
		"name": "THUNDER BEACH INT'L SPEEDWAY",
		"short": "THUNDER BEACH",
		"kind": "SUPERSPEEDWAY",
		"level": "BEGINNER",
		"shape": "trioval",
		"straight": 900.0, "radius": 260.0, "bump": 110.0,
		"width": 20.0, "apron": 9.0, "infield": 14.0,
		"bank_turn": 31.0, "bank_straight": 4.0,
		"laps": 3, "draft": 1.0, "grid_player": 9,
		"sky_top": Color(0.18, 0.38, 0.78), "sky_horizon": Color(0.72, 0.84, 0.95),
		"grass": Color(0.24, 0.55, 0.18), "fog": Color(0.70, 0.80, 0.92),
		"lake": true, "sun_elev": 58.0, "sun_az": 35.0,
	},
	{
		"name": "LONE STAR MOTOR SPEEDWAY",
		"short": "LONE STAR",
		"kind": "QUAD-OVAL SPEEDWAY",
		"level": "ADVANCED",
		"shape": "quadoval",
		"straight": 560.0, "radius": 190.0, "bump": 45.0,
		"width": 18.0, "apron": 8.0, "infield": 12.0,
		"bank_turn": 24.0, "bank_straight": 5.0,
		"laps": 4, "draft": 0.7, "grid_player": 9,
		"sky_top": Color(0.35, 0.45, 0.80), "sky_horizon": Color(0.98, 0.78, 0.55),
		"grass": Color(0.42, 0.52, 0.20), "fog": Color(0.93, 0.78, 0.62),
		"lake": false, "sun_elev": 9.0, "sun_az": 205.0,
	},
	{
		"name": "THUNDER VALLEY SHORT TRACK",
		"short": "THUNDER VALLEY",
		"kind": "SHORT TRACK",
		"level": "EXPERT",
		"shape": "oval",
		"straight": 190.0, "radius": 78.0, "bump": 0.0,
		"width": 15.0, "apron": 6.0, "infield": 8.0,
		"bank_turn": 36.0, "bank_straight": 12.0,
		"laps": 8, "draft": 0.35, "grid_player": 9,
		"sky_top": Color(0.05, 0.05, 0.20), "sky_horizon": Color(0.25, 0.20, 0.40),
		"grass": Color(0.16, 0.36, 0.14), "fog": Color(0.12, 0.10, 0.22),
		"lake": false, "night": true, "sun_elev": 40.0, "sun_az": 120.0,
	},
]

## Fictional teams. speed/accel/handling are multipliers around 1.0.
var teams: Array[Dictionary] = [
	{"num": "7", "driver": "BUCK RYDER", "sponsor": "THUNDER COLA", "c1": Color(0.85, 0.08, 0.10), "c2": Color(1, 1, 1), "cn": Color(1, 1, 1), "speed": 1.00, "accel": 1.00, "handling": 1.00},
	{"num": "22", "driver": "TRAVIS HAWK", "sponsor": "BIG RIG TIRES", "c1": Color(0.10, 0.25, 0.85), "c2": Color(1.0, 0.85, 0.1), "cn": Color(1.0, 0.85, 0.1), "speed": 1.02, "accel": 0.96, "handling": 0.99},
	{"num": "51", "driver": "RICKY VANCE", "sponsor": "SIZZLE BURGERS", "c1": Color(1.0, 0.80, 0.05), "c2": Color(0.9, 0.2, 0.1), "cn": Color(0.1, 0.1, 0.1), "speed": 0.98, "accel": 1.06, "handling": 1.01},
	{"num": "14", "driver": "WADE COLTER", "sponsor": "GATOR JUICE", "c1": Color(0.10, 0.60, 0.20), "c2": Color(0.1, 0.1, 0.1), "cn": Color(1, 1, 1), "speed": 0.99, "accel": 0.98, "handling": 1.04},
	{"num": "88", "driver": "SONNY PRUITT", "sponsor": "MOTORHEAD OIL", "c1": Color(0.08, 0.08, 0.10), "c2": Color(0.95, 0.45, 0.05), "cn": Color(0.95, 0.45, 0.05), "speed": 1.03, "accel": 0.97, "handling": 0.97},
	{"num": "31", "driver": "EARL TANNER", "sponsor": "CRUNCHY O'S", "c1": Color(0.95, 0.45, 0.70), "c2": Color(0.3, 0.1, 0.5), "cn": Color(1, 1, 1), "speed": 0.98, "accel": 1.02, "handling": 1.03},
	{"num": "5", "driver": "JEB MONROE", "sponsor": "HOG WILD BBQ", "c1": Color(0.55, 0.05, 0.10), "c2": Color(0.9, 0.8, 0.6), "cn": Color(0.9, 0.8, 0.6), "speed": 1.0, "accel": 1.0, "handling": 1.0},
	{"num": "43", "driver": "MACK DALTON", "sponsor": "SKY BLUE FREIGHT", "c1": Color(0.35, 0.70, 0.95), "c2": Color(0.1, 0.2, 0.6), "cn": Color(1, 1, 1), "speed": 1.0, "accel": 1.0, "handling": 1.0},
	{"num": "66", "driver": "DWAYNE STROUD", "sponsor": "ROCKET PARTS", "c1": Color(0.95, 0.95, 0.95), "c2": Color(0.8, 0.1, 0.1), "cn": Color(0.1, 0.1, 0.8), "speed": 1.0, "accel": 1.0, "handling": 1.0},
	{"num": "12", "driver": "KYLE BARROW", "sponsor": "PRAIRIE FEED", "c1": Color(0.60, 0.40, 0.15), "c2": Color(1, 1, 0.8), "cn": Color(1, 1, 0.8), "speed": 1.0, "accel": 1.0, "handling": 1.0},
	{"num": "9", "driver": "BOBBY LEE CRANE", "sponsor": "NITRO GUM", "c1": Color(0.45, 0.10, 0.70), "c2": Color(0.2, 0.9, 0.3), "cn": Color(0.2, 0.9, 0.3), "speed": 1.0, "accel": 1.0, "handling": 1.0},
	{"num": "28", "driver": "RUSTY HOLLIS", "sponsor": "SILVER BULLET TOOLS", "c1": Color(0.70, 0.72, 0.75), "c2": Color(0.1, 0.1, 0.1), "cn": Color(0.85, 0.1, 0.1), "speed": 1.0, "accel": 1.0, "handling": 1.0},
]
## The first N teams can be picked by the player.
const SELECTABLE_TEAMS := 6

var selected_track := 0
var selected_team := 0
var scanlines := true
## "Modern" = Forward+ PBR rendering. Needs a RenderingDevice (not available on web /
## the Compatibility renderer), otherwise the game stays in 1999 mode.
var modern_supported := false
var modern := false

signal graphics_changed

var _tex := {}

var arcade_font: FontVariation
var records := ConfigFile.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	arcade_font = FontVariation.new()
	arcade_font.base_font = ThemeDB.fallback_font
	arcade_font.variation_embolden = 0.9
	# Slant the glyphs for that italic arcade cabinet look.
	arcade_font.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.22, 1), Vector2.ZERO)
	records.load(RECORDS_PATH)
	modern_supported = RenderingServer.get_rendering_device() != null
	modern = modern_supported


func toggle_graphics() -> void:
	if not modern_supported:
		return
	modern = not modern
	restyle_tree(get_tree().root)
	graphics_changed.emit()


# --- materials -------------------------------------------------------------------

## Creates a material of a given kind; style() gives it the retro or modern look.
func make_mat(kind: String, color := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.set_meta("kind", kind)
	m.set_meta("base_color", color)
	style(m)
	return m


func restyle_tree(node: Node) -> void:
	if node is GeometryInstance3D:
		var mo = node.material_override
		if mo is StandardMaterial3D and mo.has_meta("kind"):
			style(mo)
		if node is MeshInstance3D and node.mesh:
			for i in node.mesh.get_surface_count():
				var sm = node.mesh.surface_get_material(i)
				if sm is StandardMaterial3D and sm.has_meta("kind"):
					style(sm)
		if node is MultiMeshInstance3D and node.multimesh and node.multimesh.mesh:
			for i in node.multimesh.mesh.get_surface_count():
				var mm = node.multimesh.mesh.surface_get_material(i)
				if mm is StandardMaterial3D and mm.has_meta("kind"):
					style(mm)
	if node.is_in_group("retro_only"):
		node.visible = not modern
	if node.is_in_group("modern_only"):
		node.visible = modern
	for c in node.get_children():
		restyle_tree(c)


func style(m: StandardMaterial3D) -> void:
	var kind: String = m.get_meta("kind")
	var base: Color = m.get_meta("base_color", Color.WHITE)
	# Reset to a neutral state first so switching modes is lossless.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if modern else BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.albedo_color = base
	m.metallic = 0.0
	m.metallic_specular = 0.5
	m.roughness = 0.8
	m.clearcoat_enabled = false
	m.albedo_texture = null
	m.normal_enabled = false
	m.normal_texture = null
	m.roughness_texture = null
	m.uv1_triplanar = false
	m.uv1_world_triplanar = false
	m.emission_enabled = false
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	match kind:
		"paint":
			if modern:
				m.metallic = 0.35
				m.roughness = 0.24
				m.clearcoat_enabled = true
				m.clearcoat = 1.0
				m.clearcoat_roughness = 0.06
			else:
				m.roughness = 0.4
				m.metallic_specular = 0.7
		"glass":
			m.metallic = 0.7 if modern else 0.0
			m.roughness = 0.04 if modern else 0.3
			m.metallic_specular = 1.0
		"chrome":
			m.metallic = 0.95 if modern else 0.3
			m.roughness = 0.18
		"rubber":
			m.roughness = 0.95
			m.metallic_specular = 0.2
		"plastic":
			m.roughness = 0.5
		"light":
			m.emission_enabled = true
			m.emission = base
			m.emission_energy_multiplier = 3.0 if modern else 1.0
		"asphalt", "grass", "concrete", "line", "scenery":
			m.vertex_color_use_as_albedo = true
			# The palette was picked by eye, so treat it as sRGB in the linear pipeline.
			m.vertex_color_is_srgb = modern
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			if kind == "scenery" and not modern:
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			if modern:
				m.roughness = {"asphalt": 0.82, "grass": 0.95, "concrete": 0.7, "line": 0.55, "scenery": 0.8}[kind]
				if kind in ["asphalt", "grass", "concrete"]:
					m.uv1_triplanar = true
					m.uv1_world_triplanar = true
					m.uv1_triplanar_sharpness = 4.0
					var sc: float = {"asphalt": 0.35, "grass": 0.12, "concrete": 0.25}[kind]
					m.uv1_scale = Vector3(sc, sc, sc)
					m.albedo_texture = texture(kind, false)
					m.normal_enabled = true
					m.normal_texture = texture(kind, true)
					m.normal_scale = {"asphalt": 0.9, "grass": 0.6, "concrete": 0.4}[kind]
					m.albedo_color = Color(1.12, 1.12, 1.12) * base
					if kind == "grass":
						# Tame the arcade-bright greens toward real turf.
						m.albedo_color = Color(0.78, 0.74, 0.6)
		"lamp":
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = modern
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(4, 4, 3.6) if modern else Color.WHITE
		"foliage":
			m.roughness = 1.0
		"ground":
			if modern:
				m.roughness = 0.95
				m.uv1_triplanar = true
				m.uv1_world_triplanar = true
				m.uv1_scale = Vector3(0.05, 0.05, 0.05)
				m.albedo_texture = texture("grass", false)
				m.normal_enabled = true
				m.normal_texture = texture("grass", true)
				m.normal_scale = 0.5
				m.albedo_color = base.darkened(0.3).lerp(Color(0.3, 0.3, 0.2), 0.3)
		"water":
			m.metallic_specular = 1.0
			m.roughness = 0.05 if modern else 0.1
			m.metallic = 0.3 if modern else 0.0


## Procedural, tileable surface textures (shared, generated once).
func texture(kind: String, normal: bool) -> Texture2D:
	var key := kind + ("_n" if normal else "")
	if _tex.has(key):
		return _tex[key]
	var noise := FastNoiseLite.new()
	noise.seed = hash(kind)
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = noise
	var ramp := Gradient.new()
	match kind:
		"asphalt":
			noise.noise_type = FastNoiseLite.TYPE_VALUE
			noise.frequency = 0.35
			noise.fractal_octaves = 3
			ramp.set_color(0, Color(0.62, 0.62, 0.63))
			ramp.set_color(1, Color(1.0, 1.0, 1.0))
		"grass":
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			noise.frequency = 0.06
			noise.fractal_octaves = 5
			ramp.set_color(0, Color(0.72, 0.78, 0.6))
			ramp.set_color(1, Color(1.05, 1.0, 0.9))
		_:
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			noise.frequency = 0.02
			noise.fractal_octaves = 4
			ramp.set_color(0, Color(0.85, 0.85, 0.84))
			ramp.set_color(1, Color(1.0, 1.0, 1.0))
	if normal:
		t.as_normal_map = true
		t.bump_strength = {"asphalt": 6.0, "grass": 3.0}.get(kind, 2.0)
	else:
		t.color_ramp = ramp
	_tex[key] = t
	return t


func _setup_input() -> void:
	# ints are keyboard keys, "btn:N" joypad buttons, "axis:N+/-" joypad axes.
	var binds := {
		"accelerate": [KEY_UP, KEY_W, KEY_Z, "btn:%d" % JOY_BUTTON_A, "axis:%d+" % JOY_AXIS_TRIGGER_RIGHT],
		"brake": [KEY_DOWN, KEY_S, KEY_X, "btn:%d" % JOY_BUTTON_B, "axis:%d+" % JOY_AXIS_TRIGGER_LEFT],
		"steer_left": [KEY_LEFT, KEY_A, "btn:%d" % JOY_BUTTON_DPAD_LEFT, "axis:%d-" % JOY_AXIS_LEFT_X],
		"steer_right": [KEY_RIGHT, KEY_D, "btn:%d" % JOY_BUTTON_DPAD_RIGHT, "axis:%d+" % JOY_AXIS_LEFT_X],
		"menu_up": [KEY_UP, KEY_W, "btn:%d" % JOY_BUTTON_DPAD_UP],
		"menu_down": [KEY_DOWN, KEY_S, "btn:%d" % JOY_BUTTON_DPAD_DOWN],
		"start": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, "btn:%d" % JOY_BUTTON_START, "btn:%d" % JOY_BUTTON_A],
		"back": [KEY_BACKSPACE, "btn:%d" % JOY_BUTTON_B],
		"camera": [KEY_C, "btn:%d" % JOY_BUTTON_Y],
		"pause": [KEY_ESCAPE, KEY_P, "btn:%d" % JOY_BUTTON_BACK],
		"quit_race": [KEY_Q],
		"toggle_scanlines": [KEY_F2],
		"toggle_graphics": [KEY_F3],
		"toggle_fullscreen": [KEY_F11],
	}
	for action in binds:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		for b in binds[action]:
			var ev: InputEvent
			if b is String and b.begins_with("axis:"):
				var jm := InputEventJoypadMotion.new()
				jm.axis = int(b.substr(5, b.length() - 6)) as JoyAxis
				jm.axis_value = -1.0 if b.ends_with("-") else 1.0
				ev = jm
			elif b is String:
				var jb := InputEventJoypadButton.new()
				jb.button_index = int(b.substr(4)) as JoyButton
				ev = jb
			else:
				var k := InputEventKey.new()
				k.physical_keycode = b as Key
				ev = k
			InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_graphics"):
		toggle_graphics()
	if event.is_action_pressed("toggle_fullscreen"):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


func track() -> Dictionary:
	return tracks[selected_track]


func get_record(track_idx: int, key: String) -> float:
	return records.get_value("track_%d" % track_idx, key, 0.0)


## Stores `value` if it beats the existing record (lower is better). Returns true on a new record.
func submit_record(track_idx: int, key: String, value: float) -> bool:
	var old := get_record(track_idx, key)
	if old > 0.0 and old <= value:
		return false
	records.set_value("track_%d" % track_idx, key, value)
	records.save(RECORDS_PATH)
	return true


static func format_time(t: float) -> String:
	if t <= 0.0:
		return "--'--\"--"
	var m := int(t / 60.0)
	var s := int(t) % 60
	var cs := int(fmod(t, 1.0) * 100.0)
	return "%d'%02d\"%02d" % [m, s, cs]


static func ordinal(n: int) -> String:
	if n % 100 in [11, 12, 13]:
		return "%dTH" % n
	match n % 10:
		1: return "%dST" % n
		2: return "%dND" % n
		3: return "%dRD" % n
	return "%dTH" % n


func make_label(text: String, size: int, color := Color.WHITE, outline := 6) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = arcade_font
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = Color(0, 0, 0)
	ls.shadow_size = 0
	ls.shadow_color = Color(0, 0, 0, 0.6)
	ls.shadow_offset = Vector2(3, 3)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
