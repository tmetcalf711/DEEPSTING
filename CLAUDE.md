# CLAUDE.md: DeepSting

Top-down 2.5D roguelite twin-stick shooter (Binding of Isaac structure), Godot 4.7 / GDScript.
**DESIGN.md is the living GDD.** Read §16 (architecture), §19 (decisions) and §20 (open questions) before changing systems.

## Current status
- **Milestone 0 complete:** GDD, project, autoloads, data/i18n/art scaffolding, GUT, debug console, main menu.
- **Milestone 1 complete:** playable Abandoned Hive floor (procedural layout, combat, 4 enemies + boss, workers/stash/boss shaft, brood rescue, Dig Charges + secret rooms, 12 items, HUD/minimap/pause/death).
- **Next:** Milestone 2 (all special rooms, 40 ch1 templates, room editor, curses, Royal/Den, Trader). Waiting for the user's go-ahead.
- User decisions from the M0 review are in DESIGN.md §20 (hearts + Chitin, Mana chits, Pulp, floor stash, title).
- Work in milestones (DESIGN.md §17). After each one, summarize, list known issues, and stop for review.

## Run / test
```bash
godot --headless --import                 # first time / after adding assets (generates .godot/ and *.translation)
godot                                     # run the game (main scene: scenes/ui/main_menu.tscn)
./tools/run_tests.sh                      # GUT + data validator + headless smoke run (door walk, all rooms, 600-bullet bench)
godot --headless -s res://tools/validate_data.gd   # data validator only
godot --headless -s res://tools/smoke_run.gd       # smoke run only
xvfb-run -a godot --rendering-driver opengl3 --resolution 1280x720 -s res://tools/capture_screens.gd -- /some/dir   # review screenshots
```
- `play.bat` / `play.sh`: end-user launchers (update via git or zip, fetch Godot, import, play). Keep `GODOT_VERSION` in them in sync with the engine version.
- After adding a new `class_name`, run `godot --headless --import` once so the global class cache knows it.
- Headless input in tools: use `Input.action_press/release`, not `parse_input_event`.
- Engine: **Godot 4.7.2 stable** (Compatibility renderer). Set `GODOT=/path/to/godot` for run_tests.sh if it's not on PATH.
- GUT silently *skips* test scripts that fail to parse. `run_tests.sh` greps for that, so always use it.
- Typed GDScript: `:=` cannot infer from untyped calls (e.g. methods on a `Node`-typed var). Annotate explicitly (`var x: int = ...`).
- Don't name methods `_set`/`_get` (they override Object virtuals). Single-line lambdas can't contain `;` statements, so use a method.
- **Never shuffle/mutate an array derived from a `const`** (`Array(CONST_PACKED)` can share storage). It broke floor determinism once: build a fresh array with `append_array`.

## Folder map
```
addons/gut/            vendored GUT (test framework). Don't edit.
assets/sprites/<category>/<id>.png   real art drops in here; missing = procedural placeholder (Art autoload)
assets/audio/{sfx,music}/<id>.ogg    missing = silent no-op (Audio autoload)
data/<category>/**/<id>.json         ALL content; one entry per file; file name == id
scenes/run/run.tscn    the run (RunController); scenes/ui/main_menu.tscn
scripts/autoload/      singletons (see below)
scripts/systems/       pure systems: floor_gen, item_pool, shot_spec, projectile_system, fx, input_bindings
scripts/run/           run_controller.gd (floor, transitions, juice, console cmds), room.gd (tiles, doors, clear/haul/shaft)
scripts/player/        player.gd, effect_host.gd (item effects dispatcher)
scripts/enemies/       enemy.gd (class Enemy) + behaviors/<type>.gd (chase, turret, flyer, swarm, pattern_boss)
scripts/actors/        rock, pickup, pedestal, deposit, worker, larva, brood_cell, dig_charge, trapdoor, loot_pile, familiar
scripts/effects/       one file per item effect `type` (stat_mod, projectile_mod, health, flag, familiar, active)
scripts/effects/abilities/  active item abilities (stun_flash, sunburst)
scripts/ui/            main_menu, hud, minimap, pause_menu, end_screen
tests/unit/test_*.gd   GUT tests
tools/                 validate_data.gd, run_tests.sh, smoke_run.gd, capture_screens.gd, room editor (M2)
translations/strings.csv   every player-facing string (keys,en,...)
```

## Autoloads (load order)
`Events` (signal bus) → `RNG` (seeded streams) → `Platform` (Steam wrapper, stubs) → `MetaSave` (meta/settings/run saves) → `Content` (data registry) → `Art` (sprite resolver) → `Audio` → `GameState` (app state, settings, input) → `RunState` (current run data) → `DebugConsole` (backtick, dev builds only).

## Conventions (must follow)
- **Determinism:** never call global `randf()/randi()/randomize()` or `Array.shuffle()/pick_random()` in gameplay. Use `RNG.stream("<name>")`, `RNG.room_stream(...)`, `RNG.shuffle(r, arr)`, `RNG.weighted_index(r, weights)`. Visual-only randomness uses the `fx` stream.
- **Coordinates:** 16 px tiles; a room interior is 13×7 tiles (208×112) at room-local (0,0). The camera zooms 2× on a 640×360 canvas.
- **Health/consumables:** all health is in half-hearts (`RunState.hearts`, `shields` = ["chitin"|"toxic"]). Mana = coins, Dig Charges = bombs, Royal Jelly = keys.
- **Economy:** hauls go to `RunState.floor_stash` (lost on death) and are banked as Pulp via `RunState.bank_stash()` when the boss-shaft haul finishes. Brood rescues bank immediately (`MetaSave.rescue_lost_brood`).
- **Content is data:** add items, enemies, rooms etc. as JSON in `/data`. Never branch on specific ids in gameplay code (`if item == "x"` is forbidden). New behavior = a new effect `type` script in `scripts/effects/` (with `const PERSISTENT` + `static func apply`), a new enemy `behavior.type` script, or a new ability script.
- **Room templates:** 13×7 grid chars `. R T # X S B D P` (floor, rock, tinted rock, block, pit, spikes, brood cell, deposit slot, pedestal). `room_types` says which room kinds can use a template, and the `brood_cell` tag is required for rooms hosting sealed cells. Door entry lanes must stay walkable (validator enforces).
- **Adding a data category or required field:** update `Content.SCHEMA` (and `validate()` for extra rules), then add a test.
- **Strings:** all UI text goes through `tr("KEY")`, with the key added to `translations/strings.csv`. Data files reference `*_key` fields, never literal text.
- **Art:** always `Art.texture(category, id)`. Never `load()` sprite paths directly.
- **Signals:** cross-system communication goes through `Events`. Declare typed signals there.
- **Saves:** bump `MetaSave.META_VERSION` and add a `_migrate_meta_vN_to_vN+1` step plus a test when the save shape changes. Anything that "banks immediately" (hauls, brood) calls `save_meta()` on the event.
- **Input:** actions are defined in `scripts/systems/input_bindings.gd` (not project.godot). Add new actions to `DEFAULTS`.
- **Console:** systems register commands with `DebugConsole.register(name, callable, usage)`. Stubs for future milestones live in `_register_builtins()`. Replace them when the system lands.
- **No copyrighted names/art/text** from other games anywhere in game files.
- Commit after each completed milestone or coherent step. Keep DESIGN.md §19 (decisions) updated when you resolve an ambiguity.

## Export notes (M8)
- Export presets must add `data/*` to the non-resource include filter (JSON isn't an imported resource).
- `Platform` is the only place Steam is touched. GodotSteam lands in M8.
