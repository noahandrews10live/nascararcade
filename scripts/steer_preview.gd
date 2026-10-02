extends Control
## OPTIONS: while TILT STEERING is picked, a live preview: the phone at the
## angle you're holding it (or swinging side to side on a computer) and how much
## steering that angle gives at the chosen setting.

const TouchControls := preload("res://scripts/touch_controls.gd")
var main: Node
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(400, 300)
	size = Vector2(220, 120)


## The tilt now, in degrees from straight: the real phone, or a demo swing.
func angle() -> float:
	var tc: Node = main.touch if main else null
	if tc and tc.get("_tilt_ok"):
		return wrapf(float(tc._tilt_value) - float(tc._tilt_center), -180.0, 180.0)
	return sin(_t * 1.3) * 22.0


func _process(delta: float) -> void:
	_t += delta
	var show := false
	if main and main.menu and is_instance_valid(main.menu) and main.menu_kind == "options":
		var rows: Array = main.menu.rows
		var c: int = main.menu.cursor
		show = c >= 0 and c < rows.size() and String(rows[c].get("id", "")) == "tilt_sens"
	visible = show
	if show:
		queue_redraw()


func _draw() -> void:
	var a := angle()
	var steer: float = TouchControls.tilt_steer(a)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.1, 0.85))
	# The phone, turned like a wheel.
	var c := Vector2(56, 58)
	draw_set_transform(c, deg_to_rad(a), Vector2.ONE)
	draw_rect(Rect2(-40, -20, 80, 40), Color(0.85, 0.9, 1.0), false, 2.0)
	draw_rect(Rect2(-34, -15, 68, 30), Color(0.2, 0.3, 0.45))
	draw_set_transform(Vector2.ZERO)
	# How much steering that gives.
	var bar := Rect2(118, 50, 90, 12)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	var mid := bar.position.x + bar.size.x * 0.5
	var w: float = bar.size.x * 0.5 * abs(steer)
	draw_rect(Rect2(mid if steer >= 0.0 else mid - w, bar.position.y, w, bar.size.y), Color(0.3, 1.0, 0.45) if abs(steer) < 0.99 else Color(1.0, 0.6, 0.2))
	draw_rect(Rect2(mid - 1, bar.position.y - 3, 2, bar.size.y + 6), Color.WHITE)
	var f := Game.arcade_font
	draw_string(f, Vector2(118, 40), "STEERING", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.88, 1.0))
	draw_string(f, Vector2(118, 82), "%d%% %s" % [int(abs(steer) * 100.0), "FULL LOCK" if abs(steer) >= 0.99 else "LOCK"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	draw_string(f, Vector2(10, 108), "TILT %d°  -  %s" % [int(round(abs(a))), "TRY IT: TURN YOUR PHONE" if main and main.touch and main.touch.get("_tilt_ok") else "PREVIEW"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.85, 0.3))
