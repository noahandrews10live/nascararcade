extends MultiMeshInstance3D
## Tyre marks: sliding, spinning or locked-up cars lay dark rubber streaks on the
## track. One MultiMesh used as a ring buffer, so the cost is fixed however many
## marks there are; the oldest marks are reused first.

const MAX_MARKS := 4000
const SPACING := 0.45 # metres of travel between mark segments

var _next := 0
var _count := 0
var _last := {} # car -> [Vector3 left, Vector3 right, bool front]


func _ready() -> void:
	name = "SkidMarks"
	var qm := QuadMesh.new()
	qm.size = Vector2(0.3, SPACING * 1.25)
	qm.orientation = PlaneMesh.FACE_Y
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = qm
	mm.instance_count = MAX_MARKS
	mm.visible_instance_count = 0
	multimesh = mm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.03, 0.03)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.9
	m.albedo_texture = _streak_texture()
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Call once per physics tick for each car.
func track_car(c: Node3D) -> void:
	var sliding: bool = c.speed() > 6.0 and (c.slide > 0.35 or c.scrub > 0.55 or c.spinning or (c.brake > 0.9 and c.speed() > 25.0 and c.slide > 0.15))
	# Anything in the grass cuts ruts in it (they stay for the race).
	var grass: bool = c.on_grass and c.speed() > 4.0
	if not (sliding or grass) or c.pit_state >= 2 or not c.visible:
		_last.erase(c)
		return
	var xf: Transform3D = c.global_transform
	var strength: float = clamp(max(c.slide, c.scrub * 0.8) + (0.5 if c.spinning else 0.0), 0.2, 1.0)
	var fronts: bool = c.spinning or c.scrub > 0.8 or grass
	var wheels := [Vector3(-0.84, 0.03, 1.45), Vector3(0.84, 0.03, 1.45)]
	if fronts:
		wheels.append(Vector3(-0.84, 0.03, -1.5))
		wheels.append(Vector3(0.84, 0.03, -1.5))
	var now: Array = []
	for w in wheels:
		now.append(xf * w)
	var prev: Array = _last.get(c, [])
	if prev.size() != now.size():
		_last[c] = now
		return
	for k in now.size():
		var a: Vector3 = prev[k]
		var b: Vector3 = now[k]
		var seg := b - a
		var dlen := seg.length()
		if dlen < SPACING:
			continue
		if dlen > 6.0: # teleported (reset / tow)
			prev[k] = b
			continue
		var mid := (a + b) * 0.5
		var fwd := seg / dlen
		var up: Vector3 = xf.basis.y
		var right := fwd.cross(up).normalized()
		var basis := Basis(right, up, -fwd * (dlen / SPACING))
		multimesh.set_instance_transform(_next, Transform3D(basis, mid))
		multimesh.set_instance_color(_next, Color(4.0, 2.6, 1.4, 0.8) if grass else Color(1, 1, 1, 0.55 * strength))
		_next = (_next + 1) % MAX_MARKS
		if _count < MAX_MARKS:
			_count += 1
			multimesh.visible_instance_count = _count
		prev[k] = b
	_last[c] = prev


## Soft-edged streak so marks don't look like tape.
static func _streak_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 32
	t.height = 4
	return t
