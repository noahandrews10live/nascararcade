extends SceneTree
## Screenshots of the Phase C menus (needs a renderer): OUT=/tmp/shots

var main: Node
var out := OS.get_environment("OUT")


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)


func _run() -> void:
	var game := root.get_node("Game")
	for i in 60:
		await process_frame
	main._enter_mode_select()
	main.mode_idx = 1
	main._refresh_mode_select()
	await _shot("m1_modes")
	main.mode = "race"
	main._enter_race_setup()
	await _shot("m2_race_setup")
	main._enter_garage("race_setup")
	await _shot("m3_garage")
	game.new_season(0, 0)
	for r in 3:
		var finish := []
		for i in 40:
			finish.append({"num": game.teams[(i * 7 + r) % 40].num, "pos": i + 1, "points": [40, 35, 34, 33, 32][min(i, 4)] - max(i - 4, 0)})
		game.record_season_race(r % 3, finish)
	main._enter_season_hub()
	await _shot("m4_season_hub")
	main._enter_standings()
	await _shot("m5_standings")
	game.clear_season()
	quit()
