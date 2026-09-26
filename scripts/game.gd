extends Node
## Global game data: tracks, teams, input bindings, records and the arcade font.

const TITLE := "SPEEDWAY THUNDER"
const SUBTITLE := "STOCK CAR ARCADE  '99"
const MPS_TO_MPH := 2.23694
const FIELD_SIZE := 40
const RECORDS_PATH := "user://records.cfg"

## Oval layout: two straights of `straight` metres joined by 180 degree turns of
## `radius`. `bump` pushes the frontstretch outward (tri-oval / quad-oval doglegs).
var tracks: Array[Dictionary] = [
	{
		"name": "THUNDER BEACH INT'L SPEEDWAY",
		"short": "THUNDER BEACH",
		"kind": "SUPERSPEEDWAY",
		"level": "BEGINNER",
		"back": 900.0, "radius": 260.0, "dog_phi": 12.0, "dog_r": 700.0, "front_mid": 0.0, "front_side": 330.0,
		"width": 20.0, "apron": 9.0, "infield": 14.0,
		"bank_turn": 31.0, "bank_straight": 4.0,
		"laps": 3, "draft": 1.0, "grid_player": 24,
		"hp": 510, "cda": 1.05, "cla": 1.6, "pit_mph": 55, "race_laps": 20, "full_laps": 200,
		"sky_top": Color(0.18, 0.38, 0.78), "sky_horizon": Color(0.72, 0.84, 0.95),
		"grass": Color(0.24, 0.55, 0.18), "fog": Color(0.70, 0.80, 0.92),
		"lake": true, "sun_elev": 58.0, "sun_az": 35.0,
	},
	{
		"name": "LONE STAR MOTOR SPEEDWAY",
		"short": "LONE STAR",
		"kind": "QUAD-OVAL SPEEDWAY",
		"level": "ADVANCED",
		"back": 560.0, "radius": 190.0, "dog_phi": 10.0, "dog_r": 250.0, "front_mid": 250.0, "front_side": 110.0,
		"width": 18.0, "apron": 8.0, "infield": 12.0,
		"bank_turn": 24.0, "bank_straight": 5.0,
		"laps": 4, "draft": 0.35, "grid_player": 24,
		"hp": 670, "cda": 1.0, "cla": 2.4, "pit_mph": 45, "race_laps": 30, "full_laps": 267,
		"sky_top": Color(0.35, 0.45, 0.80), "sky_horizon": Color(0.98, 0.78, 0.55),
		"grass": Color(0.42, 0.52, 0.20), "fog": Color(0.93, 0.78, 0.62),
		"lake": false, "sun_elev": 14.0, "sun_az": 205.0,
	},
	{
		"name": "THUNDER VALLEY SHORT TRACK",
		"short": "THUNDER VALLEY",
		"kind": "SHORT TRACK",
		"level": "EXPERT",
		"back": 190.0, "radius": 78.0, "dog_phi": 0.0, "front_mid": 190.0, "front_side": 0.0,
		"width": 15.0, "apron": 6.0, "infield": 8.0,
		"bank_turn": 36.0, "bank_straight": 12.0,
		"laps": 8, "draft": 0.2, "grid_player": 24,
		"hp": 750, "cda": 1.0, "cla": 2.4, "pit_mph": 30, "race_laps": 60, "full_laps": 500,
		"sky_top": Color(0.05, 0.05, 0.20), "sky_horizon": Color(0.25, 0.20, 0.40),
		"grass": Color(0.16, 0.36, 0.14), "fog": Color(0.12, 0.10, 0.22),
		"lake": false, "night": true, "sun_elev": 40.0, "sun_az": 120.0,
	},
	{
		"name": "BIG SKY SUPERSPEEDWAY",
		"short": "BIG SKY",
		"kind": "2.6 MILE SUPERSPEEDWAY",
		"level": "EXPERT",
		"back": 1150.0, "radius": 300.0, "dog_phi": 14.0, "dog_r": 900.0, "front_mid": 0.0, "front_side": 420.0,
		"width": 24.0, "apron": 10.0, "infield": 16.0,
		"bank_turn": 33.0, "bank_straight": 3.0,
		"laps": 3, "draft": 1.0, "grid_player": 24,
		"hp": 510, "cda": 1.05, "cla": 1.6, "pit_mph": 55, "race_laps": 20, "full_laps": 188,
		"sky_top": Color(0.25, 0.45, 0.85), "sky_horizon": Color(0.8, 0.85, 0.95),
		"grass": Color(0.3, 0.5, 0.2), "fog": Color(0.75, 0.8, 0.9),
		"lake": false, "sun_elev": 50.0, "sun_az": 140.0,
	},
	{
		"name": "MOTOR CITY INT'L SPEEDWAY",
		"short": "MOTOR CITY",
		"kind": "2 MILE D-OVAL",
		"level": "ADVANCED",
		"back": 800.0, "radius": 330.0, "dog_phi": 12.0, "dog_r": 700.0, "front_mid": 0.0, "front_side": 290.0,
		"width": 20.0, "apron": 9.0, "infield": 14.0,
		"bank_turn": 18.0, "bank_straight": 5.0,
		"laps": 3, "draft": 0.5, "grid_player": 24,
		"hp": 670, "cda": 1.0, "cla": 2.4, "pit_mph": 55, "race_laps": 20, "full_laps": 200,
		"sky_top": Color(0.3, 0.45, 0.75), "sky_horizon": Color(0.85, 0.85, 0.9),
		"grass": Color(0.25, 0.5, 0.2), "fog": Color(0.8, 0.82, 0.88),
		"lake": true, "sun_elev": 35.0, "sun_az": 250.0,
	},
	{
		"name": "GULF COAST MOTOR SPEEDWAY",
		"short": "GULF COAST",
		"kind": "1.5 MILE OVAL",
		"level": "ADVANCED",
		"back": 620.0, "radius": 215.0, "dog_phi": 0.0, "front_mid": 620.0, "front_side": 0.0,
		"width": 19.0, "apron": 8.0, "infield": 12.0,
		"bank_turn": 20.0, "bank_straight": 4.0,
		"laps": 4, "draft": 0.35, "grid_player": 24,
		"hp": 670, "cda": 1.0, "cla": 2.4, "pit_mph": 45, "race_laps": 25, "full_laps": 267,
		"sky_top": Color(0.3, 0.3, 0.6), "sky_horizon": Color(1.0, 0.6, 0.45),
		"grass": Color(0.3, 0.5, 0.25), "fog": Color(0.95, 0.7, 0.6),
		"lake": false, "sun_elev": 7.0, "sun_az": 290.0,
	},
	{
		"name": "PALMETTO RACEWAY",
		"short": "PALMETTO",
		"kind": "EGG-SHAPED 1.37 MILES",
		"level": "EXPERT",
		"segments": [{"s": "auto1"}, {"r": 190.0, "a": 190.0, "b": 25.0}, {"s": "auto2"}, {"r": 150.0, "a": 170.0, "b": 23.0}],
		"radius": 150.0,
		"width": 15.0, "apron": 6.0, "infield": 10.0,
		"bank_turn": 24.0, "bank_straight": 3.0,
		"laps": 5, "draft": 0.25, "grid_player": 24,
		"hp": 670, "cda": 1.0, "cla": 2.4, "pit_mph": 45, "race_laps": 30, "full_laps": 367,
		"sky_top": Color(0.3, 0.45, 0.75), "sky_horizon": Color(0.9, 0.85, 0.75),
		"grass": Color(0.35, 0.5, 0.2), "fog": Color(0.85, 0.82, 0.75),
		"lake": false, "sun_elev": 30.0, "sun_az": 60.0,
	},
	{
		"name": "MAGNOLIA SPEEDWAY",
		"short": "MAGNOLIA",
		"kind": "0.53 MILE PAPERCLIP",
		"level": "EXPERT",
		"back": 250.0, "radius": 46.0, "dog_phi": 0.0, "front_mid": 250.0, "front_side": 0.0,
		"width": 13.0, "apron": 6.0, "infield": 8.0,
		"bank_turn": 12.0, "bank_straight": 0.0,
		"laps": 10, "draft": 0.1, "grid_player": 24,
		"hp": 750, "cda": 1.0, "cla": 2.4, "pit_mph": 30, "race_laps": 60, "full_laps": 500,
		"sky_top": Color(0.25, 0.4, 0.8), "sky_horizon": Color(0.75, 0.85, 0.95),
		"grass": Color(0.25, 0.55, 0.2), "fog": Color(0.75, 0.82, 0.9),
		"lake": false, "sun_elev": 45.0, "sun_az": 20.0,
	},
	{
		"name": "DESERT SUN RACEWAY",
		"short": "DESERT SUN",
		"kind": "1 MILE DOGLEG OVAL",
		"level": "ADVANCED",
		"segments": [{"s": "auto1"}, {"r": 140.0, "a": 160.0, "b": 11.0}, {"s": "auto2"}, {"r": 260.0, "a": 20.0, "b": 4.0}, {"s": 300.0}, {"r": 175.0, "a": 180.0, "b": 9.0}],
		"radius": 150.0,
		"width": 16.0, "apron": 7.0, "infield": 10.0,
		"bank_turn": 10.0, "bank_straight": 3.0,
		"laps": 6, "draft": 0.15, "grid_player": 24,
		"hp": 750, "cda": 1.0, "cla": 2.4, "pit_mph": 45, "race_laps": 40, "full_laps": 312,
		"sky_top": Color(0.2, 0.4, 0.85), "sky_horizon": Color(0.98, 0.85, 0.65),
		"grass": Color(0.55, 0.45, 0.28), "fog": Color(0.95, 0.85, 0.7),
		"lake": false, "sun_elev": 60.0, "sun_az": 180.0,
	},
	{
		"name": "KEYSTONE TRIANGLE RACEWAY",
		"short": "KEYSTONE",
		"kind": "2.5 MILE TRIANGLE",
		"level": "EXPERT",
		"segments": [{"s": "auto1"}, {"r": 270.0, "a": 125.0, "b": 14.0}, {"s": 850.0}, {"r": 190.0, "a": 100.0, "b": 8.0}, {"s": "auto2"}, {"r": 230.0, "a": 135.0, "b": 6.0}],
		"radius": 230.0,
		"width": 18.0, "apron": 8.0, "infield": 12.0,
		"bank_turn": 10.0, "bank_straight": 2.0,
		"laps": 3, "draft": 0.4, "grid_player": 24,
		"hp": 670, "cda": 1.0, "cla": 2.4, "pit_mph": 55, "race_laps": 16, "full_laps": 160,
		"sky_top": Color(0.3, 0.45, 0.8), "sky_horizon": Color(0.8, 0.85, 0.9),
		"grass": Color(0.2, 0.5, 0.18), "fog": Color(0.75, 0.82, 0.88),
		"lake": false, "sun_elev": 40.0, "sun_az": 300.0,
	},
	{
		"name": "CANYON RIDGE ROAD COURSE",
		"short": "CANYON RIDGE",
		"kind": "2.4 MILE ROAD COURSE",
		"level": "EXPERT",
		"segments": [{"s": "auto1"}, {"r": 55.0, "a": 90.0, "b": 3.0}, {"s": 320.0}, {"r": 40.0, "a": -70.0, "b": 2.0}, {"s": 160.0}, {"r": 60.0, "a": 130.0, "b": 4.0}, {"s": 260.0}, {"r": 35.0, "a": -90.0, "b": 2.0}, {"s": 220.0}, {"r": 80.0, "a": 150.0, "b": 5.0}, {"s": "auto2"}, {"r": 45.0, "a": 150.0, "b": 3.0}],
		"radius": 60.0,
		"width": 14.0, "apron": 3.0, "infield": 10.0,
		"bank_turn": 3.0, "bank_straight": 1.0,
		"laps": 3, "draft": 0.15, "grid_player": 24,
		"hp": 750, "cda": 1.0, "cla": 2.4, "pit_mph": 45, "race_laps": 12, "full_laps": 90,
		"sky_top": Color(0.25, 0.45, 0.8), "sky_horizon": Color(0.85, 0.85, 0.8),
		"grass": Color(0.4, 0.5, 0.22), "fog": Color(0.85, 0.85, 0.8),
		"lake": false, "sun_elev": 45.0, "sun_az": 100.0, "road": true,
	},
]

## Fictional teams. speed/accel/handling are multipliers around 1.0.
var teams: Array[Dictionary] = [
	{"num": "7", "driver": "BUCK RYDER", "sponsor": "THUNDER COLA", "c1": Color(0.85, 0.08, 0.10), "c2": Color(1, 1, 1), "cn": Color(1, 1, 1), "speed": 1.00, "accel": 1.00, "handling": 1.00},
	{"num": "22", "driver": "TRAVIS HAWK", "sponsor": "BIG RIG TIRES", "c1": Color(0.10, 0.25, 0.85), "c2": Color(1.0, 0.85, 0.1), "cn": Color(1.0, 0.85, 0.1), "speed": 1.02, "accel": 0.96, "handling": 0.99},
	{"num": "51", "driver": "RICKY VANCE", "sponsor": "SIZZLE BURGERS", "c1": Color(1.0, 0.80, 0.05), "c2": Color(0.9, 0.2, 0.1), "cn": Color(0.1, 0.1, 0.1), "speed": 0.98, "accel": 1.06, "handling": 1.01},
	{"num": "14", "driver": "WADE COLTER", "sponsor": "GATOR JUICE", "c1": Color(0.10, 0.60, 0.20), "c2": Color(0.1, 0.1, 0.1), "cn": Color(1, 1, 1), "speed": 0.99, "accel": 0.98, "handling": 1.04},
	{"num": "88", "driver": "SONNY PRUITT", "sponsor": "MOTORHEAD OIL", "c1": Color(0.08, 0.08, 0.10), "c2": Color(0.95, 0.45, 0.05), "cn": Color(0.95, 0.45, 0.05), "speed": 1.03, "accel": 0.97, "handling": 0.97},
	{"num": "31", "driver": "EARL TANNER", "sponsor": "CRUNCHY O'S", "c1": Color(0.95, 0.45, 0.70), "c2": Color(0.3, 0.1, 0.5), "cn": Color(1, 1, 1), "speed": 0.98, "accel": 1.02, "handling": 1.03},
	{"num": "5", "driver": "JEB MONROE", "sponsor": "HOG WILD BBQ", "c1": Color(0.55, 0.05, 0.10), "c2": Color(0.9, 0.8, 0.6), "cn": Color(0.9, 0.8, 0.6), "speed": 1.0, "accel": 1.0, "handling": 1.0},
	{"num": "43", "driver": "MACK DALTON", "sponsor": "SKY BLUE FREIGHT", "c1": Color(0.35, 0.70, 0.95), "c2": Color(0.1, 0.2, 0.6), "cn": Color(1, 1, 1), "speed": 1.0, "accel": 1.0, "handling": 1.0},
	{"num": "66", "driver": "DWAYNE STROUD", "sponsor": "ROCKET PARTS", "c1": Color(0.95, 0.95, 0.95), "c2": Color(0.8, 0.1, 0.1), "cn": Color(0.1, 0.1, 0.8), "speed": 1.0, "accel": 1.0, "handling": 1.0},
	{"num": "12", "driver": "KYLE BARROW", "sponsor": "PRAIRIE FEED", "c1": Color(0.60, 0.40, 0.15), "c2": Color(1, 1, 0.8), "cn": Color(1, 1, 0.8), "speed": 1.0, "accel": 1.0, "handling": 1.0},
	{"num": "9", "driver": "BOBBY LEE CRANE", "sponsor": "NITRO GUM", "c1": Color(0.45, 0.10, 0.70), "c2": Color(0.2, 0.9, 0.3), "cn": Color(0.2, 0.9, 0.3), "speed": 1.0, "accel": 1.0, "handling": 1.0},
	{"num": "28", "driver": "RUSTY HOLLIS", "sponsor": "SILVER BULLET TOOLS", "c1": Color(0.70, 0.72, 0.75), "c2": Color(0.1, 0.1, 0.1), "cn": Color(0.85, 0.1, 0.1), "speed": 1.0, "accel": 1.0, "handling": 1.0},
]
## The first N teams can be picked by the player.
const SELECTABLE_TEAMS := 6

var assists := true # steering/stability/traction help for the player
var manual_shift := false
var debug_seed := 0 # fixed randomness for tests
var selected_track := 0
var selected_team := 0
var scanlines := true
## "Modern" = Forward+ PBR rendering. Needs a RenderingDevice (not available on web /
## the Compatibility renderer), otherwise the game stays in 1999 mode.
var modern_supported := false
var modern := false

signal graphics_changed

var _tex := {}

# --- settings, garage setup, season ------------------------------------------------
const SETTINGS_PATH := "user://settings.cfg"
const SEASON_PATH := "user://season.cfg"
const LENGTHS := [["SPRINT", 0.05], ["SHORT", 0.1], ["MEDIUM", 0.25], ["LONG", 0.5], ["FULL", 1.0]]
const DIFFICULTIES := [["ROOKIE", 0.955], ["VETERAN", 0.985], ["LEGEND", 1.0]]
const FIELDS := [20, 30, 40]
const WEEKENDS := ["RACE ONLY", "QUALIFY + RACE", "PRACTICE + QUALIFY + RACE"]
var settings := {
	"length": 1, "difficulty": 1, "field": 2, "cautions": 1, "damage": 1, "wear": 1,
	"assists": 1, "manual": 0, "weekend": 1,
}
## Garage setup (applied to the player's car): -3..3 balance (tight..loose),
## tyre pressure 0 low / 1 std / 2 high, gearing 0 short / 1 std / 2 long.
var setup := {"balance": 0, "pressure": 1, "gearing": 1}
## Season in progress (empty = none).
var season := {}

var arcade_font: FontVariation
var records := ConfigFile.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	arcade_font = FontVariation.new()
	arcade_font.base_font = ThemeDB.fallback_font
	arcade_font.variation_embolden = 0.9
	# Slant the glyphs for that italic arcade cabinet look.
	arcade_font.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.22, 1), Vector2.ZERO)
	records.load(RECORDS_PATH)
	_fill_teams()
	load_settings()
	load_season()
	modern_supported = RenderingServer.get_rendering_device() != null
	modern = modern_supported


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for k in settings:
			settings[k] = cf.get_value("settings", k, settings[k])
		for k in setup:
			setup[k] = cf.get_value("setup", k, setup[k])
		modern = cf.get_value("video", "modern", modern) and modern_supported
		scanlines = cf.get_value("video", "scanlines", scanlines)
	assists = settings.assists == 1
	manual_shift = settings.manual == 1


func save_settings() -> void:
	assists = settings.assists == 1
	manual_shift = settings.manual == 1
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("settings", k, settings[k])
	for k in setup:
		cf.set_value("setup", k, setup[k])
	cf.set_value("video", "modern", modern)
	cf.set_value("video", "scanlines", scanlines)
	cf.save(SETTINGS_PATH)


func race_laps(track_idx: int) -> int:
	var full: int = tracks[track_idx].get("full_laps", 200)
	return max(5, int(round(full * float(LENGTHS[settings.length][1]))))


func ai_skill_scale() -> float:
	return DIFFICULTIES[settings.difficulty][1]


## Applies the garage setup to the player's car.
func apply_setup(c: Node3D) -> void:
	var bal: float = setup.balance # + = looser
	c.grip_front = 0.98 + bal * 0.012
	c.grip_rear = 1.07 - bal * 0.014
	match int(setup.pressure):
		0:
			c.mu *= 1.025
			c.wear_mult = 1.3
		2:
			c.mu *= 0.98
			c.wear_mult = 0.75
	c.gear_scale = [1.08, 1.0, 0.93][int(setup.gearing)]


# --- season ------------------------------------------------------------------------
const SEASON_LENGTHS := [["SHORT", 6], ["HALF", 12], ["FULL", 36]]

func new_season(team_idx: int, length_idx: int) -> void:
	var n: int = SEASON_LENGTHS[length_idx][1]
	var sched: Array = []
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in n:
		sched.append(i % tracks.size() if i < tracks.size() else rng.randi() % tracks.size())
	season = {
		"team": team_idx, "schedule": sched, "round": 0,
		"points": {}, "wins": {}, "top5": {}, "results": [],
	}
	save_season()


func load_season() -> void:
	var cf := ConfigFile.new()
	if cf.load(SEASON_PATH) == OK:
		season = cf.get_value("season", "data", {})


func save_season() -> void:
	var cf := ConfigFile.new()
	cf.set_value("season", "data", season)
	cf.save(SEASON_PATH)


func clear_season() -> void:
	season = {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SEASON_PATH))


## Records a race into the season: points by car number, wins, top 5s.
func record_season_race(track_idx: int, finish: Array) -> void:
	for row in finish:
		var num: String = row.num
		season.points[num] = int(season.points.get(num, 0)) + int(row.points)
		if row.pos == 1:
			season.wins[num] = int(season.wins.get(num, 0)) + 1
		if row.pos <= 5:
			season.top5[num] = int(season.top5.get(num, 0)) + 1
	season.results.append({"track": track_idx, "winner": finish[0].num})
	season.round = int(season.round) + 1
	save_season()


## Standings: [[num, points, wins, top5], ...] sorted.
func standings() -> Array:
	var rows: Array = []
	for num in season.get("points", {}):
		rows.append([num, int(season.points[num]), int(season.wins.get(num, 0)), int(season.top5.get(num, 0))])
	rows.sort_custom(func(a, b): return a[1] > b[1] or (a[1] == b[1] and a[2] > b[2]))
	return rows


func team_by_num(num: String) -> Dictionary:
	for t in teams:
		if t.num == num:
			return t
	return {}


## Pads the hand-made teams out to a full 40-car field with generated ones.
func _fill_teams() -> void:
	var first := ["JIMMY", "CARL", "DENNY", "KYLE", "RYAN", "CHASE", "TYLER", "BRAD", "JOEY", "AUSTIN", "CODY", "DANIEL", "ERIK", "MICHAEL", "ROSS", "TODD", "CHRIS", "JUSTIN", "HARRISON", "CORY", "NOAH", "ZANE", "TY", "JOSH", "RILEY", "COLE", "BUBBA", "SHANE"]
	var last := ["WALKER", "HAYES", "BOONE", "MERCER", "DUVALL", "PIKE", "RANDALL", "CROWE", "LANGSTON", "TATE", "WHITLOCK", "BRADY", "COLLINS", "FARRIS", "HOLLOWAY", "KEENE", "LOWRY", "MADDOX", "NASH", "ODOM", "PRATT", "QUINLAN", "REEVES", "SUTTON", "TRAMMELL", "VAUGHN", "WEBB", "YANCEY"]
	var sponsors := ["PEAK AUTO PARTS", "RIVER BANK", "DIXIE DOGS", "IRONHORSE TRUCKS", "COOL BREEZE HVAC", "BLUEGRASS INSURANCE", "SPARK PLUG CO", "GULF COAST SEAFOOD", "HIGHWAY LUBE", "LONGHORN JERKY", "SUMMIT ROOFING", "PIONEER SEED", "RAPID FREIGHT", "COASTAL CREDIT", "ACE HARDWARE", "MOONSHINE ENERGY", "TITAN TOOLS", "GOLD STAR PIZZA", "CLEARVIEW GLASS", "BIG SKY BOOTS", "NORTHSTAR CABLE", "VELOCITY SODA", "FARMHAND FEED", "SUNRISE PANCAKES", "BRAVO BATTERIES", "TRAILBLAZER RV", "HARBOR PAINT", "OLD TOWN CHILI"]
	var used := {}
	for t in teams:
		used[t.num] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var i := 0
	while teams.size() < max(FIELD_SIZE, 43):
		var num := str(rng.randi_range(1, 99))
		if used.has(num):
			continue
		used[num] = true
		var c1 := Color.from_hsv(rng.randf(), rng.randf_range(0.5, 0.95), rng.randf_range(0.45, 0.95))
		var c2 := Color.from_hsv(fmod(c1.h + 0.5, 1.0), rng.randf_range(0.0, 0.8), rng.randf_range(0.7, 1.0))
		teams.append({
			"num": num,
			"driver": "%s %s" % [first[i % first.size()], last[(i * 5 + 3) % last.size()]],
			"sponsor": sponsors[i % sponsors.size()],
			"c1": c1, "c2": c2, "cn": Color.WHITE if c1.v < 0.6 else Color(0.05, 0.05, 0.05),
			"speed": rng.randf_range(0.985, 1.0), "accel": 1.0, "handling": rng.randf_range(0.975, 1.0),
			"skill": rng.randf_range(0.94, 0.985),
		})
		i += 1


func toggle_graphics() -> void:
	if not modern_supported:
		return
	modern = not modern
	restyle_tree(get_tree().root)
	graphics_changed.emit()


# --- materials -------------------------------------------------------------------

## Creates a material of a given kind; style() gives it the retro or modern look.
func make_mat(kind: String, color := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.set_meta("kind", kind)
	m.set_meta("base_color", color)
	style(m)
	return m


func restyle_tree(node: Node) -> void:
	if node is GeometryInstance3D:
		var mo = node.material_override
		if mo is StandardMaterial3D and mo.has_meta("kind"):
			style(mo)
		if node is MeshInstance3D and node.mesh:
			for i in node.mesh.get_surface_count():
				var sm = node.mesh.surface_get_material(i)
				if sm is StandardMaterial3D and sm.has_meta("kind"):
					style(sm)
		if node is MultiMeshInstance3D and node.multimesh and node.multimesh.mesh:
			for i in node.multimesh.mesh.get_surface_count():
				var mm = node.multimesh.mesh.surface_get_material(i)
				if mm is StandardMaterial3D and mm.has_meta("kind"):
					style(mm)
	if node.is_in_group("retro_only"):
		node.visible = not modern
	if node.is_in_group("modern_only"):
		node.visible = modern
	for c in node.get_children():
		restyle_tree(c)


func style(m: StandardMaterial3D) -> void:
	var kind: String = m.get_meta("kind")
	var base: Color = m.get_meta("base_color", Color.WHITE)
	# Reset to a neutral state first so switching modes is lossless.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if modern else BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.albedo_color = base
	m.metallic = 0.0
	m.metallic_specular = 0.5
	m.roughness = 0.8
	m.clearcoat_enabled = false
	m.albedo_texture = null
	m.normal_enabled = false
	m.normal_texture = null
	m.roughness_texture = null
	m.uv1_triplanar = false
	m.uv1_world_triplanar = false
	m.emission_enabled = false
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	match kind:
		"paint":
			if modern:
				m.metallic = 0.35
				m.roughness = 0.24
				m.clearcoat_enabled = true
				m.clearcoat = 1.0
				m.clearcoat_roughness = 0.06
			else:
				m.roughness = 0.4
				m.metallic_specular = 0.7
		"glass":
			m.metallic = 0.7 if modern else 0.0
			m.roughness = 0.04 if modern else 0.3
			m.metallic_specular = 1.0
		"chrome":
			m.metallic = 0.95 if modern else 0.3
			m.roughness = 0.18
		"rubber":
			m.roughness = 0.95
			m.metallic_specular = 0.2
		"plastic":
			m.roughness = 0.5
		"light":
			m.emission_enabled = true
			m.emission = base
			m.emission_energy_multiplier = 3.0 if modern else 1.0
		"asphalt", "grass", "concrete", "line", "scenery":
			m.vertex_color_use_as_albedo = true
			# The palette was picked by eye, so treat it as sRGB in the linear pipeline.
			m.vertex_color_is_srgb = modern
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			if kind == "scenery" and not modern:
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			if modern:
				m.roughness = {"asphalt": 0.82, "grass": 0.95, "concrete": 0.7, "line": 0.55, "scenery": 0.8}[kind]
				if kind in ["asphalt", "grass", "concrete"]:
					m.uv1_triplanar = true
					m.uv1_world_triplanar = true
					m.uv1_triplanar_sharpness = 4.0
					var sc: float = {"asphalt": 0.35, "grass": 0.12, "concrete": 0.25}[kind]
					m.uv1_scale = Vector3(sc, sc, sc)
					m.albedo_texture = texture(kind, false)
					m.normal_enabled = true
					m.normal_texture = texture(kind, true)
					m.normal_scale = {"asphalt": 0.9, "grass": 0.6, "concrete": 0.4}[kind]
					m.albedo_color = Color(1.12, 1.12, 1.12) * base
					if kind == "grass":
						# Tame the arcade-bright greens toward real turf.
						m.albedo_color = Color(0.78, 0.74, 0.6)
		"lamp":
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = modern
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(4, 4, 3.6) if modern else Color.WHITE
		"foliage":
			m.roughness = 1.0
		"ground":
			if modern:
				m.roughness = 0.95
				m.uv1_triplanar = true
				m.uv1_world_triplanar = true
				m.uv1_scale = Vector3(0.05, 0.05, 0.05)
				m.albedo_texture = texture("grass", false)
				m.normal_enabled = true
				m.normal_texture = texture("grass", true)
				m.normal_scale = 0.5
				m.albedo_color = base.darkened(0.3).lerp(Color(0.3, 0.3, 0.2), 0.3)
		"water":
			m.metallic_specular = 1.0
			m.roughness = 0.05 if modern else 0.1
			m.metallic = 0.3 if modern else 0.0


## Procedural, tileable surface textures (shared, generated once).
func texture(kind: String, normal: bool) -> Texture2D:
	var key := kind + ("_n" if normal else "")
	if _tex.has(key):
		return _tex[key]
	var noise := FastNoiseLite.new()
	noise.seed = hash(kind)
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = noise
	var ramp := Gradient.new()
	match kind:
		"asphalt":
			noise.noise_type = FastNoiseLite.TYPE_VALUE
			noise.frequency = 0.35
			noise.fractal_octaves = 3
			ramp.set_color(0, Color(0.62, 0.62, 0.63))
			ramp.set_color(1, Color(1.0, 1.0, 1.0))
		"grass":
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			noise.frequency = 0.06
			noise.fractal_octaves = 5
			ramp.set_color(0, Color(0.72, 0.78, 0.6))
			ramp.set_color(1, Color(1.05, 1.0, 0.9))
		_:
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			noise.frequency = 0.02
			noise.fractal_octaves = 4
			ramp.set_color(0, Color(0.85, 0.85, 0.84))
			ramp.set_color(1, Color(1.0, 1.0, 1.0))
	if normal:
		t.as_normal_map = true
		t.bump_strength = {"asphalt": 6.0, "grass": 3.0}.get(kind, 2.0)
	else:
		t.color_ramp = ramp
	_tex[key] = t
	return t


func _setup_input() -> void:
	# ints are keyboard keys, "btn:N" joypad buttons, "axis:N+/-" joypad axes.
	var binds := {
		"accelerate": [KEY_UP, KEY_W, KEY_Z, "btn:%d" % JOY_BUTTON_A, "axis:%d+" % JOY_AXIS_TRIGGER_RIGHT],
		"brake": [KEY_DOWN, KEY_S, KEY_X, "btn:%d" % JOY_BUTTON_B, "axis:%d+" % JOY_AXIS_TRIGGER_LEFT],
		"steer_left": [KEY_LEFT, KEY_A, "btn:%d" % JOY_BUTTON_DPAD_LEFT, "axis:%d-" % JOY_AXIS_LEFT_X],
		"steer_right": [KEY_RIGHT, KEY_D, "btn:%d" % JOY_BUTTON_DPAD_RIGHT, "axis:%d+" % JOY_AXIS_LEFT_X],
		"menu_up": [KEY_UP, KEY_W, "btn:%d" % JOY_BUTTON_DPAD_UP],
		"menu_down": [KEY_DOWN, KEY_S, "btn:%d" % JOY_BUTTON_DPAD_DOWN],
		"start": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, "btn:%d" % JOY_BUTTON_START, "btn:%d" % JOY_BUTTON_A],
		"back": [KEY_BACKSPACE, "btn:%d" % JOY_BUTTON_B],
		"camera": [KEY_C, "btn:%d" % JOY_BUTTON_Y],
		"pit": [KEY_TAB, "btn:%d" % JOY_BUTTON_X],
		"pit_option": [KEY_O, "btn:%d" % JOY_BUTTON_DPAD_UP],
		"shift_up": [KEY_E, "btn:%d" % JOY_BUTTON_RIGHT_SHOULDER],
		"shift_down": [KEY_Q, "btn:%d" % JOY_BUTTON_LEFT_SHOULDER],
		"pause": [KEY_ESCAPE, KEY_P, "btn:%d" % JOY_BUTTON_BACK],
		"quit_race": [KEY_Q],
		"toggle_scanlines": [KEY_F2],
		"toggle_graphics": [KEY_F3],
		"toggle_fullscreen": [KEY_F11],
	}
	for action in binds:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		for b in binds[action]:
			var ev: InputEvent
			if b is String and b.begins_with("axis:"):
				var jm := InputEventJoypadMotion.new()
				jm.axis = int(b.substr(5, b.length() - 6)) as JoyAxis
				jm.axis_value = -1.0 if b.ends_with("-") else 1.0
				ev = jm
			elif b is String:
				var jb := InputEventJoypadButton.new()
				jb.button_index = int(b.substr(4)) as JoyButton
				ev = jb
			else:
				var k := InputEventKey.new()
				k.physical_keycode = b as Key
				ev = k
			InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_graphics"):
		toggle_graphics()
	if event.is_action_pressed("toggle_fullscreen"):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


func track() -> Dictionary:
	return tracks[selected_track]


func get_record(track_idx: int, key: String) -> float:
	return records.get_value("track_%d" % track_idx, key, 0.0)


## Stores `value` if it beats the existing record (lower is better). Returns true on a new record.
func submit_record(track_idx: int, key: String, value: float) -> bool:
	var old := get_record(track_idx, key)
	if old > 0.0 and old <= value:
		return false
	records.set_value("track_%d" % track_idx, key, value)
	records.save(RECORDS_PATH)
	return true


static func format_time(t: float) -> String:
	if t <= 0.0:
		return "--'--\"--"
	var m := int(t / 60.0)
	var s := int(t) % 60
	var cs := int(fmod(t, 1.0) * 100.0)
	return "%d'%02d\"%02d" % [m, s, cs]


static func ordinal(n: int) -> String:
	if n % 100 in [11, 12, 13]:
		return "%dTH" % n
	match n % 10:
		1: return "%dST" % n
		2: return "%dND" % n
		3: return "%dRD" % n
	return "%dTH" % n


func make_label(text: String, size: int, color := Color.WHITE, outline := 6) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = arcade_font
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = Color(0, 0, 0)
	ls.shadow_size = 0
	ls.shadow_color = Color(0, 0, 0, 0.6)
	ls.shadow_offset = Vector2(3, 3)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
