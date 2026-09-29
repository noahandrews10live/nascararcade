extends SceneTree
## Screenshots of the Kenney Racing Kit props: the paddock tents and cones, the
## billboards on the backstretch, the TV dish, and a road course's barriers.
##   OUT=/tmp/shots xvfb-run ... godot --rendering-driver opengl3 -s tests/shots_props.gd

var main: Node
var out := OS.get_environment("OUT")


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)


func _view(tidx: int, views: Dictionary) -> void:
	main.mode = "race"
	main.session = "practice"
	main._use_track(tidx)
	main._enter_countdown()
	await _frames(60)
	main.hud.visible = false
	var tr = main.track
	var props: Node = tr.get_node_or_null("Props")
	print("track %d props: %s" % [tidx, str(props.get_children().map(func(c): return "%s x%d" % [c.name, c.multimesh.instance_count])) if props else "none"])
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.fov = 60.0
	for k in views:
		var v: Array = views[k].call(tr, props)
		cam.global_position = v[0]
		cam.look_at(v[1], Vector3.UP)
		await _frames(15)
		await _shot(k)
	cam.queue_free()


## A camera `off` from the 3rd placed copy of `model`, looking at it.
func _near(pr: Node, model: String, off: Vector3) -> Array:
	var mmi: MultiMeshInstance3D = pr.get_node(model)
	var t: Transform3D = mmi.global_transform * mmi.multimesh.get_instance_transform(mini(2, mmi.multimesh.instance_count - 1))
	print("   %s at %s" % [model, str(t.origin)])
	return [t.origin + off, t.origin + Vector3.UP * 1.5]


func _run() -> void:
	await _frames(30)
	var P := func(tr, s: float, d: float, up: float) -> Vector3:
		var i: int = int(fposmod(s, tr.length) / tr.length * tr.n) % tr.n
		return tr.to_global(tr.pos[i] + tr.right[i] * d + Vector3.UP * up)
	await _view(0, {
		"props_paddock": func(tr, _pr): return [P.call(tr, tr.length * 0.16, tr.inner_wall() + 6.0, 5.0), P.call(tr, tr.length * 0.24, tr.inner_wall() - 10.0, 0.0)],
		"props_billboards": func(tr, pr): return _near(pr, "billboard", Vector3(-8, 5, -22)),
		"props_media": func(tr, _pr): return [P.call(tr, -30.0, tr.inner_wall() - 30.0, 8.0), P.call(tr, 60.0, tr.inner_wall() - 58.0, 2.0)],
	})
	await _view(10, {
		"props_runoff": func(tr, pr): return _near(pr, "barrierRed", Vector3(14, 10, 26)),
	})
	quit(0)
