extends RefCounted
## Builds the Modern-look stock car: the Cup-class (Next Gen) body from the
## showroom study, built to published dimensions (110 in wheelbase, 193.4 in
## long, 18 in single-lug wheels). The body is lofted from cross-sections along
## the car, each a smooth curve from the underside round the rocker, door,
## shoulder and greenhouse to the roof centre; the wheel arches are cut out and
## the flares swell round the wheels. Glass, the driver's window net, the carbon
## rockers, splitter, diffuser, spoiler and a roll cage you can see through the
## glass complete it. Each team's colours, numbers and sponsors go on top.
##
## The body mesh can be dented in place (see dent()) so damage shows where the car
## was actually hit. Near cars use a fine mesh, far ones a coarse one.
##
## Car space: -Z forward, +X right, +Y up. The study's tables below use its own
## axes (x forward along the car, z across it); _g() converts.

# Stations along the car (m, + = forward) and at each: the roof / greenhouse top,
# the beltline, the underside and the body's half width.
const X := [-2.44, -2.39, -2.22, -1.85, -0.7, 0.05, 0.95, 1.6, 2.2, 2.4, 2.47]
const YT := [0.58, 0.9, 0.95, 0.93, 1.25, 1.25, 0.84, 0.77, 0.62, 0.46, 0.34]
const YL := [0.58, 0.88, 0.92, 0.9, 0.86, 0.85, 0.83, 0.81, 0.63, 0.47, 0.34]
const YB := [0.3, 0.22, 0.16, 0.14, 0.13, 0.13, 0.13, 0.13, 0.14, 0.14, 0.2]
const HW := [0.84, 0.92, 0.95, 0.96, 0.96, 0.96, 0.96, 0.96, 0.93, 0.84, 0.76]
const AXLES := [-1.36, 1.43] # rear and front axle stations
const ARCH_R := 0.405 # wheel arch radius
const LIFT := 0.03 # the study's floor sits 3 cm below its origin
const WHEEL_Y := 0.351 # wheel centre height = tyre radius
const WHEEL_X := 0.83 # half track
const NC := 13 # control points round each half cross-section

# Tyre cross-section (radius, axial) from the inner bead round the tread to the outer.
const TYRE := [[0.238, -0.149], [0.262, -0.159], [0.292, -0.167], [0.321, -0.163], [0.339, -0.149], [0.348, -0.126], [0.3505, -0.08], [0.351, 0.0], [0.3505, 0.08], [0.348, 0.126], [0.339, 0.149], [0.321, 0.163], [0.292, 0.167], [0.262, 0.159], [0.238, 0.149]]
const RIM := [[0.236, -0.149], [0.229, -0.142], [0.222, -0.12], [0.221, 0.02], [0.224, 0.1], [0.229, 0.138], [0.235, 0.148]]

# Shared by every car (they don't depend on the team): built once.
static var _shared := {}


## Study coordinates -> car space.
static func _g(x: float, y: float, z: float) -> Vector3:
	return Vector3(z, y + LIFT, -x)


## The study's Catmull-Rom interpolation of a station table at x.
static func _cr(t: Array, x: float) -> float:
	var i := 0
	while i < X.size() - 2 and x > float(X[i + 1]):
		i += 1
	var u: float = clamp((x - float(X[i])) / (float(X[i + 1]) - float(X[i])), 0.0, 1.0)
	var p0: float = t[max(0, i - 1)]
	var p1: float = t[i]
	var p2: float = t[i + 1]
	var p3: float = t[min(t.size() - 1, i + 2)]
	return 0.5 * (2.0 * p1 + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)


## How much the wheel flares swell the body at x (1 at an axle).
static func _flare(x: float) -> float:
	var s := 0.0
	for w in AXLES:
		s += exp(-pow((x - float(w)) / 0.55, 2.0))
	return s


## The cross-section at x: heights and the half widths of its parts.
static func sec(x: float) -> Dictionary:
	var yt := _cr(YT, x)
	var yb := _cr(YB, x)
	var hw := _cr(HW, x)
	var fl := _flare(x)
	var yl := _cr(YL, x) + 0.03 * fl
	var gh: float = clamp((yt - yl) / 0.12, 0.0, 1.0) # 1 where there's a greenhouse
	var hw_s := hw - 0.02 + 0.02 * fl
	return {"yt": yt, "yb": yb, "hw": hw, "yl": yl, "gh": gh, "hw_l": hw - 0.015, "hw_m": hw + 0.035 * fl, "hw_s": hw_s,
		"rw": hw * 0.75 * (1.0 - gh) + 0.66 * gh, "gw": (hw_s - 0.1) * (1.0 - gh) + 0.82 * gh}


## The half cross-section's control points (half width, height).
static func _ring(s: Dictionary) -> Array:
	var yb: float = s.yb
	var yl: float = s.yl
	var yt: float = s.yt
	var gh: float = s.gh
	var d := yl - yb
	var rh: float = min(0.15, 0.3 * d)
	var hw_l: float = s.hw_l
	var hw_m: float = s.hw_m
	var hw_s: float = s.hw_s
	var rw: float = s.rw
	return [Vector2(0, yb), Vector2(hw_l - 0.1, yb), Vector2(hw_l, yb + rh * 0.25), Vector2(hw_l, yb + rh * 0.87),
		Vector2(hw_l - 0.02, yb + rh), Vector2(hw_m, yb + 0.55 * d), Vector2(hw_m - 0.01, yb + 0.82 * d),
		Vector2(hw_s + 0.01, yb + 0.94 * d), Vector2(hw_s - 0.05, yl), Vector2(s.gw, yl + 0.015 * gh),
		Vector2(rw, ((yl + yt) * 0.5) * (1.0 - gh) + (yt - 0.05) * gh), Vector2(rw * 0.55, yt), Vector2(0, yt)]


## n + 1 points evenly spaced in parameter along a centripetal Catmull-Rom curve
## through `pts` (as three.js's CatmullRomCurve3 does it).
static func _crc(pts: Array, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var l := pts.size()
	for k in n + 1:
		var p := (l - 1) * float(k) / n
		var ip := int(floor(p))
		var w := p - ip
		if w == 0.0 and ip == l - 1:
			ip = l - 2
			w = 1.0
		var p0: Vector2 = pts[ip - 1] if ip > 0 else pts[0] * 2.0 - pts[1]
		var p1: Vector2 = pts[ip]
		var p2: Vector2 = pts[ip + 1]
		var p3: Vector2 = pts[ip + 2] if ip + 2 < l else pts[l - 1] * 2.0 - pts[l - 2]
		var dt0 := pow(p0.distance_squared_to(p1), 0.25)
		var dt1 := pow(p1.distance_squared_to(p2), 0.25)
		var dt2 := pow(p2.distance_squared_to(p3), 0.25)
		if dt1 < 1e-4:
			dt1 = 1.0
		if dt0 < 1e-4:
			dt0 = dt1
		if dt2 < 1e-4:
			dt2 = dt1
		var t1 := ((p1 - p0) / dt0 - (p2 - p0) / (dt0 + dt1) + (p2 - p1) / dt1) * dt1
		var t2 := ((p2 - p1) / dt1 - (p3 - p1) / (dt1 + dt2) + (p3 - p2) / dt2) * dt1
		var c2 := -3.0 * p1 + 3.0 * p2 - 2.0 * t1 - t2
		var c3 := 2.0 * p1 - 2.0 * p2 + t1 + t2
		out.append(p1 + t1 * w + c2 * w * w + c3 * w * w * w)
	return out


## Stations to build the body at: `step` apart, and `arch_step` round the wheels
## so the arches come out round.
static func _stations(step: float, arch_step: float) -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	var x0: float = X[0]
	var x1: float = X[X.size() - 1]
	var x := x0
	while x < x1 - 1e-4:
		xs.append(x)
		var near := false
		for w in AXLES:
			if abs(x - float(w)) < ARCH_R + 0.06:
				near = true
		x += arch_step if near else step
	xs.append(x1)
	return xs


## The lofted body at one level of detail. Returns the vertex data and, per
## surface (paint, carbon, glass, net), the triangles.
static func _loft(xs: PackedFloat32Array, seg: int) -> Dictionary:
	var half := (NC - 1) * seg + 1
	var ring := 2 * (half - 1)
	var pos := PackedVector3Array()
	var stripe := PackedByteArray() # 1 where the livery's second colour goes
	var uvs := PackedVector2Array()
	var code := PackedByteArray()
	var ns := xs.size()
	for i in ns:
		var x: float = xs[i]
		var s := sec(x)
		var gh: float = s.gh
		var pts := _crc(_ring(s), half - 1)
		for k in ring:
			var j := k if k < half else ring - k
			var sg := 1.0 if k < half else -1.0
			var p: Vector2 = pts[j]
			var ci := float(j) / seg
			pos.append(_g(x, p.y, sg * p.x))
			uvs.append(Vector2(x * 5.0, ci * 4.0))
			# Windows: the side glass (the driver's front part is the net), the
			# windshield and the back glass, each in a carbon frame.
			var r := 0
			var core := false
			var open := false
			if gh > 0.45 and ci >= 9.0 and ci <= 9.875 and x > -1.62 and x < 0.76 and abs(x + 0.33) > 0.04:
				r = 1
				core = ci >= 9.125 and ci <= 9.75 and x > -1.57 and x < 0.72 and abs(x + 0.33) > 0.07
				open = sg < 0.0 and x > -0.33
			if ci >= 10.125 and x > 0.12 and x < 0.92 and gh > 0.3:
				r = 2
				core = ci >= 10.25 and x > 0.2 and x < 0.87 and gh > 0.45
			if ci >= 10.125 and x > -1.8 and x < -0.74 and gh > 0.3:
				r = 3
				core = ci >= 10.25 and x > -1.75 and x < -0.79 and gh > 0.45
			code.append((3 if open else 2) if (r > 0 and core) else (1 if r > 0 else (4 if ci <= 3.3 else 0)))
			# Livery: a stripe along the lower doors, and one down the hood and deck.
			var two := (ci >= 4.0 and ci <= 4.75 and x > -2.3 and x < 2.3) or (ci >= 11.4 and gh < 0.3 and (x > 1.0 or x < -1.9))
			stripe.append(1 if two else 0)
	var tris := [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()] # paint, carbon, glass, net
	for i in ns - 1:
		for k in ring:
			var a := i * ring + k
			var b := i * ring + (k + 1) % ring
			var c := (i + 1) * ring + k
			var dd := (i + 1) * ring + (k + 1) % ring
			# The wheel arches: no body where the wheel is.
			var cen := (pos[a] + pos[b] + pos[c] + pos[dd]) * 0.25
			var cut := false
			if (abs(pos[a].x) + abs(pos[b].x) + abs(pos[c].x) + abs(pos[dd].x)) * 0.25 > 0.5:
				for w in AXLES:
					if pow(-cen.z - float(w), 2.0) + pow(cen.y - WHEEL_Y, 2.0) < ARCH_R * ARCH_R:
						cut = true
			if cut:
				continue
			var q := [code[a], code[b], code[c], code[dd]]
			var layer := 0
			if q.all(func(v): return v >= 1 and v <= 3):
				layer = 3 if q.all(func(v): return v == 3) else (2 if q.all(func(v): return v >= 2) else 1)
			elif q.all(func(v): return v == 4):
				layer = 1
			# (Godot's front faces wind the other way from the study's.)
			tris[layer].append_array(PackedInt32Array([a, b, c, b, dd, c]))
	# Smooth normals over the whole shell.
	var nrm := PackedVector3Array()
	nrm.resize(pos.size())
	for t: PackedInt32Array in tris:
		for n in range(0, t.size(), 3):
			var fa := pos[t[n]]
			var fn := (pos[t[n + 2]] - fa).cross(pos[t[n + 1]] - fa)
			nrm[t[n]] += fn
			nrm[t[n + 1]] += fn
			nrm[t[n + 2]] += fn
	# Nose and tail: flat caps fanned from the middle.
	for end in [0, ns - 1]:
		var base := pos.size()
		var sy := 0.0
		var facing := Vector3(0, 0, 1) if end == 0 else Vector3(0, 0, -1)
		for k in ring:
			var v: int = end * ring + k
			pos.append(pos[v])
			stripe.append(0)
			uvs.append(Vector2.ZERO)
			nrm.append(facing)
			sy += pos[v].y
		pos.append(Vector3(0, sy / ring, pos[end * ring].z))
		stripe.append(0)
		uvs.append(Vector2.ZERO)
		nrm.append(facing)
		var ctr := base + ring
		for k in ring:
			var p0 := pos[ctr]
			var p1 := pos[base + k]
			var p2 := pos[base + (k + 1) % ring]
			if (p2 - p0).cross(p1 - p0).dot(facing) >= 0.0:
				tris[0].append_array(PackedInt32Array([ctr, base + k, base + (k + 1) % ring]))
			else:
				tris[0].append_array(PackedInt32Array([ctr, base + (k + 1) % ring, base + k]))
	for n in nrm.size():
		nrm[n] = nrm[n].normalized() if nrm[n].length_squared() > 0.0 else Vector3.UP
	return {"pos": pos, "nrm": nrm, "stripe": stripe, "uv": uvs, "tris": tris}


## The body at one level of detail, split into its four surfaces (paint,
## carbon, glass, net), each with just the vertices it uses. Built once; every
## car shares it and only adds its colours (and its dents).
static func _lod_data(level: int) -> Dictionary:
	var key := "lod%d" % level
	if _shared.has(key):
		return _shared[key]
	var lv: Array = [[0.08, 0.035, 6], [0.16, 0.09, 2]][level]
	var lod := _loft(_stations(lv[0], lv[1]), lv[2])
	var surfaces := []
	for si in 4:
		var t: PackedInt32Array = lod.tris[si]
		var remap := {}
		var ids := PackedInt32Array()
		var idx := PackedInt32Array()
		idx.resize(t.size())
		for n in t.size():
			var v := t[n]
			if not remap.has(v):
				remap[v] = ids.size()
				ids.append(v)
			idx[n] = remap[v]
		var sp := PackedVector3Array()
		var sn := PackedVector3Array()
		var su := PackedVector2Array()
		var sm := PackedByteArray()
		var jit := PackedVector3Array()
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 3.5 # dents about a hand's width across
		noise.seed = 7
		for v in ids:
			var p: Vector3 = lod.pos[v]
			sp.append(p)
			sn.append(lod.nrm[v])
			su.append(lod.uv[v])
			sm.append(lod.stripe[v])
			# Crumple: smooth noise over the body, so a hit leaves dents rather
			# than foil, and the edges shared between surfaces stay together.
			jit.append(Vector3(noise.get_noise_3dv(p), noise.get_noise_3dv(p + Vector3(17.3, 0, 0)) - 0.3, noise.get_noise_3dv(p + Vector3(0, 0, 31.7))) * 1.6)
		surfaces.append({"pos": sp, "nrm": sn, "uv": su, "stripe": sm, "idx": idx, "jit": jit})
	var data := {"surfaces": surfaces}
	_shared[key] = data
	return data


## A body mesh from shared LOD data: this car's colours, its vertices at `pos`
## (one array per surface; null = undented).
static func _body_mesh(data: Dictionary, cols: PackedColorArray, pos: Array, mats: Array) -> ArrayMesh:
	var am := ArrayMesh.new()
	for si in 4:
		var sf: Dictionary = data.surfaces[si]
		if sf.idx.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos[si] if pos.size() > si and pos[si] != null else sf.pos
		arr[Mesh.ARRAY_NORMAL] = sf.nrm
		arr[Mesh.ARRAY_TEX_UV] = sf.uv
		if si == 0:
			arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = sf.idx
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(am.get_surface_count() - 1, mats[si])
	return am


## Builds the car under `root`. Returns {"lods": [...], "wheels": Array[Node3D]
## spinners, "holders": Array[Node3D], "interior": Node3D, "paint": Material}.
static func build(root: Node3D, team: Dictionary, wheels_parent: Node3D) -> Dictionary:
	var c1: Color = team.c1
	var c2: Color = team.c2
	var cn: Color = team.cn
	var paint := Game.make_mat("livery", Color.WHITE)
	var carbon := Game.make_mat("carbon", Color(0.045, 0.045, 0.05))
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.1, 0.15, 0.2, 0.42)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.3
	glass.roughness = 0.03
	glass.metallic_specular = 1.0
	var mats := [paint, carbon, glass, _net_mat()]

	# The body: a fine mesh up close, a coarse one further away.
	var lods := []
	for level in 2:
		var data := _lod_data(level)
		var sm: PackedByteArray = data.surfaces[0].stripe
		var cols := PackedColorArray()
		cols.resize(sm.size())
		for i in sm.size():
			cols[i] = c2 if sm[i] == 1 else c1
		var mi := MeshInstance3D.new()
		mi.name = "Body" if level == 0 else "BodyFar"
		mi.mesh = _body_mesh(data, cols, [], mats)
		mi.visibility_range_begin = 0.0 if level == 0 else 30.0
		mi.visibility_range_end = 30.0 if level == 0 else 0.0
		root.add_child(mi)
		lods.append({"data": data, "mi": mi, "mats": mats, "cols": cols})

	# Trim, wheel wells, lights and the cage inside: the same for every car.
	if not _shared.has("trim"):
		_build_shared()
	var trim := _instance(root, _shared.trim, carbon)
	trim.visibility_range_end = 0.0
	var wells := StandardMaterial3D.new()
	wells.albedo_color = Color(0.03, 0.03, 0.035)
	wells.roughness = 1.0
	wells.cull_mode = BaseMaterial3D.CULL_DISABLED
	_instance(root, _shared.wells, wells)
	_instance(root, _shared.head, Game.make_mat("light", Color(0.55, 0.55, 0.52))).visibility_range_end = 120.0
	_instance(root, _shared.tail, Game.make_mat("light", Color(0.55, 0.04, 0.03))).visibility_range_end = 120.0
	_instance(root, _shared.pipes, Game.make_mat("chrome", Color(0.62, 0.62, 0.64))).visibility_range_end = 60.0
	var interior := Node3D.new()
	interior.name = "Interior"
	root.add_child(interior)
	var cab := Game.make_mat("plastic", Color(0.2, 0.21, 0.23))
	var cage := Game.make_mat("chrome", Color(0.8, 0.8, 0.8))
	var seat := Game.make_mat("plastic", Color(0.07, 0.07, 0.08))
	for pair in [[_shared.cab, cab], [_shared.cage, cage], [_shared.seat, seat]]:
		_instance(interior, pair[0], pair[1]).visibility_range_end = 40.0

	# Numbers on the doors and roof, each door number on a contrasting panel;
	# the sponsor on the hood and the rear bumper.
	var panel_col := Color(1, 1, 1) if cn.v < 0.5 else Color(0.05, 0.05, 0.05)
	var panel_mat := Game.make_mat("paint", panel_col)
	var door_z := 0.22
	for sx in [-1.0, 1.0]:
		var hm: float = sec(-door_z).hw_m
		var pnl := _box(root, Vector3(0.01, 0.4, 0.82), Vector3(sx * (hm + 0.004), 0.6, door_z), panel_mat)
		pnl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pnl.visibility_range_end = 110.0
		var door := _label(team.num, cn, 150)
		door.position = Vector3(sx * (hm + 0.012), 0.6, door_z)
		door.rotation = Vector3(0, sx * PI * 0.5, 0)
		root.add_child(door)
	var roof := _label(team.num, cn, 170)
	roof.position = Vector3(0, sec(-0.33).yt + LIFT + 0.012, 0.33)
	roof.rotation = Vector3(-PI * 0.5, 0, 0)
	root.add_child(roof)
	var spon := _label(String(team.sponsor), c2 if c2.v > 0.35 else Color(1, 1, 1), 60)
	spon.pixel_size = 0.0042
	spon.position = Vector3(0, sec(1.55).yt + LIFT + 0.012, -1.55)
	spon.rotation = Vector3(-PI * 0.5 + 0.17, 0, 0)
	root.add_child(spon)
	var bumper := _label(String(team.sponsor), Color(1, 1, 1), 40)
	bumper.pixel_size = 0.0036
	bumper.position = Vector3(0, 0.42, 2.452)
	root.add_child(bumper)

	# Wheels: tyre, ten-spoke wheel with a single centre nut, brake disc.
	var tyre_mat := Game.make_mat("rubber", Color(0.06, 0.06, 0.065))
	var rim_mat := Game.make_mat("wheel", Color(0.17, 0.18, 0.2))
	rim_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var chrome := Game.make_mat("chrome", Color(0.72, 0.73, 0.75))
	var lug_mat := Game.make_mat("chrome", Color(0.94, 0.62, 0.15))
	var wheels: Array = []
	var holders: Array = []
	for x in [-WHEEL_X, WHEEL_X]:
		for ax in [AXLES[1], AXLES[0]]: # front then rear
			var holder := Node3D.new()
			holder.position = Vector3(x, WHEEL_Y, -float(ax))
			wheels_parent.add_child(holder)
			var spinner := Node3D.new()
			holder.add_child(spinner)
			var modern := Node3D.new()
			modern.add_to_group("modern_only")
			modern.visible = Game.modern
			spinner.add_child(modern)
			var side := "r" if x > 0.0 else "l"
			_instance(modern, _shared["tyre_" + side], tyre_mat)
			_instance(modern, _shared["wheel_" + side], rim_mat)
			_instance(modern, _shared["chrome_" + side], chrome).visibility_range_end = 70.0
			_instance(modern, _shared["lug_" + side], lug_mat).visibility_range_end = 50.0
			wheels.append(spinner)
			holders.append(holder)
	return {"lods": lods, "wheels": wheels, "holders": holders, "interior": interior, "paint": paint}


## Pushes the body in where it's been hit. `damage` is the car's per-side damage.
static func dent(info: Dictionary, damage: Dictionary, _seed_v: int) -> void:
	var df: float = damage.front
	var dr: float = damage.rear
	var dl: float = damage.left
	var dg: float = damage.right
	for lod: Dictionary in info.lods:
		var moved := []
		for sf: Dictionary in lod.data.surfaces:
			var base: PackedVector3Array = sf.pos
			var jit: PackedVector3Array = sf.jit
			var verts := base.duplicate()
			for i in base.size():
				var p: Vector3 = base[i]
				var amt: float = df * clamp((-p.z - 1.2) / 1.3, 0.0, 1.0) + dr * clamp((p.z - 1.2) / 1.3, 0.0, 1.0) \
					+ dg * clamp((p.x - 0.4) / 0.6, 0.0, 1.0) + dl * clamp((-p.x - 0.4) / 0.6, 0.0, 1.0)
				if amt > 0.0:
					amt = min(amt, 1.2)
					verts[i] = p + (Vector3(-p.x * 0.25, -0.12, -p.z * 0.05) + jit[i] * 0.07) * amt
			moved.append(verts)
		(lod.mi as MeshInstance3D).mesh = _body_mesh(lod.data, lod.cols, moved, lod.mats)


## --- Parts every car shares

static func _build_shared() -> void:
	# Carbon trim: splitter, lower grille blade, side skirts, hood vents, roof
	# flaps, spoiler, diffuser, mirror, arch lips and panel seams.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bx(st, Vector3(1.92, 0.02, 0.5), _g(2.3, 0.11, 0))
	_bx(st, Vector3(1.6, 0.02, 0.12), _g(2.56, 0.11, 0))
	_bx(st, Vector3(1.2, 0.1, 0.04), _g(2.45, 0.25, 0))
	_bx(st, Vector3(0.9, 0.04, 0.04), _g(2.37, 0.47, 0), Vector3(-0.72, 0, 0))
	_bx(st, Vector3(0.9, 0.02, 0.28), _g(2.52, 0.075, 0))
	for s in [1.0, -1.0]:
		_bx(st, Vector3(0.06, 0.09, 1.95), _g(0.04, 0.17, s * 0.985))
		_bx(st, Vector3(0.24, 0.004, 0.42), _g(1.44, 0.803, s * 0.63))
		for i in 6:
			_bx(st, Vector3(0.22, 0.012, 0.022), _g(1.26 + i * 0.07, 0.81, s * 0.63), Vector3(0.5, 0, 0))
		for x in [0.78, -0.33]:
			_bx(st, Vector3(0.004, 0.4, 0.006), _g(x, 0.53, s * (sec(x).hw_m + 0.003)))
		_bx(st, Vector3(0.004, 0.004, 1.95), _g(0.05, 0.28, s * (_cr(HW, 0.0) - 0.012)))
		_bx(st, Vector3(0.015, 0.18, 0.25), _g(-2.33, 0.97, s * 0.94))
		for ax in AXLES:
			var lip := TorusMesh.new()
			lip.inner_radius = ARCH_R - 0.02
			lip.outer_radius = ARCH_R + 0.02
			lip.rings = 40
			lip.ring_segments = 6
			st.append_from(lip, 0, Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)), _g(float(ax), WHEEL_Y - LIFT, s * (sec(float(ax)).hw_m - 0.012))))
	_bx(st, Vector3(1.1, 0.006, 0.004), _g(0.97, 0.848, 0))
	for x in [-0.15, -0.5]:
		_bx(st, Vector3(0.2, 0.006, 0.28), _g(x, 1.256, 0))
	_bx(st, Vector3(0.09, 0.04, 0.07), _g(-2.1, 0.965, 0))
	_bx(st, Vector3(1.88, 0.15, 0.02), _g(-2.40, 0.99, 0), Vector3(0.15, 0, 0))
	for z in [-0.6, 0.0, 0.6]:
		_bx(st, Vector3(0.02, 0.08, 0.07), _g(-2.36, 0.92, z))
	_bx(st, Vector3(1.7, 0.015, 0.6), _g(-2.15, 0.1, 0))
	for z in [-0.7, -0.35, 0.0, 0.35, 0.7]:
		_bx(st, Vector3(0.015, 0.13, 0.6), _g(-2.17, 0.17, z))
	_bx(st, Vector3(0.06, 0.07, 0.14), _g(0.74, 0.93, -0.87))
	_bx(st, Vector3(0.03, 0.04, 0.16), _g(0.2, sec(0.2).yt - 0.06, 0))
	_shared.trim = st.commit()
	# Wheel wells: dark open drums behind the arches.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ax in AXLES:
		for s in [1.0, -1.0]:
			var well := CylinderMesh.new()
			well.top_radius = 0.39
			well.bottom_radius = 0.39
			well.height = 0.36
			well.radial_segments = 24
			well.rings = 1
			well.cap_top = false
			well.cap_bottom = false
			st.append_from(well, 0, Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)), _g(float(ax), WHEEL_Y - LIFT, s * 0.78)))
	_shared.wells = st.commit()
	# Lights: headlight decals on the nose, a tail-light bar across the back.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [1.0, -1.0]:
		_bx(st, Vector3(0.36, 0.012, 0.22), _g(2.31, 0.565, s * 0.56), Vector3(-0.72, 0, 0))
	_shared.head = st.commit()
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bx(st, Vector3(1.5, 0.07, 0.02), _g(-2.445, 0.5, 0))
	_shared.tail = st.commit()
	# Side exhausts.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [1.0, -1.0]:
		for x in [-0.75, -0.88]:
			var pipe := CylinderMesh.new()
			pipe.top_radius = 0.045
			pipe.bottom_radius = 0.045
			pipe.height = 0.1
			pipe.radial_segments = 12
			pipe.rings = 1
			pipe.cap_top = false
			pipe.cap_bottom = false
			st.append_from(pipe, 0, Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)), _g(x, 0.2, s * 0.99)))
	_shared.pipes = st.commit()
	_build_interior()
	for side in ["l", "r"]:
		_build_wheel(side)


## What you see through the glass: floor, bulkhead, dash, the seat and the cage.
static func _build_interior() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bx(st, Vector3(1.6, 0.02, 2.4), _g(-0.35, 0.19, 0))
	_bx(st, Vector3(1.6, 0.62, 0.02), _g(-1.05, 0.5, 0))
	_bx(st, Vector3(1.5, 0.1, 0.18), _g(0.72, 0.68, 0))
	_shared.cab = st.commit()
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bx(st, Vector3(0.46, 0.07, 0.45), _g(0.08, 0.27, -0.38))
	_bx(st, Vector3(0.48, 0.64, 0.07), _g(-0.14, 0.6, -0.38), Vector3(0.18, 0, 0))
	for dz in [-0.2, 0.2]:
		_bx(st, Vector3(0.04, 0.22, 0.22), _g(-0.06, 0.86, -0.38 + dz), Vector3(0.18, 0, 0))
	var sw := TorusMesh.new()
	sw.inner_radius = 0.134
	sw.outer_radius = 0.166
	sw.rings = 24
	sw.ring_segments = 6
	st.append_from(sw, 0, Transform3D(Basis.from_euler(Vector3(PI * 0.5 - 0.35, 0, 0)), _g(0.44, 0.68, -0.38)))
	_shared.seat = st.commit()
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [1.0, -1.0]:
		_tube(st, [[-0.33, 0.2, s * 0.78], [-0.33, 0.8, s * 0.8], [-0.33, 1.06, s * 0.66], [-0.33, 1.17, s * 0.42], [-0.33, 1.19, 0]])
		var fp := [[0.92, 0.2, s * 0.8]]
		for x in [0.85, 0.7, 0.5, 0.3, 0.15]:
			var q := sec(x)
			fp.append([x, max(0.8, float(q.yt) - 0.1), s * (min(float(q.rw), 0.8) - 0.07)])
		_tube(st, fp)
		_tube(st, [[0.15, float(sec(0.15).yt) - 0.1, s * 0.42], [-0.1, 1.18, s * 0.42], [-0.33, 1.17, s * 0.42]])
		_tube(st, [[-0.33, 1.15, s * 0.5], [-0.95, 0.9, s * 0.55], [-1.5, 0.45, s * 0.6]])
		_tube(st, [[0.8, 0.45, s * 0.76], [0.2, 0.5, s * 0.78], [-0.33, 0.55, s * 0.78]])
	var yc := float(sec(0.15).yt)
	_tube(st, [[0.15, yc - 0.1, -0.42], [0.15, yc - 0.08, 0], [0.15, yc - 0.1, 0.42]])
	_tube(st, [[-0.33, 0.25, -0.78], [-0.33, 0.7, 0], [-0.33, 1.19, 0.4]])
	_shared.cage = st.commit()


## One side's wheel parts (the lathes face out on that side).
static func _build_wheel(side: String) -> void:
	var o := 1.0 if side == "r" else -1.0
	var tyre_pts := _crc(TYRE.map(func(p): return Vector2(p[0], p[1])), 24)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(_lathe(tyre_pts, 36, o), 0, Transform3D())
	# Dark backing behind the spokes.
	var back := CylinderMesh.new()
	back.top_radius = 0.222
	back.bottom_radius = 0.222
	back.height = 0.004
	back.radial_segments = 24
	back.rings = 0
	st.append_from(back, 0, Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)), Vector3(o * -0.09, 0, 0)))
	_shared["tyre_" + side] = st.commit()
	# Wheel: barrel, ten spokes, hub.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim_pts := PackedVector2Array()
	for p in RIM:
		rim_pts.append(Vector2(p[0], p[1]))
	st.append_from(_lathe(rim_pts, 36, o), 0, Transform3D())
	for i in 5:
		var spoke := BoxMesh.new()
		spoke.size = Vector3(0.015, 0.46, 0.028)
		st.append_from(spoke, 0, Transform3D(Basis.from_euler(Vector3(i * PI / 5.0, 0, 0)), Vector3(o * 0.112, 0, 0)))
	var hub := CylinderMesh.new()
	hub.top_radius = 0.066
	hub.bottom_radius = 0.074
	hub.height = 0.05
	hub.radial_segments = 16
	hub.rings = 0
	st.append_from(hub, 0, Transform3D(Basis.from_euler(Vector3(0, 0, -o * PI * 0.5)), Vector3(o * 0.09, 0, 0)))
	_shared["wheel_" + side] = st.commit()
	# Polished lip and the brake disc behind the spokes.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lip := TorusMesh.new()
	lip.inner_radius = 0.231
	lip.outer_radius = 0.245
	lip.rings = 36
	lip.ring_segments = 4
	st.append_from(lip, 0, Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)), Vector3(o * 0.15, 0, 0)))
	var rotor := CylinderMesh.new()
	rotor.top_radius = 0.2
	rotor.bottom_radius = 0.2
	rotor.height = 0.032
	rotor.radial_segments = 24
	rotor.rings = 0
	st.append_from(rotor, 0, Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)), Vector3.ZERO))
	_shared["chrome_" + side] = st.commit()
	# The single centre nut.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nut := CylinderMesh.new()
	nut.top_radius = 0.043
	nut.bottom_radius = 0.046
	nut.height = 0.045
	nut.radial_segments = 6
	nut.rings = 0
	st.append_from(nut, 0, Transform3D(Basis.from_euler(Vector3(0, 0, -o * PI * 0.5)), Vector3(o * 0.132, 0, 0)))
	_shared["lug_" + side] = st.commit()


## A surface of revolution about the X axis: `pts` are (radius, axial), axial
## pointing outwards on side `o`.
static func _lathe(pts: PackedVector2Array, segs: int, o: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size() - 1:
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var p00 := Vector3(o * pts[i].y, pts[i].x * cos(a0), pts[i].x * sin(a0))
			var p10 := Vector3(o * pts[i + 1].y, pts[i + 1].x * cos(a0), pts[i + 1].x * sin(a0))
			var p01 := Vector3(o * pts[i].y, pts[i].x * cos(a1), pts[i].x * sin(a1))
			var p11 := Vector3(o * pts[i + 1].y, pts[i + 1].x * cos(a1), pts[i + 1].x * sin(a1))
			if o > 0.0:
				for p in [p00, p10, p01, p10, p11, p01]:
					st.add_vertex(p)
			else:
				for p in [p00, p01, p10, p10, p01, p11]:
					st.add_vertex(p)
	st.index()
	st.generate_normals()
	return st.commit()


## A box into a merged mesh.
static func _bx(st: SurfaceTool, size: Vector3, p: Vector3, rot := Vector3.ZERO) -> void:
	var b := BoxMesh.new()
	b.size = size
	st.append_from(b, 0, Transform3D(Basis.from_euler(rot), p))


## A roll-cage tube along points given in the study's coordinates.
static func _tube(st: SurfaceTool, pts: Array) -> void:
	for i in pts.size() - 1:
		var a := _g(pts[i][0], pts[i][1], pts[i][2])
		var b := _g(pts[i + 1][0], pts[i + 1][1], pts[i + 1][2])
		var cy := CylinderMesh.new()
		cy.top_radius = 0.018
		cy.bottom_radius = 0.018
		cy.height = a.distance_to(b) + 0.02
		cy.radial_segments = 6
		cy.rings = 0
		cy.cap_top = false
		cy.cap_bottom = false
		var y := (b - a).normalized()
		var x := Vector3.UP.cross(y)
		if x.length() < 0.01:
			x = Vector3.RIGHT
		x = x.normalized()
		st.append_from(cy, 0, Transform3D(Basis(x, y, x.cross(y).normalized()), (a + b) * 0.5))


## The driver's window net: a dark grid with see-through holes.
static func _net_mat() -> Material:
	if not _shared.has("net_mat"):
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		img.fill_rect(Rect2i(0, 0, 64, 9), Color(0.05, 0.05, 0.05, 1))
		img.fill_rect(Rect2i(0, 0, 9, 64), Color(0.05, 0.05, 0.05, 1))
		var m := StandardMaterial3D.new()
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.4
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 1.0
		_shared.net_mat = m
	return _shared.net_mat


static func _instance(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _box(root: Node3D, size: Vector3, p: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = p
	root.add_child(mi)
	return mi


static func _label(text: String, col: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Game.arcade_font
	l.font_size = size
	l.pixel_size = 0.0035
	l.modulate = col
	l.outline_size = 20
	l.outline_modulate = Color(0, 0, 0)
	l.double_sided = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.visibility_range_end = 80.0
	return l
