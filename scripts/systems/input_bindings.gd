class_name InputBindings
extends RefCounted
## Default input map, defined in code (DESIGN.md D12) and applied at boot by GameState.
## Rebinding: settings.controls.bindings[action] = [event descriptors] overrides the defaults.
##
## Event descriptor format (JSON-friendly):
##   {"key": "W"}                       keyboard (physical keycode name)
##   {"mouse": 1}                       mouse button index
##   {"joy_button": 0}                  gamepad button index (JoyButton)
##   {"joy_axis": 0, "dir": -1}         gamepad axis (JoyAxis) and direction

const DEADZONE := 0.25

const DEFAULTS: Dictionary = {
	"move_up": [{"key": "W"}, {"joy_axis": JOY_AXIS_LEFT_Y, "dir": -1}, {"joy_button": JOY_BUTTON_DPAD_UP}],
	"move_down": [{"key": "S"}, {"joy_axis": JOY_AXIS_LEFT_Y, "dir": 1}, {"joy_button": JOY_BUTTON_DPAD_DOWN}],
	"move_left": [{"key": "A"}, {"joy_axis": JOY_AXIS_LEFT_X, "dir": -1}, {"joy_button": JOY_BUTTON_DPAD_LEFT}],
	"move_right": [{"key": "D"}, {"joy_axis": JOY_AXIS_LEFT_X, "dir": 1}, {"joy_button": JOY_BUTTON_DPAD_RIGHT}],
	"shoot_up": [{"key": "Up"}, {"joy_axis": JOY_AXIS_RIGHT_Y, "dir": -1}],
	"shoot_down": [{"key": "Down"}, {"joy_axis": JOY_AXIS_RIGHT_Y, "dir": 1}],
	"shoot_left": [{"key": "Left"}, {"joy_axis": JOY_AXIS_RIGHT_X, "dir": -1}],
	"shoot_right": [{"key": "Right"}, {"joy_axis": JOY_AXIS_RIGHT_X, "dir": 1}],
	"shoot_mouse": [{"mouse": MOUSE_BUTTON_LEFT}],
	"dash": [{"key": "Shift"}, {"mouse": MOUSE_BUTTON_RIGHT}, {"joy_button": JOY_BUTTON_RIGHT_SHOULDER}],
	"use_active": [{"key": "Space"}, {"joy_axis": JOY_AXIS_TRIGGER_RIGHT, "dir": 1}],
	"dig_charge": [{"key": "E"}, {"joy_button": JOY_BUTTON_LEFT_SHOULDER}],
	"use_consumable": [{"key": "Q"}, {"joy_axis": JOY_AXIS_TRIGGER_LEFT, "dir": 1}],
	"swap_consumable": [{"key": "Ctrl"}, {"joy_button": JOY_BUTTON_BACK}],
	"map": [{"key": "Tab"}, {"joy_button": JOY_BUTTON_LEFT_STICK}],
	"pause": [{"key": "Escape"}, {"joy_button": JOY_BUTTON_START}],
	"ui_accept_alt": [{"key": "Enter"}, {"joy_button": JOY_BUTTON_A}],
	"debug_console": [{"key": "QuoteLeft"}],
}


static func apply(overrides: Dictionary = {}) -> void:
	for action in DEFAULTS:
		var events: Array = overrides.get(action, DEFAULTS[action])
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, DEADZONE)
		for desc in events:
			var ev := descriptor_to_event(desc)
			if ev:
				InputMap.action_add_event(action, ev)


static func descriptor_to_event(desc: Dictionary) -> InputEvent:
	if desc.has("key"):
		var k := InputEventKey.new()
		k.physical_keycode = OS.find_keycode_from_string(str(desc["key"]))
		if k.physical_keycode == KEY_NONE:
			push_warning("InputBindings: unknown key '%s'" % desc["key"])
			return null
		return k
	if desc.has("mouse"):
		var m := InputEventMouseButton.new()
		m.button_index = int(desc["mouse"]) as MouseButton
		return m
	if desc.has("joy_button"):
		var b := InputEventJoypadButton.new()
		b.button_index = int(desc["joy_button"]) as JoyButton
		return b
	if desc.has("joy_axis"):
		var a := InputEventJoypadMotion.new()
		a.axis = int(desc["joy_axis"]) as JoyAxis
		a.axis_value = 1.0 if int(desc.get("dir", 1)) > 0 else -1.0
		return a
	return null


static func event_to_descriptor(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var kc: Key = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
		return {"key": OS.get_keycode_string(kc)}
	if ev is InputEventMouseButton:
		return {"mouse": int(ev.button_index)}
	if ev is InputEventJoypadButton:
		return {"joy_button": int(ev.button_index)}
	if ev is InputEventJoypadMotion:
		return {"joy_axis": int(ev.axis), "dir": 1 if ev.axis_value > 0.0 else -1}
	return {}
