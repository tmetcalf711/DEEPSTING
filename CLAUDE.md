# CLAUDE.md: DeepSting

Top-down 2.5D roguelite twin-stick shooter (Binding of Isaac structure), Godot 4.7 / GDScript.
**DESIGN.md is the living GDD.** Read §16 (architecture), §19 (decisions) and §20 (open questions) before changing systems.

## Current status
- **Milestone 0 complete:** GDD, project, autoloads, data/i18n/art scaffolding, GUT, debug console, main menu.
- **Milestone 1 complete:** playable Abandoned Hive floor (procedural layout, combat, 4 enemies + boss, workers/stash/boss shaft, brood rescue, Dig Charges + secret rooms, 12 items, HUD/minimap/pause/death).
- **Milestone 2 complete:** chapter 1 = Abandoned Hive → Topsoil; shaped rooms (1x1/2x1/1x2/2x2), every special room, Royal/Den deals, Royal Jelly locks, curses, 51 templates, in-engine room editor.
- **Milestone 3 complete:** 61 items, 15 knick-knacks, 10 fossils, 12 Strange Fluids, 12 mutations; event triggers, on-hit procs, auras, orbital/biter familiars, multishot/boomerang/wave; radiation meter + mutation picker; Synergy Lab.
- **Next:** Milestone 4 (full descent: chapters 1–4 + alternates, 3 bosses per chapter, champions, difficulty curve, first ending). Waiting for the user's go-ahead.
- User decisions from the M0 review are in DESIGN.md §20 (hearts + Chitin, Mana chits, Pulp, floor stash, title).
- Work in milestones (DESIGN.md §17). After each one, summarize, list known issues, and stop for review.

## Run / test
```bash
godot --headless --import                 # first time / after adding assets (generates .godot/ and *.translation)
godot                                     # run the game (main scene: scenes/ui/main_menu.tscn)
./tools/run_tests.sh                      # GUT + data validator + headless smoke run (door walk, both floors, every special room, curses, bullet bench)
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
scripts/systems/       pure systems: floor_gen (layout), floor_contents (what's in each room), item_pool, shot_spec, projectile_system, fx, input_bindings
scripts/run/           run_controller.gd (floors/chapters, curses, deals, transitions, camera, console cmds), room.gd (tiles, door slots, clear/haul/shaft, creep)
scripts/run/specials/  one script per special room type (shop, den, royal, sacrifice, challenge, miniboss, curse, vault, arcade)
scripts/player/        player.gd, effect_host.gd (item effects dispatcher)
scripts/enemies/       enemy.gd (class Enemy: statuses, burrowing, splitting) + behaviors/<type>.gd (chase, turret, flyer, swarm, burrow, charger, creep, pattern_boss)
scripts/actors/        rock, pickup, pedestal, ware, arcade_machine, deposit, worker, larva, brood_cell, dig_charge, trapdoor, loot_pile, familiar
scripts/tools/         room_editor.gd (scene: tools/room_editor.tscn), synergy_lab.gd (lab panel; main menu buttons in dev builds)
scripts/effects/       one file per effect `type` (stat_mod, projectile_mod, proc, trigger, aura, familiar, flag, health, consumables, active, ability, perma_stat, room_stat, radiation)
scripts/effects/abilities/  abilities used by actives/fossils/fluids (stun_flash, sunburst, reveal_map, volley, shatter_rocks, teleport)
scripts/ui/            main_menu, hud, minimap, pause_menu, end_screen, darkness (Cave-in curse)
tests/unit/test_*.gd   GUT tests
tools/                 validate_data.gd, check_scripts.gd (every script parses + menu boots), run_tests.sh, smoke_run.gd, capture_screens.gd, room editor
translations/strings.csv   every player-facing string (keys,en,...)
```

## Autoloads (load order)
`Events` (signal bus) → `RNG` (seeded streams) → `Platform` (Steam wrapper, stubs) → `MetaSave` (meta/settings/run saves) → `Content` (data registry) → `Art` (sprite resolver) → `Audio` → `GameState` (app state, settings, input) → `RunState` (current run data) → `DebugConsole` (backtick, dev builds only).

## Conventions (must follow)
- **Determinism:** never call global `randf()/randi()/randomize()` or `Array.shuffle()/pick_random()` in gameplay. Use `RNG.stream("<name>")`, `RNG.room_stream(...)`, `RNG.shuffle(r, arr)`, `RNG.weighted_index(r, weights)`. Visual-only randomness uses the `fx` stream.
- **Coordinates:** 16 px tiles; a room interior is 13×7 tiles (208×112) at room-local (0,0). The camera zooms 2× on a 640×360 canvas.
- **Health/consumables:** all health is in half-hearts (`RunState.hearts`, `shields` = ["chitin"|"toxic"]). Mana = coins, Dig Charges = bombs, Royal Jelly = keys.
- **Effects:** everything owned (items, active, knick-knack, mutations) is a source in `EffectHost.rebuild()`. Hooks are `trigger` effects (events: kill, room_clear, floor_start, damage_taken → `EffectHost.do_action`); on-hit is `proc` effects (resolved in `ProjectileSystem._hit_target`). Fluids map colors→effects per run (`EffectHost.ensure_fluid_map`). Radiation: `RunState.add_radiation`; the mutation pick appears at room clear.
- **Tools (headless `-s` scripts):** don't reference project `class_name`s that use autoloads (e.g. `EffectHost`) by name; `load()` them by path. The script compiles before autoloads exist.
- **Economy:** hauls go to `RunState.floor_stash` (lost on death) and are banked as Pulp via `RunState.bank_stash()` when the boss-shaft haul finishes. Brood rescues bank immediately (`MetaSave.rescue_lost_brood`).
- **Content is data:** add items, enemies, rooms etc. as JSON in `/data`. Never branch on specific ids in gameplay code (`if item == "x"` is forbidden). New behavior = a new effect `type` script in `scripts/effects/` (with `const PERSISTENT` + `static func apply`), a new enemy `behavior.type` script, a new ability script, or a new special-room script in `scripts/run/specials/<type>.gd`.
- **Debug console (backtick):** `give`, `spawn`, `goto <floor|room type>`, `room <template>`, `curse <id|none>`, `deal royal|den`, `mana <n>`, `jelly <n>`, `heal`, `reveal`, `god`, `seed`, `bank`, `unlock_all`.
- **Floors:** `RunController.floor_plan()` reads `config/floorgen.chapters`. Rooms are keyed by their anchor cell; doors are wall slots `"ox,oy,D"` with links `slot -> [anchor, slot]`, stored on BOTH sides (mirror flags with `RunController.mirror_door_flag`). Door kinds: normal, secret, locked, spiked, challenge, deal.
- **Room-local queries:** use `room.room_enemies()` / `room.is_ancestor_of(n)`, never raw group lists (a room being freed can still be in the tree for a frame).
- **Room templates:** big rooms are 26×7 (2x1), 13×14 (1x2) or 26×14 (2x2) tiles; `stratum: ["*"]` = shared (special rooms). 13×7 grid chars `. R T # X S B D P` (floor, rock, tinted rock, block, pit, spikes, brood cell, deposit slot, pedestal). `room_types` says which room kinds can use a template, and the `brood_cell` tag is required for rooms hosting sealed cells. Door entry lanes must stay walkable (validator enforces).
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
