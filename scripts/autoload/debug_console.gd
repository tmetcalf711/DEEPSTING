extends CanvasLayer
## Developer console (DESIGN.md §16.9). Toggle with backtick. Disabled in release builds.
## Systems register their own commands:
##     DebugConsole.register("spawn", _cmd_spawn, "spawn <enemy> [n]")
## A handler receives PackedStringArray args and returns a String to print.

const MAX_LINES := 200

var enabled: bool = false
var _commands: Dictionary = {}  # name -> {fn: Callable, usage: String}
var _history: PackedStringArray = []
var _history_pos: int = -1
var _panel: PanelContainer
var _log: RichTextLabel
var _input: LineEdit


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = OS.is_debug_build()
	_build_ui()
	_panel.visible = false
	_register_builtins()
	Events.debug_message.connect(print_line)


func register(cmd: String, fn: Callable, usage: String = "") -> void:
	_commands[cmd] = {"fn": fn, "usage": usage if usage != "" else cmd}


func has_command(cmd: String) -> bool:
	return _commands.has(cmd)


## Runs a command line and returns its output (also used by tests).
func execute(line: String) -> String:
	var parts := parse_line(line)
	if parts.is_empty():
		return ""
	var cmd := parts[0].to_lower()
	var args := parts.slice(1)
	if not _commands.has(cmd):
		return "Unknown command '%s'. Type 'help'." % cmd
	var result: Variant = _commands[cmd]["fn"].call(args)
	return str(result) if result != null else ""


## Splits on whitespace, honoring "double quotes".
static func parse_line(line: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var cur := ""
	var quoted := false
	for ch in line.strip_edges():
		if ch == "\"":
			quoted = not quoted
		elif ch == " " and not quoted:
			if cur != "":
				out.append(cur)
				cur = ""
		else:
			cur += ch
	if cur != "":
		out.append(cur)
	return out


func print_line(text: String) -> void:
	if _log == null:
		return
	_log.append_text(text + "\n")
	if _log.get_paragraph_count() > MAX_LINES:
		_log.remove_paragraph(0)


func toggle() -> void:
	if not enabled:
		return
	_panel.visible = not _panel.visible
	if _panel.visible:
		_input.grab_focus()
		_input.clear()


func _unhandled_input(event: InputEvent) -> void:
	if enabled and event.is_action_pressed("debug_console"):
		toggle()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 0.45
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.03, 0.88)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	_panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	_panel.add_child(vb)
	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	_log.bbcode_enabled = false
	_log.add_theme_font_size_override("normal_font_size", 8)
	vb.add_child(_log)
	_input = LineEdit.new()
	_input.placeholder_text = "command  (help)"
	_input.add_theme_font_size_override("font_size", 8)
	_input.text_submitted.connect(_on_submit)
	_input.gui_input.connect(_on_input_gui)
	vb.add_child(_input)
	add_child(_panel)


func _on_submit(text: String) -> void:
	if text.strip_edges() == "":
		return
	_history.append(text)
	_history_pos = -1
	print_line("> " + text)
	var out := execute(text)
	if out != "":
		print_line(out)
	_input.clear()


func _on_input_gui(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.is_action("debug_console"):
			toggle()
			_input.accept_event()
		elif event.keycode == KEY_UP and not _history.is_empty():
			_history_pos = _history.size() - 1 if _history_pos < 0 else maxi(0, _history_pos - 1)
			_input.text = _history[_history_pos]
			_input.caret_column = _input.text.length()
			_input.accept_event()


# ---------------------------------------------------------------- built-in commands

func _register_builtins() -> void:
	register("help", _cmd_help, "help")
	register("clear", _cmd_clear, "clear")
	register("seed", _cmd_seed, "seed [XXXX XXXX]  show or set the run seed")
	register("god", _cmd_god, "god  toggle invulnerability")
	register("bank", _cmd_bank, "bank <n>  add n Comb to the hive bank")
	register("unlock_all", _cmd_unlock_all, "unlock_all  unlock every content entry")
	register("content", _cmd_content, "content  list loaded content counts")
	register("save", func(_a: PackedStringArray) -> String: return "saved" if MetaSave.save_meta() else "save FAILED", "save")
	register("wipe_save", _cmd_wipe, "wipe_save confirm  delete all progress")
	# Commands whose systems arrive in later milestones.
	for stub in [["give", "give <item>", 1], ["spawn", "spawn <enemy> [n]", 1], ["goto", "goto <floor>", 2],
			["reveal", "reveal  reveal the map", 1], ["room", "room <template_id>  room test mode", 2]]:
		var m: int = stub[2]
		register(stub[0], func(_a: PackedStringArray) -> String: return "available from Milestone %d" % m, stub[1])


func _cmd_clear(_args: PackedStringArray) -> String:
	_log.clear()
	return ""


func _cmd_help(_args: PackedStringArray) -> String:
	var names := _commands.keys()
	names.sort()
	var lines: PackedStringArray = []
	for n in names:
		lines.append("  " + _commands[n]["usage"])
	return "Commands:\n" + "\n".join(lines)


func _cmd_seed(args: PackedStringArray) -> String:
	if args.is_empty():
		return "seed: %s (%d)" % [RNG.seed_to_string(RNG.run_seed), RNG.run_seed]
	var text := " ".join(args)
	var s := RNG.string_to_seed(text)
	if s < 0:
		if text.is_valid_int():
			s = int(text) & 0xFFFFFFFF
		else:
			return "invalid seed '%s'" % text
	RNG.set_run_seed(s)
	RunState.seed_value = s
	return "seed set to %s (takes full effect on next run/floor)" % RNG.seed_to_string(s)


func _cmd_god(_args: PackedStringArray) -> String:
	GameState.god_mode = not GameState.god_mode
	return "god mode %s" % ("ON" if GameState.god_mode else "OFF")


func _cmd_bank(args: PackedStringArray) -> String:
	if args.is_empty() or not args[0].is_valid_int():
		return "usage: bank <n>"
	MetaSave.bank_comb(int(args[0]))
	return "banked %s, total Comb %d" % [args[0], MetaSave.data["comb"]]


func _cmd_unlock_all(_args: PackedStringArray) -> String:
	var n := 0
	for kind in ["items", "trinkets", "fossils", "fluids", "characters", "mutations"]:
		for id in Content.ids(kind):
			if not MetaSave.is_unlocked(kind, id):
				MetaSave.unlock(kind, id, false)
				n += 1
	MetaSave.save_meta()
	return "unlocked %d entries" % n


func _cmd_content(_args: PackedStringArray) -> String:
	var lines: PackedStringArray = []
	for cat in Content.SCHEMA:
		lines.append("  %-13s %d" % [cat, Content.count(cat)])
	if not Content.errors.is_empty():
		lines.append("  ERRORS: %d (see output log)" % Content.errors.size())
	return "\n".join(lines)


func _cmd_wipe(args: PackedStringArray) -> String:
	if args.is_empty() or args[0] != "confirm":
		return "this deletes ALL progress. type: wipe_save confirm"
	MetaSave.wipe()
	return "save wiped"
