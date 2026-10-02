#!/usr/bin/env python3
"""A stand-in for the game's Supabase project, for testing scripts/cloud.gd
offline: the "st" edge function (register, profile, lap, event, friend,
session) and the read-only REST queries the game makes, in memory.

    python3 tests/tools/fake_cloud.py 24790
    ST_CLOUD=http://127.0.0.1:24790 godot ... -s tests/cloud_test.gd

POST /debug/seed {"name", "num", "code", "track", "lap_ms", "ghost"} adds another
driver with a lap (for friends and ghosts); GET /debug/state shows everything.
"""
import hashlib, json, re, secrets, sys, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qsl

TRACK_M = [3444, 2430, 869, 4212, 3685, 2590, 1989, 853, 2028, 4522, 5198,
           4023, 2478, 3862, 1609, 2414, 2198, 846, 857, 2413, 4280, 2414, 3943, 2414, 2140, 3218,
           4023, 5471, 3202, 2414, 1005, 4023, 1408, 1206, 1702, 2011, 3669, 2414, 1609, 402]
players, laps, events, friends, sessions = {}, {}, {}, set(), []
reports = []
saves, transfers = {}, {}  # player id -> {"data", "updated_at"}; code -> player id
import time


def public(p):
    return {k: p[k] for k in ("id", "name", "num", "friend_code", "xp", "level")}


def embed(row):
    p = players.get(row["player_id"], {})
    out = dict(row)
    out["players"] = {"name": p.get("name", "?"), "num": p.get("num", "")}
    return out


def act(body):
    a = body.get("action")
    if a == "claim":
        code = str(body.get("code", "")).upper()
        pid = transfers.pop(code, None)
        if not pid:
            return 404, {"error": "that code isn't valid (or has expired)"}
        for c in [c for c, p in transfers.items() if p == pid]:
            transfers.pop(c)
        sec = secrets.token_hex(24)
        players[pid]["secret_hash"] = hashlib.sha256(sec.encode()).hexdigest()
        s = saves.get(pid)
        return 200, {"ok": True, "id": pid, "secret": sec, "friend_code": players[pid]["friend_code"], "name": players[pid]["name"],
                     "save": s["data"] if s else None, "saved_at": s["updated_at"] if s else None}
    if a == "register":
        sec = secrets.token_hex(24)
        pid = str(uuid.uuid4())
        code = secrets.token_hex(3).upper()
        players[pid] = {"id": pid, "name": str(body.get("name", "DRIVER"))[:24], "num": str(body.get("num", "1")),
                        "friend_code": code, "secret_hash": hashlib.sha256(sec.encode()).hexdigest(), "xp": 0, "level": 1}
        return 200, {"id": pid, "secret": sec, "friend_code": code}
    me = players.get(body.get("id", ""))
    if not me or me["secret_hash"] != hashlib.sha256(str(body.get("secret", "")).encode()).hexdigest():
        return 401, {"error": "unknown player"}
    if a == "profile":
        me["xp"] = max(me["xp"], int(body.get("xp", 0)))
        me["streak"] = int(body.get("streak", 0))
        me["name"] = str(body.get("name", me["name"]))[:24]
        return 200, {"ok": True, "xp": me["xp"]}
    if a == "lap":
        t, ms = int(body["track"]), int(body["lap_ms"])
        if not (0 <= t < len(TRACK_M)) or ms < TRACK_M[t] / 95.0 * 1000:
            return 400, {"error": "lap time not possible"}
        old = laps.get((me["id"], t))
        if old and old["lap_ms"] <= ms:
            return 200, {"ok": True, "improved": False}
        laps[(me["id"], t)] = {"player_id": me["id"], "track": t, "lap_ms": ms, "make": int(body.get("make", 0)), "ghost": body.get("ghost")}
        return 200, {"ok": True, "improved": True}
    if a == "event":
        key = body["event_key"]
        if not re.match(r"^(daily-\d{4}-\d{2}-\d{2}|weekly-\d{4}-W\d{2})$", key):
            return 400, {"error": "bad event"}
        old = events.get((key, me["id"]))
        if not old or old["score"] > int(body["score"]):
            events[(key, me["id"])] = {"event_key": key, "player_id": me["id"], "score": int(body["score"]), "detail": body.get("detail", {})}
        return 200, {"ok": True}
    if a == "friend":
        f = next((p for p in players.values() if p["friend_code"] == str(body.get("code", "")).upper()), None)
        if not f:
            return 404, {"error": "no driver with that code"}
        friends.add((me["id"], f["id"]))
        friends.add((f["id"], me["id"]))
        return 200, {"ok": True, "friend": public(f)}
    if a == "report":
        if len(body.get("image", "")) > 300000 or len(json.dumps(body.get("state", {}))) > 100000:
            return 413, {"error": "report too big"}
        reports.append(body)
        return 200, {"ok": True, "ref": len(reports)}
    if a == "session":
        sessions.append(body)
        return 200, {"ok": True}
    if a == "save":
        files = {k: v for k, v in (body.get("files") or {}).items() if re.match(r"^[a-z_]{1,32}\.cfg$", k) and isinstance(v, str)}
        now = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()) + ".%06dZ" % (time.time_ns() // 1000 % 1000000)
        saves[me["id"]] = {"data": {"files": files}, "updated_at": now}
        return 200, {"ok": True, "saved_at": now, "bytes": len(json.dumps(files))}
    if a == "load":
        s = saves.get(me["id"])
        return 200, {"ok": True, "save": s["data"] if s else None, "saved_at": s["updated_at"] if s else None}
    if a == "transfer_code":
        for c in [c for c, p in transfers.items() if p == me["id"]]:
            transfers.pop(c)
        code = "".join(secrets.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(8))
        transfers[code] = me["id"]
        return 200, {"ok": True, "code": code}
    return 400, {"error": "unknown action"}


def query(table, q):
    filt = dict(parse_qsl(q, keep_blank_values=True))
    if table == "laps":
        rows = list(laps.values())
    elif table == "event_results":
        rows = list(events.values())
    elif table == "friends":
        rows = [{"player_id": a, "friend_id": b} for a, b in friends]
    elif table == "players":
        rows = [public(p) for p in players.values()]
    else:
        return 404, {"error": "no table"}
    for k, v in filt.items():
        if k in ("select", "order", "limit"):
            continue
        if v.startswith("eq."):
            rows = [r for r in rows if str(r.get(k)) == v[3:]]
        elif v.startswith("in.("):
            ids = v[4:-1].split(",")
            rows = [r for r in rows if str(r.get(k)) in ids]
        elif v == "not.is.null":
            rows = [r for r in rows if r.get(k)]
    if "order" in filt:
        col = filt["order"].split(".")[0]
        rows.sort(key=lambda r: r.get(col, 0))
    if "limit" in filt:
        rows = rows[: int(filt["limit"])]
    if "players(" in filt.get("select", ""):
        rows = [embed(r) for r in rows]
    return 200, rows


class H(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        raw = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(n) or b"{}")
        path = urlparse(self.path).path
        if path == "/functions/v1/st":
            self._send(*act(body))
        elif path == "/debug/seed":
            pid = str(uuid.uuid4())
            players[pid] = {"id": pid, "name": body["name"], "num": body.get("num", "9"), "friend_code": body["code"],
                            "secret_hash": "x", "xp": 0, "level": 1}
            laps[(pid, int(body["track"]))] = {"player_id": pid, "track": int(body["track"]), "lap_ms": int(body["lap_ms"]),
                                               "make": 1, "ghost": body.get("ghost")}
            self._send(200, {"id": pid})
        else:
            self._send(404, {"error": "no route"})

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/debug/state":
            self._send(200, {"players": len(players), "laps": len(laps), "events": len(events), "friends": len(friends), "sessions": len(sessions), "reports": len(reports), "last_report": reports[-1] if reports else None})
        elif u.path.startswith("/rest/v1/"):
            self._send(*query(u.path[len("/rest/v1/"):], u.query))
        else:
            self._send(404, {"error": "no route"})

    def log_message(self, *a):
        pass


ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 24790), H).serve_forever()
