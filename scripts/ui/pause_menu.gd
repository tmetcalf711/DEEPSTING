extends CanvasLayer
## Pause screen: seed, stats, items. Controller-navigable.

var _panel: Control
var _info: Label
var _resume: Button


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(260, 200)
	_panel.position = Vector2(-130, -100)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.05, 0.94)
	sb.border_color = Color(0.85, 0.65, 0.25)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var vb := VBoxContainer.new()
	_panel.add_child(vb)
	var title := Label.new()
	title.text = tr("PAUSE_TITLE")
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 8)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.custom_minimum_size = Vector2(240, 0)
	vb.add_child(_info)
	_resume = _button(vb, "PAUSE_RESUME", func() -> void: _set_open(false))
	_button(vb, "PAUSE_RESTART", func() -> void: _restart(RunState.seed_value))
	_button(vb, "PAUSE_NEW_RUN", func() -> void: _restart(RNG.random_seed()))
	_button(vb, "PAUSE_MAIN_MENU", func() -> void:
		get_tree().paused = false
		RunState.reset()
		GameState.goto_scene("main_menu"))
	_panel.visible = false


func _button(parent: Node, key: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = tr(key)
	b.add_theme_font_size_override("font_size", 10)
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


func _restart(seed_value: int) -> void:
	get_tree().paused = false
	RunState.start_new(seed_value, RunState.caste)
	GameState.goto_scene("run")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or (_panel.visible and event.is_action_pressed("ui_cancel")):
		if RunController.instance and RunController.instance._ended:
			return
		_set_open(not _panel.visible)
		get_viewport().set_input_as_handled()


func _set_open(on: bool) -> void:
	_panel.visible = on
	get_tree().paused = on
	if on:
		var s := RunState.all_stats()
		var names: PackedStringArray = []
		for id in RunState.items:
			names.append(tr(Content.get_entry("items", id).get("name_key", id)))
		if RunState.active_item != "":
			names.append(tr(Content.get_entry("items", RunState.active_item).get("name_key", "")) + " *")
		if RunState.trinket != "":
			names.append(tr(Content.get_entry("trinkets", RunState.trinket).get("name_key", "")) + " (" + tr("PAUSE_KNICKKNACK") + ")")
		for m in RunState.mutations:
			names.append(tr(Content.get_entry("mutations", m).get("name_key", "")) + " (" + tr("PAUSE_MUTATION") + ")")
		var rc := RunController.instance
		var where := tr(rc.stratum.get("name_key", "")) + "  ·  " + (tr("BANNER_FLOOR") % (RunState.floor_index + 1))
		if rc.curse_id != "":
			where += "  ·  " + tr(Content.get_entry("curses", rc.curse_id).get("name_key", ""))
		_info.text = where + "\n" + tr("PAUSE_INFO") % [RunState.seed_string(), int(RunState.elapsed) / 60, int(RunState.elapsed) % 60,
			s["damage"], s["fire_rate"], s["shot_speed"], s["range"], s["move_speed"], s["luck"],
			RunState.stash_total(), ", ".join(names) if not names.is_empty() else "-"]
		_resume.grab_focus()
