extends Node3D
## What rain does to the picture:
##  - a water film on the racing surface, glossy where it's wet and dull where
##    the cars have dried a line (it follows the weather's wet bands);
##  - spray thrown up behind the cars nearest the camera, thick enough to hide
##    the car in front at speed;
##  - beads on the windshield (cockpit and bumper views) or the lens (chase),
##    with a wiper sweep in the cockpit.

const SPRAY_POOL := 10
const FILM_STEP := 4 # track samples per film row (keeps the mesh small)

var track: Node3D
var weather: Node
var film: MeshInstance3D
var _film_mat := StandardMaterial3D.new()
var _film_wet := PackedFloat32Array()
var spray: Array[GPUParticles3D] = []
var spray_cpu: Array[CPUParticles3D] = []
var spray_car: Array = []
var glass: MeshInstance3D
var glass_mat: ShaderMaterial
var _wipe_t := -1.0
var _refill := 1.0
var _wipe_timer := 0.0
var _time := 0.0
var _film_timer := 0.0


func setup(t: Node3D, w: Node, cam: Camera3D) -> void:
	track = t
	weather = w
	_build_film()
	_build_spray()
	if glass == null:
		glass = MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1, 1)
		glass.mesh = qm
		glass_mat = ShaderMaterial.new()
		glass_mat.shader = load("res://shaders/windshield.gdshader")
		glass_mat.render_priority = 90
		glass.material_override = glass_mat
		glass.extra_cull_margin = 16384.0
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glass.position = Vector3(0, 0, -0.5)
		glass.visible = false
		cam.add_child(glass)


func clear() -> void:
	if film:
		film.queue_free()
		film = null
	for p in spray:
		p.queue_free()
	for p in spray_cpu:
		p.queue_free()
	spray.clear()
	spray_cpu.clear()
	spray_car.clear()
	if glass:
		glass.visible = false


## A thin sheet laid over the racing surface, one column per wet band.
func _build_film() -> void:
	if track == null or weather == null:
		return
	var bands: int = weather.BANDS
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: int = int(track.n / FILM_STEP)
	var hw: float = track.width * 0.5
	for r in rows:
		var i: int = r * FILM_STEP
		var i2: int = ((r + 1) % rows) * FILM_STEP
		for b in bands:
			var d0: float = -hw + float(b) / bands * track.width
			var d1: float = -hw + float(b + 1) / bands * track.width
			var a: Vector3 = track._pt(i, d0) + Vector3.UP * 0.025
			var bb: Vector3 = track._pt(i, d1) + Vector3.UP * 0.025
			var c: Vector3 = track._pt(i2, d1) + Vector3.UP * 0.025
			var dd: Vector3 = track._pt(i2, d0) + Vector3.UP * 0.025
			# UV.x carries the band so the colours can be refreshed cheaply.
			for v in [[a, b], [bb, b], [c, b], [a, b], [c, b], [dd, b]]:
				st.set_uv(Vector2(float(v[1]) + 0.5, 0.0))
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
	film = MeshInstance3D.new()
	film.mesh = st.commit()
	_film_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_film_mat.albedo_color = Color(0.03, 0.035, 0.04, 0.0)
	_film_mat.roughness = 0.04
	_film_mat.metallic_specular = 1.0
	_film_mat.albedo_texture = _band_texture(bands)
	_film_mat.uv1_scale = Vector3(1.0 / bands, 1, 1)
	_film_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	film.material_override = _film_mat
	film.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	film.visible = false
	add_child(film)


var _band_img: Image
var _band_tex: ImageTexture


func _band_texture(bands: int) -> Texture2D:
	_band_img = Image.create(bands, 1, false, Image.FORMAT_RGBA8)
	_band_img.fill(Color(1, 1, 1, 0))
	_band_tex = ImageTexture.create_from_image(_band_img)
	return _band_tex


func _refresh_film() -> void:
	if film == null or weather == null:
		return
	var any := false
	for b in weather.wet.size():
		var w: float = weather.wet[b]
		any = any or w > 0.02
		_band_img.set_pixel(b, 0, Color(1, 1, 1, clamp(w * 1.1, 0.0, 0.85)))
	_band_tex.update(_band_img)
	film.visible = any
	_film_mat.albedo_color.a = 1.0


## Mist behind the rear tyres: a pool of emitters handed to the nearest cars.
func _build_spray() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.2, 2.2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _puff_texture()
	quad.material = m
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([Color(0.85, 0.87, 0.9, 0.0), Color(0.85, 0.87, 0.9, 0.55), Color(0.85, 0.87, 0.9, 0.0)])
	for k in SPRAY_POOL:
		if Game.forward_plus:
			var p := GPUParticles3D.new()
			var pm := ParticleProcessMaterial.new()
			pm.direction = Vector3(0, 0.35, 1)
			pm.spread = 18.0
			pm.initial_velocity_min = 4.0
			pm.initial_velocity_max = 9.0
			pm.gravity = Vector3(0, -1.0, 0)
			pm.damping_min = 2.0
			pm.damping_max = 3.0
			pm.scale_min = 1.0
			pm.scale_max = 2.6
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = Vector3(0.9, 0.1, 0.2)
			var gt := GradientTexture1D.new()
			gt.gradient = ramp
			pm.color_ramp = gt
			var sc := Curve.new()
			sc.add_point(Vector2(0, 0.5))
			sc.add_point(Vector2(1, 1.6))
			var ct := CurveTexture.new()
			ct.curve = sc
			pm.scale_curve = ct
			p.process_material = pm
			p.draw_pass_1 = quad
			p.amount = 60
			p.lifetime = 1.1
			p.local_coords = false
			p.emitting = false
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			p.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 15, 60))
			add_child(p)
			spray.append(p)
		else:
			var p := CPUParticles3D.new()
			p.mesh = quad
			p.direction = Vector3(0, 0.35, 1)
			p.spread = 18.0
			p.initial_velocity_min = 4.0
			p.initial_velocity_max = 9.0
			p.gravity = Vector3(0, -1.0, 0)
			p.damping_min = 2.0
			p.damping_max = 3.0
			p.scale_amount_min = 1.0
			p.scale_amount_max = 2.6
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			p.emission_box_extents = Vector3(0.9, 0.1, 0.2)
			p.color_ramp = ramp
			p.amount = 30
			p.lifetime = 1.0
			p.local_coords = false
			p.emitting = false
			add_child(p)
			spray_cpu.append(p)
		spray_car.append(null)


static func _puff_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 32
	t.height = 32
	return t


func update(delta: float, race: Node3D, cam: Camera3D, view: String, focus: Node3D) -> void:
	_time += delta
	var rain: float = weather.rain if weather else 0.0
	var wet: float = weather.average_wet() if weather else 0.0
	_film_timer -= delta
	if _film_timer <= 0.0:
		_film_timer = 1.0
		_refresh_film()
	# Spray: the nearest cars going quickly on a wet track.
	var emitters: Array = spray if not spray.is_empty() else spray_cpu
	if emitters.is_empty() or race == null:
		return
	var near: Array = []
	if wet > 0.08:
		for c in race.cars:
			if c.towed or not c.visible or c.speed() < 18.0:
				continue
			var local_wet: float = track.wet_at(c.d)
			if local_wet < 0.08:
				continue
			near.append([c.global_position.distance_squared_to(cam.global_position), c, local_wet])
		near.sort_custom(func(a, b): return a[0] < b[0])
	for k in emitters.size():
		var p = emitters[k]
		if k < near.size():
			var c: Node3D = near[k][1]
			var lw: float = near[k][2]
			var xf: Transform3D = c.global_transform
			p.global_transform = Transform3D(xf.basis, xf * Vector3(0, 0.35, 2.4))
			if p is GPUParticles3D:
				p.amount_ratio = clamp(lw * c.speed() / 70.0, 0.1, 1.0)
				var pm: ParticleProcessMaterial = p.process_material
				pm.initial_velocity_min = c.speed() * 0.05
				pm.initial_velocity_max = c.speed() * 0.12
			p.emitting = true
		else:
			p.emitting = false
	# Glass: drops while it rains (and a little after, off the cars in front).
	if glass == null:
		return
	var on_glass: float = rain
	if focus and wet > 0.1:
		on_glass = max(on_glass, wet * 0.4)
	var inside: bool = view == "cockpit" or view == "bumper"
	glass.visible = on_glass > 0.02 and view != "" and Game.modern
	if not glass.visible:
		return
	# The cockpit has a wiper: a sweep every couple of seconds in heavy rain.
	if view == "cockpit":
		_wipe_timer -= delta
		if _wipe_t < 0.0 and _wipe_timer <= 0.0:
			_wipe_t = 0.0
			_wipe_timer = lerp(4.0, 1.4, clamp(on_glass, 0.0, 1.0))
		if _wipe_t >= 0.0:
			_wipe_t += delta / 0.45
			if _wipe_t >= 1.0:
				_wipe_t = -1.0
				_refill = 0.0
	else:
		_wipe_t = -1.0
	# Heavy rain covers the glass again almost as soon as the blade has passed.
	_refill = min(_refill + delta / lerp(2.0, 0.5, clamp(on_glass, 0.0, 1.0)), 1.0)
	glass_mat.set_shader_parameter("amount", clamp(on_glass, 0.0, 1.0))
	glass_mat.set_shader_parameter("speed", clamp(focus.speed() / 90.0 if focus else 0.0, 0.0, 1.2))
	glass_mat.set_shader_parameter("wipe", _wipe_t)
	glass_mat.set_shader_parameter("refill", _refill)
	glass_mat.set_shader_parameter("time_s", _time)
	glass_mat.set_shader_parameter("density", 1.0 if inside else 0.35)
