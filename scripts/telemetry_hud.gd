extends Control
## Crew chief's telemetry overlay (T to toggle): per-tyre tread temperatures
## (inside / middle / outside), pressures, wear, loads and shock travel; the air
## around the car; water temperature; the live gap to your best lap and a speed
## trace of this lap against it.

var car: Node3D
var W := 640.0
var H := 480.0


func _ready() -> void:
	Game.center_frame(self)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _tcol(t: float) -> Color:
	var c := Color(0.3, 0.55, 1.0).lerp(Color(0.3, 1.0, 0.4), clamp((t - 55.0) / 35.0, 0.0, 1.0))
	return c.lerp(Color(1.0, 0.25, 0.15), clamp((t - 115.0) / 30.0, 0.0, 1.0))


func _draw() -> void:
	if car == null or not is_instance_valid(car):
		return
	var f := Game.arcade_font
	var x0 := W - 214.0
	var y0 := 92.0
	draw_rect(Rect2(x0, y0, 206, 250), Color(0, 0, 0, 0.62))
	draw_string(f, Vector2(x0 + 6, y0 + 14), "TELEMETRY", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.85, 0.2))
	var names := ["LF", "RF", "LR", "RR"]
	for i in 4:
		var cx: float = x0 + 8.0 + (i % 2) * 100.0
		var cy: float = y0 + 24.0 + (i / 2) * 78.0
		# Inside edge is toward the car's centre line (car.tread_temps).
		var tt: Array = car.tread_temps(i)
		var cells := [tt[2], tt[1], tt[0]] if i % 2 == 0 else [tt[0], tt[1], tt[2]]
		for k in 3:
			draw_rect(Rect2(cx + k * 30.0, cy, 28, 14), _tcol(cells[k]))
			draw_string(f, Vector2(cx + k * 30.0 + 2, cy + 11), "%d" % int(cells[k] * 1.8 + 32.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0, 0, 0))
		var air: float = car.tyre_air[i]
		draw_string(f, Vector2(cx, cy + 28), "%s %.1f PSI%s" % [names[i], car.tyre_psi[i] * air, "  FLAT" if air < 0.6 else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 0.4, 0.3) if air < 0.6 else Color(0.85, 0.9, 1.0))
		draw_string(f, Vector2(cx, cy + 40), "WEAR %d%%  %.1fKN" % [int(car.tyre_wear4[i] * 100.0), car._nw[i] / 1000.0], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.85, 0.9, 1.0))
		draw_string(f, Vector2(cx, cy + 52), "SHOCK %+dMM%s" % [int(car._defl[i] * 1000.0), "  STOP" if car._defl[i] > car.bump_gap else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 0.8, 0.3) if car._defl[i] > car.bump_gap else Color(0.85, 0.9, 1.0))
	var yy: float = y0 + 186.0
	var air_v: Vector4 = car.get_meta("air", Vector4.ZERO)
	draw_string(f, Vector2(x0 + 8, yy), "AIR  TOW %d%%  PUSH %d%%  SIDE %d%%" % [int(air_v.x * 100.0), int(air_v.y * 100.0), int(air_v.z * 100.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.95, 1.0))
	draw_string(f, Vector2(x0 + 8, yy + 12), "H2O %dF  %s" % [int(car.engine_temp * 1.8 + 32.0), ("DERATE %d%%" % int((1.0 - car.engine_derate()) * 100.0)) if car.engine_derate() < 1.0 else "OK"], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.85, 0.9, 1.0))
	var dl: float = car.lap_delta()
	draw_string(f, Vector2(x0 + 8, yy + 26), "DELTA %+.2f" % dl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.3, 1.0, 0.4) if dl <= 0.0 else Color(1.0, 0.35, 0.3))
	# Speed trace: this lap (yellow) over the best lap (grey).
	var gx: float = x0 + 100.0
	var gy: float = yy + 30.0
	var gw := 100.0
	var gh := 30.0
	draw_rect(Rect2(gx, gy - gh, gw, gh), Color(1, 1, 1, 0.06))
	for pair in [[car.best_speed, Color(0.6, 0.6, 0.65)], [car.lap_speed, Color(1.0, 0.85, 0.2)]]:
		var arr: PackedFloat32Array = pair[0]
		if arr.size() < 100:
			continue
		var pts := PackedVector2Array()
		for k in 100:
			pts.append(Vector2(gx + k, gy - clamp(arr[k] / 100.0, 0.0, 1.0) * gh))
		draw_polyline(pts, pair[1], 1.0)
