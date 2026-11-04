# CLAUDE.md: DeepSting

Top-down 2.5D roguelite twin-stick shooter (Binding of Isaac structure), Godot 4.7 / GDScript.
**DESIGN.md is the living GDD.** Read §16 (architecture), §19 (decisions) and §20 (open questions) before changing systems.

## Current status
- **Milestone 0 complete:** GDD, project, autoloads, data/i18n/art scaffolding, GUT, debug console, main menu.
- **Next:** Milestone 1 (vertical slice on the Abandoned Hive floor). Waiting for the user's go-ahead.
- Work in milestones (DESIGN.md §17). After each one, summarize, list known issues, and stop for review.

## Run / test
```bash
godot --headless --import                 # first time / after adding assets (generates .godot/ and *.translation)
godot                                     # run the game (main scene: scenes/ui/main_menu.tscn)
./tools/run_tests.sh                      # GUT suite + data validator; non-zero exit on any failure or script parse error
godot --headless -s res://tools/validate_data.gd   # data validator only
```
- Engine: **Godot 4.7.2 stable** (Compatibility renderer). Set `GODOT=/path/to/godot` for run_tests.sh if it's not on PATH.
- GUT silently *skips* test scripts that fail to parse. `run_tests.sh` greps for that, so always use it.
- Typed GDScript: `:=` cannot infer from untyped calls (e.g. methods on a `Node`-typed var). Annotate explicitly (`var x: int = ...`).

## Folder map
```
addons/gut/            vendored GUT (test framework). Don't edit.
assets/sprites/<category>/<id>.png   real art drops in here; missing = procedural placeholder (Art autoload)
assets/audio/{sfx,music}/<id>.ogg    missing = silent no-op (Audio autoload)
data/<category>/**/<id>.json         ALL content; one entry per file; file name == id
scenes/{player,enemies,rooms,ui,hive}
scripts/autoload/      singletons (see below)
scripts/systems/       non-node systems (input_bindings.gd, later floorgen, pools, projectiles)
scripts/components/    reusable node components (hurtbox, health, etc.), M1+
scripts/effects/       item effect implementations, one file per effect `type`, M1+
scripts/ui/            UI scripts
tests/unit/test_*.gd   GUT tests
tools/                 validate_data.gd, run_tests.sh, room editor (M2)
translations/strings.csv   every player-facing string (keys,en,...)
```

## Autoloads (load order)
`Events` (signal bus) → `RNG` (seeded streams) → `Platform` (Steam wrapper, stubs) → `MetaSave` (meta/settings/run saves) → `Content` (data registry) → `Art` (sprite resolver) → `Audio` → `GameState` (app state, settings, input) → `RunState` (current run data) → `DebugConsole` (backtick, dev builds only).

## Conventions (must follow)
- **Determinism:** never call global `randf()/randi()/randomize()` or `Array.shuffle()/pick_random()` in gameplay. Use `RNG.stream("<name>")`, `RNG.room_stream(...)`, `RNG.shuffle(r, arr)`, `RNG.weighted_index(r, weights)`. Visual-only randomness uses the `fx` stream.
- **Content is data:** add items, enemies, rooms etc. as JSON in `/data`. Never branch on specific ids in gameplay code (`if item == "x"` is forbidden). New behavior = a new effect `type` script in `scripts/effects/`.
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
