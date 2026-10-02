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
		"laps": 3, "draft": 1.0, "tow": 3.0, "tow_reach": 2.0, "push": 18.0, "push_reach": 2.5, "pack_gap": 0.1, "grid_player": 24,
		"hp": 510, "cda": 0.92, "cla": 2.6, "gear": 0.9, "pit_mph": 55, "race_laps": 20, "full_laps": 200,
		"sky_top": Color(0.18, 0.38, 0.78), "sky_horizon": Color(0.72, 0.84, 0.95),
		"grass": Color(0.24, 0.55, 0.18), "fog": Color(0.70, 0.80, 0.92),
		"lake": true, "sun_elev": 58.0, "sun_az": 35.0,
	},
	{
		"name": "LONE STAR MOTOR SPEEDWAY",
		"short": "LONE STAR",
		"kind": "QUAD-OVAL SPEEDWAY",
		"level": "ADVANCED",
		"back": 540.0, "radius": 215.0, "dog_phi": 10.0, "dog_r": 250.0, "front_mid": 250.0, "front_side": 110.0,
		"width": 18.0, "apron": 8.0, "infield": 12.0,
		"bank_turn": 24.0, "bank_straight": 5.0,
		"laps": 4, "draft": 0.35, "grid_player": 24,
		"hp": 670, "cda": 1.1, "cla": 2.8, "pit_mph": 45, "race_laps": 30, "full_laps": 267,
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
		"bank_turn": 28.0, "bank_straight": 9.0,
		"laps": 8, "draft": 0.2, "grid_player": 24,
		"hp": 750, "cda": 1.2, "cla": 1.8, "pit_mph": 30, "race_laps": 60, "full_laps": 500,
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
		"laps": 3, "draft": 1.0, "tow": 3.0, "tow_reach": 2.0, "push": 15.8, "push_reach": 2.5, "pack_gap": 0.1, "grid_player": 24,
		"hp": 510, "cda": 0.92, "cla": 2.6, "gear": 0.9, "pit_mph": 55, "race_laps": 20, "full_laps": 188,
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
		"hp": 670, "cda": 1.1, "cla": 2.8, "pit_mph": 55, "race_laps": 20, "full_laps": 200,
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
		"hp": 670, "cda": 1.1, "cla": 2.8, "pit_mph": 45, "race_laps": 25, "full_laps": 267,
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
		"hp": 670, "cda": 1.1, "cla": 2.8, "pit_mph": 45, "race_laps": 30, "full_laps": 367,
		"sky_top": Color(0.3, 0.45, 0.75), "sky_horizon": Color(0.9, 0.85, 0.75),
		"grass": Color(0.35, 0.5, 0.2), "fog": Color(0.85, 0.82, 0.75),
		"lake": false, "sun_elev": 30.0, "sun_az": 60.0,
	},
	{
		"name": "MAGNOLIA SPEEDWAY",
		"short": "MAGNOLIA",
		"kind": "0.53 MILE PAPERCLIP",
		"level": "EXPERT",
		"back": 250.0, "radius": 57.0, "dog_phi": 0.0, "front_mid": 250.0, "front_side": 0.0,
		"width": 13.0, "apron": 6.0, "infield": 8.0,
		"bank_turn": 12.0, "bank_straight": 0.0, "turn_grip": 1.2, # concrete turns
		"laps": 10, "draft": 0.1, "grid_player": 24,
		"hp": 750, "cda": 1.2, "cla": 1.8, "pit_mph": 30, "race_laps": 60, "full_laps": 500,
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
		"hp": 750, "cda": 1.2, "cla": 1.8, "pit_mph": 45, "race_laps": 40, "full_laps": 312,
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
		"hp": 670, "cda": 1.1, "cla": 2.8, "pit_mph": 55, "race_laps": 16, "full_laps": 160,
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
		"hp": 750, "cda": 1.2, "cla": 1.8, "pit_mph": 45, "race_laps": 12, "full_laps": 90,
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
var assist_level := 1.0 # 0 off, 0.5 mild, 1 full
const ASSIST_LEVELS := [0.0, 0.5, 1.0]
var manual_shift := false
var debug_seed := 0 # fixed randomness for tests
var selected_track := 0

# --- create-a-car ------------------------------------------------------------------
const CUSTOM_PATH := "user://custom_car.cfg"
const PALETTE := [
	["RED", Color(0.85, 0.08, 0.1)], ["ORANGE", Color(0.95, 0.45, 0.05)], ["YELLOW", Color(1.0, 0.82, 0.05)],
	["LIME", Color(0.55, 0.9, 0.1)], ["GREEN", Color(0.1, 0.55, 0.2)], ["TEAL", Color(0.05, 0.6, 0.6)],
	["SKY BLUE", Color(0.35, 0.7, 0.95)], ["BLUE", Color(0.1, 0.25, 0.85)], ["NAVY", Color(0.05, 0.08, 0.3)],
	["PURPLE", Color(0.45, 0.1, 0.7)], ["PINK", Color(0.95, 0.45, 0.7)], ["WHITE", Color(0.95, 0.95, 0.95)],
	["SILVER", Color(0.7, 0.72, 0.75)], ["GOLD", Color(0.8, 0.62, 0.2)], ["BROWN", Color(0.45, 0.28, 0.12)],
	["BLACK", Color(0.06, 0.06, 0.07)],
]
const FIRST_NAMES := ["ACE", "BILLY", "BO", "CHARLIE", "CODY", "DALE", "DUSTY", "HANK", "JESSE", "JOHNNY", "LUKE", "MAX", "RAY", "ROCKY", "SAM", "TEX", "TOMMY", "WYATT", "ZEKE", "YOU"]
const LAST_NAMES := ["BLAZE", "BOLT", "BURNETT", "CARVER", "DAWSON", "FIELDS", "GRANGER", "HOLT", "JAMESON", "KNOX", "MCCALL", "PARKER", "RHODES", "SHELBY", "STEELE", "THORNE", "WALLACE", "WILDER", "YATES", "RACER"]
const SPONSORS := ["THUNDER COLA", "BIG RIG TIRES", "SIZZLE BURGERS", "GATOR JUICE", "MOTORHEAD OIL", "CRUNCHY O'S", "HOG WILD BBQ", "ROCKET PARTS", "NITRO GUM", "PEAK AUTO PARTS", "RIVER BANK", "MOONSHINE ENERGY", "TITAN TOOLS", "GOLD STAR PIZZA", "VELOCITY SODA", "YOUR NAME HERE"]
var custom := {"num": 1, "first": 0, "last": 0, "sponsor": 0, "c1": 7, "c2": 11, "cn": 2, "make": 0, "scheme": 0}
var custom_team_idx := -1


func load_custom() -> void:
	var cf := ConfigFile.new()
	if cf.load(CUSTOM_PATH) == OK:
		for k in custom:
			custom[k] = cf.get_value("car", k, custom[k])
	_apply_custom()


func save_custom() -> void:
	var cf := ConfigFile.new()
	for k in custom:
		cf.set_value("car", k, custom[k])
	cf.save(CUSTOM_PATH)
	save_changed.emit()
	_apply_custom()


## The custom car is a real team entry, so every mode can use it.
func custom_team() -> Dictionary:
	return {
		"num": str(custom.num), "driver": "%s %s" % [FIRST_NAMES[custom.first], LAST_NAMES[custom.last]],
		"sponsor": SPONSORS[custom.sponsor], "c1": PALETTE[custom.c1][1], "c2": PALETTE[custom.c2][1],
		"cn": PALETTE[custom.cn][1], "speed": 1.0, "accel": 1.0, "handling": 1.0, "custom": true, "make": custom.make, "scheme": custom.scheme,
	}


func _apply_custom() -> void:
	var t := custom_team()
	# Keep numbers unique: another team using this number takes a free one.
	for i in teams.size():
		if i != custom_team_idx and teams[i].num == t.num:
			var n := 100
			while team_by_num(str(n)).size() > 0:
				n += 1
			teams[i].num = str(n)
	if custom_team_idx < 0:
		teams.append(t)
		custom_team_idx = teams.size() - 1
	else:
		teams[custom_team_idx] = t


## Cars the player can pick: the six featured teams, the custom car, and the
## legendary car once enough Lightning Challenges are done.
func selectable_teams() -> Array:
	var out: Array = range(SELECTABLE_TEAMS)
	if custom_team_idx >= 0:
		out.append(custom_team_idx)
	if legend_unlocked():
		out.append(legend_team_idx())
	return out


# --- Career ------------------------------------------------------------------------
const CAREER_PATH := "user://career.cfg"
const CAREER_START_MONEY := 1000000
const UPGRADES := [
	["engine", "ENGINE", "MORE HORSEPOWER"],
	["aero", "AERO", "LESS DRAG DOWN THE STRAIGHTS"],
	["chassis", "CHASSIS", "MORE GRIP IN THE CORNERS"],
	["crew", "PIT CREW", "FASTER PIT STOPS"],
]
const MAX_UPGRADE := 5
var career := {}


func load_career() -> void:
	var cf := ConfigFile.new()
	if cf.load(CAREER_PATH) == OK:
		career = cf.get_value("career", "data", {})


func save_career() -> void:
	var cf := ConfigFile.new()
	cf.set_value("career", "data", career)
	cf.save(CAREER_PATH)
	save_changed.emit()


func clear_career() -> void:
	career = {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CAREER_PATH))
	save_changed.emit()


func new_career(team_idx: int) -> void:
	career = {
		"team": team_idx, "money": CAREER_START_MONEY, "rep": 10, "year": 1,
		"upgrades": {"engine": 0, "aero": 0, "chassis": 0, "crew": 0},
		"sponsor": {"name": "LOCAL TIRE SHOP", "per_race": 40000, "bonus_win": 100000},
		"offers": [],
		"stats": {"starts": 0, "wins": 0, "top5": 0, "top10": 0, "poles": 0, "laps_led": 0, "titles": 0, "earnings": 0},
		"history": [], "last": "",
	}
	career.offers = sponsor_offers()
	use_season(true)
	new_season(team_idx, 1)
	season.career = true
	save_season()
	save_career()


func upgrade_cost(key: String) -> int:
	return 150000 * (int(career.upgrades[key]) + 1)


func buy_upgrade(key: String) -> bool:
	var lvl: int = career.upgrades[key]
	if lvl >= MAX_UPGRADE or int(career.money) < upgrade_cost(key):
		return false
	career.money = int(career.money) - upgrade_cost(key)
	career.upgrades[key] = lvl + 1
	save_career()
	return true


## What each R&D level is worth. A new career car is as quick as the rest of
## the field; each level is a step you can feel, and a maxed car is well clear.
const UPGRADE_STEP := {"engine": 0.03, "aero": 0.025, "chassis": 0.02, "crew": 0.07}
const UPGRADE_BASE := {"engine": 1.0, "aero": 1.0, "chassis": 1.0, "crew": 1.0}
## Superspeedways keep engine and aero gains in check (the rules there are
## about the pack, and 215 mph is plenty), so those count for a third there.
const PACK_UPGRADE_SHARE := 0.35


## Multipliers for an R&D level: power, drag (lower is better), grip and pit-stop
## time (lower is better).
func upgrade_mult(key: String, lvl: int, pack_track := false) -> float:
	var step: float = UPGRADE_STEP[key] * float(lvl)
	if pack_track and (key == "engine" or key == "aero"):
		step *= PACK_UPGRADE_SHARE
	match key:
		"aero", "crew":
			return UPGRADE_BASE[key] - step
	return UPGRADE_BASE[key] + step


## The shop's line for an upgrade: what it does now, against a stock car.
func upgrade_effect_text(key: String, lvl: int) -> String:
	var m: float = upgrade_mult(key, lvl)
	match key:
		"engine":
			return "%+d%% HORSEPOWER" % roundi((m - 1.0) * 100.0)
		"aero":
			return "%+d%% DRAG" % roundi((m - 1.0) * 100.0)
		"chassis":
			return "%+d%% GRIP" % roundi((m - 1.0) * 100.0)
	return "%+d%% PIT STOP TIME" % roundi((m - 1.0) * 100.0)


func apply_career(c: Node3D) -> void:
	var u: Dictionary = career.upgrades
	var pack: bool = c.track != null and c.track.cfg.has("pack_gap")
	c.power *= upgrade_mult("engine", int(u.engine), pack)
	c.cda *= upgrade_mult("aero", int(u.aero), pack)
	c.mu *= upgrade_mult("chassis", int(u.chassis), pack)
	c.pit_crew_mult = upgrade_mult("crew", int(u.crew), pack)


func sponsor_offers() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var rep: float = career.get("rep", 10)
	var out: Array = []
	var names: Array = SPONSORS.duplicate()
	names.shuffle()
	for i in 3:
		var base: float = 40000.0 + rep * 5000.0
		var per: int = int(round(base * rng.randf_range(0.7, 1.2) / 5000.0) * 5000)
		var bonus: int = int(round((100000.0 + rep * 4000.0) * rng.randf_range(0.5, 1.5) / 10000.0) * 10000)
		out.append({"name": names[i], "per_race": per, "bonus_win": bonus})
	return out


## Money and reputation for a finish. Returns a one-line summary.
func career_race(pos: int, field: int, laps_led: int, won_pole: bool) -> String:
	var frac: float = 1.0 - float(pos - 1) / max(field - 1, 1)
	var purse := int(round((60000.0 + 540000.0 * pow(frac, 1.6)) / 1000.0) * 1000)
	var spons: int = career.sponsor.per_race
	var bonus: int = career.sponsor.bonus_win if pos == 1 else 0
	var total := purse + spons + bonus
	career.money = int(career.money) + total
	career.rep = clamp(int(career.rep) + int(round(frac * 6.0 - 2.0)) + (5 if pos == 1 else 0), 0, 100)
	var st: Dictionary = career.stats
	st.starts += 1
	st.wins += 1 if pos == 1 else 0
	st.top5 += 1 if pos <= 5 else 0
	st.top10 += 1 if pos <= 10 else 0
	st.poles += 1 if won_pole else 0
	st.laps_led += laps_led
	st.earnings += total
	career.last = "LAST RACE: %s  +$%s" % [ordinal(pos), money_text(total)]
	save_career()
	return career.last


func career_season_end(final_pos: int, points: int, wins: int) -> void:
	career.history.append({"year": career.year, "pos": final_pos, "points": points, "wins": wins})
	if final_pos == 1:
		career.stats.titles += 1
	career.year = int(career.year) + 1
	career.offers = sponsor_offers()
	new_season(int(career.team), 1)
	season.career = true
	save_season()
	save_career()


static func money_text(v: int) -> String:
	var sgn := "-" if v < 0 else ""
	var s := str(abs(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return sgn + s + out


# --- Lightning Challenges ------------------------------------------------------------
const CHALLENGES_PATH := "user://challenges.cfg"
## track: index into tracks; grid: your starting spot; start: leader's distance to the
## line at the start (negative = before it); goal: "win", "top3", "top5", "top10" or
## "time" (with "time" in seconds for a solo hot lap).
const CHALLENGES := [
	{"name": "LAST LAP LUNGE", "desc": "WHITE FLAG AT THUNDER BEACH. YOU'RE 2ND IN THE DRAFT. WIN IT.", "track": 0, "laps": 1, "field": 16, "grid": 2, "start": -500.0, "goal": "win"},
	{"name": "SHORT TRACK SCRAPPER", "desc": "START 20TH AT THUNDER VALLEY. 6 LAPS TO GET INTO THE TOP 5.", "track": 2, "laps": 6, "field": 24, "grid": 20, "goal": "top5"},
	{"name": "HOLD THE LINE", "desc": "LEADING AT BIG SKY WITH 3 TO GO AND THE PACK BEHIND YOU. WIN.", "track": 3, "laps": 3, "field": 25, "grid": 1, "goal": "win"},
	{"name": "PAPERCLIP PATIENCE", "desc": "MAGNOLIA. 12 LAPS, START 8TH WITH A BENT FENDER. WIN.", "track": 7, "laps": 12, "field": 20, "grid": 8, "damage": 0.2, "goal": "win"},
	{"name": "FUEL MISER", "desc": "GULF COAST. 8 LAPS, NOT QUITE ENOUGH FUEL. FINISH TOP 10.", "track": 5, "laps": 8, "field": 24, "grid": 6, "fuel": 0.15, "goal": "top10", "wear": true},
	{"name": "ROAD WARRIOR", "desc": "CANYON RIDGE ROAD COURSE. START 12TH, 3 LAPS. TOP 3.", "track": 10, "laps": 3, "field": 20, "grid": 12, "goal": "top3"},
	{"name": "TRIANGLE HOT LAP", "desc": "ONE LAP OF KEYSTONE, ALONE. BEAT 70 SECONDS.", "track": 9, "laps": 1, "field": 1, "grid": 1, "start": -2400.0, "goal": "time", "time": 70.0},
	{"name": "EGG TIMER", "desc": "PALMETTO ON WORN TIRES. 5 LAPS FROM 10TH. TOP 5.", "track": 6, "laps": 5, "field": 24, "grid": 10, "tyres": 0.9, "goal": "top5"},
]
var challenges_done := {}


func load_challenges() -> void:
	var cf := ConfigFile.new()
	if cf.load(CHALLENGES_PATH) == OK:
		challenges_done = cf.get_value("done", "list", {})


func complete_challenge(idx: int) -> bool:
	var first := not challenges_done.has(str(idx))
	challenges_done[str(idx)] = true
	var cf := ConfigFile.new()
	cf.load(CHALLENGES_PATH) # keep the daily results in the same file
	cf.set_value("done", "list", challenges_done)
	cf.save(CHALLENGES_PATH)
	save_changed.emit()
	return first


## Today's challenge: the same for everyone on a given day, a new one tomorrow.
func daily_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d%02d%02d" % [d.year, d.month, d.day]


## The key the online daily leaderboard files today's results under.
func daily_event_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "daily-%04d-%02d-%02d" % [d.year, d.month, d.day]


## This week's time trial: the same track for everyone all week (ISO weeks),
## best lap wins. {key, track, name}.
func weekly_event() -> Dictionary:
	var unix := int(Time.get_unix_time_from_system())
	var days := unix / 86400
	# ISO week: weeks start on Monday; 1970-01-01 was a Thursday.
	var dow := (days + 3) % 7 # 0 = Monday
	var thursday := days - dow + 3
	var td := Time.get_date_dict_from_unix_time(thursday * 86400)
	var jan1 := int(Time.get_unix_time_from_datetime_dict({"year": td.year, "month": 1, "day": 1})) / 86400
	var week := (thursday - jan1) / 7 + 1
	var track: int = (td.year * 53 + week) % mini(tracks.size(), 11)
	return {"key": "weekly-%04d-W%02d" % [td.year, week], "track": track, "name": String(tracks[track].short) + " TIME TRIAL"}


# --- progression ---------------------------------------------------------------

const PROGRESS_PATH := "user://progress.cfg"
var progress := {"xp": 0, "streak": 0, "best_streak": 0, "streak_day": ""}
## Daily challenge streak: bonus XP per day in a row (up to 7 days' worth), and a
## 7-day streak earns the CHECKERED scheme.
const STREAK_XP := 100
const STREAK_SCHEME_DAYS := 7
## What each level unlocks (the paint schemes, in order).
const SCHEME_LEVEL := [1, 1, 2, 3, 4, 5, 6] # CLASSIC, TWO-TONE, SWOOSH, TWIN STRIPES, FLAMES, ARROW, SPLIT


static func level_for(xp: int) -> int:
	# The same curve as the server: 500 XP to level 2, each level 15% more.
	var lvl := 1
	var need := 500
	var left := xp
	while left >= need and lvl < 99:
		left -= need
		lvl += 1
		need = int(round(need * 1.15))
	return lvl


## XP into this level and the XP the level takes: [into, needed].
static func level_progress(xp: int) -> Array:
	var need := 500
	var left := xp
	var lvl := 1
	while left >= need and lvl < 99:
		left -= need
		lvl += 1
		need = int(round(need * 1.15))
	return [left, need]


func level() -> int:
	return level_for(int(progress.xp))


func scheme_unlocked(i: int) -> bool:
	if i >= SCHEME_LEVEL.size():
		return int(progress.get("best_streak", 0)) >= STREAK_SCHEME_DAYS
	return level() >= int(SCHEME_LEVEL[clamp(i, 0, SCHEME_LEVEL.size() - 1)])


## What it takes to unlock a scheme, for the paint shop.
func scheme_needs(i: int) -> String:
	if i >= SCHEME_LEVEL.size():
		return "%d-DAY STREAK" % STREAK_SCHEME_DAYS
	return "LV %d" % int(SCHEME_LEVEL[i])


func load_progress() -> void:
	var cf := ConfigFile.new()
	if cf.load(PROGRESS_PATH) == OK:
		progress.xp = int(cf.get_value("progress", "xp", 0))
		progress.streak = int(cf.get_value("progress", "streak", 0))
		progress.best_streak = int(cf.get_value("progress", "best_streak", 0))
		progress.streak_day = String(cf.get_value("progress", "streak_day", ""))


func save_progress() -> void:
	var cf := ConfigFile.new()
	for k in progress:
		cf.set_value("progress", k, progress[k])
	cf.save(PROGRESS_PATH)
	save_changed.emit()


## The current streak as it stands today (0 if a day was missed).
func streak_now() -> int:
	var last := String(progress.get("streak_day", ""))
	if last == daily_key() or last == _day_key(-1):
		return int(progress.get("streak", 0))
	return 0


## A day's key like daily_key() (local date), `offset_days` from today.
func _day_key(offset_days: int) -> String:
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0)) # minutes from UTC
	var d := Time.get_date_dict_from_unix_time(int(Time.get_unix_time_from_system()) + bias * 60 + offset_days * 86400)
	return "%04d%02d%02d" % [d.year, d.month, d.day]


## Today's daily challenge done: the streak grows (or starts again), with bonus
## XP. Returns {streak, xp, unlocked_scheme}.
func add_streak_day() -> Dictionary:
	var today := daily_key()
	if String(progress.get("streak_day", "")) == today:
		return {"streak": int(progress.streak), "xp": 0, "unlocked_scheme": false}
	var had := scheme_unlocked(SCHEME_LEVEL.size())
	progress.streak = int(progress.streak) + 1 if String(progress.get("streak_day", "")) == _day_key(-1) else 1
	progress.streak_day = today
	progress.best_streak = maxi(int(progress.best_streak), int(progress.streak))
	var bonus: int = STREAK_XP * mini(int(progress.streak), STREAK_SCHEME_DAYS)
	progress.xp = int(progress.xp) + bonus
	save_progress()
	return {"streak": int(progress.streak), "xp": bonus, "unlocked_scheme": not had and scheme_unlocked(SCHEME_LEVEL.size())}


## XP for a race: the result, the laps run, a clean race, a win. Returns
## {xp, total, level, levelled_up}.
func award_race(place: int, field: int, laps: int, clean: bool) -> Dictionary:
	var before := level()
	var xp: int = 60 + maxi(field - place, 0) * 8 + laps * 6
	if place == 1:
		xp += 200
	elif place <= 3:
		xp += 80
	if clean:
		xp += 40
	progress.xp = int(progress.xp) + xp
	save_progress()
	return {"xp": xp, "total": progress.xp, "level": level(), "levelled_up": level() > before}


func daily_challenge() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("daily" + daily_key())
	var t := rng.randi_range(0, tracks.size() - 1)
	var name: String = tracks[t].short
	var kind := rng.randi_range(0, 3)
	var ch := {"track": t, "field": 24}
	match kind:
		0:
			var g := rng.randi_range(14, 22)
			ch.merge({"name": "CHARGE AT %s" % name, "laps": rng.randi_range(5, 8), "grid": g, "goal": "top5", "desc": "START %s AT %s. GET INTO THE TOP 5." % [ordinal(g), name]})
		1:
			ch.merge({"name": "HOLD ON AT %s" % name, "laps": 3, "grid": 1, "goal": "win", "desc": "LEADING AT %s, 3 TO GO, THE PACK ON YOUR BUMPER. WIN." % name})
		2:
			var g2 := rng.randi_range(5, 10)
			ch.merge({"name": "WORN OUT AT %s" % name, "laps": 5, "grid": g2, "goal": "top3", "tyres": 0.85, "wear": true, "desc": "%s ON WORN TIRES. 5 LAPS FROM %s. TOP 3." % [name, ordinal(g2)]})
		_:
			var g3 := rng.randi_range(8, 16)
			ch.merge({"name": "BENT FENDER AT %s" % name, "laps": 6, "grid": g3, "goal": "top5", "damage": 0.2, "desc": "DAMAGED CAR AT %s. 6 LAPS FROM %s. TOP 5." % [name, ordinal(g3)]})
	return ch


func daily_done() -> bool:
	var cf := ConfigFile.new()
	cf.load(CHALLENGES_PATH)
	return cf.get_value("daily", daily_key(), false)


func complete_daily() -> bool:
	var first := not daily_done()
	var cf := ConfigFile.new()
	cf.load(CHALLENGES_PATH)
	cf.set_value("daily", daily_key(), true)
	cf.save(CHALLENGES_PATH)
	save_changed.emit()
	return first


func legend_unlocked() -> bool:
	return challenges_done.size() >= 5


func legend_team_idx() -> int:
	for i in teams.size():
		if teams[i].get("legend", false):
			return i
	teams.append({"num": "00", "driver": "THUNDER JONES", "sponsor": "THUNDERBOLT", "c1": Color(0.08, 0.08, 0.1), "c2": Color(1.0, 0.8, 0.1), "cn": Color(1.0, 0.8, 0.1), "speed": 1.03, "accel": 1.04, "handling": 1.04, "legend": true})
	return teams.size() - 1
var selected_team := 0
var scanlines := true
## "Modern" = Forward+ PBR rendering. Needs a RenderingDevice (not available on web /
## the Compatibility renderer), otherwise the game stays in 1999 mode.
var modern_supported := false
var modern := false
var forward_plus := false
## Modern-mode quality: 0 AUTO, 1 LOW, 2 MEDIUM, 3 HIGH, 4 ULTRA.
const QUALITY_NAMES := ["AUTO", "LOW", "MEDIUM", "HIGH", "ULTRA"]
var quality := 0
## The level AUTO is currently running at (adjusted from measured frame times).
var auto_quality := 2 if OS.has_feature("web") else 3
## Blend car positions between physics steps so motion is smooth at any refresh rate.
var smoothing := true
var vsync := true
var motion_blur := 1 # 0 off, 1 low, 2 high (desktop Modern only)
var radio_voice := true # spoken spotter and crew chief calls
## Steering wheel: which pad and axes, pedal direction, wheel rotation, FFB strength.
var wheel := {"enabled": false, "device": 0, "steer_axis": 0, "throttle_axis": 5, "brake_axis": 4, "invert": false, "rotation": 3, "ffb": 2}

signal graphics_changed

## A file that belongs in the cloud save changed (main passes it on to the cloud).
signal save_changed
var _tex := {}
## Photo surface textures: metres per repeat (their real size, or a little more
## where a small patch would tile visibly). Each is a neutral grey detail map;
## the track's own colours tint it.
const PHOTO_TILE := {"asphalt": 3.0, "concrete": 4.0, "grass": 2.8}

# --- settings, garage setup, season ------------------------------------------------
const SETTINGS_PATH := "user://settings.cfg"
const SEASON_PATH := "user://season.cfg"
const LENGTHS := [["SPRINT", 0.05], ["SHORT", 0.1], ["MEDIUM", 0.25], ["LONG", 0.5], ["FULL", 1.0]]
const DIFFICULTIES := [["ROOKIE", 0.955], ["VETERAN", 0.985], ["LEGEND", 1.0]]
## The most cars in any race (every mode: the field sizes, AUTO, challenges,
## online). Keeps a race smooth on phones.
const MAX_CARS := 25
const FIELDS := [20, 25]
## Field size "AUTO" (settings.field = -1): as many cars as this device runs
## smoothly. Worked out from how the last race ran: the script time per frame
## against a model of it (a fixed part plus a part per car, in ms on the
## reference machine), aiming to leave room in a 60 fps frame for drawing.
const PERF_FIXED_MS := 2.5
const PERF_CAR_MS := 0.13
const PERF_BUDGET_MS := 9.0
const WEEKENDS := ["RACE ONLY", "QUALIFY + RACE", "PRACTICE + QUALIFY + RACE"]
var settings := {
	# field: -1 = AUTO (see field_size), else an index into FIELDS.
	"length": 1, "difficulty": 1, "field": -1, "auto_field": 0, "cautions": 1, "damage": 1, "wear": 1, "weather": 0,
	"assists": 2, "manual": 0, "weekend": 1, "touch_tilt": true, "tilt_sens": 1, "res_mode": 0, "commentary": 1, "catchup": 0,
	"auto_gas": 0, "tutorial_done": 0, "share_stats": 1, "haptics": 1, "battery": 1, "draft_cue": 1,
	"big_text": 0, "map_contrast": 0, "hand": 0, # accessibility: larger text, high-contrast map, left-handed controls
}
## Garage setup (applied to the player's car): -3..3 balance (tight..loose),
## tyre pressure 0 low / 1 std / 2 high, gearing 0 short / 1 std / 2 long.
var setup := {"balance": 0, "pressure": 1, "gearing": 1, "springs_f": 1, "springs_r": 1, "bar_f": 1, "bump": 1, "stagger": 1, "psi_l": 1, "psi_r": 1, "bias": 2}
## Your garage setup for each track you've tuned (track index -> setup), saved
## with the settings and put back when you go to that track.
var track_setups := {}


func remember_setup(track_idx: int) -> void:
	track_setups[str(track_idx)] = setup.duplicate()


## The setup you last used at this track, if you've tuned one there.
func recall_setup(track_idx: int) -> bool:
	var saved = track_setups.get(str(track_idx))
	if not (saved is Dictionary):
		return false
	for k in saved:
		if setup.has(k):
			setup[k] = saved[k]
	return true
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
	load_mods()
	_fill_teams()
	# Modern works on both renderers; Forward+ (desktop Vulkan/D3D12) adds SSAO,
	# SSR, volumetric fog and FSR 2 on top of the Compatibility (browser) version.
	forward_plus = RenderingServer.get_rendering_device() != null
	modern_supported = true
	modern = true
	load_settings()
	_split_seasons()
	load_season()
	load_custom()
	load_progress()
	load_challenges()
	load_career()


# --- mods: tracks and teams from JSON --------------------------------------------

const MODS_DIR := "user://mods"
const COLOR_KEYS := ["sky_top", "sky_horizon", "grass", "fog", "c1", "c2", "cn"]


## Tracks in user://mods/tracks/*.json and teams in user://mods/teams/*.json (a list
## of teams per file). Colours are "#rrggbb". Missing track settings come from a
## standard intermediate, so a mod only needs a name and a layout.
func load_mods() -> void:
	for path in _json_files(MODS_DIR + "/tracks"):
		var d = _read_json(path)
		if d is Dictionary and d.has("name"):
			add_track(d)
	for path in _json_files(MODS_DIR + "/teams"):
		var arr = _read_json(path)
		if arr is Array:
			for t in arr:
				if t is Dictionary and t.has("num"):
					teams.append(_colors_in(t))


func add_track(d: Dictionary) -> int:
	var t: Dictionary = tracks[1].duplicate(true)
	for k in ["front_mid", "front_side", "dog_r", "dog_phi", "back"]:
		t.erase(k)
	for k in d:
		t[k] = d[k]
	t = _colors_in(t)
	t["mod"] = true
	t["short"] = String(t.get("short", String(t.name).left(14)))
	for i in tracks.size():
		if tracks[i].name == t.name:
			tracks[i] = t
			return i
	tracks.append(t)
	return tracks.size() - 1


func save_track_mod(d: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(MODS_DIR + "/tracks")
	var out := {}
	for k in d:
		var v = d[k]
		out[k] = ("#" + (v as Color).to_html(false)) if v is Color else v
	var path := MODS_DIR + "/tracks/" + String(d.name).to_lower().replace(" ", "_").replace("'", "") + ".json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
	return ProjectSettings.globalize_path(path)


func _colors_in(d: Dictionary) -> Dictionary:
	for k in COLOR_KEYS:
		if d.has(k) and d[k] is String:
			d[k] = Color.html(d[k])
	return d


func _json_files(dir: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		if f.ends_with(".json"):
			out.append(dir + "/" + f)
	return out


func _read_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f else null


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for k in settings:
			settings[k] = cf.get_value("settings", k, settings[k])
		for k in setup:
			setup[k] = cf.get_value("setup", k, setup[k])
		track_setups = cf.get_value("setup", "per_track", {})
		modern = cf.get_value("video", "modern_look", modern) and modern_supported
		scanlines = cf.get_value("video", "scanlines", scanlines)
		quality = cf.get_value("video", "quality", quality)
		auto_quality = cf.get_value("video", "auto_quality", auto_quality)
		smoothing = cf.get_value("video", "smoothing", smoothing)
		vsync = cf.get_value("video", "vsync", vsync)
		motion_blur = cf.get_value("video", "motion_blur", motion_blur)
		radio_voice = cf.get_value("audio", "radio_voice", radio_voice)
		for k in wheel:
			wheel[k] = cf.get_value("wheel", k, wheel[k])
		# Field sizes used to be 20 / 30 / 40 with no AUTO: start everyone on AUTO.
		if not cf.get_value("settings", "field_v2", false):
			settings.field = -1
		# Assists used to be OFF / ON; ON is now FULL (OFF / MILD / FULL).
		if not cf.get_value("settings", "assists_v2", false) and int(settings.assists) == 1:
			settings.assists = 2
	_apply_assists()
	manual_shift = settings.manual == 1


func _apply_assists() -> void:
	assist_level = ASSIST_LEVELS[clamp(int(settings.assists), 0, 2)]
	assists = assist_level > 0.0


## The battery: [percent 0..100 or -1 if unknown, on battery (not charging)].
## Only browsers that share it (Chrome, Android) say; elsewhere it's unknown.
func battery() -> Array:
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var b = JavaScriptBridge.eval("window.stBattery ? JSON.stringify(window.stBattery) : ''", true)
		if b is String and b != "":
			var d = JSON.parse_string(b)
			if d is Dictionary:
				return [int(round(float(d.get("level", 1.0)) * 100.0)), not bool(d.get("charging", true))]
		return [-1, false]
	return [-1, false] # Godot 4 has no battery API on the phone apps


## BATTERY SAVER: OFF / AUTO (on battery at 20% or less) / ON. Saving means 30
## frames a second instead of the screen's full rate (the race itself still
## runs 60 steps a second, so it drives the same).
func battery_saving() -> bool:
	match int(settings.get("battery", 1)):
		2:
			return true
		1:
			var b := battery()
			return b[1] and b[0] >= 0 and b[0] <= 20
	return false


## After a saved game came down from the cloud: load it all again.
func reload_saved_game() -> void:
	records = ConfigFile.new()
	records.load(RECORDS_PATH)
	load_custom()
	load_progress()
	load_challenges()
	load_career()
	_split_seasons()
	load_season()


## Cars in a race: the chosen size, or on AUTO what this device handles.
func field_size() -> int:
	var f := int(settings.get("field", -1))
	if f >= 0:
		return FIELDS[clampi(f, 0, FIELDS.size() - 1)]
	var a := int(settings.get("auto_field", 0))
	return mini(a, MAX_CARS) if a > 0 else first_field_guess()


## Before any race has been timed: careful in a browser on a phone.
func first_field_guess() -> int:
	if OS.has_feature("web"):
		return 20 if touch_device() else 25
	return MAX_CARS


## What the field size on AUTO should be after a race with `cars` cars that took
## `script_ms` of script time and `frame_ms` in all per frame (averages).
static func auto_field_for(cars: int, script_ms: float, frame_ms: float, current: int) -> int:
	var slow: float = script_ms / (PERF_FIXED_MS + PERF_CAR_MS * cars) # 1 = the reference machine
	var fit: float = (PERF_BUDGET_MS / max(slow, 0.05) - PERF_FIXED_MS) / PERF_CAR_MS
	if frame_ms > 20.0: # under 50 fps whatever the model says: fewer cars
		fit = min(fit, cars - 5)
	var pick: int = FIELDS[0]
	for f in FIELDS:
		if f <= fit:
			pick = f
	# Down at once; up one size at a time.
	var i := FIELDS.find(current)
	if i >= 0 and pick > current:
		pick = FIELDS[min(i + 1, FIELDS.size() - 1)]
	return pick


## Learn from how a race ran, for AUTO next time.
func note_race_perf(cars: int, script_ms: float, frame_ms: float) -> void:
	if cars < 10:
		return
	var cur := int(settings.get("auto_field", 0))
	if cur <= 0:
		cur = first_field_guess()
	var pick := auto_field_for(cars, script_ms, frame_ms, cur)
	if pick != int(settings.get("auto_field", 0)):
		settings.auto_field = pick
		save_settings()


func save_settings() -> void:
	_apply_assists()
	manual_shift = settings.manual == 1
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("settings", k, settings[k])
	cf.set_value("settings", "assists_v2", true)
	cf.set_value("settings", "field_v2", true)
	for k in setup:
		cf.set_value("setup", k, setup[k])
	cf.set_value("setup", "per_track", track_setups)
	cf.set_value("video", "modern_look", modern)
	cf.set_value("video", "scanlines", scanlines)
	cf.set_value("video", "quality", quality)
	cf.set_value("video", "auto_quality", auto_quality)
	cf.set_value("video", "smoothing", smoothing)
	cf.set_value("video", "vsync", vsync)
	cf.set_value("video", "motion_blur", motion_blur)
	cf.set_value("audio", "radio_voice", radio_voice)
	for k in wheel:
		cf.set_value("wheel", k, wheel[k])
	cf.save(SETTINGS_PATH)


func race_laps(track_idx: int) -> int:
	var full: int = tracks[track_idx].get("full_laps", 200)
	return max(5, int(round(full * float(LENGTHS[settings.length][1]))))


func ai_skill_scale() -> float:
	return DIFFICULTIES[settings.difficulty][1]


## Applies the garage setup to the player's car.
func apply_setup(c: Node3D) -> void:
	var bal: float = setup.balance # + = looser
	c.grip_front = 1.02 + bal * 0.012 # at 0, the same balance as every other car
	c.grip_rear = 1.07 - bal * 0.014
	# Real setup pieces: wedge (cross weight), springs, sway bar, bump stops,
	# stagger, pressures per side, brake bias and gearing.
	c.wedge = -bal * 250.0
	c.k_front = 90000.0 * [0.8, 1.0, 1.25][int(setup.springs_f)]
	c.k_rear = 75000.0 * [0.8, 1.0, 1.25][int(setup.springs_r)]
	c.k_arb_f = 35000.0 * [0.7, 1.0, 1.4][int(setup.bar_f)] * (1.0 - 0.06 * bal)
	c.bump_gap = [0.045, 0.06, 0.075][int(setup.bump)]
	c.stagger *= [0.7, 1.0, 1.3][int(setup.stagger)]
	c.psi_l = [0.92, 1.0, 1.08][int(setup.psi_l)]
	c.psi_r = [0.92, 1.0, 1.08][int(setup.psi_r)]
	c.brake_bias = [0.54, 0.56, 0.58, 0.60, 0.62][int(setup.bias)]
	c.gear_scale = [1.08, 1.0, 0.93][int(setup.gearing)]


const SETUPS_DIR := "user://setups"


## Saved setup sheets for a track: name -> setup dictionary.
func setup_sheets(track_idx: int) -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(SETUPS_DIR + "/track_%d.cfg" % track_idx) != OK:
		return {}
	var out := {}
	for k in cf.get_section_keys("setups") if cf.has_section("setups") else []:
		out[k] = cf.get_value("setups", k)
	return out


func save_setup_sheet(track_idx: int, sheet_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(SETUPS_DIR)
	var cf := ConfigFile.new()
	cf.load(SETUPS_DIR + "/track_%d.cfg" % track_idx)
	cf.set_value("setups", sheet_name, setup.duplicate())
	cf.save(SETUPS_DIR + "/track_%d.cfg" % track_idx)


func load_setup(d: Dictionary) -> void:
	for k in setup:
		if d.has(k):
			setup[k] = int(d[k])
	save_settings()


## A setup as a short code you can paste to a friend ("ST1:..."), and back.
func setup_code() -> String:
	return "ST1:" + Marshalls.utf8_to_base64(JSON.stringify(setup))


func setup_from_code(code: String) -> bool:
	code = code.strip_edges()
	if not code.begins_with("ST1:"):
		return false
	var parsed = JSON.parse_string(Marshalls.base64_to_utf8(code.substr(4)))
	if not (parsed is Dictionary):
		return false
	load_setup(parsed)
	return true


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


## Season mode and the career each have their own season (schedule, points, the
## car in it), in their own file: `season` is whichever one is in use. Before
## they were split, a Season in one car would take over the career's season, and
## the career's standings and results showed the other car.
const CAREER_SEASON_PATH := "user://career_season.cfg"
var _season_career := false


func _season_path() -> String:
	return CAREER_SEASON_PATH if _season_career else SEASON_PATH


## Switch to the career's season (true) or Season mode's (false).
func use_season(career_season: bool) -> void:
	if career_season == _season_career:
		return
	_season_career = career_season
	load_season()


func load_season() -> void:
	season = {}
	var cf := ConfigFile.new()
	if cf.load(_season_path()) == OK:
		season = cf.get_value("season", "data", {})


## Saves from before the split kept the career's season in season.cfg: move it.
func _split_seasons() -> void:
	var cf := ConfigFile.new()
	if cf.load(SEASON_PATH) != OK:
		return
	var s: Dictionary = cf.get_value("season", "data", {})
	if not s.get("career", false):
		return
	if not FileAccess.file_exists(CAREER_SEASON_PATH):
		var out := ConfigFile.new()
		out.set_value("season", "data", s)
		out.save(CAREER_SEASON_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SEASON_PATH))


func save_season() -> void:
	var cf := ConfigFile.new()
	cf.set_value("season", "data", season)
	cf.save(_season_path())
	save_changed.emit()


func clear_season() -> void:
	season = {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_season_path()))


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
	var sponsors := ["PEAK AUTO PARTS", "RIVER BANK", "DIXIE DOGS", "IRONHORSE TRUCKS", "COOL BREEZE HVAC", "BLUEGRASS INSURANCE", "SPARK PLUG CO", "GULF COAST SEAFOOD", "HIGHWAY LUBE", "LONGHORN JERKY", "SUMMIT ROOFING", "PIONEER SEED", "RAPID FREIGHT", "COASTAL CREDIT", "ACE-HIGH HARDWARE", "MOONSHINE ENERGY", "TITAN TOOLS", "GOLD STAR PIZZA", "CLEARVIEW GLASS", "BIG SKY BOOTS", "NORTHSTAR CABLE", "VELOCITY SODA", "FARMHAND FEED", "SUNRISE PANCAKES", "BRAVO BATTERIES", "TRAILBLAZER RV", "HARBOR PAINT", "OLD TOWN CHILI"]
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


## Effective quality level 1..4 (LOW..ULTRA).
func quality_level() -> int:
	return auto_quality if quality == 0 else quality


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
		"livery":
			# The body mesh carries the livery in its vertex colours.
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = modern
			if modern:
				m.metallic = 0.25
				m.roughness = 0.3
				m.clearcoat_enabled = true
				m.clearcoat = 1.0
				m.clearcoat_roughness = 0.05
			else:
				m.roughness = 0.4
				m.metallic_specular = 0.7
		"carbon":
			m.roughness = 0.45 if modern else 0.6
			m.metallic = 0.1 if modern else 0.0
		"wheel":
			m.metallic = 0.6 if modern else 0.2
			m.roughness = 0.35
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
					var sc: float = 1.0 / PHOTO_TILE[kind] if _photo(kind) else {"asphalt": 0.35, "grass": 0.12, "concrete": 0.25}[kind]
					m.uv1_scale = Vector3(sc, sc, sc)
					m.albedo_texture = texture(kind, false)
					m.normal_enabled = true
					m.normal_texture = texture(kind, true)
					m.normal_scale = {"asphalt": 0.9, "grass": 0.6, "concrete": 0.4}[kind]
					m.albedo_color = Color(1.12, 1.12, 1.12) * base
					if kind == "asphalt":
						# Weathered race asphalt reflects about an eighth of the light.
						m.albedo_color = Color(1.75, 1.75, 1.72)
						m.uv1_scale = Vector3.ONE * (1.0 / PHOTO_TILE.asphalt if _photo("asphalt") else 0.33)
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
		"seats":
			# 1999: the seat rows are the crowd. Modern: plain aluminium bleachers
			# (the fans are separate models).
			m.vertex_color_use_as_albedo = not modern
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			if modern:
				m.albedo_color = Color(0.5, 0.52, 0.56)
				m.metallic = 0.5
				m.roughness = 0.5
			else:
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"tree", "crowd":
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = modern
			m.roughness = 1.0 if kind == "tree" else 0.85
			m.cull_mode = BaseMaterial3D.CULL_DISABLED if kind == "tree" else BaseMaterial3D.CULL_BACK
		"fence":
			# Chain link: a tiling wire pattern, see-through, fading to a haze with distance.
			m.albedo_texture = chain_link_texture()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.metallic = 0.6 if modern else 0.0
			m.roughness = 0.5
		"ground":
			if modern:
				m.roughness = 0.95
				m.uv1_triplanar = true
				m.uv1_world_triplanar = true
				m.uv1_scale = Vector3.ONE * (0.12 if _photo("grass") else 0.05)
				m.albedo_texture = texture("grass", false)
				m.normal_enabled = true
				m.normal_texture = texture("grass", true)
				m.normal_scale = 0.5
				m.albedo_color = base.darkened(0.3).lerp(Color(0.3, 0.3, 0.2), 0.3)
		"water":
			m.metallic_specular = 1.0
			m.roughness = 0.05 if modern else 0.1
			m.metallic = 0.3 if modern else 0.0


## Chain-link fence pattern: two sets of diagonal wires on a transparent background.
func chain_link_texture() -> Texture2D:
	if _tex.has("chain"):
		return _tex["chain"]
	var sz := 64
	var img := Image.create_empty(sz, sz, false, Image.FORMAT_RGBA8)
	for y in sz:
		for x in sz:
			var a := posmod(x + y, sz / 4)
			var b := posmod(x - y, sz / 4)
			var da: int = min(a, sz / 4 - a)
			var db: int = min(b, sz / 4 - b)
			var wire: float = max(clamp(1.6 - da, 0.0, 1.0), clamp(1.6 - db, 0.0, 1.0))
			img.set_pixel(x, y, Color(0.8, 0.82, 0.85, wire))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex["chain"] = t
	return t


## Procedural, tileable surface textures (shared, generated once).
func texture(kind: String, normal: bool) -> Texture2D:
	var key := kind + ("_n" if normal else "")
	if _tex.has(key):
		return _tex[key]
	# Photographed surfaces (CC0, assets/textures/CREDITS.md) for the modern look.
	var photo := "res://assets/textures/%s_%s.jpg" % [kind, "normal" if normal else "albedo"]
	if modern and PHOTO_TILE.has(kind) and ResourceLoader.exists(photo):
		_tex[key] = load(photo)
		return _tex[key]
	if kind == "asphalt" and modern:
		_make_asphalt()
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


func _photo(kind: String) -> bool:
	return modern and PHOTO_TILE.has(kind) and ResourceLoader.exists("res://assets/textures/%s_albedo.jpg" % kind)


## Race-track asphalt, close up: grey stone aggregate in dark binder, the odd
## lighter stone, fine grit, and a few sealed cracks; plus a bump map from the
## same heights so the stones catch the light. Tileable; about 3 m across.
func _make_asphalt() -> void:
	var sz := 512 if OS.has_feature("web") else 1024
	var rng := RandomNumberGenerator.new()
	rng.seed = 1999
	var height := PackedFloat32Array()
	height.resize(sz * sz)
	var col := PackedFloat32Array() # brightness
	col.resize(sz * sz)
	# Binder: dark, with gentle blotches (oil, patching, age).
	var blotch := FastNoiseLite.new()
	blotch.seed = 7
	blotch.noise_type = FastNoiseLite.TYPE_SIMPLEX
	blotch.frequency = 3.0 / sz
	blotch.fractal_octaves = 3
	var grit := FastNoiseLite.new()
	grit.seed = 11
	grit.noise_type = FastNoiseLite.TYPE_VALUE
	grit.frequency = 0.9
	for y in sz:
		for x in sz:
			# Seamless: sample the noise on a torus.
			var u := TAU * x / sz
			var v := TAU * y / sz
			var r := sz / TAU
			var b := blotch.get_noise_3d(cos(u) * r, sin(u) * r, cos(v) * r + sin(v) * 7.0)
			var g := grit.get_noise_2d(x, y)
			col[y * sz + x] = 0.62 + b * 0.06 + g * 0.05
			height[y * sz + x] = g * 0.15
	# Aggregate: thousands of small stones, a mix of greys, a few pale ones.
	var stones := sz * sz / 55
	for i in stones:
		var cx := rng.randi_range(0, sz - 1)
		var cy := rng.randi_range(0, sz - 1)
		var rad := rng.randf_range(0.8, 2.6) * sz / 1024.0 * 1.6
		var tone := rng.randf_range(0.72, 1.0)
		if rng.randf() < 0.03:
			tone = rng.randf_range(0.98, 1.12) # pale quartz / limestone
		var ri := int(ceil(rad))
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var dd := sqrt(dx * dx + dy * dy) / rad
				if dd > 1.0:
					continue
				var k := posmod(cy + dy, sz) * sz + posmod(cx + dx, sz)
				var dome := sqrt(1.0 - dd * dd)
				if dome * 0.6 + 0.2 > height[k]:
					height[k] = dome * 0.6 + 0.2
					col[k] = tone * (0.85 + 0.15 * dome)
	# Sealed cracks: thin, dark, wandering lines.
	for c in 5:
		var px := rng.randf() * sz
		var py := rng.randf() * sz
		var ang := rng.randf() * TAU
		for st in int(sz * rng.randf_range(0.3, 0.8)):
			ang += rng.randf_range(-0.25, 0.25)
			px += cos(ang)
			py += sin(ang)
			for w in 2:
				var k := posmod(int(py) + w, sz) * sz + posmod(int(px), sz)
				col[k] = 0.35
				height[k] = -0.2
	var img := Image.create_empty(sz, sz, false, Image.FORMAT_RGB8)
	var nimg := Image.create_empty(sz, sz, false, Image.FORMAT_RGB8)
	for y in sz:
		for x in sz:
			var c: float = clamp(col[y * sz + x], 0.0, 1.0)
			img.set_pixel(x, y, Color(c, c, c * 0.985))
			var hx: float = height[y * sz + posmod(x + 1, sz)] - height[y * sz + posmod(x - 1, sz)]
			var hy: float = height[posmod(y + 1, sz) * sz + x] - height[posmod(y - 1, sz) * sz + x]
			var nrm := Vector3(-hx * 2.5, -hy * 2.5, 1.0).normalized()
			nimg.set_pixel(x, y, Color(nrm.x * 0.5 + 0.5, nrm.y * 0.5 + 0.5, nrm.z * 0.5 + 0.5))
	img.generate_mipmaps()
	nimg.generate_mipmaps()
	_tex["asphalt"] = ImageTexture.create_from_image(img)
	_tex["asphalt_n"] = ImageTexture.create_from_image(nimg)


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
		"replay": [KEY_R, "btn:%d" % JOY_BUTTON_RIGHT_STICK],
		"pit": [KEY_TAB, "btn:%d" % JOY_BUTTON_X],
		"pit_option": [KEY_O, "btn:%d" % JOY_BUTTON_DPAD_UP],
		"shift_up": [KEY_E, "btn:%d" % JOY_BUTTON_RIGHT_SHOULDER],
		"shift_down": [KEY_Q, "btn:%d" % JOY_BUTTON_LEFT_SHOULDER],
		"pause": [KEY_ESCAPE, KEY_P, "btn:%d" % JOY_BUTTON_BACK],
		"quit_race": [KEY_Q],
		"p2_accelerate": [KEY_I, "p2btn:%d" % JOY_BUTTON_A, "p2axis:%d+" % JOY_AXIS_TRIGGER_RIGHT],
		"p2_brake": [KEY_K, "p2btn:%d" % JOY_BUTTON_B, "p2axis:%d+" % JOY_AXIS_TRIGGER_LEFT],
		"p2_left": [KEY_J, "p2btn:%d" % JOY_BUTTON_DPAD_LEFT, "p2axis:%d-" % JOY_AXIS_LEFT_X],
		"p2_right": [KEY_L, "p2btn:%d" % JOY_BUTTON_DPAD_RIGHT, "p2axis:%d+" % JOY_AXIS_LEFT_X],
		"p2_pit": [KEY_U, "p2btn:%d" % JOY_BUTTON_X],
		"toggle_scanlines": [KEY_F2],
		"telemetry": [KEY_T, "btn:%d" % JOY_BUTTON_LEFT_STICK],
		"highlights": [KEY_H, "btn:%d" % JOY_BUTTON_MISC1],
		"photo": [KEY_F, "btn:%d" % JOY_BUTTON_TOUCHPAD],
		"clip": [KEY_F9],
		"toggle_graphics": [KEY_F3],
		"toggle_fullscreen": [KEY_F11],
	}
	for action in binds:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		for b in binds[action]:
			var ev: InputEvent
			var dev := -1
			if b is String and b.begins_with("p2"):
				dev = 1 # second gamepad
				b = b.substr(2)
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
			ev.device = dev
			InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_graphics"):
		toggle_graphics()
	if event.is_action_pressed("toggle_fullscreen"):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


## In split screen, player 1's gamepad bindings listen to the first pad only.
func set_two_player_input(on: bool) -> void:
	for action in ["accelerate", "brake", "steer_left", "steer_right", "pit", "pit_option", "shift_up", "shift_down", "camera"]:
		if not InputMap.has_action(action):
			continue
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				ev.device = 0 if on else -1


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
	save_changed.emit()
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


## Lays a control out as the 640x480 design frame, centred in the window (the
## window can be wider or taller in the Modern look). Every frame is then kept
## inside the part of the screen that's actually visible (clear of a notch,
## rounded corners and the home bar), shrinking it if it has to. `avoid_touch`
## frames (the menus) also keep clear of the on-screen D-pad and A/B buttons.
func center_frame(c: Control, avoid_touch := false) -> Control:
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.offset_left = -320.0
	c.offset_right = 320.0
	c.offset_top = -240.0
	c.offset_bottom = 240.0
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frames.append([c, avoid_touch])
	return c


## --- Fitting the screen

const FRAME := Vector2(640, 480)
## Menus rarely draw in the outer edge of their frame, so an on-screen button may
## sit over this much of it (in frame units).
const FRAME_EDGE := 24.0
## A phone in landscape shows about 0.92 CSS pixels per 640x480 unit; the touch
## controls are sized for that and scaled down on bigger screens (tablets,
## touchscreen laptops) so they stay thumb-sized rather than huge.
const TOUCH_CSS_PER_UNIT := 0.92

var frames: Array = [] # [Control, avoid_touch]
## The screen edges a notch, rounded corners or the home bar cover, as fractions of
## the window: left, top, right, bottom. The web page measures them (CSS
## safe-area insets); ST_SAFE="l,t,r,b" sets them for tests.
var safe_frac := [0.0, 0.0, 0.0, 0.0]
## Rectangles (canvas units) the on-screen touch buttons take up in the menus.
var touch_reserve: Array = []
## The on-screen touch controls are showing (keyboard hints can hide).
var touch_active := false
var _css_per_unit := 0.0
var _screen_poll := 0.0
var _js_win = null


func _process(delta: float) -> void:
	_screen_poll -= delta
	if _screen_poll <= 0.0:
		_screen_poll = 0.25
		_read_screen()
	var i := frames.size() - 1
	while i >= 0:
		var c = frames[i][0]
		if not is_instance_valid(c):
			frames.remove_at(i)
		elif c.is_inside_tree():
			_fit_frame(c, frames[i][1])
		i -= 1


func _read_screen() -> void:
	var f := [0.0, 0.0, 0.0, 0.0]
	var cpu := 0.0
	var env := OS.get_environment("ST_SAFE")
	if env != "":
		var parts := env.split(",")
		for k in min(4, parts.size()):
			f[k] = clamp(float(parts[k]), 0.0, 0.4)
	elif OS.has_feature("web"):
		if _js_win == null:
			_js_win = JavaScriptBridge.get_interface("window")
		if _js_win:
			var a = _js_win.stSafe
			if a != null:
				for k in 4:
					var v = a[k]
					f[k] = clamp(float(v), 0.0, 0.4) if v != null else 0.0
			var dpr = _js_win.devicePixelRatio
			var vis := get_viewport().get_visible_rect().size
			if dpr != null and float(dpr) > 0.0 and vis.y > 0.0:
				cpu = float(get_window().size.y) / float(dpr) / vis.y
	var env_cpu := OS.get_environment("ST_CSS_PER_UNIT")
	if env_cpu != "":
		cpu = float(env_cpu)
	safe_frac = f
	_css_per_unit = cpu


## The part of `vp` (in its canvas units) that's clear of notches, rounded corners
## and the home bar.
func safe_rect(vp: Viewport) -> Rect2:
	var vis := vp.get_visible_rect()
	if not (vp is Window) or safe_frac == [0.0, 0.0, 0.0, 0.0]:
		return vis
	var ws := Vector2((vp as Window).size)
	var win_r := Rect2(safe_frac[0] * ws.x, safe_frac[1] * ws.y, ws.x * (1.0 - safe_frac[0] - safe_frac[2]), ws.y * (1.0 - safe_frac[1] - safe_frac[3]))
	var r: Rect2 = vp.get_final_transform().affine_inverse() * win_r
	r = r.intersection(vis)
	return r if r.has_area() else vis


## A phone or tablet (a touch screen is the main way in). iPad Safari reports
## itself as a Mac, so the web page's own check (touch points) is asked too.
func touch_device() -> bool:
	if OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile"):
		return true
	if OS.get_environment("ST_TOUCH") == "1":
		return true
	if OS.has_feature("web"):
		var w = JavaScriptBridge.get_interface("window")
		if w and w.stTouch == true:
			return true
	return false


## How big to draw the touch controls (1 = sized for a phone): smaller on
## screens with more room, so they stay about thumb-sized.
func touch_scale() -> float:
	if _css_per_unit <= 0.0:
		return 1.0
	return clamp(TOUCH_CSS_PER_UNIT / _css_per_unit, 0.6, 1.0)


func _fit_frame(c: Control, avoid_touch: bool) -> void:
	var sr := safe_rect(c.get_viewport())
	var s: float = min(1.0, sr.size.x / FRAME.x, sr.size.y / FRAME.y)
	var top := false
	if avoid_touch and not touch_reserve.is_empty() and _frame_hits(sr, s, false):
		# Either shrink it to fit between the buttons, or put it above them (its
		# bottom edge may overlap): whichever leaves the menu bigger.
		var side := 0.0
		var band := 0.0
		for r: Rect2 in touch_reserve:
			if r.get_center().x < sr.get_center().x:
				side = max(side, r.end.x - sr.position.x)
			else:
				side = max(side, sr.end.x - r.position.x)
			band = max(band, sr.end.y - r.position.y)
		var s_between: float = min(s, (sr.size.x - 2.0 * side) / (FRAME.x - 2.0 * FRAME_EDGE))
		var s_above: float = min(1.0, sr.size.x / FRAME.x, (sr.size.y - band) / (FRAME.y - FRAME_EDGE))
		if s_above > s_between:
			s = s_above
			top = true
		else:
			s = s_between
		s = max(s, 0.3)
	c.pivot_offset = Vector2.ZERO
	c.scale = Vector2(s, s)
	var y: float = sr.position.y if top else sr.get_center().y - FRAME.y * 0.5 * s
	c.position = Vector2(sr.get_center().x - FRAME.x * 0.5 * s, y)


func _frame_hits(sr: Rect2, s: float, top: bool) -> bool:
	var y: float = sr.position.y if top else sr.get_center().y - FRAME.y * 0.5 * s
	var fr := Rect2(sr.get_center().x - FRAME.x * 0.5 * s, y, FRAME.x * s, FRAME.y * s).grow(-FRAME_EDGE * s)
	for r: Rect2 in touch_reserve:
		if fr.intersects(r):
			return true
	return false


func make_label(text: String, size: int, color := Color.WHITE, outline := 6) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = arcade_font
	# LARGE TEXT: the small print grows (a 12 becomes 16); titles of 24 and up stay.
	ls.font_size = size if int(settings.get("big_text", 0)) == 0 else int(round(size * (1.0 + max(24 - size, 0) / 36.0)))
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = Color(0, 0, 0)
	ls.shadow_size = 0
	ls.shadow_color = Color(0, 0, 0, 0.6)
	ls.shadow_offset = Vector2(3, 3)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
