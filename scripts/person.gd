extends Node3D
## A person at the track: a crew member, the flagman, the winner in victory lane.
## Built from simple shapes on a jointed frame (hips, knees, shoulders, elbows,
## neck), so it can stand, crouch to work on a car, walk, wave and jump for joy.
## Firesuit in the team's colours with a stripe of the second colour, gloves,
## boots and a helmet (or a cap).
##   var p := Person.new(); p.setup(c1, c2); p.pose = "cheer"

var pose := "stand" # stand, work, walk, wave, cheer, arms_up
var phase := 0.0 # offsets the animation so a group doesn't move in step
var speed := 1.0

var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _leg := [] # [thigh pivot, knee pivot] x2
var _arm := [] # [shoulder pivot, elbow pivot] x2
var _suit: StandardMaterial3D
var _trim: StandardMaterial3D
var _t := 0.0

static var _m := {}


static func _mesh(key: String) -> Mesh:
	if _m.has(key):
		return _m[key]
	var mesh: Mesh
	match key:
		"thigh":
			var c := CapsuleMesh.new()
			c.radius = 0.085
			c.height = 0.5
			c.radial_segments = 8
			c.rings = 2
			mesh = c
		"shin":
			var c := CapsuleMesh.new()
			c.radius = 0.07
			c.height = 0.48
			c.radial_segments = 8
			c.rings = 2
			mesh = c
		"upper":
			var c := CapsuleMesh.new()
			c.radius = 0.062
			c.height = 0.34
			c.radial_segments = 8
			c.rings = 2
			mesh = c
		"fore":
			var c := CapsuleMesh.new()
			c.radius = 0.052
			c.height = 0.32
			c.radial_segments = 8
			c.rings = 2
			mesh = c
		"chest":
			var c := CylinderMesh.new()
			c.top_radius = 0.2
			c.bottom_radius = 0.16
			c.height = 0.56
			c.radial_segments = 10
			c.rings = 1
			mesh = c
		"pelvis":
			var c := CylinderMesh.new()
			c.top_radius = 0.16
			c.bottom_radius = 0.17
			c.height = 0.16
			c.radial_segments = 10
			c.rings = 1
			mesh = c
		"stripe":
			var b := BoxMesh.new()
			b.size = Vector3(0.03, 0.5, 0.1)
			mesh = b
		"belt":
			var c := CylinderMesh.new()
			c.top_radius = 0.165
			c.bottom_radius = 0.165
			c.height = 0.05
			c.radial_segments = 10
			c.rings = 1
			mesh = c
		"head":
			var s := SphereMesh.new()
			s.radius = 0.105
			s.height = 0.23
			s.radial_segments = 10
			s.rings = 6
			mesh = s
		"helmet":
			var s := SphereMesh.new()
			s.radius = 0.135
			s.height = 0.25
			s.radial_segments = 12
			s.rings = 6
			s.is_hemisphere = false
			mesh = s
		"visor":
			var b := BoxMesh.new()
			b.size = Vector3(0.2, 0.07, 0.04)
			mesh = b
		"cap":
			var s := SphereMesh.new()
			s.radius = 0.118
			s.height = 0.118
			s.is_hemisphere = true
			s.radial_segments = 10
			s.rings = 3
			mesh = s
		"brim":
			var b := BoxMesh.new()
			b.size = Vector3(0.2, 0.02, 0.12)
			mesh = b
		"glove":
			var s := SphereMesh.new()
			s.radius = 0.055
			s.height = 0.12
			s.radial_segments = 8
			s.rings = 4
			mesh = s
		"boot":
			var b := BoxMesh.new()
			b.size = Vector3(0.12, 0.09, 0.27)
			mesh = b
	_m[key] = mesh
	return mesh


static func _mat(key: String, col: Color, rough := 0.75) -> StandardMaterial3D:
	if _m.has("mat_" + key):
		return _m["mat_" + key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	_m["mat_" + key] = m
	return m


func _part(parent: Node3D, mesh: String, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(mesh)
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


## c1: the firesuit, c2: its stripes and the helmet. `hat`: "helmet", "cap" or "".
func setup(c1: Color, c2: Color, hat := "helmet", skin := -1) -> void:
	_suit = StandardMaterial3D.new()
	_suit.albedo_color = c1
	_suit.roughness = 0.8
	_trim = StandardMaterial3D.new()
	_trim.albedo_color = c2
	_trim.roughness = 0.6
	var skins := [Color(0.93, 0.76, 0.62), Color(0.78, 0.57, 0.42), Color(0.55, 0.37, 0.25), Color(0.36, 0.24, 0.16)]
	var sk: Color = skins[(skin if skin >= 0 else randi()) % skins.size()]
	var skin_m := StandardMaterial3D.new()
	skin_m.albedo_color = sk
	skin_m.roughness = 0.7
	var black := _mat("black", Color(0.05, 0.05, 0.06), 0.6)
	var visor := _mat("visor", Color(0.04, 0.05, 0.08), 0.1)
	_hips = _pivot(self, Vector3(0, 0.98, 0))
	_part(_hips, "pelvis", Vector3(0, -0.02, 0), _suit)
	_torso = _pivot(_hips, Vector3(0, 0.04, 0))
	var chest := _part(_torso, "chest", Vector3(0, 0.3, 0), _suit)
	chest.scale = Vector3(1, 1, 0.68)
	_part(_torso, "belt", Vector3(0, 0.04, 0), black).scale = Vector3(1, 1, 0.72)
	_part(_torso, "stripe", Vector3(0.175, 0.3, 0), _trim)
	_part(_torso, "stripe", Vector3(-0.175, 0.3, 0), _trim)
	_head = _pivot(_torso, Vector3(0, 0.66, 0))
	_part(_head, "head", Vector3(0, 0.1, 0), skin_m)
	if hat == "helmet":
		_part(_head, "helmet", Vector3(0, 0.12, 0.005), _trim)
		_part(_head, "visor", Vector3(0, 0.12, -0.12), visor)
	elif hat == "cap":
		_part(_head, "cap", Vector3(0, 0.15, 0), _trim)
		_part(_head, "brim", Vector3(0, 0.155, -0.13), _trim)
	for side in [-1.0, 1.0]:
		var hip := _pivot(_hips, Vector3(0.1 * side, -0.05, 0))
		_part(hip, "thigh", Vector3(0, -0.22, 0), _suit)
		var knee := _pivot(hip, Vector3(0, -0.45, 0))
		_part(knee, "shin", Vector3(0, -0.22, 0), _suit)
		_part(knee, "boot", Vector3(0, -0.46, -0.04), black)
		_leg.append([hip, knee])
		var sh := _pivot(_torso, Vector3(0.245 * side, 0.52, 0))
		_part(sh, "upper", Vector3(0, -0.15, 0), _suit)
		var el := _pivot(sh, Vector3(0, -0.3, 0))
		_part(el, "fore", Vector3(0, -0.14, 0), _suit)
		_part(el, "glove", Vector3(0, -0.3, 0), black)
		_arm.append([sh, el])
	phase = randf() * TAU
	_apply(0.0)


func set_colors(c1: Color, c2 = null) -> void:
	if _suit:
		_suit.albedo_color = c1
	if _trim and c2 != null:
		_trim.albedo_color = c2


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _hips == null:
		return
	_t += delta * speed
	_apply(_t)


func _apply(t: float) -> void:
	var w := t + phase
	var hy := 0.98
	var lean := 0.0
	var head_x := 0.0
	# [hip x, knee x] per leg; [shoulder x, shoulder z, elbow x] per arm
	# Angles in radians. Legs: [hip, knee] (+hip swings the leg forward, knees
	# bend back, so negative). Arms: [shoulder forward, shoulder out, elbow].
	var lg := [[0.0, 0.0], [0.0, 0.0]]
	var am := [[0.08, 0.12, 0.15], [0.08, 0.12, 0.15]]
	match pose:
		"stand":
			var b := sin(w * 1.3) * 0.03
			am = [[0.05 + b, 0.1, 0.2], [0.05 - b, 0.1, 0.2]]
			head_x = sin(w * 0.4) * 0.08
		"work":
			# Down on one knee at the wheel, hands busy.
			hy = 0.6
			lean = 0.55
			lg = [[1.5, -1.5], [0.0, -1.6]]
			var h := sin(w * 14.0) * 0.18
			am = [[1.2 + h, 0.12, 0.5], [1.2 - h, 0.12, 0.5]]
			head_x = -0.25
		"walk":
			var s := sin(w * 5.0)
			lg = [[s * 0.5, -max(0.0, -s) * 0.7], [-s * 0.5, -max(0.0, s) * 0.7]]
			am = [[-s * 0.4, 0.08, 0.3], [s * 0.4, 0.08, 0.3]]
			hy = 0.98 - abs(s) * 0.03
		"wave":
			am = [[0.05, 0.1, 0.2], [2.7, 0.35 + sin(w * 7.0) * 0.35, 0.5]]
		"cheer":
			# Jumping, both fists pumping.
			var j: float = abs(sin(w * 4.5))
			hy = 0.98 + j * 0.3
			lg = [[j * 0.4, -j * 0.8], [j * 0.4, -j * 0.8]]
			var pump := sin(w * 9.0) * 0.25
			am = [[2.7 + pump, 0.35, 0.4], [2.7 - pump, 0.35, 0.4]]
			head_x = 0.2
		"arms_up":
			var sway := sin(w * 2.0) * 0.12
			am = [[2.9, 0.25 + sway, 0.2], [2.9, 0.25 - sway, 0.2]]
			head_x = 0.25
	_hips.position.y = hy
	_torso.rotation.x = -lean
	_head.rotation.x = head_x
	for k in 2:
		(_leg[k][0] as Node3D).rotation.x = lg[k][0]
		(_leg[k][1] as Node3D).rotation.x = lg[k][1]
		var out: float = am[k][1] * (-1.0 if k == 0 else 1.0) # arm 0 is the left
		(_arm[k][0] as Node3D).rotation = Vector3(am[k][0], 0, out)
		(_arm[k][1] as Node3D).rotation.x = am[k][2]
