extends Node3D
## A stock car. Physics runs entirely in track space (s, d, yaw) which keeps the
## handling predictable and arcade-like while the banking comes for free.

const LENGTH := 4.9
const WIDTH := 1.9
const HALF_W := 0.95
const GEAR_TOPS := [22.0, 42.0, 62.0, 999.0]

var team: Dictionary
var is_player := false
var track: Node3D

# Track-space state
var dist := 0.0 # total distance travelled along the centre line; laps = floor(dist / L)
var d := 0.0
var yaw := 0.0
var v := 0.0

# Controls (0..1, steer -1..1)
var throttle := 0.0
var brake := 0.0
var steer_in := 0.0
var steer := 0.0

# Tuning (scaled by team stats)
var top_speed := 90.0
var accel := 9.0
var mu := 1.0

# Race info
var draft := 0.0
var scrub := 0.0
var wall_hit := 0.0 # impact strength this frame (for sfx/shake)
var bump := 0.0
var scraping := false
var on_grass := false
var finished := false
var finish_time := 0.0
var finish_order := 0
var best_lap := 0.0
var lap_start_time := 0.0
var last_lap := 0.0
var lap_idx := -1
var rubber := 1.0
var pace_mode := false
var pace_speed := 0.0
var pace_lane := 0.0

# AI
var ai := true
var ai_lane := 0.0
var ai_lane_timer := 0.0
var ai_skill := 1.0

var model: Node3D
var sparks: CPUParticles3D
var wheels: Array[Node3D] = []
var wheel_spin := 0.0


func setup(t: Dictionary, trk: Node3D) -> void:
	team = t
	track = trk
	top_speed = 90.0 * float(t.speed)
	accel = 9.0 * float(t.accel)
	mu = 1.0 * float(t.handling)
	_build_model()


func s() -> float:
	return fposmod(dist, track.length)


func lap() -> int:
	return int(floor(dist / track.length))


func gear() -> int:
	var av: float = abs(v)
	for g in GEAR_TOPS.size():
		if av < GEAR_TOPS[g]:
			return g + 1
	return 4


func rpm() -> float:
	var g := gear()
	var lo: float = 0.0 if g == 1 else GEAR_TOPS[g - 2]
	var hi: float = GEAR_TOPS[g - 1] if g < 4 else top_speed * 1.08
	var t: float = clamp((abs(v) - lo) / max(hi - lo, 1.0), 0.0, 1.0)
	return 3000.0 + t * 6000.0 + throttle * 400.0


func step(delta: float) -> void:
	wall_hit = 0.0
	bump = max(bump - delta * 4.0, 0.0)
	var L: float = track.length
	var ss := s()
	var k: float = track.curvature_at(ss)

	if pace_mode:
		# Rolling start formation: glide to the assigned lane at pace speed.
		v = move_toward(v, pace_speed, 6.0 * delta)
		d = move_toward(d, pace_lane, 1.5 * delta)
		yaw = 0.0
		dist += v * delta / (1.0 + k * d)
		steer = 0.0
		_update_visual(delta)
		return

	on_grass = d < track.apron_edge()
	var grip_mu := mu * (0.55 if on_grass else 1.0)
	var lat_limit: float = track.grip_limit(ss, grip_mu)

	# Longitudinal
	var vmax := top_speed * rubber * (1.0 + 0.075 * draft * float(track.cfg.draft))
	var a := 0.0
	if v >= 0.0:
		a += throttle * accel * max(1.0 - v / vmax, -0.6)
		a -= brake * 15.0
		a -= 0.8 + 1.5 * pow(v / top_speed, 2) * (1.0 - throttle)
		if on_grass:
			a -= 0.03 * v * v / 10.0 + 2.0
		v += a * delta
		if v < 0.0 and brake < 0.5:
			v = 0.0
		if v < 0.0 and brake >= 0.5:
			v = max(v, -0.1)
	else:
		# Reversing (hold brake when stopped)
		v += (brake * -6.0 + throttle * 12.0 + 2.0) * delta
		v = clamp(v, -8.0, 0.0)
		if throttle > 0.5 and v > -0.2:
			v = 0.0

	# Steering. Keyboard input ramps in, and full lock shrinks with speed.
	var ramp := 3.5 if abs(steer_in) > abs(steer) else 6.0
	steer = move_toward(steer, steer_in, ramp * delta)
	var av: float = max(abs(v), 0.1)
	var rate: float = steer * _steer_rate(lat_limit) * sign(v if v != 0.0 else 1.0)
	var lat_acc: float = abs(rate) * av
	scrub = 0.0
	if lat_acc > lat_limit:
		scrub = (lat_acc - lat_limit) / lat_limit
		rate = sign(rate) * lat_limit / av
		v -= sign(v) * min(scrub * 9.0, 12.0) * delta
	# Understeer drift if the car simply cannot carry this speed around the turn.
	var need: float = abs(k) * av * av
	if need > lat_limit * 1.02 and abs(steer) > 0.2:
		scrub = max(scrub, (need - lat_limit) / lat_limit)

	var ds := v * cos(yaw) / (1.0 + k * d)
	var dd := v * sin(yaw)
	yaw += (k * ds + rate) * delta
	# Mild self-aligning so the car settles on straights.
	if abs(steer_in) < 0.05:
		yaw -= yaw * min(1.2 * delta, 1.0) * clamp(av / 20.0, 0.0, 1.0)
	yaw = clamp(yaw, -1.1, 1.1)
	dist += ds * delta
	d += dd * delta

	# Walls
	scraping = false
	var dmax: float = track.outer_edge() - HALF_W
	var dmin: float = track.inner_wall() + HALF_W
	if d > dmax:
		d = dmax
		_hit_wall(1.0)
	elif d < dmin:
		d = dmin
		_hit_wall(-1.0)

	# Lap timing handled by race manager; clamp absurd values.
	if dist < -L:
		dist += L
	_update_visual(delta)


func _steer_rate(lat_limit: float) -> float:
	var av: float = max(abs(v), 0.1)
	return min(1.5, lat_limit * 1.3 / av) * clamp(av / 6.0, 0.0, 1.0)


func max_steer_rate() -> float:
	var grip_mu := mu * (0.55 if d < track.apron_edge() else 1.0)
	return _steer_rate(track.grip_limit(s(), grip_mu))


func _hit_wall(side: float) -> void:
	scraping = true
	var into: float = sin(yaw) * side
	if into > 0.0:
		var impact: float = into * abs(v)
		wall_hit = impact
		v *= 1.0 - clamp(into * 1.4, 0.04, 0.6)
		yaw = -yaw * 0.25
	else:
		wall_hit = max(wall_hit, 0.5)
	v *= 1.0 - 0.25 * get_physics_process_delta_time()
	yaw -= side * 0.02


func _update_visual(delta: float) -> void:
	if track == null:
		return
	var tr: Transform3D = track.car_transform(s(), d, yaw)
	# Body roll & pitch for some 90s wobble.
	var roll: float = -steer * clamp(abs(v) / 80.0, 0.0, 1.0) * 0.05
	var pitch: float = (brake - throttle * 0.4) * 0.015 * clamp(abs(v) / 30.0, 0.0, 1.0)
	model.transform = Transform3D(Basis.from_euler(Vector3(pitch, 0.0, roll)), Vector3(0, 0, 0))
	global_transform = tr
	wheel_spin += v * delta / 0.36
	for w in wheels:
		w.rotation.x = -wheel_spin
	if sparks:
		sparks.emitting = scraping and abs(v) > 12.0
		sparks.position.x = HALF_W * sign(d)


func sync_visual() -> void:
	_update_visual(0.0)


# --- model ---------------------------------------------------------------------

func _add_box(size: Vector3, p: Vector3, m: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = p
	(parent if parent else model).add_child(mi)
	return mi


func _build_model() -> void:
	model = Node3D.new()
	add_child(model)
	var c1: Color = team.c1
	var c2: Color = team.c2
	var body := Game.make_mat("paint", c1)
	var trim := Game.make_mat("paint", c2)
	var glass := Game.make_mat("glass", Color(0.06, 0.08, 0.11))
	var black := Game.make_mat("plastic", Color(0.05, 0.05, 0.05))
	var tire := Game.make_mat("rubber", Color(0.07, 0.07, 0.07))
	var light := Game.make_mat("light", Color(1.0, 0.92, 0.6))
	# lower body and nose / tail slopes
	_add_box(Vector3(1.9, 0.55, 4.9), Vector3(0, 0.55, 0), body)
	_add_box(Vector3(1.86, 0.2, 1.5), Vector3(0, 0.9, -1.65), body) # hood
	_add_box(Vector3(1.86, 0.2, 0.9), Vector3(0, 0.9, 1.95), body) # deck lid
	_add_box(Vector3(0.55, 0.02, 1.5), Vector3(0, 1.005, -1.65), trim) # hood stripe
	# greenhouse
	_add_box(Vector3(1.6, 0.5, 2.0), Vector3(0, 1.2, 0.35), glass)
	_add_box(Vector3(1.5, 0.06, 1.35), Vector3(0, 1.47, 0.45), body) # roof
	_add_box(Vector3(1.62, 0.18, 0.7), Vector3(0, 1.12, 1.05), body) # C-pillar fill
	# side stripes
	_add_box(Vector3(1.92, 0.14, 4.0), Vector3(0, 0.5, 0), trim)
	# bumpers, grille, lights
	_add_box(Vector3(1.9, 0.3, 0.12), Vector3(0, 0.38, -2.47), black)
	_add_box(Vector3(1.9, 0.3, 0.12), Vector3(0, 0.38, 2.47), black)
	_add_box(Vector3(0.35, 0.14, 0.02), Vector3(-0.6, 0.72, -2.46), light)
	_add_box(Vector3(0.35, 0.14, 0.02), Vector3(0.6, 0.72, -2.46), light)
	var tail := Game.make_mat("light", Color(0.8, 0.05, 0.05))
	_add_box(Vector3(0.45, 0.12, 0.02), Vector3(-0.55, 0.75, 2.46), tail)
	_add_box(Vector3(0.45, 0.12, 0.02), Vector3(0.55, 0.75, 2.46), tail)
	# rear spoiler
	_add_box(Vector3(1.8, 0.28, 0.05), Vector3(0, 1.12, 2.38), body)
	# wheels
	for x in [-0.86, 0.86]:
		for z in [-1.5, 1.45]:
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.36
			cm.bottom_radius = 0.36
			cm.height = 0.3
			cm.radial_segments = 8
			cm.rings = 0
			w.mesh = cm
			w.material_override = tire
			var holder := Node3D.new()
			holder.position = Vector3(x, 0.36, z)
			model.add_child(holder)
			w.rotation = Vector3(0, 0, PI * 0.5)
			var spinner := Node3D.new()
			holder.add_child(spinner)
			spinner.add_child(w)
			wheels.append(spinner)
	# numbers: roof and doors
	var num: String = team.num
	var cn: Color = team.cn
	var roof := _num_label(num, cn, 240)
	roof.position = Vector3(0, 1.505, 0.45)
	roof.rotation = Vector3(-PI * 0.5, 0, 0)
	for side in [-1.0, 1.0]:
		var door := _num_label(num, cn, 200)
		door.position = Vector3(side * 0.975, 0.72, 0.0)
		door.rotation = Vector3(0, side * PI * 0.5, 0)
		model.add_child(door)
		_add_box(Vector3(0.01, 0.5, 0.9), Vector3(side * 0.962, 0.72, 0.0), Game.make_mat("paint", Color(1, 1, 1) if cn.v < 0.5 else Color(0.05, 0.05, 0.05)))
	model.add_child(roof)
	var spon := Label3D.new()
	spon.text = team.sponsor
	spon.font = Game.arcade_font
	spon.font_size = 64
	spon.pixel_size = 0.004
	spon.modulate = c2
	spon.outline_size = 12
	spon.outline_modulate = Color(0, 0, 0)
	spon.position = Vector3(0, 1.01, -1.9)
	spon.rotation = Vector3(-PI * 0.5, 0, 0)
	spon.double_sided = false
	model.add_child(spon)
	# blob shadow
	var shadow := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.3, 5.4)
	shadow.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0, 0, 0, 0.45)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = sm
	shadow.position = Vector3(0, 0.04, 0)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Modern mode has real shadows; the blob is only for the 1999 look.
	shadow.add_to_group("retro_only")
	shadow.visible = not Game.modern
	add_child(shadow)
	# sparks
	sparks = CPUParticles3D.new()
	sparks.emitting = false
	sparks.amount = 40
	sparks.lifetime = 0.35
	sparks.local_coords = false
	sparks.direction = Vector3(0, 0.6, 1)
	sparks.spread = 35.0
	sparks.initial_velocity_min = 6.0
	sparks.initial_velocity_max = 14.0
	sparks.gravity = Vector3(0, -12, 0)
	sparks.scale_amount_min = 0.08
	sparks.scale_amount_max = 0.15
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	var spm := StandardMaterial3D.new()
	spm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spm.albedo_color = Color(1.0, 0.75, 0.2)
	spm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.material = spm
	sparks.mesh = qm
	sparks.position = Vector3(HALF_W, 0.4, 0.5)
	add_child(sparks)


func _num_label(text: String, col: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Game.arcade_font
	l.font_size = size
	l.pixel_size = 0.0035
	l.modulate = col
	l.outline_size = 24
	l.outline_modulate = Color(0, 0, 0)
	l.double_sided = false
	return l
