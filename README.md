# DeepSting (working title)

*Stung too deep.* A top-down 2.5D roguelite bullet-hell shooter. You're a yellowjacket digging the colony down through the world's most polluted basin.

- **Design:** [DESIGN.md](DESIGN.md) (living GDD)
- **Dev guide:** [CLAUDE.md](CLAUDE.md) (conventions, run/test, folder map)
- **Engine:** Godot 4.7.2 (Compatibility renderer), GDScript

## Play

**Easiest: the launcher.** Copy `play.bat` (Windows) or `play.sh` (macOS / Linux) anywhere, e.g. your Desktop, and run it (`chmod +x play.sh` once on macOS / Linux). Every time you run it, it pulls the latest version of the game into a `DeepSting` folder next to it, downloads Godot 4.7.2 the first time if it can't find it, imports the assets and starts the game. It uses [Git](https://git-scm.com) if you have it, and otherwise downloads the latest zip. Your saves are never touched by updates (`%APPDATA%\DeepSting` on Windows, `~/.local/share/DeepSting` on Linux, `~/Library/Application Support/DeepSting` on macOS).

The launcher follows the repository's default branch. To pin a branch, set `BRANCH` near the top of the file. To use your own Godot, set the `GODOT` environment variable to its path.

Or by hand:
```bash
godot --headless --import   # first run
godot                       # play
./tools/run_tests.sh        # tests + data validation + smoke run
```

Status: **Milestone 3: item & synergy system.** 61 items, knick-knacks, fossils, Strange Fluids, radiation mutations, and a dev Synergy Lab. Previously: **Milestone 2: chapter 1 playable.** The Abandoned Hive → Topsoil, with every special room (shop, Royal Chamber / Mutation Den, sacrifice altar, challenge, mini-boss, curse room, vault, arcade, library), big rooms, curses, and an in-engine room editor (main menu → Room Editor in dev builds).

## Controls (defaults)
| | Keyboard | Gamepad |
|---|---|---|
| Move | WASD | Left stick |
| Shoot | Arrow keys (or hold LMB to aim with the mouse) | Right stick |
| Dash | Shift / RMB | RB |
| Active item | Space | RT |
| Dig Charge | E | LB |
| Use fossil / fluid | Q | LT |
| Pause | Esc | Start |
| Debug console (dev builds) | ` | |
