extends Node
## Time of day and weather for a race.
##
## The clock runs from the track's start time through about two hours over the race,
## so the sun moves: shadows swing round, day races head into the evening, night
## races start at dusk and the lights take over. Track temperature follows the sun.
##
## Rain: the track gets wet (grip falls away on slicks), then dries, fastest where
## the cars run (a drying line). Ovals don't race in the rain: the field is held
## under caution until the track is dry. Road courses race on: wet tyres grip in the
## wet and overheat in the dry.

const BANDS := 10 # wetness across the track, bottom to top

var track: Node3D
var race: Node3D
var main: Node

var hour := 14.0 # time of day
var rate := 0.0 # hours per second of race time
var mode := 0 # 0 clear, 1 changing, 2 rain
var rain := 0.0 # 0..1 intensity now
var wet := PackedFloat32Array() # per band, 0 dry .. 1 soaked
var _next_change := 0.0
var _rain_target := 0.0
var _apply_timer := 0.0


func start(t: Node3D, r: Node3D, m: Node, weather_mode: int) -> void:
	track = t
	race = r
	main = m
	mode = weather_mode
	var cfg: Dictionary = t.cfg
	if cfg.get("night", false):
		hour = 19.2 # green flag at dusk, lights on as it gets dark
	elif float(cfg.get("sun_elev", 45.0)) < 20.0:
		hour = 17.0 # an evening race into sunset
	else:
		hour = 13.5
	# About two hours of clock over the race distance.
	var est: float = max(race.laps * track.length / 65.0, 300.0)
	rate = 2.0 / est
	wet.resize(BANDS)
	for i in BANDS:
		wet[i] = 0.0
	rain = 0.0
	_rain_target = 0.0
	if mode == 2:
		rain = 0.7
		_rain_target = 0.7
		for i in BANDS:
			wet[i] = 0.8
	_next_change = randf_range(60.0, 180.0) if mode == 1 else 150.0
	track.weather = self
	apply()


func is_night() -> bool:
	return sun_elevation() < 4.0


## Sun height (degrees) from the time of day, peaking at the track's usual angle.
func sun_elevation() -> float:
	var peak: float = max(float(track.cfg.get("sun_elev", 45.0)), 35.0)
	return peak * sin(PI * (hour - 6.5) / 13.5)


func sun_azimuth() -> float:
	return float(track.cfg.get("sun_az", 30.0)) + (hour - 13.5) * 15.0


## Track temperature (C): warm under the sun, cooling at night and in the rain.
func track_temp() -> float:
	var base: float = 18.0 + 24.0 * clamp(sun_elevation() / 60.0, 0.0, 1.0)
	return base - 8.0 * average_wet()


func average_wet() -> float:
	var s := 0.0
	for x in wet:
		s += x
	return s / max(wet.size(), 1)


## Wetness at lateral position d.
func wet_at(d: float) -> float:
	if wet.is_empty():
		return 0.0
	var x: float = (d + track.width * 0.5) / track.width
	var i: int = clamp(int(x * BANDS), 0, BANDS - 1)
	return wet[i]


func tick(delta: float) -> void:
	hour += rate * delta
	# Showers come and go when the weather is changeable.
	if mode == 1:
		_next_change -= delta
		if _next_change <= 0.0:
			_rain_target = 0.0 if _rain_target > 0.0 else randf_range(0.4, 0.9)
			_next_change = randf_range(90.0, 240.0) if _rain_target > 0.0 else randf_range(150.0, 400.0)
	elif mode == 2 and not track.cfg.get("road", false):
		# Ovals can't race in the rain: the storm passes and the track dries.
		_next_change -= delta
		if _next_change <= 0.0:
			_rain_target = 0.0
	rain = move_toward(rain, _rain_target, delta * 0.05)
	# Wetting and drying; running cars dry their band much faster.
	var dry: float = (0.0025 + 0.004 * clamp(track_temp() / 40.0, 0.0, 1.0)) * delta
	for i in BANDS:
		wet[i] = clamp(wet[i] + rain * 0.03 * delta - dry * (1.0 - rain), 0.0, 1.0)
	if average_wet() > 0.01 and rain < 0.3:
		for c in race.cars:
			if c.towed or c.pit_state >= 2 or c.speed() < 15.0:
				continue
			var x: float = (c.d + track.width * 0.5) / track.width
			var i: int = int(x * BANDS)
			if i >= 0 and i < BANDS:
				wet[i] = max(wet[i] - 0.0009 * delta * 60.0 / race.cars.size() * 4.0, 0.0)
	_apply_timer -= delta
	if _apply_timer <= 0.0:
		_apply_timer = 2.0
		apply()
	_race_control()


## Ovals: rain brings out the caution and holds the field until it's dry.
func _race_control() -> void:
	var ctl = race.control
	if ctl == null or not ctl.enabled or track.cfg.get("road", false):
		return
	var w := average_wet()
	if w > 0.2 and ctl.flag == ctl.Flag.GREEN or w > 0.2 and ctl.flag == ctl.Flag.WHITE:
		ctl.throw_caution("RAIN", null)
	ctl.weather_hold = w > 0.08 or rain > 0.15


## Sun, sky, light and the look of a wet track.
func apply() -> void:
	if main and main.has_method("apply_time_and_weather"):
		main.apply_time_and_weather(self)


## "7:42 PM  TRACK 96F  RAIN" for the HUD.
func summary() -> String:
	var h := int(hour) % 24
	var m := int((hour - floor(hour)) * 60.0)
	var clock := "%d:%02d %s" % [(h + 11) % 12 + 1, m, "PM" if h >= 12 else "AM"]
	var cond := ""
	var w := average_wet()
	if rain > 0.15:
		cond = "  RAIN"
	elif w > 0.25:
		cond = "  WET"
	elif w > 0.03:
		cond = "  DRYING"
	return "%s  TRACK %dF%s" % [clock, int(track_temp() * 1.8 + 32.0), cond]
