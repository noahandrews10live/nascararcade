extends RefCounted
## Builds the Modern-look stock car: a lofted Next Gen style body (cross-sections
## along the length, mirrored left/right) with a painted livery, glass, splitter,
## spoiler, diffuser, lights and detailed wheels. The body mesh can be dented in
## place (see dent()) so damage shows where the car was actually hit.
##
## Car space: -Z forward, +X right, +Y up; 5.0 m long, 1.95 m wide.

# Stations along the car: z, half width, sill height, beltline (hood / door top / deck),
# roof height and roof half width (roof == belt where there's no greenhouse).
# The low sills at the wheel stations open the wheel arches.
const STATIONS := [
	# z      w      sill   belt   roof   roof_w
	[-2.50, 0.86, 0.16, 0.40, 0.40, 0.70],
	[-2.42, 0.93, 0.13, 0.60, 0.60, 0.78],
	[-2.20, 0.965, 0.13, 0.74, 0.74, 0.82],
	[-1.95, 0.975, 0.24, 0.80, 0.80, 0.84],
	[-1.78, 0.975, 0.55, 0.83, 0.83, 0.84],
	[-1.50, 0.975, 0.70, 0.87, 0.87, 0.84],
	[-1.22, 0.975, 0.55, 0.90, 0.90, 0.84],
	[-1.05, 0.975, 0.22, 0.92, 0.92, 0.84],
	[-0.55, 0.975, 0.20, 0.96, 0.98, 0.80],
	[-0.10, 0.972, 0.20, 0.98, 1.27, 0.70],
	[0.25, 0.970, 0.20, 0.99, 1.33, 0.66],
	[0.95, 0.968, 0.22, 1.00, 1.32, 0.64],
	[1.05, 0.968, 0.22, 1.00, 1.28, 0.66],
	[1.20, 0.968, 0.55, 1.00, 1.20, 0.70],
	[1.45, 0.968, 0.70, 1.00, 1.10, 0.76],
	[1.70, 0.968, 0.55, 1.00, 1.03, 0.82],
	[1.88, 0.965, 0.24, 1.00, 1.00, 0.84],
	[2.30, 0.955, 0.20, 1.02, 1.02, 0.84],
	[2.50, 0.93, 0.22, 0.98, 0.98, 0.82],
]

# Which profile bands are glass: side windows between these z values, the
# windshield and the rear window (the slopes of the greenhouse).
const SIDE_GLASS_Z := Vector2(-0.35, 0.9)


## Right-half profile at one station, 9 points from the sill round to the roof centre.
static func _profile(st: Array) -> Array:
	var w: float = st[1]
	var sill: float = st[2]
	var belt: float = st[3]
	var roof: float = st[4]
	var rw: float = st[5]
	var has_glass := roof > belt + 0.05
	var shoulder_w := w - 0.05
	var mid: float = min(0.5, belt - 0.2)
	var pts := [
		Vector3(w - 0.03, sill, 0),                # 0 sill
		Vector3(w, max(sill + 0.08, 0.24), 0),     # 1 rocker
		Vector3(w, max(mid, sill + 0.1), 0),       # 2 stripe line
		Vector3(w, belt - 0.14, 0),                # 3 door top
		Vector3(shoulder_w, belt, 0),              # 4 shoulder
	]
	if has_glass:
		pts.append(Vector3(rw + 0.08, belt + 0.03, 0))       # 5 window base
		pts.append(Vector3(rw, roof - 0.04, 0))              # 6 window top
		pts.append(Vector3(rw * 0.6, roof, 0))               # 7 roof edge
	else:
		# Hood / deck crown: gently rounded toward the centre.
		pts.append(Vector3(shoulder_w * 0.8, belt + 0.02, 0))
		pts.append(Vector3(shoulder_w * 0.55, belt + 0.035, 0))
		pts.append(Vector3(shoulder_w * 0.3, belt + 0.045, 0))
	pts.append(Vector3(0, roof + (0.0 if has_glass else 0.05), 0)) # 8 centre
	return pts


## Builds the car under `root`. Returns {"body": MeshInstance3D, "base": PackedVector3Array,
## "arrays": Array, "wheels": Array[Node3D] spinners, "holders": Array[Node3D]}.
static func build(root: Node3D, team: Dictionary, wheels_parent: Node3D) -> Dictionary:
	var c1: Color = team.c1
	var c2: Color = team.c2
	var cn: Color = team.cn
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profiles: Array = []
	for s in STATIONS:
		var p := _profile(s)
		for k in p.size():
			p[k].z = s[0]
		profiles.append(p)
	# Loft the sides and top, mirrored.
	for i in profiles.size() - 1:
		var a: Array = profiles[i]
		var b: Array = profiles[i + 1]
		var za: float = STATIONS[i][0]
		var zb: float = STATIONS[i + 1][0]
		var zm := (za + zb) * 0.5
		var greenhouse: bool = float(STATIONS[i][4]) > float(STATIONS[i][3]) + 0.05 and float(STATIONS[i + 1][4]) > float(STATIONS[i + 1][3]) + 0.05
		for k in a.size() - 1:
			var col := c1
			# Livery: a contrasting band along the lower doors and a hood / deck stripe.
			if k == 1 and zm > -2.3 and zm < 2.4:
				col = c2
			if k == 7 and not greenhouse and (zm < -0.6 or zm > 1.9):
				col = c2
			var glass := false
			if greenhouse and k == 5 and zm > SIDE_GLASS_Z.x and zm < SIDE_GLASS_Z.y:
				glass = true # side window
			if greenhouse and k >= 5 and (zm < -0.1 or zm > 1.0):
				glass = true # windshield / rear window
			if greenhouse and k == 7 and zm > -0.1 and zm < 1.0:
				glass = false
			for side in [1.0, -1.0]:
				var m := Vector3(side, 1, 1)
				var p0: Vector3 = a[k] * m
				var p1: Vector3 = a[k + 1] * m
				var p2: Vector3 = b[k] * m
				var p3: Vector3 = b[k + 1] * m
				_quad(gst if glass else st, p0, p1, p2, p3, Color(0.05, 0.06, 0.08) if glass else col, side > 0.0)
	# Nose and tail caps (fans from the centre line).
	for cap in [0, profiles.size() - 1]:
		var pr: Array = profiles[cap]
		var z: float = STATIONS[cap][0]
		var centre := Vector3(0, (float(STATIONS[cap][2]) + float(STATIONS[cap][3])) * 0.5, z)
		for k in pr.size() - 1:
			for side in [1.0, -1.0]:
				var m := Vector3(side, 1, 1)
				var p0: Vector3 = pr[k] * m
				var p1: Vector3 = pr[k + 1] * m
				var front: bool = cap == 0
				var flip: bool = (side > 0.0) == front
				st.set_color(c1 if k != 1 else c2)
				if flip:
					st.add_vertex(centre)
					st.add_vertex(p0)
					st.add_vertex(p1)
				else:
					st.add_vertex(centre)
					st.add_vertex(p1)
					st.add_vertex(p0)
	st.generate_normals()
	gst.generate_normals()
	var paint := Game.make_mat("livery", Color.WHITE)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var arrays := st.commit_to_arrays()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, paint)
	body.mesh = am
	root.add_child(body)
	var glass_mi := MeshInstance3D.new()
	glass_mi.name = "Glass"
	glass_mi.mesh = gst.commit()
	glass_mi.material_override = Game.make_mat("glass", Color(0.05, 0.06, 0.08))
	root.add_child(glass_mi)

	var carbon := Game.make_mat("carbon", Color(0.04, 0.04, 0.045))
	# Underbody (hides the inside through the wheel arches), splitter, diffuser, skirts.
	_part(root, Vector3(1.78, 0.5, 4.7), Vector3(0, 0.38, 0), carbon)
	_part(root, Vector3(1.9, 0.04, 0.35), Vector3(0, 0.09, -2.4), carbon)
	_part(root, Vector3(1.7, 0.18, 0.3), Vector3(0, 0.2, 2.42), carbon)
	for sx in [-1.0, 1.0]:
		_part(root, Vector3(0.06, 0.1, 1.6), Vector3(sx * 0.96, 0.2, 0.05), carbon)
	# Rear spoiler: blade on two stanchions.
	_part(root, Vector3(1.8, 0.13, 0.02), Vector3(0, 1.1, 2.47), carbon, true)
	for sx in [-0.6, 0.6]:
		_part(root, Vector3(0.02, 0.1, 0.12), Vector3(sx, 1.06, 2.42), carbon, true)
	# Lights: Next Gen cars wear headlight / tail-light decals.
	var head := Game.make_mat("light", Color(0.5, 0.48, 0.42))
	var tail := Game.make_mat("light", Color(0.85, 0.05, 0.04))
	for sx in [-1.0, 1.0]:
		var hl := _part(root, Vector3(0.42, 0.1, 0.2), Vector3(sx * 0.6, 0.66, -2.36), head, true)
		hl.rotation.x = -0.5
		_part(root, Vector3(0.5, 0.08, 0.02), Vector3(sx * 0.55, 0.9, 2.505), tail, true)
	# Grille opening.
	_part(root, Vector3(0.9, 0.16, 0.02), Vector3(0, 0.3, -2.505), carbon, true)
	# Window net on the driver's side and a roll bar hint through the glass.
	var net := Game.make_mat("carbon", Color(0.1, 0.1, 0.1))
	_part(root, Vector3(0.01, 0.26, 0.5), Vector3(-0.78, 1.12, 0.35), net, true)

	# Numbers: doors and roof, each on a contrasting panel. Sponsor on the hood.
	var panel_col := Color(1, 1, 1) if cn.v < 0.5 else Color(0.05, 0.05, 0.05)
	var panel_mat := Game.make_mat("paint", panel_col)
	for sx in [-1.0, 1.0]:
		var pnl := _part(root, Vector3(0.01, 0.42, 0.95), Vector3(sx * 0.982, 0.62, -0.05), panel_mat, true)
		pnl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var door := _label(team.num, cn, 170)
		door.position = Vector3(sx * 0.99, 0.62, -0.05)
		door.rotation = Vector3(0, sx * PI * 0.5, 0)
		root.add_child(door)
	var roof := _label(team.num, cn, 220)
	roof.position = Vector3(0, 1.345, 0.6)
	roof.rotation = Vector3(-PI * 0.5, 0, 0)
	root.add_child(roof)
	var spon := _label(String(team.sponsor), c2 if c2.v > 0.35 else Color(1, 1, 1), 60)
	spon.pixel_size = 0.0045
	spon.position = Vector3(0, 0.99, -1.45)
	spon.rotation = Vector3(-PI * 0.5 + 0.06, 0, 0)
	root.add_child(spon)
	var bumper := _label(String(team.sponsor), Color(1, 1, 1), 40)
	bumper.pixel_size = 0.004
	bumper.position = Vector3(0, 0.62, 2.51)
	root.add_child(bumper)

	# Wheels: tyre with a sidewall, single-lug wheel, all on spinners the car turns.
	var tyre_mat := Game.make_mat("rubber", Color(0.06, 0.06, 0.065))
	var rim_mat := Game.make_mat("wheel", Color(0.08, 0.08, 0.09))
	var lug_mat := Game.make_mat("chrome", Color(0.8, 0.8, 0.82))
	var letter_mat := Game.make_mat("paint", Color(0.95, 0.8, 0.1))
	var tyre := CylinderMesh.new()
	tyre.top_radius = 0.345
	tyre.bottom_radius = 0.345
	tyre.height = 0.31
	tyre.radial_segments = 22
	tyre.rings = 1
	var rim := CylinderMesh.new()
	rim.top_radius = 0.23
	rim.bottom_radius = 0.23
	rim.height = 0.012
	rim.radial_segments = 18
	rim.rings = 0
	var lug := CylinderMesh.new()
	lug.top_radius = 0.045
	lug.bottom_radius = 0.06
	lug.height = 0.06
	lug.radial_segments = 8
	lug.rings = 0
	var ring := TorusMesh.new()
	ring.inner_radius = 0.28
	ring.outer_radius = 0.3
	ring.rings = 18
	ring.ring_segments = 4
	var wheels: Array = []
	var holders: Array = []
	for x in [-0.84, 0.84]:
		for z in [-1.5, 1.45]:
			var holder := Node3D.new()
			holder.position = Vector3(x, 0.345, z)
			wheels_parent.add_child(holder)
			var spinner := Node3D.new()
			holder.add_child(spinner)
			var modern := Node3D.new()
			modern.add_to_group("modern_only")
			modern.visible = Game.modern
			spinner.add_child(modern)
			var t := MeshInstance3D.new()
			t.mesh = tyre
			t.material_override = tyre_mat
			t.rotation = Vector3(0, 0, PI * 0.5)
			modern.add_child(t)
			var out_x: float = sign(x)
			var r := MeshInstance3D.new()
			r.mesh = rim
			r.material_override = rim_mat
			r.rotation = Vector3(0, 0, PI * 0.5)
			r.position.x = out_x * 0.15
			modern.add_child(r)
			var l := MeshInstance3D.new()
			l.mesh = lug
			l.material_override = lug_mat
			l.rotation = Vector3(0, 0, -out_x * PI * 0.5)
			l.position.x = out_x * 0.17
			l.visibility_range_end = 60.0
			modern.add_child(l)
			# Yellow sidewall lettering hint.
			var ringi := MeshInstance3D.new()
			ringi.mesh = ring
			ringi.material_override = letter_mat
			ringi.rotation = Vector3(0, 0, PI * 0.5)
			ringi.position.x = out_x * 0.155
			ringi.visibility_range_end = 45.0
			ringi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			modern.add_child(ringi)
			wheels.append(spinner)
			holders.append(holder)
	return {"body": body, "base": arrays[Mesh.ARRAY_VERTEX], "arrays": arrays, "wheels": wheels, "holders": holders, "paint": paint}


## Pushes the body in where it's been hit. `damage` is the car's per-side damage.
static func dent(info: Dictionary, damage: Dictionary, seed_v: int) -> void:
	var base: PackedVector3Array = info.base
	var verts := PackedVector3Array()
	verts.resize(base.size())
	var rng := RandomNumberGenerator.new()
	for i in base.size():
		var p: Vector3 = base[i]
		var amt := 0.0
		amt += float(damage.front) * clamp((-p.z - 1.2) / 1.3, 0.0, 1.0)
		amt += float(damage.rear) * clamp((p.z - 1.2) / 1.3, 0.0, 1.0)
		amt += float(damage.right) * clamp((p.x - 0.4) / 0.6, 0.0, 1.0)
		amt += float(damage.left) * clamp((-p.x - 0.4) / 0.6, 0.0, 1.0)
		amt = min(amt, 1.2)
		if amt <= 0.0:
			verts[i] = p
			continue
		# Same position always gets the same crumple, so the mesh doesn't tear.
		rng.seed = hash(Vector3i(roundi(p.x * 50.0), roundi(p.y * 50.0), roundi(p.z * 50.0))) ^ seed_v
		var push := Vector3(-p.x * 0.25, -0.12, -p.z * 0.05) * amt
		push += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 0.4), rng.randf_range(-1, 1)) * 0.07 * amt
		verts[i] = p + push
	var arrays: Array = info.arrays.duplicate()
	arrays[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, info.paint)
	(info.body as MeshInstance3D).mesh = am


static func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, col: Color, right_side: bool) -> void:
	st.set_color(col)
	if right_side:
		st.add_vertex(p0)
		st.add_vertex(p2)
		st.add_vertex(p1)
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(p3)
	else:
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(p1)
		st.add_vertex(p3)
		st.add_vertex(p2)


static func _part(root: Node3D, size: Vector3, p: Vector3, m: Material, detail := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = p
	if detail:
		mi.visibility_range_end = 110.0
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
