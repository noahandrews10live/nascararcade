extends Node3D
## The track remembers the race. Every car lays a little rubber where it drives,
## so the line the field actually uses darkens and gains grip lap by lap, and
## worn-off rubber (marbles) collects just outside it where it's slippery. Hits
## leave scuffs of tyre rubber and paint on the walls.
##
## One grid of cells (along the track x across it) drives both the grip model
## (track.grip_at) and the overlay drawn on the surface.

const BANDS := 24
const ROW_STEP := 6 # track samples per row
const PASSES_FULL := 120.0 # passes over a cell for a fully rubbered groove
const MAX_SCUFFS := 600

var track: Node3D
var rows := 0
var rubber := PackedFloat32Array() # passes per cell
var marbles := PackedFloat32Array() # 0..1
var _img: Image
var _tex: ImageTexture
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _refresh := 0.0
var _scuffs: MultiMeshInstance3D
var _scuff_next := 0
var _scuff_count := 0
var _last_scuff := {}


func setup(t: Node3D) -> void:
	track = t
	rows = max(int(track.n / ROW_STEP), 8)
	rubber.resize(rows * BANDS)
	rubber.fill(0.0)
	marbles.resize(rows * BANDS)
	marbles.fill(0.0)
	_img = Image.create_empty(BANDS, rows, false, Image.FORMAT_RG8)
	_img.fill(Color(0, 0, 0))
	_tex = ImageTexture.create_from_image(_img)
	_build_overlay()
	_build_scuffs()


func cell(s: float, d: float) -> int:
	var row: int = int(fposmod(s, track.length) / track.length * rows) % rows
	var x: float = (d + track.width * 0.5) / track.width
	if x < 0.0 or x >= 1.0:
		return -1
	return row * BANDS + int(x * BANDS)


## 0..1: how rubbered-in the surface is here.
func rubber_at(s: float, d: float) -> float:
	var i := cell(s, d)
	return clamp(rubber[i] / PASSES_FULL, 0.0, 1.0) if i >= 0 else 0.0


func marbles_at(s: float, d: float) -> float:
	var i := cell(s, d)
	return marbles[i] if i >= 0 else 0.0


## Each physics tick: every car at speed lays rubber over the cells under it.
func track_cars(cars: Array, delta: float) -> void:
	var cell_len: float = track.length / rows
	for c in cars:
		if c.towed or c.pit_state >= 2 or c.on_grass or c.tumbling:
			continue
		var sp: float = c.speed()
		if sp < 15.0:
			continue
		var i := cell(c.s(), c.d)
		if i < 0:
			continue
		# One pass over a cell adds one; sliding cars lay (and tear off) more.
		var add: float = sp * delta / cell_len * (1.0 + c.slide * 2.0)
		rubber[i] += add
		if i % BANDS > 0:
			rubber[i - 1] += add * 0.35
		if i % BANDS < BANDS - 1:
			rubber[i + 1] += add * 0.35
		# Worn rubber is thrown to the outside of the turn: marbles land beyond
		# the line.
		var k: float = track.curvature_at(c.s())
		if abs(k) > 0.0015 and sp > 25.0:
			var shift: int = (2 + int(abs(c.vy) * 0.3)) * (1 if k > 0.0 else -1)
			var b: int = (i % BANDS) + shift
			if b >= 0 and b < BANDS:
				marbles[i + shift] = min(marbles[i + shift] + add * 0.0016 * (1.0 + c.slide * 3.0), 1.0)
		# Driving over marbles picks them up again (and the line stays clean).
		marbles[i] = max(marbles[i] - add * 0.01, 0.0)


## Wall scuffs where cars hit.
func scuff(c: Node3D) -> void:
	if _scuffs == null or c.wall_hit < 2.0:
		return
	var s: float = c.s()
	var last: float = _last_scuff.get(c, -1e9)
	if abs(s - last) < 1.2:
		return
	_last_scuff[c] = s
	var outer: bool = c.d > 0.0
	var wall_d: float = (track.outer_edge() + 0.02) if outer else (track.inner_wall() - 0.02)
	if abs(c.d - wall_d) > 2.5:
		return
	var p: Vector3 = track.surface_point(s, wall_d) + Vector3.UP * (0.25 + randf() * 0.35)
	var fwd: Vector3 = track.fwd_at(s)
	var nrm: Vector3 = -track.right_at(s) if outer else track.right_at(s)
	var len: float = clamp(c.speed() * 0.08, 0.8, 4.0)
	var b := Basis(fwd * len, Vector3.UP * (0.15 + c.wall_hit * 0.01), nrm)
	_scuffs.multimesh.set_instance_transform(_scuff_next, Transform3D(b, p + nrm * 0.03))
	var paint: Color = c.team.get("c1", Color(0.2, 0.2, 0.2))
	_scuffs.multimesh.set_instance_color(_scuff_next, (Color(0.05, 0.05, 0.05) if randf() < 0.5 else paint) * Color(1, 1, 1, 0.8))
	_scuff_next = (_scuff_next + 1) % MAX_SCUFFS
	_scuff_count = min(_scuff_count + 1, MAX_SCUFFS)
	_scuffs.multimesh.visible_instance_count = _scuff_count


func _build_scuffs() -> void:
	_scuffs = MultiMeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = qm
	mm.instance_count = MAX_SCUFFS
	mm.visible_instance_count = 0
	_scuffs.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.7
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 8
	m.albedo_texture = t
	_scuffs.material_override = m
	_scuffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_scuffs)


## The rubber and marbles overlay: one quad per cell row, UV addressing the grid.
func _build_overlay() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw: float = track.width * 0.5
	for r in rows:
		var i: int = r * ROW_STEP
		var i2: int = ((r + 1) % rows) * ROW_STEP
		var v0: float = float(r) / rows
		var v1: float = float(r + 1) / rows
		for k in 4:
			var d0: float = -hw + k / 4.0 * track.width
			var d1: float = -hw + (k + 1) / 4.0 * track.width
			var u0: float = k / 4.0
			var u1: float = (k + 1) / 4.0
			var a: Vector3 = track._pt(i, d0) + Vector3.UP * 0.018
			var b: Vector3 = track._pt(i, d1) + Vector3.UP * 0.018
			var c: Vector3 = track._pt(i2, d1) + Vector3.UP * 0.018
			var dd: Vector3 = track._pt(i2, d0) + Vector3.UP * 0.018
			var quad := [[a, Vector2(u0, v0)], [b, Vector2(u1, v0)], [c, Vector2(u1, v1)], [a, Vector2(u0, v0)], [c, Vector2(u1, v1)], [dd, Vector2(u0, v1)]]
			for q in quad:
				st.set_uv(q[1])
				st.set_uv2(Vector2(q[0].x, q[0].z) * 0.5)
				st.set_normal(Vector3.UP)
				st.add_vertex(q[0])
	_mesh = MeshInstance3D.new()
	_mesh.mesh = st.commit()
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/track_wear.gdshader")
	_mat.set_shader_parameter("wear", _tex)
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0.0 or track == null:
		return
	_refresh = 2.0
	for r in rows:
		for b in BANDS:
			var i: int = r * BANDS + b
			_img.set_pixel(b, r, Color(clamp(rubber[i] / PASSES_FULL, 0.0, 1.0), marbles[i], 0.0))
	_tex.update(_img)
