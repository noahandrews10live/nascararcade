extends Node
## The rear-view mirror (Options -> MIRROR): a strip at the top of the screen
## showing what's behind you, the way a real one does (flipped left for right).
## It's a small second camera on the roof looking back, drawn into a low-
## resolution picture every other frame, so it costs a phone little; in pack
## racing it's how you see the push coming and the run to block.

const PX := Vector2i(320, 72) # the picture (pixels)
const SIZE := Vector2(232.0, 52.0) # on the HUD (HUD units)

var vp: SubViewport
var cam: Camera3D
var rect: TextureRect
var frame_box: Panel
var hud: Control
var _odd := false


func setup(world: World3D, hud_node: Control) -> void:
	hud = hud_node
	vp = SubViewport.new()
	vp.size = PX
	vp.world_3d = world
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.positional_shadow_atlas_size = 0
	add_child(vp)
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.3
	cam.far = 450.0
	vp.add_child(cam)
	frame_box = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.05, 0.9)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.15, 0.15, 0.15)
	frame_box.add_theme_stylebox_override("panel", sb)
	frame_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(frame_box)
	rect = TextureRect.new()
	rect.texture = vp.get_texture()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.flip_h = true # a mirror
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_box.add_child(rect)
	frame_box.visible = false


static func wanted() -> bool:
	return int(Game.settings.get("mirror", 1)) == 1


## Where it sits on the HUD (top centre, under the TV ticker if that's on).
func box() -> Rect2:
	return Rect2((hud.W - SIZE.x) * 0.5, 4.0 + hud.top, SIZE.x, SIZE.y)


## Each frame: follow the car (after it's been placed for drawing).
func update(car: Node3D, on: bool) -> void:
	on = on and wanted() and car != null and is_instance_valid(car)
	frame_box.visible = on
	var room: float = (SIZE.y + 6.0) if on else 0.0
	if room != hud.mirror_room:
		hud.mirror_room = room
		hud._layout()
	if not on:
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var b := box()
	frame_box.position = b.position
	frame_box.size = b.size
	rect.position = Vector2(3, 3)
	rect.size = b.size - Vector2(6, 6)
	var t: Transform3D = car.global_transform
	# On the roof, looking back (the car's +Z points backward).
	var fwd: Vector3 = -t.basis.z.normalized()
	var up := Vector3.UP
	var eye: Vector3 = t.origin + up * 1.35 - fwd * 0.4
	cam.global_transform = Transform3D(Basis.looking_at(-fwd + Vector3(0, -0.04, 0), up), eye)
	# Every other frame is plenty for a mirror.
	_odd = not _odd
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE if _odd else SubViewport.UPDATE_DISABLED
