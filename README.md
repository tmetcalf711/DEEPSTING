# DeepSting (working title)

*Stung too deep.* A top-down 2.5D roguelite bullet-hell shooter. You're a yellowjacket digging the colony down through the world's most polluted basin.

- **Design:** [DESIGN.md](DESIGN.md) (living GDD)
- **Dev guide:** [CLAUDE.md](CLAUDE.md) (conventions, run/test, folder map)
- **Engine:** Godot 4.7.2 (Compatibility renderer), GDScript

```bash
godot --headless --import   # first run
godot                       # play
./tools/run_tests.sh        # tests + data validation
```

Status: **Milestone 1: playable vertical slice** (one Abandoned Hive floor).

## Controls (defaults)
| | Keyboard | Gamepad |
|---|---|---|
| Move | WASD | Left stick |
| Shoot | Arrow keys (or hold LMB to aim with the mouse) | Right stick |
| Dash | Shift / RMB | RB |
| Active item | Space | RT |
| Dig Charge | E | LB |
| Pause | Esc | Start |
| Debug console (dev builds) | ` | |
