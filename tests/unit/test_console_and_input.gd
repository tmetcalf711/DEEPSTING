extends GutTest

const ConsoleScript := preload("res://scripts/autoload/debug_console.gd")


func test_parse_line_quotes() -> void:
	assert_eq(ConsoleScript.parse_line('give "raw geode" 2'), PackedStringArray(["give", "raw geode", "2"]))
	assert_eq(ConsoleScript.parse_line("   "), PackedStringArray())


func test_unknown_command() -> void:
	assert_string_contains(DebugConsole.execute("nope"), "Unknown command")


func test_help_lists_required_commands() -> void:
	var out := DebugConsole.execute("help")
	for c in ["give", "spawn", "goto", "seed", "god", "reveal", "unlock_all", "bank", "room"]:
		assert_string_contains(out, c)


func test_seed_command_round_trip() -> void:
	var s := RNG.seed_to_string(0x0BADF00D)
	DebugConsole.execute("seed " + s)
	assert_eq(RNG.run_seed, 0x0BADF00D)


func test_god_toggles() -> void:
	var before := GameState.god_mode
	DebugConsole.execute("god")
	assert_ne(GameState.god_mode, before)
	DebugConsole.execute("god")


func test_input_actions_registered() -> void:
	for action in InputBindings.DEFAULTS:
		assert_true(InputMap.has_action(action), action)
		assert_gt(InputMap.action_get_events(action).size(), 0, action)


func test_binding_descriptor_round_trip() -> void:
	for desc in [{"key": "W"}, {"mouse": 1}, {"joy_button": 0}, {"joy_axis": 2, "dir": -1}]:
		var ev := InputBindings.descriptor_to_event(desc)
		assert_not_null(ev)
		assert_eq(InputBindings.event_to_descriptor(ev), desc)
