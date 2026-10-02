extends Node3D
## Race-day props from Kenney's Racing Kit (CC0, assets/models/kenney): a row of
## team tents in the paddock with cones along its walkway, sponsor billboards
## facing the backstretch, a TV dish by the media centre and, on road courses,
## red and white barriers lining the outside of the tight corners.
##
## The models are tiny and low-poly (a few dozen to a few hundred triangles);
## each is drawn once for all its copies (a MultiMesh), so the whole lot costs a
## handful of draw calls.

const DIR := "res://assets/models/kenney/"
## Kenney's kit is about a fifth of real size: these make a cone 0.7 m tall, a
## tent 3.5 m across, a billboard 9 m wide and a barrier section 1.5 m long.
const SCALE := {"pylon": 5.4, "tent": 3.5, "tentLong": 3.5, "billboard": 9.0,
	"radarEquipment": 9.0, "barrierRed": 6.0, "barrierWhite": 6.0}

var track: Node3D
var _placed := {} # model -> Array[Transform3D]


static func available() -> bool:
	return ResourceLoader.exists(DIR + "pylon.glb")


func build(t: Node3D) -> void:
	track = t
	name = "Props"
	_paddock()
	_billboards()
	_media()
	if track.turns_both_ways():
		_runoff()
	for m in _placed:
		_commit(m)


## Infield props keep clear of the track (on a short track the paddock runs round
## the turns, close to the other side).
func _infield_ok(p: Vector3, size: float) -> bool:
	return track._clear_of_track(p, track.infield_clear() + size)


func _put(model: String, pos: Vector3, yaw: float, extra_scale := 1.0) -> void:
	var s: float = SCALE.get(model, 1.0) * extra_scale
	var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s)
	if not _placed.has(model):
		_placed[model] = []
	_placed[model].append(Transform3D(b, pos))


## Track frame at distance s: [centre, right, yaw facing along the track].
func _frame(s: float) -> Array:
	var i: int = int(fposmod(s, track.length) / track.length * track.n) % track.n
	var f: Vector3 = track.fwd[i]
	return [track.pos[i], track.right[i], atan2(f.x, f.z)]


## Tents between the inner wall and the hauler lot, a cone every few metres
## along their walkway.
func _paddock() -> void:
	if track.cfg.get("road", false):
		return
	var iw: float = track.inner_wall()
	var lot0: float = track.length * 0.12
	var lot_len: float = min(360.0, track.length * 0.3)
	var s := lot0 + 10.0
	var k := 0
	while s < lot0 + lot_len - 10.0:
		var fr: Array = _frame(s)
		var p: Vector3 = fr[0] + fr[1] * (iw - 9.0)
		if _infield_ok(p, 4.0):
			_put("tentLong" if k % 3 == 1 else "tent", Vector3(p.x, -0.1, p.z), fr[2])
		s += 16.0
		k += 1
	s = lot0 + 4.0
	while s < lot0 + lot_len - 4.0:
		var fr: Array = _frame(s)
		var p: Vector3 = fr[0] + fr[1] * (iw - 4.0)
		if _infield_ok(p, 0.5):
			_put("pylon", Vector3(p.x, -0.1, p.z), fr[2])
		s += 6.0


## Billboards outside the backstretch, facing the cars.
func _billboards() -> void:
	var hw: float = track.width * 0.5
	var s0: float = track.length * 0.36
	var s1: float = track.length * 0.64
	var s := s0
	while s < s1:
		var fr: Array = _frame(s)
		var p: Vector3 = fr[0] + fr[1] * (hw + 26.0)
		# Face the track: the board's front looks back along -right.
		var r: Vector3 = fr[1]
		_put("billboard", Vector3(p.x, 0.0, p.z), atan2(-r.x, -r.z))
		s += 140.0


## The TV compound by the media centre: a satellite dish.
func _media() -> void:
	if track.cfg.get("road", false):
		return
	var fr: Array = _frame(0.0)
	var iw: float = track.inner_wall()
	var p: Vector3 = fr[0] + fr[1] * (iw - 58.0) + track.fwd[0] * 62.0
	if _infield_ok(p, 8.0):
		_put("radarEquipment", Vector3(p.x, 0.0, p.z), fr[2] + PI * 0.75)


## Road courses: red / white barrier sections lining the track's edge on the
## outside of tight corners, tilted with the surface.
func _runoff() -> void:
	var s := 0.0
	var k := 0
	while s < track.length:
		var kk: float = track.curvature_at(s)
		if abs(kk) > 1.0 / 150.0:
			# Just off the edge of the racing surface, never on it.
			var d: float = track.outer_edge() + 1.2 if kk > 0.0 else track.apron_edge() - 1.2
			var t: Transform3D = track.car_transform(s, d, 0.0)
			var m := "barrierRed" if k % 2 == 0 else "barrierWhite"
			var sc: float = SCALE[m]
			var b: Basis = (t.basis * Basis(Vector3.UP, PI * 0.5)).scaled(Vector3.ONE * sc)
			if not _placed.has(m):
				_placed[m] = []
			_placed[m].append(Transform3D(b, t.origin))
			k += 1
		s += 1.5


func _commit(model: String) -> void:
	var list: Array = _placed[model]
	if list.is_empty():
		return
	var sc: PackedScene = load(DIR + model + ".glb")
	if sc == null:
		return
	var root: Node = sc.instantiate()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mi.mesh
		mm.instance_count = list.size()
		# Kenney's pieces aren't centred: stand each on the middle of its footprint.
		var ab: AABB = mi.mesh.get_aabb()
		var local := Transform3D(Basis.IDENTITY, -Vector3(ab.position.x + ab.size.x * 0.5, ab.position.y, ab.position.z + ab.size.z * 0.5))
		for i in list.size():
			mm.set_instance_transform(i, list[i] * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = model
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if model in ["tent", "tentLong", "billboard"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 1500.0
		add_child(mmi)
	root.free()
