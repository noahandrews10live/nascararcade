extends SceneTree
## Wet vs dry lap times on the road course with the whole field on the right
## tyres from the start. Only clean laps count (green flag, no pit stop). Run it
## both ways and compare: wet laps should be roughly 8-12% slower.
##   WET=1 godot --headless --fixed-fps 60 -s tests/wet_bench.gd

var main: Node

func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()

func _run() -> void:
	for i in 20:
		await physics_frame
	var wet_run := OS.get_environment("WET") == "1"
	var game := root.get_node("Game")
	var tidx := int(OS.get_environment("TRACK")) if OS.get_environment("TRACK") != "" else 10
	game.tracks[tidx].full_laps = 40
	game.settings.length = 1
	game.settings.field = 0
	game.settings.weather = 2 if wet_run else 0
	game.settings.weekend = 0
	main.mode = "race"
	main.session = "race"
	main._use_track(tidx)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true
	var race = main.race
	var w = race.weather
	for c in race.cars:
		c.change_tyres([0, 1, 2, 3], "wet" if wet_run else "slick")
	var laps := {}
	var dirty := {} # cars whose current lap had a pit stop or a caution
	var inc := {"spin": 0, "out": 0}
	race.incident.connect(func(_c, k): inc[k] = inc.get(k, 0) + 1)
	var sim := 0.0
	var samples := 0
	var grip := 0.0
	var tgrip := 0.0
	var temp := 0.0
	var eng := 0.0
	while sim < 700.0 and main.state != main.State.RESULTS:
		if wet_run:
			for i in w.wet.size():
				w.wet[i] = 1.0
			w.rain = 0.7
			w._rain_target = 0.7
		await physics_frame
		sim += 1.0 / 60.0
		var p = race.player
		if p.speed() > 20.0:
			samples += 1
			grip += p.tyre_grip()
			tgrip += p._track_grip
			eng = max(eng, p.engine_temp)
			temp += (p.tyre_temp[0] + p.tyre_temp[1] + p.tyre_temp[2] + p.tyre_temp[3]) * 0.25
		var ctl = race.control
		for c in race.cars:
			if c.last_lap > 0.0 and not laps.has([c, c.lap_idx]):
				laps[[c, c.lap_idx]] = -1.0 if dirty.get(c, 0) >= c.lap_idx - 1 else c.last_lap
			if c.pit_state != 0 or c.want_pit or (ctl and ctl.flag != ctl.Flag.GREEN):
				dirty[c] = c.lap_idx
	var outs := 0
	for c in race.cars:
		outs += int(c.out)
	var times: Array = []
	for k in laps:
		if k[1] >= 2 and laps[k] > 0.0:
			times.append(laps[k])
	times.sort()
	print("incidents: %s" % str(inc))
	var hot := 0.0
	for c in race.cars:
		hot = max(hot, c.engine_temp)
	print("player's hottest engine %.0f C, hottest in the field now %.0f C" % [eng, hot])
	print("out: %d of %d cars, laps done by leader %d" % [outs, race.cars.size(), race.order[0].lap_idx])
	print("%s: laps timed %d  best %.1f  median %.1f   player: tyre grip %.2f  track grip %.2f  tyre temp %.0f C  track %.0f C" % [
		"WET" if wet_run else "DRY", times.size(), times[0] if times.size() else 0.0, times[times.size() / 2] if times.size() else 0.0,
		grip / max(samples, 1), tgrip / max(samples, 1), temp / max(samples, 1), race.track.track_temp()])
	quit(0)
