extends Node
## Times the game's own work each frame: from the first node's _process to the
## last one's, and the same for each physics step. (Performance's time monitors
## are smoothed and don't add up to a frame.) Drawing isn't included.
##   busy_ms: the last frame's script + physics time.

var busy_ms := 0.0
var _t0 := 0
var _p0 := 0
var _phys := 0.0


class Edge extends Node:
	var first := true
	var timer: Node

	func _process(_d: float) -> void:
		if first:
			timer._t0 = Time.get_ticks_usec()
		else:
			timer.busy_ms = (Time.get_ticks_usec() - timer._t0) / 1000.0 + timer._phys
			timer._phys = 0.0

	func _physics_process(_d: float) -> void:
		if first:
			timer._p0 = Time.get_ticks_usec()
		else:
			timer._phys += (Time.get_ticks_usec() - timer._p0) / 1000.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for first in [true, false]:
		var e := Edge.new()
		e.first = first
		e.timer = self
		e.process_mode = Node.PROCESS_MODE_ALWAYS
		e.process_priority = -100000 if first else 100000
		e.process_physics_priority = -100000 if first else 100000
		add_child(e)
