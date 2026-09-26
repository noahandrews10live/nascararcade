extends Node
## Online racing over WebSockets.
##
## One player hosts (desktop: opens a port) and friends join with the address. The
## host runs the AI cars and relays every car's state; each player drives and
## simulates their own car locally (so it responds instantly) and sends its state
## 20 times a second. Everyone else's cars are smoothed and extrapolated between
## updates. Contact is resolved by each player for the car they own, so both sides
## of a hit feel it. Online races are green-flag races (no cautions or pit stops).
##
## Browsers can join a host that's reachable over wss:// (a page served over https
## can't open plain ws:// connections).

signal lobby_changed
signal race_started(config: Dictionary)
signal results_in(order: Array)
signal status(text: String)

const PORT := 24565
const SEND_HZ := 20.0
const STATE_SIZE := 13 # idx, dist, d, yaw, v, vy, r, roll, pitch, heave, visible, finished, lap

var peer: WebSocketMultiplayerPeer
var players := {} # peer id -> {"name": String, "team": int}
var hosting := false
var connected := false
var in_race := false
var race: Node3D
var owners := {} # car index -> peer id (1 = the host, which also owns the AI)
var _send_t := 0.0


func my_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1


func host(port := PORT) -> String:
	leave()
	peer = WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		return "COULDN'T OPEN PORT %d" % port
	multiplayer.multiplayer_peer = peer
	hosting = true
	connected = true
	players = {1: {"name": _my_name(), "team": Game.selected_team}}
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	lobby_changed.emit()
	return ""


func join(url: String) -> String:
	leave()
	peer = WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		return "COULDN'T CONNECT TO " + url
	multiplayer.multiplayer_peer = peer
	hosting = false
	if not multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(func(): status.emit("CONNECTION FAILED"))
		multiplayer.server_disconnected.connect(_on_server_gone)
	status.emit("CONNECTING TO " + url)
	return ""


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	hosting = false
	connected = false
	in_race = false
	players.clear()


func _my_name() -> String:
	return String(Game.custom.get("driver", "PLAYER")) if not Game.custom.is_empty() else "PLAYER"


func _on_connected() -> void:
	connected = true
	status.emit("CONNECTED")
	_hello.rpc_id(1, _my_name(), Game.selected_team)


func _on_server_gone() -> void:
	connected = false
	in_race = false
	status.emit("THE HOST LEFT")


func _on_peer_connected(_id: int) -> void:
	pass # they introduce themselves with _hello


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	# Their car carries on under AI control.
	if race and in_race:
		for idx in owners:
			if owners[idx] == id:
				owners[idx] = 1
				var c: Node3D = race.cars[idx]
				c.remote = false
				c.ai = true
	_lobby.rpc(players)
	lobby_changed.emit()


@rpc("any_peer", "reliable")
func _hello(pname: String, team: int) -> void:
	if not hosting:
		return
	players[multiplayer.get_remote_sender_id()] = {"name": pname, "team": team}
	_lobby.rpc(players)
	lobby_changed.emit()


@rpc("authority", "reliable")
func _lobby(p: Dictionary) -> void:
	players = p
	lobby_changed.emit()


## Host: build the grid (players spread through the field, each on a different
## team) and start everyone.
func start_race(track_idx: int, laps: int, field: int) -> void:
	if not hosting:
		return
	var used := {}
	var humans: Array = []
	for id in players:
		var t: int = int(players[id].team)
		while used.has(t) or t >= Game.teams.size():
			t = (t + 1) % Game.teams.size()
		used[t] = true
		humans.append([id, t])
	var size: int = max(field, humans.size())
	var others: Array = range(Game.teams.size()).filter(func(i): return not used.has(i) and not Game.teams[i].get("legend", false))
	others.shuffle()
	var roster: Array = []
	var owner_map := {}
	var slots: Array = []
	for k in humans.size():
		slots.append(int(float(k + 1) / (humans.size() + 1) * size))
	for g in size:
		var h := slots.find(g)
		if h >= 0:
			roster.append(humans[h][1])
			owner_map[g] = humans[h][0]
		else:
			roster.append(others.pop_back())
			owner_map[g] = 1
	var config := {"track": track_idx, "laps": laps, "roster": roster, "owners": owner_map, "seed": randi()}
	_start.rpc(config)


@rpc("authority", "call_local", "reliable")
func _start(config: Dictionary) -> void:
	owners.clear()
	for k in config.owners:
		owners[int(k)] = int(config.owners[k])
	race_started.emit(config)


## The grid slot this peer drives.
func my_slot(config: Dictionary) -> int:
	for k in config.owners:
		if int(config.owners[k]) == my_id():
			return int(k)
	return -1


## Called by main once the race is built.
func attach(r: Node3D) -> void:
	race = r
	in_race = true
	for idx in owners:
		var c: Node3D = race.cars[idx]
		if owners[idx] != my_id():
			c.remote = true
			c.ai = false


func tick(delta: float) -> void:
	if not in_race or race == null or multiplayer.multiplayer_peer == null:
		return
	_send_t -= delta
	if _send_t > 0.0:
		return
	_send_t = 1.0 / SEND_HZ
	var data := PackedFloat32Array()
	# The host relays every car (its AI, its own, and the other players'); a client
	# sends only its own.
	for idx in race.cars.size():
		if hosting or owners.get(idx, 1) == my_id():
			_pack(data, idx, race.cars[idx])
	if hosting:
		_states.rpc(data)
	else:
		_client_state.rpc_id(1, data)


func _pack(data: PackedFloat32Array, idx: int, c: Node3D) -> void:
	data.append(idx)
	data.append(c.dist)
	data.append(c.d)
	data.append(c.yaw)
	data.append(c.v)
	data.append(c.vy)
	data.append(c.r)
	data.append(c.chassis_roll)
	data.append(c.chassis_pitch)
	data.append(c.chassis_z)
	data.append(1.0 if c.visible else 0.0)
	data.append(1.0 if c.finished else 0.0)
	data.append(c.lap_idx)


func _apply(data: PackedFloat32Array) -> void:
	if race == null:
		return
	for o in range(0, data.size() - STATE_SIZE + 1, STATE_SIZE):
		var idx := int(data[o])
		if idx < 0 or idx >= race.cars.size() or owners.get(idx, 1) == my_id():
			continue
		var c: Node3D = race.cars[idx]
		if not c.remote:
			continue
		c.net_state(data.slice(o + 1, o + STATE_SIZE))


@rpc("any_peer", "unreliable_ordered")
func _client_state(data: PackedFloat32Array) -> void:
	if hosting:
		_apply(data)


@rpc("authority", "unreliable_ordered")
func _states(data: PackedFloat32Array) -> void:
	_apply(data)


## Host: the final order, so every screen shows the same result.
func send_results(order: Array) -> void:
	if hosting:
		_results.rpc(order)


@rpc("authority", "reliable")
func _results(order: Array) -> void:
	results_in.emit(order)
