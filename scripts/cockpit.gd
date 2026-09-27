extends Node3D
## The driver's seat: roll cage, dash with a digital display and shift lights,
## a steering wheel your hands turn, the window net, and a rear-view mirror that
## really shows the cars behind (a small second camera).
##
## Built into the car's sprung body (it rolls and pitches with the chassis) and
## only shown while you're in the cockpit view. Car space: -Z forward, +X right.

# Fitted to the Cup-class body (see car_body.gd): the seat sits just behind the
# middle of the car, under the front of the roof, with a long raked windshield.
const EYE := Vector3(-0.36, 1.02, 0.04)
const WHEEL_POS := Vector3(-0.36, 0.8, -0.38)
const WHEEL_R := 0.175
const STEER_TURNS := 2.4 # wheel rotation (rad) at full steering lock

var car: Node3D
var wheel: Node3D
var display: Label3D
var shift_lights: Array[MeshInstance3D] = []
var mirror_vp: SubViewport
var mirror_cam: Camera3D
var mirror_on := true
var _frame := 0

var _dark := StandardMaterial3D.new()
var _cage := StandardMaterial3D.new()
var _net := StandardMaterial3D.new()
var _glove := StandardMaterial3D.new()


func build(c: Node3D, with_mirror: bool) -> void:
	car = c
	_dark.albedo_color = Color(0.07, 0.07, 0.08)
	_dark.roughness = 0.85
	_cage.albedo_color = Color(0.72, 0.73, 0.75)
	_cage.metallic = 0.6
	_cage.roughness = 0.35
	_net.albedo_color = Color(0.03, 0.03, 0.03)
	_net.roughness = 1.0
	var livery: Color = c.team.get("c1", Color(0.8, 0.1, 0.1))
	_glove.albedo_color = livery.lerp(Color(0.1, 0.1, 0.1), 0.35)
	_glove.roughness = 0.9
	# Shell: roof lining, door panels, floor, rear bulkhead.
	_box(Vector3(0, 1.255, 0.32), Vector3(1.0, 0.02, 0.74), _dark)
	_box(Vector3(-0.935, 0.55, -0.1), Vector3(0.02, 0.62, 1.7), _dark)
	_box(Vector3(0.935, 0.55, -0.1), Vector3(0.02, 0.62, 1.7), _dark)
	_box(Vector3(0, 0.22, -0.15), Vector3(1.85, 0.02, 1.6), _dark)
	_box(Vector3(0, 0.72, 0.64), Vector3(1.85, 0.98, 0.02), _dark)
	# Dash and cowl, reaching forward to the foot of the windshield.
	_box(Vector3(0, 0.78, -0.62), Vector3(1.85, 0.16, 0.4), _dark)
	_box(Vector3(0, 0.855, -0.885), Vector3(1.85, 0.02, 0.14), _dark)
	# Roll cage: main hoop behind the seat, A-pillar bars up the windshield, the
	# roof rails, the centre windshield bar and the door bars on the driver's side.
	for x in [-0.8, 0.8]:
		_tube(Vector3(x, 0.24, 0.33), Vector3(x * 0.98, 0.83, 0.33))
		_tube(Vector3(x * 0.98, 0.83, 0.33), Vector3(x * 0.78, 1.22, 0.33))
		_tube(Vector3(x * 0.92, 0.87, -0.92), Vector3(x * 0.72, 1.22, -0.1))
		_tube(Vector3(x * 0.72, 1.22, -0.1), Vector3(x * 0.78, 1.22, 0.33))
	_tube(Vector3(-0.62, 1.22, 0.33), Vector3(0.62, 1.22, 0.33))
	_tube(Vector3(-0.58, 1.22, -0.1), Vector3(0.58, 1.22, -0.1))
	_tube(Vector3(0, 0.88, -0.93), Vector3(0, 1.235, -0.12))
	for k in 3:
		var y := 0.42 + k * 0.14
		_tube(Vector3(-0.86, y, -0.8), Vector3(-0.86, y + 0.06, 0.3))
	# Window net on the driver's (left) side.
	for k in 7:
		var z := -0.55 + k * 0.12
		_box(Vector3(-0.84, 1.02, z), Vector3(0.01, 0.26, 0.018), _net)
	for k in 4:
		var y := 0.91 + k * 0.07
		_box(Vector3(-0.84, y, -0.19), Vector3(0.01, 0.018, 0.74), _net)
	# Steering column and wheel (with gloved hands at a quarter to three).
	_tube(Vector3(-0.36, 0.74, -0.72), WHEEL_POS + Vector3(0, -0.03, -0.05), 0.022)
	wheel = Node3D.new()
	wheel.position = WHEEL_POS
	wheel.rotation.x = deg_to_rad(-68.0) # tilted back towards the driver
	add_child(wheel)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = WHEEL_R - 0.02
	tm.outer_radius = WHEEL_R + 0.012
	tm.rings = 32
	tm.ring_segments = 8
	rim.mesh = tm
	rim.material_override = _dark
	wheel.add_child(rim)
	var hub := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(WHEEL_R * 1.7, 0.03, 0.06)
	hub.mesh = hb
	hub.material_override = _dark
	wheel.add_child(hub)
	for side in [-1.0, 1.0]:
		var g := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.035
		cm.height = 0.12
		g.mesh = cm
		g.material_override = _glove
		g.position = Vector3(side * WHEEL_R * 0.98, 0.0, 0.02)
		g.rotation.z = side * 0.3
		wheel.add_child(g)
	# Digital dash, straight ahead through the wheel.
	display = Label3D.new()
	# The dash display sits right of the wheel, where the driver can glance at it.
	display.position = Vector3(-0.08, 0.905, -0.5)
	display.rotation = Vector3(deg_to_rad(-30.0), deg_to_rad(-25.0), 0.0) # turned towards the driver
	display.pixel_size = 0.00045
	display.font_size = 32
	display.outline_size = 0
	display.modulate = Color(0.55, 1.0, 0.7)
	display.shaded = false
	display.double_sided = false
	display.no_depth_test = false
	if Game.arcade_font:
		display.font = Game.arcade_font
	add_child(display)
	# Shift lights across the top of the dash.
	for k in 10:
		var m := MeshInstance3D.new()
		var q := BoxMesh.new()
		q.size = Vector3(0.018, 0.012, 0.012)
		m.mesh = q
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.1, 0.1, 0.1)
		m.material_override = mat
		m.position = Vector3(-0.36 - 0.1 + k * 0.022, 0.868, -0.5)
		add_child(m)
		shift_lights.append(m)
	if with_mirror:
		_build_mirror()
	visible = false


func _box(p: Vector3, size: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = p
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)


func _tube(a: Vector3, b: Vector3, r := 0.025) -> void:
	var m := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = r
	cy.bottom_radius = r
	cy.height = a.distance_to(b)
	cy.radial_segments = 8
	cy.rings = 1
	m.mesh = cy
	m.material_override = _cage
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	var dir := (b - a).normalized()
	var up := Vector3.UP
	var basis_y := dir
	var basis_x := up.cross(basis_y)
	if basis_x.length() < 0.01:
		basis_x = Vector3.RIGHT
	basis_x = basis_x.normalized()
	var basis_z := basis_x.cross(basis_y).normalized()
	m.transform = Transform3D(Basis(basis_x, basis_y, basis_z), (a + b) * 0.5)


## The rear-view mirror: a wide strip at the top of the windshield showing a
## low-resolution view out of the back of the car.
func _build_mirror() -> void:
	mirror_vp = SubViewport.new()
	mirror_vp.size = Vector2i(320, 64)
	mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	mirror_vp.msaa_3d = Viewport.MSAA_DISABLED
	mirror_vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	add_child(mirror_vp)
	mirror_cam = Camera3D.new()
	mirror_cam.fov = 28.0
	mirror_cam.far = 400.0
	mirror_cam.cull_mask = 0xFFFFF & ~(1 << 19) # not the cockpit itself
	mirror_vp.add_child(mirror_cam)
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.36, 0.07)
	quad.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = mirror_vp.get_texture()
	mat.uv1_scale = Vector3(-1, 1, 1) # a mirror flips left and right
	mat.uv1_offset = Vector3(1, 0, 0)
	quad.material_override = mat
	quad.position = Vector3(0.0, 1.115, -0.3)
	quad.rotation.x = deg_to_rad(-6.0)
	# (A quad faces +Z, which is towards the driver.)
	add_child(quad)
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.39, 0.09, 0.02)
	frame.mesh = fb
	frame.material_override = _dark
	frame.position = Vector3(0.0, 1.115, -0.312)
	add_child(frame)


func _set_layers(n: Node) -> void:
	if n is VisualInstance3D and n != mirror_vp:
		(n as VisualInstance3D).layers = 1 << 19
	for ch in n.get_children():
		_set_layers(ch)


func show_inside(on: bool) -> void:
	if visible == on:
		return
	visible = on
	# The car's own simple interior (seen through its glass) makes way.
	if car and car.get("_body") is Dictionary and car._body.has("interior"):
		car._body.interior.visible = not on
	if on:
		_set_layers(self)
	if mirror_vp:
		mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE if on else SubViewport.UPDATE_DISABLED


## Head position in world space (the camera goes here, plus the camera feel).
func eye_transform() -> Transform3D:
	return global_transform * Transform3D(Basis(), EYE)


func update(delta: float) -> void:
	if not visible or car == null:
		return
	wheel.rotation.y = 0.0
	wheel.transform.basis = Basis.from_euler(Vector3(deg_to_rad(-68.0), 0.0, 0.0)) * Basis(Vector3.UP, -car.steer * STEER_TURNS)
	var rpm: float = car.rpm()
	var mph := int(abs(car.v) * 2.237)
	display.text = "%d   %d\n%d MPH\nH2O %d  OIL %d" % [car.gear, int(rpm), mph, int(car.engine_temp * 1.8 + 32.0), int(car.engine_temp * 1.8 + 50.0)]
	display.modulate = Color(1.0, 0.35, 0.3) if car.engine_temp > 125.0 else Color(0.55, 1.0, 0.7)
	var lit := int(clamp((rpm - 6500.0) / 2400.0, 0.0, 1.0) * shift_lights.size())
	var flash: bool = rpm > 8800.0 and int(Time.get_ticks_msec() / 80) % 2 == 0
	for k in shift_lights.size():
		var col := Color(0.08, 0.08, 0.08)
		if k < lit:
			col = Color(0.2, 1.0, 0.3) if k < 4 else (Color(1.0, 0.8, 0.1) if k < 7 else Color(1.0, 0.15, 0.1))
		if flash:
			col = Color(0.3, 0.5, 1.0)
		(shift_lights[k].material_override as StandardMaterial3D).albedo_color = col
	if mirror_cam:
		# Mirror camera: at the mirror, looking out the back window.
		var t: Transform3D = global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 1.18, 0.7))
		mirror_cam.global_transform = t
		# Every other frame is plenty for a mirror.
		_frame += 1
		if _frame % 2 == 0:
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
