extends SceneTree
## Measures how long the game's per-frame work takes in a 40-car Single Race.
var main: Node


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node("Game")
	for i in 20:
		await process_frame
	game.settings.field = int(OS.get_environment("FIELD")) if OS.get_environment("FIELD") != "" else 2
	main.mode = "race"
	main.session = "race"
	main._use_track(1)
	main._enter_countdown()
	main.autopilot = true
	for i in 400:
		await physics_frame
	var race: Node3D = main.race
	# race.tick alone
	var t0 := Time.get_ticks_usec()
	for i in 120:
		race.tick(1.0 / 60.0)
	var tick_ms := (Time.get_ticks_usec() - t0) / 120.0 / 1000.0
	# the pieces
	t0 = Time.get_ticks_usec()
	for i in 120:
		race._aero(1.0 / 60.0)
	var aero_ms := (Time.get_ticks_usec() - t0) / 120.0 / 1000.0
	t0 = Time.get_ticks_usec()
	for i in 120:
		race._collide()
	var col_ms := (Time.get_ticks_usec() - t0) / 120.0 / 1000.0
	t0 = Time.get_ticks_usec()
	for i in 120:
		for c in race.cars:
			if c.ai:
				race._drive_ai(c, 1.0 / 60.0)
	var ai_ms := (Time.get_ticks_usec() - t0) / 120.0 / 1000.0
	t0 = Time.get_ticks_usec()
	for i in 120:
		for c in race.cars:
			c.step(1.0 / 60.0)
	var phys_ms := (Time.get_ticks_usec() - t0) / 120.0 / 1000.0
	t0 = Time.get_ticks_usec()
	for i in 120:
		race.control.tick(1.0 / 60.0)
	var ctl_ms := (Time.get_ticks_usec() - t0) / 120.0 / 1000.0
	race.control.throw_caution("TEST", null)
	for i in 1200:
		race.tick(1.0 / 60.0)
	t0 = Time.get_ticks_usec()
	for i in 120:
		race.tick(1.0 / 60.0)
	var caution_ms := (Time.get_ticks_usec() - t0) / 120.0 / 1000.0
	# audio synth: one second of samples
	var syn: Node = main.synth
	syn.engine_on = true
	syn.engine_rpm = 8000.0
	syn.pass_volume = 0.5
	var gen: AudioStreamGenerator = syn.player.stream
	t0 = Time.get_ticks_usec()
	var frames := int(gen.mix_rate)
	var buf := PackedVector2Array()
	buf.resize(frames)
	# replicate the synth loop cost by calling its generator body indirectly
	syn.set_process(false)
	var cost := syn.has_method("_render") 
	print("cars=%d  race.tick %.2f ms (under caution %.2f)  | aero %.2f  collide %.2f  ai %.2f  physics %.2f  control %.2f" % [race.cars.size(), tick_ms, caution_ms, aero_ms, col_ms, ai_ms, phys_ms, ctl_ms])
	quit()
