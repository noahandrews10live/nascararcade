extends Control
## Confetti falling over a screen for a few seconds (milestones, titles).

const COLORS := [Color(1, 0.85, 0.15), Color(0.3, 0.9, 1.0), Color(1, 0.35, 0.3), Color(0.4, 1.0, 0.45), Color(1, 1, 1)]
var bits: Array = [] # [pos, vel, spin, angle, color]
var t := 0.0
var length := 3.5


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 90:
		bits.append([Vector2(randf_range(0, 640), randf_range(-480, -10)), Vector2(randf_range(-30, 30), randf_range(90, 200)),
			randf_range(-8, 8), randf() * TAU, COLORS[i % COLORS.size()]])


func _process(delta: float) -> void:
	t += delta
	if t > length + 2.0:
		queue_free()
		return
	for b in bits:
		b[0] += b[1] * delta
		b[0].x += sin(t * 3.0 + b[3]) * 20.0 * delta
		b[3] += b[2] * delta
	queue_redraw()


func _draw() -> void:
	var fade: float = clamp((length + 2.0 - t) / 2.0, 0.0, 1.0)
	for b in bits:
		var c: Color = b[4]
		c.a = fade
		draw_set_transform(b[0], b[3], Vector2(1.0, abs(sin(t * 6.0 + b[3]))))
		draw_rect(Rect2(-3, -2, 6, 4), c)
	draw_set_transform(Vector2.ZERO)
