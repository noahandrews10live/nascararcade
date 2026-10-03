extends Node
## Superspeedway pack tools (Daytona, Talladega: the tracks where the draft is
## everything). Your car alone is a sitting duck; a line of cars pushing each
## other is the fastest thing on the track. So:
##   - a drafting partner: the car of your make the crew lines you up with
##     before the green. They trust you, and will push when asked;
##   - the push call (G, the right stick, PUSH on the phone): asks the car
##     directly behind you to push. They decide for themselves: go with you
##     (close to your bumper and shove), or hang you out (pull out of line and
##     go). Trust decides it: your partner almost always helps, a car of your
##     make often, anyone else only if you've pushed them before; and nobody's
##     your friend on the last lap (your partner least of all... almost);
##   - pushing earns it: a clean bump-draft on a car's bumper builds its trust,
##     and your partner asks you for one now and then.
## The spotter calls all of it.

var race: Node3D
var active := false # a drafting track (the pack tools are on)
var partner: Node3D = null
var cool := 0.0 # seconds before the push can be called again
var _ask_t := 30.0 # seconds to the partner's next ask for a push
var _thanked := {} # car -> true once their trust has been earned
var _pushed_at := {} # car -> race time of your last push on them

const CALL_COOL := 4.0
const REACH := 35.0 # metres behind: the car that can push you
const PUSH_TIME := 9.0 # seconds a helper stays on your bumper
const HANG_TIME := 6.0
const HELP_AT := 0.45 # trust (with the modifiers) needed to go with you
const TRUST_PARTNER := 0.75
const TRUST_MAKE := 0.5
const TRUST_OTHER := 0.35
const TRUST_PER_PUSH := 0.12
const COMMIT_DRAG := 0.88 # a car going with you tucks right in and drives to your bumper


func setup(r: Node3D) -> void:
	race = r
	active = float(race.track.cfg.draft) > 0.8 and race.player != null and race.player2 == null
	partner = null
	if not active:
		return
	var p: Node3D = race.player
	var make: int = int(p.team.get("make", -1))
	# The partner: the nearest car of your make on the grid (else the nearest car).
	var best_d := 1e9
	for c in race.cars:
		if c == p or c.is_player or c.remote:
			continue
		var same: bool = make >= 0 and int(c.team.get("make", -2)) == make
		c.trust = TRUST_MAKE if same else TRUST_OTHER
		var dg: float = abs(float(c.get_meta("grid", 0)) - float(p.get_meta("grid", 0))) + (0.0 if same else 1000.0)
		if dg < best_d:
			best_d = dg
			partner = c
	if partner:
		partner.trust = TRUST_PARTNER
		partner.partner = true


## Before the green: the crew names your partner.
func announce() -> void:
	if not active or partner == null or race.control == null:
		return
	var key: String = "TAP PUSH TO CALL FOR ONE" if Game.touch_active else "G CALLS FOR A PUSH"
	race.control.message_for(race.player, "CREW: YOUR DRAFTING PARTNER IS THE %s. WORK TOGETHER - %s" % [partner.team.num, key], "info")


## The car that would push you: directly behind, in your line, close enough.
func pusher_for(p: Node3D) -> Node3D:
	var best: Node3D = null
	var best_g := -REACH
	var nbl: Array = p.nb
	for q in range(0, nbl.size(), 2):
		var o: Node3D = nbl[q]
		var g: float = nbl[q + 1]
		if g < -1.0 and g > best_g and abs(o.d - p.d) < 2.2 and not o.is_player and not o.remote and o.ai \
				and o.pit_state == 0 and not o.out and not o.spinning and not o.finished:
			best = o
			best_g = g
	return best


## Whether the push can be called now (the phone shows PUSH only then).
func can_call(p: Node3D) -> bool:
	return active and cool <= 0.0 and _green() and p.pit_state == 0 and not p.out and pusher_for(p) != null


func _green() -> bool:
	if not race.running:
		return false
	var ctl: Node = race.control
	return ctl == null or ctl.flag == ctl.Flag.GREEN


func laps_left(c: Node3D) -> int:
	return race.laps - c.lap()


## How much `c` wants to help you right now (above HELP_AT: they go with you).
func willing(c: Node3D, p: Node3D) -> float:
	var w: float = c.trust + (0.25 if c.partner else 0.0)
	w -= 0.8 * float(c.rivals.get(p, 0.0))
	var left := laps_left(c)
	var selfish := 0.45 if left <= 1 else (0.2 if left <= 3 else 0.0)
	w -= selfish * (0.5 if c.partner else 1.0)
	return w


## The push call. Returns "help", "hang" or "none".
func call_push(p: Node3D) -> String:
	if not active or cool > 0.0 or not _green():
		return "none"
	cool = CALL_COOL
	var c: Node3D = pusher_for(p)
	if c == null:
		_say(p, "SPOTTER: NOBODY IN LINE BEHIND YOU")
		return "none"
	var who: String = ("YOUR PARTNER, THE %s," if c.partner else "THE %s") % c.team.num
	if willing(c, p) + race.rng.randf_range(-0.12, 0.12) >= HELP_AT:
		c.push_for = p
		c.push_t = PUSH_TIME
		c.hang_t = 0.0
		_say(p, "SPOTTER: %s IS GOING WITH YOU - HERE COMES THE PUSH" % who)
		return "help"
	# Hung out: they pull out of line and go for it themselves (or, boxed in,
	# back out of your draft).
	var lanes: Array = race.lanes
	var idx := 0
	for i in lanes.size():
		if abs(lanes[i] - p.d) < abs(lanes[idx] - p.d):
			idx = i
	var alts: Array = []
	for a in [idx - 1, idx + 1]:
		if a >= 0 and a < lanes.size() and race._lane_clear(c, lanes[a]):
			alts.append(a)
	c.hang_t = HANG_TIME
	c.push_t = 0.0
	c.push_for = null
	c.set_meta("hang_from", p.d)
	if alts.is_empty():
		c.set_meta("hang_back", true)
		_say(p, "SPOTTER: %s HUNG YOU OUT - BACKED OUT OF YOUR DRAFT" % who)
	else:
		var alt: int = alts[race.rng.randi() % alts.size()]
		c.ai_lane = lanes[alt]
		c.set_meta("hang_back", false)
		_say(p, "SPOTTER: %s HUNG YOU OUT - GONE %s" % [who, "HIGH" if alt > idx else "LOW"])
	return "hang"


## A clean bump-draft: `pusher` on `pushed`'s bumper. Yours builds trust.
func on_push(pusher: Node3D, pushed: Node3D) -> void:
	if not active or not pusher.is_player or pushed.is_player:
		return
	var t: float = race.time
	if t - float(_pushed_at.get(pushed, -99.0)) < 2.5:
		return
	_pushed_at[pushed] = t
	pushed.trust = min(pushed.trust + TRUST_PER_PUSH, 1.0)
	if pushed.trust >= 0.6 and not _thanked.has(pushed):
		_thanked[pushed] = true
		_say(pusher, "SPOTTER: THE %s LIKED THAT PUSH - THEY'LL RETURN THE FAVOUR" % pushed.team.num)


func tick(delta: float) -> void:
	if not active:
		return
	cool = max(cool - delta, 0.0)
	var p: Node3D = race.player
	if partner == null or p == null or not _green() or partner.out or p.out:
		return
	# The partner, just ahead in your line, asks for a push now and then.
	_ask_t -= delta
	if _ask_t > 0.0:
		return
	var g: float = race._gap(p, partner)
	if g > 7.0 and g < 25.0 and abs(partner.d - p.d) < 2.2 and partner.pit_state == 0 and p.pit_state == 0:
		_say(p, "SPOTTER: THE %s WANTS A PUSH - GET TO THEIR BUMPER" % partner.team.num)
		_ask_t = 45.0
	else:
		_ask_t = 3.0


func _say(p: Node3D, text: String) -> void:
	if race.control:
		race.control.message_for(p, text, "spotter")
