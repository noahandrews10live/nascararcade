extends SceneTree
## The air meter and draft sounds: in a pack at Big Sky the HUD reads DRAFT
## (with the closing speed), PUSH and SIDE DRAFT at times, calls PULL OUT when
## you're closing fast in the tow with room to go, and ticks for each; the
## cue stays quiet under yellow and when the setting is off.
##   ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/draft_cue_test.gd

var main: Node
var game: Node
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _run() -> void:
	game = root.get_node("Game")
	for i in 20:
		await physics_frame
	main.clear_checkpoint()
	game.settings.weather = 0
	game.settings.field = 0
	game.settings.weekend = 0
	game.settings.cautions = 0
	game.settings.length = 1
	game.settings.draft_cue = 1
	main.mode = "race"
	main.session = "race"
	main._use_track(3)
	main._enter_countdown()
	main.autopilot = true
	var seen := {}
	var cues := 0
	var beeps := 0
	var max_close := 0.0
	var label_closing := false
	var prev := ""
	var n := 0
	while n < 60 * 90:
		await physics_frame
		n += 1
		if main.state != main.State.RACE:
			continue
		var a: Dictionary = main.hud.air(main.race.player, main.race)
		seen[a.state] = int(seen.get(a.state, 0)) + 1
		if a.cue:
			cues += 1
			max_close = max(max_close, a.closing)
		if a.state == "DRAFT" and String(main.hud.l_draft.text).contains("+"):
			label_closing = true
		if main._air_state != prev and main._air_state in ["PULL", "DRAFT"]:
			beeps += 1
		prev = main._air_state
	print("   states %s, PULL OUT frames %d (closing up to %.1f mph), cue changes %d" % [str(seen), cues, max_close, beeps])
	_check(int(seen.get("DRAFT", 0)) > 60, "in the pack the meter reads DRAFT")
	_check(label_closing, "with the closing speed on it (DRAFT +n)")
	_check(cues > 0 and max_close > 2.5, "PULL OUT comes up when closing fast in the tow")
	_check(beeps >= 2, "and the meter follows the air: the cue comes and goes (%d changes)" % beeps)
	# Quiet under yellow.
	var ctl: Node = main.race.control
	ctl.flag = ctl.Flag.YELLOW
	var any := false
	for i in 60:
		await physics_frame
		any = any or main.hud.air(main.race.player, main.race).cue
	_check(not any, "no PULL OUT under yellow")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
