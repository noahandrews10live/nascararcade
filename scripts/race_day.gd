extends Node3D
## The people around the race:
##  - pit crews vault the wall and work round the car (right side first, then
##    the left on a four-tyre stop, the jack going up and down, fuel at the back);
##  - the flagman on his stand over the line waves whichever flag is out;
##  - the crowd gets on its feet for wrecks and lead changes and does the wave
##    under caution;
##  - fireworks over the stands and a winner's burnout at the finish.

const CREWS := 4
const CREW_SIZE := 6
# Crew spots round the car (car space: -Z forward, +X right): the four tyre
# changers, the jack man and the gas man.
const SPOTS := [
	Vector3(1.25, 0, -1.5), Vector3(1.25, 0, 1.45), Vector3(-1.25, 0, -1.5), Vector3(-1.25, 0, 1.45),
	Vector3(1.3, 0, 0.0), Vector3(-1.1, 0, 2.1),
]

var race: Node3D
var track: Node3D
var soundscape: Node
var atmosphere: Node
var crews: Array = [] # [Node3D root, Array[Node3D] people, car or null]
var _crew_total := {} # car -> pit time when it stopped
var flag_root: Node3D
var flag_mat: ShaderMaterial
var flagman_arm: Node3D
var fireworks: Array = []
var _fw_timer := 0.0
var _burnout_car: Node3D
var _burnout_t := 0.0
var _leader: Node3D
var _time := 0.0
var _wave := 0.0


func setup(r: Node3D, s: Node, a: Node) -> void:
	race = r
	track = r.track
	soundscape = s
	atmosphere = a
	for k in CREWS:
		var root := Node3D.new()
		root.visible = false
		add_child(root)
		var people: Array[Node3D] = []
		for j in CREW_SIZE:
			var p := _person(Color(0.8, 0.1, 0.1))
			root.add_child(p)
			people.append(p)
		crews.append([root, people, null])
	_build_flag_stand()
	if Game.modern:
		_build_grills()
	race.car_finished.connect(_on_finished)


## Race-day life in the infield: smoke drifting up from the campers' grills.
func _build_grills() -> void:
	var qm := QuadMesh.new()
	qm.size = Vector2(1.6, 1.6)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	qm.material = m
	var fade := Gradient.new()
	fade.set_color(0, Color(0.75, 0.75, 0.75, 0.0))
	fade.add_point(0.15, Color(0.72, 0.72, 0.72, 0.35))
	fade.set_color(fade.get_point_count() - 1, Color(0.85, 0.85, 0.88, 0.0))
	for k in 6:
		var i: int = int(track.n * (0.08 + 0.84 * k / 5.0)) % track.n
		var p := CPUParticles3D.new()
		p.amount = 14
		p.lifetime = 7.0
		p.mesh = qm
		p.direction = Vector3(0.3, 1, 0.1)
		p.spread = 12.0
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 1.1
		p.gravity = Vector3(0.25, 0.15, 0.0)
		p.scale_amount_min = 1.0
		p.scale_amount_max = 3.0
		p.color_ramp = fade
		p.visibility_range_end = 380.0
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		p.global_position = track.pos[i] + track.right[i] * (track.inner_wall() - 40.0 - 8.0 * (k % 2)) + Vector3.UP * 1.0


## A crew member in a firesuit and helmet.
func _person(col: Color) -> Node3D:
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.2
	cap.height = 1.2
	cap.radial_segments = 8
	cap.rings = 2
	body.mesh = cap
	body.position.y = 0.62
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.8
	body.material_override = m
	n.add_child(body)
	var head := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.15
	sp.height = 0.3
	sp.radial_segments = 8
	sp.rings = 4
	head.mesh = sp
	head.position.y = 1.38
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.92, 0.92, 0.95)
	hm.roughness = 0.3
	head.material_override = hm
	n.add_child(head)
	return n


func _build_flag_stand() -> void:
	flag_root = Node3D.new()
	add_child(flag_root)
	var s0 := 0.0
	var wall: float = track.outer_edge() + 0.8
	var base: Vector3 = track.surface_point(s0, wall)
	var right: Vector3 = track.right_at(s0)
	var fwd: Vector3 = track.fwd_at(s0)
	flag_root.global_transform = Transform3D(Basis(right, Vector3.UP, -fwd).orthonormalized(), base)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.55, 0.57, 0.6)
	steel.metallic = 0.5
	steel.roughness = 0.4
	# Posts and a platform hanging out over the track.
	for x in [0.0, 1.6]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.15, 6.0, 0.15)
		post.mesh = bm
		post.material_override = steel
		post.position = Vector3(x, 3.0, 0)
		flag_root.add_child(post)
	var deck := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(3.2, 0.12, 1.4)
	deck.mesh = dm
	deck.material_override = steel
	deck.position = Vector3(-0.6, 6.0, 0)
	flag_root.add_child(deck)
	var man := _person(Color(0.95, 0.95, 0.95))
	man.position = Vector3(-1.4, 6.06, 0)
	man.rotation.y = PI * 0.5 # facing down the track at the oncoming cars
	flag_root.add_child(man)
	flagman_arm = Node3D.new()
	flagman_arm.position = Vector3(-1.4, 7.25, 0.1)
	flag_root.add_child(flagman_arm)
	var stick := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.015
	sm.bottom_radius = 0.015
	sm.height = 1.1
	stick.mesh = sm
	stick.material_override = steel
	stick.position = Vector3(0, 0.55, 0)
	flagman_arm.add_child(stick)
	var cloth := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.9, 0.65)
	pm.subdivide_width = 8
	pm.subdivide_depth = 4
	pm.orientation = PlaneMesh.FACE_Z
	cloth.mesh = pm
	flag_mat = ShaderMaterial.new()
	flag_mat.shader = load("res://shaders/flag.gdshader")
	cloth.material_override = flag_mat
	cloth.position = Vector3(0.45, 0.8, 0)
	flagman_arm.add_child(cloth)


func _flag_colours() -> Array:
	var ctl = race.control
	var chequered: bool = race.order.size() > 0 and race.order[0].finished
	if chequered:
		return [Color(0.05, 0.05, 0.05), Color(0.97, 0.97, 0.97), 1.0]
	if ctl == null:
		return [Color(0.1, 0.75, 0.2), Color(0.1, 0.75, 0.2), 0.0]
	match ctl.flag:
		ctl.Flag.YELLOW:
			return [Color(1.0, 0.85, 0.05), Color(1.0, 0.85, 0.05), 0.0]
		ctl.Flag.WHITE:
			return [Color(0.97, 0.97, 0.97), Color(0.97, 0.97, 0.97), 0.0]
		ctl.Flag.CHECKERED:
			return [Color(0.05, 0.05, 0.05), Color(0.97, 0.97, 0.97), 1.0]
	return [Color(0.1, 0.75, 0.2), Color(0.1, 0.75, 0.2), 0.0]


func _on_finished(car: Node3D, place: int) -> void:
	if place != 1:
		return
	soundscape.cheer(1.0)
	_fw_timer = 12.0
	# An AI winner lights up the tyres on the front stretch.
	if car.ai and not car.is_player:
		_burnout_car = car
		_burnout_t = 0.0


func update(delta: float) -> void:
	if race == null:
		return
	_time += delta
	# Flag: waved in figure-eights while it's out.
	var fc := _flag_colours()
	flag_mat.set_shader_parameter("col_a", fc[0])
	flag_mat.set_shader_parameter("col_b", fc[1])
	flag_mat.set_shader_parameter("checks", fc[2])
	flagman_arm.rotation = Vector3(0.0, 0.0, -0.5 + sin(_time * 5.0) * 0.6)
	flagman_arm.rotation.x = cos(_time * 10.0) * 0.25
	# Crowd: lead changes get them up too.
	if race.order.size() > 0:
		var lead: Node3D = race.order[0]
		if _leader != null and lead != _leader and race.running:
			soundscape.cheer(0.7)
		_leader = lead
	if track.crowd_mat:
		track.crowd_mat.set_shader_parameter("excitement", soundscape.excitement)
		var caution: bool = race.control != null and race.control.flag == race.control.Flag.YELLOW
		_wave = move_toward(_wave, 1.0 if caution else 0.0, delta * 0.3)
		track.crowd_mat.set_shader_parameter("wave", _wave)
	_update_crews(delta)
	_update_fireworks(delta)
	_update_burnout(delta)


func _update_crews(delta: float) -> void:
	# Cars sitting in their pit boxes get a crew (the nearest few).
	var boxed: Array = []
	for c in race.cars:
		if c.pit_state == 3:
			boxed.append(c)
		else:
			_crew_total.erase(c)
	for k in crews.size():
		var cr: Array = crews[k]
		var car: Node3D = boxed[k] if k < boxed.size() else null
		var root: Node3D = cr[0]
		if car == null:
			root.visible = false
			cr[2] = null
			continue
		if cr[2] != car:
			cr[2] = car
			var col: Color = car.team.get("c1", Color(0.8, 0.1, 0.1))
			for p in cr[1]:
				(p.get_child(0) as MeshInstance3D).material_override.albedo_color = col
		root.visible = true
		if not _crew_total.has(car):
			_crew_total[car] = max(car.pit_timer, 0.1)
		var total: float = _crew_total[car]
		var prog: float = clamp(1.0 - car.pit_timer / total, 0.0, 1.0)
		var xf: Transform3D = car.global_transform
		root.global_transform = xf
		var four: bool = car.pit_plan != "2" and car.pit_plan != "F"
		var tyres: bool = car.pit_plan != "F"
		var people: Array = cr[1]
		for j in people.size():
			var p: Node3D = people[j]
			var spot: Vector3 = SPOTS[j]
			var active := true
			if j < 4:
				active = tyres and (j < 2 or four)
				# The left-side changers wait for the right side to finish.
				if j >= 2 and prog < 0.45:
					spot = SPOTS[j - 2] + Vector3(0.6, 0, 0)
			if j == 4 and four and prog > 0.45:
				spot = Vector3(-1.3, 0, 0.0) # the jack goes round to the left
			# Everyone comes over the wall at the start and goes back at the end.
			var over: float = clamp(prog * 8.0, 0.0, 1.0) * clamp((1.0 - prog) * 10.0, 0.0, 1.0)
			var wall_pos := Vector3(4.0, 0, spot.z)
			var pos: Vector3 = wall_pos.lerp(spot, over) if active else wall_pos
			var busy: float = 1.0 if over > 0.99 and active else 0.0
			pos.y = -0.35 * busy + 0.06 * sin(_time * 18.0 + j) * busy
			p.position = p.position.lerp(pos, clamp(delta * 12.0, 0.0, 1.0))
			p.rotation.y = atan2(-p.position.x, -p.position.z) if busy > 0.0 else 0.0


func _update_fireworks(delta: float) -> void:
	for i in range(fireworks.size() - 1, -1, -1):
		var f: Array = fireworks[i]
		f[1] -= delta
		if f[1] <= 0.0:
			(f[0] as Node).queue_free()
			fireworks.remove_at(i)
	if _fw_timer <= 0.0:
		return
	_fw_timer -= delta
	if randf() < delta * 2.5:
		var spots: Array = track.crowd_spots()
		if spots.is_empty():
			return
		var at: Vector3 = spots[randi() % spots.size()] + Vector3(randf_range(-30, 30), randf_range(35.0, 60.0), randf_range(-10, 10))
		var burst := _burst(Color.from_hsv(randf(), 0.8, 1.0) * 3.0)
		add_child(burst)
		burst.global_position = at
		burst.emitting = true
		fireworks.append([burst, 3.0])
		if soundscape.has_method("cheer"):
			soundscape.cheer(0.8)


func _burst(col: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	qm.material = m
	p.mesh = qm
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 90
	p.lifetime = 2.2
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 18.0
	p.gravity = Vector3(0, -6.0, 0)
	p.damping_min = 3.0
	p.damping_max = 4.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	g.colors = PackedColorArray([col, col * 0.6, Color(col.r, col.g, col.b, 0.0)])
	p.color_ramp = g
	p.emitting = false
	return p


## The winner's burnout: once it's slowed on the cool-down, full throttle and
## full lock on the front stretch until the smoke rolls (about five seconds).
func _update_burnout(delta: float) -> void:
	var c := _burnout_car
	if c == null or not is_instance_valid(c):
		return
	var on_front: bool = abs(fposmod(c.s() + track.length * 0.5, track.length) - track.length * 0.5) < track.length * 0.12
	if _burnout_t == 0.0 and not (c.speed() < 26.0 and on_front):
		return
	_burnout_t += delta
	if _burnout_t > 5.5 or c.wall_hit > 1.0 or c.tumbling:
		c.ai = true
		c.set_meta("burnout", false)
		_burnout_car = null
		return
	c.set_meta("burnout", true)
	c.ai = false
	c.throttle = 1.0
	c.brake = 0.0
	c.steer_in = -1.0
	if randf() < delta * 2.0:
		atmosphere.puff(c.global_position, 0.8)
