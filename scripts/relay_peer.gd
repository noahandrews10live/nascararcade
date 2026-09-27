extends MultiplayerPeerExtension
## Online through a relay, so a phone can host: every player connects out to a
## Supabase Realtime channel named after the room code, and the game's network
## packets are broadcast on it. The host is peer 1; each joiner picks a random id,
## says hello, and the host welcomes it. The game's RPC code runs over this just
## as it does over a direct WebSocket connection.
##
## The channel speaks the Phoenix protocol Supabase Realtime uses: phx_join to
## join, "broadcast" messages carrying our own events, a heartbeat every 25 s.

const HEARTBEAT := 25.0

var ws := WebSocketPeer.new()
var topic := ""
var host := false
var my_id := 0
var peers := {} # id -> true
var _url := ""
var _ref := 0
var _join_ref := ""
var _joined := false
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _inbox: Array = [] # [from, data, channel, mode]
var _target := 0
var _channel := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _beat := 0.0
var _last := 0
var _hello_t := 0.0


## Start a room (as the host) or join one. `url` is the realtime websocket,
## `code` the room code.
func open(url: String, code: String, as_host: bool) -> Error:
	_url = url
	topic = "realtime:st-" + code.to_upper()
	host = as_host
	my_id = 1 if as_host else randi_range(2, 2147483646)
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	var err := ws.connect_to_url(url)
	if err != OK:
		return err
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	_last = Time.get_ticks_msec()
	return OK


func _next_ref() -> String:
	_ref += 1
	return str(_ref)


func _send_raw(msg: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))


func _broadcast(event: String, payload: Dictionary) -> void:
	_send_raw({"topic": topic, "event": "broadcast", "ref": _next_ref(),
		"payload": {"type": "broadcast", "event": event, "payload": payload}})


func _poll() -> void:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_CLOSED:
		_drop_all()
		return
	if st != WebSocketPeer.STATE_OPEN:
		return
	var now := Time.get_ticks_msec()
	var dt := (now - _last) / 1000.0
	_last = now
	if _join_ref == "":
		_join_ref = _next_ref()
		_send_raw({"topic": topic, "event": "phx_join", "ref": _join_ref, "join_ref": _join_ref,
			"payload": {"config": {"broadcast": {"self": false, "ack": false}, "presence": {"key": ""}, "private": false}}})
	_beat += dt
	if _beat > HEARTBEAT:
		_beat = 0.0
		_send_raw({"topic": "phoenix", "event": "heartbeat", "payload": {}, "ref": _next_ref()})
	# A joiner keeps saying hello until the host answers.
	if _joined and not host and _status == MultiplayerPeer.CONNECTION_CONNECTING:
		_hello_t -= dt
		if _hello_t <= 0.0:
			_hello_t = 1.0
			_broadcast("hello", {"f": my_id})
	while ws.get_available_packet_count() > 0:
		var txt := ws.get_packet().get_string_from_utf8()
		var msg = JSON.parse_string(txt)
		if typeof(msg) == TYPE_DICTIONARY:
			_handle(msg)


func _handle(msg: Dictionary) -> void:
	var ev: String = String(msg.get("event", ""))
	if ev == "phx_reply" and String(msg.get("ref", "")) == _join_ref:
		var ok: bool = String(msg.get("payload", {}).get("status", "")) == "ok"
		if not ok:
			_drop_all()
			return
		_joined = true
		if host:
			_status = MultiplayerPeer.CONNECTION_CONNECTED
		return
	if ev == "phx_error" or ev == "phx_close":
		_drop_all()
		return
	if ev != "broadcast":
		return
	var outer: Dictionary = msg.get("payload", {})
	var kind: String = String(outer.get("event", ""))
	var p: Dictionary = outer.get("payload", {})
	var from := int(p.get("f", 0))
	match kind:
		"hello":
			if host and from > 1:
				if not peers.has(from):
					peers[from] = true
					peer_connected.emit(from)
				_broadcast("welcome", {"f": 1, "t": from})
		"welcome":
			if not host and int(p.get("t", 0)) == my_id and _status != MultiplayerPeer.CONNECTION_CONNECTED:
				_status = MultiplayerPeer.CONNECTION_CONNECTED
				peers[1] = true
				peer_connected.emit(1)
		"bye":
			if peers.has(from):
				peers.erase(from)
				peer_disconnected.emit(from)
			if from == 1 and not host:
				_drop_all()
		"p":
			var to := int(p.get("t", 0))
			if from == my_id or not (to == 0 or to == my_id):
				return
			if not host and from != 1:
				return # joiners only hear from the host
			if host and not peers.has(from):
				return
			_inbox.append([from, Marshalls.base64_to_raw(String(p.get("d", ""))), int(p.get("c", 0)), int(p.get("m", 0))])


func _drop_all() -> void:
	for id in peers.keys():
		peer_disconnected.emit(id)
	peers.clear()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_joined = false


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	_broadcast("p", {"f": my_id, "t": _target if host else 1, "c": _channel, "m": _mode, "d": Marshalls.raw_to_base64(buffer)})
	return OK


func _get_packet_script() -> PackedByteArray:
	if _inbox.is_empty():
		return PackedByteArray()
	return _inbox.pop_front()[1]


func _get_available_packet_count() -> int:
	return _inbox.size()


func _get_packet_peer() -> int:
	return _inbox[0][0] if not _inbox.is_empty() else 0


func _get_packet_channel() -> int:
	return _inbox[0][2] if not _inbox.is_empty() else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return (_inbox[0][3] if not _inbox.is_empty() else 0) as MultiplayerPeer.TransferMode


func _get_max_packet_size() -> int:
	return 1 << 16


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_target_peer(peer: int) -> void:
	_target = peer


func _get_unique_id() -> int:
	return my_id


func _is_server() -> bool:
	return host


func _is_server_relay_supported() -> bool:
	return true


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _close() -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_broadcast("bye", {"f": my_id})
		ws.close()
	_drop_all()


func _disconnect_peer(peer: int, _force: bool) -> void:
	if peers.has(peer):
		peers.erase(peer)
		peer_disconnected.emit(peer)


func _set_refuse_new_connections(_enable: bool) -> void:
	pass


func _is_refusing_new_connections() -> bool:
	return false
