extends Node3D
## Procedurally built oval. Everything on track is addressed in track space:
## `s` = distance along the centre line (0 = start/finish), `d` = lateral offset
## (positive = right of travel = towards the outside wall on these left-turning ovals).

const STEP := 3.0 # metres between centre line samples
const G := 9.81

var cfg: Dictionary
var length := 0.0
var n := 0
var width := 18.0
var apron := 8.0
var infield := 12.0

var pos: PackedVector3Array # centre line, y = 0
var fwd: PackedVector3Array
var right: PackedVector3Array
var curv: PackedFloat32Array # signed curvature, > 0 turning left
var bank: PackedFloat32Array # radians, raises the outside edge
var speed_profile: PackedFloat32Array # max comfortable speed for a nominal car
var minimap: PackedVector2Array # normalised 0..1 outline

var mat: StandardMaterial3D


func setup(config: Dictionary) -> void:
	cfg = config
	width = cfg.width
	apron = cfg.apron
	infield = cfg.infield
	_build_centerline()
	_build_profile()
	_build_minimap()
	mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_build_mesh()
	_build_scenery()


# --- geometry ----------------------------------------------------------------

func _raw_outline() -> PackedVector2Array:
	var S: float = cfg.straight
	var R: float = cfg.radius
	var B: float = cfg.bump
	var shape: String = cfg.shape
	var pts := PackedVector2Array()
	var fine := 0.5
	var front := func(x: float) -> float:
		var u := x / S
		if shape == "trioval":
			return R + B * pow(cos(PI * u), 2)
		elif shape == "quadoval":
			return R + B * pow(sin(2.0 * PI * u), 2)
		return R
	# Front stretch (0 -> +S/2), turn 1-2, back stretch, turn 3-4, front stretch (-S/2 -> 0)
	var x := 0.0
	while x < S * 0.5:
		pts.append(Vector2(x, front.call(x)))
		x += fine
	var steps := int(PI * R / fine)
	for i in steps:
		var a := PI * 0.5 - PI * float(i) / steps
		pts.append(Vector2(S * 0.5 + cos(a) * R, sin(a) * R))
	x = S * 0.5
	while x > -S * 0.5:
		pts.append(Vector2(x, -R))
		x -= fine
	for i in steps:
		var a := -PI * 0.5 - PI * float(i) / steps
		pts.append(Vector2(-S * 0.5 + cos(a) * R, sin(a) * R))
	x = -S * 0.5
	while x < 0.0:
		pts.append(Vector2(x, front.call(x)))
		x += fine
	return pts


func _build_centerline() -> void:
	var raw := _raw_outline()
	# Cumulative length of the dense polyline.
	var cum := PackedFloat32Array()
	cum.resize(raw.size() + 1)
	cum[0] = 0.0
	for i in raw.size():
		cum[i + 1] = cum[i] + raw[i].distance_to(raw[(i + 1) % raw.size()])
	var total := cum[raw.size()]
	n = int(round(total / STEP))
	length = total
	var seg_len := total / n
	pos.resize(n)
	var j := 0
	for i in n:
		var target := i * seg_len
		while cum[j + 1] < target:
			j += 1
		var t: float = (target - cum[j]) / max(cum[j + 1] - cum[j], 0.0001)
		var p := raw[j].lerp(raw[(j + 1) % raw.size()], t)
		pos[i] = Vector3(p.x, 0.0, p.y)
	# Make sure we race counter-clockwise seen from above (left turns): shoelace sign.
	var area := 0.0
	for i in n:
		var p0 := pos[i]
		var p1 := pos[(i + 1) % n]
		area += p0.x * p1.z - p1.x * p0.z
	if area > 0.0:
		var rp := PackedVector3Array()
		rp.resize(n)
		for i in n:
			rp[i] = pos[(n - i) % n]
		pos = rp
	fwd.resize(n)
	right.resize(n)
	curv.resize(n)
	bank.resize(n)
	for i in n:
		var f := (pos[(i + 1) % n] - pos[(i - 1 + n) % n]).normalized()
		fwd[i] = f
		right[i] = f.cross(Vector3.UP).normalized()
	var raw_k := PackedFloat32Array()
	raw_k.resize(n)
	for i in n:
		var a := fwd[(i - 1 + n) % n]
		var b := fwd[(i + 1) % n]
		# cross.y > 0 when the heading swings left.
		raw_k[i] = atan2(a.cross(b).y, a.dot(b)) / (2.0 * seg_len)
	# Smooth curvature so banking and handling transition like real spiral entries.
	var win := int(45.0 / seg_len)
	for i in n:
		var acc := 0.0
		for o in range(-win, win + 1):
			acc += raw_k[(i + o + n) % n]
		curv[i] = acc / (2 * win + 1)
	var k_turn := 1.0 / float(cfg.radius)
	var bt := deg_to_rad(cfg.bank_turn)
	var bs := deg_to_rad(cfg.bank_straight)
	for i in n:
		bank[i] = lerp(bs, bt, clamp(abs(curv[i]) / k_turn, 0.0, 1.0))


## Returns index and fraction for distance s.
func _locate(s: float) -> Vector2:
	var u := fposmod(s, length) / length * n
	var i := int(u) % n
	return Vector2(i, u - floor(u))


func curvature_at(s: float) -> float:
	var l := _locate(s)
	var i := int(l.x)
	return lerp(curv[i], curv[(i + 1) % n], l.y)


func bank_at(s: float) -> float:
	var l := _locate(s)
	var i := int(l.x)
	return lerp(bank[i], bank[(i + 1) % n], l.y)


func inner_edge() -> float:
	return -width * 0.5


func outer_edge() -> float:
	return width * 0.5


func apron_edge() -> float:
	return -width * 0.5 - apron


func inner_wall() -> float:
	return -width * 0.5 - apron - infield


## Surface height at lateral offset d for a given banking angle.
func height_at(d: float, b: float) -> float:
	var di := inner_edge()
	if d <= di:
		# Apron is gently sloped, infield grass is flat.
		var ae := apron_edge()
		if d <= ae:
			return 0.0
		return (d - ae) / apron * 0.35
	return 0.35 + (d - di) * tan(b)


func surface_point(s: float, d: float) -> Vector3:
	var l := _locate(s)
	var i := int(l.x)
	var i2 := (i + 1) % n
	var p := pos[i].lerp(pos[i2], l.y)
	var r := right[i].lerp(right[i2], l.y).normalized()
	var b: float = lerp(bank[i], bank[i2], l.y)
	return p + r * d + Vector3.UP * height_at(d, b)


## Full transform of a car at (s, d) with yaw offset `yaw` (radians, + = heading right).
func car_transform(s: float, d: float, yaw: float) -> Transform3D:
	var l := _locate(s)
	var i := int(l.x)
	var i2 := (i + 1) % n
	var f := fwd[i].lerp(fwd[i2], l.y).normalized()
	var r := right[i].lerp(right[i2], l.y).normalized()
	var b: float = lerp(bank[i], bank[i2], l.y)
	var p := pos[i].lerp(pos[i2], l.y) + r * d + Vector3.UP * height_at(d, b)
	var tilt := b if d > inner_edge() else (atan(0.35 / apron) if d > apron_edge() else 0.0)
	var rb := (r * cos(tilt) + Vector3.UP * sin(tilt)).normalized()
	var up := rb.cross(f).normalized()
	var basis := Basis(rb, up, -f)
	basis = basis.rotated(up, -yaw)
	return Transform3D(basis.orthonormalized(), p)


## Lateral grip limit (m/s^2) including banking.
func grip_limit(s: float, mu: float) -> float:
	var b := bank_at(s)
	var denom: float = max(cos(b) - mu * sin(b), 0.38)
	return G * (sin(b) + mu * cos(b)) / denom


func _build_profile() -> void:
	# Speed a nominal car can carry, with a backwards pass for braking zones.
	speed_profile.resize(n)
	var seg := length / n
	for i in n:
		var k: float = abs(curv[i])
		var lim := grip_limit(i * seg, 1.0) * 0.94
		speed_profile[i] = 200.0 if k < 0.0001 else sqrt(lim / k)
	var decel := 11.0
	for _pass in 2:
		for idx in range(n - 1, -1, -1):
			var nxt := speed_profile[(idx + 1) % n]
			speed_profile[idx] = min(speed_profile[idx], sqrt(nxt * nxt + 2.0 * decel * seg))


func profile_at(s: float) -> float:
	var l := _locate(s)
	return speed_profile[int(l.x)]


func _build_minimap() -> void:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in pos:
		mn = mn.min(Vector2(p.x, p.z))
		mx = mx.max(Vector2(p.x, p.z))
	var size := mx - mn
	var sc: float = max(size.x, size.y)
	minimap.resize(0)
	for i in range(0, n, 4):
		var p := pos[i]
		minimap.append((Vector2(p.x, p.z) - mn) / sc + (Vector2(sc, sc) - size) / sc * 0.5)
	set_meta("mm_min", mn)
	set_meta("mm_scale", sc)
	set_meta("mm_size", size)


func to_minimap(world: Vector3) -> Vector2:
	var mn: Vector2 = get_meta("mm_min")
	var sc: float = get_meta("mm_scale")
	var size: Vector2 = get_meta("mm_size")
	return (Vector2(world.x, world.z) - mn) / sc + (Vector2(sc, sc) - size) / sc * 0.5


# --- mesh ----------------------------------------------------------------------

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	# a,b on sample i; c,d on sample i+1 (a->b left to right)
	st.set_color(col)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(d)


func _pt(i: int, d: float) -> Vector3:
	i = (i + n) % n
	return pos[i] + right[i] * d + Vector3.UP * height_at(d, bank[i])


func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	var iw := inner_wall()
	var ae := apron_edge()
	var grass: Color = cfg.grass
	var sponsor_cols := [Color(0.9, 0.1, 0.1), Color(0.1, 0.3, 0.9), Color(1.0, 0.8, 0.1), Color(0.1, 0.6, 0.2), Color(0.95, 0.95, 0.95), Color(0.9, 0.4, 0.05)]
	var wall_h := 1.2
	var fence_h := 5.0
	for i in n:
		var i2 := (i + 1) % n
		var stripe := (i / 3) % 2 == 0
		var shade := 1.0 if stripe else 0.94
		var asphalt := Color(0.30, 0.30, 0.32) * shade
		asphalt.a = 1.0
		var groove := Color(0.24, 0.24, 0.26) * shade
		groove.a = 1.0
		# infield grass strip + inner wall
		_quad(st, _pt(i, iw), _pt(i, ae), _pt(i2, iw), _pt(i2, ae), grass * (1.0 if stripe else 0.93))
		_quad(st, _pt(i, iw) + Vector3.UP * 0.9, _pt(i, iw), _pt(i2, iw) + Vector3.UP * 0.9, _pt(i2, iw), Color(0.85, 0.85, 0.85))
		# apron
		_quad(st, _pt(i, ae), _pt(i, -hw - 0.7), _pt(i2, ae), _pt(i2, -hw - 0.7), Color(0.42, 0.42, 0.44) * shade)
		# double yellow
		_quad(st, _pt(i, -hw - 0.7), _pt(i, -hw - 0.45), _pt(i2, -hw - 0.7), _pt(i2, -hw - 0.45), Color(1.0, 0.85, 0.1))
		_quad(st, _pt(i, -hw - 0.45), _pt(i, -hw - 0.25), _pt(i2, -hw - 0.45), _pt(i2, -hw - 0.25), Color(0.40, 0.40, 0.42))
		_quad(st, _pt(i, -hw - 0.25), _pt(i, -hw), _pt(i2, -hw - 0.25), _pt(i2, -hw), Color(1.0, 0.85, 0.1))
		# racing surface: bottom lane, groove, upper lane
		_quad(st, _pt(i, -hw), _pt(i, -hw + width * 0.2), _pt(i2, -hw), _pt(i2, -hw + width * 0.2), asphalt)
		_quad(st, _pt(i, -hw + width * 0.2), _pt(i, -hw + width * 0.55), _pt(i2, -hw + width * 0.2), _pt(i2, -hw + width * 0.55), groove)
		_quad(st, _pt(i, -hw + width * 0.55), _pt(i, hw - 0.6), _pt(i2, -hw + width * 0.55), _pt(i2, hw - 0.6), asphalt)
		_quad(st, _pt(i, hw - 0.6), _pt(i, hw), _pt(i2, hw - 0.6), _pt(i2, hw), Color(0.92, 0.92, 0.92))
		# outer wall with sponsor panels
		var panel: Color = sponsor_cols[(i / 8) % sponsor_cols.size()]
		var wb := _pt(i, hw)
		var wb2 := _pt(i2, hw)
		_quad(st, wb + Vector3.UP * wall_h * 0.45, wb, wb2 + Vector3.UP * wall_h * 0.45, wb2, Color(0.95, 0.95, 0.95))
		_quad(st, wb + Vector3.UP * wall_h, wb + Vector3.UP * wall_h * 0.45, wb2 + Vector3.UP * wall_h, wb2 + Vector3.UP * wall_h * 0.45, panel)
		var ro := right[i] * 0.5
		var ro2 := right[i2] * 0.5
		_quad(st, wb + Vector3.UP * wall_h, wb + Vector3.UP * wall_h + ro, wb2 + Vector3.UP * wall_h, wb2 + Vector3.UP * wall_h + ro2, Color(0.8, 0.8, 0.8))
		# catch fence (thin top rail) and posts every 4th sample
		_quad(st, wb + Vector3.UP * fence_h + ro, wb + Vector3.UP * (fence_h - 0.15) + ro, wb2 + Vector3.UP * fence_h + ro2, wb2 + Vector3.UP * (fence_h - 0.15) + ro2, Color(0.55, 0.55, 0.58))
		if i % 4 == 0:
			var f := fwd[i] * 0.15
			var base := wb + Vector3.UP * wall_h + ro
			_quad(st, base + Vector3.UP * (fence_h - wall_h) - f, base - f, base + Vector3.UP * (fence_h - wall_h) + f, base + f, Color(0.35, 0.35, 0.38))
		# outside run-off to the ground
		var ob := _pt(i, hw) + ro
		var ob2 := _pt(i2, hw) + ro2
		var og := pos[i] + right[i] * (hw + 25.0)
		var og2 := pos[i2] + right[i2] * (hw + 25.0)
		_quad(st, ob + Vector3.UP * wall_h, og, ob2 + Vector3.UP * wall_h, og2, grass * 0.85)
	# Start / finish checkers
	for row in 2:
		var cells := int(width)
		for c in cells:
			var d0 := -hw + c * (width / cells)
			var d1 := d0 + width / cells
			var s0 := -1.0 + row * 1.0
			var col := Color.WHITE if (c + row) % 2 == 0 else Color(0.05, 0.05, 0.05)
			var a := surface_point(s0, d0) + Vector3.UP * 0.03
			var b := surface_point(s0, d1) + Vector3.UP * 0.03
			var cc := surface_point(s0 + 1.0, d0) + Vector3.UP * 0.03
			var dd := surface_point(s0 + 1.0, d1) + Vector3.UP * 0.03
			_quad(st, a, b, cc, dd, col)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.name = "TrackMesh"
	add_child(mi)


func _box(st: SurfaceTool, center: Vector3, size: Vector3, basis: Basis, col: Color) -> void:
	var h := size * 0.5
	var c := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]
	var shade := [0.85, 0.85, 0.75, 0.75, 1.0, 0.6]
	for fi in faces.size():
		var f: Array = faces[fi]
		var p := []
		for k in 4:
			p.append(center + basis * c[f[k]])
		st.set_color(Color(col.r * shade[fi], col.g * shade[fi], col.b * shade[fi]))
		st.add_vertex(p[0])
		st.add_vertex(p[2])
		st.add_vertex(p[1])
		st.add_vertex(p[0])
		st.add_vertex(p[3])
		st.add_vertex(p[2])


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cfg.name)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	var S: float = cfg.straight
	var night: bool = cfg.get("night", false)
	# Grandstands along the frontstretch, outside the wall.
	var stand_len := S * 0.9 + float(cfg.bump) * 1.5
	var crowd := [Color(0.9, 0.2, 0.2), Color(0.2, 0.3, 0.9), Color(1, 1, 1), Color(1, 0.8, 0.2), Color(0.3, 0.8, 0.3), Color(0.9, 0.5, 0.1), Color(0.6, 0.2, 0.7)]
	var seg := length / n
	var rows := 14
	for i in n:
		var s := i * seg
		var sd: float = min(s, length - s)
		if sd > stand_len * 0.5:
			continue
		var i2 := (i + 1) % n
		for r in rows:
			var d0 := hw + 8.0 + r * 2.2
			var h0 := 2.0 + r * 1.3
			var a := pos[i] + right[i] * d0 + Vector3.UP * h0
			var b := pos[i] + right[i] * (d0 + 2.2) + Vector3.UP * h0
			var c := pos[i2] + right[i2] * d0 + Vector3.UP * h0
			var d := pos[i2] + right[i2] * (d0 + 2.2) + Vector3.UP * h0
			var col: Color = crowd[rng.randi() % crowd.size()] if rng.randf() < 0.8 else Color(0.5, 0.5, 0.55)
			_quad(st, a, b, c, d, col * (0.8 if night else 1.0))
			# riser
			_quad(st, b, b + Vector3.UP * 1.3, d, d + Vector3.UP * 1.3, Color(0.45, 0.45, 0.5))
		# back wall of the stand
		var top := hw + 8.0 + rows * 2.2
		var bt := pos[i] + right[i] * top
		var bt2 := pos[i2] + right[i2] * top
		_quad(st, bt + Vector3.UP * (2.0 + rows * 1.3 + 3.0), bt, bt2 + Vector3.UP * (2.0 + rows * 1.3 + 3.0), bt2, Color(0.55, 0.55, 0.6))
		# roof
		var roof_h := 2.0 + rows * 1.3 + 3.0
		_quad(st, pos[i] + right[i] * (hw + 14.0) + Vector3.UP * roof_h, bt + Vector3.UP * roof_h, pos[i2] + right[i2] * (hw + 14.0) + Vector3.UP * roof_h, bt2 + Vector3.UP * roof_h, Color(0.75, 0.75, 0.8))
	# Scoring pylon in the infield at start/finish.
	var pyl := pos[0] + right[0] * (inner_wall() - 30.0)
	_box(st, pyl + Vector3.UP * 16.0, Vector3(4, 32, 4), Basis.IDENTITY, Color(0.2, 0.2, 0.25))
	for k in 10:
		_box(st, pyl + Vector3.UP * (3.0 + k * 2.8) + right[0] * 2.05, Vector3(0.1, 2.2, 3.2), Basis(Vector3.UP, atan2(right[0].x, right[0].z)), crowd[k % crowd.size()])
	# Flag stand gantry over the start/finish line.
	var b0 := Basis(Vector3.UP, atan2(fwd[0].x, fwd[0].z))
	var p_in := surface_point(0.0, -hw - 1.5)
	var p_out := surface_point(0.0, hw + 0.5)
	var top_y: float = max(p_in.y, p_out.y) + 9.0
	_box(st, Vector3(p_in.x, (p_in.y + top_y) * 0.5, p_in.z), Vector3(0.6, top_y - p_in.y, 0.6), b0, Color(0.8, 0.8, 0.8))
	_box(st, Vector3(p_out.x, (p_out.y + top_y) * 0.5, p_out.z), Vector3(0.6, top_y - p_out.y, 0.6), b0, Color(0.8, 0.8, 0.8))
	var mid := (p_in + p_out) * 0.5
	mid.y = top_y
	_box(st, mid, Vector3(p_in.distance_to(p_out) + 1.0, 1.6, 1.2), Basis(Vector3.UP, atan2(right[0].x, right[0].z) - PI * 0.5), Color(0.1, 0.1, 0.12))
	# Infield buildings / haulers.
	for k in 14:
		var t := float(k) / 14.0
		var idx := int(t * n * 0.35 + n * 0.08) % n
		var p := pos[idx] + right[idx] * (inner_wall() - 22.0 - rng.randf() * 20.0)
		var truck_col: Color = crowd[rng.randi() % crowd.size()]
		_box(st, p + Vector3.UP * 2.0, Vector3(3.0, 4.0, 16.0), Basis(Vector3.UP, atan2(fwd[idx].x, fwd[idx].z) + 0.4), truck_col)
	# Light towers for night tracks.
	if night:
		for i in range(0, n, max(1, n / 16)):
			var lp := pos[i] + right[i] * (hw + 6.0)
			_box(st, lp + Vector3.UP * 17.0, Vector3(0.8, 34, 0.8), Basis.IDENTITY, Color(0.4, 0.4, 0.45))
			_box(st, lp + Vector3.UP * 34.0, Vector3(4.0, 2.5, 1.0), Basis(Vector3.UP, atan2(right[i].x, right[i].z)), Color(3.0, 3.0, 2.6))
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var smat := mat.duplicate()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = smat
	mi.name = "Scenery"
	add_child(mi)

	# Ground plane
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000, 9000)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = cfg.grass
	gm.roughness = 1.0
	ground.material_override = gm
	ground.position.y = -0.15
	add_child(ground)

	if cfg.get("lake", false):
		var lake := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = cfg.radius * 0.45
		cm.bottom_radius = cfg.radius * 0.45
		cm.height = 0.05
		cm.radial_segments = 24
		lake.mesh = cm
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.15, 0.35, 0.65)
		lm.metallic_specular = 1.0
		lm.roughness = 0.1
		lake.material_override = lm
		lake.position = Vector3(0, -0.08, 0)
		lake.scale = Vector3(2.2, 1, 0.9)
		add_child(lake)

	# Trees outside the track (MultiMesh cones).
	var tree := CylinderMesh.new()
	tree.top_radius = 0.0
	tree.bottom_radius = 4.0
	tree.height = 12.0
	tree.radial_segments = 6
	tree.rings = 1
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.1, 0.35, 0.12) if not night else Color(0.05, 0.15, 0.08)
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	tree.material = tm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tree
	var count := 260
	mm.instance_count = count
	for k in count:
		var idx := rng.randi() % n
		var off := hw + 45.0 + rng.randf() * 260.0
		var p := pos[idx] + right[idx] * off
		var sc := 0.7 + rng.randf() * 0.9
		mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3(sc, sc, sc)), p + Vector3.UP * 6.0 * sc))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
