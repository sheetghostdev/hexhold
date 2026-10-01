# Hexhold

**Build · Power · Battle.** A quick 1v1 strategy game on a small hex map, set in the
near future. Build a base, keep the power on, gather Alloy and Fuel, and destroy the
enemy Home Base. A match takes about 10 minutes. It's made for phones, and you play a
friend by **sending them an invite link on Discord**.

Made with Godot 4.7 (GDScript, Compatibility renderer so it runs in phone browsers).
Low-poly 3D in bright colours. All models are simple placeholders generated in code.

## Playing

- **Play a friend online:** you get an invite link (share it to Discord or copy it).
  The match starts when your friend opens it. Keep your page open: your browser runs
  the match. Each turn has a 60 second clock.
- **Quick match vs AI:** play the computer, no clock.
- **Win:** destroy the enemy Home Base. After 12 turns each, the higher score wins.
  At the end, **Rematch** starts a new map right away.

### Rules in short

- **Start:** Home Base, Power Plant, Barracks, an Engineer and a Rifleman, 12 Alloy and 12 Fuel.
- **Territory** is the area around your buildings (2 hexes around the Home Base, 1 around
  other buildings). Tap an empty hex in it to build: Power, Production, Economy, Defense.
  You get a preview first. Buildings take 1 to 3 turns.
- **Power:** buildings use power, Power Plants make it. If you need more than you make,
  your **newest** buildings switch off until the rest fits (red bolt). Switched-off
  buildings can't train, shoot or drill.
- **Resources:** Alloy comes from rocks, Fuel from trees. An Engineer clears a tree or rock
  hex over a few turns and collects what's left; then you can build there. Drills pull
  1 per turn from every neighbouring tree or rock hex. Engineers can also build outside
  your territory, next to themselves.
- **Units:** Rifleman, Sniper (range 3), Tank (wrecks buildings), Engineer.
  **Research** at the Home Base: Power Grid, Composite Armor, Recon Drones, AP Rounds.
- **Fog of war:** you only see what your units and buildings see. At the start of your
  turn you watch a replay of the enemy actions you saw (Skip / 2x).

## How online play works

The host's browser runs the match (`MatchHost`) and is the only one with the full state.
Each player gets **only what they may know**: a view without hidden units, buildings,
terrain or enemy stockpiles, and only the events they saw (tagged with who could see
them at the moment they happened). Players connect directly browser-to-browser (WebRTC
via [PeerJS](https://peerjs.com) and its free public signalling server), so there is no
server of our own. `src/rts/net_peer.gd` is the only transport-specific file, so a relay
server (e.g. Cloudflare Workers) can replace it if some networks can't connect directly.

## Balancing (data files)

Everything numeric lives in Godot resource files you can edit in the Godot inspector or
any text editor:

| Folder / file | What |
| --- | --- |
| `data/rules.tres` | map size, starting stockpile, Home Base income, turn timer, turn limit, army cap, terrain mix |
| `data/units/*.tres` | hp, attack, defense, move, range, vision, costs |
| `data/buildings/*.tres` | category, costs, build time, power made/used, territory, turret stats, what it trains |
| `data/obstacles/*.tres` | trees/rocks: resource, amount, turns to clear, cover |
| `data/upgrades/*.tres` | research: costs, turns, effects like `{"tank.attack": 1.0}` |

## Put it online

GitHub Pages: push to `main`; the workflow (`.github/workflows/deploy.yml`) runs the
tests, exports the web build and publishes it to `https://<user>.github.io/hexhold/`.
Any static host works (upload `build/web/`).

## Run it locally

- Open the folder in **Godot 4.7** and press Play (mouse: click to tap, drag to pan,
  wheel to zoom).
- Web build: `godot --headless --export-release "Web" build/web/index.html`, then serve
  `build/web` (e.g. `python3 -m http.server -d build/web`).
- Tests: `godot --headless --script res://tests/test_match.gd` (rules, power, gathering,
  research, fog of war never leaking hidden data, AI-vs-AI matches) and
  `res://tests/check.gd` (every script parses).
- Debug URL options: `?debug` (test hooks), `&seed=N` (fixed map vs AI),
  `&peerhost=127.0.0.1&peerport=9000&peerlib=peerjs.min.js` (local PeerJS server).

## Project layout

| Path | What it does |
| --- | --- |
| `src/rts/match_state.gd` | the rules: state, commands → events, fog tagging, views |
| `src/rts/match_gen.gd` | mirror-fair map and starting bases |
| `src/rts/match_ai.gd` | computer player (uses the same commands as people) |
| `src/rts/match_host.gd` | the authority: applies commands, sends each player only their share |
| `src/rts/*_link.gd`, `net_peer.gd` | vs AI / online host / online guest, WebRTC transport |
| `src/rts/match_screen.gd`, `match_hud.gd`, `match_board.gd` | input, UI, 3D board, replay |
| `src/rts/mil_meshes.gd`, `mil_icons.gd` | placeholder 3D models and UI icons |
| `src/rts/defs/*.gd`, `src/rts/db.gd` | data definitions and loader |
| `src/menu.gd`, `src/main.gd` | title menu, lobby, joining by link |
