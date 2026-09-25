# Speedway Thunder '99 — Stock Car Arcade

![Title screen](docs/title.png) ![Racing](docs/race.png)

A late-90s arcade stock car racer, like the NASCAR arcade cabinets of 1999, built in **Godot 4.3**.

Everything is generated at runtime: tracks, grandstands, cars, the HUD and the synth
audio. The project has no imported assets. It renders at 640×480 with vertex-coloured
low-poly geometry, per-vertex lighting, distance fog and optional CRT scanlines.

## Features

- **Arcade flow.** Attract-mode demo race, then course select, car select (each with a
  20-second timer), a rolling two-wide start with a 3-2-1 green flag, the race, and results.
  After the results you return to the title screen.
- **Arcade clock.** A countdown timer gets **EXTENDED TIME** each lap. If it runs out,
  it's **GAME OVER**.
- **Three ovals:**
  - *Thunder Beach* is a 2.15 mi superspeedway tri-oval with 31° banking. Drafting matters most here (Beginner).
  - *Lone Star* is a 1.46 mi quad-oval. You have to lift in the turns (Advanced).
  - *Thunder Valley* is a 0.54 mi night short track with 36° banking and heavy braking (Expert).
- **12-car field** of fictional teams. The AI changes lanes to pass, brakes for traffic and
  rubber-bands to keep the pack close.
- **Drafting.** Tuck in behind a car for extra top speed. The DRAFT meter lights up when you're in it.
- **Contact.** You can bump-draft, trade paint side by side and scrape the wall (sparks, speed loss, camera shake).
- **Banking.** Banked turns increase grip, and the cars and camera tilt with the banking.
- **Three cameras:** far chase, near chase and bumper.
- **Procedural audio.** The V8 engine note follows RPM through a 4-speed automatic.
  There are also pass-by whooshes, tyre squeal, crunches and countdown beeps.
- **Records.** Best lap and best race time for each track are saved to `user://records.cfg`.

## Running

1. Install [Godot 4.3+](https://godotengine.org/download). The standard build is fine; you don't need .NET.
2. Open `project.godot` in the editor and press **F5**, or run from the command line:
   ```sh
   godot --path .
   ```

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Steer | ← → / A D | Left stick / D-pad |
| Gas | ↑ / W / Z | RT / A |
| Brake / reverse | ↓ / S / X | LT / B |
| Start / select | Enter / Space | Start / A |
| Back (menus) | Backspace | B |
| Change camera | C | Y |
| Pause | Esc / P | Back |
| Quit race (while paused) | Q | — |
| Toggle scanlines | F2 | — |
| Fullscreen | F11 | — |

## Project layout

```
project.godot          640x480 viewport stretch, GL Compatibility renderer
scenes/main.tscn       single scene; everything else is built in code
scripts/game.gd        autoload: tracks, teams, input map, records, arcade font
scripts/main.gd        state machine, menus, cameras, arcade clock
scripts/track.gd       oval generator: centre line, banking, speed profile, meshes, scenery
scripts/race.gd        field spawn, AI drivers, drafting, contact, laps, running order
scripts/car.gd         car model + arcade physics in track space (s, d, yaw)
scripts/hud.gd         time / lap / position / tach / minimap / messages
scripts/audio.gd       AudioStreamGenerator software synth
tests/smoke_test.gd    headless: runs a full autopilot race on every track
tests/screenshots.gd   captures screenshots of each screen (needs a renderer)
```

### How the physics works

Each car's state is kept in *track space*: distance along the centre line `s`, lateral
offset `d` and a yaw angle relative to the track. Every frame, the track's curvature turns
the ground under the car, so you have to steer into each turn. How much you can steer
depends on a grip limit that includes the banking:
`g·(sinθ + μcosθ)/(cosθ − μsinθ)`. If you turn harder than that, the tyres scrub off speed.
The walls, apron, grass, drafting and car-to-car contact are all simple 1D/2D checks in
this space. That keeps the handling stable and predictable, the way an arcade racer should feel.

## Tests

```sh
# Full race on each track with the player on autopilot (~20 s)
godot --headless --fixed-fps 60 --path . -s tests/smoke_test.gd

# Screenshots of each screen (Linux without a display: wrap in xvfb-run)
OUT=/tmp/shots godot --rendering-driver opengl3 --fixed-fps 60 --path . -s tests/screenshots.gd
```

In headless mode, Godot's dummy renderer prints `mesh_get_surface_count` errors.
They're harmless and don't appear with a real renderer.

## Notes

All team names, drivers, sponsors and tracks are fictional. The title lives in
`scripts/game.gd` (`TITLE` / `SUBTITLE`) and in the title screen in `scripts/main.gd`
if you want to rename the game.
