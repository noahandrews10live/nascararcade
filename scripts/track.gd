extends Node3D
## Procedurally built oval. Everything on track is addressed in track space:
## `s` = distance along the centre line (0 = start/finish), `d` = lateral offset
## (positive = right of travel = towards the outside wall on these left-turning ovals).

const STEP := 3.0 # metres between centre line samples
const G := 9.81
const CAR_MASS := 1600.0
const PIT_LANE_EXT := 170.0 # entry / exit lanes beyond the pit road itself

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

var _st := {} # material kind -> SurfaceTool
var _raw_bank := PackedFloat32Array() # per raw point banking (degrees) for segment layouts
var _front_len := 0.0


func setup(config: Dictionary) -> void:
	cfg = config
	width = cfg.width
	apron = cfg.apron
	infield = cfg.infield
	_build_centerline()
	_build_profile()
	_build_minimap()
	_build_mesh()
	_build_scenery()
	_commit_surfaces()
	_build_fence()
	_build_crowd()


# --- geometry ----------------------------------------------------------------

## Builds the centre line with a turtle: start/finish at the middle of the front
## stretch, then [front half, dog-leg arc, front side, turn, back half] twice. The
## path is palindromic with 360 degrees of turning, so it always closes, and every
## piece turns left (real tri-ovals and quad-ovals never bend the other way).
## General layouts: a list of straights {"s": metres} and arcs {"r": radius, "a": degrees
## (+ = the track's main turning direction, - = the other way), "b": banking degrees}.
## Two straights can be "auto": their lengths are solved so the layout closes. The
## first entry is the front stretch; the start/finish line sits at its middle.
func _segments_outline() -> PackedVector2Array:
	var segs: Array = cfg.segments
	# Pass 1: headings, known displacement, and the directions of the auto straights.
	var h := 0.0
	var known := Vector2.ZERO
	var auto_dirs := {}
	for sg in segs:
		if sg.has("s"):
			var dir := Vector2(cos(h), sin(h))
			if sg.s is String:
				auto_dirs[sg.s] = dir
			else:
				known += dir * float(sg.s)
		else:
			var r: float = sg.r
			var a := deg_to_rad(float(sg.a))
			var sgn := signf(a)
			# chord of an arc turning by a with radius r from heading h
			var c := Vector2(sin(h + a) - sin(h), -cos(h + a) + cos(h)) * r * sgn
			known += c
			h += a
	var lens := {}
	if auto_dirs.size() == 2:
		var u1: Vector2 = auto_dirs["auto1"]
		var u2: Vector2 = auto_dirs["auto2"]
		var det := u1.x * u2.y - u1.y * u2.x
		var rhs := -known
		lens["auto1"] = (rhs.x * u2.y - rhs.y * u2.x) / det
		lens["auto2"] = (u1.x * rhs.y - u1.y * rhs.x) / det
		if lens.auto1 < 20.0 or lens.auto2 < 20.0:
			push_warning("Track %s: closure straights came out short (%.0f, %.0f)" % [cfg.name, lens.auto1, lens.auto2])
	# Pass 2: walk it, starting from the middle of the front stretch.
	var st := {"p": Vector2.ZERO, "h": 0.0, "pts": PackedVector2Array(), "bank": PackedFloat32Array()}
	var bs: float = cfg.bank_straight
	var straight := func(length: float) -> void:
		var steps: int = max(1, int(length / 0.5))
		for i in steps:
			st.pts.append(st.p)
			st.bank.append(bs)
			st.p += Vector2(cos(st.h), sin(st.h)) * (length / steps)
	var arc := func(radius: float, angle: float, bank_deg: float) -> void:
		var steps: int = max(1, int(radius * abs(angle) / 0.5))
		var da := angle / steps
		for i in steps:
			st.pts.append(st.p)
			st.bank.append(bank_deg)
			var mid: float = st.h + da * 0.5
			st.p += Vector2(cos(mid), sin(mid)) * (2.0 * radius * sin(abs(da) * 0.5))
			st.h += da
	var first_len: float = lens.get(segs[0].s, 0.0) if segs[0].s is String else float(segs[0].s)
	_front_len = first_len
	straight.call(first_len * 0.5)
	for i in range(1, segs.size()):
		var sg: Dictionary = segs[i]
		if sg.has("s"):
			straight.call(lens.get(sg.s, 0.0) if sg.s is String else float(sg.s))
		else:
			arc.call(float(sg.r), deg_to_rad(float(sg.a)), float(sg.get("b", cfg.bank_turn)))
	straight.call(first_len * 0.5)
	_raw_bank = st.bank
	return st.pts


func _raw_outline() -> PackedVector2Array:
	if cfg.has("segments"):
		return _segments_outline()
	var S: float = cfg.back # back stretch
	var R: float = cfg.radius
	var phi := deg_to_rad(float(cfg.get("dog_phi", 0.0)))
	var rd: float = cfg.get("dog_r", 500.0)
	var lc: float = cfg.get("front_mid", S)
	var ls: float = cfg.get("front_side", 0.0)
	# Turtle state lives in a Dictionary: lambdas capture locals by value.
	var st := {"p": Vector2.ZERO, "h": 0.0, "pts": PackedVector2Array()}
	var straight := func(length: float) -> void:
		var steps := int(length / 0.5)
		for i in steps:
			st.pts.append(st.p)
			st.p += Vector2(cos(st.h), sin(st.h)) * (length / steps)
	var arc := func(radius: float, angle: float) -> void:
		var steps: int = max(1, int(radius * angle / 0.5))
		var da := angle / steps
		for i in steps:
			st.pts.append(st.p)
			var mid: float = st.h + da * 0.5
			st.p += Vector2(cos(mid), sin(mid)) * (2.0 * radius * sin(da * 0.5))
			st.h += da
	straight.call(lc * 0.5)
	if phi > 0.0:
		arc.call(rd, phi)
	straight.call(ls)
	arc.call(R, PI - phi)
	straight.call(S)
	arc.call(R, PI - phi)
	straight.call(ls)
	if phi > 0.0:
		arc.call(rd, phi)
	straight.call(lc * 0.5)
	var pts: PackedVector2Array = st.pts
	# Centre the layout on the origin.
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for q in pts:
		mn = mn.min(q)
		mx = mx.max(q)
	var c := (mn + mx) * 0.5
	for i in pts.size():
		pts[i] -= c
	return pts


func _build_centerline() -> void:
	var raw := _raw_outline()
	# Race counter-clockwise seen from above (left turns): reverse the raw outline if needed.
	var raw_area := 0.0
	for i in raw.size():
		var a0 := raw[i]
		var a1 := raw[(i + 1) % raw.size()]
		raw_area += a0.x * a1.y - a1.x * a0.y
	if raw_area > 0.0:
		var rr := PackedVector2Array()
		var rb := PackedFloat32Array()
		for i in raw.size():
			rr.append(raw[(raw.size() - i) % raw.size()])
			if _raw_bank.size() == raw.size():
				rb.append(_raw_bank[(raw.size() - i) % raw.size()])
		raw = rr
		if _raw_bank.size() == raw.size():
			_raw_bank = rb
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
	var seg_bank := PackedFloat32Array()
	var j := 0
	for i in n:
		var target := i * seg_len
		while cum[j + 1] < target:
			j += 1
		var t: float = (target - cum[j]) / max(cum[j + 1] - cum[j], 0.0001)
		var p := raw[j].lerp(raw[(j + 1) % raw.size()], t)
		pos[i] = Vector3(p.x, 0.0, p.y)
		if _raw_bank.size() == raw.size():
			seg_bank.append(_raw_bank[j])
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
	if seg_bank.size() == n:
		# Segment layouts: each corner has its own banking; ease it in and out, and
		# tilt it the right way for right-hand corners.
		var bw := int(40.0 / seg_len)
		for i in n:
			var acc := 0.0
			for o in range(-bw, bw + 1):
				acc += seg_bank[(i + o + n) % n]
			var mag := deg_to_rad(acc / (2 * bw + 1))
			bank[i] = mag * (-1.0 if curv[i] < -0.0005 else 1.0)


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


## Pit road runs along the inside of the front stretch, between the apron and the
## inner wall. Entry (commitment line) is at the end of turn 4, exit at turn 1.
func front_length() -> float:
	if _front_len > 0.0:
		return _front_len
	return float(cfg.get("front_mid", 0.0)) + 2.0 * float(cfg.get("front_side", 0.0)) + 2.0 * float(cfg.get("dog_r", 0.0)) * deg_to_rad(float(cfg.get("dog_phi", 0.0)))


func pit_half() -> float:
	return max(front_length() * 0.5 - 15.0, 60.0)


func pit_in_s() -> float:
	return length - pit_half()


func pit_out_s() -> float:
	return pit_half()


func pit_lane_d() -> float:
	return apron_edge() - infield * 0.5


## Is track position s along the pit road (between entry and exit, across the line)?
func in_pit_zone(s_pos: float) -> bool:
	var ss := fposmod(s_pos, length)
	return ss >= pit_in_s() or ss <= pit_out_s()


## Pit road plus its entry and exit lanes (paved, off the racing surface).
func in_pit_roadway(s_pos: float) -> bool:
	var ss := fposmod(s_pos, length)
	return ss >= pit_in_s() - PIT_LANE_EXT or ss <= pit_out_s() + PIT_LANE_EXT


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


## Fastest steady speed through sample i for a nominal car: the tyres (with load
## sensitivity and downforce) must supply the in-plane lateral force the banking
## doesn't. Mirrors the model in car.gd.
func corner_speed(i: int, mu0: float, cla_v: float) -> float:
	var k: float = curv[i]
	if abs(k) < 0.00002:
		return 200.0
	var b: float = bank[i]
	var lo := 5.0
	var hi := 160.0
	for _it in 28:
		var u := (lo + hi) * 0.5
		var nz: float = CAR_MASS * (G * cos(b) + u * u * k * sin(b)) + 0.5 * 1.2 * cla_v * u * u * 0.95
		nz = max(nz, CAR_MASS * 2.0)
		var mu_e: float = mu0 * pow(nz / (CAR_MASS * G), -0.3)
		var need: float = abs(u * u * k * cos(b) - G * sin(b))
		if need <= mu_e * nz / CAR_MASS * 0.96:
			lo = u
		else:
			hi = u
	return lo


func _build_profile() -> void:
	# Corner speeds for a nominal car, then a backwards pass for the braking zones.
	speed_profile.resize(n)
	var seg := length / n
	var cla_v: float = cfg.get("cla", 2.2)
	for i in n:
		speed_profile[i] = corner_speed(i, 1.0, cla_v)
	var decel := 13.0
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
# Geometry is sorted into one surface per material kind (asphalt, grass, concrete,
# paint lines, scenery, lamps) so each can get its own retro or modern material.

func _st_for(kind: String) -> SurfaceTool:
	if not _st.has(kind):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[kind] = st
	return _st[kind]


## a,b on sample i; c,d on sample i+1 (a->b left to right). n0/n1 are optional
## smooth normals for the two edges; otherwise the face normal is used.
func _quad(kind: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, n0 := Vector3.ZERO, n1 := Vector3.ZERO) -> void:
	var st := _st_for(kind)
	if n0 == Vector3.ZERO:
		n0 = (b - a).cross(c - a).normalized()
		if n0 == Vector3.ZERO:
			n0 = (d - b).cross(c - b).normalized()
		n1 = n0
	st.set_color(col)
	st.set_normal(n0)
	st.add_vertex(a)
	st.set_normal(n1)
	st.add_vertex(c)
	st.set_normal(n0)
	st.add_vertex(b)
	st.add_vertex(b)
	st.set_normal(n1)
	st.add_vertex(c)
	st.add_vertex(d)


func _commit_surfaces() -> void:
	for kind in _st:
		var mi := MeshInstance3D.new()
		mi.mesh = _st[kind].commit()
		mi.material_override = Game.make_mat(kind)
		mi.name = "Surface_" + kind
		if kind == "lamp":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_st.clear()


func _pt(i: int, d: float) -> Vector3:
	i = (i + n) % n
	return pos[i] + right[i] * d + Vector3.UP * height_at(d, bank[i])


## Surface normal of the banked racing surface at sample i.
func _road_up(i: int, tilt: float) -> Vector3:
	i = (i + n) % n
	var rb := (right[i] * cos(tilt) + Vector3.UP * sin(tilt)).normalized()
	return rb.cross(fwd[i]).normalized()


func _build_mesh() -> void:
	var hw := width * 0.5
	var iw := inner_wall()
	var ae := apron_edge()
	var grass: Color = cfg.grass
	var sponsor_cols := [Color(0.9, 0.1, 0.1), Color(0.1, 0.3, 0.9), Color(1.0, 0.8, 0.1), Color(0.1, 0.6, 0.2), Color(0.95, 0.95, 0.95), Color(0.9, 0.4, 0.05)]
	var wall_h := 1.2
	var fence_h := 5.0
	var apron_tilt := atan(0.35 / apron)
	var up := Vector3.UP
	for i in n:
		var i2 := (i + 1) % n
		var stripe := (i / 3) % 2 == 0
		var shade := 1.0 if stripe else 0.97
		var asphalt := Color(0.30, 0.30, 0.32) * shade
		asphalt.a = 1.0
		var groove := Color(0.24, 0.24, 0.26) * shade
		groove.a = 1.0
		var ru0 := _road_up(i, bank[i])
		var ru1 := _road_up(i2, bank[i2])
		var au0 := _road_up(i, apron_tilt)
		var au1 := _road_up(i2, apron_tilt)
		# infield grass strip (or pit road along the front stretch) + inner wall
		var seg_s := i * (length / n)
		if in_pit_roadway(seg_s) and in_pit_roadway(seg_s + length / n):
			var pl := pit_lane_d()
			var pw := infield * 0.4
			_quad("grass", _pt(i, iw), _pt(i, pl - pw), _pt(i2, iw), _pt(i2, pl - pw), grass * 0.9, up, up)
			_quad("asphalt", _pt(i, pl - pw), _pt(i, ae), _pt(i2, pl - pw), _pt(i2, ae), Color(0.36, 0.36, 0.38) * shade, up, up)
			_quad("line", _pt(i, pl + pw * 0.55) + up * 0.02, _pt(i, pl + pw * 0.62) + up * 0.02, _pt(i2, pl + pw * 0.55) + up * 0.02, _pt(i2, pl + pw * 0.62) + up * 0.02, Color(0.95, 0.95, 0.95), up, up)
			if i % 4 == 0:
				# pit box lines
				_quad("line", _pt(i, pl - pw) + up * 0.02, _pt(i, pl) + up * 0.02, _pt(i, pl - pw) + fwd[i] * 0.2 + up * 0.02, _pt(i, pl) + fwd[i] * 0.2 + up * 0.02, Color(1.0, 0.85, 0.1), up, up)
		else:
			_quad("grass", _pt(i, iw), _pt(i, ae), _pt(i2, iw), _pt(i2, ae), grass * (1.0 if stripe else 0.93), up, up)
		_quad("concrete", _pt(i, iw) + up * 0.9, _pt(i, iw), _pt(i2, iw) + up * 0.9, _pt(i2, iw), Color(0.85, 0.85, 0.85))
		# apron
		_quad("asphalt", _pt(i, ae), _pt(i, -hw - 0.7), _pt(i2, ae), _pt(i2, -hw - 0.7), Color(0.42, 0.42, 0.44) * shade, au0, au1)
		# double yellow
		_quad("line", _pt(i, -hw - 0.7), _pt(i, -hw - 0.45), _pt(i2, -hw - 0.7), _pt(i2, -hw - 0.45), Color(1.0, 0.85, 0.1), au0, au1)
		_quad("asphalt", _pt(i, -hw - 0.45), _pt(i, -hw - 0.25), _pt(i2, -hw - 0.45), _pt(i2, -hw - 0.25), Color(0.40, 0.40, 0.42), au0, au1)
		_quad("line", _pt(i, -hw - 0.25), _pt(i, -hw), _pt(i2, -hw - 0.25), _pt(i2, -hw), Color(1.0, 0.85, 0.1), au0, au1)
		# racing surface: bottom lane, rubbered-in groove, upper lane
		_quad("asphalt", _pt(i, -hw), _pt(i, -hw + width * 0.2), _pt(i2, -hw), _pt(i2, -hw + width * 0.2), asphalt, ru0, ru1)
		_quad("asphalt", _pt(i, -hw + width * 0.2), _pt(i, -hw + width * 0.55), _pt(i2, -hw + width * 0.2), _pt(i2, -hw + width * 0.55), groove, ru0, ru1)
		_quad("asphalt", _pt(i, -hw + width * 0.55), _pt(i, hw - 0.6), _pt(i2, -hw + width * 0.55), _pt(i2, hw - 0.6), asphalt, ru0, ru1)
		_quad("line", _pt(i, hw - 0.6), _pt(i, hw), _pt(i2, hw - 0.6), _pt(i2, hw), Color(0.92, 0.92, 0.92), ru0, ru1)
		# outer wall with sponsor panels
		var panel: Color = sponsor_cols[(i / 8) % sponsor_cols.size()]
		var wb := _pt(i, hw)
		var wb2 := _pt(i2, hw)
		_quad("concrete", wb + up * wall_h * 0.45, wb, wb2 + up * wall_h * 0.45, wb2, Color(0.95, 0.95, 0.95))
		_quad("line", wb + up * wall_h, wb + up * wall_h * 0.45, wb2 + up * wall_h, wb2 + up * wall_h * 0.45, panel)
		var ro := right[i] * 0.5
		var ro2 := right[i2] * 0.5
		_quad("concrete", wb + up * wall_h, wb + up * wall_h + ro, wb2 + up * wall_h, wb2 + up * wall_h + ro2, Color(0.8, 0.8, 0.8), up, up)
		# catch fence (thin top rail) and posts every 4th sample
		_quad("scenery", wb + up * fence_h + ro, wb + up * (fence_h - 0.15) + ro, wb2 + up * fence_h + ro2, wb2 + up * (fence_h - 0.15) + ro2, Color(0.55, 0.55, 0.58))
		if i % 4 == 0:
			var f := fwd[i] * 0.15
			var base := wb + up * wall_h + ro
			_quad("scenery", base + up * (fence_h - wall_h) - f, base - f, base + up * (fence_h - wall_h) + f, base + f, Color(0.35, 0.35, 0.38))
		# outside run-off to the ground
		var ob := _pt(i, hw) + ro
		var ob2 := _pt(i2, hw) + ro2
		var og := pos[i] + right[i] * (hw + 25.0)
		var og2 := pos[i2] + right[i2] * (hw + 25.0)
		_quad("grass", ob + up * wall_h, og, ob2 + up * wall_h, og2, grass * 0.85)
	# Start / finish checkers
	for row in 2:
		var cells := int(width)
		for c in cells:
			var d0 := -hw + c * (width / cells)
			var d1 := d0 + width / cells
			var s0 := -1.0 + row * 1.0
			var col := Color.WHITE if (c + row) % 2 == 0 else Color(0.05, 0.05, 0.05)
			var a := surface_point(s0, d0) + up * 0.03
			var b := surface_point(s0, d1) + up * 0.03
			var cc := surface_point(s0 + 1.0, d0) + up * 0.03
			var dd := surface_point(s0 + 1.0, d1) + up * 0.03
			_quad("line", a, b, cc, dd, col)


func _box(kind: String, center: Vector3, size: Vector3, basis: Basis, col: Color) -> void:
	var h := size * 0.5
	var c := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]
	var shade := [0.85, 0.85, 0.75, 0.75, 1.0, 0.6]
	var st := _st_for(kind)
	for fi in faces.size():
		var f: Array = faces[fi]
		var p := []
		for k in 4:
			p.append(center + basis * c[f[k]])
		var nrm: Vector3 = ((p[1] - p[0]) as Vector3).cross(p[2] - p[0]).normalized()
		st.set_color(Color(col.r * shade[fi], col.g * shade[fi], col.b * shade[fi]))
		st.set_normal(nrm)
		st.add_vertex(p[0])
		st.add_vertex(p[2])
		st.add_vertex(p[1])
		st.add_vertex(p[0])
		st.add_vertex(p[3])
		st.add_vertex(p[2])


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cfg.name)
	var hw := width * 0.5
	var night: bool = cfg.get("night", false)
	# Grandstands along the frontstretch, outside the wall.
	var stand_len := float(cfg.get("front_mid", 0.0)) + 2.0 * float(cfg.get("front_side", 0.0)) + 2.0 * float(cfg.get("dog_r", 0.0)) * deg_to_rad(float(cfg.get("dog_phi", 0.0)))
	stand_len *= 0.9
	var crowd := [Color(0.9, 0.2, 0.2), Color(0.2, 0.3, 0.9), Color(1, 1, 1), Color(1, 0.8, 0.2), Color(0.3, 0.8, 0.3), Color(0.9, 0.5, 0.1), Color(0.6, 0.2, 0.7)]
	var seg := length / n
	var rows := 14
	var up := Vector3.UP
	for i in n:
		var s := i * seg
		var sd: float = min(s, length - s)
		if sd > stand_len * 0.5:
			continue
		var i2 := (i + 1) % n
		for r in rows:
			var d0 := hw + 8.0 + r * 2.2
			var h0 := 2.0 + r * 1.3
			var a := pos[i] + right[i] * d0 + up * h0
			var b := pos[i] + right[i] * (d0 + 2.2) + up * h0
			var c := pos[i2] + right[i2] * d0 + up * h0
			var d := pos[i2] + right[i2] * (d0 + 2.2) + up * h0
			var col: Color = crowd[rng.randi() % crowd.size()] if rng.randf() < 0.8 else Color(0.5, 0.5, 0.55)
			_quad("seats", a, b, c, d, col * (0.8 if night else 1.0), up, up)
			# riser
			_quad("concrete", b, b + up * 1.3, d, d + up * 1.3, Color(0.45, 0.45, 0.5))
		# back wall of the stand
		var top := hw + 8.0 + rows * 2.2
		var bt := pos[i] + right[i] * top
		var bt2 := pos[i2] + right[i2] * top
		_quad("concrete", bt + up * (2.0 + rows * 1.3 + 3.0), bt, bt2 + up * (2.0 + rows * 1.3 + 3.0), bt2, Color(0.55, 0.55, 0.6))
		# roof
		var roof_h := 2.0 + rows * 1.3 + 3.0
		_quad("scenery", pos[i] + right[i] * (hw + 14.0) + up * roof_h, bt + up * roof_h, pos[i2] + right[i2] * (hw + 14.0) + up * roof_h, bt2 + up * roof_h, Color(0.75, 0.75, 0.8))
	# Scoring pylon in the infield at start/finish.
	var pyl := pos[0] + right[0] * (inner_wall() - 30.0)
	_box("scenery", pyl + up * 16.0, Vector3(4, 32, 4), Basis.IDENTITY, Color(0.2, 0.2, 0.25))
	for k in 10:
		_box("lamp" if night else "scenery", pyl + up * (3.0 + k * 2.8) + right[0] * 2.05, Vector3(0.1, 2.2, 3.2), Basis(up, atan2(right[0].x, right[0].z)), crowd[k % crowd.size()])
	# Flag stand gantry over the start/finish line.
	var b0 := Basis(up, atan2(fwd[0].x, fwd[0].z))
	var p_in := surface_point(0.0, -hw - 1.5)
	var p_out := surface_point(0.0, hw + 0.5)
	var top_y: float = max(p_in.y, p_out.y) + 9.0
	_box("scenery", Vector3(p_in.x, (p_in.y + top_y) * 0.5, p_in.z), Vector3(0.6, top_y - p_in.y, 0.6), b0, Color(0.8, 0.8, 0.8))
	_box("scenery", Vector3(p_out.x, (p_out.y + top_y) * 0.5, p_out.z), Vector3(0.6, top_y - p_out.y, 0.6), b0, Color(0.8, 0.8, 0.8))
	var mid := (p_in + p_out) * 0.5
	mid.y = top_y
	_box("scenery", mid, Vector3(p_in.distance_to(p_out) + 1.0, 1.6, 1.2), Basis(up, atan2(right[0].x, right[0].z) - PI * 0.5), Color(0.1, 0.1, 0.12))
	# Infield buildings / haulers.
	for k in 14:
		var t := float(k) / 14.0
		var idx := int(t * n * 0.35 + n * 0.08) % n
		var p := pos[idx] + right[idx] * (inner_wall() - 22.0 - rng.randf() * 20.0)
		var truck_col: Color = crowd[rng.randi() % crowd.size()]
		_box("scenery", p + up * 2.0, Vector3(3.0, 4.0, 16.0), Basis(up, atan2(fwd[idx].x, fwd[idx].z) + 0.4), truck_col)
	# Light towers for night tracks. In modern mode each one gets a real spotlight
	# so the volumetric fog shows beams.
	if night:
		for i in range(0, n, max(1, n / 16)):
			var lp := pos[i] + right[i] * (hw + 6.0)
			_box("scenery", lp + up * 17.0, Vector3(0.8, 34, 0.8), Basis.IDENTITY, Color(0.4, 0.4, 0.45))
			_box("lamp", lp + up * 34.0, Vector3(4.0, 2.5, 1.0), Basis(up, atan2(right[i].x, right[i].z)), Color(1.0, 1.0, 0.9))
			var spot := SpotLight3D.new()
			add_child(spot)
			spot.position = lp + up * 33.0 - right[i] * 1.0
			spot.look_at(pos[i] - right[i] * 6.0, up)
			spot.light_color = Color(1.0, 0.95, 0.85)
			spot.light_energy = 9.0
			spot.spot_range = 150.0
			spot.spot_angle = 50.0
			spot.spot_attenuation = 0.6
			spot.light_volumetric_fog_energy = 0.6
			spot.shadow_enabled = false
			if Game.forward_plus:
				spot.add_to_group("modern_only")
				spot.visible = Game.modern
			else:
				spot.visible = false # too many lights for the browser renderer

	# Ground plane
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000, 9000)
	ground.mesh = pm
	ground.material_override = Game.make_mat("ground", cfg.grass)
	ground.position.y = -0.15
	add_child(ground)

	if cfg.get("lake", false):
		var lake := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = cfg.radius * 0.45
		cm.bottom_radius = cfg.radius * 0.45
		cm.height = 0.05
		cm.radial_segments = 48
		lake.mesh = cm
		lake.material_override = Game.make_mat("water", Color(0.12, 0.28, 0.45))
		lake.position = Vector3(0, -0.08, 0)
		lake.scale = Vector3(2.2, 1, 0.9)
		add_child(lake)

	# Trees outside the track: pines and broadleaf trees, each species one MultiMesh.
	var foliage := Game.make_mat("tree", Color(1, 1, 1))
	var kinds := [_pine_mesh(), _broadleaf_mesh()]
	for kind_i in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = kinds[kind_i]
		var count := 220
		mm.instance_count = count
		for k in count:
			var idx := rng.randi() % n
			var off := hw + 45.0 + rng.randf() * 260.0
			var p := pos[idx] + right[idx] * off
			var sc := 0.7 + rng.randf() * 0.8
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.85, 1.2), sc))
			mm.set_instance_transform(k, Transform3D(b, p))
			var tint := rng.randf_range(0.75, 1.1)
			var col := Color(tint, tint * rng.randf_range(0.95, 1.05), tint * rng.randf_range(0.85, 1.0))
			if night:
				col *= 0.45
			mm.set_instance_color(k, col)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = foliage
		add_child(mmi)


## A pine: trunk and three stacked cones, vertex coloured (the MultiMesh tints it).
static func _pine_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cone(st, Vector3.ZERO, 0.35, 0.25, 3.0, 6, Color(0.3, 0.2, 0.12))
	for t in 3:
		_cone(st, Vector3(0, 2.2 + t * 2.6, 0), 3.6 - t * 0.9, 0.0, 4.2, 9, Color(0.1, 0.26, 0.12).lightened(t * 0.05))
	st.generate_normals()
	return st.commit()


## A broadleaf tree: trunk and a clump of low-poly spheres.
static func _broadleaf_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cone(st, Vector3.ZERO, 0.4, 0.3, 5.0, 6, Color(0.32, 0.22, 0.14))
	var blobs := [Vector3(0, 7.5, 0), Vector3(1.8, 6.5, 0.6), Vector3(-1.6, 6.8, -0.8), Vector3(0.3, 6.2, 1.9), Vector3(-0.4, 9.0, 0.2)]
	var radii := [3.2, 2.4, 2.5, 2.2, 2.0]
	for k in blobs.size():
		_blob(st, blobs[k], radii[k], Color(0.2, 0.36, 0.13).darkened(k * 0.04))
	st.generate_normals()
	return st.commit()


static func _cone(st: SurfaceTool, base: Vector3, r0: float, r1: float, h: float, seg: int, col: Color) -> void:
	st.set_color(col)
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var b0 := base + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var b1 := base + Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		var t0 := base + Vector3(cos(a0) * r1, h, sin(a0) * r1)
		var t1 := base + Vector3(cos(a1) * r1, h, sin(a1) * r1)
		st.add_vertex(b0)
		st.add_vertex(t0)
		st.add_vertex(b1)
		if r1 > 0.0:
			st.add_vertex(b1)
			st.add_vertex(t0)
			st.add_vertex(t1)


static func _blob(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	st.set_color(col)
	var rings := 4
	var seg := 7
	for i in rings:
		var p0 := PI * i / rings
		var p1 := PI * (i + 1) / rings
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var v00 := c + Vector3(sin(p0) * cos(a0), cos(p0), sin(p0) * sin(a0)) * r
			var v01 := c + Vector3(sin(p0) * cos(a1), cos(p0), sin(p0) * sin(a1)) * r
			var v10 := c + Vector3(sin(p1) * cos(a0), cos(p1), sin(p1) * sin(a0)) * r
			var v11 := c + Vector3(sin(p1) * cos(a1), cos(p1), sin(p1) * sin(a1)) * r
			st.add_vertex(v00)
			st.add_vertex(v01)
			st.add_vertex(v10)
			st.add_vertex(v01)
			st.add_vertex(v11)
			st.add_vertex(v10)


## Chain-link catch fence on top of the outside wall (Modern look; the 1999 look
## keeps just the rail and posts). UVs run along the wall so the mesh pattern is even.
func _build_fence() -> void:
	var hw := width * 0.5
	var wall_h := 1.2
	var fence_h := 5.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var u := 0.0
	var tile := 0.6 # metres per texture repeat
	for i in n:
		var i2 := (i + 1) % n
		var ro := right[i] * 0.5
		var ro2 := right[i2] * 0.5
		var a := _pt(i, hw) + ro + Vector3.UP * wall_h
		var b := _pt(i2, hw) + ro2 + Vector3.UP * wall_h
		var du := a.distance_to(b) / tile
		var vt := (fence_h - wall_h) / tile
		var nrm := -right[i]
		st.set_normal(nrm)
		st.set_uv(Vector2(u, vt))
		st.add_vertex(a)
		st.set_uv(Vector2(u, 0))
		st.add_vertex(a + Vector3.UP * (fence_h - wall_h))
		st.set_uv(Vector2(u + du, vt))
		st.add_vertex(b)
		st.add_vertex(b)
		st.set_uv(Vector2(u, 0))
		st.add_vertex(a + Vector3.UP * (fence_h - wall_h))
		st.set_uv(Vector2(u + du, 0))
		st.add_vertex(b + Vector3.UP * (fence_h - wall_h))
		u = fmod(u + du, 64.0)
	var mi := MeshInstance3D.new()
	mi.name = "CatchFence"
	mi.mesh = st.commit()
	mi.material_override = Game.make_mat("fence", Color(0.7, 0.72, 0.75))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_to_group("modern_only")
	mi.visible = Game.modern
	add_child(mi)


## Fans in the frontstretch grandstands: one MultiMesh of little people in team
## colours (Modern look).
func _build_crowd() -> void:
	var stand_len := float(cfg.get("front_mid", 0.0)) + 2.0 * float(cfg.get("front_side", 0.0)) + 2.0 * float(cfg.get("dog_r", 0.0)) * deg_to_rad(float(cfg.get("dog_phi", 0.0)))
	stand_len *= 0.9
	var hw := width * 0.5
	var rows := 14
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cfg.name) + 7
	# Mostly everyday colours with some team gear mixed in.
	var shirts := [Color(0.9, 0.9, 0.88), Color(0.9, 0.9, 0.88), Color(0.12, 0.12, 0.14), Color(0.12, 0.12, 0.14), Color(0.35, 0.36, 0.4),
		Color(0.2, 0.28, 0.5), Color(0.45, 0.55, 0.7), Color(0.6, 0.15, 0.12), Color(0.85, 0.7, 0.2), Color(0.25, 0.4, 0.25), Color(0.75, 0.35, 0.12)]
	var xforms: Array[Transform3D] = []
	var cols: Array[Color] = []
	var seg := length / n
	var spacing := 0.7
	for i in n:
		var s := i * seg
		var sd: float = min(s, length - s)
		if sd > stand_len * 0.5:
			continue
		var per := int(seg / spacing)
		for r in rows * 2:
			# Two rows of seats on each 2.2 m step.
			var d0 := hw + 8.0 + (r / 2) * 2.2 + 0.55 + (r % 2) * 1.1
			var h0 := 2.0 + (r / 2) * 1.3
			for k in per:
				if rng.randf() > 0.85:
					continue # empty seat
				var t := (k + rng.randf_range(0.1, 0.9)) / per
				var i2 := (i + 1) % n
				var p: Vector3 = pos[i].lerp(pos[i2], t) + right[i].lerp(right[i2], t).normalized() * (d0 + rng.randf_range(-0.3, 0.3))
				p.y = h0
				var facing := -right[i]
				var b := Basis.looking_at(facing, Vector3.UP).scaled(Vector3.ONE * rng.randf_range(0.9, 1.1))
				xforms.append(Transform3D(b, p))
				cols.append(shirts[rng.randi() % shirts.size()])
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _fan_mesh()
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
		mm.set_instance_color(k, cols[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Crowd"
	mmi.multimesh = mm
	mmi.material_override = Game.make_mat("crowd", Color(1, 1, 1))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.add_to_group("modern_only")
	mmi.visible = Game.modern
	add_child(mmi)


## One seated fan: torso and head (the instance colour is the shirt).
static func _fan_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box_st(st, Vector3(0, 0.45, 0), Vector3(0.44, 0.6, 0.28), Color(1, 1, 1))
	_box_st(st, Vector3(0, 0.9, 0), Vector3(0.2, 0.24, 0.22), Color(0.9, 0.75, 0.6))
	st.generate_normals()
	return st.commit()


static func _box_st(st: SurfaceTool, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var v := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]
	st.set_color(col)
	for f in faces:
		st.add_vertex(c + v[f[0]])
		st.add_vertex(c + v[f[2]])
		st.add_vertex(c + v[f[1]])
		st.add_vertex(c + v[f[0]])
		st.add_vertex(c + v[f[3]])
		st.add_vertex(c + v[f[2]])
