// Speedway Thunder: every write the game makes. Players register once and get a
// secret (only its hash is stored); each later call proves who it is with it.
// Lap times are checked against what the track allows before they count.
//   POST {action: "register" | "profile" | "lap" | "event" | "friend" | "session"
//                | "save" | "load" | "transfer_code" | "claim" | "report", ...}
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Track lengths in metres (the game's 11 tracks); a lap faster than 95 m/s
// average (212 mph) isn't possible anywhere.
const TRACK_M = [3444, 2430, 869, 4216, 3685, 2591, 1996, 853, 2028, 4522, 5198];
const MAX_AVG = 95.0;
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
// A saved game: a few small config files as text. Plenty of room.
const MAX_SAVE_BYTES = 256_000;
const TRANSFER_HOURS = 24;
// Problem reports: a small screenshot and the race state, a few a day each.
const MAX_REPORT_IMAGE = 300_000; // base64 characters
const MAX_REPORT_STATE = 100_000; // JSON characters
const REPORTS_PER_DAY = 20;
const REPORT_TAGS = ["HANDLING", "CONTROLS", "GRAPHICS", "CRASH", "RULES", "MENUS", "SOUND", "OTHER"];

function reply(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

async function sha256(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function randomCode(n = 6): string {
  const b = crypto.getRandomValues(new Uint8Array(n));
  return [...b].map((x) => CODE_CHARS[x % CODE_CHARS.length]).join("");
}

function newSecret(): string {
  return [...crypto.getRandomValues(new Uint8Array(24))].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function levelFor(xp: number): number {
  // 500 XP to level 2, each level a little more.
  let lvl = 1, need = 500, left = xp;
  while (left >= need && lvl < 99) { left -= need; lvl += 1; need = Math.round(need * 1.15); }
  return lvl;
}

function cleanName(s: unknown): string {
  return String(s ?? "").toUpperCase().replace(/[^A-Z0-9 .'-]/g, "").trim().slice(0, 24) || "DRIVER";
}

async function who(body: Record<string, unknown>) {
  const id = String(body.id ?? "");
  const secret = String(body.secret ?? "");
  if (!/^[0-9a-f-]{36}$/.test(id) || secret.length < 32) return null;
  const { data } = await db.from("players").select("id, secret_hash, xp").eq("id", id).maybeSingle();
  if (!data || data.secret_hash !== await sha256(secret)) return null;
  return data;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reply({ error: "POST only" }, 405);
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply({ error: "bad json" }, 400); }
  const action = String(body.action ?? "");

  if (action === "register") {
    const secret = newSecret();
    for (let tries = 0; tries < 5; tries++) {
      const code = randomCode();
      const { data, error } = await db.from("players").insert({
        name: cleanName(body.name), num: String(body.num ?? "1").slice(0, 3),
        friend_code: code, secret_hash: await sha256(secret),
      }).select("id, friend_code").single();
      if (!error && data) return reply({ id: data.id, secret, friend_code: data.friend_code });
    }
    return reply({ error: "couldn't register" }, 500);
  }

  // A new phone: a one-time code from the old one hands over the account. The
  // secret is replaced (only its hash is stored), so the old phone is signed out.
  if (action === "claim") {
    const code = String(body.code ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
    if (code.length !== 8) return reply({ error: "codes are 8 letters and numbers" }, 400);
    const { data: t } = await db.from("transfers").select("player_id, expires_at").eq("code", code).maybeSingle();
    if (!t || new Date(t.expires_at).getTime() < Date.now()) return reply({ error: "that code isn't valid (or has expired)" }, 404);
    await db.from("transfers").delete().eq("player_id", t.player_id);
    const secret = newSecret();
    const { data: p } = await db.from("players").update({ secret_hash: await sha256(secret) })
      .eq("id", t.player_id).select("id, friend_code, name").single();
    const { data: s } = await db.from("saves").select("data, updated_at").eq("player_id", t.player_id).maybeSingle();
    return reply({ ok: true, id: p!.id, secret, friend_code: p!.friend_code, name: p!.name, save: s?.data ?? null, saved_at: s?.updated_at ?? null });
  }

  const me = await who(body);
  if (!me) return reply({ error: "unknown player" }, 401);

  switch (action) {
    case "profile": {
      const xp = Math.max(Number(me.xp) || 0, Math.min(Math.floor(Number(body.xp) || 0), 10_000_000));
      const streak = Math.max(0, Math.min(Math.floor(Number(body.streak) || 0), 10_000));
      await db.from("players").update({
        name: cleanName(body.name), num: String(body.num ?? "1").slice(0, 3),
        xp, level: levelFor(xp), streak, last_seen: new Date().toISOString(),
      }).eq("id", me.id);
      return reply({ ok: true, xp, level: levelFor(xp) });
    }
    case "lap": {
      const track = Math.floor(Number(body.track));
      const ms = Math.floor(Number(body.lap_ms));
      if (!(track >= 0 && track < TRACK_M.length)) return reply({ error: "no leaderboard for that track" }, 400);
      if (!(ms >= TRACK_M[track] / MAX_AVG * 1000 && ms < 600_000)) return reply({ error: "lap time not possible" }, 400);
      const ghost = typeof body.ghost === "string" && body.ghost.length <= 120000 ? body.ghost : null;
      const { data: old } = await db.from("laps").select("lap_ms").eq("player_id", me.id).eq("track", track).maybeSingle();
      if (old && old.lap_ms <= ms) return reply({ ok: true, best: old.lap_ms, improved: false });
      await db.from("laps").upsert({ player_id: me.id, track, lap_ms: ms, make: Math.floor(Number(body.make) || 0) % 8, ghost, updated_at: new Date().toISOString() });
      return reply({ ok: true, best: ms, improved: true });
    }
    case "event": {
      const key = String(body.event_key ?? "");
      if (!/^(daily-\d{4}-\d{2}-\d{2}|weekly-\d{4}-W\d{2})$/.test(key)) return reply({ error: "bad event" }, 400);
      const score = Math.floor(Number(body.score));
      if (!Number.isFinite(score) || score < 0) return reply({ error: "bad score" }, 400);
      const { data: old } = await db.from("event_results").select("score").eq("event_key", key).eq("player_id", me.id).maybeSingle();
      if (old && old.score <= score) return reply({ ok: true, best: old.score, improved: false });
      const detail = typeof body.detail === "object" && body.detail ? body.detail : {};
      await db.from("event_results").upsert({ event_key: key, player_id: me.id, score, detail });
      return reply({ ok: true, best: score, improved: true });
    }
    case "friend": {
      const code = String(body.code ?? "").toUpperCase().trim();
      const { data: f } = await db.from("players").select("id, name, num, friend_code").eq("friend_code", code).maybeSingle();
      if (!f) return reply({ error: "no driver with that code" }, 404);
      if (f.id === me.id) return reply({ error: "that's your own code" }, 400);
      await db.from("friends").upsert([{ player_id: me.id, friend_id: f.id }, { player_id: f.id, friend_id: me.id }]);
      return reply({ ok: true, friend: { id: f.id, name: f.name, num: f.num, friend_code: f.friend_code } });
    }
    case "session": {
      await db.from("sessions").insert({
        player_id: me.id, device: String(body.device ?? "").slice(0, 60), touch: !!body.touch,
        fps_avg: Number(body.fps_avg) || null, fps_p5: Number(body.fps_p5) || null,
        cars: Math.floor(Number(body.cars) || 0), quality: Math.floor(Number(body.quality) || 0),
        secs: Math.floor(Number(body.secs) || 0), mode: String(body.mode ?? "").slice(0, 20),
      });
      return reply({ ok: true });
    }
    case "save": {
      // {files: {"career.cfg": "...", ...}}: the saved game, as the game's own files.
      const files = body.files;
      if (typeof files !== "object" || !files || Array.isArray(files)) return reply({ error: "bad save" }, 400);
      const clean: Record<string, string> = {};
      for (const [k, v] of Object.entries(files as Record<string, unknown>)) {
        if (/^[a-z_]{1,32}\.cfg$/.test(k) && typeof v === "string") clean[k] = v;
      }
      const bytes = JSON.stringify(clean).length;
      if (bytes > MAX_SAVE_BYTES) return reply({ error: "save too big" }, 413);
      const now = new Date().toISOString();
      await db.from("saves").upsert({ player_id: me.id, data: { files: clean }, bytes, updated_at: now });
      return reply({ ok: true, saved_at: now, bytes });
    }
    case "load": {
      const { data: s } = await db.from("saves").select("data, updated_at").eq("player_id", me.id).maybeSingle();
      return reply({ ok: true, save: s?.data ?? null, saved_at: s?.updated_at ?? null });
    }
    case "report": {
      const since = new Date(Date.now() - 24 * 3600_000).toISOString();
      const { count } = await db.from("reports").select("id", { count: "exact", head: true })
        .eq("player_id", me.id).gte("created_at", since);
      if ((count ?? 0) >= REPORTS_PER_DAY) return reply({ error: "too many reports today" }, 429);
      const state = typeof body.state === "object" && body.state && !Array.isArray(body.state) ? body.state : {};
      const stateText = JSON.stringify(state);
      if (stateText.length > MAX_REPORT_STATE) return reply({ error: "report too big" }, 413);
      let image = typeof body.image === "string" ? body.image : "";
      if (image.length > MAX_REPORT_IMAGE || !/^[A-Za-z0-9+/=]*$/.test(image)) image = "";
      const tags = Array.isArray(body.tags) ? (body.tags as unknown[]).map(String).filter((t) => REPORT_TAGS.includes(t)).slice(0, 4) : [];
      const { data: r, error } = await db.from("reports").insert({
        player_id: me.id, version: String(body.version ?? "").slice(0, 40),
        note: String(body.note ?? "").slice(0, 600), tags, state, image: image || null,
        bytes: stateText.length + image.length,
      }).select("id").single();
      if (error || !r) return reply({ error: "couldn't save the report" }, 500);
      return reply({ ok: true, ref: r.id });
    }
    case "transfer_code": {
      await db.from("transfers").delete().eq("player_id", me.id);
      const expires = new Date(Date.now() + TRANSFER_HOURS * 3600_000).toISOString();
      for (let tries = 0; tries < 5; tries++) {
        const code = randomCode(8);
        const { error } = await db.from("transfers").insert({ code, player_id: me.id, expires_at: expires });
        if (!error) return reply({ ok: true, code, expires_at: expires });
      }
      return reply({ error: "couldn't make a code" }, 500);
    }
  }
  return reply({ error: "unknown action" }, 400);
});
