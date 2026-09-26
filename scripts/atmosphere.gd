extends Node
## Depth and air: haze that thickens with distance and hangs low at dawn and
## dusk, shafts of sunlight through smoke (HIGH and up on desktop), smoke that
## hangs in the air after a wreck, a touch of focus blur at speed, and glare
## when you look into the sun.

const MAX_SMOKE := 6

var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var attrs: CameraAttributesPractical
var flare: MeshInstance3D
var flare_mat: ShaderMaterial
var smoke: Array = [] # [FogVolume, age, life]
var _smoke_mat: FogMaterial
var enabled := false
var use_attrs := false
var shafts := false


func setup(c: Camera3D, e: Environment, s: DirectionalLight3D) -> void:
	cam = c
	env = e
	sun = s
	attrs = CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = false
	attrs.dof_blur_near_enabled = false
	flare = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	flare.mesh = qm
	flare_mat = ShaderMaterial.new()
	flare_mat.shader = load("res://shaders/sun_flare.gdshader")
	flare_mat.render_priority = 110
	flare.material_override = flare_mat
	flare.extra_cull_margin = 16384.0
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flare.position = Vector3(0, 0, -1)
	flare.visible = false
	cam.add_child(flare)
	_smoke_mat = FogMaterial.new()
	_smoke_mat.albedo = Color(0.78, 0.78, 0.8)
	_smoke_mat.height_falloff = 0.25
	_smoke_mat.edge_fade = 0.6


## Called when the time, weather or quality changes (from apply_time_and_weather).
func configure(modern: bool, fp: bool, q: int, night: bool, hour: float, wet: float) -> void:
	enabled = modern
	if not modern:
		env.fog_height_density = 0.0
		cam.attributes = null
		flare.visible = false
		return
	# Morning and evening air sits low and thick; rain fills it with spray.
	var low_sun: float = clamp(1.0 - abs(hour - 13.5) / 6.5, 0.0, 1.0)
	var haze: float = 1.0 - low_sun * 0.6 + wet * 0.8
	env.fog_density = (0.00030 if not night else 0.0010) * haze
	env.fog_height = 4.0
	env.fog_height_density = 0.012 * haze if fp else 0.0
	env.fog_aerial_perspective = 0.7
	# Sun shafts: volumetric fog in daylight, faint enough to only show in light.
	shafts = fp and q >= 3
	if shafts and not night:
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.0011 + 0.003 * wet
		env.volumetric_fog_anisotropy = 0.7
		env.volumetric_fog_length = 200.0
		env.volumetric_fog_albedo = Color(0.95, 0.95, 0.97)
		sun.light_volumetric_fog_energy = 1.0
	use_attrs = fp and q >= 2
	if not use_attrs and cam.attributes == attrs:
		cam.attributes = null


## Smoke that lingers after a spin or crash (volumetric: needs HIGH on desktop).
func puff(at: Vector3, size: float) -> void:
	if not shafts or not env.volumetric_fog_enabled:
		return
	if smoke.size() >= MAX_SMOKE:
		var old: Array = smoke.pop_front()
		(old[0] as Node).queue_free()
	var fv := FogVolume.new()
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	fv.size = Vector3(8.0, 3.5, 8.0) * size
	var m: FogMaterial = _smoke_mat.duplicate()
	m.density = 0.35
	fv.material = m
	add_child(fv)
	fv.global_position = at + Vector3(0, 1.2, 0)
	smoke.append([fv, 0.0, 9.0])


func clear_smoke() -> void:
	for s in smoke:
		(s[0] as Node).queue_free()
	smoke.clear()


func update(delta: float, speed: float, inside: bool, active: bool) -> void:
	# Smoke drifts, spreads and thins out.
	for i in range(smoke.size() - 1, -1, -1):
		var s: Array = smoke[i]
		s[1] += delta
		var fv: FogVolume = s[0]
		var k: float = s[1] / s[2]
		if k >= 1.0:
			fv.queue_free()
			smoke.remove_at(i)
			continue
		fv.size += Vector3(1.5, 0.4, 1.5) * delta
		fv.position.y += 0.25 * delta
		(fv.material as FogMaterial).density = 0.35 * (1.0 - k) * (1.0 - k)
	if not enabled or not active:
		flare.visible = false
		if cam.attributes == attrs:
			attrs.dof_blur_far_enabled = false
			attrs.dof_blur_near_enabled = false
		return
	if use_attrs and cam.attributes != attrs:
		cam.attributes = attrs
	# Focus: the far distance softens as speed rises; in the cockpit the eyes are
	# on the road, so the dash and cage are a little soft too.
	var spd: float = clamp(speed / 90.0, 0.0, 1.2)
	attrs.dof_blur_far_enabled = spd > 0.2
	attrs.dof_blur_far_distance = lerp(900.0, 320.0, clamp(spd, 0.0, 1.0))
	attrs.dof_blur_far_transition = 400.0
	# (No near blur: the dash and wheel have to stay readable.)
	attrs.dof_blur_near_enabled = false
	attrs.dof_blur_amount = 0.04
	# Glare: only when the sun is up and in front of the camera.
	var sun_dir: Vector3 = sun.global_transform.basis.z # towards the sun
	var elev: float = sun_dir.y
	var p: Vector3 = cam.global_position + sun_dir * 2000.0
	if elev < 0.0 or cam.is_position_behind(p):
		flare.visible = false
		return
	var vp: Vector2 = cam.get_viewport().get_visible_rect().size
	var sp: Vector2 = cam.unproject_position(p) / vp
	var edge: float = clamp(1.4 - (sp - Vector2(0.5, 0.5)).length() * 1.4, 0.0, 1.0)
	flare.visible = edge > 0.0
	flare_mat.set_shader_parameter("sun_uv", sp)
	flare_mat.set_shader_parameter("aspect", vp.x / max(vp.y, 1.0))
	flare_mat.set_shader_parameter("strength", edge * clamp(elev * 4.0, 0.0, 1.0) * sun.light_energy * 0.8)
	flare_mat.set_shader_parameter("tint", Vector3(sun.light_color.r, sun.light_color.g * 0.95, sun.light_color.b * 0.85))
