#!/usr/bin/env python3
"""Builds scripts/replica_tracks.gd: layouts modelled on every track on the
2026 NASCAR Cup calendar (the 27 points-paying venues, the Clash's quarter-mile
and the All-Star race's mile), with fictional names.

Each layout is a list of straights and arcs (the game's "segments" format). The
ovals are drawn symmetric and closed exactly by solving for the back straight;
the road courses are closed by two straights the game solves (like the
original road course). Then the whole shape is scaled to the real length.
Road courses that really run clockwise are drawn mirrored, as the game races
anticlockwise.

    python3 tools/make_replicas.py        (rewrites scripts/replica_tracks.gd)
"""
import math
import os
import sys

# PLOT=dir: draw every layout to dir/<short>.png and report problems instead of
# stopping at the first one.
PLOT = os.environ.get("PLOT", "")
PROBLEMS = []


def check(ok, what):
    if not ok:
        if PLOT:
            PROBLEMS.append(what)
        else:
            raise AssertionError(what)

MILE = 1609.344


def chord(h, a, r):
    """The displacement of an arc turning by a (radians) at radius r from heading h,
    the same formula as track.gd."""
    sg = 1.0 if a >= 0 else -1.0
    return (math.sin(h + a) - math.sin(h)) * r * sg, (-math.cos(h + a) + math.cos(h)) * r * sg


def walk(segs, lens):
    """Total displacement of a closed walk, with lens for named straights."""
    h = 0.0
    x = y = 0.0
    for sg in segs:
        if "s" in sg:
            L = lens[sg["s"]] if isinstance(sg["s"], str) else sg["s"]
            x += math.cos(h) * L
            y += math.sin(h) * L
        else:
            a = math.radians(sg["a"])
            dx, dy = chord(h, a, sg["r"])
            x += dx
            y += dy
            h += a
    return x, y


def heading_at(segs, name):
    h = 0.0
    for sg in segs:
        if "s" in sg and sg["s"] == name:
            return h
        if "a" in sg:
            h += math.radians(sg["a"])
    raise KeyError(name)


def solve(segs):
    """Solves the named straights so the loop closes. One name: least squares
    along its direction (symmetric ovals). Two: exact (road courses)."""
    names = [sg["s"] for sg in segs if "s" in sg and isinstance(sg["s"], str)]
    if not names:
        return {}
    zero = {n: 0.0 for n in names}
    x0, y0 = walk(segs, zero)
    if len(names) == 1:
        h = heading_at(segs, names[0])
        u = (math.cos(h), math.sin(h))
        L = -(x0 * u[0] + y0 * u[1])
        res = math.hypot(x0 + L * u[0], y0 + L * u[1])
        check(res < 0.05, "not closed: %.3f" % res)
        return {names[0]: L}
    n1, n2 = names
    h1, h2 = heading_at(segs, n1), heading_at(segs, n2)
    u1 = (math.cos(h1), math.sin(h1))
    u2 = (math.cos(h2), math.sin(h2))
    det = u1[0] * u2[1] - u1[1] * u2[0]
    rx, ry = -x0, -y0
    return {n1: (rx * u2[1] - ry * u2[0]) / det, n2: (u1[0] * ry - u1[1] * rx) / det}


def length(segs, lens):
    t = 0.0
    for sg in segs:
        if "s" in sg:
            t += lens[sg["s"]] if isinstance(sg["s"], str) else sg["s"]
        else:
            t += sg["r"] * abs(math.radians(sg["a"]))
    return t


def finish(segs, miles, keep_autos):
    """Closes the loop, scales it to the real length; returns (segments, front length)."""
    total_turn = sum(sg.get("a", 0.0) for sg in segs)
    check(abs(total_turn - 360.0) < 1e-6, "turns add up to %.2f" % total_turn)
    lens = solve(segs)
    for n, v in lens.items():
        check(v > 15.0, "%.2f mi: straight %s came out %.1f" % (miles, n, v))
    k = miles * MILE / length(segs, lens)
    out = []
    for sg in segs:
        if "s" in sg:
            if isinstance(sg["s"], str):
                out.append({"s": sg["s"]} if keep_autos else {"s": round(lens[sg["s"]] * k, 3)})
            else:
                out.append({"s": round(sg["s"] * k, 3)})
        else:
            d = {"r": round(sg["r"] * k, 3), "a": sg["a"]}
            if "b" in sg:
                d["b"] = sg["b"]
            out.append(d)
    if keep_autos:
        # Check what the game's solver will make of the scaled layout.
        lens2 = solve(out)
        for n, v in lens2.items():
            check(v > 20.0, "%.2f mi: auto %s %.1f" % (miles, n, v))
    return out, k


def oval(miles, straight, radius, bank):
    """A plain oval: two straights, two 180 degree turns."""
    segs = [{"s": straight}, {"r": radius, "a": 180.0, "b": bank}, {"s": "back"}, {"r": radius, "a": 180.0, "b": bank}]
    out, k = finish(segs, miles, False)
    return out, out[0]["s"]


def kinked(miles, center, kink_r, kink_deg, side, radius, bank, kink_bank):
    """Tri-oval (center ~0), quad-oval (center > 0) or D-oval (side 0, big kink
    radius): the front stretch bends outward at the kinks; the back is solved."""
    half = kink_deg / 2.0
    turn = 180.0 - half
    segs = [{"s": center}, {"r": kink_r, "a": half, "b": kink_bank}, {"s": side}, {"r": radius, "a": turn, "b": bank},
            {"s": "back"}, {"r": radius, "a": turn, "b": bank}, {"s": side}, {"r": kink_r, "a": half, "b": kink_bank}]
    segs = [sg for sg in segs if not ("s" in sg and not isinstance(sg["s"], str) and sg["s"] <= 0.0)]
    out, k = finish(segs, miles, False)
    # The front stretch: the middle, both kinks and both side straights.
    front = out[0]["s"]
    for sg in out:
        if sg is out[0]:
            continue
        if "r" in sg and abs(sg["a"]) < 90.0:
            front += sg["r"] * math.radians(abs(sg["a"]))
    front += 2.0 * side * k
    return out, front


def course(miles, segs, last_turn_index=-1):
    """A road course or an odd oval: the turn at last_turn_index is set so the
    turns add up to one lap anticlockwise; two named straights close it."""
    others = sum(sg.get("a", 0.0) for i, sg in enumerate(segs) if "a" in sg and i != (last_turn_index % len(segs)))
    segs[last_turn_index]["a"] = round(360.0 - others, 4)
    out, k = finish(segs, miles, True)
    return out, None


def corners(miles, pts, bank=2.0, banks=None):
    """A road course from its corners: [(x, y, radius), ...] in metres, in the
    order you drive them, starting with the corner at the END of the main
    straight (so the main straight is the edge from the last corner to the
    first). Each corner is rounded with an arc of its radius; the edges between
    become straights. Drawn clockwise, the course is mirrored (the game races
    anticlockwise). Returns closed segments scaled to the real length."""
    n = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    if area < 0:
        pts = [(-x, y, r) for (x, y, r) in pts]  # mirror: clockwise in real life
    turns = []
    for i in range(n):
        x0, y0, _ = pts[i - 1]
        x1, y1, r = pts[i]
        x2, y2, _ = pts[(i + 1) % n]
        h_in = math.atan2(y1 - y0, x1 - x0)
        h_out = math.atan2(y2 - y1, x2 - x1)
        a = (h_out - h_in + math.pi) % (2 * math.pi) - math.pi
        turns.append(a)
    total = math.degrees(sum(turns))
    check(abs(total - 360.0) < 0.01, "corners turn %.1f degrees" % total)
    # Straights: edge length less each end's tangent.
    segs_body = []
    for i in range(n):
        x1, y1, r1 = pts[i]
        x2, y2, r2 = pts[(i + 1) % n]
        edge = math.hypot(x2 - x1, y2 - y1)
        t1 = r1 * math.tan(abs(turns[i]) / 2.0)
        t2 = r2 * math.tan(abs(turns[(i + 1) % n]) / 2.0)
        L = edge - t1 - t2
        check(L > 8.0, "%.2f mi: the straight after corner %d is %.1f m" % (miles, i + 1, L))
        segs_body.append((i, L))
    # Main straight first (the edge from the last corner to corner 1), then
    # corner 1, straight, corner 2 ...
    main_L = segs_body[n - 1][1]
    segs = [{"s": max(main_L, 1.0)}]
    for i in range(n):
        b = banks[i] if banks else bank
        segs.append({"r": float(pts[i][2]), "a": math.degrees(turns[i]), "b": b})
        if i < n - 1:
            segs.append({"s": max(segs_body[i][1], 1.0)})
    # Rounding: make the turns add to exactly 360.
    err = 360.0 - sum(sg.get("a", 0.0) for sg in segs)
    segs[-1]["a"] += err
    total_len = length(segs, {})
    k = miles * MILE / total_len
    out = []
    for sg in segs:
        if "s" in sg:
            out.append({"s": round(sg["s"] * k, 3)})
        else:
            out.append({"r": round(sg["r"] * k, 3), "a": round(sg["a"], 4), "b": sg["b"]})
    x, y = walk(out, {})
    check(math.hypot(x, y) < 1.0, "%.2f mi: corners don't close (%.2f m)" % (miles, math.hypot(x, y)))
    return out, None


def egg(miles, r1, a1, r2, a2, bank1, bank2, extra=None):
    segs = [{"s": "auto1"}, {"r": r1, "a": a1, "b": bank1}, {"s": "auto2"}, {"r": r2, "a": a2, "b": bank2}]
    if extra:
        segs = extra
    out, k = finish(segs, miles, True)
    return out, None


# --- the tracks --------------------------------------------------------------------------
# Common looks.
SUN = {"sky_top": "Color(0.25, 0.45, 0.82)", "sky_horizon": "Color(0.82, 0.86, 0.94)", "grass": "Color(0.26, 0.52, 0.2)", "fog": "Color(0.78, 0.83, 0.9)"}
DUSK = {"sky_top": "Color(0.3, 0.32, 0.62)", "sky_horizon": "Color(1.0, 0.66, 0.48)", "grass": "Color(0.3, 0.48, 0.22)", "fog": "Color(0.95, 0.72, 0.6)"}
NIGHT = {"sky_top": "Color(0.04, 0.05, 0.18)", "sky_horizon": "Color(0.22, 0.18, 0.38)", "grass": "Color(0.15, 0.34, 0.14)", "fog": "Color(0.12, 0.1, 0.22)"}
DESERT = {"sky_top": "Color(0.2, 0.42, 0.86)", "sky_horizon": "Color(0.98, 0.86, 0.66)", "grass": "Color(0.56, 0.46, 0.3)", "fog": "Color(0.95, 0.85, 0.7)"}
COAST = {"sky_top": "Color(0.18, 0.4, 0.8)", "sky_horizon": "Color(0.72, 0.85, 0.95)", "grass": "Color(0.25, 0.56, 0.2)", "fog": "Color(0.7, 0.8, 0.92)"}

SUPER = {"hp": 510, "cda": 0.92, "cla": 2.6, "gear": 0.9, "draft": 1.0, "tow": 3.0, "tow_reach": 2.0, "push": 15.8, "push_reach": 2.5, "pack_gap": 0.1}
INTER = {"hp": 670, "cda": 1.1, "cla": 2.8, "draft": 0.35}
SHORT = {"hp": 750, "cda": 1.2, "cla": 1.8, "draft": 0.15}
ROAD = {"hp": 750, "cda": 1.2, "cla": 1.8, "draft": 0.15, "road": True}

T = []


def add(name, short, real, kind, level, layout, miles, full_laps, look, pkg, **kw):
    segs, front = layout
    d = {"name": name, "short": short, "kind": kind, "level": level, "real": real, "miles": miles, "segments": segs,
         "full_laps": full_laps, "look": look, "pkg": pkg}
    if front:
        d["front"] = round(front, 2)
    d.update(kw)
    T.append(d)


# 1 Daytona: 2.5 mi tri-oval, 31 degree turns, 18 at the tri-oval.
add("SURFSIDE INT'L SPEEDWAY", "SURFSIDE", "Daytona International Speedway", "2.5 MILE TRI-OVAL", "BEGINNER",
    kinked(2.5, 4, 600, 36, 340, 300, 31.0, 18.0), 2.5, 200, COAST, SUPER, width=20.0, apron=9.0, infield=14.0,
    bank_straight=3.0, pit_mph=55, lake=True, sun_elev=58.0, sun_az=35.0)
# 2 Atlanta (EchoPark): 1.54 mi quad-oval reprofiled to 28 degrees, pack racing.
add("PEACHTREE MOTOR SPEEDWAY", "PEACHTREE", "EchoPark Speedway (Atlanta)", "1.54 MILE QUAD-OVAL", "ADVANCED",
    kinked(1.54, 150, 230, 24, 60, 200, 28.0, 5.0), 1.54, 260, SUN, dict(SUPER, push=12.0), width=19.0, apron=8.0, infield=12.0,
    bank_straight=5.0, pit_mph=45, sun_elev=40.0, sun_az=230.0)
# 3 COTA: 2.4 mi (national layout), anticlockwise like the real one.
add("HILL COUNTRY GRAND PRIX", "HILL COUNTRY", "Circuit of the Americas", "2.4 MILE ROAD COURSE", "EXPERT",
    corners(2.4, [(0, 520, 25), (-180, 380, 70), (-300, 420, 45), (-380, 330, 45), (-480, 380, 45), (-560, 280, 60),
                   (-680, 300, 40), (-760, 160, 22), (-650, -700, 25), (-500, -640, 35), (-400, -720, 35), (-280, -660, 35),
                   (-150, -760, 90), (0, -800, 30)]),
    2.4, 95, DESERT, ROAD, width=15.0, apron=3.0, infield=10.0, bank_straight=1.0, pit_mph=45, sun_elev=50.0, sun_az=160.0)
# 4 Phoenix: 1 mi with the backstretch dogleg, flat.
add("SAGUARO RACEWAY", "SAGUARO", "Phoenix Raceway", "1 MILE DOGLEG OVAL", "ADVANCED",
    egg(1.0, 0, 0, 0, 0, 0, 0, [{"s": "auto1"}, {"r": 140.0, "a": 160.0, "b": 11.0}, {"s": "auto2"}, {"r": 260.0, "a": 20.0, "b": 4.0},
                                {"s": 300.0}, {"r": 175.0, "a": 180.0, "b": 9.0}]),
    1.0, 312, DESERT, SHORT, width=16.0, apron=7.0, infield=10.0, bank_straight=3.0, pit_mph=45, sun_elev=60.0, sun_az=200.0)
# 5 Las Vegas: 1.5 mi tri-oval, 20 degrees.
add("NEON VALLEY MOTOR SPEEDWAY", "NEON VALLEY", "Las Vegas Motor Speedway", "1.5 MILE TRI-OVAL", "INTERMEDIATE",
    kinked(1.5, 4, 330, 30, 160, 215, 20.0, 9.0), 1.5, 267, DESERT, INTER, width=19.0, apron=8.0, infield=12.0,
    bank_straight=9.0, pit_mph=45, sun_elev=20.0, sun_az=260.0)
# 6 Darlington: 1.366 mi egg, 25/23 degrees.
add("PEE DEE RACEWAY", "PEE DEE", "Darlington Raceway", "1.366 MILE EGG", "EXPERT",
    egg(1.366, 190.0, 190.0, 150.0, 170.0, 25.0, 23.0), 1.366, 293, DUSK, INTER, width=15.0, apron=6.0, infield=10.0,
    bank_straight=3.0, pit_mph=45, sun_elev=12.0, sun_az=280.0)
# 7 Martinsville: 0.526 mi paperclip, 12 degrees, concrete turns.
add("BLUE RIDGE SPEEDWAY", "BLUE RIDGE", "Martinsville Speedway", "0.526 MILE PAPERCLIP", "EXPERT",
    oval(0.526, 245.0, 56.0, 12.0), 0.526, 400, SUN, dict(SHORT, draft=0.1), width=13.0, apron=6.0, infield=8.0,
    bank_straight=0.0, turn_grip=1.2, pit_mph=30, sun_elev=40.0, sun_az=30.0)
# 8 Bristol: 0.533 mi concrete bowl, 28 degrees, under the lights.
add("THUNDER HOLLOW SPEEDWAY", "THUNDER HOLLOW", "Bristol Motor Speedway", "0.533 MILE CONCRETE BOWL", "EXPERT",
    oval(0.533, 190.0, 77.0, 28.0), 0.533, 500, NIGHT, dict(SHORT, draft=0.2), width=15.0, apron=6.0, infield=8.0,
    bank_straight=8.0, turn_grip=1.08, pit_mph=30, night=True, sun_elev=40.0, sun_az=120.0)
# 9 Kansas: 1.5 mi tri-oval, progressive 17-20.
add("PRAIRIE SPEEDWAY", "PRAIRIE", "Kansas Speedway", "1.5 MILE TRI-OVAL", "INTERMEDIATE",
    kinked(1.5, 4, 360, 28, 170, 220, 19.0, 10.0), 1.5, 267, SUN, INTER, width=19.0, apron=8.0, infield=12.0,
    bank_straight=5.0, pit_mph=45, sun_elev=35.0, sun_az=210.0)
# 10 Talladega: 2.66 mi tri-oval, 33 degrees.
add("COTTON STATE SUPERSPEEDWAY", "COTTON STATE", "Talladega Superspeedway", "2.66 MILE TRI-OVAL", "EXPERT",
    kinked(2.66, 4, 700, 34, 420, 300, 33.0, 16.5), 2.66, 188, SUN, SUPER, width=24.0, apron=10.0, infield=16.0,
    bank_straight=3.0, pit_mph=55, sun_elev=50.0, sun_az=150.0)
# 11 Texas: 1.5 mi quad-oval, 24/20 degrees.
add("LONGHORN MOTOR SPEEDWAY", "LONGHORN", "Texas Motor Speedway", "1.5 MILE QUAD-OVAL", "ADVANCED",
    kinked(1.5, 250, 250, 20, 110, 215, 22.0, 5.0), 1.5, 267, DUSK, INTER, width=18.0, apron=8.0, infield=12.0,
    bank_straight=5.0, pit_mph=45, sun_elev=14.0, sun_az=205.0)
# 12 Watkins Glen: 2.45 mi (drawn mirrored).
add("FINGER LAKES INT'L", "FINGER LAKES", "Watkins Glen International", "2.45 MILE ROAD COURSE", "EXPERT",
    corners(2.45, [(500, 0, 30), (560, -160, 90), (530, -320, 90), (600, -480, 120), (430, -1080, 20), (400, -1130, 20),
                    (380, -1180, 20), (150, -1350, 90), (-300, -700, 40), (-200, 0, 35)]),
    2.45, 90, SUN, ROAD, width=14.0, apron=3.0, infield=10.0, bank_straight=1.0, pit_mph=40, sun_elev=45.0, sun_az=100.0)
# 13 Charlotte: 1.5 mi quad-oval, 24 degrees, 600 miles.
add("QUEEN CITY MOTOR SPEEDWAY", "QUEEN CITY", "Charlotte Motor Speedway", "1.5 MILE QUAD-OVAL", "ADVANCED",
    kinked(1.5, 240, 240, 20, 120, 215, 24.0, 5.0), 1.5, 400, DUSK, INTER, width=19.0, apron=8.0, infield=12.0,
    bank_straight=5.0, pit_mph=45, sun_elev=10.0, sun_az=270.0)
# 14 Nashville Superspeedway: 1.33 mi concrete tri-oval, 14 degrees.
add("MUSIC ROW SUPERSPEEDWAY", "MUSIC ROW", "Nashville Superspeedway", "1.33 MILE CONCRETE TRI-OVAL", "INTERMEDIATE",
    kinked(1.33, 4, 300, 26, 150, 190, 14.0, 9.0), 1.33, 300, DUSK, INTER, width=18.0, apron=8.0, infield=12.0,
    bank_straight=6.0, turn_grip=1.05, pit_mph=45, sun_elev=16.0, sun_az=250.0)
# 15 Michigan: 2 mi D-oval, 18 degrees.
add("IRISH HILLS INT'L SPEEDWAY", "IRISH HILLS", "Michigan International Speedway", "2 MILE D-OVAL", "INTERMEDIATE",
    kinked(2.0, 4, 650, 24, 260, 330, 18.0, 12.0), 2.0, 200, SUN, dict(INTER, draft=0.5), width=20.0, apron=9.0, infield=14.0,
    bank_straight=5.0, pit_mph=55, lake=True, sun_elev=35.0, sun_az=250.0)
# 16 Pocono: 2.5 mi triangle, 14/8/6 degrees.
add("LAUREL MOUNTAIN RACEWAY", "LAUREL MTN", "Pocono Raceway", "2.5 MILE TRIANGLE", "EXPERT",
    egg(2.5, 0, 0, 0, 0, 0, 0, [{"s": "auto1"}, {"r": 270.0, "a": 125.0, "b": 14.0}, {"s": 850.0}, {"r": 190.0, "a": 100.0, "b": 8.0},
                                {"s": "auto2"}, {"r": 230.0, "a": 135.0, "b": 6.0}]),
    2.5, 160, SUN, dict(INTER, draft=0.4), width=18.0, apron=8.0, infield=12.0, bank_straight=2.0, pit_mph=55, sun_elev=40.0, sun_az=300.0)
# 17 San Diego: 3.4 mi street course on a naval air station: long runway straights, 19 turns.
add("HARBOR BASE STREET CIRCUIT", "HARBOR BASE", "Naval Base Coronado street course (San Diego)", "3.4 MILE STREET COURSE", "EXPERT",
    corners(3.4, [(950, 0, 25), (950, 400, 25), (700, 420, 25), (700, 700, 30), (-400, 700, 60), (-500, 500, 22),
                   (-300, 450, 16), (-260, 410, 16), (-220, 450, 16), (100, 450, 25), (100, 250, 25), (-150, 250, 25),
                   (-200, 0, 25)], bank=1.0),
    3.4, 75, COAST, ROAD, width=13.0, apron=1.5, infield=8.0, bank_straight=0.5, pit_mph=40, lake=True, sun_elev=55.0, sun_az=200.0)
# 18 Sonoma: 1.99 mi (drawn mirrored), hilly, carousel and hairpin.
add("WINE COUNTRY RACEWAY", "WINE COUNTRY", "Sonoma Raceway", "1.99 MILE ROAD COURSE", "EXPERT",
    corners(1.99, [(40, 300, 70), (150, 380, 40), (260, 300, 40), (380, 360, 30), (520, 250, 30), (450, -50, 60),
                    (300, -200, 55), (420, -330, 25), (300, -420, 35), (200, -330, 35), (100, -420, 35), (0, -360, 18)]),
    1.99, 110, DESERT, ROAD, width=14.0, apron=3.0, infield=10.0, bank_straight=1.0, pit_mph=40, sun_elev=50.0, sun_az=140.0)
# 19 Chicagoland: 1.5 mi D-oval, 18 degrees.
add("LAKESHORE SPEEDWAY", "LAKESHORE", "Chicagoland Speedway", "1.5 MILE D-OVAL", "INTERMEDIATE",
    kinked(1.5, 4, 520, 26, 100, 220, 18.0, 11.0), 1.5, 267, SUN, INTER, width=19.0, apron=8.0, infield=12.0,
    bank_straight=5.0, pit_mph=45, lake=True, sun_elev=40.0, sun_az=230.0)
# 20 North Wilkesboro: 0.625 mi, 14 degrees, old worn asphalt.
add("MOONSHINE SPEEDWAY", "MOONSHINE", "North Wilkesboro Speedway", "0.625 MILE OVAL", "EXPERT",
    oval(0.625, 230.0, 82.0, 14.0), 0.625, 400, DUSK, dict(SHORT, draft=0.12), width=14.0, apron=6.0, infield=8.0,
    bank_straight=3.0, turn_grip=0.95, pit_mph=30, sun_elev=10.0, sun_az=260.0)
# 21 Indianapolis: 2.5 mi rectangle, four 9 degree turns, short chutes.
add("CROSSROADS MOTOR SPEEDWAY", "CROSSROADS", "Indianapolis Motor Speedway", "2.5 MILE RECTANGLE", "EXPERT",
    egg(2.5, 0, 0, 0, 0, 0, 0, [{"s": 1006.0}, {"r": 255.0, "a": 90.0, "b": 9.0}, {"s": "auto1"}, {"r": 255.0, "a": 90.0, "b": 9.0},
                                {"s": "auto2"}, {"r": 255.0, "a": 90.0, "b": 9.0}, {"s": 201.0}, {"r": 255.0, "a": 90.0, "b": 9.0}]),
    2.5, 160, SUN, dict(INTER, draft=0.5), width=17.0, apron=6.0, infield=12.0, bank_straight=0.0, pit_mph=55, sun_elev=55.0, sun_az=180.0)
# 22 Iowa: 0.875 mi, progressive 12-14 degrees, slight D.
add("CORN BELT SPEEDWAY", "CORN BELT", "Iowa Speedway", "0.875 MILE D-OVAL", "ADVANCED",
    kinked(0.875, 4, 260, 18, 80, 115, 13.0, 9.0), 0.875, 350, SUN, SHORT, width=16.0, apron=7.0, infield=10.0,
    bank_straight=6.0, pit_mph=40, sun_elev=30.0, sun_az=240.0)
# 23 Richmond: 0.75 mi D-shape, 14 degrees.
add("CAPITAL CITY RACEWAY", "CAPITAL CITY", "Richmond Raceway", "0.75 MILE D-OVAL", "ADVANCED",
    kinked(0.75, 4, 230, 30, 40, 95, 14.0, 8.0), 0.75, 400, NIGHT, SHORT, width=16.0, apron=7.0, infield=10.0,
    bank_straight=2.0, pit_mph=35, night=True, sun_elev=40.0, sun_az=60.0)
# 24 New Hampshire: 1.058 mi flat paperclip, 2-7 degrees.
add("GRANITE STATE SPEEDWAY", "GRANITE STATE", "New Hampshire Motor Speedway", "1.058 MILE FLAT OVAL", "ADVANCED",
    oval(1.058, 470.0, 100.0, 6.0), 1.058, 301, SUN, SHORT, width=16.0, apron=7.0, infield=10.0, bank_straight=1.0,
    pit_mph=35, lake=True, sun_elev=40.0, sun_az=120.0)
# 25 Gateway (World Wide Technology Raceway): 1.25 mi egg, tight turns 1-2 (11), wide 3-4 (9).
add("RIVERBEND RACEWAY", "RIVERBEND", "World Wide Technology Raceway (Gateway)", "1.25 MILE EGG", "ADVANCED",
    egg(1.25, 115.0, 170.0, 150.0, 190.0, 11.0, 9.0), 1.25, 240, DUSK, SHORT, width=16.0, apron=7.0, infield=10.0,
    bank_straight=3.0, pit_mph=40, sun_elev=12.0, sun_az=275.0)
# 26 Charlotte Roval: 2.28 mi, the oval's banking plus the infield and chicanes.
add("QUEEN CITY ROVAL", "QC ROVAL", "Charlotte Motor Speedway Roval", "2.28 MILE ROVAL", "EXPERT",
    corners(2.28, [(380, 30, 60), (420, 150, 25), (250, 160, 20), (150, 260, 25), (230, 320, 25), (440, 420, 50),
                    (60, 440, 18), (20, 410, 16), (-20, 440, 18), (-480, 440, 200), (-480, 0, 200), (-250, 0, 18),
                    (-210, 25, 16), (-170, 0, 18)],
            banks=[20, 2, 2, 2, 2, 20, 1, 1, 1, 24, 24, 1, 1, 1]),
    2.28, 109, DUSK, ROAD, width=15.0, apron=4.0, infield=10.0, bank_straight=4.0, pit_mph=40, sun_elev=14.0, sun_az=260.0)
# 27 Homestead: 1.5 mi oval, progressive 18-20 degrees.
add("BISCAYNE SPEEDWAY", "BISCAYNE", "Homestead-Miami Speedway", "1.5 MILE OVAL", "INTERMEDIATE",
    oval(1.5, 600.0, 225.0, 20.0), 1.5, 267, COAST, INTER, width=19.0, apron=8.0, infield=12.0, bank_straight=4.0,
    pit_mph=45, lake=True, sun_elev=25.0, sun_az=250.0)
# 28 Dover (All-Star): 1 mi concrete, 24 degrees.
add("FIRST STATE SPEEDWAY", "FIRST STATE", "Dover Motor Speedway", "1 MILE CONCRETE OVAL", "EXPERT",
    oval(1.0, 330.0, 150.0, 24.0), 1.0, 400, SUN, SHORT, width=16.0, apron=7.0, infield=10.0, bank_straight=9.0,
    turn_grip=1.08, pit_mph=35, sun_elev=45.0, sun_az=160.0)
# 29 Bowman Gray (the Clash): 0.25 mi flat quarter-mile inside a football stadium.
add("TWIN CITY STADIUM", "TWIN CITY", "Bowman Gray Stadium", "0.25 MILE STADIUM OVAL", "EXPERT",
    oval(0.25, 80.0, 38.0, 1.0), 0.25, 200, NIGHT, dict(SHORT, draft=0.05), width=11.0, apron=3.0, infield=6.0,
    bank_straight=0.0, pit_mph=25, night=True, sun_elev=40.0, sun_az=90.0)

# The 2026 Cup calendar (the 36 points races), as indices into the list above.
CAL = ["SURFSIDE", "PEACHTREE", "HILL COUNTRY", "SAGUARO", "NEON VALLEY", "PEE DEE", "BLUE RIDGE", "THUNDER HOLLOW",
       "PRAIRIE", "COTTON STATE", "LONGHORN", "FINGER LAKES", "QUEEN CITY", "MUSIC ROW", "IRISH HILLS", "LAUREL MTN",
       "HARBOR BASE", "WINE COUNTRY", "LAKESHORE", "PEACHTREE", "MOONSHINE", "CROSSROADS", "CORN BELT", "CAPITAL CITY",
       "GRANITE STATE", "SURFSIDE",
       "PEE DEE", "RIVERBEND", "THUNDER HOLLOW", "PRAIRIE", "NEON VALLEY", "QC ROVAL", "SAGUARO", "COTTON STATE",
       "BLUE RIDGE", "BISCAYNE"]


def gd(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(float(v)) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return v if v.startswith("Color(") else '"%s"' % v.replace('"', '\\"')
    if isinstance(v, dict):
        return "{" + ", ".join('"%s": %s' % (k, gd(x)) for k, x in v.items()) + "}"
    if isinstance(v, list):
        return "[" + ", ".join(gd(x) for x in v) + "]"
    raise TypeError(v)


def laps_for(miles, kind):
    """A race at SHORT length gets about this many laps by default (race_laps),
    and the arcade's 'laps'."""
    return max(3, int(round(8.0 / max(miles, 0.25) ** 0.9)))


def points(segs):
    lens = solve(segs)
    h = 0.0
    x = y = 0.0
    pts = [(x, y)]
    for sg in segs:
        if "s" in sg:
            L = lens[sg["s"]] if isinstance(sg["s"], str) else sg["s"]
            x += math.cos(h) * L
            y += math.sin(h) * L
            pts.append((x, y))
        else:
            a = math.radians(sg["a"])
            n = max(2, int(abs(a) * 12))
            for i in range(n):
                dx, dy = chord(h, a / n, sg["r"])
                x += dx
                y += dy
                h += a / n
                pts.append((x, y))
    return pts


def plot(t, path):
    from PIL import Image, ImageDraw
    pts = points(t["segments"])
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    w = max(max(xs) - min(xs), max(ys) - min(ys), 1.0)
    sc = 360.0 / w
    im = Image.new("RGB", (400, 400), (20, 24, 32))
    dr = ImageDraw.Draw(im)
    q = [((p[0] - min(xs)) * sc + 20, 380 - (p[1] - min(ys)) * sc) for p in pts]
    dr.line(q, fill=(240, 240, 240), width=3)
    dr.ellipse([q[0][0] - 5, q[0][1] - 5, q[0][0] + 5, q[0][1] + 5], fill=(255, 60, 60))
    dr.text((8, 6), "%s  %.2f mi" % (t["short"], t["miles"]), fill=(255, 220, 80))
    im.save(path)


def main():
    if PLOT:
        os.makedirs(PLOT, exist_ok=True)
        for t in T:
            try:
                plot(t, os.path.join(PLOT, t["short"].replace(" ", "_") + ".png"))
            except Exception as e:
                print("plot", t["short"], e)
        print("\n".join(PROBLEMS) or "no problems")
        return
    shorts = [t["short"] for t in T]
    cal = [shorts.index(s) for s in CAL]
    assert len(cal) == 36
    lines = ['## Generated by tools/make_replicas.py: do not edit by hand.',
             '## Layouts modelled on the tracks of the 2026 NASCAR Cup calendar (fictional',
             '## names; "real" is the venue each copies). Road courses that run clockwise',
             '## are drawn mirrored (the game races anticlockwise).',
             'extends RefCounted', '', 'const TRACKS := [']
    for t in T:
        d = {"name": t["name"], "short": t["short"], "kind": t["kind"], "level": t["level"], "replica": True, "real": t["real"],
             "segments": t["segments"]}
        if "front" in t:
            d["front"] = t["front"]
        radii = [s["r"] for s in t["segments"] if "r" in s]
        d["radius"] = round(min(radii), 3)
        for k in ["width", "apron", "infield"]:
            d[k] = t[k]
        banks = [s.get("b", 0.0) for s in t["segments"] if "r" in s]
        d["bank_turn"] = max(banks)
        d["bank_straight"] = t["bank_straight"]
        d["laps"] = laps_for(t["miles"], t["kind"])
        d["grid_player"] = 24
        for k, v in t["pkg"].items():
            d[k] = v
        d["pit_mph"] = t["pit_mph"]
        d["race_laps"] = max(5, int(round(t["full_laps"] * 0.1)))
        d["full_laps"] = t["full_laps"]
        for k, v in t["look"].items():
            d[k] = v
        for k in ["lake", "night", "turn_grip", "sun_elev", "sun_az"]:
            if k in t:
                d[k] = t[k]
        d.setdefault("lake", False)
        lines.append("\t" + gd(d) + ",")
    lines.append("]")
    lines.append("")
    lines.append("## The 2026 calendar's 36 points races, as indices into TRACKS.")
    lines.append("const CALENDAR := " + gd(cal))
    lines.append("")
    path = os.path.join(os.path.dirname(__file__), "..", "scripts", "replica_tracks.gd")
    with open(path, "w") as f:
        f.write("\n".join(lines))
    for t in T:
        print("%-28s %-34s %5.3f mi" % (t["short"], t["real"], t["miles"]))
    print(len(T), "tracks")


if __name__ == "__main__":
    main()
