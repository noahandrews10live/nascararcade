extends SceneTree
## Online racing between two game instances on this machine:
##   ROLE=host godot --headless --fixed-fps 60 -s tests/net_test.gd &
##   ROLE=client godot --headless --fixed-fps 60 -s tests/net_test.gd
## The host waits for the client, starts a short race with a few AI cars, both
## drive on autopilot; each checks the other's car moves on its screen and that
## the race finishes. Midway the host throws a caution: the client must see the
## yellow and the pace car, make its pit call (the host must get it), and both
## must go back to green.

var main: Node
var failures := 0
var role := OS.get_environment("ROLE")


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("[%s] " % role + ("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _run() -> void:
	for i in 30:
		await physics_frame
	var game := root.get_node("Game")
	var net: Node = main.net
	if role == "host":
		game.selected_team = 0
		_check(net.host(24777) == "", "hosting")
		var waited := 0.0
		while net.players.size() < 2 and waited < 30.0:
			await physics_frame
			waited += 1.0 / 60.0
		_check(net.players.size() == 2, "the client joined the lobby")
		for i in 30:
			await physics_frame
		net.start_race(2, 6, 6)
	else:
		game.selected_team = 1
		for i in 60:
			await physics_frame
		_check(net.join("ws://127.0.0.1:24777") == "", "connecting")
		var waited := 0.0
		while main.mode != "online" and waited < 40.0:
			await physics_frame
			waited += 1.0 / 60.0
		_check(net.connected, "connected to the host")
	var waited2 := 0.0
	while main.mode != "online" and waited2 < 40.0:
		await physics_frame
		waited2 += 1.0 / 60.0
	_check(main.mode == "online" and main.race != null, "the race started")
	main.autopilot = true
	var race: Node3D = main.race
	var other: Node3D = null
	for c in race.cars:
		if c.remote and c.team.num == game.teams[1 if role == "host" else 0].num:
			other = c
	_check(other != null, "the other player's car is on the grid (driven over the network)")
	var start_dist: float = other.dist if other else 0.0
	var sim := 0.0
	var ctl: Node = race.control
	_check(ctl != null, "the full rules are on")
	var saw_yellow := false
	var saw_pace := false
	var green_again := false
	var thrown := false
	var answered := false
	var got_call := false
	while main.state != main.State.RESULTS and sim < 600.0:
		await physics_frame
		sim += 1.0 / 60.0
		if ctl == null:
			continue
		if role == "host" and not thrown and sim > 25.0:
			thrown = true
			ctl.throw_caution("TEST", null)
		if ctl.flag == ctl.Flag.YELLOW:
			saw_yellow = true
			saw_pace = saw_pace or ctl.pace_car.visible
		elif saw_yellow and ctl.flag == ctl.Flag.GREEN:
			green_again = true
		# The client answers its pit call (two tyres).
		if role == "client" and main.pit_menu and is_instance_valid(main.pit_menu) and not answered:
			answered = true
			main._close_pit_menu()
		if role == "host" and ctl.quick_phase == "decide" and not ctl._waiting.is_empty():
			got_call = true # waiting on the client...
		if role == "host" and got_call and ctl._waiting.is_empty() and not answered:
			answered = true # ...and it came in
	_check(saw_yellow, "the caution showed on this screen")
	_check(saw_pace, "the pace car came out on this screen")
	_check(green_again, "back to green after the caution")
	if role == "client":
		_check(answered, "this player got the pit call and answered it")
	else:
		_check(answered, "the client's pit call reached the host")
	var moved: float = (other.dist - start_dist) if other else 0.0
	print("[%s]    other player's car covered %.0f m on this screen; race over in %.0f s" % [role, moved, sim])
	_check(moved > race.track.length * 2.0, "the other player's car races on this screen")
	_check(main.state == main.State.RESULTS, "the race finished")
	for i in 60:
		await physics_frame
	net.leave()
	print("[%s] FAILURES: %d" % [role, failures])
	quit(1 if failures > 0 else 0)
