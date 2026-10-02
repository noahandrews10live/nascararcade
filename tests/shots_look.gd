extends SceneTree
## The same five views every time, for comparing the look between changes and
## renderers (OUT=dir, TRACK=n, TAG=prefix):
##   OUT=/tmp/look xvfb-run -a godot --rendering-method mobile -s tests/shots_look.gd
## (forward_plus, mobile or gl_compatibility; the race is paused and the HUD
## hidden, so only the picture changes).

var main: Node
var out := OS.get_environment("OUT")
var tag := OS.get_environment("TAG")


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("%s%s.png" % [tag, name]))
	print("saved ", name)


func _run() -> void:
	await _frames(20)
	var game := root.get_node("Game")
	seed(7)
	game.settings.weather = 0
	game.settings.weekend = 0
	game.settings.field = 0
	game.settings.cautions = 0
	main.mode = "race"
	main.session = "race"
	main._use_track(int(OS.get_environment("TRACK")) if OS.get_environment("TRACK") != "" else 1)
	main._enter_countdown()
	main.autopilot = true
	while main.state != main.State.RACE:
		await process_frame
	await _frames(int(OS.get_environment("WARM")) if OS.get_environment("WARM") != "" else 60 * 9)
	var race = main.race
	var t: Node3D = main.track
	var p: Node3D = race.player
	main.hud.visible = false
	main.ui_root.visible = false
	for n in ["tv_ticker", "pit_show"]:
		var c = main.get(n)
		if c:
			c.visible = false
	# 1. The chase camera in the pack.
	await _frames(2)
	await _shot("chase")
	main.paused = true
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	# 2. Close on the player's car from low at the side (paint, tyres, glass).
	var cp: Vector3 = p.global_position
	var fwd: Vector3 = t.fwd_at(p.s())
	var right: Vector3 = t.right_at(p.s())
	cam.fov = 40.0
	cam.global_position = cp + fwd * 5.5 - right * 3.2 + Vector3.UP * 0.9
	cam.look_at(cp + Vector3.UP * 0.5, Vector3.UP)
	await _frames(3)
	await _shot("car")
	# 3. Turn 1 from the infield: banking, the wall, the fence and the stands.
	var s1: float = fposmod(t.front_length() * 0.5 + 120.0, t.length)
	var base: Vector3 = t.global_transform * t.surface_point(s1, 0.0)
	cam.fov = 55.0
	cam.global_position = base - t.right_at(s1) * 60.0 + Vector3.UP * 6.0 - t.fwd_at(s1) * 40.0
	cam.look_at(base + t.fwd_at(s1) * 120.0 + t.right_at(s1) * 10.0, Vector3.UP)
	await _frames(3)
	await _shot("turn")
	# 4. Down the front stretch at the wall (asphalt, wall, grandstands).
	var s0: float = fposmod(-60.0, t.length)
	var b0: Vector3 = t.global_transform * t.surface_point(s0, t.outer_edge() - 2.0)
	cam.fov = 50.0
	cam.global_position = b0 + Vector3.UP * 1.6
	cam.look_at(b0 + t.fwd_at(s0) * 80.0 - t.right_at(s0) * 8.0, Vector3.UP)
	await _frames(3)
	await _shot("wall")
	# 5. TV: long lens on the pack from high in the stands.
	var lead: Node3D = race.order[0]
	var lp: Vector3 = lead.global_position
	cam.fov = 18.0
	cam.global_position = lp - t.right_at(lead.s()) * 70.0 + Vector3.UP * 14.0 - t.fwd_at(lead.s()) * 30.0
	cam.look_at(lp - t.fwd_at(lead.s()) * 15.0, Vector3.UP)
	await _frames(3)
	await _shot("tv")
	print("renderer ", RenderingServer.get_current_rendering_method())
	quit()
