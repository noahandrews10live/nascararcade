extends Node3D
## A Next Gen-style stock car.
##
## The car is a planar rigid body riding on the banked track surface. Position lives
## in track space (`dist` along the centre line, `d` lateral, + = towards the outside
## wall), heading `yaw` is relative to the track tangent (+ = pointing right), and the
## body-frame state is forward speed `v`, lateral speed `vy` (+ = right) and yaw rate
## `r` (+ = clockwise seen from above). Tyres use a Pacejka-style curve with a grip
## peak and fall-off, so cars can be loose, tight, spin and wreck.

const CarBody := preload("res://scripts/car_body.gd")
const LENGTH := 5.0
const WIDTH := 1.95
const HALF_L := 2.5
const HALF_W := 0.975
const MASS := 1600.0
const IZ := 3800.0
const CG_F := 1.40 # CG to front axle
const CG_R := 1.36 # CG to rear axle
const WHEELBASE := 2.76
const CG_H := 0.42
const RHO := 1.2
const G := 9.81
const TYRE_B_F := 14.0 # slip stiffness (front): peak grip at ~0.12 rad
const TYRE_B_R := 19.0 # rear is stiffer and grippier: a slightly tight, stable setup
const TYRE_C := 1.35 # shape: grip falls to ~85% when fully sliding, so slides are catchable
const RPM_PER_MPS := [260.0, 190.0, 150.0, 120.0, 100.0] # 5-speed sequential
const REDLINE := 9300.0
const FUEL_CAPACITY := 75.0 # litres (20 US gal)

var team: Dictionary
var is_player := false
var track: Node3D

# Track-space state
var dist := 0.0 # total distance along the centre line; laps = floor(dist / L)
var d := 0.0
var yaw := 0.0
var v := 0.0 # forward speed, body frame
var vy := 0.0 # lateral speed, body frame
var r := 0.0 # yaw rate

# Controls (0..1, steer -1..1)
var throttle := 0.0
var brake := 0.0
var steer_in := 0.0
var steer := 0.0
var assisted := true # steering / stability / traction assists
var manual := false
var shift_request := 0

# Car spec (scaled by team stats and track package)
var power := 708000.0 # watts at the peak (950 hp)
var cda := 1.0
var cla := 2.0
var mu := 1.0
var grip_front := 0.98 # setup balance (wedge / track bar / stagger all end up here)
var grip_rear := 1.07
var wear_mult := 1.0 # tyre pressure trade-off
var gear_scale := 1.0 # gearing: >1 shorter (more accel, lower top speed)
var gear_track := 1.0 # the track's gear package (superspeedways run tall gears)
var damage_mult := 1.0 # 0 = damage off
var pit_crew_mult := 1.0 # career pit crew upgrades
var gear := 1
var rpm_now := 3000.0

# Aero from other cars (set by the race each frame)
var drag_mult := 1.0
var df_front_mult := 1.0
var draft := 0.0 # 0..1, for the HUD

# Condition
var damage := {"front": 0.0, "rear": 0.0, "left": 0.0, "right": 0.0}
var tyre_wear := 0.0 # 0 = new
var fuel := FUEL_CAPACITY
var out := false # wrecked / retired
var out_reason := ""

# Per-frame feedback
var scrub := 0.0
var slide := 0.0 # rear slip beyond the grip peak, 0..1+
var wall_hit := 0.0
var bump := 0.0
var scraping := false
var on_grass := false
var spinning := false

# Race info
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

# Race control
var pit_state := 0 # race_control.Pit
var pit_timer := 0.0
var pit_plan := "4" # "4", "2" or "F"
var want_pit := false
var pitted_this_caution := false
var kin_v := 0.0 # pit road target speed / lane (automatic pit road driving)
var kin_d := 0.0
var towed := false
var stage_points := 0
var laps_led := 0
var burn_scale := 1.0
var ai_driving_caution_choice := false
var autopilot_forced := false

# AI
var ai := true
var ai_lane := 0.0
var ai_lane_timer := 0.0
var ai_skill := 1.0
var ai_aggression := 0.5
var ai_r_des := 0.0 # AI asks the steering assist for a yaw rate
var ai_stuck := 0.0
var ai_reverse := 0.0

var model: Node3D
var _retro: Node3D
var _body := {}
var _dented_at := 0.0
var _haze: MeshInstance3D
var _haze_s := -1.0
static var _haze_mat: ShaderMaterial
var sparks: CPUParticles3D
var smoke: GeometryInstance3D
var tyre_smoke: GeometryInstance3D
var wheels: Array[Node3D] = []
var panels: Array[MeshInstance3D] = []
var wheel_spin := 0.0
var _delta_f := 0.0 # current front wheel angle
var dbg := []
var _tr_prev := Transform3D()
var _tr_cur := Transform3D()
var _has_tr := false
var _tr_frame := 0
var nb: Array = [] # neighbours [car, gap, ...] from race.gd
var r_max_now := 1.0 # yaw rate the grip allows right now (for the AI)
var _fy_f_prev := 0.0
var _fy_r_prev := 0.0
var _r_ref := 0.0
var _steer_int := 0.0


func setup(t: Dictionary, trk: Node3D) -> void:
	team = t
	track = trk
	var pkg: Dictionary = trk.cfg if trk else {}
	power = float(pkg.get("hp", 670)) * 745.7 * float(t.get("speed", 1.0))
	cda = float(pkg.get("cda", 1.0)) / pow(float(t.get("speed", 1.0)), 0.5)
	cla = float(pkg.get("cla", 2.2))
	gear_track = float(pkg.get("gear", 1.0))
	mu = 1.0 * float(t.get("handling", 1.0))
	_build_model()


func s() -> float:
	return fposmod(dist, track.length)


func lap() -> int:
	return int(floor(dist / track.length))


func speed() -> float:
	return sqrt(v * v + vy * vy)


func rpm() -> float:
	return rpm_now


func total_damage() -> float:
	return (damage.front + damage.rear + damage.left + damage.right) * 0.25


func tyre_grip() -> float:
	return 1.0 - 0.14 * clamp(tyre_wear, 0.0, 1.5)


func _engine_power(rpm_v: float) -> float:
	# Broad V8 curve peaking near 8,500 rpm.
	var x: float = (rpm_v - 8500.0) / 6500.0
	return power * clamp(1.0 - x * x, 0.2, 1.0)


func _auto_shift() -> void:
	var u: float = abs(v)
	if manual and is_player:
		if shift_request != 0:
			gear = clamp(gear + shift_request, 1, 5)
			shift_request = 0
		return
	if gear < 5 and u * RPM_PER_MPS[gear - 1] * gear_scale * gear_track > 9000.0:
		gear += 1
	elif gear > 1 and u * RPM_PER_MPS[gear - 2] * gear_scale * gear_track < 8200.0:
		gear -= 1


## Pacejka-ish lateral force for a slip angle, as a fraction of the grip limit.
static func _tyre(alpha: float, stiff: float) -> float:
	return sin(TYRE_C * atan(stiff * alpha))


func _mu_eff(load_ratio: float) -> float:
	# Tyres lose relative grip as load rises (why real cars lift at banked tracks).
	var surf := 1.0
	if on_grass:
		surf = 0.5
	elif d < track.inner_edge():
		surf = 0.95
	return mu * tyre_grip() * surf * pow(max(load_ratio, 0.3), -0.3)


func step(delta: float) -> void:
	wall_hit = 0.0
	scraping = false
	bump = max(bump - delta * 4.0, 0.0)
	var ss := s()
	var k: float = track.curvature_at(ss)

	if pace_mode:
		# Formation / caution: glide to the assigned lane at pace speed.
		v = move_toward(v, pace_speed, 6.0 * delta)
		vy = 0.0
		d = move_toward(d, pace_lane, 1.5 * delta)
		yaw = 0.0
		r = -k * cos(track.bank_at(ss)) * v
		dist += v * delta / (1.0 + k * d)
		steer = 0.0
		rpm_now = 3000.0 + v * 60.0
		_update_visual(delta)
		return

	if pit_state >= 2:
		# Pit road (automatic): follow race control's speed and lane directly.
		v = move_toward(v, kin_v, (9.0 if kin_v < v else 5.0) * delta)
		vy = 0.0
		r = -k * v
		var dd: float = clamp(kin_d - d, -3.0 * delta, 3.0 * delta)
		d += dd
		yaw = lerp(yaw, clamp(dd / max(v * delta, 0.01), -0.3, 0.3), min(6.0 * delta, 1.0))
		dist += v * delta / (1.0 + k * d)
		throttle = 0.4 if kin_v > v else 0.0
		brake = 0.3 if kin_v < v else 0.0
		rpm_now = clamp(v * RPM_PER_MPS[1], 2800.0, 9000.0)
		gear = 2
		_update_visual(delta)
		return

	if out:
		throttle = 0.0
		brake = 1.0
		steer_in = 0.0

	var steps: int = 4 if is_player else 2 # AI cars integrate at 120 Hz, yours at 240 Hz
	var h := delta / steps
	for _i in steps:
		_integrate(h)
	_walls()
	# Wear and fuel
	var travelled: float = abs(v) * delta
	tyre_wear += travelled / 1000.0 * (0.006 + 0.08 * slide * slide + 0.01 * scrub) * burn_scale * wear_mult
	fuel = max(0.0, fuel - travelled / 1000.0 * 0.62 * (0.3 + 0.7 * throttle) * burn_scale)
	spinning = abs(yaw) > 0.6 and speed() > 8.0
	if total_damage() > 0.72 and not out:
		out = true
		out_reason = "ACCIDENT"
	_update_visual(delta)


func _integrate(h: float) -> void:
	var ss := s()
	var k: float = track.curvature_at(ss)
	var b: float = track.bank_at(ss)
	if d < track.inner_edge():
		b = atan(0.35 / track.apron) if d > track.apron_edge() else 0.0
	var on_pit_road: bool = track.in_pit_roadway(ss) and d > track.pit_lane_d() - track.infield * 0.4
	on_grass = d < track.apron_edge() and not on_pit_road
	var u: float = v
	var au: float = max(abs(u), 3.0)

	# --- engine / gearbox
	_auto_shift()
	rpm_now = clamp(abs(u) * RPM_PER_MPS[gear - 1] * gear_scale * gear_track, 2800.0, REDLINE + 200.0)
	var dmg_power: float = 1.0 - 0.45 * clamp(damage.front - 0.35, 0.0, 1.0)
	var p_avail: float = _engine_power(rpm_now) * dmg_power
	if rpm_now >= REDLINE or fuel <= 0.0:
		p_avail = 0.0
	var fx_drive: float = throttle * p_avail * 0.88 / max(abs(u), 4.0)
	var fx_brake: float = brake * 2.3 * MASS * G * (1.0 if u > 0.3 else 0.0)
	var reverse := false
	if u <= 0.3 and brake > 0.5 and throttle < 0.1 and ((is_player and not ai) or ai_reverse > 0.0):
		# Hold brake when stopped to reverse off a wall.
		reverse = true
		fx_brake = 0.0
		fx_drive = -brake * 0.25 * MASS * G if u > -6.0 else 0.0

	# --- aero
	var dmg_aero: float = damage.front + damage.rear
	var q: float = 0.5 * RHO * u * u
	var f_drag: float = q * cda * drag_mult * (1.0 + 0.35 * dmg_aero) * sign(u)
	var f_down: float = q * cla * (1.0 - 0.3 * dmg_aero)
	var f_down_front: float = f_down * 0.45 * df_front_mult
	var f_down_rear: float = f_down * 0.55

	# --- normal loads on the banked surface
	var n_body: float = MASS * (G * cos(b) + u * u * k * sin(b))
	n_body = max(n_body, MASS * 2.0)
	var ax_est: float = (fx_drive - fx_brake - f_drag) / MASS
	var transfer: float = MASS * ax_est * CG_H / WHEELBASE
	var nf: float = max(n_body * CG_R / WHEELBASE - transfer + f_down_front, 500.0)
	var nr: float = max(n_body * CG_F / WHEELBASE + transfer + f_down_rear, 500.0)
	var load_ratio: float = (nf + nr) / (MASS * G)
	var m_eff: float = _mu_eff(load_ratio)
	var cap_f: float = m_eff * nf * grip_front
	var cap_r: float = m_eff * nr * grip_rear

	# --- steering
	var steer_ramp: float = 3.5 if abs(steer_in) > abs(steer) else 6.0
	steer = move_toward(steer, steer_in, steer_ramp * h)
	var max_delta: float = 0.35 / (1.0 + au / 18.0)
	var alpha_r: float = atan2(vy - r * CG_R, au)
	var delta_f: float
	if assisted:
		# The wheel asks for a yaw rate; the assist finds the steering angle and
		# counter-steers slides. Grip limits still apply.
		# Banking helps turn the car too, so count its in-plane gravity.
		var lat_cap: float = (cap_f + cap_r) / MASS + G * abs(sin(b))
		var r_max: float = min(lat_cap * (1.1 if ai else 1.2) / au, 1.6)
		r_max_now = lat_cap * 1.05 / au
		var r_des: float = clamp(ai_r_des, -r_max, r_max) if (ai and ai_reverse <= 0.0) else steer * r_max
		_r_ref = r_des
		# Proportional + integral: like a driver winding on more lock until the car
		# actually rotates at the rate asked for.
		_steer_int = clamp(_steer_int + (r_des - r) * h * 0.8, -0.06, 0.06)
		if abs(v) < 5.0:
			_steer_int = 0.0
		delta_f = r_des * WHEELBASE / au + 0.3 * (r_des - r) + _steer_int
		# Catch the slide: counter-steer as the rear breaks away.
		if abs(alpha_r) > 0.06:
			delta_f += -(alpha_r - 0.06 * sign(alpha_r)) * 1.2
		delta_f = clamp(delta_f, -max_delta * 1.6, max_delta * 1.6)
	else:
		delta_f = steer * max_delta
	# Damage bends the toe: the car pulls to the damaged side.
	delta_f += (damage.right - damage.left) * 0.012
	_delta_f = delta_f

	# --- tyre forces (friction circle)
	var fx_f: float = -fx_brake * 0.64
	var fx_r: float = fx_drive - fx_brake * 0.36
	if assisted and not reverse:
		# Traction control / ABS: only use the grip cornering isn't already using.
		var spare_r: float = sqrt(max(cap_r * cap_r - pow(_fy_r_prev * 1.15, 2.0), pow(cap_r * 0.2, 2.0)))
		var spare_f: float = sqrt(max(cap_f * cap_f - pow(_fy_f_prev * 1.15, 2.0), pow(cap_f * 0.25, 2.0)))
		fx_r = clamp(fx_r, -spare_r * 0.6, spare_r * 0.9)
		fx_f = max(fx_f, -spare_f * 0.9)
	fx_f = clamp(fx_f, -cap_f, cap_f)
	fx_r = clamp(fx_r, -cap_r, cap_r)
	var lat_f: float = sqrt(max(cap_f * cap_f - fx_f * fx_f, 0.0))
	var lat_r: float = sqrt(max(cap_r * cap_r - fx_r * fx_r, 0.0))
	var alpha_f: float = atan2(vy + r * CG_F, au) - delta_f
	var fy_f: float = -lat_f * _tyre(alpha_f, TYRE_B_F)
	var fy_r: float = -lat_r * _tyre(alpha_r, TYRE_B_R)
	dbg = [alpha_f, alpha_r, fy_f, fy_r, lat_f, lat_r, delta_f, nf, nr]
	_fy_f_prev = fy_f
	_fy_r_prev = fy_r
	scrub = clamp((abs(alpha_f) - 0.1) * 6.0, 0.0, 1.0)
	slide = clamp((abs(alpha_r) - 0.1) * 5.0, 0.0, 2.0)

	# --- in-plane gravity (downhill = towards the inside)
	var g_along: float = -G * sin(b) * sin(yaw)
	var g_right: float = -G * sin(b) * cos(yaw)

	var roll_res: float = 0.012 * MASS * G * sign(u) if abs(u) > 0.2 else 0.0
	var ax: float = (fx_f * cos(delta_f) - fy_f * sin(delta_f) + fx_r - f_drag - roll_res) / MASS + g_along
	var ay: float = (fy_f * cos(delta_f) + fx_f * sin(delta_f) + fy_r) / MASS + g_right
	var rdot: float = (CG_F * (fy_f * cos(delta_f) + fx_f * sin(delta_f)) - CG_R * fy_r) / IZ
	var u_new: float = u + (ax + r * vy) * h
	if not reverse and u > 0.0 and u_new < 0.0 and brake > 0.0:
		u_new = 0.0
	v = u_new
	vy += (ay - r * u) * h
	r += rdot * h
	# Driver skill / stability assist: gathers up small slides (a yaw moment like a
	# driver catching it). It backs off after a hard hit so real wrecks still happen.
	if assisted and abs(v) > 8.0:
		var catch_strength: float = (1.6 if ai else 1.1) * ai_skill if ai else 1.1
		catch_strength *= clamp(1.0 - (bump - 4.0) / 6.0, 0.0, 1.0)
		if abs(yaw) < 0.9:
			r += (_r_ref - r) * min(catch_strength * h, 1.0)
			vy -= vy * min(0.6 * catch_strength * h, 1.0) * clamp(abs(alpha_r) * 6.0, 0.0, 1.0)
	# Low-speed damping so stopped cars settle.
	if abs(v) < 2.0:
		vy *= 1.0 - min(6.0 * h, 1.0)
		r *= 1.0 - min(6.0 * h, 1.0)

	# --- kinematics in track space. On a banked surface the turn curves less within
	# the road plane (geodesic curvature = k * cos(bank)).
	var ds: float = (v * cos(yaw) - vy * sin(yaw)) / (1.0 + k * d)
	var dd: float = v * sin(yaw) + vy * cos(yaw)
	yaw = wrapf(yaw + (r + k * cos(b) * ds) * h, -PI, PI)
	dist += ds * h
	d += dd * h


## Velocity of the car's body in track axes (along, right).
func track_velocity() -> Vector2:
	return Vector2(v * cos(yaw) - vy * sin(yaw), v * sin(yaw) + vy * cos(yaw))


## Body offset (forward, right) -> track axes (along, right).
func body_to_track(p: Vector2) -> Vector2:
	return Vector2(p.x * cos(yaw) - p.y * sin(yaw), p.x * sin(yaw) + p.y * cos(yaw))


func track_to_body(p: Vector2) -> Vector2:
	return Vector2(p.x * cos(yaw) + p.y * sin(yaw), -p.x * sin(yaw) + p.y * cos(yaw))


## Velocity (track axes) of a point at track-axes offset `rp` from the CG.
func point_velocity(rp: Vector2) -> Vector2:
	var rb: Vector2 = track_to_body(rp)
	return body_to_track(Vector2(v - r * rb.y, vy + r * rb.x))


## Applies an impulse `j` (track axes, N*s) at track-axes offset `rp` from the CG.
func apply_impulse(j: Vector2, rp: Vector2) -> void:
	var jb: Vector2 = track_to_body(j)
	var rb: Vector2 = track_to_body(rp)
	v += jb.x / MASS
	vy += jb.y / MASS
	r += (rb.x * jb.y - rb.y * jb.x) / IZ


## Effective inverse mass of the car along a direction for a contact at `rp`.
func inv_mass_along(n: Vector2, rp: Vector2) -> float:
	var c: float = rp.x * n.y - rp.y * n.x
	return 1.0 / MASS + c * c / IZ


func add_damage(j: float, rp_track: Vector2) -> void:
	var rb: Vector2 = track_to_body(rp_track)
	var amount: float = j / (MASS * 55.0) * damage_mult
	if amount < 0.01:
		return
	if abs(rb.x) > 1.2:
		var key := "front" if rb.x > 0.0 else "rear"
		damage[key] = min(1.0, damage[key] + amount)
	if abs(rb.y) > 0.5 or abs(rb.x) <= 1.2:
		var side := "right" if rb.y > 0.0 else "left"
		damage[side] = min(1.0, damage[side] + amount * 0.8)
	_update_damage_visual()


func corners_track() -> Array[Vector2]:
	var out_c: Array[Vector2] = []
	for c in [Vector2(HALF_L, HALF_W), Vector2(HALF_L, -HALF_W), Vector2(-HALF_L, HALF_W), Vector2(-HALF_L, -HALF_W)]:
		out_c.append(body_to_track(c))
	return out_c


func _walls() -> void:
	var outer: float = track.outer_edge()
	var inner: float = track.inner_wall()
	for side in [1.0, -1.0]:
		var deepest := 0.0
		var contact := Vector2.ZERO
		for c in corners_track():
			var pen: float = (d + c.y - outer) if side > 0.0 else (inner - (d + c.y))
			if pen > deepest:
				deepest = pen
				contact = c
		if deepest <= 0.0:
			continue
		scraping = true
		var n := Vector2(0, -side) # points back onto the track
		var vp: Vector2 = point_velocity(contact)
		var vn: float = vp.dot(n)
		d -= side * deepest
		if vn < 0.0:
			var j: float = -(1.0 + 0.25) * vn / inv_mass_along(n, contact)
			var t := Vector2(1, 0)
			var vt: float = vp.dot(t)
			var jt: float = clamp(-vt / inv_mass_along(t, contact), -0.35 * j, 0.35 * j)
			apply_impulse(n * j + t * jt, contact)
			wall_hit = max(wall_hit, -vn)
			add_damage(j, contact)
		else:
			wall_hit = max(wall_hit, 0.5)
			# grinding along the wall
			v *= 1.0 - 0.15 / 60.0


## `snap` = teleported (grid, restart): don't blend from the old spot.
func sync_visual(snap := true) -> void:
	_update_visual(0.0)
	if snap:
		_tr_prev = _tr_cur


## Called every rendered frame: places the car between its last two physics
## positions, so motion is smooth at any refresh rate (physics runs at 60 Hz).
func interpolate(f: float) -> void:
	if not _has_tr:
		return
	# Not moved on the latest physics frame (paused, parked): sit still.
	if _tr_frame != Engine.get_physics_frames():
		f = 1.0
	global_transform = _tr_prev.interpolate_with(_tr_cur, f)


func _update_visual(delta: float) -> void:
	if track == null:
		return
	var tr: Transform3D = track.car_transform(s(), d, yaw)
	# Body roll & pitch from the tyre loads.
	var roll: float = clamp(-r * v * 0.0022, -0.07, 0.07)
	var pitch: float = (brake - throttle * 0.4) * 0.015 * clamp(abs(v) / 30.0, 0.0, 1.0)
	model.transform = Transform3D(Basis.from_euler(Vector3(pitch, 0.0, roll)), Vector3.ZERO)
	_tr_prev = _tr_cur if _has_tr and _tr_cur.origin.distance_squared_to(tr.origin) < 400.0 else tr
	_tr_cur = tr
	_has_tr = true
	_tr_frame = Engine.get_physics_frames()
	global_transform = tr
	wheel_spin += v * delta / 0.36
	for i in wheels.size():
		wheels[i].rotation.x = -wheel_spin
		if i % 2 == 0: # front wheels
			wheels[i].get_parent().rotation.y = -_delta_f * 2.0
	if sparks:
		sparks.emitting = scraping and speed() > 12.0
		sparks.position.x = HALF_W * sign(d)
	if _haze:
		# Heat shimmer from the exhaust: strongest on the gas, fades at speed as the
		# air carries it away.
		var hs: float = throttle * (1.0 - clamp(abs(v) / 90.0, 0.0, 0.6))
		if abs(hs - _haze_s) > 0.05:
			_haze_s = hs
			_haze.set_instance_shader_parameter("strength", hs)
	if tyre_smoke:
		_set_emitting(tyre_smoke, (slide > 0.4 or scrub > 0.6 or (spinning and speed() > 6.0)) and speed() > 6.0)
	if smoke:
		_set_emitting(smoke, total_damage() > 0.3 or out)


## Only touch `emitting` when it changes (re-setting it can restart GPU particles).
static func _set_emitting(p: Node, on: bool) -> void:
	if p.get("emitting") != on:
		p.set("emitting", on)


# --- model ---------------------------------------------------------------------

func _add_box(size: Vector3, p: Vector3, m: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = p
	(parent if parent else _retro).add_child(mi)
	panels.append(mi)
	mi.set_meta("home", p)
	return mi


## Crumples body panels in proportion to the damage on that corner of the car.
func _update_damage_visual() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(team.num)
	for mi in panels:
		var home: Vector3 = mi.get_meta("home")
		var amt := 0.0
		if home.z < -1.0:
			amt += damage.front
		if home.z > 1.0:
			amt += damage.rear
		amt += damage.right if home.x > 0.2 else (damage.left if home.x < -0.2 else 0.0)
		amt = min(amt, 1.0)
		var jitter := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 0.3), rng.randf_range(-1, 1))
		mi.position = home + jitter * amt * 0.12
		mi.rotation = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * amt * 0.18
	# Rebuilding the dented body costs a little, so only when the damage has grown.
	var total := total_damage()
	if _body.size() > 0 and abs(total - _dented_at) > 0.015:
		_dented_at = total
		CarBody.dent(_body, damage, hash(team.num))


func _build_model() -> void:
	model = Node3D.new()
	add_child(model)
	# Two looks: the sculpted Modern car and the boxy 1999 one (whichever is on).
	var modern_root := Node3D.new()
	modern_root.name = "Modern"
	modern_root.add_to_group("modern_only")
	modern_root.visible = Game.modern
	model.add_child(modern_root)
	_retro = Node3D.new()
	_retro.name = "Retro"
	_retro.add_to_group("retro_only")
	_retro.visible = not Game.modern
	model.add_child(_retro)
	_body = CarBody.build(modern_root, team, model)
	if Game.forward_plus:
		if _haze_mat == null:
			_haze_mat = ShaderMaterial.new()
			_haze_mat.shader = load("res://shaders/heat_haze.gdshader")
		_haze = MeshInstance3D.new()
		var hq := QuadMesh.new()
		hq.size = Vector2(1.8, 1.1)
		_haze.mesh = hq
		_haze.material_override = _haze_mat
		_haze.position = Vector3(0, 0.75, 2.9)
		_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_haze.visibility_range_end = 45.0
		_haze.add_to_group("haze")
		modern_root.add_child(_haze)
	wheels.assign(_body.wheels)
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
	# 1999 wheels: 8-sided cylinders on the shared spinners.
	for sp in wheels:
		var w := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.36
		cm.bottom_radius = 0.36
		cm.height = 0.3
		cm.radial_segments = 8
		cm.rings = 0
		w.mesh = cm
		w.material_override = tire
		w.rotation = Vector3(0, 0, PI * 0.5)
		w.add_to_group("retro_only")
		w.visible = not Game.modern
		sp.add_child(w)
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
		_retro.add_child(door)
		_add_box(Vector3(0.01, 0.5, 0.9), Vector3(side * 0.962, 0.72, 0.0), Game.make_mat("paint", Color(1, 1, 1) if cn.v < 0.5 else Color(0.05, 0.05, 0.05)))
	_retro.add_child(roof)
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
	_retro.add_child(spon)
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
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.2
	# The spark size lives in the quad itself: particle scale doesn't reliably
	# survive billboarding, and a 1 m "spark" fills the screen.
	var qm := QuadMesh.new()
	qm.size = Vector2(0.1, 0.1)
	var spm := StandardMaterial3D.new()
	spm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Slightly over-bright so sparks catch the bloom in the Modern look.
	spm.albedo_color = Color(2.2, 1.4, 0.4) if Game.modern else Color(1.0, 0.75, 0.2)
	spm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = spm
	sparks.mesh = qm
	sparks.position = Vector3(HALF_W, 0.4, 0.5)
	add_child(sparks)
	tyre_smoke = _smoke_emitter(Color(0.85, 0.85, 0.85, 0.5), 2.5)
	tyre_smoke.position = Vector3(0, 0.3, 1.5)
	smoke = _smoke_emitter(Color(0.25, 0.25, 0.27, 0.6), 1.6)
	smoke.position = Vector3(0, 0.8, -2.0)


static var _puff: GradientTexture2D


## Soft round puff shared by all smoke emitters.
static func _puff_texture() -> GradientTexture2D:
	if _puff == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.9))
		g.set_color(1, Color(1, 1, 1, 0.0))
		_puff = GradientTexture2D.new()
		_puff.gradient = g
		_puff.fill = GradientTexture2D.FILL_RADIAL
		_puff.fill_from = Vector2(0.5, 0.5)
		_puff.fill_to = Vector2(1.0, 0.5)
		_puff.width = 64
		_puff.height = 64
	return _puff


func _smoke_emitter(col: Color, size: float) -> GeometryInstance3D:
	if Game.forward_plus:
		return _gpu_smoke(col, size)
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 28
	p.lifetime = 1.4
	p.local_coords = false
	p.direction = Vector3(0, 1, 0.3)
	p.spread = 40.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, 1.2, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, col)
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = grad
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size) * 0.6 # base puff size in the quad (see sparks)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = _puff_texture()
	qm.material = m
	p.mesh = qm
	add_child(p)
	return p


## Desktop smoke: simulated on the GPU, so it can be thicker and hang around longer
## (a spinning car leaves a proper cloud) at no CPU cost.
func _gpu_smoke(col: Color, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.emitting = false
	p.amount = 72
	p.lifetime = 2.6
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 25, 60))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0.3)
	pm.spread = 45.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0, 0.8, 0)
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.inherit_velocity_ratio = 0.35
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.9, 0.1, 0.6)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	grad.colors = PackedColorArray([Color(col.r, col.g, col.b, 0.0), col, Color(col.r, col.g, col.b, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size) * 0.6
	var m := StandardMaterial3D.new()
	# Lit, so the smoke picks up sun and shadow instead of glowing.
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.albedo_texture = _puff_texture()
	m.roughness = 1.0
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.6
	qm.material = m
	p.draw_pass_1 = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


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
