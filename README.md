# Speedway Thunder '99

Modern mode:

![Modern graphics, day](docs/modern_day.png) ![Modern graphics, night](docs/modern_night.png)

1999 mode:

![Title screen](docs/title.png) ![Racing](docs/race.png)

A stock car racing game built in **Godot 4.7**. It has the feature set of the classic
NASCAR console games of the early 2000s, with racing modelled on 2026 Next Gen Cup cars.
It also keeps its roots as a 1999 arcade cabinet racer.

Everything is generated at runtime: tracks, grandstands, cars, the HUD and the synth
audio. The project has no imported assets.

### Two graphics modes (F3 to switch)

- **Modern** (the default) is the realistic look:
  - a Cup-class (Next Gen) car built to published dimensions (110 in wheelbase,
    193.4 in long, 18 in single-lug wheels): flared wheel arches, a long raked
    windshield with the roll cage visible through the glass, the driver's window
    net, carbon splitter, skirts, diffuser and spoiler, headlight decals, side
    exhausts and ten-spoke wheels with brake discs, in each team's two-tone
    livery; the body crumples where it's hit (`tests/shots_showroom.gd` renders
    it on its own);
  - four bodies on that chassis, as Cup's makes each run their own (unbranded):
    **FASTBACK** (pony car: sloping fastback roof, louvred back glass, three-bar tail
    lamps, shark nose), **LONG HOOD** (V8 sports car: long low hood, thin angular
    headlights, gills behind the front wheels, split tail lamps, quad centre exhausts),
    **SPORT COUPE** (Japanese sports coupe: double-bubble roof, swollen haunches, low
    pointed nose, a slim full-width tail light, big corner intakes) and **GRAND TOURER**
    (Japanese GT: long low hood, a big hourglass mesh grille, slim swept headlights
    with arrow running lights, deep scoops behind the doors, the widest haunches, thin
    L-shaped tail lamps). Same speed. Every field is split evenly between the four
    (your own pick counts toward its make); choose yours in the Paint Shop (BODY);
  - race-track asphalt generated stone by stone (grey aggregate in dark binder, sealed
    cracks, a bump map so the stones catch the light) at a real asphalt brightness,
    plus grass and concrete textures with normal maps;
  - real skies for lighting: the cars' paint, glass and chrome reflect photographed
    CC0 skies from Poly Haven (clear day, sunset, overcast, night; see
    `assets/hdri/CREDITS.md`), turned so the photo's sun sits where the game's sun is
    and swapped as the race clock and the weather change; AgX filmic tone mapping;
  - grandstands full of fans, pine and broadleaf trees and a chain-link catch fence;
  - a procedural sky with clouds (stars at night), sun shadows and bloom;
  - on desktop (Forward+): ambient occlusion, screen-space reflections, volumetric fog
    with light-tower beams at night, and FSR 2 upscaling with temporal anti-aliasing.
  Options → Quality picks LOW / MEDIUM / HIGH / ULTRA, or AUTO, which lowers detail
  when frames run late. The browser build runs Modern with lighter effects.
- **1999** is the original look: 640×480 upscaled, vertex colours, boxy cars, blob
  shadows and CRT scanlines (F2).

Motion is smooth on any refresh rate: cars are drawn between physics steps (Options →
Motion smoothing), and Options → VSync off gives the lowest input delay.

## Game modes

| Mode | What it is |
|---|---|
| **Arcade** | The 1999 cabinet game: 16 cars, a short race and a countdown clock with EXTENDED TIME each lap. |
| **Single Race** | A full race weekend (practice, qualifying, race) with 20–40 cars and the full rules below. |
| **Season** | A 6-, 12- or 36-race championship with points, wins and top 5s. Standings are saved between sessions. |
| **Career** | Rookie to champion. Start underfunded, then earn prize money and reputation, sign sponsors and buy engine, aero, chassis and pit-crew R&D. It runs season after season with a career record. |
| **2 Player** | Split-screen racing. Player 2 uses I/J/K/L (U to pit) or a second gamepad. |
| **Lightning Challenges** | Eight race-defining scenarios, such as a last-lap draft, a charge from the back or saving fuel. Completing five unlocks the #00 Thunderbolt legend car. |
| **Paint Shop** | Create your own car: number, driver name, sponsor and colours. You can race it in every mode. |
| **Online** | Race friends over the internet or a local network. One player hosts (desktop, port 24565), others join by address. Green-flag races with an AI field. |
| **Track Editor** | Build a track from straights and turns (radius, angle, banking), see it drawn live, test-drive it and save it as a mod. |

## Racing: how it models 2026 Next Gen racing

- **Built to published Gen 3 figures.** Each track runs its 2026 engine package:
  510 hp on the superspeedways, 670 hp on the intermediates, 750 hp on short tracks
  and road courses, with drag and downforce to match. Tyres grip like racing slicks
  (peak mu 1.35, falling off with load as real tyres do). Solo qualifying laps land
  close to the real pole speeds at the track each one is modelled on:

  | Track | Modelled on | Game | Real pole |
  |---|---|---|---|
  | Thunder Beach | Daytona | 183 mph | ~181 |
  | Lone Star | Texas | 183 | ~185 |
  | Thunder Valley | Bristol | 125 | ~127 |
  | Big Sky | Talladega | 184 | ~181 |
  | Motor City | Michigan | 189 | ~186 |
  | Gulf Coast | Kansas | 179 | ~182 |
  | Palmetto | Darlington | 169 | ~168 |
  | Magnolia | Martinsville | 91 | ~97 |
  | Desert Sun | Phoenix | 133 | ~137 |
  | Keystone | Pocono | 164 | ~171 |
  | Canyon Ridge | Watkins Glen / COTA | 116 | ~110 |

  `tests/lap_bench.gd` runs these in seconds.

- **Car physics.** Each car is simulated like a real stock car:
  - **four tyres**, each with its own load, slip angle, grip peak and fall-off, a
    friction circle (braking or driving uses up cornering grip), brakes that can
    lock a wheel, and wheelspin;
  - **a spool rear axle with stagger** sized to each oval's turns (road courses run
    none), so the car pushes or turns like the real thing;
  - **suspension**: the body heaves, pitches and rolls on springs, dampers,
    anti-roll bars and bump stops (it rides on the stops in the banking), so load
    transfer, and the car's balance, comes from the chassis. Pavement seams and
    turn-entry bumps upset it;
  - **tyre temperature, pressure and wear per tyre**: grip peaks around 100 °C,
    fresh tyres are cold for a lap, overheated ones go greasy, right sides run
    hottest on ovals. The HUD shows all four;
  - **the track changes**: a rubbered-in groove gets faster, marbles build up high,
    night tracks grip more;
  - **aero** that depends on ride height and yaw: downforce fades as the car turns
    sideways, becomes lift when it's backwards (roof flaps pop up past ~130°), a
    car tucked in off your rear quarter takes air off the spoiler and makes you
    loose;
  - **3D wrecks**: a car that tips far enough, gets lifted in a hit, or goes
    sideways at speed becomes a free 3D body and can get airborne, barrel-roll and
    land on its wheels or its roof;
  - a 5-speed sequential gearbox and fuel burn.

  Driving assists are OFF, MILD (steering help only, looser traction and ABS) or
  FULL. Gamepads rumble with scrub, bumps, locked brakes and hits.
- **Power.** Gen-3 style, unrestricted 950 hp everywhere:
  - superspeedways run tall gears and trimmed drag: about 208–212 mph alone and
    215–220 mph in the draft;
  - everywhere else the cars carry more drag and downforce, so they're quick off
    the corners but top out around 180–195 mph.
- **Drafting.**
  - Superspeedways: pack drafting worth about 9 mph that builds through a line of cars. A car on your bumper pushes you, and a car alongside your rear quarter slows you down (side-drafting).
  - Other tracks: the draft is smaller, and a car close behind another loses front downforce in its dirty air and pushes up the track.
- **Contact and wrecks.** Car-to-car and wall contact is resolved as physical impulses at the contact point:
  - A tap in the right rear can hook a car into a spin.
  - Pack wrecks collect several cars.
  - Damage reduces aero, power and alignment, and heavy damage retires the car.
- **Race rules.**
  - **When the yellow flies:**
    - A wreck: a car out, a heavily damaged car, or three or more cars spinning.
    - A car stopped on the racing surface, or a pile of debris.
    - A spin the driver gathers up and drives away from gets a spotter call, not a caution. Road courses only go yellow for a car that's out or stuck on the track.
    - Light rubs lean on cars rather than turning them around; real hits and hooks still spin them.
    - A typical 20-car race has two stage breaks and none to a few incident cautions.
  - **Quick cautions** (the default: race setting CAUTIONS → QUICK) take about 15 seconds from yellow to green:
    - Scoring freezes and the field slows for a few seconds.
    - **Your pit call:** the race pauses and asks you. Choose 4 tyres, 2 tyres, fuel only, wet tyres (road courses in changeable weather) or stay out, plus an optional chassis change (a round of wedge in or out). The screen shows your tyres, fuel laps, damage, the crew chief's call (*) and roughly where each choice restarts you.
    - **The AI decides for itself.** Tyres are worth positions over the run that's left; a stop costs the places of the cars behind that stay out. Fuel, damage, flats and the weather force stops. Each driver's racecraft, aggression, patience and consistency colour the call, so the field splits on strategy.
    - **Restart order:** cars that stayed out keep their order from the caution. The cars that pitted follow, in the order they get off pit road: where they went in plus how long their stop took. Then come the free pass car, the lapped cars that pitted, and the wave-arounds. The field lines up double file behind the pace car and goes green at the restart zone.
  - **Full cautions** (CAUTIONS → FULL): the pace car picks up the leader and the field runs the real caution laps single file. Pit road opens after a lap, with the free pass and wave-arounds, then "one to go" and double-file restarts with the choose rule.
  - **Stages:** stage points go to the top 10 at the end of each stage.
  - **Finish:** overtime (green-white-checkered), and a caution on the final lap ends the race.
- **Pit stops.** Choose 4 tyres, 2 tyres or fuel only; stops also repair damage. Pit road is driven automatically, and the AI runs its own pit strategy.
- **Spotter.** Callouts for car high, car low, three wide and clear.
- **Garage.** Adjust handling balance (tight or loose), tyre pressure (grip versus wear) and gearing.
- **Replays.** After any race, press R to watch it with TV, chase, bumper or helicopter cameras.

## Race day

- **Tyre failures and damage rules.**
  - Tyres cut from debris or bent fenders and leak down; overheated or worn-out tyres blow (a right front at turn entry sends you up the track).
  - Locking a wheel grinds a flat spot you can feel.
  - Water temperature climbs when you run tucked in a draft or pick up debris on the grille. Clean air can blow small pieces off; the crew clears the rest at a stop. Past 145 °C the engine fails.
  - Wrecks leave debris on the track (enough of it brings out a caution).
  - The Damaged Vehicle Policy gives you a six-minute repair clock, and cars that can't make minimum speed are parked.
- **The air.** Every car leaves a wake. A line of cars stacks its tow; a car right behind pushes you; a car tucked in off your rear quarter takes air off your spoiler (you go loose); a car at your rear quarter side-drafts you; pull out of line and you hit the air wall.
- **Drivers with character.** Aggression, patience, consistency and racecraft differ per driver:
  - smart drivers pick the moving line and block late;
  - drivers you wreck remember it;
  - bump-and-run happens on short tracks at the end;
  - inconsistent drivers make mistakes under pressure;
  - pit calls depend on position and laps left.
- **Weather and time of day.**
  - The sun moves through the race: day races run into sunset, night races start at dusk. Track temperature follows.
  - Race setting WEATHER: CLEAR, CHANGEABLE or RAIN. Ovals are held under caution until the track dries (a drying line forms where the cars run). Road courses race on, with wet tyres (pit plan W).
- **Crew chief.**
  - The garage has wedge, springs, sway bar, bump stops, stagger, pressures per side, brake bias and gearing. Setup sheets save per track, and you can share them as codes.
  - The telemetry overlay (T) shows tread temperatures across each tyre, pressures, wear, loads, shock travel, the air around you, water temperature, a live delta to your best lap, and a speed trace.
  - A radio voice (the system's text-to-speech) gives the spotter's and crew chief's calls.
- **Broadcast director.**
  - Replays cut between incidents, battles and the leader, with TV, chase, roof, blimp and helicopter shots.
  - Highlights (H on the results) show every spin, flip, big hit and lead change in slow motion.
  - Photo mode (F, in a replay or mid-race) lets you orbit, zoom and use depth of field, then save a PNG.
- **Steering wheels.** Options → Wheel Setup: pick the axes by moving them, set rotation and force feedback strength.
  - Force feedback comes from the front tyres' aligning torque, bumps and hits.
  - It runs through a small native helper next to the game: `ffb_helper.exe` (DirectInput) on Windows, SDL2 on Linux. `native/build.sh` builds it.
- **Mods.**
  - Drop tracks in `user://mods/tracks/*.json`: a name plus a `segments` layout, with any other setting you want. Colours are `#rrggbb`.
  - Drop teams in `user://mods/teams/*.json` (a list).
  - The Track Editor writes track mods for you.

## Being there

- **A Gen 3 engine note.** Every car sounds like a 358 cubic inch pushrod V8 with a cross-plane crank: the real firing order (1-8-4-3-6-5-7-2), each bank's exhaust pulses coming unevenly, so it burbles at low revs and howls at 9,000, four pulses per crank turn (600 Hz at 9,000 rpm), following each car's rpm through every shift and the limiter. Lift at high revs and it crackles and pops. The two banks come out either side of your car. (`tests/engine_sound_test.gd` checks it and can write a rev-up WAV.)
- **Sound in 3D.** Every nearby car's engine comes from where the car is, rising and falling in pitch as it passes. Walls and grandstands echo; the crowd is out in the stands and roars at wrecks, lead changes and the finish; wind noise builds with speed. In the cockpit the world outside is muffled.
- **A camera with weight.** Views lean out in the corners, dip under braking and sink back on the throttle, like a head on a neck. Road texture, seams and the engine at high revs come through as vibration, and hits jolt the view.
- **Cockpit view** (C to cycle to it). You get the roll cage and centre bar, the window net, a digital dash with shift lights, and a steering wheel your hands turn. The rear-view mirror shows the cars behind. The whole interior rolls and pitches with the chassis.
- **Air and light.**
  - Haze thickens with distance and sits low in the morning and evening.
  - On HIGH and above, the sun throws shafts through the air, and smoke from a spin or wreck hangs there with light coming through it.
  - The far distance softens with speed, and looking into the sun gives glare. The glare is blocked by anything in front of the sun.
- **Rain you see.**
  - The track carries a film of water with a dry line where the cars run.
  - Cars in front throw up spray that hides them at speed.
  - Beads run up the windshield, and the cockpit wiper sweeps them away.
- **A track that remembers the race.** The line the field actually drives rubbers in: it gets darker and grippier lap by lap. Marbles collect outside it, where they're slippery. Walls keep tyre and paint scuffs, and grass keeps ruts.
- **Feel.**
  - Controller rumble comes in layers: an engine hum that buzzes on the limiter, pulses that quicken as the tyres reach the limit, road texture, a stutter from locked wheels, and thumps from contact.
  - Wheels get heavier with speed, tug towards countersteer when the rear steps out, and snap on wall hits.
- **Race day.**
  - Pit crews come over the wall and work round the car.
  - The flagman waves the flag that's out.
  - Fans jump up for the action and do the wave under caution.
  - The winner gets fireworks and does a burnout.

## Tracks (11, all fictional)

| Track | Type |
|---|---|
| Thunder Beach | 2.1-mile tri-oval superspeedway, 31° banking |
| Big Sky | 2.6-mile superspeedway, 33° banking |
| Lone Star | 1.4-mile quad-oval, sunset |
| Gulf Coast | 1.6-mile oval at dusk |
| Motor City | 2.3-mile D-oval |
| Keystone Triangle | 2.8-mile triangle, a different banking in each corner |
| Palmetto | 1.2-mile egg-shaped oval |
| Desert Sun | 1.3-mile dog-leg oval |
| Thunder Valley | 0.5-mile high-banked night short track |
| Magnolia | 0.5-mile flat paperclip |
| Canyon Ridge | 3.2-mile road course with left and right turns |

## Running

**Windows, no install:** download
[`downloads/SpeedwayThunder-windows.zip`](downloads/SpeedwayThunder-windows.zip),
unzip it and double-click `SpeedwayThunder.exe`. The exe isn't code-signed, so Windows
SmartScreen may warn you: click **More info → Run anyway**.

**Any platform, from source:**

1. Install [Godot 4.7+](https://godotengine.org/download). The standard build is fine; you don't need .NET. The full Modern effects need a Vulkan (or Direct3D 12) capable GPU; on older machines, launch with `godot --path . --rendering-method gl_compatibility` for the lighter version.
2. Open `project.godot` in the editor and press **F5**, or run from the command line:
   ```sh
   godot --path .
   ```

### Web build

`export_presets.cfg` has a **Web** preset. It is single-threaded, so it runs on ordinary
static hosting without cross-origin isolation headers. Install the Godot 4.7 export
templates, then run:
```sh
godot --headless --path . --export-release Web build/web/index.html
```

## Full screen and phones

- The Modern look fills any screen shape: laptops, ultrawides, and phones in landscape. The race view widens, and menus stay centred. The 1999 look keeps its 4:3 picture.
- In the browser, Start goes full screen (untick it to play in the page). On Android it also locks landscape. A full screen button appears when you move the mouse or touch the bottom middle of the screen. iPhone Safari has no full screen for web pages; the game still fills the page.
- **Fits every screen.** The HUD, menus and touch buttons stay clear of a notch or camera cut-out, rounded corners and the home bar (the page reads the phone's safe area). Menus shrink if they have to, and make room for the on-screen D-pad and A/B buttons. Touch buttons are sized for thumbs: on a tablet or touchscreen laptop they get smaller, so they don't take over the screen. `tests/fit_test.gd` checks every screen on phone, tablet, laptop, ultrawide and tall-window shapes.
- **Touch controls** appear on phones and tablets, and on a touchscreen laptop as soon as you touch it. Using a keyboard or gamepad hides them again.
  - Steer by tilting the device like a wheel. Full lock takes only 12° of tilt (Options → TILT STEERING: 18°, 12°, 9° or 6°). A gentle curve gives fine control near the centre, a small dead zone ignores wobble, and the sensor is smoothed. Wherever you hold it at the start counts as straight ahead; it re-centres after a pause or pit call, or when you tap CTR. You can also drag a thumb anywhere on the left side, where a full lock is about a thumb's width. TILT/DRAG switches between the two.
  - Two round pedals on the right: green GAS and red BRAKE just to its left. Small buttons: II pause, CAM, PIT.
  - Menus, results and replays show a D-pad with A (select) and B (back). The pause screen shows RESUME and QUIT buttons.
  - Tilt needs the motion sensor: iPhone asks permission when you tap Start. The page reads the accelerometer, or the orientation sensor where that's all there is. It works out each phone's sign convention from which edge of the screen is higher. Where the browser or an embedding page blocks the sensor, the game says so and uses drag steering. The installed app isn't embedded, so tilt works there.
- **Native resolution and 120 Hz.** The game renders at the screen's full pixel count, e.g. 2868 × 1320 on a 460 ppi iPhone 16 Pro Max in landscape, so text and the HUD are always pin-sharp. The page measures the display's refresh rate (60, 90, 120 or 144 Hz) and AUTO quality aims for that frame rate.
  - Options → RESOLUTION: **AUTO** keeps native resolution and trims only the 3D scene (down to 50%) if the frame rate can't hold, then restores it when there's headroom. **NATIVE** always renders at 100%, **BALANCED** at 75%, **PERFORMANCE** at 50%. The row shows the screen size, refresh rate and current 3D scale.
  - iPhone and iPad web apps are held to 60 Hz by iOS unless you turn off **Settings → Apps → Safari → Advanced → Feature Flags → Prefer Page Rendering Updates near 60fps**. Android Chrome runs at the full 120 Hz.

## Install it on your phone

`docs/` holds the game built as an installable web app. It has a manifest with icon, an offline cache (service worker), full-screen display and a landscape lock. GitHub Pages serves it:

1. On GitHub: **Settings → Pages → Build and deployment**. Choose **Deploy from a branch**, then the branch holding `docs/` and the **/docs** folder. Save.
2. After a minute the game is at `https://<user>.github.io/nascararcade/`. If Pages serves the repository root rather than `/docs`, the root `index.html` forwards to `docs/`, so the same address works either way.
3. On the phone, open that link.
   - **Android (Chrome):** tap **Install the app** on the start screen, or use the ⋮ menu → **Install app**.
   - **iPhone (Safari):** tap **Share → Add to Home Screen**.
4. It then opens from its own icon: full screen, landscape, and playable offline after the first load.

Phones race in landscape only. Android installs lock to landscape. iPhone can't lock, so holding it upright shows a "turn your phone sideways" card and pauses the race.

Rebuild after changes: export the **Web App** preset (`godot --headless --export-release "Web App" docs/index.html`) and add an empty `docs/.nojekyll`. The page around the game is `web/shell.html`. `web/make_artifact_page.py` builds the single-page variant (engine split into parts) from the plain **Web** export.

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Steer | ← → / A D | Left stick / D-pad |
| Gas | ↑ / W / Z | RT / A |
| Brake / reverse | ↓ / S / X | LT / B |
| Start / select | Enter / Space | Start / A |
| Back (menus) | Backspace | B |
| Change camera (chase, close chase, bumper, cockpit) | C | Y |
| Pause | Esc / P | Back |
| Quit race (while paused) | Q | — |
| Pit this lap / change pit plan (Single Race, Season, Career) | Tab / O | X / D-pad up |
| Choose restart lane at "one to go" | ← / → | Left stick |
| Shift up / down (manual gearbox) | E / Q | RB / LB |
| Watch replay / highlights (results screen) | R / H | Right stick click / — |
| Telemetry overlay | T | Left stick click |
| Photo mode (replay, or mid-race) | F | Touchpad |
| Graphics: Modern / 1999 | F3 | — |
| Toggle scanlines (1999 mode) | F2 | — |
| Fullscreen | F11 | — |

## Project layout

```
project.godot              Forward+ on desktop, Compatibility on web; 640x480 base UI
scenes/main.tscn           single scene; everything else is built in code
scripts/game.gd            autoload: tracks, teams, input, settings, season, career,
                           paint shop, challenges, records, retro/modern materials
scripts/main.gd            state machine, menus, race weekends, cameras, replays, split screen
scripts/menu.gd            reusable arcade-style list menu
scripts/track.gd           track builder (ovals + segment layouts), banking, pit road,
                           AI speed profile, meshes and scenery
scripts/car.gd             Next Gen car: rigid-body physics on the banked surface, tyres,
                           gearbox, damage, fuel/wear, assists, model
scripts/race.gd            field, AI drivers, drafting / dirty air, contact, laps, recording
scripts/race_control.gd    flags, cautions, pace car, pit stops, restarts, stages, points
scripts/hud.gd             HUD (scales to any view size, used twice in split screen)
scripts/audio.gd           AudioStreamGenerator software synth (your own engine, wind, beeps)
scripts/soundscape.gd      3D engines of the cars around you, crowd, echo
scripts/cam_feel.gd        camera weight: g-force head movement and vibration
scripts/cockpit.gd         the interior, dash, wheel and rear-view mirror
scripts/atmosphere.gd      haze, sun shafts, lingering smoke, focus, sun glare
scripts/rain_fx.gd         water film and dry line, spray, drops on the glass
scripts/track_wear.gd      the rubber line, marbles and wall scuffs (also drives grip)
scripts/race_day.gd        pit crews, flagman, crowd reactions, fireworks, burnout
scripts/touch_controls.gd  phone/tablet controls: tilt or drag steering, pedals, menu pad
tests/                     headless test benches and screenshot scripts (see below)
```

### How the physics works

Each car's position is kept in *track space*: distance along the centre line and offset
across the track. Its heading, body-frame velocities and yaw rate are then integrated like
a real vehicle:
- **Tyres:** front and rear forces from slip angles, using a Pacejka-style curve inside a
  friction circle, with load sensitivity.
- **Banking:** the banked surface adds normal load, its slope pulls the car toward the
  inside, and the turn curves less within the tilted road plane.
- **Aero:** downforce and drag, adjusted by the cars around you.

The AI and the optional player assists steer by requesting a yaw rate, which lets them
catch small slides. Hard hits switch that help off, so real wrecks still happen.

## Tests

All tests run headless (`godot --headless --fixed-fps 60 --path . -s <script>`):

| Script | What it checks |
|---|---|
| `tests/smoke_test.gd` | Arcade game flow on every track |
| `tests/weather_test.gd` | Rain on an oval (held under caution until dry) and a road course (wet tyres), and the moving clock |
| `tests/director_test.gd` | Replay director, photo mode and the highlight reel |
| `tests/net_test.gd` | Online: run with ROLE=host and ROLE=client together |
| `tests/wheel_test.gd` | Starts the force-feedback helper and checks it answers |
| `tests/telemetry_test.gd` | Chassis telemetry (roll, tyre loads, temperatures, bump stops) and wreck physics checks |
| `tests/physics_test.gd` | Solo lap speeds, draft gain and a 40-car race per track |
| `tests/field_test.gd` | Full-field AI race with incident tracing (`TRACK=n SECS=s TRACE=car#`) |
| `tests/rules_test.gd` | A full rules race: cautions, pits, stages and points |
| `tests/caution_test.gd` | Quick cautions: the pit call screen, AI pit calls, the restart order, about 15 s yellow to green |
| `tests/race_mode_test.gd` | Single Race through the real game flow |
| `tests/weekend_test.gd` | Practice → qualifying → race, plus a season round |
| `tests/career_test.gd` | Career money, R&D, season rollover |
| `tests/challenge_test.gd` | Every Lightning Challenge reaches a verdict |
| `tests/tracks_test.gd` | Every track builds and laps cleanly |
| `tests/split_shots.gd` | Two-player race (screenshot with `OUT=dir` and a renderer) |

`tests/screenshots.gd`, `tests/menu_shots.gd` and `tests/replay_shots.gd` capture
screenshots when run with a renderer (for example under `xvfb-run`).
`tests/screenshots_modern.sh` does the same with the Forward+ renderer.

In headless mode, Godot's dummy renderer prints `mesh_get_surface_count` errors.
They're harmless and don't appear with a real renderer.

## Notes

All team names, drivers, sponsors and tracks are fictional. The title lives in
`scripts/game.gd` (`TITLE` / `SUBTITLE`) and in the title screen in `scripts/main.gd`
if you want to rename the game.
