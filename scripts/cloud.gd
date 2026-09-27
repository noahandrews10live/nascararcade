extends Node
## The online side of your career: who you are, your best laps (and their
## ghosts) on the leaderboards, your friends, the daily and weekly events, and
## anonymous stats about how the game runs on your device.
##
## It talks to the game's Supabase project: reads go straight to its tables
## (read-only for everyone), writes go through its "st" function, which checks
## your secret and that a lap time is possible. Nothing here ever blocks the
## game: with no connection every call just gives up quietly.
##
## Your identity is a random id and secret made on first use, saved on the
## device (user://cloud.cfg), with a 6-character friend code to share.

signal changed # your profile or friends changed

const URL := "https://nlkfuldftcaikdbvwoxx.supabase.co"
## The project's public "anon" key (read-only; writes go through the function).
const KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5sa2Z1bGRmdGNhaWtkYnZ3b3h4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA0OTMwMjAsImV4cCI6MjEwNjA2OTAyMH0.fKZ8-80brPK9Jm7ZUE_ccFMFMQ7KPK2o9v5qYV6DYTE"
const SAVE := "user://cloud.cfg"
## Leaderboards exist for the game's own 11 tracks (not mods).
const RANKED_TRACKS := 11

var id := ""
var secret := ""
var friend_code := ""
var friends: Array = [] # [{id, name, num, friend_code, level}]
var online := false # the last call got through
var enabled := true
var _base := URL
var _registering := false


func _ready() -> void:
	var env := OS.get_environment("ST_CLOUD")
	if env != "":
		_base = env
	elif DisplayServer.get_name() == "headless":
		enabled = false # tests never touch the real leaderboards
	var cf := ConfigFile.new()
	if cf.load(SAVE) == OK:
		id = cf.get_value("me", "id", "")
		secret = cf.get_value("me", "secret", "")
		friend_code = cf.get_value("me", "code", "")


func registered() -> bool:
	return id != "" and secret != ""


# --- plumbing ---------------------------------------------------------------------

## One HTTP call; `done` gets (ok: bool, data) with the parsed JSON.
func _call(method: HTTPClient.Method, path: String, body = null, done := Callable()) -> void:
	if not enabled:
		if done.is_valid():
			done.call(false, null)
		return
	var req := HTTPRequest.new()
	req.timeout = 12.0
	add_child(req)
	var headers := PackedStringArray(["apikey: " + KEY, "Authorization: Bearer " + KEY, "Content-Type: application/json"])
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, raw: PackedByteArray):
		req.queue_free()
		var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
		online = result == HTTPRequest.RESULT_SUCCESS
		var data = JSON.parse_string(raw.get_string_from_utf8()) if raw.size() > 0 else null
		if done.is_valid():
			done.call(ok, data))
	var err := req.request(_base + path, headers, method, JSON.stringify(body) if body != null else "")
	if err != OK:
		req.queue_free()
		online = false
		if done.is_valid():
			done.call(false, null)


func _act(action: String, fields: Dictionary, done := Callable()) -> void:
	if not registered():
		register(func(ok: bool):
			if ok:
				_act(action, fields, done)
			elif done.is_valid():
				done.call(false, null))
		return
	var body := fields.duplicate()
	body.action = action
	body.id = id
	body.secret = secret
	_call(HTTPClient.METHOD_POST, "/functions/v1/st", body, done)


func _fetch(query: String, done: Callable) -> void:
	_call(HTTPClient.METHOD_GET, "/rest/v1/" + query, null, done)


# --- you ------------------------------------------------------------------------------

func register(done := Callable()) -> void:
	if registered():
		if done.is_valid():
			done.call(true)
		return
	if _registering:
		if done.is_valid():
			get_tree().create_timer(2.0).timeout.connect(func(): done.call(registered()))
		return
	_registering = true
	var t: Dictionary = Game.custom_team()
	_call(HTTPClient.METHOD_POST, "/functions/v1/st", {"action": "register", "name": t.driver, "num": t.num}, func(ok: bool, data):
		_registering = false
		if ok and data is Dictionary and data.has("id"):
			id = String(data.id)
			secret = String(data.secret)
			friend_code = String(data.friend_code)
			var cf := ConfigFile.new()
			cf.set_value("me", "id", id)
			cf.set_value("me", "secret", secret)
			cf.set_value("me", "code", friend_code)
			cf.save(SAVE)
			changed.emit()
		if done.is_valid():
			done.call(registered()))


## Your name, number and XP (the server keeps the highest XP it has seen).
func push_profile() -> void:
	var t: Dictionary = Game.custom_team()
	_act("profile", {"name": t.driver, "num": t.num, "xp": int(Game.progress.xp)})


# --- laps and ghosts -------------------------------------------------------------------

## A new personal best on `track` (and the ghost to race against).
func submit_lap(track: int, lap_s: float, make: int, ghost: PackedFloat32Array, done := Callable()) -> void:
	if track < 0 or track >= RANKED_TRACKS or lap_s <= 0.0:
		return
	var g := ""
	if ghost.size() > 0:
		g = Marshalls.raw_to_base64(var_to_bytes(ghost).compress(FileAccess.COMPRESSION_DEFLATE))
		if g.length() > 110000:
			g = ""
	var fields := {"track": track, "lap_ms": int(round(lap_s * 1000.0)), "make": make}
	if g != "":
		fields.ghost = g
	_act("lap", fields, done)
	# This week's time trial is on one track: a lap there counts for it too.
	var wk: Dictionary = Game.weekly_event()
	if int(wk.track) == track:
		_act("event", {"event_key": wk.key, "score": int(round(lap_s * 1000.0)), "detail": {"make": make}})


## The fastest laps on `track`: done(rows) with [{name, num, lap_ms, make, player_id}].
func top_laps(track: int, done: Callable, limit := 10) -> void:
	_fetch("laps?select=player_id,lap_ms,make,players(name,num)&track=eq.%d&order=lap_ms.asc&limit=%d" % [track, limit], func(ok: bool, data):
		done.call(_rows(ok, data)))


## Your friends' laps on `track`, with their ghosts.
func friend_laps(track: int, done: Callable) -> void:
	if friends.is_empty():
		done.call([])
		return
	var ids := ",".join(friends.map(func(f): return String(f.id)))
	_fetch("laps?select=player_id,lap_ms,make,ghost,players(name,num)&track=eq.%d&player_id=in.(%s)&order=lap_ms.asc&limit=10" % [track, ids], func(ok: bool, data):
		done.call(_rows(ok, data)))


## The best lap to chase on `track`: your fastest friend's, or else the world
## record's. done(row or {}) where the row has the decoded "samples".
func rival_ghost(track: int, done: Callable) -> void:
	friend_laps(track, func(rows: Array):
		var pick := {}
		for r in rows:
			if r.player_id != id and String(r.get("ghost", "")) != "":
				pick = r
				break
		if not pick.is_empty():
			done.call(_with_samples(pick))
			return
		_fetch("laps?select=player_id,lap_ms,make,ghost,players(name,num)&track=eq.%d&ghost=not.is.null&order=lap_ms.asc&limit=2" % track, func(ok: bool, data):
			for r in _rows(ok, data):
				if r.player_id != id:
					done.call(_with_samples(r))
					return
			done.call({})))


func _with_samples(r: Dictionary) -> Dictionary:
	var raw := Marshalls.base64_to_raw(String(r.get("ghost", "")))
	var bytes := raw.decompress_dynamic(4 << 20, FileAccess.COMPRESSION_DEFLATE)
	var v = bytes_to_var(bytes) if bytes.size() > 0 else null
	if v is PackedFloat32Array:
		r.samples = v
	return r


## Flattens the embedded player into each row: name, num.
func _rows(ok: bool, data) -> Array:
	var out: Array = []
	if not ok or not (data is Array):
		return out
	for r in data:
		if not (r is Dictionary):
			continue
		var p = r.get("players", null)
		r.name = String(p.get("name", "?")) if p is Dictionary else "?"
		r.num = String(p.get("num", "")) if p is Dictionary else ""
		out.append(r)
	return out


# --- events ---------------------------------------------------------------------------

## Today's challenge result: finishing place first, then race time.
func submit_daily(place: int, race_s: float) -> void:
	var score: int = place * 1000000 + min(int(race_s * 100.0), 999999)
	_act("event", {"event_key": Game.daily_event_key(), "score": score, "detail": {"place": place, "time": snappedf(race_s, 0.01)}})


func event_board(key: String, done: Callable, limit := 10) -> void:
	_fetch("event_results?select=player_id,score,detail,players(name,num)&event_key=eq.%s&order=score.asc&limit=%d" % [key.uri_encode(), limit], func(ok: bool, data):
		done.call(_rows(ok, data)))


# --- friends ----------------------------------------------------------------------------

func load_friends(done := Callable()) -> void:
	if not registered():
		if done.is_valid():
			done.call(false)
		return
	_fetch("friends?select=friend_id&player_id=eq." + id, func(ok: bool, data):
		if not ok or not (data is Array) or data.is_empty():
			if ok:
				friends = []
			if done.is_valid():
				done.call(ok)
			return
		var ids := ",".join(data.map(func(r): return String(r.friend_id)))
		_fetch("players?select=id,name,num,friend_code,level&id=in.(%s)" % ids, func(ok2: bool, pl):
			if ok2 and pl is Array:
				friends = pl
				changed.emit()
			if done.is_valid():
				done.call(ok2)))


## Adds a friend by their code: done(ok, message).
func add_friend(code: String, done: Callable) -> void:
	_act("friend", {"code": code.strip_edges().to_upper()}, func(ok: bool, data):
		if ok:
			load_friends()
			done.call(true, "ADDED " + String(data.friend.name) if data is Dictionary and data.has("friend") else "ADDED")
		else:
			done.call(false, String(data.get("error", "COULDN'T REACH THE SERVER")).to_upper() if data is Dictionary else "COULDN'T REACH THE SERVER"))


# --- how the game runs --------------------------------------------------------------------

## After a race: frame rate and the device (no names, no location).
func submit_session(stats: Dictionary) -> void:
	if int(Game.settings.get("share_stats", 1)) == 0:
		return
	_act("session", stats)
