extends RefCounted
## Makes the camera feel the car: a spring-damper "head" pushed around by the
## car's accelerations (leans out in corners, dips under braking, sinks back on
## the throttle) plus layered vibration - road texture, seams, engine buzz at
## high revs - and jolts on contact.
##
## update() returns a local offset transform to apply on top of the camera's
## mounted position. Chase cameras use it gently; the cockpit uses it fully.

var off := Vector3.ZERO # lateral, vertical, longitudinal (m)
var vel := Vector3.ZERO
var tilt := Vector2.ZERO # roll, pitch (rad)
var tilt_v := Vector2.ZERO
var _prev_v := 0.0
var _car: Node3D
var _t := 0.0
var _jolt := 0.0
var _noise := FastNoiseLite.new()


func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0


func reset() -> void:
	off = Vector3.ZERO
	vel = Vector3.ZERO
	tilt = Vector2.ZERO
	tilt_v = Vector2.ZERO
	_car = null


func jolt(amount: float) -> void:
	_jolt = max(_jolt, clamp(amount, 0.0, 1.0))


## strength: 0 (off) .. 1 (full cockpit head movement); vibration scales the
## shake separately (a long chase-cam arm doesn't buzz like a seat does).
func update(car: Node3D, delta: float, strength: float, vibration := 1.0) -> Transform3D:
	if delta <= 0.0 or car == null:
		return Transform3D.IDENTITY
	if car != _car:
		reset()
		_car = car
		_prev_v = car.v
	_t += delta
	# Accelerations in the car's frame (m/s^2).
	var a_long: float = clamp((car.v - _prev_v) / delta, -40.0, 40.0)
	_prev_v = car.v
	var a_lat: float = clamp(car.v * car.r, -40.0, 40.0)
	var a_vert: float = clamp(car.chassis_vz, -3.0, 3.0) * 6.0
	# The head is a mass on a spring: it lags behind the car's accelerations.
	# Where the head would settle under these loads: ~7 cm out in a 2.5 g corner,
	# ~6 cm forward under hard braking.
	var target := Vector3(a_lat * 0.003, -a_vert * 0.002, a_long * 0.004)
	var k := 55.0
	var c := 11.0
	vel += ((target - off) * k - vel * c) * delta
	off += vel * delta
	off = off.clamp(Vector3(-0.25, -0.12, -0.25), Vector3(0.25, 0.12, 0.25))
	# Roll with the body (the cockpit leans), pitch with dive and squat.
	var tt := Vector2(-a_lat * 0.0022 + car.chassis_roll * 0.8, a_long * 0.0016 + car.chassis_pitch * 0.8)
	tilt_v += ((tt - tilt) * 70.0 - tilt_v * 13.0) * delta
	tilt += tilt_v * delta
	# Vibration: road texture (from the suspension), seams, and engine buzz.
	var rough := 0.0
	if "_road_rate" in car:
		for i in 4:
			rough += abs(car._road_rate[i])
	var spd: float = clamp(car.speed() / 90.0, 0.0, 1.3)
	var buzz: float = clamp((car.rpm() - 7000.0) / 3000.0, 0.0, 1.0) * 0.0025
	var road: float = rough * 0.012 + spd * 0.004
	var seam: float = clamp(car.bump / 25.0, 0.0, 1.0) * 0.05
	_jolt = max(_jolt, clamp(car.wall_hit / 18.0, 0.0, 1.0))
	var shake: float = road + seam + _jolt * 0.12
	var n1 := _noise.get_noise_2d(_t * 25.0, 0.0)
	var n2 := _noise.get_noise_2d(0.0, _t * 25.0)
	var n3 := sin(_t * TAU * car.rpm() / 60.0 * 0.5) # half-order engine shake
	var v := Vector3(n1 * shake, n2 * shake + n3 * buzz, 0.0) * vibration
	_jolt = max(_jolt - delta * 3.0, 0.0)
	var pos := (off + v) * strength
	var rot := Basis.from_euler(Vector3(tilt.y * strength, 0.0, tilt.x * strength + n1 * _jolt * 0.05))
	return Transform3D(rot, Vector3(pos.x, pos.y, pos.z))
