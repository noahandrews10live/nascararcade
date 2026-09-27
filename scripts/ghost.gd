extends Node3D
## Ghost laps: your best lap at each track, saved, and driven again by a see-through
## car in practice, qualifying and time challenges, so you can chase yourself.
## Recorded ten times a second as (time into the lap, distance round, lateral
## position, heading); played back smoothly between the samples.

const Car := preload("res://scripts/car.gd")
const HZ := 10.0

var track_idx := -1
var _rec := PackedFloat32Array() # t, s, d, yaw ...
var _rec_clock := 0.0
var _lap_start := 0.0
var _best := PackedFloat32Array()
var _car: Node3D # the ghost's body
var _mat: StandardMaterial3D
var active := false


func _path(idx: int) -> String:
	return "user://ghost_%d.dat" % idx


## A new race: load the saved ghost for this track (if showing one).
func begin(idx: int, show: bool, team: Dictionary) -> void:
	track_idx = idx
	_rec.clear()
	_rec_clock = 0.0
	_best = PackedFloat32Array()
	if FileAccess.file_exists(_path(idx)):
		var f := FileAccess.open(_path(idx), FileAccess.READ)
		if f:
			var v = bytes_to_var(f.get_buffer(f.get_length()))
			if v is PackedFloat32Array:
				_best = v
	active = show and _best.size() >= 8
	if _car and is_instance_valid(_car):
		_car.queue_free()
		_car = null
	if active:
		_car = Car.new()
		add_child(_car)
		_car.setup(team, null)
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.4, 0.8, 1.0, 0.28)
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.cull_mode = BaseMaterial3D.CULL_BACK
		_ghostify(_car)
		_car.visible = false


func end() -> void:
	active = false
	if _car and is_instance_valid(_car):
		_car.queue_free()
	_car = null


func _ghostify(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_override = _mat
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif c is Label3D or c is GPUParticles3D or c is CPUParticles3D:
			(c as Node3D).visible = false
		_ghostify(c)


## Every physics tick while the player drives.
func record(car: Node3D, race_time: float, delta: float) -> void:
	if car.lap_start_time != _lap_start:
		_lap_start = car.lap_start_time
		_rec.clear()
		_rec_clock = 0.0
	_rec_clock -= delta
	if _rec_clock > 0.0:
		return
	_rec_clock = 1.0 / HZ
	_rec.append_array(PackedFloat32Array([race_time - car.lap_start_time, car.s(), car.d, car.yaw]))


## The player just set a new best lap here: keep this one.
func save_best() -> void:
	if track_idx < 0 or _rec.size() < 8:
		return
	var f := FileAccess.open(_path(track_idx), FileAccess.WRITE)
	if f:
		f.store_buffer(var_to_bytes(_rec))
	_best = _rec.duplicate()


## Places the ghost where your best lap was at this point into the current lap.
func update(track: Node3D, car: Node3D, race_time: float) -> void:
	if not active or _car == null:
		return
	var t: float = race_time - car.lap_start_time
	var n := _best.size() / 4
	if n < 2 or t < 0.0 or t > _best[(n - 1) * 4]:
		_car.visible = false
		return
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _best[mid * 4] <= t:
			lo = mid
		else:
			hi = mid
	var f: float = (t - _best[lo * 4]) / max(_best[hi * 4] - _best[lo * 4], 0.001)
	var s0: float = _best[lo * 4 + 1]
	var s1: float = _best[hi * 4 + 1]
	if s1 < s0 - track.length * 0.5:
		s1 += track.length # across the line
	var s := fposmod(lerp(s0, s1, f), track.length)
	var d: float = lerp(_best[lo * 4 + 2], _best[hi * 4 + 2], f)
	var yaw: float = lerp_angle(_best[lo * 4 + 3], _best[hi * 4 + 3], f)
	_car.global_transform = track.car_transform(s, d, yaw)
	# Fade it out when you're right on top of it.
	var near: float = _car.global_position.distance_to(car.global_position)
	_car.visible = near > 2.5
	_mat.albedo_color.a = clamp((near - 2.5) / 12.0, 0.0, 1.0) * 0.3
