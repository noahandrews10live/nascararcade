extends SceneTree
## Car select in the showroom and the Paint Shop (screenshots with OUT=dir).

var main: Node
var out := OS.get_environment("OUT")


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _shot(name: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	root.get_node("Game").screen_image(root).save_png(out.path_join(name + ".png"))
	print("saved ", name)


func _wait(secs: float) -> void:
	var n := 0
	while n < int(secs * 30.0):
		await process_frame
		n += 1


func _run() -> void:
	await _wait(0.2)
	main.showtime.skip_intro()
	await _wait(0.5)
	main.mode = "race"
	main._enter_track_select()
	main._enter_car_select()
	await _wait(1.0)
	await _shot("sel_1s")
	await _wait(3.0)
	await _shot("sel_4s")
	await _wait(6.0)
	await _shot("sel_10s")
	quit(0)
