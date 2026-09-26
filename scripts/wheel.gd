extends Node
## Steering wheels: reads the wheel and pedals directly (axes chosen in Options →
## Wheel Setup), and drives force feedback through the native helper
## (native/ffb_helper, started next to the game).
##
## Force: the front tyres' aligning torque (the wheel goes light as the fronts
## slide, heavy as they load up), plus bumps, kerbs, and hits.

const HELPER_PORT := 24570
const ROTATIONS := [270, 540, 720, 900, 1080]
const STRENGTHS := [0.0, 0.35, 0.6, 0.85, 1.0]

var udp := PacketPeerUDP.new()
var helper_pid := -1
var status := "" # "OK <name>", "NONE", or ""
var _send := 0.0
var detecting := "" # which setting is waiting for an axis to move
var _rest := {}


func settings() -> Dictionary:
	return Game.wheel


## The steering, throttle and brake the wheel is asking for, or {} when off.
func read() -> Dictionary:
	var w: Dictionary = Game.wheel
	if not w.enabled:
		return {}
	var dev: int = int(w.device)
	var steer: float = Input.get_joy_axis(dev, int(w.steer_axis))
	# Full lock of the car's steering at +-270 degrees of wheel (15:1).
	var half_rot: float = ROTATIONS[int(w.rotation)] * 0.5
	steer = clamp(steer * half_rot / 270.0, -1.0, 1.0)
	return {
		"steer": steer,
		"throttle": _pedal(dev, int(w.throttle_axis)),
		"brake": _pedal(dev, int(w.brake_axis)),
	}


func _pedal(dev: int, axis: int) -> float:
	var raw: float = Input.get_joy_axis(dev, axis)
	# Most pedals rest at +1 or -1; "invert" flips which end is released.
	var x: float = (raw + 1.0) * 0.5
	if Game.wheel.invert:
		x = 1.0 - x
	return clamp((x - 0.03) / 0.94, 0.0, 1.0)


func start_helper() -> void:
	if helper_pid > 0 or not Game.wheel.enabled or OS.has_feature("web"):
		return
	var exe := "ffb_helper.exe" if OS.has_feature("windows") else "ffb_helper"
	var candidates := [OS.get_executable_path().get_base_dir().path_join(exe), ProjectSettings.globalize_path("res://native/bin/" + exe)]
	for path in candidates:
		if FileAccess.file_exists(path):
			helper_pid = OS.create_process(path, [])
			break
	udp.connect_to_host("127.0.0.1", HELPER_PORT)


func stop_helper() -> void:
	if helper_pid > 0:
		udp.put_packet("Q\n".to_ascii_buffer())
		helper_pid = -1


func _exit_tree() -> void:
	stop_helper()


## Called each physics frame with the player's car (or null when not driving).
func update(car: Node3D, delta: float) -> void:
	while udp.get_available_packet_count() > 0:
		status = udp.get_packet().get_string_from_ascii()
	if not Game.wheel.enabled or helper_pid <= 0:
		return
	_send -= delta
	if _send > 0.0:
		return
	_send = 1.0 / 60.0
	var force := 0.0
	var rumble := 0.0
	if car:
		var strength: float = STRENGTHS[int(Game.wheel.ffb)]
		# Aligning torque pulls the wheel back toward straight, in proportion to
		# how hard the fronts are working; it drops away as they slide.
		var align: float = clamp(abs(car.steer_feel), 0.0, 1.0) * (1.0 - 0.7 * clamp(car.scrub, 0.0, 1.0))
		# Heavier with speed (the fronts carry downforce), light when they slide.
		align *= 0.6 + 0.4 * clamp(car.speed() / 80.0, 0.0, 1.0)
		force = -sign(car.steer) * align
		# When the rear steps out the wheel tugs towards the countersteer.
		force += sign(car.vy) * clamp(car.slide, 0.0, 1.0) * 0.35
		# Contact snaps the wheel: a wall on the right kicks it left, and so on.
		if car.wall_hit > 3.0:
			force += -sign(car.d) * clamp(car.wall_hit / 15.0, 0.0, 1.0) * 0.8
		force = clamp(force, -1.0, 1.0) * strength
		var main := get_parent()
		var h: Dictionary = main.haptics(car, Time.get_ticks_msec() / 1000.0) if main and main.has_method("haptics") else {"strong": 0.0, "weak": 0.0}
		rumble = clamp(h.strong + h.weak * 0.3, 0.0, 1.0) * strength
	udp.put_packet(("F %.3f %.3f\n" % [force, rumble]).to_ascii_buffer())


## Axis detection: remember where every axis rests, then the first one moved far
## becomes the chosen control.
func begin_detect(what: String) -> void:
	detecting = what
	_rest.clear()
	for dev in Input.get_connected_joypads():
		for a in 8:
			_rest[Vector2i(dev, a)] = Input.get_joy_axis(dev, a)


func poll_detect() -> bool:
	if detecting == "":
		return false
	for key in _rest:
		var now: float = Input.get_joy_axis(key.x, key.y)
		if abs(now - float(_rest[key])) > 0.5:
			Game.wheel.device = key.x
			Game.wheel[detecting] = key.y
			detecting = ""
			Game.save_settings()
			return true
	return false
