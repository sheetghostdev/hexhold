# Hexhold

**Roads · Walls · Conquest.** A turn-based strategy game on hexagons: Polytopia's
quick, readable 4X turns mixed with Stronghold's castles, walls and economy.
It's built for phones, and you play with friends by **sending each other a link on Discord**.

Made with Godot 4.7 (GDScript, Compatibility renderer so it runs in phone browsers).
The world is **3D low-poly** in bright colours, like Polytopia: hex tiles, trees,
mountains, castles, walls and little soldiers, all generated in code with flat-shaded
procedural meshes. There are no model, image or audio files to manage.

## How a game with your brothers works

1. Someone opens Hexhold and picks **New game → Send turns by link**, then adds the players.
2. They play their turn and press **End turn**. The game shows **Share to Discord…**
   (or **Copy link**). Post it in your Discord chat.
3. Whoever's turn it is taps the link. The game opens in their browser right where
   it left off, shows what happened since their last turn, and they play.
4. Repeat. Nobody needs to be online at the same time, there's no server, and every
   game is also saved on each phone under **Continue**.

The whole game state is packed into the link: about 450 characters at the start and
under 1,400 even in big late games, so it fits in a Discord message.

**Pass & play** (one phone passed around) and **computer opponents** are supported too.

## Features

- **Hex map**, procedurally generated with fair starting positions, villages,
  ruins, bandit camps, fertile soil, stone and gold veins.
- **Roads you draw with your finger.** Tap *Road* and drag across tiles. Roads
  join up automatically into a clean network. Road-to-road moves cost half,
  bridges cross water, and a road from a town to your capital is a **trade route**
  (+1 gold per turn).
- **Stronghold-style walls.** Tap *Wall* and drag. Walls join up with crenellations,
  block enemies, and give your own troops on them double defence. Archers on walls
  shoot further. **Towers** shoot the nearest enemy every turn. **Catapults**
  ignore fortifications and smash them.
- **Economy:** gold, wood and stone. Farms grow towns, lumber camps and quarries
  feed construction, and markets earn gold from their neighbours (so layout matters).
  Soldiers draw wages, you can throw **feasts** to grow towns faster, and taxes
  can be set to Generous, Fair or Harsh.
- **Keep upgrades:** Wooden Keep → Stone Keep → Castle unlock new troops and buildings.
- **Units:** Spearman (anti-cavalry), Archer, Swordsman, Knight (fast), Catapult (siege).
  Units become veterans after 3 kills. Bandits guard loot.
- **Phone-first UI:** big buttons, a battle forecast before every attack, Undo,
  and a "what happened while you were away" summary each turn.
- **Two victory modes:** Conquest, or Glory (highest score after 30 turns).

## Put it online (free, about 5 minutes)

Links only work when the game is hosted on the web. GitHub Pages is free:

1. Create a GitHub repository (e.g. `hexhold`) and push this folder to the `main` branch.
2. In the repo, go to **Settings → Pages → Build and deployment → Source** and choose **GitHub Actions**.
3. The included workflow (`.github/workflows/deploy.yml`) runs the tests, exports the
   web build and publishes it. Your game will be at
   `https://<your-username>.github.io/hexhold/`.
4. Open that address on your phone and tap *Add to Home screen* if you like.

Every push to `main` redeploys. Turn links point at whatever address the game was
opened from, so they work automatically on any host.

Other hosts: any static host works (Netlify, Cloudflare Pages, your own server).
Upload the contents of `build/web/`. itch.io also works, but because it runs games
inside a frame, links can't jump straight into a turn. Players use
**Open turn link** in the menu and paste instead.

## Run it locally

- Open the folder in **Godot 4.7** and press Play. Mouse controls: left-click to tap,
  left-drag to pan (or paint roads and walls), wheel to zoom, right-drag to pan.
- Web build: `godot --headless --export-release "Web" build/web/index.html`, then serve
  `build/web` with any static server (e.g. `python3 -m http.server -d build/web`).
- Tests (rules, save links, AI-vs-AI games):
  `godot --headless --script res://tests/run_tests.gd`
- Add `?debug` to the web address to enable `window.hexDebug()`, which reports
  where tiles and units are on screen (used for automated UI tests).

## Project layout

| File | What it does |
| --- | --- |
| `src/defs.gd` | All numbers: units, buildings, costs, colours. **Tweak balance here.** |
| `src/game_state.gd` | The rules: movement, combat, building, economy, turns, victory. No UI code. |
| `src/mapgen.gd` | Map generation. |
| `src/codec.gd` | Packs a game into a compact URL-safe code (binary + deflate + base64url). |
| `src/ai.gd` | Computer opponent. |
| `src/board.gd` | The 3D map: batches terrain, roads, walls, towns, units, clouds and effects; tilted orthographic camera with pan and pinch-zoom. |
| `src/lowpoly.gd` | Builds every low-poly mesh in code (tiles, trees, castle, units, ...). |
| `src/game_screen.gd` | Touch input, camera, actions, undo, animations, turn hand-off. |
| `src/hud.gd` | In-game UI: resource bar, context card, toolbar, pop-ups. |
| `src/menu.gd` | Title screen, new game setup, saved games, opening links. |
| `src/net.gd` | Browser glue: reading the link, share sheet, clipboard. |
| `src/storage.gd` | Local saves and settings. |
| `src/sfx.gd` | Synthesized sound effects. |
| `src/ui/*` | Theme, 2D UI icons and help text. |

## Ideas for later

- A Discord bot or webhook that posts "your turn" automatically.
- Animated replay of the opponent's moves.
- More unit types (boats, siege towers), wonders, and a simple tech tree.
- Android build (Godot exports APKs directly).

Fonts: Cinzel and Nunito, both under the SIL Open Font License (see `fonts/`).
