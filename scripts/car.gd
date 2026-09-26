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
# Chassis and suspension (wheel rates include the tyre's own spring)
const TW := 0.80 # half the track width
const IX := 550.0 # roll inertia
const IY := 2400.0 # pitch inertia
const C_DAMP := 5500.0
const K_BUMP := 600000.0
const ROLL_ARM := 0.40 # CG height above the roll centre
const Y_CG := -0.035 # left-side weight (about 52%)
static var WX := PackedFloat32Array([1.40, 1.40, -1.36, -1.36]) # wheel positions: FL, FR, RL, RR
static var WY := PackedFloat32Array([-0.80, 0.80, -0.80, 0.80])
const WHEEL_OF_HOLDER := [0, 2, 1, 3] # model wheel order (FL, RL, FR, RR) -> physics order
const NOMINAL_LOAD := 1600.0 * 9.81 * 0.25
const SPOOL_K := 5.0 # how hard the locked rear resists the wheels turning at different speeds
const AERO_SIDE := 3.2 # side force area (m^2)
const AERO_LIFT_SIDE := 3.0 # lift area when sideways (the roof becomes a wing)
const AERO_LIFT_BACK := 3.2 # lift area when backwards (enough to fly at ~200 mph)
# Contact points relative to the CG in car space (x right, y up, z back): tyres
# then the body's corners.
const T_WHEELS := [Vector3(-0.84, -0.42, -1.40), Vector3(0.84, -0.42, -1.40), Vector3(-0.84, -0.42, 1.36), Vector3(0.84, -0.42, 1.36)]
const T_BODY := [Vector3(-0.95, -0.28, -2.45), Vector3(0.95, -0.28, -2.45), Vector3(-0.95, -0.28, 2.45), Vector3(0.95, -0.28, 2.45),
	Vector3(-0.75, 0.9, -0.2), Vector3(0.75, 0.9, -0.2), Vector3(-0.75, 0.9, 0.9), Vector3(0.75, 0.9, 0.9),
	Vector3(-0.95, 0.5, -2.2), Vector3(0.95, 0.5, -2.2), Vector3(-0.95, 0.55, 2.2), Vector3(0.95, 0.55, 2.2)]

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
var df_rear_mult := 1.0 # a car tucked in behind takes air off the spoiler
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
# Personality (0..1): patience before forcing a pass, consistency (fewer mistakes),
# racecraft (smart lines, blocking). Rivals: who has wronged us, and how much.
var ai_patience := 0.5
var ai_consistency := 0.8
var ai_racecraft := 0.6
var rivals := {}
var _stuck_behind := 0.0
var _mistake := 0.0 # seconds left of an overcooked corner

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
# Chassis state: heave (m, + = up), pitch (rad, + = nose up), roll (rad, + = right
# side up) and their rates, relative to the static ride on the track surface.
var chassis_z := 0.0
var chassis_vz := 0.0
var chassis_pitch := 0.0
var pitch_rate := 0.0
var chassis_roll := 0.0
var roll_rate := 0.0
var airborne := false
# 3D wreck mode: a free rigid body (flips, barrel rolls, getting airborne)
var tumbling := false
var t_pos := Vector3.ZERO # CG, world
var t_vel := Vector3.ZERO
var t_basis := Basis()
var t_w := Vector3.ZERO # angular velocity, world
var _tumble_time := 0.0
var _rest_time := 0.0
var roof_flaps := false
var steer_feel := 0.0 # aligning torque from the front tyres (for force feedback)
var locked_wheels := 0 # bitmask of wheels locked under braking
var assist_level := 1.0 # 0 off, 0.5 mild, 1 full
var far_away := false # set by the race: well away from any player (cheaper physics)
var stagger := 0.01 # right rear bigger than left rear (fraction of circumference)
# Setup (the garage): wheel rates, bump stop gap, brake bias, cold pressures per side
var k_front := 90000.0
var k_rear := 75000.0
var bump_gap := 0.06 # travel to the bump stops (the car rides on them in the banking)
var brake_bias := 0.58 # share of braking on the front
var psi_l := 1.0 # cold pressure, left / right side (1 = standard)
var psi_r := 1.0
var k_arb_f := 35000.0
var k_arb_r := 6000.0
var wedge := 0.0 # cross weight, N (+ = more on LF/RR: tighter)
var _nw := PackedFloat32Array([0, 0, 0, 0]) # tyre loads
var _defl := PackedFloat32Array([0, 0, 0, 0])
var _cap := PackedFloat32Array([0, 0, 0, 0])
var _fx := PackedFloat32Array([0, 0, 0, 0])
var _fy_prev := PackedFloat32Array([0, 0, 0, 0])
var _alpha := PackedFloat32Array([0, 0, 0, 0])
var _road := PackedFloat32Array([0, 0, 0, 0])
var _road_rate := PackedFloat32Array([0, 0, 0, 0])
var _f_static := PackedFloat32Array([0, 0, 0, 0])
var _tyre_factor := PackedFloat32Array([1, 1, 1, 1]) # temperature x wear, per tyre
var _slip_power := PackedFloat32Array([0, 0, 0, 0]) # energy put into each tyre this tick
var _track_grip := 1.0
# Tyres, per corner (FL, FR, RL, RR): temperature (C), pressure (psi), wear (0 = new)
var tyre_temp := PackedFloat32Array([60, 60, 60, 60])
var tyre_psi := PackedFloat32Array([0, 0, 0, 0])
var tyre_wear4 := PackedFloat32Array([0, 0, 0, 0])
var cold_psi := 1.0 # garage pressure setting (1 = standard)
var tyre_compound := "slick" # or "wet" (road courses in the rain)
var _wet := 0.0 # how wet the track is under the car
# Tyre failures: air left in each tyre (1 = full), how fast it's leaking (per s),
# and flat spots worn in by locking a wheel.
var tyre_air := PackedFloat32Array([1, 1, 1, 1])
var tyre_leak := PackedFloat32Array([0, 0, 0, 0])
var flat_spot := PackedFloat32Array([0, 0, 0, 0])
# Engine: water temperature (C) and how much of the grille is blocked (debris,
# a torn-off sign, front damage). Running tucked up behind another car heats it too.
var engine_temp := 90.0
var grille_block := 0.0
var _overheat_time := 0.0
var dvp_clock := -1.0 # damaged vehicle policy: repair time left (s); -1 = not on the clock
signal tyre_failed(car: Node3D, wheel: int, kind: String)
var _wear_avg := 0.0
# Telemetry: tread temperature spread per tyre (inside/outside), and this lap's
# time and speed at 100 points round the lap (plus the best lap's, for a delta).
var tread_bias := PackedFloat32Array([0, 0, 0, 0])
var lap_clock := 0.0
var lap_trace := PackedFloat32Array()
var lap_speed := PackedFloat32Array()
var best_trace := PackedFloat32Array()
var best_speed := PackedFloat32Array()
var _trace_bucket := -1
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
	# Stagger sized for the track's turns (a touch under neutral: the car pushes a
	# little on throttle, like a real oval setup).
	stagger = clamp(2.0 * TW / float(pkg.get("radius", 250.0)) * 0.85, 0.003, 0.045)
	if trk and trk.turns_both_ways():
		stagger = 0.0 # road courses run equal tyres
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


## Average grip left in the tyres (temperature and wear), for the HUD and the AI.
func tyre_grip() -> float:
	return (_tyre_factor[0] + _tyre_factor[1] + _tyre_factor[2] + _tyre_factor[3]) * 0.25


## Picks up tyre changes made from outside (pit stops, challenges) and works out
## each tyre's grip from its temperature, pressure and wear.
func _update_tyres_before() -> void:
	if abs(tyre_wear - _wear_avg) > 0.00001:
		if tyre_wear <= 0.0001:
			# Fresh sticker tyres: no wear, and cold (pit stops cost grip for a lap).
			var amb: float = track.track_temp() if track else 30.0
			for i in 4:
				tyre_wear4[i] = 0.0
				tyre_temp[i] = amb + 12.0
		elif _wear_avg > 0.0:
			var f: float = tyre_wear / _wear_avg
			for i in 4:
				tyre_wear4[i] *= f
		else:
			for i in 4:
				tyre_wear4[i] = tyre_wear
		_wear_avg = tyre_wear
	for i in 4:
		var t: float = tyre_temp[i]
		# Grip peaks around 100 C: cold tyres are slick, overheated ones go greasy.
		var dt: float = (t - 100.0) / 70.0
		var temp_f: float = 1.0 - 0.12 * min(dt * dt, 1.0)
		# Hot air raises the pressure; past its sweet spot the contact patch shrinks.
		var side_psi: float = psi_l if i % 2 == 0 else psi_r
		var psi: float = 22.0 * cold_psi * side_psi * (t + 273.0) / (track.track_temp() + 273.0 if track else 303.0)
		tyre_psi[i] = psi
		var over: float = max(psi / (22.0 * 1.2) - 1.0, 0.0)
		_tyre_factor[i] = temp_f * (1.0 - 0.14 * clamp(tyre_wear4[i], 0.0, 1.5)) * (1.0 - 2.0 * over * over)
		# Lower pressure: a bigger contact patch (more grip) that wears faster.
		_tyre_factor[i] *= 1.0 + (1.0 - side_psi) * 0.3
		# A tyre going down loses nearly everything; a flat spot costs a little.
		_tyre_factor[i] *= (0.12 + 0.88 * tyre_air[i]) * (1.0 - 0.04 * flat_spot[i])


func _update_tyres_after(delta: float, travelled: float) -> void:
	var amb: float = track.track_temp()
	var cool: float = 0.004 + 0.0004 * abs(v)
	var total := 0.0
	for i in 4:
		var p_slip: float = _slip_power[i] / max(delta, 0.001)
		var p_roll: float = 0.004 * _nw[i] * abs(v)
		var t: float = tyre_temp[i]
		# Fronts run bigger slip angles for the same work, so less of it is heat.
		# Wets cook themselves on a dry track; water cools any tyre.
		var heat_mult: float = 1.0 + 2.0 * (1.0 - _wet) if tyre_compound == "wet" else 1.0
		t += ((p_slip * (0.000125 if i < 2 else 0.00021) + p_roll * 0.00012) * heat_mult - (t - amb) * cool * (1.0 + 2.0 * _wet)) * delta
		tyre_temp[i] = clamp(t, amb - 5.0, 260.0)
		var hot: float = 1.0 + max(t - 115.0, 0.0) / 20.0
		var psi_wear: float = 1.0 + (1.0 - (psi_l if i % 2 == 0 else psi_r)) * 3.5
		tyre_wear4[i] += (travelled / 1000.0 * 0.004 + _slip_power[i] * 2.2e-8 * hot) * burn_scale * wear_mult * psi_wear
		_slip_power[i] = 0.0
		total += tyre_wear4[i]
		# Locking a wheel at speed grinds a flat spot into it.
		if locked_wheels & (1 << i) and abs(v) > 15.0:
			flat_spot[i] = min(flat_spot[i] + delta * abs(v) / 60.0, 1.0)
		# Blowouts: cooked or corded tyres let go (right front most often).
		if tyre_air[i] > 0.0 and tyre_leak[i] == 0.0:
			var risk: float = max(tyre_temp[i] - 170.0, 0.0) * 0.02 + max(tyre_wear4[i] - 1.0, 0.0) * 0.6
			if risk > 0.0 and randf() < risk * delta:
				fail_tyre(i, "blowout")
		if tyre_leak[i] > 0.0:
			tyre_air[i] = max(tyre_air[i] - tyre_leak[i] * delta, 0.0)
	tyre_wear = total * 0.25
	_wear_avg = tyre_wear
	for i in 4:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		tread_bias[i] = lerp(tread_bias[i], clamp(-_fy_prev[i] / max(_cap[i], 1.0), -1.0, 1.0) * side, 0.05)
	_trace(delta)
	# Bent sheet metal rubbing a front tyre can cut it; a caved-in nose blocks the
	# grille.
	for i in 2:
		var side_dmg: float = damage.left if i == 0 else damage.right
		if side_dmg > 0.25 and abs(v) > 20.0 and randf() < (side_dmg - 0.25) * 0.015 * delta:
			fail_tyre(i, "cut")
	grille_block = max(grille_block, clamp((damage.front - 0.3) * 0.7, 0.0, 0.45))
	flat_time = flat_time + delta if has_flat() else 0.0
	_update_engine(delta)


func _trace(delta: float) -> void:
	if lap_trace.is_empty():
		lap_trace.resize(100)
		lap_speed.resize(100)
	lap_clock += delta
	var b := int(s() / track.length * 100.0) % 100
	if b != _trace_bucket:
		_trace_bucket = b
		lap_trace[b] = lap_clock
		lap_speed[b] = abs(v)


## Called by the race at the line: keep the trace of a new best lap.
func end_lap_trace(lap_time: float) -> void:
	if best_trace.is_empty() or (lap_time > 0.0 and lap_time <= best_lap + 0.001):
		best_trace = lap_trace.duplicate()
		best_speed = lap_speed.duplicate()
	lap_clock = 0.0


## Seconds up (-) or down (+) on the best lap at this point of the lap.
func lap_delta() -> float:
	if best_trace.is_empty() or _trace_bucket < 0:
		return 0.0
	return lap_clock - best_trace[_trace_bucket]


## A tyre starts losing air: "blowout" (gone in half a second) or "cut" (a slow
## leak from debris or a fender rub; the driver has a lap or two to get it in).
func fail_tyre(i: int, kind: String) -> void:
	if tyre_air[i] <= 0.0 or tyre_leak[i] > 0.0:
		return
	tyre_leak[i] = 2.5 if kind == "blowout" else randf_range(0.02, 0.06)
	tyre_failed.emit(self, i, kind)


## New tyres on the given corners (0 FL, 1 FR, 2 RL, 3 RR): no wear, full air, no
## flat spots, and cold.
func change_tyres(corners: Array, compound := "") -> void:
	var amb: float = track.track_temp() if track else 30.0
	if compound != "":
		tyre_compound = compound
	for i in corners:
		tyre_wear4[i] = 0.0
		tyre_air[i] = 1.0
		tyre_leak[i] = 0.0
		flat_spot[i] = 0.0
		tyre_temp[i] = amb + 12.0
	tyre_wear = (tyre_wear4[0] + tyre_wear4[1] + tyre_wear4[2] + tyre_wear4[3]) * 0.25
	_wear_avg = tyre_wear


var flat_time := 0.0 # how long a tyre has been down (drivers take a moment to react)


func has_flat() -> bool:
	for i in 4:
		if tyre_air[i] < 0.6:
			return true
	return false


## Water temperature: heat from the engine working, cooled by air through the
## grille. Tucked up behind another car (dirty air) or with the grille blocked it
## climbs; past ~125 C the engine is protected (less power), past 145 C it fails.
func _update_engine(delta: float) -> void:
	var airflow: float = clamp(abs(v) / 80.0, 0.15, 1.2) * (1.0 - grille_block) * (1.0 - 0.12 * clamp(draft, 0.0, 1.0)) * (1.0 - 0.4 * clamp(damage.front - 0.2, 0.0, 1.0))
	var heat: float = (0.25 + 0.75 * throttle) * 2.4
	engine_temp += (heat - (engine_temp - 40.0) * airflow * 0.037) * delta
	engine_temp = clamp(engine_temp, 40.0, 170.0)
	# In clean air at speed, debris on the grille can blow off (drivers pull out of
	# line to clear it).
	if grille_block > 0.0 and grille_block < 0.4 and draft < 0.1 and abs(v) > 55.0:
		grille_block = max(grille_block - 0.012 * delta, 0.0)
	if engine_temp > 145.0:
		_overheat_time += delta
		if _overheat_time > 10.0 and not out:
			out = true
			out_reason = "ENGINE"
	else:
		_overheat_time = max(_overheat_time - delta, 0.0)


## Engine protection when hot.
func engine_derate() -> float:
	return clamp(1.0 - (engine_temp - 125.0) / 60.0, 0.5, 1.0)


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


## Corner loads on the springs at 1 g: front/rear from the CG position, 52% on the
## left side, and wedge (cross weight) moved between the diagonals.
func _update_static_loads() -> void:
	var front: float = MASS * G * CG_R / WHEELBASE * 0.5
	var rear: float = MASS * G * CG_F / WHEELBASE * 0.5
	var df: float = MASS * G * (CG_R / WHEELBASE) * Y_CG / TW * 0.5
	var dr: float = MASS * G * (CG_F / WHEELBASE) * Y_CG / TW * 0.5
	_f_static[0] = front - df + wedge
	_f_static[1] = front + df - wedge
	_f_static[2] = rear - dr - wedge
	_f_static[3] = rear + dr + wedge


func _sample_road(ss: float, h: float) -> void:
	var cy := cos(yaw)
	var sy := sin(yaw)
	for i in 4:
		var rh: float = track.road_height(ss + WX[i] * cy - WY[i] * sy, d + WY[i] * cy + WX[i] * sy)
		if flat_spot[i] > 0.05:
			# Once a wheel revolution the flat spot thumps the suspension.
			rh += flat_spot[i] * 0.004 * sin(dist / 0.36 + i)
		if tyre_air[i] < 1.0:
			rh -= (1.0 - tyre_air[i]) * 0.09 # the car sits down on the flat
		_road_rate[i] = clamp((rh - _road[i]) / h, -2.0, 2.0)
		_road[i] = rh


func reset_chassis() -> void:
	chassis_z = 0.0
	chassis_vz = 0.0
	chassis_pitch = 0.0
	pitch_rate = 0.0
	chassis_roll = 0.0
	roll_rate = 0.0
	airborne = false


func step(delta: float) -> void:
	wall_hit = 0.0
	scraping = false
	bump = max(bump - delta * 4.0, 0.0)
	var ss := s()
	var k: float = track.curvature_at(ss)

	if tumbling:
		for _i in 8:
			_integrate_tumble(delta / 8.0)
		spinning = true
		_update_visual(delta)
		return

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
		reset_chassis()
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
		reset_chassis()
		_update_visual(delta)
		return

	if out:
		throttle = 0.0
		brake = 1.0
		steer_in = 0.0

	_update_static_loads()
	_update_tyres_before()
	_track_grip = track.grip_at(ss, d)
	_wet = track.wet_at(d)
	if tyre_compound == "wet":
		_track_grip *= 0.9 - 0.08 * (1.0 - _wet) # grooved: fine in the wet, soft in the dry
	else:
		_track_grip *= 1.0 - 0.42 * _wet # slicks aquaplane
	# Your car integrates at 240 Hz, cars around you at 120 Hz, distant ones at 60 Hz.
	var steps: int = 4 if is_player else (1 if far_away and slide < 0.2 and bump < 1.0 else 2)
	var h := delta / steps
	if not is_player:
		_sample_road(ss, delta)
	for _i in steps:
		_integrate(h)
		if abs(chassis_roll) > 0.5 or abs(chassis_pitch) > 0.4 or (airborne and chassis_z > 0.3):
			_enter_tumble()
			for _j in 4:
				_integrate_tumble(delta / 8.0)
			spinning = true
			_update_visual(delta)
			return
	_walls()
	# Tyres heat up and wear from the work they do; fuel burns with throttle.
	var travelled: float = abs(v) * delta
	_update_tyres_after(delta, travelled)
	fuel = max(0.0, fuel - travelled / 1000.0 * 0.62 * (0.3 + 0.7 * throttle) * burn_scale)
	spinning = abs(yaw) > 0.6 and speed() > 8.0
	if total_damage() > 0.72 and not out:
		out = true
		out_reason = "ACCIDENT"
	_update_visual(delta)


## Full model: four tyres with their own loads, a spool rear axle with stagger, and
## the body moving on its springs (heave, pitch and roll) with dampers, anti-roll
## bars and bump stops. Load transfer, and so the car's balance, comes out of that.
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
	var p_avail: float = _engine_power(rpm_now) * dmg_power * engine_derate()
	if rpm_now >= REDLINE or fuel <= 0.0:
		p_avail = 0.0
	var fx_drive: float = throttle * p_avail * 0.88 / max(abs(u), 4.0)
	var fx_brake: float = brake * 2.3 * MASS * G * (1.0 if u > 0.3 else 0.0)
	var reverse := false
	if u <= 0.3 and brake > 0.5 and throttle < 0.1 and ((is_player and not ai) or ai_reverse > 0.0):
		reverse = true
		fx_brake = 0.0
		fx_drive = -brake * 0.25 * MASS * G if u > -6.0 else 0.0

	# --- aero: drag along the motion, side force, downforce that fades as the car
	# turns sideways and becomes lift when it's backwards (roof flaps cut that).
	var sp2: float = u * u + vy * vy
	var q_air: float = 0.5 * RHO * sp2
	var cb := 1.0
	var sb := 0.0
	if sp2 > 4.0:
		var spd: float = sqrt(sp2)
		cb = u / spd
		sb = vy / spd
	var dmg_aero: float = damage.front + damage.rear
	var drag: float = q_air * cda * drag_mult * (1.0 + 0.35 * dmg_aero) * (1.0 + 1.6 * sb * sb)
	var fa_x: float = -drag * cb
	var fa_y: float = -drag * sb - q_air * AERO_SIDE * sb
	var ride: float = clamp(1.0 - 2.5 * chassis_z, 0.9, 1.2) # lower = more downforce
	var df: float = 0.0
	if cb > 0.0:
		df = q_air * cla * (1.0 - 0.3 * dmg_aero) * cb * cb * ride
	var lift_side: float = q_air * AERO_LIFT_SIDE * sb * sb
	var lift_back: float = q_air * AERO_LIFT_BACK * cb * cb if cb < 0.0 else 0.0
	roof_flaps = cb < -0.6 # the flaps pop up once the car is past ~130 degrees
	if roof_flaps:
		lift_side *= 0.4
		lift_back *= 0.35
	var df_f: float = df * 0.45 * df_front_mult
	var df_r: float = df * 0.55 * df_rear_mult

	# --- road under each tyre (seams, bumps). Your car samples it every sub-step;
	# the others once a frame (see step()), which is plenty for them.
	if is_player:
		_sample_road(ss, h)

	# --- suspension: spring + damper + bump stop per corner, anti-roll bars
	var n_eff: float = max(MASS * (G * cos(b) + u * u * k * sin(b)), MASS * 2.0)
	var fz := 0.0
	var mp := 0.0
	var mr := 0.0
	for i in 4:
		var defl: float = -(chassis_z + WX[i] * chassis_pitch + WY[i] * chassis_roll) + _road[i]
		var rate: float = -(chassis_vz + WX[i] * pitch_rate + WY[i] * roll_rate) + _road_rate[i]
		var f: float = _f_static[i] + (k_front if i < 2 else k_rear) * defl + C_DAMP * rate
		if defl > bump_gap:
			f += K_BUMP * (defl - bump_gap)
		_defl[i] = defl
		_nw[i] = f
	var arb_f: float = k_arb_f * (_defl[0] - _defl[1])
	var arb_r: float = k_arb_r * (_defl[2] - _defl[3])
	_nw[0] += arb_f
	_nw[1] -= arb_f
	_nw[2] += arb_r
	_nw[3] -= arb_r
	for i in 4:
		if _nw[i] < 0.0:
			_nw[i] = 0.0
		fz += _nw[i]
		mp += _nw[i] * WX[i]
		mr += _nw[i] * WY[i]

	# --- tyre grip per corner (load sensitivity, temperature, wear, surface)
	var surf := 1.0
	if on_grass:
		surf = 0.5
	elif d < track.inner_edge():
		surf = 0.95
	surf *= _track_grip
	var cap := _cap
	for i in 4:
		var ratio: float = max(_nw[i] / NOMINAL_LOAD, 0.3)
		cap[i] = mu * surf * _tyre_factor[i] * pow(ratio, -0.3) * _nw[i] * (grip_front if i < 2 else grip_rear)
	var cap_f: float = cap[0] + cap[1]
	var cap_r: float = cap[2] + cap[3]

	# --- steering (driver input, or the yaw-rate assist)
	var steer_ramp: float = 3.5 if abs(steer_in) > abs(steer) else 6.0
	steer = move_toward(steer, steer_in, steer_ramp * h)
	var max_delta: float = 0.35 / (1.0 + au / 18.0)
	var alpha_r: float = atan2(vy - r * CG_R, au)
	var delta_f: float
	if assisted:
		var lat_cap: float = (cap_f + cap_r) / MASS + G * abs(sin(b))
		var r_max: float = min(lat_cap * (1.1 if ai else 1.2) / au, 1.6)
		r_max_now = lat_cap * 1.05 / au
		var r_des: float = clamp(ai_r_des, -r_max, r_max) if (ai and ai_reverse <= 0.0) else steer * r_max
		_r_ref = r_des
		_steer_int = clamp(_steer_int + (r_des - r) * h * 0.8, -0.06, 0.06)
		if abs(v) < 5.0:
			_steer_int = 0.0
		delta_f = r_des * WHEELBASE / au + 0.3 * (r_des - r) + _steer_int
		if abs(alpha_r) > 0.06:
			delta_f += -(alpha_r - 0.06 * sign(alpha_r)) * 1.2 * assist_level
		delta_f = clamp(delta_f, -max_delta * 1.6, max_delta * 1.6)
	else:
		delta_f = steer * max_delta
	delta_f += (damage.right - damage.left) * 0.012
	_delta_f = delta_f

	# --- longitudinal demand per tyre: brakes (58% front), drive through a spool
	# (both rears turn together; stagger lets the bigger right rear roll round the
	# turn, otherwise the spool pushes the car wide)
	var fx := _fx
	fx[0] = -fx_brake * brake_bias * 0.5
	fx[1] = -fx_brake * brake_bias * 0.5
	fx[2] = fx_drive * 0.5 - fx_brake * (1.0 - brake_bias) * 0.5
	fx[3] = fx_drive * 0.5 - fx_brake * (1.0 - brake_bias) * 0.5
	# A flat tyre drags (rim and rubber on the ground), pulling the car that way.
	for i in 4:
		if tyre_air[i] < 0.9:
			fx[i] -= (1.0 - tyre_air[i]) * 0.18 * _nw[i] * sign(u)
	var spool_slip: float = (-2.0 * r * TW) / au - stagger
	var f_sp: float = clamp(SPOOL_K * spool_slip * (_nw[2] + _nw[3]) * 0.5, -0.22 * cap_r, 0.22 * cap_r)
	fx[2] += f_sp
	fx[3] -= f_sp
	var locked := 0
	var spun := 0
	for i in 4:
		var c_i: float = cap[i]
		if assisted and not reverse:
			# ABS / traction control: only use the grip cornering isn't using.
			var spare: float = sqrt(max(c_i * c_i - pow(_fy_prev[i] * 1.15, 2.0), pow(c_i * 0.22, 2.0)))
			var lim: float = spare * (0.9 if assist_level >= 1.0 else 0.97)
			fx[i] = clamp(fx[i], -lim, lim)
		if fx[i] < -c_i:
			fx[i] = -c_i * 0.85 # locked wheel: sliding friction
			locked |= 1 << i
		elif fx[i] > c_i:
			fx[i] = c_i * 0.85 # wheelspin
			spun |= 1 << i

	# --- lateral forces (friction circle) and the totals
	var fx_tot := 0.0
	var fy_tot := 0.0
	var mz := 0.0
	var sat := 0.0
	for i in 4:
		var vxi: float = u - r * WY[i]
		var vyi: float = vy + r * WX[i]
		var dl: float = delta_f if i < 2 else 0.0
		var alpha: float = atan2(vyi, max(abs(vxi), 3.0)) - dl
		var c_i: float = cap[i]
		var lat: float = sqrt(max(c_i * c_i - fx[i] * fx[i], 0.0))
		var fyi: float
		if (locked | spun) & (1 << i):
			lat *= 0.45
		fyi = -lat * _tyre(alpha, TYRE_B_F if i < 2 else TYRE_B_R)
		_fy_prev[i] = fyi
		_alpha[i] = alpha
		# Heat from the work the tyre does: cornering slip, plus braking and drive
		# slip (what keeps road-course tyres hot); far more when locked or spinning.
		var long_slip: float = abs(fx[i]) / (40.0 * max(_nw[i], 500.0))
		if (locked | spun) & (1 << i):
			long_slip = 0.3
		_slip_power[i] += (abs(fyi * sin(alpha)) + abs(fx[i]) * long_slip) * au * h
		var fxb: float = fx[i]
		var fyb: float = fyi
		if i < 2:
			var cd := cos(dl)
			var sd := sin(dl)
			fxb = fx[i] * cd - fyi * sd
			fyb = fyi * cd + fx[i] * sd
			sat += -fyi * clamp(0.05 * (1.0 - abs(alpha) / 0.18), -0.02, 0.05)
		fx_tot += fxb
		fy_tot += fyb
		mz += WX[i] * fyb - WY[i] * fxb
	steer_feel = sat / (MASS * G * 0.05)
	locked_wheels = locked
	var alpha_f: float = (_alpha[0] + _alpha[1]) * 0.5
	scrub = clamp((abs(alpha_f) - 0.1) * 6.0, 0.0, 1.0)
	slide = clamp((abs(alpha_r) - 0.1) * 5.0, 0.0, 2.0)
	_fy_f_prev = _fy_prev[0] + _fy_prev[1]
	_fy_r_prev = _fy_prev[2] + _fy_prev[3]

	# --- in-plane gravity (downhill = towards the inside)
	var g_along: float = -G * sin(b) * sin(yaw)
	var g_right: float = -G * sin(b) * cos(yaw)
	var roll_res: float = 0.012 * MASS * G * sign(u) if abs(u) > 0.2 else 0.0
	var ax: float = (fx_tot + fa_x - roll_res) / MASS + g_along
	var ay: float = (fy_tot + fa_y) / MASS + g_right
	var rdot: float = (mz - 0.25 * q_air * AERO_SIDE * sb) / IZ

	# --- body on its springs
	var az: float = (fz - n_eff - df + lift_side + lift_back) / MASS
	var pitch_acc: float = (mp + fx_tot * CG_H - df_f * CG_F + df_r * CG_R - lift_back * 1.6) / IY
	var roll_acc: float = (mr + fy_tot * ROLL_ARM - n_eff * Y_CG + lift_side * 0.7 * sign(sb)) / IX
	if on_grass and abs(vy) > 20.0:
		# Sliding sideways in the grass at big speed the tyres dig in and can trip
		# the car over.
		roll_acc += -sign(vy) * clamp((abs(vy) - 20.0) / 12.0, 0.0, 1.0) * 30.0
	chassis_vz += az * h
	pitch_rate += pitch_acc * h
	roll_rate += roll_acc * h
	chassis_z += chassis_vz * h
	chassis_pitch += pitch_rate * h
	chassis_roll += roll_rate * h
	airborne = fz <= 0.0

	# --- planar motion
	var u_new: float = u + (ax + r * vy) * h
	if not reverse and u > 0.0 and u_new < 0.0 and brake > 0.0:
		u_new = 0.0
	v = u_new
	vy += (ay - r * u) * h
	r += rdot * h
	if assisted and abs(v) > 8.0:
		var catch_strength: float = ((1.6 if ai else 1.1) * ai_skill if ai else 1.1) * assist_level
		catch_strength *= clamp(1.0 - (bump - 4.0) / 6.0, 0.0, 1.0)
		if abs(yaw) < 0.9 and catch_strength > 0.0:
			r += (_r_ref - r) * min(catch_strength * h, 1.0)
			vy -= vy * min(0.6 * catch_strength * h, 1.0) * clamp(abs(alpha_r) * 6.0, 0.0, 1.0)
	if v * v + vy * vy < 4.0: # nearly stopped (not just sideways)
		vy *= 1.0 - min(6.0 * h, 1.0)
		r *= 1.0 - min(6.0 * h, 1.0)

	var ds: float = (v * cos(yaw) - vy * sin(yaw)) / (1.0 + k * d)
	var dd: float = v * sin(yaw) + vy * cos(yaw)
	yaw = wrapf(yaw + (r + k * cos(b) * ds) * h, -PI, PI)
	dist += ds * h
	d += dd * h


# --- 3D wreck mode -------------------------------------------------------------

## Leave the track-plane model: the car becomes a free rigid body in the world.
func _enter_tumble() -> void:
	var tr: Transform3D = track.car_transform(s(), d, yaw)
	var bb := Basis.from_euler(Vector3(chassis_pitch, 0.0, chassis_roll))
	t_basis = (tr.basis * bb).orthonormalized()
	t_pos = tr.origin + tr.basis * Vector3(0.0, CG_H + chassis_z, 0.0)
	t_vel = tr.basis * Vector3(vy, chassis_vz, -v)
	t_w = t_basis * Vector3(pitch_rate, -r, roll_rate)
	tumbling = true
	_tumble_time = 0.0
	_rest_time = 0.0
	bump = 10.0 # assists let go


func _inv_inertia_world(torque: Vector3) -> Vector3:
	var tl: Vector3 = t_basis.transposed() * torque
	return t_basis * Vector3(tl.x / IY, tl.y / IZ, tl.z / IX)


## Track position and surface frame under a world point, starting from s near it.
func _surface_under(w: Vector3, s_hint: float) -> Array:
	var p0: Vector3 = track.surface_point(s_hint, 0.0)
	var f: Vector3 = track.fwd_at(s_hint)
	var sw: float = s_hint + (w - p0).dot(f)
	var rt: Vector3 = track.right_at(sw)
	var p1: Vector3 = track.surface_point(sw, 0.0)
	var dw: float = (w - p1).dot(rt)
	var sp: Vector3 = track.surface_point(sw, dw)
	var nrm: Vector3 = track.car_transform(sw, dw, 0.0).basis.y
	return [sw, dw, sp, nrm]


func _integrate_tumble(h: float) -> void:
	_tumble_time += h
	var force := Vector3(0.0, -G * MASS, 0.0)
	var torque := Vector3.ZERO
	var spd: float = t_vel.length()
	# Aero: drag, plus lift through the roof when backwards or sideways.
	if spd > 1.0:
		var q_air: float = 0.5 * RHO * spd * spd
		force += -t_vel / spd * q_air * cda * 1.6
		var lv: Vector3 = t_basis.transposed() * t_vel / spd
		var cb: float = -lv.z # + = moving forwards
		var sb: float = lv.x
		var flaps: bool = cb < -0.6
		roof_flaps = flaps
		var up: Vector3 = t_basis.y
		if cb < 0.0:
			var lb: float = q_air * AERO_LIFT_BACK * cb * cb * (0.35 if flaps else 1.0)
			var at: Vector3 = t_basis * Vector3(0.0, 0.0, 1.6)
			force += up * lb
			torque += at.cross(up * lb)
		var ls: float = q_air * AERO_LIFT_SIDE * sb * sb * (0.4 if flaps else 1.0)
		var at2: Vector3 = t_basis * Vector3(0.7 * sign(sb), 0.0, 0.0)
		force += up * ls
		torque += at2.cross(up * ls)
	# Ground and wall contact at the tyres and the body's corners.
	var s_now := s()
	scraping = false
	var outer: float = track.outer_edge()
	var inner: float = track.inner_wall()
	for ci in 16:
		var is_tyre: bool = ci < 4
		var lp: Vector3 = T_WHEELS[ci] if is_tyre else T_BODY[ci - 4]
		var rw: Vector3 = t_basis * lp
		var w: Vector3 = t_pos + rw
		var su: Array = _surface_under(w, s_now)
		var sp: Vector3 = su[2]
		var nrm: Vector3 = su[3]
		var pen: float = (sp - w).dot(nrm)
		var vp: Vector3 = t_vel + t_w.cross(rw)
		if pen > 0.0:
			var vn: float = vp.dot(nrm)
			var k_c: float = 160000.0 if is_tyre else 320000.0
			var fn: float = max(k_c * pen - 9000.0 * vn, 0.0)
			var vt: Vector3 = vp - nrm * vn
			var vtl: float = vt.length()
			var ft := Vector3.ZERO
			if vtl > 0.01:
				var mu_c: float = 0.55
				if is_tyre:
					# Tyres roll along their heading and grip sideways.
					var roll_dir: Vector3 = (t_basis.z - nrm * t_basis.z.dot(nrm)).normalized()
					var v_roll: float = vt.dot(roll_dir)
					var v_side: Vector3 = vt - roll_dir * v_roll
					ft = -roll_dir * v_roll * 30.0 - v_side.normalized() * min(1.0 * fn, v_side.length() * 4000.0)
				else:
					ft = -vt / vtl * mu_c * fn * clamp(vtl / 0.5, 0.0, 1.0)
					if vtl > 5.0 and fn > 2000.0:
						scraping = true
			var fc: Vector3 = nrm * fn + ft
			force += fc
			torque += rw.cross(fc)
		# Outside wall and catch fence (up to 6 m), inside wall.
		var dw: float = su[1]
		var hgt: float = (w - sp).dot(nrm)
		var wall_pen := 0.0
		var wall_n := Vector3.ZERO
		if dw > outer and hgt < 6.0:
			wall_pen = dw - outer
			wall_n = -track.right_at(su[0])
		elif dw < inner and hgt < 1.2:
			wall_pen = inner - dw
			wall_n = track.right_at(su[0])
		if wall_pen > 0.0:
			var vnw: float = vp.dot(wall_n)
			var fw: float = max(300000.0 * wall_pen - 12000.0 * vnw, 0.0)
			var vtw: Vector3 = vp - wall_n * vnw
			var fwc: Vector3 = wall_n * fw - vtw.normalized() * 0.4 * fw if vtw.length() > 0.1 else wall_n * fw
			force += fwc
			torque += rw.cross(fwc)
			scraping = true
			if -vnw > 3.0:
				wall_hit = max(wall_hit, -vnw)
				add_damage(fw * h * 0.5, Vector2(lp.z * -1.0, lp.x))
	# Integrate the free body.
	t_vel += force / MASS * h
	t_pos += t_vel * h
	var wl: Vector3 = t_basis.transposed() * t_w
	var tl: Vector3 = t_basis.transposed() * torque
	var iw := Vector3(IY * wl.x, IZ * wl.y, IX * wl.z)
	var gyro: Vector3 = wl.cross(iw)
	wl += Vector3((tl.x - gyro.x) / IY, (tl.y - gyro.y) / IZ, (tl.z - gyro.z) / IX) * h
	wl *= 1.0 - 0.3 * h # air and structural damping
	t_w = t_basis * wl
	var wlen: float = t_w.length()
	if wlen > 0.0001:
		t_basis = t_basis.rotated(t_w / wlen, wlen * h).orthonormalized()
	_sync_from_tumble()
	# Back on its wheels and settled: hand back to the normal model.
	var su0: Array = _surface_under(t_pos, s())
	var nrm0: Vector3 = su0[3]
	var height: float = (t_pos - (su0[2] as Vector3)).dot(nrm0)
	var upright: float = t_basis.y.dot(nrm0)
	if _tumble_time > 0.4 and upright > 0.93 and t_w.length() < 1.2 and height < CG_H + 0.2:
		_exit_tumble(nrm0, height)
		return
	# Stopped on its roof or side: that's the end of this car's race.
	if upright < 0.5 and t_vel.length() < 1.5:
		_rest_time += h
		if _rest_time > 2.0 and not out:
			out = true
			out_reason = "FLIPPED"
	else:
		_rest_time = 0.0


## Keeps the track-space state (used by the rest of the race) following the body.
func _sync_from_tumble() -> void:
	var s_old := s()
	var su: Array = _surface_under(t_pos, s_old)
	var sw: float = su[0]
	var ds: float = sw - s_old
	if ds > track.length * 0.5:
		ds -= track.length
	elif ds < -track.length * 0.5:
		ds += track.length
	dist += ds
	d = su[1]
	var f: Vector3 = track.fwd_at(sw)
	var rt: Vector3 = track.right_at(sw)
	var head: Vector3 = -t_basis.z
	yaw = atan2(head.dot(rt), head.dot(f))
	var fwd_h: Vector3 = (f * cos(yaw) + rt * sin(yaw))
	var right_h: Vector3 = (rt * cos(yaw) - f * sin(yaw))
	v = t_vel.dot(fwd_h)
	vy = t_vel.dot(right_h)
	r = -t_w.dot(su[3])


func _exit_tumble(nrm: Vector3, height: float) -> void:
	tumbling = false
	_sync_from_tumble()
	var tr: Transform3D = track.car_transform(s(), d, yaw)
	var local: Basis = tr.basis.inverse() * t_basis
	var e: Vector3 = local.get_euler()
	chassis_pitch = clamp(e.x, -0.2, 0.2)
	chassis_roll = clamp(e.z, -0.2, 0.2)
	chassis_z = clamp(height - CG_H, -0.1, 0.2)
	chassis_vz = t_vel.dot(nrm)
	pitch_rate = 0.0
	roll_rate = 0.0


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
	if tumbling:
		var f: Vector3 = track.fwd_at(s())
		var rt: Vector3 = track.right_at(s())
		var jw: Vector3 = f * j.x + rt * j.y
		var rw: Vector3 = f * rp.x + rt * rp.y
		t_vel += jw / MASS
		t_w += _inv_inertia_world(rw.cross(jw))
		return
	var jb: Vector2 = track_to_body(j)
	var rb: Vector2 = track_to_body(rp)
	v += jb.x / MASS
	vy += jb.y / MASS
	r += (rb.x * jb.y - rb.y * jb.x) / IZ


## Vertical and rotational kick (a hard hit, a car climbing another, digging in).
## jz up (N*s), j_roll (+ = right side up) and j_pitch (+ = nose up) in N*m*s.
func kick(jz: float, j_roll: float, j_pitch: float) -> void:
	if tumbling:
		t_vel += t_basis.y * jz / MASS
		t_w += t_basis * Vector3(j_pitch / IY, 0.0, j_roll / IX)
		return
	chassis_vz += jz / MASS
	roll_rate += j_roll / IX
	pitch_rate += j_pitch / IY


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
	if d < outer - 2.8 and d > inner + 2.8:
		return # nowhere near either wall
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
	if snap:
		reset_chassis()
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
	var tr: Transform3D
	if tumbling:
		tr = Transform3D(t_basis, t_pos - t_basis * Vector3(0.0, CG_H, 0.0))
		model.transform = Transform3D()
		_tr_prev = _tr_cur if _has_tr and _tr_cur.origin.distance_squared_to(tr.origin) < 400.0 else tr
		_tr_cur = tr
		_has_tr = true
		_tr_frame = Engine.get_physics_frames()
		global_transform = tr
		if sparks:
			sparks.emitting = scraping and t_vel.length() > 8.0
		if tyre_smoke:
			_set_emitting(tyre_smoke, t_vel.length() > 6.0)
		return
	tr = track.car_transform(s(), d, yaw)
	# The body sits on its springs: heave, pitch and roll from the chassis model,
	# pivoting about the CG. The wheels stay on the ground (suspension travel).
	var pivot := Vector3(0.0, CG_H, 0.0)
	var bb := Basis.from_euler(Vector3(chassis_pitch, 0.0, chassis_roll))
	model.transform = Transform3D(bb, pivot + Vector3(0.0, chassis_z, 0.0) - bb * pivot)
	for j in wheels.size():
		var holder: Node3D = wheels[j].get_parent()
		var wi: int = WHEEL_OF_HOLDER[j]
		holder.position.y = 0.345 + clamp(_defl[wi], -0.12, 0.14) - (1.0 - tyre_air[wi]) * 0.09
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
		sparks.emitting = (scraping or (has_flat() and speed() > 8.0)) and speed() > 8.0
		sparks.position.x = HALF_W * sign(d)
	if _haze:
		# Heat shimmer from the exhaust: strongest on the gas, fades at speed as the
		# air carries it away.
		var hs: float = throttle * (1.0 - clamp(abs(v) / 90.0, 0.0, 0.6))
		if abs(hs - _haze_s) > 0.05:
			_haze_s = hs
			_haze.set_instance_shader_parameter("strength", hs)
	if tyre_smoke:
		# Tyre smoke when sliding, spray off the tyres on a wet track.
		_set_emitting(tyre_smoke, ((slide > 0.4 or scrub > 0.6 or (spinning and speed() > 6.0)) and speed() > 6.0) or (_wet > 0.25 and speed() > 25.0))
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
